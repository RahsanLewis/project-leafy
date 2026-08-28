import { createClient } from "npm:@supabase/supabase-js@2";
import { requireCatalogAdmin, requireUser } from "../_shared/auth.ts";
import { cors, errorResponse, json } from "../_shared/http.ts";
import { calculateAndPersistPFQS } from "../_shared/pfqs/persistence.ts";
import { normalizePFQSJurisdiction } from "../_shared/pfqs/scorer.ts";
import type { PFQSNutrientCode, PFQSNutrients } from "../_shared/pfqs/types.ts";
import { nutrientCodes, nutrientUnits } from "../_shared/nutrients.ts";
import { applyNutritionFootnoteDeclarations } from "../_shared/package-label.ts";
import { fulfillCatalogLogRequest, markCatalogLogRequest } from "../_shared/catalog-log.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

type Row = Record<string, unknown>;
type Body = {
  action?:
    | "start"
    | "register_asset"
    | "extract"
    | "enqueue"
    | "submit"
    | "list"
    | "detail"
    | "pending_logs"
    | "cancel_log"
    | "delete_draft"
    | "log"
    | "admin_retry";
  contribution_id?: string;
  barcode?: string;
  market_country?: string;
  asset_kind?: string;
  object_path?: string;
  confirmed_fields?: Row;
  nutrients?: NutrientInput[];
  consent_version?: number;
  grams?: number;
  consumed_at?: string;
  local_date?: string;
  time_zone?: string;
  meal_type?: string;
  serving_count?: number;
  refresh_existing?: boolean;
};
type NutrientInput = {
  code: string;
  amount_per_serving: number;
  unit: string;
  percent_daily_value?: number | null;
  confidence?: number;
  declaration_type?:
    | "quantified"
    | "declared_zero"
    | "not_significant_source"
    | "derived";
  printed_text?: string | null;
  evidence_section?: string | null;
};

const knownNutrients = ["energy_kcal", ...nutrientCodes];
// These are the nutrients needed to publish a useful consumer record. Optional
// micronutrients may be absent from a U.S. label and must not block recognition.
const requiredNutrients = [
  "energy_kcal",
  "fat_g",
  "saturated_fat_g",
  "sodium_mg",
  "carbohydrate_g",
  "fiber_g",
  "added_sugars_g",
  "protein_g",
];
const units: Record<string, string> = { energy_kcal: "kcal", ...nutrientUnits };
const extractionSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "product_name",
    "brand_name",
    "brand_not_shown",
    "flavor",
    "claims",
    "serving_description",
    "serving_amount",
    "serving_unit",
    "metric_serving_amount",
    "metric_serving_unit",
    "serving_grams",
    "servings_per_container",
    "ingredients",
    "allergens",
    "nutrients",
    "label_sections",
    "evidence",
    "field_confidence",
  ],
  properties: {
    product_name: { type: "string" },
    brand_name: { type: "string" },
    brand_not_shown: { type: "boolean" },
    flavor: { type: "string" },
    claims: { type: "array", items: { type: "string" }, maxItems: 40 },
    serving_description: { type: "string" },
    serving_amount: { type: ["number", "null"] },
    serving_unit: { type: "string" },
    metric_serving_amount: { type: ["number", "null"] },
    metric_serving_unit: { type: "string" },
    serving_grams: { type: ["number", "null"] },
    servings_per_container: { type: "string" },
    ingredients: { type: "string" },
    allergens: { type: "array", items: { type: "string" }, maxItems: 30 },
    nutrients: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "code",
          "amount_per_serving",
          "unit",
          "percent_daily_value",
          "confidence",
          "declaration_type",
          "printed_text",
          "evidence_section",
        ],
        properties: {
          code: { type: "string", enum: knownNutrients },
          amount_per_serving: { type: "number" },
          unit: { type: "string" },
          percent_daily_value: { type: ["number", "null"] },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          declaration_type: {
            type: "string",
            enum: ["quantified", "declared_zero", "not_significant_source"],
          },
          printed_text: { type: ["string", "null"] },
          evidence_section: { type: ["string", "null"] },
        },
      },
    },
    label_sections: {
      type: "object",
      additionalProperties: false,
      required: [
        "front",
        "nutrition_facts",
        "nutrition_footnote",
        "ingredients",
        "other",
      ],
      properties: {
        front: { type: "string" },
        nutrition_facts: { type: "string" },
        nutrition_footnote: { type: "string" },
        ingredients: { type: "string" },
        other: { type: "string" },
      },
    },
    evidence: {
      type: "object",
      additionalProperties: false,
      required: [
        "front_legible",
        "nutrition_facts_legible",
        "ingredients_legible",
      ],
      properties: {
        front_legible: { type: "boolean" },
        nutrition_facts_legible: { type: "boolean" },
        ingredients_legible: { type: "boolean" },
      },
    },
    field_confidence: { type: "number", minimum: 0, maximum: 1 },
  },
};

const verificationSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "exact_gtin_match",
    "product_name",
    "brand_name",
    "serving_description",
    "serving_grams",
    "ingredients",
    "nutrients",
    "source_quality",
    "matched_fields",
    "conflict_fields",
    "summary",
  ],
  properties: {
    exact_gtin_match: { type: "boolean" },
    product_name: { type: "string" },
    brand_name: { type: "string" },
    serving_description: { type: "string" },
    serving_grams: { type: "number" },
    ingredients: { type: "string" },
    nutrients: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["code", "amount_per_serving", "unit", "confidence"],
        properties: {
          code: { type: "string", enum: knownNutrients },
          amount_per_serving: { type: "number" },
          unit: { type: "string", enum: ["kcal", "g", "mg", "mcg"] },
          confidence: { type: "number", minimum: 0, maximum: 1 },
        },
      },
    },
    source_quality: {
      type: "string",
      enum: ["manufacturer", "usda", "retailer", "database", "other", "none"],
    },
    matched_fields: { type: "array", items: { type: "string" }, maxItems: 20 },
    conflict_fields: { type: "array", items: { type: "string" }, maxItems: 20 },
    summary: { type: "string" },
  },
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  try {
    const body = await request.json().catch(() => ({})) as Body;
    const action = body.action ?? "list";
    if (action === "admin_retry") {
      const { admin } = await requireCatalogAdmin(request);
      if (!body.contribution_id) {
        return json({ error: "A contribution identifier is required." }, 400);
      }
      const contribution = await byID(
        admin,
        body.contribution_id,
      );
      EdgeRuntime.waitUntil(
        runAutomation(
          admin,
          String(contribution.user_id),
          String(contribution.id),
        ).catch((error) => console.error("admin retry failed", error)),
      );
      return json({ outcome: "processing" }, 202);
    }
    const { user, admin } = await requireUser(request);

    if (action === "start") return json(await start(admin, user.id, body));
    if (action === "list") {
      EdgeRuntime.waitUntil(
        resumeReadyJobs(admin, user.id).catch((error) =>
          console.error("catalog retry resume failed", error)
        ),
      );
      return json({ contributions: await list(admin, user.id) });
    }
    if (action === "pending_logs") {
      return json({ pending_logs: await pendingLogs(admin, user.id, body.local_date) });
    }
    if (!body.contribution_id) {
      return json({ error: "A contribution identifier is required." }, 400);
    }
    const contribution = await owned(admin, user.id, body.contribution_id);
    if (action === "detail") {
      return json({ contribution: await detail(admin, contribution) });
    }
    if (action === "register_asset") {
      return json({
        contribution: await registerAsset(admin, contribution, body),
      });
    }
    if (action === "extract") {
      return json({
        contribution: await extract(admin, user.id, contribution),
      });
    }
    if (action === "enqueue") {
      const queued = await enqueueAutomation(
        admin,
        user.id,
        contribution,
        body,
      );
      EdgeRuntime.waitUntil(
        runAutomation(admin, user.id, String(contribution.id)).catch(
          (error) => {
            console.error("catalog automation background task failed", error);
          },
        ),
      );
      return json({
        outcome: "processing",
        contribution: queued,
        food_version_id: null,
        pending_log: await pendingLogForContribution(admin, user.id, String(contribution.id)),
      }, 202);
    }
    if (action === "submit") {
      return json(await submit(admin, contribution, body));
    }
    if (action === "delete_draft") {
      return json(await deleteDraft(admin, contribution));
    }
    if (action === "cancel_log") {
      const cancelled = await admin.from("catalog_contribution_log_requests").update({
        status: "cancelled", updated_at: new Date().toISOString(),
      }).eq("contribution_id", contribution.id).eq("user_id", user.id)
        .in("status", ["pending", "processing", "needs_action", "failed"])
        .select("id").maybeSingle();
      if (cancelled.error) throw cancelled.error;
      return json({ ok: true });
    }
    if (action === "log") {
      return json({
        entry: await logContribution(admin, user.id, contribution, body),
      });
    }
    return json({ error: "Unsupported contribution action." }, 400);
  } catch (error) {
    console.error("manage-catalog-contribution failed", error);
    return errorResponse(error, "Unable to update that product.");
  }
});

