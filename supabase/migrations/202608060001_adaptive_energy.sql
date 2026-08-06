create type public.intake_day_status as enum ('pending', 'confirmed', 'incomplete', 'fasted');
create type public.plan_source as enum ('formula', 'adaptive');

alter table public.food_entries
  add column entry_source text not null default 'manual'
    check (entry_source in ('manual', 'barcode', 'recipe', 'photo_ai', 'text_ai', 'import')),
  add column calorie_method text not null default 'user_entered'
    check (calorie_method in ('user_entered', 'nutrition_database', 'estimated', 'imported'));

alter table public.nutrition_plans
  add column source public.plan_source not null default 'formula';

create table public.daily_intake_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  local_date date not null,
  status public.intake_day_status not null default 'pending',
  confirmed_calories integer check (confirmed_calories between 0 and 50000),
  confirmed_item_count integer check (confirmed_item_count >= 0),
  time_zone text not null check (char_length(time_zone) between 1 and 80),
  revision integer not null default 1 check (revision > 0),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, local_date),
  check (
    (status in ('confirmed', 'fasted') and confirmed_calories is not null and confirmed_item_count is not null and confirmed_at is not null)
    or (status in ('pending', 'incomplete') and confirmed_calories is null and confirmed_item_count is null and confirmed_at is null)
  ),
  check (status <> 'fasted' or (confirmed_calories = 0 and confirmed_item_count = 0))
);

create table public.adaptive_energy_estimates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  window_start date not null,
  window_end date not null,
  model_version text not null,
  input_revision_hash text not null,
  confirmed_day_count integer not null,
  weight_count integer not null,
  mean_confirmed_intake_kcal numeric(9,2),
  weight_slope_kg_per_day numeric(10,6),
  estimated_expenditure_kcal numeric(9,2),
  candidate_target_kcal integer,
  outcome text not null check (outcome in ('learning', 'rejected', 'unchanged', 'eligible', 'applied', 'shadow')),
  reason text not null,
  created_at timestamptz not null default now(),
  unique (user_id, window_end, model_version, input_revision_hash)
);

alter table public.nutrition_plans
  add column energy_estimate_id uuid references public.adaptive_energy_estimates(id) on delete set null;

create table public.plan_adjustments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.nutrition_plans(id) on delete cascade,
  energy_estimate_id uuid not null references public.adaptive_energy_estimates(id) on delete cascade,
  previous_calorie_target_kcal integer not null,
  new_calorie_target_kcal integer not null,
  explanation text not null,
  applied_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  unique (plan_id)
);

create index daily_intake_days_user_date_idx on public.daily_intake_days(user_id, local_date desc);
create index adaptive_energy_estimates_user_date_idx on public.adaptive_energy_estimates(user_id, window_end desc);
create index plan_adjustments_user_unread_idx on public.plan_adjustments(user_id, acknowledged_at, applied_at desc);

alter table public.daily_intake_days enable row level security;
alter table public.adaptive_energy_estimates enable row level security;
alter table public.plan_adjustments enable row level security;

create policy "users read own intake days" on public.daily_intake_days
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "users read own plan adjustments" on public.plan_adjustments
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "users acknowledge own plan adjustments" on public.plan_adjustments
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke insert, update, delete on public.daily_intake_days from anon, authenticated;
revoke all on public.adaptive_energy_estimates from anon, authenticated;
revoke insert, delete on public.plan_adjustments from anon, authenticated;
grant select on public.daily_intake_days, public.plan_adjustments to authenticated;
grant update (acknowledged_at) on public.plan_adjustments to authenticated;

create or replace function public.invalidate_intake_day()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  affected_user uuid;
  affected_date date;
  affected_zone text;
begin
  affected_user := coalesce(new.user_id, old.user_id);

  if tg_op in ('UPDATE', 'DELETE') then
    insert into public.daily_intake_days (user_id, local_date, status, time_zone)
    values (old.user_id, old.local_date, 'pending', old.time_zone)
    on conflict (user_id, local_date) do update set
      status = 'pending', confirmed_calories = null, confirmed_item_count = null,
      confirmed_at = null, revision = public.daily_intake_days.revision + 1, updated_at = now();
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    insert into public.daily_intake_days (user_id, local_date, status, time_zone)
    values (new.user_id, new.local_date, 'pending', new.time_zone)
    on conflict (user_id, local_date) do update set
      status = 'pending', confirmed_calories = null, confirmed_item_count = null,
      confirmed_at = null, time_zone = excluded.time_zone,
      revision = public.daily_intake_days.revision + 1, updated_at = now();
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger invalidate_intake_day_after_food_change
after insert or update or delete on public.food_entries
for each row execute function public.invalidate_intake_day();

insert into public.daily_intake_days (user_id, local_date, status, time_zone)
select user_id, local_date, 'pending', max(time_zone)
from public.food_entries
group by user_id, local_date
on conflict (user_id, local_date) do nothing;

create or replace function public.persist_adaptive_plan(
  p_user_id uuid,
  p_input jsonb,
  p_result jsonb,
  p_estimate_id uuid,
  p_previous_target integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  new_plan public.nutrition_plans;
  new_adjustment public.plan_adjustments;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  new_plan := public.persist_nutrition_plan(p_user_id, p_input, p_result);
  update public.nutrition_plans set source = 'adaptive', energy_estimate_id = p_estimate_id
    where id = new_plan.id returning * into new_plan;
  update public.adaptive_energy_estimates set outcome = 'applied'
    where id = p_estimate_id and user_id = p_user_id;
  insert into public.plan_adjustments (
    user_id, plan_id, energy_estimate_id, previous_calorie_target_kcal,
    new_calorie_target_kcal, explanation
  ) values (
    p_user_id, new_plan.id, p_estimate_id, p_previous_target,
    new_plan.calorie_target_kcal,
    'Your daily budget was updated using your last four weeks of food and weight trends.'
  ) returning * into new_adjustment;
  return jsonb_build_object('plan', to_jsonb(new_plan), 'adjustment', to_jsonb(new_adjustment));
end;
$$;

revoke all on function public.persist_adaptive_plan(uuid, jsonb, jsonb, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.persist_adaptive_plan(uuid, jsonb, jsonb, uuid, integer)
  to service_role;
