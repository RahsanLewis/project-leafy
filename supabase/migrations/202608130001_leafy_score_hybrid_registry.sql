-- Installs the expanded hybrid registry schema as a new draft release. The
-- currently active algorithm remains unchanged until benchmark and expert gates pass.
alter table public.food_additive_registry
  add column if not exists fda_status text check (fda_status in ('listed', 'active_review', 'federal_action')),
  add column if not exists processing_class text check (processing_class in (
    'artificial_colors','high_intensity_sweeteners','preservatives','emulsifiers',
    'stabilizers_thickeners','synthetic_antioxidants','sequestrants_phosphates',
    'flavor_enhancers','modified_starch_carriers','artificial_flavor','flour_treatment_agents'
  )),
  add column if not exists generic_declaration boolean not null default false,
  add column if not exists fda_rationale text,
  add column if not exists processing_rationale text;

alter table public.food_version_scores
  add column if not exists fda_evidence_deduction integer not null default 0 check (fda_evidence_deduction between 0 and 40),
  add column if not exists formulation_deduction integer not null default 0 check (formulation_deduction between 0 and 15),
  add column if not exists ingredient_deduction integer not null default 0 check (ingredient_deduction between 0 and 40);

update public.nutrition_score_releases
set status = 'retired'
where algorithm_version = 'leafy-score-v2-us-fda-dv' and status = 'draft';

insert into public.nutrition_score_releases (algorithm_version, registry_version, status)
values ('leafy-score-v2.1-us-fda-dv-hybrid', 'leafy-additives-us-v2-hybrid', 'draft')
on conflict (algorithm_version) do update set registry_version = excluded.registry_version;

