import { createClient } from "npm:@supabase/supabase-js@2";
import { cors, json } from "../_shared/http.ts";
import {
  chatMealGroundingReminder,
  mealEstimateItemSchema,
  mealPromptVersion,
  mealSchemaVersion,
  normalizeMealOutput,
} from "../_shared/meal-estimate.ts";
import {
  type ChatScope,
  type ScopeRouterSource,
  countsTowardLimit,
  effectiveChatScope,
  fallbackScope,
  looksLikeUrgentHealth,
  offTopicRedirect,
  parseScope,
  scopePrompt,
  scopeRouterInstruction,
  scopeSchema,
} from "../_shared/chat-scope.ts";
import {
  fetchOpenAIResponses,
  openAIUsage,
  openAIUserMessage,
  openaiTimeoutMs,
  parseOpenAIJSONOutput,
  providerErrorMessage,
} from "../_shared/openai.ts";
import {
  applyNutritionChatTools,
  assertPromptAndToolsInvariant,
  nutritionChatAnswerTurn,
} from "../_shared/nutrition-chat-privacy.ts";

type Body = {
  action: "send" | "list_threads" | "load_thread" | "delete_thread";
  thread_id?: string;
  message?: string;
  client_message_id?: string;
  local_date?: string;
  time_zone?: string;
};
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const messageColumns =
  "id,role,content,sources,suggested_log_description,meal_estimate_session_id,created_at";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  try {
    const authorization = request.headers.get("Authorization") ?? "";
    const url = Deno.env.get("SUPABASE_URL")!;
    const publishable = Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY")!;
    const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SECRET_KEY")!;
    const auth = createClient(url, publishable, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: { user }, error: authError } = await auth.auth.getUser();
    if (authError || !user) return json({ error: "Unauthorized" }, 401);
    const admin = createClient(url, secret);
    const body = await request.json() as Body;

    if (body.action === "list_threads") {
      const result = await admin.from("ai_chat_threads").select(
        "id,title,last_message_at,created_at",
      ).eq("user_id", user.id).order("last_message_at", { ascending: false })
        .limit(50);
      if (result.error) throw result.error;
      return json({ threads: result.data ?? [] });
    }
    if (body.action === "load_thread") {
      const thread = await ownedThread(admin, user.id, body.thread_id);
      const messages = await admin.from("ai_chat_messages").select(
        messageColumns,
      ).eq("thread_id", thread.id).eq("user_id", user.id).order("created_at");
      if (messages.error) throw messages.error;
      return json({
        thread,
        messages: await decorateMessages(admin, user.id, messages.data ?? []),
      });
    }
    if (body.action === "delete_thread") {
      const thread = await ownedThread(admin, user.id, body.thread_id);
      const deleted = await admin.from("ai_chat_threads").delete().eq(
        "id",
        thread.id,
      ).eq("user_id", user.id);
      if (deleted.error) throw deleted.error;
      return json({ ok: true });
    }
    if (body.action !== "send") {
      return json({ error: "Unsupported chat action." }, 400);
    }

    const message = String(body.message ?? "").trim();
    if (!message || message.length > 2000) {
      return json({
        error: "Keep your question between 1 and 2,000 characters.",
      }, 400);
    }
    if (!body.client_message_id || !uuid.test(body.client_message_id)) {
      return json({ error: "A client message ID is required." }, 400);
    }
    const duplicate = await admin.from("ai_chat_messages").select("thread_id")
      .eq("user_id", user.id).eq("client_message_id", body.client_message_id)
      .maybeSingle();
    if (duplicate.data) {
      return await loadLatest(admin, user.id, duplicate.data.thread_id);
    }

    const since = new Date(Date.now() - 86_400_000).toISOString();
    let thread = body.thread_id
      ? await ownedThread(admin, user.id, body.thread_id)
      : null;
    const historyResult = thread
      ? await admin.from("ai_chat_messages").select("role,content")
        .eq("thread_id", thread.id).eq("user_id", user.id)
        .or("scope_classification.is.null,scope_classification.neq.off_topic")
        .order("created_at", { ascending: false }).limit(12)
      : { data: [], error: null };
    if (historyResult.error) throw historyResult.error;
    const key = Deno.env.get("OPENAI_API_KEY");
    if (!key) throw new Error("Ask Leafy is not configured yet.");
    const history = (historyResult.data ?? []).reverse();
    const routing = await routeScope(key, user.id, history, message);
    let offTopicCount = routing.scope === "off_topic"
      ? await recentOffTopicCount(admin, user.id, since)
      : 0;
    let shouldCount = countsTowardLimit(routing.scope, offTopicCount);
    if (shouldCount) {
      const count = await recentCountedMessageCount(admin, user.id, since);
      if (count >= Number(Deno.env.get("NUTRITION_CHAT_DAILY_LIMIT") ?? 30)) {
        return json({
          error: "You reached today’s Ask Leafy limit. Try again tomorrow.",
        }, 429);
      }
    }
    if (!thread) {
      const created = await admin.from("ai_chat_threads").insert({
        user_id: user.id,
        title: titleFor(message),
      }).select("id,title,last_message_at,created_at").single();
      if (created.error) throw created.error;
      thread = created.data;
    }
    const started = Date.now();
    if (routing.scope === "off_topic") {
      const now = new Date().toISOString();
      const userRow = await admin.from("ai_chat_messages").insert({
        thread_id: thread.id,
        user_id: user.id,
        role: "user",
        content: message,
        client_message_id: body.client_message_id,
        scope_classification: routing.scope,
        counts_toward_limit: shouldCount,
        scope_model_id: routing.model,
        scope_input_tokens: routing.inputTokens,
        scope_output_tokens: routing.outputTokens,
        scope_latency_ms: routing.latency,
      }).select(messageColumns).single();
      if (userRow.error) throw userRow.error;
      const assistantRow = await admin.from("ai_chat_messages").insert({
        thread_id: thread.id,
        user_id: user.id,
        role: "assistant",
        content: offTopicRedirect,
        sources: [],
        scope_classification: routing.scope,
        counts_toward_limit: false,
      }).select(messageColumns).single();
      if (assistantRow.error) throw assistantRow.error;
      const updated = await admin.from("ai_chat_threads").update({
        last_message_at: now,
        updated_at: now,
      })
        .eq("id", thread.id).eq("user_id", user.id).select(
          "id,title,last_message_at,created_at",
        ).single();
      if (updated.error) throw updated.error;
      const decorated = await decorateMessages(admin, user.id, [
        userRow.data,
        assistantRow.data,
      ]);
      return json({
        thread: updated.data,
        user_message: decorated[0],
        assistant_message: decorated[1],
      });
    }
    // Paid answer path. Router, unverified, and heuristic all go through
    // nutritionChatAnswerTurn so private context never pairs with required
    // web_search. Tool policy is decided only by private context.
    const context = await personalContext(admin, user.id, body.local_date);
    const foods = await catalogMatches(admin, message);
    const turn = nutritionChatAnswerTurn(context, routing.source);
    const prompt = systemPrompt(
      foods,
      routing.scope,
      routing.source,
      turn,
      context.day,
    );
    const model = Deno.env.get("OPENAI_CHAT_MODEL") ?? "gpt-5.6-sol";
    const responseBody = applyNutritionChatTools({
      model,
      store: false,
      reasoning: { effort: "low" },
      safety_identifier: await safetyID(user.id),
      input: [
        {
          role: "system",
          content: [{
            type: "input_text",
            text: prompt,
          }],
        },
        ...history.map((row) => ({
          role: row.role,
          content: [{ type: "input_text", text: row.content }],
        })),
        { role: "user", content: [{ type: "input_text", text: message }] },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "leafy_nutrition_chat",
          strict: true,
          schema: chatSchema,
        },
      },
    }, turn);
    assertPromptAndToolsInvariant({ prompt, turn, body: responseBody });
    const requestedWebSearch = Boolean(turn.tools?.length);
    let usedWebSearch = false;
    let payload: Record<string, unknown>;
    try {
      const first = await fetchOpenAIResponses(
        key,
        responseBody,
        openaiTimeoutMs.chat,
      );
      payload = first.payload;
      usedWebSearch = requestedWebSearch && first.ok;
      if (!first.ok && requestedWebSearch) {
        console.warn(
          "Ask Leafy web search failed; returning an immediate model estimate",
          providerErrorMessage(first.payload),
        );
        const { tools: _tools, tool_choice: _choice, include: _include, ...fallbackBody } =
          responseBody;
        const fallback = await fetchOpenAIResponses(
          key,
          fallbackBody,
          openaiTimeoutMs.chat,
        );
        payload = fallback.payload;
        usedWebSearch = false;
        if (!fallback.ok) {
          console.warn(
            "Ask Leafy answer request failed",
            providerErrorMessage(fallback.payload),
          );
          throw new Error("Ask Leafy could not answer right now. Try again.");
        }
      } else if (!first.ok) {
        console.warn(
          "Ask Leafy answer request failed",
          providerErrorMessage(first.payload),
        );
        throw new Error("Ask Leafy could not answer right now. Try again.");
      }
    } catch (error) {
      throw new Error(openAIUserMessage(error, "chat"));
    }
    const parsed = parseOpenAIJSONOutput(
      payload,
      "Ask Leafy returned an empty response. Try again.",
      "Ask Leafy returned an unreadable response. Try again.",
    );
    const parsedResponseScope = parseScope(parsed.scope);
    const responseScope: ChatScope = parsedResponseScope ??
      (looksLikeUrgentHealth(message, history) ? "urgent_health" : "health");
    const enforceRedirect = responseScope === "off_topic";
    const effectiveScope = effectiveChatScope(
      routing.scope,
      responseScope,
      routing.source,
    );
    if (enforceRedirect) {
      offTopicCount = await recentOffTopicCount(admin, user.id, since);
      shouldCount = countsTowardLimit("off_topic", offTopicCount);
    }
    const sources = [
      ...allowedSources(
        parsed.source_keys,
        turn.attachedPrivateContext ?? {},
        foods,
      ),
      ...(usedWebSearch ? webSources(payload) : []),
    ].filter((source, index, all) =>
      all.findIndex((candidate) =>
        candidate.kind === source.kind && candidate.label === source.label &&
        candidate.url === source.url
      ) === index
    ).slice(0, 6);
    const mealSuggestionRaw = !enforceRedirect && parsed.meal_status === "ready"
      ? normalizeMealOutput({
        status: "ready",
        follow_up_question: null,
        items: parsed.meal_items,
        total_calories: parsed.meal_total_calories,
        calorie_low: parsed.meal_calorie_low,
        calorie_high: parsed.meal_calorie_high,
        confidence: parsed.meal_confidence,
        assumptions: parsed.meal_assumptions,
      }, true)
      : null;
    const mealSuggestion = mealSuggestionRaw && !usedWebSearch
      ? downgradeChatEstimate(mealSuggestionRaw)
      : mealSuggestionRaw;
    const now = new Date().toISOString();
    const userRow = await admin.from("ai_chat_messages").insert({
      thread_id: thread.id,
      user_id: user.id,
      role: "user",
      content: message,
      client_message_id: body.client_message_id,
      scope_classification: effectiveScope,
      counts_toward_limit: shouldCount,
      scope_model_id: routing.model,
      scope_input_tokens: routing.inputTokens,
      scope_output_tokens: routing.outputTokens,
      scope_latency_ms: routing.latency,
    }).select(messageColumns).single();
    if (userRow.error) throw userRow.error;
    const mealSessionID = mealSuggestion
      ? await persistMealSuggestion(
        admin,
        user.id,
        message,
        body,
        mealSuggestion,
        model,
        payload,
        Date.now() - started,
      )
      : null;
    const assistantRow = await admin.from("ai_chat_messages").insert({
      thread_id: thread.id,
      user_id: user.id,
      role: "assistant",
      content: enforceRedirect
        ? offTopicRedirect
        : String(parsed.answer).slice(0, 8000),
      sources: enforceRedirect ? [] : sources,
      scope_classification: responseScope,
      counts_toward_limit: false,
      suggested_log_description: enforceRedirect || mealSessionID
        ? null
        : (parsed.suggested_log_description || null),
      model_id: model,
      provider_response_id: typeof payload.id === "string" ? payload.id : null,
      meal_estimate_session_id: mealSessionID,
      input_tokens: openAIUsage(payload).inputTokens,
      output_tokens: openAIUsage(payload).outputTokens,
      latency_ms: Date.now() - started,
    }).select(messageColumns).single();
    if (assistantRow.error) throw assistantRow.error;
    const updated = await admin.from("ai_chat_threads").update({
      last_message_at: now,
      updated_at: now,
    }).eq("id", thread.id).eq("user_id", user.id).select(
      "id,title,last_message_at,created_at",
    ).single();
    if (updated.error) throw updated.error;
    const decorated = await decorateMessages(admin, user.id, [
      userRow.data,
      assistantRow.data,
    ]);
    return json({
      thread: updated.data,
      user_message: decorated[0],
      assistant_message: decorated[1],
    });
  } catch (error) {
    console.error("nutrition-chat failed", error);
    return json({
      error: openAIUserMessage(error, "chat"),
    }, 400);
  }
});

