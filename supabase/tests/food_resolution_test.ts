import { assert, assertEquals } from 'jsr:@std/assert'
import {
  amountsPer100g, describedGrams, deterministicFoodKey, gramsForRequestedServing, likelySingleReusableFood,
  normalizeFoodQuery, nutritionFactsCore, nutrientsForPortion, requestedServing,
  reusableEstimate,
} from '../functions/_shared/food-resolution.ts'

Deno.test('normalizes catalog queries without preserving punctuation', () => {
  assertEquals(normalizeFoodQuery('  Grilled  Chicken—Breast! '), 'grilled chicken breast')
  assertEquals(deterministicFoodKey('Grilled Chicken Breast', 'prepared'), 'prepared:grilled chicken breast')
})

Deno.test('selects the matching USDA portion and respects its stored amount', () => {
  const portions = [
    { amount: 1, unit: 'tablespoon', description: '1 tbsp', gram_weight: 16 },
    { amount: 0.5, unit: 'cup', description: '1/2 cup', gram_weight: 120 },
  ]
  assertEquals(gramsForRequestedServing({ amount: 2, unit: 'tbsp' }, portions), 32)
  assertEquals(gramsForRequestedServing({ amount: 1, unit: 'cup' }, portions), 240)
  assertEquals(gramsForRequestedServing({ amount: 2, unit: 'oz' }, portions), 56.699)
})

Deno.test('distinguishes reusable items from mixed meal descriptions', () => {
  assert(likelySingleReusableFood('scrambled eggs'))
  assert(!likelySingleReusableFood('scrambled eggs and toast'))
  assert(!likelySingleReusableFood('rice, beans, salsa'))
})

Deno.test('extracts explicit serving information', () => {
  assertEquals(describedGrams('Chicken\nServing consumed: 170 g'), 170)
  assertEquals(requestedServing('Chicken\nServing consumed: 2 serving'), { amount: 2, unit: 'serving' })
  assertEquals(requestedServing('Oats\nServing consumed: 0.5 cup'), { amount: 0.5, unit: 'cup' })
})

Deno.test('scales catalog nutrients to a consumed portion and back to 100 grams', () => {
  const portion = nutrientsForPortion([
    { nutrient_code: 'protein_g', amount_per_100g: 20 },
    { nutrient_code: 'sodium_mg', amount_per_100g: 120 },
  ], 150, 1)
  assertEquals(portion.map((value) => [value.code, value.amount]), [
    ['protein_g', 30], ['sodium_mg', 180],
  ])
  assertEquals(amountsPer100g([{ code: 'protein_g', amount: 30 }], 300, 150), [
    { nutrient_code: 'protein_g', amount_per_100g: 20 },
    { nutrient_code: 'energy_kcal', amount_per_100g: 200 },
  ])
})

Deno.test('AI catalog promotion requires confidence, grams, and Nutrition Facts coverage', () => {
  const nutrients = nutritionFactsCore.map((code) => ({ code, amount: 1, confidence: 0.8 }))
  assert(reusableEstimate(0.8, 100, nutrients))
  assert(!reusableEstimate(0.79, 100, nutrients))
  assert(!reusableEstimate(0.9, null, nutrients))
  assert(!reusableEstimate(0.9, 100, nutrients.slice(1)))
})
