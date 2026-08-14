import { type Input } from './calculator.ts'

export const adaptiveModelVersion = 'leafy-energy-balance-v2-weekly-average'

export type DatedWeight = { recorded_on: string; weight_kg: number }

export type RollingWeeklyTrend = {
  currentAverage: number | null
  previousAverage: number | null
  currentCount: number
  previousCount: number
  weeklyChange: number | null
}

export type AdaptiveCandidate = {
  meanIntake: number
  weightSlope: number
  estimatedExpenditure: number
  rawTarget: number
  target: number
  result: {
    calculator_version: string
    bmr_kcal: number
    tdee_kcal: number
    calorie_target_kcal: number
    protein_g: number
    carbohydrate_g: number
    fat_g: number
    projected_weekly_change_kg: number
    estimated_goal_date: string | null
  }
}

export function theilSenSlope(entries: DatedWeight[]): number {
  const ordered = [...entries].sort((a, b) => a.recorded_on.localeCompare(b.recorded_on))
  const slopes: number[] = []
  for (let i = 0; i < ordered.length; i++) {
    for (let j = i + 1; j < ordered.length; j++) {
      const days = daysBetween(ordered[i].recorded_on, ordered[j].recorded_on)
      if (days > 0) slopes.push((Number(ordered[j].weight_kg) - Number(ordered[i].weight_kg)) / days)
    }
  }
  if (slopes.length === 0) return 0
  slopes.sort((a, b) => a - b)
  const middle = Math.floor(slopes.length / 2)
  return slopes.length % 2 ? slopes[middle] : (slopes[middle - 1] + slopes[middle]) / 2
}

export function rollingWeeklyTrend(entries: DatedWeight[], minimumSamples = 4): RollingWeeklyTrend {
  const daily = [...new Map(
    [...entries]
      .sort((a, b) => a.recorded_on.localeCompare(b.recorded_on))
      .map((entry) => [entry.recorded_on, { ...entry, weight_kg: Number(entry.weight_kg) }]),
  ).values()]
  const latest = daily.at(-1)?.recorded_on
  if (!latest) return { currentAverage: null, previousAverage: null, currentCount: 0, previousCount: 0, weeklyChange: null }
  const currentStart = addDays(latest, -6)
  const previousStart = addDays(latest, -13)
  const previousEnd = addDays(latest, -7)
  const current = daily.filter((entry) => entry.recorded_on >= currentStart && entry.recorded_on <= latest)
  const previous = daily.filter((entry) => entry.recorded_on >= previousStart && entry.recorded_on <= previousEnd)
  const currentAverage = average(current.map((entry) => entry.weight_kg))
  const previousAverage = average(previous.map((entry) => entry.weight_kg))
  return {
    currentAverage,
    previousAverage,
    currentCount: current.length,
    previousCount: previous.length,
    weeklyChange: current.length >= minimumSamples && previous.length >= minimumSamples
      && currentAverage != null && previousAverage != null
      ? currentAverage - previousAverage
      : null,
  }
}

export function adaptiveCandidate(
  input: Input,
  currentTarget: number,
  bmr: number,
  confirmedCalories: number[],
  weights: DatedWeight[],
  now: Date,
): AdaptiveCandidate {
  const meanIntake = confirmedCalories.reduce((sum, value) => sum + value, 0) / confirmedCalories.length
  const trend = rollingWeeklyTrend(weights)
  if (trend.weeklyChange == null || trend.currentAverage == null) {
    throw new Error('Two rolling weeks with at least four weigh-ins each are required.')
  }
  const weightSlope = trend.weeklyChange / 7
  const estimatedExpenditure = meanIntake - 7700 * weightSlope
  const pace = paceAdjustment(input.goal, input.pace)
  let rawTarget = estimatedExpenditure * (1 + pace)
  if (input.goal === 'lose') rawTarget = Math.max(rawTarget, bmr, 1200)

  const roundedRaw = Math.round(rawTarget / 10) * 10
  const target = Math.round(clamp(roundedRaw, currentTarget - 100, currentTarget + 100) / 10) * 10
  const macros = macrosFor(target, input)
  const weeklyChange = input.goal === 'maintain' ? 0 : Math.abs(estimatedExpenditure - target) * 7 / 7700
  let estimatedGoalDate: string | null = null
  if (input.goal !== 'maintain' && input.target_weight_kg != null && weeklyChange > 0) {
    const currentWeight = trend.currentAverage
    const days = Math.ceil(Math.abs(input.target_weight_kg - currentWeight) / weeklyChange * 7)
    const date = new Date(now)
    date.setUTCDate(date.getUTCDate() + days)
    estimatedGoalDate = date.toISOString().slice(0, 10)
  }

  return {
    meanIntake,
    weightSlope,
    estimatedExpenditure,
    rawTarget,
    target,
    result: {
      calculator_version: adaptiveModelVersion,
      bmr_kcal: Math.round(bmr),
      tdee_kcal: Math.round(estimatedExpenditure),
      calorie_target_kcal: target,
      protein_g: macros.protein,
      carbohydrate_g: macros.carbohydrate,
      fat_g: macros.fat,
      projected_weekly_change_kg: weeklyChange,
      estimated_goal_date: estimatedGoalDate,
    },
  }
}

export function isPlausible(candidate: AdaptiveCandidate, bmr: number, latestWeightKG: number): boolean {
  const weeklyWeightFraction = Math.abs(candidate.weightSlope * 7) / latestWeightKG
  return candidate.estimatedExpenditure >= bmr * 0.8
    && candidate.estimatedExpenditure <= bmr * 2.5
    && weeklyWeightFraction <= 0.015
}

function macrosFor(calories: number, input: Input) {
  const referenceWeight = input.goal === 'maintain' ? input.current_weight_kg : input.target_weight_kg!
  const desiredProteinCalories = referenceWeight * (input.goal === 'maintain' ? 1.2 : 1.6) * 4
  const proteinCalories = clamp(desiredProteinCalories, calories * 0.10, calories * 0.35)
  let fatCalories = calories * 0.30
  const minimumCarbohydrateCalories = calories * 0.45
  if (calories - proteinCalories - fatCalories < minimumCarbohydrateCalories) {
    fatCalories = Math.max(calories * 0.20, calories - proteinCalories - minimumCarbohydrateCalories)
  }
  return {
    protein: Math.round(proteinCalories / 4),
    carbohydrate: Math.round((calories - proteinCalories - fatCalories) / 4),
    fat: Math.round(fatCalories / 9),
  }
}

function paceAdjustment(goal: Input['goal'], pace: Input['pace']) {
  if (goal === 'maintain') return 0
  if (goal === 'lose') return pace === 'gentle' ? -0.10 : pace === 'steady' ? -0.15 : -0.20
  return pace === 'gentle' ? 0.05 : pace === 'steady' ? 0.10 : 0.15
}

function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(Math.max(value, minimum), maximum)
}

function daysBetween(first: string, second: string) {
  return Math.round((Date.parse(`${second}T00:00:00Z`) - Date.parse(`${first}T00:00:00Z`)) / 86_400_000)
}

function addDays(date: string, amount: number) {
  const value = new Date(`${date}T00:00:00Z`)
  value.setUTCDate(value.getUTCDate() + amount)
  return value.toISOString().slice(0, 10)
}

function average(values: number[]): number | null {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null
}
