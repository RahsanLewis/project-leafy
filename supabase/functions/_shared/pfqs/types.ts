export const PFQS_MODEL_VERSION = 'PFQS-1.1'
export const PFQS_TAXONOMY_VERSION = 'PFQS-TAXONOMY-1.0'
export const PFQS_ADDITIVE_DATABASE_VERSION = 'PFQS-ADDITIVES-2026-08-13'
export const PFQS_INGREDIENT_DATABASE_VERSION = 'PFQS-INGREDIENTS-2026-08-24'

export type PFQSNutrientCode =
  | 'energy_kcal'
  | 'added_sugars_g'
  | 'fiber_g'
  | 'sodium_mg'
  | 'saturated_fat_g'
  | 'trans_fat_g'
  | 'protein_g'

export type PFQSNutrients = Partial<Record<PFQSNutrientCode, number>>

export type PFQSNutrientEvidence = Partial<Record<PFQSNutrientCode, {
  source: 'label' | 'derived' | 'estimated' | 'user_entered'
  confidence: number
}>>

export type PFQSProductType =
  | 'food'
  | 'supplement'
  | 'infant_formula'
  | 'medical_food'
  | 'alcohol'
  | 'restaurant'
  | 'manual'
  | 'ai_estimate'

export type FrozenIngredientClassification = {
  canonical_name: string
  quality_class: 'A' | 'B' | 'C' | 'D' | 'E'
  beneficial: boolean
  confidence: number
  source: 'curated' | 'ai' | 'human_review'
  model?: string | null
  prompt_version?: string | null
}

export type PFQSInput = {
  product_name: string
  jurisdiction: string
  assessment_date: string
  serving_size: { amount: number; unit: string; description?: string | null }
  nutrition: PFQSNutrients
  explicitly_reported_nutrients?: PFQSNutrientCode[]
  nutrient_evidence?: PFQSNutrientEvidence
  ingredients_raw: string
  ingredient_percentages?: Record<string, number>
  frozen_ingredient_classifications?: FrozenIngredientClassification[]
  verification_status?: string | null
  product_type?: PFQSProductType
  verified_single_ingredient?: boolean
}

export type ParsedIngredient = {
  raw: string
  name: string
  canonical_name: string
  position: number
  percentage: number | null
  parent: string | null
  subingredients: ParsedIngredient[]
}

export type ClassifiedIngredient = ParsedIngredient & {
  quality_class: 'A' | 'B' | 'C' | 'D' | 'E'
  quality_coefficient: number
  beneficial: boolean
  confidence: number
  classification_source: 'curated' | 'ai' | 'human_review'
}

export type PFQSComponent = {
  score: number
  max: number
  normalized_value?: number
  unit?: string
  method?: string
}

export type PFQSAdditiveResult = {
  name: string
  canonical_id: string
  family: string | null
  tier: 0 | 1 | 2 | 3 | 4 | null
  penalty: number
  status: 'classified' | 'unclassified'
  reason: string
  matched_alias: string
  evidence_confidence?: string | null
  sources?: { organization: string; document: string; url?: string | null }[]
}

export type PFQSIngredientResult = {
  canonical_id: string
  canonical_name: string
  raw: string
  position: number
  depth: number
  parent_canonical_id: string | null
  percentage: number | null
  ingredient_path: string
  quality_class: 'A' | 'B' | 'C' | 'D' | 'E' | null
  quality_coefficient: number | null
  beneficial: boolean
  classification_confidence: number | null
  classification_source: 'curated' | 'ai' | 'human_review' | null
  review_status: 'reviewed' | 'classified' | 'unclassified'
  risk_canonical_id: string | null
}

export type PFQSResult = {
  score: number | null
  rating: string | null
  score_status: 'complete' | 'provisional' | 'pending' | 'ineligible'
  base_score: number | null
  additive_penalty: number
  ingredient_concern_penalty: number
  components: Record<string, PFQSComponent>
  additives: PFQSAdditiveResult[]
  ingredient_concerns: PFQSAdditiveResult[]
  ingredients: PFQSIngredientResult[]
  flags: {
    tier_4_additive_present: boolean
    score_ceiling_applied: boolean
    regulatory_flag: boolean
  }
  strengths: string[]
  weaknesses: string[]
  explanation: string[]
  missing_fields: string[]
  unavailable_reasons: string[]
  evidence_coverage: number
  evidence_confidence: number
  confidence_level: 'high' | 'moderate' | 'low' | 'none'
  included_components: string[]
  parsed_ingredients: ParsedIngredient[]
  classified_ingredients: ClassifiedIngredient[]
  model_version: string
  ingredient_taxonomy_version: string
  additive_database_version: string
  ingredient_database_version: string
  jurisdiction: string
  assessment_date: string
}
