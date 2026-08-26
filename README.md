# Leafy

Leafy is a native iOS nutrition and weight-management app. It guides eligible adults through goal setup, creates versioned calorie and nutrient targets, supports food and weight logging, and saves authoritative server-calculated revisions in Supabase.

Leafy uses Plus Jakarta Sans under the SIL Open Font License. The bundled license is available at `Leafy/Resources/Fonts/OFL.txt`.

## Requirements

- Xcode 26+
- XcodeGen 2.46+
- Supabase CLI
- iOS 18+ deployment target
- Apple Developer team for Sign in with Apple and TestFlight

## Local setup

1. Run `xcodegen generate` to create `Leafy.xcodeproj`.
2. Debug builds use `Config/Staging.xcconfig`; Release and TestFlight builds use `Config/Production.xcconfig`. Keep their Supabase and Google OAuth clients isolated. Shared public URLs live in `Config/Base.xcconfig`. Never place a service-role key or OAuth client secret in the app.
3. Link the Supabase staging project before local development, then run `supabase db push`. Deploy production changes deliberately by passing its project reference.
4. Configure email/password, Apple, and Google providers separately in both Supabase environments. Enable Sign in with Apple for the app identifier in the Apple Developer portal.
5. Deploy the Edge Functions in `supabase/functions`. For Apple revocation during deletion, configure `APPLE_CLIENT_ID` and a generated `APPLE_CLIENT_SECRET` as function secrets.
6. Configure `OPENAI_API_KEY` as a Supabase function secret for AI meal photo/text estimates and Ask Leafy. Set `OPENAI_MEAL_MODEL` and `OPENAI_CHAT_MODEL` to the approved model IDs. Keep all secrets server-side; never add them to an xcconfig or the iOS app.
7. Select the Apple development team in Xcode, build, and run.

The app intentionally keeps an unsigned onboarding draft in memory. A preview is computed locally; after authentication, the backend validates and recomputes it before persisting an immutable revision.

## Verification

- iOS: `xcodebuild test -project Leafy.xcodeproj -scheme Leafy -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- Backend functions and calculation policy: `deno test --allow-read supabase/tests`
- Backend: start Supabase locally and verify migrations/RLS before deploying.

## TestFlight checklist

Deploy production backend changes before uploading the client: apply required migrations, deploy the referenced Edge Functions, then run the release validator. The validator checks production legal-acceptance storage and every Edge Function used by the Release client before Xcode archives the app.

- Replace all placeholder configuration and legal URLs.
- Supply a real 1024×1024 App Store icon.
- Confirm Apple, Google, and email/password sign-in using real accounts.
- Confirm cross-user reads and direct writes are rejected by RLS.
- Confirm plan creation, revision history, offline cache, sign out, and permanent deletion.
- Complete App Store Connect privacy details for user ID, email, physical characteristics, and health/fitness data.
- Have wellness copy and calculation policy reviewed before inviting external testers.

## Internal dogfood upload

Leafy's release workflow uploads internal-only TestFlight builds. Create an App Store Connect API key and store it outside the repository at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`.

```sh
export ASC_KEY_ID="your-key-id"
export ASC_ISSUER_ID="your-issuer-id"
./scripts/upload-testflight.sh
```

The script requires a clean Git worktree, validates the icon and public legal URLs, assigns a timestamp-based build number, archives with automatic signing, and uploads directly to App Store Connect. API keys and signing credentials must never be committed.
