import { assertEquals, assert, assertAlmostEquals } from 'jsr:@std/assert@1'
import { calculate } from '../functions/_shared/calculator.ts'

function assertRejectsExactErrorMessage(
  fn: () => unknown,
  expectedMessage: string,
  label: string,
) {
  let didThrow = false
  let err: unknown = undefined

  try {
    fn()
  } catch (e) {
    didThrow = true
    err = e
  }

  assert(didThrow, `${label}: expected to throw`)
  assert(err instanceof Error, `${label}: expected thrown value to be an Error`)
  assertEquals((err as Error).message, expectedMessage)
}

Deno.test('male steady loss matches the Swift fixture', () => {
  const result = calculate({
    birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180,
    current_weight_kg: 90, target_weight_kg: 80, activity_level: 'moderate',
    goal: 'lose', pace: 'steady', unit_system: 'metric',
  }, new Date('2026-07-29T12:00:00Z'))
  assertEquals(result.bmr_kcal, 1880)
  assertEquals(result.tdee_kcal, 2914)
  assertEquals(result.calorie_target_kcal, 2480)
  assertEquals(result.protein_g, 128)
  assertEquals(result.fat_g, 83)
  assertEquals(result.carbohydrate_g, 306)
  assertAlmostEquals(result.projected_weekly_change_kg, 0.39454545454545453, 1e-9)
  assertEquals(result.estimated_goal_date, '2027-01-23')
})

Deno.test('maintain has no date and zero weekly change', () => {
  const result = calculate({
    birth_date: '1986-01-01', calculation_sex: 'female', height_cm: 165,
    current_weight_kg: 65, activity_level: 'light',
    goal: 'maintain', pace: 'steady', unit_system: 'imperial',
  }, new Date('2026-07-29T12:00:00Z'))
  assertAlmostEquals(result.projected_weekly_change_kg, 0, 0.0001)
  assertEquals(result.estimated_goal_date, null)
})

const now = new Date('2026-07-29T12:00:00Z')

