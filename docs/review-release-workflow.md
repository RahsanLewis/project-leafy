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
→ Xcode Cloud build/archive
→ internal TestFlight distribution
```

## Implementation and review

Codex works on a scoped feature branch, runs the relevant iOS and backend verification, and opens or updates a pull request against `main`. The pull request must identify release dependencies such as database migrations, Edge Function deployments, data backfills, configuration changes, and client/backend sequencing requirements.

The pull request must pass all required GitHub CI checks and receive an independent Grok review. Codex addresses reviewer blockers on the same feature branch, re-runs the appropriate verification, and pushes the fixes to the existing pull request. CI and independent review repeat until the change is satisfactory.

Codex must not push directly to `main`, merge its own pull request, deploy production backend changes, or upload a TestFlight build.

## Merge and release

A human merges the approved pull request to `main`. Only after the pull request has passed its required checks, passed independent review, and been merged may the release process deploy production backend dependencies and use Xcode Cloud to build and archive the iOS app for internal TestFlight distribution. Backend release dependencies must be deployed in the required order before distributing a client that depends on them.

Promotion to external TestFlight testers remains a manual decision.

## Manual TestFlight fallback

`scripts/upload-testflight.sh` remains available as a manual fallback. Implementation agents must not invoke it automatically. Using the fallback is a separate, post-merge release action performed by an authorized human or release process.
