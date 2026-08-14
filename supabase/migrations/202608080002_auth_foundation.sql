-- Versioned account legal acceptance records. Existing profile timestamps remain for compatibility.
create table public.account_legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_key text not null check (document_key in ('terms_of_use', 'privacy_policy')),
  document_version integer not null check (document_version > 0),
  locale text not null default 'en-US',
  app_version text not null,
  accepted_at timestamptz not null default now(),
  unique (user_id, document_key, document_version)
);

alter table public.account_legal_acceptances enable row level security;
create policy "users read own legal acceptances" on public.account_legal_acceptances
  for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.account_legal_acceptances to authenticated;
revoke insert, update, delete on public.account_legal_acceptances from anon, authenticated;

create index account_legal_acceptances_user_idx
  on public.account_legal_acceptances(user_id, accepted_at desc);
