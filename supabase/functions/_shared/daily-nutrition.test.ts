import { assertEquals, assertAlmostEquals } from 'jsr:@std/assert@1'
import { buildDailyNutritionSummary, type NutritionRow } from './daily-nutrition.ts'

const dates = ['2026-08-20', '2026-08-21', '2026-08-22', '2026-08-23', '2026-08-24', '2026-08-25', '2026-08-26']

Deno.test('seven-day flags require four covered days and use a 90 percent low threshold', () => {
  const definitions: NutritionRow[] = [{
    code: 'vitamin_c_mg', name: 'Vitamin C', unit: 'mg', nutrient_class: 'vitamin',
    display_order: 1, target_kind: 'goal', is_displayed: true,
  }]
  const items = dates.slice(0, 4).map((date, index) => ({
    id: `item-${index}`, local_date: date, description: `Food ${index}`, calories_kcal: 100,
  }))
  const observations = items.map((item, index) => ({
    consumption_item_id: item.id, nutrient_code: 'vitamin_c_mg', amount: index === 3 ? 66 : 60,
    derivation_method: 'estimated', confidence: 0.8,
  }))
  const summary = buildDailyNutritionSummary(dates[6], dates, items, observations, {
    definitions, legacyTargets: new Map(),
    profile: { birth_date: '1990-01-01', calculation_sex: 'female', current_weight_kg: 60 },
    weights: [{ recorded_on: '2026-01-01', weight_kg: 60 }],
  })
  const nutrient = summary.nutrients[0]
  assertEquals(nutrient.trend_qualifying_days, 4)
  assertEquals(nutrient.below_target_flag, true)
  assertAlmostEquals(nutrient.trend_percent_of_target!, 0.82)
})

Deno.test('all contributing foods are returned in descending amount order', () => {
  const definitions: NutritionRow[] = [{
    code: 'fiber_g', name: 'Fiber', unit: 'g', nutrient_class: 'fiber',
    display_order: 1, target_kind: 'goal', is_displayed: true,
  }]
  const items = [
    { id: 'one', local_date: dates[6], description: 'Beans', calories_kcal: 200 },
    { id: 'two', local_date: dates[6], description: 'Berries', calories_kcal: 100 },
  ]
  const observations = [
    { consumption_item_id: 'one', nutrient_code: 'fiber_g', amount: 8, derivation_method: 'calculated' },
    { consumption_item_id: 'two', nutrient_code: 'fiber_g', amount: 3, derivation_method: 'estimated' },
  ]
  const summary = buildDailyNutritionSummary(dates[6], dates, items, observations, {
    definitions, legacyTargets: new Map(),
    profile: { birth_date: '1990-01-01', calculation_sex: 'female', current_weight_kg: 60 },
    weights: [],
  })
  assertEquals(summary.nutrients[0].food_sources.map((source) => source.name), ['Beans', 'Berries'])
  assertEquals(summary.nutrients[0].amount, 11)
})
