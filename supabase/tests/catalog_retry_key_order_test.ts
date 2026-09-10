import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  CatalogRetryConflictError,
  CatalogRetryRecoveryError,
  isCatalogRetryConflict,
  retryRecognition,
} from "../functions/review-catalog-contribution/retry-recognition.ts";

const contribution = {
  id: "c1",
  user_id: "u1",
  status: "pending_review",
  revision: 1,
  review_reason: "Needs clearer photos",
};
const reviewer = {
  kind: "admin" as const,
  user_id: "u1",
  email: "ops@example.com",
};
const catalogReviewKey = "review-key-configured";
const functionUrl = "https://internal.example";
const retryableContributionStatuses = [
  "draft",
  "needs_review",
  "pending_review",
];

type AdminCall = {
  op: "contributions.update" | "jobs.update" | "jobs.upsert";
  table: string;
  payload: Record<string, unknown>;
  opts?: Record<string, unknown>;
  filters?: Array<[string, unknown]>;
};

type QueryResult = { data: unknown; error: unknown };

function recordingAdmin(options: {
  updateResult?: QueryResult;
  rollbackResult?: QueryResult;
  jobResult?: QueryResult;
  jobRecoveryResult?: QueryResult;
  timeline?: string[];
} = {}) {
  const calls: AdminCall[] = [];
  const timeline = options.timeline ?? [];
  const state: { jobStatus: string | null } = { jobStatus: null };
  const updatedRow = {
    ...contribution,
    status: "processing",
    review_reason: null,
  };
  const admin = {
    from(table: string) {
      return {
        upsert(
          payload: Record<string, unknown>,
          opts?: Record<string, unknown>,
        ) {
          calls.push({ op: "jobs.upsert", table, payload, opts });
          timeline.push("jobs.upsert");
          const result = options.jobResult ?? { data: payload, error: null };
          if (!result.error) state.jobStatus = String(payload.status);
          return Promise.resolve(result);
        },
        update(payload: Record<string, unknown>) {
          const op = table === "catalog_contribution_jobs"
            ? "jobs.update"
            : "contributions.update";
          const filters: Array<[string, unknown]> = [];
          calls.push({
            op,
            table,
            payload,
            filters,
          });
          timeline.push(op);
          const result = op === "jobs.update"
            ? options.jobRecoveryResult ?? {
              data: { id: "job-1" },
              error: null,
            }
            : payload.status === "processing"
            ? options.updateResult ?? { data: updatedRow, error: null }
            : options.rollbackResult ?? {
              data: { id: contribution.id },
              error: null,
            };
          const builder = {
            eq(column: string, value: unknown) {
              filters.push([column, value]);
              return builder;
            },
            in(column: string, values: unknown[]) {
              filters.push([column, values]);
              return builder;
            },
            select(_columns?: string) {
              return builder;
            },
            maybeSingle() {
              if (op === "jobs.update" && !result.error && result.data) {
                state.jobStatus = String(payload.status);
              }
              return Promise.resolve(result);
            },
          };
          return builder;
        },
      };
    },
  };
  return { admin, calls, state, updatedRow, timeline };
}

function concurrentClaimAdmin() {
  const state = {
    contributionStatus: String(contribution.status),
    jobUpserts: 0,
  };
  const admin = {
    from(table: string) {
      return {
        update(payload: Record<string, unknown>) {
          const equalityFilters = new Map<string, unknown>();
          const inFilters = new Map<string, unknown[]>();
          const builder = {
            eq(column: string, value: unknown) {
              equalityFilters.set(column, value);
              return builder;
            },
            in(column: string, values: unknown[]) {
              inFilters.set(column, values);
              return builder;
            },
            select(_columns?: string) {
              return builder;
            },
            async maybeSingle() {
              // Let both retry calls reach the guarded update before resolving
              // either one, matching two requests racing on the same snapshot.
              await Promise.resolve();
              assertEquals(table, "catalog_contributions");
              const matches = equalityFilters.get("id") === contribution.id &&
                equalityFilters.get("revision") === contribution.revision &&
                (inFilters.get("status") ?? []).includes(
                  state.contributionStatus,
                );
              if (!matches) return { data: null, error: null };
              state.contributionStatus = String(payload.status);
              return {
                data: { ...contribution, status: state.contributionStatus },
                error: null,
              };
            },
          };
          return builder;
        },
        upsert(payload: Record<string, unknown>) {
          assertEquals(table, "catalog_contribution_jobs");
          state.jobUpserts += 1;
          return Promise.resolve({ data: payload, error: null });
        },
      };
    },
  };
  return { admin, state };
}

