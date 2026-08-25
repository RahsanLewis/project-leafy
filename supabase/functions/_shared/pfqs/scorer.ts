import {
  PFQS_ADDITIVE_DATABASE_VERSION, PFQS_INGREDIENT_DATABASE_VERSION, PFQS_MODEL_VERSION, PFQS_TAXONOMY_VERSION,
  type ClassifiedIngredient, type PFQSComponent, type PFQSInput, type PFQSNutrientCode, type PFQSResult,
} from './types.ts'
import {
  PFQS_FAMILY_CAPS, PFQS_INELIGIBLE_PRODUCT_TYPES, PFQS_POSITION_WEIGHTS,
  PFQS_RATING_BANDS, PFQS_REQUIRED_NUTRIENTS, PFQS_SUPPORTED_JURISDICTIONS,
} from './config.ts'
import { parseIngredients } from './ingredient-parser.ts'
import { classifyTopLevelIngredients } from './ingredient-taxonomy.ts'
import { detectAdditives } from './additive-registry.ts'
import { buildIngredientCatalog } from './ingredient-catalog.ts'

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
  const top = ingredients.filter((item) => item.position <= 5)
  const denominator = top.reduce((total, item) => total + PFQS_POSITION_WEIGHTS[item.position - 1], 0)
  if (!denominator) return 0
  const numerator = top.reduce((total, item) => total + PFQS_POSITION_WEIGHTS[item.position - 1] * item.quality_coefficient, 0)
  return Math.round(clamp(numerator / denominator * 20, 0, 20))
}

export function scoreBeneficialFoods(ingredients: ClassifiedIngredient[], percentages?: Record<string, number>) {
  const top = ingredients.filter((item) => item.position <= 5)
  const declared = top.map((item) => percentages?.[item.canonical_name] ?? item.percentage)
  const completePercentages = top.length > 0 && declared.every((value) => Number.isFinite(value))
  const declaredTotal = declared.reduce<number>((total, value) => total + Number(value ?? 0), 0)
  if (completePercentages && declaredTotal >= 98 && declaredTotal <= 102) {
    const share = top.reduce((total, item, index) => total + (item.beneficial ? Number(declared[index]) : 0), 0)
    return share >= 50 ? 10 : share >= 25 ? 7 : share >= 10 ? 4 : share >= 2 ? 1 : 0
  }
  const denominator = top.reduce((total, item) => total + PFQS_POSITION_WEIGHTS[item.position - 1], 0)
  if (!denominator) return 0
  const index = top.reduce((total, item) => total + (item.beneficial ? PFQS_POSITION_WEIGHTS[item.position - 1] : 0), 0) / denominator
  return index >= 0.75 ? 10 : index >= 0.5 ? 7 : index >= 0.25 ? 4 : index > 0 ? 1 : 0
}

