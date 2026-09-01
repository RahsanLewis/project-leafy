import {
  assert,
  assertEquals,
  assertFalse,
  assertThrows,
} from "jsr:@std/assert";
import {
  applyNutritionChatTools,
  assertPrivateContextToolInvariant,
  assertPromptAndToolsInvariant,
  hasPrivateHealthFields,
  NUTRITION_CHAT_ROUTER_PATHS,
  nutritionChatAnswerTurn,
  nutritionChatGroundingInstructions,
  nutritionChatModelTurn,
  sanitizePrivateContext,
} from "../functions/_shared/nutrition-chat-privacy.ts";

const emptyLoadedContext = {
  day: "2026-09-01",
  plan: null,
  goal: null,
  calories_eaten: 0,
  foods_logged: [] as string[],
  latest_weight_kg: null,
  thirty_day_weight_change_kg: null,
};

const privateCases: Array<{ name: string; context: unknown }> = [
  {
    name: "plan macros",
    context: { plan: { calorie_target_kcal: 1800, protein_g: 140 } },
  },
  {
    name: "goal and target weight",
    context: { goal: { goal: "lose", pace: "steady", target_weight_kg: 70 } },
  },
  { name: "calories eaten", context: { calories_eaten: 450 } },
  { name: "food log names", context: { foods_logged: ["oatmeal"] } },
  { name: "latest weight", context: { latest_weight_kg: 82.4 } },
  {
    name: "weight trend",
    context: { thirty_day_weight_change_kg: -1.2 },
  },
  {
    name: "full personalContext shape",
    context: {
      day: "2026-09-01",
      plan: { calorie_target_kcal: 1800, protein_g: 140, carbohydrate_g: 180, fat_g: 60 },
      goal: { goal: "lose", pace: "steady", target_weight_kg: 70 },
      calories_eaten: 450,
      foods_logged: ["oatmeal", "coffee"],
      latest_weight_kg: 82.4,
      thirty_day_weight_change_kg: -1.2,
    },
  },
];

const emptyCases: Array<{ name: string; context: unknown }> = [
  { name: "undefined", context: undefined },
  { name: "null", context: null },
  { name: "empty object", context: {} },
  { name: "loaded empty personalContext", context: emptyLoadedContext },
  {
    name: "null nested objects",
    context: { plan: null, goal: { goal: null, pace: null, target_weight_kg: null } },
  },
  { name: "empty plan object", context: { plan: {} } },
  { name: "zero calories without foods", context: { calories_eaten: 0 } },
  { name: "blank food names", context: { foods_logged: ["", "  "] } },
];

function hasWebSearch(tools: unknown): boolean {
  return Array.isArray(tools) &&
    tools.some((tool) =>
      Boolean(tool && typeof tool === "object" &&
        (tool as { type?: string }).type === "web_search")
    );
}

Deno.test("private-context + tools matrix: private fields omit web_search and required tool_choice", () => {
  for (const { name, context } of privateCases) {
    const turn = nutritionChatModelTurn(context);
    assertEquals(turn.includePrivateContext, true, name);
    assertEquals(turn.tools, undefined, name);
    assertEquals(turn.tool_choice, undefined, name);
    assertEquals(turn.include, undefined, name);
    assert(turn.attachedPrivateContext);
    assertFalse(hasWebSearch(turn.tools), name);
    assertPrivateContextToolInvariant({
      includePrivateContext: turn.includePrivateContext,
      tools: turn.tools,
      tool_choice: turn.tool_choice,
    });
  }
});

Deno.test("private-context + tools matrix: empty context keeps unconstrained web_search", () => {
  for (const { name, context } of emptyCases) {
    const turn = nutritionChatModelTurn(context);
    assertEquals(turn.includePrivateContext, false, name);
    assertEquals(turn.attachedPrivateContext, null, name);
    assertEquals(turn.tools, [{ type: "web_search" }], name);
    assertEquals(turn.tool_choice, "required", name);
    assertEquals(turn.include, ["web_search_call.action.sources"], name);
    assert(hasWebSearch(turn.tools), name);
    assertPrivateContextToolInvariant({
      includePrivateContext: turn.includePrivateContext,
      tools: turn.tools,
      tool_choice: turn.tool_choice,
    });
  }
});

