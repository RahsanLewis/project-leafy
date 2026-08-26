import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'
import { calculateAndPersistPFQS, pfqsAPIResult } from '../_shared/pfqs/persistence.ts'
import { normalizePFQSJurisdiction } from '../_shared/pfqs/scorer.ts'
import type { PFQSNutrientCode, PFQSNutrients } from '../_shared/pfqs/types.ts'

type Body = {
  action: 'search' | 'barcode' | 'detail' | 'history' | 'logging_recents' | 'log'
  query?: string
  barcode?: string
  fdc_id?: number
  food_version_id?: string
  grams?: number
  consumed_at?: string
  local_date?: string
  time_zone?: string
  meal_type?: string
  record_history?: boolean
}

const nutrientCodes: Record<number, string> = {
  1008: 'energy_kcal', 1003: 'protein_g', 1005: 'carbohydrate_g', 1004: 'fat_g',
  1079: 'fiber_g', 2000: 'sugars_g', 1235: 'added_sugars_g', 1258: 'saturated_fat_g',
  1257: 'trans_fat_g', 1253: 'cholesterol_mg', 1093: 'sodium_mg', 1092: 'potassium_mg',
  1087: 'calcium_mg', 1089: 'iron_mg', 1090: 'magnesium_mg', 1114: 'vitamin_d_mcg',
  1106: 'vitamin_a_mcg_rae', 1162: 'vitamin_c_mg', 1109: 'vitamin_e_mg', 1185: 'vitamin_k_mcg',
  1165: 'thiamin_mg', 1166: 'riboflavin_mg', 1167: 'niacin_mg_ne', 1175: 'vitamin_b6_mg',
  1177: 'folate_mcg_dfe', 1178: 'vitamin_b12_mcg', 1176: 'biotin_mcg', 1170: 'pantothenic_acid_mg',
  1091: 'phosphorus_mg', 1100: 'iodine_mcg', 1095: 'zinc_mg', 1103: 'selenium_mcg',
  1098: 'copper_mg', 1101: 'manganese_mg', 1096: 'chromium_mcg', 1102: 'molybdenum_mcg',
  1088: 'chloride_mg', 1180: 'choline_mg', 1057: 'caffeine_mg', 1094: 'sulfur_mg',
  1221: 'histidine_g', 1212: 'isoleucine_g', 1213: 'leucine_g', 1214: 'lysine_g',
  1215: 'methionine_g', 1217: 'phenylalanine_g', 1211: 'threonine_g',
  1210: 'tryptophan_g', 1219: 'valine_g', 1216: 'cystine_g', 1218: 'tyrosine_g',
  1316: 'linoleic_acid_g', 1269: 'linoleic_acid_g',
  1404: 'alpha_linolenic_acid_g', 1270: 'alpha_linolenic_acid_g',
}

