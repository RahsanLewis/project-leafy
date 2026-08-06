import { nutritionScore } from '../functions/_shared/nutrition-score.ts'

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`)
  }
}

Deno.test('nutrition score requires core label nutrients', () => {
  const result = nutritionScore({ energy_kcal: 100, protein_g: 8 })
  assertEquals(result.score, null)
  assertEquals(result.missing_fields, ['sugars_g', 'saturated_fat_g', 'sodium_mg'])
})

Deno.test('nutrition score rewards fiber and protein', () => {
  const result = nutritionScore({
    energy_kcal: 120, sugars_g: 2, saturated_fat_g: 0.5,
    sodium_mg: 80, fiber_g: 5, protein_g: 12,
  })
  assertEquals(result.label, 'Excellent')
  assertEquals(result.positive_factors, ['Good source of fiber', 'High in protein'])
})

Deno.test('nutrition score identifies limiting nutrients', () => {
  const result = nutritionScore({
    energy_kcal: 450, sugars_g: 25, saturated_fat_g: 9,
    sodium_mg: 700, fiber_g: 1, protein_g: 3,
  })
  assertEquals(result.label, 'Limited')
  assertEquals(result.limiting_factors, ['High in sodium', 'High in sugar', 'High in saturated fat'])
})