-- The runtime registry is source-controlled in additive-registry.ts. These rows
-- record every scored family and its federal status for audit queries; aliases,
-- citations, and full rationales remain versioned in that canonical manifest.
with registry(additive_id, display_name, fda_status, processing_class, generic_declaration) as (values
  ('citric-acid','Citric acid','listed',null,false), ('ascorbic-acid','Ascorbic acid','listed',null,false),
  ('natural-flavor','Natural flavor','listed',null,true), ('artificial-flavor','Artificial flavor','listed','artificial_flavor',true),
  ('fdc-blue-1','FD&C Blue No. 1','active_review','artificial_colors',false), ('fdc-blue-2','FD&C Blue No. 2','active_review','artificial_colors',false),
  ('fdc-green-3','FD&C Green No. 3','active_review','artificial_colors',false), ('fdc-red-40','FD&C Red No. 40','active_review','artificial_colors',false),
  ('fdc-yellow-5','FD&C Yellow No. 5','active_review','artificial_colors',false), ('fdc-yellow-6','FD&C Yellow No. 6','active_review','artificial_colors',false),
  ('fdc-red-3','FD&C Red No. 3','federal_action','artificial_colors',false), ('titanium-dioxide','Titanium dioxide','active_review','artificial_colors',false),
  ('caramel-color','Caramel color','listed','artificial_colors',false), ('aspartame','Aspartame','listed','high_intensity_sweeteners',false),
  ('sucralose','Sucralose','listed','high_intensity_sweeteners',false), ('acesulfame-potassium','Acesulfame potassium','listed','high_intensity_sweeteners',false),
  ('saccharin','Saccharin','listed','high_intensity_sweeteners',false), ('neotame','Neotame','listed','high_intensity_sweeteners',false),
  ('advantame','Advantame','listed','high_intensity_sweeteners',false), ('steviol-glycosides','Steviol glycosides','listed','high_intensity_sweeteners',false),
  ('sodium-benzoate','Sodium benzoate','listed','preservatives',false), ('potassium-benzoate','Potassium benzoate','listed','preservatives',false),
  ('potassium-sorbate','Potassium sorbate','listed','preservatives',false), ('sodium-sorbate','Sodium sorbate','listed','preservatives',false),
  ('sorbic-acid','Sorbic acid','listed','preservatives',false), ('calcium-propionate','Calcium propionate','listed','preservatives',false),
  ('sodium-propionate','Sodium propionate','listed','preservatives',false), ('nitrites','Nitrites','listed','preservatives',false),
  ('nitrates','Nitrates','listed','preservatives',false), ('sulfites','Sulfites','listed','preservatives',false),
  ('natamycin','Natamycin','listed','preservatives',false), ('propylparaben','Propylparaben','active_review','preservatives',false),
  ('lecithins','Lecithins','listed','emulsifiers',false), ('mono-diglycerides','Mono- and diglycerides','listed','emulsifiers',false),
  ('datem','DATEM','listed','emulsifiers',false), ('sodium-stearoyl-lactylate','Sodium stearoyl lactylate','listed','emulsifiers',false),
  ('calcium-stearoyl-lactylate','Calcium stearoyl lactylate','listed','emulsifiers',false), ('polysorbate-60','Polysorbate 60','listed','emulsifiers',false),
  ('polysorbate-80','Polysorbate 80','listed','emulsifiers',false), ('pgpr','Polyglycerol polyricinoleate','listed','emulsifiers',false),
  ('brominated-vegetable-oil','Brominated vegetable oil','federal_action','emulsifiers',false),
  ('xanthan-gum','Xanthan gum','listed','stabilizers_thickeners',false), ('guar-gum','Guar gum','listed','stabilizers_thickeners',false),
  ('gellan-gum','Gellan gum','listed','stabilizers_thickeners',false), ('locust-bean-gum','Locust bean gum','listed','stabilizers_thickeners',false),
  ('carrageenan','Carrageenan','listed','stabilizers_thickeners',false), ('cellulose-gum','Cellulose gum','listed','stabilizers_thickeners',false),
  ('microcrystalline-cellulose','Microcrystalline cellulose','listed','stabilizers_thickeners',false), ('methylcellulose','Methylcellulose','listed','stabilizers_thickeners',false),
  ('hydroxypropyl-methylcellulose','Hydroxypropyl methylcellulose','listed','stabilizers_thickeners',false), ('pectin','Pectin','listed','stabilizers_thickeners',false),
  ('agar','Agar','listed','stabilizers_thickeners',false), ('alginates','Alginates','listed','stabilizers_thickeners',false),
  ('bha','BHA','active_review','synthetic_antioxidants',false), ('bht','BHT','active_review','synthetic_antioxidants',false),
  ('tbhq','TBHQ','listed','synthetic_antioxidants',false), ('propyl-gallate','Propyl gallate','listed','synthetic_antioxidants',false),
  ('phosphoric-acid','Phosphoric acid','listed','sequestrants_phosphates',false), ('sodium-phosphates','Sodium phosphates','listed','sequestrants_phosphates',false),
  ('calcium-phosphates','Calcium phosphates','listed','sequestrants_phosphates',false), ('pyrophosphates','Pyrophosphates','listed','sequestrants_phosphates',false),
  ('polyphosphates','Polyphosphates','listed','sequestrants_phosphates',false), ('edta','EDTA salts','listed','sequestrants_phosphates',false),
  ('monosodium-glutamate','Monosodium glutamate','listed','flavor_enhancers',false), ('disodium-inosinate','Disodium inosinate','listed','flavor_enhancers',false),
  ('disodium-guanylate','Disodium guanylate','listed','flavor_enhancers',false), ('hydrolyzed-protein','Hydrolyzed protein','listed','flavor_enhancers',false),
  ('modified-food-starch','Modified food starch','listed','modified_starch_carriers',false), ('maltodextrin','Maltodextrin','listed','modified_starch_carriers',false),
  ('silicon-dioxide','Silicon dioxide','listed','modified_starch_carriers',false), ('azodicarbonamide','Azodicarbonamide','active_review','flour_treatment_agents',false),
  ('potassium-bromate','Potassium bromate','active_review','flour_treatment_agents',false), ('benzoyl-peroxide','Benzoyl peroxide','listed','flour_treatment_agents',false),
  ('chlorine-dioxide','Chlorine dioxide','listed','flour_treatment_agents',false)
)
insert into public.food_additive_registry (
  registry_version, additive_id, display_name, concern_level, aliases, rationale,
  source_title, source_url, reviewed_at, fda_status, processing_class,
  generic_declaration, fda_rationale, processing_rationale
)
select 'leafy-additives-us-v2-hybrid', additive_id, display_name,
  case fda_status when 'federal_action' then 'higher' when 'active_review' then 'limited' else 'none' end,
  jsonb_build_array(display_name),
  'See the source-controlled registry manifest for the exact versioned rationale and aliases.',
  'FDA Food Ingredient and Packaging Inventories',
  'https://www.fda.gov/food/food-ingredients-packaging/food-ingredient-packaging-inventories',
  '2026-08-13', fda_status, processing_class, generic_declaration,
  'Federal status is versioned in the Leafy registry manifest.',
  case when processing_class is null then null else 'Package-visible formulation class.' end
from registry
on conflict (registry_version, additive_id) do update set
  display_name = excluded.display_name, concern_level = excluded.concern_level,
  fda_status = excluded.fda_status, processing_class = excluded.processing_class,
  generic_declaration = excluded.generic_declaration,
  fda_rationale = excluded.fda_rationale, processing_rationale = excluded.processing_rationale;

comment on column public.food_version_scores.fda_evidence_deduction is 'Points from FDA active-review or federal-action evidence.';
comment on column public.food_version_scores.formulation_deduction is 'Points from distinct package-visible formulation classes after overlap suppression.';
comment on column public.food_version_scores.ingredient_deduction is 'Combined capped ingredient deduction; retained additive_deduction mirrors this for older clients.';