Deno.test(
  "LEAFY-015: retry-catalog retry fails closed without mutations when catalog retry key is missing",
  async () => {
    const fromCalls: string[] = [];
    const addEventCalls: unknown[] = [];
    let waitUntilCalls = 0;
    let fetchCalls = 0;

    const admin = {
      from: (table: string) => {
        fromCalls.push(table);
        throw new Error(`unexpected admin.from(${table}) call`);
      },
    };

    let error: unknown;
    try {
      await retryRecognition(
        admin,
        contribution,
        reviewer,
        functionUrl,
        {
          // Deterministic: even if the environment is configured, treat this as
          // missing for the failure-mode test.
          catalogReviewKeyValue: "",
          addEvent: async (...args: unknown[]) => {
            addEventCalls.push(args);
            throw new Error("unexpected addEvent() call");
          },
          waitUntil: (_promise: Promise<unknown>) => {
            waitUntilCalls += 1;
            throw new Error("unexpected waitUntil() call");
          },
          fetchImpl: async () => {
            fetchCalls += 1;
            return new Response("{}", { status: 200 });
          },
        },
      );
    } catch (e) {
      error = e;
    }

    assert(error instanceof Error);
    assertEquals(
      (error as Error).message,
      "Catalog review key is not configured.",
    );

    // Hard guarantee: no DB writes, no event insert, and no internal hop.
    assertEquals(fromCalls, []);
    assertEquals(addEventCalls.length, 0);
    assertEquals(waitUntilCalls, 0);
    assertEquals(fetchCalls, 0);
  },
);

Deno.test(
  "LEAFY-015: configured retry writes status, queues the job, records the event, then hops internally",
  async () => {
    const timeline: string[] = [];
    const { admin, calls, updatedRow } = recordingAdmin({ timeline });
    const addEventCalls: unknown[][] = [];
    const fetchCalls: Array<{ url: string; init?: RequestInit }> = [];
    let waitUntilCalls = 0;

    const result = await retryRecognition(
      admin,
      contribution,
      reviewer,
      functionUrl,
      {
        catalogReviewKeyValue: catalogReviewKey,
        addEvent: async (...args: unknown[]) => {
          timeline.push("addEvent");
          addEventCalls.push(args);
        },
        waitUntil: (_promise: Promise<unknown>) => {
          timeline.push("waitUntil");
          waitUntilCalls += 1;
        },
        fetchImpl: async (input, init) => {
          timeline.push("fetch");
          fetchCalls.push({ url: String(input), init });
          return new Response("{}", { status: 200 });
        },
      },
    );

    assertEquals(timeline, [
      "contributions.update",
      "jobs.upsert",
      "addEvent",
      "fetch",
      "waitUntil",
    ]);

    const statusUpdate = calls[0];
    assertEquals(statusUpdate.table, "catalog_contributions");
    assertEquals(statusUpdate.payload.status, "processing");
    assertEquals(statusUpdate.payload.review_reason, null);
    assertEquals(statusUpdate.filters, [
      ["id", contribution.id],
      ["revision", contribution.revision],
      ["status", retryableContributionStatuses],
    ]);

    const jobUpsert = calls[1];
    assertEquals(jobUpsert.table, "catalog_contribution_jobs");
    assertEquals(jobUpsert.payload.contribution_id, contribution.id);
    assertEquals(jobUpsert.payload.user_id, contribution.user_id);
    assertEquals(jobUpsert.payload.status, "queued");
    assertEquals(jobUpsert.opts, { onConflict: "contribution_id" });
    assertEquals(calls.length, 2);

    assertEquals(addEventCalls.length, 1);
    assertEquals(addEventCalls[0][1], contribution.id);
    assertEquals(addEventCalls[0][2], contribution.status);
    assertEquals(addEventCalls[0][3], "processing");
    assertEquals(addEventCalls[0][4], "Recognition retried by catalog review.");
    assertEquals(addEventCalls[0][5], reviewer);

    assertEquals(waitUntilCalls, 1);
    assertEquals(fetchCalls.length, 1);
    assertEquals(
      fetchCalls[0].url,
      `${functionUrl}/functions/v1/manage-catalog-contribution`,
    );
    assertEquals(fetchCalls[0].init?.method, "POST");
    const headers = fetchCalls[0].init?.headers as Record<string, string>;
    assertEquals(headers["x-leafy-admin-key"], catalogReviewKey);
    assertEquals(headers["Content-Type"], "application/json");
    assertEquals(JSON.parse(String(fetchCalls[0].init?.body)), {
      action: "admin_retry",
      contribution_id: contribution.id,
    });

    assertEquals(result, updatedRow);
  },
);

