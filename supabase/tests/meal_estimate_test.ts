import { assert, assertEquals, assertThrows } from 'jsr:@std/assert'
import {
  chatMealGroundingReminder, mealPromptVersion, mealSchemaVersion,
  normalizeMealOutput, systemPrompt, userPrompt,
} from '../functions/_shared/meal-estimate.ts'

Deno.test('normalizes item calories and calculates totals from items', () => {
  const result = normalizeMealOutput({
    status: 'ready', follow_up_question: null,
    items: [
      { name: 'Grilled chicken', portion: 'one breast', estimated_grams: 170, calories: 280, calorie_low: 240, calorie_high: 330, confidence: 0.8, assumptions: [] },
      { name: 'Rice', portion: 'one cup', estimated_grams: 190, calories: 240, calorie_low: 200, calorie_high: 300, confidence: 0.7, assumptions: ['Cooked'] },
    ],
    total_calories: 999, calorie_low: 1, calorie_high: 2, confidence: 0.72, assumptions: [],
  })
  assertEquals(result.total_calories, 520)
  assertEquals(result.calorie_low, 440)
  assertEquals(result.calorie_high, 630)
})

Deno.test('force ready suppresses further clarification', () => {
  const result = normalizeMealOutput({
    status: 'needs_clarification', follow_up_question: 'How much dressing?',
    items: [{ name: 'Salad', portion: 'one bowl', estimated_grams: null, calories: 300, calorie_low: 150, calorie_high: 600, confidence: 0.3, assumptions: [] }],
    total_calories: 300, calorie_low: 150, calorie_high: 600, confidence: 0.3, assumptions: [],
  }, true)
  assertEquals(result.status, 'ready')
  assertEquals(result.follow_up_question, null)
})

Deno.test('rejects estimates without food items', () => {
  assertThrows(() => normalizeMealOutput({ status: 'ready', items: [] }))
})

Deno.test('prompts combine typed, spoken, and clarification context', () => {
  const prompt = userPrompt('two tacos', 'with chicken', [{ question: 'Any cheese?', answer: 'No' }])
  assert(prompt.includes('Typed description: two tacos'))
  assert(prompt.includes('Voice transcript: with chicken'))
  assert(prompt.includes('Answer: No'))
  assert(systemPrompt().includes('Always return status ready'))
})

Deno.test('grounded exact restaurant meal keeps every item and deterministic total', () => {
  const official = (name: string, calories: number, portion: string) => ({
    name, portion, estimated_grams: null, calories, calorie_low: calories, calorie_high: calories,
    confidence: 0.99, assumptions: [], nutrients: [], nutrition_basis: 'official',
    market_country: 'US', source_title: "McDonald's", source_url: 'https://www.mcdonalds.com/us/en-us/about-our-food/nutrition-calculator.html',
    source_kind: 'restaurant', exact_source_match: true,
  })
  const result = normalizeMealOutput({
    status: 'ready', follow_up_question: null,
    items: [
      official('Bacon Caesar McCrispy', 750, '1 sandwich'),
      official('French Fries', 480, '1 large order'),
      official('Coke Zero', 0, '1 large drink'),
    ],
    total_calories: 0, calorie_low: 0, calorie_high: 0, confidence: 0.99, assumptions: [],
  }, true)
  assertEquals(result.items.length, 3)
  assertEquals(result.total_calories, 1230)
  assertEquals(result.calorie_low, 1230)
  assertEquals(result.calorie_high, 1230)
  assertEquals(result.follow_up_question, null)
})

Deno.test('grounded prompt is answer first and includes zero calorie drinks', () => {
  const prompt = systemPrompt('US')
  assert(prompt.includes('never block the first result'))
  assert(prompt.includes('including zero-calorie drinks'))
  assert(prompt.includes('restaurant or manufacturer'))
})

Deno.test('chat meal grounding stays aligned with meal v3 versions and semantics', () => {
  assertEquals(mealPromptVersion, 'leafy-meal-grounded-v3')
  assertEquals(mealSchemaVersion, 3)
  const reminder = chatMealGroundingReminder()
  assert(reminder.includes(mealPromptVersion))
  assert(reminder.includes('schema 3'))
  assert(reminder.includes('including zero-calorie drinks'))
  assert(reminder.includes('nutrition_basis'))
  assert(reminder.includes('Never present estimates as laboratory'))
  assert(reminder.includes('Do not ask a follow-up before showing the first result'))
})
