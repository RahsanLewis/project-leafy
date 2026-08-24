"use client";

/* eslint-disable @typescript-eslint/no-explicit-any, @next/next/no-img-element */
import { useCallback, useEffect, useMemo, useState } from "react";
import { createClient, type Session } from "@supabase/supabase-js";

type Tab = "queue" | "foods" | "ingredients";
type Row = Record<string, any>;
type RuntimeConfig = { supabaseUrl: string; supabaseAnonKey: string; adminApiUrl: string };
type QueueFilter = "active" | "pending_review" | "needs_review" | "processing" | "draft" | "accepted" | "rejected";

const queueFilters: { value: QueueFilter; label: string }[] = [
  { value: "active", label: "All active" }, { value: "pending_review", label: "Ready for review" },
  { value: "needs_review", label: "Needs photos" }, { value: "processing", label: "Processing" },
  { value: "draft", label: "Drafts" }, { value: "accepted", label: "Approved" }, { value: "rejected", label: "Rejected" },
];

export default function Home() {
  const [config, setConfig] = useState<RuntimeConfig | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [tab, setTab] = useState<Tab>("queue");
  const [summary, setSummary] = useState<Row>({});
  const [rows, setRows] = useState<Row[]>([]);
  const [selected, setSelected] = useState<Row | null>(null);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [reason, setReason] = useState("");
  const [queueFilter, setQueueFilter] = useState<QueueFilter>("active");
  const supabase = useMemo(() => config ? createClient(config.supabaseUrl, config.supabaseAnonKey, { auth: { detectSessionInUrl: true, persistSession: true } }) : null, [config]);

  useEffect(() => {
    fetch("/api/config")
      .then(async (response) => {
        const value = await response.json();
        if (!response.ok) throw new Error(value.error ?? "Dashboard configuration is unavailable.");
        setConfig(value);
      })
      .catch(() => setError("The dashboard is not configured yet."));
  }, []);

  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => data.subscription.unsubscribe();
  }, [supabase]);

  const api = useCallback(async (body: Row) => {
    if (!session || !config) throw new Error("Sign in required.");
    const response = await fetch(config.adminApiUrl, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}`, apikey: config.supabaseAnonKey }, body: JSON.stringify(body) });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(result.error ?? "The request could not be completed.");
    return result;
  }, [config, session]);

  const refresh = useCallback(async (search = "") => {
    setLoading(true); setError(""); setSelected(null);
    try {
      const [counts, result] = await Promise.all([
        api({ action: "summary" }),
        tab === "queue" ? api({ action: "list", statuses: queueFilter === "active" ? ["pending_review", "needs_review", "processing", "draft"] : [queueFilter], query: search }) : tab === "foods" ? api({ action: "search_foods", query: search }) : api({ action: "search_ingredients", query: search }),
      ]);
      setSummary(counts);
      setRows(result.contributions ?? result.foods ?? result.ingredients ?? []);
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Unable to load data."); }
    finally { setLoading(false); }
  }, [api, tab, queueFilter]);

  // Loading the selected operational view is the synchronization this effect owns.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { if (session) void refresh(); }, [session, tab, refresh]);

  async function open(row: Row) {
    setLoading(true); setError("");
    try {
      let result: Row;
      if (tab === "queue") result = await api({ action: "detail", contribution_id: row.id });
      else if (tab === "foods") {
        const foodVersionID = row.food_version_id ?? (await api({ action: "import_usda", fdc_id: row.fdc_id })).food_version_id;
        result = await api({ action: "food_detail", food_version_id: foodVersionID });
        await refresh(query);
      } else result = await api({ action: "ingredient_detail", canonical_id: row.canonical_id });
      setSelected(result.contribution ?? result.food ?? result.ingredient ?? null);
      if (result.food) setSelected({ ...result.food, nutrients: result.nutrients, portions: result.portions, pfqs: result.pfqs });
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Unable to load details."); }
    finally { setLoading(false); }
  }

  async function moderate(action: "approve" | "request_photos" | "reject" | "retry", payload: Row = {}) {
    if (!selected) return;
    setLoading(true); setError("");
    try {
      const result = await api({ action, contribution_id: selected.id, reason, ...payload });
      setReason("");
      if (result.contribution) setSelected(result.contribution);
      await refreshListOnly();
    }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Review failed."); setLoading(false); }
  }

  async function saveReview(confirmed_fields: Row, nutrients: Row[]) {
    if (!selected) return;
    setLoading(true); setError("");
    try {
      const result = await api({ action: "save", contribution_id: selected.id, expected_revision: selected.revision, confirmed_fields, nutrients });
      setSelected(result.contribution);
      await refreshListOnly();
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Edits could not be saved."); }
    finally { setLoading(false); }
  }

  async function refreshListOnly() {
    const result = tab === "queue" ? await api({ action: "list", statuses: queueFilter === "active" ? ["pending_review", "needs_review", "processing", "draft"] : [queueFilter], query }) : { contributions: rows };
    if (tab === "queue") setRows(result.contributions ?? []);
    setLoading(false);
  }

  if (!config) return <main className="login"><div className="login-mark">●</div><p className="eyebrow">Leafy internal</p><h1>Catalog operations</h1>{error ? <div className="error">{error}</div> : <p>Preparing the secure workspace…</p>}</main>;
  if (!session || !supabase) return <SignIn supabase={supabase} />;

  return (
    <main className="shell">
      <aside className="sidebar">
        <div className="brand"><span className="leaf">●</span><div><b>Leafy</b><small>Catalog Admin</small></div></div>
        <div className="environment">Production</div>
        <nav>
          <button className={tab === "queue" ? "active" : ""} onClick={() => setTab("queue")}>Product activity <span>{activeContributionCount(summary)}</span></button>
          <button className={tab === "foods" ? "active" : ""} onClick={() => setTab("foods")}>Food catalog <span>{summary.catalog ?? "—"}</span></button>
          <button className={tab === "ingredients" ? "active" : ""} onClick={() => setTab("ingredients")}>Ingredients <span>{summary.ingredients ?? "—"}</span></button>
        </nav>
        <button className="signout" onClick={() => supabase.auth.signOut()}>Sign out</button>
      </aside>
      <section className="workspace">
        <header><div><p className="eyebrow">Leafy operations</p><h1>{tab === "queue" ? "Product activity" : tab === "foods" ? "Food catalog" : "Ingredient catalog"}</h1><p>{tab === "queue" ? "Track every community submission from draft through approval." : tab === "foods" ? "Browse Leafy records or search USDA FoodData Central and import a verified source." : "Search every ingredient Leafy has observed, its aliases, product usage, classification, and reviewed concerns."}</p></div></header>
        {tab === "queue" && <div className="filters">{queueFilters.map((filter) => <button key={filter.value} className={queueFilter === filter.value ? "active" : ""} onClick={() => setQueueFilter(filter.value)}>{filter.label}<span>{filter.value === "active" ? activeContributionCount(summary) : summary.contributions?.[filter.value] ?? 0}</span></button>)}</div>}
        <form className="search" onSubmit={(event) => { event.preventDefault(); void refresh(query); }}><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={tab === "ingredients" ? "Ingredient name, alias, category, or family" : tab === "foods" ? "Search Leafy and USDA by name, brand, or barcode" : "Name, brand, or barcode"}/><button>Search</button></form>
        {error && <div className="error">{error}</div>}
        <div className="content">
          <div className="list">
            {loading && !rows.length ? <p className="muted">Loading…</p> : rows.length ? rows.map((row) => <ResultRow key={row.id ?? row.food_version_id ?? row.canonical_id} row={row} tab={tab} active={selected?.id === row.id || selected?.id === row.food_version_id || selected?.canonical_id === row.canonical_id} onClick={() => void open(row)}/>) : <Empty tab={tab}/>} 
          </div>
          <div className="detail">{selected ? <Detail tab={tab} data={selected} reason={reason} setReason={setReason} moderate={moderate} saveReview={saveReview} loading={loading}/> : <div className="empty-detail"><span>↗</span><h2>Select a record</h2><p>Its evidence, structured data, and history will appear here.</p></div>}</div>
        </div>
      </section>
    </main>
  );
}

function SignIn({ supabase }: { supabase: ReturnType<typeof createClient> }) {
  const [error, setError] = useState("");
  async function signIn() {
    const { error: authError } = await supabase.auth.signInWithOAuth({ provider: "google", options: { redirectTo: window.location.origin } });
    if (authError) setError(authError.message);
  }
  return <main className="login"><div className="login-mark">●</div><p className="eyebrow">Leafy internal</p><h1>Catalog operations</h1><p>Review community submissions and inspect the production food-quality data used by Leafy.</p><button onClick={() => void signIn()}><span className="google">G</span> Continue with Google</button>{error && <div className="error">{error}</div>}<small>Access is limited to approved Beyond Solid administrators.</small></main>;
}

function ResultRow({ row, tab, active, onClick }: { row: Row; tab: Tab; active: boolean; onClick: () => void }) {
  const title = tab === "queue" ? row.confirmed_fields?.product_name || `Barcode ${row.gtin}` : tab === "foods" ? row.description : row.canonical_name;
  const subtitle = tab === "queue" ? `${row.confirmed_fields?.brand_name || "Brand not shown"} · ${date(row.last_submitted_at || row.updated_at || row.created_at)}` : tab === "foods" ? `${row.brand_name || "No brand"} · ${row.gtin || row.market_country || "No barcode"}` : `${titleCase(row.review_status || "unclassified")} · ${row.product_count ?? 0} products`;
  return <button className={`result ${active ? "selected" : ""}`} onClick={onClick}><div><b>{title}</b><small>{subtitle}</small>{tab === "queue" && <em className={`status ${row.status}`}>{statusLabel(row.status)}</em>}{tab === "foods" && <em className={`status ${row.source_kind}`}>{row.source_kind === "usda" ? "USDA · import to inspect" : row.source || "Leafy catalog"}</em>}</div><span>›</span></button>;
}

function Detail({ tab, data, reason, setReason, moderate, saveReview, loading }: { tab: Tab; data: Row; reason: string; setReason: (value: string) => void; moderate: (action: any, payload?: Row) => void; saveReview: (fields: Row, nutrients: Row[]) => void; loading: boolean }) {
  if (tab === "queue") return <ReviewDetail key={`${data.id}:${data.revision}:${data.status}`} data={data} reason={reason} setReason={setReason} moderate={moderate} saveReview={saveReview} loading={loading}/>;
  if (tab === "foods") return <FoodDetail data={data}/>;
  return <IngredientDetail data={data}/>;
}

function ReviewDetail({ data, reason, setReason, moderate, saveReview, loading }: any) {
  const [fields, setFields] = useState<Row>(data.confirmed_fields ?? {});
  const [nutrients, setNutrients] = useState<Row[]>(() => editableNutrients(data.nutrients));
  const canModerate = ["pending_review", "needs_review"].includes(data.status);
  const canRetry = ["pending_review", "needs_review", "processing", "draft"].includes(data.status);
  const original = JSON.stringify({ fields: data.confirmed_fields ?? {}, nutrients: editableNutrients(data.nutrients) });
  const dirty = JSON.stringify({ fields, nutrients }) !== original;
  const updateField = (key: string, value: any) => setFields((current) => ({ ...current, [key]: value }));
  const updateNutrient = (code: string, key: string, value: any) => setNutrients((current) => current.map((item) => item.code === code ? { ...item, [key]: value } : item));
  return <article><div className="detail-heading"><div><p className="eyebrow">{statusLabel(data.status)}</p><h2>{fields.product_name || `Barcode ${data.gtin}`}</h2><p>{fields.brand_name || "Brand not shown"} · {data.gtin}</p></div></div>
    {!canModerate && <section><h3>Current state</h3><p className="bodycopy">{statusDescription(data.status, data.review_reason)}</p>{data.job && <dl><Field label="Processor" value={data.job.status}/><Field label="Attempts" value={data.job.attempt_count}/><Field label="Last issue" value={data.job.last_error}/></dl>}</section>}
    <section><h3>Package evidence</h3><div className="photos">{data.evidence?.map((image: Row) => <a href={image.signed_url} target="_blank" rel="noreferrer" key={image.id}><img src={image.signed_url} alt={image.asset_kind}/><small>{image.asset_kind.replaceAll("_", " ")}</small></a>)}</div></section>
    <section><div className="section-title"><h3>Product details</h3>{canModerate && <span className={dirty ? "unsaved" : "saved"}>{dirty ? "Unsaved changes" : `Revision ${data.revision}`}</span>}</div>
      {canModerate ? <div className="editor-grid"><label>Product name<input value={fields.product_name ?? ""} onChange={(event) => updateField("product_name", event.target.value)}/></label><label>Flavor<input value={fields.flavor ?? ""} onChange={(event) => updateField("flavor", event.target.value)}/></label><label>Brand<input disabled={fields.brand_not_shown} value={fields.brand_name ?? ""} onChange={(event) => updateField("brand_name", event.target.value)}/></label><label className="checkbox"><input type="checkbox" checked={fields.brand_not_shown === true} onChange={(event) => updateField("brand_not_shown", event.target.checked)}/>Brand is not shown</label><label>Serving amount<input inputMode="decimal" value={fields.serving_amount ?? ""} onChange={(event) => updateField("serving_amount", event.target.value)}/></label><label>Serving unit<input value={fields.serving_unit ?? ""} onChange={(event) => updateField("serving_unit", event.target.value)}/></label><label>Metric amount<input inputMode="decimal" value={fields.metric_serving_amount ?? ""} onChange={(event) => updateField("metric_serving_amount", event.target.value)}/></label><label>Metric unit<input value={fields.metric_serving_unit ?? ""} onChange={(event) => updateField("metric_serving_unit", event.target.value)}/></label><label>Serving description<input value={fields.serving_description ?? ""} onChange={(event) => updateField("serving_description", event.target.value)}/></label><label>Serving weight in grams (only if printed)<input inputMode="decimal" value={fields.serving_grams ?? ""} onChange={(event) => updateField("serving_grams", event.target.value)}/></label><label>Servings per container<input value={fields.servings_per_container ?? ""} onChange={(event) => updateField("servings_per_container", event.target.value)}/></label><label>Package claims (comma separated)<input value={(fields.claims ?? []).join(", ")} onChange={(event) => updateField("claims", event.target.value.split(",").map((value) => value.trim()).filter(Boolean))}/></label><label className="wide">Ingredients<textarea value={fields.ingredients ?? ""} onChange={(event) => updateField("ingredients", event.target.value)}/></label><label className="wide">Allergens (comma separated)<input value={(fields.allergens ?? []).join(", ")} onChange={(event) => updateField("allergens", event.target.value.split(",").map((value) => value.trim()).filter(Boolean))}/></label><label className="wide">Nutrition footnote<textarea value={fields.label_sections?.nutrition_footnote ?? ""} onChange={(event) => updateField("label_sections", { ...(fields.label_sections ?? {}), nutrition_footnote: event.target.value })}/></label></div> : <dl><Field label="Serving" value={servingLabel(fields)}/><Field label="Servings per container" value={fields.servings_per_container}/><Field label="Claims" value={(fields.claims || []).join(", ")}/><Field label="Ingredients" value={fields.ingredients || "—"}/><Field label="Allergens" value={(fields.allergens || []).join(", ") || "None declared"}/></dl>}
    </section>
    <section><h3>Nutrition per serving</h3><div className="nutrient-editor">{nutrients.map((item: Row) => <label key={item.code}><span>{nutrientLabel(item.code)} <small>{declarationLabel(item)}</small></span><div><input disabled={!canModerate} inputMode="decimal" value={item.amount_per_serving ?? ""} placeholder="—" onChange={(event) => updateNutrient(item.code, "amount_per_serving", event.target.value)}/><b>{item.unit}</b><input className="dv" disabled={!canModerate} inputMode="decimal" value={item.percent_daily_value ?? ""} placeholder="%DV" onChange={(event) => updateNutrient(item.code, "percent_daily_value", event.target.value)}/></div></label>)}</div></section>
    {Array.isArray(data.validation_results?.missing_fields) && data.validation_results.missing_fields.length > 0 && <section className="issues"><h3>Needs attention</h3><p>{data.validation_results.missing_fields.map(friendlyIssue).join(" · ")}</p><small>Only information absent or unreadable on the submitted label is listed here. Nutrients covered by a “not a significant source” statement are complete declarations.</small></section>}
    <section><h3>Verification</h3><p className="bodycopy">{data.verification_results?.summary || "Review the package images and any source matches before publishing."}</p>{data.verification_sources?.map((source: Row) => <a className="source" href={source.url} target="_blank" rel="noreferrer" key={source.id}>{source.title || source.domain || source.url} ↗</a>)}</section>
    {(canModerate || canRetry) && <section><h3>Review actions</h3><textarea value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Optional internal note or photo instructions"/><div className="actions">{canModerate && <button className="save" disabled={loading || !dirty} onClick={() => saveReview(fields, nutrients.filter((item) => item.amount_per_serving !== ""))}>Save edits</button>}{canModerate && <button className="approve" disabled={loading || dirty} title={dirty ? "Save edits before publishing" : ""} onClick={() => moderate("approve")}>Approve & publish</button>}{canRetry && <button disabled={loading || dirty} onClick={() => moderate("retry")}>Retry recognition</button>}{canModerate && <button disabled={loading} onClick={() => moderate("request_photos")}>Request photos</button>}{canModerate && <button className="reject" disabled={loading} onClick={() => moderate("reject")}>Reject</button>}</div>{dirty && <p className="hint">Save edits before approving or retrying recognition.</p>}</section>}
    <section><h3>Event history</h3>{data.events?.map((event: Row) => <div className="event" key={event.id}><span>{event.from_status || "created"} → {event.to_status}</span><small>{date(event.created_at)} · {event.actor_type}</small></div>)}</section>
  </article>;
}

const nutrientDefinitions = [
  ["energy_kcal", "Cal", true], ["fat_g", "g", true], ["saturated_fat_g", "g", true], ["trans_fat_g", "g", false], ["cholesterol_mg", "mg", false], ["sodium_mg", "mg", true], ["carbohydrate_g", "g", true], ["fiber_g", "g", true], ["sugars_g", "g", false], ["added_sugars_g", "g", true], ["protein_g", "g", true],
  ["vitamin_d_mcg", "mcg", false], ["calcium_mg", "mg", false], ["iron_mg", "mg", false], ["potassium_mg", "mg", false], ["vitamin_a_mcg_rae", "mcg RAE", false], ["vitamin_c_mg", "mg", false], ["vitamin_e_mg", "mg", false], ["vitamin_k_mcg", "mcg", false], ["thiamin_mg", "mg", false], ["riboflavin_mg", "mg", false], ["niacin_mg_ne", "mg NE", false], ["vitamin_b6_mg", "mg", false], ["folate_mcg_dfe", "mcg DFE", false], ["vitamin_b12_mcg", "mcg", false], ["biotin_mcg", "mcg", false], ["pantothenic_acid_mg", "mg", false], ["phosphorus_mg", "mg", false], ["iodine_mcg", "mcg", false], ["zinc_mg", "mg", false], ["selenium_mcg", "mcg", false], ["copper_mg", "mg", false], ["manganese_mg", "mg", false], ["chromium_mcg", "mcg", false], ["molybdenum_mcg", "mcg", false], ["chloride_mg", "mg", false], ["choline_mg", "mg", false], ["magnesium_mg", "mg", false], ["caffeine_mg", "mg", false],
] as const;
function editableNutrients(values: Row[] = []) { const map = new Map(values.map((item) => [item.nutrient_code ?? item.code, item])); const known = nutrientDefinitions.map(([code, unit, required]) => ({ code, unit, required, amount_per_serving: map.get(code)?.amount_per_serving ?? "", percent_daily_value: map.get(code)?.percent_daily_value ?? null, confidence: map.get(code)?.confidence ?? 1, declaration_type: map.get(code)?.declaration_type ?? "quantified", printed_text: map.get(code)?.printed_text ?? null, evidence_section: map.get(code)?.evidence_section ?? "nutrition_facts" })); return known; }
function nutrientLabel(code: string) { return code.replaceAll("_", " ").replace("energy kcal", "Calories").replace(/\b\w/g, (letter) => letter.toUpperCase()); }
function declarationLabel(item: Row) { if (item.declaration_type === "not_significant_source") return "label footnote"; if (item.declaration_type === "declared_zero") return "printed zero"; return item.required ? "core label value" : item.percent_daily_value != null ? `${item.percent_daily_value}% DV` : "label value"; }
function friendlyIssue(value: string) { const labels: Row = { energy_kcal: "Calories", fat_g: "Total fat", saturated_fat_g: "Saturated fat", sodium_mg: "Sodium", carbohydrate_g: "Total carbohydrate", fiber_g: "Dietary fiber", added_sugars_g: "Added sugars", protein_g: "Protein" }; return labels[value] ?? value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase()); }
function servingLabel(fields: Row) { const household = fields.serving_amount && fields.serving_unit ? `${fields.serving_amount} ${fields.serving_unit}` : fields.serving_description; const metric = fields.metric_serving_amount && fields.metric_serving_unit ? `${fields.metric_serving_amount} ${fields.metric_serving_unit}` : fields.serving_grams ? `${fields.serving_grams} g` : ""; return [household, metric && `(${metric})`].filter(Boolean).join(" ") || "—"; }

function FoodDetail({ data }: { data: Row }) { return <article><p className="eyebrow">Active catalog record</p><h2>{data.description}</h2><p>{data.brand_name || "No brand"} · {data.gtin || "No barcode"}</p><section><h3>Identity & provenance</h3><dl><Field label="Canonical name" value={data.foods?.canonical_name}/><Field label="Source" value={`${data.source_system} · ${data.source_data_type || "record"}`}/><Field label="Verification" value={data.verification_status}/><Field label="Market" value={data.market_country}/></dl></section><section><h3>Portions</h3>{data.portions?.map((portion: Row) => <div className="event" key={portion.id}><span>{portion.amount} {portion.unit} · {portion.description}</span><b>{portion.gram_weight} g</b></div>)}</section><section><h3>Nutrients per 100 g</h3><div className="nutrients">{data.nutrients?.map((item: Row) => <div key={item.nutrient_code}><span>{item.nutrient_definitions?.name || item.nutrient_code}</span><b>{Number(item.amount_per_100g).toFixed(2)} {item.nutrient_definitions?.unit}</b></div>)}</div></section><section><h3>Ingredients</h3><p className="bodycopy">{data.ingredients_text || "No ingredients recorded."}</p></section>{data.pfqs && <section><h3>PFQS</h3><div className="score"><strong>{data.pfqs.score_100 ?? "—"}</strong><span>{data.pfqs.rating || data.pfqs.score_status}<small>{data.pfqs.model_version}</small></span></div></section>}</article>; }

function IngredientDetail({ data }: { data: Row }) { const concern = data.concern; return <article><p className="eyebrow">Unified ingredient catalog</p><h2>{data.canonical_name}</h2><p>{data.category || data.family_id || "Uncategorized"} · {titleCase(data.review_status || "unclassified")}</p><section><h3>Classification</h3><dl><Field label="Aliases" value={data.aliases?.join(", ")}/><Field label="Whole-food class" value={data.quality_class}/><Field label="Quality coefficient" value={data.quality_coefficient}/><Field label="Beneficial food" value={data.beneficial ? "Yes" : "No"}/><Field label="Confidence" value={data.classification_confidence}/><Field label="Source" value={data.classification_source}/></dl></section><section><h3>Found in products</h3>{data.products?.length ? data.products.map((product: Row) => <div className="event" key={product.id}><span>{product.description}</span><small>{product.brand_name || "No brand"} · {product.gtin || "No barcode"}</small></div>) : <p className="bodycopy">No current product occurrences.</p>}</section><section><h3>Reviewed concern</h3>{concern ? <><p className="bodycopy">{concern.evidence?.summary}</p>{concern.jurisdiction_rules?.map((rule: Row, index: number) => <div className="rule" key={index}><strong>Tier {rule.tier} · −{rule.penalty}</strong><span>{rule.jurisdiction} · {rule.start_date} → {rule.end_date || "current"}</span><p>{rule.reason}</p></div>)}</> : <p className="bodycopy">No evidence-based PFQS concern is classified for this ingredient. Being unfamiliar or processed does not create a penalty.</p>}</section></article>; }

function Field({ label, value }: { label: string; value: any }) { return <div><dt>{label}</dt><dd>{value || "—"}</dd></div>; }
function Empty({ tab }: { tab: Tab }) { return <div className="empty-list"><b>{tab === "queue" ? "No submissions here" : "No results"}</b><p>{tab === "queue" ? "Choose another status to inspect the rest of product activity." : "Try a broader search."}</p></div>; }
function date(value: string) { return value ? new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Unknown date"; }
function titleCase(value: string) { return value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase()); }
function activeContributionCount(summary: Row) { const values = summary.contributions ?? {}; return ["pending_review", "needs_review", "processing", "draft"].reduce((total, status) => total + Number(values[status] ?? 0), 0) || "—"; }
function statusLabel(status: string) { return ({ pending_review: "Ready for review", needs_review: "Needs photos", processing: "Processing", draft: "Draft", accepted: "Approved", rejected: "Rejected" } as Row)[status] ?? status?.replaceAll("_", " ") ?? "Unknown"; }
function statusDescription(status: string, reason?: string) { if (reason) return reason; return ({ needs_review: "Leafy needs clearer package photos before this submission can be verified.", processing: "Leafy is reading the package and checking its product information.", draft: "The contributor started this submission but has not sent it for processing.", accepted: "This submission has been approved and published to the Leafy catalog.", rejected: "This submission was not published." } as Row)[status] ?? "This record is available for inspection."; }
