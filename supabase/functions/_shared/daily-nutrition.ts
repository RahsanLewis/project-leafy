import { ageOnDate, driReference, resolveNutrientReference, type CalculationSex } from './dri.ts'

export type NutritionRow = Record<string, unknown>

export type DailyNutritionMetadata = {
  definitions: NutritionRow[]
  legacyTargets: Map<string, number>
  profile: { birth_date: string; calculation_sex: CalculationSex; current_weight_kg: number }
  weights: { recorded_on: string; weight_kg: number }[]
}

export function buildDailyNutritionSummary(
  selectedDate: string,
  dates: string[],
  items: NutritionRow[],
  observations: NutritionRow[],
  metadata: DailyNutritionMetadata,
  jobs: NutritionRow[] = [],
) {
  const itemsByID = new Map(items.map((item) => [String(item.id), item]))
  const itemsByDate = new Map(dates.map((date) => [date, items.filter((item) => item.local_date === date)]))
  const observationsByItem = new Map<string, Map<string, NutritionRow>>()
  for (const row of observations) {
    const itemID = String(row.consumption_item_id)
    const values = observationsByItem.get(itemID) ?? new Map<string, NutritionRow>()
    values.set(String(row.nutrient_code), row)
    observationsByItem.set(itemID, values)
  }
  const selectedItems = itemsByDate.get(selectedDate) ?? []
  const totalCalories = selectedItems.reduce((sum, item) => sum + Number(item.calories_kcal ?? 0), 0)
  const selectedWeight = weightForDate(selectedDate, metadata.weights, metadata.profile.current_weight_kg)
  const selectedAge = ageOnDate(metadata.profile.birth_date, selectedDate)

  const nutrients = metadata.definitions
    .filter((definition) => definition.is_displayed !== false && String(definition.code) !== 'energy_kcal')
    .map((definition) => {
      const code = String(definition.code)
      const rule = resolveNutrientReference(code, selectedAge, metadata.profile.calculation_sex, selectedWeight)
      const target = rule.targetAmount ?? metadata.legacyTargets.get(code) ?? null
      const targetType = rule.targetAmount == null && target != null ? 'fda_daily_value' : rule.targetType
      const amountRows = rowsFor(code, selectedItems, observationsByItem)
      const basisRows = basisRowsFor(rule.targetBasisCodes, selectedItems, observationsByItem)
      const amount = sumRows(amountRows)
      const targetBasisAmount = sumRows(basisRows)
      const coverage = coverageFor(rule.targetBasisCodes, selectedItems, observationsByItem)
      const estimatedAmount = amountRows.filter((row) => row.derivation_method === 'estimated')
        .reduce((sum, row) => sum + Number(row.amount ?? 0), 0)
      const confidenceRows = amountRows.filter((row) => row.confidence != null)
      const confidence = confidenceRows.length
        ? confidenceRows.reduce((sum, row) => sum + Number(row.confidence), 0) / confidenceRows.length
        : null

      const trendDays = dates.map((date) => {
        const dayItems = itemsByDate.get(date) ?? []
        const weight = weightForDate(date, metadata.weights, metadata.profile.current_weight_kg)
        const age = ageOnDate(metadata.profile.birth_date, date)
        const dayRule = resolveNutrientReference(code, age, metadata.profile.calculation_sex, weight)
        const dayTarget = dayRule.targetAmount ?? metadata.legacyTargets.get(code) ?? null
        const dayAmount = sumRows(basisRowsFor(dayRule.targetBasisCodes, dayItems, observationsByItem))
        const dayCoverage = coverageFor(dayRule.targetBasisCodes, dayItems, observationsByItem)
        return {
          targetRatio: dayTarget && dayTarget > 0 ? dayAmount / dayTarget : null,
          upperRatio: dayRule.upperLimitAmount && dayRule.upperLimitAmount > 0
            ? dayAmount / dayRule.upperLimitAmount : null,
          coverage: dayCoverage,
        }
      })
      const targetTrend = trendDays.filter((day) => day.targetRatio != null && (day.coverage ?? 0) >= 0.8)
      const upperTrend = trendDays.filter((day) => day.upperRatio != null && (day.coverage ?? 0) >= 0.8)
      const trendPercentOfTarget = average(targetTrend.map((day) => day.targetRatio!))
      const trendPercentOfUpperLimit = average(upperTrend.map((day) => day.upperRatio!))
      const belowTargetFlag = rule.lowFlagEnabled && targetTrend.length >= 4
        ? (trendPercentOfTarget ?? 1) < 0.9
        : null
      const excessFlag = rule.upperLimitScope === 'total' && upperTrend.length >= 4
        ? (trendPercentOfUpperLimit ?? 0) > 1
        : null

      const sources = amountRows.filter((row) => Number(row.amount ?? 0) > 0).map((row) => {
        const item = itemsByID.get(String(row.consumption_item_id)) ?? {}
        const sourceAmount = Number(row.amount ?? 0)
        return {
          consumption_item_id: row.consumption_item_id,
          food_entry_id: item.legacy_food_entry_id ?? null,
          name: item.description ?? 'Logged food',
          amount: sourceAmount,
          percent_of_daily_amount: amount > 0 ? sourceAmount / amount : null,
          derivation_method: row.derivation_method,
          confidence: row.confidence ?? null,
        }
      }).sort((left, right) => right.amount - left.amount)

      return {
        code, name: definition.name, unit: definition.unit, nutrient_class: definition.nutrient_class,
        display_order: definition.display_order,
        target_kind: code === 'sodium_mg' ? 'goal' : definition.target_kind,
        amount, target_basis_amount: targetBasisAmount, target_basis_codes: rule.targetBasisCodes,
        target_amount: target, target_type: targetType,
        percent_of_target: target && target > 0 ? targetBasisAmount / target : null,
        upper_limit_amount: rule.upperLimitAmount, upper_limit_scope: rule.upperLimitScope,
        guidance_limit_amount: rule.guidanceLimitAmount, guidance_limit_type: rule.guidanceLimitType,
        below_target_flag: belowTargetFlag, excess_flag: excessFlag,
        trend_qualifying_days: targetTrend.length,
        trend_required_days: 4,
        trend_percent_of_target: trendPercentOfTarget,
        trend_percent_of_upper_limit: trendPercentOfUpperLimit,
        reference_url: driReference.source_url, reference_note: rule.note ?? definition.essentiality_note ?? null,
        food_sources: sources,
        coverage, estimated_amount: estimatedAmount, verified_amount: Math.max(0, amount - estimatedAmount), confidence,
      }
    })

  const macroCodes = ['protein_g', 'carbohydrate_g', 'fat_g']
  const macroCoveredCalories = selectedItems.filter((item) => macroCodes.every((code) =>
    observationsByItem.get(String(item.id))?.has(code)))
    .reduce((sum, item) => sum + Number(item.calories_kcal ?? 0), 0)
  return {
    local_date: selectedDate,
    total_calories: totalCalories,
    macro_coverage: totalCalories > 0 ? macroCoveredCalories / totalCalories : null,
    reference: driReference,
    nutrients,
    trend_window: { start_date: dates[0], end_date: selectedDate, required_qualifying_days: 4 },
    enrichment_status: jobs.some((job) => ['queued', 'processing', 'retry_wait'].includes(String(job.status)))
      ? 'processing' : jobs.some((job) => job.status === 'failed') ? 'failed' : 'complete',
    pending_item_count: jobs.filter((job) => ['queued', 'processing', 'retry_wait'].includes(String(job.status))).length,
  }
}

