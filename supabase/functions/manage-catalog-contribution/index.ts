import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'
import { calculateAndPersistPFQS } from '../_shared/pfqs/persistence.ts'
import type { PFQSNutrientCode, PFQSNutrients } from '../_shared/pfqs/types.ts'

type Row = Record<string, unknown>
type Body = {
  action?: 'start' | 'register_asset' | 'extract' | 'submit' | 'list' | 'detail' | 'delete_draft' | 'log'
  contribution_id?: string
  barcode?: string
  market_country?: string
  asset_kind?: string
  object_path?: string
  confirmed_fields?: Row
  nutrients?: NutrientInput[]
  consent_version?: number
  grams?: number
  consumed_at?: string
  local_date?: string
  time_zone?: string
  meal_type?: string
}
type NutrientInput = {
  code: string
  amount_per_serving: number
  unit: string
  percent_daily_value?: number | null
  confidence?: number
}

const requiredNutrients = [
  'energy_kcal', 'fat_g', 'saturated_fat_g', 'trans_fat_g', 'cholesterol_mg',
  'sodium_mg', 'carbohydrate_g', 'fiber_g', 'sugars_g', 'added_sugars_g',
  'protein_g', 'vitamin_d_mcg', 'calcium_mg', 'iron_mg', 'potassium_mg',
]
const units: Record<string, string> = {
  energy_kcal: 'kcal', protein_g: 'g', carbohydrate_g: 'g', fat_g: 'g', fiber_g: 'g',
  sugars_g: 'g', added_sugars_g: 'g', saturated_fat_g: 'g', trans_fat_g: 'g',
  cholesterol_mg: 'mg', sodium_mg: 'mg', potassium_mg: 'mg', calcium_mg: 'mg',
  iron_mg: 'mg', vitamin_d_mcg: 'mcg',
}
const extractionSchema = {
  type: 'object', additionalProperties: false,
  required: ['product_name', 'brand_name', 'brand_not_shown', 'serving_description', 'serving_grams', 'servings_per_container', 'ingredients', 'allergens', 'nutrients', 'evidence', 'field_confidence'],
  properties: {
    product_name: { type: 'string' }, brand_name: { type: 'string' }, brand_not_shown: { type: 'boolean' },
    serving_description: { type: 'string' }, serving_grams: { type: 'number' }, servings_per_container: { type: 'string' },
    ingredients: { type: 'string' }, allergens: { type: 'array', items: { type: 'string' }, maxItems: 30 },
    nutrients: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['code', 'amount_per_serving', 'unit', 'percent_daily_value', 'confidence'], properties: {
      code: { type: 'string', enum: requiredNutrients }, amount_per_serving: { type: 'number' },
      unit: { type: 'string', enum: ['kcal', 'g', 'mg', 'mcg'] }, percent_daily_value: { type: ['number', 'null'] },
      confidence: { type: 'number', minimum: 0, maximum: 1 },
    } } },
    evidence: { type: 'object', additionalProperties: false, required: ['front_legible', 'nutrition_facts_legible', 'ingredients_legible'], properties: {
      front_legible: { type: 'boolean' }, nutrition_facts_legible: { type: 'boolean' }, ingredients_legible: { type: 'boolean' },
    } },
    field_confidence: { type: 'number', minimum: 0, maximum: 1 },
  },
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
    const body = await request.json().catch(() => ({})) as Body
    const action = body.action ?? 'list'

    if (action === 'start') return json(await start(admin, user.id, body))
    if (action === 'list') return json({ contributions: await list(admin, user.id) })
    if (!body.contribution_id) return json({ error: 'A contribution identifier is required.' }, 400)
    const contribution = await owned(admin, user.id, body.contribution_id)
    if (action === 'detail') return json({ contribution: await detail(admin, contribution) })
    if (action === 'register_asset') return json({ contribution: await registerAsset(admin, contribution, body) })
    if (action === 'extract') return json({ contribution: await extract(admin, user.id, contribution) })
    if (action === 'submit') return json(await submit(admin, contribution, body))
    if (action === 'delete_draft') return json(await deleteDraft(admin, contribution))
    if (action === 'log') return json({ entry: await logContribution(admin, user.id, contribution, body) })
    return json({ error: 'Unsupported contribution action.' }, 400)
  } catch (error) {
    console.error('manage-catalog-contribution failed', error)
    return json({ error: error instanceof Error ? error.message : 'Unable to update that product.' }, 400)
  }
})

