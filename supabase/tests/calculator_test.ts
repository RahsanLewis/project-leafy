import { assertEquals, assert } from 'jsr:@std/assert@1'
import { calculate } from '../functions/_shared/calculator.ts'

Deno.test('male steady loss matches the Swift fixture', () => {
  const result = calculate({
    birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180,
    current_weight_kg: 90, target_weight_kg: 80, activity_level: 'moderate',
    goal: 'lose', pace: 'steady', unit_system: 'metric',
  }, new Date('2026-07-29T12:00:00Z'))
  assertEquals(result.bmr_kcal, 1880)
  assertEquals(result.tdee_kcal, 2914)
  assertEquals(result.calorie_target_kcal, 2480)
  assertEquals(result.protein_g, 128)
  assertEquals(result.fat_g, 83)
  assertEquals(result.carbohydrate_g, 306)
  assert(result.estimated_goal_date)
})