function adminClient(url: string, secret: string) {
  return createClient(url, secret, { auth: { persistSession: false } });
}

async function byID(admin: any, id: string) {
  const result = await admin.from("catalog_contributions").select("*").eq(
    "id",
    id,
  ).single();
  if (result.error) throw result.error;
  return result.data;
}

async function start(admin: any, userID: string, body: Body) {
  const gtin = normalizeBarcode(body.barcode ?? "");
  if (!gtin) throw new Error("Scan a valid UPC or EAN barcode.");
  const market = String(body.market_country ?? "US").trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(market)) {
    throw new Error("Choose a valid product market.");
  }
  const existing = await activeProduct(admin, gtin, market);
  if (existing && body.refresh_existing !== true) {
    return {
      outcome: "existing",
      food_version_id: existing.id,
      contribution: null,
    };
  }
  let resumedQuery = admin.from("catalog_contributions").select("*").eq(
    "user_id",
    userID,
  ).eq("gtin", gtin)
    .in("status", ["draft", "processing", "pending_review", "needs_review"])
    .order("updated_at", { ascending: false }).limit(1);
  if (body.refresh_existing === true && existing) {
    resumedQuery = resumedQuery.eq("target_food_version_id", existing.id);
  } else resumedQuery = resumedQuery.is("target_food_version_id", null);
  const resumed = await resumedQuery.maybeSingle();
  if (resumed.error) throw resumed.error;
  if (resumed.data) {
    return {
      outcome: "contribution",
      contribution: await detail(admin, resumed.data),
    };
  }
  const created = await admin.from("catalog_contributions").insert({
    user_id: userID,
    gtin,
    market_country: market,
    status: "draft",
    target_food_version_id: body.refresh_existing === true
      ? existing?.id ?? null
      : null,
  }).select("*").single();
  if (created.error) throw created.error;
  await event(
    admin,
    created.data.id,
    "user",
    null,
    "draft",
    "Unknown barcode contribution started",
  );
  return {
    outcome: "contribution",
    contribution: await detail(admin, created.data),
  };
}

async function list(admin: any, userID: string) {
  const result = await admin.from("catalog_contributions").select("*").eq(
    "user_id",
    userID,
  ).order("updated_at", { ascending: false }).limit(100);
  if (result.error) throw result.error;
  return result.data ?? [];
}

async function pendingLogs(admin: any, userID: string, localDate?: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(localDate ?? ""))) {
    throw new Error("Choose a valid food-log date.");
  }
  const result = await admin.from("catalog_contribution_log_requests").select(
    "id,contribution_id,serving_count,consumed_at,local_date,time_zone,meal_type,status,last_error,food_entry_id,created_at,updated_at,catalog_contributions(gtin,confirmed_fields,extracted_fields,status)",
  ).eq("user_id", userID).eq("local_date", localDate)
    .in("status", ["pending", "processing", "needs_action", "failed"])
    .order("consumed_at", { ascending: true });
  if (result.error) throw result.error;
  return (result.data ?? []).map((row: Row) => {
    const contribution = row.catalog_contributions as Row ?? {};
    const fields = contribution.confirmed_fields as Row ?? contribution.extracted_fields as Row ?? {};
    return {
      id: row.id,
      contribution_id: row.contribution_id,
      name: fields.product_name || `Barcode ${contribution.gtin ?? ""}`,
      barcode: contribution.gtin,
      serving_count: row.serving_count,
      consumed_at: row.consumed_at,
      local_date: row.local_date,
      time_zone: row.time_zone,
      meal_type: row.meal_type,
      status: row.status,
      message: row.last_error,
      updated_at: row.updated_at,
    };
  });
}

async function pendingLogForContribution(admin: any, userID: string, contributionID: string) {
  const result = await admin.from("catalog_contribution_log_requests").select("*")
    .eq("user_id", userID).eq("contribution_id", contributionID).maybeSingle();
  if (result.error) throw result.error;
  if (!result.data) return null;
  const contribution = await owned(admin, userID, contributionID);
  const fields = contribution.confirmed_fields as Row ?? contribution.extracted_fields as Row ?? {};
  return {
    id: result.data.id,
    contribution_id: contributionID,
    name: fields.product_name || `Barcode ${contribution.gtin}`,
    barcode: contribution.gtin,
    serving_count: result.data.serving_count,
    consumed_at: result.data.consumed_at,
    local_date: result.data.local_date,
    time_zone: result.data.time_zone,
    meal_type: result.data.meal_type,
    status: result.data.status,
    message: result.data.last_error,
    updated_at: result.data.updated_at,
  };
}

async function resumeReadyJobs(admin: any, userID: string) {
  const ready = await admin.from("catalog_contribution_jobs").select(
    "contribution_id",
  )
    .eq("user_id", userID).in("status", ["queued", "retry_wait"]).lte(
      "next_attempt_at",
      new Date().toISOString(),
    ).limit(3);
  if (ready.error) throw ready.error;
  await Promise.all(
    (ready.data ?? []).map((job: Row) =>
      runAutomation(admin, userID, String(job.contribution_id))
    ),
  );
}

async function detail(admin: any, contribution: Row) {
  const assets = await admin.from("product_label_assets").select(
    "id,asset_kind,object_path,created_at",
  ).eq("contribution_id", contribution.id);
  if (assets.error) throw assets.error;
  const nutrients = await admin.from("catalog_contribution_nutrients").select(
    "nutrient_code,amount_per_serving,unit,percent_daily_value,confidence,declaration_type,printed_text,evidence_section",
  ).eq("contribution_id", contribution.id).eq(
    "revision",
    contribution.revision,
  );
  if (nutrients.error) throw nutrients.error;
  const job = await admin.from("catalog_contribution_jobs").select(
    "status,last_error,completed_at",
  ).eq("contribution_id", contribution.id).maybeSingle();
  if (job.error) throw job.error;
  return {
    ...contribution,
    assets: assets.data ?? [],
    nutrients: nutrients.data ?? [],
    extraction_diagnostics: extractionDiagnostics(contribution),
    processing_stage: job.data?.status ?? null,
  };
}

