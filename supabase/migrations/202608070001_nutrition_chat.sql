create table public.ai_chat_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index ai_chat_threads_user_recent_idx on public.ai_chat_threads(user_id, last_message_at desc);

create table public.ai_chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.ai_chat_threads(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(btrim(content)) between 1 and 8000),
  sources jsonb not null default '[]'::jsonb check (jsonb_typeof(sources) = 'array'),
  suggested_log_description text check (suggested_log_description is null or char_length(suggested_log_description) <= 2000),
  client_message_id uuid,
  model_id text,
  provider_response_id text,
  input_tokens integer,
  output_tokens integer,
  latency_ms integer,
  commercial_eligible boolean not null default false check (commercial_eligible = false),
  created_at timestamptz not null default now()
);

create index ai_chat_messages_thread_time_idx on public.ai_chat_messages(thread_id, created_at);
create unique index ai_chat_messages_client_id_idx on public.ai_chat_messages(user_id, client_message_id) where client_message_id is not null;

alter table public.ai_chat_threads enable row level security;
alter table public.ai_chat_messages enable row level security;
create policy "users read own chat threads" on public.ai_chat_threads for select to authenticated using ((select auth.uid()) = user_id);
create policy "users read own chat messages" on public.ai_chat_messages for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.ai_chat_threads, public.ai_chat_messages to authenticated;
revoke insert, update, delete on public.ai_chat_threads, public.ai_chat_messages from anon, authenticated;

comment on table public.ai_chat_messages is 'Private nutrition-assistant history. Never included in Leafy commercial datasets.';
