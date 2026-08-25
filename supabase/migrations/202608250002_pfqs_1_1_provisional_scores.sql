-- PFQS 1.1 gives ordinary foods a best-available provisional score while
-- preserving strict complete scores and the reproducibility of PFQS 1.0.

alter table public.food_version_nutrients
  add column if not exists source_version text,
  add column if not exists confidence numeric check (confidence between 0 and 1);

alter table public.pfqs_scores
  drop constraint if exists pfqs_scores_score_status_check,
  drop constraint if exists pfqs_scores_check;

alter table public.pfqs_scores
  add constraint pfqs_scores_score_status_check
    check (score_status in ('complete', 'provisional', 'pending', 'incomplete', 'ineligible')),
  add constraint pfqs_scores_result_shape_check check (
    (score_status in ('complete', 'provisional') and score_100 is not null and rating is not null and base_score is not null)
    or (score_status in ('pending', 'incomplete', 'ineligible') and score_100 is null and rating is null)
  ),
  add column if not exists evidence_coverage numeric not null default 0 check (evidence_coverage between 0 and 1),
  add column if not exists evidence_confidence numeric not null default 0 check (evidence_confidence between 0 and 1),
  add column if not exists confidence_level text not null default 'none'
    check (confidence_level in ('high', 'moderate', 'low', 'none')),
  add column if not exists included_components text[] not null default '{}';

update public.pfqs_releases
set status = 'retired', retired_at = coalesce(retired_at, now())
where status = 'active';

insert into public.pfqs_releases (
  model_version, ingredient_taxonomy_version, additive_database_version,
  status, configuration, validation_report, activated_at
) values (
  'PFQS-1.1', 'PFQS-TAXONOMY-1.0', 'PFQS-ADDITIVES-2026-08-13', 'active',
  jsonb_build_object(
    'normalization_calorie_floor', 50,
    'best_available_reweighting', true,
    'ordinary_food_types', jsonb_build_array('food', 'restaurant', 'manual', 'ai_estimate'),
    'excluded_product_types', jsonb_build_array('supplement', 'infant_formula', 'medical_food', 'alcohol')
  ),
  jsonb_build_object('release_decision', 'approved_for_provisional_consumer_release'),
  now()
) on conflict (model_version) do update set
  status = 'active', configuration = excluded.configuration,
  validation_report = excluded.validation_report, activated_at = coalesce(public.pfqs_releases.activated_at, now()),
  retired_at = null;

create table public.pfqs_food_entry_scores (
  food_entry_id uuid primary key references public.food_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  model_version text not null,
  score_status text not null check (score_status in ('complete', 'provisional', 'pending', 'ineligible')),
  score_100 smallint check (score_100 between 0 and 100),
  evidence_coverage numeric not null check (evidence_coverage between 0 and 1),
  evidence_confidence numeric not null check (evidence_confidence between 0 and 1),
  result jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.pfqs_food_entry_scores enable row level security;
create policy "Users read own PFQS entry scores"
  on public.pfqs_food_entry_scores for select to authenticated
  using ((select auth.uid()) = user_id);
grant select on public.pfqs_food_entry_scores to authenticated;

create view public.food_entries_with_score
with (security_invoker = true)
as
select fe.*, pes.result as score
from public.food_entries fe
left join public.pfqs_food_entry_scores pes on pes.food_entry_id = fe.id;
grant select on public.food_entries_with_score to authenticated;
