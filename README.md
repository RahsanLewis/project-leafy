# Leafy

Leafy is a native iOS nutrition-target planner. This first vertical slice guides an eligible adult through goal setup, previews a versioned calorie/macronutrient plan, authenticates with Apple or email OTP, and saves an authoritative server-calculated revision in Supabase.

## Requirements

- Xcode 26+
- XcodeGen 2.46+
- Supabase CLI
- iOS 18+ deployment target
- Apple Developer team for Sign in with Apple and TestFlight

## Local setup

1. Run `xcodegen generate` to create `Leafy.xcodeproj`.
2. Open `Config/Base.xcconfig` and replace the placeholder Supabase URL, publishable key, and hosted legal/support URLs. Never place a service-role key in the app.
3. Create or link a Supabase project in the U.S. East region, then run `supabase db push`.
4. Configure passwordless email OTP and the Apple provider in Supabase. Enable Sign in with Apple for the app identifier in the Apple Developer portal.
5. Deploy `save-nutrition-plan` and `delete-account`. For Apple revocation during deletion, configure `APPLE_CLIENT_ID` and a generated `APPLE_CLIENT_SECRET` as function secrets.
6. Select the Apple development team in Xcode, build, and run.

The app intentionally keeps an unsigned onboarding draft in memory. A preview is computed locally; after authentication, the backend validates and recomputes it before persisting an immutable revision.

## Verification

- iOS: `xcodebuild test -project Leafy.xcodeproj -scheme Leafy -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- Edge calculator: `deno test supabase/tests/calculator_test.ts`
- Backend: start Supabase locally and verify migrations/RLS before deploying.

## TestFlight checklist

- Replace all placeholder configuration and legal URLs.
- Supply a real 1024×1024 App Store icon.
- Confirm Apple and email OTP sign-in using real accounts.
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