function rowsFor(code: string, items: NutritionRow[], byItem: Map<string, Map<string, NutritionRow>>) {
  return items.flatMap((item) => {
    const row = byItem.get(String(item.id))?.get(code)
    return row ? [row] : []
  })
}

function basisRowsFor(codes: string[], items: NutritionRow[], byItem: Map<string, Map<string, NutritionRow>>) {
  return codes.flatMap((code) => rowsFor(code, items, byItem))
}

function sumRows(rows: NutritionRow[]) {
  return rows.reduce((sum, row) => sum + Number(row.amount ?? 0), 0)
}

function coverageFor(codes: string[], items: NutritionRow[], byItem: Map<string, Map<string, NutritionRow>>) {
  const totalCalories = items.reduce((sum, item) => sum + Number(item.calories_kcal ?? 0), 0)
  if (totalCalories <= 0) return null
  const coveredCalories = items.filter((item) => {
    const values = byItem.get(String(item.id))
    return codes.every((code) => values?.has(code))
  }).reduce((sum, item) => sum + Number(item.calories_kcal ?? 0), 0)
  return coveredCalories / totalCalories
}

function weightForDate(date: string, weights: { recorded_on: string; weight_kg: number }[], fallback: number) {
  return weights.find((weight) => weight.recorded_on <= date)?.weight_kg ?? weights.at(-1)?.weight_kg ?? fallback
}

function average(values: number[]): number | null {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null
}
