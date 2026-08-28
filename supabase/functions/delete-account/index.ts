import { requireUser } from '../_shared/auth.ts'
import { cors, errorResponse, json } from '../_shared/http.ts'

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
    const { user, admin } = await requireUser(request)
    const body = await request.json().catch(() => ({}))
    const appleRevoked = body.apple_authorization_code ? await revokeApple(body.apple_authorization_code) : false
    const { data: mediaRows, error: mediaError } = await admin.from('nutrition_media_assets')
      .select('object_path').eq('user_id', user.id).is('deleted_at', null)
    if (mediaError && mediaError.code !== '42P01') throw mediaError
    const { data: labelRows, error: labelError } = await admin.from('product_label_assets')
      .select('object_path').eq('user_id', user.id)
    if (labelError && labelError.code !== '42P01') throw labelError
    const objectPaths = [
      ...(mediaRows ?? []).map((row) => row.object_path),
      ...(labelRows ?? []).map((row) => row.object_path),
    ]
    if (objectPaths.length) {
      const { error: storageError } = await admin.storage.from('nutrition-media').remove(objectPaths)
      if (storageError) throw storageError
    }
    const { error } = await admin.auth.admin.deleteUser(user.id)
    if (error) throw error
    return json({ ok: true, apple_revoked: appleRevoked })
  } catch (error) {
    return errorResponse(error, 'Unable to delete account')
  }
})
