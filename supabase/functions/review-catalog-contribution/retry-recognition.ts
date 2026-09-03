import { configuredCatalogReviewKey } from "../_shared/catalog-admin.ts";

type Row = Record<string, any>;
type Reviewer =
  | { kind: "admin"; user_id: string; email: string }
  | { kind: "key"; user_id: null; email: "review-key" };

export const RETRY_CONFLICT_MESSAGE =
  "This submission is already being reviewed.";

export class CatalogRetryConflictError extends Error {
  readonly status = 409 as const;
  constructor() {
    super(RETRY_CONFLICT_MESSAGE);
    this.name = "CatalogRetryConflictError";
  }
}

export function isCatalogRetryConflict(
  error: unknown,
): error is CatalogRetryConflictError {
  return error instanceof CatalogRetryConflictError;
}

export async function retryRecognition(
  admin: any,
  contribution: Row,
  reviewer: Reviewer,
  url: string,
  options: {
    catalogReviewKeyValue?: string | null;
    addEvent: (...args: any[]) => Promise<void>;
    waitUntil: (promise: Promise<unknown>) => void;
    fetchImpl?: typeof fetch;
  },
) {
  // Fail-closed before any destructive write: if the internal retry key is
  // missing, we must not queue a job, mark the contribution as processing,
  // or record a status event.
  const key = configuredCatalogReviewKey(
    options.catalogReviewKeyValue ??
      Deno.env.get("CATALOG_REVIEW_KEY"),
  );
  if (!key) {
    throw new Error("Catalog review key is not configured.");
  }

  const now = new Date().toISOString();
  // Claim the contribution first. The revision guard must fail closed before
  // any job row is written, otherwise a concurrent edit leaves a queued job
  // with no worker and no status event.
  const claim = await admin.from("catalog_contributions").update({
    status: "processing",
    review_reason: null,
    updated_at: now,
  }).eq("id", contribution.id).eq("revision", contribution.revision).select(
    "*",
  ).maybeSingle();
  if (claim.error) throw claim.error;
  if (!claim.data) {
    throw new CatalogRetryConflictError();
  }

  try {
    const job = await admin.from("catalog_contribution_jobs").upsert({
      contribution_id: contribution.id,
      user_id: contribution.user_id,
      status: "queued",
      attempts: 0,
      next_attempt_at: now,
      last_error: null,
      started_at: null,
      completed_at: null,
      updated_at: now,
    }, { onConflict: "contribution_id" });
    if (job.error) throw job.error;

    await options.addEvent(
      admin,
      contribution.id,
      String(contribution.status),
      "processing",
      "Recognition retried by catalog review.",
      reviewer,
    );
  } catch (error) {
    await admin.from("catalog_contributions").update({
      status: contribution.status,
      review_reason: contribution.review_reason,
      updated_at: new Date().toISOString(),
    }).eq("id", contribution.id).eq("status", "processing");
    throw error;
  }

  const fetchImpl = options.fetchImpl ?? fetch;
  options.waitUntil(
    fetchImpl(`${url}/functions/v1/manage-catalog-contribution`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-leafy-admin-key": key },
      body: JSON.stringify({
        action: "admin_retry",
        contribution_id: contribution.id,
      }),
    }).then(async (response) => {
      if (!response.ok) {
        throw new Error(
          (await response.json().catch(() => ({})))?.error ??
            "Recognition retry failed.",
        );
      }
    }).catch((error) => console.error("admin catalog retry failed", error)),
  );

  return claim.data;
}
