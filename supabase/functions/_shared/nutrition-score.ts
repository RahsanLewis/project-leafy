export type ScoreNutrients = {
  energy_kcal?: number
  sugars_g?: number
  saturated_fat_g?: number
  sodium_mg?: number
  fiber_g?: number
  protein_g?: number
}

export type NutritionScore = {
  algorithm_version: string
  score: number | null
  label: 'Excellent' | 'Good' | 'Fair' | 'Poor' | 'Limited' | null
  confidence: number
  positive_factors: string[]
  limiting_factors: string[]
  missing_fields: string[]
  components: Record<string, number>
}

const required: (keyof ScoreNutrients)[] = ['energy_kcal', 'sugars_g', 'saturated_fat_g', 'sodium_mg']

export function nutritionScore(nutrients: ScoreNutrients): NutritionScore {
  const missing = required.filter((key) => !Number.isFinite(nutrients[key]))
  if (missing.length) return {
    algorithm_version: 'leafy-nutrition-v1-ns2023', score: null, label: null,
    confidence: Math.max(0, (required.length - missing.length) / required.length),
    positive_factors: [], limiting_factors: [], missing_fields: missing, components: {},
  }

  const energy = clamp((nutrients.energy_kcal! - 80) / 4.2, 0, 35)
  const sugar = clamp(nutrients.sugars_g! * 2.15, 0, 35)
  const saturated = clamp(nutrients.saturated_fat_g! * 3.1, 0, 30)
  const sodium = clamp(nutrients.sodium_mg! / 30, 0, 30)
  const fiber = clamp((nutrients.fiber_g ?? 0) * 4.5, 0, 20)
  const protein = clamp((nutrients.protein_g ?? 0) * 1.7, 0, 15)
  const raw = energy + sugar + saturated + sodium - fiber - protein
  const score = Math.round(clamp(100 - raw, 0, 100))
  const label = score >= 80 ? 'Excellent' : score >= 60 ? 'Good' : score >= 40 ? 'Fair' : score >= 20 ? 'Poor' : 'Limited'
  const positive: string[] = []
  const limiting: string[] = []
  if ((nutrients.fiber_g ?? 0) >= 3) positive.push('Good source of fiber')
  if ((nutrients.protein_g ?? 0) >= 10) positive.push('High in protein')
  if (nutrients.sodium_mg! >= 600) limiting.push('High in sodium')
  if (nutrients.sugars_g! >= 15) limiting.push('High in sugar')
  if (nutrients.saturated_fat_g! >= 5) limiting.push('High in saturated fat')
  return {
    algorithm_version: 'leafy-nutrition-v1-ns2023', score, label, confidence: 1,
    positive_factors: positive, limiting_factors: limiting, missing_fields: [],
    components: { energy, sugar, saturated_fat: saturated, sodium, fiber, protein, raw_points: raw },
  }
}

function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(Math.max(value, minimum), maximum)
}
