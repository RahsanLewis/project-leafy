-- Durable background nutrient enrichment for logged foods.

create table public.nutrient_enrichment_jobs (
  id uuid primary key default gen_random_uuid(),
  consumption_item_id uuid not null unique references public.consumption_items(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  food_version_id uuid references public.food_versions(id) on delete set null,
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'retry_wait', 'complete', 'failed')),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  source_hash text,
  model_version text,
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index nutrient_enrichment_jobs_ready_idx
  on public.nutrient_enrichment_jobs(user_id, status, next_attempt_at)
  where status in ('queued', 'retry_wait');

alter table public.nutrient_enrichment_jobs enable row level security;
create policy "users read own nutrient enrichment jobs" on public.nutrient_enrichment_jobs
  for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.nutrient_enrichment_jobs to authenticated;
revoke insert, update, delete on public.nutrient_enrichment_jobs from anon, authenticated;

create or replace function public.queue_consumption_nutrient_enrichment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.nutrient_enrichment_jobs (
    consumption_item_id, user_id, food_version_id, status, attempts,
    next_attempt_at, last_error, completed_at, updated_at
  ) values (
    new.id, new.user_id, new.food_version_id, 'queued', 0,
    now(), null, null, now()
  ) on conflict (consumption_item_id) do update set
    food_version_id = excluded.food_version_id,
    status = case
      when public.nutrient_enrichment_jobs.source_hash is distinct from
        md5(concat_ws('|', new.description, new.calories_kcal, new.normalized_grams, new.portion_description, new.food_version_id))
      then 'queued' else public.nutrient_enrichment_jobs.status end,
    attempts = case
      when public.nutrient_enrichment_jobs.source_hash is distinct from
        md5(concat_ws('|', new.description, new.calories_kcal, new.normalized_grams, new.portion_description, new.food_version_id))
      then 0 else public.nutrient_enrichment_jobs.attempts end,
    next_attempt_at = now(),
    updated_at = now();
  return new;
end;
$$;

create trigger queue_nutrient_enrichment_after_consumption_change
after insert or update of description, calories_kcal, normalized_grams, portion_description, food_version_id
on public.consumption_items for each row execute function public.queue_consumption_nutrient_enrichment();

insert into public.nutrient_enrichment_jobs (consumption_item_id, user_id, food_version_id)
select ci.id, ci.user_id, ci.food_version_id
from public.consumption_items ci
where ci.deleted_at is null
  and exists (
    select 1 from public.nutrient_definitions nd
    where nd.code <> 'energy_kcal'
      and not exists (
        select 1 from public.consumption_item_nutrients cin
        where cin.consumption_item_id = ci.id and cin.nutrient_code = nd.code
      )
  )
on conflict (consumption_item_id) do nothing;

