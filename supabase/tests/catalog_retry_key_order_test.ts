import { assertEquals, assert } from "jsr:@std/assert@1";
import {
  CatalogRetryConflictError,
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

type AdminCall = {
  op: "contributions.update" | "jobs.upsert";
  table: string;
  payload: Record<string, unknown>;
  opts?: Record<string, unknown>;
  filters?: Array<[string, unknown]>;
};

function recordingAdmin(options: {
  updateResult?: { data: unknown; error: unknown };
  jobResult?: { data: unknown; error: unknown };
  timeline?: string[];
} = {}) {
  const calls: AdminCall[] = [];
  const timeline = options.timeline ?? [];
  const updatedRow = {
    ...contribution,
    status: "processing",
    review_reason: null,
  };
  const admin = {
    from(table: string) {
      return {
        upsert(payload: Record<string, unknown>, opts?: Record<string, unknown>) {
          calls.push({ op: "jobs.upsert", table, payload, opts });
          timeline.push("jobs.upsert");
          return Promise.resolve(
            options.jobResult ?? { data: payload, error: null },
          );
        },
        update(payload: Record<string, unknown>) {
          const filters: Array<[string, unknown]> = [];
          const call: AdminCall = {
            op: "contributions.update",
            table,
            payload,
            filters,
          };
          calls.push(call);
          timeline.push("contributions.update");
          const builder = {
            eq(column: string, value: unknown) {
              filters.push([column, value]);
              return builder;
            },
            select(_columns?: string) {
              return builder;
            },
            maybeSingle() {
              return Promise.resolve(
                options.updateResult ?? { data: updatedRow, error: null },
              );
            },
            then(
              onFulfilled?: (value: { data: null; error: null }) => unknown,
              onRejected?: (reason: unknown) => unknown,
            ) {
              return Promise.resolve({ data: null, error: null }).then(
                onFulfilled,
                onRejected,
              );
            },
          };
          return builder;
        },
      };
    },
  };
  return { admin, calls, updatedRow, timeline };
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
    ]);

    const jobUpsert = calls[1];
    assertEquals(jobUpsert.table, "catalog_contribution_jobs");
    assertEquals(jobUpsert.payload.contribution_id, contribution.id);
    assertEquals(jobUpsert.payload.user_id, contribution.user_id);
    assertEquals(jobUpsert.payload.status, "queued");
    assertEquals(jobUpsert.opts, { onConflict: "contribution_id" });

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
    assertEquals(
      String(error.message).includes("JSON object requested"),
      false,
    );

    assertEquals(calls.length, 1);
    assertEquals(calls[0].op, "contributions.update");
    assertEquals(calls[0].table, "catalog_contributions");
    assertEquals(calls[0].filters, [
      ["id", contribution.id],
      ["revision", contribution.revision],
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
  "LEAFY-022: job upsert failure after claim reverts status and review_reason",
  async () => {
    const jobError = new Error("job upsert failed");
    const { admin, calls } = recordingAdmin({
      jobResult: { data: null, error: jobError },
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

    assertEquals(error, jobError);

    assertEquals(calls.length, 3);
    assertEquals(calls[0].op, "contributions.update");
    assertEquals(calls[0].payload.status, "processing");
    assertEquals(calls[0].payload.review_reason, null);
    assertEquals(calls[0].filters, [
      ["id", contribution.id],
      ["revision", contribution.revision],
    ]);

    assertEquals(calls[1].op, "jobs.upsert");
    assertEquals(calls[1].table, "catalog_contribution_jobs");

    const revert = calls[2];
    assertEquals(revert.op, "contributions.update");
    assertEquals(revert.table, "catalog_contributions");
    assertEquals(revert.payload.status, contribution.status);
    assert(
      Object.hasOwn(revert.payload, "review_reason"),
      "revert payload must restore review_reason; a status-only revert is a bug",
    );
    assertEquals(revert.payload.review_reason, contribution.review_reason);
    assertEquals(revert.filters, [
      ["id", contribution.id],
      ["status", "processing"],
    ]);

    assertEquals(addEventCalls.length, 0);
    assertEquals(waitUntilCalls, 0);
    assertEquals(fetchCalls, 0);
  },
);

Deno.test(
  "LEAFY-022: retry action maps CatalogRetryConflictError to HTTP 409",
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
    assert(retryBranch.includes("409"));
    assertEquals(retryBranch.includes("JSON object requested"), false);
  },
);
