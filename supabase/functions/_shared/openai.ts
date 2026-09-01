export const openaiResponsesURL = "https://api.openai.com/v1/responses";

/**
 * Per-attempt budgets. Scope is short so a hung classifier still leaves time
 * for the main Ask Leafy answer. Chat and meal keep a no-tools fallback on
 * HTTP errors; timeouts do not start a second billed call (the hung request
 * may already be in flight, and two sequential waits can exceed the typical
 * 60s Edge Function wall time). Clients already expose Retry.
 */
export const openaiTimeoutMs = {
  scope: 10_000,
  chat: 25_000,
  meal: 28_000,
} as const;

export type OpenAIFeature = "chat" | "meal";

export function isTimeoutError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return error.name === "TimeoutError" || error.name === "AbortError";
}

export function isNetworkError(error: unknown): boolean {
  if (!(error instanceof Error) || isTimeoutError(error)) return false;
  return error.name === "TypeError" ||
    /failed to fetch|networkerror|dns|econnreset|econnrefused|enotfound/i.test(
      error.message,
    );
}

export function openAIUserMessage(
  error: unknown,
  feature: OpenAIFeature,
): string {
  const chat = feature === "chat";
  if (isTimeoutError(error)) {
    return chat
      ? "Ask Leafy took too long. Try again."
      : "Meal estimate took too long. Try again.";
  }
  if (isNetworkError(error)) {
    return chat
      ? "Ask Leafy could not reach the AI service. Try again."
      : "Meal estimate could not reach the AI service. Try again.";
  }
  if (error instanceof Error && error.message === "malformed_openai_http_body") {
    return chat
      ? "Ask Leafy returned an unreadable response. Try again."
      : "Meal estimate returned an unreadable response. Try again.";
  }
  if (error instanceof Error && error.message.trim()) return error.message;
  return chat
    ? "Ask Leafy could not answer right now. Try again."
    : "Unable to estimate that meal. Try again.";
}

export async function fetchOpenAIResponses(
  key: string,
  body: unknown,
  timeoutMs: number,
): Promise<{ ok: boolean; payload: Record<string, unknown> }> {
  try {
    return await fetchOpenAIResponsesOnce(key, body, timeoutMs);
  } catch (error) {
    if (!isNetworkError(error)) throw error;
    // Single retry only when no HTTP response arrived (DNS/connect blip).
    // Timeouts are not retried: the original request may already be billed,
    // and a second wait can exceed Edge Function wall time.
    return await fetchOpenAIResponsesOnce(key, body, timeoutMs);
  }
}

async function fetchOpenAIResponsesOnce(
  key: string,
  body: unknown,
  timeoutMs: number,
): Promise<{ ok: boolean; payload: Record<string, unknown> }> {
  const response = await fetch(openaiResponsesURL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const text = await response.text();
  if (!text.trim()) {
    return { ok: response.ok, payload: {} };
  }
  try {
    const payload = JSON.parse(text) as Record<string, unknown>;
    return { ok: response.ok, payload };
  } catch {
    throw new Error("malformed_openai_http_body");
  }
}

export function extractOpenAIOutputText(
  payload: unknown,
  emptyMessage: string,
): string {
  if (!payload || typeof payload !== "object") throw new Error(emptyMessage);
  const record = payload as Record<string, unknown>;
  if (typeof record.output_text === "string" && record.output_text.trim()) {
    return record.output_text;
  }
  const output = Array.isArray(record.output) ? record.output : [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = (item as Record<string, unknown>).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (!part || typeof part !== "object") continue;
      const entry = part as Record<string, unknown>;
      if (entry.type === "output_text" && typeof entry.text === "string" &&
        entry.text.trim()
      ) {
        return entry.text;
      }
    }
  }
  throw new Error(emptyMessage);
}

export function parseOpenAIJSONOutput(
  payload: unknown,
  emptyMessage: string,
  malformedMessage: string,
): Record<string, unknown> {
  const text = extractOpenAIOutputText(payload, emptyMessage);
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error(malformedMessage);
    }
    return parsed as Record<string, unknown>;
  } catch (error) {
    if (error instanceof Error && error.message === malformedMessage) throw error;
    throw new Error(malformedMessage);
  }
}

export function providerErrorMessage(payload: Record<string, unknown>): string | null {
  const error = payload.error;
  if (!error || typeof error !== "object") return null;
  const message = (error as Record<string, unknown>).message;
  return typeof message === "string" && message.trim() ? message : null;
}

export function openAIUsage(payload: Record<string, unknown>): {
  inputTokens: number | null;
  outputTokens: number | null;
} {
  const usage = payload.usage;
  if (!usage || typeof usage !== "object") {
    return { inputTokens: null, outputTokens: null };
  }
  const record = usage as Record<string, unknown>;
  const input = Number(record.input_tokens);
  const output = Number(record.output_tokens);
  return {
    inputTokens: Number.isFinite(input) ? input : null,
    outputTokens: Number.isFinite(output) ? output : null,
  };
}
