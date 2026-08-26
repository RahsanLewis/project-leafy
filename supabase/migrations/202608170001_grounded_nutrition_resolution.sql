-- Item-level provenance for reproducible, web-grounded nutrition resolution.

alter table public.ai_meal_sessions
  add column if not exists market_country text not null default 'US' check (char_length(market_country) = 2);

alter table public.ai_meal_items
  drop constraint if exists ai_meal_items_resolution_source_check;

alter table public.ai_meal_items
  add constraint ai_meal_items_resolution_source_check
    check (resolution_source in ('official', 'manufacturer', 'restaurant', 'leafy_catalog', 'usda', 'secondary', 'ai')),
  add column if not exists nutrition_basis text not null default 'ai_estimate'
    check (nutrition_basis in ('official', 'usda', 'leafy_catalog', 'secondary', 'ai_estimate')),
  add column if not exists market_country text not null default 'US' check (char_length(market_country) = 2),
  add column if not exists source_title text,
  add column if not exists source_url text,
  add column if not exists source_kind text
    check (source_kind is null or source_kind in ('manufacturer', 'restaurant', 'usda', 'leafy_catalog', 'database', 'retailer', 'other')),
  add column if not exists exact_source_match boolean not null default false,
  add column if not exists retrieved_at timestamptz;

create index if not exists ai_meal_items_source_url_idx
  on public.ai_meal_items(source_url) where source_url is not null;
