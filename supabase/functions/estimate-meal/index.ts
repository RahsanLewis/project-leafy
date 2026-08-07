import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'
import {
  mealEstimateSchema, mealPromptVersion, mealSchemaVersion,
  normalizeMealOutput, systemPrompt, userPrompt,
} from '../_shared/meal-estimate.ts'

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
  items?: { id: string; name: string; portion: string; calories: number; nutrients?: { code: string; amount: number }[] }[]
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
        id: String(item.id), name: String(item.name ?? '').trim().slice(0, 120),
        portion: String(item.portion ?? '').trim().slice(0, 240), calories: Math.round(Number(item.calories)),
      }))
      if (normalized.some((item) => !isUUID(item.id) || !item.name || item.calories < 1 || item.calories > 10000)) {
        return json({ error: 'Review each food name and calorie estimate before saving.' }, 400)
      }
      const { data, error } = await admin.rpc('confirm_ai_meal', {
        p_user_id: user.id, p_session_id: body.session_id, p_items: normalized,
      })
      if (error) throw error
      await persistConfirmedNutrients(admin, user.id, body.session_id, normalized)
      return json({ entries: data ?? [] })
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
      forceReady = Boolean(body.skip) || Number(session.follow_up_count ?? 0) >= 3
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
  const update = await admin.from('ai_meal_sessions').update({
    status: estimate.status, model_id: model, provider_response_id: payload.id ?? null,
    estimated_calories: estimate.total_calories, calorie_low: estimate.calorie_low,
    calorie_high: estimate.calorie_high, confidence: estimate.confidence,
    assumptions: estimate.assumptions, input_tokens: payload.usage?.input_tokens ?? null,
    output_tokens: payload.usage?.output_tokens ?? null, latency_ms: Date.now() - started,
    error_code: null, error_message: null, updated_at: new Date().toISOString(),
  }).eq('id', session.id)
  if (update.error) throw update.error
  const remove = await admin.from('ai_meal_items').delete().eq('session_id', session.id)
  if (remove.error) throw remove.error
  const rows = estimate.items.map((item, index) => ({
    session_id: session.id, ordinal: index + 1, predicted_name: item.name,
    predicted_portion: item.portion, predicted_grams: item.estimated_grams,
    predicted_calories: item.calories, calorie_low: item.calorie_low, calorie_high: item.calorie_high,
    confidence: item.confidence, assumptions: item.assumptions,
  }))
  const inserted = await admin.from('ai_meal_items').insert(rows).select('*').order('ordinal')
  if (inserted.error) throw inserted.error
  const nutrientRows = (inserted.data ?? []).flatMap((row: Record<string, unknown>, index: number) =>
    estimate.items[index].nutrients.map((nutrient) => ({
      ai_meal_item_id: row.id, nutrient_code: nutrient.code,
      predicted_amount: nutrient.amount, confidence: nutrient.confidence,
    })))
  if (nutrientRows.length) {
    const nutrientInsert = await admin.from('ai_meal_item_nutrients').insert(nutrientRows)
    if (nutrientInsert.error) throw nutrientInsert.error
  }
  let followUp = null
  if (estimate.status === 'needs_clarification' && estimate.follow_up_question) {
    const ordinal = Number(session.follow_up_count ?? 0) + 1
    const created = await admin.from('ai_meal_follow_ups').insert({
      session_id: session.id, ordinal, question: estimate.follow_up_question,
    }).select('*').single()
    if (created.error) throw created.error
    followUp = created.data
    const countUpdate = await admin.from('ai_meal_sessions').update({ follow_up_count: ordinal }).eq('id', session.id)
    if (countUpdate.error) throw countUpdate.error
  }
  return sessionResponse(session.id, estimate, inserted.data ?? [], followUp)
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
      nutrients: estimate.items[index]?.nutrients ?? [],
    })),
    follow_up: followUp ? { id: followUp.id, ordinal: followUp.ordinal, question: followUp.question } : null,
  }
}

// deno-lint-ignore no-explicit-any
async function persistConfirmedNutrients(admin: any, userID: string, sessionID: string, requested: { id: string; name: string; portion: string; calories: number }[]) {
  const ids = requested.map((item) => item.id)
  const { data: items, error: itemError } = await admin.from('ai_meal_items')
    .select('id,food_entry_id').eq('session_id', sessionID).in('id', ids)
  if (itemError) throw itemError
  for (const item of items ?? []) {
    if (!item.food_entry_id) continue
    const [{ data: predictions, error: predictionError }, { data: consumption, error: consumptionError }] = await Promise.all([
      admin.from('ai_meal_item_nutrients').select('nutrient_code,predicted_amount,confidence').eq('ai_meal_item_id', item.id),
      admin.from('consumption_items').select('id').eq('legacy_food_entry_id', item.food_entry_id).eq('user_id', userID).single(),
    ])
    if (predictionError) throw predictionError
    if (consumptionError) throw consumptionError
    const snapshots = (predictions ?? []).map((nutrient: Record<string, unknown>) => ({
      consumption_item_id: consumption.id, nutrient_code: nutrient.nutrient_code,
      amount: nutrient.predicted_amount, derivation_method: 'estimated',
      source_version: 'leafy-meal-v2', confidence: nutrient.confidence,
    }))
    if (snapshots.length) {
      const saved = await admin.from('consumption_item_nutrients').upsert(snapshots, { onConflict: 'consumption_item_id,nutrient_code' })
      if (saved.error) throw saved.error
    }
  }
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