Deno.test('msj-amdr-v1 calculator: boundary + floor + acceptance matrix (table-driven)', () => {
  type WeeklyAssertion =
    | { mode: 'exact'; value: number }
    | { mode: 'almost'; value: number; errorBound?: number }

  type SuccessCase = {
    label: string
    input: Parameters<typeof calculate>[0]
    expected: Partial<{
      bmr_kcal: number
      tdee_kcal: number
      calorie_target_kcal: number
      protein_g: number
      carbohydrate_g: number
      fat_g: number
      projected_weekly_change_kg: WeeklyAssertion
      estimated_goal_date: string | null
    }>
  }

  // IMPORTANT (nutrition-policy review): maintain and gain intentionally have NO calorie floor.
  // These cases pin behavior at accepted input boundaries, including sub-1200 calorie targets.
  // If this changes, a policy decision + `calculator_version` bump is required (not done in tests).
  const successCases: SuccessCase[] = [
    // A. Numeric weekly-change assertions
    {
      label: 'A1 GOLDEN male steady lose',
      input: {
        birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 80, activity_level: 'moderate',
        goal: 'lose', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1880,
        tdee_kcal: 2914,
        calorie_target_kcal: 2480,
        protein_g: 128,
        carbohydrate_g: 306,
        fat_g: 83,
        projected_weekly_change_kg: { mode: 'almost', value: 0.39454545454545453, errorBound: 1e-9 },
        estimated_goal_date: '2027-01-23',
      },
    },

    // B. Gain smoke tests
    {
      label: 'B2 gain gentle',
      input: {
        birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 70, target_weight_kg: 78, activity_level: 'moderate',
        goal: 'gain', pace: 'gentle', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1680,
        tdee_kcal: 2604,
        calorie_target_kcal: 2730,
        protein_g: 125,
        carbohydrate_g: 353,
        fat_g: 91,
        projected_weekly_change_kg: { mode: 'almost', value: 0.11454545454545455, errorBound: 1e-9 },
        estimated_goal_date: '2027-11-30',
      },
    },
    {
      label: 'B3 gain steady',
      input: {
        birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 70, target_weight_kg: 78, activity_level: 'moderate',
        goal: 'gain', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1680,
        tdee_kcal: 2604,
        calorie_target_kcal: 2860,
        protein_g: 125,
        carbohydrate_g: 376,
        fat_g: 95,
        projected_weekly_change_kg: { mode: 'almost', value: 0.23272727272727273, errorBound: 1e-9 },
        estimated_goal_date: '2027-03-27',
      },
    },
    {
      label: 'B4 gain faster',
      input: {
        birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 70, target_weight_kg: 78, activity_level: 'moderate',
        goal: 'gain', pace: 'faster', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1680,
        tdee_kcal: 2604,
        calorie_target_kcal: 2990,
        protein_g: 125,
        carbohydrate_g: 398,
        fat_g: 100,
        projected_weekly_change_kg: { mode: 'almost', value: 0.3509090909090909, errorBound: 1e-9 },
        estimated_goal_date: '2027-01-05',
      },
    },

    // C. Calorie floor matrix for lose
    {
      label: 'C5 BMR-floor dominant (lose, faster)',
      input: {
        birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 80, activity_level: 'sedentary',
        goal: 'lose', pace: 'faster', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1880,
        tdee_kcal: 2256,
        calorie_target_kcal: 1880,
        protein_g: 128,
        carbohydrate_g: 212,
        fat_g: 58,
        projected_weekly_change_kg: { mode: 'almost', value: 0.3418181818181818, errorBound: 1e-9 },
        estimated_goal_date: '2027-02-19',
      },
    },
    {
      label: 'C6 1200-floor dominant (lose, faster)',
      input: {
        birth_date: '1976-07-01', calculation_sex: 'female', height_cm: 155,
        current_weight_kg: 45, target_weight_kg: 44.5, activity_level: 'light',
        goal: 'lose', pace: 'faster', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1008,
        tdee_kcal: 1386,
        calorie_target_kcal: 1200,
        protein_g: 71,
        carbohydrate_g: 139,
        fat_g: 40,
        projected_weekly_change_kg: { mode: 'almost', value: 0.1687784090909091, errorBound: 1e-9 },
        estimated_goal_date: '2026-08-19',
      },
    },
    {
      label: 'C7 No floor applied (lose, gentle)',
      input: {
        birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 80, activity_level: 'moderate',
        goal: 'lose', pace: 'gentle', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1880,
        tdee_kcal: 2914,
        calorie_target_kcal: 2620,
        protein_g: 128,
        carbohydrate_g: 331,
        fat_g: 87,
      },
    },

    // D. Maintain / gain have NO calorie floor
    {
      label: 'D8 maintain height at 120cm minimum',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 120,
        current_weight_kg: 40, activity_level: 'sedentary',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 809,
        tdee_kcal: 971,
        calorie_target_kcal: 970,
        protein_g: 48,
        carbohydrate_g: 122,
        fat_g: 32,
        projected_weekly_change_kg: { mode: 'exact', value: 0 },
        estimated_goal_date: null,
      },
    },
    {
      label: 'D9 maintain weight at 35kg minimum',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 150,
        current_weight_kg: 35, activity_level: 'sedentary',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 947,
        tdee_kcal: 1136,
        calorie_target_kcal: 1140,
        protein_g: 42,
        carbohydrate_g: 158,
        fat_g: 38,
        projected_weekly_change_kg: { mode: 'exact', value: 0 },
        estimated_goal_date: null,
      },
    },
    {
      label: 'D10 gain below 1200 (sub-1200 reachable)',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 120,
        current_weight_kg: 35, target_weight_kg: 40, activity_level: 'sedentary',
        goal: 'gain', pace: 'gentle', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 759,
        tdee_kcal: 911,
        calorie_target_kcal: 960,
        protein_g: 64,
        carbohydrate_g: 108,
        fat_g: 30,
        projected_weekly_change_kg: { mode: 'almost', value: 0.04472727272727277, errorBound: 1e-9 },
      },
    },
    {
      label: 'E11 maintain male sedentary gentle (weekly exact zero)',
      input: {
        birth_date: '1990-03-15', calculation_sex: 'male', height_cm: 178,
        current_weight_kg: 82, activity_level: 'sedentary',
        goal: 'maintain', pace: 'gentle', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1758,
        tdee_kcal: 2109,
        calorie_target_kcal: 2110,
        protein_g: 98,
        carbohydrate_g: 271,
        fat_g: 70,
        projected_weekly_change_kg: { mode: 'exact', value: 0 },
        estimated_goal_date: null,
      },
    },

    // F. Input boundary acceptance
    {
      label: 'F12 age exactly 18',
      input: {
        birth_date: '2008-07-29', calculation_sex: 'female', height_cm: 165,
        current_weight_kg: 65, activity_level: 'light',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1430,
        tdee_kcal: 1967,
        calorie_target_kcal: 1970,
        protein_g: 78,
        carbohydrate_g: 267,
        fat_g: 66,
      },
    },
    {
      label: 'F13 age exactly 100',
      input: {
        birth_date: '1926-07-29', calculation_sex: 'male', height_cm: 170,
        current_weight_kg: 70, activity_level: 'sedentary',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1268,
        tdee_kcal: 1521,
        calorie_target_kcal: 1520,
        protein_g: 84,
        carbohydrate_g: 182,
        fat_g: 51,
      },
    },
    {
      label: 'F14 height 230 max',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 230,
        current_weight_kg: 120, activity_level: 'athlete',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 2463,
        tdee_kcal: 4679,
        calorie_target_kcal: 4680,
        protein_g: 144,
        carbohydrate_g: 675,
        fat_g: 156,
      },
    },
    {
      label: 'F15 weight 350 max',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 190,
        current_weight_kg: 350, activity_level: 'sedentary',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 4513,
        tdee_kcal: 5415,
        calorie_target_kcal: 5420,
        protein_g: 420,
        carbohydrate_g: 610,
        fat_g: 145,
      },
    },
    // G. very_active multiplier coverage (1.725)
    {
      label: 'G8 very_active maintain',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 80, activity_level: 'very_active',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1750,
        tdee_kcal: 3019,
        calorie_target_kcal: 3020,
        protein_g: 96,
        carbohydrate_g: 433,
        fat_g: 101,
        projected_weekly_change_kg: { mode: 'exact', value: 0 },
        estimated_goal_date: null,
      },
    },
    {
      label: 'G9 very_active lose steady',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 170,
        current_weight_kg: 75, target_weight_kg: 68, activity_level: 'very_active',
        goal: 'lose', pace: 'steady', unit_system: 'metric',
      },
      expected: {
        bmr_kcal: 1472,
        tdee_kcal: 2538,
        calorie_target_kcal: 2160,
        protein_g: 109,
        carbohydrate_g: 269,
        fat_g: 72,
        projected_weekly_change_kg: {
          mode: 'almost',
          value: 0.3439431818181819,
          errorBound: 1e-9,
        },
        estimated_goal_date: '2026-12-19',
      },
    },
  ]

  for (const tc of successCases) {
    const result = calculate(tc.input, now)

    try {
      if (tc.expected.bmr_kcal !== undefined) assertEquals(result.bmr_kcal, tc.expected.bmr_kcal)
      if (tc.expected.tdee_kcal !== undefined) assertEquals(result.tdee_kcal, tc.expected.tdee_kcal)
      if (tc.expected.calorie_target_kcal !== undefined) assertEquals(result.calorie_target_kcal, tc.expected.calorie_target_kcal)
      if (tc.expected.protein_g !== undefined) assertEquals(result.protein_g, tc.expected.protein_g)
      if (tc.expected.carbohydrate_g !== undefined) assertEquals(result.carbohydrate_g, tc.expected.carbohydrate_g)
      if (tc.expected.fat_g !== undefined) assertEquals(result.fat_g, tc.expected.fat_g)
      if (tc.expected.projected_weekly_change_kg !== undefined) {
        const weekly = tc.expected.projected_weekly_change_kg
        if (weekly.mode === 'exact') {
          assertEquals(result.projected_weekly_change_kg, weekly.value)
        } else {
          assertAlmostEquals(
            result.projected_weekly_change_kg,
            weekly.value,
            weekly.errorBound ?? 1e-9,
          )
        }
      }
      if (tc.expected.estimated_goal_date !== undefined) {
        assertEquals(result.estimated_goal_date, tc.expected.estimated_goal_date)
      }
    } catch (err) {
      throw new Error(`${tc.label}: ${(err as Error).message}`)
    }
  }
})

