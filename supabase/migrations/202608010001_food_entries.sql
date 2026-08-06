create table public.food_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  calories integer not null check (calories between 1 and 10000),
  consumed_at timestamptz not null,
  local_date date not null,
  time_zone text not null check (char_length(time_zone) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index food_entries_user_date_time_idx
  on public.food_entries(user_id, local_date, consumed_at);

alter table public.food_entries enable row level security;

create policy "users read own food entries"
  on public.food_entries for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "users insert own food entries"
  on public.food_entries for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "users update own food entries"
  on public.food_entries for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "users delete own food entries"
  on public.food_entries for delete to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.food_entries to authenticated;
