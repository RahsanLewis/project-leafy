import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'
import { calculateAndPersistPFQS } from '../_shared/pfqs/persistence.ts'
import type { PFQSNutrientCode, PFQSNutrients } from '../_shared/pfqs/types.ts'

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void }

type Row = Record<string, unknown>
type Body = {
  action?: 'start' | 'register_asset' | 'extract' | 'enqueue' | 'submit' | 'list' | 'detail' | 'delete_draft' | 'log'
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
  serving_count?: number
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

const verificationSchema = {
  type: 'object', additionalProperties: false,
  required: ['exact_gtin_match', 'product_name', 'brand_name', 'source_quality', 'matched_fields', 'conflict_fields', 'summary'],
  properties: {
    exact_gtin_match: { type: 'boolean' },
    product_name: { type: 'string' },
    brand_name: { type: 'string' },
    source_quality: { type: 'string', enum: ['manufacturer', 'usda', 'retailer', 'database', 'other', 'none'] },
    matched_fields: { type: 'array', items: { type: 'string' }, maxItems: 20 },
    conflict_fields: { type: 'array', items: { type: 'string' }, maxItems: 20 },
    summary: { type: 'string' },
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
    if (action === 'list') {
      EdgeRuntime.waitUntil(resumeReadyJobs(admin, user.id).catch((error) => console.error('catalog retry resume failed', error)))
      return json({ contributions: await list(admin, user.id) })
    }
    if (!body.contribution_id) return json({ error: 'A contribution identifier is required.' }, 400)
    const contribution = await owned(admin, user.id, body.contribution_id)
    if (action === 'detail') return json({ contribution: await detail(admin, contribution) })
    if (action === 'register_asset') return json({ contribution: await registerAsset(admin, contribution, body) })
    if (action === 'extract') return json({ contribution: await extract(admin, user.id, contribution) })
    if (action === 'enqueue') {
      const queued = await enqueueAutomation(admin, user.id, contribution, body)
      EdgeRuntime.waitUntil(runAutomation(admin, user.id, String(contribution.id)).catch((error) => {
        console.error('catalog automation background task failed', error)
      }))
      return json({ outcome: 'processing', contribution: queued, food_version_id: null }, 202)
    }
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
    .in('status', ['draft', 'processing', 'pending_review', 'needs_review']).order('updated_at', { ascending: false }).limit(1).maybeSingle()
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

async function resumeReadyJobs(admin: any, userID: string) {
  const ready = await admin.from('catalog_contribution_jobs').select('contribution_id')
    .eq('user_id', userID).in('status', ['queued', 'retry_wait']).lte('next_attempt_at', new Date().toISOString()).limit(3)
  if (ready.error) throw ready.error
  await Promise.all((ready.data ?? []).map((job: Row) => runAutomation(admin, userID, String(job.contribution_id))))
}

async function detail(admin: any, contribution: Row) {
  const assets = await admin.from('product_label_assets').select('id,asset_kind,object_path,created_at').eq('contribution_id', contribution.id)
  if (assets.error) throw assets.error
  const nutrients = await admin.from('catalog_contribution_nutrients').select('nutrient_code,amount_per_serving,unit,percent_daily_value,confidence').eq('contribution_id', contribution.id).eq('revision', contribution.revision)
  if (nutrients.error) throw nutrients.error
  const job = await admin.from('catalog_contribution_jobs').select('status,last_error,completed_at').eq('contribution_id', contribution.id).maybeSingle()
  if (job.error) throw job.error
  return {
    ...contribution,
    assets: assets.data ?? [],
    nutrients: nutrients.data ?? [],
    extraction_diagnostics: extractionDiagnostics(contribution),
    processing_stage: job.data?.status ?? null,
  }
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
  const validation = validate(extracted, extracted.nutrients, extracted)
  const update = await admin.from('catalog_contributions').update({
    extracted_fields: extracted,
    validation_results: validation,
    updated_at: new Date().toISOString(),
  }).eq('id', contribution.id).select('*').single()
  if (update.error) throw update.error
  return detail(admin, update.data)
}

async function enqueueAutomation(admin: any, userID: string, contribution: Row, body: Body) {
  assertEditable(contribution)
  if (body.consent_version !== 1) throw new Error('Review the current catalog contribution terms before submitting.')
  const assets = await admin.from('product_label_assets').select('asset_kind').eq('contribution_id', contribution.id)
  if (assets.error) throw assets.error
  const kinds = new Set((assets.data ?? []).map((row: Row) => String(row.asset_kind)))
  if (!kinds.has('front')) throw new Error('Add a clear photo of the package front.')
  if (!kinds.has('back_label') && !(kinds.has('nutrition_facts') && kinds.has('ingredients'))) {
    throw new Error('Add a clear photo showing Nutrition Facts and ingredients.')
  }
  const requestedLog = body.serving_count == null ? null : {
    serving_count: number(body.serving_count, 0.25, 100),
    consumed_at: body.consumed_at,
    local_date: body.local_date,
    time_zone: body.time_zone,
    meal_type: body.meal_type ?? 'unspecified',
  }
  const now = new Date().toISOString()
  const update = await admin.from('catalog_contributions').update({
    status: 'processing', consent_version: 1, submitted_at: contribution.submitted_at ?? now,
    review_reason: null, automation_version: 'catalog-automation-1.0', updated_at: now,
  }).eq('id', contribution.id).select('*').single()
  if (update.error) throw update.error
  const job = await admin.from('catalog_contribution_jobs').upsert({
    contribution_id: contribution.id, user_id: userID, status: 'queued', attempts: 0,
    next_attempt_at: now, requested_log: requestedLog, last_error: null,
    started_at: null, completed_at: null, updated_at: now,
  }, { onConflict: 'contribution_id' })
  if (job.error) throw job.error
  await event(admin, String(contribution.id), 'user', String(contribution.status), 'processing', 'Two-photo automated verification started')
  return detail(admin, update.data)
}

async function runAutomation(admin: any, userID: string, contributionID: string) {
  const startedAt = new Date().toISOString()
  const claimed = await admin.from('catalog_contribution_jobs').update({
    status: 'extracting', started_at: startedAt, updated_at: startedAt,
  }).eq('contribution_id', contributionID).in('status', ['queued', 'retry_wait']).select('*').maybeSingle()
  if (claimed.error) throw claimed.error
  if (!claimed.data) return
  try {
    let contribution = await owned(admin, userID, contributionID)
    const extractedContribution = await extract(admin, userID, contribution)
    const diagnostics = extractedContribution.extraction_diagnostics ?? extractionDiagnostics(extractedContribution as unknown as Row)
    if (diagnostics?.status === 'needs_photos') {
      const firstRetake = Number(contribution.retake_count ?? 0) < 1
      const status = firstRetake ? 'needs_review' : 'pending_review'
      const message = firstRetake ? String(diagnostics.message) : 'Leafy could not confidently read every required label detail. Our catalog team will review it.'
      const updated = await admin.from('catalog_contributions').update({
        status, retake_count: firstRetake ? 1 : contribution.retake_count,
        review_reason: message, updated_at: new Date().toISOString(),
      }).eq('id', contributionID)
      if (updated.error) throw updated.error
      await finishJob(admin, contributionID, 'complete', null)
      await event(admin, contributionID, 'automatic', 'processing', status, message)
      return
    }

    contribution = await owned(admin, userID, contributionID)
    const fields = normalizeFields(contribution.extracted_fields as Row ?? {})
    const nutrients = normalizeNutrients((contribution.extracted_fields as Row)?.nutrients ?? [])
    const validation = validate(fields, nutrients, contribution.extracted_fields as Row ?? {})
    const revisionNumber = Number(contribution.revision ?? 1)
    await persistAutomatedRevision(admin, contributionID, revisionNumber, contribution.extracted_fields as Row ?? {}, fields, nutrients, validation)

    const verifying = await admin.from('catalog_contribution_jobs').update({ status: 'verifying', updated_at: new Date().toISOString() }).eq('contribution_id', contributionID)
    if (verifying.error) throw verifying.error
    const verification = await verifyIdentityOnline(userID, String(contribution.gtin), String(contribution.market_country), fields)
    await persistVerificationSources(
      admin, contributionID, revisionNumber, verification.sources,
      verification.result.exact_gtin_match === true, verification.result.matched_fields,
    )
    const identityAgreement = verification.result.exact_gtin_match === true &&
      verification.result.conflict_fields.length === 0 &&
      namesAgree(String(fields.product_name), verification.result.product_name) &&
      (Boolean(fields.brand_not_shown) || namesAgree(String(fields.brand_name), verification.result.brand_name))
    const trustedSource = ['manufacturer', 'usda', 'retailer', 'database'].includes(verification.result.source_quality)
    const autoPublish = validation.auto_approve === true && identityAgreement && trustedSource

    // A private nutrient snapshot can be logged before the shared product is published.
    const job = await admin.from('catalog_contribution_jobs').select('requested_log').eq('contribution_id', contributionID).single()
    if (job.error) throw job.error
    const requestedLog = job.data?.requested_log as Row | null
    if (requestedLog && !requestedLog.logged_entry_id) {
      const provisional = { ...contribution, status: 'pending_review', confirmed_fields: fields, accepted_food_version_id: null }
      const servingGrams = Number(fields.serving_grams)
      const logBody = {
        ...requestedLog,
        grams: servingGrams * Number(requestedLog.serving_count ?? 1),
      } as Body
      const entry = await logContribution(admin, userID, provisional, logBody)
      const savedLog = await admin.from('catalog_contribution_jobs').update({
        requested_log: { ...requestedLog, logged_entry_id: entry.id }, updated_at: new Date().toISOString(),
      }).eq('contribution_id', contributionID)
      if (savedLog.error) throw savedLog.error
    }

    let foodVersionID: string | null = null
    let status = 'pending_review'
    let reason = verification.result.summary || 'Leafy could not verify this package with enough confidence to publish it automatically.'
    if (autoPublish) {
      const publishing = await admin.from('catalog_contribution_jobs').update({ status: 'publishing', updated_at: new Date().toISOString() }).eq('contribution_id', contributionID)
      if (publishing.error) throw publishing.error
      const existing = await activeProduct(admin, String(contribution.gtin), String(contribution.market_country))
      foodVersionID = existing?.id ?? await publish(
        admin, contribution, fields, nutrients,
        ['manufacturer', 'usda'].includes(verification.result.source_quality) ? 'verified' : 'community_confirmed',
      )
      status = 'accepted'
      reason = 'Package details verified and added to Leafy.'
    }
    const now = new Date().toISOString()
    const update = await admin.from('catalog_contributions').update({
      status, confirmed_fields: fields, validation_results: validation,
      verification_results: verification.result, accepted_food_version_id: foodVersionID,
      last_submitted_at: now, reviewed_at: status === 'accepted' ? now : null,
      review_reason: reason, updated_at: now,
    }).eq('id', contributionID)
    if (update.error) throw update.error
    await finishJob(admin, contributionID, 'complete', null)
    await event(admin, contributionID, 'automatic', 'processing', status, reason, { verification: verification.result })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Automated product processing failed.'
    const job = await admin.from('catalog_contribution_jobs').select('attempts').eq('contribution_id', contributionID).single()
    const attempts = Number(job.data?.attempts ?? 0) + 1
    const retry = attempts < 3
    const next = new Date(Date.now() + Math.pow(2, attempts) * 30_000).toISOString()
    const failed = await admin.from('catalog_contribution_jobs').update({
      status: retry ? 'retry_wait' : 'failed', attempts, next_attempt_at: next,
      last_error: message, completed_at: retry ? null : new Date().toISOString(), updated_at: new Date().toISOString(),
    }).eq('contribution_id', contributionID)
    if (failed.error) console.error('could not save catalog job failure', failed.error)
    if (!retry) {
      await admin.from('catalog_contributions').update({
        status: 'pending_review', review_reason: 'Leafy could not finish automatic verification. Our catalog team will review it.',
        updated_at: new Date().toISOString(),
      }).eq('id', contributionID)
    }
    throw error
  }
}

async function persistAutomatedRevision(admin: any, contributionID: string, revision: number, extracted: Row, fields: Row, nutrients: NutrientInput[], validation: Row) {
  const revisionWrite = await admin.from('catalog_contribution_revisions').upsert({
    contribution_id: contributionID, revision, extracted_fields: extracted, confirmed_fields: fields, validation_results: validation,
  }, { onConflict: 'contribution_id,revision' })
  if (revisionWrite.error) throw revisionWrite.error
  await admin.from('catalog_contribution_nutrients').delete().eq('contribution_id', contributionID).eq('revision', revision)
  if (nutrients.length) {
    const write = await admin.from('catalog_contribution_nutrients').insert(nutrients.map((item) => ({
      contribution_id: contributionID, revision, nutrient_code: item.code,
      amount_per_serving: item.amount_per_serving, unit: item.unit,
      percent_daily_value: item.percent_daily_value ?? null, confidence: item.confidence ?? 1, printed_on_label: true,
    })))
    if (write.error) throw write.error
  }
}

async function verifyIdentityOnline(userID: string, gtin: string, market: string, fields: Row) {
  const key = Deno.env.get('OPENAI_API_KEY')
  if (!key) throw new Error('Online product verification is not configured yet.')
  const model = Deno.env.get('OPENAI_MEAL_MODEL') ?? 'gpt-5.6-terra'
  const prompt = `Verify the identity of packaged food barcode ${gtin} sold in ${market}. The photographed package reads product name "${fields.product_name}" and brand "${fields.brand_name}". Search exact-barcode manufacturer/brand pages and USDA branded-food records first, then reputable retailers or product databases. Do not use search-result snippets alone. Mark exact_gtin_match true only when a consulted page explicitly associates this exact barcode with the product. Report identity conflicts; do not replace package nutrition or ingredients.`
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model, store: false, reasoning: { effort: 'low' }, safety_identifier: await safetyID(userID),
      tools: [{ type: 'web_search' }], include: ['web_search_call.action.sources'],
      input: [{ role: 'system', content: [{ type: 'input_text', text: 'You verify packaged-food identity. Prefer primary sources and exact barcode matches. Return conservative structured results.' }] }, { role: 'user', content: [{ type: 'input_text', text: prompt }] }],
      text: { format: { type: 'json_schema', name: 'leafy_catalog_identity', strict: true, schema: verificationSchema } },
    }),
  })
  const payload = await response.json()
  if (!response.ok) throw new Error(payload?.error?.message ?? 'Leafy could not verify that product online.')
  const result = JSON.parse(extractOutputText(payload))
  return { result, sources: collectWebSources(payload, result.source_quality) }
}

