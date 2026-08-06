import { assert, assertEquals, assertThrows } from 'jsr:@std/assert'
import { normalizeMealOutput, systemPrompt, userPrompt } from '../functions/_shared/meal-estimate.ts'

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
  assert(systemPrompt(true).includes('must return status ready'))
})
