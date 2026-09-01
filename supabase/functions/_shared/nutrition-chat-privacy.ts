/**
 * AppSec AI-01 / LEAFY-008.
 *
 * Private health, plan, weight, and food-log fields must never share a
 * Responses API turn with unconstrained `web_search`, and must never use
 * `tool_choice: "required"`.
 *
 * Product decision: when any private context is attached, omit web_search
 * entirely rather than mediating search queries. When private context is
 * empty (new user with no plan, profile goal, food log, or weight),
 * web_search may remain as before, including `tool_choice: "required"`,
 * so general nutrition questions can still be grounded.
 *
 * Catalog candidates are public USDA/Leafy records matched to the user's
 * question and are not private health fields.
 *
 * Router outcome never relaxes this invariant. Paid answer turns after a
 * successful router, a failed router, an unverified fallback, or a local
 * urgent heuristic all use the same tool policy: private context attached
 * ⇒ no unconstrained web_search and no tool_choice required.
 */

export type NutritionChatWebSearchTool = { type: "web_search" };

/**
 * How the pre-answer scope label was produced. Values align with Ask Leafy
 * safety routing (`router` / `unverified` / `heuristic`) plus `failed` for
 * the current fail-open catch. This label must not enable web_search.
 */
export type NutritionChatRouterPath =
  | "router"
  | "failed"
  | "unverified"
  | "heuristic";

export type NutritionChatModelTurn = {
  includePrivateContext: boolean;
  attachedPrivateContext: Record<string, unknown> | null;
  tools: NutritionChatWebSearchTool[] | undefined;
  tool_choice: "required" | undefined;
  include: string[] | undefined;
  groundingInstructions: string;
  privateContextBlock: string;
};

const PLAN_KEYS = [
  "calorie_target_kcal",
  "protein_g",
  "carbohydrate_g",
  "fat_g",
] as const;

const GOAL_KEYS = ["goal", "pace", "target_weight_kg"] as const;

const MAX_FOOD_NAMES = 8;

function isPresent(value: unknown): boolean {
  if (value == null) return false;
  if (typeof value === "string") return value.trim().length > 0;
  if (typeof value === "number") return Number.isFinite(value);
  if (typeof value === "boolean") return true;
  if (Array.isArray(value)) return value.some(isPresent);
  if (typeof value === "object") {
    return Object.values(value as Record<string, unknown>).some(isPresent);
  }
  return false;
}

function pickPresent(
  record: Record<string, unknown>,
  keys: readonly string[],
): Record<string, unknown> | null {
  const picked: Record<string, unknown> = {};
  for (const key of keys) {
    if (isPresent(record[key])) picked[key] = record[key];
  }
  return Object.keys(picked).length ? picked : null;
}

function foodNames(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string =>
      typeof item === "string" && item.trim().length > 0
    )
    .map((item) => item.trim())
    .slice(0, MAX_FOOD_NAMES);
}

/**
 * Allowlisted, non-empty private fields only. Calendar `day` is not a
 * private health field and is omitted. Unknown keys never pass through.
 */
export function sanitizePrivateContext(
  context: unknown,
): Record<string, unknown> {
  if (!context || typeof context !== "object" || Array.isArray(context)) {
    return {};
  }
  const raw = context as Record<string, unknown>;
  const attached: Record<string, unknown> = {};

  if (raw.plan && typeof raw.plan === "object" && !Array.isArray(raw.plan)) {
    const plan = pickPresent(raw.plan as Record<string, unknown>, PLAN_KEYS);
    if (plan) attached.plan = plan;
  }

  if (raw.goal && typeof raw.goal === "object" && !Array.isArray(raw.goal)) {
    const goal = pickPresent(raw.goal as Record<string, unknown>, GOAL_KEYS);
    if (goal) attached.goal = goal;
  }

  const logged = foodNames(raw.foods_logged);
  const calories = typeof raw.calories_eaten === "number" &&
      Number.isFinite(raw.calories_eaten)
    ? raw.calories_eaten
    : null;
  if (logged.length > 0) {
    attached.foods_logged = logged;
    if (typeof raw.foods_logged_count === "number" &&
      Number.isFinite(raw.foods_logged_count) &&
      raw.foods_logged_count > logged.length
    ) {
      attached.foods_logged_count = raw.foods_logged_count;
    }
  }
  if (calories != null && (calories > 0 || logged.length > 0)) {
    attached.calories_eaten = calories;
  }

  if (raw.latest_weight_kg != null && isPresent(raw.latest_weight_kg)) {
    attached.latest_weight_kg = raw.latest_weight_kg;
  }
  if (
    raw.thirty_day_weight_change_kg != null &&
    isPresent(raw.thirty_day_weight_change_kg)
  ) {
    attached.thirty_day_weight_change_kg = raw.thirty_day_weight_change_kg;
  }

  return attached;
}

export function hasPrivateHealthFields(context: unknown): boolean {
  return Object.keys(sanitizePrivateContext(context)).length > 0;
}

