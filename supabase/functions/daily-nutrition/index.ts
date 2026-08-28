import { requireUser } from '../_shared/auth.ts'
import { buildDailyNutritionSummary, type NutritionRow } from '../_shared/daily-nutrition.ts'
import { cors, errorResponse, json } from '../_shared/http.ts'
import { processNutrientJobs } from '../_shared/nutrient-enrichment.ts'

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void }

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const { user, admin } = await requireUser(request)
    const body = await request.json() as { local_date?: string }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(body.local_date ?? '')) return json({ error: 'A valid local date is required.' }, 400)

    const selectedDate = body.local_date!
    const dates = rollingDates(selectedDate)
    const [{ data: occasions, error: occasionError }, metadata] = await Promise.all([
      admin.from('eating_occasions').select('id,local_date').eq('user_id', user.id)
        .gte('local_date', dates[0]).lte('local_date', selectedDate),
      loadMetadata(admin, user.id, selectedDate),
    ])
    if (occasionError) throw occasionError
    const occasionRows = (occasions ?? []) as NutritionRow[]
    const dateByOccasion = new Map(occasionRows.map((row) => [String(row.id), String(row.local_date)]))
    const occasionIDs = [...dateByOccasion.keys()]
    let itemRows: NutritionRow[] = []
    let observations: NutritionRow[] = []
    let jobs: NutritionRow[] = []
    if (occasionIDs.length) {
      const { data: items, error: itemError } = await admin.from('consumption_items')
        .select('id,occasion_id,legacy_food_entry_id,description,calories_kcal')
        .eq('user_id', user.id).in('occasion_id', occasionIDs).is('deleted_at', null)
      if (itemError) throw itemError
      itemRows = ((items ?? []) as NutritionRow[]).map((item) => ({
        ...item, local_date: dateByOccasion.get(String(item.occasion_id)),
      }))
      const itemIDs = itemRows.map((row) => String(row.id))
      if (itemIDs.length) {
        const selectedItemIDs = itemRows.filter((row) => row.local_date === selectedDate).map((row) => String(row.id))
        const [observationResult, jobResult] = await Promise.all([
          admin.from('consumption_item_nutrients')
            .select('consumption_item_id,nutrient_code,amount,derivation_method,confidence').in('consumption_item_id', itemIDs),
          selectedItemIDs.length
            ? admin.from('nutrient_enrichment_jobs').select('status').in('consumption_item_id', selectedItemIDs)
            : Promise.resolve({ data: [], error: null }),
        ])
        if (observationResult.error) throw observationResult.error
        if (jobResult.error) throw jobResult.error
        observations = (observationResult.data ?? []) as NutritionRow[]
        jobs = (jobResult.data ?? []) as NutritionRow[]
      }
    }
    EdgeRuntime.waitUntil(processNutrientJobs(admin, user.id, 3)
      .catch((error) => console.error('nutrient retry resume failed', error)))
    return json(buildDailyNutritionSummary(selectedDate, dates, itemRows, observations, metadata, jobs))
  } catch (error) {
    console.error('daily-nutrition failed', error)
    return errorResponse(error, 'Unable to load daily nutrition.')
  }
})

// deno-lint-ignore no-explicit-any
async function loadMetadata(admin: any, userID: string, selectedDate: string) {
  const [definitionsResult, referenceResult, profileResult, weightsResult] = await Promise.all([
    admin.from('nutrient_definitions')
      .select('code,name,unit,nutrient_class,display_order,target_kind,is_displayed,essentiality_note')
      .order('display_order'),
    admin.from('nutrient_reference_sets')
      .select('nutrient_reference_values(nutrient_code,amount)').eq('code', 'fda_adults_4_plus_2020').single(),
    admin.from('profiles').select('birth_date,calculation_sex,current_weight_kg').eq('user_id', userID).single(),
    admin.from('weight_entries').select('recorded_on,weight_kg').eq('user_id', userID)
      .lte('recorded_on', selectedDate).order('recorded_on', { ascending: false }),
  ])
  if (definitionsResult.error) throw definitionsResult.error
  if (referenceResult.error) throw referenceResult.error
  if (profileResult.error) throw profileResult.error
  if (weightsResult.error) throw weightsResult.error
  const targets = (referenceResult.data?.nutrient_reference_values ?? []) as NutritionRow[]
  return {
    definitions: (definitionsResult.data ?? []) as NutritionRow[],
    legacyTargets: new Map(targets.map((row) => [String(row.nutrient_code), Number(row.amount)])),
    profile: {
      birth_date: String(profileResult.data.birth_date),
      calculation_sex: profileResult.data.calculation_sex,
      current_weight_kg: Number(profileResult.data.current_weight_kg),
    },
    weights: ((weightsResult.data ?? []) as NutritionRow[]).map((row) => ({
      recorded_on: String(row.recorded_on), weight_kg: Number(row.weight_kg),
    })),
  }
}

function rollingDates(endDate: string): string[] {
  const date = new Date(`${endDate}T00:00:00Z`)
  return Array.from({ length: 7 }, (_, index) => {
    const value = new Date(date)
    value.setUTCDate(date.getUTCDate() - (6 - index))
    return value.toISOString().slice(0, 10)
  })
}
