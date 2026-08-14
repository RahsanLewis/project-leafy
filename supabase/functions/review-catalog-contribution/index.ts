import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'
import { calculateAndPersistPFQS } from '../_shared/pfqs/persistence.ts'
import type { PFQSNutrientCode, PFQSNutrients } from '../_shared/pfqs/types.ts'

type Row = Record<string, unknown>

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const reviewKey = Deno.env.get('CATALOG_REVIEW_KEY')
    if (!reviewKey || request.headers.get('x-leafy-admin-key') !== reviewKey) return json({ error: 'Unauthorized' }, 401)
    const url = Deno.env.get('SUPABASE_URL')!
    const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')!
    const admin = createClient(url, secret)
    const body = await request.json().catch(() => ({})) as { action?: string; contribution_id?: string; reason?: string }
    if ((body.action ?? 'list') === 'list') {
      const result = await admin.from('catalog_contributions').select('*').eq('status', 'pending_review').order('last_submitted_at').limit(100)
      if (result.error) throw result.error
      return json({ contributions: result.data ?? [] })
    }
    if (!body.contribution_id) throw new Error('A contribution identifier is required.')
    const contributionResult = await admin.from('catalog_contributions').select('*').eq('id', body.contribution_id).single()
    if (contributionResult.error) throw contributionResult.error
    const contribution = contributionResult.data
    if (body.action === 'detail') return json({ contribution: await withEvidence(admin, contribution) })
    if (contribution.status !== 'pending_review') throw new Error('Only pending submissions can be moderated.')
    if (body.action === 'request_changes') return json({ contribution: await transition(admin, contribution, 'needs_review', body.reason || 'Please review the submitted label information.', 'admin') })
    if (body.action === 'reject') return json({ contribution: await transition(admin, contribution, 'rejected', body.reason || 'This submission could not be verified.', 'admin') })
    if (body.action === 'approve') {
      const existing = await admin.from('food_versions').select('id').eq('gtin', contribution.gtin).eq('market_country', contribution.market_country).is('superseded_at', null).neq('verification_status', 'rejected').maybeSingle()
      if (existing.error) throw existing.error
      const foodVersionID = existing.data?.id ?? await publish(admin, contribution)
      const now = new Date().toISOString()
      const update = await admin.from('catalog_contributions').update({ status: 'accepted', accepted_food_version_id: foodVersionID, reviewed_at: now, review_reason: body.reason || 'Approved by Leafy review.', updated_at: now }).eq('id', contribution.id).select('*').single()
      if (update.error) throw update.error
      await addEvent(admin, contribution.id, 'pending_review', 'accepted', body.reason || 'Approved by Leafy review.')
      return json({ contribution: update.data, food_version_id: foodVersionID })
    }
    throw new Error('Unsupported review action.')
  } catch (error) {
    console.error('review-catalog-contribution failed', error)
    return json({ error: error instanceof Error ? error.message : 'Unable to review that product.' }, 400)
  }
})

async function withEvidence(admin: any, contribution: Row) {
  const assets = await admin.from('product_label_assets').select('id,asset_kind,object_path').eq('contribution_id', contribution.id)
  if (assets.error) throw assets.error
  const evidence = await Promise.all((assets.data ?? []).map(async (asset: Row) => {
    const signed = await admin.storage.from('nutrition-media').createSignedUrl(String(asset.object_path), 900)
    if (signed.error) throw signed.error
    return { id: asset.id, asset_kind: asset.asset_kind, signed_url: signed.data.signedUrl }
  }))
  const nutrients = await admin.from('catalog_contribution_nutrients').select('*').eq('contribution_id', contribution.id).eq('revision', contribution.revision)
  if (nutrients.error) throw nutrients.error
  return { ...contribution, evidence, nutrients: nutrients.data ?? [] }
}

