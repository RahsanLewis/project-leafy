import { nutrientCodes, type EstimatedNutrient, type NutrientCode } from './nutrients.ts'

export const resolverVersion = 'leafy-food-resolver-v1'

export const nutritionFactsCore = [
  'protein_g', 'carbohydrate_g', 'fat_g', 'fiber_g', 'sugars_g',
  'added_sugars_g', 'saturated_fat_g', 'trans_fat_g', 'cholesterol_mg', 'sodium_mg',
  'potassium_mg', 'calcium_mg', 'iron_mg', 'vitamin_d_mcg',
] as const

export type ResolutionSource = 'leafy_catalog' | 'usda' | 'ai'

export function normalizeFoodQuery(value: string) {
  return value.toLowerCase().normalize('NFKD')
    .replace(/[^a-z0-9]+/g, ' ').replace(/\s+/g, ' ').trim()
}

export function likelySingleReusableFood(value: string) {
  const text = normalizeFoodQuery(value)
  if (!text || text.length > 140) return false
  return !/\b(and|with a side of|plus)\b/.test(text) && !/[;,]/.test(value)
}

export function describedGrams(value: string) {
  const match = value.match(/(?:^|\s)(\d+(?:\.\d+)?)\s*(?:g|gram|grams)\b/i)
  if (!match) return null
  const grams = Number(match[1])
  return Number.isFinite(grams) && grams > 0 && grams <= 5000 ? grams : null
}

export function requestedServing(value: string) {
  const match = value.match(/Serving consumed:\s*(\d+(?:\.\d+)?)\s*(serving|g|oz|cup|piece|tbsp|tsp)\b/i)
  if (!match) return null
  const amount = Number(match[1])
  return Number.isFinite(amount) && amount > 0 && amount <= 100
    ? { amount, unit: match[2].toLowerCase() }
    : null
}

export type StoredFoodPortion = {
  amount: number
  unit: string
  description: string
  gram_weight: number
}

function canonicalServingUnit(value: string) {
  const unit = normalizeFoodQuery(value)
  if (/\b(ounce|ounces|oz)\b/.test(unit)) return 'oz'
  if (/\b(gram|grams|g)\b/.test(unit)) return 'g'
  if (/\b(cup|cups)\b/.test(unit)) return 'cup'
  if (/\b(tablespoon|tablespoons|tbsp)\b/.test(unit)) return 'tbsp'
  if (/\b(teaspoon|teaspoons|tsp)\b/.test(unit)) return 'tsp'
  if (/\b(piece|pieces|item|items)\b/.test(unit)) return 'piece'
  if (/\b(serving|servings)\b/.test(unit)) return 'serving'
  return unit
}

export function gramsForRequestedServing(
  requested: { amount: number; unit: string } | null,
  portions: StoredFoodPortion[],
) {
  if (!requested) return Number(portions[0]?.gram_weight ?? 100)
  if (requested.unit === 'g') return requested.amount
  if (requested.unit === 'oz') return requested.amount * 28.3495

  const wanted = canonicalServingUnit(requested.unit)
  const portion = portions.find((candidate) =>
    canonicalServingUnit(candidate.unit) === wanted
    || canonicalServingUnit(candidate.description) === wanted
    || normalizeFoodQuery(candidate.description).includes(wanted)
  ) ?? portions[0]
  if (!portion) return requested.amount * 100
  const storedAmount = Number(portion.amount) > 0 ? Number(portion.amount) : 1
  return requested.amount * Number(portion.gram_weight) / storedAmount
}

export function reusableEstimate(
  confidence: number,
  grams: number | null,
  nutrients: { code: string; amount: number; confidence?: number }[],
) {
  if (confidence < 0.80 || !grams || grams <= 0) return false
  const codes = new Set(nutrients.map((item) => item.code))
  return nutritionFactsCore.every((code) => codes.has(code))
}

export function nutrientsForPortion(
  per100g: { nutrient_code?: string; code?: string; amount_per_100g: number }[],
  grams: number,
  confidence: number,
): EstimatedNutrient[] {
  return per100g.flatMap((item) => {
    const code = String(item.nutrient_code ?? item.code ?? '') as NutrientCode
    const amount = Number(item.amount_per_100g) * grams / 100
    if (!nutrientCodes.includes(code) || !Number.isFinite(amount) || amount < 0) return []
    return [{ code, amount: Number(amount.toFixed(6)), confidence }]
  })
}

export function amountsPer100g(
  nutrients: { code: string; amount: number }[],
  calories: number,
  grams: number,
) {
  const rows = nutrients.flatMap((item) => {
    if (!nutrientCodes.includes(item.code as NutrientCode)) return []
    const amount = Number(item.amount) * 100 / grams
    return Number.isFinite(amount) && amount >= 0
      ? [{ nutrient_code: item.code, amount_per_100g: Number(amount.toFixed(6)) }]
      : []
  })
  rows.push({ nutrient_code: 'energy_kcal', amount_per_100g: Number((calories * 100 / grams).toFixed(6)) })
  return rows
}

export function deterministicFoodKey(name: string, kind: string) {
  return `${kind}:${normalizeFoodQuery(name)}`
}
