type Row = Record<string, any>;

export async function fulfillCatalogLogRequest(admin: any, contribution: Row) {
  const requestResult = await admin.from("catalog_contribution_log_requests")
    .select("*").eq("contribution_id", contribution.id).maybeSingle();
  if (requestResult.error) throw requestResult.error;
  const request = requestResult.data as Row | null;
  if (!request || ["completed", "cancelled"].includes(String(request.status))) return null;

  const existing = await admin.from("food_entries").select("*")
    .eq("provenance->>catalog_log_request_id", request.id).maybeSingle();
  if (existing.error) throw existing.error;

  const fields = contribution.confirmed_fields as Row | null;
  if (!fields) return needsAction(admin, request, "Leafy still needs readable package details.");
  const nutrients = await admin.from("catalog_contribution_nutrients").select("*")
    .eq("contribution_id", contribution.id).eq("revision", contribution.revision);
  if (nutrients.error) throw nutrients.error;
  const energy = nutrients.data?.find((item: Row) => item.nutrient_code === "energy_kcal");
  if (!energy) return needsAction(admin, request, "Leafy still needs readable calorie information.");

  const servingGrams = Number(fields.serving_grams);
  const servingCount = Number(request.serving_count);
  const hasGrams = Number.isFinite(servingGrams) && servingGrams > 0;
  const grams = hasGrams ? servingGrams * servingCount : null;
  const now = new Date().toISOString();
  const claimed = await admin.from("catalog_contribution_log_requests").update({
    status: "processing", last_error: null, updated_at: now,
  }).eq("id", request.id).in("status", ["pending", "failed", "needs_action", "processing"]);
  if (claimed.error) throw claimed.error;

  const inserted = existing.data ? { data: existing.data, error: null } : await admin.from("food_entries").insert({
    user_id: request.user_id,
    name: fields.product_name,
    calories: Math.max(1, Math.round(Number(energy.amount_per_serving) * servingCount)),
    consumed_at: request.consumed_at,
    local_date: request.local_date,
    time_zone: request.time_zone,
    gram_weight: grams,
    amount: grams ?? servingCount,
    amount_unit: grams == null ? "serving" : "g",
    portion_description: grams == null
      ? `${format(servingCount)} serving${servingCount === 1 ? "" : "s"}`
      : `${format(grams)} g`,
    meal_type: request.meal_type,
    entry_source: "barcode",
    calorie_method: "nutrition_label",
    confidence: 0.85,
    user_confirmed: true,
    provenance: {
      source: "leafy_contribution",
      contribution_id: contribution.id,
      catalog_log_request_id: request.id,
      revision: contribution.revision,
    },
  }).select("*").single();
  let entry = inserted.data;
  if (inserted.error) {
    if (inserted.error.code !== "23505") throw inserted.error;
    const replay = await admin.from("food_entries").select("*")
      .eq("provenance->>catalog_log_request_id", request.id).single();
    if (replay.error) throw replay.error;
    entry = replay.data;
  }

  const item = await admin.from("consumption_items").select("id")
    .eq("legacy_food_entry_id", entry.id).single();
  if (item.error) throw item.error;
  const snapshots = (nutrients.data ?? []).map((nutrient: Row) => ({
    consumption_item_id: item.data.id,
    nutrient_code: nutrient.nutrient_code,
    amount: Number((Number(nutrient.amount_per_serving) * servingCount).toFixed(6)),
    derivation_method: "label",
    source_version: `leafy-contribution:${contribution.id}:${contribution.revision}`,
    confidence: 0.85,
  }));
  if (snapshots.length) {
    const saved = await admin.from("consumption_item_nutrients").upsert(snapshots, {
      onConflict: "consumption_item_id,nutrient_code",
    });
    if (saved.error) throw saved.error;
  }
  await complete(admin, request, entry.id);
  await admin.from("catalog_contribution_jobs").update({
    requested_log: {
      serving_count: request.serving_count, consumed_at: request.consumed_at,
      local_date: request.local_date, time_zone: request.time_zone,
      meal_type: request.meal_type, logged_entry_id: entry.id,
    },
    updated_at: new Date().toISOString(),
  }).eq("contribution_id", contribution.id);
  return entry;
}

export async function markCatalogLogRequest(
  admin: any, contributionID: string, status: "pending" | "needs_action" | "failed", message: string | null,
) {
  const result = await admin.from("catalog_contribution_log_requests").update({
    status, last_error: message, updated_at: new Date().toISOString(),
  }).eq("contribution_id", contributionID).not("status", "in", '(completed,cancelled)');
  if (result.error) throw result.error;
}

async function complete(admin: any, request: Row, entryID: string) {
  const result = await admin.from("catalog_contribution_log_requests").update({
    status: "completed", food_entry_id: entryID, last_error: null,
    completed_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  }).eq("id", request.id).neq("status", "cancelled");
  if (result.error) throw result.error;
}

async function needsAction(admin: any, request: Row, message: string) {
  const result = await admin.from("catalog_contribution_log_requests").update({
    status: "needs_action", last_error: message, updated_at: new Date().toISOString(),
  }).eq("id", request.id).neq("status", "cancelled");
  if (result.error) throw result.error;
  return null;
}

function format(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}
