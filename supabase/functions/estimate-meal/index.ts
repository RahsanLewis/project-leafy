import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'
import {
  mealEstimateSchema, mealPromptVersion, mealSchemaVersion,
  normalizeMealOutput, systemPrompt, userPrompt,
} from '../_shared/meal-estimate.ts'
import {
  amountsPer100g, describedGrams, deterministicFoodKey, likelySingleReusableFood,
  normalizeFoodQuery, nutritionFactsCore, nutrientsForPortion, resolverVersion,
  gramsForRequestedServing, requestedServing, reusableEstimate,
} from '../_shared/food-resolution.ts'
import { nutrientCodes } from '../_shared/nutrients.ts'

type Body = {
  action: 'analyze' | 'answer' | 'confirm' | 'discard' | 'delete_entry'
  session_id?: string
  description?: string
  voice_transcript?: string
  photo_object_path?: string
  consumed_at?: string
  local_date?: string
  time_zone?: string
  meal_type?: string
  answer?: string
  skip?: boolean
  items?: { id?: string; client_item_id?: string; prediction_id?: string | null; origin?: 'prediction' | 'user_added'; name: string; portion: string; calories: number; estimated_grams?: number | null; nutrients?: {
    code: string; amount: number; derivation_method?: string; source_version?: string; confidence?: number | null;
  }[] }[]
  food_entry_id?: string
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authorization = request.headers.get('Authorization') ?? ''
    const url = Deno.env.get('SUPABASE_URL')!
    const publishable = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!
    const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')!
    const auth = createClient(url, publishable, { global: { headers: { Authorization: authorization } } })
    const { data: { user }, error: authError } = await auth.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)
    const admin = createClient(url, secret)
    const body = await request.json() as Body
    if (body.action === 'delete_entry') {
      if (!body.food_entry_id || !isUUID(body.food_entry_id)) return json({ error: 'A valid food entry is required.' }, 400)
      await deleteAIEntry(admin, user.id, body.food_entry_id)
      return json({ ok: true })
    }
    if (!body.session_id || !isUUID(body.session_id)) return json({ error: 'A valid estimate session is required.' }, 400)

    if (body.action === 'discard') {
      const session = await ownedSession(admin, user.id, body.session_id)
      if (session.status === 'confirmed') return json({ error: 'A saved meal cannot be discarded here.' }, 409)
      await purgeSession(admin, user.id, body.session_id)
      return json({ ok: true })
    }

    if (body.action === 'confirm') {
      if (!Array.isArray(body.items) || !body.items.length) return json({ error: 'Choose at least one item to log.' }, 400)
      const normalized = body.items.map((item) => ({
        id: String(item.prediction_id ?? item.id ?? ''),
        client_item_id: String(item.client_item_id ?? item.id ?? ''),
        origin: item.origin === 'user_added' ? 'user_added' : 'prediction',
        name: String(item.name ?? '').trim().slice(0, 120),
        portion: String(item.portion ?? '').trim().slice(0, 240), calories: Math.round(Number(item.calories)),
        estimated_grams: item.estimated_grams == null ? null : Number(item.estimated_grams),
        nutrients: Array.isArray(item.nutrients) ? item.nutrients.flatMap((nutrient) => {
          const code = String(nutrient.code)
          const amount = Number(nutrient.amount)
          if (!nutrientCodes.includes(code as typeof nutrientCodes[number]) || !Number.isFinite(amount) || amount < 0) return []
          const methods = ['laboratory', 'label', 'calculated', 'estimated', 'user_entered']
          const method = methods.includes(String(nutrient.derivation_method))
            ? String(nutrient.derivation_method) : 'user_entered'
          const confidence = nutrient.confidence == null ? null : Math.min(1, Math.max(0, Number(nutrient.confidence)))
          return [{ code, amount: Math.min(amount, 1_000_000), derivation_method: method,
            source_version: String(nutrient.source_version ?? 'ios-nutrition-review-v1').slice(0, 120),
            confidence: Number.isFinite(confidence) ? confidence : null }]
        }) : [],
      }))
      if (normalized.some((item) => !isUUID(item.client_item_id) || (item.origin === 'prediction' && !isUUID(item.id)) || !item.name || item.calories < 1 || item.calories > 10000 || (item.estimated_grams != null && (!Number.isFinite(item.estimated_grams) || item.estimated_grams <= 0 || item.estimated_grams > 5000)))) {
        return json({ error: 'Review each food name and calorie estimate before saving.' }, 400)
      }
      const suppliedTiming = body.consumed_at || body.local_date || body.time_zone
      if (suppliedTiming && (!body.consumed_at || !/^\d{4}-\d{2}-\d{2}$/.test(body.local_date ?? '') || !body.time_zone)) {
        return json({ error: 'A valid meal date and time are required.' }, 400)
      }
      for (const item of normalized) {
        if (item.origin !== 'prediction' || item.estimated_grams == null) continue
        const update = await admin.from('ai_meal_items').update({
          predicted_grams: item.estimated_grams,
        }).eq('id', item.id).eq('session_id', body.session_id)
        if (update.error) throw update.error
      }
      const { data, error } = await admin.rpc('confirm_ai_meal', {
        p_user_id: user.id, p_session_id: body.session_id, p_items: normalized,
        ...(suppliedTiming ? {
          p_consumed_at: body.consumed_at, p_local_date: body.local_date,
          p_time_zone: String(body.time_zone).slice(0, 80),
        } : {}),
      })
      if (error) throw error
      await persistConfirmedNutrients(admin, user.id, body.session_id, normalized)
      await attachResolvedFoodsAndPromote(admin, user.id, body.session_id)
      const ids = (data ?? []).map((entry: Record<string, unknown>) => entry.id)
      const refreshed = ids.length
        ? await admin.from('food_entries').select('*').eq('user_id', user.id).in('id', ids).order('consumed_at')
        : { data: [], error: null }
      if (refreshed.error) throw refreshed.error
      return json({ entries: refreshed.data ?? [] })
    }

    let session: Record<string, unknown>
    let forceReady = false
    if (body.action === 'analyze') {
      session = await startSession(admin, user.id, body)
    } else if (body.action === 'answer') {
      session = await ownedSession(admin, user.id, body.session_id)
      const { data: pending, error } = await admin.from('ai_meal_follow_ups').select('*')
        .eq('session_id', body.session_id).is('answered_at', null).order('ordinal', { ascending: false }).limit(1).maybeSingle()
      if (error) throw error
      if (!pending) return json({ error: 'There is no follow-up question waiting for an answer.' }, 409)
      const answer = String(body.answer ?? '').trim().slice(0, 1000)
      if (!body.skip && !answer) return json({ error: 'Enter an answer or skip this question.' }, 400)
      const update = await admin.from('ai_meal_follow_ups').update({
        answer: body.skip ? null : answer, skipped: Boolean(body.skip), answered_at: new Date().toISOString(),
      }).eq('id', pending.id)
      if (update.error) throw update.error
      // Clarification is intentionally required when the model still considers
      // the meal materially ambiguous. `skip` remains supported for older app
      // versions, but we no longer force a guess after an arbitrary number of
      // follow-ups.
      forceReady = Boolean(body.skip)
    } else {
      return json({ error: 'Unsupported meal estimate action.' }, 400)
    }

    const result = await runAnalysis(admin, user.id, session, forceReady)
    return json(result)
  } catch (error) {
    console.error('estimate-meal failed', error)
    const message = error instanceof Error ? error.message : 'Unable to estimate that meal.'
    const status = message === 'Unauthorized' ? 401 : 400
    return json({ error: message }, status)
  }
})