Deno.test('msj-amdr-v1 calculator: rejection cases (exact error messages)', () => {
  const rejectionCases: Array<{
    label: string
    input: Parameters<typeof calculate>[0]
    message: string
  }> = [
    // 16-17. Age bounds
    {
      label: 'age 17 rejected',
      input: {
        birth_date: '2008-07-30', calculation_sex: 'female', height_cm: 165,
        current_weight_kg: 65, activity_level: 'light',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      message: 'Leafy currently supports adults ages 18 through 100.',
    },
    {
      label: 'age 101 rejected',
      input: {
        birth_date: '1925-07-28', calculation_sex: 'male', height_cm: 170,
        current_weight_kg: 70, activity_level: 'sedentary',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      message: 'Leafy currently supports adults ages 18 through 100.',
    },

    // 18-19. Height / weight bounds
    {
      label: 'height 119 rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 119,
        current_weight_kg: 40, activity_level: 'sedentary',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      message: 'Height is outside the supported range.',
    },
    {
      label: 'weight 34 rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 150,
        current_weight_kg: 34, activity_level: 'sedentary',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      message: 'Weight is outside the supported range.',
    },
    {
      label: 'height 231 rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 231,
        current_weight_kg: 120, activity_level: 'sedentary',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      message: 'Height is outside the supported range.',
    },
    {
      label: 'weight 351 rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 190,
        current_weight_kg: 351, activity_level: 'sedentary',
        goal: 'maintain', pace: 'steady', unit_system: 'metric',
      },
      message: 'Weight is outside the supported range.',
    },

    // 20-21. BMI floor for lose
    {
      label: 'lose with current BMI < 18.5 rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 170,
        current_weight_kg: 50, target_weight_kg: 45, activity_level: 'light',
        goal: 'lose', pace: 'steady', unit_system: 'metric',
      },
      message: 'Leafy cannot create a weight-loss plan below a BMI of 18.5.',
    },
    {
      label: 'lose with target BMI < 18.5 rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 170,
        current_weight_kg: 60, target_weight_kg: 50, activity_level: 'light',
        goal: 'lose', pace: 'steady', unit_system: 'metric',
      },
      message: 'Leafy cannot create a weight-loss plan below a BMI of 18.5.',
    },

    // 22-24. Target weight validation (out-of-range / zero)
    // NOTE: Backend intentionally collapses missing-target and out-of-range-target into one message:
    //   (!target || target < 35 || target > 350)
    // so `0` is caught by the falsy check.
    // Swift distinguishes these, but that divergence is under product review — pin current backend behavior.
    {
      label: 'target 20 lose rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 20, activity_level: 'moderate',
        goal: 'lose', pace: 'steady', unit_system: 'metric',
      },
      message: 'A valid target weight is required.',
    },
    {
      label: 'target 400 gain rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 400, activity_level: 'moderate',
        goal: 'gain', pace: 'steady', unit_system: 'metric',
      },
      message: 'A valid target weight is required.',
    },
    {
      label: 'target 0 lose rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 0, activity_level: 'moderate',
        goal: 'lose', pace: 'steady', unit_system: 'metric',
      },
      message: 'A valid target weight is required.',
    },

    // Target weight equals current weight (conflicts)
    {
      label: 'lose target == current rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 90, activity_level: 'moderate',
        goal: 'lose', pace: 'steady', unit_system: 'metric',
      },
      message: 'Target weight conflicts with the selected goal.',
    },
    {
      label: 'gain target == current rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 90, activity_level: 'moderate',
        goal: 'gain', pace: 'steady', unit_system: 'metric',
      },
      message: 'Target weight conflicts with the selected goal.',
    },

    // 22-24. Goal/target conflicts and missing target
    {
      label: 'lose target above current rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 95, activity_level: 'moderate',
        goal: 'lose', pace: 'steady', unit_system: 'metric',
      },
      message: 'Target weight conflicts with the selected goal.',
    },
    {
      label: 'gain target below current rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 90, target_weight_kg: 85, activity_level: 'moderate',
        goal: 'gain', pace: 'steady', unit_system: 'metric',
      },
      message: 'Target weight conflicts with the selected goal.',
    },
    {
      label: 'gain missing target rejected',
      input: {
        birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 180,
        current_weight_kg: 70, activity_level: 'moderate',
        goal: 'gain', pace: 'steady', unit_system: 'metric',
      },
      message: 'A valid target weight is required.',
    },

    // 25. Deficit too small
    {
      label: 'deficit too small rejected',
      input: {
        birth_date: '1966-01-01', calculation_sex: 'female', height_cm: 150,
        current_weight_kg: 50, target_weight_kg: 45, activity_level: 'sedentary',
        goal: 'lose', pace: 'faster', unit_system: 'metric',
      },
      message: 'Leafy cannot create a meaningful generic deficit from these inputs.',
    },
  ]

  for (const tc of rejectionCases) {
    assertRejectsExactErrorMessage(
      () => calculate(tc.input, now),
      tc.message,
      tc.label,
    )
  }
})

