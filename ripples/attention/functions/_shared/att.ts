// _shared/att.ts — shared runtime for every att-* edge function (Ripples v5 attention layer, W7).
//
// DEPLOY NOTE: the Supabase MCP deploy uploads only the files listed in each function's `files` array, so every
// collector ships its own copy of this file as ./att.ts next to index.ts and imports it with `import ... from "./att.ts"`.
// The canonical copy lives in ripples/attention/functions/_shared/att.ts. Keep copies byte-identical (ATT_VERSION).
//
// Provides: token check, the honest User-Agent, a robots.txt cache in ripples.att_state (24 h TTL; unreachable = deny),
// a per-host serial queue with spacing, the RED-source denylist, 429/503/403 kill switch, budget via att_take_budget,
// ingest via att_ingest / att_ingest_edges / att_ingest_candidates, the run log (att_runs), job completion, and the
// §7.3 request/response contract through serve().
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const ATT_VERSION = "2026-09-25.1";
export const UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)";
export const ROBOTS_TOKEN = "ripples-research";
export const WALL_MS = 110_000;
export const ROBOTS_TTL_MS = 24 * 3600 * 1000;

export const db: SupabaseClient = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

// ---------------------------------------------------------------- small utils
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, Math.max(0, ms)));
export const ymd = (d: Date) => d.toISOString().slice(0, 10);
export const compact = (s: string) => s.replaceAll("-", "");
export const addDays = (s: string, n: number) => ymd(new Date(Date.parse(s + "T00:00:00Z") + n * 86400000));
export const yesterday = () => ymd(new Date(Date.now() - 86400000));
export const errMsg = (e: unknown) => (e instanceof Error ? e.message : String(e));
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

// ---------------------------------------------------------------- auth
export async function checkToken(req: Request): Promise<boolean> {
  const t = req.headers.get("x-collector-token") ?? "";
  if (!t) return false;
  const { data, error } = await db.rpc("check_collector_token", { t });
  return !error && data === true;
}

