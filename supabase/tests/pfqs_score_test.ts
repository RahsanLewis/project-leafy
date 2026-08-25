import {
  calculateAdditivePenalty, calculatePFQS, scoreAddedSugar, scoreBeneficialFoods,
  normalizePFQSJurisdiction, scoreFiber, scoreIngredientQuality, scoreProtein, scoreSaturatedTransFat, scoreSodium,
} from '../functions/_shared/pfqs/scorer.ts'
import { parseIngredients } from '../functions/_shared/pfqs/ingredient-parser.ts'
import { classifyTopLevelIngredients } from '../functions/_shared/pfqs/ingredient-taxonomy.ts'

function assertEquals(actual: unknown, expected: unknown, message = '') {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`${message}\nExpected ${JSON.stringify(expected)} but received ${JSON.stringify(actual)}`)
}

Deno.test('PFQS nutrient thresholds are exact at every boundary', () => {
  assertEquals([scoreAddedSugar(0), scoreAddedSugar(0.5), scoreAddedSugar(1), scoreAddedSugar(1.01), scoreAddedSugar(5), scoreAddedSugar(5.01)], [20, 18, 18, 15, 3, 0])
  assertEquals([scoreFiber(0.49), scoreFiber(0.5), scoreFiber(0.99), scoreFiber(1), scoreFiber(2.99), scoreFiber(3)], [0, 3, 3, 6, 12, 15])
  assertEquals([scoreSodium(50), scoreSodium(50.01), scoreSodium(100), scoreSodium(300), scoreSodium(300.01)], [15, 13, 13, 4, 0])
  assertEquals([scoreProtein(1.99), scoreProtein(2), scoreProtein(3.99), scoreProtein(4), scoreProtein(8)], [0, 3, 3, 6, 10])
  assertEquals([scoreSaturatedTransFat(0.5, 0), scoreSaturatedTransFat(0.51, 0), scoreSaturatedTransFat(0.2, 0.1), scoreSaturatedTransFat(0.2, 0.5)], [10, 8, 4, 0])
})

Deno.test('ingredient parser preserves top-level order and nested additives', () => {
  const parsed = parseIngredients('Whole grain oats, chocolate chips (sugar, chocolate liquor, soy lecithin), almonds')
  assertEquals(parsed.map((item) => item.canonical_name), ['whole grain oats', 'chocolate chips', 'almonds'])
  assertEquals(parsed[1].subingredients.map((item) => item.canonical_name), ['sugar', 'chocolate liquor', 'soy lecithin'])
})

Deno.test('ingredient and beneficial scoring normalize short ingredient lists', () => {
  const parsed = parseIngredients('Whole grain oats, sugar, almonds')
  const { classified, unresolved } = classifyTopLevelIngredients(parsed)
  assertEquals(unresolved.length, 0)
  assertEquals(scoreIngredientQuality(classified), 14)
  assertEquals(scoreBeneficialFoods(classified), 7)
})

Deno.test('complete PFQS example produces its deterministic component sum', () => {
  const result = calculatePFQS({
    product_name: 'Oat and almond cereal', jurisdiction: 'US', assessment_date: '2026-08-13',
    serving_size: { amount: 50, unit: 'g' }, verification_status: 'verified',
    nutrition: { energy_kcal: 200, added_sugars_g: 3.4, fiber_g: 4.8, sodium_mg: 260, saturated_fat_g: 2, trans_fat_g: 0, protein_g: 14 },
    explicitly_reported_nutrients: ['energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg', 'saturated_fat_g', 'trans_fat_g', 'protein_g'],
    ingredients_raw: 'Whole grain oats, sugar, almonds',
  })
  assertEquals(result.score_status, 'complete')
  assertEquals(result.components.added_sugar.score, 15)
  assertEquals(result.components.fiber.score, 12)
  assertEquals(result.components.sodium.score, 10)
  assertEquals(result.components.saturated_trans_fat.score, 8)
  assertEquals(result.components.protein.score, 8)
  assertEquals(result.score, 74)
})

Deno.test('missing trans fat produces a numeric provisional score without assuming zero', () => {
  const result = calculatePFQS({
    product_name: 'Test food', jurisdiction: 'US', assessment_date: '2026-08-13',
    serving_size: { amount: 30, unit: 'g' }, verification_status: 'verified',
    nutrition: { energy_kcal: 120, added_sugars_g: 0, fiber_g: 3, sodium_mg: 50, saturated_fat_g: 0, protein_g: 5 },
    explicitly_reported_nutrients: ['energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg', 'saturated_fat_g', 'protein_g'],
    ingredients_raw: 'Whole grain oats',
  })
  assertEquals(result.score_status, 'provisional')
  assertEquals(result.score, 92)
  assertEquals(result.evidence_coverage, 0.9)
  assertEquals(result.missing_fields.includes('trans_fat_g'), true)
})

