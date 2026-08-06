create table public.weight_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  weight_kg numeric(6,2) not null check (weight_kg between 35 and 350),
  recorded_on date not null,
  time_zone text not null check (char_length(time_zone) between 1 and 80),
  source text not null default 'manual' check (source in ('baseline', 'manual')),
  plan_id uuid references public.nutrition_plans(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, recorded_on)
);

create index weight_entries_user_date_idx
  on public.weight_entries(user_id, recorded_on desc);

insert into public.weight_entries (user_id, weight_kg, recorded_on, time_zone, source)
select user_id, current_weight_kg, created_at::date, 'UTC', 'baseline'
from public.profiles
on conflict (user_id, recorded_on) do nothing;

create or replace function public.seed_starting_weight()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.weight_entries (user_id, weight_kg, recorded_on, time_zone, source)
  values (new.user_id, new.current_weight_kg, new.created_at::date, 'UTC', 'baseline')
  on conflict (user_id, recorded_on) do nothing;
  return new;
end;
$$;

create trigger seed_starting_weight_after_profile_insert
after insert on public.profiles
for each row execute function public.seed_starting_weight();

alter table public.weight_entries enable row level security;

create policy "users read own weight entries"
  on public.weight_entries for select to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update, delete on public.weight_entries from anon, authenticated;
grant select on public.weight_entries to authenticated;

create or replace function public.persist_weight_change(
  p_user_id uuid,
  p_action text,
  p_entry_id uuid,
  p_weight_kg numeric,
  p_recorded_on date,
  p_time_zone text,
  p_input jsonb,
  p_result jsonb,
  p_outcome text,
  p_should_recalculate boolean,
  p_expected_latest_date date,
  p_expected_latest_weight numeric
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  changed_entry public.weight_entries;
  current_entry public.weight_entries;
  new_plan public.nutrition_plans;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  if p_action = 'upsert' then
    if p_entry_id is null then
      insert into public.weight_entries (user_id, weight_kg, recorded_on, time_zone, source)
      values (p_user_id, p_weight_kg, p_recorded_on, p_time_zone, 'manual')
      on conflict (user_id, recorded_on) do update set
        weight_kg = excluded.weight_kg,
        time_zone = excluded.time_zone,
        source = 'manual',
        updated_at = now()
      returning * into changed_entry;
    else
      update public.weight_entries set
        weight_kg = p_weight_kg,
        recorded_on = p_recorded_on,
        time_zone = p_time_zone,
        updated_at = now()
      where id = p_entry_id and user_id = p_user_id
      returning * into changed_entry;
      if changed_entry.id is null then raise exception 'Weight entry not found'; end if;
    end if;
  elsif p_action = 'delete' then
    if exists (
      select 1 from public.weight_entries
      where id = p_entry_id and user_id = p_user_id and source = 'baseline'
    ) then raise exception 'Starting weight cannot be deleted'; end if;
    delete from public.weight_entries
      where id = p_entry_id and user_id = p_user_id
      returning * into changed_entry;
    if changed_entry.id is null then raise exception 'Weight entry not found'; end if;
  else
    raise exception 'Unsupported weight action';
  end if;

  select * into current_entry from public.weight_entries
    where user_id = p_user_id order by recorded_on desc limit 1;
  if current_entry.id is null then raise exception 'A starting weight is required'; end if;
  if current_entry.recorded_on is distinct from p_expected_latest_date
    or current_entry.weight_kg is distinct from p_expected_latest_weight then
    raise exception 'Weight history changed; retry the request';
  end if;

  if p_should_recalculate then
    if p_result is not null then
      new_plan := public.persist_nutrition_plan(p_user_id, p_input, p_result);
      update public.weight_entries set plan_id = new_plan.id
        where id = current_entry.id returning * into current_entry;
    else
      update public.profiles set current_weight_kg = current_entry.weight_kg, updated_at = now()
        where user_id = p_user_id;
    end if;
  end if;

  return jsonb_build_object(
    'entry', case when p_action = 'delete' then null else to_jsonb(changed_entry) end,
    'current_entry', to_jsonb(current_entry),
    'plan', case when new_plan.id is null then null else to_jsonb(new_plan) end,
    'plan_input', p_input,
    'plan_updated', new_plan.id is not null,
    'outcome', p_outcome
  );
end;
$$;

revoke all on function public.persist_weight_change(uuid, text, uuid, numeric, date, text, jsonb, jsonb, text, boolean, date, numeric)
  from public, anon, authenticated;
grant execute on function public.persist_weight_change(uuid, text, uuid, numeric, date, text, jsonb, jsonb, text, boolean, date, numeric)
  to service_role;