async function registerAsset(admin: any, contribution: Row, body: Body) {
  assertEditable(contribution);
  const kind = String(body.asset_kind ?? "");
  if (
    !["front", "back_label", "nutrition_facts", "ingredients"].includes(kind)
  ) throw new Error("Choose a valid label photo type.");
  const path = String(body.object_path ?? "");
  if (
    !path.startsWith(
      `${contribution.user_id}/catalog-contributions/${contribution.id}/`,
    )
  ) throw new Error("That label photo does not belong to this contribution.");
  const downloaded = await admin.storage.from("nutrition-media").download(path);
  if (downloaded.error) throw downloaded.error;
  const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
  if (!bytes.length || bytes.length > 8 * 1024 * 1024) {
    throw new Error("Choose a label photo smaller than 8 MB.");
  }
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hash = [...new Uint8Array(digest)].map((x) =>
    x.toString(16).padStart(2, "0")
  ).join("");
  const previous = await admin.from("product_label_assets").select(
    "object_path",
  ).eq("contribution_id", contribution.id).eq("asset_kind", kind).maybeSingle();
  if (previous.error) throw previous.error;
  const result = await admin.from("product_label_assets").upsert({
    contribution_id: contribution.id,
    user_id: contribution.user_id,
    asset_kind: kind,
    object_path: path,
    content_hash: hash,
    metadata_stripped: true,
    mime_type: "image/jpeg",
    byte_count: bytes.length,
  }, { onConflict: "contribution_id,asset_kind" });
  if (result.error) throw result.error;
  if (previous.data?.object_path && previous.data.object_path !== path) {
    await admin.storage.from("nutrition-media").remove([
      previous.data.object_path,
    ]);
  }
  await touch(admin, String(contribution.id));
  return detail(
    admin,
    await owned(admin, String(contribution.user_id), String(contribution.id)),
  );
}

async function extract(admin: any, userID: string, contribution: Row) {
  assertEditable(contribution);
  const assets = await admin.from("product_label_assets").select("*").eq(
    "contribution_id",
    contribution.id,
  ).order("created_at");
  if (assets.error) throw assets.error;
  const kinds = new Set((assets.data ?? []).map((row: Row) => row.asset_kind));
  if (!kinds.has("front")) {
    throw new Error("Add a clear photo of the front of the package.");
  }
  if (
    !kinds.has("back_label") &&
    !(kinds.has("nutrition_facts") && kinds.has("ingredients"))
  ) {
    throw new Error(
      "Add a clear back-label photo showing Nutrition Facts and ingredients.",
    );
  }
  const content: Row[] = [{
    type: "input_text",
    text: extractionPrompt(String(contribution.gtin)),
  }];
  for (const asset of assets.data ?? []) {
    const downloaded = await admin.storage.from("nutrition-media").download(
      asset.object_path,
    );
    if (downloaded.error) throw downloaded.error;
    const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
    content.push({
      type: "input_text",
      text: `Image role: ${asset.asset_kind}`,
    });
    content.push({
      type: "input_image",
      image_url: `data:image/jpeg;base64,${toBase64(bytes)}`,
      detail: "high",
    });
  }
  const key = Deno.env.get("OPENAI_API_KEY");
  if (!key) throw new Error("Product label extraction is not configured yet.");
  const model = Deno.env.get("OPENAI_MEAL_MODEL") ?? "gpt-5.6-terra";
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      store: false,
      reasoning: { effort: "low" },
      safety_identifier: await safetyID(userID),
      input: [{
        role: "system",
        content: [{
          type: "input_text",
          text:
            "Extract only facts visibly printed on this U.S. packaged-food label. Never infer or estimate missing nutrients. Use 0 only when the label explicitly prints 0. Return all standard nutrient codes, using an amount of -1 for a field that is not visible.",
        }],
      }, { role: "user", content }],
      text: {
        format: {
          type: "json_schema",
          name: "leafy_product_label",
          strict: true,
          schema: extractionSchema,
        },
      },
    }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(
      payload?.error?.message ?? "Leafy could not read that product label.",
    );
  }
  const extracted = JSON.parse(extractOutputText(payload));
  extracted.nutrients = normalizeLabelNutrients(extracted);
  const validation = validate(extracted, extracted.nutrients, extracted);
  const update = await admin.from("catalog_contributions").update({
    extracted_fields: extracted,
    validation_results: validation,
    updated_at: new Date().toISOString(),
  }).eq("id", contribution.id).select("*").single();
  if (update.error) throw update.error;
  return detail(admin, update.data);
}

async function enqueueAutomation(
  admin: any,
  userID: string,
  contribution: Row,
  body: Body,
) {
  assertEditable(contribution);
  if (body.consent_version !== 1) {
    throw new Error(
      "Review the current catalog contribution terms before submitting.",
    );
  }
  const assets = await admin.from("product_label_assets").select("asset_kind")
    .eq("contribution_id", contribution.id);
  if (assets.error) throw assets.error;
  const kinds = new Set(
    (assets.data ?? []).map((row: Row) => String(row.asset_kind)),
  );
  if (!kinds.has("front")) {
    throw new Error("Add a clear photo of the package front.");
  }
  if (
    !kinds.has("back_label") &&
    !(kinds.has("nutrition_facts") && kinds.has("ingredients"))
  ) {
    throw new Error(
      "Add a clear photo showing Nutrition Facts and ingredients.",
    );
  }
  const requestedLog = body.serving_count == null ? null : {
    serving_count: number(body.serving_count, 0.25, 100),
    consumed_at: body.consumed_at,
    local_date: body.local_date,
    time_zone: body.time_zone,
    meal_type: body.meal_type ?? "unspecified",
  };
  const now = new Date().toISOString();
  const update = await admin.from("catalog_contributions").update({
    status: "processing",
    consent_version: 1,
    submitted_at: contribution.submitted_at ?? now,
    review_reason: null,
    automation_version: "catalog-automation-1.0",
    updated_at: now,
  }).eq("id", contribution.id).select("*").single();
  if (update.error) throw update.error;
  const job = await admin.from("catalog_contribution_jobs").upsert({
    contribution_id: contribution.id,
    user_id: userID,
    status: "queued",
    attempts: 0,
    next_attempt_at: now,
    requested_log: requestedLog,
    last_error: null,
    started_at: null,
    completed_at: null,
    updated_at: now,
  }, { onConflict: "contribution_id" });
  if (job.error) throw job.error;
  if (requestedLog) {
    const logRequest = await admin.from("catalog_contribution_log_requests").upsert({
      contribution_id: contribution.id,
      user_id: userID,
      serving_count: requestedLog.serving_count,
      consumed_at: requestedLog.consumed_at,
      local_date: requestedLog.local_date,
      time_zone: requestedLog.time_zone,
      meal_type: requestedLog.meal_type,
      status: "pending",
      food_entry_id: null,
      last_error: null,
      completed_at: null,
      updated_at: now,
    }, { onConflict: "contribution_id" });
    if (logRequest.error) throw logRequest.error;
  }
  await event(
    admin,
    String(contribution.id),
    "user",
    String(contribution.status),
    "processing",
    "Two-photo automated verification started",
  );
  return detail(admin, update.data);
}

