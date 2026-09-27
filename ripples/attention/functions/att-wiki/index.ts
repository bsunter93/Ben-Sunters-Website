// att-wiki — Wikimedia attention collector (Ripples v5 attention layer, W7; ATTENTION_STACK §3.3 / §3.4 / §3.6).
//
// Modes (POST, x-collector-token; §7.3 contract via att.ts serve()):
//   top_country       wiki.topcc  Top-per-country (AQS top-per-country, ~45 countries, previous UTC day): for registry
//                                 titles a rank series per country (value = rank, aux = views_ceil) plus the daily
//                                 Reach series (number of countries, SQL att_wiki_topcc_reach); discovery candidates
//                                 (rank <= 200, not evergreen: views >= 2x the title's own level over the previous 3
//                                 days, where absence from a previous list counts as that list's rank-1000 threshold).
//                                 Resumable per day (att_state 'topcc.day:<day>'); rows hidden by Wikimedia's privacy
//                                 threshold are never reconstructed.
//   pageviews         wiki.pv     AQS per-article daily views (all-access, agent=user) for registry titles that are not
//                                 already collected as public.signals (those are mirrored in SQL, no request): one call
//                                 per article; full 420-day history on first sight, then incremental from last_day + 1.
//                                 Active topics daily, panel-only topics every att_config.wiki.panel_every_days.
//   mediarequests     wiki.media  Commons file requests for each active topic's lead image. The image is the topic's
//                                 Wikidata P18 claim, read from Special:EntityData/<QID>.json (a /wiki/ path: robots.txt
//                                 is checked; streamed, stops at the P18 claim; one call per topic). The MediaWiki Action
//                                 API route (prop=pageimages, 50 titles per call, maxlag=5) is used ONLY if the owner sets
//                                 att_config.wiki.action_api_ok = true (DEMARCATION §7.1 vs §0 / matrix row 200) and adds
//                                 wikipedia.org to the source's hosts. Topics without an image are remembered and skipped
//                                 for 30 days. Deferred while any active topic still lacks its pageview history.
//   clickstream_small wiki.cs     Monthly clickstream for small wikis, only if the compressed file is <= cs_max_mb
//                                 (HEAD check). Every current clickstream wiki is far larger, so they are reported as
//                                 GitHub-Action-only (ripples-clickstream.yml) and nothing is downloaded.
//   backfill          wiki.pv     att_tick('backfill') jobs: full histories for the job keys (same code as pageviews);
//                                 jobs are settled per key (done / requeued with a sensible not_before).
//   ping                          no requests.
//
// att_sources.per_day_cap is enforced even for sources inside the shared bucket (wiki.cs: 3/day): get() also charges
// the per-source day bucket 'src:<source>' for every request made.
// Every Wikimedia request goes through att.ts politeFetch: honest UA (+Api-User-Agent), shared 'wikimedia' budget
// (1,500/day attention share; charged per request, unspent units refunded), per-source per-run caps, >= 1 s serial
// spacing per host, the 06:30-07:20 UTC quiet window, the UA contact gate, and the kill switch (429/503: host stopped
// for the UTC day after at most one AQS retry per run; 401/403: permanent). Only counts, ranks and indices are stored.
import {
  serve, politeFetch, wikiApiJson, ingest, ingestCandidates, ingestEdges, watchlist, stateGet, stateSet, configGet,
  sourceInfo, takeBudget, db, addDays, compact, lines, type Run, type ObsRow,
} from "./att.ts";

const WIKI_VERSION = "2026-09-25.w2";
const AQS = "https://wikimedia.org/api/rest_v1/metrics";

// ---------------------------------------------------------------- config
interface WikiCfg {
  countries: string[]; topcc_access: string; topcc_max_tries: number; topcc_hist_days: number;
  topcc_cand_max_rank: number; topcc_cand_min_ratio: number; pv_days: number; pv_max_articles: number;
  media_day_cap: number; cs_wikis: string[]; cs_max_mb: number; action_api_ok: boolean; entitydata_max_mb: number;
}
const DEFAULTS: WikiCfg = {
  countries: ["US", "GB", "CA", "AU", "IN", "DE", "FR", "ES", "IT", "BR", "MX", "JP"],
  topcc_access: "all-access", topcc_max_tries: 3, topcc_hist_days: 3, topcc_cand_max_rank: 200,
  topcc_cand_min_ratio: 2, pv_days: 420, pv_max_articles: 400, media_day_cap: 200,
  cs_wikis: ["ptwiki", "plwiki", "zhwiki"], cs_max_mb: 8, action_api_ok: false, entitydata_max_mb: 12,
};
async function wikiCfg(): Promise<WikiCfg> {
  const c = (await configGet("wiki").catch(() => null)) as Partial<WikiCfg> | null;
  return { ...DEFAULTS, ...(c ?? {}) };
}

// ---------------------------------------------------------------- helpers
const isoDay = (ts: string) => `${ts.slice(0, 4)}-${ts.slice(4, 6)}-${ts.slice(6, 8)}`;
const r2 = (x: number) => Math.round(x * 100) / 100;
function median(a: number[]): number {
  const s = [...a].sort((x, y) => x - y);
  const n = s.length;
  return n === 0 ? 0 : n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
}
/** Reasons that end all further work on a host in this run. */
const HARD_STOP = /^(host_killed|host_busy|host_lease_error|wm_quiet_window|ua_contact_unreachable|daily_budget_spent|per_run_cap|source_disabled|unknown_source|host_not_in_source|robots_disallow|red_source|wikimedia_(maxlag|ratelimited))/;

