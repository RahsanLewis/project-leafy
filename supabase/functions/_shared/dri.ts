export type CalculationSex = 'female' | 'male'
export type TargetType = 'rda' | 'ai' | 'weight_based_rda' | 'legacy_ai' | 'informational'
export type UpperLimitScope = 'total' | 'preformed_only' | 'synthetic_only' | 'supplemental_only'

export type NutrientReferenceRule = {
  targetAmount: number | null
  targetType: TargetType
  targetBasisCodes: string[]
  upperLimitAmount: number | null
  upperLimitScope: UpperLimitScope | null
  guidanceLimitAmount: number | null
  guidanceLimitType: 'cdrr' | null
  lowFlagEnabled: boolean
  note: string | null
}

export const driReference = {
  code: 'nasem_dri_adults_2026_1',
  name: 'National Academies Dietary Reference Intakes',
  population: 'Adults personalized by age, calculation sex, and current weight where applicable',
  source_url: 'https://ods.od.nih.gov/HealthInformation/nutrientrecommendations/',
} as const

export function ageOnDate(birthDate: string, localDate: string): number {
  const [birthYear, birthMonth, birthDay] = birthDate.split('-').map(Number)
  const [year, month, day] = localDate.split('-').map(Number)
  let age = year - birthYear
  if (month < birthMonth || (month === birthMonth && day < birthDay)) age -= 1
  return age
}

export function resolveNutrientReference(
  code: string,
  age: number,
  sex: CalculationSex,
  weightKG: number,
  fallbackFiberTarget: number | null = null,
): NutrientReferenceRule {
  const target = targetFor(code, age, sex, weightKG, fallbackFiberTarget)
  const upper = upperLimitFor(code, age)
  return {
    targetAmount: target.amount,
    targetType: target.type,
    targetBasisCodes: basisCodes(code),
    upperLimitAmount: upper.amount,
    upperLimitScope: upper.scope,
    guidanceLimitAmount: code === 'sodium_mg' ? 2300 : null,
    guidanceLimitType: code === 'sodium_mg' ? 'cdrr' : null,
    lowFlagEnabled: target.amount != null && code !== 'chromium_mcg' && code !== 'sulfur_mg',
    note: noteFor(code),
  }
}

function targetFor(code: string, age: number, sex: CalculationSex, weightKG: number, fallbackFiberTarget: number | null) {
  const female = sex === 'female'
  const teen = age <= 18
  const older = age > 70
  const over50 = age > 50
  const over30 = age > 30
  const value = (amount: number, type: TargetType = 'rda') => ({ amount, type })
  switch (code) {
    case 'vitamin_a_mcg_rae': return value(female ? 700 : 900)
    case 'vitamin_c_mg': return value(teen ? (female ? 65 : 75) : (female ? 75 : 90))
    case 'vitamin_d_mcg': return value(older ? 20 : 15)
    case 'vitamin_e_mg': return value(15)
    case 'vitamin_k_mcg': return value(teen ? 75 : (female ? 90 : 120), 'ai')
    case 'thiamin_mg': return value(teen ? (female ? 1 : 1.2) : (female ? 1.1 : 1.2))
    case 'riboflavin_mg': return value(teen ? (female ? 1 : 1.3) : (female ? 1.1 : 1.3))
    case 'niacin_mg_ne': return value(female ? 14 : 16)
    case 'vitamin_b6_mg': return value(teen ? (female ? 1.2 : 1.3) : over50 ? (female ? 1.5 : 1.7) : 1.3)
    case 'biotin_mcg': return value(teen ? 25 : 30, 'ai')
    case 'folate_mcg_dfe': return value(400)
    case 'vitamin_b12_mcg': return value(2.4)
    case 'pantothenic_acid_mg': return value(5, 'ai')
    case 'calcium_mg': return value(teen ? 1300 : older || (female && over50) ? 1200 : 1000)
    case 'phosphorus_mg': return value(teen ? 1250 : 700)
    case 'magnesium_mg': return value(teen ? (female ? 360 : 410) : female ? (over30 ? 320 : 310) : (over30 ? 420 : 400))
    case 'sodium_mg': return value(1500, 'ai')
    case 'potassium_mg': return value(teen ? (female ? 2300 : 3000) : (female ? 2600 : 3400), 'ai')
    case 'chloride_mg': return value(older ? 1800 : over50 ? 2000 : 2300, 'ai')
    case 'iron_mg': return value(teen ? (female ? 15 : 11) : female && !over50 ? 18 : 8)
    case 'zinc_mg': return value(teen ? (female ? 9 : 11) : (female ? 8 : 11))
    case 'copper_mg': return value(teen ? 0.89 : 0.9)
    case 'manganese_mg': return value(teen ? (female ? 1.6 : 2.2) : (female ? 1.8 : 2.3), 'ai')
    case 'iodine_mcg': return value(150)
    case 'selenium_mcg': return value(55)
    case 'molybdenum_mcg': return value(teen ? 43 : 45)
    case 'chromium_mcg': return value(teen ? (female ? 24 : 35) : over50 ? (female ? 20 : 30) : (female ? 25 : 35), 'legacy_ai')
    case 'choline_mg': return value(teen ? (female ? 400 : 550) : (female ? 425 : 550), 'ai')
    case 'fiber_g': return fallbackFiberTarget == null
      ? value(teen ? (female ? 26 : 38) : over50 ? (female ? 21 : 30) : (female ? 25 : 38), 'ai')
      : value(fallbackFiberTarget, 'ai')
    case 'linoleic_acid_g': return value(teen ? (female ? 11 : 16) : over50 ? (female ? 11 : 14) : (female ? 12 : 17), 'ai')
    case 'alpha_linolenic_acid_g': return value(female ? 1.1 : 1.6, 'ai')
    case 'histidine_g': return value(weightKG * (teen ? (female ? 14 : 15) : 14) / 1000, 'weight_based_rda')
    case 'isoleucine_g': return value(weightKG * (teen ? (female ? 19 : 21) : 19) / 1000, 'weight_based_rda')
    case 'leucine_g': return value(weightKG * (teen ? (female ? 44 : 47) : 42) / 1000, 'weight_based_rda')
    case 'lysine_g': return value(weightKG * (teen ? (female ? 40 : 43) : 38) / 1000, 'weight_based_rda')
    case 'methionine_g': return value(weightKG * (teen ? (female ? 19 : 21) : 19) / 1000, 'weight_based_rda')
    case 'phenylalanine_g': return value(weightKG * (teen ? (female ? 35 : 38) : 33) / 1000, 'weight_based_rda')
    case 'threonine_g': return value(weightKG * (teen ? (female ? 21 : 22) : 20) / 1000, 'weight_based_rda')
    case 'tryptophan_g': return value(weightKG * (teen ? (female ? 5 : 6) : 5) / 1000, 'weight_based_rda')
    case 'valine_g': return value(weightKG * (teen ? (female ? 24 : 27) : 24) / 1000, 'weight_based_rda')
    case 'sulfur_mg': return { amount: null, type: 'informational' as const }
    default: return { amount: null, type: 'informational' as const }
  }
}