Deno.test('msj-amdr-v1 calculator: macro kcal reconstruction drift stays bounded (within ±5 kcal)', () => {
  type CaseForDrift = { label: string; input: Parameters<typeof calculate>[0] }

  // Drift comes from independently rounding each macro (protein/carbs/fat) before recomputing kcal.
  // This is under nutrition-policy review; the test pins current drift so it cannot change silently.
  const driftCases: CaseForDrift[] = [
    // From the success cases above: A1, B2-B4, C5-C7, D8-D10, E11, F12-F15.
    { label: 'A1', input: { birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180, current_weight_kg: 90, target_weight_kg: 80, activity_level: 'moderate', goal: 'lose', pace: 'steady', unit_system: 'metric' } },
    { label: 'B2', input: { birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180, current_weight_kg: 70, target_weight_kg: 78, activity_level: 'moderate', goal: 'gain', pace: 'gentle', unit_system: 'metric' } },
    { label: 'B3', input: { birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180, current_weight_kg: 70, target_weight_kg: 78, activity_level: 'moderate', goal: 'gain', pace: 'steady', unit_system: 'metric' } },
    { label: 'B4', input: { birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180, current_weight_kg: 70, target_weight_kg: 78, activity_level: 'moderate', goal: 'gain', pace: 'faster', unit_system: 'metric' } },
    { label: 'C5', input: { birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180, current_weight_kg: 90, target_weight_kg: 80, activity_level: 'sedentary', goal: 'lose', pace: 'faster', unit_system: 'metric' } },
    { label: 'C6', input: { birth_date: '1976-07-01', calculation_sex: 'female', height_cm: 155, current_weight_kg: 45, target_weight_kg: 44.5, activity_level: 'light', goal: 'lose', pace: 'faster', unit_system: 'metric' } },
    { label: 'C7', input: { birth_date: '1996-07-01', calculation_sex: 'male', height_cm: 180, current_weight_kg: 90, target_weight_kg: 80, activity_level: 'moderate', goal: 'lose', pace: 'gentle', unit_system: 'metric' } },
    { label: 'D8', input: { birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 120, current_weight_kg: 40, activity_level: 'sedentary', goal: 'maintain', pace: 'steady', unit_system: 'metric' } },
    { label: 'D9', input: { birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 150, current_weight_kg: 35, activity_level: 'sedentary', goal: 'maintain', pace: 'steady', unit_system: 'metric' } },
    { label: 'D10', input: { birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 120, current_weight_kg: 35, target_weight_kg: 40, activity_level: 'sedentary', goal: 'gain', pace: 'gentle', unit_system: 'metric' } },
    { label: 'E11', input: { birth_date: '1990-03-15', calculation_sex: 'male', height_cm: 178, current_weight_kg: 82, activity_level: 'sedentary', goal: 'maintain', pace: 'gentle', unit_system: 'metric' } },
    { label: 'F12', input: { birth_date: '2008-07-29', calculation_sex: 'female', height_cm: 165, current_weight_kg: 65, activity_level: 'light', goal: 'maintain', pace: 'steady', unit_system: 'metric' } },
    { label: 'F13', input: { birth_date: '1926-07-29', calculation_sex: 'male', height_cm: 170, current_weight_kg: 70, activity_level: 'sedentary', goal: 'maintain', pace: 'steady', unit_system: 'metric' } },
    { label: 'F14', input: { birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 230, current_weight_kg: 120, activity_level: 'athlete', goal: 'maintain', pace: 'steady', unit_system: 'metric' } },
    { label: 'F15', input: { birth_date: '1990-01-01', calculation_sex: 'male', height_cm: 190, current_weight_kg: 350, activity_level: 'sedentary', goal: 'maintain', pace: 'steady', unit_system: 'metric' } },
  ]

  for (const tc of driftCases) {
    const result = calculate(tc.input, now)
    const reconstructed = result.protein_g * 4 + result.carbohydrate_g * 4 + result.fat_g * 9
    const delta = reconstructed - result.calorie_target_kcal
    assert(Math.abs(delta) <= 5, `${tc.label}: drift=${delta} kcal (reconstructed=${reconstructed}, target=${result.calorie_target_kcal})`)
  }
})