// deno-lint-ignore no-explicit-any
async function startSession(admin: any, userID: string, body: Body) {
  const description = String(body.description ?? '').trim().slice(0, 2000)
  const transcript = String(body.voice_transcript ?? '').trim().slice(0, 2000)
  const photoPath = String(body.photo_object_path ?? '')
  if (!description && !transcript && !photoPath) throw new Error('Add a photo or describe what you ate.')
  if (photoPath && !validPhotoPath(userID, body.session_id!, photoPath)) throw new Error('The meal photo path is invalid.')
  if (!body.consumed_at || !body.local_date || !body.time_zone) throw new Error('Meal date and time are required.')
  const modalities = [description ? 'text' : '', transcript ? 'voice' : '', photoPath ? 'photo' : ''].filter(Boolean)
  const values = {
    id: body.session_id, user_id: userID, status: 'analyzing', input_modalities: modalities,
    description_text: description || null, voice_transcript: transcript || null,
    meal_type: validMealType(body.meal_type), consumed_at: body.consumed_at,
    local_date: body.local_date, time_zone: String(body.time_zone).slice(0, 80),
    provider: 'openai', prompt_version: mealPromptVersion, schema_version: mealSchemaVersion,
    error_code: null, error_message: null, updated_at: new Date().toISOString(),
  }
  const { data, error } = await admin.from('ai_meal_sessions').upsert(values, { onConflict: 'id' }).select('*').single()
  if (error) throw error
  if (photoPath) await registerPhoto(admin, userID, body.session_id!, photoPath)
  return { ...data, photo_object_path: photoPath || null }
}