function collectWebSources(payload: Row, fallbackKind: string) {
  const found = new Map<string, Row>()
  const visit = (value: unknown) => {
    if (Array.isArray(value)) { value.forEach(visit); return }
    if (!value || typeof value !== 'object') return
    const row = value as Row
    if (typeof row.url === 'string' && /^https?:\/\//.test(row.url)) {
      found.set(row.url, { url: row.url, title: String(row.title ?? ''), source_kind: normalizeSourceKind(fallbackKind) })
    }
    Object.values(row).forEach(visit)
  }
  visit(payload.output)
  return [...found.values()]
}

async function persistVerificationSources(admin: any, contributionID: string, revision: number, sources: Row[], exactGTINMatch: boolean, matchedFields: unknown) {
  if (!sources.length) return
  const rows = await Promise.all(sources.map(async (source) => {
    const parsed = new URL(String(source.url))
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(String(source.url)))
    return {
      contribution_id: contributionID, revision, url: String(source.url), title: String(source.title ?? ''),
      domain: parsed.hostname, source_kind: normalizeSourceKind(String(source.source_kind ?? 'other')),
      exact_gtin_match: exactGTINMatch,
      matched_fields: Array.isArray(matchedFields) ? matchedFields.map(String).slice(0, 20) : [],
      content_hash: [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join(''),
    }
  }))
  const write = await admin.from('catalog_verification_sources').upsert(rows, { onConflict: 'contribution_id,revision,url' })
  if (write.error) throw write.error
}

