import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'

type Row = Record<string, unknown>

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authorization = request.headers.get('Authorization') ?? ''
    const url = Deno.env.get('SUPABASE_URL')!
    const publishable = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!
    const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')!
    const auth = createClient(url, publishable, { global: { headers: { Authorization: authorization } } })
    const { data: { user }, error: authError } = await auth.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)
    const body = await request.json() as { anchor_date?: string }
    const anchor = body.anchor_date ?? ''
    if (!/^\d{4}-\d{2}-\d{2}$/.test(anchor)) return json({ error: 'A valid anchor date is required.' }, 400)

    const admin = createClient(url, secret)
    const start = addDays(anchor, -28)
    const recentStart = addDays(anchor, -2)
    const { data: days, error: dayError } = await admin.from('daily_intake_days')
      .select('local_date,status').eq('user_id', user.id)
      .gte('local_date', start).lt('local_date', anchor)
      .in('status', ['confirmed', 'fasted'])
    if (dayError) throw dayError
    const confirmedDates = new Set((days ?? []).map((row: Row) => String(row.local_date)))
    if (confirmedDates.size < 10) return json(empty(confirmedDates.size))

    const { data: occasions, error: occasionError } = await admin.from('eating_occasions')
      .select('id,local_date').eq('user_id', user.id).gte('local_date', start).lt('local_date', anchor)
    if (occasionError) throw occasionError
    const occasionRows = (occasions ?? []).filter((row: Row) => confirmedDates.has(String(row.local_date))) as Row[]
    const occasionDate = new Map(occasionRows.map((row) => [String(row.id), String(row.local_date)]))
    if (!occasionRows.length) return json(empty(confirmedDates.size))

    const { data: items, error: itemError } = await admin.from('consumption_items')
      .select('id,occasion_id').eq('user_id', user.id)
      .in('occasion_id', [...occasionDate.keys()]).is('deleted_at', null)
    if (itemError) throw itemError
    const itemDate = new Map((items ?? []).map((row: Row) => [String(row.id), occasionDate.get(String(row.occasion_id))!]))
    if (!itemDate.size) return json(empty(confirmedDates.size))

    const { data: nutrients, error: nutrientError } = await admin.from('consumption_item_nutrients')
      .select('consumption_item_id,nutrient_code,amount')
      .in('consumption_item_id', [...itemDate.keys()])
      .in('nutrient_code', ['carbohydrate_g', 'sodium_mg'])
    if (nutrientError) throw nutrientError

    const daily = new Map<string, Record<string, number>>()
    for (const row of (nutrients ?? []) as Row[]) {
      const date = itemDate.get(String(row.consumption_item_id))
      if (!date) continue
      const code = String(row.nutrient_code)
      const totals = daily.get(date) ?? {}
      totals[code] = (totals[code] ?? 0) + Number(row.amount ?? 0)
      daily.set(date, totals)
    }

    const elevated: string[] = []
    for (const code of ['carbohydrate_g', 'sodium_mg']) {
      const baseline = [...daily.entries()]
        .filter(([date, totals]) => date < recentStart && totals[code] != null)
        .map(([, totals]) => totals[code]).sort((a, b) => a - b)
      const recent = [...daily.entries()]
        .filter(([date, totals]) => date >= recentStart && totals[code] != null)
        .map(([, totals]) => totals[code])
      if (baseline.length < 8 || !recent.length) continue
      const recentAverage = recent.reduce((sum, value) => sum + value, 0) / recent.length
      if (recentAverage > quantile(baseline, 0.75)) elevated.push(code)
    }
    return json({ available: true, confirmed_day_count: confirmedDates.size, elevated_nutrients: elevated })
  } catch (error) {
    console.error('weight-fluctuation-context failed', error)
    return json({ error: error instanceof Error ? error.message : 'Unable to load weight context.' }, 400)
  }
})

function empty(days: number) {
  return { available: false, confirmed_day_count: days, elevated_nutrients: [] }
}

function addDays(date: string, amount: number) {
  const value = new Date(`${date}T00:00:00Z`)
  value.setUTCDate(value.getUTCDate() + amount)
  return value.toISOString().slice(0, 10)
}

function quantile(sorted: number[], percentile: number) {
  const position = percentile * (sorted.length - 1)
  const lower = Math.floor(position)
  const upper = Math.ceil(position)
  if (lower === upper) return sorted[lower]
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower)
}