// deno-lint-ignore no-explicit-any
async function runAnalysis(admin: any, userID: string, sessionInput: Record<string, unknown>, forceReady: boolean) {
  const session = await ownedSession(admin, userID, String(sessionInput.id))
  const [{ data: answers, error: answerError }, { data: media, error: mediaError }] = await Promise.all([
    admin.from('ai_meal_follow_ups').select('question,answer,skipped').eq('session_id', session.id).not('answered_at', 'is', null).order('ordinal'),
    admin.from('nutrition_media_assets').select('object_path,mime_type').eq('ai_meal_session_id', session.id).is('deleted_at', null).maybeSingle(),
  ])
  if (answerError) throw answerError
  if (mediaError) throw mediaError
  if (!media && !(answers ?? []).length && !forceReady && likelySingleReusableFood(String(session.description_text ?? ''))) {
    const known = await resolveKnownFood(admin, String(session.description_text ?? ''))
    if (known) return persistEstimate(admin, session, known, null, {
      provider: known.items[0].resolution_source === 'usda' ? 'usda_fdc' : 'leafy_catalog',
      modelID: null, providerResponseID: null, inputTokens: null, outputTokens: null, latencyMS: 0,
    })
  }
  const answerPairs = (answers ?? []).map((row: Record<string, unknown>) => ({
    question: String(row.question), answer: row.skipped ? 'User skipped this question.' : String(row.answer ?? ''),
  }))
  const content: Record<string, unknown>[] = [{
    type: 'input_text',
    text: userPrompt(String(session.description_text ?? ''), String(session.voice_transcript ?? ''), answerPairs),
  }]
  if (media) {
    const { data: blob, error } = await admin.storage.from('nutrition-media').download(media.object_path)
    if (error) throw error
    const bytes = new Uint8Array(await blob.arrayBuffer())
    content.push({ type: 'input_image', image_url: `data:${media.mime_type};base64,${toBase64(bytes)}`, detail: 'high' })
  }
  const key = Deno.env.get('OPENAI_API_KEY')
  if (!key) throw new Error('AI meal estimates are not configured yet.')
  const model = Deno.env.get('OPENAI_MEAL_MODEL') ?? 'gpt-5.6-terra'
  const started = Date.now()
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model, store: false, reasoning: { effort: 'low' }, safety_identifier: await safetyID(userID),
      input: [
        { role: 'system', content: [{ type: 'input_text', text: systemPrompt(forceReady) }] },
        { role: 'user', content },
      ],
      text: { format: { type: 'json_schema', name: 'leafy_meal_estimate', strict: true, schema: mealEstimateSchema } },
    }),
  })
  const payload = await response.json()
  if (!response.ok) throw new Error(payload?.error?.message ?? 'The AI service could not analyze this meal.')
  const outputText = extractOutputText(payload)
  const estimate = normalizeMealOutput(JSON.parse(outputText), forceReady)
  return persistEstimate(admin, session, {
    ...estimate,
    items: estimate.items.map((item) => ({
      ...item, resolution_source: 'ai' as const, food_version_id: null,
      catalog_eligible: reusableEstimate(item.confidence, item.estimated_grams, item.nutrients),
    })),
  }, estimate.follow_up_question, {
    provider: 'openai', modelID: model, providerResponseID: payload.id ?? null,
    inputTokens: payload.usage?.input_tokens ?? null, outputTokens: payload.usage?.output_tokens ?? null,
    latencyMS: Date.now() - started,
  })
}

