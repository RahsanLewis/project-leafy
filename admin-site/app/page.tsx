"use client";

/* eslint-disable @typescript-eslint/no-explicit-any, @next/next/no-img-element */
import { useCallback, useEffect, useMemo, useState } from "react";
import { createClient, type Session } from "@supabase/supabase-js";

type Tab = "queue" | "foods" | "additives";
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
        tab === "queue" ? api({ action: "list", statuses: queueFilter === "active" ? ["pending_review", "needs_review", "processing", "draft"] : [queueFilter], query: search }) : tab === "foods" ? api({ action: "search_foods", query: search }) : api({ action: "search_additives", query: search }),
      ]);
      setSummary(counts);
      setRows(result.contributions ?? result.foods ?? result.additives ?? []);
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
      } else result = await api({ action: "additive_detail", canonical_id: row.canonical_id });
      setSelected(result.contribution ?? result.food ?? result.additive ?? null);
      if (result.food) setSelected({ ...result.food, nutrients: result.nutrients, portions: result.portions, pfqs: result.pfqs });
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Unable to load details."); }
    finally { setLoading(false); }
  }

  async function moderate(action: "approve" | "request_changes" | "reject") {
    if (!selected) return;
    setLoading(true); setError("");
    try { await api({ action, contribution_id: selected.id, reason }); setReason(""); await refresh(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Review failed."); setLoading(false); }
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
          <button className={tab === "additives" ? "active" : ""} onClick={() => setTab("additives")}>Additives <span>{summary.additives ?? "—"}</span></button>
        </nav>
        <button className="signout" onClick={() => supabase.auth.signOut()}>Sign out</button>
      </aside>
      <section className="workspace">
        <header><div><p className="eyebrow">Leafy operations</p><h1>{tab === "queue" ? "Product activity" : tab === "foods" ? "Food catalog" : "PFQS additive registry"}</h1><p>{tab === "queue" ? "Track every community submission from draft through approval." : tab === "foods" ? "Browse Leafy records or search USDA FoodData Central and import a verified source." : "Search the exact versioned registry used by the PFQS scorer."}</p></div></header>
        {tab === "queue" && <div className="filters">{queueFilters.map((filter) => <button key={filter.value} className={queueFilter === filter.value ? "active" : ""} onClick={() => setQueueFilter(filter.value)}>{filter.label}<span>{filter.value === "active" ? activeContributionCount(summary) : summary.contributions?.[filter.value] ?? 0}</span></button>)}</div>}
        <form className="search" onSubmit={(event) => { event.preventDefault(); void refresh(query); }}><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={tab === "additives" ? "Name, alias, E-number, family, or tier" : tab === "foods" ? "Search Leafy and USDA by name, brand, or barcode" : "Name, brand, or barcode"}/><button>Search</button></form>
        {error && <div className="error">{error}</div>}
        <div className="content">
          <div className="list">
            {loading && !rows.length ? <p className="muted">Loading…</p> : rows.length ? rows.map((row) => <ResultRow key={row.id ?? row.food_version_id ?? row.canonical_id} row={row} tab={tab} active={selected?.id === row.id || selected?.id === row.food_version_id || selected?.canonical_id === row.canonical_id} onClick={() => void open(row)}/>) : <Empty tab={tab}/>} 
          </div>
          <div className="detail">{selected ? <Detail tab={tab} data={selected} reason={reason} setReason={setReason} moderate={moderate} loading={loading}/> : <div className="empty-detail"><span>↗</span><h2>Select a record</h2><p>Its evidence, structured data, and history will appear here.</p></div>}</div>
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
  const subtitle = tab === "queue" ? `${row.confirmed_fields?.brand_name || "Brand not shown"} · ${date(row.last_submitted_at || row.updated_at || row.created_at)}` : tab === "foods" ? `${row.brand_name || "No brand"} · ${row.gtin || row.market_country || "No barcode"}` : `${row.family || "Uncategorized"} · ${maxTier(row)} tier`;
  return <button className={`result ${active ? "selected" : ""}`} onClick={onClick}><div><b>{title}</b><small>{subtitle}</small>{tab === "queue" && <em className={`status ${row.status}`}>{statusLabel(row.status)}</em>}{tab === "foods" && <em className={`status ${row.source_kind}`}>{row.source_kind === "usda" ? "USDA · import to inspect" : row.source || "Leafy catalog"}</em>}</div><span>›</span></button>;
}

function Detail({ tab, data, reason, setReason, moderate, loading }: { tab: Tab; data: Row; reason: string; setReason: (value: string) => void; moderate: (action: any) => void; loading: boolean }) {
  if (tab === "queue") return <ReviewDetail data={data} reason={reason} setReason={setReason} moderate={moderate} loading={loading}/>;
  if (tab === "foods") return <FoodDetail data={data}/>;
  return <AdditiveDetail data={data}/>;
}

function ReviewDetail({ data, reason, setReason, moderate, loading }: any) {
  const fields = data.confirmed_fields ?? {};
  const canModerate = data.status === "pending_review";
  return <article><div className="detail-heading"><div><p className="eyebrow">{statusLabel(data.status)}</p><h2>{fields.product_name || `Barcode ${data.gtin}`}</h2><p>{fields.brand_name || "Brand not shown"} · {data.gtin}</p></div></div>
    {!canModerate && <section><h3>Current state</h3><p className="bodycopy">{statusDescription(data.status, data.review_reason)}</p>{data.job && <dl><Field label="Processor" value={data.job.status}/><Field label="Attempts" value={data.job.attempt_count}/><Field label="Last issue" value={data.job.last_error}/></dl>}</section>}
    <section><h3>Package evidence</h3><div className="photos">{data.evidence?.map((image: Row) => <a href={image.signed_url} target="_blank" rel="noreferrer" key={image.id}><img src={image.signed_url} alt={image.asset_kind}/><small>{image.asset_kind.replaceAll("_", " ")}</small></a>)}</div></section>
    <section><h3>Extracted label</h3><dl><Field label="Serving" value={`${fields.serving_description || "—"} (${fields.serving_grams || "—"} g)`}/><Field label="Ingredients" value={fields.ingredients || "—"}/><Field label="Allergens" value={(fields.allergens || []).join(", ") || "None declared"}/></dl></section>
    <section><h3>Nutrition per serving</h3><div className="nutrients">{data.nutrients?.map((item: Row) => <div key={item.nutrient_code}><span>{item.nutrient_code.replaceAll("_", " ")}</span><b>{item.amount_per_serving} {item.unit}</b></div>)}</div></section>
    <section><h3>Verification</h3><p className="bodycopy">{data.verification_results?.summary || "Review the package images and any source matches before publishing."}</p>{data.verification_sources?.map((source: Row) => <a className="source" href={source.url} target="_blank" rel="noreferrer" key={source.id}>{source.title || source.domain || source.url} ↗</a>)}</section>
    {canModerate && <section><h3>Decision note</h3><textarea value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Optional internal reason or clear instructions for the contributor"/><div className="actions"><button className="approve" disabled={loading} onClick={() => moderate("approve")}>Approve & publish</button><button disabled={loading} onClick={() => moderate("request_changes")}>Request changes</button><button className="reject" disabled={loading} onClick={() => moderate("reject")}>Reject</button></div></section>}
    <section><h3>Event history</h3>{data.events?.map((event: Row) => <div className="event" key={event.id}><span>{event.from_status || "created"} → {event.to_status}</span><small>{date(event.created_at)} · {event.actor_type}</small></div>)}</section>
  </article>;
}

function FoodDetail({ data }: { data: Row }) { return <article><p className="eyebrow">Active catalog record</p><h2>{data.description}</h2><p>{data.brand_name || "No brand"} · {data.gtin || "No barcode"}</p><section><h3>Identity & provenance</h3><dl><Field label="Canonical name" value={data.foods?.canonical_name}/><Field label="Source" value={`${data.source_system} · ${data.source_data_type || "record"}`}/><Field label="Verification" value={data.verification_status}/><Field label="Market" value={data.market_country}/></dl></section><section><h3>Portions</h3>{data.portions?.map((portion: Row) => <div className="event" key={portion.id}><span>{portion.amount} {portion.unit} · {portion.description}</span><b>{portion.gram_weight} g</b></div>)}</section><section><h3>Nutrients per 100 g</h3><div className="nutrients">{data.nutrients?.map((item: Row) => <div key={item.nutrient_code}><span>{item.nutrient_definitions?.name || item.nutrient_code}</span><b>{Number(item.amount_per_100g).toFixed(2)} {item.nutrient_definitions?.unit}</b></div>)}</div></section><section><h3>Ingredients</h3><p className="bodycopy">{data.ingredients_text || "No ingredients recorded."}</p></section>{data.pfqs && <section><h3>PFQS</h3><div className="score"><strong>{data.pfqs.score_100 ?? "—"}</strong><span>{data.pfqs.rating || data.pfqs.score_status}<small>{data.pfqs.model_version}</small></span></div></section>}</article>; }

function AdditiveDetail({ data }: { data: Row }) { return <article><p className="eyebrow">Current PFQS registry</p><h2>{data.canonical_name}</h2><p>{data.family || "No family"} · {data.canonical_id}</p><section><h3>Classification</h3><dl><Field label="Aliases" value={data.aliases?.join(", ")}/><Field label="Evidence confidence" value={data.evidence?.confidence}/><Field label="Last reviewed" value={data.evidence?.last_reviewed}/></dl><p className="bodycopy">{data.evidence?.summary}</p></section><section><h3>Jurisdiction rules</h3>{data.jurisdiction_rules?.length ? data.jurisdiction_rules.map((rule: Row, index: number) => <div className="rule" key={index}><strong>Tier {rule.tier} · −{rule.penalty}</strong><span>{rule.jurisdiction} · {rule.start_date} → {rule.end_date || "current"}</span><p>{rule.reason}</p></div>) : <p className="bodycopy">Recognized with no PFQS penalty classification.</p>}</section><section><h3>Primary sources</h3>{data.sources?.length ? data.sources.map((source: Row) => <a className="source" href={source.url} target="_blank" rel="noreferrer" key={source.document}>{source.organization}: {source.document} ↗</a>) : <p className="bodycopy">No penalty source is required for this recognized Tier 0 entry.</p>}</section></article>; }

function Field({ label, value }: { label: string; value: any }) { return <div><dt>{label}</dt><dd>{value || "—"}</dd></div>; }
function Empty({ tab }: { tab: Tab }) { return <div className="empty-list"><b>{tab === "queue" ? "No submissions here" : "No results"}</b><p>{tab === "queue" ? "Choose another status to inspect the rest of product activity." : "Try a broader search."}</p></div>; }
function date(value: string) { return value ? new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Unknown date"; }
function maxTier(row: Row) { return Math.max(0, ...(row.jurisdiction_rules || []).map((rule: Row) => rule.tier)); }
function activeContributionCount(summary: Row) { const values = summary.contributions ?? {}; return ["pending_review", "needs_review", "processing", "draft"].reduce((total, status) => total + Number(values[status] ?? 0), 0) || "—"; }
function statusLabel(status: string) { return ({ pending_review: "Ready for review", needs_review: "Needs photos", processing: "Processing", draft: "Draft", accepted: "Approved", rejected: "Rejected" } as Row)[status] ?? status?.replaceAll("_", " ") ?? "Unknown"; }
function statusDescription(status: string, reason?: string) { if (reason) return reason; return ({ needs_review: "Leafy needs clearer package photos before this submission can be verified.", processing: "Leafy is reading the package and checking its product information.", draft: "The contributor started this submission but has not sent it for processing.", accepted: "This submission has been approved and published to the Leafy catalog.", rejected: "This submission was not published." } as Row)[status] ?? "This record is available for inspection."; }