// deno-lint-ignore no-explicit-any
async function ownedThread(admin: any, userID: string, id?: string) {
  if (!id || !uuid.test(id)) throw new Error("A valid chat is required.");
  const result = await admin.from("ai_chat_threads").select(
    "id,title,last_message_at,created_at",
  ).eq("id", id).eq("user_id", userID).single();
  if (result.error || !result.data) throw new Error("Chat not found.");
  return result.data;
}

// deno-lint-ignore no-explicit-any
async function loadLatest(admin: any, userID: string, threadID: string) {
  const thread = await ownedThread(admin, userID, threadID);
  const rows = await admin.from("ai_chat_messages").select(messageColumns).eq(
    "thread_id",
    threadID,
  ).eq("user_id", userID).order("created_at", { ascending: false }).limit(2);
  if (rows.error) throw rows.error;
  const messages = await decorateMessages(
    admin,
    userID,
    (rows.data ?? []).reverse(),
  );
  return json({
    thread,
    user_message: messages[0],
    assistant_message: messages[1],
  });
}

// deno-lint-ignore no-explicit-any
async function personalContext(admin: any, userID: string, localDate?: string) {
  const day = /^\d{4}-\d{2}-\d{2}$/.test(localDate ?? "")
    ? localDate!
    : new Date().toISOString().slice(0, 10);
  const [plan, profile, entries, weights] = await Promise.all([
    admin.from("nutrition_plans").select(
      "calorie_target_kcal,protein_g,carbohydrate_g,fat_g",
    ).eq("user_id", userID).order("revision", { ascending: false }).limit(1)
      .maybeSingle(),
    admin.from("profiles").select("goal,pace,target_weight_kg").eq(
      "user_id",
      userID,
    ).maybeSingle(),
    admin.from("food_entries").select("name,calories").eq("user_id", userID).eq(
      "local_date",
      day,
    ),
    admin.from("weight_entries").select("weight_kg,recorded_on").eq(
      "user_id",
      userID,
    ).order("recorded_on", { ascending: false }).limit(30),
  ]);
  for (const result of [plan, profile, entries, weights]) {
    if (result.error) throw result.error;
  }
  const eaten = (entries.data ?? []).reduce(
    (sum: number, row: { calories: number }) => sum + row.calories,
    0,
  );
  const names = (entries.data ?? []).map((x: { name: string }) => x.name);
  const list = weights.data ?? [];
  const trend = list.length > 1
    ? Number(list[0].weight_kg) - Number(list[list.length - 1].weight_kg)
    : null;
  return {
    day,
    plan: plan.data,
    goal: profile.data,
    calories_eaten: eaten,
    foods_logged: names,
    foods_logged_count: names.length,
    latest_weight_kg: list[0]?.weight_kg ?? null,
    thirty_day_weight_change_kg: trend,
  };
}

