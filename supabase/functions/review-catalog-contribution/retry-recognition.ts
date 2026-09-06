import { configuredCatalogReviewKey } from "../_shared/catalog-admin.ts";

type Row = Record<string, any>;
type Reviewer =
  | { kind: "admin"; user_id: string; email: string }
  | { kind: "key"; user_id: null; email: "review-key" };

export const RETRY_CONFLICT_MESSAGE =
  "This submission is already being reviewed.";

const RETRYABLE_CONTRIBUTION_STATUSES = [
  "draft",
  "needs_review",
  "pending_review",
];

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

export class CatalogRetryRecoveryError extends Error {
  readonly originalError: unknown;
  readonly recoveryErrors: readonly Error[];

  constructor(originalError: unknown, recoveryErrors: Error[]) {
    const originalMessage = originalError instanceof Error
      ? originalError.message
      : String(originalError);
    super(
      `Recognition retry failed (${originalMessage}) and recovery did not complete: ${
        recoveryErrors.map((error) => error.message).join("; ")
      }`,
    );
    this.name = "CatalogRetryRecoveryError";
    this.originalError = originalError;
    this.recoveryErrors = recoveryErrors;
  }
}

function recoveryError(message: string, error?: unknown) {
  if (error instanceof Error) return new Error(`${message}: ${error.message}`);
  if (error != null) return new Error(`${message}: ${String(error)}`);
  return new Error(message);
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
  // Claim the contribution first. The revision and pre-processing status
  // guards must fail closed before any job row is written, otherwise a
  // concurrent edit or retry can leave a duplicate queued job.
  const claim = await admin.from("catalog_contributions").update({
    status: "processing",
    review_reason: null,
    updated_at: now,
  }).eq("id", contribution.id).eq("revision", contribution.revision).in(
    "status",
    RETRYABLE_CONTRIBUTION_STATUSES,
  ).select("*").maybeSingle();
  if (claim.error) throw claim.error;
  if (!claim.data) throw new CatalogRetryConflictError();

  let queuedJobWritten = false;
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
    queuedJobWritten = true;

    await options.addEvent(
      admin,
      contribution.id,
      String(contribution.status),
      "processing",
      "Recognition retried by catalog review.",
      reviewer,
    );
  } catch (error) {
    const recoveryErrors: Error[] = [];
    const recoveredAt = new Date().toISOString();
    let queuedJobNeutralized = !queuedJobWritten;

    // A queued job is runnable independently of this request. If the status
    // event failed, neutralize that job before restoring the contribution so
    // another request cannot pick up work that was never fully recorded.
    if (queuedJobWritten) {
      try {
        const jobRecovery = await admin.from("catalog_contribution_jobs")
          .update({
            status: "failed",
            last_error:
              "Retry setup failed before its status event was recorded.",
            completed_at: recoveredAt,
            updated_at: recoveredAt,
          })
          .eq("contribution_id", contribution.id)
          .eq("status", "queued")
          .select("id")
          .maybeSingle();
        if (jobRecovery.error) {
          recoveryErrors.push(
            recoveryError(
              "Could not neutralize the queued recognition job",
              jobRecovery.error,
            ),
          );
        } else if (!jobRecovery.data) {
          recoveryErrors.push(
            recoveryError(
              "Could not neutralize the queued recognition job because it was not found",
            ),
          );
        } else {
          queuedJobNeutralized = true;
        }
      } catch (jobRecoveryError) {
        recoveryErrors.push(
          recoveryError(
            "Could not neutralize the queued recognition job",
            jobRecoveryError,
          ),
        );
      }
    }

    // Keep the contribution in processing when the queued job could not be
    // neutralized. It may already be running, so restoring the prior status
    // would make that work appear unclaimed and allow another retry.
    if (!queuedJobNeutralized) {
      throw new CatalogRetryRecoveryError(error, recoveryErrors);
    }

    try {
      const contributionRecovery = await admin.from("catalog_contributions")
        .update({
          status: contribution.status,
          review_reason: contribution.review_reason,
          updated_at: recoveredAt,
        })
        .eq("id", contribution.id)
        .eq("revision", contribution.revision)
        .eq("status", "processing")
        .select("id")
        .maybeSingle();
      if (contributionRecovery.error) {
        recoveryErrors.push(
          recoveryError(
            "Could not restore the claimed catalog contribution",
            contributionRecovery.error,
          ),
        );
      } else if (!contributionRecovery.data) {
        recoveryErrors.push(
          recoveryError(
            "Could not restore the claimed catalog contribution because it no longer matched the claim",
          ),
        );
      }
    } catch (contributionRecoveryError) {
      recoveryErrors.push(
        recoveryError(
          "Could not restore the claimed catalog contribution",
          contributionRecoveryError,
        ),
      );
    }

    if (recoveryErrors.length > 0) {
      throw new CatalogRetryRecoveryError(error, recoveryErrors);
    }
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
