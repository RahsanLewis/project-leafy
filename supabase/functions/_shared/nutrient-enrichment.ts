import { nutrientCodes, nutrientUnits, normalizeNutrients } from './nutrients.ts'
import { scoreFoodEntry } from './pfqs/entry.ts'

type Admin = any // Supabase client type is supplied by the edge runtime.
type Row = Record<string, unknown>

export async function processNutrientJobs(admin: Admin, userID: string, limit = 3) {
  const ready = await admin.from('nutrient_enrichment_jobs')
    .select('id,consumption_item_id,attempts').eq('user_id', userID)
    .in('status', ['queued', 'retry_wait']).lte('next_attempt_at', new Date().toISOString())
    .order('created_at').limit(limit)
  if (ready.error) throw ready.error
  for (const job of ready.data ?? []) await processJob(admin, userID, job as Row)
}

async function processJob(admin: Admin, userID: string, job: Row) {
  const jobID = String(job.id)
  const claimed = await admin.from('nutrient_enrichment_jobs').update({
    status: 'processing', started_at: new Date().toISOString(),
    attempts: Number(job.attempts ?? 0) + 1, updated_at: new Date().toISOString(),
  }).eq('id', jobID).in('status', ['queued', 'retry_wait']).select('id').maybeSingle()
  if (claimed.error || !claimed.data) return
  try {
    const itemResult = await admin.from('consumption_items')
      .select('id,user_id,food_version_id,description,calories_kcal,normalized_grams,portion_description')
      .eq('id', job.consumption_item_id).eq('user_id', userID).is('deleted_at', null).single()
    if (itemResult.error) throw itemResult.error
    const item = itemResult.data as Row
    const existingResult = await admin.from('consumption_item_nutrients')
      .select('nutrient_code').eq('consumption_item_id', item.id)
    if (existingResult.error) throw existingResult.error
    const existing = new Set((existingResult.data ?? []).map((row: Row) => String(row.nutrient_code)))

    // Reuse canonical food nutrients before spending an API call.
    if (item.food_version_id && Number(item.normalized_grams ?? 0) > 0) {
      const cached = await admin.from('food_version_nutrients').select('nutrient_code,amount_per_100g,derivation_method,source_version,confidence')
        .eq('food_version_id', item.food_version_id)
      if (cached.error) throw cached.error
      const grams = Number(item.normalized_grams)
      const snapshots = (cached.data ?? []).filter((row: Row) => !existing.has(String(row.nutrient_code))).map((row: Row) => ({
        consumption_item_id: item.id, nutrient_code: row.nutrient_code,
        amount: Number(row.amount_per_100g) * grams / 100,
        derivation_method: row.derivation_method, source_version: row.source_version, confidence: row.confidence,
      }))
      if (snapshots.length) {
        const saved = await admin.from('consumption_item_nutrients').insert(snapshots)
        if (saved.error) throw saved.error
        snapshots.forEach((row: Row) => existing.add(String(row.nutrient_code)))
      }
    }

    const missing = nutrientCodes.filter((code) => !existing.has(code))
    if (missing.length) {
      const estimates = await estimateMissingNutrients(userID, item, missing)
      const snapshots = estimates.map((value) => ({
        consumption_item_id: item.id, nutrient_code: value.code, amount: value.amount,
        derivation_method: 'estimated', source_version: 'leafy-nutrient-enrichment-1', confidence: value.confidence,
      }))
      const saved = await admin.from('consumption_item_nutrients').insert(snapshots)
      if (saved.error) throw saved.error

      // Cache reusable per-100g estimates without overwriting label or laboratory data.
      const grams = Number(item.normalized_grams ?? 0)
      if (item.food_version_id && grams > 0) {
        const cache = estimates.map((value) => ({
          food_version_id: item.food_version_id, nutrient_code: value.code,
          amount_per_100g: value.amount * 100 / grams, derivation_method: 'estimated',
          source_version: 'leafy-nutrient-enrichment-1', confidence: value.confidence,
        }))
        const cached = await admin.from('food_version_nutrients').insert(cache)
        // A concurrent worker may already have filled a code; snapshots remain valid.
        if (cached.error && cached.error.code !== '23505') throw cached.error
      }
    }
    const source = [item.description, item.calories_kcal, item.normalized_grams, item.portion_description, item.food_version_id].join('|')
    await admin.from('nutrient_enrichment_jobs').update({
      status: 'complete', source_hash: await sha256(source), model_version: 'leafy-nutrient-enrichment-1',
      last_error: null, completed_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    }).eq('id', jobID)
    const legacy = await admin.from('consumption_items').select('legacy_food_entry_id').eq('id', item.id).maybeSingle()
    if (legacy.error) throw legacy.error
    if (legacy.data?.legacy_food_entry_id) await scoreFoodEntry(admin, String(legacy.data.legacy_food_entry_id), userID)
  } catch (error) {
    const attempts = Number(job.attempts ?? 0) + 1
    const terminal = attempts >= 3
    await admin.from('nutrient_enrichment_jobs').update({
      status: terminal ? 'failed' : 'retry_wait',
      next_attempt_at: new Date(Date.now() + Math.pow(2, attempts) * 30_000).toISOString(),
      last_error: error instanceof Error ? error.message.slice(0, 500) : 'Nutrient enrichment failed.',
      updated_at: new Date().toISOString(),
    }).eq('id', jobID)
  }
}