const nutrientPriority: Record<number, number> = { 1316: 1, 1269: 2, 1404: 1, 1270: 2 }

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authorization = request.headers.get('Authorization') ?? ''
    const url = Deno.env.get('SUPABASE_URL')!
    const publicKey = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!
    const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')!
    const auth = createClient(url, publicKey, { global: { headers: { Authorization: authorization } } })
    const { data: { user }, error: authError } = await auth.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)
    const admin = createClient(url, secret)
    const body = await request.json() as Body

    if (body.action === 'search') {
      const query = (body.query ?? '').trim()
      if (query.length < 2) return json({ products: [] })
      const { data: local, error } = await admin.rpc('search_food_catalog', { p_query: query, p_limit: 20 })
      if (error) throw error
      const localProducts = await Promise.all((local ?? []).map((row: Record<string, unknown>) => productForVersion(admin, String(row.food_version_id))))
      const external = localProducts.length >= 8 ? [] : await searchUSDA(query)
      return json({ products: deduplicate([...localProducts, ...external]) })
    }
    if (body.action === 'barcode') {
      const barcode = normalizeBarcode(body.barcode ?? '')
      if (!barcode) return json({ error: 'Scan a valid UPC or EAN barcode.' }, 400)
      const { data: local } = await admin.from('food_versions').select('id').eq('gtin', barcode).is('superseded_at', null).maybeSingle()
      if (local) return json({ product: await productForVersion(admin, local.id) })
      const matches = await searchUSDA(barcode)
      if (!matches.length) return json({ product: null })
      return json({ product: await importUSDA(admin, Number(matches[0].fdc_id)) })
    }
    if (body.action === 'detail') {
      let product
      if (body.food_version_id) product = await productForVersion(admin, body.food_version_id)
      else if (body.fdc_id) product = await importUSDA(admin, body.fdc_id)
      else return json({ error: 'A product identifier is required.' }, 400)
      if (body.record_history !== false) {
        await admin.from('product_analysis_history').insert({ user_id: user.id, food_version_id: product.food_version_id, discovery_method: 'search', score_snapshot: product.score })
      }
      return json({ product })
    }
    if (body.action === 'history') {
      const { data, error } = await admin.from('product_analysis_history').select('id, analyzed_at, food_version_id').eq('user_id', user.id).order('analyzed_at', { ascending: false }).limit(50)
      if (error) throw error
      const products = await Promise.all((data ?? []).map(async (row) => ({ history_id: row.id, analyzed_at: row.analyzed_at, ...(await productForVersion(admin, row.food_version_id)) })))
      return json({ products })
    }
    if (body.action === 'logging_recents') {
      const since = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString()
      const [{ data: logged, error: loggedError }, { data: viewed, error: viewedError }] = await Promise.all([
        admin.from('food_entries').select('canonical_food_version_id,consumed_at')
          .eq('user_id', user.id).not('canonical_food_version_id', 'is', null)
          .gte('consumed_at', since).order('consumed_at', { ascending: false }).limit(50),
        admin.from('product_analysis_history').select('food_version_id,analyzed_at')
          .eq('user_id', user.id).order('analyzed_at', { ascending: false }).limit(30),
      ])
      if (loggedError) throw loggedError
      if (viewedError) throw viewedError
      const ids: string[] = []
      for (const row of logged ?? []) {
        const id = String(row.canonical_food_version_id ?? '')
        if (id && !ids.includes(id)) ids.push(id)
        if (ids.length === 8) break
      }
      for (const row of viewed ?? []) {
        const id = String(row.food_version_id ?? '')
        if (id && !ids.includes(id)) ids.push(id)
        if (ids.length === 8) break
      }
      const products = await Promise.all(ids.map((id) => productForVersion(admin, id)))
      return json({ products })
    }
    if (body.action === 'log') {
      const grams = Number(body.grams)
      if (!body.food_version_id || !Number.isFinite(grams) || grams <= 0 || grams > 5000) return json({ error: 'Choose a valid serving amount.' }, 400)
      const product = await productForVersion(admin, body.food_version_id)
      const energy = product.nutrients.find((item: Record<string, unknown>) => item.code === 'energy_kcal')?.amount_per_100g
      if (!Number.isFinite(energy)) return json({ error: 'This product does not include enough calorie data to log.' }, 400)
      const calories = Math.max(1, Math.round(Number(energy) * grams / 100))
      const { data, error } = await admin.from('food_entries').insert({
        user_id: user.id, name: product.name, calories, consumed_at: body.consumed_at,
        local_date: body.local_date, time_zone: body.time_zone, gram_weight: grams,
        amount: grams, amount_unit: 'g', portion_description: `${format(grams)} g`,
        meal_type: body.meal_type ?? 'unspecified', entry_source: 'barcode', calorie_method: 'nutrition_database',
        canonical_food_version_id: body.food_version_id, confidence: verificationConfidence(product.verification_status),
        user_confirmed: true, provenance: { source: product.source, source_record_id: product.source_record_id, capture_version: 'ios-product-v1' },
      }).select('*').single()
      if (error) throw error
      const { data: item, error: itemError } = await admin.from('consumption_items').select('id').eq('legacy_food_entry_id', data.id).single()
      if (itemError) throw itemError
      const snapshots = product.nutrients.map((nutrient: { code: string; amount_per_100g: number }) => ({
        consumption_item_id: item.id,
        nutrient_code: nutrient.code,
        amount: Number((nutrient.amount_per_100g * grams / 100).toFixed(6)),
        derivation_method: 'calculated',
        source_version: `${product.source}:${product.source_record_id}`,
        confidence: verificationConfidence(product.verification_status),
      }))
      if (snapshots.length) {
        const snapshotResult = await admin.from('consumption_item_nutrients').upsert(snapshots, { onConflict: 'consumption_item_id,nutrient_code' })
        if (snapshotResult.error) throw snapshotResult.error
      }
      return json({ entry: data })
    }
    return json({ error: 'Unsupported product action.' }, 400)
  } catch (error) {
    console.error('discover-food-product failed', error)
    return json({ error: error instanceof Error ? error.message : 'Unable to find that product.' }, 400)
  }
})

