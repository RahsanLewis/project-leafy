-- Auditable AI meal estimates. Predictions are retained separately from the
-- user-confirmed food log so corrections can be measured without rewriting history.

create table public.ai_meal_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  status text not null default 'draft'
    check (status in ('draft', 'analyzing', 'needs_clarification', 'ready', 'confirmed', 'failed', 'discarded')),
  input_modalities text[] not null default '{}',
  description_text text check (char_length(description_text) <= 2000),
  voice_transcript text check (char_length(voice_transcript) <= 2000),
  meal_type text not null default 'unspecified'
    check (meal_type in ('breakfast', 'lunch', 'dinner', 'snack', 'drink', 'supplement', 'unspecified')),
  consumed_at timestamptz not null,
  local_date date not null,
  time_zone text not null check (char_length(time_zone) between 1 and 80),
  provider text not null default 'openai',
  model_id text,
  prompt_version text not null default 'leafy-meal-v1',
  schema_version integer not null default 1,
  provider_response_id text,
  estimated_calories integer check (estimated_calories between 0 and 50000),
  calorie_low integer check (calorie_low between 0 and 50000),
  calorie_high integer check (calorie_high between 0 and 50000),
  confidence numeric(5,4) check (confidence between 0 and 1),
  assumptions jsonb not null default '[]'::jsonb check (jsonb_typeof(assumptions) = 'array'),
  follow_up_count integer not null default 0 check (follow_up_count between 0 and 3),
  confirmed_calories integer check (confirmed_calories between 0 and 50000),
  input_tokens integer check (input_tokens >= 0),
  output_tokens integer check (output_tokens >= 0),
  latency_ms integer check (latency_ms >= 0),
  error_code text,
  error_message text,
  confirmed_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (calorie_low is null or calorie_high is null or calorie_low <= calorie_high)
);

create index ai_meal_sessions_user_created_idx
  on public.ai_meal_sessions(user_id, created_at desc);

create table public.ai_meal_follow_ups (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.ai_meal_sessions(id) on delete cascade,
  ordinal integer not null check (ordinal between 1 and 3),
  question text not null check (char_length(btrim(question)) between 1 and 500),
  answer text check (char_length(answer) <= 1000),
  skipped boolean not null default false,
  answered_at timestamptz,
  created_at timestamptz not null default now(),
  unique(session_id, ordinal)
);

create table public.ai_meal_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.ai_meal_sessions(id) on delete cascade,
  ordinal integer not null check (ordinal > 0),
  predicted_name text not null check (char_length(btrim(predicted_name)) between 1 and 240),
  predicted_portion text check (char_length(predicted_portion) <= 240),
  predicted_grams numeric(12,4) check (predicted_grams > 0),
  predicted_calories integer not null check (predicted_calories between 0 and 10000),
  calorie_low integer not null check (calorie_low between 0 and 10000),
  calorie_high integer not null check (calorie_high between 0 and 10000),
  confidence numeric(5,4) not null check (confidence between 0 and 1),
  assumptions jsonb not null default '[]'::jsonb check (jsonb_typeof(assumptions) = 'array'),
  confirmed_name text check (char_length(btrim(confirmed_name)) between 1 and 240),
  confirmed_portion text check (char_length(confirmed_portion) <= 240),
  confirmed_calories integer check (confirmed_calories between 1 and 10000),
  review_outcome text check (review_outcome in ('accepted', 'edited', 'removed')),
  food_entry_id uuid unique references public.food_entries(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(session_id, ordinal),
  check (calorie_low <= calorie_high)
);

alter table public.nutrition_media_assets
  add column ai_meal_session_id uuid references public.ai_meal_sessions(id) on delete cascade;

create unique index nutrition_media_ai_meal_photo_idx
  on public.nutrition_media_assets(ai_meal_session_id)
  where ai_meal_session_id is not null and asset_kind = 'meal_photo' and deleted_at is null;

alter table public.food_entries add column occasion_id uuid;
update public.food_entries set occasion_id = id where occasion_id is null;
create index food_entries_occasion_idx on public.food_entries(occasion_id);