async function estimateMissingNutrients(userID: string, item: Row, missing: string[]) {
  const key = Deno.env.get('OPENAI_API_KEY')
  if (!key) throw new Error('Nutrient estimates are not configured.')
  const model = Deno.env.get('OPENAI_MEAL_MODEL') ?? 'gpt-5.6-terra'
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model, store: false, reasoning: { effort: 'low' }, safety_identifier: await sha256(`leafy:${userID}`),
      input: [
        { role: 'system', content: [{ type: 'input_text', text: `Estimate the requested missing nutrients for a food log. Return every requested code exactly once, including likely-zero values. Do not alter known label values. Units: ${missing.map((code) => `${code}=${nutrientUnits[code as keyof typeof nutrientUnits]}`).join(', ')}. Use conservative central estimates and lower confidence for uncertain micronutrients.` }] },
        { role: 'user', content: [{ type: 'input_text', text: `Food: ${item.description}\nCalories: ${item.calories_kcal}\nServing: ${item.portion_description ?? 'unspecified'}\nGrams: ${item.normalized_grams ?? 'unspecified'}\nRequired codes: ${missing.join(', ')}` }] },
      ],
      text: { format: { type: 'json_schema', name: 'leafy_missing_nutrients', strict: true, schema: {
        type: 'object', additionalProperties: false, required: ['nutrients'], properties: { nutrients: {
          type: 'array', minItems: missing.length, maxItems: missing.length,
          items: { type: 'object', additionalProperties: false, required: ['code', 'amount', 'confidence'], properties: {
            code: { type: 'string', enum: missing }, amount: { type: 'number' }, confidence: { type: 'number' },
          } },
        } },
      } } },
    }),
  })
  const payload = await response.json()
  if (!response.ok) throw new Error(payload?.error?.message ?? 'The nutrient service is unavailable.')
  const output = typeof payload.output_text === 'string' ? payload.output_text : payload.output?.flatMap((value: Row) => value.content ?? []).find((value: Row) => value.type === 'output_text')?.text
  if (typeof output !== 'string') throw new Error('The nutrient service returned no estimate.')
  const values = normalizeNutrients(JSON.parse(output).nutrients).filter((value) => missing.includes(value.code))
  if (new Set(values.map((value) => value.code)).size !== missing.length) throw new Error('The nutrient estimate was incomplete.')
  return values
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}