async function runAutomation(
  admin: any,
  userID: string,
  contributionID: string,
) {
  const startedAt = new Date().toISOString();
  const claimed = await admin.from("catalog_contribution_jobs").update({
    status: "extracting",
    started_at: startedAt,
    updated_at: startedAt,
  }).eq("contribution_id", contributionID).in("status", [
    "queued",
    "retry_wait",
  ]).select("*").maybeSingle();
  if (claimed.error) throw claimed.error;
  if (!claimed.data) return;
  try {
    let contribution = await owned(admin, userID, contributionID);
    // Search the exact barcode while vision reads the package. This mirrors the
    // stronger consumer workflow: package evidence plus current primary sources.
    const onlinePromise = verifyIdentityOnline(
      userID,
      String(contribution.gtin),
      String(contribution.market_country),
      {},
    );
    await extract(admin, userID, contribution);
    const verification = await onlinePromise;
    contribution = await owned(admin, userID, contributionID);
    const visualFields = normalizeFields(
      contribution.extracted_fields as Row ?? {},
    );
    const visualNutrients = normalizeLabelNutrients(
      (contribution.extracted_fields as Row) ?? {},
    );
    const merged = mergeTrustedProductData(
      visualFields,
      visualNutrients,
      verification.result,
    );
    const mergedExtracted = {
      ...(contribution.extracted_fields as Row ?? {}),
      ...merged.fields,
      nutrients: merged.nutrients,
      online_verification: verification.result,
      field_provenance: merged.provenance,
    };
    const validation = validate(
      merged.fields,
      merged.nutrients,
      mergedExtracted,
    );
    const revisionNumber = Number(contribution.revision ?? 1);
    await persistAutomatedRevision(
      admin,
      contributionID,
      revisionNumber,
      mergedExtracted,
      merged.fields,
      merged.nutrients,
      validation,
    );
    await persistVerificationSources(
      admin,
      contributionID,
      revisionNumber,
      verification.sources,
      verification.result.exact_gtin_match === true,
      verification.result.matched_fields,
    );
    const diagnostics = extractionDiagnostics({
      ...contribution,
      extracted_fields: mergedExtracted,
      validation_results: validation,
    });
    if (diagnostics?.status === "needs_photos") {
      const firstRetake = Number(contribution.retake_count ?? 0) < 1;
      const status = firstRetake ? "needs_review" : "pending_review";
      const message = firstRetake
        ? String(diagnostics.message)
        : "Leafy could not confidently read every required label detail. Our catalog team will review it.";
      const updated = await admin.from("catalog_contributions").update({
        status,
        retake_count: firstRetake ? 1 : contribution.retake_count,
        extracted_fields: mergedExtracted,
        confirmed_fields: merged.fields,
        validation_results: validation,
        verification_results: verification.result,
        review_reason: message,
        updated_at: new Date().toISOString(),
      }).eq("id", contributionID);
      if (updated.error) throw updated.error;
      await markCatalogLogRequest(admin, contributionID, "needs_action", message);
      await finishJob(admin, contributionID, "complete", null);
      await event(
        admin,
        contributionID,
        "automatic",
        "processing",
        status,
        message,
      );
      return;
    }

    const fields = merged.fields;
    const nutrients = merged.nutrients;

    const verifying = await admin.from("catalog_contribution_jobs").update({
      status: "verifying",
      updated_at: new Date().toISOString(),
    }).eq("contribution_id", contributionID);
    if (verifying.error) throw verifying.error;
    const identityAgreement = verification.result.exact_gtin_match === true &&
      verification.result.conflict_fields.length === 0 &&
      namesAgree(
        String(fields.product_name),
        verification.result.product_name,
      ) &&
      (Boolean(fields.brand_not_shown) ||
        namesAgree(String(fields.brand_name), verification.result.brand_name));
    const trustedSource = ["manufacturer", "usda", "retailer", "database"]
      .includes(verification.result.source_quality);
    // A clear, internally consistent package label is itself authoritative. Online
    // identity lookup improves provenance, but its absence must not force a complete
    // label into the manual queue.
    const autoPublish = validation.auto_approve === true;

    // Fulfill the user's original logging intent before shared publication.
    await fulfillCatalogLogRequest(admin, {
      ...contribution,
      confirmed_fields: fields,
    });

    let foodVersionID: string | null = null;
    let status = "pending_review";
    let reason = verification.result.summary ||
      "Leafy could not verify this package with enough confidence to publish it automatically.";
    if (autoPublish) {
      const publishing = await admin.from("catalog_contribution_jobs").update({
        status: "publishing",
        updated_at: new Date().toISOString(),
      }).eq("contribution_id", contributionID);
      if (publishing.error) throw publishing.error;
      const existing = await activeProduct(
        admin,
        String(contribution.gtin),
        String(contribution.market_country),
      );
      foodVersionID = existing?.id ?? await publish(
        admin,
        contribution,
        fields,
        nutrients,
        identityAgreement && trustedSource &&
          ["manufacturer", "usda"].includes(verification.result.source_quality)
          ? "verified"
          : "community_confirmed",
      );
      status = "accepted";
      reason = "Package details verified and added to Leafy.";
    }
    const now = new Date().toISOString();
    const update = await admin.from("catalog_contributions").update({
      status,
      extracted_fields: mergedExtracted,
      confirmed_fields: fields,
      validation_results: validation,
      verification_results: verification.result,
      accepted_food_version_id: foodVersionID,
      last_submitted_at: now,
      reviewed_at: status === "accepted" ? now : null,
      review_reason: reason,
      updated_at: now,
    }).eq("id", contributionID);
    if (update.error) throw update.error;
    await finishJob(admin, contributionID, "complete", null);
    await event(
      admin,
      contributionID,
      "automatic",
      "processing",
      status,
      reason,
      { verification: verification.result },
    );
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Automated product processing failed.";
    const job = await admin.from("catalog_contribution_jobs").select("attempts")
      .eq("contribution_id", contributionID).single();
    const attempts = Number(job.data?.attempts ?? 0) + 1;
    const retry = attempts < 3;
    const next = new Date(Date.now() + Math.pow(2, attempts) * 30_000)
      .toISOString();
    const failed = await admin.from("catalog_contribution_jobs").update({
      status: retry ? "retry_wait" : "failed",
      attempts,
      next_attempt_at: next,
      last_error: message,
      completed_at: retry ? null : new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("contribution_id", contributionID);
    if (failed.error) {
      console.error("could not save catalog job failure", failed.error);
    }
    if (!retry) {
      await admin.from("catalog_contributions").update({
        status: "pending_review",
        review_reason:
          "Leafy could not finish automatic verification. Our catalog team will review it.",
        updated_at: new Date().toISOString(),
      }).eq("id", contributionID);
      await markCatalogLogRequest(admin, contributionID, "failed", message);
    } else {
      await markCatalogLogRequest(admin, contributionID, "pending", null);
    }
    throw error;
  }
}

async function persistAutomatedRevision(
  admin: any,
  contributionID: string,
  revision: number,
  extracted: Row,
  fields: Row,
  nutrients: NutrientInput[],
  validation: Row,
) {
  const revisionWrite = await admin.from("catalog_contribution_revisions")
    .upsert({
      contribution_id: contributionID,
      revision,
      extracted_fields: extracted,
      confirmed_fields: fields,
      validation_results: validation,
    }, { onConflict: "contribution_id,revision" });
  if (revisionWrite.error) throw revisionWrite.error;
  await admin.from("catalog_contribution_nutrients").delete().eq(
    "contribution_id",
    contributionID,
  ).eq("revision", revision);
  if (nutrients.length) {
    const write = await admin.from("catalog_contribution_nutrients").insert(
      nutrients.map((item) => ({
        contribution_id: contributionID,
        revision,
        nutrient_code: item.code,
        amount_per_serving: item.amount_per_serving,
        unit: item.unit,
        percent_daily_value: item.percent_daily_value ?? null,
        confidence: item.confidence ?? 1,
        printed_on_label: true,
        declaration_type: item.declaration_type ?? "quantified",
        printed_text: item.printed_text ?? null,
        evidence_section: item.evidence_section ?? "nutrition_facts",
      })),
    );
    if (write.error) throw write.error;
  }
}

async function verifyIdentityOnline(
  userID: string,
  gtin: string,
  market: string,
  fields: Row,
) {
  const key = Deno.env.get("OPENAI_API_KEY");
  if (!key) {
    throw new Error("Online product verification is not configured yet.");
  }
  const model = Deno.env.get("OPENAI_MEAL_MODEL") ?? "gpt-5.6-terra";
  const photographed = fields.product_name
    ? `The photographed package appears to read product name "${fields.product_name}" and brand "${fields.brand_name}".`
    : "Package vision is running in parallel, so identify the product independently from its barcode.";
  const prompt =
    `Research packaged food barcode ${gtin} sold in ${market}. ${photographed} Search the exact GTIN on official manufacturer or brand pages and USDA branded-food records first, then reputable retailers and established product databases. Open sources rather than relying on snippets. Return the official product identity, serving, ingredients, and all nutrition values explicitly supported by an exact-barcode source. Use -1 for unsupported nutrient values. Mark exact_gtin_match true only when a consulted source explicitly associates this exact barcode with the product. Report any conflicts conservatively.`;
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      store: false,
      reasoning: { effort: "medium" },
      safety_identifier: await safetyID(userID),
      tools: [{ type: "web_search" }],
      include: ["web_search_call.action.sources"],
      input: [{
        role: "system",
        content: [{
          type: "input_text",
          text:
            "You verify packaged-food identity. Prefer primary sources and exact barcode matches. Return conservative structured results.",
        }],
      }, { role: "user", content: [{ type: "input_text", text: prompt }] }],
      text: {
        format: {
          type: "json_schema",
          name: "leafy_catalog_identity",
          strict: true,
          schema: verificationSchema,
        },
      },
    }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(
      payload?.error?.message ?? "Leafy could not verify that product online.",
    );
  }
  const result = JSON.parse(extractOutputText(payload));
  return { result, sources: collectWebSources(payload, result.source_quality) };
}

