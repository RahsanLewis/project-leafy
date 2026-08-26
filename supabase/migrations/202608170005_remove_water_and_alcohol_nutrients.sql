-- Water and alcohol are intentionally outside Leafy's tracked nutrient model.
-- Remove only their nutrient facts; parent foods, products, meals, and logs remain intact.

delete from public.catalog_contribution_nutrients
where nutrient_code in ('water_g', 'alcohol_g');

delete from public.ai_meal_item_nutrients
where nutrient_code in ('water_g', 'alcohol_g');

delete from public.nutrient_reference_values
where nutrient_code in ('water_g', 'alcohol_g');

delete from public.consumption_item_nutrients
where nutrient_code in ('water_g', 'alcohol_g');

delete from public.food_version_nutrients
where nutrient_code in ('water_g', 'alcohol_g');

delete from public.pfqs_label_nutrients
where nutrient_code in ('water_g', 'alcohol_g');

delete from public.nutrient_definitions
where code in ('water_g', 'alcohol_g');
