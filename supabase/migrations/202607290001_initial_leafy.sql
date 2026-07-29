create type public.calculation_sex as enum ('female', 'male');
create type public.weight_goal as enum ('lose', 'maintain', 'gain');
create type public.goal_pace as enum ('gentle', 'steady', 'faster');
create type public.activity_level as enum ('sedentary', 'light', 'moderate', 'very_active', 'athlete');
create type public.unit_system as enum ('imperial', 'metric');

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  birth_date date not null,
  calculation_sex public.calculation_sex not null,
  height_cm numeric(6,2) not null check (height_cm between 120 and 230),
  current_weight_kg numeric(6,2) not null check (current_weight_kg between 35 and 350),
  target_weight_kg numeric(6,2) check (target_weight_kg between 35 and 350),
  activity_level public.activity_level not null,
  goal public.weight_goal not null,
  pace public.goal_pace not null,
  unit_system public.unit_system not null,
  terms_accepted_at timestamptz not null default now(),
  privacy_accepted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((goal = 'maintain' and target_weight_kg is null) or (goal <> 'maintain' and target_weight_kg is not null))
);

create table public.nutrition_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  revision integer not null check (revision > 0),
  calculator_version text not null,
  input_snapshot jsonb not null,
  bmr_kcal integer not null check (bmr_kcal > 0),
  tdee_kcal integer not null check (tdee_kcal > 0),
  calorie_target_kcal integer not null check (calorie_target_kcal > 0),
  protein_g integer not null check (protein_g > 0),
  carbohydrate_g integer not null check (carbohydrate_g > 0),
  fat_g integer not null check (fat_g > 0),
  projected_weekly_change_kg numeric(7,4) not null check (projected_weekly_change_kg >= 0),
  estimated_goal_date date,
  created_at timestamptz not null default now(),
  unique(user_id, revision)
);

create index nutrition_plans_user_revision_idx on public.nutrition_plans(user_id, revision desc);

alter table public.profiles enable row level security;
alter table public.nutrition_plans enable row level security;

create policy "users read own profile" on public.profiles for select to authenticated using ((select auth.uid()) = user_id);
create policy "users read own plans" on public.nutrition_plans for select to authenticated using ((select auth.uid()) = user_id);

revoke insert, update, delete on public.profiles from anon, authenticated;
revoke insert, update, delete on public.nutrition_plans from anon, authenticated;
grant select on public.profiles, public.nutrition_plans to authenticated;

create or replace function public.persist_nutrition_plan(
  p_user_id uuid,
  p_input jsonb,
  p_result jsonb
) returns public.nutrition_plans
language plpgsql security definer set search_path = '' as $$
declare
  new_plan public.nutrition_plans;
  next_revision integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  insert into public.profiles (
    user_id, birth_date, calculation_sex, height_cm, current_weight_kg, target_weight_kg,
    activity_level, goal, pace, unit_system
  ) values (
    p_user_id, (p_input->>'birth_date')::date, (p_input->>'calculation_sex')::public.calculation_sex,
    (p_input->>'height_cm')::numeric, (p_input->>'current_weight_kg')::numeric,
    nullif(p_input->>'target_weight_kg', '')::numeric, (p_input->>'activity_level')::public.activity_level,
    (p_input->>'goal')::public.weight_goal, (p_input->>'pace')::public.goal_pace,
    (p_input->>'unit_system')::public.unit_system
  ) on conflict (user_id) do update set
    birth_date = excluded.birth_date, calculation_sex = excluded.calculation_sex,
    height_cm = excluded.height_cm, current_weight_kg = excluded.current_weight_kg,
    target_weight_kg = excluded.target_weight_kg, activity_level = excluded.activity_level,
    goal = excluded.goal, pace = excluded.pace, unit_system = excluded.unit_system, updated_at = now();

  select coalesce(max(revision), 0) + 1 into next_revision from public.nutrition_plans where user_id = p_user_id;
  insert into public.nutrition_plans (
    user_id, revision, calculator_version, input_snapshot, bmr_kcal, tdee_kcal,
    calorie_target_kcal, protein_g, carbohydrate_g, fat_g,
    projected_weekly_change_kg, estimated_goal_date
  ) values (
    p_user_id, next_revision, p_result->>'calculator_version', p_input,
    (p_result->>'bmr_kcal')::integer, (p_result->>'tdee_kcal')::integer,
    (p_result->>'calorie_target_kcal')::integer, (p_result->>'protein_g')::integer,
    (p_result->>'carbohydrate_g')::integer, (p_result->>'fat_g')::integer,
    (p_result->>'projected_weekly_change_kg')::numeric,
    nullif(p_result->>'estimated_goal_date', '')::date
  ) returning * into new_plan;
  return new_plan;
end;
$$;

revoke all on function public.persist_nutrition_plan(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.persist_nutrition_plan(uuid, jsonb, jsonb) to service_role;