export function calculatePFQS(input: PFQSInput): PFQSResult {
  const parsed = parseIngredients(input.ingredients_raw ?? '')
  const emptyResult = baseResult(input, parsed)
  const productType = input.product_type ?? 'food'
  if ((PFQS_INELIGIBLE_PRODUCT_TYPES as readonly string[]).includes(productType)) {
    return { ...emptyResult, score_status: 'ineligible', unavailable_reasons: ['unsupported_product_type'] }
  }

  const explicitlyReported = new Set(input.explicitly_reported_nutrients ?? [])
  const missing: string[] = []
  if (!(Number(input.serving_size?.amount) > 0) || !String(input.serving_size?.unit ?? '').trim()) missing.push('serving_size')
  for (const code of PFQS_REQUIRED_NUTRIENTS) {
    const value = input.nutrition[code]
    if (!Number.isFinite(value) || Number(value) < 0) missing.push(code)
    else if (productType === 'food' && !explicitlyReported.has(code)) missing.push(`label_declaration:${code}`)
  }
  if (!input.ingredients_raw?.trim() && !input.verified_single_ingredient) missing.push('ingredients')
  const calories = Number(input.nutrition.energy_kcal)
  const water = isVerifiedPlainWater(input)
  if (water && !missing.includes('serving_size')) {
    return {
      ...emptyResult, score: 100, rating: 'Exceptional', score_status: 'complete', base_score: 100,
      strengths: ['Plain water supports hydration without added sugar, sodium, or saturated fat.'],
      explanation: ['Verified plain water receives the PFQS plain-water score of 100.'], missing_fields: [],
      evidence_coverage: 1, evidence_confidence: 1, confidence_level: 'high', included_components: ['plain_water'],
    }
  }

  const classification = classifyTopLevelIngredients(parsed, input.frozen_ingredient_classifications)
  const unresolvedTopFive = classification.unresolved.filter((item) => item.position <= 5)
  missing.push(...unresolvedTopFive.map((item) => `ingredient_classification:${item.canonical_name}`))

  const normalizationCalories = Math.max(calories, 50)
  const density = (code: PFQSNutrientCode) => round(Number(input.nutrition[code]) * 100 / normalizationCalories)
  const valid = (code: PFQSNutrientCode) => Number.isFinite(input.nutrition[code]) && Number(input.nutrition[code]) >= 0
  const componentValues: Record<string, PFQSComponent> = {}
  const componentCoverage: Record<string, number> = {}
  if (valid('energy_kcal') && valid('added_sugars_g')) {
    const value = density('added_sugars_g'); componentValues.added_sugar = component(scoreAddedSugar(value), 20, value, 'g/100 kcal')
    componentCoverage.added_sugar = 1
  }
  if (valid('energy_kcal') && valid('fiber_g')) {
    const value = density('fiber_g'); componentValues.fiber = component(scoreFiber(value), 15, value, 'g/100 kcal')
    componentCoverage.fiber = 1
  }
  if (valid('energy_kcal') && valid('sodium_mg')) {
    const value = density('sodium_mg'); componentValues.sodium = component(scoreSodium(value), 15, value, 'mg/100 kcal')
    componentCoverage.sodium = 1
  }
  if (valid('energy_kcal') && valid('saturated_fat_g') && valid('trans_fat_g')) {
    const value = density('saturated_fat_g'); componentValues.saturated_trans_fat = component(scoreSaturatedTransFat(value, Number(input.nutrition.trans_fat_g)), 10, value, 'g saturated fat/100 kcal')
    componentCoverage.saturated_trans_fat = 1
  }
  if (valid('energy_kcal') && valid('protein_g')) {
    const value = density('protein_g'); componentValues.protein = component(scoreProtein(value), 10, value, 'g/100 kcal')
    componentCoverage.protein = 1
  }
  if (classification.classified.length) {
    const availableIngredientWeight = classification.classified.filter((item) => item.position <= 5)
      .reduce((total, item) => total + PFQS_POSITION_WEIGHTS[item.position - 1], 0)
    const totalIngredientWeight = parsed.filter((item) => item.position <= 5)
      .reduce((total, item) => total + PFQS_POSITION_WEIGHTS[item.position - 1], 0)
    const ingredientCoverage = totalIngredientWeight ? availableIngredientWeight / totalIngredientWeight : 0
    componentValues.ingredient_quality = component(scoreIngredientQuality(classification.classified), 20, undefined, undefined, 'available_position_weighted')
    componentValues.beneficial_foods = component(scoreBeneficialFoods(classification.classified, input.ingredient_percentages), 10, undefined, undefined, 'available_position_or_percentage')
    componentCoverage.ingredient_quality = ingredientCoverage
    componentCoverage.beneficial_foods = ingredientCoverage
  }
  const availableMax = Object.entries(componentValues).reduce((total, [name, item]) => total + item.max * (componentCoverage[name] ?? 1), 0)
  if (!availableMax) {
    return { ...emptyResult, score_status: 'pending', missing_fields: [...new Set(missing)], unavailable_reasons: ['nutrient_enrichment_required'] }
  }
  const earned = Object.entries(componentValues).reduce((total, [name, item]) => total + item.score * (componentCoverage[name] ?? 1), 0)
  const baseScore = Math.round(earned / availableMax * 100)
  const additives = detectAdditives(parsed, input.jurisdiction, input.assessment_date)
  const ingredients = buildIngredientCatalog(parsed, classification.classified, additives)
  const additivePenalty = calculateAdditivePenalty(additives)
  const tier4 = additives.some((item) => item.tier === 4)
  const preliminary = baseScore - additivePenalty
  const score = Math.round(clamp(tier4 ? Math.min(preliminary, 50) : preliminary, 0, 100))
  const strengths = strengthsFor(componentValues, classification.classified)
  const weaknesses = weaknessesFor(componentValues, additives)
  const evidenceCoverage = round(availableMax / 100)
  const evidenceConfidence = round(evidenceCoverage * evidenceReliability(input, componentValues, componentCoverage, classification.classified))
  const complete = availableMax === 100
    && PFQS_REQUIRED_NUTRIENTS.every((code) => explicitlyReported.has(code))
    && unresolvedTopFive.length === 0
    && ['verified', 'community_confirmed'].includes(input.verification_status ?? '')
    && (PFQS_SUPPORTED_JURISDICTIONS as readonly string[]).includes(input.jurisdiction)
    && validDate(input.assessment_date)
  const limitations: string[] = []
  if (!(PFQS_SUPPORTED_JURISDICTIONS as readonly string[]).includes(input.jurisdiction)) limitations.push('jurisdiction_evidence_limited')
  if (!['verified', 'community_confirmed'].includes(input.verification_status ?? '')) limitations.push('unverified_source')
  return {
    ...emptyResult,
    score, rating: rating(score), score_status: complete ? 'complete' : 'provisional', base_score: baseScore,
    additive_penalty: additivePenalty, ingredient_concern_penalty: additivePenalty,
    components: componentValues, additives, ingredient_concerns: additives, ingredients,
    flags: { tier_4_additive_present: tier4, score_ceiling_applied: tier4 && preliminary > 50, regulatory_flag: tier4 },
    strengths, weaknesses,
    explanation: [
      `Base food-quality score: ${baseScore}.`,
      additivePenalty ? `Evidence-based ingredient concern adjustment: −${additivePenalty}.` : 'No ingredient-concern deduction was applied.',
      `Final PFQS: ${score}/100 — ${rating(score)}.`,
    ],
    missing_fields: [...new Set(missing)], unavailable_reasons: limitations, classified_ingredients: classification.classified,
    evidence_coverage: evidenceCoverage, evidence_confidence: evidenceConfidence,
    confidence_level: confidenceLevel(evidenceConfidence), included_components: Object.keys(componentValues),
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

export function normalizePFQSJurisdiction(value: string | null | undefined) {
  const normalized = String(value ?? '').trim().toLowerCase().replace(/[^a-z]/g, '')
  if (['us', 'usa', 'unitedstates', 'unitedstatesofamerica'].includes(normalized)) return 'US'
  const raw = String(value ?? '').trim()
  return raw.length === 2 ? raw.toUpperCase() : raw || 'US'
}

function baseResult(input: PFQSInput, parsed: ReturnType<typeof parseIngredients>): PFQSResult {
  const ingredients = buildIngredientCatalog(parsed, [], [])
  return {
    score: null, rating: null, score_status: 'pending', base_score: null, additive_penalty: 0,
    ingredient_concern_penalty: 0, components: {}, additives: [], ingredient_concerns: [], ingredients,
    flags: { tier_4_additive_present: false, score_ceiling_applied: false, regulatory_flag: false },
    strengths: [], weaknesses: [], explanation: [], missing_fields: [], unavailable_reasons: [],
    evidence_coverage: 0, evidence_confidence: 0, confidence_level: 'none', included_components: [],
    parsed_ingredients: parsed, classified_ingredients: [], model_version: PFQS_MODEL_VERSION,
    ingredient_taxonomy_version: PFQS_TAXONOMY_VERSION, additive_database_version: PFQS_ADDITIVE_DATABASE_VERSION,
    ingredient_database_version: PFQS_INGREDIENT_DATABASE_VERSION,
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
  if (components.fiber?.score >= 12) values.push('High fiber density')
  if (components.protein?.score >= 8) values.push('Strong protein density')
  if (components.added_sugar?.score >= 18) values.push('Little or no added sugar')
  if (components.sodium?.score >= 13) values.push('Low sodium density')
  if (ingredients[0]?.beneficial) values.push(`${title(ingredients[0].canonical_name)} is the main ingredient`)
  return values.slice(0, 4)
}
function weaknessesFor(components: Record<string, PFQSComponent>, additives: PFQSResult['additives']) {
  const values: string[] = []
  if (components.added_sugar?.score <= 7) values.push('Added sugar reduces the score')
  if (components.sodium?.score <= 7) values.push('Sodium reduces the score')
  if (components.saturated_trans_fat?.score <= 4) values.push('Saturated or trans fat reduces the score')
  if (components.ingredient_quality?.score <= 8) values.push('The leading ingredients are mostly refined or formulation ingredients')
  for (const additive of additives.filter((item) => item.penalty > 0)) values.push(`${additive.name}: −${additive.penalty}`)
  return values.slice(0, 4)
}
function title(value: string) { return value.replace(/\b\w/g, (letter) => letter.toUpperCase()) }
function round(value: number) { return Number(value.toFixed(4)) }
function clamp(value: number, minimum: number, maximum: number) { return Math.min(Math.max(value, minimum), maximum) }

function evidenceReliability(input: PFQSInput, components: Record<string, PFQSComponent>, coverage: Record<string, number>, ingredients: ClassifiedIngredient[]) {
  const nutrients: Record<string, PFQSNutrientCode[]> = {
    added_sugar: ['energy_kcal', 'added_sugars_g'], fiber: ['energy_kcal', 'fiber_g'],
    sodium: ['energy_kcal', 'sodium_mg'], saturated_trans_fat: ['energy_kcal', 'saturated_fat_g', 'trans_fat_g'],
    protein: ['energy_kcal', 'protein_g'],
  }
  let weighted = 0
  let maximum = 0
  for (const [name, value] of Object.entries(components)) {
    const codes = nutrients[name]
    const reliability = codes
      ? codes.reduce((total, code) => total + clamp(input.nutrient_evidence?.[code]?.confidence
        ?? (input.explicitly_reported_nutrients?.includes(code) ? 1 : 0.85), 0, 1), 0) / codes.length
      : ingredients.reduce((total, ingredient) => total + ingredient.confidence, 0) / Math.max(ingredients.length, 1)
    const availableWeight = value.max * (coverage[name] ?? 1)
    weighted += reliability * availableWeight
    maximum += availableWeight
  }
  const verification = ['verified', 'community_confirmed'].includes(input.verification_status ?? '') ? 1 : 0.85
  return maximum ? weighted / maximum * verification : 0
}

function confidenceLevel(value: number): PFQSResult['confidence_level'] {
  return value >= 0.85 ? 'high' : value >= 0.6 ? 'moderate' : value > 0 ? 'low' : 'none'
}

export type { PFQSInput, PFQSResult } from './types.ts'
