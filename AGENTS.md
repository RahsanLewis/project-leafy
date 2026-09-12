# Leafy review and release policy

For qualifying implementation work, the implementation agent's responsibility ends with a review-ready pull request. Qualifying work includes iOS behavior or configuration and production backend behavior consumed by the app.

Before declaring qualifying implementation work review-ready, the implementation agent must:

1. Work on a scoped feature branch.
2. Run the relevant iOS and backend verification.
3. Identify any required migrations, Edge Function deployments, data backfills, or other release dependencies in the pull request.
4. Create a scoped commit containing only the completed work.
5. Push the feature branch.
6. Open or update a pull request against `main`.
7. Report the commit SHA and verification results.

The implementation agent must not:

- Push directly to `main`.
- Merge its own pull request.
- Deploy production backend changes.
- Upload a TestFlight build.

Reviewer findings must be fixed on the same feature branch. After each fix, re-run the appropriate verification, push the new commit, and update the pull request.

## Independent reviewer handoff

When Codex is invoked from a pull request comment containing a Grok review:

- Verify that the review's `Reviewed SHA` matches the current pull request head before changing code.
- If the reviewed SHA does not match the current pull request head, do not implement the stale review.
- Address all `BLOCKER` and `IMPORTANT` findings.
- Treat `SUGGESTION` findings as non-blocking. Do not implement them unless the user requests them or a blocking fix requires them.
- Keep fixes on the existing pull request branch.
- Run the relevant verification after making fixes.
- Push fixes to the same pull request.
- Never merge the pull request.
- Never deploy production changes.
- Never upload a build to TestFlight.

## CI completion policy

For normal pull requests, Codex treats these as the required completion gates for
the current pull request head SHA:

- GitHub `backend-tests` passed.
- The `Leafy Test Bot / PR Tests` commit status is `success`.
- The independent Grok review result is `REVIEW PASSED`.

The Leafy Test Bot runs the iOS build, all `LeafyTests`, and the four-test PR UI
smoke suite against the exact pull request head. GitHub Actions owns the fast
backend test gate. Codex must not wait for the removed GitHub-hosted `ios-build`,
`ios-unit-tests`, or `ios-ui-smoke-tests` jobs.

A new commit invalidates both the previous `Leafy Test Bot / PR Tests` status and
the previous Grok review. Codex must require new successful results that identify
the current pull request head SHA.

The complete `ios-ui-tests` suite runs separately after pushes to `main` and on manual workflow dispatch. While LEAFY-027 remains unresolved, the full suite keeps `continue-on-error: true` and is a non-blocking signal. Codex must not wait for it to finish as part of a normal PR task. If it is still running, report that it remains in progress and is non-blocking under LEAFY-027. If it fails, surface the failure for follow-up investigation without retroactively waiting on every pull request or attempting unrelated fixes.

A task specifically concerning UI-test behavior may still run additional targeted UI verification as appropriate.

Production backend deployment and TestFlight distribution occur only after the pull request has passed the required automated checks, passed independent review, and been merged. External TestFlight tester promotion remains manual.

Do not include unrelated user changes in a feature commit. If verification, Git push, or pull request creation fails, preserve recoverable state, stop at the failed gate, and report the blocker instead of claiming the work is review-ready.

Keep `scripts/upload-testflight.sh` as a manual fallback. Implementation agents must not invoke it automatically.
