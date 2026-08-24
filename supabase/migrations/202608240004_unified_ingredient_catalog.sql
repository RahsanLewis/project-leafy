create table if not exists public.pfqs_ingredient_releases (
  version text primary key,
  taxonomy_version text not null,
  status text not null check (status in ('draft', 'active', 'retired')),
  published_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.pfqs_ingredients (
  ingredient_database_version text not null references public.pfqs_ingredient_releases(version) on delete restrict,
  canonical_id text not null,
  canonical_name text not null,
  category text,
  family_id text,
  quality_class text check (quality_class is null or quality_class in ('A', 'B', 'C', 'D', 'E')),
  quality_coefficient numeric check (quality_coefficient is null or quality_coefficient between 0 and 1),
  beneficial boolean not null default false,
  classification_confidence numeric check (classification_confidence is null or classification_confidence between 0 and 1),
  classification_source text,
  review_status text not null default 'unclassified' check (review_status in ('unclassified', 'classified', 'reviewed')),
  risk_canonical_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (ingredient_database_version, canonical_id)
);

create table if not exists public.pfqs_ingredient_aliases (
  ingredient_database_version text not null,
  canonical_id text not null,
  alias text not null,
  normalized_alias text not null,
  created_at timestamptz not null default now(),
  primary key (ingredient_database_version, normalized_alias),
  foreign key (ingredient_database_version, canonical_id)
    references public.pfqs_ingredients(ingredient_database_version, canonical_id) on delete cascade
);

create table if not exists public.pfqs_food_ingredient_occurrences (
  id uuid primary key default gen_random_uuid(),
  food_version_id uuid not null references public.food_versions(id) on delete cascade,
  ingredient_database_version text not null,
  canonical_id text not null,
  raw_text text not null,
  canonical_name text not null,
  parent_canonical_id text,
  position integer not null check (position > 0),
  depth integer not null default 0 check (depth >= 0),
  percentage numeric,
  ingredient_path text not null,
  created_at timestamptz not null default now(),
  unique (food_version_id, ingredient_database_version, ingredient_path),
  foreign key (ingredient_database_version, canonical_id)
    references public.pfqs_ingredients(ingredient_database_version, canonical_id) on delete cascade
);

create index if not exists pfqs_ingredients_name_idx on public.pfqs_ingredients (ingredient_database_version, canonical_name);
create index if not exists pfqs_ingredients_review_idx on public.pfqs_ingredients (ingredient_database_version, review_status);
create index if not exists pfqs_ingredient_aliases_name_idx on public.pfqs_ingredient_aliases (ingredient_database_version, normalized_alias);
create index if not exists pfqs_food_ingredient_occurrences_food_idx on public.pfqs_food_ingredient_occurrences (food_version_id);
create index if not exists pfqs_food_ingredient_occurrences_ingredient_idx on public.pfqs_food_ingredient_occurrences (ingredient_database_version, canonical_id);

alter table public.pfqs_ingredient_releases enable row level security;
alter table public.pfqs_ingredients enable row level security;
alter table public.pfqs_ingredient_aliases enable row level security;
alter table public.pfqs_food_ingredient_occurrences enable row level security;

insert into public.pfqs_ingredient_releases (version, taxonomy_version, status, published_at)
values ('PFQS-INGREDIENTS-2026-08-24', 'PFQS-TAXONOMY-1.0', 'active', now())
on conflict (version) do update set status = excluded.status, published_at = coalesce(public.pfqs_ingredient_releases.published_at, excluded.published_at);

insert into public.pfqs_ingredients (
  ingredient_database_version, canonical_id, canonical_name, family_id, review_status, risk_canonical_id
)
select 'PFQS-INGREDIENTS-2026-08-24',
       'ingredient_' || trim(both '_' from regexp_replace(lower(a.canonical_name), '[^a-z0-9]+', '_', 'g')),
       lower(a.canonical_name), a.family_id, 'reviewed', a.canonical_id
from public.pfqs_additives a
where a.additive_database_version = 'PFQS-ADDITIVES-2026-08-13'
on conflict (ingredient_database_version, canonical_id) do update
set family_id = excluded.family_id, review_status = 'reviewed', risk_canonical_id = excluded.risk_canonical_id, updated_at = now();

insert into public.pfqs_ingredient_aliases (ingredient_database_version, canonical_id, alias, normalized_alias)
select 'PFQS-INGREDIENTS-2026-08-24',
       'ingredient_' || trim(both '_' from regexp_replace(lower(a.canonical_name), '[^a-z0-9]+', '_', 'g')),
       aa.alias, lower(trim(aa.normalized_alias))
from public.pfqs_additive_aliases aa
join public.pfqs_additives a
  on a.additive_database_version = aa.additive_database_version and a.canonical_id = aa.canonical_id
where aa.additive_database_version = 'PFQS-ADDITIVES-2026-08-13'
on conflict (ingredient_database_version, normalized_alias) do nothing;

with classified as (
  select c.value as ingredient
  from public.pfqs_ingredient_snapshots s
  cross join lateral jsonb_array_elements(coalesce(s.classified_ingredients, '[]'::jsonb)) c(value)
), values_to_classify as (
  select distinct on (lower(trim(ingredient->>'canonical_name')))
    lower(trim(ingredient->>'canonical_name')) as canonical_name,
    nullif(ingredient->>'quality_class', '') as quality_class,
    nullif(ingredient->>'quality_coefficient', '')::numeric as quality_coefficient,
    coalesce((ingredient->>'beneficial')::boolean, false) as beneficial,
    nullif(ingredient->>'confidence', '')::numeric as confidence,
    nullif(ingredient->>'classification_source', '') as classification_source
  from classified
  where coalesce(trim(ingredient->>'canonical_name'), '') <> ''
)
insert into public.pfqs_ingredients (
  ingredient_database_version, canonical_id, canonical_name, quality_class,
  quality_coefficient, beneficial, classification_confidence, classification_source, review_status
)
select 'PFQS-INGREDIENTS-2026-08-24',
       'ingredient_' || trim(both '_' from regexp_replace(canonical_name, '[^a-z0-9]+', '_', 'g')),
       canonical_name, quality_class, quality_coefficient, beneficial, confidence,
       classification_source, 'classified'
from values_to_classify
on conflict (ingredient_database_version, canonical_id) do update set
  quality_class = coalesce(public.pfqs_ingredients.quality_class, excluded.quality_class),
  quality_coefficient = coalesce(public.pfqs_ingredients.quality_coefficient, excluded.quality_coefficient),
  beneficial = public.pfqs_ingredients.beneficial or excluded.beneficial,
  classification_confidence = coalesce(public.pfqs_ingredients.classification_confidence, excluded.classification_confidence),
  classification_source = coalesce(public.pfqs_ingredients.classification_source, excluded.classification_source),
  review_status = case when public.pfqs_ingredients.review_status = 'reviewed' then 'reviewed' else 'classified' end,
  updated_at = now();

with recursive expanded as (
  select s.food_version_id, e.value as ingredient, e.ordinality::int as position, 0 as depth,
         e.ordinality::text as ingredient_path
  from public.pfqs_ingredient_snapshots s
  cross join lateral jsonb_array_elements(coalesce(s.parsed_ingredients, '[]'::jsonb)) with ordinality e(value, ordinality)
  union all
  select expanded.food_version_id, child.value, child.ordinality::int, expanded.depth + 1,
         expanded.ingredient_path || '.' || child.ordinality::text
  from expanded
  cross join lateral jsonb_array_elements(coalesce(expanded.ingredient->'subingredients', '[]'::jsonb)) with ordinality child(value, ordinality)
), names as (
  select distinct lower(trim(ingredient->>'canonical_name')) as canonical_name
  from expanded where coalesce(trim(ingredient->>'canonical_name'), '') <> ''
)
insert into public.pfqs_ingredients (ingredient_database_version, canonical_id, canonical_name, review_status)
select 'PFQS-INGREDIENTS-2026-08-24',
       'ingredient_' || trim(both '_' from regexp_replace(canonical_name, '[^a-z0-9]+', '_', 'g')),
       canonical_name, 'unclassified'
from names
on conflict (ingredient_database_version, canonical_id) do nothing;

with recursive expanded as (
  select e.value as ingredient
  from public.pfqs_ingredient_snapshots s
  cross join lateral jsonb_array_elements(coalesce(s.parsed_ingredients, '[]'::jsonb)) e(value)
  union all
  select child.value
  from expanded
  cross join lateral jsonb_array_elements(coalesce(expanded.ingredient->'subingredients', '[]'::jsonb)) child(value)
), aliases as (
  select distinct lower(trim(ingredient->>'canonical_name')) as canonical_name,
         coalesce(nullif(trim(ingredient->>'raw'), ''), trim(ingredient->>'name')) as alias
  from expanded
  where coalesce(trim(ingredient->>'canonical_name'), '') <> ''
)
insert into public.pfqs_ingredient_aliases (ingredient_database_version, canonical_id, alias, normalized_alias)
select 'PFQS-INGREDIENTS-2026-08-24',
       'ingredient_' || trim(both '_' from regexp_replace(canonical_name, '[^a-z0-9]+', '_', 'g')),
       alias, trim(both ' ' from regexp_replace(lower(alias), '[^a-z0-9]+', ' ', 'g'))
from aliases where coalesce(alias, '') <> ''
on conflict (ingredient_database_version, normalized_alias) do nothing;

with recursive expanded as (
  select s.food_version_id, e.value as ingredient, e.ordinality::int as position, 0 as depth,
         e.ordinality::text as ingredient_path, null::text as parent_name
  from public.pfqs_ingredient_snapshots s
  cross join lateral jsonb_array_elements(coalesce(s.parsed_ingredients, '[]'::jsonb)) with ordinality e(value, ordinality)
  union all
  select expanded.food_version_id, child.value, child.ordinality::int, expanded.depth + 1,
         expanded.ingredient_path || '.' || child.ordinality::text, lower(trim(expanded.ingredient->>'canonical_name'))
  from expanded
  cross join lateral jsonb_array_elements(coalesce(expanded.ingredient->'subingredients', '[]'::jsonb)) with ordinality child(value, ordinality)
)
insert into public.pfqs_food_ingredient_occurrences (
  food_version_id, ingredient_database_version, canonical_id, raw_text, canonical_name,
  parent_canonical_id, position, depth, percentage, ingredient_path
)
select food_version_id, 'PFQS-INGREDIENTS-2026-08-24',
       'ingredient_' || trim(both '_' from regexp_replace(lower(trim(ingredient->>'canonical_name')), '[^a-z0-9]+', '_', 'g')),
       coalesce(ingredient->>'raw', ingredient->>'name'), lower(trim(ingredient->>'canonical_name')),
       case when parent_name is null then null else 'ingredient_' || trim(both '_' from regexp_replace(parent_name, '[^a-z0-9]+', '_', 'g')) end,
       position, depth, nullif(ingredient->>'percentage', '')::numeric, ingredient_path
from expanded where coalesce(trim(ingredient->>'canonical_name'), '') <> ''
on conflict (food_version_id, ingredient_database_version, ingredient_path) do nothing;