Deno.test(
  "LEAFY-022: empty maybeSingle revision conflict writes nothing and throws 409",
  async () => {
    const { admin, calls } = recordingAdmin({
      updateResult: { data: null, error: null },
    });
    const addEventCalls: unknown[] = [];
    let waitUntilCalls = 0;
    let fetchCalls = 0;

    let error: unknown;
    try {
      await retryRecognition(
        admin,
        contribution,
        reviewer,
        functionUrl,
        {
          catalogReviewKeyValue: catalogReviewKey,
          addEvent: async (...args: unknown[]) => {
            addEventCalls.push(args);
            throw new Error("unexpected addEvent() call");
          },
          waitUntil: (_promise: Promise<unknown>) => {
            waitUntilCalls += 1;
            throw new Error("unexpected waitUntil() call");
          },
          fetchImpl: async () => {
            fetchCalls += 1;
            return new Response("{}", { status: 200 });
          },
        },
      );
    } catch (e) {
      error = e;
    }

    assert(error instanceof CatalogRetryConflictError);
    assert(isCatalogRetryConflict(error));
    assertEquals(error.status, 409);
    assertEquals(error.message, "This submission is already being reviewed.");
    assertEquals(error.message.includes("JSON object requested"), false);
    assertEquals(calls.length, 1);
    assertEquals(calls[0].op, "contributions.update");
    assertEquals(calls[0].table, "catalog_contributions");
    assertEquals(calls[0].filters, [
      ["id", contribution.id],
      ["revision", contribution.revision],
      ["status", retryableContributionStatuses],
    ]);
    assertEquals(
      calls.some((call) => call.op === "jobs.upsert"),
      false,
    );
    assertEquals(addEventCalls.length, 0);
    assertEquals(waitUntilCalls, 0);
    assertEquals(fetchCalls, 0);
  },
);

Deno.test(
  "LEAFY-022: concurrent retries of one revision allow only one processing claim",
  async () => {
    const { admin, state } = concurrentClaimAdmin();
    const handoffs: Promise<unknown>[] = [];
    let addEventCalls = 0;
    let fetchCalls = 0;

    const options = {
      catalogReviewKeyValue: catalogReviewKey,
      addEvent: async () => {
        addEventCalls += 1;
      },
      waitUntil: (promise: Promise<unknown>) => {
        handoffs.push(promise);
      },
      fetchImpl: async () => {
        fetchCalls += 1;
        return new Response("{}", { status: 200 });
      },
    };
    const results = await Promise.allSettled([
      retryRecognition(admin, contribution, reviewer, functionUrl, options),
      retryRecognition(admin, contribution, reviewer, functionUrl, options),
    ]);
    await Promise.all(handoffs);

    assertEquals(
      results.map((result) => result.status).sort(),
      ["fulfilled", "rejected"],
    );
    const rejected = results.find((result) => result.status === "rejected");
    assert(rejected?.status === "rejected");
    assert(rejected.reason instanceof CatalogRetryConflictError);
    assertEquals(rejected.reason.status, 409);
    assertEquals(state.contributionStatus, "processing");
    assertEquals(state.jobUpserts, 1);
    assertEquals(addEventCalls, 1);
    assertEquals(fetchCalls, 1);
    assertEquals(handoffs.length, 1);
  },
);

Deno.test(
  "LEAFY-022: job upsert failure after claim restores status and review_reason",
  async () => {
    const jobError = new Error("job upsert failed");
    const { admin, calls } = recordingAdmin({
      jobResult: { data: null, error: jobError },
    });
    let addEventCalls = 0;
    let waitUntilCalls = 0;
    let fetchCalls = 0;

    let error: unknown;
    try {
      await retryRecognition(admin, contribution, reviewer, functionUrl, {
        catalogReviewKeyValue: catalogReviewKey,
        addEvent: async () => {
          addEventCalls += 1;
        },
        waitUntil: () => {
          waitUntilCalls += 1;
        },
        fetchImpl: async () => {
          fetchCalls += 1;
          return new Response("{}", { status: 200 });
        },
      });
    } catch (caught) {
      error = caught;
    }

    assertEquals(error, jobError);
    assertEquals(calls.length, 3);
    assertEquals(calls[1].op, "jobs.upsert");
    assertRevertedContribution(calls[2]);
    assertEquals(addEventCalls, 0);
    assertEquals(waitUntilCalls, 0);
    assertEquals(fetchCalls, 0);
  },
);

