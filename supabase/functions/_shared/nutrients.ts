export const nutrientCodes = [
  'protein_g', 'carbohydrate_g', 'fat_g', 'fiber_g', 'sugars_g', 'added_sugars_g',
  'saturated_fat_g', 'trans_fat_g', 'cholesterol_mg', 'sodium_mg', 'potassium_mg',
  'calcium_mg', 'iron_mg', 'magnesium_mg', 'vitamin_d_mcg', 'vitamin_a_mcg_rae',
  'vitamin_c_mg', 'vitamin_e_mg', 'vitamin_k_mcg', 'thiamin_mg', 'riboflavin_mg',
  'niacin_mg_ne', 'vitamin_b6_mg', 'folate_mcg_dfe', 'vitamin_b12_mcg', 'biotin_mcg',
  'pantothenic_acid_mg', 'phosphorus_mg', 'iodine_mcg', 'zinc_mg', 'selenium_mcg',
  'copper_mg', 'manganese_mg', 'chromium_mcg', 'molybdenum_mcg', 'chloride_mg',
  'choline_mg', 'water_g', 'caffeine_mg', 'alcohol_g',
] as const

export type NutrientCode = typeof nutrientCodes[number]
export type EstimatedNutrient = { code: NutrientCode; amount: number; confidence: number }

export const nutrientArraySchema = {
  type: 'array', minItems: 3, maxItems: nutrientCodes.length,
  items: {
    type: 'object', additionalProperties: false,
    required: ['code', 'amount', 'confidence'],
    properties: {
      code: { type: 'string', enum: nutrientCodes },
      amount: { type: 'number' },
      confidence: { type: 'number' },
    },
  },
} as const

export const nutrientUnits: Record<NutrientCode, string> = {
  protein_g: 'g', carbohydrate_g: 'g', fat_g: 'g', fiber_g: 'g', sugars_g: 'g',
  added_sugars_g: 'g', saturated_fat_g: 'g', trans_fat_g: 'g', cholesterol_mg: 'mg',
  sodium_mg: 'mg', potassium_mg: 'mg', calcium_mg: 'mg', iron_mg: 'mg', magnesium_mg: 'mg',
  vitamin_d_mcg: 'mcg', vitamin_a_mcg_rae: 'mcg RAE', vitamin_c_mg: 'mg', vitamin_e_mg: 'mg',
  vitamin_k_mcg: 'mcg', thiamin_mg: 'mg', riboflavin_mg: 'mg', niacin_mg_ne: 'mg NE',
  vitamin_b6_mg: 'mg', folate_mcg_dfe: 'mcg DFE', vitamin_b12_mcg: 'mcg', biotin_mcg: 'mcg',
  pantothenic_acid_mg: 'mg', phosphorus_mg: 'mg', iodine_mcg: 'mcg', zinc_mg: 'mg',
  selenium_mcg: 'mcg', copper_mg: 'mg', manganese_mg: 'mg', chromium_mcg: 'mcg',
  molybdenum_mcg: 'mcg', chloride_mg: 'mg', choline_mg: 'mg', water_g: 'g',
  caffeine_mg: 'mg', alcohol_g: 'g',
}

export function normalizeNutrients(value: unknown): EstimatedNutrient[] {
  if (value == null) return []
  if (!Array.isArray(value)) throw new Error('The AI returned invalid nutrient estimates.')
  const seen = new Set<string>()
  return value.flatMap((raw) => {
    if (!raw || typeof raw !== 'object') return []
    const item = raw as Record<string, unknown>
    const code = String(item.code) as NutrientCode
    if (!nutrientCodes.includes(code) || seen.has(code)) return []
    const amount = Number(item.amount)
    const confidence = Number(item.confidence)
    if (!Number.isFinite(amount) || amount < 0 || !Number.isFinite(confidence)) return []
    seen.add(code)
    return [{ code, amount: Math.min(amount, 1_000_000), confidence: Math.min(1, Math.max(0, confidence)) }]
  })
}

export function nutrientPrompt() {
  return `Estimate nutrients for each food in canonical units encoded in each nutrient code. Return every supported nutrient you can estimate, including values likely to be zero. Anchor protein, carbohydrate, fat, and alcohol to the calorie estimate using reasonable food-composition assumptions. Micronutrients are uncertain: use conservative central estimates and lower confidence when ingredients, fortification, preparation, or brand are unknown. Never present these estimates as laboratory measurements.`
}