async function searchUSDA(query: string) {
  const key = Deno.env.get('FDC_API_KEY') ?? 'DEMO_KEY'
  const response = await fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${encodeURIComponent(key)}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, dataType: ['Branded'], pageSize: 20 }),
  })
  if (!response.ok) throw new Error('The USDA food catalog is temporarily unavailable.')
  const payload = await response.json()
  return (payload.foods ?? []).map(summaryFromUSDA)
}

function summaryFromUSDA(food: Record<string, unknown>) {
  const nutrients = Object.fromEntries(((food.foodNutrients as Record<string, unknown>[]) ?? []).map((n) => [String(n.nutrientId), Number(n.value)]))
  return {
    id: `usda:${food.fdcId}`, fdc_id: food.fdcId, food_version_id: null, name: food.description,
    brand: food.brandOwner ?? food.brandName ?? null, barcode: food.gtinUpc ?? null, source: 'USDA FoodData Central',
    food_kind: 'packaged', resolution_source: 'usda',
    serving_size: food.servingSize ?? null, serving_unit: food.servingSizeUnit ?? null,
    calories_per_100g: nutrients['1008'] ?? null, image_url: null, score: null,
  }
}

// Edge functions use a dynamically shaped database client; generated database types are
// intentionally not bundled into deployments.
// deno-lint-ignore no-explicit-any
async function importUSDA(admin: any, fdcID: number) {
  const existing = await admin.from('food_versions').select('id').eq('source_system', 'usda_fdc').eq('source_record_id', String(fdcID)).is('superseded_at', null).maybeSingle()
  if (existing.data) return productForVersion(admin, existing.data.id)
  const key = Deno.env.get('FDC_API_KEY') ?? 'DEMO_KEY'
  const response = await fetch(`https://api.nal.usda.gov/fdc/v1/food/${fdcID}?api_key=${encodeURIComponent(key)}`)
  if (!response.ok) throw new Error('USDA could not return product details.')
  const food = await response.json()
  const { data: canonical, error: foodError } = await admin.from('foods').insert({ canonical_name: food.description }).select('id').single()
  if (foodError) throw foodError
  const { data: version, error: versionError } = await admin.from('food_versions').insert({
    food_id: canonical.id, source_system: 'usda_fdc', source_record_id: String(fdcID), source_data_type: food.dataType,
    description: food.description, brand_name: food.brandOwner ?? food.brandName, gtin: normalizeBarcode(food.gtinUpc ?? ''),
    market_country: food.marketCountry ?? 'US', ingredients_text: food.ingredients ?? null,
    serving_size: food.servingSize ?? null, serving_unit: food.servingSizeUnit ?? null,
    source_updated_at: food.modifiedDate ?? null, verification_status: 'verified', raw_source: food,
  }).select('id').single()
  if (versionError) throw versionError
  const nutrientCandidates = ((food.foodNutrients ?? []) as Record<string, unknown>[]).flatMap((item) => {
    const nutrient = item.nutrient as Record<string, unknown> | undefined
    const id = Number(nutrient?.id ?? item.nutrientId)
    const code = nutrientCodes[id]
    const amount = Number(item.amount ?? item.value)
    return code && Number.isFinite(amount) && amount >= 0
      ? [{ id, code, amount, item, priority: nutrientPriority[id] ?? 1 }]
      : []
  })
  const selectedByCode = new Map<string, typeof nutrientCandidates[number]>()
  for (const candidate of nutrientCandidates) {
    const current = selectedByCode.get(candidate.code)
    if (!current || candidate.priority < current.priority) selectedByCode.set(candidate.code, candidate)
  }
  const selectedNutrients = [...selectedByCode.values()]
  const nutrients = selectedNutrients.map((candidate) => ({
    food_version_id: version.id, nutrient_code: candidate.code,
    amount_per_100g: candidate.amount, derivation_method: 'label',
  }))
  if (nutrients.length) { const result = await admin.from('food_version_nutrients').insert(nutrients); if (result.error) throw result.error }
  const servingAmount = Number(food.servingSize)
  const servingUnit = String(food.servingSizeUnit ?? '')
  if (Number.isFinite(servingAmount) && servingAmount > 0 && /^(g|gram|grams|grm)$/i.test(servingUnit)) {
    const portionResult = await admin.from('food_portions').insert({ food_version_id: version.id, amount: 1, unit: 'serving', description: food.householdServingFullText ?? 'Serving', gram_weight: servingAmount, source: 'usda_fdc' })
    if (portionResult.error) throw portionResult.error
    const sourceByCode = new Map(selectedNutrients.map((candidate) => [candidate.code, candidate.item] as const))
    const servingRows = nutrients.map((item) => {
      const source = sourceByCode.get(item.nutrient_code)
      const percent = Number(source?.percentDailyValue)
      return {
        food_version_id: version.id,
        nutrient_code: item.nutrient_code,
        amount_per_serving: Number((item.amount_per_100g * servingAmount / 100).toFixed(6)),
        unit: nutrientUnit(item.nutrient_code),
        percent_daily_value: Number.isFinite(percent) && percent >= 0 ? percent : null,
        declaration_type: 'derived',
        evidence_section: 'usda_fdc',
      }
    })
    if (servingRows.length) {
      const servingWrite = await admin.from('food_version_serving_nutrients').upsert(servingRows, { onConflict: 'food_version_id,nutrient_code' })
      if (servingWrite.error) throw servingWrite.error
    }
  }
  const labelNutrients = pfqsLabelNutrients(nutrients, servingAmount, servingUnit)
  if (labelNutrients.length) {
    const labelWrite = await admin.from('pfqs_label_nutrients').upsert(labelNutrients.map((item) => ({
      food_version_id: version.id, ...item, source_method: 'source_conversion',
      source_version: `usda_fdc:${fdcID}`, confidence: 1,
    })), { onConflict: 'food_version_id,nutrient_code' })
    if (labelWrite.error) throw labelWrite.error
  }
  await calculateAndPersistPFQS(admin, version.id, {
    product_name: String(food.description ?? ''), jurisdiction: normalizePFQSJurisdiction(String(food.marketCountry ?? 'US')),
    assessment_date: new Date().toISOString().slice(0, 10),
    serving_size: { amount: servingAmount, unit: normalizedServingUnit(servingUnit), description: food.householdServingFullText ?? null },
    nutrition: Object.fromEntries(labelNutrients.map((item) => [item.nutrient_code, item.amount_per_serving])) as PFQSNutrients,
    explicitly_reported_nutrients: labelNutrients.filter((item) => item.explicitly_reported).map((item) => item.nutrient_code as PFQSNutrientCode),
    nutrient_evidence: Object.fromEntries(labelNutrients.map((item) => [item.nutrient_code, { source: 'derived', confidence: 0.9 }])),
    ingredients_raw: String(food.ingredients ?? ''), verification_status: 'verified', product_type: 'food',
  })
  return productForVersion(admin, version.id)
}

