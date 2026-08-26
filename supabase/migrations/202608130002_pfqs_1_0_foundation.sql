-- PFQS 1.0 is intentionally isolated from legacy Leafy score tables so prior
-- results remain reproducible while the new model is validated and activated.

create table if not exists public.pfqs_releases (
  model_version text primary key,
  ingredient_taxonomy_version text not null,
  additive_database_version text not null,
  status text not null default 'draft' check (status in ('draft', 'active', 'retired')),
  configuration jsonb not null default '{}'::jsonb,
  validation_report jsonb not null default '{}'::jsonb,
  activated_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists pfqs_one_active_release on public.pfqs_releases ((status)) where status = 'active';

insert into public.pfqs_releases (
  model_version, ingredient_taxonomy_version, additive_database_version, status, configuration
) values (
  'PFQS-1.0', 'PFQS-TAXONOMY-1.0', 'PFQS-ADDITIVES-2026-08-13', 'draft',
  jsonb_build_object(
    'normalization_calorie_floor', 50,
    'additive_penalty_cap', 25,
    'tier_4_score_ceiling', 50,
    'supported_jurisdictions', jsonb_build_array('US')
  )
) on conflict (model_version) do update set
  ingredient_taxonomy_version = excluded.ingredient_taxonomy_version,
  additive_database_version = excluded.additive_database_version,
  configuration = excluded.configuration;

create table if not exists public.pfqs_label_nutrients (
  food_version_id uuid not null references public.food_versions(id) on delete cascade,
  nutrient_code text not null,
  amount_per_serving numeric not null check (amount_per_serving >= 0),
  unit text not null,
  explicitly_reported boolean not null default false,
  source_method text not null check (source_method in ('label', 'source_conversion', 'human_review')),
  source_version text,
  confidence numeric not null default 1 check (confidence between 0 and 1),
  created_at timestamptz not null default now(),
  primary key (food_version_id, nutrient_code)
);

create table if not exists public.pfqs_ingredient_snapshots (
  food_version_id uuid not null references public.food_versions(id) on delete cascade,
  taxonomy_version text not null,
  ingredients_raw text not null,
  parsed_ingredients jsonb not null default '[]'::jsonb,
  classified_ingredients jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  primary key (food_version_id, taxonomy_version)
);

create table if not exists public.pfqs_additive_releases (
  version text primary key,
  status text not null default 'draft' check (status in ('draft', 'active', 'retired')),
  evidence_coverage numeric check (evidence_coverage between 0 and 1),
  reviewed_by text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.pfqs_additives (
  additive_database_version text not null references public.pfqs_additive_releases(version) on delete restrict,
  canonical_id text not null,
  canonical_name text not null,
  family_id text,
  e_number text,
  cas_number text,
  evidence_confidence text not null,
  evidence_summary text not null,
  last_reviewed date not null,
  reviewer text,
  sources jsonb not null default '[]'::jsonb,
  primary key (additive_database_version, canonical_id)
);

create table if not exists public.pfqs_additive_aliases (
  additive_database_version text not null,
  canonical_id text not null,
  alias text not null,
  normalized_alias text not null,
  primary key (additive_database_version, normalized_alias),
  foreign key (additive_database_version, canonical_id)
    references public.pfqs_additives(additive_database_version, canonical_id) on delete cascade
);

create table if not exists public.pfqs_additive_rules (
  id uuid primary key default gen_random_uuid(),
  additive_database_version text not null,
  canonical_id text not null,
  jurisdiction text not null,
  start_date date not null,
  end_date date,
  tier smallint not null check (tier between 0 and 4),
  penalty smallint not null check (penalty in (0, 1, 3, 7, 15)),
  regulatory_status text,
  reason text not null,
  check (end_date is null or end_date >= start_date),
  foreign key (additive_database_version, canonical_id)
    references public.pfqs_additives(additive_database_version, canonical_id) on delete cascade,
  unique (additive_database_version, canonical_id, jurisdiction, start_date)
);

create table if not exists public.pfqs_family_caps (
  additive_database_version text not null references public.pfqs_additive_releases(version) on delete cascade,
  family_id text not null,
  penalty_cap smallint not null check (penalty_cap between 0 and 25),
  rationale text not null,
  primary key (additive_database_version, family_id)
);

create table if not exists public.pfqs_scores (
  id uuid primary key default gen_random_uuid(),
  food_version_id uuid not null references public.food_versions(id) on delete cascade,
  model_version text not null,
  ingredient_taxonomy_version text not null,
  additive_database_version text not null,
  jurisdiction text not null,
  assessment_date date not null,
  score_status text not null check (score_status in ('complete', 'incomplete', 'ineligible')),
  score_100 smallint check (score_100 between 0 and 100),
  rating text check (rating in ('Exceptional', 'Excellent', 'Good', 'Above Average', 'Mixed', 'Below Average', 'Poor', 'Very Poor')),
  base_score smallint check (base_score between 0 and 100),
  additive_penalty smallint not null default 0 check (additive_penalty between 0 and 25),
  components jsonb not null default '{}'::jsonb,
  additive_results jsonb not null default '[]'::jsonb,
  flags jsonb not null default '{}'::jsonb,
  strengths text[] not null default '{}',
  weaknesses text[] not null default '{}',
  explanation text[] not null default '{}',
  missing_fields text[] not null default '{}',
  unavailable_reasons text[] not null default '{}',
  input_snapshot jsonb not null,
  created_at timestamptz not null default now(),
  unique (food_version_id, model_version, ingredient_taxonomy_version, additive_database_version, jurisdiction, assessment_date),
  check (
    (score_status = 'complete' and score_100 is not null and rating is not null and base_score is not null)
    or (score_status <> 'complete' and score_100 is null and rating is null)
  )
);
create index if not exists pfqs_scores_product_created on public.pfqs_scores (food_version_id, created_at desc);

-- Prevent overlapping effective windows for the same additive and jurisdiction.
create extension if not exists btree_gist;
alter table public.pfqs_additive_rules
  drop constraint if exists pfqs_additive_rules_no_overlap;
alter table public.pfqs_additive_rules
  add constraint pfqs_additive_rules_no_overlap exclude using gist (
    additive_database_version with =,
    canonical_id with =,
    jurisdiction with =,
    daterange(start_date, coalesce(end_date + 1, 'infinity'::date), '[)') with &&
  );

alter table public.pfqs_releases enable row level security;
alter table public.pfqs_label_nutrients enable row level security;
alter table public.pfqs_ingredient_snapshots enable row level security;
alter table public.pfqs_additive_releases enable row level security;
alter table public.pfqs_additives enable row level security;
alter table public.pfqs_additive_aliases enable row level security;
alter table public.pfqs_additive_rules enable row level security;
alter table public.pfqs_family_caps enable row level security;
alter table public.pfqs_scores enable row level security;

create policy "Authenticated users read active PFQS release"
  on public.pfqs_releases for select to authenticated using (status = 'active');
create policy "Authenticated users read active PFQS scores"
  on public.pfqs_scores for select to authenticated using (
    exists (select 1 from public.pfqs_releases r where r.model_version = pfqs_scores.model_version and r.status = 'active')
  );

-- Legacy score releases are retired at PFQS activation, not at migration time.
-- This draft migration makes no destructive changes to historical score rows.
