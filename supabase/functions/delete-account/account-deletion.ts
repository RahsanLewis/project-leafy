export const NUTRITION_MEDIA_BUCKET = 'nutrition-media'
export const STORAGE_REMOVE_CHUNK = 100
const LIST_PAGE = 1000
const MAX_LISTED_PATHS = 10_000
const MAX_LISTED_DIRECTORIES = 5_000

export type AppleRevokeErrorCode =
  | 'missing_authorization_code'
  | 'server_not_configured'
  | 'token_exchange_failed'
  | 'revoke_failed'
  | 'invalid_token_response'

export type DeleteAccountErrorCode =
  | 'unauthorized'
  | 'method_not_allowed'
  | 'apple_authorization_code_required'
  | 'apple_server_not_configured'
  | 'storage_purge_failed'
  | 'user_delete_failed'
  | 'invalid_request'

export class DeleteAccountError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: DeleteAccountErrorCode,
    readonly details: Record<string, unknown> = {},
  ) {
    super(message)
    this.name = 'DeleteAccountError'
  }
}

export type AuthUserLike = {
  id: string
  identities?: Array<{ provider?: string | null } | null> | null
  app_metadata?: { provider?: string | null; providers?: string[] | null } | null
}

export type StorageListItem = {
  name: string
  id?: string | null
}

export type StorageGateway = {
  list(
    prefix: string,
    options?: { limit?: number; offset?: number },
  ): Promise<{ data: StorageListItem[] | null; error: { message: string; statusCode?: string | number } | null }>
  remove(paths: string[]): Promise<{ error: { message: string } | null }>
}

export type AdminGateway = {
  listNutritionMediaPaths(userId: string): Promise<string[]>
  listProductLabelPaths(userId: string): Promise<string[]>
  deleteAuthUser(userId: string): Promise<void>
}

export type AppleConfig = {
  clientID: string | null
  clientSecret: string | null
}

export type AppleRevokeResult = {
  revoked: boolean
  error: AppleRevokeErrorCode | null
}

export type DeleteAccountSuccess = {
  ok: true
  deleted: true
  apple_identity: boolean
  apple_revoked: boolean
  apple_revoke_error: AppleRevokeErrorCode | null
  errors: string[]
  storage_objects_removed: number
}

export type DeleteAccountFailure = {
  ok: false
  error: string
  error_code: DeleteAccountErrorCode
  apple_identity?: boolean
  apple_revoked: boolean
  apple_revoke_error: AppleRevokeErrorCode | null
  errors: string[]
}

export type DeleteAccountBody = {
  apple_authorization_code?: unknown
  user_id?: unknown
}

export function userStoragePrefix(userId: string) {
  return userId.trim().toLowerCase()
}

export function isUnderUserPrefix(path: string, userId: string) {
  const prefix = userStoragePrefix(userId)
  const normalized = path.replace(/^\/+/, '')
  return normalized === prefix || normalized.startsWith(`${prefix}/`)
}

export function hasAppleIdentity(user: AuthUserLike) {
  const identities = user.identities ?? []
  if (identities.some((identity) => identity?.provider === 'apple')) return true
  const metadata = user.app_metadata ?? {}
  if (metadata.provider === 'apple') return true
  return (metadata.providers ?? []).includes('apple')
}

export function readAppleAuthorizationCode(body: DeleteAccountBody) {
  const value = body.apple_authorization_code
  if (value == null) return null
  if (typeof value !== 'string') {
    throw new DeleteAccountError('apple_authorization_code must be a string.', 400, 'invalid_request')
  }
  const code = value.trim()
  return code.length ? code : null
}

export function collectOwnedObjectPaths(userId: string, ...groups: Array<Iterable<string> | null | undefined>) {
  const owned = new Set<string>()
  for (const group of groups) {
    for (const path of group ?? []) {
      if (typeof path !== 'string') continue
      const normalized = path.replace(/^\/+/, '').trim()
      if (!normalized) continue
      if (isUnderUserPrefix(normalized, userId)) owned.add(normalized)
    }
  }
  return [...owned]
}

export function chunkPaths(paths: string[], size = STORAGE_REMOVE_CHUNK) {
  const chunks: string[][] = []
  for (let index = 0; index < paths.length; index += size) {
    chunks.push(paths.slice(index, index + size))
  }
  return chunks
}

