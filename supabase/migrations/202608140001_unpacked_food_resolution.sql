-- Reusable non-packaged foods and provenance for the merged Describe flow.

alter table public.food_versions
  add column if not exists food_kind text not null default 'packaged'
    check (food_kind in ('packaged', 'generic', 'prepared')),
  add column if not exists resolution_confidence numeric(5,4)
    check (resolution_confidence between 0 and 1),
  add column if not exists nutrition_core_complete boolean not null default false,
  add column if not exists resolver_version text;

create index if not exists food_versions_active_source_record_idx
  on public.food_versions(source_system, source_record_id)
  where superseded_at is null;

update public.food_versions
set food_kind = case
  when gtin is null and source_system = 'usda_fdc' then 'generic'
  else 'packaged'
end
where food_kind = 'packaged';

create table public.food_aliases (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  alias text not null check (char_length(btrim(alias)) between 1 and 240),
  normalized_alias text generated always as (
    regexp_replace(lower(btrim(alias)), '[^a-z0-9]+', ' ', 'g')
  ) stored,
  locale text not null default 'en-US',
  source text not null check (source in ('canonical', 'usda', 'leafy_ai', 'user_confirmed', 'import')),
  created_at timestamptz not null default now(),
  unique (food_id, normalized_alias, locale)
);
create index food_aliases_normalized_idx on public.food_aliases(normalized_alias);

insert into public.food_aliases(food_id, alias, source)
select id, canonical_name, 'canonical' from public.foods
on conflict (food_id, normalized_alias, locale) do nothing;

alter table public.ai_meal_items
  add column if not exists food_version_id uuid references public.food_versions(id) on delete set null,
  add column if not exists resolution_source text not null default 'ai'
    check (resolution_source in ('leafy_catalog', 'usda', 'ai')),
  add column if not exists catalog_eligible boolean not null default false;

create table public.food_catalog_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  food_version_id uuid references public.food_versions(id) on delete set null,
  ai_meal_item_id uuid references public.ai_meal_items(id) on delete set null,
  feedback_kind text not null check (feedback_kind in ('confirmed', 'corrected', 'rejected')),
  corrected_fields jsonb not null default '{}'::jsonb check (jsonb_typeof(corrected_fields) = 'object'),
  created_at timestamptz not null default now()
);
create index food_catalog_feedback_version_idx on public.food_catalog_feedback(food_version_id, created_at desc);

alter table public.food_aliases enable row level security;
alter table public.food_catalog_feedback enable row level security;
create policy "users read food aliases" on public.food_aliases for select to authenticated using (true);
create policy "users read own food feedback" on public.food_catalog_feedback
  for select to authenticated using ((select auth.uid()) = user_id);

grant select on public.food_aliases, public.food_catalog_feedback to authenticated;
revoke insert, update, delete on public.food_aliases, public.food_catalog_feedback from anon, authenticated;

create or replace function public.search_unpacked_food_catalog(p_query text, p_limit integer default 8)
returns table (
  food_version_id uuid,
  canonical_name text,
  description text,
  source_system text,
  source_record_id text,
  verification_status text,
  resolution_confidence numeric,
  nutrition_core_complete boolean,
  rank real
)
language sql stable security invoker set search_path = '' as $$
  with normalized as (
    select regexp_replace(lower(btrim(p_query)), '[^a-z0-9]+', ' ', 'g') as value
  )
  select fv.id, f.canonical_name, fv.description, fv.source_system,
    fv.source_record_id, fv.verification_status, fv.resolution_confidence,
    fv.nutrition_core_complete,
    greatest(
      coalesce((select max(greatest(
        case when candidate.normalized_alias = normalized.value then 1 else 0 end,
        extensions.similarity(candidate.normalized_alias, normalized.value)
      )) from public.food_aliases candidate where candidate.food_id = f.id), 0),
      extensions.similarity(lower(f.canonical_name), lower(p_query)),
      extensions.similarity(lower(fv.description), lower(p_query))
    )::real as rank
  from public.food_versions fv
  join public.foods f on f.id = fv.food_id
  cross join normalized
  where fv.superseded_at is null
    and fv.food_kind in ('generic', 'prepared')
    and fv.verification_status <> 'rejected'
    and (
      fv.source_system = 'usda_fdc'
      or fv.verification_status in ('verified', 'community_confirmed')
      or (
        fv.source_system = 'leafy'
        and fv.resolution_confidence >= 0.80
        and fv.nutrition_core_complete
      )
    )
    and (
      exists (select 1 from public.food_aliases candidate
        where candidate.food_id = f.id and (
          candidate.normalized_alias = normalized.value
          or candidate.normalized_alias operator(extensions.%) normalized.value
        ))
      or lower(f.canonical_name) operator(extensions.%) lower(p_query)
      or lower(fv.description) operator(extensions.%) lower(p_query)
    )
  order by rank desc, (fv.source_system = 'usda_fdc') desc, fv.effective_from desc
  limit least(greatest(p_limit, 1), 20);
$$;

grant execute on function public.search_unpacked_food_catalog(text, integer) to authenticated;
