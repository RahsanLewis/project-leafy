import { createClient } from 'npm:@supabase/supabase-js@2'
import { calculatePFQS } from '../supabase/functions/_shared/pfqs/scorer.ts'
import { calculateAndPersistPFQS } from '../supabase/functions/_shared/pfqs/persistence.ts'
import type { PFQSNutrientCode, PFQSNutrients } from '../supabase/functions/_shared/pfqs/types.ts'

const url = Deno.env.get('SUPABASE_URL')
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')
if (!url || !key) throw new Error('SUPABASE_URL and a Supabase service key are required.')

const apply = Deno.args.includes('--apply')
const admin = createClient(url, key, { auth: { persistSession: false } })
const required = new Set<PFQSNutrientCode>([
  'energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg',
  'saturated_fat_g', 'trans_fat_g', 'protein_g',
])
const totals = { scanned: 0, complete: 0, incomplete: 0, ineligible: 0, written: 0 }

for (let offset = 0;; offset += 200) {
  const versions = await admin.from('food_versions')
    .select('id,description,market_country,ingredients_text,serving_size,serving_unit,verification_status,food_kind')
    .is('superseded_at', null).neq('verification_status', 'rejected')
    .order('id').range(offset, offset + 199)
  if (versions.error) throw versions.error
  if (!versions.data?.length) break

  for (const version of versions.data) {
    const labels = await admin.from('pfqs_label_nutrients')
      .select('nutrient_code,amount_per_serving,explicitly_reported')
      .eq('food_version_id', version.id)
    if (labels.error) throw labels.error
    const usable = (labels.data ?? []).filter((item) => required.has(item.nutrient_code as PFQSNutrientCode))
    const input = {
      product_name: String(version.description),
      jurisdiction: String(version.market_country ?? 'US') === 'United States' ? 'US' : String(version.market_country ?? 'US'),
      assessment_date: new Date().toISOString().slice(0, 10),
      serving_size: {
        amount: Number(version.serving_size ?? 0),
        unit: String(version.serving_unit ?? ''),
      },
      nutrition: Object.fromEntries(usable.map((item) => [item.nutrient_code, Number(item.amount_per_serving)])) as PFQSNutrients,
      explicitly_reported_nutrients: usable.filter((item) => item.explicitly_reported).map((item) => item.nutrient_code as PFQSNutrientCode),
      ingredients_raw: String(version.ingredients_text ?? ''),
      verification_status: String(version.verification_status ?? ''),
      product_type: 'food' as const,
    }
    const result = calculatePFQS(input)
    totals.scanned += 1
    totals[result.score_status] += 1
    if (apply) {
      await calculateAndPersistPFQS(admin, version.id, input)
      totals.written += 1
    }
  }
  if (versions.data.length < 200) break
}

console.log(JSON.stringify({ mode: apply ? 'apply' : 'dry-run', ...totals }, null, 2))
