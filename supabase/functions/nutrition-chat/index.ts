import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'

type Body = { action: 'send' | 'list_threads' | 'load_thread' | 'delete_thread'; thread_id?: string; message?: string; client_message_id?: string; local_date?: string }
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

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

    if (body.action === 'list_threads') {
      const result = await admin.from('ai_chat_threads').select('id,title,last_message_at,created_at').eq('user_id', user.id).order('last_message_at', { ascending: false }).limit(50)
      if (result.error) throw result.error
      return json({ threads: result.data ?? [] })
    }
    if (body.action === 'load_thread') {
      const thread = await ownedThread(admin, user.id, body.thread_id)
      const messages = await admin.from('ai_chat_messages').select('id,role,content,sources,suggested_log_description,created_at').eq('thread_id', thread.id).eq('user_id', user.id).order('created_at')
      if (messages.error) throw messages.error
      return json({ thread, messages: messages.data ?? [] })
    }
    if (body.action === 'delete_thread') {
      const thread = await ownedThread(admin, user.id, body.thread_id)
      const deleted = await admin.from('ai_chat_threads').delete().eq('id', thread.id).eq('user_id', user.id)
      if (deleted.error) throw deleted.error
      return json({ ok: true })
    }
    if (body.action !== 'send') return json({ error: 'Unsupported chat action.' }, 400)

    const message = String(body.message ?? '').trim()
    if (!message || message.length > 2000) return json({ error: 'Keep your question between 1 and 2,000 characters.' }, 400)
    if (!body.client_message_id || !uuid.test(body.client_message_id)) return json({ error: 'A client message ID is required.' }, 400)
    const since = new Date(Date.now() - 86_400_000).toISOString()
    const count = await admin.from('ai_chat_messages').select('id', { count: 'exact', head: true }).eq('user_id', user.id).eq('role', 'user').gte('created_at', since)
    if (count.error) throw count.error
    if ((count.count ?? 0) >= Number(Deno.env.get('NUTRITION_CHAT_DAILY_LIMIT') ?? 30)) return json({ error: 'You reached today’s Ask Leafy limit. Try again tomorrow.' }, 429)

    const duplicate = await admin.from('ai_chat_messages').select('thread_id').eq('user_id', user.id).eq('client_message_id', body.client_message_id).maybeSingle()
    if (duplicate.data) return await loadLatest(admin, user.id, duplicate.data.thread_id)

    let thread
    if (body.thread_id) thread = await ownedThread(admin, user.id, body.thread_id)
    else {
      const created = await admin.from('ai_chat_threads').insert({ user_id: user.id, title: titleFor(message) }).select('id,title,last_message_at,created_at').single()
      if (created.error) throw created.error
      thread = created.data
    }

    const historyResult = await admin.from('ai_chat_messages').select('role,content').eq('thread_id', thread.id).eq('user_id', user.id).order('created_at', { ascending: false }).limit(12)
    if (historyResult.error) throw historyResult.error
    const context = await personalContext(admin, user.id, body.local_date)
    const foods = await catalogMatches(admin, message)
    const model = Deno.env.get('OPENAI_CHAT_MODEL') ?? 'gpt-5.6-sol'
    const key = Deno.env.get('OPENAI_API_KEY')
    if (!key) throw new Error('Ask Leafy is not configured yet.')
    const started = Date.now()
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model, store: false, reasoning: { effort: 'low' }, safety_identifier: await safetyID(user.id),
        input: [
          { role: 'system', content: [{ type: 'input_text', text: systemPrompt(context, foods) }] },
          ...(historyResult.data ?? []).reverse().map((row) => ({ role: row.role, content: [{ type: 'input_text', text: row.content }] })),
          { role: 'user', content: [{ type: 'input_text', text: message }] },
        ],
        text: { format: { type: 'json_schema', name: 'leafy_nutrition_chat', strict: true, schema: chatSchema } },
      }),
    })
    const payload = await response.json()
    if (!response.ok) throw new Error(payload?.error?.message ?? 'Ask Leafy could not answer right now.')
    const parsed = JSON.parse(outputText(payload))
    const sources = allowedSources(parsed.source_keys, context, foods)
    const now = new Date().toISOString()
    const userRow = await admin.from('ai_chat_messages').insert({ thread_id: thread.id, user_id: user.id, role: 'user', content: message, client_message_id: body.client_message_id }).select('id,role,content,sources,suggested_log_description,created_at').single()
    if (userRow.error) throw userRow.error
    const assistantRow = await admin.from('ai_chat_messages').insert({
      thread_id: thread.id, user_id: user.id, role: 'assistant', content: String(parsed.answer).slice(0, 8000), sources,
      suggested_log_description: parsed.suggested_log_description || null, model_id: model, provider_response_id: payload.id ?? null,
      input_tokens: payload.usage?.input_tokens ?? null, output_tokens: payload.usage?.output_tokens ?? null, latency_ms: Date.now() - started,
    }).select('id,role,content,sources,suggested_log_description,created_at').single()
    if (assistantRow.error) throw assistantRow.error
    const updated = await admin.from('ai_chat_threads').update({ last_message_at: now, updated_at: now }).eq('id', thread.id).eq('user_id', user.id).select('id,title,last_message_at,created_at').single()
    if (updated.error) throw updated.error
    return json({ thread: updated.data, user_message: userRow.data, assistant_message: assistantRow.data })
  } catch (error) {
    console.error('nutrition-chat failed', error)
    return json({ error: error instanceof Error ? error.message : 'Ask Leafy could not answer right now.' }, 400)
  }
})

