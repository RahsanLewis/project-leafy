-- User mutations are mediated by Edge Functions so validation and ownership
-- checks cannot be bypassed through PostgREST.
drop policy if exists "users insert own food entries" on public.food_entries;
drop policy if exists "users update own food entries" on public.food_entries;
drop policy if exists "users delete own food entries" on public.food_entries;
revoke insert, update, delete on public.food_entries from authenticated;

drop policy if exists "users acknowledge own plan adjustments" on public.plan_adjustments;
revoke update (acknowledged_at) on public.plan_adjustments from authenticated;

-- The client consumes one food aggregate. consumption_items remains an
-- internal projection maintained by the food_entries trigger.
create or replace view public.food_entries_with_score
with (security_invoker = true)
as
select
  fe.*,
  pes.result as score,
  coalesce(n.nutrients, '[]'::jsonb) as nutrients
from public.food_entries fe
left join public.pfqs_food_entry_scores pes on pes.food_entry_id = fe.id
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'code', cin.nutrient_code,
      'amount', cin.amount,
      'derivation_method', cin.derivation_method,
      'source_version', cin.source_version,
      'confidence', cin.confidence
    ) order by cin.nutrient_code
  ) filter (where cin.nutrient_code <> 'energy_kcal') as nutrients
  from public.consumption_items ci
  join public.consumption_item_nutrients cin on cin.consumption_item_id = ci.id
  where ci.legacy_food_entry_id = fe.id and ci.deleted_at is null
) n on true;

grant select on public.food_entries_with_score to authenticated;