function mergeTrustedProductData(
  visualFields: Row,
  visualNutrients: NutrientInput[],
  online: Row,
) {
  const trusted = online.exact_gtin_match === true &&
    ["manufacturer", "usda", "retailer", "database"].includes(
      String(online.source_quality),
    );
  const onlineFields: Row = normalizeFields({
    product_name: online.product_name,
    brand_name: online.brand_name,
    brand_not_shown: false,
    serving_description: online.serving_description,
    serving_grams: online.serving_grams,
    ingredients: online.ingredients,
  });
  const fields = { ...visualFields };
  const provenance: Row = {};
  for (
    const key of [
      "product_name",
      "brand_name",
      "serving_description",
      "serving_grams",
      "ingredients",
    ]
  ) {
    const visualValue = fields[key];
    const lookupValue = onlineFields[key];
    if (visualValue !== "" && visualValue !== 0 && visualValue != null) {
      provenance[key] = "package_image";
    } else if (
      trusted && lookupValue !== "" && lookupValue !== 0 && lookupValue != null
    ) {
      fields[key] = lookupValue;
      provenance[key] = "verified_exact_barcode_source";
    }
  }
  const onlineNutrients = trusted ? normalizeNutrients(online.nutrients) : [];
  const nutrientMap = new Map(
    visualNutrients.map((item) => [item.code, { ...item }]),
  );
  for (const nutrient of onlineNutrients) {
    if (!nutrientMap.has(nutrient.code)) {
      nutrientMap.set(nutrient.code, {
        ...nutrient,
        confidence: Math.min(0.95, nutrient.confidence ?? 0.9),
      });
    }
  }
  provenance.nutrients = Object.fromEntries(
    [...nutrientMap].map(([code]) => [
      code,
      visualNutrients.some((item) => item.code === code)
        ? "package_image"
        : "verified_exact_barcode_source",
    ]),
  );
  return { fields, nutrients: [...nutrientMap.values()], provenance };
}

function collectWebSources(payload: Row, fallbackKind: string) {
  const found = new Map<string, Row>();
  const visit = (value: unknown) => {
    if (Array.isArray(value)) {
      value.forEach(visit);
      return;
    }
    if (!value || typeof value !== "object") return;
    const row = value as Row;
    if (typeof row.url === "string" && /^https?:\/\//.test(row.url)) {
      found.set(row.url, {
        url: row.url,
        title: String(row.title ?? ""),
        source_kind: normalizeSourceKind(fallbackKind),
      });
    }
    Object.values(row).forEach(visit);
  };
  visit(payload.output);
  return [...found.values()];
}

async function persistVerificationSources(
  admin: any,
  contributionID: string,
  revision: number,
  sources: Row[],
  exactGTINMatch: boolean,
  matchedFields: unknown,
) {
  if (!sources.length) return;
  const rows = await Promise.all(sources.map(async (source) => {
    const parsed = new URL(String(source.url));
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(String(source.url)),
    );
    return {
      contribution_id: contributionID,
      revision,
      url: String(source.url),
      title: String(source.title ?? ""),
      domain: parsed.hostname,
      source_kind: normalizeSourceKind(String(source.source_kind ?? "other")),
      exact_gtin_match: exactGTINMatch,
      matched_fields: Array.isArray(matchedFields)
        ? matchedFields.map(String).slice(0, 20)
        : [],
      content_hash: [...new Uint8Array(digest)].map((x) =>
        x.toString(16).padStart(2, "0")
      ).join(""),
    };
  }));
  const write = await admin.from("catalog_verification_sources").upsert(rows, {
    onConflict: "contribution_id,revision,url",
  });
  if (write.error) throw write.error;
}

function normalizeSourceKind(value: string) {
  return ["manufacturer", "usda", "retailer", "database"].includes(value)
    ? value
    : "other";
}

function namesAgree(left: string, right: string) {
  const tokens = (value: string) =>
    new Set(
      value.toLowerCase().replace(/[^a-z0-9 ]/g, " ").split(/\s+/).filter((
        item,
      ) => item.length > 1),
    );
  const a = tokens(left);
  const b = tokens(right);
  if (!a.size || !b.size) return false;
  const intersection = [...a].filter((item) => b.has(item)).length;
  return intersection / Math.min(a.size, b.size) >= 0.6;
}

async function finishJob(
  admin: any,
  contributionID: string,
  status: string,
  error: string | null,
) {
  const result = await admin.from("catalog_contribution_jobs").update({
    status,
    last_error: error,
    completed_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }).eq("contribution_id", contributionID);
  if (result.error) throw result.error;
}

