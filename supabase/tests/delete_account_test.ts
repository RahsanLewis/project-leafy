import { assert, assertEquals, assertRejects, assertStringIncludes } from 'jsr:@std/assert@1'
import {
  DeleteAccountError,
  chunkPaths,
  collectOwnedObjectPaths,
  collectPathsToPurge,
  deleteAuthenticatedAccount,
  failureBody,
  hasAppleIdentity,
  isUnderUserPrefix,
  listStoragePrefix,
  planAppleRevoke,
  readAppleAuthorizationCode,
  revokeAppleToken,
  userStoragePrefix,
  type AdminGateway,
  type AuthUserLike,
  type StorageGateway,
  type StorageListItem,
} from '../functions/delete-account/account-deletion.ts'

const userId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
const otherUserId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

function user(overrides: Partial<AuthUserLike> = {}): AuthUserLike {
  return { id: userId, identities: [], app_metadata: {}, ...overrides }
}

function memoryStorage(files: Record<string, StorageListItem[]>, removed: string[] = []): StorageGateway {
  return {
    async list(prefix) {
      return { data: files[prefix] ?? [], error: null }
    },
    async remove(paths) {
      removed.push(...paths)
      return { error: null }
    },
  }
}

function adminGateway(input: {
  media?: string[]
  labels?: string[]
  deleted?: string[]
}): AdminGateway {
  return {
    async listNutritionMediaPaths() {
      return input.media ?? []
    },
    async listProductLabelPaths() {
      return input.labels ?? []
    },
    async deleteAuthUser(id) {
      ;(input.deleted ??= []).push(id)
    },
  }
}

Deno.test('D-02: owned path collection includes soft-deleted media and ignores foreign prefixes', () => {
  const paths = collectOwnedObjectPaths(userId, [
    `${userId}/ai-meals/live.jpg`,
    `${userId}/ai-meals/soft-deleted.jpg`,
    `${otherUserId}/ai-meals/not-ours.jpg`,
    '/absolute-should-not-pass',
    '',
  ], [
    `${userId}/catalog-contributions/c1/front-1.jpg`,
  ])
  assertEquals(paths.sort(), [
    `${userId}/ai-meals/live.jpg`,
    `${userId}/ai-meals/soft-deleted.jpg`,
    `${userId}/catalog-contributions/c1/front-1.jpg`,
  ])
})

Deno.test('D-02: prefix listing walks nested folders and keeps only the authenticated user prefix', async () => {
  const storage = memoryStorage({
    [userId]: [
      { name: 'ai-meals', id: null },
      { name: 'catalog-contributions', id: null },
    ],
    [`${userId}/ai-meals`]: [
      { name: 'live.jpg', id: 'file-1' },
      { name: 'soft-deleted.jpg', id: 'file-2' },
    ],
    [`${userId}/catalog-contributions`]: [
      { name: 'c1', id: null },
    ],
    [`${userId}/catalog-contributions/c1`]: [
      { name: 'front-1.jpg', id: 'file-3' },
    ],
  })
  const listed = await listStoragePrefix(storage, userId)
  assertEquals(listed.sort(), [
    `${userId}/ai-meals/live.jpg`,
    `${userId}/ai-meals/soft-deleted.jpg`,
    `${userId}/catalog-contributions/c1/front-1.jpg`,
  ])
})

Deno.test('D-02: purge set unions DB rows (including soft-deleted) with prefix orphans', async () => {
  const removed: string[] = []
  const storage = memoryStorage({
    [userId]: [{ name: 'ai-meals', id: null }],
    [`${userId}/ai-meals`]: [
      { name: 'orphan-after-soft-delete.jpg', id: 'file-orphan' },
    ],
  }, removed)
  const paths = await collectPathsToPurge(
    adminGateway({
      media: [
        `${userId}/ai-meals/soft-deleted.jpg`,
        `${userId}/ai-meals/still-active.jpg`,
      ],
      labels: [`${userId}/catalog-contributions/c1/front-1.jpg`],
    }),
    storage,
    userId,
  )
  assertEquals(paths.sort(), [
    `${userId}/ai-meals/orphan-after-soft-delete.jpg`,
    `${userId}/ai-meals/soft-deleted.jpg`,
    `${userId}/ai-meals/still-active.jpg`,
    `${userId}/catalog-contributions/c1/front-1.jpg`,
  ])
})

