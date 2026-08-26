import { assert, assertStringIncludes } from 'jsr:@std/assert@1'

const migration = await Deno.readTextFile(
  new URL('../migrations/202608060002_comprehensive_nutrition.sql', import.meta.url),
)
const aiMigration = await Deno.readTextFile(
  new URL('../migrations/202608060004_ai_meal_estimation.sql', import.meta.url),
)

Deno.test('normalized nutrition schema keeps source versions and intake snapshots', () => {
  assertStringIncludes(migration, 'create table public.food_versions')
  assertStringIncludes(migration, 'create table public.consumption_items')
  assertStringIncludes(migration, 'create table public.consumption_item_nutrients')
  assertStringIncludes(migration, 'legacy_food_entry_id uuid unique')
  assertStringIncludes(migration, 'sync_food_entry_to_consumption_after_change')
})

Deno.test('commercial data requires consent and excludes platform health sources', () => {
  assertStringIncludes(migration, 'commercial_eligible = false or consent_grant_id is not null')
  assertStringIncludes(migration, "origin_system not in ('healthkit', 'health_connect')")
  assertStringIncludes(migration, "cg.purpose = 'commercial_dataset' and cg.revoked_at is null")
  assertStringIncludes(migration, "ci.pii_scan_status = 'approved'")
})

Deno.test('buyer-specific authorization is enforced by jurisdiction policy', () => {
  assertStringIncludes(migration, "values ('US', 'WA', true, 'RCW 19.373.070'")
  assertStringIncludes(migration, 'public.sale_authorizations sa')
  assertStringIncludes(migration, 'sa.project_id = p_project_id')
})

Deno.test('raw photos cannot become commercially eligible', () => {
  assertStringIncludes(migration, "asset_kind = 'derived_food_crop' or commercial_eligible = false")
  assertStringIncludes(migration, "metadata_stripped and redaction_status = 'approved'")
  assert(migration.includes("bucket_id = 'nutrition-media'"))
})

Deno.test('AI meals retain predictions, corrections, media, and grouped occasions', () => {
  assertStringIncludes(aiMigration, 'create table public.ai_meal_sessions')
  assertStringIncludes(aiMigration, 'create table public.ai_meal_items')
  assertStringIncludes(aiMigration, 'predicted_calories')
  assertStringIncludes(aiMigration, 'confirmed_calories')
  assertStringIncludes(aiMigration, 'ai_meal_session_id')
  assertStringIncludes(aiMigration, 'occasion_id')
  assertStringIncludes(aiMigration, 'confirm_ai_meal')
  assertStringIncludes(aiMigration, "source_kind := case when 'photo'")
})