Deno.test(
  "LEAFY-022: rollback database and no-row failures surface recovery errors",
  async () => {
    const cases: Array<{
      name: string;
      rollbackResult: QueryResult;
      expectedMessage: string;
    }> = [
      {
        name: "database error",
        rollbackResult: {
          data: null,
          error: new Error("rollback update failed"),
        },
        expectedMessage: "rollback update failed",
      },
      {
        name: "no restored row",
        rollbackResult: { data: null, error: null },
        expectedMessage: "no longer matched the claim",
      },
    ];

    for (const testCase of cases) {
      const jobError = new Error(`job upsert failed: ${testCase.name}`);
      const { admin } = recordingAdmin({
        jobResult: { data: null, error: jobError },
        rollbackResult: testCase.rollbackResult,
      });

      let error: unknown;
      try {
        await retryRecognition(admin, contribution, reviewer, functionUrl, {
          catalogReviewKeyValue: catalogReviewKey,
          addEvent: async () => {},
          waitUntil: () => {},
          fetchImpl: async () => new Response("{}", { status: 200 }),
        });
      } catch (caught) {
        error = caught;
      }

      assert(error instanceof CatalogRetryRecoveryError);
      assertEquals(error.originalError, jobError);
      assertEquals(error.recoveryErrors.length, 1);
      assertStringIncludes(error.message, testCase.expectedMessage);
    }
  },
);

Deno.test(
  "LEAFY-022: event failure neutralizes the queued job before restoring the contribution",
  async () => {
    const eventError = new Error("event insert failed");
    const { admin, calls, state } = recordingAdmin();
    let addEventCalls = 0;
    let waitUntilCalls = 0;
    let fetchCalls = 0;

    let error: unknown;
    try {
      await retryRecognition(admin, contribution, reviewer, functionUrl, {
        catalogReviewKeyValue: catalogReviewKey,
        addEvent: async () => {
          addEventCalls += 1;
          throw eventError;
        },
        waitUntil: () => {
          waitUntilCalls += 1;
        },
        fetchImpl: async () => {
          fetchCalls += 1;
          return new Response("{}", { status: 200 });
        },
      });
    } catch (caught) {
      error = caught;
    }

    assertEquals(error, eventError);
    assertEquals(calls.length, 4);
    assertEquals(calls[1].op, "jobs.upsert");
    assertEquals(state.jobStatus, "failed");
    assertNeutralizedJob(calls[2]);
    assertRevertedContribution(calls[3]);
    assertEquals(addEventCalls, 1);
    assertEquals(waitUntilCalls, 0);
    assertEquals(fetchCalls, 0);
  },
);

Deno.test(
  "LEAFY-022: event failure with a job neutralization database error keeps the contribution processing",
  async () => {
    const eventError = new Error("event insert failed");
    const neutralizationError = new Error("job neutralization failed");
    const { admin, calls, state } = recordingAdmin({
      jobRecoveryResult: { data: null, error: neutralizationError },
    });

    let error: unknown;
    try {
      await retryRecognition(admin, contribution, reviewer, functionUrl, {
        catalogReviewKeyValue: catalogReviewKey,
        addEvent: async () => {
          throw eventError;
        },
        waitUntil: () => {},
        fetchImpl: async () => new Response("{}", { status: 200 }),
      });
    } catch (caught) {
      error = caught;
    }

    assert(error instanceof CatalogRetryRecoveryError);
    assertEquals(error.originalError, eventError);
    assertEquals(error.recoveryErrors.length, 1);
    assertStringIncludes(error.message, neutralizationError.message);
    assertEquals(calls.length, 3);
    assertNeutralizedJob(calls[2]);
    assertContributionRestoreSkipped(calls);
    assertEquals(state.jobStatus, "queued");
  },
);

