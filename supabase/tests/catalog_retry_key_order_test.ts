import { assertEquals, assert } from "jsr:@std/assert@1";
import { retryRecognition } from "../functions/review-catalog-contribution/retry-recognition.ts";

const contribution = {
  id: "c1",
  user_id: "u1",
  status: "pending_review",
  revision: 1,
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
          const builder = {
            eq(column: string, value: unknown) {
              filters.push([column, value]);
              return builder;
            },
            select(_columns?: string) {
              return builder;
            },
            single() {
              calls.push({
                op: "contributions.update",
                table,
                payload,
                filters,
              });
              timeline.push("contributions.update");
              return Promise.resolve(
                options.updateResult ?? { data: updatedRow, error: null },
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
  "LEAFY-015: revision-guarded status update failure writes no job, event, or internal hop",
  async () => {
    const { admin, calls } = recordingAdmin({
      updateResult: {
        data: null,
        error: { message: "JSON object requested, multiple (or no) rows returned" },
      },
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

    assert(error);
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