Deno.test('D-02: missing storage prefix is treated as empty, not a purge failure', async () => {
  const listed = await listStoragePrefix({
    async list() {
      return { data: null, error: { message: 'The resource was not found', statusCode: '404' } }
    },
    async remove() {
      return { error: null }
    },
  }, userId)
  assertEquals(listed, [])
})

Deno.test('storage prefix helpers reject caller-supplied foreign paths', () => {
  assertEquals(userStoragePrefix(` ${userId.toUpperCase()} `), userId)
  assertEquals(isUnderUserPrefix(`${userId}/ai-meals/x.jpg`, userId), true)
  assertEquals(isUnderUserPrefix(`${otherUserId}/ai-meals/x.jpg`, userId), false)
  assertEquals(chunkPaths(['a', 'b', 'c', 'd'], 2), [['a', 'b'], ['c', 'd']])
})

Deno.test('D-01: Apple identity is read from the authenticated user, not the request body', () => {
  assertEquals(hasAppleIdentity(user()), false)
  assertEquals(hasAppleIdentity(user({ identities: [{ provider: 'email' }] })), false)
  assertEquals(hasAppleIdentity(user({ identities: [{ provider: 'apple' }] })), true)
  assertEquals(hasAppleIdentity(user({ app_metadata: { provider: 'apple' } })), true)
  assertEquals(hasAppleIdentity(user({ app_metadata: { providers: ['google', 'apple'] } })), true)
})

Deno.test('D-01: missing Apple authorization code rejects before any deletion', () => {
  const decision = planAppleRevoke({
    appleIdentity: true,
    authorizationCode: null,
    config: { clientID: 'com.projectleafy.app', clientSecret: 'secret' },
  })
  assertEquals(decision.action, 'reject')
  if (decision.action === 'reject') {
    assertEquals(decision.status, 409)
    assertEquals(decision.code, 'apple_authorization_code_required')
    assertEquals(decision.apple_revoke_error, 'missing_authorization_code')
  }
})

Deno.test('D-01: Apple revoke is not attempted when the user has no Apple identity', () => {
  const decision = planAppleRevoke({
    appleIdentity: false,
    authorizationCode: null,
    config: { clientID: null, clientSecret: null },
  })
  assertEquals(decision.action, 'skip')
})

Deno.test('D-01: missing Apple server secrets reject without claiming success', () => {
  const decision = planAppleRevoke({
    appleIdentity: true,
    authorizationCode: 'code',
    config: { clientID: null, clientSecret: null },
  })
  assertEquals(decision.action, 'reject')
  if (decision.action === 'reject') {
    assertEquals(decision.status, 503)
    assertEquals(decision.apple_revoke_error, 'server_not_configured')
  }
})

Deno.test('D-01: Apple token exchange and revoke succeed only when both HTTP calls succeed', async () => {
  const calls: string[] = []
  const fetchImpl: typeof fetch = async (input, init) => {
    calls.push(`${init?.method} ${String(input)}`)
    const url = String(input)
    if (url.endsWith('/auth/token')) {
      return Response.json({ refresh_token: 'rt', access_token: 'at' })
    }
    return new Response(null, { status: 200 })
  }
  const result = await revokeAppleToken('auth-code', { clientID: 'id', clientSecret: 'secret' }, fetchImpl)
  assertEquals(result, { revoked: true, error: null })
  assertEquals(calls, [
    'POST https://appleid.apple.com/auth/token',
    'POST https://appleid.apple.com/auth/revoke',
  ])
})

Deno.test('D-01: Apple revoke failures are explicit and never reported as revoked', async () => {
  const failedExchange = await revokeAppleToken('code', { clientID: 'id', clientSecret: 'secret' }, async () =>
    new Response('nope', { status: 400 })
  )
  assertEquals(failedExchange, { revoked: false, error: 'token_exchange_failed' })

  const failedRevoke = await revokeAppleToken('code', { clientID: 'id', clientSecret: 'secret' }, async (input) => {
    if (String(input).endsWith('/auth/token')) return Response.json({ access_token: 'at' })
    return new Response('nope', { status: 400 })
  })
  assertEquals(failedRevoke, { revoked: false, error: 'revoke_failed' })

  const missingToken = await revokeAppleToken('code', { clientID: 'id', clientSecret: 'secret' }, async () =>
    Response.json({})
  )
  assertEquals(missingToken, { revoked: false, error: 'invalid_token_response' })
})

