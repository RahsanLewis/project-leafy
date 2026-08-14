import {
  PFQS_ADDITIVE_DATABASE_VERSION, PFQS_MODEL_VERSION, PFQS_TAXONOMY_VERSION,
  type ClassifiedIngredient, type PFQSComponent, type PFQSInput, type PFQSNutrientCode, type PFQSResult,
} from './types.ts'
import {
  PFQS_FAMILY_CAPS, PFQS_INELIGIBLE_PRODUCT_TYPES, PFQS_POSITION_WEIGHTS,
  PFQS_RATING_BANDS, PFQS_REQUIRED_NUTRIENTS, PFQS_SUPPORTED_JURISDICTIONS,
} from './config.ts'
import { parseIngredients } from './ingredient-parser.ts'
import { classifyTopLevelIngredients } from './ingredient-taxonomy.ts'
import { detectAdditives } from './additive-registry.ts'

export function scoreAddedSugar(value: number) {
  if (value === 0) return 20
  if (value <= 1) return 18
  if (value <= 2) return 15
  if (value <= 3) return 11
  if (value <= 4) return 7
  if (value <= 5) return 3
  return 0
}

export function scoreFiber(value: number) {
  if (value < 0.5) return 0
  if (value < 1) return 3
  if (value < 1.5) return 6
  if (value < 2) return 9
  if (value < 3) return 12
  return 15
}

export function scoreSodium(value: number) {
  if (value <= 50) return 15
  if (value <= 100) return 13
  if (value <= 150) return 10
  if (value <= 200) return 7
  if (value <= 300) return 4
  return 0
}

export function scoreSaturatedTransFat(saturatedFatDensity: number, transFat: number) {
  let score = saturatedFatDensity <= 0.5 ? 10
    : saturatedFatDensity <= 1 ? 8
    : saturatedFatDensity <= 1.5 ? 6
    : saturatedFatDensity <= 2 ? 4
    : saturatedFatDensity <= 3 ? 2 : 0
  if (transFat >= 0.5) score = 0
  else if (transFat > 0) score = Math.min(score, 4)
  return score
}

export function scoreProtein(value: number) {
  if (value < 2) return 0
  if (value < 4) return 3
  if (value < 6) return 6
  if (value < 8) return 8
  return 10
}

export function scoreIngredientQuality(ingredients: ClassifiedIngredient[]) {
  const top = ingredients.slice(0, 5)
  const denominator = top.reduce((total, _item, index) => total + PFQS_POSITION_WEIGHTS[index], 0)
  if (!denominator) return 0
  const numerator = top.reduce((total, item, index) => total + PFQS_POSITION_WEIGHTS[index] * item.quality_coefficient, 0)
  return Math.round(clamp(numerator / denominator * 20, 0, 20))
}

export function scoreBeneficialFoods(ingredients: ClassifiedIngredient[], percentages?: Record<string, number>) {
  const top = ingredients.slice(0, 5)
  const declared = top.map((item) => percentages?.[item.canonical_name] ?? item.percentage)
  const completePercentages = top.length > 0 && declared.every((value) => Number.isFinite(value))
  const declaredTotal = declared.reduce<number>((total, value) => total + Number(value ?? 0), 0)
  if (completePercentages && declaredTotal >= 98 && declaredTotal <= 102) {
    const share = top.reduce((total, item, index) => total + (item.beneficial ? Number(declared[index]) : 0), 0)
    return share >= 50 ? 10 : share >= 25 ? 7 : share >= 10 ? 4 : share >= 2 ? 1 : 0
  }
  const denominator = top.reduce((total, _item, index) => total + PFQS_POSITION_WEIGHTS[index], 0)
  if (!denominator) return 0
  const index = top.reduce((total, item, position) => total + (item.beneficial ? PFQS_POSITION_WEIGHTS[position] : 0), 0) / denominator
  return index >= 0.75 ? 10 : index >= 0.5 ? 7 : index >= 0.25 ? 4 : index > 0 ? 1 : 0
}