async function transition(admin: any, contribution: Row, status: string, reason: string, actor: string) {
  const update = await admin.from('catalog_contributions').update({ status, review_reason: reason, reviewed_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq('id', contribution.id).select('*').single()
  if (update.error) throw update.error
  const event = await admin.from('catalog_contribution_events').insert({ contribution_id: contribution.id, actor_type: actor, from_status: contribution.status, to_status: status, reason })
  if (event.error) throw event.error
  return update.data
}

async function publish(admin: any, contribution: Row) {
  const fields = contribution.confirmed_fields as Row
  const nutrientsResult = await admin.from('catalog_contribution_nutrients').select('*').eq('contribution_id', contribution.id).eq('revision', contribution.revision)
  if (nutrientsResult.error) throw nutrientsResult.error
  const foods = await admin.from('foods').insert({ canonical_name: fields.product_name }).select('id').single()
  if (foods.error) throw foods.error
  const version = await admin.from('food_versions').insert({
    food_id: foods.data.id, source_system: 'leafy', source_record_id: String(contribution.id), source_data_type: 'community_label',
    description: fields.product_name, brand_name: fields.brand_not_shown ? null : fields.brand_name, gtin: contribution.gtin,
    market_country: contribution.market_country, ingredients_text: fields.ingredients, allergens: fields.allergens ?? [],
    serving_size: fields.serving_grams, serving_unit: 'g', verification_status: 'community_confirmed',
    raw_source: { contribution_id: contribution.id, revision: contribution.revision, reviewed: true },
  }).select('id').single()
  if (version.error) throw version.error
  const per100 = (nutrientsResult.data ?? []).map((item: Row) => ({ food_version_id: version.data.id, nutrient_code: item.nutrient_code, amount_per_100g: Number((Number(item.amount_per_serving) * 100 / Number(fields.serving_grams)).toFixed(6)), derivation_method: 'label' }))
  const nutrients = await admin.from('food_version_nutrients').insert(per100)
  if (nutrients.error) throw nutrients.error
  const portion = await admin.from('food_portions').insert({ food_version_id: version.data.id, amount: 1, unit: 'serving', description: fields.serving_description, gram_weight: fields.serving_grams, source: 'leafy_label' })
  if (portion.error) throw portion.error
  const pfqsNutrients = (nutrientsResult.data ?? []).filter((item: Row) => isPFQSNutrient(String(item.nutrient_code)))
  const labelWrite = await admin.from('pfqs_label_nutrients').upsert(pfqsNutrients.map((item: Row) => ({
    food_version_id: version.data.id, nutrient_code: item.nutrient_code, amount_per_serving: item.amount_per_serving,
    unit: item.unit, explicitly_reported: item.printed_on_label === true, source_method: 'human_review',
    source_version: `leafy-contribution:${contribution.id}:${contribution.revision}`, confidence: item.confidence ?? 1,
  })), { onConflict: 'food_version_id,nutrient_code' })
  if (labelWrite.error) throw labelWrite.error
  await calculateAndPersistPFQS(admin, version.data.id, {
    product_name: String(fields.product_name), jurisdiction: String(contribution.market_country ?? 'US'),
    assessment_date: new Date().toISOString().slice(0, 10),
    serving_size: { amount: Number(fields.serving_grams), unit: 'g', description: String(fields.serving_description ?? '') },
    nutrition: Object.fromEntries(pfqsNutrients.map((item: Row) => [String(item.nutrient_code), Number(item.amount_per_serving)])) as PFQSNutrients,
    explicitly_reported_nutrients: pfqsNutrients.filter((item: Row) => item.printed_on_label === true).map((item: Row) => String(item.nutrient_code) as PFQSNutrientCode),
    ingredients_raw: String(fields.ingredients ?? ''), verification_status: 'community_confirmed', product_type: 'food',
  })
  return String(version.data.id)
}

function isPFQSNutrient(value: string): value is PFQSNutrientCode {
  return ['energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg', 'saturated_fat_g', 'trans_fat_g', 'protein_g'].includes(value)
}

async function addEvent(admin: any, id: string, from: string, to: string, reason: string) {
  const result = await admin.from('catalog_contribution_events').insert({ contribution_id: id, actor_type: 'admin', from_status: from, to_status: to, reason })
  if (result.error) throw result.error
}
