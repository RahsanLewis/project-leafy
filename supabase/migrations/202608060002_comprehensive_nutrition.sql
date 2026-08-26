-- Leafy's normalized, provenance-first nutrition data foundation.
-- The existing food_entries table remains the compatibility write API.

create extension if not exists pgcrypto with schema extensions;

create table public.consent_documents (
  id uuid primary key default gen_random_uuid(),
  document_key text not null,
  version integer not null check (version > 0),
  jurisdiction text not null default 'global',
  title text not null,
  body text not null,
  content_hash text not null,
  effective_at timestamptz not null,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  unique (document_key, version, jurisdiction)
);

insert into public.consent_documents (
  document_key, version, jurisdiction, title, body, content_hash, effective_at
) values (
  'commercial_nutrition_dataset', 1, 'global', 'Leafy nutrition data program',
  'Joining is optional. Leafy may make coded nutrition and energy-balance records available to lawful buyers in a controlled data environment. Direct account identifiers, original photos, and HealthKit or Health Connect data are excluded. You may withdraw from future access at any time without losing access to Leafy.',
  '1391596c7c4f7491b3f5613e31434db8f6c57e7355637b9f33df8ca122bce43a',
  '2026-08-06T00:00:00Z'
);

create table public.consent_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id uuid not null references public.consent_documents(id),
  purpose text not null check (purpose in ('personalization', 'commercial_dataset', 'medical_research')),
  jurisdiction_country text not null check (char_length(jurisdiction_country) = 2),
  jurisdiction_region text,
  data_scopes jsonb not null default '[]'::jsonb check (jsonb_typeof(data_scopes) = 'array'),
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  signature_hash text not null,
  created_at timestamptz not null default now(),
  check (expires_at is null or expires_at > granted_at),
  check (revoked_at is null or revoked_at >= granted_at)
);

create unique index consent_grants_one_active_purpose_idx
  on public.consent_grants(user_id, purpose) where revoked_at is null;

create table public.research_subjects (
  user_id uuid primary key references auth.users(id) on delete cascade,
  participant_id uuid not null default gen_random_uuid() unique,
  created_at timestamptz not null default now()
);

create table public.data_buyers (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null,
  contact_name text not null,
  contact_email text not null,
  country_code text not null check (char_length(country_code) = 2),
  status text not null default 'pending' check (status in ('pending', 'approved', 'suspended', 'closed')),
  created_at timestamptz not null default now()
);

create table public.data_projects (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.data_buyers(id),
  name text not null,
  declared_purpose text not null,
  requested_scopes jsonb not null check (jsonb_typeof(requested_scopes) = 'array'),
  starts_on date not null,
  ends_on date not null,
  status text not null default 'draft' check (status in ('draft', 'authorizing', 'active', 'expired', 'revoked')),
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create table public.jurisdiction_data_rules (
  country_code text not null check (char_length(country_code) = 2),
  region_code text not null default '',
  buyer_specific_authorization_required boolean not null default false,
  policy_reference text not null,
  effective_from date not null,
  reviewed_at timestamptz not null default now(),
  primary key (country_code, region_code)
);

insert into public.jurisdiction_data_rules (
  country_code, region_code, buyer_specific_authorization_required, policy_reference, effective_from
) values ('US', 'WA', true, 'RCW 19.373.070', '2024-03-31');

create table public.sale_authorizations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.data_projects(id),
  consent_grant_id uuid not null references public.consent_grants(id),
  authorized_scopes jsonb not null check (jsonb_typeof(authorized_scopes) = 'array'),
  jurisdiction_country text not null check (char_length(jurisdiction_country) = 2),
  jurisdiction_region text,
  signed_at timestamptz not null,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  signature_hash text not null,
  authorization_snapshot jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, project_id),
  check (expires_at > signed_at),
  check (expires_at <= signed_at + interval '1 year'),
  check (revoked_at is null or revoked_at >= signed_at)
);