function isMissingPrefixError(error: { message: string; statusCode?: string | number } | null) {
  if (!error) return false
  if (String(error.statusCode ?? '') === '404') return true
  const message = error.message.toLowerCase()
  return message.includes('not found') || message.includes('does not exist')
}

export async function listStoragePrefix(storage: StorageGateway, userId: string) {
  const root = userStoragePrefix(userId)
  const files: string[] = []
  const queue = [root]
  let directories = 0

  while (queue.length) {
    const directory = queue.shift()!
    directories += 1
    if (directories > MAX_LISTED_DIRECTORIES) {
      throw new DeleteAccountError('Unable to list account media for deletion.', 500, 'storage_purge_failed')
    }

    let offset = 0
    while (true) {
      const { data, error } = await storage.list(directory, { limit: LIST_PAGE, offset })
      if (error) {
        if (isMissingPrefixError(error) && offset === 0) break
        throw new DeleteAccountError('Unable to list account media for deletion.', 500, 'storage_purge_failed')
      }
      const items = data ?? []
      if (!items.length) break

      for (const item of items) {
        if (!item?.name) continue
        const child = `${directory}/${item.name}`.replace(/\/{2,}/g, '/')
        if (!isUnderUserPrefix(child, userId)) continue
        if (item.id) {
          files.push(child)
          if (files.length > MAX_LISTED_PATHS) {
            throw new DeleteAccountError('Unable to list account media for deletion.', 500, 'storage_purge_failed')
          }
        } else {
          queue.push(child)
        }
      }

      if (items.length < LIST_PAGE) break
      offset += items.length
    }
  }

  return files
}

export async function collectPathsToPurge(admin: AdminGateway, storage: StorageGateway, userId: string) {
  const [mediaPaths, labelPaths, listedPaths] = await Promise.all([
    admin.listNutritionMediaPaths(userId),
    admin.listProductLabelPaths(userId),
    listStoragePrefix(storage, userId),
  ])
  return collectOwnedObjectPaths(userId, mediaPaths, labelPaths, listedPaths)
}

export async function purgeOwnedStorage(storage: StorageGateway, paths: string[]) {
  for (const chunk of chunkPaths(paths)) {
    const { error } = await storage.remove(chunk)
    if (error) throw new DeleteAccountError('Unable to delete account media.', 500, 'storage_purge_failed')
  }
}

export function planAppleRevoke(input: {
  appleIdentity: boolean
  authorizationCode: string | null
  config: AppleConfig
}) {
  if (!input.appleIdentity) {
    return { action: 'skip' as const }
  }
  if (!input.config.clientID || !input.config.clientSecret) {
    return {
      action: 'reject' as const,
      status: 503 as const,
      code: 'apple_server_not_configured' as const,
      apple_revoke_error: 'server_not_configured' as const,
      message: 'Apple account revocation is not configured. Try again later.',
    }
  }
  if (!input.authorizationCode) {
    return {
      action: 'reject' as const,
      status: 409 as const,
      code: 'apple_authorization_code_required' as const,
      apple_revoke_error: 'missing_authorization_code' as const,
      message: 'Apple Sign in must be confirmed before deleting this account.',
    }
  }
  return { action: 'attempt' as const, code: input.authorizationCode }
}

export async function revokeAppleToken(
  code: string,
  config: AppleConfig,
  fetchImpl: typeof fetch = fetch,
): Promise<AppleRevokeResult> {
  if (!config.clientID || !config.clientSecret) {
    return { revoked: false, error: 'server_not_configured' }
  }

  const tokenBody = new URLSearchParams({
    client_id: config.clientID,
    client_secret: config.clientSecret,
    code,
    grant_type: 'authorization_code',
  })
  const tokenResponse = await fetchImpl('https://appleid.apple.com/auth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: tokenBody,
  })
  if (!tokenResponse.ok) return { revoked: false, error: 'token_exchange_failed' }

  let tokens: { refresh_token?: unknown; access_token?: unknown }
  try {
    tokens = await tokenResponse.json()
  } catch {
    return { revoked: false, error: 'invalid_token_response' }
  }

  const refreshToken = typeof tokens.refresh_token === 'string' ? tokens.refresh_token : null
  const accessToken = typeof tokens.access_token === 'string' ? tokens.access_token : null
  const token = refreshToken ?? accessToken
  if (!token) return { revoked: false, error: 'invalid_token_response' }

  const revokeBody = new URLSearchParams({
    client_id: config.clientID,
    client_secret: config.clientSecret,
    token,
    token_type_hint: refreshToken ? 'refresh_token' : 'access_token',
  })
  const revokeResponse = await fetchImpl('https://appleid.apple.com/auth/revoke', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: revokeBody,
  })
  if (!revokeResponse.ok) return { revoked: false, error: 'revoke_failed' }
  return { revoked: true, error: null }
}

