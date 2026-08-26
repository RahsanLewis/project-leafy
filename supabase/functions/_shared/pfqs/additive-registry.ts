import { canonicalizeIngredient, flattenIngredients } from './ingredient-parser.ts'
import type { PFQSAdditiveResult, ParsedIngredient } from './types.ts'

export type AdditiveRule = {
  jurisdiction: string
  start_date: string
  end_date: string | null
  tier: 0 | 1 | 2 | 3 | 4
  penalty: 0 | 1 | 3 | 7 | 15
  reason: string
}

export type AdditiveRegistryEntry = {
  canonical_id: string
  canonical_name: string
  aliases: string[]
  family: string | null
  jurisdiction_rules: AdditiveRule[]
  evidence: { confidence: string; summary: string; last_reviewed: string }
  sources: { organization: string; document: string; url?: string }[]
}

function additive(
  canonical_id: string,
  canonical_name: string,
  aliases: string[],
  family: string | null,
  jurisdiction_rules: AdditiveRule[] = [],
  sources: AdditiveRegistryEntry['sources'] = [],
): AdditiveRegistryEntry {
  return {
    canonical_id, canonical_name,
    aliases: [canonical_name, ...aliases].map(canonicalizeIngredient),
    family, jurisdiction_rules,
    evidence: { confidence: jurisdiction_rules.length ? 'high' : 'not_penalty_classified', summary: jurisdiction_rules.length ? jurisdiction_rules[0].reason : 'Recognized additive with no PFQS penalty classification.', last_reviewed: '2026-08-13' },
    sources,
  }
}

const red3Reason = 'FDA revoked authorization for this color additive; the U.S. food compliance date determines whether it is pending removal or no longer permitted.'
const bvoReason = 'FDA revoked authorization for brominated vegetable oil in food after concluding its intended use was no longer considered safe.'
const phoReason = 'Partially hydrogenated oils are no longer generally recognized as safe for food use in the United States.'

export const additiveRegistry: AdditiveRegistryEntry[] = [
  additive('fdc_red_3', 'FD&C Red No. 3', ['red 3', 'red no 3', 'erythrosine', 'e127'], 'synthetic_colors', [
    { jurisdiction: 'US', start_date: '2025-01-15', end_date: '2027-01-14', tier: 3, penalty: 7, reason: red3Reason },
    { jurisdiction: 'US', start_date: '2027-01-15', end_date: null, tier: 4, penalty: 15, reason: red3Reason },
  ], [{ organization: 'FDA', document: 'FDA revokes authorization for the use of Red No. 3 in food and ingested drugs', url: 'https://www.fda.gov/food/hfp-constituent-updates/fda-revokes-authorization-use-red-no-3-food-and-ingested-drugs' }]),
  additive('brominated_vegetable_oil', 'Brominated vegetable oil', ['bvo'], 'emulsifiers', [
    { jurisdiction: 'US', start_date: '2025-08-02', end_date: null, tier: 4, penalty: 15, reason: bvoReason },
  ], [{ organization: 'FDA', document: 'FDA revokes regulation allowing the use of brominated vegetable oil in food', url: 'https://www.fda.gov/food/hfp-constituent-updates/fda-revokes-regulation-allowing-use-brominated-vegetable-oil-bvo-food' }]),
  additive('partially_hydrogenated_oils', 'Partially hydrogenated oils', ['partially hydrogenated oil', 'partially hydrogenated soybean oil', 'partially hydrogenated cottonseed oil'], 'fats', [
    { jurisdiction: 'US', start_date: '2021-01-01', end_date: null, tier: 4, penalty: 15, reason: phoReason },
  ], [{ organization: 'FDA', document: 'Final determination regarding partially hydrogenated oils', url: 'https://www.fda.gov/food/food-additives-petitions/trans-fat' }]),
  additive('citric_acid', 'Citric acid', [], 'acidity_regulators'),
  additive('ascorbic_acid', 'Ascorbic acid', ['vitamin c'], 'antioxidants'),
  additive('soy_lecithin', 'Soy lecithin', ['lecithin', 'sunflower lecithin'], 'emulsifiers'),
  additive('mono_diglycerides', 'Mono- and diglycerides', ['mono and diglycerides', 'monoglycerides', 'diglycerides'], 'emulsifiers'),
  additive('datem', 'DATEM', ['diacetyl tartaric acid esters of mono and diglycerides'], 'emulsifiers'),
  additive('polysorbate_80', 'Polysorbate 80', [], 'emulsifiers'),
  additive('polysorbate_60', 'Polysorbate 60', [], 'emulsifiers'),
  additive('xanthan_gum', 'Xanthan gum', [], 'stabilizers'),
  additive('guar_gum', 'Guar gum', [], 'stabilizers'),
  additive('gellan_gum', 'Gellan gum', [], 'stabilizers'),
  additive('carrageenan', 'Carrageenan', [], 'stabilizers'),
  additive('cellulose_gum', 'Cellulose gum', ['carboxymethyl cellulose'], 'stabilizers'),
  additive('sodium_benzoate', 'Sodium benzoate', [], 'preservatives'),
  additive('potassium_sorbate', 'Potassium sorbate', [], 'preservatives'),
  additive('calcium_propionate', 'Calcium propionate', [], 'preservatives'),
  additive('sodium_nitrite', 'Sodium nitrite', [], 'preservatives'),
  additive('sodium_nitrate', 'Sodium nitrate', [], 'preservatives'),
  additive('bha', 'BHA', ['butylated hydroxyanisole'], 'antioxidants'),
  additive('bht', 'BHT', ['butylated hydroxytoluene'], 'antioxidants'),
  additive('tbhq', 'TBHQ', ['tertiary butylhydroquinone'], 'antioxidants'),
  additive('aspartame', 'Aspartame', [], 'sweeteners'),
  additive('sucralose', 'Sucralose', [], 'sweeteners'),
  additive('acesulfame_potassium', 'Acesulfame potassium', ['acesulfame k', 'ace k'], 'sweeteners'),
  additive('saccharin', 'Saccharin', [], 'sweeteners'),
  additive('fdc_red_40', 'FD&C Red No. 40', ['red 40', 'allura red', 'e129'], 'synthetic_colors'),
  additive('fdc_yellow_5', 'FD&C Yellow No. 5', ['yellow 5', 'tartrazine', 'e102'], 'synthetic_colors'),
  additive('fdc_yellow_6', 'FD&C Yellow No. 6', ['yellow 6', 'sunset yellow', 'e110'], 'synthetic_colors'),
  additive('fdc_blue_1', 'FD&C Blue No. 1', ['blue 1', 'brilliant blue', 'e133'], 'synthetic_colors'),
  additive('fdc_blue_2', 'FD&C Blue No. 2', ['blue 2', 'indigo carmine', 'e132'], 'synthetic_colors'),
  additive('titanium_dioxide', 'Titanium dioxide', ['e171'], 'colors'),
  additive('modified_food_starch', 'Modified food starch', ['modified corn starch', 'food starch modified'], 'starches'),
  additive('maltodextrin', 'Maltodextrin', [], 'carriers'),
  additive('silicon_dioxide', 'Silicon dioxide', ['silica'], 'anticaking_agents'),
  additive('monosodium_glutamate', 'Monosodium glutamate', ['msg'], 'flavor_enhancers'),
  additive('disodium_inosinate', 'Disodium inosinate', [], 'flavor_enhancers'),
  additive('disodium_guanylate', 'Disodium guanylate', [], 'flavor_enhancers'),
  additive('phosphoric_acid', 'Phosphoric acid', [], 'phosphates'),
  additive('sodium_phosphates', 'Sodium phosphate', ['monosodium phosphate', 'disodium phosphate', 'trisodium phosphate'], 'phosphates'),
]

