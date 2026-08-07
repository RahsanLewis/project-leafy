-- Daily macro and micronutrient tracking. Nutrient observations remain attached
-- to immutable consumption snapshots while reference targets are versioned.

alter table public.nutrient_definitions
  add column if not exists display_order integer not null default 1000,
  add column if not exists target_kind text not null default 'informational'
    check (target_kind in ('goal', 'limit', 'informational'));

insert into public.nutrient_definitions
  (code, fdc_nutrient_id, name, unit, nutrient_class, display_order, target_kind)
values
  ('vitamin_a_mcg_rae', 1106, 'Vitamin A', 'mcg RAE', 'vitamin', 100, 'goal'),
  ('vitamin_c_mg', 1162, 'Vitamin C', 'mg', 'vitamin', 110, 'goal'),
  ('vitamin_e_mg', 1109, 'Vitamin E', 'mg', 'vitamin', 130, 'goal'),
  ('vitamin_k_mcg', 1185, 'Vitamin K', 'mcg', 'vitamin', 140, 'goal'),
  ('thiamin_mg', 1165, 'Thiamin', 'mg', 'vitamin', 150, 'goal'),
  ('riboflavin_mg', 1166, 'Riboflavin', 'mg', 'vitamin', 160, 'goal'),
  ('niacin_mg_ne', 1167, 'Niacin', 'mg NE', 'vitamin', 170, 'goal'),
  ('vitamin_b6_mg', 1175, 'Vitamin B6', 'mg', 'vitamin', 180, 'goal'),
  ('folate_mcg_dfe', 1177, 'Folate', 'mcg DFE', 'vitamin', 190, 'goal'),
  ('vitamin_b12_mcg', 1178, 'Vitamin B12', 'mcg', 'vitamin', 200, 'goal'),
  ('biotin_mcg', 1176, 'Biotin', 'mcg', 'vitamin', 210, 'goal'),
  ('pantothenic_acid_mg', 1170, 'Pantothenic acid', 'mg', 'vitamin', 220, 'goal'),
  ('phosphorus_mg', 1091, 'Phosphorus', 'mg', 'mineral', 310, 'goal'),
  ('iodine_mcg', 1100, 'Iodine', 'mcg', 'mineral', 320, 'goal'),
  ('zinc_mg', 1095, 'Zinc', 'mg', 'mineral', 340, 'goal'),
  ('selenium_mcg', 1103, 'Selenium', 'mcg', 'mineral', 350, 'goal'),
  ('copper_mg', 1098, 'Copper', 'mg', 'mineral', 360, 'goal'),
  ('manganese_mg', 1101, 'Manganese', 'mg', 'mineral', 370, 'goal'),
  ('chromium_mcg', 1096, 'Chromium', 'mcg', 'mineral', 380, 'goal'),
  ('molybdenum_mcg', 1102, 'Molybdenum', 'mcg', 'mineral', 390, 'goal'),
  ('chloride_mg', 1088, 'Chloride', 'mg', 'mineral', 400, 'goal'),
  ('choline_mg', 1180, 'Choline', 'mg', 'other', 410, 'goal')
on conflict (code) do update set
  fdc_nutrient_id = excluded.fdc_nutrient_id,
  name = excluded.name,
  unit = excluded.unit,
  nutrient_class = excluded.nutrient_class,
  display_order = excluded.display_order,
  target_kind = excluded.target_kind;

update public.nutrient_definitions set display_order = case code
  when 'energy_kcal' then 0 when 'protein_g' then 10 when 'carbohydrate_g' then 20
  when 'fat_g' then 30 when 'fiber_g' then 40 when 'vitamin_d_mcg' then 120
  when 'calcium_mg' then 300 when 'iron_mg' then 330 when 'magnesium_mg' then 335
  when 'potassium_mg' then 420 when 'saturated_fat_g' then 500
  when 'sodium_mg' then 510 when 'added_sugars_g' then 520 when 'cholesterol_mg' then 530
  when 'sugars_g' then 600 when 'trans_fat_g' then 610 when 'water_g' then 620
  when 'caffeine_mg' then 630 when 'alcohol_g' then 640 else display_order end,
  target_kind = case
    when code in ('saturated_fat_g','sodium_mg','added_sugars_g','cholesterol_mg') then 'limit'
    when code in ('energy_kcal','sugars_g','trans_fat_g','water_g','caffeine_mg','alcohol_g') then 'informational'
    else 'goal' end;

create table public.nutrient_reference_sets (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  population text not null,
  source_url text not null,
  effective_from date not null,
  created_at timestamptz not null default now()
);

create table public.nutrient_reference_values (
  reference_set_id uuid not null references public.nutrient_reference_sets(id) on delete cascade,
  nutrient_code text not null references public.nutrient_definitions(code),
  amount numeric(14,6) not null check (amount > 0),
  primary key (reference_set_id, nutrient_code)
);

