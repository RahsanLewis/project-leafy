import { createClient } from 'npm:@supabase/supabase-js@2'
import { calculatePFQS } from '../supabase/functions/_shared/pfqs/scorer.ts'
import { normalizePFQSJurisdiction } from '../supabase/functions/_shared/pfqs/scorer.ts'
import { calculateAndPersistPFQS } from '../supabase/functions/_shared/pfqs/persistence.ts'
import type { PFQSNutrientCode, PFQSNutrients } from '../supabase/functions/_shared/pfqs/types.ts'
import { calculateAndPersistEntryPFQS } from '../supabase/functions/_shared/pfqs/persistence.ts'
import { pfqsInputForFoodEntry } from '../supabase/functions/_shared/pfqs/entry.ts'

const url = Deno.env.get('SUPABASE_URL')
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')
if (!url || !key) throw new Error('SUPABASE_URL and a Supabase service key are required.')

const apply = Deno.args.includes('--apply')
const admin = createClient(url, key, { auth: { persistSession: false } })
const required = new Set<PFQSNutrientCode>([
  'energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg',
  'saturated_fat_g', 'trans_fat_g', 'protein_g',
])
const totals = { scanned: 0, entries_scanned: 0, complete: 0, provisional: 0, pending: 0, ineligible: 0, written: 0 }

for (let offset = 0;; offset += 200) {
  const versions = await admin.from('food_versions')
    .select('id,description,market_country,ingredients_text,serving_size,serving_unit,verification_status,food_kind,source_data_type')
    .is('superseded_at', null).neq('verification_status', 'rejected')
    .order('id').range(offset, offset + 199)
  if (versions.error) throw versions.error
  if (!versions.data?.length) break

  for (const version of versions.data) {
    const [labels, normalized] = await Promise.all([
      admin.from('pfqs_label_nutrients').select('nutrient_code,amount_per_serving,explicitly_reported,source_method,confidence').eq('food_version_id', version.id),
      admin.from('food_version_nutrients').select('nutrient_code,amount_per_100g,derivation_method').eq('food_version_id', version.id),
    ])
    if (labels.error) throw labels.error
    if (normalized.error) throw normalized.error
    const labelUsable = (labels.data ?? []).filter((item) => required.has(item.nutrient_code as PFQSNutrientCode))
    const canScale = Number(version.serving_size) > 0 && /^(g|gram|grams|grm)$/i.test(String(version.serving_unit ?? ''))
    const derived = (normalized.data ?? []).filter((item) => required.has(item.nutrient_code as PFQSNutrientCode)).map((item) => ({
      nutrient_code: item.nutrient_code,
      amount_per_serving: Number(item.amount_per_100g) * (canScale ? Number(version.serving_size) / 100 : 1),
      explicitly_reported: false,
      source_method: item.derivation_method === 'estimated' ? 'estimated' : 'source_conversion',
      confidence: item.derivation_method === 'estimated' ? 0.7 : 0.9,
    }))
    const usable = [...new Map([...derived, ...labelUsable].map((item) => [item.nutrient_code, item])).values()]
    const productType = String(version.source_data_type) === 'ai_estimate' ? 'ai_estimate' : 'food'
    const input = {
      product_name: String(version.description),
      jurisdiction: normalizePFQSJurisdiction(String(version.market_country ?? 'US')),
      assessment_date: new Date().toISOString().slice(0, 10),
      serving_size: {
        amount: canScale || labelUsable.length ? Number(version.serving_size ?? 0) : 100,
        unit: canScale || labelUsable.length ? String(version.serving_unit ?? '') : 'g',
      },
      nutrition: Object.fromEntries(usable.map((item) => [item.nutrient_code, Number(item.amount_per_serving)])) as PFQSNutrients,
      explicitly_reported_nutrients: usable.filter((item) => item.explicitly_reported).map((item) => item.nutrient_code as PFQSNutrientCode),
      nutrient_evidence: Object.fromEntries(usable.map((item) => [item.nutrient_code, {
        source: item.source_method === 'label' || item.source_method === 'human_review' ? 'label'
          : item.source_method === 'estimated' ? 'estimated' : 'derived',
        confidence: Number(item.confidence ?? 0.9),
      }])),
      ingredients_raw: String(version.ingredients_text ?? ''),
      verification_status: String(version.verification_status ?? ''),
      product_type: productType as 'food' | 'ai_estimate',
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

for (let offset = 0;; offset += 200) {
  const entries = await admin.from('food_entries').select('id,user_id').order('id').range(offset, offset + 199)
  if (entries.error) throw entries.error
  if (!entries.data?.length) break
  for (const entry of entries.data) {
    const input = await pfqsInputForFoodEntry(admin, String(entry.id), String(entry.user_id))
    const result = calculatePFQS(input)
    totals.entries_scanned += 1
    totals[result.score_status] += 1
    if (apply) {
      await calculateAndPersistEntryPFQS(admin, String(entry.id), String(entry.user_id), input)
      totals.written += 1
    }
  }
  if (entries.data.length < 200) break
}

console.log(JSON.stringify({ mode: apply ? 'apply' : 'dry-run', ...totals }, null, 2))