async function start(admin: any, userID: string, body: Body) {
  const gtin = normalizeBarcode(body.barcode ?? '')
  if (!gtin) throw new Error('Scan a valid UPC or EAN barcode.')
  const market = String(body.market_country ?? 'US').trim().toUpperCase()
  if (!/^[A-Z]{2}$/.test(market)) throw new Error('Choose a valid product market.')
  const existing = await activeProduct(admin, gtin, market)
  if (existing) return { outcome: 'existing', food_version_id: existing.id, contribution: null }
  const resumed = await admin.from('catalog_contributions').select('*').eq('user_id', userID).eq('gtin', gtin)
    .in('status', ['draft', 'needs_review']).order('updated_at', { ascending: false }).limit(1).maybeSingle()
  if (resumed.error) throw resumed.error
  if (resumed.data) return { outcome: 'contribution', contribution: await detail(admin, resumed.data) }
  const created = await admin.from('catalog_contributions').insert({ user_id: userID, gtin, market_country: market, status: 'draft' }).select('*').single()
  if (created.error) throw created.error
  await event(admin, created.data.id, 'user', null, 'draft', 'Unknown barcode contribution started')
  return { outcome: 'contribution', contribution: await detail(admin, created.data) }
}

async function list(admin: any, userID: string) {
  const result = await admin.from('catalog_contributions').select('*').eq('user_id', userID).order('updated_at', { ascending: false }).limit(100)
  if (result.error) throw result.error
  return result.data ?? []
}

async function detail(admin: any, contribution: Row) {
  const assets = await admin.from('product_label_assets').select('id,asset_kind,object_path,created_at').eq('contribution_id', contribution.id)
  if (assets.error) throw assets.error
  const nutrients = await admin.from('catalog_contribution_nutrients').select('nutrient_code,amount_per_serving,unit,percent_daily_value,confidence').eq('contribution_id', contribution.id).eq('revision', contribution.revision)
  if (nutrients.error) throw nutrients.error
  return { ...contribution, assets: assets.data ?? [], nutrients: nutrients.data ?? [] }
}

