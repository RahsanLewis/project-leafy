-- Durable, auditable processing for two-photo catalog contributions.

alter table public.catalog_contributions
  drop constraint if exists catalog_contributions_status_check;
alter table public.catalog_contributions
  add constraint catalog_contributions_status_check
  check (status in ('draft', 'processing', 'pending_review', 'accepted', 'needs_review', 'rejected'));

alter table public.catalog_contributions
  add column if not exists verification_results jsonb not null default '{}'::jsonb
    check (jsonb_typeof(verification_results) = 'object'),
  add column if not exists automation_version text,
  add column if not exists retake_count integer not null default 0 check (retake_count between 0 and 1);

create table public.catalog_contribution_jobs (
  id uuid primary key default gen_random_uuid(),
  contribution_id uuid not null unique references public.catalog_contributions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'queued'
    check (status in ('queued', 'extracting', 'verifying', 'publishing', 'retry_wait', 'complete', 'failed')),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  requested_log jsonb check (requested_log is null or jsonb_typeof(requested_log) = 'object'),
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index catalog_contribution_jobs_ready_idx
  on public.catalog_contribution_jobs(status, next_attempt_at)
  where status in ('queued', 'retry_wait');

create table public.catalog_verification_sources (
  id uuid primary key default gen_random_uuid(),
  contribution_id uuid not null references public.catalog_contributions(id) on delete cascade,
  revision integer not null,
  url text not null,
  title text,
  domain text,
  source_kind text not null check (source_kind in ('manufacturer', 'usda', 'retailer', 'database', 'other')),
  exact_gtin_match boolean not null default false,
  matched_fields jsonb not null default '[]'::jsonb check (jsonb_typeof(matched_fields) = 'array'),
  retrieved_at timestamptz not null default now(),
  content_hash text,
  unique (contribution_id, revision, url)
);

alter table public.catalog_contribution_jobs enable row level security;
alter table public.catalog_verification_sources enable row level security;

create policy "users read own catalog jobs" on public.catalog_contribution_jobs
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "users read own catalog verification sources" on public.catalog_verification_sources
  for select to authenticated using (exists (
    select 1 from public.catalog_contributions cc
    where cc.id = contribution_id and cc.user_id = (select auth.uid())
  ));

grant select on public.catalog_contribution_jobs, public.catalog_verification_sources to authenticated;
revoke insert, update, delete on public.catalog_contribution_jobs, public.catalog_verification_sources from anon, authenticated;

alter table public.account_legal_acceptances
  drop constraint if exists account_legal_acceptances_document_key_check;
alter table public.account_legal_acceptances
  add constraint account_legal_acceptances_document_key_check
  check (document_key in ('terms_of_use', 'privacy_policy', 'core_data_use', 'catalog_product_contribution'));