export function calculatePFQS(input: PFQSInput): PFQSResult {
  const parsed = parseIngredients(input.ingredients_raw ?? '')
  const emptyResult = baseResult(input, parsed)
  const unavailable: string[] = []
  const productType = input.product_type ?? 'food'
  if ((PFQS_INELIGIBLE_PRODUCT_TYPES as readonly string[]).includes(productType)) unavailable.push('unsupported_product_type')
  if (!(PFQS_SUPPORTED_JURISDICTIONS as readonly string[]).includes(input.jurisdiction)) unavailable.push('unsupported_jurisdiction')
  if (!['verified', 'community_confirmed'].includes(input.verification_status ?? '')) unavailable.push('verified_product_required')
  if (!validDate(input.assessment_date)) unavailable.push('valid_assessment_date_required')
  if (unavailable.length) return { ...emptyResult, score_status: 'ineligible', unavailable_reasons: unavailable }

  const explicitlyReported = new Set(input.explicitly_reported_nutrients ?? [])
  const missing: string[] = []
  if (!(Number(input.serving_size?.amount) > 0) || !String(input.serving_size?.unit ?? '').trim()) missing.push('serving_size')
  for (const code of PFQS_REQUIRED_NUTRIENTS) {
    const value = input.nutrition[code]
    if (!Number.isFinite(value) || Number(value) < 0 || !explicitlyReported.has(code)) missing.push(code)
  }
  if (!input.ingredients_raw?.trim() && !input.verified_single_ingredient) missing.push('ingredients')
  const calories = Number(input.nutrition.energy_kcal)
  const water = isVerifiedPlainWater(input)
  if (water && missing.every((field) => field !== 'serving_size')) {
    return {
      ...emptyResult, score: 100, rating: 'Exceptional', score_status: 'complete', base_score: 100,
      strengths: ['Plain water supports hydration without added sugar, sodium, or saturated fat.'],
      explanation: ['Verified plain water receives the PFQS plain-water score of 100.'], missing_fields: [],
    }
  }
  if (missing.length) return { ...emptyResult, missing_fields: [...new Set(missing)] }

  const classification = classifyTopLevelIngredients(parsed, input.frozen_ingredient_classifications)
  const unresolvedTopFive = classification.unresolved.filter((item) => item.position <= 5)
  if (unresolvedTopFive.length) {
    return { ...emptyResult, missing_fields: unresolvedTopFive.map((item) => `ingredient_classification:${item.canonical_name}`) }
  }

  const normalizationCalories = Math.max(calories, 50)
  const density = (code: PFQSNutrientCode) => round(Number(input.nutrition[code]) * 100 / normalizationCalories)
  const sugarDensity = density('added_sugars_g')
  const fiberDensity = density('fiber_g')
  const sodiumDensity = density('sodium_mg')
  const saturatedDensity = density('saturated_fat_g')
  const proteinDensity = density('protein_g')
  const componentValues: Record<string, PFQSComponent> = {
    added_sugar: component(scoreAddedSugar(sugarDensity), 20, sugarDensity, 'g/100 kcal'),
    fiber: component(scoreFiber(fiberDensity), 15, fiberDensity, 'g/100 kcal'),
    sodium: component(scoreSodium(sodiumDensity), 15, sodiumDensity, 'mg/100 kcal'),
    saturated_trans_fat: component(scoreSaturatedTransFat(saturatedDensity, Number(input.nutrition.trans_fat_g)), 10, saturatedDensity, 'g saturated fat/100 kcal'),
    protein: component(scoreProtein(proteinDensity), 10, proteinDensity, 'g/100 kcal'),
    ingredient_quality: component(scoreIngredientQuality(classification.classified), 20, undefined, undefined, 'position_weighted'),
    beneficial_foods: component(scoreBeneficialFoods(classification.classified, input.ingredient_percentages), 10, undefined, undefined, 'position_or_declared_percentage'),
  }
  const baseScore = Object.values(componentValues).reduce((total, item) => total + item.score, 0)
  const additives = detectAdditives(parsed, input.jurisdiction, input.assessment_date)
  const additivePenalty = calculateAdditivePenalty(additives)
  const tier4 = additives.some((item) => item.tier === 4)
  const preliminary = baseScore - additivePenalty
  const score = Math.round(clamp(tier4 ? Math.min(preliminary, 50) : preliminary, 0, 100))
  const strengths = strengthsFor(componentValues, classification.classified)
  const weaknesses = weaknessesFor(componentValues, additives)
  return {
    ...emptyResult,
    score, rating: rating(score), score_status: 'complete', base_score: baseScore,
    additive_penalty: additivePenalty, components: componentValues, additives,
    flags: { tier_4_additive_present: tier4, score_ceiling_applied: tier4 && preliminary > 50, regulatory_flag: tier4 },
    strengths, weaknesses,
    explanation: [
      `Base food-quality score: ${baseScore}.`,
      additivePenalty ? `Evidence-based additive adjustment: −${additivePenalty}.` : 'No additive-risk deduction was applied.',
      `Final PFQS: ${score}/100 — ${rating(score)}.`,
    ],
    missing_fields: [], unavailable_reasons: [], classified_ingredients: classification.classified,
  }
}