Deno.test('unknown ingredients reduce coverage instead of blocking known nutrition', () => {
  const result = calculatePFQS({
    product_name: 'Unfamiliar food', jurisdiction: 'US', assessment_date: '2026-08-25',
    serving_size: { amount: 30, unit: 'g' }, verification_status: 'verified',
    nutrition: { energy_kcal: 100, added_sugars_g: 0, fiber_g: 2, sodium_mg: 100, saturated_fat_g: 1, trans_fat_g: 0, protein_g: 4 },
    explicitly_reported_nutrients: ['energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg', 'saturated_fat_g', 'trans_fat_g', 'protein_g'],
    ingredients_raw: 'Uncatalogued botanical blend',
  })
  assertEquals(result.score_status, 'provisional')
  assertEquals(result.evidence_coverage, 0.7)
  assertEquals(result.missing_fields, ['ingredient_classification:uncatalogued botanical blend'])
})

Deno.test('unverified ordinary foods remain eligible while specialized products do not', () => {
  const ordinary = calculatePFQS({
    product_name: 'Estimated soup', jurisdiction: 'US', assessment_date: '2026-08-25',
    serving_size: { amount: 1, unit: 'bowl' }, verification_status: 'unverified', product_type: 'restaurant',
    nutrition: { energy_kcal: 200, sodium_mg: 500 }, ingredients_raw: '',
  })
  assertEquals(ordinary.score_status, 'provisional')
  assertEquals(ordinary.score !== null, true)
  const supplement = calculatePFQS({ ...ordinaryInput(), product_type: 'supplement' })
  assertEquals(supplement.score_status, 'ineligible')
})

Deno.test('zero scorable evidence is pending and common US names normalize', () => {
  const result = calculatePFQS({
    product_name: 'Unknown food', jurisdiction: 'US', assessment_date: '2026-08-25',
    serving_size: { amount: 1, unit: 'serving' }, verification_status: 'unverified',
    nutrition: { energy_kcal: 100 }, ingredients_raw: '', product_type: 'manual',
  })
  assertEquals(result.score_status, 'pending')
  assertEquals(result.score, null)
  assertEquals(['US', 'USA', 'United States', 'United States of America'].map(normalizePFQSJurisdiction), ['US', 'US', 'US', 'US'])
})

Deno.test('50 calorie floor is used for very low calorie products', () => {
  const result = calculatePFQS({
    product_name: 'Low calorie test', jurisdiction: 'US', assessment_date: '2026-08-13',
    serving_size: { amount: 30, unit: 'g' }, verification_status: 'verified',
    nutrition: { energy_kcal: 10, added_sugars_g: 1, fiber_g: 0, sodium_mg: 25, saturated_fat_g: 0, trans_fat_g: 0, protein_g: 0 },
    explicitly_reported_nutrients: ['energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg', 'saturated_fat_g', 'trans_fat_g', 'protein_g'],
    ingredients_raw: 'Sugar',
  })
  assertEquals(result.components.added_sugar.normalized_value, 2)
})

Deno.test('additive aliases are deduplicated and Tier 4 caps the score', () => {
  const result = calculatePFQS({
    product_name: 'Colored oats', jurisdiction: 'US', assessment_date: '2027-02-01',
    serving_size: { amount: 30, unit: 'g' }, verification_status: 'verified',
    nutrition: { energy_kcal: 100, added_sugars_g: 0, fiber_g: 4, sodium_mg: 20, saturated_fat_g: 0, trans_fat_g: 0, protein_g: 8 },
    explicitly_reported_nutrients: ['energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg', 'saturated_fat_g', 'trans_fat_g', 'protein_g'],
    ingredients_raw: 'Whole grain oats, FD&C Red No. 3, erythrosine',
    frozen_ingredient_classifications: [
      { canonical_name: 'fd and c red no. 3', quality_class: 'E', beneficial: false, confidence: 1, source: 'human_review' },
      { canonical_name: 'erythrosine', quality_class: 'E', beneficial: false, confidence: 1, source: 'human_review' },
    ],
  })
  assertEquals(result.additives.length, 1)
  assertEquals(result.additive_penalty, 15)
  assertEquals(result.score, 50)
  assertEquals(result.flags.score_ceiling_applied, true)
})

Deno.test('total additive penalty is capped at 25', () => {
  assertEquals(calculateAdditivePenalty([
    additiveResult('a', 15), additiveResult('b', 15), additiveResult('c', 7),
  ]), 25)
})

function additiveResult(id: string, penalty: number): any {
  return { name: id, canonical_id: id, family: null, tier: 4, penalty, status: 'classified', reason: '', matched_alias: id }
}

function ordinaryInput(): any {
  return {
    product_name: 'Food', jurisdiction: 'US', assessment_date: '2026-08-25',
    serving_size: { amount: 1, unit: 'serving' }, verification_status: 'verified',
    nutrition: { energy_kcal: 100, sodium_mg: 100 }, ingredients_raw: '',
  }
}
