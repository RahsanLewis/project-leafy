import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1'
import { normalizeNutrients, nutrientCodes } from '../functions/_shared/nutrients.ts'

const migration = await Deno.readTextFile(
  new URL('../migrations/202608070002_daily_nutrition.sql', import.meta.url),
)
const essentialMigration = await Deno.readTextFile(
  new URL('../migrations/202608260001_essential_nutrient_tracking.sql', import.meta.url),
)

Deno.test('nutrient normalization keeps the FDA set and rejects invalid values', () => {
  const nutrients = normalizeNutrients([
    { code: 'protein_g', amount: 42, confidence: 0.8 },
    { code: 'sodium_mg', amount: -1 },
    { code: 'not_a_nutrient', amount: 10 },
  ])

  assertEquals(nutrients.length, 1)
  assertEquals(nutrients[0].code, 'protein_g')
  assertEquals(nutrients[0].amount, 42)
  assertEquals(nutrientCodes.includes('vitamin_b12_mcg'), true)
  const supportedCodes: readonly string[] = nutrientCodes
  assertEquals(supportedCodes.includes('water_g'), false)
  assertEquals(supportedCodes.includes('alcohol_g'), false)
  assertEquals(supportedCodes.includes('histidine_g'), true)
  assertEquals(supportedCodes.includes('alpha_linolenic_acid_g'), true)
})

Deno.test('essential nutrient migration includes source aliases and a scoped backfill', () => {
  assertStringIncludes(essentialMigration, "'sulfur_mg', 1094")
  assertStringIncludes(essentialMigration, "'linoleic_acid_g', 1316")
  assertStringIncludes(essentialMigration, "1269, 'linoleic_acid_g'")
  assertStringIncludes(essentialMigration, 'nasem_dri_adults_2026_1')
  assertStringIncludes(essentialMigration, 'raw_backfill_2026_1')
})

Deno.test('daily nutrition migration is versioned and preserves nutrient provenance', () => {
  assertStringIncludes(migration, 'fda_adults_4_plus_2020')
  assertStringIncludes(migration, 'create table public.nutrient_reference_sets')
  assertStringIncludes(migration, 'create table public.ai_meal_item_nutrients')
  assertStringIncludes(migration, 'create or replace function public.replace_food_entry_nutrients')
  assertStringIncludes(migration, 'derivation_method')
  assertStringIncludes(migration, 'source_version')
})