async function submit(admin: any, contribution: Row, body: Body) {
  assertEditable(contribution);
  if (body.consent_version !== 1) {
    throw new Error(
      "Review the current catalog contribution terms before submitting.",
    );
  }
  const fields = normalizeFields(body.confirmed_fields ?? {});
  const nutrients = normalizeNutrients(body.nutrients ?? []);
  const validation = validate(
    fields,
    nutrients,
    contribution.extracted_fields as Row ?? {},
  );
  const nextRevision = contribution.last_submitted_at
    ? Number(contribution.revision ?? 1) + 1
    : Number(contribution.revision ?? 1);
  const revision = await admin.from("catalog_contribution_revisions").upsert({
    contribution_id: contribution.id,
    revision: nextRevision,
    extracted_fields: contribution.extracted_fields ?? {},
    confirmed_fields: fields,
    validation_results: validation,
  }, { onConflict: "contribution_id,revision" });
  if (revision.error) throw revision.error;
  const removeNutrients = await admin.from("catalog_contribution_nutrients")
    .delete().eq("contribution_id", contribution.id).eq(
      "revision",
      nextRevision,
    );
  if (removeNutrients.error) throw removeNutrients.error;
  if (nutrients.length) {
    const inserted = await admin.from("catalog_contribution_nutrients").insert(
      nutrients.map((item) => ({
        contribution_id: contribution.id,
        revision: nextRevision,
        nutrient_code: item.code,
        amount_per_serving: item.amount_per_serving,
        unit: item.unit,
        percent_daily_value: item.percent_daily_value ?? null,
        confidence: item.confidence ?? 1,
        printed_on_label: true,
        declaration_type: item.declaration_type ?? "quantified",
        printed_text: item.printed_text ?? null,
        evidence_section: item.evidence_section ?? "nutrition_facts",
      })),
    );
    if (inserted.error) throw inserted.error;
  }
  let status = validation.missing_fields.length
    ? "needs_review"
    : validation.auto_approve
    ? "accepted"
    : "pending_review";
  let foodVersionID: string | null = null;
  if (status === "accepted") {
    const existing = await activeProduct(
      admin,
      String(contribution.gtin),
      String(contribution.market_country),
    );
    if (existing) foodVersionID = existing.id;
    else {foodVersionID = await publish(
        admin,
        contribution,
        fields,
        nutrients,
        "unverified",
      );}
  }
  const now = new Date().toISOString();
  const update = await admin.from("catalog_contributions").update({
    status,
    confirmed_fields: fields,
    validation_results: validation,
    consent_version: 1,
    revision: nextRevision,
    accepted_food_version_id: foodVersionID,
    submitted_at: contribution.submitted_at ?? now,
    last_submitted_at: now,
    reviewed_at: status === "accepted" ? now : null,
    review_reason: validation.reason,
    updated_at: now,
  }).eq("id", contribution.id).select("*").single();
  if (update.error) throw update.error;
  await event(
    admin,
    String(contribution.id),
    "automatic",
    String(contribution.status),
    status,
    validation.reason,
    validation,
  );
  return {
    outcome: status,
    contribution: await detail(admin, update.data),
    food_version_id: foodVersionID,
    validation_results: validation,
  };
}

async function publish(
  admin: any,
  contribution: Row,
  fields: Row,
  nutrients: NutrientInput[],
  verification: string,
) {
  const targetID = contribution.target_food_version_id
    ? String(contribution.target_food_version_id)
    : null;
  let foodID: string;
  if (targetID) {
    const target = await admin.from("food_versions").select("food_id").eq(
      "id",
      targetID,
    ).is("superseded_at", null).single();
    if (target.error) throw target.error;
    foodID = String(target.data.food_id);
  } else {
    const canonical = await admin.from("foods").insert({
      canonical_name: fields.product_name,
    }).select("id").single();
    if (canonical.error) throw canonical.error;
    foodID = String(canonical.data.id);
  }
  const version = await admin.from("food_versions").insert({
    food_id: foodID,
    source_system: "leafy",
    source_record_id: String(contribution.id),
    source_data_type: "community_label",
    description: fields.product_name,
    brand_name: fields.brand_not_shown ? null : fields.brand_name,
    gtin: contribution.gtin,
    market_country: contribution.market_country,
    ingredients_text: fields.ingredients,
    allergens: fields.allergens ?? [],
    serving_size: fields.serving_amount,
    serving_unit: fields.serving_unit,
    servings_per_container: fields.servings_per_container || null,
    metric_serving_size: fields.metric_serving_amount,
    metric_serving_unit: fields.metric_serving_unit || null,
    package_claims: fields.claims ?? [],
    label_sections: fields.label_sections ?? {},
    verification_status: targetID ? "rejected" : verification,
    raw_source: {
      contribution_id: contribution.id,
      revision: contribution.revision,
      label_sections: fields.label_sections ?? {},
    },
  }).select("id").single();
  if (version.error) throw version.error;
  const servingWrite = await admin.from("food_version_serving_nutrients")
    .insert(nutrients.map((item) => ({
      food_version_id: version.data.id,
      nutrient_code: item.code,
      amount_per_serving: item.amount_per_serving,
      unit: item.unit,
      percent_daily_value: item.percent_daily_value ?? null,
      declaration_type: item.declaration_type ?? "quantified",
      printed_text: item.printed_text ?? null,
      evidence_section: item.evidence_section ?? "nutrition_facts",
    })));
  if (servingWrite.error) throw servingWrite.error;
  if (Number(fields.serving_grams) > 0) {
    const per100 = nutrients.map((item) => ({
      food_version_id: version.data.id,
      nutrient_code: item.code,
      amount_per_100g: Number(
        (item.amount_per_serving * 100 / Number(fields.serving_grams)).toFixed(
          6,
        ),
      ),
      derivation_method: "label",
    }));
    const inserted = await admin.from("food_version_nutrients").insert(per100);
    if (inserted.error) throw inserted.error;
    const portion = await admin.from("food_portions").insert({
      food_version_id: version.data.id,
      amount: 1,
      unit: "serving",
      description: fields.serving_description,
      gram_weight: fields.serving_grams,
      source: "leafy_label",
    });
    if (portion.error) throw portion.error;
  }
  const pfqsNutrients = nutrients.filter((item) => isPFQSNutrient(item.code));
  const labelWrite = await admin.from("pfqs_label_nutrients").upsert(
    pfqsNutrients.map((item) => ({
      food_version_id: version.data.id,
      nutrient_code: item.code,
      amount_per_serving: item.amount_per_serving,
      unit: item.unit,
      explicitly_reported: true,
      source_method: "label",
      source_version:
        `leafy-contribution:${contribution.id}:${contribution.revision}`,
      confidence: item.confidence ?? 1,
    })),
    { onConflict: "food_version_id,nutrient_code" },
  );
  if (labelWrite.error) throw labelWrite.error;
  await calculateAndPersistPFQS(admin, version.data.id, {
    product_name: String(fields.product_name),
    jurisdiction: normalizePFQSJurisdiction(
      String(contribution.market_country ?? "US"),
    ),
    assessment_date: new Date().toISOString().slice(0, 10),
    serving_size: {
      amount: Number(fields.serving_amount),
      unit: String(fields.serving_unit),
      description: String(fields.serving_description ?? ""),
    },
    nutrition: Object.fromEntries(
      pfqsNutrients.map((item) => [item.code, item.amount_per_serving]),
    ) as PFQSNutrients,
    explicitly_reported_nutrients: pfqsNutrients.map((item) =>
      item.code as PFQSNutrientCode
    ),
    nutrient_evidence: Object.fromEntries(
      pfqsNutrients.map((item) => [item.code, {
        source: "label",
        confidence: Number(item.confidence ?? 1),
      }]),
    ),
    ingredients_raw: String(fields.ingredients ?? ""),
    verification_status: verification,
    product_type: "food",
  });
  if (targetID) {
    const activated = await admin.rpc("activate_food_version_replacement", {
      p_previous_id: targetID,
      p_replacement_id: version.data.id,
      p_verification_status: verification,
    });
    if (activated.error) throw activated.error;
  }
  return String(version.data.id);
}

function isPFQSNutrient(value: string): value is PFQSNutrientCode {
  return [
    "energy_kcal",
    "added_sugars_g",
    "fiber_g",
    "sodium_mg",
    "saturated_fat_g",
    "trans_fat_g",
    "protein_g",
  ].includes(value);
}