// deno-lint-ignore no-explicit-any
async function productForVersion(admin: any, id: string) {
  const [{ data: version, error }, { data: nutrients }, { data: portions }, { data: servingNutrients }, { data: release }] = await Promise.all([
    admin.from('food_versions').select('*').eq('id', id).single(),
    admin.from('food_version_nutrients').select('nutrient_code, amount_per_100g').eq('food_version_id', id),
    admin.from('food_portions').select('id, amount, unit, description, gram_weight').eq('food_version_id', id),
    admin.from('food_version_serving_nutrients').select('nutrient_code,amount_per_serving,unit,percent_daily_value,declaration_type,printed_text,evidence_section').eq('food_version_id', id),
    admin.from('pfqs_releases').select('model_version,ingredient_taxonomy_version,additive_database_version').eq('status', 'active').maybeSingle(),
  ])
  if (error) throw error
  const scoreResult = release?.model_version
    ? await admin.from('pfqs_scores').select('*').eq('food_version_id', id)
      .eq('model_version', release.model_version)
      .eq('ingredient_taxonomy_version', release.ingredient_taxonomy_version)
      .eq('additive_database_version', release.additive_database_version)
      .order('assessment_date', { ascending: false }).limit(1).maybeSingle()
    : { data: null }
  const values = (nutrients ?? []).map((n: Record<string, unknown>) => ({ code: String(n.nutrient_code), amount_per_100g: Number(n.amount_per_100g) }))
  let scoreAPI = scoreResult.data ? pfqsAPIResult(scoreResult.data) : null
  if (!scoreAPI && release?.model_version) {
    const required = new Set<PFQSNutrientCode>(['energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg', 'saturated_fat_g', 'trans_fat_g', 'protein_g'])
    const labelValues = (servingNutrients ?? []).filter((item: Record<string, unknown>) => required.has(String(item.nutrient_code) as PFQSNutrientCode))
    const canScale = Number(version.serving_size) > 0 && /^(g|gram|grams|grm)$/i.test(String(version.serving_unit ?? ''))
    const derivedValues = values.filter((item: { code: string }) => required.has(item.code as PFQSNutrientCode)).map((item: { code: string; amount_per_100g: number }) => ({
      nutrient_code: item.code,
      amount_per_serving: item.amount_per_100g * (canScale ? Number(version.serving_size) / 100 : 1),
      declaration_type: 'derived',
    }))
    const usable = [...new Map([...derivedValues, ...labelValues].map((item: Record<string, unknown>) => [String(item.nutrient_code), item])).values()]
    scoreAPI = await calculateAndPersistPFQS(admin, id, {
      product_name: String(version.description), jurisdiction: normalizePFQSJurisdiction(String(version.market_country ?? 'US')),
      assessment_date: new Date().toISOString().slice(0, 10),
      serving_size: {
        amount: canScale || labelValues.length ? Number(version.serving_size ?? 0) : 100,
        unit: canScale || labelValues.length ? String(version.serving_unit ?? '') : 'g',
      },
      nutrition: Object.fromEntries(usable.map((item: Record<string, unknown>) => [String(item.nutrient_code), Number(item.amount_per_serving)])) as PFQSNutrients,
      explicitly_reported_nutrients: usable.filter((item: Record<string, unknown>) => item.declaration_type !== 'derived')
        .map((item: Record<string, unknown>) => String(item.nutrient_code) as PFQSNutrientCode),
      nutrient_evidence: Object.fromEntries(usable.map((item: Record<string, unknown>) => [String(item.nutrient_code), {
        source: item.declaration_type === 'derived' ? 'derived' : 'label', confidence: item.declaration_type === 'derived' ? 0.9 : 1,
      }])),
      ingredients_raw: String(version.ingredients_text ?? ''), verification_status: String(version.verification_status ?? ''),
      product_type: version.source_data_type === 'ai_estimate' ? 'ai_estimate' : 'food',
    })
  }
  return {
    id, food_version_id: id, fdc_id: version.source_system === 'usda_fdc' ? Number(version.source_record_id) : null,
    name: version.description, brand: version.brand_name, barcode: version.gtin, source: version.source_system === 'usda_fdc' ? 'USDA FoodData Central' : 'Leafy catalog',
    food_kind: version.food_kind ?? (version.gtin ? 'packaged' : 'generic'),
    resolution_source: version.source_system === 'usda_fdc' ? 'usda' : 'leafy_catalog',
    source_record_id: version.source_record_id, serving_size: version.serving_size, serving_unit: version.serving_unit,
    servings_per_container: version.servings_per_container,
    metric_serving_size: version.metric_serving_size, metric_serving_unit: version.metric_serving_unit,
    nutrition_footnote: version.label_sections?.nutrition_footnote ?? null,
    calories_per_100g: values.find((n: { code: string; amount_per_100g: number }) => n.code === 'energy_kcal')?.amount_per_100g ?? null,
    ingredients: version.ingredients_text, allergens: version.allergens ?? [], image_url: version.image_url,
    verification_status: version.verification_status, nutrients: values, portions: portions ?? [],
    label_nutrients: (servingNutrients ?? []).map((item: Record<string, unknown>) => ({
      code: item.nutrient_code, amount_per_serving: Number(item.amount_per_serving), unit: item.unit,
      percent_daily_value: item.percent_daily_value == null ? null : Number(item.percent_daily_value),
      declaration_type: item.declaration_type, printed_text: item.printed_text,
      evidence_section: item.evidence_section,
      value_source: item.declaration_type === 'derived' ? 'source_derived' : 'package_label',
    })),
    score: scoreAPI,
  }
}