create table public.nutrient_definitions (
  code text primary key,
  fdc_nutrient_id integer unique,
  name text not null,
  unit text not null,
  nutrient_class text not null check (nutrient_class in ('energy', 'macro', 'fat', 'carbohydrate', 'vitamin', 'mineral', 'other')),
  created_at timestamptz not null default now()
);

insert into public.nutrient_definitions (code, fdc_nutrient_id, name, unit, nutrient_class) values
  ('energy_kcal', 1008, 'Energy', 'kcal', 'energy'),
  ('protein_g', 1003, 'Protein', 'g', 'macro'),
  ('carbohydrate_g', 1005, 'Carbohydrate', 'g', 'macro'),
  ('fat_g', 1004, 'Total fat', 'g', 'macro'),
  ('fiber_g', 1079, 'Dietary fiber', 'g', 'carbohydrate'),
  ('sugars_g', 2000, 'Total sugars', 'g', 'carbohydrate'),
  ('added_sugars_g', 1235, 'Added sugars', 'g', 'carbohydrate'),
  ('saturated_fat_g', 1258, 'Saturated fat', 'g', 'fat'),
  ('trans_fat_g', 1257, 'Trans fat', 'g', 'fat'),
  ('cholesterol_mg', 1253, 'Cholesterol', 'mg', 'other'),
  ('sodium_mg', 1093, 'Sodium', 'mg', 'mineral'),
  ('potassium_mg', 1092, 'Potassium', 'mg', 'mineral'),
  ('calcium_mg', 1087, 'Calcium', 'mg', 'mineral'),
  ('iron_mg', 1089, 'Iron', 'mg', 'mineral'),
  ('magnesium_mg', 1090, 'Magnesium', 'mg', 'mineral'),
  ('vitamin_d_mcg', 1114, 'Vitamin D', 'mcg', 'vitamin'),
  ('caffeine_mg', 1057, 'Caffeine', 'mg', 'other'),
  ('alcohol_g', 1018, 'Alcohol', 'g', 'other'),
  ('water_g', 1051, 'Water', 'g', 'other')
on conflict (code) do nothing;

create table public.foods (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  category_code text,
  category_system text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.food_versions (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  source_system text not null check (source_system in ('usda_fdc', 'manufacturer', 'leafy', 'user_recipe', 'import')),
  source_record_id text not null,
  source_data_type text,
  description text not null,
  brand_name text,
  gtin text,
  market_country text,
  ingredients_text text,
  allergens jsonb not null default '[]'::jsonb check (jsonb_typeof(allergens) = 'array'),
  published_at timestamptz,
  effective_from timestamptz not null default now(),
  superseded_at timestamptz,
  raw_source jsonb,
  created_at timestamptz not null default now(),
  unique (source_system, source_record_id, effective_from)
);

create index food_versions_gtin_idx on public.food_versions(gtin) where gtin is not null;
create index food_versions_food_effective_idx on public.food_versions(food_id, effective_from desc);

create table public.food_version_nutrients (
  food_version_id uuid not null references public.food_versions(id) on delete cascade,
  nutrient_code text not null references public.nutrient_definitions(code),
  amount_per_100g numeric(14,6) not null check (amount_per_100g >= 0),
  derivation_method text not null check (derivation_method in ('laboratory', 'label', 'calculated', 'estimated', 'user_entered')),
  min_amount numeric(14,6),
  max_amount numeric(14,6),
  primary key (food_version_id, nutrient_code),
  check (min_amount is null or min_amount >= 0),
  check (max_amount is null or max_amount >= coalesce(min_amount, 0))
);

create table public.food_portions (
  id uuid primary key default gen_random_uuid(),
  food_version_id uuid not null references public.food_versions(id) on delete cascade,
  amount numeric(12,4) not null check (amount > 0),
  unit text not null,
  description text,
  gram_weight numeric(12,4) not null check (gram_weight > 0),
  source text not null,
  created_at timestamptz not null default now()
);

create table public.eating_occasions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  occasion_type text not null default 'unspecified'
    check (occasion_type in ('breakfast', 'lunch', 'dinner', 'snack', 'drink', 'supplement', 'unspecified')),
  started_at timestamptz not null,
  local_date date not null,
  time_zone text not null check (char_length(time_zone) between 1 and 80),
  place_category text check (place_category in ('home', 'restaurant', 'work', 'school', 'travel', 'other')),
  unusualness text check (unusualness in ('less', 'usual', 'more')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index eating_occasions_user_date_idx on public.eating_occasions(user_id, local_date, started_at);

create table public.consumption_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  occasion_id uuid not null references public.eating_occasions(id) on delete cascade,
  food_version_id uuid references public.food_versions(id),
  legacy_food_entry_id uuid unique references public.food_entries(id) on delete cascade,
  description text not null check (char_length(btrim(description)) between 1 and 240),
  original_amount numeric(12,4) check (original_amount > 0),
  original_unit text,
  normalized_grams numeric(12,4) check (normalized_grams > 0),
  portion_description text,
  calories_kcal integer not null check (calories_kcal between 0 and 10000),
  preparation text,
  fraction_consumed numeric(6,5) check (fraction_consumed > 0 and fraction_consumed <= 1),
  entry_source text not null,
  calorie_method text not null,
  origin_system text not null default 'leafy',
  source_record_id text,
  source_version text,
  model_version text,
  confidence numeric(5,4) check (confidence between 0 and 1),
  user_confirmed boolean not null default false,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance) = 'object'),
  pii_scan_status text not null default 'pending'
    check (pii_scan_status in ('pending', 'approved', 'rejected')),
  revision integer not null default 1 check (revision > 0),
  supersedes_id uuid references public.consumption_items(id),
  commercial_eligible boolean not null default false,
  consent_grant_id uuid references public.consent_grants(id) on delete set null,
  valid_from timestamptz not null default now(),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (commercial_eligible = false or consent_grant_id is not null),
  check (origin_system not in ('healthkit', 'health_connect') or commercial_eligible = false)
);

