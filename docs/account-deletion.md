# Account deletion contract

This document is the client/server contract for `delete-account` after the D-01/D-02 remediation. It is also the handoff note for iOS.

Baseline reviewed by AppSec: `7c58bf7a`.

## Auth

The function authenticates with `auth.getUser()` from the request `Authorization` bearer token. It never trusts a caller-supplied `user_id` or any other identity field in the JSON body.

`verify_jwt` remains false in `supabase/config.toml` because the function validates the user itself. Unauthenticated requests return HTTP 401 and do not delete.

Only `POST` is accepted (`OPTIONS` for CORS). Other methods return HTTP 405.

## Request

```json
{
  "apple_authorization_code": "<Apple authorization code, required when the account has an Apple identity>"
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `apple_authorization_code` | Required when the authenticated user has a Sign in with Apple identity | UTF-8 string from `ASAuthorizationAppleIDCredential.authorizationCode`. Not the identity token. Extra whitespace is trimmed. |
| `user_id` | Ignored | Present only as a footgun; the authenticated user id is used. |

## Response

Success (HTTP 200) means the Leafy auth user was deleted:

```json
{
  "ok": true,
  "deleted": true,
  "apple_identity": true,
  "apple_revoked": true,
  "apple_revoke_error": null,
  "errors": [],
  "storage_objects_removed": 3
}
```

`apple_revoked` is `true` only when Apple's revoke endpoint returned success. A 200 with `apple_revoked: false` is a partial outcome: the Leafy account is gone, Sign in with Apple cleanup is not.

Failure (HTTP 4xx/5xx) means the Leafy account was **not** deleted:

```json
{
  "ok": false,
  "error": "Apple Sign in must be confirmed before deleting this account.",
  "error_code": "apple_authorization_code_required",
  "apple_identity": true,
  "apple_revoked": false,
  "apple_revoke_error": "missing_authorization_code",
  "errors": ["Apple Sign in must be confirmed before deleting this account."]
}
```

### When delete proceeds vs fails

| Condition | HTTP | Deleted? | `apple_revoked` |
| --- | --- | --- | --- |
| Missing/invalid session | 401 | No | false |
| Non-POST | 405 | No | false |
| Apple identity, no authorization code | 409 `apple_authorization_code_required` | No | false |
| Apple identity, `APPLE_CLIENT_ID` / `APPLE_CLIENT_SECRET` missing | 503 `apple_server_not_configured` | No | false |
| Apple identity, code present, Apple token or revoke HTTP fails | 200 | **Yes** | false, `apple_revoke_error` set, `errors` populated |
| Apple identity, revoke succeeds | 200 | Yes | true |
| No Apple identity | 200 | Yes | false, `apple_revoke_error` null |
| Storage listing/remove fails | 500 `storage_purge_failed` | No | reflects Apple step if it already ran |
| `auth.admin.deleteUser` fails | 500 `user_delete_failed` | No | reflects Apple step if it already ran |

Apple authorization codes are single-use. If Apple consumes the code and then revoke fails, Leafy still deletes the account so the user is not trapped. The response must not be treated as full Sign in with Apple cleanup.

`apple_revoke_error` values: `missing_authorization_code`, `server_not_configured`, `token_exchange_failed`, `revoke_failed`, `invalid_token_response`.

## Storage purge (D-02)

Before `auth.admin.deleteUser`, the function removes **all** `nutrition-media` objects under the authenticated user's prefix (`{user_id}/...`), including:

- `nutrition_media_assets` rows with `deleted_at` set (soft-deleted meal photos)
- `product_label_assets`
- prefix orphans that are in Storage but no longer referenced by a row

`auth.users` cascade deletes media **rows**. It does not reliably delete Storage objects, which is why prefix purge runs first.

## CLIENT UPDATE REQUIRED: YES

### HANDOFF → Senior iOS

Current iOS calls `PlanService.deleteAccount()` with no Apple authorization code (`AppModel.deleteAccount()`, `AccountCenterView`, `CoreDataUseAcknowledgmentView`). `PlanService.deleteAccount(appleAuthorizationCode:)` already accepts the field.

Required client work:

1. If `account.identities` contains `provider == "apple"` (or the user originally signed in with Apple), present `ASAuthorizationAppleIDProvider` as part of the delete confirmation flow and send `authorizationCode` as `apple_authorization_code`.
2. Do not send `identityToken` in that field.
3. Decode `ok`, `deleted`, `apple_revoked`, `apple_revoke_error`, `error`, `error_code`, and `errors`. `EmptyResponse` is no longer sufficient to know whether Apple cleanup succeeded.
4. HTTP 409: re-prompt Apple and retry. Do not tell the user the account was deleted.
5. HTTP 503: ask the user to retry later. Do not tell the user the account was deleted.
6. HTTP 200 with `apple_revoked == false`: the Leafy account is deleted. Do not claim Apple credential revocation succeeded. A generic “account deleted” confirmation is fine; do not invent legal copy about Apple.
7. Deploy the iOS change together with this Edge Function. Shipping the function first will 409 Apple-linked deletions on current TestFlight clients.

## D-03 — retained `food_versions` vs privacy copy (coordination)

This PR does **not** change legal or in-app privacy copy.

Fact from schema/code:

- User-owned rows (`profiles`, plans, food/weight logs, `catalog_contributions`, `product_label_assets`, `nutrition_media_assets`, chat, etc.) reference `auth.users(id) on delete cascade`.
- Accepted catalog contributions may publish `food_versions` with `source_system = 'leafy'` and `source_record_id = contribution.id`. `food_versions` has no `user_id` and is **not** deleted when the contributor’s account is deleted.
- In-app account deletion copy currently says product contributions are permanently removed. That is accurate for the contributor’s private records and label photos (after D-02). It is not necessarily accurate for catalog `food_versions` already published from those contributions.

Privacy/Legal should decide whether retained catalog versions must be unpublished, anonymized, or disclosed. Do not edit privacy policy or settings copy in the client until that decision exists.

## Secrets

Never log `apple_authorization_code`, Apple client secrets, or storage service-role keys. Function secrets remain `APPLE_CLIENT_ID` and `APPLE_CLIENT_SECRET` (see `docs/authentication-setup.md`).
