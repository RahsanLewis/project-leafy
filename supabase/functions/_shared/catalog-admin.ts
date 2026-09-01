/** Fail-closed catalog administration. Never default to a hardcoded email or the service role. */

export function configuredBootstrapAdminEmails(
  raw: string | undefined | null,
): Set<string> {
  if (raw == null) return new Set();
  return new Set(
    raw.split(",").map((value) => value.trim().toLowerCase()).filter(Boolean),
  );
}

export function emailMatchesBootstrapAllowlist(
  email: string | undefined | null,
  allowlist: Set<string>,
): boolean {
  if (!email || allowlist.size === 0) return false;
  return allowlist.has(email.trim().toLowerCase());
}

export function configuredCatalogReviewKey(
  raw: string | undefined | null,
): string | null {
  const value = raw?.trim() ?? "";
  return value.length > 0 ? value : null;
}

export function catalogReviewKeyAuthorizes(
  provided: string | null | undefined,
  configured: string | null,
): boolean {
  if (!configured) return false;
  return provided === configured;
}

export function userContributionQueueStatus(
  missingFieldCount: number,
): "needs_review" | "pending_review" {
  return missingFieldCount > 0 ? "needs_review" : "pending_review";
}
