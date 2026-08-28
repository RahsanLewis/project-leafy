import { requireUser } from '../_shared/auth.ts'
import { adaptiveCandidate, adaptiveModelVersion, isPlausible, rollingWeeklyTrend, type DatedWeight } from '../_shared/adaptive-energy.ts'
import { type Input } from '../_shared/calculator.ts'
import { cors, errorResponse, HTTPError, json } from '../_shared/http.ts'

type Action = 'confirmed' | 'incomplete' | 'fasted' | 'refresh' | 'acknowledge_adjustment'
type RequestBody = { action: Action; local_date?: string; time_zone?: string; adjustment_id?: string }

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const { user, admin } = await requireUser(request)
    const body = await request.json() as RequestBody
    if (body.action === 'acknowledge_adjustment') {
      if (!body.adjustment_id || !isUUID(body.adjustment_id)) return json({ error: 'A valid plan adjustment is required.' }, 400)
      const owned = await admin.from('plan_adjustments').select('id,acknowledged_at')
        .eq('id', body.adjustment_id).eq('user_id', user.id).maybeSingle()
      if (owned.error) throw owned.error
      if (!owned.data) throw new HTTPError(404, 'Plan adjustment not found.')
      if (!owned.data.acknowledged_at) {
        const update = await admin.from('plan_adjustments').update({ acknowledged_at: new Date().toISOString() })
          .eq('id', body.adjustment_id).eq('user_id', user.id)
        if (update.error) throw update.error
      }
      return json({ ok: true })
    }
    if (!body.time_zone) return json({ error: 'A time zone is required.' }, 400)
    let day = null

    if (body.action !== 'refresh') {
      const date = body.local_date ?? ''
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || date >= localDate(new Date(), body.time_zone)) {
        return json({ error: 'Only a past day can be reviewed.' }, 400)
      }
      const { data: entries, error: entryError } = await admin.from('food_entries')
        .select('calories').eq('user_id', user.id).eq('local_date', date)
      if (entryError) throw entryError
      const calories = (entries ?? []).reduce((sum, entry) => sum + Number(entry.calories), 0)
      const count = entries?.length ?? 0
      if (body.action === 'fasted' && count > 0) return json({ error: 'Remove logged food before marking the day as fasted.' }, 400)
      const complete = body.action === 'confirmed' || body.action === 'fasted'
      const payload = {
        user_id: user.id,
        local_date: date,
        status: body.action,
        confirmed_calories: complete ? (body.action === 'fasted' ? 0 : calories) : null,
        confirmed_item_count: complete ? (body.action === 'fasted' ? 0 : count) : null,
        confirmed_at: complete ? new Date().toISOString() : null,
        time_zone: body.time_zone,
        updated_at: new Date().toISOString(),
      }
      const { data, error } = await admin.from('daily_intake_days').upsert(payload).select().single()
      if (error) throw error
      day = data
    }

    const adaptive = await refreshAdaptiveTarget(admin, user.id, body.time_zone)
    return json({ day, ...adaptive })
  } catch (error) {
    console.error('manage-daily-checkin failed', error)
    return errorResponse(error, errorMessage(error))
  }
})

