export type Input = {
  birth_date: string
  calculation_sex: 'female' | 'male'
  height_cm: number
  current_weight_kg: number
  target_weight_kg?: number | null
  activity_level: 'sedentary' | 'light' | 'moderate' | 'very_active' | 'athlete'
  goal: 'lose' | 'maintain' | 'gain'
  pace: 'gentle' | 'steady' | 'faster'
  unit_system: 'imperial' | 'metric'
}

const activity = { sedentary: 1.2, light: 1.375, moderate: 1.55, very_active: 1.725, athlete: 1.9 }
const adjustment = {
  lose: { gentle: -0.10, steady: -0.15, faster: -0.20 },
  maintain: { gentle: 0, steady: 0, faster: 0 },
  gain: { gentle: 0.05, steady: 0.10, faster: 0.15 },
}

export function calculate(input: Input, now = new Date()) {
  const birth = new Date(`${input.birth_date}T00:00:00Z`)
  let age = now.getUTCFullYear() - birth.getUTCFullYear()
  const beforeBirthday = now.getUTCMonth() < birth.getUTCMonth() || (now.getUTCMonth() === birth.getUTCMonth() && now.getUTCDate() < birth.getUTCDate())
  if (beforeBirthday) age--
  if (age < 18 || age > 100) throw new Error('Leafy currently supports adults ages 18 through 100.')
  if (input.height_cm < 120 || input.height_cm > 230) throw new Error('Height is outside the supported range.')
  if (input.current_weight_kg < 35 || input.current_weight_kg > 350) throw new Error('Weight is outside the supported range.')
  if (input.goal !== 'maintain') {
    const target = input.target_weight_kg
    if (!target || target < 35 || target > 350) throw new Error('A valid target weight is required.')
    if ((input.goal === 'lose' && target >= input.current_weight_kg) || (input.goal === 'gain' && target <= input.current_weight_kg)) throw new Error('Target weight conflicts with the selected goal.')
    const currentBMI = input.current_weight_kg / Math.pow(input.height_cm / 100, 2)
    const targetBMI = target / Math.pow(input.height_cm / 100, 2)
    if (input.goal === 'lose' && (currentBMI < 18.5 || targetBMI < 18.5)) throw new Error('Leafy cannot create a weight-loss plan below a BMI of 18.5.')
  }

  const bmr = 10 * input.current_weight_kg + 6.25 * input.height_cm - 5 * age + (input.calculation_sex === 'male' ? 5 : -161)
  const tdee = bmr * activity[input.activity_level]
  let targetCalories = tdee * (1 + adjustment[input.goal][input.pace])
  if (input.goal === 'lose') {
    targetCalories = Math.max(targetCalories, bmr, 1200)
    if (tdee - targetCalories < 50) throw new Error('Leafy cannot create a meaningful generic deficit from these inputs.')
  }
  const calories = Math.round(targetCalories / 10) * 10
  const referenceWeight = input.goal === 'maintain' ? input.current_weight_kg : input.target_weight_kg!
  const desiredProteinCalories = referenceWeight * (input.goal === 'maintain' ? 1.2 : 1.6) * 4
  const proteinCalories = Math.min(Math.max(desiredProteinCalories, calories * 0.10), calories * 0.35)
  let fatCalories = calories * 0.30
  const minimumCarbohydrateCalories = calories * 0.45
  if (calories - proteinCalories - fatCalories < minimumCarbohydrateCalories) fatCalories = Math.max(calories * 0.20, calories - proteinCalories - minimumCarbohydrateCalories)
  const carbohydrateCalories = calories - proteinCalories - fatCalories
  const weeklyChange = Math.abs(tdee - calories) * 7 / 7700
  let estimatedDate: string | null = null
  if (input.goal !== 'maintain' && weeklyChange > 0) {
    const days = Math.ceil(Math.abs(input.target_weight_kg! - input.current_weight_kg) / weeklyChange * 7)
    const date = new Date(now); date.setUTCDate(date.getUTCDate() + days)
    estimatedDate = date.toISOString().slice(0, 10)
  }
  return {
    calculator_version: 'msj-amdr-v1', bmr_kcal: Math.round(bmr), tdee_kcal: Math.round(tdee),
    calorie_target_kcal: calories, protein_g: Math.round(proteinCalories / 4),
    carbohydrate_g: Math.round(carbohydrateCalories / 4), fat_g: Math.round(fatCalories / 9),
    projected_weekly_change_kg: weeklyChange, estimated_goal_date: estimatedDate,
  }
}

