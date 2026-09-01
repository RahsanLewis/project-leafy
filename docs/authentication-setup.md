# Leafy authentication deployment

The app supports email/password, Sign in with Apple, Google Sign-In, password recovery, scoped sign-out, versioned legal acceptance, universal links, and optional local app locking.

Leafy uses two isolated environments:

| Build | Google Cloud | Supabase | Auth host | App scheme |
| --- | --- | --- | --- | --- |
| Debug | Leafy Staging | `etokppyizagduatnritq` | `auth-staging.projectleafy.app` | `leafy-staging` |
| Release/TestFlight | Leafy Production | `auccbmadpqowyksevygj` | `auth.projectleafy.app` | `leafy` |

Before distributing a build:

1. Host `auth-site/` at `https://auth.projectleafy.app`. Serve the AASA file as `application/json` without redirects.
2. Host the same site at `https://auth-staging.projectleafy.app` for Debug builds. The fallback page automatically selects the correct custom URL scheme from the hostname.
3. Configure each Supabase Authentication URL Configuration independently:
   - Production Site URL: `https://auth.projectleafy.app/auth/callback`; allow `https://auth.projectleafy.app/auth/**` and `leafy://auth/**`.
   - Staging Site URL: `https://auth-staging.projectleafy.app/auth/callback`; allow `https://auth-staging.projectleafy.app/auth/**` and `leafy-staging://auth/**`.
4. Configure Resend as Supabase custom SMTP. Authenticate the sending domain and use a transactional address such as `accounts@projectleafy.app`.
5. Configure Google authentication separately in `Leafy Production` and `Leafy Staging`:
   - Configure an external audience. Keep staging in testing mode; publish production only after its brand and domain details are complete.
   - Configure the brand as `Leafy`, with `https://projectleafy.app` as the homepage and matching privacy, terms, and support pages on that domain. Verify `projectleafy.app` in Google Search Console before publishing the brand.
   - Request only the `openid`, `email`, and `profile` scopes.
   - Create an iOS OAuth client in each project for bundle ID `com.projectleafy.app`.
   - Create a Web OAuth client in each project. Production redirects to `https://auccbmadpqowyksevygj.supabase.co/auth/v1/callback`; staging redirects to `https://etokppyizagduatnritq.supabase.co/auth/v1/callback`.
   - Put each environment's iOS client ID, Web/server client ID, and reversed iOS client ID in its corresponding xcconfig. These identifiers are public configuration, not secrets.
   - In each Supabase project's Google provider, enter that environment's Web client ID first and iOS client ID second, separated by a comma. Store the matching Web client secret only in Supabase and leave nonce verification enabled.
   - Generate a Release build and confirm `GIDClientID`, `GIDServerClientID`, and the Google URL scheme are populated before uploading to TestFlight.
6. Keep email confirmation enabled. Set minimum password length to 8. Do not add composition rules.
7. Deploy migration `202608080002_auth_foundation.sql` and the updated `save-nutrition-plan` and `delete-account` functions.
8. For account deletion, keep `APPLE_CLIENT_ID` and `APPLE_CLIENT_SECRET` configured on the `delete-account` function. The iOS client must send `apple_authorization_code` when the user has a Sign in with Apple identity. See `docs/account-deletion.md` for the request/response contract and when deletion proceeds vs fails.

Never commit OAuth client secrets, the Supabase service role key, Resend API keys, or Apple private keys.
