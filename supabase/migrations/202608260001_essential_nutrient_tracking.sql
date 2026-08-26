-- Essential nutrient expansion with source mappings and a versioned DRI reference.

alter table public.nutrient_definitions
  drop constraint if exists nutrient_definitions_nutrient_class_check;

alter table public.nutrient_definitions
  add constraint nutrient_definitions_nutrient_class_check check (nutrient_class in (
    'energy', 'macro', 'fat', 'carbohydrate', 'vitamin', 'mineral', 'amino_acid',
    'amino_acid_support', 'essential_fatty_acid', 'fiber', 'choline', 'other'
  )),
  add column if not exists is_displayed boolean not null default true,
  add column if not exists essentiality_note text;

update public.nutrient_definitions set nutrient_class = 'fiber' where code = 'fiber_g';
update public.nutrient_definitions set nutrient_class = 'choline' where code = 'choline_mg';

insert into public.nutrient_definitions
  (code, fdc_nutrient_id, name, unit, nutrient_class, display_order, target_kind, is_displayed, essentiality_note)
values
  ('sulfur_mg', 1094, 'Sulfur', 'mg', 'mineral', 405, 'informational', true,
   'No separate Dietary Reference Intake is established for sulfur.'),
  ('histidine_g', 1221, 'Histidine', 'g', 'amino_acid', 700, 'goal', true, null),
  ('isoleucine_g', 1212, 'Isoleucine', 'g', 'amino_acid', 710, 'goal', true, null),
  ('leucine_g', 1213, 'Leucine', 'g', 'amino_acid', 720, 'goal', true, null),
  ('lysine_g', 1214, 'Lysine', 'g', 'amino_acid', 730, 'goal', true, null),
  ('methionine_g', 1215, 'Methionine', 'g', 'amino_acid', 740, 'goal', true,
   'The Dietary Reference Intake is established for methionine plus cysteine.'),
  ('phenylalanine_g', 1217, 'Phenylalanine', 'g', 'amino_acid', 750, 'goal', true,
   'The Dietary Reference Intake is established for phenylalanine plus tyrosine.'),
  ('threonine_g', 1211, 'Threonine', 'g', 'amino_acid', 760, 'goal', true, null),
  ('tryptophan_g', 1210, 'Tryptophan', 'g', 'amino_acid', 770, 'goal', true, null),
  ('valine_g', 1219, 'Valine', 'g', 'amino_acid', 780, 'goal', true, null),
  ('cystine_g', 1216, 'Cystine', 'g', 'amino_acid_support', 790, 'informational', false, null),
  ('tyrosine_g', 1218, 'Tyrosine', 'g', 'amino_acid_support', 800, 'informational', false, null),
  ('linoleic_acid_g', 1316, 'Linoleic acid (LA, omega-6)', 'g', 'essential_fatty_acid', 810, 'goal', true, null),
  ('alpha_linolenic_acid_g', 1404, 'Alpha-linolenic acid (ALA, omega-3)', 'g', 'essential_fatty_acid', 820, 'goal', true, null)
on conflict (code) do update set
  fdc_nutrient_id = excluded.fdc_nutrient_id,
  name = excluded.name,
  unit = excluded.unit,
  nutrient_class = excluded.nutrient_class,
  display_order = excluded.display_order,
  target_kind = excluded.target_kind,
  is_displayed = excluded.is_displayed,
  essentiality_note = excluded.essentiality_note;

update public.nutrient_definitions set essentiality_note =
  'Chromium is tracked against the historical U.S. Adequate Intake, but its essential status and a deficiency state are not established.'
where code = 'chromium_mcg';

create table public.nutrient_source_mappings (
  source_system text not null,
  source_nutrient_id integer not null,
  nutrient_code text not null references public.nutrient_definitions(code) on delete cascade,
  priority integer not null default 100 check (priority > 0),
  primary key (source_system, source_nutrient_id)
);

insert into public.nutrient_source_mappings
  (source_system, source_nutrient_id, nutrient_code, priority)
values
  ('usda_fdc', 1094, 'sulfur_mg', 1),
  ('usda_fdc', 1221, 'histidine_g', 1), ('usda_fdc', 1212, 'isoleucine_g', 1),
  ('usda_fdc', 1213, 'leucine_g', 1), ('usda_fdc', 1214, 'lysine_g', 1),
  ('usda_fdc', 1215, 'methionine_g', 1), ('usda_fdc', 1217, 'phenylalanine_g', 1),
  ('usda_fdc', 1211, 'threonine_g', 1), ('usda_fdc', 1210, 'tryptophan_g', 1),
  ('usda_fdc', 1219, 'valine_g', 1), ('usda_fdc', 1216, 'cystine_g', 1),
  ('usda_fdc', 1218, 'tyrosine_g', 1),
  ('usda_fdc', 1316, 'linoleic_acid_g', 1), ('usda_fdc', 1269, 'linoleic_acid_g', 2),
  ('usda_fdc', 1404, 'alpha_linolenic_acid_g', 1), ('usda_fdc', 1270, 'alpha_linolenic_acid_g', 2)
