# Catalog contribution security

This document records the fail-closed catalog-admin properties and the iOS client contract after the HIGH remediations in `202609010001_catalog_contribution_write_lockdown.sql`.

## F-01 — Catalog admin bootstrap

- `review-catalog-contribution` does not hardcode a bootstrap email.
- If `CATALOG_BOOTSTRAP_ADMIN_EMAILS` is missing or empty, email bootstrap fails closed.
- Matching an explicitly configured allowlist does **not** upsert `admin_memberships`.
- Production catalog admins should be granted out of band with `scripts/manage-admin-membership.ts`.
- Optional `CATALOG_BOOTSTRAP_ADMIN_EMAILS` (comma-separated, no defaults) is an in-memory emergency allowlist only.

## F-02 — Shared catalog publication

Authenticated non-admin JWTs cannot insert or update shared `foods` / `food_versions` / nutrients / PFQS rows from:

- `manage-catalog-contribution` `submit` or `enqueue` / `runAutomation`
- `estimate-meal` confirmed AI estimates

User paths create or update **user-owned** `catalog_contributions` (and private `food_entries` logs). Shared catalog rows are written only after a human `catalog_admin` (or `CATALOG_REVIEW_KEY`) accepts the contribution in `review-catalog-contribution`.

`auto_approve` remains a reviewer hint from label-quality checks. It never publishes.

Trusted-source ingest in `discover-food-product` (USDA cache) is unchanged: it is not user-authored catalog content.

## F-03 — Client writes

After migration `202609010001_catalog_contribution_write_lockdown.sql`:

| Role | `catalog_contributions` | `product_label_assets` |
| --- | --- | --- |
| `authenticated` | SELECT own rows | SELECT own rows |
| `anon` | none | none |
| `service_role` / Edge | INSERT/UPDATE/DELETE | INSERT/UPDATE/DELETE |

iOS already writes through `manage-catalog-contribution` (`PlanService`). Direct PostgREST inserts/updates/deletes of contribution or label-asset rows will fail with a permission error. Do not add client table writes.

### How F-03 was tested

Deno tests inspect the new migration for SELECT-only policies and revoked writes. Live PostgREST verification (AppSec retest):

1. Apply the migration.
2. As an authenticated user JWT (not service role), `POST /rest/v1/catalog_contributions` and `PATCH` / `DELETE` must return `42501` / `401`/`403`.
3. `GET /rest/v1/catalog_contributions?select=id` must return only the caller’s rows.
4. Repeat for `product_label_assets`.
5. The same user JWT can still `POST /functions/v1/manage-catalog-contribution` with `action=start` (creates a **draft**) and `action=enqueue` (queues **pending_review**, does not publish).

## F-05 — `verify_jwt`

Gateway JWT verification is enabled for JWT-only live functions. Intentional `verify_jwt = false` exceptions in `supabase/config.toml`:

| Function | Reason |
| --- | --- |
| `review-catalog-contribution` | CLI / ops `CATALOG_REVIEW_KEY` without a user JWT |
| `manage-catalog-contribution` | Internal `admin_retry` using `CATALOG_REVIEW_KEY` |
| `manage-data-contribution` | Retired tombstone must return 410 without a JWT |
| `transcribe-meal-audio` | Retired tombstone must return 410 without a JWT |
| `weight-fluctuation-context` | Retired tombstone must return 410 without a JWT |

Every live function still independently calls `auth.getUser()` (or the catalog review key) and never trusts a caller-supplied user id.

## F-07 — Catalog review key

`CATALOG_REVIEW_KEY` has no service-role fallback. If the secret is unset, key auth and internal `admin_retry` fail closed.

## Product behavior

- Automatic shared-catalog publish from user submit/automation is removed.
- Confirmed AI meal items stay on the user’s private food log; they are not promoted into `food_versions`.
- Users still see “Leafy is identifying it” / “under review” until an admin accepts.

## Deployment

1. Apply migration `202609010001_catalog_contribution_write_lockdown.sql`.
2. Redeploy Edge Functions: `review-catalog-contribution`, `manage-catalog-contribution`, `estimate-meal`.
3. Confirm `CATALOG_REVIEW_KEY` is set in production function secrets (required for admin retry and key auth).
4. Confirm at least one `admin_memberships` row exists (or set `CATALOG_BOOTSTRAP_ADMIN_EMAILS` explicitly if emergency allowlist is required).
5. Redeploy remaining JWT-only functions so `verify_jwt = true` from `config.toml` takes effect.
