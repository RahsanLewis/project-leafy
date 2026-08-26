import { assertEquals, assertAlmostEquals } from 'jsr:@std/assert@1'
import { ageOnDate, resolveNutrientReference } from './dri.ts'

Deno.test('DRI resolver honors birthdays and adult age/sex boundaries', () => {
  assertEquals(ageOnDate('1975-08-27', '2026-08-26'), 50)
  assertEquals(ageOnDate('1975-08-26', '2026-08-26'), 51)
  assertEquals(resolveNutrientReference('iron_mg', 40, 'female', 70).targetAmount, 18)
  assertEquals(resolveNutrientReference('iron_mg', 51, 'female', 70).targetAmount, 8)
  assertEquals(resolveNutrientReference('calcium_mg', 51, 'female', 70).targetAmount, 1200)
  assertEquals(resolveNutrientReference('vitamin_d_mcg', 71, 'male', 70).targetAmount, 20)
})

Deno.test('amino acid targets use weight and official combined pair bases', () => {
  const leucine = resolveNutrientReference('leucine_g', 35, 'male', 80)
  assertAlmostEquals(leucine.targetAmount!, 3.36)
  const methionine = resolveNutrientReference('methionine_g', 35, 'male', 80)
  assertEquals(methionine.targetBasisCodes, ['methionine_g', 'cystine_g'])
  assertAlmostEquals(methionine.targetAmount!, 1.52)
  assertEquals(resolveNutrientReference('phenylalanine_g', 35, 'female', 60).targetBasisCodes,
    ['phenylalanine_g', 'tyrosine_g'])
})

Deno.test('restricted upper limits never masquerade as total intake limits', () => {
  assertEquals(resolveNutrientReference('vitamin_a_mcg_rae', 35, 'female', 60).upperLimitScope, 'preformed_only')
  assertEquals(resolveNutrientReference('magnesium_mg', 35, 'female', 60).upperLimitScope, 'supplemental_only')
  assertEquals(resolveNutrientReference('vitamin_c_mg', 35, 'female', 60).upperLimitScope, 'total')
  assertEquals(resolveNutrientReference('sodium_mg', 35, 'female', 60).upperLimitAmount, null)
  assertEquals(resolveNutrientReference('sodium_mg', 35, 'female', 60).guidanceLimitAmount, 2300)
})

Deno.test('chromium and sulfur remain non-diagnostic', () => {
  const chromium = resolveNutrientReference('chromium_mcg', 35, 'female', 60)
  assertEquals(chromium.targetType, 'legacy_ai')
  assertEquals(chromium.lowFlagEnabled, false)
  const sulfur = resolveNutrientReference('sulfur_mg', 35, 'female', 60)
  assertEquals(sulfur.targetAmount, null)
  assertEquals(sulfur.upperLimitAmount, null)
})