/**
 * att_sources.per_day_cap for a source that draws on a shared bucket (wiki.cs: 3/day inside 'wikimedia'). politeFetch
 * charges only the shared bucket, so the per-source day bucket 'src:<source>' (SQL _att_bucket: cap = per_day_cap) is
 * charged here: one unit before the request, then settled to the number of requests actually made (redirect hops
 * included; unspent units refunded). Returns a stop reason when the day's per-source cap is spent.
 */
async function withSourceDayCap<T>(run: Run, source: string, host: string, fn: () => Promise<T>): Promise<T | { stop: string }> {
  const s = await sourceInfo(source).catch(() => null);
  if (!s || s.per_day_cap == null || !s.budget_bucket || s.budget_bucket === source) return await fn();
  const b = `src:${source}`;
  const held = await takeBudget(b, 1).catch(() => 0);
  if (held <= 0) { run.partial = true; run.skip(host, `daily_budget_spent:${b}`); return { stop: `daily_budget_spent:${b}` }; }
  const before = run.reqBySource[source] ?? 0;
  try {
    return await fn();
  } finally {
    const made = (run.reqBySource[source] ?? 0) - before;
    if (made < held) await db.rpc("att_budget_refund", { p_bucket: b, p_n: held - made });
    else if (made > held) await takeBudget(b, made - held).catch(() => 0);
  }
}

/**
 * One request through politeFetch. Returns the Response, or {stop} when this run must stop using the host (kill,
 * budget, cap, quiet window, contact gate, lease), or {soft} for a one-off failure (network error, bad redirect).
 */
async function get(run: Run, url: string, source: string, init: Record<string, unknown> = {}):
  Promise<Response | { stop: string } | { soft: string }> {
  const nSkip = run.skipped.length, nErr = run.errors.length;
  const host = new URL(url).hostname.toLowerCase();
  const res = await withSourceDayCap(run, source, host,
    () => politeFetch(run, url, { source, aqsRetry: host === "wikimedia.org", ...init }));
  if (isStop(res)) return res;
  if (res) return res;
  const skip = run.skipped.slice(nSkip).map((s) => s.reason).find((r) => HARD_STOP.test(r));
  if (skip) return { stop: skip };
  if (run.killed.has(host)) return { stop: run.killed.get(host)! };
  if (run.timeLeft() < 2000) return { stop: "out_of_time" };
  return { soft: run.errors.slice(nErr).join("; ") || "request_failed" };
}
const isStop = (x: unknown): x is { stop: string } => !!x && typeof x === "object" && "stop" in (x as object);
const isSoft = (x: unknown): x is { soft: string } => !!x && typeof x === "object" && "soft" in (x as object);

function srcStatus(stop: string | null, partial: boolean): string {
  if (!stop) return partial ? "partial" : "ok";
  if (stop.startsWith("daily_budget_spent") || stop.startsWith("per_run_cap")) return "budget_exhausted";
  if (stop.startsWith("host_killed_429") || stop.startsWith("host_killed_503")) return "host_killed_429";
  if (stop.startsWith("robots_disallow")) return "robots_disallow";
  if (stop.startsWith("source_disabled")) return "disabled";
  return "partial";
}

// ---------------------------------------------------------------- top_country
interface Snap { thr: number; t: string[]; v: number[] }
interface TopccDay { done: string[]; unavailable: Record<string, number>; tries: number }

