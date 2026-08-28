-- Durable food-log intent for products that still need label processing.

create table public.catalog_contribution_log_requests (
  id uuid primary key default gen_random_uuid(),
  contribution_id uuid not null unique references public.catalog_contributions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  serving_count numeric not null check (serving_count between 0.25 and 100),
  consumed_at timestamptz not null,
  local_date date not null,
  time_zone text not null,
  meal_type text not null default 'unspecified'
    check (meal_type in ('breakfast', 'lunch', 'dinner', 'snack', 'drink', 'supplement', 'unspecified')),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'needs_action', 'failed', 'completed', 'cancelled')),
  food_entry_id uuid unique references public.food_entries(id) on delete set null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index catalog_contribution_log_requests_user_day_idx
  on public.catalog_contribution_log_requests(user_id, local_date, consumed_at);

-- A worker may stop after creating the entry but before marking the request
-- complete. This key makes replay safe.
create unique index food_entries_catalog_contribution_log_idx
  on public.food_entries ((provenance ->> 'catalog_log_request_id'))
  where provenance ->> 'catalog_log_request_id' is not null;

alter table public.catalog_contribution_log_requests enable row level security;
create policy "users read own catalog log requests"
  on public.catalog_contribution_log_requests for select to authenticated
  using (auth.uid() = user_id);
grant select on public.catalog_contribution_log_requests to authenticated;
revoke insert, update, delete on public.catalog_contribution_log_requests from anon, authenticated;

-- Preserve requests queued by the previous JSON-backed implementation.
insert into public.catalog_contribution_log_requests (
  contribution_id, user_id, serving_count, consumed_at, local_date, time_zone,
  meal_type, status, food_entry_id, completed_at, created_at, updated_at
)
select
  job.contribution_id,
  job.user_id,
  greatest(0.25, least(100, coalesce((job.requested_log ->> 'serving_count')::numeric, 1))),
  (job.requested_log ->> 'consumed_at')::timestamptz,
  (job.requested_log ->> 'local_date')::date,
  coalesce(nullif(job.requested_log ->> 'time_zone', ''), 'UTC'),
  coalesce(nullif(job.requested_log ->> 'meal_type', ''), 'unspecified'),
  case when job.requested_log ->> 'logged_entry_id' is not null then 'completed' else 'pending' end,
  nullif(job.requested_log ->> 'logged_entry_id', '')::uuid,
  case when job.requested_log ->> 'logged_entry_id' is not null then coalesce(job.completed_at, job.updated_at) end,
  job.created_at,
  job.updated_at
from public.catalog_contribution_jobs job
where job.requested_log is not null
  and job.requested_log ->> 'consumed_at' is not null
  and job.requested_log ->> 'local_date' is not null
on conflict (contribution_id) do nothing;

update public.food_entries entry
set provenance = entry.provenance || jsonb_build_object('catalog_log_request_id', request.id)
from public.catalog_contribution_log_requests request
where request.food_entry_id = entry.id
  and entry.provenance ->> 'catalog_log_request_id' is null;