with reference as (
  insert into public.nutrient_reference_sets
    (code, name, population, source_url, effective_from)
  values (
    'fda_adults_4_plus_2020', 'FDA Daily Values', 'Adults and children age 4 and older',
    'https://www.fda.gov/food/nutrition-facts-label/daily-value-nutrition-and-supplement-facts-labels',
    date '2020-01-01'
  ) on conflict (code) do update set name = excluded.name
  returning id
)
insert into public.nutrient_reference_values (reference_set_id, nutrient_code, amount)
select reference.id, values.code, values.amount from reference cross join (values
  ('protein_g',50::numeric), ('carbohydrate_g',275), ('fat_g',78), ('fiber_g',28),
  ('added_sugars_g',50), ('saturated_fat_g',20), ('cholesterol_mg',300), ('sodium_mg',2300),
  ('potassium_mg',4700), ('calcium_mg',1300), ('iron_mg',18), ('magnesium_mg',420),
  ('vitamin_d_mcg',20), ('vitamin_a_mcg_rae',900), ('vitamin_c_mg',90), ('vitamin_e_mg',15),
  ('vitamin_k_mcg',120), ('thiamin_mg',1.2), ('riboflavin_mg',1.3), ('niacin_mg_ne',16),
  ('vitamin_b6_mg',1.7), ('folate_mcg_dfe',400), ('vitamin_b12_mcg',2.4), ('biotin_mcg',30),
  ('pantothenic_acid_mg',5), ('phosphorus_mg',1250), ('iodine_mcg',150), ('zinc_mg',11),
  ('selenium_mcg',55), ('copper_mg',0.9), ('manganese_mg',2.3), ('chromium_mcg',35),
  ('molybdenum_mcg',45), ('chloride_mg',2300), ('choline_mg',550)
) as values(code, amount)
on conflict (reference_set_id, nutrient_code) do update set amount = excluded.amount;

create table public.ai_meal_item_nutrients (
  ai_meal_item_id uuid not null references public.ai_meal_items(id) on delete cascade,
  nutrient_code text not null references public.nutrient_definitions(code),
  predicted_amount numeric(14,6) not null check (predicted_amount >= 0),
  confidence numeric(5,4) not null check (confidence between 0 and 1),
  confirmed_amount numeric(14,6) check (confirmed_amount >= 0),
  primary key (ai_meal_item_id, nutrient_code)
);

create or replace function public.replace_food_entry_nutrients(
  p_user_id uuid,
  p_food_entry_id uuid,
  p_nutrients jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare
  item_id uuid;
  nutrient jsonb;
begin
  select ci.id into item_id
  from public.consumption_items ci
  join public.food_entries fe on fe.id = ci.legacy_food_entry_id
  where fe.id = p_food_entry_id and fe.user_id = p_user_id;
  if item_id is null then raise exception 'Food entry not found'; end if;
  if jsonb_typeof(p_nutrients) <> 'array' then raise exception 'Nutrients must be an array'; end if;

  delete from public.consumption_item_nutrients
  where consumption_item_id = item_id and nutrient_code <> 'energy_kcal';

  for nutrient in select value from jsonb_array_elements(p_nutrients)
  loop
    if not exists (select 1 from public.nutrient_definitions where code = nutrient->>'code') then
      raise exception 'Unsupported nutrient code';
    end if;
    insert into public.consumption_item_nutrients (
      consumption_item_id, nutrient_code, amount, derivation_method, source_version, confidence
    ) values (
      item_id, nutrient->>'code', greatest(0, (nutrient->>'amount')::numeric),
      coalesce(nutrient->>'derivation_method', 'user_entered'),
      nullif(nutrient->>'source_version', ''),
      nullif(nutrient->>'confidence', '')::numeric
    ) on conflict (consumption_item_id, nutrient_code) do update set
      amount = excluded.amount, derivation_method = excluded.derivation_method,
      source_version = excluded.source_version, confidence = excluded.confidence;
  end loop;
end;
$$;

revoke all on function public.replace_food_entry_nutrients(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.replace_food_entry_nutrients(uuid, uuid, jsonb) to service_role;

alter table public.nutrient_reference_sets enable row level security;
alter table public.nutrient_reference_values enable row level security;
alter table public.ai_meal_item_nutrients enable row level security;
create policy "users read nutrient reference sets" on public.nutrient_reference_sets for select to authenticated using (true);
create policy "users read nutrient reference values" on public.nutrient_reference_values for select to authenticated using (true);
create policy "users read own ai meal nutrients" on public.ai_meal_item_nutrients for select to authenticated using (exists (
  select 1 from public.ai_meal_items i join public.ai_meal_sessions s on s.id = i.session_id
  where i.id = ai_meal_item_id and s.user_id = (select auth.uid())
));
grant select on public.nutrient_reference_sets, public.nutrient_reference_values, public.ai_meal_item_nutrients to authenticated;
revoke insert, update, delete on public.nutrient_reference_sets, public.nutrient_reference_values,
  public.ai_meal_item_nutrients from anon, authenticated;