async function topCountry(run: Run) {
  const t0 = Date.now();
  const cfg = await wikiCfg();
  const day: string = typeof run.params.date === "string" ? run.params.date : run.asOf;
  const access: string = run.params.access ?? cfg.topcc_access;
  const want: string[] = (Array.isArray(run.params.countries) ? run.params.countries : cfg.countries)
    .map((c: string) => String(c).toUpperCase()).filter((c: string) => /^[A-Z]{2}$/.test(c));
  const stKey = `topcc.day:${day}`;
  const st = ((await stateGet(stKey)) as TopccDay | null) ?? { done: [], unavailable: {}, tries: 0 };
  st.tries++;
  const todo = want.filter((c) => !st.done.includes(c) && (st.unavailable[c] ?? 0) < cfg.topcc_max_tries);

  // registry titles (project|title -> topic) and prior snapshots for the evergreen filter
  const reg = new Map<string, number>();
  for (const k of await watchlist(run, "wiki.pv", 20000)) reg.set(`${k.geo}|${k.key}`, k.topic_id);
  const prev = new Map<string, Array<{ thr: number; m: Map<string, number> }>>();
  {
    const { data, error } = await db.rpc("att_wiki_topcc_prev", { p_day: day, p_days: cfg.topcc_hist_days });
    if (error) run.errors.push(`att_wiki_topcc_prev: ${error.message}`);
    for (const r of (data ?? []) as Array<{ cc: string; v: Snap }>) {
      if (!r?.v || !Array.isArray(r.v.t)) continue;
      const m = new Map<string, number>();
      r.v.t.forEach((t, i) => m.set(t, Number(r.v.v[i]) || 0));
      (prev.get(r.cc) ?? prev.set(r.cc, []).get(r.cc)!).push({ thr: Number(r.v.thr) || 0, m });
    }
  }

  const rows: ObsRow[] = [];
  const cands: Array<Record<string, any>> = [];
  let stop: string | null = null, calls = 0, noHist = 0;
  const [y, mo, d] = day.split("-");
  for (const cc of todo) {
    if (run.outOfTime(8000)) { run.partial = true; stop = stop ?? "out_of_time"; break; }
    const r = await get(run, `${AQS}/pageviews/top-per-country/${cc}/${access}/${y}/${mo}/${d}`, "wiki.topcc");
    if (isStop(r)) { stop = r.stop; run.partial = true; break; }
    if (isSoft(r)) { st.unavailable[cc] = (st.unavailable[cc] ?? 0) + 1; continue; }
    calls++;
    if (r.status === 404) { await r.body?.cancel(); st.unavailable[cc] = (st.unavailable[cc] ?? 0) + 1; continue; }
    if (!r.ok) { await r.body?.cancel(); run.errors.push(`top-per-country ${cc} http ${r.status}`); continue; }
    const j = await r.json().catch(() => null);
    const arts: Array<{ article: string; project: string; views_ceil?: number; views?: number; rank: number }> =
      j?.items?.[0]?.articles ?? [];
    if (!arts.length) { st.unavailable[cc] = (st.unavailable[cc] ?? 0) + 1; continue; }
    const snap: Snap = { thr: 0, t: [], v: [] };
    const N = arts.length;
    let thr = Infinity;
    for (const a of arts) {
      const pm = /^([a-z][a-z0-9-]*)\.wikipedia$/.exec(String(a.project ?? ""));
      const views = Number(a.views_ceil ?? a.views ?? 0);
      if (views > 0) thr = Math.min(thr, views);
      if (!pm || typeof a.article !== "string") continue;
      const lang = pm[1], title = a.article, rank = Number(a.rank) || 0;
      snap.t.push(`${lang}|${title}`); snap.v.push(views);
      const topic = reg.get(`${a.project}|${title}`);
      if (topic != null && rank > 0) {
        rows.push({ source: "wiki.topcc", metric: "rank", geo: cc, key: `${lang}:${title}`, day, value: rank, aux: views, topic_id: topic });
      }
      if (rank > 0 && rank <= cfg.topcc_cand_max_rank) {
        const hist = prev.get(cc) ?? [];
        if (!hist.length) { noHist++; continue; }
        const base = median(hist.map((h) => h.m.get(`${lang}|${title}`) ?? h.thr));
        const isNew = hist.every((h) => !h.m.has(`${lang}|${title}`));
        const ratio = views / Math.max(base, 1);
        if (ratio < cfg.topcc_cand_min_ratio) continue;
        cands.push({ day, source: "wiki.topcc", geo: cc, label: title.replaceAll("_", " "), title, rank, value: views,
          evidence: r2(Math.max(0, Math.min(1, 1 - Math.log(rank) / Math.log(N + 1)))), topic_id: topic ?? null,
          meta: { lang, ratio: r2(ratio), new: isNew, method: "topcc_prev3" } });
      }
    }
    snap.thr = Number.isFinite(thr) ? thr : 0;
    await stateSet(`topcc.snap:${cc}:${day}`, snap);
    st.done.push(cc);
  }

  // SKIP rules (main pages, namespaces, lists, dates, disambiguation...) on candidate titles
  let candRows: Array<Record<string, any>> = [];
  if (cands.length) {
    const { data, error } = await db.rpc("att_filter_titles", { p_titles: [...new Set(cands.map((c) => c.title))] });
    if (error) run.errors.push(`att_filter_titles: ${error.message}`);
    const keep = new Set<string>((data ?? []) as string[]);
    candRows = cands.filter((c) => keep.has(c.title)).map(({ title: _t, ...c }) => c);
  }
  await ingest(run, rows);
  await ingestCandidates(run, candRows);
  await stateSet(stKey, st);
  let reach: unknown = null;
  if (st.done.length && !run.dryRun) {
    const { data, error } = await db.rpc("att_wiki_topcc_reach", { p_day: day, p_coverage: st.done.length });
    if (error) run.errors.push(`att_wiki_topcc_reach: ${error.message}`); else reach = data;
  }
  const left = want.filter((c) => !st.done.includes(c) && (st.unavailable[c] ?? 0) < cfg.topcc_max_tries);
  if (left.length) { run.partial = true; run.nextCursor = { date: day, countries: left }; }
  run.extra = { ...run.extra, wiki_version: WIKI_VERSION, wikimedia_calls: calls, day, countries_done: st.done.length,
    countries_wanted: want.length, unavailable: st.unavailable, registry_rows: rows.length, candidates: candRows.length,
    candidates_no_history: noHist, reach, stop };
  run.source({ source: "wiki.topcc", status: srcStatus(stop, left.length > 0), keys: st.done.length,
    rows: rows.length, ms: Date.now() - t0, note: stop ?? (noHist ? "no prior snapshots yet: candidates start on day 2" : null) });
}

// ---------------------------------------------------------------- pageviews (and backfill)
interface PlanRow { key: string; geo: string; topic_id: number | null; series_id: number | null; from_day: string | null;
  kind: string; prio: number; last_day: string | null; first_day: string | null; act: boolean }