export function calculateAdditivePenalty(additives: PFQSResult['additives']) {
  const familyTotals = new Map<string, number>()
  let ungrouped = 0
  for (const additive of additives) {
    if (!additive.family) ungrouped += additive.penalty
    else familyTotals.set(additive.family, (familyTotals.get(additive.family) ?? 0) + additive.penalty)
  }
  const grouped = [...familyTotals.entries()].reduce((total, [family, penalty]) => {
    const cap = PFQS_FAMILY_CAPS.find((item) => item.family_id === family)?.cap
    return total + (cap == null ? penalty : Math.min(penalty, cap))
  }, 0)
  return Math.min(25, ungrouped + grouped)
}

function baseResult(input: PFQSInput, parsed: ReturnType<typeof parseIngredients>): PFQSResult {
  return {
    score: null, rating: null, score_status: 'incomplete', base_score: null, additive_penalty: 0,
    components: {}, additives: [], flags: { tier_4_additive_present: false, score_ceiling_applied: false, regulatory_flag: false },
    strengths: [], weaknesses: [], explanation: [], missing_fields: [], unavailable_reasons: [],
    parsed_ingredients: parsed, classified_ingredients: [], model_version: PFQS_MODEL_VERSION,
    ingredient_taxonomy_version: PFQS_TAXONOMY_VERSION, additive_database_version: PFQS_ADDITIVE_DATABASE_VERSION,
    jurisdiction: input.jurisdiction, assessment_date: input.assessment_date,
  }
}

function component(score: number, max: number, normalized_value?: number, unit?: string, method?: string): PFQSComponent {
  return { score, max, ...(normalized_value == null ? {} : { normalized_value }), ...(unit ? { unit } : {}), ...(method ? { method } : {}) }
}
function rating(score: number) { return PFQS_RATING_BANDS.find((item) => score >= item.minimum)!.label }
function validDate(value: string) { return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`)) }
function isVerifiedPlainWater(input: PFQSInput) {
  const ingredients = input.ingredients_raw.toLowerCase().replace(/[^a-z ]/g, '').replace(/\s+/g, ' ').trim()
  return /water/i.test(input.product_name) && ['water', 'purified water', 'spring water', 'filtered water'].includes(ingredients)
}
function strengthsFor(components: Record<string, PFQSComponent>, ingredients: ClassifiedIngredient[]) {
  const values: string[] = []
  if (components.fiber.score >= 12) values.push('High fiber density')
  if (components.protein.score >= 8) values.push('Strong protein density')
  if (components.added_sugar.score >= 18) values.push('Little or no added sugar')
  if (components.sodium.score >= 13) values.push('Low sodium density')
  if (ingredients[0]?.beneficial) values.push(`${title(ingredients[0].canonical_name)} is the main ingredient`)
  return values.slice(0, 4)
}
function weaknessesFor(components: Record<string, PFQSComponent>, additives: PFQSResult['additives']) {
  const values: string[] = []
  if (components.added_sugar.score <= 7) values.push('Added sugar reduces the score')
  if (components.sodium.score <= 7) values.push('Sodium reduces the score')
  if (components.saturated_trans_fat.score <= 4) values.push('Saturated or trans fat reduces the score')
  if (components.ingredient_quality.score <= 8) values.push('The leading ingredients are mostly refined or formulation ingredients')
  for (const additive of additives.filter((item) => item.penalty > 0)) values.push(`${additive.name}: −${additive.penalty}`)
  return values.slice(0, 4)
}
function title(value: string) { return value.replace(/\b\w/g, (letter) => letter.toUpperCase()) }
function round(value: number) { return Number(value.toFixed(4)) }
function clamp(value: number, minimum: number, maximum: number) { return Math.min(Math.max(value, minimum), maximum) }

export type { PFQSInput, PFQSResult } from './types.ts'
