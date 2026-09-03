import { assertEquals, assert } from "jsr:@std/assert@1";
import { retryRecognition } from "../functions/review-catalog-contribution/retry-recognition.ts";

Deno.test(
  "LEAFY-015: retry-catalog retry fails closed without mutations when catalog retry key is missing",
  async () => {
    const fromCalls: string[] = [];
    const addEventCalls: any[] = [];
    let waitUntilCalls = 0;
    let fetchCalls = 0;

    const admin = {
      from: (table: string) => {
        fromCalls.push(table);
        throw new Error(`unexpected admin.from(${table}) call`);
      },
    };

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

    let error: unknown;
    try {
      await retryRecognition(
        admin,
        contribution,
        reviewer,
        "https://internal.example",
        {
          // Deterministic: even if the environment is configured, treat this as
          // missing for the failure-mode test.
          catalogReviewKeyValue: "",
          addEvent: async (...args: any[]) => {
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

