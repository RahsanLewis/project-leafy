-- Production catalog administration is deliberately separate from consumer data.
-- Membership is checked only by service-role Edge Functions; no client role can
-- enumerate or mutate this table directly.
create table if not exists public.admin_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('catalog_admin')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

alter table public.admin_memberships enable row level security;
revoke all on public.admin_memberships from anon, authenticated;

comment on table public.admin_memberships is
  'Server-only allowlist for Leafy internal catalog administration.';