-- Group multiple compatibility food rows under one normalized eating occasion.
create or replace function public.sync_food_entry_to_consumption()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  item_id uuid;
  active_grant uuid;
  active_occasion uuid;
  old_occasion uuid;
begin
  if tg_op = 'DELETE' then
    old_occasion := coalesce(old.occasion_id, old.id);
    if not exists (
      select 1 from public.food_entries
      where user_id = old.user_id and coalesce(occasion_id, id) = old_occasion
    ) then
      delete from public.eating_occasions where id = old_occasion and user_id = old.user_id;
    end if;
    return old;
  end if;

  active_occasion := coalesce(new.occasion_id, new.id);

  select id into active_grant from public.consent_grants
  where user_id = new.user_id and purpose = 'commercial_dataset'
    and revoked_at is null and granted_at <= now()
    and (expires_at is null or expires_at > now())
  order by granted_at desc limit 1;

  insert into public.eating_occasions (
    id, user_id, occasion_type, started_at, local_date, time_zone, created_at, updated_at
  ) values (
    active_occasion, new.user_id, new.meal_type, new.consumed_at, new.local_date,
    new.time_zone, new.created_at, new.updated_at
  ) on conflict (id) do update set
    occasion_type = excluded.occasion_type, started_at = least(public.eating_occasions.started_at, excluded.started_at),
    local_date = excluded.local_date, time_zone = excluded.time_zone, updated_at = excluded.updated_at;

  insert into public.consumption_items (
    user_id, occasion_id, food_version_id, legacy_food_entry_id, description,
    original_amount, original_unit, normalized_grams, portion_description, calories_kcal,
    entry_source, calorie_method, confidence, user_confirmed, provenance,
    commercial_eligible, consent_grant_id, created_at, updated_at
  ) values (
    new.user_id, active_occasion, new.canonical_food_version_id, new.id, new.name,
    new.amount, new.amount_unit, new.gram_weight, new.portion_description, new.calories,
    new.entry_source, new.calorie_method, new.confidence, new.user_confirmed, new.provenance,
    active_grant is not null, active_grant, new.created_at, new.updated_at
  ) on conflict (legacy_food_entry_id) do update set
    occasion_id = excluded.occasion_id, food_version_id = excluded.food_version_id,
    description = excluded.description, original_amount = excluded.original_amount,
    original_unit = excluded.original_unit, normalized_grams = excluded.normalized_grams,
    portion_description = excluded.portion_description, calories_kcal = excluded.calories_kcal,
    entry_source = excluded.entry_source, calorie_method = excluded.calorie_method,
    confidence = excluded.confidence, user_confirmed = excluded.user_confirmed,
    provenance = excluded.provenance, revision = public.consumption_items.revision + 1,
    updated_at = excluded.updated_at
  returning id into item_id;

  insert into public.consumption_item_nutrients (
    consumption_item_id, nutrient_code, amount, derivation_method, confidence
  ) values (
    item_id, 'energy_kcal', new.calories,
    case when new.calorie_method = 'nutrition_database' then 'calculated'
         when new.calorie_method = 'estimated' then 'estimated'
         else 'user_entered' end,
    new.confidence
  ) on conflict (consumption_item_id, nutrient_code) do update set
    amount = excluded.amount, derivation_method = excluded.derivation_method,
    confidence = excluded.confidence;

  if tg_op = 'UPDATE' then
    old_occasion := coalesce(old.occasion_id, old.id);
    if old_occasion <> active_occasion and not exists (
      select 1 from public.food_entries
      where user_id = old.user_id and coalesce(occasion_id, id) = old_occasion
    ) then
      delete from public.eating_occasions where id = old_occasion and user_id = old.user_id;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.confirm_ai_meal(
  p_user_id uuid,
  p_session_id uuid,
  p_items jsonb
) returns setof public.food_entries
language plpgsql security definer set search_path = '' as $$
declare
  session_row public.ai_meal_sessions;
  prediction public.ai_meal_items;
  requested jsonb;
  new_entry public.food_entries;
  occasion_uuid uuid := gen_random_uuid();
  total_calories integer := 0;
  selected_ids uuid[] := '{}';
  source_kind text;
