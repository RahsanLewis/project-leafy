import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'

type Row = Record<string, unknown>

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
    const body = await request.json() as { local_date?: string }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(body.local_date ?? '')) return json({ error: 'A valid local date is required.' }, 400)
    const admin = createClient(url, secret)

    const { data: occasions, error: occasionError } = await admin.from('eating_occasions')
      .select('id').eq('user_id', user.id).eq('local_date', body.local_date)
    if (occasionError) throw occasionError
    const occasionIDs = (occasions ?? []).map((row: Row) => String(row.id))
    if (!occasionIDs.length) return json(await emptySummary(admin, body.local_date!))

    const { data: items, error: itemError } = await admin.from('consumption_items')
      .select('id,calories_kcal').eq('user_id', user.id).in('occasion_id', occasionIDs).is('deleted_at', null)
    if (itemError) throw itemError
    const itemRows = (items ?? []) as Row[]
    const itemIDs = itemRows.map((row) => String(row.id))
    if (!itemIDs.length) return json(await emptySummary(admin, body.local_date!))

    const [{ data: observations, error: observationError }, metadata] = await Promise.all([
      admin.from('consumption_item_nutrients').select('consumption_item_id,nutrient_code,amount,derivation_method,confidence').in('consumption_item_id', itemIDs),
      loadMetadata(admin),
    ])
    if (observationError) throw observationError
    return json(buildSummary(body.local_date!, itemRows, (observations ?? []) as Row[], metadata))
  } catch (error) {
    console.error('daily-nutrition failed', error)
    return json({ error: error instanceof Error ? error.message : 'Unable to load daily nutrition.' }, 400)
  }
})

// deno-lint-ignore no-explicit-any
async function loadMetadata(admin: any) {
  const [{ data: definitions, error: definitionError }, { data: reference, error: referenceError }] = await Promise.all([
    admin.from('nutrient_definitions').select('code,name,unit,nutrient_class,display_order,target_kind').order('display_order'),
    admin.from('nutrient_reference_sets').select('id,code,name,population,source_url,nutrient_reference_values(nutrient_code,amount)')
      .eq('code', 'fda_adults_4_plus_2020').single(),
  ])
  if (definitionError) throw definitionError
  if (referenceError) throw referenceError
  return { definitions: (definitions ?? []) as Row[], reference: reference as Row }
}

// deno-lint-ignore no-explicit-any
async function emptySummary(admin: any, localDate: string) {
  const metadata = await loadMetadata(admin)
  return buildSummary(localDate, [], [], metadata)
}

function buildSummary(localDate: string, items: Row[], observations: Row[], metadata: { definitions: Row[]; reference: Row }) {
  const caloriesByItem = new Map(items.map((item) => [String(item.id), Number(item.calories_kcal ?? 0)]))
  const totalCalories = [...caloriesByItem.values()].reduce((sum, value) => sum + value, 0)
  const targetRows = (metadata.reference.nutrient_reference_values ?? []) as Row[]
  const targets = new Map(targetRows.map((row) => [String(row.nutrient_code), Number(row.amount)]))
  const byCode = new Map<string, Row[]>()
  for (const row of observations) {
    const code = String(row.nutrient_code)
    byCode.set(code, [...(byCode.get(code) ?? []), row])
  }
  const nutrients = metadata.definitions.filter((definition) => String(definition.code) !== 'energy_kcal').map((definition) => {
    const code = String(definition.code)
    const rows = byCode.get(code) ?? []
    const covered = new Set(rows.map((row) => String(row.consumption_item_id)))
    const coveredCalories = [...covered].reduce((sum, id) => sum + (caloriesByItem.get(id) ?? 0), 0)
    const amount = rows.reduce((sum, row) => sum + Number(row.amount ?? 0), 0)
    const estimatedAmount = rows.filter((row) => row.derivation_method === 'estimated').reduce((sum, row) => sum + Number(row.amount ?? 0), 0)
    const confidenceWeights = rows.filter((row) => row.confidence != null)
    const confidence = confidenceWeights.length
      ? confidenceWeights.reduce((sum, row) => sum + Number(row.confidence), 0) / confidenceWeights.length
      : null
    const target = targets.get(code) ?? null
    return {
      code, name: definition.name, unit: definition.unit, nutrient_class: definition.nutrient_class,
      display_order: definition.display_order, target_kind: definition.target_kind,
      amount, target_amount: target, percent_of_target: target ? amount / target : null,
      coverage: totalCalories > 0 ? coveredCalories / totalCalories : null,
      estimated_amount: estimatedAmount, verified_amount: Math.max(0, amount - estimatedAmount), confidence,
    }
  })
  const macroCodes = ['protein_g', 'carbohydrate_g', 'fat_g']
  const macroCoveredItems = items.filter((item) => macroCodes.every((code) =>
    (byCode.get(code) ?? []).some((row) => String(row.consumption_item_id) === String(item.id))))
  const macroCoveredCalories = macroCoveredItems.reduce((sum, item) => sum + Number(item.calories_kcal ?? 0), 0)
  return {
    local_date: localDate, total_calories: totalCalories,
    macro_coverage: totalCalories > 0 ? macroCoveredCalories / totalCalories : null,
    reference: {
      code: metadata.reference.code, name: metadata.reference.name,
      population: metadata.reference.population, source_url: metadata.reference.source_url,
    },
    nutrients,
  }
}
