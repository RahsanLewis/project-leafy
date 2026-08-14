import { assertStringIncludes } from 'jsr:@std/assert@1'

const migration = await Deno.readTextFile(
  new URL('../migrations/202608080001_catalog_contributions.sql', import.meta.url),
)
const functionSource = await Deno.readTextFile(
  new URL('../functions/manage-catalog-contribution/index.ts', import.meta.url),
)

Deno.test('catalog contributions retain revisions, nutrients, evidence, and status events', () => {
  assertStringIncludes(migration, 'create table public.catalog_contribution_revisions')
  assertStringIncludes(migration, 'create table public.catalog_contribution_nutrients')
  assertStringIncludes(migration, 'create table public.catalog_contribution_events')
  assertStringIncludes(migration, "'catalog_product_contribution'")
})

Deno.test('product label images remain private user-owned evidence', () => {
  assertStringIncludes(migration, "'back_label'")
  assertStringIncludes(functionSource, 'metadata_stripped: true')
  assertStringIncludes(functionSource, "storage.from('nutrition-media')")
})

Deno.test('automatic publication requires evidence, nutrition completeness, and calorie consistency', () => {
  assertStringIncludes(functionSource, 'confidence >= 0.9')
  assertStringIncludes(functionSource, 'calorieDifference <= Math.max(20, calories * 0.15)')
  assertStringIncludes(functionSource, "evidence.front_legible === true")
  assertStringIncludes(functionSource, "status = validation.missing_fields.length ? 'needs_review'")
})
