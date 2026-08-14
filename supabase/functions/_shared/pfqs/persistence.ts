import { calculatePFQS, type PFQSInput, type PFQSResult } from './scorer.ts'

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
  return result
}

export function pfqsAPIResult(score: Record<string, any> | null): PFQSResult | null {
  if (!score) return null
  return {
    score: score.score_100, rating: score.rating, score_status: score.score_status,
    base_score: score.base_score, additive_penalty: score.additive_penalty,
    components: score.components ?? {}, additives: score.additive_results ?? [], flags: score.flags ?? {},
    strengths: score.strengths ?? [], weaknesses: score.weaknesses ?? [], explanation: score.explanation ?? [],
    missing_fields: score.missing_fields ?? [], unavailable_reasons: score.unavailable_reasons ?? [],
    parsed_ingredients: [], classified_ingredients: [], model_version: score.model_version,
    ingredient_taxonomy_version: score.ingredient_taxonomy_version,
    additive_database_version: score.additive_database_version,
    jurisdiction: score.jurisdiction, assessment_date: score.assessment_date,
  }
}