// ---------------------------------------------------------------- policy: RED denylist (never fetched)
const RED: RegExp[] = [
  /(^|\.)reddit\.com$/, /(^|\.)redd\.it$/, /(^|\.)trends24\.in$/, /(^|\.)getdaytrends\.com$/,
  /^ads\.tiktok\.com$/, /(^|\.)tiktok\.com$/, /^suggestqueries\.google\.com$/, /^clients1\.google\.com$/,
  /^news\.google\.com$/, /(^|\.)yahoo\.com$/, /(^|\.)stooq\.(com|pl)$/, /(^|\.)nasdaq\.com$/,
  /^production\.dataviz\.cnn\.io$/, /(^|\.)cboe\.com$/, /(^|\.)spotify\.com$/, /(^|\.)billboard\.com$/,
  /(^|\.)boxofficemojo\.com$/, /^play\.google\.com$/, /(^|\.)flixpatrol\.com$/, /(^|\.)stocktwits\.com$/,
  /(^|\.)tradestie\.com$/, /(^|\.)opensky-network\.org$/, /^radar\.cloudflare\.com$/, /(^|\.)duckduckgo\.com$/,
  /^completion\.amazon\.[a-z.]+$/, /^autosug\.ebay\.com$/, /(^|\.)ebay\.com$/, /(^|\.)amazon\.[a-z.]+$/,
  /^(efts|www|data)\.sec\.gov$/, // disabled: SEC requires an owner contact email in the UA
];
const RED_PATH: Array<[RegExp, RegExp]> = [
  [/^(www\.)?google\.[a-z.]+$/, /^\/(complete|finance|search)/],
  [/^trends\.google\.[a-z.]+$/, /^\/(_\/|trends\/explore|trends\/api\/|trends\/embed)/], // RSS (/trending/rss) only
  [/^api\.bing\.com$/, /^\/osjson/], [/^www\.bing\.com$/, /^\/(AS|osjson)/i],
  [/^api\.gdeltproject\.org$/, /^\/api\/v2\/doc/],
  [/^api\.cloudflare\.com$/, /\/radar\//],
];
export function isRed(u: URL): boolean {
  const h = u.hostname.toLowerCase();
  if (RED.some((r) => r.test(h))) return true;
  return RED_PATH.some(([hr, pr]) => hr.test(h) && pr.test(u.pathname));
}

// Wikimedia documented APIs: robots.txt is not applied (DEMARCATION §7.1 lead decision); maxlag=5 on the Action API.
export function isWikimediaApi(u: URL): boolean {
  const h = u.hostname.toLowerCase();
  if (h === "wikimedia.org" || h === "api.wikimedia.org" || h === "stream.wikimedia.org") return true;
  if (/(^|\.)(wikipedia\.org|wikidata\.org|wikimedia\.org)$/.test(h)) {
    return u.pathname.startsWith("/w/api.php") || u.pathname.startsWith("/api/rest_v1/");
  }
  return false;
}

// ---------------------------------------------------------------- robots.txt
type Rule = [boolean, string]; // [allow, pattern]
interface RobotsEntry { status: number; fetched_at: number; deny_all: boolean; rules: Rule[] }
const robotsMem = new Map<string, RobotsEntry>();

export function parseRobots(txt: string, token = ROBOTS_TOKEN): Rule[] {
  type G = { agents: string[]; rules: Rule[] };
  const groups: G[] = [];
  let cur: G | null = null;
  let lastAgent = false;
  for (const raw of txt.split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, "").trim();
    if (!line) continue;
    const i = line.indexOf(":");
    if (i < 0) continue;
    const k = line.slice(0, i).trim().toLowerCase();
    const v = line.slice(i + 1).trim();
    if (k === "user-agent") {
      if (!cur || !lastAgent) { cur = { agents: [], rules: [] }; groups.push(cur); }
      cur.agents.push(v.toLowerCase());
      lastAgent = true;
      continue;
    }
    lastAgent = false;
    if (!cur) continue;
    if ((k === "allow" || k === "disallow") && v !== "") cur.rules.push([k === "allow", v]);
  }
  const mine = groups.filter((g) => g.agents.some((a) => a !== "*" && a.split("/")[0] === token));
  const use = mine.length ? mine : groups.filter((g) => g.agents.includes("*"));
  return use.flatMap((g) => g.rules);
}

function patternMatches(pattern: string, path: string): boolean {
  const anchored = pattern.endsWith("$");
  const p = anchored ? pattern.slice(0, -1) : pattern;
  const re = "^" + p.split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*") + (anchored ? "$" : "");
  try { return new RegExp(re).test(path); } catch { return false; }
}

export function robotsVerdict(rules: Rule[], pathAndQuery: string): boolean {
  let best = -1;
  let allow = true;
  for (const [a, p] of rules) {
    if (patternMatches(p, pathAndQuery)) {
      if (p.length > best || (p.length === best && a)) { best = p.length; allow = a; }
    }
  }
  return allow;
}

async function loadRobots(run: Run, origin: string, host: string): Promise<RobotsEntry> {
  const mem = robotsMem.get(origin);
  if (mem && Date.now() - mem.fetched_at < ROBOTS_TTL_MS) return mem;
  const cached = await stateGet(`robots:${origin}`) as RobotsEntry | null;
  if (cached && Date.now() - cached.fetched_at < ROBOTS_TTL_MS) { robotsMem.set(origin, cached); return cached; }
  let entry: RobotsEntry;
  try {
    const res = await serial(host, 1000, () =>
      fetch(`${origin}/robots.txt`, { headers: { "User-Agent": UA }, signal: AbortSignal.timeout(10_000) }));
    run.count(host, res.status);
    if (res.ok) {
      const txt = (await res.text()).slice(0, 512_000);
      entry = { status: res.status, fetched_at: Date.now(), deny_all: false, rules: parseRobots(txt) };
    } else if (res.status >= 400 && res.status < 500 && ![401, 403, 429].includes(res.status)) {
      await res.body?.cancel();
      entry = { status: res.status, fetched_at: Date.now(), deny_all: false, rules: [] }; // no robots.txt = allowed
    } else {
      await res.body?.cancel();
      entry = { status: res.status, fetched_at: Date.now(), deny_all: true, rules: [] }; // 401/403/429/5xx = deny
    }
  } catch (_e) {
    entry = { status: 0, fetched_at: Date.now(), deny_all: true, rules: [] }; // unreachable = deny
  }
  robotsMem.set(origin, entry);
  await stateSet(`robots:${origin}`, entry);
  return entry;
}