/** Fetch AQS per-article views for plan rows; returns the set of "geo|key" fully processed plus the stop reason. */
async function fetchPageviews(run: Run, plan: PlanRow[], cfg: WikiCfg, to: string) {
  const done = new Set<string>();
  const nodata: Record<string, string> = {};
  let rows: ObsRow[] = [];
  let stop: string | null = null, calls = 0, soft = 0, first = 0, incr = 0, hasTo = false;
  const flush = async () => { if (rows.length) { await ingest(run, rows); rows = []; } };
  for (const p of plan) {
    if (p.kind !== "first" && p.kind !== "incr") continue;
    if (run.outOfTime(12000)) { run.partial = true; stop = "out_of_time"; break; }
    const from = p.from_day ?? addDays(to, -cfg.pv_days);
    if (from > to) { done.add(`${p.geo}|${p.key}`); continue; }
    const url = `${AQS}/pageviews/per-article/${p.geo}/all-access/user/${encodeURIComponent(p.key)}/daily/${compact(from)}00/${compact(to)}00`;
    const r = await get(run, url, "wiki.pv");
    if (isStop(r)) { stop = r.stop; run.partial = true; break; }
    if (isSoft(r)) { if (++soft >= 3) { stop = "network_errors"; run.partial = true; break; } continue; }
    calls++;
    if (r.status === 404) {
      await r.body?.cancel();
      if (p.kind === "first") nodata[`${p.geo}|${p.key}`] = to;       // no views at all in 420 days: retry in 7 days
      else if (hasTo) for (let dd = from; dd <= to; dd = addDays(dd, 1)) rows.push({ source: "wiki.pv", geo: p.geo, key: p.key, day: dd, value: 0, topic_id: p.topic_id });
      done.add(`${p.geo}|${p.key}`);
      continue;
    }
    if (!r.ok) { await r.body?.cancel(); run.errors.push(`per-article ${p.geo} http ${r.status}`); continue; }
    const j = await r.json().catch(() => null);
    const byDay = new Map<string, number>();
    let last = "";
    for (const it of (j?.items ?? []) as Array<{ timestamp: string; views: number }>) {
      const dd = isoDay(String(it.timestamp));
      byDay.set(dd, Number(it.views) || 0);
      if (dd > last) last = dd;
    }
    if (byDay.has(to)) hasTo = true;
    // AQS omits zero days: fill zeros up to `to` once this run has seen data for `to`, else up to the last day present
    const end = hasTo ? to : last;
    if (end) for (let dd = from; dd <= end; dd = addDays(dd, 1)) {
      rows.push({ source: "wiki.pv", geo: p.geo, key: p.key, day: dd, value: byDay.get(dd) ?? 0, topic_id: p.topic_id });
    }
    if (p.kind === "first") first++; else incr++;
    done.add(`${p.geo}|${p.key}`);
    if (rows.length >= 8000) await flush();
  }
  await flush();
  if (Object.keys(nodata).length && !run.dryRun) {
    const cur = ((await stateGet("wiki.pv.nodata").catch(() => null)) ?? {}) as Record<string, string>;
    await stateSet("wiki.pv.nodata", { ...cur, ...nodata });
  }
  return { done, stop, calls, first, incr, nodata: Object.keys(nodata).length };
}

async function pageviews(run: Run) {
  const t0 = Date.now();
  const cfg = await wikiCfg();
  const to = run.asOf;
  const mirror = run.dryRun ? null : (await db.rpc("att_wiki_mirror_signals", { p_as_of: to })).data;
  const limit = Math.min(Number(run.params.max_articles ?? cfg.pv_max_articles), 2000);
  const { data, error } = await db.rpc("att_wiki_pv_plan", { p_as_of: to, p_limit: limit, p_keys: null });
  if (error) throw new Error(`att_wiki_pv_plan: ${error.message}`);
  const plan = (data ?? []) as PlanRow[];
  const out = await fetchPageviews(run, plan, cfg, to);
  const swept = run.dryRun ? 0 : (await db.rpc("att_wiki_jobs_sweep", { p_as_of: to })).data;
  if (out.done.size < plan.length) run.partial = true;
  run.extra = { ...run.extra, wiki_version: WIKI_VERSION, wikimedia_calls: out.calls, planned: plan.length,
    fetched_first: out.first, fetched_incr: out.incr, nodata: out.nodata, mirror, jobs_swept: swept, stop: out.stop };
  run.source({ source: "wiki.pv", status: srcStatus(out.stop, out.done.size < plan.length), keys: out.done.size,
    rows: run.rows.obs, ms: Date.now() - t0, note: out.stop });
}

/** 10:05 UTC tomorrow: the next att-backfill window after a block that lasts for the rest of the UTC day. */
function nextWindow(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 10, 5)).toISOString();
}

