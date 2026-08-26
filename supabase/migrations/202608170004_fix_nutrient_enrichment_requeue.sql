-- Requeue only when the consumption item trigger fires. The trigger is already
-- scoped to source fields, so comparing hashes here is redundant and allowed
-- differing database/worker hash implementations to cause needless retries.

create or replace function public.queue_consumption_nutrient_enrichment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.nutrient_enrichment_jobs (
    consumption_item_id, user_id, food_version_id, status, attempts,
    next_attempt_at, source_hash, model_version, last_error,
    started_at, completed_at, updated_at
  ) values (
    new.id, new.user_id, new.food_version_id, 'queued', 0,
    now(), null, null, null, null, null, now()
  ) on conflict (consumption_item_id) do update set
    user_id = excluded.user_id,
    food_version_id = excluded.food_version_id,
    status = 'queued',
    attempts = 0,
    next_attempt_at = now(),
    source_hash = null,
    model_version = null,
    last_error = null,
    started_at = null,
    completed_at = null,
    updated_at = now();
  return new;
end;
$$;
