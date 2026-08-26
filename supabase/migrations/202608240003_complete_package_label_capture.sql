-- Preserve complete package-label evidence, including volume servings and
-- nutrients declared in Nutrition Facts footnotes.

alter table public.catalog_contribution_nutrients
  add column if not exists declaration_type text not null default 'quantified'
    check (declaration_type in ('quantified', 'declared_zero', 'not_significant_source', 'derived')),
  add column if not exists printed_text text,
  add column if not exists evidence_section text;

alter table public.food_versions
  add column if not exists servings_per_container text,
  add column if not exists metric_serving_size numeric(12,4),
  add column if not exists metric_serving_unit text,
  add column if not exists package_claims jsonb not null default '[]'::jsonb
    check (jsonb_typeof(package_claims) = 'array'),
  add column if not exists label_sections jsonb not null default '{}'::jsonb
    check (jsonb_typeof(label_sections) = 'object');

create table if not exists public.food_version_serving_nutrients (
  food_version_id uuid not null references public.food_versions(id) on delete cascade,
  nutrient_code text not null references public.nutrient_definitions(code),
  amount_per_serving numeric(14,6) not null check (amount_per_serving >= 0),
  unit text not null,
  percent_daily_value numeric(8,3) check (percent_daily_value is null or percent_daily_value >= 0),
  declaration_type text not null default 'quantified'
    check (declaration_type in ('quantified', 'declared_zero', 'not_significant_source', 'derived')),
  printed_text text,
  evidence_section text,
  primary key (food_version_id, nutrient_code)
);

alter table public.food_version_serving_nutrients enable row level security;
drop policy if exists "users read food serving nutrients" on public.food_version_serving_nutrients;
create policy "users read food serving nutrients" on public.food_version_serving_nutrients
  for select to authenticated using (true);
grant select on public.food_version_serving_nutrients to authenticated;
revoke insert, update, delete on public.food_version_serving_nutrients from anon, authenticated;

