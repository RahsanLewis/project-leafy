alter table public.ai_chat_messages
  add column meal_estimate_session_id uuid references public.ai_meal_sessions(id) on delete set null;

create index ai_chat_messages_meal_session_idx
  on public.ai_chat_messages(meal_estimate_session_id)
  where meal_estimate_session_id is not null;

comment on column public.ai_chat_messages.meal_estimate_session_id is
  'Optional canonical AI meal estimate shown inline in Ask Leafy. Logging still requires explicit user confirmation.';
