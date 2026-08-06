create extension if not exists pg_trgm with schema extensions;

alter table public.food_versions
  add column if not exists verification_status text not null default 'unverified'
    check (verification_status in ('unverified', 'community_confirmed', 'verified', 'rejected')),
  add column if not exists source_updated_at timestamptz,
  add column if not exists image_url text,
  add column if not exists serving_size numeric(12,4),
  add column if not exists serving_unit text;

create unique index if not exists food_versions_active_gtin_market_idx
  on public.food_versions(gtin, coalesce(market_country, ''))
  where gtin is not null and superseded_at is null and verification_status <> 'rejected';
create index if not exists foods_name_trgm_idx
  on public.foods using gin (canonical_name extensions.gin_trgm_ops);
create index if not exists food_versions_description_trgm_idx
  on public.food_versions using gin (description extensions.gin_trgm_ops);
create index if not exists food_versions_brand_trgm_idx
  on public.food_versions using gin (brand_name extensions.gin_trgm_ops);

create table public.food_version_scores (
  food_version_id uuid not null references public.food_versions(id) on delete cascade,
  algorithm_version text not null,
  score_100 integer check (score_100 between 0 and 100),
  label text check (label in ('Excellent', 'Good', 'Fair', 'Poor', 'Limited')),
  raw_points numeric(10,4),
  confidence numeric(5,4) not null check (confidence between 0 and 1),
  positive_factors jsonb not null default '[]'::jsonb check (jsonb_typeof(positive_factors) = 'array'),
  limiting_factors jsonb not null default '[]'::jsonb check (jsonb_typeof(limiting_factors) = 'array'),
  missing_fields jsonb not null default '[]'::jsonb check (jsonb_typeof(missing_fields) = 'array'),
  components jsonb not null default '{}'::jsonb check (jsonb_typeof(components) = 'object'),
  created_at timestamptz not null default now(),
  primary key (food_version_id, algorithm_version)
);

create table public.product_analysis_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  food_version_id uuid not null references public.food_versions(id) on delete cascade,
  discovery_method text not null check (discovery_method in ('barcode', 'search', 'contribution')),
  query_text text,
  score_snapshot jsonb,
  analyzed_at timestamptz not null default now()
);
create index product_analysis_history_user_time_idx
  on public.product_analysis_history(user_id, analyzed_at desc);

create table public.catalog_contributions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  gtin text not null check (gtin ~ '^[0-9]{8,14}$'),
  market_country text not null default 'US',
  status text not null default 'draft'
    check (status in ('draft', 'pending_review', 'accepted', 'needs_review', 'rejected')),
  consent_version integer,
  extracted_fields jsonb not null default '{}'::jsonb check (jsonb_typeof(extracted_fields) = 'object'),
  confirmed_fields jsonb not null default '{}'::jsonb check (jsonb_typeof(confirmed_fields) = 'object'),
  accepted_food_version_id uuid references public.food_versions(id),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.product_label_assets (
  id uuid primary key default gen_random_uuid(),
  contribution_id uuid not null references public.catalog_contributions(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  asset_kind text not null check (asset_kind in ('front', 'nutrition_facts', 'ingredients')),
  object_path text not null unique,
  content_hash text,
  metadata_stripped boolean not null default true,
  created_at timestamptz not null default now(),
  unique (contribution_id, asset_kind)
);

alter table public.food_version_scores enable row level security;
alter table public.product_analysis_history enable row level security;
alter table public.catalog_contributions enable row level security;
alter table public.product_label_assets enable row level security;

create policy "users read catalog scores" on public.food_version_scores
  for select to authenticated using (true);
create policy "users manage own analysis history" on public.product_analysis_history
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "users manage own catalog contributions" on public.catalog_contributions
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "users manage own product label assets" on public.product_label_assets
  for all to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select on public.food_version_scores to authenticated;
grant select, insert, update, delete on public.product_analysis_history to authenticated;
grant select, insert, update, delete on public.catalog_contributions, public.product_label_assets to authenticated;

create or replace function public.search_food_catalog(p_query text, p_limit integer default 20)
returns table (
  food_version_id uuid, description text, brand_name text, gtin text,
  market_country text, image_url text, verification_status text, rank real
)
language sql stable security invoker set search_path = '' as $$
  select fv.id, fv.description, fv.brand_name, fv.gtin, fv.market_country,
    fv.image_url, fv.verification_status,
    greatest(
      extensions.similarity(lower(fv.description), lower(p_query)),
      extensions.similarity(lower(coalesce(fv.brand_name, '')), lower(p_query)),
      extensions.similarity(lower(f.canonical_name), lower(p_query))
    )::real as rank
  from public.food_versions fv
  join public.foods f on f.id = fv.food_id
  where fv.superseded_at is null and fv.verification_status <> 'rejected'
    and (
      lower(fv.description) operator(extensions.%) lower(p_query)
      or lower(coalesce(fv.brand_name, '')) operator(extensions.%) lower(p_query)
      or lower(f.canonical_name) operator(extensions.%) lower(p_query)
      or fv.gtin = regexp_replace(p_query, '[^0-9]', '', 'g')
    )
  order by
    (fv.gtin = regexp_replace(p_query, '[^0-9]', '', 'g')) desc,
    (lower(fv.description) = lower(p_query)) desc,
    (fv.market_country = 'US') desc,
    rank desc, fv.source_updated_at desc nulls last
  limit least(greatest(p_limit, 1), 50);
$$;
grant execute on function public.search_food_catalog(text, integer) to authenticated;