// deno-lint-ignore no-explicit-any
async function catalogMatches(admin: any, query: string) {
  const result = await admin.rpc("search_food_catalog", {
    p_query: query.slice(0, 120),
    p_limit: 5,
  });
  if (result.error) return [];
  return (result.data ?? []).slice(0, 5).map((
    row: Record<string, unknown>,
  ) => ({
    name: row.description ?? row.canonical_name,
    brand: row.brand_name ?? null,
    calories_per_100g: row.calories_per_100g ?? null,
    source: row.source_system ?? "Leafy catalog",
  }));
}

function systemPrompt(
  foods: unknown[],
  routedScope: ChatScope,
  routerSource: ScopeRouterSource,
  turn: ReturnType<typeof nutritionChatAnswerTurn>,
  localDate?: string,
) {
  const dateLine = /^\d{4}-\d{2}-\d{2}$/.test(localDate ?? "")
    ? `\nLOCAL DATE: ${localDate}`
    : "";
  return `You are Ask Leafy, an adult general-health and nutrition assistant. Your scope includes food, nutrition, calories, weight, exercise, sleep, stress, mental wellness, symptoms, supplements, hydration, medications, health data, and general wellness education. Do not answer unrelated requests such as coding, finance, travel, entertainment, general writing, news, or homework. For mixed requests, answer only the health-related portion and briefly state that you stay focused on nutrition and health. Set scope to health, mixed, off_topic, or urgent_health based on the newest message. Treat potentially urgent physical or mental-health situations, severe symptoms, immediate danger, or self-harm as urgent_health. If the request is off_topic, use this exact answer: ${
    JSON.stringify(offTopicRedirect)
  } and leave all meal/log fields empty.

Be practical, concise, nonjudgmental, and transparent about uncertainty. Never diagnose, treat disease, change medication, promote eating-disorder behaviors, or give unsafe rapid-weight-loss guidance. For urgent_health, clearly encourage appropriate urgent or emergency help and do not diagnose. For pregnancy, breastfeeding, eating-disorder recovery, clinician-directed diets, severe symptoms, or medication interactions, provide only broad safety information and recommend an appropriate clinician. Use the private Leafy context only when relevant. Catalog candidates may be approximate. Format simple answers as concise prose. For answers with multiple recommendations, you may use short Markdown bullets and limited bold emphasis. Do not use headings, tables, links, or block quotes.

${turn.groundingInstructions}

${chatMealGroundingReminder()} Return only the requested JSON.\n${
    scopeRouterInstruction(routedScope, routerSource)
  }${dateLine}${turn.privateContextBlock}\nCATALOG CANDIDATES: ${JSON.stringify(foods)}`;
}

const chatSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    scope: {
      type: "string",
      enum: ["health", "mixed", "off_topic", "urgent_health"],
    },
    answer: { type: "string" },
    source_keys: {
      type: "array",
      items: { type: "string", enum: ["plan", "today", "weight", "catalog"] },
    },
    suggested_log_description: { type: ["string", "null"] },
    meal_status: {
      type: "string",
      enum: ["none", "needs_clarification", "ready"],
    },
    meal_items: {
      type: "array",
      minItems: 0,
      maxItems: 12,
      items: mealEstimateItemSchema,
    },
    meal_total_calories: { type: ["integer", "null"] },
    meal_calorie_low: { type: ["integer", "null"] },
    meal_calorie_high: { type: ["integer", "null"] },
    meal_confidence: { type: ["number", "null"] },
    meal_assumptions: { type: "array", items: { type: "string" }, maxItems: 8 },
  },
  required: [
    "scope",
    "answer",
    "source_keys",
    "suggested_log_description",
    "meal_status",
    "meal_items",
    "meal_total_calories",
    "meal_calorie_low",
    "meal_calorie_high",
    "meal_confidence",
    "meal_assumptions",
  ],
};

async function routeScope(
  key: string,
  userID: string,
  history: Array<{ role: string; content: string }>,
  message: string,
) {
  const model = Deno.env.get("OPENAI_SCOPE_MODEL") ?? "gpt-5.6-sol";
  const started = Date.now();
  try {
    const { ok, payload } = await fetchOpenAIResponses(key, {
      model,
      store: false,
      reasoning: { effort: "low" },
      safety_identifier: await safetyID(userID),
      input: [{
        role: "user",
        content: [{
          type: "input_text",
          text: scopePrompt(history, message),
        }],
      }],
      text: {
        format: {
          type: "json_schema",
          name: "leafy_chat_scope",
          strict: true,
          schema: scopeSchema,
        },
      },
    }, openaiTimeoutMs.scope);
    if (!ok) {
      throw new Error(providerErrorMessage(payload) ?? "Scope routing failed.");
    }
    const parsed = parseOpenAIJSONOutput(
      payload,
      "Scope routing returned an empty response.",
      "Scope routing returned an unreadable response.",
    );
    const scope = parseScope(parsed.scope);
    if (!scope) {
      throw new Error("Scope routing returned an unknown label.");
    }
    const usage = openAIUsage(payload);
    return {
      scope,
      source: "router" as const,
      model,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      latency: Date.now() - started,
    };
  } catch (error) {
    const fallback = fallbackScope(message, history);
    console.warn(
      "Ask Leafy scope router failed; using local fallback",
      fallback,
      error,
    );
    return {
      scope: fallback.scope,
      source: fallback.source,
      model,
      inputTokens: null,
      outputTokens: null,
      latency: Date.now() - started,
    };
  }
}

