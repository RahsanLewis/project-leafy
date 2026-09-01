import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert";
import {
  extractOpenAIOutputText,
  fetchOpenAIResponses,
  isNetworkError,
  isTimeoutError,
  openAIUserMessage,
  parseOpenAIJSONOutput,
} from "../functions/_shared/openai.ts";

Deno.test("timeout and network errors map to retryable client messages", () => {
  const timeout = Object.assign(new Error("The operation was aborted"), {
    name: "TimeoutError",
  });
  assertEquals(isTimeoutError(timeout), true);
  assertEquals(
    openAIUserMessage(timeout, "chat"),
    "Ask Leafy took too long. Try again.",
  );
  assertEquals(
    openAIUserMessage(timeout, "meal"),
    "Meal estimate took too long. Try again.",
  );

  const network = Object.assign(new Error("Failed to fetch"), {
    name: "TypeError",
  });
  assertEquals(isNetworkError(network), true);
  assertEquals(
    openAIUserMessage(network, "chat"),
    "Ask Leafy could not reach the AI service. Try again.",
  );
  assertEquals(
    openAIUserMessage(new Error("malformed_openai_http_body"), "chat"),
    "Ask Leafy returned an unreadable response. Try again.",
  );
  assertEquals(
    openAIUserMessage(new Error("Keep your question between 1 and 2,000 characters."), "chat"),
    "Keep your question between 1 and 2,000 characters.",
  );
});

Deno.test("empty and malformed model output become user-facing errors", () => {
  assertThrows(
    () => extractOpenAIOutputText({}, "Ask Leafy returned an empty response. Try again."),
    Error,
    "Ask Leafy returned an empty response. Try again.",
  );
  assertThrows(
    () =>
      parseOpenAIJSONOutput(
        { output_text: "not-json" },
        "empty",
        "Ask Leafy returned an unreadable response. Try again.",
      ),
    Error,
    "Ask Leafy returned an unreadable response. Try again.",
  );
  assertEquals(
    parseOpenAIJSONOutput(
      { output_text: '{"scope":"health"}' },
      "empty",
      "malformed",
    ),
    { scope: "health" },
  );
  assertEquals(
    parseOpenAIJSONOutput(
      {
        output: [{
          content: [{ type: "output_text", text: '{"ok":true}' }],
        }],
      },
      "empty",
      "malformed",
    ),
    { ok: true },
  );
});

Deno.test("retries once on a transient network error and not on timeout", async () => {
  const original = globalThis.fetch;
  let networkCalls = 0;
  globalThis.fetch = (async () => {
    networkCalls += 1;
    if (networkCalls === 1) {
      throw Object.assign(new Error("Failed to fetch"), { name: "TypeError" });
    }
    return new Response('{"id":"resp"}', { status: 200 });
  }) as typeof fetch;
  try {
    const result = await fetchOpenAIResponses("test-key", { model: "test" }, 1_000);
    assertEquals(result.ok, true);
    assertEquals(result.payload, { id: "resp" });
    assertEquals(networkCalls, 2);
  } finally {
    globalThis.fetch = original;
  }

  let timeoutCalls = 0;
  globalThis.fetch = (async () => {
    timeoutCalls += 1;
    throw Object.assign(new Error("The operation was aborted"), {
      name: "TimeoutError",
    });
  }) as typeof fetch;
  try {
    await assertRejects(
      () => fetchOpenAIResponses("test-key", { model: "test" }, 1_000),
      Error,
    );
    assertEquals(timeoutCalls, 1);
  } finally {
    globalThis.fetch = original;
  }
});