// deno-lint-ignore no-explicit-any
async function persistEstimate(admin: any, session: Record<string, unknown>, estimate: any, followUpQuestion: string | null, trace: {
  provider: string; modelID: string | null; providerResponseID: string | null;
  inputTokens: number | null; outputTokens: number | null; latencyMS: number;
}) {
  const update = await admin.from('ai_meal_sessions').update({
    status: estimate.status, provider: trace.provider, model_id: trace.modelID,
    provider_response_id: trace.providerResponseID, estimated_calories: estimate.total_calories,
    calorie_low: estimate.calorie_low, calorie_high: estimate.calorie_high,
    confidence: estimate.confidence, assumptions: estimate.assumptions,
    input_tokens: trace.inputTokens, output_tokens: trace.outputTokens, latency_ms: trace.latencyMS,
    error_code: null, error_message: null, updated_at: new Date().toISOString(),
  }).eq('id', session.id)
  if (update.error) throw update.error
  const remove = await admin.from('ai_meal_items').delete().eq('session_id', session.id)
  if (remove.error) throw remove.error
  const rows = estimate.items.map((item: Record<string, unknown>, index: number) => ({
    session_id: session.id, ordinal: index + 1, predicted_name: item.name,
    predicted_portion: item.portion, predicted_grams: item.estimated_grams,
    predicted_calories: item.calories, calorie_low: item.calorie_low, calorie_high: item.calorie_high,
    confidence: item.confidence, assumptions: item.assumptions,
    food_version_id: item.food_version_id ?? null,
    resolution_source: item.resolution_source ?? 'ai', catalog_eligible: item.catalog_eligible ?? false,
  }))
  const inserted = await admin.from('ai_meal_items').insert(rows).select('*').order('ordinal')
  if (inserted.error) throw inserted.error
  const nutrientRows = (inserted.data ?? []).flatMap((row: Record<string, unknown>, index: number) =>
    estimate.items[index].nutrients.map((nutrient: Record<string, unknown>) => ({
      ai_meal_item_id: row.id, nutrient_code: nutrient.code,
      predicted_amount: nutrient.amount, confidence: nutrient.confidence,
    })))
  if (nutrientRows.length) {
    const nutrientInsert = await admin.from('ai_meal_item_nutrients').insert(nutrientRows)
    if (nutrientInsert.error) throw nutrientInsert.error
  }
  let followUp = null
  if (estimate.status === 'needs_clarification' && followUpQuestion) {
    const ordinal = Number(session.follow_up_count ?? 0) + 1
    const created = await admin.from('ai_meal_follow_ups').insert({
      session_id: session.id, ordinal, question: followUpQuestion,
    }).select('*').single()
    if (created.error) throw created.error
    followUp = created.data
    const countUpdate = await admin.from('ai_meal_sessions').update({ follow_up_count: ordinal }).eq('id', session.id)
    if (countUpdate.error) throw countUpdate.error
  }
  return sessionResponse(String(session.id), estimate, inserted.data ?? [], followUp)
}