Deno.test('D-05/D-06: Apple-linked delete without a code does not purge storage or delete the user', async () => {
  const deleted: string[] = []
  const removed: string[] = []
  const error = await assertRejects(
    () =>
      deleteAuthenticatedAccount({
        user: user({ identities: [{ provider: 'apple' }] }),
        body: { user_id: otherUserId },
        admin: adminGateway({ media: [`${userId}/ai-meals/x.jpg`], deleted }),
        storage: memoryStorage({}, removed),
        appleConfig: { clientID: 'id', clientSecret: 'secret' },
      }),
    DeleteAccountError,
  )
  assertEquals(error.status, 409)
  assertEquals(error.code, 'apple_authorization_code_required')
  assertEquals(deleted, [])
  assertEquals(removed, [])
})

Deno.test('D-05/D-06: caller-provided user_id is ignored; auth user storage is purged before auth delete', async () => {
  const deleted: string[] = []
  const removed: string[] = []
  const result = await deleteAuthenticatedAccount({
    user: user({ identities: [{ provider: 'email' }] }),
    body: { user_id: otherUserId, apple_authorization_code: 'should-be-ignored' },
    admin: adminGateway({
      media: [
        `${userId}/ai-meals/soft-deleted.jpg`,
        `${otherUserId}/ai-meals/foreign.jpg`,
      ],
      deleted,
    }),
    storage: memoryStorage({
      [userId]: [{ name: 'ai-meals', id: null }],
      [`${userId}/ai-meals`]: [{ name: 'orphan.jpg', id: 'file-1' }],
    }, removed),
    appleConfig: { clientID: 'id', clientSecret: 'secret' },
  })
  assertEquals(result.ok, true)
  assertEquals(result.deleted, true)
  assertEquals(result.apple_identity, false)
  assertEquals(result.apple_revoked, false)
  assertEquals(result.apple_revoke_error, null)
  assertEquals(result.errors, [])
  assertEquals(deleted, [userId])
  assertEquals(removed.sort(), [
    `${userId}/ai-meals/orphan.jpg`,
    `${userId}/ai-meals/soft-deleted.jpg`,
  ])
})

Deno.test('D-01/D-06: Apple revoke API failure still deletes and reports apple_revoked false', async () => {
  const deleted: string[] = []
  const result = await deleteAuthenticatedAccount({
    user: user({ identities: [{ provider: 'apple' }] }),
    body: { apple_authorization_code: 'one-time-code' },
    admin: adminGateway({ deleted }),
    storage: memoryStorage({}),
    appleConfig: { clientID: 'id', clientSecret: 'secret' },
    revokeApple: async () => ({ revoked: false, error: 'revoke_failed' }),
  })
  assertEquals(result.ok, true)
  assertEquals(result.deleted, true)
  assertEquals(result.apple_identity, true)
  assertEquals(result.apple_revoked, false)
  assertEquals(result.apple_revoke_error, 'revoke_failed')
  assert(result.errors[0].includes('Apple token revocation failed'))
  assertEquals(deleted, [userId])
})

Deno.test('D-01/D-06: successful Apple revoke is the only path that sets apple_revoked true', async () => {
  const result = await deleteAuthenticatedAccount({
    user: user({ identities: [{ provider: 'apple' }] }),
    body: { apple_authorization_code: 'one-time-code' },
    admin: adminGateway({}),
    storage: memoryStorage({}),
    appleConfig: { clientID: 'id', clientSecret: 'secret' },
    revokeApple: async () => ({ revoked: true, error: null }),
  })
  assertEquals(result.apple_revoked, true)
  assertEquals(result.apple_revoke_error, null)
  assertEquals(result.errors, [])
})

