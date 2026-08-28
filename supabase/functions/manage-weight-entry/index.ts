import { requireUser } from '../_shared/auth.ts'
import { type Input } from '../_shared/calculator.ts'
import { cors, errorResponse, json } from '../_shared/http.ts'
import { findWeightEntryIndex } from '../_shared/weight-entry.ts'

type WeightRow = {
  id: string
  weight_kg: number
  recorded_on: string
  time_zone: string
  source: 'baseline' | 'manual'
}

type RequestBody = {
  action: 'upsert' | 'delete'
  id?: string
  weight_kg?: number
  recorded_on?: string
  time_zone?: string
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const { user, admin } = await requireUser(request)

    const body = await request.json() as RequestBody
    if (body.action !== 'upsert' && body.action !== 'delete') return json({ error: 'Unsupported weight action' }, 400)

    const [{ data: profile, error: profileError }, { data: history, error: historyError }] = await Promise.all([
      admin.from('profiles').select('*').eq('user_id', user.id).single(),
      admin.from('weight_entries').select('*').eq('user_id', user.id).order('recorded_on', { ascending: false }),
    ])
    if (profileError || !profile) throw profileError ?? new Error('Profile not found')
    if (historyError) throw historyError

    const before = (history ?? []) as WeightRow[]
    if (before.length === 0) throw new Error('A starting weight is required')
    const simulated = before.map((entry) => ({ ...entry }))

    if (body.action === 'upsert') {
      const weight = roundWeight(Number(body.weight_kg))
      const date = body.recorded_on ?? ''
      const zone = body.time_zone ?? ''
      if (!Number.isFinite(weight) || weight < 35 || weight > 350) throw new Error('Weight must be between 35 and 350 kg.')
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('Choose a valid date.')
      if (!zone || date > localDate(new Date(), zone)) throw new Error('Weight cannot be logged for a future date.')

      const index = body.id
        ? findWeightEntryIndex(simulated, body.id)
        : simulated.findIndex((entry) => entry.recorded_on === date)
      if (body.id && index < 0) throw new Error('Weight entry not found')
      if (body.id && simulated.some((entry, candidate) => candidate !== index && entry.recorded_on === date)) {
        throw new Error('A weight is already logged for that date.')
      }
      const replacement: WeightRow = {
        id: index >= 0 ? simulated[index].id : crypto.randomUUID(),
        weight_kg: weight,
        recorded_on: date,
        time_zone: zone,
        source: 'manual',
      }
      if (index >= 0) simulated[index] = replacement
      else simulated.push(replacement)
    } else {
      const index = findWeightEntryIndex(simulated, body.id)
      if (index < 0) throw new Error('Weight entry not found')
      if (simulated[index].source === 'baseline') throw new Error('Starting weight cannot be deleted')
      simulated.splice(index, 1)
    }

    simulated.sort((a, b) => b.recorded_on.localeCompare(a.recorded_on))
    const latestBefore = before[0]
    const latestAfter = simulated[0]
    const shouldRecalculate = latestBefore.id !== latestAfter.id
      || Number(latestBefore.weight_kg) !== Number(latestAfter.weight_kg)
      || latestBefore.recorded_on !== latestAfter.recorded_on

    const input: Input = {
      birth_date: profile.birth_date,
      calculation_sex: profile.calculation_sex,
      height_cm: Number(profile.height_cm),
      current_weight_kg: Number(latestAfter.weight_kg),
      target_weight_kg: profile.target_weight_kg == null ? null : Number(profile.target_weight_kg),
      activity_level: profile.activity_level,
      goal: profile.goal,
      pace: profile.pace,
      unit_system: profile.unit_system,
    }

    // Weight changes update the profile and feed the adaptive energy model. They no longer
    // create a new generic formula plan on every weigh-in.
    const outcome = 'tracked'

    const { data, error } = await admin.rpc('persist_weight_change', {
      p_user_id: user.id,
      p_action: body.action,
      p_entry_id: body.id ?? null,
      p_weight_kg: body.weight_kg ?? null,
      p_recorded_on: body.recorded_on ?? null,
      p_time_zone: body.time_zone ?? 'UTC',
      p_input: input,
      p_result: null,
      p_outcome: outcome,
      p_should_recalculate: shouldRecalculate,
      p_expected_latest_date: latestAfter.recorded_on,
      p_expected_latest_weight: latestAfter.weight_kg,
    })
    if (error) throw error
    return json(data)
  } catch (error) {
    console.error('manage-weight-entry failed', error)
    return errorResponse(error, errorMessage(error))
  }
})

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message) return error.message
  if (error && typeof error === 'object') {
    const candidate = error as Record<string, unknown>
    const message = typeof candidate.message === 'string' ? candidate.message : null
    const details = typeof candidate.details === 'string' ? candidate.details : null
    const hint = typeof candidate.hint === 'string' ? candidate.hint : null
    return [message, details, hint].filter(Boolean).join(' ') || 'Unable to update weight'
  }
  return typeof error === 'string' && error ? error : 'Unable to update weight'
}

function roundWeight(weight: number): number {
  return Math.round((weight + Number.EPSILON) * 100) / 100
}

function localDate(date: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(date)
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]))
  return `${value.year}-${value.month}-${value.day}`
}