// deno-lint-ignore no-explicit-any
async function registerPhoto(admin: any, userID: string, sessionID: string, path: string) {
  const { data: blob, error } = await admin.storage.from('nutrition-media').download(path)
  if (error) throw new Error('Upload the meal photo before starting the estimate.')
  const bytes = new Uint8Array(await blob.arrayBuffer())
  if (!bytes.length || bytes.length > 4 * 1024 * 1024) throw new Error('Choose a meal photo smaller than 4 MB.')
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  const contentHash = [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('')
  const result = await admin.from('nutrition_media_assets').upsert({
    user_id: userID, ai_meal_session_id: sessionID, asset_kind: 'meal_photo', object_path: path,
    content_hash: contentHash, mime_type: 'image/jpeg', byte_count: bytes.length,
    metadata_stripped: true, redaction_status: 'not_scanned', commercial_eligible: false,
  }, { onConflict: 'object_path' })
  if (result.error) throw result.error
}

// deno-lint-ignore no-explicit-any
async function ownedSession(admin: any, userID: string, id: string) {
  const { data, error } = await admin.from('ai_meal_sessions').select('*').eq('id', id).eq('user_id', userID).is('deleted_at', null).single()
  if (error || !data) throw new Error('Meal estimate not found.')
  return data
}

// deno-lint-ignore no-explicit-any
async function purgeSession(admin: any, userID: string, id: string) {
  const { data: media, error } = await admin.from('nutrition_media_assets').select('object_path').eq('user_id', userID).eq('ai_meal_session_id', id).is('deleted_at', null)
  if (error) throw error
  const paths = (media ?? []).map((row: Record<string, string>) => row.object_path)
  if (paths.length) {
    const removed = await admin.storage.from('nutrition-media').remove(paths)
    if (removed.error) throw removed.error
  }
  const deleted = await admin.from('ai_meal_sessions').delete().eq('id', id).eq('user_id', userID)
  if (deleted.error) throw deleted.error
}

// deno-lint-ignore no-explicit-any
async function deleteAIEntry(admin: any, userID: string, entryID: string) {
  const { data: item, error: itemError } = await admin.from('ai_meal_items').select('id,session_id')
    .eq('food_entry_id', entryID).maybeSingle()
  if (itemError) throw itemError
  if (!item) throw new Error('AI food entry not found.')
  const sessionID = String(item.session_id)
  await ownedSession(admin, userID, sessionID)
  const deleted = await admin.from('food_entries').delete().eq('id', entryID).eq('user_id', userID)
  if (deleted.error) throw deleted.error
  const itemUpdate = await admin.from('ai_meal_items').update({
    food_entry_id: null, review_outcome: 'removed', updated_at: new Date().toISOString(),
  }).eq('id', item.id)
  if (itemUpdate.error) throw itemUpdate.error
  const { count, error: countError } = await admin.from('ai_meal_items').select('id', { count: 'exact', head: true })
    .eq('session_id', sessionID).not('food_entry_id', 'is', null)
  if (countError) throw countError
  if ((count ?? 0) === 0) {
    const { data: media, error: mediaError } = await admin.from('nutrition_media_assets').select('id,object_path')
      .eq('ai_meal_session_id', sessionID).is('deleted_at', null)
    if (mediaError) throw mediaError
    const paths = (media ?? []).map((row: Record<string, string>) => row.object_path)
    if (paths.length) {
      const storage = await admin.storage.from('nutrition-media').remove(paths)
      if (storage.error) throw storage.error
    }
    const now = new Date().toISOString()
    if ((media ?? []).length) {
      const mediaUpdate = await admin.from('nutrition_media_assets').update({ deleted_at: now })
        .eq('ai_meal_session_id', sessionID)
      if (mediaUpdate.error) throw mediaUpdate.error
    }
    const sessionUpdate = await admin.from('ai_meal_sessions').update({ status: 'discarded', deleted_at: now, updated_at: now })
      .eq('id', sessionID).eq('user_id', userID)
    if (sessionUpdate.error) throw sessionUpdate.error
  }
}

function sessionResponse(id: string, estimate: ReturnType<typeof normalizeMealOutput>, items: Record<string, unknown>[], followUp: Record<string, unknown> | null) {
  return {
    session_id: id, status: estimate.status, total_calories: estimate.total_calories,
    calorie_low: estimate.calorie_low, calorie_high: estimate.calorie_high,
    confidence: estimate.confidence, assumptions: estimate.assumptions,
    items: items.map((row, index) => ({
      id: row.id, name: row.predicted_name, portion: row.predicted_portion,
      estimated_grams: row.predicted_grams, calories: row.predicted_calories,
      calorie_low: row.calorie_low, calorie_high: row.calorie_high,
      confidence: row.confidence, assumptions: row.assumptions,
      resolution_source: row.resolution_source ?? 'ai',
      food_version_id: row.food_version_id ?? null,
      catalog_eligible: row.catalog_eligible ?? false,
      nutrients: estimate.items[index]?.nutrients ?? [],
    })),
    follow_up: followUp ? { id: followUp.id, ordinal: followUp.ordinal, question: followUp.question } : null,
  }
}

const fdcNutrients: Record<number, string> = {
  1008: 'energy_kcal', 1003: 'protein_g', 1005: 'carbohydrate_g', 1004: 'fat_g',
  1079: 'fiber_g', 2000: 'sugars_g', 1235: 'added_sugars_g', 1258: 'saturated_fat_g',
  1257: 'trans_fat_g', 1253: 'cholesterol_mg', 1093: 'sodium_mg', 1092: 'potassium_mg',
  1087: 'calcium_mg', 1089: 'iron_mg', 1114: 'vitamin_d_mcg',
}

// deno-lint-ignore no-explicit-any
async function resolveKnownFood(admin: any, description: string) {
  const query = normalizeFoodQuery(description.split('\n')[0])
  if (!query) return null
  const { data: local, error } = await admin.rpc('search_unpacked_food_catalog', { p_query: query, p_limit: 3 })
  if (error) throw error
  const localRows = local ?? []
  if (localRows.length && (Number(localRows[0].rank) === 1 || (
    Number(localRows[0].rank) >= 0.90 && Number(localRows[0].rank) - Number(localRows[1]?.rank ?? 0) >= 0.05
  ))) return estimateFromVersion(admin, String(localRows[0].food_version_id), description,
    localRows[0].source_system === 'usda_fdc' ? 'usda' : 'leafy_catalog')

  const match = await searchGenericUSDA(query)
  if (!match) return null
  const versionID = await importGenericUSDA(admin, Number(match.fdcId))
  return estimateFromVersion(admin, versionID, description, 'usda')
}

async function searchGenericUSDA(query: string) {
  const key = Deno.env.get('FDC_API_KEY') ?? 'DEMO_KEY'
  const response = await fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${encodeURIComponent(key)}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, dataType: ['Foundation', 'Survey (FNDDS)', 'SR Legacy'], pageSize: 5 }),
  })
  if (!response.ok) return null
  const payload = await response.json()
  const foods = Array.isArray(payload.foods) ? payload.foods : []
  if (!foods.length) return null
  const top = foods[0]
  const topName = normalizeFoodQuery(String(top.description ?? ''))
  const tokens = query.split(' ').filter((token) => token.length > 1)
  return tokens.every((token) => topName.includes(token)) ? top : null
}