Deno.test('D-05: storage purge failure does not delete the auth user', async () => {
  const deleted: string[] = []
  const error = await assertRejects(
    () =>
      deleteAuthenticatedAccount({
        user: user(),
        body: {},
        admin: adminGateway({ media: [`${userId}/ai-meals/x.jpg`], deleted }),
        storage: {
          async list() {
            return { data: [], error: null }
          },
          async remove() {
            return { error: { message: 'remove failed' } }
          },
        },
        appleConfig: { clientID: null, clientSecret: null },
      }),
    DeleteAccountError,
  )
  assertEquals(error.code, 'storage_purge_failed')
  assertEquals(deleted, [])
})

Deno.test('authorization code must be a non-empty string when provided', () => {
  assertEquals(readAppleAuthorizationCode({}), null)
  assertEquals(readAppleAuthorizationCode({ apple_authorization_code: '  abc  ' }), 'abc')
  const error = assertThrowsType(() => readAppleAuthorizationCode({ apple_authorization_code: 123 }))
  assertEquals(error.code, 'invalid_request')
})

Deno.test('failure payloads never claim Apple cleanup succeeded', () => {
  const body = failureBody(
    new DeleteAccountError('Apple Sign in must be confirmed before deleting this account.', 409, 'apple_authorization_code_required', {
      apple_identity: true,
      apple_revoked: false,
      apple_revoke_error: 'missing_authorization_code',
    }),
    {
      ok: false,
      error: 'Unable to delete account',
      error_code: 'invalid_request',
      apple_revoked: false,
      apple_revoke_error: null,
      errors: ['Unable to delete account'],
    },
  )
  assertEquals(body.ok, false)
  assertEquals(body.apple_revoked, false)
  assertEquals(body.apple_revoke_error, 'missing_authorization_code')
  assertEquals(body.error_code, 'apple_authorization_code_required')
})

Deno.test('delete-account source no longer skips soft-deleted nutrition media', async () => {
  const source = await Deno.readTextFile(
    new URL('../functions/delete-account/index.ts', import.meta.url),
  )
  const logic = await Deno.readTextFile(
    new URL('../functions/delete-account/account-deletion.ts', import.meta.url),
  )
  assertStringIncludes(source, "from('nutrition_media_assets')")
  assert(!source.includes(".is('deleted_at', null)"), 'purge listing must include soft-deleted rows')
  assertStringIncludes(logic, 'listNutritionMediaPaths')
  assertStringIncludes(logic, 'listStoragePrefix')
  assertStringIncludes(logic, 'apple_authorization_code_required')
  assertStringIncludes(logic, 'apple_revoked')
})

Deno.test('D-03/D-06: user rows cascade from auth.users; published food_versions are catalog data', async () => {
  const media = await Deno.readTextFile(
    new URL('../migrations/202608060002_comprehensive_nutrition.sql', import.meta.url),
  )
  const discovery = await Deno.readTextFile(
    new URL('../migrations/202608060003_product_discovery.sql', import.meta.url),
  )
  const functionSource = await Deno.readTextFile(
    new URL('../functions/manage-catalog-contribution/index.ts', import.meta.url),
  )
  assertStringIncludes(media, 'user_id uuid not null default auth.uid() references auth.users(id) on delete cascade')
  assertStringIncludes(media, 'create table public.nutrition_media_assets')
  assertStringIncludes(discovery, 'user_id uuid not null default auth.uid() references auth.users(id) on delete cascade')
  assertStringIncludes(discovery, 'create table public.catalog_contributions')
  assertStringIncludes(discovery, 'accepted_food_version_id uuid references public.food_versions(id)')
  assertStringIncludes(functionSource, 'source_system: "leafy"')
  const foodVersionsStart = media.indexOf('create table public.food_versions')
  const foodVersionsEnd = media.indexOf('create table public.', foodVersionsStart + 1)
  const foodVersionsTable = media.slice(foodVersionsStart, foodVersionsEnd)
  assert(!foodVersionsTable.includes('auth.users'))
})

function assertThrowsType(fn: () => unknown) {
  try {
    fn()
  } catch (error) {
    if (error instanceof DeleteAccountError) return error
    throw error
  }
  throw new Error('expected DeleteAccountError')
}