Deno.test("sanitize drops empty fields, calendar day, and unknown keys", () => {
  const sanitized = sanitizePrivateContext({
    day: "2026-09-01",
    user_id: "secret-user",
    email: "user@example.com",
    plan: { calorie_target_kcal: 1800, notes: "private clinician note" },
    goal: { goal: "lose", extra: "ssn" },
    calories_eaten: 0,
    foods_logged: [],
    latest_weight_kg: null,
    thirty_day_weight_change_kg: null,
  });
  assertEquals(sanitized, {
    plan: { calorie_target_kcal: 1800 },
    goal: { goal: "lose" },
  });
  assertFalse("day" in sanitized);
  assertFalse("user_id" in sanitized);
  assertFalse("email" in sanitized);
  assertFalse("notes" in (sanitized.plan as Record<string, unknown>));
});

Deno.test("sanitize caps food names and omits zero-calorie empty logs", () => {
  const names = Array.from({ length: 12 }, (_, index) => `food-${index}`);
  const sanitized = sanitizePrivateContext({
    foods_logged: names,
    foods_logged_count: 12,
    calories_eaten: 0,
  });
  assertEquals((sanitized.foods_logged as string[]).length, 8);
  assertEquals(sanitized.foods_logged_count, 12);
  assertEquals(sanitized.calories_eaten, 0);
  assertEquals(sanitizePrivateContext({ calories_eaten: 0 }), {});
});

Deno.test("hasPrivateHealthFields matches sanitizer", () => {
  assertEquals(hasPrivateHealthFields(emptyLoadedContext), false);
  assertEquals(hasPrivateHealthFields({ plan: { protein_g: 120 } }), true);
});

Deno.test("applyNutritionChatTools strips smuggled web_search when private context is attached", () => {
  const turn = nutritionChatModelTurn({ latest_weight_kg: 80 });
  const body = applyNutritionChatTools({
    model: "test",
    tools: [{ type: "web_search" }],
    tool_choice: "required",
    include: ["web_search_call.action.sources"],
    input: "placeholder",
  }, turn);
  assertEquals("tools" in body, false);
  assertEquals("tool_choice" in body, false);
  assertEquals("include" in body, false);
  assertEquals(body.model, "test");
  const serialized = JSON.stringify(body);
  assertFalse(serialized.includes("web_search"));
  assertFalse(serialized.includes("required"));
});

Deno.test("applyNutritionChatTools attaches web_search only for empty private context", () => {
  const turn = nutritionChatModelTurn(emptyLoadedContext);
  const body = applyNutritionChatTools({ model: "test" }, turn);
  assertEquals(body.tools, [{ type: "web_search" }]);
  assertEquals(body.tool_choice, "required");
});

Deno.test("invariant rejects private context with unconstrained web_search or required tool_choice", () => {
  assertThrows(
    () =>
      assertPrivateContextToolInvariant({
        includePrivateContext: true,
        tools: [{ type: "web_search" }],
      }),
    Error,
    "unconstrained web_search",
  );
  assertThrows(
    () =>
      assertPrivateContextToolInvariant({
        includePrivateContext: true,
        tools: [],
        tool_choice: "required",
      }),
    Error,
    "tool_choice required",
  );
});

Deno.test("prompt grounding never asks for live web search when private context is attached", () => {
  const privateTurn = nutritionChatModelTurn({ plan: { calorie_target_kcal: 2000 } });
  assert(privateTurn.privateContextBlock.includes("PRIVATE CONTEXT:"));
  assert(privateTurn.privateContextBlock.includes("2000"));
  assertFalse(privateTurn.groundingInstructions.includes("Use live web sources"));
  assertFalse(privateTurn.groundingInstructions.includes("search the exact item"));
  assert(privateTurn.groundingInstructions.includes("Do not use web search"));

  const publicTurn = nutritionChatModelTurn(emptyLoadedContext);
  assertEquals(publicTurn.privateContextBlock, "");
  assert(publicTurn.groundingInstructions.includes("Use live web sources"));
});

