import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'
import { normalizeNutrients, nutrientArraySchema, nutrientPrompt } from '../_shared/nutrients.ts'

type NutrientInput = { code: string; amount: number; derivation_method?: string; source_version?: string; confidence?: number }
type Body = {
  action: 'create' | 'update' | 'autofill'
  id?: string
  name?: string
  calories?: number
  consumed_at?: string
  local_date?: string
  time_zone?: string
  amount?: number
  amount_unit?: string
  gram_weight?: number
  portion_description?: string
  meal_type?: string
  nutrients?: NutrientInput[]
}

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
    const admin = createClient(url, secret)
    const body = await request.json() as Body
    if (body.action === 'autofill') return json(await autoFill(user.id, body))
    const values = validatedEntry(body)
    let entry: Record<string, unknown>
    if (body.action === 'create') {
      const result = await admin.from('food_entries').insert({ ...values, user_id: user.id }).select('*').single()
      if (result.error) throw result.error
      entry = result.data
    } else if (body.action === 'update') {
      if (!body.id || !isUUID(body.id)) return json({ error: 'A valid food entry is required.' }, 400)
      const result = await admin.from('food_entries').update({ ...values, updated_at: new Date().toISOString() })
        .eq('id', body.id).eq('user_id', user.id).select('*').single()
      if (result.error) throw result.error
      entry = result.data
    } else return json({ error: 'Unsupported food entry action.' }, 400)

    if (Array.isArray(body.nutrients)) {
      const nutrients = body.nutrients.map(validateNutrient)
      const result = await admin.rpc('replace_food_entry_nutrients', {
        p_user_id: user.id, p_food_entry_id: entry.id, p_nutrients: nutrients,
      })
      if (result.error) throw result.error
    }
    return json({ entry })
  } catch (error) {
    console.error('manage-food-entry failed', error)
    return json({ error: error instanceof Error ? error.message : 'Unable to save that food.' }, 400)
  }
})

function validatedEntry(body: Body) {
  const name = String(body.name ?? '').trim().slice(0, 120)
  const calories = Math.round(Number(body.calories))
  if (!name || calories < 0 || calories > 10000) throw new Error('Enter a food name and calories between 0 and 10,000.')
  if (!body.consumed_at || !/^\d{4}-\d{2}-\d{2}$/.test(body.local_date ?? '') || !body.time_zone) throw new Error('Food date and time are required.')
  const values: Record<string, unknown> = {
    name, calories, consumed_at: body.consumed_at, local_date: body.local_date,
    time_zone: String(body.time_zone).slice(0, 80), meal_type: validMealType(body.meal_type),
    user_confirmed: true, entry_source: 'manual', calorie_method: 'user_entered',
    provenance: { capture_version: 'ios-nutrients-v1' },
  }
  for (const key of ['amount', 'amount_unit', 'gram_weight', 'portion_description'] as const) {
    if (body[key] != null && body[key] !== '') values[key] = body[key]
  }
  return values
}

function validateNutrient(value: NutrientInput) {
  const amount = Number(value.amount)
  if (!value.code || !Number.isFinite(amount) || amount < 0) throw new Error('Review the nutrient values before saving.')
  const method = ['laboratory', 'label', 'calculated', 'estimated', 'user_entered'].includes(value.derivation_method ?? '')
    ? value.derivation_method : 'user_entered'
  return {
    code: value.code, amount, derivation_method: method,
    source_version: String(value.source_version ?? '').slice(0, 120),
    confidence: value.confidence == null ? null : Math.min(1, Math.max(0, Number(value.confidence))),
  }
}

async function autoFill(userID: string, body: Body) {
  const name = String(body.name ?? '').trim().slice(0, 120)
  const calories = Math.round(Number(body.calories))
  if (!name || calories < 0 || calories > 10000) throw new Error('Enter a food name and calories before using Auto-fill.')
  const key = Deno.env.get('OPENAI_API_KEY')
  if (!key) throw new Error('AI nutrient estimates are not configured yet.')
  const model = Deno.env.get('OPENAI_MEAL_MODEL') ?? 'gpt-5.6-terra'
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model, store: false, reasoning: { effort: 'low' }, safety_identifier: await safetyID(userID),
      input: [
        { role: 'system', content: [{ type: 'input_text', text: `You estimate food composition for a general-wellness nutrition log. ${nutrientPrompt()} Return only the structured result.` }] },
        { role: 'user', content: [{ type: 'input_text', text: `Food: ${name}\nLogged calories: ${calories}\nServing: ${body.portion_description ?? 'not specified'}\nGrams: ${body.gram_weight ?? 'not specified'}` }] },
      ],
      text: { format: { type: 'json_schema', name: 'leafy_nutrient_estimate', strict: true, schema: {
        type: 'object', additionalProperties: false, required: ['nutrients'], properties: { nutrients: nutrientArraySchema },
      } } },
    }),
  })
  const payload = await response.json()
  if (!response.ok) throw new Error(payload?.error?.message ?? 'The AI service could not estimate nutrients.')
  const parsed = JSON.parse(extractOutputText(payload))
  return { nutrients: normalizeNutrients(parsed.nutrients), model_id: model, provider_response_id: payload.id ?? null }
}

function extractOutputText(payload: Record<string, unknown>) {
  if (typeof payload.output_text === 'string') return payload.output_text
  for (const item of (Array.isArray(payload.output) ? payload.output : []) as Record<string, unknown>[]) {
    for (const part of (Array.isArray(item.content) ? item.content : []) as Record<string, unknown>[]) {
      if (part.type === 'output_text' && typeof part.text === 'string') return part.text
    }
  }
  throw new Error('The AI service returned no nutrient estimate.')
}

async function safetyID(userID: string) {
  const salt = Deno.env.get('AI_SAFETY_SALT') ?? Deno.env.get('SUPABASE_SECRET_KEY') ?? 'leafy'
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${salt}:${userID}`))
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('')
}
function isUUID(value: string) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) }
function validMealType(value?: string) { return ['breakfast', 'lunch', 'dinner', 'snack', 'drink', 'supplement', 'unspecified'].includes(value ?? '') ? value : 'unspecified' }
