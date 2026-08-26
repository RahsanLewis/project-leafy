create table public.ai_meal_review_additions (
  id uuid primary key,
  session_id uuid not null references public.ai_meal_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  portion text check (char_length(portion) <= 240),
  calories integer not null check (calories between 1 and 10000),
  food_entry_id uuid unique references public.food_entries(id) on delete set null,
  created_at timestamptz not null default now()
);

create index ai_meal_review_additions_session_idx on public.ai_meal_review_additions(session_id);
alter table public.ai_meal_review_additions enable row level security;
create policy "users read own ai meal additions" on public.ai_meal_review_additions
  for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.ai_meal_review_additions to authenticated;
revoke insert, update, delete on public.ai_meal_review_additions from anon, authenticated;

drop function if exists public.confirm_ai_meal(uuid, uuid, jsonb);
create or replace function public.confirm_ai_meal(
  p_user_id uuid,
  p_session_id uuid,
  p_items jsonb,
  p_consumed_at timestamptz default null,
  p_local_date date default null,
  p_time_zone text default null
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
  prediction_uuid uuid;
  client_uuid uuid;
  is_added boolean;
  source_kind text;
  item_confidence numeric;
begin
  select * into session_row from public.ai_meal_sessions
  where id = p_session_id and user_id = p_user_id and deleted_at is null for update;
  if not found or session_row.status <> 'ready' then raise exception 'This estimate is not ready to save'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Choose at least one food item'; end if;
  if (p_consumed_at is null) <> (p_local_date is null) or (p_consumed_at is null) <> (p_time_zone is null) then
    raise exception 'Meal date and time must be provided together';
  end if;
  if p_consumed_at is not null then
    update public.ai_meal_sessions set consumed_at = p_consumed_at, local_date = p_local_date,
      time_zone = left(p_time_zone, 80), updated_at = now() where id = p_session_id;
    session_row.consumed_at := p_consumed_at; session_row.local_date := p_local_date; session_row.time_zone := left(p_time_zone, 80);
  end if;
  source_kind := case when 'photo' = any(session_row.input_modalities) then 'photo_ai' else 'text_ai' end;

  for requested in select value from jsonb_array_elements(p_items) loop
    is_added := coalesce(requested->>'origin', 'prediction') = 'user_added';
    client_uuid := (requested->>'client_item_id')::uuid;
    if coalesce((requested->>'calories')::integer, 0) not between 1 and 10000 or btrim(coalesce(requested->>'name', '')) = '' then
      raise exception 'Review each food name and calorie estimate before saving';
    end if;
    if is_added then
      prediction := null; prediction_uuid := null; item_confidence := 1;
    else
      prediction_uuid := coalesce(requested->>'id', requested->>'prediction_id')::uuid;
      select * into prediction from public.ai_meal_items where id = prediction_uuid and session_id = p_session_id for update;
      if not found then raise exception 'An estimated food item is invalid'; end if;
      item_confidence := prediction.confidence;
    end if;

    insert into public.food_entries (
      user_id, name, calories, consumed_at, local_date, time_zone, amount, amount_unit,
      gram_weight, portion_description, meal_type, entry_source, calorie_method,
      confidence, user_confirmed, provenance, occasion_id
    ) values (
      p_user_id, btrim(requested->>'name'), (requested->>'calories')::integer,
      session_row.consumed_at, session_row.local_date, session_row.time_zone,
      case when is_added then null else prediction.predicted_grams end,
      case when is_added or prediction.predicted_grams is null then null else 'g' end,
      case when is_added then null else prediction.predicted_grams end,
      nullif(btrim(requested->>'portion'), ''), session_row.meal_type, source_kind,
      case when is_added then 'user_entered' else 'estimated' end, item_confidence, true,
      jsonb_build_object('capture_version', 'ios-chat-meal-v2', 'ai_meal_session_id', p_session_id,
        'ai_meal_item_id', prediction_uuid, 'review_origin', case when is_added then 'user_added' else 'prediction' end),
      occasion_uuid
    ) returning * into new_entry;

    if is_added then
      insert into public.ai_meal_review_additions(id, session_id, user_id, name, portion, calories, food_entry_id)
      values (client_uuid, p_session_id, p_user_id, new_entry.name, new_entry.portion_description, new_entry.calories, new_entry.id);
    else
      update public.ai_meal_items set confirmed_name = new_entry.name,
        confirmed_portion = new_entry.portion_description, confirmed_calories = new_entry.calories,
        review_outcome = case when new_entry.name = prediction.predicted_name
          and coalesce(new_entry.portion_description, '') = coalesce(prediction.predicted_portion, '')
          and new_entry.calories = prediction.predicted_calories then 'accepted' else 'edited' end,
        food_entry_id = new_entry.id, updated_at = now() where id = prediction.id;
      selected_ids := array_append(selected_ids, prediction.id);
    end if;
    total_calories := total_calories + new_entry.calories;
    return next new_entry;
  end loop;

  update public.ai_meal_items set review_outcome = 'removed', updated_at = now()
  where session_id = p_session_id and not (id = any(selected_ids));
  update public.ai_meal_sessions set status = 'confirmed', confirmed_calories = total_calories,
    confirmed_at = now(), updated_at = now() where id = p_session_id;
end;
$$;

revoke all on function public.confirm_ai_meal(uuid, uuid, jsonb, timestamptz, date, text) from public, anon, authenticated;
grant execute on function public.confirm_ai_meal(uuid, uuid, jsonb, timestamptz, date, text) to service_role;