// deno-lint-ignore no-explicit-any
async function importGenericUSDA(admin: any, fdcID: number) {
  const existing = await admin.from('food_versions').select('id').eq('source_system', 'usda_fdc')
    .eq('source_record_id', String(fdcID)).is('superseded_at', null).maybeSingle()
  if (existing.error) throw existing.error
  if (existing.data) return String(existing.data.id)
  const key = Deno.env.get('FDC_API_KEY') ?? 'DEMO_KEY'
  const response = await fetch(`https://api.nal.usda.gov/fdc/v1/food/${fdcID}?api_key=${encodeURIComponent(key)}`)
  if (!response.ok) throw new Error('USDA could not return food details.')
  const food = await response.json()
  const name = String(food.description ?? '').trim()
  const canonical = await admin.from('foods').insert({ canonical_name: name }).select('id').single()
  if (canonical.error) throw canonical.error
  const rawNutrients = (Array.isArray(food.foodNutrients) ? food.foodNutrients : []).flatMap((item: Record<string, unknown>) => {
    const nutrient = item.nutrient as Record<string, unknown> | undefined
    const code = fdcNutrients[Number(nutrient?.id ?? item.nutrientId)]
    const amount = Number(item.amount ?? item.value)
    return code && Number.isFinite(amount) && amount >= 0 ? [{ nutrient_code: code, amount_per_100g: amount }] : []
  })
  const coreComplete = nutritionFactsCore.every((code) => rawNutrients.some((item: { nutrient_code: string }) => item.nutrient_code === code))
  const version = await admin.from('food_versions').insert({
    food_id: canonical.data.id, source_system: 'usda_fdc', source_record_id: String(fdcID),
    source_data_type: food.dataType, description: name, market_country: 'US',
    verification_status: 'verified', source_updated_at: food.modifiedDate ?? null,
    food_kind: /restaurant|sandwich|pizza|soup|salad|cooked|prepared/i.test(name) ? 'prepared' : 'generic',
    resolution_confidence: 1, nutrition_core_complete: coreComplete, resolver_version: resolverVersion,
    raw_source: food,
  }).select('id').single()
  if (version.error) {
    const raced = await admin.from('food_versions').select('id').eq('source_system', 'usda_fdc')
      .eq('source_record_id', String(fdcID)).is('superseded_at', null).single()
    if (raced.error) throw version.error
    return String(raced.data.id)
  }
  if (rawNutrients.length) {
    const saved = await admin.from('food_version_nutrients').insert(rawNutrients.map((item: Record<string, unknown>) => ({
      food_version_id: version.data.id, ...item,
      derivation_method: food.dataType === 'Foundation' || food.dataType === 'SR Legacy' ? 'laboratory' : 'calculated',
    })))
    if (saved.error) throw saved.error
  }
  const portions = Array.isArray(food.foodPortions) ? food.foodPortions : []
  for (const portion of portions.slice(0, 12)) {
    const grams = Number(portion.gramWeight)
    if (!Number.isFinite(grams) || grams <= 0) continue
    await admin.from('food_portions').insert({
      food_version_id: version.data.id, amount: Number(portion.amount ?? 1) || 1,
      unit: String(portion.measureUnit?.name ?? portion.modifier ?? 'serving').slice(0, 80),
      description: String(portion.portionDescription ?? portion.modifier ?? 'Serving').slice(0, 240),
      gram_weight: grams, source: 'usda_fdc',
    })
  }
  await admin.from('food_aliases').insert({ food_id: canonical.data.id, alias: name, source: 'usda' })
  return String(version.data.id)
}

// deno-lint-ignore no-explicit-any
async function estimateFromVersion(admin: any, versionID: string, description: string, source: 'leafy_catalog' | 'usda') {
  const [{ data: version, error }, { data: nutrients, error: nutrientError }, { data: portions, error: portionError }] = await Promise.all([
    admin.from('food_versions').select('id,description,resolution_confidence,verification_status').eq('id', versionID).single(),
    admin.from('food_version_nutrients').select('nutrient_code,amount_per_100g').eq('food_version_id', versionID),
    admin.from('food_portions').select('amount,unit,description,gram_weight').eq('food_version_id', versionID).order('created_at').limit(20),
  ])
  if (error) throw error
  if (nutrientError) throw nutrientError
  if (portionError) throw portionError
  const requested = requestedServing(description)
  const explicitGrams = describedGrams(description)
  const portion = portions?.[0]
  const grams = explicitGrams
    ?? gramsForRequestedServing(requested, portions ?? [])
  const values = nutrientsForPortion(nutrients ?? [], grams, source === 'usda' ? 1 : Number(version.resolution_confidence ?? 0.8))
  const energy = (nutrients ?? []).find((item: Record<string, unknown>) => item.nutrient_code === 'energy_kcal')
  if (!energy) return null
  const calories = Math.max(1, Math.round(Number(energy.amount_per_100g) * grams / 100))
  const confidence = source === 'usda' ? 1 : Number(version.resolution_confidence ?? 0.8)
  const portionText = requested
    ? `${requested.amount} ${requested.unit}`
    : explicitGrams ? `${explicitGrams} g` : String(portion?.description ?? `${grams} g`)
  return {
    status: 'ready', follow_up_question: null,
    items: [{
      name: version.description, portion: portionText, estimated_grams: grams, calories,
      calorie_low: Math.max(0, Math.round(calories * (source === 'usda' ? 0.95 : 0.85))),
      calorie_high: Math.round(calories * (source === 'usda' ? 1.05 : 1.15)), confidence,
      assumptions: requested || explicitGrams ? [] : [`Using a typical serving of ${portionText}.`], nutrients: values,
      resolution_source: source, food_version_id: versionID, catalog_eligible: true,
    }],
    total_calories: calories, calorie_low: Math.max(0, Math.round(calories * (source === 'usda' ? 0.95 : 0.85))),
    calorie_high: Math.round(calories * (source === 'usda' ? 1.05 : 1.15)), confidence,
    assumptions: requested || explicitGrams ? [] : [`Review the suggested ${portionText} serving before logging.`],
  }
}