export async function robotsAllowed(run: Run, url: string | URL): Promise<boolean> {
  const u = typeof url === "string" ? new URL(url) : url;
  const e = await loadRobots(run, u.origin, u.hostname);
  if (e.deny_all) return false;
  return robotsVerdict(e.rules, u.pathname + u.search);
}

// ---------------------------------------------------------------- per-host serial queue
const hostQ = new Map<string, { chain: Promise<unknown>; last: number }>();
export function serial<T>(host: string, spacingMs: number, fn: () => Promise<T>): Promise<T> {
  const q = hostQ.get(host) ?? { chain: Promise.resolve(), last: 0 };
  hostQ.set(host, q);
  const p = q.chain.then(async () => {
    const wait = q.last + spacingMs - Date.now();
    if (wait > 0) await sleep(wait);
    q.last = Date.now();
    return await fn();
  });
  q.chain = p.then(() => undefined, () => undefined);
  return p;
}

// ---------------------------------------------------------------- state / budget / sources
export async function stateGet(k: string): Promise<unknown> {
  const { data, error } = await db.rpc("att_state_get", { p_k: k });
  if (error) throw new Error(`att_state_get: ${error.message}`);
  return data;
}
export async function stateSet(k: string, v: unknown): Promise<void> {
  const { error } = await db.rpc("att_state_set", { p_k: k, p_v: v });
  if (error) throw new Error(`att_state_set: ${error.message}`);
}
export async function configGet(k: string): Promise<unknown> {
  const { data, error } = await db.rpc("att_config_get", { p_key: k });
  if (error) throw new Error(`att_config_get: ${error.message}`);
  return data;
}
export interface SourceRow {
  source: string; enabled: boolean; grade: string; per_run_cap: number | null; per_day_cap: number | null;
  spacing_ms: number; budget_bucket: string | null; hosts: string[]; robots_required: boolean; reason: string | null;
  needs_secret: string | null; value_kind: string; grain: string;
}
const srcMem = new Map<string, SourceRow | null>();
export async function sourceInfo(source: string): Promise<SourceRow | null> {
  if (srcMem.has(source)) return srcMem.get(source)!;
  const { data, error } = await db.rpc("att_source_get", { p_source: source });
  if (error) throw new Error(`att_source_get: ${error.message}`);
  srcMem.set(source, (data as SourceRow) ?? null);
  return (data as SourceRow) ?? null;
}

/** Atomically take up to n units from a source's (or shared bucket's) daily budget. Returns the granted count (0 = stop). */
export async function takeBudget(bucket: string, n: number): Promise<number> {
  const { data, error } = await db.rpc("att_take_budget", { p_bucket: bucket, p_n: n });
  if (error) throw new Error(`att_take_budget: ${error.message}`);
  return Number(data ?? 0);
}

/** Chunked budget: call await b.take() before each request; false means the day's budget is spent. */
export function budget(run: Run, bucket: string, chunk = 25, perRunCap = Infinity) {
  let left = 0;
  let used = 0;
  let exhausted = false;
  return {
    async take(): Promise<boolean> {
      if (exhausted || used >= perRunCap) { run.partial = true; return false; }
      if (left <= 0) {
        const g = await takeBudget(bucket, Math.min(chunk, perRunCap - used));
        run.granted += g;
        if (g <= 0) { exhausted = true; run.partial = true; return false; }
        left = g;
      }
      left--; used++;
      return true;
    },
    get used() { return used; },
  };
}