create index consumption_items_user_occasion_idx on public.consumption_items(user_id, occasion_id);
create index consumption_items_commercial_idx on public.consumption_items(commercial_eligible, consent_grant_id)
  where commercial_eligible = true and deleted_at is null;

create table public.consumption_item_nutrients (
  consumption_item_id uuid not null references public.consumption_items(id) on delete cascade,
  nutrient_code text not null references public.nutrient_definitions(code),
  amount numeric(14,6) not null check (amount >= 0),
  derivation_method text not null check (derivation_method in ('laboratory', 'label', 'calculated', 'estimated', 'user_entered')),
  source_version text,
  confidence numeric(5,4) check (confidence between 0 and 1),
  primary key (consumption_item_id, nutrient_code)
);

create table public.nutrition_media_assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  consumption_item_id uuid references public.consumption_items(id) on delete cascade,
  parent_asset_id uuid references public.nutrition_media_assets(id) on delete cascade,
  asset_kind text not null check (asset_kind in ('meal_photo', 'label_photo', 'receipt_photo', 'derived_food_crop')),
  object_path text not null unique,
  content_hash text not null,
  mime_type text not null,
  byte_count bigint not null check (byte_count > 0),
  metadata_stripped boolean not null default false,
  redaction_status text not null default 'not_scanned'
    check (redaction_status in ('not_scanned', 'pending', 'approved', 'rejected')),
  commercial_eligible boolean not null default false,
  consent_grant_id uuid references public.consent_grants(id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (asset_kind = 'derived_food_crop' or commercial_eligible = false),
  check (commercial_eligible = false or (metadata_stripped and redaction_status = 'approved' and consent_grant_id is not null))
);

create table public.data_access_audit (
  id bigint generated always as identity primary key,
  project_id uuid not null references public.data_projects(id),
  actor_id text not null,
  action text not null,
  query_hash text,
  row_count bigint,
  occurred_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb
);

