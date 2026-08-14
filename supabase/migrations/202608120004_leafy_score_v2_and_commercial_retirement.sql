-- Leafy Score v2 is installed as a gated draft. Activating it requires completing
-- the benchmark and expert-review fields, then changing exactly one release row.
create table if not exists public.nutrition_score_releases (
  algorithm_version text primary key,
  registry_version text not null,
  status text not null check (status in ('draft', 'active', 'retired')),
  methodology_url text,
  benchmark_completed_at timestamptz,
  expert_reviewed_at timestamptz,
  expert_reviewer text,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  check (algorithm_version <> 'leafy-score-v2-us-fda-dv' or status <> 'active' or (benchmark_completed_at is not null and expert_reviewed_at is not null and expert_reviewer is not null))
);
create unique index if not exists nutrition_score_one_active_idx
  on public.nutrition_score_releases ((status)) where status = 'active';

insert into public.nutrition_score_releases (algorithm_version, registry_version, status)
values ('leafy-score-v2-us-fda-dv', 'leafy-additives-us-v1', 'draft')
on conflict (algorithm_version) do nothing;

insert into public.nutrition_score_releases (algorithm_version, registry_version, status, activated_at)
values ('leafy-nutrition-v1-ns2023', 'none', 'active', now())
on conflict (algorithm_version) do nothing;

create table if not exists public.food_additive_registry (
  registry_version text not null,
  additive_id text not null,
  display_name text not null,
  concern_level text not null check (concern_level in ('none', 'limited', 'higher')),
  aliases jsonb not null check (jsonb_typeof(aliases) = 'array'),
  rationale text not null,
  source_title text not null,
  source_url text not null,
  reviewed_at date not null,
  active boolean not null default true,
  primary key (registry_version, additive_id)
);

insert into public.food_additive_registry
  (registry_version, additive_id, display_name, concern_level, aliases, rationale, source_title, source_url, reviewed_at)
values
  ('leafy-additives-us-v1','citric-acid','Citric acid','none','["citric acid"]','No identified concern in the current registry.','FDA Substances Added to Food inventory','https://hfpappexternal.fda.gov/scripts/fdcc/?set=FoodSubstances','2026-08-12'),
  ('leafy-additives-us-v1','ascorbic-acid','Ascorbic acid','none','["ascorbic acid","vitamin c"]','No identified concern in the current registry.','FDA Substances Added to Food inventory','https://hfpappexternal.fda.gov/scripts/fdcc/?set=FoodSubstances','2026-08-12'),
  ('leafy-additives-us-v1','bht','BHT','limited','["bht","butylated hydroxytoluene"]','FDA announced a post-market assessment; this is not a conclusive safety verdict.','FDA post-market assessments of chemicals in food','https://www.fda.gov/food/food-chemical-safety/post-market-assessments-chemicals-food','2026-08-12'),
  ('leafy-additives-us-v1','azodicarbonamide','Azodicarbonamide','limited','["azodicarbonamide","ada"]','FDA announced a post-market assessment; this is not a conclusive safety verdict.','FDA post-market assessments of chemicals in food','https://www.fda.gov/food/food-chemical-safety/post-market-assessments-chemicals-food','2026-08-12'),
  ('leafy-additives-us-v1','brominated-vegetable-oil','Brominated vegetable oil','higher','["brominated vegetable oil","bvo"]','FDA revoked the regulation authorizing BVO in food.','FDA revokes authorization for brominated vegetable oil','https://www.fda.gov/food/hfp-constituent-updates/fda-revokes-regulation-allowing-use-brominated-vegetable-oil-bvo-food','2026-08-12'),
  ('leafy-additives-us-v1','fdc-red-3','FD&C Red No. 3','higher','["fd&c red no. 3","fdc red no 3","red 3","red dye 3","erythrosine"]','FDA revoked authorizations for Red No. 3 in food and ingested drugs.','FDA revokes authorization for Red No. 3','https://www.fda.gov/food/hfp-constituent-updates/fda-revokes-authorization-use-red-no-3-food-and-ingested-drugs','2026-08-12')
on conflict (registry_version, additive_id) do update set
  display_name = excluded.display_name, concern_level = excluded.concern_level,
  aliases = excluded.aliases, rationale = excluded.rationale, source_title = excluded.source_title,
  source_url = excluded.source_url, reviewed_at = excluded.reviewed_at;

alter table public.food_version_scores drop constraint if exists food_version_scores_label_check;
alter table public.food_version_scores add constraint food_version_scores_label_check
  check (label in ('Excellent', 'Good', 'Fair', 'Poor', 'Very poor', 'Limited'));
alter table public.food_version_scores
  add column if not exists registry_version text,
  add column if not exists nutrition_base_score integer check (nutrition_base_score between 0 and 100),
  add column if not exists additive_deduction integer not null default 0 check (additive_deduction between 0 and 40),
  add column if not exists serving_grams numeric(12,4),
  add column if not exists serving_basis text,
  add column if not exists unavailable_reasons jsonb not null default '[]'::jsonb check (jsonb_typeof(unavailable_reasons) = 'array');

alter table public.nutrition_score_releases enable row level security;
alter table public.food_additive_registry enable row level security;
create policy "users read score releases" on public.nutrition_score_releases for select to authenticated using (true);
create policy "users read additive registry" on public.food_additive_registry for select to authenticated using (true);
grant select on public.nutrition_score_releases, public.food_additive_registry to authenticated;

-- Permanently retire the optional commercial nutrition-data program.
update public.consent_grants set revoked_at = coalesce(revoked_at, now())
where purpose = 'commercial_dataset' and revoked_at is null;
update public.consumption_items set commercial_eligible = false, consent_grant_id = null
where commercial_eligible or consent_grant_id is not null;
update public.media_assets set commercial_eligible = false, consent_grant_id = null
where commercial_eligible or consent_grant_id is not null;
update public.consent_documents set retired_at = coalesce(retired_at, now())
where document_key = 'commercial_nutrition_dataset' and retired_at is null;
drop function if exists public.commercial_project_dataset(uuid);
create function public.commercial_project_dataset(p_project_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  raise exception using errcode = '0A000', message = 'Commercial nutrition datasets are retired';
end;
$$;
revoke all on function public.commercial_project_dataset(uuid) from public, anon, authenticated, service_role;

comment on table public.nutrition_score_releases is 'Server-controlled Leafy Score releases. Draft v2 must pass benchmark and expert review before activation.';
comment on table public.food_additive_registry is 'Versioned, deterministic, source-cited US additive registry. It is not a substitute for regulatory or medical advice.';
