import { calculatePFQS, type PFQSInput, type PFQSResult } from './scorer.ts'
import { PFQS_INGREDIENT_DATABASE_VERSION } from './types.ts'

export async function calculateAndPersistPFQS(admin: any, foodVersionID: string, input: PFQSInput) {
  const result = calculatePFQS(input)
  const scoreWrite = await admin.from('pfqs_scores').upsert({
    food_version_id: foodVersionID,
    model_version: result.model_version,
    ingredient_taxonomy_version: result.ingredient_taxonomy_version,
    additive_database_version: result.additive_database_version,
    jurisdiction: result.jurisdiction,
    assessment_date: result.assessment_date,
    score_status: result.score_status,
    score_100: result.score,
    rating: result.rating,
    base_score: result.base_score,
    additive_penalty: result.additive_penalty,
    components: result.components,
    additive_results: result.additives,
    flags: result.flags,
    strengths: result.strengths,
    weaknesses: result.weaknesses,
    explanation: result.explanation,
    missing_fields: result.missing_fields,
    unavailable_reasons: result.unavailable_reasons,
    input_snapshot: input,
  }, { onConflict: 'food_version_id,model_version,ingredient_taxonomy_version,additive_database_version,jurisdiction,assessment_date' })
  if (scoreWrite.error) throw scoreWrite.error

  const ingredientWrite = await admin.from('pfqs_ingredient_snapshots').upsert({
    food_version_id: foodVersionID,
    taxonomy_version: result.ingredient_taxonomy_version,
    ingredients_raw: input.ingredients_raw,
    parsed_ingredients: result.parsed_ingredients,
    classified_ingredients: result.classified_ingredients,
  }, { onConflict: 'food_version_id,taxonomy_version' })
  if (ingredientWrite.error) throw ingredientWrite.error

  const catalogRows = [...new Map(result.ingredients.map((ingredient) => [ingredient.canonical_id, ingredient])).values()]
  if (catalogRows.length) {
    const catalogIDs = catalogRows.map((ingredient) => ingredient.canonical_id)
    const existingRead = await admin.from('pfqs_ingredients').select(
      'canonical_id,canonical_name,quality_class,quality_coefficient,beneficial,classification_confidence,classification_source,review_status,risk_canonical_id',
    ).eq('ingredient_database_version', result.ingredient_database_version).in('canonical_id', catalogIDs)
    if (existingRead.error) throw existingRead.error
    const existingByID = new Map<string, Record<string, any>>(
      (existingRead.data ?? []).map((ingredient: Record<string, any>) => [ingredient.canonical_id, ingredient]),
    )
    const now = new Date().toISOString()
    const catalogWrite = await admin.from('pfqs_ingredients').upsert(catalogRows.map((ingredient) => {
      const existing = existingByID.get(ingredient.canonical_id)
      const preserveClassification = existing?.review_status === 'reviewed'
        || (existing?.review_status === 'classified' && ingredient.review_status === 'unclassified')
      return {
        ingredient_database_version: result.ingredient_database_version,
        canonical_id: ingredient.canonical_id,
        canonical_name: existing?.canonical_name ?? ingredient.canonical_name,
        quality_class: preserveClassification ? existing.quality_class : ingredient.quality_class,
        quality_coefficient: preserveClassification ? existing.quality_coefficient : ingredient.quality_coefficient,
        beneficial: preserveClassification ? existing.beneficial : ingredient.beneficial,
        classification_confidence: preserveClassification ? existing.classification_confidence : ingredient.classification_confidence,
        classification_source: preserveClassification ? existing.classification_source : ingredient.classification_source,
        review_status: preserveClassification ? existing.review_status : ingredient.review_status,
        risk_canonical_id: existing?.risk_canonical_id ?? ingredient.risk_canonical_id,
        updated_at: now,
      }
    }), { onConflict: 'ingredient_database_version,canonical_id' })
    if (catalogWrite.error) throw catalogWrite.error

    const aliasesByName = new Map<string, Record<string, string>>()
    for (const ingredient of result.ingredients) {
      const normalized = ingredient.raw.normalize('NFKD').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
      if (!normalized || aliasesByName.has(normalized)) continue
      aliasesByName.set(normalized, {
        ingredient_database_version: result.ingredient_database_version,
        canonical_id: ingredient.canonical_id,
        alias: ingredient.raw,
        normalized_alias: normalized,
      })
    }
    const aliases = [...aliasesByName.values()]
    if (aliases.length) {
      const aliasWrite = await admin.from('pfqs_ingredient_aliases').upsert(aliases, {
        onConflict: 'ingredient_database_version,normalized_alias',
        ignoreDuplicates: true,
      })
      if (aliasWrite.error) throw aliasWrite.error
    }
  }

  const deleteOccurrences = await admin.from('pfqs_food_ingredient_occurrences').delete()
    .eq('food_version_id', foodVersionID).eq('ingredient_database_version', result.ingredient_database_version)
  if (deleteOccurrences.error) throw deleteOccurrences.error
  if (result.ingredients.length) {
    const occurrenceWrite = await admin.from('pfqs_food_ingredient_occurrences').insert(result.ingredients.map((ingredient) => ({
      food_version_id: foodVersionID,
      ingredient_database_version: result.ingredient_database_version,
      canonical_id: ingredient.canonical_id,
      raw_text: ingredient.raw,
      canonical_name: ingredient.canonical_name,
      parent_canonical_id: ingredient.parent_canonical_id,
      position: ingredient.position,
      depth: ingredient.depth,
      percentage: ingredient.percentage,
      ingredient_path: ingredient.ingredient_path,
    })))
    if (occurrenceWrite.error) throw occurrenceWrite.error
  }
  return result
}

export function pfqsAPIResult(score: Record<string, any> | null): PFQSResult | null {
  if (!score) return null
  return {
    score: score.score_100, rating: score.rating, score_status: score.score_status,
    base_score: score.base_score, additive_penalty: score.additive_penalty,
    ingredient_concern_penalty: score.ingredient_concern_penalty ?? score.additive_penalty ?? 0,
    components: score.components ?? {}, additives: score.additive_results ?? [],
    ingredient_concerns: score.ingredient_concerns ?? score.additive_results ?? [],
    ingredients: score.ingredients ?? [], flags: score.flags ?? {},
    strengths: score.strengths ?? [], weaknesses: score.weaknesses ?? [], explanation: score.explanation ?? [],
    missing_fields: score.missing_fields ?? [], unavailable_reasons: score.unavailable_reasons ?? [],
    parsed_ingredients: [], classified_ingredients: [], model_version: score.model_version,
    ingredient_taxonomy_version: score.ingredient_taxonomy_version,
    additive_database_version: score.additive_database_version,
    ingredient_database_version: score.ingredient_database_version ?? PFQS_INGREDIENT_DATABASE_VERSION,
    jurisdiction: score.jurisdiction, assessment_date: score.assessment_date,
  }
}
