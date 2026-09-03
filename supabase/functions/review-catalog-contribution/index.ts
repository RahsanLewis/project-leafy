import { createClient } from "npm:@supabase/supabase-js@2";
import {
  catalogReviewKeyAuthorizes,
  configuredBootstrapAdminEmails,
  configuredCatalogReviewKey,
  emailMatchesBootstrapAllowlist,
} from "../_shared/catalog-admin.ts";
import { calculateAndPersistPFQS } from "../_shared/pfqs/persistence.ts";
import { normalizePFQSJurisdiction } from "../_shared/pfqs/scorer.ts";
import { additiveRegistry } from "../_shared/pfqs/additive-registry.ts";
import { PFQS_INGREDIENT_DATABASE_VERSION } from "../_shared/pfqs/types.ts";
import type { PFQSNutrientCode, PFQSNutrients } from "../_shared/pfqs/types.ts";
import { nutrientUnits as sharedNutrientUnits } from "../_shared/nutrients.ts";
import { retryRecognition } from "./retry-recognition.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

type Row = Record<string, any>;
type Reviewer = { kind: "admin"; user_id: string; email: string } | {
  kind: "key";
  user_id: null;
  email: "review-key";
};
type NutrientInput = {
  code: string;
  amount_per_serving: number;
  unit: string;
  percent_daily_value?: number | null;
  confidence?: number;
  declaration_type?: string;
  printed_text?: string | null;
  evidence_section?: string | null;
};
const reviewableStatuses = ["needs_review", "pending_review"];
const nutrientUnits: Record<string, string> = {
  energy_kcal: "kcal",
  ...sharedNutrientUnits,
};
const publicationNutrients = [
  "energy_kcal",
  "fat_g",
  "saturated_fat_g",
  "sodium_mg",
  "carbohydrate_g",
  "fiber_g",
  "added_sugars_g",
  "protein_g",
];
const allowedOrigins = new Set([
  "https://admin.projectleafy.app",
  "http://localhost:3000",
  "http://localhost:5173",
  ...(Deno.env.get("CATALOG_ADMIN_ORIGINS") ?? "").split(",").map((value) =>
    value.trim()
  ).filter(Boolean),
]);

