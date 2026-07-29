import { createClient } from 'npm:@supabase/supabase-js@2'
import { calculate, type Input } from '../_shared/calculator.ts'
import { cors, json } from '../_shared/http.ts'

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authorization = request.headers.get('Authorization') ?? ''
    const url = Deno.env.get('SUPABASE_URL')!
    const publishable = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!
    const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')!
    const authClient = createClient(url, publishable, { global: { headers: { Authorization: authorization } } })
    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)
    const input = await request.json() as Input
    const result = calculate(input)
    const admin = createClient(url, secret)
    const { data, error } = await admin.rpc('persist_nutrition_plan', { p_user_id: user.id, p_input: input, p_result: result }).single()
    if (error) throw error
    return json(data)
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unable to save plan' }, 400)
  }
})

