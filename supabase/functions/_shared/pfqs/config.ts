export const PFQS_POSITION_WEIGHTS = [0.45, 0.25, 0.15, 0.10, 0.05] as const

export const PFQS_QUALITY_COEFFICIENTS = {
  A: 1,
  B: 0.75,
  C: 0.5,
  D: 0.25,
  E: 0,
} as const

export const PFQS_RATING_BANDS = [
  { minimum: 90, label: 'Exceptional' },
  { minimum: 80, label: 'Excellent' },
  { minimum: 70, label: 'Good' },
  { minimum: 60, label: 'Above Average' },
  { minimum: 50, label: 'Mixed' },
  { minimum: 40, label: 'Below Average' },
  { minimum: 25, label: 'Poor' },
  { minimum: 0, label: 'Very Poor' },
] as const

export const PFQS_SUPPORTED_JURISDICTIONS = ['US'] as const
export const PFQS_REQUIRED_NUTRIENTS = [
  'energy_kcal', 'added_sugars_g', 'fiber_g', 'sodium_mg',
  'saturated_fat_g', 'trans_fat_g', 'protein_g',
] as const

export const PFQS_INELIGIBLE_PRODUCT_TYPES = [
  'supplement', 'infant_formula', 'medical_food', 'alcohol',
] as const

export type PFQSFamilyCap = { family_id: string; cap: number }

// Version 1 supports family caps but deliberately activates none until a
// human-reviewed evidence decision is recorded in the additive release.
export const PFQS_FAMILY_CAPS: PFQSFamilyCap[] = []