function normalizeSourceKind(value: string) {
  return ['manufacturer', 'usda', 'retailer', 'database'].includes(value) ? value : 'other'
}

function namesAgree(left: string, right: string) {
  const tokens = (value: string) => new Set(value.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter((item) => item.length > 1))
  const a = tokens(left); const b = tokens(right)
  if (!a.size || !b.size) return false
  const intersection = [...a].filter((item) => b.has(item)).length
  return intersection / Math.min(a.size, b.size) >= 0.6
}

async function finishJob(admin: any, contributionID: string, status: string, error: string | null) {
  const result = await admin.from('catalog_contribution_jobs').update({
    status, last_error: error, completed_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  }).eq('contribution_id', contributionID)
  if (result.error) throw result.error
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
function extractionDiagnostics(contribution: Row) {
  const extracted = contribution.extracted_fields as Row | null
  if (!extracted || !Object.keys(extracted).length) return null
  const validation = contribution.validation_results as Row ?? validate(
    extracted,
    normalizeNutrients(extracted.nutrients),
    extracted,
  )
  const missing = Array.isArray(validation.missing_fields)
    ? validation.missing_fields.map(String)
    : []
  const evidence = extracted.evidence as Row ?? {}
  const requested = new Set<string>()
  if (evidence.front_legible !== true || missing.some((field) => field === 'Product name' || field === 'Brand')) {
    requested.add('front')
  }
  if (
    evidence.nutrition_facts_legible !== true ||
    validation.calorie_consistent === false ||
    missing.some((field) => field === 'Serving weight' || field === 'Serving description' || requiredNutrients.includes(field))
  ) requested.add('nutrition_facts')
  if (evidence.ingredients_legible !== true || missing.includes('Ingredients')) requested.add('ingredients')
  if (missing.includes('Clear package evidence')) {
    if (evidence.front_legible !== true) requested.add('front')
    if (evidence.nutrition_facts_legible !== true) requested.add('nutrition_facts')
    if (evidence.ingredients_legible !== true) requested.add('ingredients')
  }
  const needsPhotos = requested.size > 0 || missing.length > 0 || validation.calorie_consistent === false
  const requestedAssets = [...requested]
  const names: Record<string, string> = {
    front: 'the package front', nutrition_facts: 'the Nutrition Facts label', ingredients: 'the ingredients list',
  }
  const targets = requestedAssets.map((item) => names[item]).filter(Boolean)
  return {
    status: needsPhotos ? 'needs_photos' : 'complete',
    missing_fields: missing,
    requested_assets: requestedAssets,
    message: needsPhotos
      ? `Leafy needs a clearer photo of ${joinReadable(targets)}.`
      : 'Leafy read the package label successfully.',
  }
}
function joinReadable(values: string[]) {
  if (!values.length) return 'the missing label information'
  if (values.length === 1) return values[0]
  if (values.length === 2) return `${values[0]} and ${values[1]}`
  return `${values.slice(0, -1).join(', ')}, and ${values.at(-1)}`
}
function extractionPrompt(barcode: string) { return `The scanned barcode is ${barcode}. Read the product front and U.S. Nutrition Facts / ingredients evidence. Product name should be specific but concise. Capture printed amounts per serving for every standard nutrient code in the schema. For a nutrient not visible, return -1 so it can be flagged for review. Ingredients must be a faithful transcription. Do not invent a brand, serving, ingredient, nutrient, or allergen.` }
function clean(value: unknown, max: number) { return typeof value === 'string' ? value.trim().slice(0, max) : '' }
function number(value: unknown, min: number, max: number) { const parsed = Number(value); return Number.isFinite(parsed) ? Math.min(Math.max(parsed, min), max) : min }
function normalizeBarcode(value: string) { const digits = String(value).replace(/\D/g, ''); return digits.length >= 8 && digits.length <= 14 ? digits : '' }
function format(value: number) { return Number.isInteger(value) ? String(value) : value.toFixed(1) }
function assertEditable(contribution: Row) { if (!['draft', 'needs_review', 'processing'].includes(String(contribution.status))) throw new Error('This submission can no longer be edited.') }
async function owned(admin: any, userID: string, id: string) { const result = await admin.from('catalog_contributions').select('*').eq('id', id).eq('user_id', userID).single(); if (result.error || !result.data) throw new Error('Contribution not found.'); return result.data }
async function activeProduct(admin: any, gtin: string, market: string) { const result = await admin.from('food_versions').select('id').eq('gtin', gtin).eq('market_country', market).is('superseded_at', null).neq('verification_status', 'rejected').maybeSingle(); if (result.error) throw result.error; return result.data }
async function touch(admin: any, id: string) { const result = await admin.from('catalog_contributions').update({ updated_at: new Date().toISOString() }).eq('id', id); if (result.error) throw result.error }
async function event(admin: any, id: string, actor: string, from: string | null, to: string, reason?: string, metadata: Row = {}) { const result = await admin.from('catalog_contribution_events').insert({ contribution_id: id, actor_type: actor, from_status: from, to_status: to, reason: reason ?? null, metadata }); if (result.error) throw result.error }
function extractOutputText(payload: Row) { for (const item of (Array.isArray(payload.output) ? payload.output : []) as Row[]) for (const part of (Array.isArray(item.content) ? item.content : []) as Row[]) if (part.type === 'output_text' && typeof part.text === 'string') return part.text; throw new Error('The label extractor returned no structured result.') }
function toBase64(bytes: Uint8Array) { let binary = ''; const chunk = 0x8000; for (let index = 0; index < bytes.length; index += chunk) binary += String.fromCharCode(...bytes.subarray(index, Math.min(index + chunk, bytes.length))); return btoa(binary) }
async function safetyID(userID: string) { const salt = Deno.env.get('OPENAI_SAFETY_SALT') ?? Deno.env.get('SUPABASE_URL') ?? 'leafy'; const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${salt}:${userID}`)); return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('') }
