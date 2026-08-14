alter table public.ai_chat_messages
  add column scope_classification text
    check (scope_classification is null or scope_classification in ('health', 'mixed', 'off_topic', 'urgent_health')),
  add column counts_toward_limit boolean not null default true,
  add column scope_model_id text,
  add column scope_input_tokens integer check (scope_input_tokens is null or scope_input_tokens >= 0),
  add column scope_output_tokens integer check (scope_output_tokens is null or scope_output_tokens >= 0),
  add column scope_latency_ms integer check (scope_latency_ms is null or scope_latency_ms >= 0);

create index ai_chat_messages_user_limit_idx
  on public.ai_chat_messages(user_id, created_at desc)
  where role = 'user' and counts_toward_limit = true;

create index ai_chat_messages_user_off_topic_idx
  on public.ai_chat_messages(user_id, created_at desc)
  where role = 'user' and scope_classification = 'off_topic';

comment on column public.ai_chat_messages.scope_classification is
  'Private Ask Leafy routing metadata. Never exposed as user health data or included in commercial datasets.';