Deno.serve(async (request) => {
  const origin = request.headers.get("origin") ?? "";
  const headers = corsHeaders(origin);
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  const respond = (value: unknown, status = 200) =>
    new Response(JSON.stringify(value), {
      status,
      headers: { ...headers, "Content-Type": "application/json" },
    });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SECRET_KEY")!;
    const admin = createClient(url, secret, {
      auth: { persistSession: false },
    });
    const reviewer = await authorize(request, admin);
    const body = await request.json().catch(() => ({})) as Row;
    const action = body.action ?? "list";

    if (action === "summary") {
      const statuses = [
        "draft",
        "processing",
        "pending_review",
        "needs_review",
        "accepted",
        "rejected",
      ];
      const [statusResults, catalog, ingredients] = await Promise.all([
        Promise.all(
          statuses.map((status) =>
            admin.from("catalog_contributions").select("id", {
              count: "exact",
              head: true,
            }).eq("status", status)
          ),
        ),
        admin.from("food_versions").select("id", { count: "exact", head: true })
          .is("superseded_at", null).neq("verification_status", "rejected"),
        admin.from("pfqs_ingredients").select("canonical_id", { count: "exact", head: true })
          .eq("ingredient_database_version", PFQS_INGREDIENT_DATABASE_VERSION),
      ]);
      for (const result of statusResults) if (result.error) throw result.error;
      if (catalog.error) throw catalog.error;
      if (ingredients.error) throw ingredients.error;
      const contributions = Object.fromEntries(
        statuses.map((
          status,
          index,
        ) => [status, statusResults[index].count ?? 0]),
      );
      return respond({
        pending: contributions.pending_review,
        contributions,
        catalog: catalog.count ?? 0,
        ingredients: ingredients.count ?? 0,
        additives: additiveRegistry.length,
      });
    }

    if (action === "list") {
      const statuses = Array.isArray(body.statuses)
        ? body.statuses.map(String)
        : [String(body.status ?? "pending_review")];
      const limit = Math.min(Math.max(Number(body.limit ?? 100), 1), 100);
      const offset = Math.max(Number(body.offset ?? 0), 0);
      let query = admin.from("catalog_contributions").select("*").in(
        "status",
        statuses,
      ).order("updated_at", { ascending: false }).range(
        offset,
        offset + limit - 1,
      );
      if (body.query) {
        query = query.or(
          `gtin.ilike.%${
            safeFilter(body.query)
          }%,confirmed_fields->>product_name.ilike.%${safeFilter(body.query)}%`,
        );
      }
      const result = await query;
      if (result.error) throw result.error;
      return respond({ contributions: result.data ?? [] });
    }

    if (action === "search_foods") {
      const term = String(body.query ?? "").trim();
      const limit = Math.min(Math.max(Number(body.limit ?? 30), 1), 50);
      let localRows: Row[] = [];
      if (term) {
        const result = await admin.rpc("search_food_catalog", {
          p_query: term,
          p_limit: limit,
        });
        if (result.error) throw result.error;
        localRows = result.data ?? [];
      } else {
        const result = await admin.from("food_versions").select(
          "id,description,brand_name,gtin,market_country,image_url,verification_status,source_system,source_record_id,source_updated_at,effective_from",
        )
          .is("superseded_at", null).neq("verification_status", "rejected")
          .order("source_updated_at", { ascending: false, nullsFirst: false })
          .order("effective_from", { ascending: false }).limit(limit);
        if (result.error) throw result.error;
        localRows = (result.data ?? []).map((row: Row) => ({
          ...row,
          food_version_id: row.id,
        }));
      }
      const local = localRows.map(localFoodSummary);
      const external = term.length >= 2 && local.length < limit
        ? await searchUSDA(term, Math.min(20, limit - local.length))
        : [];
      return respond({
        foods: deduplicateFoods([...local, ...external]),
        local_count: local.length,
        external_count: external.length,
      });
    }

    if (action === "import_usda") {
      const fdcID = Number(body.fdc_id);
      if (!Number.isInteger(fdcID) || fdcID <= 0) {
        return respond({ error: "A USDA food identifier is required." }, 400);
      }
      const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ??
        Deno.env.get("SUPABASE_PUBLISHABLE_KEY")!;
      const imported = await fetch(
        `${url}/functions/v1/discover-food-product`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: request.headers.get("authorization") ?? "",
            apikey: publicKey,
          },
          body: JSON.stringify({
            action: "detail",
            fdc_id: fdcID,
            record_history: false,
          }),
        },
      );
      const payload = await imported.json().catch(() => ({})) as Row;
      if (!imported.ok || !payload.product?.food_version_id) {
        throw new Error(payload.error ?? "USDA product import failed.");
      }
      return respond({ food_version_id: payload.product.food_version_id });
    }

    if (action === "food_detail") {
      const id = requireID(body.food_version_id, "food version");
      const version = await admin.from("food_versions").select("*,foods(*)").eq(
        "id",
        id,
      ).single();
      if (version.error) throw version.error;
      const [nutrients, portions, scores] = await Promise.all([
        admin.from("food_version_nutrients").select(
          "*,nutrient_definitions(name,unit,nutrient_class)",
        ).eq("food_version_id", id).order("nutrient_code"),
        admin.from("food_portions").select("*").eq("food_version_id", id).order(
          "amount",
        ),
        admin.from("pfqs_scores").select("*").eq("food_version_id", id).order(
          "created_at",
          { ascending: false },
        ).limit(1),
      ]);
      for (const result of [nutrients, portions, scores]) {
        if (result.error) throw result.error;
      }
      return respond({
        food: version.data,
        nutrients: nutrients.data ?? [],
        portions: portions.data ?? [],
        pfqs: scores.data?.[0] ?? null,
      });
    }

    if (action === "search_additives") {
      const term = String(body.query ?? "").trim().toLowerCase();
      const additives = additiveRegistry.filter((item) =>
        !term ||
        [
          item.canonical_name,
          item.canonical_id,
          item.family ?? "",
          ...item.aliases,
        ].some((value) => value.toLowerCase().includes(term))
      ).slice(0, 100);
      return respond({ additives });
    }

    if (action === "search_ingredients") {
      const term = String(body.query ?? "").trim();
      const limit = Math.min(Math.max(Number(body.limit ?? 100), 1), 100);
      let ingredientQuery = admin.from("pfqs_ingredients").select("*")
        .eq("ingredient_database_version", PFQS_INGREDIENT_DATABASE_VERSION)
        .order("canonical_name").limit(limit);
      if (term) {
        const pattern = `%${safeFilter(term)}%`;
        const aliasMatches = await admin.from("pfqs_ingredient_aliases").select("canonical_id")
          .eq("ingredient_database_version", PFQS_INGREDIENT_DATABASE_VERSION)
          .ilike("normalized_alias", pattern).limit(200);
        if (aliasMatches.error) throw aliasMatches.error;
        const directMatches = await admin.from("pfqs_ingredients").select("canonical_id")
          .eq("ingredient_database_version", PFQS_INGREDIENT_DATABASE_VERSION)
          .or(`canonical_name.ilike.${pattern},category.ilike.${pattern},family_id.ilike.${pattern}`)
          .limit(200);
        if (directMatches.error) throw directMatches.error;
        const ids = [...new Set([...(aliasMatches.data ?? []), ...(directMatches.data ?? [])].map((row: Row) => row.canonical_id))];
        if (!ids.length) return respond({ ingredients: [] });
        ingredientQuery = admin.from("pfqs_ingredients").select("*")
          .eq("ingredient_database_version", PFQS_INGREDIENT_DATABASE_VERSION)
          .in("canonical_id", ids).order("canonical_name").limit(limit);
      }
      const ingredientRows = await ingredientQuery;
      if (ingredientRows.error) throw ingredientRows.error;
      const ids = (ingredientRows.data ?? []).map((row: Row) => row.canonical_id);
      const counts = new Map<string, Set<string>>();
      if (ids.length) {
        const occurrences = await admin.from("pfqs_food_ingredient_occurrences")
          .select("canonical_id,food_version_id")
          .eq("ingredient_database_version", PFQS_INGREDIENT_DATABASE_VERSION).in("canonical_id", ids);
        if (occurrences.error) throw occurrences.error;
        for (const row of occurrences.data ?? []) {
          if (!counts.has(row.canonical_id)) counts.set(row.canonical_id, new Set());
          counts.get(row.canonical_id)!.add(row.food_version_id);
        }
      }
      return respond({ ingredients: (ingredientRows.data ?? []).map((row: Row) => ({
        ...row,
        product_count: counts.get(row.canonical_id)?.size ?? 0,
      })) });
    }

    if (action === "ingredient_detail") {
      const canonicalID = String(body.canonical_id ?? "");
      const ingredient = await admin.from("pfqs_ingredients").select("*")
        .eq("ingredient_database_version", PFQS_INGREDIENT_DATABASE_VERSION)
        .eq("canonical_id", canonicalID).single();
      if (ingredient.error) throw ingredient.error;
      const [aliases, occurrences] = await Promise.all([
        admin.from("pfqs_ingredient_aliases").select("alias").eq("ingredient_database_version", PFQS_INGREDIENT_DATABASE_VERSION).eq("canonical_id", canonicalID).order("alias"),
        admin.from("pfqs_food_ingredient_occurrences").select("food_version_id,raw_text,ingredient_path").eq("ingredient_database_version", PFQS_INGREDIENT_DATABASE_VERSION).eq("canonical_id", canonicalID).limit(100),
      ]);
      if (aliases.error) throw aliases.error;
      if (occurrences.error) throw occurrences.error;
      const foodIDs = [...new Set((occurrences.data ?? []).map((row: Row) => row.food_version_id))];
      let products: Row[] = [];
      if (foodIDs.length) {
        const foods = await admin.from("food_versions").select("id,description,brand_name,gtin")
          .in("id", foodIDs).is("superseded_at", null).limit(100);
        if (foods.error) throw foods.error;
        products = foods.data ?? [];
      }
      const concern = ingredient.data.risk_canonical_id
        ? additiveRegistry.find((item) => item.canonical_id === ingredient.data.risk_canonical_id) ?? null
        : null;
      return respond({ ingredient: {
        ...ingredient.data,
        aliases: (aliases.data ?? []).map((row: Row) => row.alias),
        products,
        concern,
      } });
    }

    if (action === "additive_detail") {
      const additive = additiveRegistry.find((item) =>
        item.canonical_id === body.canonical_id
      );
      if (!additive) return respond({ error: "Additive not found." }, 404);
      return respond({ additive });
    }

    const contributionID = requireID(body.contribution_id, "contribution");
    const contributionResult = await admin.from("catalog_contributions").select(
      "*",
    ).eq("id", contributionID).single();
    if (contributionResult.error) throw contributionResult.error;
    const contribution = contributionResult.data;
    if (action === "detail") {
      return respond({ contribution: await withEvidence(admin, contribution) });
    }
    if (action === "save") {
      if (!reviewableStatuses.includes(String(contribution.status))) {
        return respond({
          error: "Only submissions awaiting review can be edited.",
        }, 409);
      }
      const saved = await saveReview(admin, contribution, body, reviewer);
      return respond({ contribution: await withEvidence(admin, saved) });
    }
    if (action === "retry") {
      if (
        !["draft", "needs_review", "pending_review", "processing"].includes(
          String(contribution.status),
        )
      ) {
        return respond({
          error: "This submission can no longer be reprocessed.",
        }, 409);
      }
      const retried = await retryRecognition(
        admin,
        contribution,
        reviewer,
        url,
        {
          addEvent,
          waitUntil: (promise) => EdgeRuntime.waitUntil(promise),
        },
      );
      return respond({ contribution: await withEvidence(admin, retried) }, 202);
    }
    if (!reviewableStatuses.includes(String(contribution.status))) {
      return respond({ error: "This submission is not awaiting review." }, 409);
    }

    const reason = String(body.reason ?? "").trim();
    if (action === "request_changes" || action === "request_photos") {
      return respond({
        contribution: await transition(
          admin,
          contribution,
          "needs_review",
          reason ||
            "Please add clearer photos of the package front, Nutrition Facts, and ingredients.",
          reviewer,
        ),
      });
    }
    if (action === "reject") {
      return respond({
        contribution: await transition(
          admin,
          contribution,
          "rejected",
          reason || "This submission could not be verified.",
          reviewer,
        ),
      });
    }
    if (action === "approve") {
      const now = new Date().toISOString();
      const issues = publicationIssues(
        contribution.confirmed_fields as Row ?? {},
        await currentNutrients(admin, contribution),
      );
      if (issues.length) {
        return respond({
          error: `Complete these fields before publishing: ${
            issues.join(", ")
          }.`,
        }, 422);
      }
      const claim = await admin.from("catalog_contributions").update({
        status: "processing",
        updated_at: now,
      }).eq("id", contribution.id).eq("revision", contribution.revision).in(
        "status",
        reviewableStatuses,
      ).select("*").maybeSingle();
      if (claim.error) throw claim.error;
      if (!claim.data) {
        return respond(
          { error: "This submission is already being reviewed." },
          409,
        );
      }
      try {
        const existing = await admin.from("food_versions").select("id").eq(
          "gtin",
          contribution.gtin,
        ).eq("market_country", contribution.market_country).is(
          "superseded_at",
          null,
        ).neq("verification_status", "rejected").maybeSingle();
        if (existing.error) throw existing.error;
        const foodVersionID = existing.data?.id ??
          await publish(admin, contribution);
        const update = await admin.from("catalog_contributions").update({
          status: "accepted",
          accepted_food_version_id: foodVersionID,
          reviewed_at: now,
          review_reason: reason || "Approved by Leafy review.",
          updated_at: now,
        }).eq("id", contribution.id).eq("status", "processing").select("*")
          .maybeSingle();
        if (update.error) throw update.error;
        if (!update.data) {
          throw new Error(
            "This submission changed while it was being published.",
          );
        }
        await addEvent(
          admin,
          contribution.id,
          String(contribution.status),
          "accepted",
          reason || "Approved by Leafy review.",
          reviewer,
        );
        return respond({
          contribution: update.data,
          food_version_id: foodVersionID,
        });
      } catch (error) {
        await admin.from("catalog_contributions").update({
          status: contribution.status,
          updated_at: new Date().toISOString(),
        }).eq("id", contribution.id).eq("status", "processing");
        throw error;
      }
    }
    return respond({ error: "Unsupported admin action." }, 400);
  } catch (error) {
    console.error("catalog admin failed", error);
    const message = error instanceof Error
      ? error.message
      : "The catalog request could not be completed.";
    return respond({ error: message }, message === "Unauthorized" ? 401 : 400);
  }
});