async function registerAsset(admin: any, contribution: Row, body: Body) {
  assertEditable(contribution)
  const kind = String(body.asset_kind ?? '')
  if (!['front', 'back_label', 'nutrition_facts', 'ingredients'].includes(kind)) throw new Error('Choose a valid label photo type.')
  const path = String(body.object_path ?? '')
  if (!path.startsWith(`${contribution.user_id}/catalog-contributions/${contribution.id}/`)) throw new Error('That label photo does not belong to this contribution.')
  const downloaded = await admin.storage.from('nutrition-media').download(path)
  if (downloaded.error) throw downloaded.error
  const bytes = new Uint8Array(await downloaded.data.arrayBuffer())
  if (!bytes.length || bytes.length > 8 * 1024 * 1024) throw new Error('Choose a label photo smaller than 8 MB.')
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  const hash = [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('')
  const previous = await admin.from('product_label_assets').select('object_path').eq('contribution_id', contribution.id).eq('asset_kind', kind).maybeSingle()
  if (previous.error) throw previous.error
  const result = await admin.from('product_label_assets').upsert({
    contribution_id: contribution.id, user_id: contribution.user_id, asset_kind: kind, object_path: path,
    content_hash: hash, metadata_stripped: true, mime_type: 'image/jpeg', byte_count: bytes.length,
  }, { onConflict: 'contribution_id,asset_kind' })
  if (result.error) throw result.error
  if (previous.data?.object_path && previous.data.object_path !== path) await admin.storage.from('nutrition-media').remove([previous.data.object_path])
  await touch(admin, String(contribution.id))
  return detail(admin, await owned(admin, String(contribution.user_id), String(contribution.id)))
}

async function extract(admin: any, userID: string, contribution: Row) {
  assertEditable(contribution)
  const assets = await admin.from('product_label_assets').select('*').eq('contribution_id', contribution.id).order('created_at')
  if (assets.error) throw assets.error
  const kinds = new Set((assets.data ?? []).map((row: Row) => row.asset_kind))
  if (!kinds.has('front')) throw new Error('Add a clear photo of the front of the package.')
  if (!kinds.has('back_label') && !(kinds.has('nutrition_facts') && kinds.has('ingredients'))) throw new Error('Add a clear back-label photo showing Nutrition Facts and ingredients.')
  const content: Row[] = [{ type: 'input_text', text: extractionPrompt(String(contribution.gtin)) }]
  for (const asset of assets.data ?? []) {
    const downloaded = await admin.storage.from('nutrition-media').download(asset.object_path)
    if (downloaded.error) throw downloaded.error
    const bytes = new Uint8Array(await downloaded.data.arrayBuffer())
    content.push({ type: 'input_text', text: `Image role: ${asset.asset_kind}` })
    content.push({ type: 'input_image', image_url: `data:image/jpeg;base64,${toBase64(bytes)}`, detail: 'high' })
  }
  const key = Deno.env.get('OPENAI_API_KEY')
  if (!key) throw new Error('Product label extraction is not configured yet.')
  const model = Deno.env.get('OPENAI_MEAL_MODEL') ?? 'gpt-5.6-terra'
  const response = await fetch('https://api.openai.com/v1/responses', { method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify({
    model, store: false, reasoning: { effort: 'low' }, safety_identifier: await safetyID(userID),
    input: [{ role: 'system', content: [{ type: 'input_text', text: 'Extract only facts visibly printed on this U.S. packaged-food label. Never infer or estimate missing nutrients. Use 0 only when the label explicitly prints 0. Return all standard nutrient codes, using an amount of -1 for a field that is not visible.' }] }, { role: 'user', content }],
    text: { format: { type: 'json_schema', name: 'leafy_product_label', strict: true, schema: extractionSchema } },
  }) })
  const payload = await response.json()
  if (!response.ok) throw new Error(payload?.error?.message ?? 'Leafy could not read that product label.')
  const extracted = JSON.parse(extractOutputText(payload))
  extracted.nutrients = normalizeNutrients(extracted.nutrients)
  const update = await admin.from('catalog_contributions').update({ extracted_fields: extracted, updated_at: new Date().toISOString() }).eq('id', contribution.id).select('*').single()
  if (update.error) throw update.error
  return detail(admin, update.data)
}

async function submit(admin: any, contribution: Row, body: Body) {
  assertEditable(contribution)
  if (body.consent_version !== 1) throw new Error('Review the current catalog contribution terms before submitting.')
  const fields = normalizeFields(body.confirmed_fields ?? {})
  const nutrients = normalizeNutrients(body.nutrients ?? [])
  const validation = validate(fields, nutrients, contribution.extracted_fields as Row ?? {})
  const nextRevision = contribution.last_submitted_at ? Number(contribution.revision ?? 1) + 1 : Number(contribution.revision ?? 1)
  const revision = await admin.from('catalog_contribution_revisions').upsert({
    contribution_id: contribution.id, revision: nextRevision,
    extracted_fields: contribution.extracted_fields ?? {}, confirmed_fields: fields, validation_results: validation,
  }, { onConflict: 'contribution_id,revision' })
  if (revision.error) throw revision.error
  const removeNutrients = await admin.from('catalog_contribution_nutrients').delete().eq('contribution_id', contribution.id).eq('revision', nextRevision)
  if (removeNutrients.error) throw removeNutrients.error
  if (nutrients.length) {
    const inserted = await admin.from('catalog_contribution_nutrients').insert(nutrients.map((item) => ({
      contribution_id: contribution.id, revision: nextRevision, nutrient_code: item.code,
      amount_per_serving: item.amount_per_serving, unit: item.unit, percent_daily_value: item.percent_daily_value ?? null,
      confidence: item.confidence ?? 1, printed_on_label: true,
    })))
    if (inserted.error) throw inserted.error
  }
  let status = validation.missing_fields.length ? 'needs_review' : validation.auto_approve ? 'accepted' : 'pending_review'
  let foodVersionID: string | null = null
  if (status === 'accepted') {
    const existing = await activeProduct(admin, String(contribution.gtin), String(contribution.market_country))
    if (existing) foodVersionID = existing.id
    else foodVersionID = await publish(admin, contribution, fields, nutrients, 'unverified')
  }
  const now = new Date().toISOString()
  const update = await admin.from('catalog_contributions').update({
    status, confirmed_fields: fields, validation_results: validation, consent_version: 1,
    revision: nextRevision,
    accepted_food_version_id: foodVersionID, submitted_at: contribution.submitted_at ?? now,
    last_submitted_at: now, reviewed_at: status === 'accepted' ? now : null,
    review_reason: validation.reason, updated_at: now,
  }).eq('id', contribution.id).select('*').single()
  if (update.error) throw update.error
  await event(admin, String(contribution.id), 'automatic', String(contribution.status), status, validation.reason, validation)
  return { outcome: status, contribution: await detail(admin, update.data), food_version_id: foodVersionID, validation_results: validation }
}

async function publish(admin: any, contribution: Row, fields: Row, nutrients: NutrientInput[], verification: string) {
  const canonical = await admin.from('foods').insert({ canonical_name: fields.product_name }).select('id').single()
  if (canonical.error) throw canonical.error
  const version = await admin.from('food_versions').insert({
    food_id: canonical.data.id, source_system: 'leafy', source_record_id: String(contribution.id), source_data_type: 'community_label',
    description: fields.product_name, brand_name: fields.brand_not_shown ? null : fields.brand_name,
    gtin: contribution.gtin, market_country: contribution.market_country, ingredients_text: fields.ingredients,
    allergens: fields.allergens ?? [], serving_size: fields.serving_grams, serving_unit: 'g',
    verification_status: verification, raw_source: { contribution_id: contribution.id, revision: contribution.revision },
  }).select('id').single()
  if (version.error) throw version.error
  const per100 = nutrients.map((item) => ({ food_version_id: version.data.id, nutrient_code: item.code, amount_per_100g: Number((item.amount_per_serving * 100 / Number(fields.serving_grams)).toFixed(6)), derivation_method: 'label' }))
  const inserted = await admin.from('food_version_nutrients').insert(per100)
  if (inserted.error) throw inserted.error
  const portion = await admin.from('food_portions').insert({ food_version_id: version.data.id, amount: 1, unit: 'serving', description: fields.serving_description, gram_weight: fields.serving_grams, source: 'leafy_label' })
  if (portion.error) throw portion.error
  const pfqsNutrients = nutrients.filter((item) => isPFQSNutrient(item.code))
  const labelWrite = await admin.from('pfqs_label_nutrients').upsert(pfqsNutrients.map((item) => ({
    food_version_id: version.data.id, nutrient_code: item.code, amount_per_serving: item.amount_per_serving,
    unit: item.unit, explicitly_reported: true, source_method: 'label',
    source_version: `leafy-contribution:${contribution.id}:${contribution.revision}`, confidence: item.confidence ?? 1,
  })), { onConflict: 'food_version_id,nutrient_code' })
  if (labelWrite.error) throw labelWrite.error
  await calculateAndPersistPFQS(admin, version.data.id, {
    product_name: String(fields.product_name), jurisdiction: String(contribution.market_country ?? 'US'),
    assessment_date: new Date().toISOString().slice(0, 10),
    serving_size: { amount: Number(fields.serving_grams), unit: 'g', description: String(fields.serving_description ?? '') },
    nutrition: Object.fromEntries(pfqsNutrients.map((item) => [item.code, item.amount_per_serving])) as PFQSNutrients,
    explicitly_reported_nutrients: pfqsNutrients.map((item) => item.code as PFQSNutrientCode),
    ingredients_raw: String(fields.ingredients ?? ''), verification_status: verification, product_type: 'food',
  })
  return String(version.data.id)
}

function isPFQSNutrient(value: string): value is PFQSNutrientCode {
  return ['energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg', 'saturated_fat_g', 'trans_fat_g', 'protein_g'].includes(value)
}

async function logContribution(admin: any, userID: string, contribution: Row, body: Body) {
  if (!['accepted', 'pending_review'].includes(String(contribution.status))) throw new Error('Finish reviewing this product before logging it.')
  if (contribution.accepted_food_version_id) throw new Error('accepted_product')
  const fields = contribution.confirmed_fields as Row
  const grams = Number(body.grams)
  const servingGrams = Number(fields.serving_grams)
  if (!Number.isFinite(grams) || grams <= 0 || grams > 5000 || !Number.isFinite(servingGrams) || servingGrams <= 0) throw new Error('Choose a valid serving amount.')
  const nutrientResult = await admin.from('catalog_contribution_nutrients').select('*').eq('contribution_id', contribution.id).eq('revision', contribution.revision)
  if (nutrientResult.error) throw nutrientResult.error
  const energy = nutrientResult.data?.find((item: Row) => item.nutrient_code === 'energy_kcal')
  if (!energy) throw new Error('This product does not have enough calorie data to log.')
  const scale = grams / servingGrams
  const entry = await admin.from('food_entries').insert({
    user_id: userID, name: fields.product_name, calories: Math.max(1, Math.round(Number(energy.amount_per_serving) * scale)),
    consumed_at: body.consumed_at, local_date: body.local_date, time_zone: body.time_zone,
    gram_weight: grams, amount: grams, amount_unit: 'g', portion_description: `${format(grams)} g`,
    meal_type: body.meal_type ?? 'unspecified', entry_source: 'barcode', calorie_method: 'nutrition_label',
    confidence: 0.85, user_confirmed: true, provenance: { source: 'leafy_contribution', contribution_id: contribution.id, revision: contribution.revision },
  }).select('*').single()
  if (entry.error) throw entry.error
  const item = await admin.from('consumption_items').select('id').eq('legacy_food_entry_id', entry.data.id).single()
  if (item.error) throw item.error
  const snapshots = (nutrientResult.data ?? []).map((nutrient: Row) => ({ consumption_item_id: item.data.id, nutrient_code: nutrient.nutrient_code, amount: Number((Number(nutrient.amount_per_serving) * scale).toFixed(6)), derivation_method: 'label', source_version: `leafy-contribution:${contribution.id}:${contribution.revision}`, confidence: 0.85 }))
  if (snapshots.length) { const result = await admin.from('consumption_item_nutrients').upsert(snapshots, { onConflict: 'consumption_item_id,nutrient_code' }); if (result.error) throw result.error }
  return entry.data
}

async function deleteDraft(admin: any, contribution: Row) {
  if (!['draft', 'needs_review'].includes(String(contribution.status))) throw new Error('Only drafts and submissions needing changes can be deleted.')
  const assets = await admin.from('product_label_assets').select('object_path').eq('contribution_id', contribution.id)
  if (assets.error) throw assets.error
  const paths = (assets.data ?? []).map((item: Row) => String(item.object_path))
  if (paths.length) { const removed = await admin.storage.from('nutrition-media').remove(paths); if (removed.error) throw removed.error }
  const removed = await admin.from('catalog_contributions').delete().eq('id', contribution.id)
  if (removed.error) throw removed.error
  return { ok: true }
}

function validate(fields: Row, nutrients: NutrientInput[], extracted: Row) {
  const missing: string[] = []
  if (!String(fields.product_name ?? '').trim()) missing.push('Product name')
  if (!String(fields.ingredients ?? '').trim()) missing.push('Ingredients')
  if (!fields.brand_not_shown && !String(fields.brand_name ?? '').trim()) missing.push('Brand')
  if (!(Number(fields.serving_grams) > 0)) missing.push('Serving weight')
  if (!String(fields.serving_description ?? '').trim()) missing.push('Serving description')
  const map = new Map(nutrients.map((item) => [item.code, item]))
  for (const code of requiredNutrients) if (!map.has(code)) missing.push(code)
  const evidence = extracted.evidence as Row ?? {}
  const evidenceComplete = evidence.front_legible === true && evidence.nutrition_facts_legible === true && evidence.ingredients_legible === true
  if (!evidenceComplete) missing.push('Clear package evidence')
  const calories = Number(map.get('energy_kcal')?.amount_per_serving)
  const macroCalories = Number(map.get('protein_g')?.amount_per_serving ?? 0) * 4 + Number(map.get('carbohydrate_g')?.amount_per_serving ?? 0) * 4 + Number(map.get('fat_g')?.amount_per_serving ?? 0) * 9
  const calorieDifference = Math.abs(calories - macroCalories)
  const calorieConsistent = Number.isFinite(calories) && calories >= 0 && calorieDifference <= Math.max(20, calories * 0.15)
  const confidence = Math.min(Number(extracted.field_confidence ?? 0), ...nutrients.map((item) => Number(item.confidence ?? 1)))
  const plausible = nutrients.every((item) => Number.isFinite(item.amount_per_serving) && item.amount_per_serving >= 0 && item.amount_per_serving <= (item.unit === 'g' ? 5000 : item.unit === 'kcal' ? 10000 : 1_000_000))
  const autoApprove = !missing.length && calorieConsistent && plausible && confidence >= 0.9
  const reason = missing.length ? `Missing or unreadable: ${missing.join(', ')}` : !calorieConsistent ? 'Calories do not closely match the printed macronutrients.' : !plausible ? 'One or more nutrient values needs review.' : confidence < 0.9 ? 'Label extraction confidence is below the automatic-publish threshold.' : 'Passed automatic label review.'
  return { missing_fields: missing, evidence_complete: evidenceComplete, calorie_consistent: calorieConsistent, calorie_difference: calorieDifference, plausible, confidence, auto_approve: autoApprove, reason }
}

function normalizeFields(raw: Row) {
  return {
    product_name: clean(raw.product_name, 180), brand_name: clean(raw.brand_name, 120), brand_not_shown: raw.brand_not_shown === true,
    serving_description: clean(raw.serving_description, 120), serving_grams: number(raw.serving_grams, 0, 5000),
    servings_per_container: clean(raw.servings_per_container, 80), ingredients: clean(raw.ingredients, 5000),
    allergens: Array.isArray(raw.allergens) ? raw.allergens.map((item) => clean(item, 100)).filter(Boolean).slice(0, 30) : [],
  }
}
function normalizeNutrients(raw: unknown): NutrientInput[] {
  if (!Array.isArray(raw)) return []
  const seen = new Set<string>()
  return raw.flatMap((value) => {
    const item = value as Row; const code = String(item.code ?? '')
    const amount = Number(item.amount_per_serving)
    if (!requiredNutrients.includes(code) || seen.has(code) || !Number.isFinite(amount) || amount < 0) return []
    seen.add(code)
    return [{ code, amount_per_serving: amount, unit: units[code], percent_daily_value: item.percent_daily_value == null ? null : number(item.percent_daily_value, 0, 10000), confidence: number(item.confidence ?? 1, 0, 1) }]
  })
}
function extractionPrompt(barcode: string) { return `The scanned barcode is ${barcode}. Read the product front and U.S. Nutrition Facts / ingredients evidence. Product name should be specific but concise. Capture printed amounts per serving for every standard nutrient code in the schema. For a nutrient not visible, return -1 so it can be flagged for review. Ingredients must be a faithful transcription. Do not invent a brand, serving, ingredient, nutrient, or allergen.` }
function clean(value: unknown, max: number) { return typeof value === 'string' ? value.trim().slice(0, max) : '' }
function number(value: unknown, min: number, max: number) { const parsed = Number(value); return Number.isFinite(parsed) ? Math.min(Math.max(parsed, min), max) : min }
function normalizeBarcode(value: string) { const digits = String(value).replace(/\D/g, ''); return digits.length >= 8 && digits.length <= 14 ? digits : '' }
function format(value: number) { return Number.isInteger(value) ? String(value) : value.toFixed(1) }
function assertEditable(contribution: Row) { if (!['draft', 'needs_review'].includes(String(contribution.status))) throw new Error('This submission can no longer be edited.') }
async function owned(admin: any, userID: string, id: string) { const result = await admin.from('catalog_contributions').select('*').eq('id', id).eq('user_id', userID).single(); if (result.error || !result.data) throw new Error('Contribution not found.'); return result.data }
async function activeProduct(admin: any, gtin: string, market: string) { const result = await admin.from('food_versions').select('id').eq('gtin', gtin).eq('market_country', market).is('superseded_at', null).neq('verification_status', 'rejected').maybeSingle(); if (result.error) throw result.error; return result.data }
async function touch(admin: any, id: string) { const result = await admin.from('catalog_contributions').update({ updated_at: new Date().toISOString() }).eq('id', id); if (result.error) throw result.error }
async function event(admin: any, id: string, actor: string, from: string | null, to: string, reason?: string, metadata: Row = {}) { const result = await admin.from('catalog_contribution_events').insert({ contribution_id: id, actor_type: actor, from_status: from, to_status: to, reason: reason ?? null, metadata }); if (result.error) throw result.error }
function extractOutputText(payload: Row) { for (const item of (Array.isArray(payload.output) ? payload.output : []) as Row[]) for (const part of (Array.isArray(item.content) ? item.content : []) as Row[]) if (part.type === 'output_text' && typeof part.text === 'string') return part.text; throw new Error('The label extractor returned no structured result.') }
function toBase64(bytes: Uint8Array) { let binary = ''; const chunk = 0x8000; for (let index = 0; index < bytes.length; index += chunk) binary += String.fromCharCode(...bytes.subarray(index, Math.min(index + chunk, bytes.length))); return btoa(binary) }
async function safetyID(userID: string) { const salt = Deno.env.get('OPENAI_SAFETY_SALT') ?? Deno.env.get('SUPABASE_URL') ?? 'leafy'; const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${salt}:${userID}`)); return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('') }