create or replace function public.commercial_project_dataset(p_project_id uuid)
returns table (
  project_subject_id text,
  consumed_at timestamptz,
  local_date date,
  meal_type text,
  food_description text,
  food_version_id uuid,
  amount numeric,
  amount_unit text,
  gram_weight numeric,
  calories_kcal integer,
  entry_source text,
  calorie_method text,
  confidence numeric,
  nutrients jsonb,
  weight_kg numeric,
  intake_day_status text
)
language plpgsql security definer set search_path = '' as $$
declare
  exported_count bigint;
begin
  if not exists (
    select 1 from public.data_projects p join public.data_buyers b on b.id = p.buyer_id
    where p.id = p_project_id and p.status = 'active' and b.status = 'approved'
      and current_date between p.starts_on and p.ends_on
  ) then raise exception 'Project is not active'; end if;

  return query
  with eligible as (
    select ci.*, eo.started_at, eo.local_date as occasion_date, eo.occasion_type,
      cg.jurisdiction_country, cg.jurisdiction_region, rs.participant_id,
      ((get_byte(extensions.digest(rs.participant_id::text || p_project_id::text, 'sha256'), 0) % 61) - 30)::integer as shift_days
    from public.consumption_items ci
    join public.eating_occasions eo on eo.id = ci.occasion_id
    join public.consent_grants cg on cg.id = ci.consent_grant_id
    join public.research_subjects rs on rs.user_id = ci.user_id
    where ci.commercial_eligible and ci.deleted_at is null
      and ci.pii_scan_status = 'approved'
      and ci.origin_system not in ('healthkit', 'health_connect')
      and cg.purpose = 'commercial_dataset' and cg.revoked_at is null
      and (cg.expires_at is null or cg.expires_at > now())
      and not exists (
        select 1 from public.jurisdiction_data_rules jr
        where jr.country_code = cg.jurisdiction_country
          and jr.region_code in ('', coalesce(cg.jurisdiction_region, ''))
          and jr.buyer_specific_authorization_required
          and not exists (
            select 1 from public.sale_authorizations sa
            where sa.user_id = ci.user_id and sa.project_id = p_project_id
              and sa.revoked_at is null and now() between sa.signed_at and sa.expires_at
          )
      )
  )
  select
    encode(extensions.hmac(e.participant_id::text, p_project_id::text, 'sha256'), 'hex'),
    e.started_at + make_interval(days => e.shift_days),
    e.occasion_date + e.shift_days,
    e.occasion_type,
    coalesce(fv.description, e.description),
    e.food_version_id,
    e.original_amount,
    e.original_unit,
    e.normalized_grams,
    e.calories_kcal,
    e.entry_source,
    e.calorie_method,
    e.confidence,
    coalesce((
      select jsonb_object_agg(cin.nutrient_code, cin.amount)
      from public.consumption_item_nutrients cin where cin.consumption_item_id = e.id
    ), '{}'::jsonb),
    (select we.weight_kg from public.weight_entries we
      where we.user_id = e.user_id and we.recorded_on <= e.occasion_date
      order by we.recorded_on desc limit 1),
    (select did.status::text from public.daily_intake_days did
      where did.user_id = e.user_id and did.local_date = e.occasion_date)
  from eligible e
  left join public.food_versions fv on fv.id = e.food_version_id;

  get diagnostics exported_count = row_count;
  insert into public.data_access_audit(project_id, actor_id, action, row_count)
  values (p_project_id, current_user, 'dataset_query', exported_count);
end;
$$;

revoke all on function public.commercial_project_dataset(uuid) from public, anon, authenticated;
grant execute on function public.commercial_project_dataset(uuid) to service_role;

alter table public.food_entries
  add column amount numeric(12,4) check (amount > 0),
  add column amount_unit text,
  add column gram_weight numeric(12,4) check (gram_weight > 0),
  add column portion_description text,
  add column meal_type text not null default 'unspecified'
    check (meal_type in ('breakfast', 'lunch', 'dinner', 'snack', 'drink', 'supplement', 'unspecified')),
  add column canonical_food_version_id uuid references public.food_versions(id),
  add column confidence numeric(5,4) check (confidence between 0 and 1),
  add column user_confirmed boolean not null default false,
  add column provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance) = 'object');