function upperLimitFor(code: string, age: number): { amount: number | null; scope: UpperLimitScope | null } {
  const teen = age <= 18
  const older = age > 70
  const total = (amount: number) => ({ amount, scope: 'total' as const })
  const scoped = (amount: number, scope: UpperLimitScope) => ({ amount, scope })
  switch (code) {
    case 'vitamin_a_mcg_rae': return scoped(teen ? 2800 : 3000, 'preformed_only')
    case 'vitamin_c_mg': return total(teen ? 1800 : 2000)
    case 'vitamin_d_mcg': return total(100)
    case 'vitamin_e_mg': return scoped(teen ? 800 : 1000, 'synthetic_only')
    case 'niacin_mg_ne': return scoped(teen ? 30 : 35, 'synthetic_only')
    case 'vitamin_b6_mg': return total(teen ? 80 : 100)
    case 'folate_mcg_dfe': return scoped(teen ? 800 : 1000, 'synthetic_only')
    case 'calcium_mg': return total(teen ? 3000 : age > 50 ? 2000 : 2500)
    case 'phosphorus_mg': return total(older ? 3000 : 4000)
    case 'magnesium_mg': return scoped(350, 'supplemental_only')
    case 'chloride_mg': return total(3600)
    case 'iron_mg': return total(45)
    case 'zinc_mg': return total(teen ? 34 : 40)
    case 'copper_mg': return total(teen ? 8 : 10)
    case 'manganese_mg': return total(teen ? 9 : 11)
    case 'iodine_mcg': return total(teen ? 900 : 1100)
    case 'selenium_mcg': return total(400)
    case 'molybdenum_mcg': return total(teen ? 1700 : 2000)
    case 'choline_mg': return total(teen ? 3000 : 3500)
    default: return { amount: null, scope: null }
  }
}

function basisCodes(code: string): string[] {
  if (code === 'methionine_g') return ['methionine_g', 'cystine_g']
  if (code === 'phenylalanine_g') return ['phenylalanine_g', 'tyrosine_g']
  return [code]
}

function noteFor(code: string): string | null {
  if (code === 'methionine_g') return 'Target progress includes cystine because the DRI is established for methionine plus cysteine.'
  if (code === 'phenylalanine_g') return 'Target progress includes tyrosine because the DRI is established for phenylalanine plus tyrosine.'
  if (code === 'chromium_mcg') return 'This historical Adequate Intake is shown for context; chromium essentiality and deficiency remain debated.'
  if (code === 'sulfur_mg') return 'Sulfur is tracked for context, but no separate daily target or upper limit is established.'
  return null
}