Deno.test(
  "LEAFY-022: event failure with no queued job match keeps the contribution processing",
  async () => {
    const eventError = new Error("event insert failed");
    const { admin, calls, state } = recordingAdmin({
      jobRecoveryResult: { data: null, error: null },
    });

    let error: unknown;
    try {
      await retryRecognition(admin, contribution, reviewer, functionUrl, {
        catalogReviewKeyValue: catalogReviewKey,
        addEvent: async () => {
          throw eventError;
        },
        waitUntil: () => {},
        fetchImpl: async () => new Response("{}", { status: 200 }),
      });
    } catch (caught) {
      error = caught;
    }

    assert(error instanceof CatalogRetryRecoveryError);
    assertEquals(error.originalError, eventError);
    assertEquals(error.recoveryErrors.length, 1);
    assertStringIncludes(error.message, "was not found");
    assertEquals(calls.length, 3);
    assertNeutralizedJob(calls[2]);
    assertContributionRestoreSkipped(calls);
    assertEquals(state.jobStatus, "queued");
  },
);

Deno.test(
  "LEAFY-022: worker handoff failure does not roll back a completed claim",
  async () => {
    const handoffError = new Error("waitUntil failed");
    const { admin, calls } = recordingAdmin();
    let fetchCalls = 0;

    let error: unknown;
    try {
      await retryRecognition(admin, contribution, reviewer, functionUrl, {
        catalogReviewKeyValue: catalogReviewKey,
        addEvent: async () => {},
        waitUntil: () => {
          throw handoffError;
        },
        fetchImpl: async () => {
          fetchCalls += 1;
          return new Response("{}", { status: 200 });
        },
      });
    } catch (caught) {
      error = caught;
    }

    assertEquals(error, handoffError);
    assertEquals(fetchCalls, 1);
    assertEquals(calls.length, 2);
    assertEquals(calls[0].op, "contributions.update");
    assertEquals(calls[1].op, "jobs.upsert");
  },
);

Deno.test(
  "LEAFY-022: retry action maps only the typed claim conflict to HTTP 409",
  async () => {
    const reviewSource = await Deno.readTextFile(
      new URL(
        "../functions/review-catalog-contribution/index.ts",
        import.meta.url,
      ),
    );
    const retrySource = await Deno.readTextFile(
      new URL(
        "../functions/review-catalog-contribution/retry-recognition.ts",
        import.meta.url,
      ),
    );
    const retryStart = reviewSource.indexOf('if (action === "retry")');
    assert(retryStart >= 0);
    const afterRetry = reviewSource.slice(retryStart);
    const retryBranch = afterRetry.slice(
      0,
      afterRetry.indexOf("if (!reviewableStatuses.includes"),
    );

    assert(retrySource.includes(".maybeSingle()"));
    assertEquals(retrySource.includes(".single()"), false);
    assert(retrySource.includes("CatalogRetryConflictError"));
    assert(retrySource.includes("This submission is already being reviewed."));
    assert(retryBranch.includes("isCatalogRetryConflict"));
    assert(retryBranch.includes("error.status"));
    assertEquals(retryBranch.includes("JSON object requested"), false);
  },
);

function assertRevertedContribution(call: AdminCall) {
  assertEquals(call.op, "contributions.update");
  assertEquals(call.table, "catalog_contributions");
  assertEquals(call.payload.status, contribution.status);
  assert(
    Object.hasOwn(call.payload, "review_reason"),
    "rollback must restore review_reason as well as status",
  );
  assertEquals(call.payload.review_reason, contribution.review_reason);
  assertEquals(call.filters, [
    ["id", contribution.id],
    ["revision", contribution.revision],
    ["status", "processing"],
  ]);
}

function assertNeutralizedJob(call: AdminCall) {
  assertEquals(call.op, "jobs.update");
  assertEquals(call.table, "catalog_contribution_jobs");
  assertEquals(call.payload.status, "failed");
  assertEquals(
    ["queued", "retry_wait"].includes(String(call.payload.status)),
    false,
  );
  assertEquals(call.payload.completed_at == null, false);
  assertEquals(call.filters, [
    ["contribution_id", contribution.id],
    ["status", "queued"],
  ]);
}

function assertContributionRestoreSkipped(calls: AdminCall[]) {
  const contributionUpdates = calls.filter((call) =>
    call.op === "contributions.update"
  );
  assertEquals(contributionUpdates.length, 1);
  assertEquals(contributionUpdates[0].payload.status, "processing");
}
