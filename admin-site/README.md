# Leafy Catalog Admin

Private production operations dashboard for reviewing community product-label submissions and searching Leafy's food and PFQS additive catalogs.

## Runtime configuration

Configure these variables through the hosting platform, not in source control:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `ADMIN_API_URL`

The dashboard uses Google OAuth through Supabase. Access requires an active `catalog_admin` row in `admin_memberships` (grant with `scripts/manage-admin-membership.ts`) or an explicitly configured `CATALOG_BOOTSTRAP_ADMIN_EMAILS` allowlist. The review function never upserts membership from a hardcoded email.

## Local development

```bash
npm install
npm run dev
```

Node.js 22.13 or newer is required.

## Verification

```bash
npm run lint
npm test
```
