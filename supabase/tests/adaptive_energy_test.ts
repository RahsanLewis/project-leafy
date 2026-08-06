import { assert, assertEquals } from 'jsr:@std/assert@1'
import { adaptiveCandidate, isPlausible, theilSenSlope } from '../functions/_shared/adaptive-energy.ts'
import type { Input } from '../functions/_shared/calculator.ts'

const input: Input = {
  birth_date: '1990-01-01', calculation_sex: 'female', height_cm: 168,
  current_weight_kg: 80, target_weight_kg: 70, activity_level: 'light',
  goal: 'lose', pace: 'steady', unit_system: 'metric',
}

Deno.test('Theil-Sen slope resists one isolated scale outlier', () => {
  const slope = theilSenSlope([
    { recorded_on: '2026-07-01', weight_kg: 80 },
    { recorded_on: '2026-07-08', weight_kg: 79.5 },
    { recorded_on: '2026-07-15', weight_kg: 84 },
    { recorded_on: '2026-07-22', weight_kg: 78.5 },
    { recorded_on: '2026-07-28', weight_kg: 78 },
  ])
  assert(slope < 0)
  assert(Math.abs(slope) < 0.15)
})

Deno.test('adaptive target is capped to 100 calories per update', () => {
  const weights = Array.from({ length: 18 }, (_, index) => ({
    recorded_on: `2026-07-${String(index + 1).padStart(2, '0')}`,
    weight_kg: 80 - index * 0.02,
  }))
  const candidate = adaptiveCandidate(input, 1900, 1500, Array(24).fill(2300), weights, new Date('2026-08-01T12:00:00Z'))
  assertEquals(candidate.target, 2000)
})

Deno.test('implausibly fast weight change is rejected', () => {
  const weights = Array.from({ length: 18 }, (_, index) => ({
    recorded_on: `2026-07-${String(index + 1).padStart(2, '0')}`,
    weight_kg: 80 - index * 0.4,
  }))
  const candidate = adaptiveCandidate(input, 1900, 1500, Array(24).fill(1800), weights, new Date('2026-08-01T12:00:00Z'))
  assertEquals(isPlausible(candidate, 1500, 73.2), false)
})

Deno.test('stable maintenance data estimates logged intake as expenditure', () => {
  const maintain = { ...input, goal: 'maintain' as const, target_weight_kg: null }
  const weights = Array.from({ length: 18 }, (_, index) => ({
    recorded_on: `2026-07-${String(index + 1).padStart(2, '0')}`,
    weight_kg: 80,
  }))
  const candidate = adaptiveCandidate(maintain, 2100, 1500, Array(24).fill(2200), weights, new Date('2026-08-01T12:00:00Z'))
  assertEquals(Math.round(candidate.estimatedExpenditure), 2200)
  assertEquals(candidate.target, 2200)
})