// ---------------------------------------------------------------- kill switch
const killMem = new Map<string, string | null>();
export async function hostKilled(run: Run, host: string): Promise<string | null> {
  if (run.killed.has(host)) return run.killed.get(host)!;
  if (!killMem.has(host)) {
    const k = await stateGet(`kill:${host.toLowerCase()}`) as { status: number; until: string } | null;
    killMem.set(host, k && Date.parse(k.until) > Date.now() ? `host_killed_${k.status}` : null);
  }
  return killMem.get(host) ?? null;
}
/** 429/503/403: stop the host for the rest of the day, spend the source's budget, halve tomorrow's (429/503). */
export async function killHost(run: Run, host: string, status: number, source?: string) {
  const reason = `host_killed_${status}`;
  run.killed.set(host, reason);
  killMem.set(host, reason);
  run.partial = true;
  run.skip(host, reason);
  const { error } = await db.rpc("att_host_kill", { p_host: host, p_status: status, p_source: source ?? null });
  if (error) run.errors.push(`att_host_kill: ${error.message}`);
}

// ---------------------------------------------------------------- polite fetch
export interface FetchOpts extends RequestInit {
  source?: string;        // for spacing defaults + budget/kill attribution
  robots?: boolean;       // default: true unless a Wikimedia documented API
  spacingMs?: number;     // default: source spacing_ms, else 1000
  timeoutMs?: number;     // default 30 s, capped by the run's remaining wall time
  aqsRetry?: boolean;     // Wikimedia AQS only: one retry after 5 s on 429 (lead decision §7.3)
}
/**
 * The only way collectors should make outbound requests. Returns null when the request was not made or must not be
 * used (RED, robots disallow, killed host, out of time, 403/429/503, network error); the reason is recorded in run.
 */
export async function politeFetch(run: Run, url: string, o: FetchOpts = {}): Promise<Response | null> {
  let u: URL;
  try { u = new URL(url); } catch { run.errors.push(`bad url ${url}`); return null; }
  const host = u.hostname.toLowerCase();
  if (isRed(u)) { run.skip(host, "red_source"); return null; }
  const killed = await hostKilled(run, host);
  if (killed) { run.skip(host, killed); return null; }
  const wm = isWikimediaApi(u);
  if (wm && u.pathname.startsWith("/w/api.php") && !u.searchParams.has("maxlag")) u.searchParams.set("maxlag", "5");
  const needRobots = o.robots ?? !wm;
  if (needRobots && !(await robotsAllowed(run, u))) { run.skip(host, "robots_disallow"); return null; }
  const src = o.source ? await sourceInfo(o.source) : null;
  const spacing = o.spacingMs ?? src?.spacing_ms ?? 1000;
  const headers = new Headers(o.headers ?? {});
  headers.set("User-Agent", UA);
  if (wm) headers.set("Api-User-Agent", UA);
  headers.delete("cookie");
  let attempt = 0;
  while (true) {
    const remaining = run.timeLeft() - 1500;
    if (remaining <= 0) { run.partial = true; return null; }
    const timeout = Math.min(o.timeoutMs ?? 30_000, remaining);
    let res: Response;
    try {
      res = await serial(host, spacing, () =>
        fetch(u, { ...o, headers, redirect: o.redirect ?? "follow", signal: AbortSignal.timeout(timeout) }));
    } catch (e) {
      run.count(host, 0);
      run.errors.push(`${host}: ${errMsg(e)}`);
      return null;
    }
    run.count(host, res.status);
    if (res.status === 429 && o.aqsRetry && host === "wikimedia.org" && attempt === 0) {
      await res.body?.cancel();
      attempt++;
      await sleep(5000);
      continue;
    }
    if (res.status === 429 || res.status === 503 || res.status === 403) {
      await res.body?.cancel();
      await killHost(run, host, res.status, o.source);
      return null;
    }
    return res;
  }
}