const aliasIndex = new Map(additiveRegistry.flatMap((item) => item.aliases.map((alias) => [alias, item] as const)))

export function detectAdditives(ingredients: ParsedIngredient[], jurisdiction: string, assessmentDate: string) {
  const unique = new Map<string, PFQSAdditiveResult>()
  for (const ingredient of flattenIngredients(ingredients)) {
    const match = aliasIndex.get(ingredient.canonical_name)
    if (!match || unique.has(match.canonical_id)) continue
    const rule = match.jurisdiction_rules.find((candidate) =>
      candidate.jurisdiction === jurisdiction && candidate.start_date <= assessmentDate && (!candidate.end_date || candidate.end_date >= assessmentDate)
    )
    unique.set(match.canonical_id, {
      name: match.canonical_name,
      canonical_id: match.canonical_id,
      family: match.family,
      tier: rule?.tier ?? 0,
      penalty: rule?.penalty ?? 0,
      status: 'classified',
      reason: rule?.reason ?? 'No PFQS additive-risk penalty is assigned for this recognized ingredient.',
      matched_alias: ingredient.raw,
      evidence_confidence: match.evidence.confidence,
      sources: match.sources,
    })
  }
  for (const ingredient of flattenIngredients(ingredients)) {
    if (aliasIndex.has(ingredient.canonical_name) || !looksAdditiveLike(ingredient.canonical_name)) continue
    const key = `unclassified:${ingredient.canonical_name}`
    if (unique.has(key)) continue
    unique.set(key, {
      name: ingredient.name,
      canonical_id: key,
      family: null,
      tier: null,
      penalty: 0,
      status: 'unclassified',
      reason: 'This ingredient is not currently classified in the PFQS additive database.',
      matched_alias: ingredient.raw,
    })
  }
  return [...unique.values()]
}

export function recognizedAdditive(value: string) { return aliasIndex.has(canonicalizeIngredient(value)) }

function looksAdditiveLike(value: string) {
  return /(?:acid|ate|ite|gum|color|flavou?r|extract|enzyme|preservative|sweetener|emulsifier|stabilizer|phosphate|carbonate|chloride|sulfate|nitrate|nitrite|dioxide|lecithin|cellulose|glycer)/.test(value)
}