create or replace function public.sync_food_entry_to_consumption()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  item_id uuid;
  active_grant uuid;
begin
  if tg_op = 'DELETE' then
    delete from public.eating_occasions where id = old.id and user_id = old.user_id;
    return old;
  end if;

  select id into active_grant from public.consent_grants
  where user_id = new.user_id and purpose = 'commercial_dataset'
    and revoked_at is null and granted_at <= now()
    and (expires_at is null or expires_at > now())
  order by granted_at desc limit 1;

  insert into public.eating_occasions (
    id, user_id, occasion_type, started_at, local_date, time_zone, created_at, updated_at
  ) values (
    new.id, new.user_id, new.meal_type, new.consumed_at, new.local_date, new.time_zone, new.created_at, new.updated_at
  ) on conflict (id) do update set
    occasion_type = excluded.occasion_type, started_at = excluded.started_at,
    local_date = excluded.local_date, time_zone = excluded.time_zone, updated_at = excluded.updated_at;

  insert into public.consumption_items (
    user_id, occasion_id, food_version_id, legacy_food_entry_id, description,
    original_amount, original_unit, normalized_grams, portion_description, calories_kcal,
    entry_source, calorie_method, confidence, user_confirmed, provenance,
    commercial_eligible, consent_grant_id, created_at, updated_at
  ) values (
    new.user_id, new.id, new.canonical_food_version_id, new.id, new.name,
    new.amount, new.amount_unit, new.gram_weight, new.portion_description, new.calories,
    new.entry_source, new.calorie_method, new.confidence, new.user_confirmed, new.provenance,
    active_grant is not null, active_grant, new.created_at, new.updated_at
  ) on conflict (legacy_food_entry_id) do update set
    food_version_id = excluded.food_version_id, description = excluded.description,
    original_amount = excluded.original_amount, original_unit = excluded.original_unit,
    normalized_grams = excluded.normalized_grams, portion_description = excluded.portion_description,
    calories_kcal = excluded.calories_kcal, entry_source = excluded.entry_source,
    calorie_method = excluded.calorie_method, confidence = excluded.confidence,
    user_confirmed = excluded.user_confirmed, provenance = excluded.provenance,
    revision = public.consumption_items.revision + 1, updated_at = excluded.updated_at
  returning id into item_id;

  insert into public.consumption_item_nutrients (
    consumption_item_id, nutrient_code, amount, derivation_method, confidence
  ) values (
    item_id, 'energy_kcal', new.calories,
    case when new.calorie_method = 'nutrition_database' then 'calculated'
         when new.calorie_method = 'estimated' then 'estimated'
         else 'user_entered' end,
    new.confidence
  ) on conflict (consumption_item_id, nutrient_code) do update set
    amount = excluded.amount, derivation_method = excluded.derivation_method,
    confidence = excluded.confidence;
  return new;
end;
$$;

create trigger sync_food_entry_to_consumption_after_change
after insert or update or delete on public.food_entries
for each row execute function public.sync_food_entry_to_consumption();

insert into public.eating_occasions (
  id, user_id, occasion_type, started_at, local_date, time_zone, created_at, updated_at
)
select id, user_id, meal_type, consumed_at, local_date, time_zone, created_at, updated_at
from public.food_entries on conflict (id) do nothing;

insert into public.consumption_items (
  user_id, occasion_id, food_version_id, legacy_food_entry_id, description,
  original_amount, original_unit, normalized_grams, portion_description, calories_kcal,
  entry_source, calorie_method, confidence, user_confirmed, provenance, created_at, updated_at
)
select user_id, id, canonical_food_version_id, id, name, amount, amount_unit, gram_weight,
  portion_description, calories, entry_source, calorie_method, confidence, user_confirmed,
  provenance, created_at, updated_at
from public.food_entries on conflict (legacy_food_entry_id) do nothing;