// deno-lint-ignore no-explicit-any
async function ownedThread(admin: any, userID: string, id?: string) {
  if (!id || !uuid.test(id)) throw new Error('A valid chat is required.')
  const result = await admin.from('ai_chat_threads').select('id,title,last_message_at,created_at').eq('id', id).eq('user_id', userID).single()
  if (result.error || !result.data) throw new Error('Chat not found.')
  return result.data
}

// deno-lint-ignore no-explicit-any
async function loadLatest(admin: any, userID: string, threadID: string) {
  const thread = await ownedThread(admin, userID, threadID)
  const rows = await admin.from('ai_chat_messages').select('id,role,content,sources,suggested_log_description,created_at').eq('thread_id', threadID).eq('user_id', userID).order('created_at', { ascending: false }).limit(2)
  if (rows.error) throw rows.error
  const messages = (rows.data ?? []).reverse()
  return json({ thread, user_message: messages[0], assistant_message: messages[1] })
}

// deno-lint-ignore no-explicit-any
async function personalContext(admin: any, userID: string, localDate?: string) {
  const day = /^\d{4}-\d{2}-\d{2}$/.test(localDate ?? '') ? localDate! : new Date().toISOString().slice(0, 10)
  const [plan, profile, entries, weights] = await Promise.all([
    admin.from('nutrition_plans').select('calorie_target_kcal,protein_g,carbohydrate_g,fat_g').eq('user_id', userID).order('revision', { ascending: false }).limit(1).maybeSingle(),
    admin.from('profiles').select('goal,pace,target_weight_kg').eq('user_id', userID).maybeSingle(),
    admin.from('food_entries').select('name,calories').eq('user_id', userID).eq('local_date', day),
    admin.from('weight_entries').select('weight_kg,recorded_on').eq('user_id', userID).order('recorded_on', { ascending: false }).limit(30),
  ])
  for (const result of [plan, profile, entries, weights]) if (result.error) throw result.error
  const eaten = (entries.data ?? []).reduce((sum: number, row: { calories: number }) => sum + row.calories, 0)
  const list = weights.data ?? []
  const trend = list.length > 1 ? Number(list[0].weight_kg) - Number(list[list.length - 1].weight_kg) : null
  return { day, plan: plan.data, goal: profile.data, calories_eaten: eaten, foods_logged: (entries.data ?? []).map((x: { name: string }) => x.name), latest_weight_kg: list[0]?.weight_kg ?? null, thirty_day_weight_change_kg: trend }
}

// deno-lint-ignore no-explicit-any
async function catalogMatches(admin: any, query: string) {
  const result = await admin.rpc('search_food_catalog', { p_query: query.slice(0, 120), p_limit: 5 })
  if (result.error) return []
  return (result.data ?? []).slice(0, 5).map((row: Record<string, unknown>) => ({ name: row.description ?? row.canonical_name, brand: row.brand_name ?? null, calories_per_100g: row.calories_per_100g ?? null, source: row.source_system ?? 'Leafy catalog' }))
}

function systemPrompt(context: unknown, foods: unknown[]) {
  return `You are Ask Leafy, an adult general-wellness nutrition assistant. Be practical, concise, nonjudgmental, and transparent about uncertainty. Never diagnose, treat disease, change medication, promote eating-disorder behaviors, or give unsafe rapid-weight-loss guidance. For pregnancy, breastfeeding, eating-disorder recovery, clinician-directed diets, severe symptoms, or medication interactions, provide only broad safety information and recommend an appropriate clinician. Use the private Leafy context only when relevant. Do not claim exact calories without portion details. Catalog candidates may be approximate. If the user clearly describes food they already ate and a reviewable description can be created, set suggested_log_description; otherwise it must be null. Never say food was logged. Return only the requested JSON.\nPRIVATE CONTEXT: ${JSON.stringify(context)}\nCATALOG CANDIDATES: ${JSON.stringify(foods)}`
}

const chatSchema = { type: 'object', additionalProperties: false, properties: { answer: { type: 'string' }, source_keys: { type: 'array', items: { type: 'string', enum: ['plan', 'today', 'weight', 'catalog'] } }, suggested_log_description: { type: ['string', 'null'] } }, required: ['answer', 'source_keys', 'suggested_log_description'] }

// deno-lint-ignore no-explicit-any
function outputText(payload: any) { const text = payload.output_text ?? payload.output?.flatMap((item: any) => item.content ?? []).find((item: any) => item.type === 'output_text')?.text; if (!text) throw new Error('Ask Leafy returned an empty response.'); return text }
function allowedSources(keys: unknown, context: Record<string, unknown>, foods: unknown[]) { const requested = Array.isArray(keys) ? keys : []; const all: Record<string, { kind: string; label: string } | null> = { plan: context.plan ? { kind: 'plan', label: 'Your Leafy plan' } : null, today: { kind: 'log', label: 'Today’s food log' }, weight: context.latest_weight_kg ? { kind: 'weight', label: 'Your weight trend' } : null, catalog: foods.length ? { kind: 'catalog', label: 'Leafy food catalog / USDA' } : null }; return requested.map((key) => all[String(key)]).filter(Boolean) }
function titleFor(message: string) { const compact = message.replace(/\s+/g, ' ').trim(); return compact.length <= 55 ? compact : `${compact.slice(0, 52)}…` }
async function safetyID(userID: string) { const salt = Deno.env.get('OPENAI_SAFETY_SALT') ?? Deno.env.get('SUPABASE_URL') ?? 'leafy'; const bytes = new TextEncoder().encode(`${salt}:${userID}`); const digest = await crypto.subtle.digest('SHA-256', bytes); return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('') }