// deno-lint-ignore no-explicit-any
async function persistConfirmedNutrients(admin: any, userID: string, sessionID: string, requested: {
  id: string; name: string; portion: string; calories: number;
  nutrients: { code: string; amount: number; derivation_method?: string; source_version?: string; confidence?: number | null }[];
}[]) {
  const ids = requested.map((item) => item.id)
  const { data: items, error: itemError } = await admin.from('ai_meal_items')
    .select('id,food_entry_id').eq('session_id', sessionID).in('id', ids)
  if (itemError) throw itemError
  for (const item of items ?? []) {
    if (!item.food_entry_id) continue
    const { data: consumption, error: consumptionError } = await admin.from('consumption_items').select('id')
      .eq('legacy_food_entry_id', item.food_entry_id).eq('user_id', userID).single()
    if (consumptionError) throw consumptionError
    const reviewed = requested.find((value) => value.id === item.id)
    const snapshots = (reviewed?.nutrients ?? []).map((nutrient) => ({
      consumption_item_id: consumption.id, nutrient_code: nutrient.code,
      amount: nutrient.amount, derivation_method: nutrient.derivation_method ?? 'estimated',
      source_version: nutrient.source_version ?? 'leafy-meal-v2', confidence: nutrient.confidence ?? null,
    }))
    if (snapshots.length) {
      const saved = await admin.from('consumption_item_nutrients').upsert(snapshots, { onConflict: 'consumption_item_id,nutrient_code' })
      if (saved.error) throw saved.error
    }
  }
}

// deno-lint-ignore no-explicit-any
async function attachResolvedFoodsAndPromote(admin: any, userID: string, sessionID: string) {
  const { data: items, error } = await admin.from('ai_meal_items').select(
    'id,predicted_name,predicted_portion,predicted_grams,predicted_calories,confidence,food_entry_id,food_version_id,resolution_source,catalog_eligible,review_outcome',
  ).eq('session_id', sessionID).not('food_entry_id', 'is', null)
  if (error) throw error
  for (const item of items ?? []) {
    let versionID = item.food_version_id ? String(item.food_version_id) : null
    if (!versionID && item.resolution_source === 'ai' && item.catalog_eligible && item.review_outcome === 'accepted') {
      const { data: nutrients, error: nutrientError } = await admin.from('ai_meal_item_nutrients')
        .select('nutrient_code,predicted_amount,confidence').eq('ai_meal_item_id', item.id)
      if (nutrientError) throw nutrientError
      if (reusableEstimate(Number(item.confidence), Number(item.predicted_grams), (nutrients ?? []).map((value: Record<string, unknown>) => ({
        code: String(value.nutrient_code), amount: Number(value.predicted_amount), confidence: Number(value.confidence),
      })))) {
        versionID = await promoteAIEstimate(admin, item, nutrients ?? [])
      }
    }
    if (!versionID) {
      await admin.from('food_catalog_feedback').insert({
        user_id: userID, ai_meal_item_id: item.id,
        feedback_kind: item.review_outcome === 'accepted' ? 'confirmed' : 'corrected',
        corrected_fields: item.review_outcome === 'accepted' ? {} : { name: true, portion: true, calories: true },
      })
      continue
    }
    const knownSource = item.resolution_source === 'leafy_catalog' || item.resolution_source === 'usda'
    const entryUpdate: Record<string, unknown> = {
      canonical_food_version_id: versionID,
      confidence: Number(item.confidence),
    }
    if (knownSource) {
      entryUpdate.provenance = {
        capture_version: 'ios-describe-v1', resolver_version: resolverVersion,
        ai_meal_session_id: sessionID, ai_meal_item_id: item.id,
        resolution_source: item.resolution_source,
      }
      entryUpdate.entry_source = 'manual'
      entryUpdate.calorie_method = 'nutrition_database'
    }
    const updated = await admin.from('food_entries').update(entryUpdate)
      .eq('id', item.food_entry_id).eq('user_id', userID)
    if (updated.error) throw updated.error
    await admin.from('food_catalog_feedback').insert({
      user_id: userID, food_version_id: versionID, ai_meal_item_id: item.id,
      feedback_kind: item.review_outcome === 'accepted' ? 'confirmed' : 'corrected',
      corrected_fields: item.review_outcome === 'accepted' ? {} : { name: true, portion: true, calories: true },
    })
  }
}

