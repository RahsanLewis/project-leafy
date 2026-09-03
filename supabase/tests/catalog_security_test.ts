import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1'
import {
  catalogReviewKeyAuthorizes,
  configuredBootstrapAdminEmails,
  configuredCatalogReviewKey,
  emailMatchesBootstrapAllowlist,
  userContributionQueueStatus,
} from '../functions/_shared/catalog-admin.ts'

const reviewSource = await Deno.readTextFile(
  new URL('../functions/review-catalog-contribution/index.ts', import.meta.url),
)
const reviewRetrySource = await Deno.readTextFile(
  new URL(
    '../functions/review-catalog-contribution/retry-recognition.ts',
    import.meta.url,
  ),
)
const manageSource = await Deno.readTextFile(
  new URL('../functions/manage-catalog-contribution/index.ts', import.meta.url),
)
const estimateSource = await Deno.readTextFile(
  new URL('../functions/estimate-meal/index.ts', import.meta.url),
)
const writeLockdown = await Deno.readTextFile(
  new URL('../migrations/202609010001_catalog_contribution_write_lockdown.sql', import.meta.url),
)
const config = await Deno.readTextFile(
  new URL('../config.toml', import.meta.url),
)
const mealWritePattern = await Deno.readTextFile(
  new URL('../migrations/202608060004_ai_meal_estimation.sql', import.meta.url),
)

Deno.test('F-01 missing bootstrap allowlist fails closed and never defaults to a hardcoded email', () => {
  assertEquals(configuredBootstrapAdminEmails(undefined).size, 0)
  assertEquals(configuredBootstrapAdminEmails(null).size, 0)
  assertEquals(configuredBootstrapAdminEmails('').size, 0)
  assertEquals(configuredBootstrapAdminEmails('  ,  ').size, 0)
  assertEquals(
    emailMatchesBootstrapAllowlist('rahsan@beyondsolid.dev', new Set()),
    false,
  )
  assert(!reviewSource.includes('rahsan@beyondsolid.dev'))
  assert(!reviewSource.includes('?? "rahsan'))
  assert(!reviewSource.includes('admin_memberships").upsert'))
  assertStringIncludes(reviewSource, 'configuredBootstrapAdminEmails')
  assertStringIncludes(reviewSource, 'emailMatchesBootstrapAllowlist')
})

Deno.test('F-01 explicit non-default allowlist matches email in memory without implying membership upsert', () => {
  const allowlist = configuredBootstrapAdminEmails('ops@example.com, Admin@Leafy.app')
  assertEquals(allowlist.has('ops@example.com'), true)
  assertEquals(emailMatchesBootstrapAllowlist('Admin@leafy.app', allowlist), true)
  assertEquals(emailMatchesBootstrapAllowlist('other@example.com', allowlist), false)
})

Deno.test('F-02 user contribution paths queue pending review and never publish food_versions', () => {
  assertEquals(userContributionQueueStatus(0), 'pending_review')
  assertEquals(userContributionQueueStatus(1), 'needs_review')
  assertStringIncludes(manageSource, 'userContributionQueueStatus')
  assertStringIncludes(manageSource, 'const status = "pending_review"')
  assert(!manageSource.includes('async function publish('))
  assert(!manageSource.includes('.from("foods").insert'))
  assert(!manageSource.includes('.from("food_versions").insert'))
  assert(!manageSource.includes('status = "accepted"'))
  assertStringIncludes(reviewSource, 'await publish(admin, contribution)')
  assertStringIncludes(reviewSource, 'status: "accepted"')
})

Deno.test('F-02 estimate-meal does not promote confirmed AI items into the shared catalog', () => {
  assert(!estimateSource.includes('promoteAIEstimate'))
  assert(!estimateSource.includes(".from('foods').insert"))
  assert(!estimateSource.includes(".from('food_versions').insert"))
  assertStringIncludes(estimateSource, 'catalog_admin acceptance or trusted-source ingest')
})

Deno.test('F-03 authenticated clients have SELECT-only catalog contribution writes locked to Edge', () => {
  assertStringIncludes(writeLockdown, 'drop policy if exists "users manage own catalog contributions"')
  assertStringIncludes(writeLockdown, 'drop policy if exists "users manage own product label assets"')
  assertStringIncludes(writeLockdown, 'create policy "users read own catalog contributions"')
  assertStringIncludes(writeLockdown, 'create policy "users read own product label assets"')
  assertStringIncludes(writeLockdown, 'for select to authenticated')
  assertStringIncludes(
    writeLockdown,
    'revoke insert, update, delete on public.catalog_contributions, public.product_label_assets',
  )
  assert(!writeLockdown.toLowerCase().includes('for all'))
  assertStringIncludes(mealWritePattern, 'revoke insert, update, delete on public.ai_meal_sessions')
})

Deno.test('F-07 catalog review key fails closed and never falls back to the service role', () => {
  assertEquals(configuredCatalogReviewKey(undefined), null)
  assertEquals(configuredCatalogReviewKey(''), null)
  assertEquals(configuredCatalogReviewKey('   '), null)
  assertEquals(catalogReviewKeyAuthorizes('secret', null), false)
  assertEquals(catalogReviewKeyAuthorizes('secret', 'secret'), true)
  assertEquals(catalogReviewKeyAuthorizes('other', 'secret'), false)
  assert(!reviewSource.includes('CATALOG_REVIEW_KEY") ?? secret'))
  assert(!manageSource.includes('CATALOG_REVIEW_KEY") ?? secret'))
  assert(!reviewRetrySource.includes('CATALOG_REVIEW_KEY") ?? secret'))
  assertStringIncludes(
    reviewRetrySource,
    'Catalog review key is not configured.',
  )
  assertStringIncludes(reviewRetrySource, 'configuredCatalogReviewKey')
  assertStringIncludes(manageSource, 'configuredCatalogReviewKey')
})

Deno.test('F-05 gateway JWT stays off only for catalog review key and retired tombstones', () => {
  for (const name of [
    'save-nutrition-plan',
    'delete-account',
    'discover-food-product',
    'estimate-meal',
    'nutrition-chat',
    'daily-nutrition',
    'manage-food-entry',
    'manage-legal-acceptance',
  ]) {
    const block = config.split(`[functions.${name}]`)[1]?.split('[functions.')[0] ?? ''
    assertStringIncludes(block, 'verify_jwt = true')
  }
  for (const name of [
    'manage-catalog-contribution',
    'review-catalog-contribution',
    'manage-data-contribution',
    'transcribe-meal-audio',
    'weight-fluctuation-context',
  ]) {
    const block = config.split(`[functions.${name}]`)[1]?.split('[functions.')[0] ?? ''
    assertStringIncludes(block, 'verify_jwt = false')
  }
})
