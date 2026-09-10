# Review and release workflow

Leafy implementation work follows a review-first workflow. An implementation agent finishes at a review-ready pull request; it does not merge or release its own work.

The target workflow is:

```text
Codex implementation
→ GitHub pull request
→ required GitHub CI checks
→ independent Grok review
→ Codex fixes reviewer blockers
→ CI + review repeat until satisfactory
→ human merge to main
→ automatic TestFlight workflow queued for qualifying changes
→ human approval through the protected testflight environment
→ internal TestFlight distribution
```

## Implementation and review

Codex works on a scoped feature branch, runs the relevant iOS and backend verification, and opens or updates a pull request against `main`. The pull request must identify release dependencies such as database migrations, Edge Function deployments, data backfills, configuration changes, and client/backend sequencing requirements.

The pull request must pass all required GitHub CI checks and receive an independent Grok review. Codex addresses reviewer blockers on the same feature branch, re-runs the appropriate verification, and pushes the fixes to the existing pull request. CI and independent review repeat until the change is satisfactory.

Codex must not push directly to `main`, merge its own pull request, deploy production backend changes, or upload a TestFlight build.

## Merge and release

A human merges the approved pull request to `main`. Reviewed code must be merged before a TestFlight release begins. Only after the pull request has passed its required checks, passed independent review, and been merged may the release process deploy production backend dependencies or distribute an internal TestFlight build. Backend release dependencies must be deployed in the required order before distributing a client that depends on them.

Qualifying merges to `main` automatically queue the **TestFlight** workflow in GitHub Actions. Qualifying changes are limited to iOS app, test, configuration, project-generation, and release-script paths, so documentation-only and Supabase-only merges do not trigger a release. The protected `testflight` GitHub environment still requires human approval before the workflow can access its App Store Connect credentials and proceed with the upload. The manual `workflow_dispatch` trigger remains available for authorized releases from `main`.

Promotion to external TestFlight testers remains a manual decision.

## Manual TestFlight fallback

The GitHub Actions workflow delegates release validation, archive, export, and upload to `scripts/upload-testflight.sh`. The script also remains available as a manual fallback. Implementation agents must not invoke it automatically. Using the fallback is a separate, post-merge release action performed by an authorized human or release process.
