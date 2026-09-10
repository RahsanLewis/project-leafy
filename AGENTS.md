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

Production backend deployment and TestFlight distribution occur only after the pull request has passed the required automated checks, passed independent review, and been merged. External TestFlight tester promotion remains manual.

Do not include unrelated user changes in a feature commit. If verification, Git push, or pull request creation fails, preserve recoverable state, stop at the failed gate, and report the blocker instead of claiming the work is review-ready.

Keep `scripts/upload-testflight.sh` as a manual fallback. Implementation agents must not invoke it automatically.