function nutrientUnit(code: string) {
  if (code === 'energy_kcal') return 'kcal'
  if (code.endsWith('_mcg') || code === 'vitamin_a_mcg_rae' || code === 'folate_mcg_dfe') return 'mcg'
  if (code.endsWith('_mg') || code === 'niacin_mg_ne') return 'mg'
  return 'g'
}

function normalizedServingUnit(value: string) {
  return /^(g|gram|grams|grm)$/i.test(value) ? 'g' : /^(ml|milliliter|milliliters)$/i.test(value) ? 'mL' : value
}

function pfqsLabelNutrients(nutrients: { nutrient_code: string; amount_per_100g: number }[], servingAmount: number, servingUnit: string) {
  const required = new Set<PFQSNutrientCode>(['energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg', 'saturated_fat_g', 'trans_fat_g', 'protein_g'])
  const canConvert = Number.isFinite(servingAmount) && servingAmount > 0 && /^(g|gram|grams|grm)$/i.test(servingUnit)
  return nutrients.filter((item) => required.has(item.nutrient_code as PFQSNutrientCode)).map((item) => ({
    nutrient_code: item.nutrient_code as PFQSNutrientCode,
    amount_per_serving: canConvert ? Number((item.amount_per_100g * servingAmount / 100).toFixed(6)) : Number.NaN,
    unit: item.nutrient_code === 'energy_kcal' ? 'kcal' : item.nutrient_code === 'sodium_mg' ? 'mg' : 'g',
    explicitly_reported: false,
  })).filter((item) => Number.isFinite(item.amount_per_serving))
}

function normalizeBarcode(value: string) { const digits = String(value).replace(/\D/g, ''); return digits.length >= 8 && digits.length <= 14 ? digits : '' }
function verificationConfidence(value: string | null) { return value === 'verified' ? 1 : value === 'community_confirmed' ? 0.95 : 0.8 }
function deduplicate(products: Record<string, unknown>[]) { const seen = new Set<string>(); return products.filter((p) => { const key = String(p.barcode ?? p.id); if (seen.has(key)) return false; seen.add(key); return true }) }
function format(value: number) { return Number.isInteger(value) ? String(value) : value.toFixed(1) }