async function backfill(run: Run) {
  const t0 = Date.now();
  const src = String(run.params.source ?? "wiki.pv");
  const ids = run.jobIds();
  if (src !== "wiki.pv") {
    // only wiki.pv has history jobs (att_sources.backfill_fn); anything else is settled as skipped
    if (ids.length && !run.dryRun) await db.rpc("att_jobs_done", { p_jobs: ids, p_status: "skipped", p_error: `att-wiki: no backfill for ${src}`, p_not_before: null });
    run.body.job_ids = []; run.body.job_id = null;
    run.source({ source: src, status: "disabled", keys: 0, rows: 0, ms: 0, note: "no backfill path for this source" });
    return;
  }
  const cfg = await wikiCfg();
  const to = run.asOf;
  const keys = (Array.isArray(run.body?.keys) ? run.body.keys : []).map((k: any) => ({ key: String(k.key), geo: String(k.geo ?? "en.wikipedia") }));
  if (!run.dryRun) await db.rpc("att_wiki_mirror_signals", { p_as_of: to });
  const { data, error } = await db.rpc("att_wiki_pv_plan", { p_as_of: to, p_limit: 5000, p_keys: keys });
  if (error) throw new Error(`att_wiki_pv_plan: ${error.message}`);
  const plan = (data ?? []) as PlanRow[];
  // a backfill job only needs the full history; incremental updates belong to the pageviews mode
  const need = plan.filter((p) => p.kind === "first");
  const out = await fetchPageviews(run, need, cfg, to);
  const pending = new Set(need.filter((p) => !out.done.has(`${p.geo}|${p.key}`)).map((p) => `${p.geo}|${p.key}`));

  // settle each merged job by its own keys (att.ts finish() would requeue everything for +1 h)
  let settled: Record<string, number> = {};
  if (ids.length && !run.dryRun) {
    const { data: jk, error: e2 } = await db.rpc("att_wiki_jobs", { p_ids: ids });
    if (e2) run.errors.push(`att_wiki_jobs: ${e2.message}`);
    else {
      const doneIds: number[] = [], waitIds: number[] = [];
      for (const j of (jk ?? []) as Array<{ id: number; keys: Array<{ key: string; geo?: string }> }>) {
        const open = (j.keys ?? []).some((k) => pending.has(`${k.geo ?? "en.wikipedia"}|${k.key}`));
        (open ? waitIds : doneIds).push(Number(j.id));
      }
      const s = out.stop ?? "";
      const dayScoped = /^(daily_budget_spent|host_killed_429|host_killed_503|wm_quiet_window)/.test(s);
      const later = /^(ua_contact_unreachable|host_killed_.*_permanent)/.test(s);
      const nb = dayScoped ? nextWindow()
        : later ? new Date(Date.now() + 6 * 3600_000).toISOString()
        : new Date(Date.now() + 3 * 60_000).toISOString();
      if (doneIds.length) await db.rpc("att_jobs_done", { p_jobs: doneIds, p_status: "done", p_error: null, p_not_before: null });
      if (waitIds.length) await db.rpc("att_jobs_done", { p_jobs: waitIds, p_status: "requeue", p_error: out.stop ?? "partial", p_not_before: nb });
      settled = { done: doneIds.length, requeued: waitIds.length };
      run.extra.requeue_not_before = waitIds.length ? nb : null;
      run.body.job_ids = []; run.body.job_id = null; // settled here; keep att.ts finish() from re-settling
    }
  }
  if (!run.dryRun) await db.rpc("att_wiki_jobs_sweep", { p_as_of: to });
  run.extra = { ...run.extra, wiki_version: WIKI_VERSION, wikimedia_calls: out.calls, job_keys: keys.length,
    by_kind: plan.reduce((a: Record<string, number>, p) => { a[p.kind] = (a[p.kind] ?? 0) + 1; return a; }, {}),
    fetched_first: out.first, nodata: out.nodata, jobs: settled, stop: out.stop };
  run.source({ source: "wiki.pv", status: srcStatus(out.stop, pending.size > 0), keys: out.done.size,
    rows: run.rows.obs, ms: Date.now() - t0, note: out.stop });
}

// ---------------------------------------------------------------- mediarequests
interface MediaPlan { kind: string; topic_id: number; project: string | null; title: string | null; qid: string | null;
  key: string | null; path: string | null; series_id: number | null; from_day: string | null; last_day: string | null }

/** MD5 (hex) of a UTF-8 string: Commons upload paths are /<md5[0]>/<md5[0..2]>/<File_name>. WebCrypto has no MD5. */
const MD5_S = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];
const MD5_K = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32) >>> 0);
export function md5hex(str: string): string {
  const bytes = new TextEncoder().encode(str);
  const len = bytes.length;
  const buf = new Uint8Array((((len + 8) >> 6) + 1) * 64);
  buf.set(bytes);
  buf[len] = 0x80;
  const dv = new DataView(buf.buffer);
  dv.setUint32(buf.length - 8, (len * 8) >>> 0, true);
  dv.setUint32(buf.length - 4, Math.floor((len * 8) / 2 ** 32), true);
  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  for (let off = 0; off < buf.length; off += 64) {
    let A = a0, B = b0, C = c0, D = d0;
    for (let i = 0; i < 64; i++) {
      let F: number, g: number;
      if (i < 16) { F = (B & C) | (~B & D); g = i; }
      else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
      else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
      else { F = C ^ (B | ~D); g = (7 * i) % 16; }
      F = (F + A + MD5_K[i] + dv.getUint32(off + g * 4, true)) >>> 0;
      A = D; D = C; C = B;
      const sh = MD5_S[(i >> 4) * 4 + (i % 4)];
      B = (B + ((F << sh) | (F >>> (32 - sh)))) >>> 0;
    }
    a0 = (a0 + A) >>> 0; b0 = (b0 + B) >>> 0; c0 = (c0 + C) >>> 0; d0 = (d0 + D) >>> 0;
  }
  const out = new DataView(new ArrayBuffer(16));
  [a0, b0, c0, d0].forEach((w, i) => out.setUint32(i * 4, w, true));
  return [...new Uint8Array(out.buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Commons file name (P18 value) -> { key, upload path } as used by AQS mediarequests. */
export function commonsPath(file: string): { key: string; path: string } | null {
  let name = file.trim().replaceAll(" ", "_");
  if (!name || name.includes("/") || name.length > 240) return null;
  name = name[0].toUpperCase() + name.slice(1);
  const h = md5hex(name);
  return { key: `commons:${name}`, path: `/wikipedia/commons/${h[0]}/${h.slice(0, 2)}/${name}` };
}

const P18_START = '"P18":[{"mainsnak":';
const P18_END = /\],"P\d+":\[\{"mainsnak":|"sitelinks":/;
const P18_SNAK = /"mainsnak":\{"snaktype":"value","property":"P18",(?:"hash":"[0-9a-f]+",)?"datavalue":\{"value":"((?:[^"\\]|\\.)*)","type":"string"\}(?:.*?"rank":"(preferred|normal|deprecated)")?/gs;

/**
 * Stream a Special:EntityData JSON body and return the P18 file name (preferred rank first, deprecated ignored).
 * CPU-lean: only a 32-char carry is kept until the P18 claim starts; reading stops at the end of that claim, at
 * "sitelinks" (claims come before sitelinks: no P18), or at maxBytes (undecided).
 */
export async function p18FromEntityData(res: Response, maxBytes: number): Promise<{ file: string | null; decided: boolean }> {
  if (!res.body) return { file: null, decided: false };
  const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
  let carry = "", seg: string | null = null, n = 0, decided = false, ended = false;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) { ended = true; break; }
      n += value.length;
      if (seg === null) {
        const s = carry + value;
        const i = s.indexOf(P18_START);
        if (i >= 0) seg = s.slice(i);
        else if (s.includes('"sitelinks":')) { decided = true; break; }
        else carry = s.slice(-32);
      } else seg += value;
      if (seg !== null) {
        const e = seg.slice(P18_START.length).search(P18_END);
        if (e >= 0) { seg = seg.slice(0, e + P18_START.length); break; }
        if (seg.length > 256_000) break;
      }
      if (n > maxBytes) return { file: null, decided: false };
    }
  } finally {
    await reader.cancel().catch(() => undefined);
  }
  if (seg === null) return { file: null, decided: decided || ended };
  let best: string | null = null, bestRank = -1;
  for (const m of seg.matchAll(P18_SNAK)) {
    const rank = m[2] === "preferred" ? 2 : m[2] === "deprecated" ? -1 : 1;
    if (rank > bestRank) {
      try { best = JSON.parse(`"${m[1]}"`) as string; bestRank = rank; } catch { /* malformed escape: skip */ }
    }
  }
  return { file: bestRank >= 0 ? best : null, decided: true };
}

