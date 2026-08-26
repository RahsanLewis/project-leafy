# Leafy release policy

For every completed user-facing implementation plan, production release is part of the definition of done. User-facing work includes iOS behavior or configuration and production backend behavior consumed by the app. Documentation, tests, and tooling-only changes do not require a TestFlight build.

Before declaring qualifying work complete:

1. Run the relevant iOS and backend verification.
2. Deploy required production migrations, Edge Functions, and data backfills before shipping a dependent client.
3. Create a scoped commit containing only the completed plan and push the current branch.
4. Upload the matching clean commit with `./scripts/upload-testflight.sh` as an internal-only TestFlight build.
5. Report the commit SHA, deployed backend changes, marketing version, and TestFlight build number.

Do not include unrelated user changes in a release commit. If verification, production deployment, Git push, or TestFlight upload fails, preserve recoverable state, stop at the failed gate, and report the blocker instead of claiming the plan is complete or released. External tester promotion remains manual.