/** MediaWiki Action API JSON (maxlag=5 added automatically). A maxlag/ratelimit error stops the host for this run. */
export async function wikiApiJson(run: Run, url: string, source = "wikidata"): Promise<any | null> {
  const res = await politeFetch(run, url, { source, spacingMs: 1100, robots: false });
  if (!res) return null;
  if (!res.ok) { await res.body?.cancel(); run.errors.push(`${new URL(url).hostname} http ${res.status}`); return null; }
  const j = await res.json().catch(() => null);
  const code = j?.error?.code;
  if (code === "maxlag" || code === "ratelimited") {
    run.killed.set(new URL(url).hostname, `wikimedia_${code}`);
    run.skip(new URL(url).hostname, `wikimedia_${code}`);
    run.partial = true;
    return null;
  }
  if (code) { run.errors.push(`wikimedia api error ${code}`); return null; }
  return j;
}

// ---------------------------------------------------------------- streaming helpers (CPU-lean)
/** Iterate text lines of a response body (optionally gzip). Use an indexOf prefilter before any JSON.parse. */
export async function* lines(res: Response, gzip = false): AsyncGenerator<string> {
  if (!res.body) return;
  let stream: ReadableStream<any> = res.body;
  if (gzip) stream = stream.pipeThrough(new DecompressionStream("gzip"));
  const reader = stream.pipeThrough(new TextDecoderStream()).getReader();
  let buf = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += value;
    let i: number;
    while ((i = buf.indexOf("\n")) >= 0) { yield buf.slice(0, i).replace(/\r$/, ""); buf = buf.slice(i + 1); }
  }
  if (buf) yield buf;
}

/** Tiny HyperLogLog (p=12, ~1.6% error) for distinct counts (e.g. DIDs). Only the estimate may be stored. */
export class HLL {
  private reg = new Uint8Array(4096);
  add(s: string) {
    let h = 0x811c9dc5;
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
    h ^= h >>> 16; h = Math.imul(h, 0x85ebca6b) >>> 0; h ^= h >>> 13; h = Math.imul(h, 0xc2b2ae35) >>> 0; h ^= h >>> 16;
    const idx = h >>> 20;
    const w = (h << 12) >>> 0;
    const rho = w === 0 ? 21 : Math.clz32(w) + 1;
    if (rho > this.reg[idx]) this.reg[idx] = rho;
  }
  count(): number {
    const m = 4096;
    let sum = 0, zeros = 0;
    for (const r of this.reg) { sum += 2 ** -r; if (r === 0) zeros++; }
    const e = (0.7213 / (1 + 1.079 / m)) * m * m / sum;
    return Math.round(e <= 2.5 * m && zeros ? m * Math.log(m / zeros) : e);
  }
}

