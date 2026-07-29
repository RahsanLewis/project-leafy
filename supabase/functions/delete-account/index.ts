import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'

async function revokeApple(code: string) {
  const clientID = Deno.env.get('APPLE_CLIENT_ID')
  const clientSecret = Deno.env.get('APPLE_CLIENT_SECRET')
  if (!clientID || !clientSecret) return false
  const tokenBody = new URLSearchParams({ client_id: clientID, client_secret: clientSecret, code, grant_type: 'authorization_code' })
  const tokenResponse = await fetch('https://appleid.apple.com/auth/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: tokenBody })
  if (!tokenResponse.ok) return false
  const tokens = await tokenResponse.json()
  const token = tokens.refresh_token ?? tokens.access_token
  if (!token) return false
  const revokeBody = new URLSearchParams({ client_id: clientID, client_secret: clientSecret, token, token_type_hint: tokens.refresh_token ? 'refresh_token' : 'access_token' })
  const revokeResponse = await fetch('https://appleid.apple.com/auth/revoke', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: revokeBody })
  return revokeResponse.ok
}

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
    const body = await request.json().catch(() => ({}))
    const appleRevoked = body.apple_authorization_code ? await revokeApple(body.apple_authorization_code) : false
    const admin = createClient(url, secret)
    const { error } = await admin.auth.admin.deleteUser(user.id)
    if (error) throw error
    return json({ ok: true, apple_revoked: appleRevoked })
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unable to delete account' }, 400)
  }
})