async function logContribution(
  admin: any,
  userID: string,
  contribution: Row,
  body: Body,
) {
  if (!["accepted", "pending_review"].includes(String(contribution.status))) {
    throw new Error("Finish reviewing this product before logging it.");
  }
  if (contribution.accepted_food_version_id) {
    throw new Error("accepted_product");
  }
  const fields = contribution.confirmed_fields as Row;
  const grams = Number(body.grams);
  const servingCount = Number(body.serving_count ?? 1);
  const servingGrams = Number(fields.serving_grams);
  const hasGramScale = Number.isFinite(grams) && grams > 0 && grams <= 5000 &&
    Number.isFinite(servingGrams) && servingGrams > 0;
  if (
    !hasGramScale &&
    (!Number.isFinite(servingCount) || servingCount <= 0 || servingCount > 100)
  ) throw new Error("Choose a valid serving amount.");
  const nutrientResult = await admin.from("catalog_contribution_nutrients")
    .select("*").eq("contribution_id", contribution.id).eq(
      "revision",
      contribution.revision,
    );
  if (nutrientResult.error) throw nutrientResult.error;
  const energy = nutrientResult.data?.find((item: Row) =>
    item.nutrient_code === "energy_kcal"
  );
  if (!energy) {
    throw new Error("This product does not have enough calorie data to log.");
  }
  const scale = hasGramScale ? grams / servingGrams : servingCount;
  const entry = await admin.from("food_entries").insert({
    user_id: userID,
    name: fields.product_name,
    calories: Math.max(
      1,
      Math.round(Number(energy.amount_per_serving) * scale),
    ),
    consumed_at: body.consumed_at,
    local_date: body.local_date,
    time_zone: body.time_zone,
    gram_weight: hasGramScale ? grams : null,
    amount: hasGramScale ? grams : servingCount,
    amount_unit: hasGramScale ? "g" : "serving",
    portion_description: hasGramScale
      ? `${format(grams)} g`
      : `${format(servingCount)} serving${servingCount === 1 ? "" : "s"}`,
    meal_type: body.meal_type ?? "unspecified",
    entry_source: "barcode",
    calorie_method: "nutrition_label",
    confidence: 0.85,
    user_confirmed: true,
    provenance: {
      source: "leafy_contribution",
      contribution_id: contribution.id,
      revision: contribution.revision,
    },
  }).select("*").single();
  if (entry.error) throw entry.error;
  const item = await admin.from("consumption_items").select("id").eq(
    "legacy_food_entry_id",
    entry.data.id,
  ).single();
  if (item.error) throw item.error;
  const snapshots = (nutrientResult.data ?? []).map((nutrient: Row) => ({
    consumption_item_id: item.data.id,
    nutrient_code: nutrient.nutrient_code,
    amount: Number((Number(nutrient.amount_per_serving) * scale).toFixed(6)),
    derivation_method: "label",
    source_version:
      `leafy-contribution:${contribution.id}:${contribution.revision}`,
    confidence: 0.85,
  }));
  if (snapshots.length) {
    const result = await admin.from("consumption_item_nutrients").upsert(
      snapshots,
      { onConflict: "consumption_item_id,nutrient_code" },
    );
    if (result.error) throw result.error;
  }
  return entry.data;
}

async function deleteDraft(admin: any, contribution: Row) {
  if (!["draft", "needs_review"].includes(String(contribution.status))) {
    throw new Error(
      "Only drafts and submissions needing changes can be deleted.",
    );
  }
  const assets = await admin.from("product_label_assets").select("object_path")
    .eq("contribution_id", contribution.id);
  if (assets.error) throw assets.error;
  const paths = (assets.data ?? []).map((item: Row) =>
    String(item.object_path)
  );
  if (paths.length) {
    const removed = await admin.storage.from("nutrition-media").remove(paths);
    if (removed.error) throw removed.error;
  }
  const removed = await admin.from("catalog_contributions").delete().eq(
    "id",
    contribution.id,
  );
  if (removed.error) throw removed.error;
  return { ok: true };
}

function validate(fields: Row, nutrients: NutrientInput[], extracted: Row) {
  const missing: string[] = [];
  if (!String(fields.product_name ?? "").trim()) missing.push("Product name");
  if (!String(fields.ingredients ?? "").trim()) missing.push("Ingredients");
  if (!fields.brand_not_shown && !String(fields.brand_name ?? "").trim()) {
    missing.push("Brand");
  }
  if (
    !(Number(fields.serving_amount) > 0) ||
    !String(fields.serving_unit ?? "").trim()
  ) missing.push("Serving size");
  if (!String(fields.serving_description ?? "").trim()) {
    missing.push("Serving description");
  }
  const map = new Map(nutrients.map((item) => [item.code, item]));
  for (const code of requiredNutrients) if (!map.has(code)) missing.push(code);
  const evidence = extracted.evidence as Row ?? {};
  const online = extracted.online_verification as Row ?? {};
  const trustedExactLookup = online.exact_gtin_match === true &&
    ["manufacturer", "usda", "retailer", "database"].includes(
      String(online.source_quality),
    );
  const evidenceComplete = (evidence.front_legible === true &&
    evidence.nutrition_facts_legible === true &&
    evidence.ingredients_legible === true) || trustedExactLookup;
  if (!evidenceComplete) missing.push("Clear package evidence");
  const calories = Number(map.get("energy_kcal")?.amount_per_serving);
  const macroCalories =
    Number(map.get("protein_g")?.amount_per_serving ?? 0) * 4 +
    Number(map.get("carbohydrate_g")?.amount_per_serving ?? 0) * 4 +
    Number(map.get("fat_g")?.amount_per_serving ?? 0) * 9;
  const calorieDifference = Math.abs(calories - macroCalories);
  const calorieConsistent = Number.isFinite(calories) && calories >= 0 &&
    calorieDifference <= Math.max(20, calories * 0.15);
  const confidence = Math.min(
    Number(extracted.field_confidence ?? 0),
    ...nutrients.map((item) => Number(item.confidence ?? 1)),
  );
  const plausible = nutrients.every((item) =>
    Number.isFinite(item.amount_per_serving) && item.amount_per_serving >= 0 &&
    item.amount_per_serving <=
      (item.unit === "g" ? 5000 : item.unit === "kcal" ? 10000 : 1_000_000)
  );
  const autoApprove = !missing.length && calorieConsistent && plausible &&
    confidence >= 0.9;
  const reason = missing.length
    ? `Missing or unreadable: ${missing.join(", ")}`
    : !calorieConsistent
    ? "Calories do not closely match the printed macronutrients."
    : !plausible
    ? "One or more nutrient values needs review."
    : confidence < 0.9
    ? "Label extraction confidence is below the automatic-publish threshold."
    : "Passed automatic label review.";
  return {
    missing_fields: missing,
    evidence_complete: evidenceComplete,
    calorie_consistent: calorieConsistent,
    calorie_difference: calorieDifference,
    plausible,
    confidence,
    auto_approve: autoApprove,
    reason,
  };
}

