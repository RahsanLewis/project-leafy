import { calculateAndPersistEntryPFQS } from './persistence.ts'
import type { PFQSInput, PFQSNutrientCode, PFQSNutrients } from './types.ts'

type Row = Record<string, any>

export async function scoreFoodEntry(admin: any, foodEntryID: string, userID: string) {
  const input = await pfqsInputForFoodEntry(admin, foodEntryID, userID)
  return calculateAndPersistEntryPFQS(admin, foodEntryID, userID, input)
}

export async function pfqsInputForFoodEntry(admin: any, foodEntryID: string, userID: string) {
  const entryRead = await admin.from('food_entries').select(
    'id,name,calories,amount,amount_unit,gram_weight,portion_description,meal_type,entry_source,confidence,canonical_food_version_id',
  ).eq('id', foodEntryID).eq('user_id', userID).single()
  if (entryRead.error) throw entryRead.error
  const entry = entryRead.data as Row
  const itemRead = await admin.from('consumption_items').select('id')
    .eq('legacy_food_entry_id', foodEntryID).eq('user_id', userID).is('deleted_at', null).maybeSingle()
  if (itemRead.error) throw itemRead.error
  const nutrientRead = itemRead.data
    ? await admin.from('consumption_item_nutrients').select('nutrient_code,amount,derivation_method,confidence')
      .eq('consumption_item_id', itemRead.data.id)
    : { data: [], error: null }
  if (nutrientRead.error) throw nutrientRead.error
  const rows = (nutrientRead.data ?? []) as Row[]
  const nutrition = Object.fromEntries(rows.map((row) => [String(row.nutrient_code), Number(row.amount)])) as PFQSNutrients
  nutrition.energy_kcal = Number(entry.calories)
  const evidence = Object.fromEntries(rows.map((row) => [String(row.nutrient_code), {
    source: evidenceSource(String(row.derivation_method)),
    confidence: row.confidence == null ? defaultConfidence(String(row.derivation_method)) : Number(row.confidence),
  }])) as PFQSInput['nutrient_evidence']
  evidence!.energy_kcal = {
    source: entry.entry_source === 'manual' ? 'user_entered' : 'estimated',
    confidence: Number(entry.confidence ?? (entry.entry_source === 'manual' ? 0.8 : 0.7)),
  }
  const explicit = rows.filter((row) => ['label', 'laboratory'].includes(String(row.derivation_method)))
    .map((row) => String(row.nutrient_code) as PFQSNutrientCode)
  const input: PFQSInput = {
    product_name: String(entry.name), jurisdiction: 'US', assessment_date: new Date().toISOString().slice(0, 10),
    serving_size: {
      amount: Number(entry.amount ?? 1) || 1,
      unit: String(entry.amount_unit ?? 'serving'),
      description: entry.portion_description == null ? null : String(entry.portion_description),
    },
    nutrition, nutrient_evidence: evidence, explicitly_reported_nutrients: explicit,
    ingredients_raw: '', verification_status: entry.canonical_food_version_id ? 'verified' : 'unverified',
    product_type: entry.meal_type === 'supplement' ? 'supplement'
      : ['photo_ai', 'text_ai'].includes(String(entry.entry_source)) ? 'ai_estimate' : 'manual',
  }
  return input
}

function evidenceSource(value: string): 'label' | 'derived' | 'estimated' | 'user_entered' {
  if (value === 'label' || value === 'laboratory') return 'label'
  if (value === 'estimated') return 'estimated'
  if (value === 'user_entered') return 'user_entered'
  return 'derived'
}

function defaultConfidence(value: string) {
  return value === 'label' || value === 'laboratory' ? 1 : value === 'estimated' ? 0.7 : value === 'user_entered' ? 0.8 : 0.9
}
