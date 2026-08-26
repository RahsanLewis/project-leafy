import { assertEquals } from "jsr:@std/assert";
import {
  countsTowardLimit,
  normalizeScope,
  offTopicRedirect,
  scopePrompt,
} from "../functions/_shared/chat-scope.ts";

Deno.test("off-topic grace allows five attempts before counting", () => {
  for (let attempts = 0; attempts < 5; attempts++) {
    assertEquals(countsTowardLimit("off_topic", attempts), false);
  }
  assertEquals(countsTowardLimit("off_topic", 5), true);
  assertEquals(countsTowardLimit("health", 0), true);
  assertEquals(countsTowardLimit("mixed", 0), true);
  assertEquals(countsTowardLimit("urgent_health", 0), true);
});

Deno.test("unknown router output fails open to health handling", () => {
  assertEquals(normalizeScope("off_topic"), "off_topic");
  assertEquals(normalizeScope("unexpected"), "health");
  assertEquals(normalizeScope(null), "health");
});

Deno.test("router prompt includes conversation context and explicit boundaries", () => {
  const prompt = scopePrompt([{
    role: "assistant",
    content: "Greek yogurt can add protein.",
  }], "What about dairy-free?");
  assertEquals(prompt.includes("Greek yogurt"), true);
  assertEquals(prompt.includes("What about dairy-free?"), true);
  assertEquals(prompt.includes("coding, finance, travel"), true);
});

Deno.test("redirect is concise and offers relevant next steps", () => {
  assertEquals(offTopicRedirect.includes("nutrition and health"), true);
  assertEquals(offTopicRedirect.includes("plan what to eat"), true);
});