// deno-lint-ignore no-explicit-any
async function recentOffTopicCount(admin: any, userID: string, since: string) {
  const result = await admin.from("ai_chat_messages").select("id", {
    count: "exact",
    head: true,
  })
    .eq("user_id", userID).eq("role", "user").eq(
      "scope_classification",
      "off_topic",
    ).gte("created_at", since);
  if (result.error) throw result.error;
  return result.count ?? 0;
}

// deno-lint-ignore no-explicit-any
async function recentCountedMessageCount(
  admin: any,
  userID: string,
  since: string,
) {
  const result = await admin.from("ai_chat_messages").select("id", {
    count: "exact",
    head: true,
  }).eq("user_id", userID).eq("role", "user").eq(
    "counts_toward_limit",
    true,
  ).gte("created_at", since);
  if (result.error) throw result.error;
  return result.count ?? 0;
}

async function persistMealSuggestion(
  // deno-lint-ignore no-explicit-any
  admin: any,
  userID: string,
  description: string,
  body: Body,
  estimate: ReturnType<typeof normalizeMealOutput>,
  model: string,
  // deno-lint-ignore no-explicit-any
  payload: any,
  latency: number,
) {
  const sessionID = crypto.randomUUID();
  const now = new Date();
  const localDate = /^\d{4}-\d{2}-\d{2}$/.test(body.local_date ?? "")
    ? body.local_date!
    : now.toISOString().slice(0, 10);
  const timeZone = String(body.time_zone ?? "UTC").slice(0, 80) || "UTC";
  const session = await admin.from("ai_meal_sessions").insert({
    id: sessionID,
    user_id: userID,
    status: "ready",
    input_modalities: ["chat"],
    description_text: description.slice(0, 2000),
    meal_type: "unspecified",
    consumed_at: now.toISOString(),
    local_date: localDate,
    time_zone: timeZone,
    provider: "openai",
    model_id: model,
    prompt_version: mealPromptVersion,
    schema_version: mealSchemaVersion,
    provider_response_id: payload.id ?? null,
    estimated_calories: estimate.total_calories,
    calorie_low: estimate.calorie_low,
    calorie_high: estimate.calorie_high,
    confidence: estimate.confidence,
    assumptions: estimate.assumptions,
    input_tokens: payload.usage?.input_tokens ?? null,
    output_tokens: payload.usage?.output_tokens ?? null,
    latency_ms: Math.max(0, latency),
  });
  if (session.error) throw session.error;
  const rows = estimate.items.map((item, index) => ({
    session_id: sessionID,
    ordinal: index + 1,
    predicted_name: item.name,
    predicted_portion: item.portion,
    predicted_grams: item.estimated_grams,
    predicted_calories: item.calories,
    calorie_low: item.calorie_low,
    calorie_high: item.calorie_high,
    confidence: item.confidence,
    assumptions: item.assumptions,
    nutrition_basis: item.nutrition_basis,
    market_country: item.market_country,
    source_title: item.source_title,
    source_url: item.source_url,
    source_kind: item.source_kind,
    exact_source_match: item.exact_source_match,
    resolution_source: item.nutrition_basis === "official"
      ? (item.source_kind === "restaurant" ? "restaurant" : "manufacturer")
      : item.nutrition_basis === "usda" ? "usda"
      : item.nutrition_basis === "leafy_catalog" ? "leafy_catalog"
      : item.nutrition_basis === "secondary" ? "secondary" : "ai",
    retrieved_at: item.source_url ? new Date().toISOString() : null,
  }));
  const inserted = await admin.from("ai_meal_items").insert(rows).select(
    "id,ordinal",
  );
  if (inserted.error) throw inserted.error;
  const itemIDs = new Map(
    (inserted.data ?? []).map((
      row: Record<string, unknown>,
    ) => [Number(row.ordinal), String(row.id)]),
  );
  const nutrients = estimate.items.flatMap((item, index) =>
    item.nutrients.map((nutrient) => ({
      ai_meal_item_id: itemIDs.get(index + 1),
      nutrient_code: nutrient.code,
      predicted_amount: nutrient.amount,
      confidence: nutrient.confidence,
    }))
  ).filter((row) => row.ai_meal_item_id);
  if (nutrients.length) {
    const result = await admin.from("ai_meal_item_nutrients").insert(nutrients);
    if (result.error) throw result.error;
  }
  return sessionID;
}

