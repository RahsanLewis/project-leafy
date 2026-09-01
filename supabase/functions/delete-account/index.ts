import { createClient } from 'npm:@supabase/supabase-js@2'
import { cors, json } from '../_shared/http.ts'
import {
  DeleteAccountError,
  NUTRITION_MEDIA_BUCKET,
  deleteAuthenticatedAccount,
  failureBody,
  type AdminGateway,
  type AppleConfig,
  type AuthUserLike,
  type DeleteAccountBody,
  type StorageGateway,
} from './account-deletion.ts'

const MISSING_TABLE = '42P01'

function appleConfigFromEnv(env: Pick<typeof Deno.env, 'get'> = Deno.env): AppleConfig {
  return {
    clientID: env.get('APPLE_CLIENT_ID'),
    clientSecret: env.get('APPLE_CLIENT_SECRET'),
  }
}

function ignoreMissingTable(error: { code?: string } | null) {
  return Boolean(error && error.code === MISSING_TABLE)
}

function createAdminGateway(admin: ReturnType<typeof createClient>): AdminGateway {
  return {
    async listNutritionMediaPaths(userId) {
      // Include soft-deleted rows. Filtering deleted_at IS NULL orphans Storage objects (D-02).
      const { data, error } = await admin.from('nutrition_media_assets')
        .select('object_path')
        .eq('user_id', userId)
      if (error && !ignoreMissingTable(error)) throw error
      return (data ?? []).map((row: { object_path?: string }) => String(row.object_path ?? '')).filter(Boolean)
    },
    async listProductLabelPaths(userId) {
      const { data, error } = await admin.from('product_label_assets')
        .select('object_path')
        .eq('user_id', userId)
      if (error && !ignoreMissingTable(error)) throw error
      return (data ?? []).map((row: { object_path?: string }) => String(row.object_path ?? '')).filter(Boolean)
    },
    async deleteAuthUser(userId) {
      const { error } = await admin.auth.admin.deleteUser(userId)
      if (error) throw error
    },
  }
}

function createStorageGateway(admin: ReturnType<typeof createClient>): StorageGateway {
  const bucket = admin.storage.from(NUTRITION_MEDIA_BUCKET)
  return {
    list(prefix, options) {
      return bucket.list(prefix, options)
    },
    remove(paths) {
      return bucket.remove(paths)
    },
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (request.method !== 'POST') {
    return json({
      ok: false,
      error: 'Method not allowed',
      error_code: 'method_not_allowed',
      apple_revoked: false,
      apple_revoke_error: null,
      errors: ['Method not allowed'],
    }, 405)
  }

  try {
    const authorization = request.headers.get('Authorization') ?? ''
    const url = Deno.env.get('SUPABASE_URL')!
    const publishable = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!
    const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')!
    const authClient = createClient(url, publishable, { global: { headers: { Authorization: authorization } } })
    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) {
      return json({
        ok: false,
        error: 'Unauthorized',
        error_code: 'unauthorized',
        apple_revoked: false,
        apple_revoke_error: null,
        errors: ['Unauthorized'],
      }, 401)
    }

    const body = await request.json().catch(() => ({})) as DeleteAccountBody
    const admin = createClient(url, secret)
    const result = await deleteAuthenticatedAccount({
      user: user as AuthUserLike,
      body,
      admin: createAdminGateway(admin),
      storage: createStorageGateway(admin),
      appleConfig: appleConfigFromEnv(),
    })
    return json(result)
  } catch (error) {
    const status = error instanceof DeleteAccountError ? error.status : 400
    return json(failureBody(error, {
      ok: false,
      error: 'Unable to delete account',
      error_code: 'invalid_request',
      apple_revoked: false,
      apple_revoke_error: null,
      errors: ['Unable to delete account'],
    }), status)
  }
})