// ---------------------------------------------------------------- writes
export interface ObsRow {
  source: string; key: string; metric?: string; geo?: string; day?: string; ts?: string;
  value: number; aux?: number | null; meta?: Record<string, unknown> | null; topic_id?: number | null;
}
async function rpcBatched(run: Run, fnName: string, rows: unknown[], batch: number, extra: Record<string, unknown> = {}) {
  const out = { rows: 0, series_new: 0, rejected: [] as unknown[] };
  for (let i = 0; i < rows.length; i += batch) {
    const slice = rows.slice(i, i + batch);
    const { data, error } = await db.rpc(fnName, { ...extra, p_rows: slice });
    if (error) { run.errors.push(`${fnName}: ${error.message}`); continue; }
    const d = data as { rows?: number; series_new?: number; rejected?: unknown };
    out.rows += d?.rows ?? 0;
    out.series_new += d?.series_new ?? 0;
    if (Array.isArray(d?.rejected)) out.rejected.push(...d!.rejected.slice(0, 20).map((r: any) => ({ ...r, i: (r.i ?? 0) + i })));
    else if (typeof d?.rejected === "number" && d.rejected > 0) out.rejected.push({ batch: i, n: d.rejected });
  }
  return out;
}
/** Upsert observations (daily `day` or hourly `ts`) through att_ingest. Honours dry_run. */
export async function ingest(run: Run, rows: ObsRow[], batch = 2000) {
  if (!rows.length) return { rows: 0, series_new: 0, rejected: [] };
  if (run.dryRun) { run.dryRows.push(...rows.slice(0, 50 - run.dryRows.length)); return { rows: rows.length, series_new: 0, rejected: [] }; }
  const r = await rpcBatched(run, "att_ingest", rows, batch, { p_run: { run_id: run.runId } });
  const hourly = rows.filter((x) => x.ts).length;
  run.rows.obs_hourly += Math.min(hourly, r.rows);
  run.rows.obs += Math.max(0, r.rows - Math.min(hourly, r.rows));
  run.rows.series_new += r.series_new;
  if (r.rejected.length) run.rejected.push(...r.rejected.slice(0, 50));
  return r;
}
export async function ingestEdges(run: Run, rows: Record<string, unknown>[], batch = 2000) {
  if (!rows.length || run.dryRun) return { rows: rows.length, series_new: 0, rejected: [] };
  const r = await rpcBatched(run, "att_ingest_edges", rows, batch);
  run.rows.edges += r.rows;
  return r;
}
export async function ingestCandidates(run: Run, rows: Record<string, unknown>[], batch = 2000) {
  if (!rows.length || run.dryRun) return { rows: rows.length, series_new: 0, rejected: [] };
  const r = await rpcBatched(run, "att_ingest_candidates", rows, batch);
  run.rows.candidates += r.rows;
  return r;
}
export interface WatchKey {
  key: string; geo: string; metric: string; match: Record<string, unknown>; series_id: number | null;
  topic_id: number; key_type: string;
}
/** Keys to query this run: body.keys if given, else att_watchlist(source) (active first, then panel). */
export async function watchlist(run: Run, source: string, limit = 5000, slice: number | null = null, nslices = 3): Promise<WatchKey[]> {
  if (Array.isArray(run.body?.keys) && run.body.keys.length) {
    return run.body.keys.map((k: any) => ({ key: String(k.key), geo: k.geo ?? "ALL", metric: k.metric ?? "n",
      match: k.match ?? {}, series_id: k.series_id ?? null, topic_id: k.topic_id ?? null, key_type: k.key_type ?? "term" }));
  }
  const { data, error } = await db.rpc("att_watchlist", { p_source: source, p_limit: limit, p_slice: slice, p_nslices: nslices });
  if (error) throw new Error(`att_watchlist: ${error.message}`);
  return (data ?? []) as WatchKey[];
}
export async function jobsDone(ids: number[], status: "done" | "failed" | "skipped" | "requeue", err?: string) {
  if (!ids.length) return;
  await db.rpc("att_jobs_done", { p_jobs: ids, p_status: status, p_error: err ?? null, p_not_before: null });
}