begin
  select * into session_row from public.ai_meal_sessions
  where id = p_session_id and user_id = p_user_id and deleted_at is null
  for update;
  if not found or session_row.status <> 'ready' then
    raise exception 'This estimate is not ready to save';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Choose at least one food item';
  end if;

  source_kind := case when 'photo' = any(session_row.input_modalities) then 'photo_ai' else 'text_ai' end;

  for requested in select value from jsonb_array_elements(p_items)
  loop
    select * into prediction from public.ai_meal_items
    where id = (requested->>'id')::uuid and session_id = p_session_id
    for update;
    if not found then raise exception 'An estimated food item is invalid'; end if;
    if coalesce((requested->>'calories')::integer, 0) not between 1 and 10000 then
      raise exception 'Calories must be between 1 and 10,000';
    end if;

    insert into public.food_entries (
      user_id, name, calories, consumed_at, local_date, time_zone,
      amount, amount_unit, gram_weight, portion_description, meal_type,
      entry_source, calorie_method, confidence, user_confirmed, provenance, occasion_id
    ) values (
      p_user_id, btrim(requested->>'name'), (requested->>'calories')::integer,
      session_row.consumed_at, session_row.local_date, session_row.time_zone,
      prediction.predicted_grams, case when prediction.predicted_grams is null then null else 'g' end,
      prediction.predicted_grams, nullif(btrim(requested->>'portion'), ''), session_row.meal_type,
      source_kind, 'estimated', prediction.confidence, true,
      jsonb_build_object(
        'capture_version', 'ios-ai-meal-v1', 'ai_meal_session_id', p_session_id,
        'ai_meal_item_id', prediction.id, 'provider', session_row.provider,
        'model_id', session_row.model_id, 'prompt_version', session_row.prompt_version,
        'schema_version', session_row.schema_version
      ), occasion_uuid
    ) returning * into new_entry;

    update public.ai_meal_items set
      confirmed_name = new_entry.name,
      confirmed_portion = new_entry.portion_description,
      confirmed_calories = new_entry.calories,
      review_outcome = case
        when new_entry.name = prediction.predicted_name
          and coalesce(new_entry.portion_description, '') = coalesce(prediction.predicted_portion, '')
          and new_entry.calories = prediction.predicted_calories then 'accepted'
        else 'edited' end,
      food_entry_id = new_entry.id,
      updated_at = now()
    where id = prediction.id;

    selected_ids := array_append(selected_ids, prediction.id);
    total_calories := total_calories + new_entry.calories;
    return next new_entry;
  end loop;

  update public.ai_meal_items set review_outcome = 'removed', updated_at = now()
  where session_id = p_session_id and not (id = any(selected_ids));

  update public.ai_meal_sessions set
    status = 'confirmed', confirmed_calories = total_calories,
    confirmed_at = now(), updated_at = now()
  where id = p_session_id;
end;
$$;

revoke all on function public.confirm_ai_meal(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.confirm_ai_meal(uuid, uuid, jsonb) to service_role;

alter table public.ai_meal_sessions enable row level security;
alter table public.ai_meal_follow_ups enable row level security;
alter table public.ai_meal_items enable row level security;

create policy "users read own ai meal sessions" on public.ai_meal_sessions
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "users read own ai meal follow ups" on public.ai_meal_follow_ups
  for select to authenticated using (exists (
    select 1 from public.ai_meal_sessions s
    where s.id = session_id and s.user_id = (select auth.uid())
  ));
create policy "users read own ai meal items" on public.ai_meal_items
  for select to authenticated using (exists (
    select 1 from public.ai_meal_sessions s
    where s.id = session_id and s.user_id = (select auth.uid())
  ));

grant select on public.ai_meal_sessions, public.ai_meal_follow_ups, public.ai_meal_items to authenticated;
revoke insert, update, delete on public.ai_meal_sessions, public.ai_meal_follow_ups, public.ai_meal_items
  from anon, authenticated;
