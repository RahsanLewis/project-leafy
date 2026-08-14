-- Community product contributions for barcodes that are not yet in Leafy's catalog.

alter table public.food_entries drop constraint if exists food_entries_calorie_method_check;
alter table public.food_entries
  add constraint food_entries_calorie_method_check
  check (calorie_method in ('user_entered', 'nutrition_database', 'nutrition_label', 'estimated', 'imported'));

alter table public.catalog_contributions
  add column if not exists revision integer not null default 1 check (revision > 0),
  add column if not exists validation_results jsonb not null default '{}'::jsonb
    check (jsonb_typeof(validation_results) = 'object'),
  add column if not exists review_reason text,
  add column if not exists last_submitted_at timestamptz;

alter table public.product_label_assets drop constraint if exists product_label_assets_asset_kind_check;
alter table public.product_label_assets
  add constraint product_label_assets_asset_kind_check
  check (asset_kind in ('front', 'back_label', 'nutrition_facts', 'ingredients'));
alter table public.product_label_assets
  add column if not exists mime_type text not null default 'image/jpeg',
  add column if not exists byte_count integer check (byte_count is null or byte_count > 0);

create table public.catalog_contribution_revisions (
  contribution_id uuid not null references public.catalog_contributions(id) on delete cascade,
  revision integer not null check (revision > 0),
  extracted_fields jsonb not null default '{}'::jsonb check (jsonb_typeof(extracted_fields) = 'object'),
  confirmed_fields jsonb not null default '{}'::jsonb check (jsonb_typeof(confirmed_fields) = 'object'),
  validation_results jsonb not null default '{}'::jsonb check (jsonb_typeof(validation_results) = 'object'),
  created_at timestamptz not null default now(),
  primary key (contribution_id, revision)
);

create table public.catalog_contribution_nutrients (
  contribution_id uuid not null references public.catalog_contributions(id) on delete cascade,
  revision integer not null,
  nutrient_code text not null references public.nutrient_definitions(code),
  amount_per_serving numeric(14,6) not null check (amount_per_serving >= 0),
  unit text not null,
  percent_daily_value numeric(8,3) check (percent_daily_value is null or percent_daily_value >= 0),
  confidence numeric(5,4) not null default 1 check (confidence between 0 and 1),
  printed_on_label boolean not null default true,
  primary key (contribution_id, revision, nutrient_code),
  foreign key (contribution_id, revision)
    references public.catalog_contribution_revisions(contribution_id, revision) on delete cascade
);

create table public.catalog_contribution_events (
  id uuid primary key default gen_random_uuid(),
  contribution_id uuid not null references public.catalog_contributions(id) on delete cascade,
  actor_type text not null check (actor_type in ('user', 'automatic', 'admin')),
  from_status text,
  to_status text not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now()
);

create index catalog_contributions_user_updated_idx
  on public.catalog_contributions(user_id, updated_at desc);
create index catalog_contributions_review_queue_idx
  on public.catalog_contributions(status, last_submitted_at)
  where status = 'pending_review';

alter table public.catalog_contribution_revisions enable row level security;
alter table public.catalog_contribution_nutrients enable row level security;
alter table public.catalog_contribution_events enable row level security;

create policy "users read own catalog contribution revisions" on public.catalog_contribution_revisions
  for select to authenticated using (exists (
    select 1 from public.catalog_contributions cc
    where cc.id = contribution_id and cc.user_id = (select auth.uid())
  ));
create policy "users read own catalog contribution nutrients" on public.catalog_contribution_nutrients
  for select to authenticated using (exists (
    select 1 from public.catalog_contributions cc
    where cc.id = contribution_id and cc.user_id = (select auth.uid())
  ));
create policy "users read own catalog contribution events" on public.catalog_contribution_events
  for select to authenticated using (exists (
    select 1 from public.catalog_contributions cc
    where cc.id = contribution_id and cc.user_id = (select auth.uid())
  ));

grant select on public.catalog_contribution_revisions,
  public.catalog_contribution_nutrients, public.catalog_contribution_events to authenticated;
revoke insert, update, delete on public.catalog_contribution_revisions,
  public.catalog_contribution_nutrients, public.catalog_contribution_events from anon, authenticated;

insert into public.consent_documents (
  document_key, version, jurisdiction, title, body, content_hash, effective_at
) values (
  'catalog_product_contribution', 1, 'global', 'Leafy catalog contribution terms',
  'By submitting, you confirm that the package information is accurate to the best of your knowledge and that Leafy may use the structured label data to improve its shared food catalog. Submitted label photos remain private verification evidence and are not displayed as catalog imagery.',
  'catalog-product-contribution-v1', '2026-08-08T00:00:00Z'
) on conflict (document_key, version, jurisdiction) do nothing;
