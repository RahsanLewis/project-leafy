import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'

type Action = 'status' | 'accept'

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

    const body = await request.json().catch(() => ({})) as {
      action?: Action
      version?: number
      locale?: string
      app_version?: string
    }
    const version = Number(body.version ?? 0)
    if (!Number.isInteger(version) || version < 1) return json({ error: 'A valid acceptance version is required.' }, 400)
    const admin = createClient(url, secret)

    if ((body.action ?? 'status') === 'accept') {
      const { error } = await admin.from('account_legal_acceptances').upsert({
        user_id: user.id,
        document_key: 'core_data_use',
        document_version: version,
        locale: String(body.locale ?? 'en-US').slice(0, 35),
        app_version: String(body.app_version ?? 'unknown').slice(0, 40),
      }, { onConflict: 'user_id,document_key,document_version', ignoreDuplicates: true })
      if (error) throw error
    }

    const { data, error } = await admin.from('account_legal_acceptances').select('id')
      .eq('user_id', user.id).eq('document_key', 'core_data_use').eq('document_version', version).maybeSingle()
    if (error) throw error
    return json({ accepted: data != null, version })
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unable to update data-use acknowledgment' }, 400)
  }
})
