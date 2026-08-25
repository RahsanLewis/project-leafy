-- Ship PFQS 1.0 and allow verified package evidence to supersede an older
-- catalog version without exposing a partially published replacement.

update public.pfqs_releases
set status = 'active',
    activated_at = coalesce(activated_at, now()),
    validation_report = validation_report || jsonb_build_object(
      'release_decision', 'approved_for_consumer_release',
      'released_at', now()
    )
where model_version = 'PFQS-1.0';

update public.nutrition_score_releases
set status = 'retired'
where status = 'active' and algorithm_version = 'leafy-nutrition-v1-ns2023';

alter table public.catalog_contributions
  add column if not exists target_food_version_id uuid
    references public.food_versions(id) on delete set null;

create or replace function public.activate_food_version_replacement(
  p_previous_id uuid,
  p_replacement_id uuid,
  p_verification_status text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  previous_row public.food_versions;
  replacement_row public.food_versions;
  activation_time timestamptz := clock_timestamp();
begin
  if p_verification_status not in ('verified', 'community_confirmed') then
    raise exception 'Replacement verification status is invalid';
  end if;

  select * into previous_row from public.food_versions
    where id = p_previous_id and superseded_at is null for update;
  select * into replacement_row from public.food_versions
    where id = p_replacement_id and verification_status = 'rejected' for update;

  if previous_row.id is null or replacement_row.id is null
     or previous_row.food_id <> replacement_row.food_id
     or previous_row.gtin is distinct from replacement_row.gtin
     or coalesce(previous_row.market_country, '') <> coalesce(replacement_row.market_country, '') then
    raise exception 'Catalog replacement does not match the active product';
  end if;

  update public.food_versions set superseded_at = activation_time where id = p_previous_id;
  update public.food_versions
    set verification_status = p_verification_status,
        effective_from = activation_time
    where id = p_replacement_id;
end;
$$;

revoke all on function public.activate_food_version_replacement(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.activate_food_version_replacement(uuid, uuid, text)
  to service_role;

-- Earlier USDA imports treated volume servings as grams. Remove only those
-- synthetic portions so consumers fall back to an explicitly gram-based view.
delete from public.food_portions fp
using public.food_versions fv
where fp.food_version_id = fv.id
  and fp.source = 'usda_fdc'
  and coalesce(lower(fv.serving_unit), '') not in ('g', 'gram', 'grams', 'grm');

-- Reconstruct safe USDA per-serving values for already imported gram-based
-- products. Printed/source %DV is recovered from the retained raw response.
insert into public.food_version_serving_nutrients (
  food_version_id, nutrient_code, amount_per_serving, unit,
  percent_daily_value, declaration_type, evidence_section
)
select
  fv.id,
  fvn.nutrient_code,
  round(fvn.amount_per_100g * fv.serving_size / 100, 6),
  nd.unit,
  nullif(raw_nutrient.value->>'percentDailyValue', '')::numeric,
  'derived',
  'usda_fdc'
from public.food_versions fv
join public.food_version_nutrients fvn on fvn.food_version_id = fv.id
join public.nutrient_definitions nd on nd.code = fvn.nutrient_code
left join lateral (
  select value
  from jsonb_array_elements(coalesce(fv.raw_source->'foodNutrients', '[]'::jsonb)) value
  where coalesce(
    nullif(value->'nutrient'->>'id', '')::integer,
    nullif(value->>'nutrientId', '')::integer
  ) = nd.fdc_nutrient_id
  limit 1
) raw_nutrient on true
where fv.source_system = 'usda_fdc'
  and fv.serving_size > 0
  and lower(fv.serving_unit) in ('g', 'gram', 'grams', 'grm')
on conflict (food_version_id, nutrient_code) do nothing;