// ---------------------------------------------------------------- run + §7.3 contract
export interface SourceReport { source: string; status: string; keys?: number; rows?: number; ms?: number; note?: string | null }
export class Run {
  readonly t0 = Date.now();
  readonly startedAt = new Date().toISOString();
  readonly deadline: number;
  runId: number | null = null;
  made = 0;
  granted = 0;
  byHost: Record<string, Record<string, number>> = {};
  rows = { obs: 0, obs_hourly: 0, edges: 0, candidates: 0, series_new: 0 };
  sources: SourceReport[] = [];
  skipped: Array<{ host: string; reason: string }> = [];
  errors: string[] = [];
  rejected: unknown[] = [];
  dryRows: unknown[] = [];
  killed = new Map<string, string>();
  partial = false;
  nextCursor: unknown = null;
  extra: Record<string, unknown> = {};
  readonly asOf: string;
  readonly dryRun: boolean;
  readonly params: Record<string, any>;
  constructor(readonly fn: string, readonly mode: string, readonly body: any) {
    const wall = Math.min(WALL_MS, Number(body?.limit?.wall_ms ?? WALL_MS));
    this.deadline = this.t0 + wall;
    this.asOf = typeof body?.as_of === "string" ? body.as_of : yesterday();
    this.dryRun = body?.dry_run === true;
    this.params = body?.params ?? {};
  }
  timeLeft() { return this.deadline - Date.now(); }
  outOfTime(marginMs = 3000) { return this.timeLeft() < marginMs; }
  count(host: string, status: number) {
    this.made++;
    const h = (this.byHost[host] ??= {});
    h[String(status)] = (h[String(status)] ?? 0) + 1;
  }
  skip(host: string, reason: string) {
    if (!this.skipped.some((s) => s.host === host && s.reason === reason)) this.skipped.push({ host, reason });
  }
  source(r: SourceReport) { this.sources.push(r); }
  jobIds(): number[] {
    const ids = Array.isArray(this.body?.job_ids) ? this.body.job_ids : (this.body?.job_id ? [this.body.job_id] : []);
    return ids.map(Number).filter((x: number) => Number.isFinite(x));
  }
  async start() {
    const { data, error } = await db.rpc("att_run_start", {
      p_fn: this.fn, p_mode: this.mode || "?",
      p_detail: { as_of: this.asOf, dry_run: this.dryRun, job_ids: this.jobIds(), att_version: ATT_VERSION },
    });
    if (!error) this.runId = Number(data);
  }
  result() {
    return {
      ok: this.errors.length === 0,
      fn: this.fn,
      mode: this.mode,
      run_id: this.runId,
      as_of: this.asOf,
      started_at: this.startedAt,
      finished_at: new Date().toISOString(),
      partial: this.partial,
      next_cursor: this.nextCursor,
      requests: { made: this.made, granted: this.granted, by_host: this.byHost },
      rows: this.rows,
      sources: this.sources,
      skipped: this.skipped,
      errors: this.errors.slice(0, 50),
      ...(this.rejected.length ? { rejected: this.rejected.slice(0, 50) } : {}),
      ...(this.dryRun ? { dry_rows: this.dryRows } : {}),
      ...this.extra,
    };
  }
  async finish() {
    const out = this.result();
    if (this.runId) {
      await db.rpc("att_run_finish", { p_run: this.runId, p_result: { ...out, extra: this.extra, dry_rows: undefined } });
    }
    const ids = this.jobIds();
    if (ids.length && !this.dryRun) {
      const anyRows = this.rows.obs + this.rows.obs_hourly + this.rows.edges + this.rows.candidates > 0;
      const status = this.errors.length && !anyRows ? "failed" : this.partial ? "requeue" : "done";
      await jobsDone(ids, status, this.errors.slice(0, 5).join("; ") || undefined);
    }
    return out;
  }
}

export type ModeHandler = (run: Run) => Promise<void>;
/**
 * Serve an att-* function: POST only, x-collector-token checked against the vault (401 otherwise), §7.3 body in,
 * §7.3 body out (always HTTP 200 once authenticated; errors are reported in the body), one att_runs row per call.
 */
export function serve(fn: string, modes: Record<string, ModeHandler>) {
  Deno.serve(async (req) => {
    if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);
    if (!(await checkToken(req))) return json({ ok: false, error: "unauthorized" }, 401);
    const body = await req.json().catch(() => ({}));
    const mode = String(body?.mode ?? "");
    const run = new Run(fn, mode, body);
    const handler = modes[mode];
    await run.start();
    if (!handler) run.errors.push(`unknown mode '${mode}'; modes: ${Object.keys(modes).join(", ")}`);
    else {
      try { await handler(run); } catch (e) { run.errors.push(errMsg(e)); }
    }
    return json(await run.finish());
  });
}