// deno-lint-ignore no-explicit-any
async function promoteAIEstimate(admin: any, item: Record<string, any>, nutrients: Record<string, any>[]) {
  const name = String(item.predicted_name).trim()
  const kind = /sandwich|pizza|soup|salad|cooked|grilled|baked|fried|scrambled|roasted/i.test(name) ? 'prepared' : 'generic'
  const sourceRecordID = await sha256(deterministicFoodKey(name, kind))
  const existing = await admin.from('food_versions').select('id').eq('source_system', 'leafy')
    .eq('source_record_id', sourceRecordID).is('superseded_at', null).maybeSingle()
  if (existing.error) throw existing.error
  if (existing.data) return String(existing.data.id)
  const food = await admin.from('foods').insert({ canonical_name: name }).select('id').single()
  if (food.error) throw food.error
  const values = amountsPer100g(
    nutrients.map((value) => ({ code: String(value.nutrient_code), amount: Number(value.predicted_amount) })),
    Number(item.predicted_calories), Number(item.predicted_grams),
  )
  const complete = nutritionFactsCore.every((code) => values.some((value) => value.nutrient_code === code))
  const version = await admin.from('food_versions').insert({
    food_id: food.data.id, source_system: 'leafy', source_record_id: sourceRecordID,
    source_data_type: 'ai_estimate', description: name, market_country: 'US',
    verification_status: 'unverified', food_kind: kind,
    resolution_confidence: Number(item.confidence), nutrition_core_complete: complete,
    resolver_version: resolverVersion,
    raw_source: { resolver_version: resolverVersion, source: 'confirmed_ai_estimate' },
  }).select('id').single()
  if (version.error) {
    const raced = await admin.from('food_versions').select('id').eq('source_system', 'leafy')
      .eq('source_record_id', sourceRecordID).is('superseded_at', null).single()
    if (raced.error) throw version.error
    return String(raced.data.id)
  }
  const nutrientWrite = await admin.from('food_version_nutrients').insert(values.map((value) => ({
    food_version_id: version.data.id, ...value, derivation_method: 'estimated',
  })))
  if (nutrientWrite.error) throw nutrientWrite.error
  const portionWrite = await admin.from('food_portions').insert({
    food_version_id: version.data.id, amount: 1, unit: 'serving',
    description: String(item.predicted_portion ?? 'Serving').slice(0, 240),
    gram_weight: Number(item.predicted_grams), source: resolverVersion,
  })
  if (portionWrite.error) throw portionWrite.error
  const aliasWrite = await admin.from('food_aliases').insert({ food_id: food.data.id, alias: name, source: 'leafy_ai' })
  if (aliasWrite.error) throw aliasWrite.error
  return String(version.data.id)
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function extractOutputText(payload: Record<string, unknown>) {
  if (typeof payload.output_text === 'string') return payload.output_text
  const output = Array.isArray(payload.output) ? payload.output : []
  for (const item of output as Record<string, unknown>[]) {
    const content = Array.isArray(item.content) ? item.content : []
    for (const part of content as Record<string, unknown>[]) if (part.type === 'output_text' && typeof part.text === 'string') return part.text
  }
  throw new Error('The AI service returned no meal estimate.')
}

async function safetyID(userID: string) {
  const salt = Deno.env.get('AI_SAFETY_SALT') ?? Deno.env.get('SUPABASE_SECRET_KEY') ?? 'leafy'
  const bytes = new TextEncoder().encode(`${salt}:${userID}`)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('')
}

function toBase64(bytes: Uint8Array) {
  let binary = ''; const chunk = 0x8000
  for (let index = 0; index < bytes.length; index += chunk) binary += String.fromCharCode(...bytes.subarray(index, index + chunk))
  return btoa(binary)
}
function isUUID(value: string) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) }
function validPhotoPath(userID: string, sessionID: string, path: string) { return path === `${userID}/ai-meals/${sessionID}.jpg` }
function validMealType(value?: string) { return ['breakfast', 'lunch', 'dinner', 'snack', 'drink', 'supplement', 'unspecified'].includes(value ?? '') ? value : 'unspecified' }