function downgradeChatEstimate(estimate: ReturnType<typeof normalizeMealOutput>) {
  const items = estimate.items.map((item) => ({
    ...item, nutrition_basis: "ai_estimate" as const, source_title: null, source_url: null,
    source_kind: null, exact_source_match: false, confidence: Math.min(item.confidence, 0.55),
    calorie_low: Math.min(item.calorie_low, Math.round(item.calories * 0.8)),
    calorie_high: Math.max(item.calorie_high, Math.round(item.calories * 1.2)),
  }));
  return {
    ...estimate, items, status: "ready" as const, follow_up_question: null,
    total_calories: items.reduce((sum, item) => sum + item.calories, 0),
    calorie_low: items.reduce((sum, item) => sum + item.calorie_low, 0),
    calorie_high: items.reduce((sum, item) => sum + item.calorie_high, 0),
    confidence: Math.min(estimate.confidence, 0.55),
    assumptions: [...estimate.assumptions, "Live sources were unavailable; review this estimate before logging."].slice(0, 8),
  };
}

// deno-lint-ignore no-explicit-any
async function decorateMessages(
  admin: any,
  userID: string,
  messages: Record<string, unknown>[],
) {
  return await Promise.all(messages.map(async (message) => {
    const sessionID = message.meal_estimate_session_id;
    if (!sessionID) return { ...message, meal_suggestion: null };
    return {
      ...message,
      meal_suggestion: await loadMealSuggestion(
        admin,
        userID,
        String(sessionID),
      ),
    };
  }));
}