Deno.test("assembled prompt plus request body never mix PRIVATE CONTEXT with web_search", () => {
  for (const { name, context } of [...privateCases, ...emptyCases]) {
    const turn = nutritionChatModelTurn(context);
    const prompt =
      `You are Ask Leafy.\n${turn.groundingInstructions}${turn.privateContextBlock}\nCATALOG CANDIDATES: []`;
    const body = applyNutritionChatTools({ model: "test" }, turn);
    assertPromptAndToolsInvariant({ prompt, turn, body });
    if (turn.includePrivateContext) {
      assert(prompt.includes("PRIVATE CONTEXT:"), name);
      assertFalse(JSON.stringify(body).includes("web_search"), name);
      assertFalse(body.tool_choice === "required", name);
    } else {
      assertFalse(prompt.includes("PRIVATE CONTEXT:"), name);
      assert(JSON.stringify(body).includes("web_search"), name);
    }
  }
});

Deno.test("private context + router failure/unverified/heuristic omits required web_search", () => {
  const privateContext = {
    plan: { calorie_target_kcal: 1800, protein_g: 140 },
    goal: { goal: "lose", target_weight_kg: 70 },
    latest_weight_kg: 82.4,
    foods_logged: ["oatmeal"],
    calories_eaten: 320,
  };
  const failurePaths = ["failed", "unverified", "heuristic"] as const;
  for (const routerPath of failurePaths) {
    const turn = nutritionChatAnswerTurn(privateContext, routerPath);
    const body = applyNutritionChatTools({
      model: "test",
      tools: [{ type: "web_search" }],
      tool_choice: "required",
      include: ["web_search_call.action.sources"],
    }, turn);
    assertEquals(turn.includePrivateContext, true, routerPath);
    assertEquals(turn.tools, undefined, routerPath);
    assertEquals(turn.tool_choice, undefined, routerPath);
    assertFalse("tools" in body, routerPath);
    assertFalse("tool_choice" in body, routerPath);
    assertFalse(JSON.stringify(body).includes("web_search"), routerPath);
    assertFalse(body.tool_choice === "required", routerPath);
    assert(turn.privateContextBlock.includes("PRIVATE CONTEXT:"), routerPath);
    assertFalse(turn.groundingInstructions.includes("Use live web sources"), routerPath);
  }
});

Deno.test("every router path keeps the private-context / web_search invariant", () => {
  for (const routerPath of NUTRITION_CHAT_ROUTER_PATHS) {
    for (const { name, context } of [...privateCases, ...emptyCases]) {
      const turn = nutritionChatAnswerTurn(context, routerPath);
      const prompt =
        `You are Ask Leafy.\n${turn.groundingInstructions}${turn.privateContextBlock}\nCATALOG CANDIDATES: []`;
      const body = applyNutritionChatTools({
        model: "test",
        tools: [{ type: "web_search" }],
        tool_choice: "required",
      }, turn);
      assertPromptAndToolsInvariant({ prompt, turn, body });
      if (turn.includePrivateContext) {
        assertEquals(body.tools, undefined, `${routerPath} ${name}`);
        assertEquals(body.tool_choice, undefined, `${routerPath} ${name}`);
      }
    }
  }
});

Deno.test("nutrition-chat wires the helper and does not hardcode required web_search", async () => {
  const source = await Deno.readTextFile(
    new URL("../functions/nutrition-chat/index.ts", import.meta.url),
  );
  assert(source.includes('from "../_shared/nutrition-chat-privacy.ts"'));
  assert(source.includes("nutritionChatAnswerTurn"));
  assert(source.includes("applyNutritionChatTools"));
  assert(source.includes("assertPromptAndToolsInvariant"));
  assert(source.includes("nutritionChatAnswerTurn(context, routing.source)"));
  assert(source.includes('source: "failed"'));
  assert(source.includes('source: "router"'));
  assertFalse(/tool_choice:\s*"required"/.test(source));
  assertFalse(/tools:\s*\[\s*\{\s*type:\s*"web_search"\s*\}\s*\]/.test(source));
  assert(
    source.includes("turn.privateContextBlock"),
    "system prompt must use the helper private-context block",
  );
  assert(
    source.includes("turn.groundingInstructions"),
    "system prompt must use helper grounding instructions",
  );
});

Deno.test("grounding helper matches model-turn flags", () => {
  assertEquals(
    nutritionChatGroundingInstructions(true).includes("Do not use web search"),
    true,
  );
  assertEquals(
    nutritionChatGroundingInstructions(false).includes("Use live web sources"),
    true,
  );
});