/** Lead image = Wikidata P18 via Special:EntityData/<QID>.json (robots.txt checked by politeFetch; one call per topic). */
async function resolveViaEntityData(run: Run, items: MediaPlan[], maxCalls: number, maxBytes: number) {
  const out: Array<Record<string, unknown>> = [];
  let calls = 0, stop: string | null = null, noQid = 0, undecided = 0;
  for (const it of items) {
    if (!it.qid || !/^Q[0-9]+$/.test(it.qid)) { noQid++; continue; }
    if (calls >= maxCalls) { run.partial = true; stop = "media_day_cap"; break; }
    if (run.outOfTime(15000)) { run.partial = true; stop = "out_of_time"; break; }
    const r = await get(run, `https://www.wikidata.org/wiki/Special:EntityData/${it.qid}.json`, "wiki.media");
    if (isStop(r)) { stop = r.stop; run.partial = true; break; }
    if (isSoft(r)) continue;
    calls++;
    if (r.status === 404) { await r.body?.cancel(); out.push({ topic_id: it.topic_id, none: true }); continue; }
    if (!r.ok) { await r.body?.cancel(); run.errors.push(`EntityData ${it.qid} http ${r.status}`); continue; }
    const p = await p18FromEntityData(r, maxBytes);
    if (!p.decided) { undecided++; continue; }
    const cp = p.file ? commonsPath(p.file) : null;
    if (cp) out.push({ topic_id: it.topic_id, key: cp.key, path: cp.path });
    else out.push({ topic_id: it.topic_id, none: true }); // no image: re-check in 30 days
  }
  return { out, calls, stop, noQid, undecided };
}

/** Lead image via the Action API (prop=pageimages, 50 titles per call). Only when att_config.wiki.action_api_ok. */
async function resolveViaPageImages(run: Run, items: MediaPlan[], maxCalls: number) {
  const byProject = new Map<string, MediaPlan[]>();
  for (const it of items) if (it.project && it.title) (byProject.get(it.project) ?? byProject.set(it.project, []).get(it.project)!).push(it);
  const out: Array<Record<string, unknown>> = [];
  let calls = 0, stop: string | null = null;
  for (const [project, list] of byProject) {
    const lang = project.split(".")[0];
    for (let i = 0; i < list.length; i += 50) {
      if (calls >= maxCalls) { run.partial = true; stop = "media_day_cap"; break; }
      if (run.outOfTime(20000)) { run.partial = true; stop = "out_of_time"; break; }
      const chunk = list.slice(i, i + 50);
      const u = new URL(`https://${lang}.wikipedia.org/w/api.php`);
      for (const [k, v] of Object.entries({ action: "query", format: "json", formatversion: "2", prop: "pageimages",
        piprop: "original", pilicense: "free", redirects: "1", titles: chunk.map((c) => c.title!).join("|") })) u.searchParams.set(k, v);
      const nSkip = run.skipped.length;
      const j = await wikiApiJson(run, u.toString(), "wiki.media");
      calls++;
      if (!j) {
        const why = run.skipped.slice(nSkip).map((s) => s.reason).find((r) => HARD_STOP.test(r));
        if (why || run.killed.has(u.hostname)) { stop = why ?? run.killed.get(u.hostname)!; run.partial = true; break; }
        continue;
      }
      const norm = new Map<string, string>();
      for (const n of (j.query?.normalized ?? []) as Array<{ from: string; to: string }>) norm.set(n.from, n.to);
      const redir = new Map<string, string>();
      for (const n of (j.query?.redirects ?? []) as Array<{ from: string; to: string }>) redir.set(n.from, n.to);
      const pages = new Map<string, any>();
      for (const p of (j.query?.pages ?? []) as any[]) pages.set(p.title, p);
      for (const c of chunk) {
        let t = norm.get(c.title!) ?? c.title!.replaceAll("_", " ");
        t = redir.get(t) ?? t;
        const pg = pages.get(t);
        const src: string | undefined = pg?.original?.source;
        let path: string | null = null;
        try { if (src) { const su = new URL(src); if (su.hostname === "upload.wikimedia.org") path = decodeURIComponent(su.pathname); } } catch { path = null; }
        const m = path ? /^\/wikipedia\/([a-z0-9-]+)\/[0-9a-f]\/[0-9a-f]{2}\/([^/]+)$/.exec(path) : null;
        if (m) out.push({ topic_id: c.topic_id, key: `${m[1]}:${m[2]}`, path });
        else out.push({ topic_id: c.topic_id, none: true }); // no free lead image (or page missing): re-check in 30 days
      }
    }
    if (stop) break;
  }
  return { out, calls, stop, noQid: 0, undecided: 0 };
}