// deno-lint-ignore no-explicit-any
async function loadMealSuggestion(
  admin: any,
  userID: string,
  sessionID: string,
) {
  const session = await admin.from("ai_meal_sessions")
    .select(
      "id,status,estimated_calories,calorie_low,calorie_high,confidence,assumptions",
    )
    .eq("id", sessionID).eq("user_id", userID).is("deleted_at", null)
    .maybeSingle();
  if (session.error || !session.data) return null;
  const items = await admin.from("ai_meal_items")
    .select(
      "id,ordinal,predicted_name,predicted_portion,predicted_grams,predicted_calories,calorie_low,calorie_high,confidence,assumptions,food_entry_id,resolution_source,nutrition_basis,market_country,source_title,source_url,source_kind,exact_source_match,retrieved_at",
    )
    .eq("session_id", sessionID).order("ordinal");
  if (items.error) throw items.error;
  const ids = (items.data ?? []).map((item: Record<string, unknown>) =>
    String(item.id)
  );
  const nutrients = ids.length
    ? await admin.from("ai_meal_item_nutrients").select(
      "ai_meal_item_id,nutrient_code,predicted_amount,confidence",
    ).in("ai_meal_item_id", ids)
    : { data: [], error: null };
  if (nutrients.error) throw nutrients.error;
  const nutrientMap = new Map<string, Record<string, unknown>[]>();
  for (const nutrient of nutrients.data ?? []) {
    const id = String(nutrient.ai_meal_item_id);
    nutrientMap.set(id, [...(nutrientMap.get(id) ?? []), {
      code: nutrient.nutrient_code,
      amount: nutrient.predicted_amount,
      confidence: nutrient.confidence,
    }]);
  }
  const status = session.data.status === "confirmed"
    ? "logged"
    : session.data.status === "ready"
    ? "ready"
    : "unavailable";
  return {
    session_id: session.data.id,
    status,
    total_calories: session.data.estimated_calories,
    calorie_low: session.data.calorie_low,
    calorie_high: session.data.calorie_high,
    confidence: session.data.confidence,
    assumptions: session.data.assumptions ?? [],
    items: (items.data ?? []).map((item: Record<string, unknown>) => ({
      id: item.id,
      name: item.predicted_name,
      portion: item.predicted_portion ?? "",
      estimated_grams: item.predicted_grams,
      calories: item.predicted_calories,
      calorie_low: item.calorie_low,
      calorie_high: item.calorie_high,
      confidence: item.confidence,
      assumptions: item.assumptions ?? [],
      resolution_source: item.resolution_source,
      nutrition_basis: item.nutrition_basis,
      market_country: item.market_country,
      source_title: item.source_title,
      source_url: item.source_url,
      source_kind: item.source_kind,
      exact_source_match: item.exact_source_match,
      retrieved_at: item.retrieved_at,
      nutrients: nutrientMap.get(String(item.id)) ?? [],
    })),
  };
}