// The service client is intentionally untyped here because this function queries
// tables introduced by a migration that are not part of a generated Database type.
async function refreshAdaptiveTarget(admin: any, userID: string, timeZone: string) {
  const today = localDate(new Date(), timeZone)
  const windowEnd = addDays(today, -1)
  const windowStart = addDays(windowEnd, -27)
  const [{ data: profile, error: profileError }, { data: plans, error: planError }, { data: days, error: dayError }, { data: weights, error: weightError }] = await Promise.all([
    admin.from('profiles').select('*').eq('user_id', userID).single(),
    admin.from('nutrition_plans').select('*').eq('user_id', userID).order('revision', { ascending: false }),
    admin.from('daily_intake_days').select('*').eq('user_id', userID).gte('local_date', windowStart).lte('local_date', windowEnd),
    admin.from('weight_entries').select('recorded_on,weight_kg').eq('user_id', userID).gte('recorded_on', windowStart).lte('recorded_on', windowEnd).order('recorded_on', { ascending: true }),
  ])
  if (profileError || !profile) throw profileError ?? new Error('Profile not found')
  if (planError || dayError || weightError) throw planError ?? dayError ?? weightError
  const currentPlan = plans?.[0]
  if (!currentPlan) return { adaptive_outcome: 'learning', plan: null, adjustment: null }

  const confirmed = (days ?? []).filter((day: any) => day.status === 'confirmed' || day.status === 'fasted')
  const weightRows = (weights ?? []).map((weight: any) => ({ recorded_on: weight.recorded_on, weight_kg: Number(weight.weight_kg) })) as DatedWeight[]
  const rollingTrend = rollingWeeklyTrend(weightRows)
  const latestManual = (plans ?? []).find((plan: any) => (plan.source ?? 'formula') === 'formula')
  const latestAdaptive = (plans ?? []).find((plan: any) => plan.source === 'adaptive')
  let outcome = 'eligible'
  let reason = 'Sufficient confirmed intake and weight history.'

  if (confirmed.length < 24 || weightRows.length < 18) {
    outcome = 'learning'; reason = `Learning: ${confirmed.length}/24 confirmed days and ${weightRows.length}/18 weigh-ins.`
  } else if (rollingTrend.weeklyChange == null) {
    outcome = 'learning'; reason = `Learning: rolling weeks contain ${rollingTrend.currentCount}/4 and ${rollingTrend.previousCount}/4 weigh-ins.`
  } else if (latestManual && daysBetween(latestManual.created_at.slice(0, 10), windowEnd) < 28) {
    outcome = 'learning'; reason = 'The current manual plan is less than 28 days old.'
  } else if (latestAdaptive && daysBetween(latestAdaptive.created_at.slice(0, 10), windowEnd) < 7) {
    outcome = 'unchanged'; reason = 'A personalized update was applied within the last seven days.'
  }

  const input: Input = {
    birth_date: profile.birth_date,
    calculation_sex: profile.calculation_sex,
    height_cm: Number(profile.height_cm),
    current_weight_kg: rollingTrend.currentAverage ?? Number(profile.current_weight_kg),
    target_weight_kg: profile.target_weight_kg == null ? null : Number(profile.target_weight_kg),
    activity_level: profile.activity_level,
    goal: profile.goal,
    pace: profile.pace,
    unit_system: profile.unit_system,
  }
  const calories = confirmed.map((day: any) => Number(day.confirmed_calories))
  const candidate = calories.length && rollingTrend.weeklyChange != null
    ? adaptiveCandidate(input, Number(currentPlan.calorie_target_kcal), Number(currentPlan.bmr_kcal), calories, weightRows, new Date())
    : null
  if (outcome === 'eligible' && candidate && !isPlausible(candidate, Number(currentPlan.bmr_kcal), rollingTrend.currentAverage ?? input.current_weight_kg)) {
    outcome = 'rejected'; reason = 'The observed trend is outside the model safety range.'
  }
  if (outcome === 'eligible' && candidate && Math.abs(candidate.target - Number(currentPlan.calorie_target_kcal)) < 50) {
    outcome = 'unchanged'; reason = 'The personalized target differs by less than 50 calories.'
  }

  const hash = await inputHash(days ?? [], weightRows, currentPlan.id)
  const estimatePayload = {
    user_id: userID, window_start: windowStart, window_end: windowEnd,
    model_version: adaptiveModelVersion, input_revision_hash: hash,
    confirmed_day_count: confirmed.length, weight_count: weightRows.length,
    mean_confirmed_intake_kcal: candidate?.meanIntake ?? null,
    weight_slope_kg_per_day: candidate?.weightSlope ?? null,
    estimated_expenditure_kcal: candidate?.estimatedExpenditure ?? null,
    candidate_target_kcal: candidate?.target ?? null, outcome, reason,
  }
  const { data: estimate, error: estimateError } = await admin.from('adaptive_energy_estimates')
    .upsert(estimatePayload, { onConflict: 'user_id,window_end,model_version,input_revision_hash' }).select().single()
  if (estimateError) throw estimateError

  const applyEnabled = Deno.env.get('ADAPTIVE_TARGET_APPLY_ENABLED') !== 'false'
  if (outcome !== 'eligible' || !candidate || !applyEnabled) {
    if (outcome === 'eligible' && !applyEnabled) {
      await admin.from('adaptive_energy_estimates').update({ outcome: 'shadow', reason: 'Automatic application is disabled.' }).eq('id', estimate.id)
    }
    return { adaptive_outcome: applyEnabled ? outcome : 'shadow', plan: null, adjustment: null }
  }

  const { data, error } = await admin.rpc('persist_adaptive_plan', {
    p_user_id: userID, p_input: input, p_result: candidate.result,
    p_estimate_id: estimate.id, p_previous_target: currentPlan.calorie_target_kcal,
  })
  if (error) throw error
  return { adaptive_outcome: 'applied', plan: data.plan, adjustment: data.adjustment }
}

async function inputHash(days: unknown[], weights: unknown[], planID: string) {
  const bytes = new TextEncoder().encode(JSON.stringify({ days, weights, planID }))
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function localDate(date: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(date)
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]))
  return `${value.year}-${value.month}-${value.day}`
}

function addDays(date: string, amount: number) {
  const value = new Date(`${date}T12:00:00Z`); value.setUTCDate(value.getUTCDate() + amount)
  return value.toISOString().slice(0, 10)
}

function daysBetween(first: string, second: string) {
  return Math.floor((Date.parse(`${second}T00:00:00Z`) - Date.parse(`${first}T00:00:00Z`)) / 86_400_000)
}

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message) return error.message
  if (error && typeof error === 'object' && typeof (error as Record<string, unknown>).message === 'string') return String((error as Record<string, unknown>).message)
  return 'Unable to update the daily check-in.'
}

function isUUID(value: string) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) }