export function nutritionChatGroundingInstructions(
  includePrivateContext: boolean,
): string {
  if (includePrivateContext) {
    return "Ground answers in the private Leafy context and catalog candidates. Do not use web search or other outbound retrieval tools. For named restaurant or branded foods, prefer catalog candidates and established public nutrition facts; do not invent live URLs. Do not substitute a generic analogue when an exact catalog or official value is available.";
  }
  return "Use live web sources for every in-scope answer. For named restaurant or branded foods, search the exact item, size, market, and customization and prefer official restaurant/manufacturer sources, then USDA, then a verified Leafy catalog record, then reputable databases or retailers. Do not substitute a generic analogue when exact official nutrition is available.";
}

export function nutritionChatPrivateContextBlock(
  includePrivateContext: boolean,
  attached: Record<string, unknown> | null,
): string {
  if (!includePrivateContext || !attached || !Object.keys(attached).length) {
    return "";
  }
  return `\nPRIVATE CONTEXT: ${JSON.stringify(attached)}`;
}

export function nutritionChatModelTurn(
  context: unknown,
  routerPath: NutritionChatRouterPath = "router",
): NutritionChatModelTurn {
  // routerPath is accepted on every paid answer path so callers cannot
  // accidentally keep a separate "router failed → required web_search" body.
  // It is intentionally unused for tool selection.
  void routerPath;
  const attached = sanitizePrivateContext(context);
  const includePrivateContext = Object.keys(attached).length > 0;
  const groundingInstructions = nutritionChatGroundingInstructions(
    includePrivateContext,
  );
  const privateContextBlock = nutritionChatPrivateContextBlock(
    includePrivateContext,
    includePrivateContext ? attached : null,
  );
  if (includePrivateContext) {
    return {
      includePrivateContext: true,
      attachedPrivateContext: attached,
      tools: undefined,
      tool_choice: undefined,
      include: undefined,
      groundingInstructions,
      privateContextBlock,
    };
  }
  return {
    includePrivateContext: false,
    attachedPrivateContext: null,
    tools: [{ type: "web_search" }],
    tool_choice: "required",
    include: ["web_search_call.action.sources"],
    groundingInstructions,
    privateContextBlock,
  };
}

export function assertPrivateContextToolInvariant(input: {
  includePrivateContext: boolean;
  tools?: unknown;
  tool_choice?: unknown;
}): void {
  const tools = Array.isArray(input.tools) ? input.tools : [];
  const hasWebSearch = tools.some((tool) =>
    Boolean(
      tool && typeof tool === "object" &&
        (tool as { type?: string }).type === "web_search",
    )
  );
  if (input.includePrivateContext && hasWebSearch) {
    throw new Error(
      "Private health context cannot share a model turn with unconstrained web_search.",
    );
  }
  if (input.includePrivateContext && input.tool_choice === "required") {
    throw new Error(
      "tool_choice required cannot be set when private health context is attached.",
    );
  }
}

/**
 * Attach web_search only from the policy turn. Caller-supplied tools are
 * dropped so a template cannot smuggle search beside private context.
 */
export function applyNutritionChatTools(
  body: Record<string, unknown>,
  turn: NutritionChatModelTurn,
): Record<string, unknown> {
  const {
    tools: _ignoredTools,
    tool_choice: _ignoredChoice,
    include: _ignoredInclude,
    ...rest
  } = body;
  const next: Record<string, unknown> = { ...rest };
  if (!turn.includePrivateContext && turn.tools?.length) {
    next.tools = turn.tools;
    if (turn.tool_choice !== undefined) next.tool_choice = turn.tool_choice;
    if (turn.include !== undefined) next.include = turn.include;
  }
  assertPrivateContextToolInvariant({
    includePrivateContext: turn.includePrivateContext,
    tools: next.tools,
    tool_choice: next.tool_choice,
  });
  return next;
}

export const NUTRITION_CHAT_ROUTER_PATHS = [
  "router",
  "failed",
  "unverified",
  "heuristic",
] as const satisfies readonly NutritionChatRouterPath[];

/**
 * Single paid-answer entry point. Router failure / unverified / heuristic
 * still attach private context when present, and therefore still omit
 * unconstrained web_search.
 */
export function nutritionChatAnswerTurn(
  context: unknown,
  routerPath: NutritionChatRouterPath,
): NutritionChatModelTurn {
  const turn = nutritionChatModelTurn(context, routerPath);
  assertPrivateContextToolInvariant({
    includePrivateContext: turn.includePrivateContext,
    tools: turn.tools,
    tool_choice: turn.tool_choice,
  });
  return turn;
}

export function assertPromptAndToolsInvariant(input: {
  prompt: string;
  turn: NutritionChatModelTurn;
  body: Record<string, unknown>;
}): void {
  assertPrivateContextToolInvariant({
    includePrivateContext: input.turn.includePrivateContext,
    tools: input.body.tools,
    tool_choice: input.body.tool_choice,
  });
  const hasPrivateMarker = input.prompt.includes("PRIVATE CONTEXT:");
  const serializedTools = JSON.stringify({
    tools: input.body.tools ?? null,
    tool_choice: input.body.tool_choice ?? null,
  });
  if (hasPrivateMarker && serializedTools.includes("web_search")) {
    throw new Error(
      "Prompt private context cannot share a turn with unconstrained web_search.",
    );
  }
  if (input.turn.includePrivateContext && !hasPrivateMarker) {
    throw new Error("Private context was selected but omitted from the prompt.");
  }
  if (!input.turn.includePrivateContext && hasPrivateMarker) {
    throw new Error("PRIVATE CONTEXT must not appear when it is not selected.");
  }
}