async function resolveImages(run: Run, items: MediaPlan[], cfg: WikiCfg, maxCalls: number) {
  const via = cfg.action_api_ok === true ? "action_api_pageimages" : "wikidata_entitydata_p18";
  const r = via === "action_api_pageimages"
    ? await resolveViaPageImages(run, items, maxCalls)
    : await resolveViaEntityData(run, items, maxCalls, Math.max(1, cfg.entitydata_max_mb) * 1048576);
  let reg: unknown = null;
  if (r.out.length && !run.dryRun) {
    const { data, error } = await db.rpc("att_wiki_media_keys", { p_rows: r.out });
    if (error) run.errors.push(`att_wiki_media_keys: ${error.message}`); else reg = data;
  }
  return { via, calls: r.calls, stop: r.stop, resolved: r.out.filter((o) => o.key).length,
    none: r.out.filter((o) => o.none).length, no_qid: r.noQid, undecided: r.undecided, reg };
}

async function mediarequests(run: Run) {
  const t0 = Date.now();
  const cfg = await wikiCfg();
  const to = run.asOf;
  // pageview histories take the shared budget first
  const { data: pvPending } = await db.rpc("att_wiki_pv_plan", { p_as_of: to, p_limit: 1, p_keys: null });
  const firstLeft = ((pvPending ?? []) as PlanRow[]).filter((p) => p.kind === "first" && p.act).length;
  if (firstLeft && run.params.force !== true) {
    run.extra = { ...run.extra, wiki_version: WIKI_VERSION, wikimedia_calls: 0, deferred: "active topics still lack pageview history" };
    run.source({ source: "wiki.media", status: "partial", keys: 0, rows: 0, ms: Date.now() - t0, note: "deferred: pageview histories first" });
    return;
  }
  const used = Number((await db.rpc("att_wiki_calls_today", { p_mode: "mediarequests" })).data ?? 0);
  let allowance = Math.max(0, cfg.media_day_cap - used);
  if (allowance <= 0) {
    run.source({ source: "wiki.media", status: "budget_exhausted", keys: 0, rows: 0, ms: Date.now() - t0, note: `media_day_cap ${cfg.media_day_cap} reached` });
    return;
  }
  const plan1 = ((await db.rpc("att_wiki_media_plan", { p_as_of: to, p_limit: 2000 })).data ?? []) as MediaPlan[];
  // lookups get at most half of today's allowance so file histories also progress
  const res = await resolveImages(run, plan1.filter((p) => p.kind === "resolve"), cfg, Math.floor(allowance / 2));
  allowance -= res.calls;
  let stop = res.stop === "media_day_cap" ? null : res.stop, calls = 0, fetched = 0, hasTo = false;
  let rows: ObsRow[] = [];
  if (!stop) {
    const plan2 = ((await db.rpc("att_wiki_media_plan", { p_as_of: to, p_limit: 2000 })).data ?? []) as MediaPlan[];
    for (const p of plan2) {
      if (p.kind !== "first" && p.kind !== "incr") continue;
      if (calls >= allowance) { run.partial = true; stop = "media_day_cap"; break; }
      if (run.outOfTime(10000)) { run.partial = true; stop = "out_of_time"; break; }
      const from = p.from_day ?? addDays(to, -420);
      if (!p.path || from > to) continue;
      const url = `${AQS}/mediarequests/per-file/all-referers/user/${encodeURIComponent(p.path)}/daily/${compact(from)}00/${compact(to)}00`;
      const r = await get(run, url, "wiki.media");
      if (isStop(r)) { stop = r.stop; run.partial = true; break; }
      if (isSoft(r)) continue;
      calls++;
      if (r.status === 404) {
        await r.body?.cancel();
        if (hasTo) for (let dd = from; dd <= to; dd = addDays(dd, 1)) rows.push({ source: "wiki.media", key: p.key!, day: dd, value: 0, topic_id: p.topic_id });
        continue;
      }
      if (!r.ok) { await r.body?.cancel(); run.errors.push(`mediarequests http ${r.status}`); continue; }
      const j = await r.json().catch(() => null);
      const byDay = new Map<string, number>();
      let last = "";
      for (const it of (j?.items ?? []) as Array<{ timestamp: string; requests: number }>) {
        const dd = isoDay(String(it.timestamp));
        byDay.set(dd, Number(it.requests) || 0);
        if (dd > last) last = dd;
      }
      if (byDay.has(to)) hasTo = true;
      const end = hasTo ? to : last;
      if (end) for (let dd = from; dd <= end; dd = addDays(dd, 1)) rows.push({ source: "wiki.media", key: p.key!, day: dd, value: byDay.get(dd) ?? 0, topic_id: p.topic_id });
      fetched++;
      if (rows.length >= 8000) { await ingest(run, rows); rows = []; }
    }
  }
  if (rows.length) await ingest(run, rows);
  run.extra = { ...run.extra, wiki_version: WIKI_VERSION, wikimedia_calls: res.calls + calls, lookup_via: res.via,
    lookup_calls: res.calls, images_resolved: res.resolved, no_image: res.none, no_qid: res.no_qid,
    lookup_undecided: res.undecided, files_fetched: fetched, stop };
  run.source({ source: "wiki.media", status: srcStatus(stop && stop !== "media_day_cap" ? stop : null, run.partial),
    keys: fetched, rows: run.rows.obs, ms: Date.now() - t0, note: stop });
}