function allowedSources(
  keys: unknown,
  context: Record<string, unknown>,
  foods: unknown[],
) {
  const requested = Array.isArray(keys) ? keys : [];
  const all: Record<string, { kind: string; label: string; url: null } | null> = {
    plan: context.plan ? { kind: "plan", label: "Your Leafy plan", url: null } : null,
    today: (Array.isArray(context.foods_logged) && context.foods_logged.length) ||
        (typeof context.calories_eaten === "number" && context.calories_eaten > 0)
      ? { kind: "log", label: "Today’s food log", url: null }
      : null,
    weight: context.latest_weight_kg != null ||
        context.thirty_day_weight_change_kg != null
      ? { kind: "weight", label: "Your weight trend", url: null }
      : null,
    catalog: foods.length
      ? { kind: "catalog", label: "Leafy food catalog / USDA", url: null }
      : null,
  };
  return requested.map((key) => all[String(key)]).filter(
    (source): source is { kind: string; label: string; url: null } =>
      source !== null,
  );
}

// The Responses API nests consulted URLs under web_search_call.action.sources.
// Keep this traversal tolerant of response-shape additions while only exposing
// valid HTTPS links to the client.
function webSources(payload: unknown) {
  const found: Array<{ kind: string; label: string; url: string }> = [];
  const visit = (value: unknown) => {
    if (Array.isArray(value)) {
      value.forEach(visit);
      return;
    }
    if (!value || typeof value !== "object") return;
    const record = value as Record<string, unknown>;
    if (typeof record.url === "string" && /^https:\/\//i.test(record.url)) {
      let hostname = "Source";
      try {
        hostname = new URL(record.url).hostname.replace(/^www\./, "");
      } catch { /* URL was already constrained above. */ }
      const title = typeof record.title === "string" && record.title.trim()
        ? record.title.trim()
        : hostname;
      found.push({ kind: "web", label: title.slice(0, 80), url: record.url });
    }
    Object.values(record).forEach(visit);
  };
  visit(payload);
  return found.filter((source, index, all) =>
    all.findIndex((candidate) => candidate.url === source.url) === index
  );
}
function titleFor(message: string) {
  const compact = message.replace(/\s+/g, " ").trim();
  return compact.length <= 55 ? compact : `${compact.slice(0, 52)}…`;
}
async function safetyID(userID: string) {
  const salt = Deno.env.get("OPENAI_SAFETY_SALT") ??
    Deno.env.get("SUPABASE_URL") ?? "leafy";
  const bytes = new TextEncoder().encode(`${salt}:${userID}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