function appleFailureMessage(error: AppleRevokeErrorCode) {
  switch (error) {
    case 'token_exchange_failed':
      return 'Apple token exchange failed; the Leafy account was still deleted.'
    case 'revoke_failed':
      return 'Apple token revocation failed; the Leafy account was still deleted.'
    case 'invalid_token_response':
      return 'Apple did not return a revocable token; the Leafy account was still deleted.'
    default:
      return 'Apple Sign in with Apple cleanup did not complete; the Leafy account was still deleted.'
  }
}

export async function deleteAuthenticatedAccount(input: {
  user: AuthUserLike
  body: DeleteAccountBody
  admin: AdminGateway
  storage: StorageGateway
  appleConfig: AppleConfig
  revokeApple?: typeof revokeAppleToken
}) {
  const userId = input.user.id
  const appleIdentity = hasAppleIdentity(input.user)
  const authorizationCode = readAppleAuthorizationCode(input.body)
  const plan = planAppleRevoke({ appleIdentity, authorizationCode, config: input.appleConfig })

  if (plan.action === 'reject') {
    throw new DeleteAccountError(plan.message, plan.status, plan.code, {
      apple_identity: true,
      apple_revoked: false,
      apple_revoke_error: plan.apple_revoke_error,
    })
  }

  let appleRevoked = false
  let appleRevokeError: AppleRevokeErrorCode | null = null
  const errors: string[] = []

  let paths: string[]
  try {
    paths = await collectPathsToPurge(input.admin, input.storage, userId)
    await purgeOwnedStorage(input.storage, paths)
  } catch (error) {
    if (error instanceof DeleteAccountError) throw error
    throw new DeleteAccountError('Unable to delete account media.', 500, 'storage_purge_failed', {
      apple_identity: appleIdentity,
      apple_revoked: appleRevoked,
      apple_revoke_error: appleRevokeError,
    })
  }

  try {
    await input.admin.deleteAuthUser(userId)
  } catch {
    throw new DeleteAccountError('Unable to delete account.', 500, 'user_delete_failed', {
      apple_identity: appleIdentity,
      apple_revoked: appleRevoked,
      apple_revoke_error: appleRevokeError,
    })
  }

  // Purge + local auth deletion can fail and must abort before any irreversible external
  // Apple credential revoke happens.
  if (plan.action === 'attempt') {
    const revoke = input.revokeApple ?? revokeAppleToken
    try {
      const result = await revoke(plan.code, input.appleConfig)
      appleRevoked = result.revoked
      appleRevokeError = result.error
    } catch {
      appleRevoked = false
      appleRevokeError = 'token_exchange_failed'
    }
    if (!appleRevoked && appleRevokeError) errors.push(appleFailureMessage(appleRevokeError))
  }

  const response: DeleteAccountSuccess = {
    ok: true,
    deleted: true,
    apple_identity: appleIdentity,
    apple_revoked: appleRevoked,
    apple_revoke_error: appleRevokeError,
    errors,
    storage_objects_removed: paths.length,
  }
  return response
}

export function failureBody(error: unknown, fallback: DeleteAccountFailure): DeleteAccountFailure {
  if (error instanceof DeleteAccountError) {
    const appleIdentity = typeof error.details.apple_identity === 'boolean' ? error.details.apple_identity : fallback.apple_identity
    const appleRevoked = typeof error.details.apple_revoked === 'boolean' ? error.details.apple_revoked : false
    const appleRevokeError = typeof error.details.apple_revoke_error === 'string'
      ? error.details.apple_revoke_error as AppleRevokeErrorCode
      : fallback.apple_revoke_error
    return {
      ok: false,
      error: error.message,
      error_code: error.code,
      apple_identity: appleIdentity,
      apple_revoked: appleRevoked,
      apple_revoke_error: appleRevokeError,
      errors: [error.message],
    }
  }
  return fallback
}
