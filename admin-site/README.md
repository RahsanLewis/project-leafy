# Leafy Catalog Admin

Private production operations dashboard for reviewing community product-label submissions and searching Leafy's food and PFQS additive catalogs.

## Runtime configuration

Configure these variables through the hosting platform, not in source control:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `ADMIN_API_URL`

The dashboard uses Google OAuth through Supabase. Access also requires an active `catalog_admin` membership, enforced by the `review-catalog-contribution` Edge Function.

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
