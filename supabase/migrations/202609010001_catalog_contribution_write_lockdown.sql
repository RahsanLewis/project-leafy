-- F-03: authenticated clients may read their own contribution rows, but all
-- inserts, updates, and deletes go through service-role Edge Functions.
-- Matches the AI meal / chat write pattern (SELECT-only RLS + revoke writes).

drop policy if exists "users manage own catalog contributions" on public.catalog_contributions;
drop policy if exists "users manage own product label assets" on public.product_label_assets;

create policy "users read own catalog contributions"
  on public.catalog_contributions
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "users read own product label assets"
  on public.product_label_assets
  for select to authenticated
  using ((select auth.uid()) = user_id);

grant select on public.catalog_contributions, public.product_label_assets to authenticated;
revoke insert, update, delete on public.catalog_contributions, public.product_label_assets
  from anon, authenticated;

comment on table public.catalog_contributions is
  'User-owned catalog submission drafts. Authenticated clients have SELECT of own rows; writes are service-role/Edge only.';
comment on table public.product_label_assets is
  'Private package-label evidence. Authenticated clients have SELECT of own rows; writes are service-role/Edge only.';
