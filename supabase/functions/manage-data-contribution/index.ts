import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'

type Action = 'status' | 'join' | 'leave'

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

    const body = await request.json().catch(() => ({})) as {
      action?: Action
      jurisdiction_country?: string
      jurisdiction_region?: string
    }
    const action = body.action ?? 'status'
    const admin = createClient(url, secret)

    if (action === 'status') return json(await status(admin, user.id))
    if (action === 'leave') {
      const revokedAt = new Date().toISOString()
      const { error } = await admin.from('consent_grants').update({ revoked_at: revokedAt })
        .eq('user_id', user.id).eq('purpose', 'commercial_dataset').is('revoked_at', null)
      if (error) throw error
      const { error: eligibilityError } = await admin.from('consumption_items')
        .update({ commercial_eligible: false }).eq('user_id', user.id).eq('commercial_eligible', true)
      if (eligibilityError) throw eligibilityError
      return json(await status(admin, user.id))
    }
    if (action !== 'join') return json({ error: 'Unsupported action' }, 400)

    const country = body.jurisdiction_country?.trim().toUpperCase()
    if (!country || !/^[A-Z]{2}$/.test(country)) return json({ error: 'A two-letter country code is required.' }, 400)
    const existing = await status(admin, user.id)
    if (existing.is_participating) return json(existing)

    const { data: document, error: documentError } = await admin.from('consent_documents')
      .select('*').eq('document_key', 'commercial_nutrition_dataset')
      .eq('jurisdiction', 'global').is('retired_at', null).order('version', { ascending: false }).limit(1).single()
    if (documentError || !document) throw documentError ?? new Error('Consent document not found')

    const grantedAt = new Date().toISOString()
    const signatureHash = await sha256(`${user.id}:${document.content_hash}:${grantedAt}:${country}:${body.jurisdiction_region ?? ''}`)
    const { data: grant, error: grantError } = await admin.from('consent_grants').insert({
      user_id: user.id,
      document_id: document.id,
      purpose: 'commercial_dataset',
      jurisdiction_country: country,
      jurisdiction_region: body.jurisdiction_region?.trim() || null,
      data_scopes: ['nutrition_intake', 'weight', 'leafy_activity', 'derived_media'],
      granted_at: grantedAt,
      signature_hash: signatureHash,
    }).select().single()
    if (grantError) throw grantError
    await admin.from('research_subjects').upsert({ user_id: user.id }, { onConflict: 'user_id', ignoreDuplicates: true })
    return json({
      is_participating: true,
      grant,
      document: { title: document.title, body: document.body, version: document.version },
    })
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unable to update data contribution' }, 400)
  }
})

async function status(admin: any, userID: string) {
  const { data: grant, error } = await admin.from('consent_grants').select('*,consent_documents(title,body,version)')
    .eq('user_id', userID).eq('purpose', 'commercial_dataset').is('revoked_at', null)
    .order('granted_at', { ascending: false }).limit(1).maybeSingle()
  if (error) throw error
  return {
    is_participating: grant != null && (grant.expires_at == null || new Date(grant.expires_at) > new Date()),
    grant: grant ?? null,
    document: grant?.consent_documents ?? null,
  }
}

async function sha256(value: string) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(bytes)).map((byte) => byte.toString(16).padStart(2, '0')).join('')
}