function normalizeFields(raw: Row) {
  return {
    product_name: clean(raw.product_name, 180),
    brand_name: clean(raw.brand_name, 120),
    brand_not_shown: raw.brand_not_shown === true,
    flavor: clean(raw.flavor, 120),
    claims: Array.isArray(raw.claims)
      ? raw.claims.map((item) => clean(item, 180)).filter(Boolean).slice(0, 40)
      : [],
    serving_description: clean(raw.serving_description, 120),
    serving_amount: nullableNumber(raw.serving_amount, 0, 100000),
    serving_unit: clean(raw.serving_unit, 30),
    metric_serving_amount: nullableNumber(raw.metric_serving_amount, 0, 100000),
    metric_serving_unit: clean(raw.metric_serving_unit, 30),
    serving_grams: nullableNumber(raw.serving_grams, 0, 5000),
    servings_per_container: clean(raw.servings_per_container, 80),
    ingredients: clean(raw.ingredients, 5000),
    allergens: Array.isArray(raw.allergens)
      ? raw.allergens.map((item) => clean(item, 100)).filter(Boolean).slice(
        0,
        30,
      )
      : [],
    label_sections: raw.label_sections && typeof raw.label_sections === "object"
      ? raw.label_sections
      : {},
  };
}
function normalizeNutrients(raw: unknown): NutrientInput[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  return raw.flatMap((value) => {
    const item = value as Row;
    const code = String(item.code ?? "");
    const amount = Number(item.amount_per_serving);
    if (
      !knownNutrients.includes(code) || seen.has(code) ||
      !Number.isFinite(amount) || amount < 0
    ) return [];
    seen.add(code);
    const declaration =
      ["quantified", "declared_zero", "not_significant_source", "derived"]
          .includes(String(item.declaration_type))
        ? String(item.declaration_type) as NutrientInput["declaration_type"]
        : amount === 0
        ? "declared_zero"
        : "quantified";
    return [{
      code,
      amount_per_serving: amount,
      unit: clean(item.unit, 20) || units[code],
      percent_daily_value: item.percent_daily_value == null
        ? null
        : number(item.percent_daily_value, 0, 10000),
      confidence: number(item.confidence ?? 1, 0, 1),
      declaration_type: declaration,
      printed_text: clean(item.printed_text, 240) || null,
      evidence_section: clean(item.evidence_section, 80) || "nutrition_facts",
    }];
  });
}
function normalizeLabelNutrients(fields: Row): NutrientInput[] {
  const sections = (fields.label_sections ?? {}) as Row;
  return applyNutritionFootnoteDeclarations(
    normalizeNutrients(fields.nutrients),
    String(sections.nutrition_footnote ?? ""),
  ) as NutrientInput[];
}
function extractionDiagnostics(contribution: Row) {
  const extracted = contribution.extracted_fields as Row | null;
  if (!extracted || !Object.keys(extracted).length) return null;
  const validation = contribution.validation_results as Row ?? validate(
    extracted,
    normalizeLabelNutrients(extracted),
    extracted,
  );
  const missing = Array.isArray(validation.missing_fields)
    ? validation.missing_fields.map(String)
    : [];
  const evidence = extracted.evidence as Row ?? {};
  const online = extracted.online_verification as Row ?? {};
  const trustedExactLookup = online.exact_gtin_match === true &&
    ["manufacturer", "usda", "retailer", "database"].includes(
      String(online.source_quality),
    );
  const requested = new Set<string>();
  if (
    (!trustedExactLookup && evidence.front_legible !== true) ||
    missing.some((field) => field === "Product name" || field === "Brand")
  ) {
    requested.add("front");
  }
  if (
    (!trustedExactLookup && evidence.nutrition_facts_legible !== true) ||
    validation.calorie_consistent === false ||
    missing.some((field) =>
      field === "Serving size" || field === "Serving description" ||
      requiredNutrients.includes(field)
    )
  ) requested.add("nutrition_facts");
  if (
    (!trustedExactLookup && evidence.ingredients_legible !== true) ||
    missing.includes("Ingredients")
  ) requested.add("ingredients");
  if (missing.includes("Clear package evidence")) {
    if (evidence.front_legible !== true) requested.add("front");
    if (evidence.nutrition_facts_legible !== true) {
      requested.add("nutrition_facts");
    }
    if (evidence.ingredients_legible !== true) requested.add("ingredients");
  }
  const needsPhotos = requested.size > 0 || missing.length > 0 ||
    validation.calorie_consistent === false;
  const requestedAssets = [...requested];
  const names: Record<string, string> = {
    front: "the package front",
    nutrition_facts: "the Nutrition Facts label",
    ingredients: "the ingredients list",
  };
  const targets = requestedAssets.map((item) => names[item]).filter(Boolean);
  return {
    status: needsPhotos ? "needs_photos" : "complete",
    missing_fields: missing,
    requested_assets: requestedAssets,
    message: needsPhotos
      ? `Leafy needs a clearer photo of ${joinReadable(targets)}.`
      : "Leafy read the package label successfully.",
  };
}
function joinReadable(values: string[]) {
  if (!values.length) return "the missing label information";
  if (values.length === 1) return values[0];
  if (values.length === 2) return `${values[0]} and ${values[1]}`;
  return `${values.slice(0, -1).join(", ")}, and ${values.at(-1)}`;
}
function extractionPrompt(barcode: string) {
  return `The scanned barcode is ${barcode}. Read every visible part of the photographed package as authoritative label evidence. Capture the official product and flavor, claims, barcode, servings per container, household serving size, metric equivalent, every printed nutrient amount and percent Daily Value, separately printed compounds such as caffeine, the complete ingredients and allergens, and faithful raw transcriptions of the front, Nutrition Facts, footnotes, ingredients, and other-label sections. A Nutrition Facts footnote saying a nutrient is "not a significant source" is an explicit declaration: include that nutrient with amount 0, declaration_type "not_significant_source", its printed text, and evidence_section "nutrition_footnote"; do not report it as missing and do not imply a laboratory zero. Use declaration_type "declared_zero" only for an amount printed as zero. For liquids preserve fl oz/mL serving sizes and leave serving_grams null unless a gram weight is actually printed; never invent a density conversion. The package label outranks online estimates. Do not invent any value.`;
}
function clean(value: unknown, max: number) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}
function number(value: unknown, min: number, max: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.min(Math.max(parsed, min), max) : min;
}
function nullableNumber(value: unknown, min: number, max: number) {
  const parsed = Number(value);
  return value == null || value === "" || !Number.isFinite(parsed)
    ? null
    : Math.min(Math.max(parsed, min), max);
}
function normalizeBarcode(value: string) {
  const digits = String(value).replace(/\D/g, "");
  return digits.length >= 8 && digits.length <= 14 ? digits : "";
}
function format(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}
function assertEditable(contribution: Row) {
  if (
    !["draft", "needs_review", "processing"].includes(
      String(contribution.status),
    )
  ) throw new Error("This submission can no longer be edited.");
}
async function owned(admin: any, userID: string, id: string) {
  const result = await admin.from("catalog_contributions").select("*").eq(
    "id",
    id,
  ).eq("user_id", userID).single();
  if (result.error || !result.data) throw new Error("Contribution not found.");
  return result.data;
}
async function activeProduct(admin: any, gtin: string, market: string) {
  const result = await admin.from("food_versions").select("id").eq("gtin", gtin)
    .eq("market_country", market).is("superseded_at", null).neq(
      "verification_status",
      "rejected",
    ).maybeSingle();
  if (result.error) throw result.error;
  return result.data;
}
async function touch(admin: any, id: string) {
  const result = await admin.from("catalog_contributions").update({
    updated_at: new Date().toISOString(),
  }).eq("id", id);
  if (result.error) throw result.error;
}
async function event(
  admin: any,
  id: string,
  actor: string,
  from: string | null,
  to: string,
  reason?: string,
  metadata: Row = {},
) {
  const result = await admin.from("catalog_contribution_events").insert({
    contribution_id: id,
    actor_type: actor,
    from_status: from,
    to_status: to,
    reason: reason ?? null,
    metadata,
  });
  if (result.error) throw result.error;
}
function extractOutputText(payload: Row) {
  for (
    const item of (Array.isArray(payload.output) ? payload.output : []) as Row[]
  ) {
    for (
      const part of (Array.isArray(item.content) ? item.content : []) as Row[]
    ) {
      if (
        part.type === "output_text" && typeof part.text === "string"
      ) return part.text;
    }
  }
  throw new Error("The label extractor returned no structured result.");
}
function toBase64(bytes: Uint8Array) {
  let binary = "";
  const chunk = 0x8000;
  for (let index = 0; index < bytes.length; index += chunk) {
    binary += String.fromCharCode(
      ...bytes.subarray(index, Math.min(index + chunk, bytes.length)),
    );
  }
  return btoa(binary);
}
async function safetyID(userID: string) {
  const salt = Deno.env.get("OPENAI_SAFETY_SALT") ??
    Deno.env.get("SUPABASE_URL") ?? "leafy";
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${salt}:${userID}`),
  );
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
