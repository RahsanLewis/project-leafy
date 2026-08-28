import { requireUser } from '../_shared/auth.ts'
import { cors, errorResponse, json } from '../_shared/http.ts'

type Action = 'status' | 'accept'

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const { user, admin } = await requireUser(request)

    const body = await request.json().catch(() => ({})) as {
      action?: Action
      version?: number
      locale?: string
      app_version?: string
    }
    const version = Number(body.version ?? 0)
    if (!Number.isInteger(version) || version < 1) return json({ error: 'A valid acceptance version is required.' }, 400)

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
    return errorResponse(error, 'Unable to update data-use acknowledgment')
  }
})
