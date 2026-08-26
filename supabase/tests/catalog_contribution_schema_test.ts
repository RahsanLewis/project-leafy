import { assertStringIncludes } from 'jsr:@std/assert@1'

const migration = await Deno.readTextFile(
  new URL('../migrations/202608080001_catalog_contributions.sql', import.meta.url),
)
const functionSource = await Deno.readTextFile(
  new URL('../functions/manage-catalog-contribution/index.ts', import.meta.url),
)
const automationMigration = await Deno.readTextFile(
  new URL('../migrations/202608150001_automated_catalog_ingestion.sql', import.meta.url),
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
  assertStringIncludes(functionSource, 'storage.from("nutrition-media")')
})

Deno.test('automatic publication requires evidence, nutrition completeness, and calorie consistency', () => {
  assertStringIncludes(functionSource, 'confidence >= 0.9')
  assertStringIncludes(functionSource, 'calorieDifference <= Math.max(20, calories * 0.15)')
  assertStringIncludes(functionSource, "evidence.front_legible === true")
  assertStringIncludes(functionSource, 'let status = validation.missing_fields.length')
})

Deno.test('incomplete photo extraction requests focused retakes instead of a blank review form', () => {
  assertStringIncludes(functionSource, 'extraction_diagnostics: extractionDiagnostics(contribution)')
  assertStringIncludes(functionSource, 'requested.add("front")')
  assertStringIncludes(functionSource, 'requested.add("nutrition_facts")')
  assertStringIncludes(functionSource, 'requested.add("ingredients")')
  assertStringIncludes(functionSource, 'status: needsPhotos ? "needs_photos" : "complete"')
})

Deno.test('two-photo automation uses durable jobs and source provenance', () => {
  assertStringIncludes(automationMigration, 'create table public.catalog_contribution_jobs')
  assertStringIncludes(automationMigration, 'create table public.catalog_verification_sources')
  assertStringIncludes(automationMigration, "status in ('draft', 'processing'")
  assertStringIncludes(functionSource, 'action === "enqueue"')
  assertStringIncludes(functionSource, 'EdgeRuntime.waitUntil')
  assertStringIncludes(functionSource, 'tools: [{ type: "web_search" }]')
  assertStringIncludes(functionSource, "verification.result.exact_gtin_match === true")
})

Deno.test('online sources verify identity but package values remain authoritative', () => {
  assertStringIncludes(functionSource, 'The package label outranks online estimates')
  assertStringIncludes(functionSource, 'const fields = normalizeFields(body.confirmed_fields')
  assertStringIncludes(functionSource, 'let status = "pending_review"')
  assertStringIncludes(functionSource, ': "community_confirmed"')
})
