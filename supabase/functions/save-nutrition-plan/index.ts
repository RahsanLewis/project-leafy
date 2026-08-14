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
    const payload = await request.json() as Input & {
      plan_input?: Input
      legal_acceptances?: { terms_version?: number; privacy_version?: number; core_data_use_version?: number; locale?: string; app_version?: string }
    }
    const input = payload.plan_input ?? payload
    const result = calculate(input)
    const admin = createClient(url, secret)
    if (payload.legal_acceptances) {
      const legal = payload.legal_acceptances
      const rows = [
        { document_key: 'terms_of_use', document_version: Number(legal.terms_version ?? 0) },
        { document_key: 'privacy_policy', document_version: Number(legal.privacy_version ?? 0) },
        { document_key: 'core_data_use', document_version: Number(legal.core_data_use_version ?? 0) },
      ]
      if (rows.some((row) => !Number.isInteger(row.document_version) || row.document_version < 1)) {
        return json({ error: 'Current legal and core data-use acceptance is required.' }, 400)
      }
      const accepted = await admin.from('account_legal_acceptances').upsert(rows.map((row) => ({
        user_id: user.id,
        ...row,
        locale: String(legal.locale ?? 'en-US').slice(0, 35),
        app_version: String(legal.app_version ?? 'unknown').slice(0, 40),
      })), { onConflict: 'user_id,document_key,document_version', ignoreDuplicates: true })
      if (accepted.error) throw accepted.error
    }
    const { data, error } = await admin.rpc('persist_nutrition_plan', { p_user_id: user.id, p_input: input, p_result: result }).single()
    if (error) throw error
    return json(data)
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unable to save plan' }, 400)
  }
})