on conflict (source_system, source_nutrient_id) do update set
  nutrient_code = excluded.nutrient_code, priority = excluded.priority;

alter table public.nutrient_source_mappings enable row level security;
create policy "users read nutrient source mappings"
  on public.nutrient_source_mappings for select to authenticated using (true);
grant select on public.nutrient_source_mappings to authenticated;
revoke insert, update, delete on public.nutrient_source_mappings from anon, authenticated;

insert into public.nutrient_reference_sets
  (code, name, population, source_url, effective_from)
values (
  'nasem_dri_adults_2026_1', 'National Academies Dietary Reference Intakes',
  'Adults personalized by age, calculation sex, and current weight where applicable',
  'https://ods.od.nih.gov/HealthInformation/nutrientrecommendations/', date '2026-08-26'
)
on conflict (code) do update set
  name = excluded.name, population = excluded.population,
  source_url = excluded.source_url, effective_from = excluded.effective_from;

-- Recover new USDA values already retained in raw source responses. When both a
-- specific fatty acid and its undifferentiated fallback exist, keep the specific value.
with candidates as (
  select
    fv.id as food_version_id,
    mapping.nutrient_code,
    nullif(value->>'amount', '')::numeric as amount_per_100g,
    mapping.priority,
    row_number() over (
      partition by fv.id, mapping.nutrient_code order by mapping.priority
    ) as preference
  from public.food_versions fv
  cross join lateral jsonb_array_elements(coalesce(fv.raw_source->'foodNutrients', '[]'::jsonb)) value
  join public.nutrient_source_mappings mapping
    on mapping.source_system = 'usda_fdc'
   and mapping.source_nutrient_id = coalesce(
     nullif(value->'nutrient'->>'id', '')::integer,
     nullif(value->>'nutrientId', '')::integer
   )
  where fv.source_system = 'usda_fdc'
)
insert into public.food_version_nutrients
  (food_version_id, nutrient_code, amount_per_100g, derivation_method, source_version, confidence)
select food_version_id, nutrient_code, amount_per_100g, 'label', 'usda_fdc:raw_backfill_2026_1', 1
from candidates
where preference = 1 and amount_per_100g is not null and amount_per_100g >= 0
on conflict (food_version_id, nutrient_code) do nothing;

-- Deterministically fill immutable intake snapshots from canonical food data.
insert into public.consumption_item_nutrients
  (consumption_item_id, nutrient_code, amount, derivation_method, source_version, confidence)
select
  ci.id, fvn.nutrient_code,
  round(fvn.amount_per_100g * ci.normalized_grams / 100, 6),
  fvn.derivation_method, fvn.source_version, fvn.confidence
from public.consumption_items ci
join public.food_version_nutrients fvn on fvn.food_version_id = ci.food_version_id
where ci.deleted_at is null and ci.normalized_grams > 0
  and fvn.nutrient_code in (
    'sulfur_mg', 'histidine_g', 'isoleucine_g', 'leucine_g', 'lysine_g',
    'methionine_g', 'phenylalanine_g', 'threonine_g', 'tryptophan_g', 'valine_g',
    'cystine_g', 'tyrosine_g', 'linoleic_acid_g', 'alpha_linolenic_acid_g'
  )
on conflict (consumption_item_id, nutrient_code) do nothing;

-- Requeue only entries still missing an expanded nutrient; the v2 worker fills
-- these lazily without replacing verified or previously recorded observations.
update public.nutrient_enrichment_jobs job set
  status = 'queued', attempts = 0, next_attempt_at = now(), model_version = null,
  last_error = null, started_at = null, completed_at = null, updated_at = now()
where exists (
  select 1 from public.consumption_items ci
  where ci.id = job.consumption_item_id and ci.deleted_at is null
)
and exists (
  select 1 from public.nutrient_definitions nd
  where nd.code in (
    'sulfur_mg', 'histidine_g', 'isoleucine_g', 'leucine_g', 'lysine_g',
    'methionine_g', 'phenylalanine_g', 'threonine_g', 'tryptophan_g', 'valine_g',
    'cystine_g', 'tyrosine_g', 'linoleic_acid_g', 'alpha_linolenic_acid_g'
  )
  and not exists (
    select 1 from public.consumption_item_nutrients cin
    where cin.consumption_item_id = job.consumption_item_id and cin.nutrient_code = nd.code
  )
);