insert into public.consumption_item_nutrients (
  consumption_item_id, nutrient_code, amount, derivation_method, confidence
)
select ci.id, 'energy_kcal', fe.calories,
  case when fe.calorie_method = 'nutrition_database' then 'calculated'
       when fe.calorie_method = 'estimated' then 'estimated'
       else 'user_entered' end,
  fe.confidence
from public.consumption_items ci
join public.food_entries fe on fe.id = ci.legacy_food_entry_id
on conflict (consumption_item_id, nutrient_code) do nothing;

insert into public.research_subjects (user_id)
select user_id from public.profiles on conflict (user_id) do nothing;

create or replace function public.seed_research_subject()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.research_subjects(user_id) values (new.user_id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger seed_research_subject_after_profile
after insert on public.profiles for each row execute function public.seed_research_subject();

alter table public.consent_documents enable row level security;
alter table public.consent_grants enable row level security;
alter table public.research_subjects enable row level security;
alter table public.data_buyers enable row level security;
alter table public.data_projects enable row level security;
alter table public.jurisdiction_data_rules enable row level security;
alter table public.sale_authorizations enable row level security;
alter table public.nutrient_definitions enable row level security;
alter table public.foods enable row level security;
alter table public.food_versions enable row level security;
alter table public.food_version_nutrients enable row level security;
alter table public.food_portions enable row level security;
alter table public.eating_occasions enable row level security;
alter table public.consumption_items enable row level security;
alter table public.consumption_item_nutrients enable row level security;
alter table public.nutrition_media_assets enable row level security;
alter table public.data_access_audit enable row level security;

create policy "users read consent documents" on public.consent_documents
  for select to authenticated using (retired_at is null);
create policy "users read own consent grants" on public.consent_grants
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "users read own sale authorizations" on public.sale_authorizations
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "users read nutrient definitions" on public.nutrient_definitions
  for select to authenticated using (true);
create policy "users read food catalog" on public.foods
  for select to authenticated using (true);
create policy "users read food versions" on public.food_versions
  for select to authenticated using (true);
create policy "users read food nutrients" on public.food_version_nutrients
  for select to authenticated using (true);
create policy "users read food portions" on public.food_portions
  for select to authenticated using (true);
create policy "users read own eating occasions" on public.eating_occasions
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "users read own consumption items" on public.consumption_items
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "users read own consumption nutrients" on public.consumption_item_nutrients
  for select to authenticated using (exists (
    select 1 from public.consumption_items ci
    where ci.id = consumption_item_id and ci.user_id = (select auth.uid())
  ));
create policy "users read own nutrition media" on public.nutrition_media_assets
  for select to authenticated using ((select auth.uid()) = user_id);

grant select on public.consent_documents, public.consent_grants, public.sale_authorizations,
  public.nutrient_definitions, public.foods, public.food_versions, public.food_version_nutrients,
  public.food_portions, public.eating_occasions, public.consumption_items,
  public.consumption_item_nutrients, public.nutrition_media_assets to authenticated;

revoke insert, update, delete on public.consent_documents, public.consent_grants,
  public.research_subjects, public.data_buyers, public.data_projects, public.sale_authorizations,
  public.jurisdiction_data_rules,
  public.nutrient_definitions, public.foods, public.food_versions, public.food_version_nutrients,
  public.food_portions, public.eating_occasions, public.consumption_items,
  public.consumption_item_nutrients, public.nutrition_media_assets, public.data_access_audit
  from anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('nutrition-media', 'nutrition-media', false, 15728640, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

create policy "users read own nutrition objects" on storage.objects
  for select to authenticated using (
    bucket_id = 'nutrition-media' and (storage.foldername(name))[1] = (select auth.uid())::text
  );
create policy "users upload own nutrition objects" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'nutrition-media' and (storage.foldername(name))[1] = (select auth.uid())::text
  );
create policy "users delete own nutrition objects" on storage.objects
  for delete to authenticated using (
    bucket_id = 'nutrition-media' and (storage.foldername(name))[1] = (select auth.uid())::text
  );