function corsHeaders(origin: string) {
  return {
    ...(allowedOrigins.has(origin)
      ? { "Access-Control-Allow-Origin": origin }
      : {}),
    "Vary": "Origin",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-leafy-admin-key",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

async function authorize(request: Request, admin: any): Promise<Reviewer> {
  const reviewKey = configuredCatalogReviewKey(
    Deno.env.get("CATALOG_REVIEW_KEY"),
  );
  if (
    catalogReviewKeyAuthorizes(
      request.headers.get("x-leafy-admin-key"),
      reviewKey,
    )
  ) {
    return { kind: "key", user_id: null, email: "review-key" };
  }
  const token = request.headers.get("authorization")?.replace(
    /^Bearer\s+/i,
    "",
  );
  if (!token) throw new Error("Unauthorized");
  const userResult = await admin.auth.getUser(token);
  if (userResult.error || !userResult.data.user) {
    throw new Error("Unauthorized");
  }
  const user = userResult.data.user;
  const bootstrapAuthorized = emailMatchesBootstrapAllowlist(
    user.email,
    configuredBootstrapAdminEmails(
      Deno.env.get("CATALOG_BOOTSTRAP_ADMIN_EMAILS"),
    ),
  );
  const membership = await admin.from("admin_memberships").select("role,active")
    .eq("user_id", user.id).eq("role", "catalog_admin").eq("active", true)
    .maybeSingle();
  if ((membership.error || !membership.data) && !bootstrapAuthorized) {
    throw new Error("Unauthorized");
  }
  return { kind: "admin", user_id: user.id, email: user.email ?? "unknown" };
}

async function withEvidence(admin: any, contribution: Row) {
  const [assets, nutrients, revisions, events, sources, jobs] = await Promise
    .all([
      admin.from("product_label_assets").select("id,asset_kind,object_path").eq(
        "contribution_id",
        contribution.id,
      ),
      admin.from("catalog_contribution_nutrients").select("*").eq(
        "contribution_id",
        contribution.id,
      ).eq("revision", contribution.revision).order("nutrient_code"),
      admin.from("catalog_contribution_revisions").select("*").eq(
        "contribution_id",
        contribution.id,
      ).order("revision", { ascending: false }),
      admin.from("catalog_contribution_events").select("*").eq(
        "contribution_id",
        contribution.id,
      ).order("created_at", { ascending: false }),
      admin.from("catalog_verification_sources").select("*").eq(
        "contribution_id",
        contribution.id,
      ).eq("revision", contribution.revision).order("source_kind"),
      admin.from("catalog_contribution_jobs").select("*").eq(
        "contribution_id",
        contribution.id,
      ).maybeSingle(),
    ]);
  for (const result of [assets, nutrients, revisions, events, sources, jobs]) {
    if (result.error) throw result.error;
  }
  const evidence = await Promise.all(
    (assets.data ?? []).map(async (asset: Row) => {
      const signed = await admin.storage.from("nutrition-media")
        .createSignedUrl(String(asset.object_path), 900);
      if (signed.error) {
        throw signed.error;
      }
      return {
        id: asset.id,
        asset_kind: asset.asset_kind,
        signed_url: signed.data.signedUrl,
      };
    }),
  );
  return {
    ...contribution,
    evidence,
    nutrients: nutrients.data ?? [],
    revisions: revisions.data ?? [],
    events: events.data ?? [],
    verification_sources: sources.data ?? [],
    job: jobs.data ?? null,
  };
}

async function transition(
  admin: any,
  contribution: Row,
  status: string,
  reason: string,
  reviewer: Reviewer,
) {
  const now = new Date().toISOString();
  const update = await admin.from("catalog_contributions").update({
    status,
    review_reason: reason,
    reviewed_at: now,
    updated_at: now,
  }).eq("id", contribution.id).eq("revision", contribution.revision).in(
    "status",
    reviewableStatuses,
  ).select("*").maybeSingle();
  if (update.error) throw update.error;
  if (!update.data) {
    throw new Error("This submission was reviewed in another session.");
  }
  await addEvent(
    admin,
    contribution.id,
    contribution.status,
    status,
    reason,
    reviewer,
  );
  return update.data;
}

async function currentNutrients(admin: any, contribution: Row) {
  const result = await admin.from("catalog_contribution_nutrients").select("*")
    .eq("contribution_id", contribution.id).eq(
      "revision",
      contribution.revision,
    );
  if (result.error) throw result.error;
  return result.data ?? [];
}

async function saveReview(
  admin: any,
  contribution: Row,
  body: Row,
  reviewer: Reviewer,
) {
  const expected = Number(body.expected_revision);
  if (
    !Number.isInteger(expected) || expected !== Number(contribution.revision)
  ) {
    throw new Error(
      "This submission changed in another session. Reload it before saving.",
    );
  }
  const fields = normalizeReviewFields(body.confirmed_fields as Row ?? {});
  const nutrients = normalizeReviewNutrients(body.nutrients);
  const issues = publicationIssues(fields, nutrients);
  const nextRevision = expected + 1;
  const validation = {
    ...(contribution.validation_results as Row ?? {}),
    manual_review: true,
    missing_fields: issues,
    auto_approve: false,
    reason: issues.length
      ? `Still missing: ${issues.join(", ")}`
      : "Ready for human approval.",
  };
  const revision = await admin.from("catalog_contribution_revisions").insert({
    contribution_id: contribution.id,
    revision: nextRevision,
    extracted_fields: contribution.extracted_fields ?? {},
    confirmed_fields: fields,
    validation_results: validation,
  });
  if (revision.error) throw revision.error;
  if (nutrients.length) {
    const write = await admin.from("catalog_contribution_nutrients").insert(
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
    if (write.error) throw write.error;
  }
  const sources = await admin.from("catalog_verification_sources").select("*")
    .eq("contribution_id", contribution.id).eq("revision", expected);
  if (sources.error) throw sources.error;
  if (sources.data?.length) {
    const copies = sources.data.map((
      { id: _id, created_at: _created, ...source }: Row,
    ) => ({ ...source, revision: nextRevision }));
    const copy = await admin.from("catalog_verification_sources").insert(
      copies,
    );
    if (copy.error) throw copy.error;
  }
  const now = new Date().toISOString();
  const update = await admin.from("catalog_contributions").update({
    revision: nextRevision,
    confirmed_fields: fields,
    validation_results: validation,
    updated_at: now,
  }).eq("id", contribution.id).eq("revision", expected).in(
    "status",
    reviewableStatuses,
  ).select("*").maybeSingle();
  if (update.error) throw update.error;
  if (!update.data) {
    throw new Error(
      "This submission changed in another session. Reload it before saving.",
    );
  }
  await addEvent(
    admin,
    contribution.id,
    String(contribution.status),
    String(contribution.status),
    "Review edits saved.",
    reviewer,
    {
      from_revision: expected,
      to_revision: nextRevision,
      remaining_issues: issues,
    },
  );
  return update.data;
}

function normalizeReviewFields(raw: Row) {
  return {
    product_name: String(raw.product_name ?? "").trim().slice(0, 180),
    brand_name: String(raw.brand_name ?? "").trim().slice(0, 120),
    brand_not_shown: raw.brand_not_shown === true,
    flavor: String(raw.flavor ?? "").trim().slice(0, 120),
    claims: Array.isArray(raw.claims)
      ? raw.claims.map(String).filter(Boolean).slice(0, 40)
      : [],
    serving_description: String(raw.serving_description ?? "").trim().slice(
      0,
      120,
    ),
    serving_amount: finiteNullable(raw.serving_amount),
    serving_unit: String(raw.serving_unit ?? "").trim().slice(0, 30),
    metric_serving_amount: finiteNullable(raw.metric_serving_amount),
    metric_serving_unit: String(raw.metric_serving_unit ?? "").trim().slice(
      0,
      30,
    ),
    serving_grams: finiteNullable(raw.serving_grams),
    servings_per_container: String(raw.servings_per_container ?? "").trim()
      .slice(0, 80),
    ingredients: String(raw.ingredients ?? "").trim().slice(0, 5000),
    allergens: Array.isArray(raw.allergens)
      ? raw.allergens.map(String).map((value) => value.trim()).filter(Boolean)
        .slice(0, 30)
      : [],
    label_sections: raw.label_sections && typeof raw.label_sections === "object"
      ? raw.label_sections
      : {},
  };
}

function normalizeReviewNutrients(value: unknown): NutrientInput[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  return value.flatMap((raw) => {
    const item = raw as Row;
    const code = String(item.code ?? item.nutrient_code ?? "");
    const amount = Number(item.amount_per_serving);
    if (
      !nutrientUnits[code] || seen.has(code) || !Number.isFinite(amount) ||
      amount < 0
    ) return [];
    seen.add(code);
    return [{
      code,
      amount_per_serving: amount,
      unit: String(item.unit ?? nutrientUnits[code]),
      percent_daily_value: item.percent_daily_value == null
        ? null
        : finiteNumber(item.percent_daily_value),
      confidence: Math.min(1, Math.max(0, Number(item.confidence ?? 1))),
      declaration_type:
        ["quantified", "declared_zero", "not_significant_source", "derived"]
            .includes(String(item.declaration_type))
          ? item.declaration_type
          : amount === 0
          ? "declared_zero"
          : "quantified",
      printed_text: String(item.printed_text ?? "").trim() || null,
      evidence_section: String(item.evidence_section ?? "").trim() ||
        "nutrition_facts",
    }];
  });
}

function publicationIssues(fields: Row, nutrients: Row[]) {
  const issues: string[] = [];
  if (!String(fields.product_name ?? "").trim()) issues.push("product name");
  if (!fields.brand_not_shown && !String(fields.brand_name ?? "").trim()) {
    issues.push("brand");
  }
  if (
    !(Number(fields.serving_amount) > 0) ||
    !String(fields.serving_unit ?? "").trim()
  ) issues.push("serving size");
  if (!String(fields.serving_description ?? "").trim()) {
    issues.push("serving description");
  }
  if (!String(fields.ingredients ?? "").trim()) issues.push("ingredients");
  const codes = new Set(
    nutrients.map((item) => String(item.code ?? item.nutrient_code)),
  );
  for (const code of publicationNutrients) {
    if (!codes.has(code)) issues.push(code.replaceAll("_", " "));
  }
  return issues;
}

function finiteNumber(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : 0;
}
function finiteNullable(value: unknown) {
  const number = Number(value);
  return value == null || value === "" || !Number.isFinite(number) || number < 0
    ? null
    : number;
}

async function publish(admin: any, contribution: Row) {
  const fields = contribution.confirmed_fields as Row;
  const nutrientsResult = await admin.from("catalog_contribution_nutrients")
    .select("*").eq("contribution_id", contribution.id).eq(
      "revision",
      contribution.revision,
    );
  if (nutrientsResult.error) throw nutrientsResult.error;
  const targetID = contribution.target_food_version_id
    ? String(contribution.target_food_version_id)
    : null;
  let foodID: string;
  if (targetID) {
    const target = await admin.from("food_versions").select("food_id").eq("id", targetID).is("superseded_at", null).single();
    if (target.error) throw target.error;
    foodID = String(target.data.food_id);
  } else {
    const foods = await admin.from("foods").insert({
      canonical_name: fields.product_name,
    }).select("id").single();
    if (foods.error) throw foods.error;
    foodID = String(foods.data.id);
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
    verification_status: targetID ? "rejected" : "community_confirmed",
    raw_source: {
      contribution_id: contribution.id,
      revision: contribution.revision,
      reviewed: true,
      label_sections: fields.label_sections ?? {},
    },
  }).select("id").single();
  if (version.error) throw version.error;
  const servingRows = (nutrientsResult.data ?? []).map((item: Row) => ({
    food_version_id: version.data.id,
    nutrient_code: item.nutrient_code,
    amount_per_serving: item.amount_per_serving,
    unit: item.unit,
    percent_daily_value: item.percent_daily_value,
    declaration_type: item.declaration_type ?? "quantified",
    printed_text: item.printed_text,
    evidence_section: item.evidence_section ?? "nutrition_facts",
  }));
  if (servingRows.length) {
    const result = await admin.from("food_version_serving_nutrients").insert(
      servingRows,
    );
    if (result.error) throw result.error;
  }
  if (Number(fields.serving_grams) > 0) {
    const per100 = (nutrientsResult.data ?? []).map((item: Row) => ({
      food_version_id: version.data.id,
      nutrient_code: item.nutrient_code,
      amount_per_100g: Number(
        (Number(item.amount_per_serving) * 100 / Number(fields.serving_grams))
          .toFixed(6),
      ),
      derivation_method: "label",
    }));
    if (per100.length) {
      const result = await admin.from("food_version_nutrients").insert(per100);
      if (result.error) throw result.error;
    }
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
  const pfqsNutrients = (nutrientsResult.data ?? []).filter((item: Row) =>
    isPFQSNutrient(String(item.nutrient_code))
  );
  const labelWrite = await admin.from("pfqs_label_nutrients").upsert(
    pfqsNutrients.map((item: Row) => ({
      food_version_id: version.data.id,
      nutrient_code: item.nutrient_code,
      amount_per_serving: item.amount_per_serving,
      unit: item.unit,
      explicitly_reported: item.printed_on_label === true,
      source_method: "human_review",
      source_version:
        `leafy-contribution:${contribution.id}:${contribution.revision}`,
      confidence: item.confidence ?? 1,
    })),
    { onConflict: "food_version_id,nutrient_code" },
  );
  if (labelWrite.error) throw labelWrite.error;
  await calculateAndPersistPFQS(admin, version.data.id, {
    product_name: String(fields.product_name),
    jurisdiction: normalizePFQSJurisdiction(String(contribution.market_country ?? "US")),
    assessment_date: new Date().toISOString().slice(0, 10),
    serving_size: {
      amount: Number(fields.serving_amount),
      unit: String(fields.serving_unit),
      description: String(fields.serving_description ?? ""),
    },
    nutrition: Object.fromEntries(
      pfqsNutrients.map((
        item: Row,
      ) => [String(item.nutrient_code), Number(item.amount_per_serving)]),
    ) as PFQSNutrients,
    explicitly_reported_nutrients: pfqsNutrients.filter((item: Row) =>
      item.printed_on_label === true
    ).map((item: Row) => String(item.nutrient_code) as PFQSNutrientCode),
    nutrient_evidence: Object.fromEntries(pfqsNutrients.map((item: Row) => [String(item.nutrient_code), {
      source: item.printed_on_label === true ? "label" : "derived",
      confidence: Number(item.confidence ?? 1),
    }])),
    ingredients_raw: String(fields.ingredients ?? ""),
    verification_status: "community_confirmed",
    product_type: "food",
  });
  if (targetID) {
    const activated = await admin.rpc("activate_food_version_replacement", {
      p_previous_id: targetID,
      p_replacement_id: version.data.id,
      p_verification_status: "community_confirmed",
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
async function addEvent(
  admin: any,
  id: string,
  from: string,
  to: string,
  reason: string,
  reviewer: Reviewer,
  metadata: Row = {},
) {
  const result = await admin.from("catalog_contribution_events").insert({
    contribution_id: id,
    actor_type: "admin",
    from_status: from,
    to_status: to,
    reason,
    metadata: {
      reviewer_id: reviewer.user_id,
      reviewer_email: reviewer.email,
      auth_kind: reviewer.kind,
      ...metadata,
    },
  });
  if (result.error) throw result.error;
}
function requireID(value: unknown, name: string) {
  const id = String(value ?? "");
  if (!id) throw new Error(`A ${name} identifier is required.`);
  return id;
}
function safeFilter(value: unknown) {
  return String(value).replace(/[,%()]/g, " ").trim();
}

function localFoodSummary(row: Row) {
  return {
    id: String(row.food_version_id ?? row.id),
    food_version_id: String(row.food_version_id ?? row.id),
    fdc_id: null,
    description: row.description,
    brand_name: row.brand_name,
    gtin: row.gtin,
    market_country: row.market_country,
    image_url: row.image_url,
    verification_status: row.verification_status,
    source: row.source_system === "usda_fdc"
      ? "USDA FoodData Central"
      : "Leafy catalog",
    source_kind: "leafy",
    imported: true,
  };
}

async function searchUSDA(query: string, limit: number) {
  if (limit <= 0) return [];
  const key = Deno.env.get("FDC_API_KEY") ?? "DEMO_KEY";
  const response = await fetch(
    `https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${
      encodeURIComponent(key)
    }`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query, dataType: ["Branded"], pageSize: limit }),
    },
  );
  if (!response.ok) {
    throw new Error("The USDA food catalog is temporarily unavailable.");
  }
  const payload = await response.json() as Row;
  return (payload.foods ?? []).map((food: Row) => ({
    id: `usda:${food.fdcId}`,
    food_version_id: null,
    fdc_id: Number(food.fdcId),
    description: food.description,
    brand_name: food.brandOwner ?? food.brandName ?? null,
    gtin: food.gtinUpc ?? null,
    market_country: food.marketCountry ?? "US",
    image_url: null,
    verification_status: "external",
    source: "USDA FoodData Central",
    source_kind: "usda",
    imported: false,
  }));
}

function deduplicateFoods(rows: Row[]) {
  const seen = new Set<string>();
  return rows.filter((row) => {
    const key = String(row.gtin || `${row.source_kind}:${row.id}`).replace(
      /^0+/,
      "",
    );
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