// ---------------------------------------------------------------- clickstream_small
async function clickstreamSmall(run: Run) {
  const t0 = Date.now();
  const cfg = await wikiCfg();
  const now = new Date();
  const pm = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const month: string = typeof run.params.month === "string" ? run.params.month : pm.toISOString().slice(0, 7);
  const wikis: string[] = (Array.isArray(run.params.wikis) ? run.params.wikis : cfg.cs_wikis).filter((w: string) => /^[a-z]{2,3}wiki$/.test(w));
  const maxBytes = cfg.cs_max_mb * 1048576;
  const report: Record<string, unknown> = {};
  let stop: string | null = null, edges = 0;
  for (const wiki of wikis) {
    if (run.outOfTime(15000)) { run.partial = true; stop = "out_of_time"; break; }
    const url = `https://dumps.wikimedia.org/other/clickstream/${month}/clickstream-${wiki}-${month}.tsv.gz`;
    const h = await get(run, url, "wiki.cs", { method: "HEAD" });
    if (isStop(h)) { stop = h.stop; run.partial = true; break; }
    if (isSoft(h)) { report[wiki] = { error: h.soft }; continue; }
    const size = Number(h.headers.get("content-length") ?? NaN);
    await h.body?.cancel();
    if (!h.ok) { report[wiki] = { status: h.status }; continue; }
    if (!Number.isFinite(size) || size > maxBytes) {
      report[wiki] = { bytes: Number.isFinite(size) ? size : null, action: "github_action_only" };
      run.skip("dumps.wikimedia.org", `github_action_only:${wiki}:${Number.isFinite(size) ? Math.round(size / 1048576) : "?"}MB`);
      continue;
    }
    // small enough for one edge run: stream, keep only edges touching registry titles of this wiki
    const lang = wiki.replace(/wiki$/, "");
    const reg = new Map<string, number>();
    for (const k of await watchlist(run, "wiki.pv", 20000)) if (k.geo === `${lang}.wikipedia`) reg.set(k.key, k.topic_id);
    const r = await get(run, url, "wiki.cs");
    if (isStop(r)) { stop = r.stop; run.partial = true; break; }
    if (isSoft(r) || !r.ok) { report[wiki] = { error: isSoft(r) ? r.soft : `http ${r.status}` }; continue; }
    const out = new Map<string, Array<{ to: string; n: number }>>();
    const inc: Array<Record<string, unknown>> = [];
    let n = 0;
    for await (const line of lines(r, true)) {
      if (++n % 20000 === 0 && run.outOfTime(8000)) { run.partial = true; stop = "out_of_time"; break; }
      const t1 = line.indexOf("\t"); if (t1 < 0) continue;
      const t2 = line.indexOf("\t", t1 + 1); if (t2 < 0) continue;
      const prev = line.slice(0, t1), curr = line.slice(t1 + 1, t2);
      const pu = reg.has(prev), cu = reg.has(curr);
      if (!pu && !cu) continue;
      const cnt = Number(line.slice(line.lastIndexOf("\t") + 1)) || 0;
      if (pu && !prev.startsWith("other-")) (out.get(prev) ?? out.set(prev, []).get(prev)!).push({ to: curr, n: cnt });
      if (cu && (prev.startsWith("other-") || cnt >= 50)) inc.push({ from_key: prev, to_key: curr, n: cnt, to_topic: reg.get(curr) ?? null, from_topic: reg.get(prev) ?? null });
    }
    const period = `${month}-01`;
    const rows: Array<Record<string, unknown>> = [];
    for (const [u, list] of out) for (const e of list.sort((a, b) => b.n - a.n).slice(0, 20)) {
      rows.push({ source: "wiki.cs", geo: `${lang}.wikipedia`, from_key: u, to_key: e.to, period, grain: "month", n: e.n, from_topic: reg.get(u) ?? null, to_topic: reg.get(e.to) ?? null });
    }
    for (const e of inc) rows.push({ source: "wiki.cs", geo: `${lang}.wikipedia`, period, grain: "month", ...e });
    const w = await ingestEdges(run, rows);
    edges += w.rows;
    report[wiki] = { bytes: size, lines: n, edges: w.rows };
    if (stop) break;
  }
  if (!run.dryRun) await stateSet(`wiki.cs:${month}`, { at: new Date().toISOString(), report }).catch(() => undefined);
  run.extra = { ...run.extra, wiki_version: WIKI_VERSION, month, wikis: report, edges, cs_max_mb: cfg.cs_max_mb,
    note: "clickstream files above cs_max_mb are processed by the GitHub Action ripples-clickstream.yml (monthly), not here" };
  run.source({ source: "wiki.cs", status: srcStatus(stop, false), keys: wikis.length, rows: edges, ms: Date.now() - t0, note: stop });
}

// ---------------------------------------------------------------- ping
async function ping(run: Run) {
  run.extra = { ...run.extra, wiki_version: WIKI_VERSION, modes: ["top_country", "pageviews", "mediarequests", "clickstream_small", "backfill", "ping"] };
  run.source({ source: "wiki.pv", status: "ok", keys: 0, rows: 0, ms: 0, note: "ping (no requests)" });
}

serve("att-wiki", {
  top_country: topCountry,
  pageviews,
  mediarequests,
  clickstream_small: clickstreamSmall,
  backfill,
  ping,
});
