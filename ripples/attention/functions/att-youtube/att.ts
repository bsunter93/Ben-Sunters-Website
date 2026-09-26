// _shared/att.ts — shared runtime for every att-* edge function (Ripples v5 attention layer, W7).
//
// DEPLOY NOTE: the Supabase MCP deploy uploads only the files listed in each function's `files` array, so every
// collector ships its own copy of this file as ./att.ts next to index.ts and imports it with `import ... from "./att.ts"`.
// The canonical copy lives in ripples/attention/functions/_shared/att.ts. Keep copies byte-identical (ATT_VERSION).
//
// Provides: token check, the honest User-Agent, a robots.txt cache in ripples.att_state (24 h TTL; unreachable = deny),
// a per-host serial queue with spacing plus a cross-isolate host lease (one run per host at a time), the RED-source
// denylist, the kill switch (429/503: rest of the UTC day; 401/403/sign-in redirect: permanent until the owner clears it),
// manual redirect handling (every hop re-checked; credentials never cross origins), central per-run caps AND per-day
// budgets charged inside politeFetch (att_take_budget, chunked, unspent units refunded), a spacing floor per source, the
// Wikimedia quiet window, the UA contact gate, ingest via att_ingest / att_ingest_edges / att_ingest_candidates, the run
// log (att_runs), job completion, and the §7.3 request/response contract through serve().
// Keys (OWNER D-5 / D-7 / D-10): Vault secrets are read ONLY at run time through public.att_secret (attSecret), kept in
// memory, and scrubbed (values and key-like query parameters) from everything Run.finish() persists or returns. The SEC
// contact email (Vault 'sec_contact_email') is added to the User-Agent ONLY for requests to sec.gov hosts (secUa).
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const ATT_VERSION = "2026-09-25.4";
export const UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)";
/** The contact page named in UA. Wikimedia (§7.1) requires a UA "that includes a contact": the contact gate refuses
 *  requests in scope (att_config.contact_gate.scope: 'wikimedia' | 'all') while this page does not answer 2xx. */
export const CONTACT_URL = "https://bensunter.com/ripples/methods/";
export const ROBOTS_TOKEN = "ripples-research";
export const WALL_MS = 110_000;
export const ROBOTS_TTL_MS = 24 * 3600 * 1000;
export const DEFAULT_SPACING_MS = 5000; // DEMARCATION Q6: 1 request / 5 s per host where no limit is published
const KILL_CACHE_MS = 30_000;          // kill lookups are re-read at least every 30 s (and on every new Run)
const MAX_REDIRECTS = 5;

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
  // DEMARCATION §3 matrix R rows (terms bans, barriers, robots disallow) — listed so the denylist is auditable
  /(^|\.)goodreads\.com$/, /^trends\.pinterest\.com$/, /(^|\.)x\.com$/, /(^|\.)twitter\.com$/, /(^|\.)twimg\.com$/,
  /^data\.indeed\.com$/, /^files\.tmdb\.org$/, /^data\.commoncrawl\.org$/, /^itunes\.apple\.com$/,
  /^rss\.itunes\.apple\.com$/, /^api\.weather\.gov$/, /^query\.wikidata\.org$/, /(^|\.)letterboxd\.com$/,
  /(^|\.)trakt\.tv$/, /(^|\.)chess\.com$/, /(^|\.)boardgamegeek\.com$/, /(^|\.)weibo\.(com|cn)$/,
  /(^|\.)zhihu\.com$/, /(^|\.)bilibili\.com$/, /(^|\.)deezer\.com$/, /^top10\.netflix\.com$/,
  /(^|\.)newsapi\.org$/, /(^|\.)gnews\.io$/, /(^|\.)yandex\.[a-z.]+$/, /(^|\.)ya\.ru$/, /^api\.fortnite\.com$/,
];
const RED_PATH: Array<[RegExp, RegExp]> = [
  [/^(www\.)?google\.[a-z.]+$/, /^\/(complete|finance|search)/],
  [/^trends\.google\.[a-z.]+$/, /^\/(_\/|trends\/explore|trends\/api\/|trends\/embed)/], // RSS (/trending/rss) only
  [/^api\.bing\.com$/, /^\/osjson/], [/^www\.bing\.com$/, /^\/(AS|osjson)/i],
  [/^api\.gdeltproject\.org$/, /^\/api\/v2\/doc/],
  [/^api\.cloudflare\.com$/, /\/radar\//],
  [/^(www\.|m\.)?youtube\.com$/, /^\/feed\/trending/],
  [/^(public\.api\.bsky\.app|api\.bsky\.app|bsky\.social)$/, /^\/xrpc\/app\.bsky\.feed\.searchPosts/i],
  [/^(www\.)?lichess\.org$/, /^\/api\//],
  [/^(www\.)?shazam\.com$/, /^\/shazam\/v[13]/],
  [/^(www\.)?netflix\.com$/, /^\/tudum\/top10/],
  [/^[a-z-]+\.wikipedia\.org$/, /^\/w\/index\.php/],   // HTML/dynamic pages are crawling, not the API (§7.1)
];
export function isRed(u: URL): boolean {
  const h = u.hostname.toLowerCase();
  if (RED.some((r) => r.test(h))) return true;
  return RED_PATH.some(([hr, pr]) => hr.test(h) && pr.test(u.pathname));
}

// ---------------------------------------------------------------- secrets (OWNER D-5 / D-7 / D-10)
const SECRET_VALUES = new Set<string>();
const SECRET_PARAM = /((?:api_?key|apikey|registrationkey|access_token|token|key)=)[^&\s"'<>)]+/gi;
/** Read a Vault secret via public.att_secret (service_role only). null when absent. The value is never logged. */
export async function attSecret(run: Run, name: string): Promise<string | null> {
  if (run.secretMem.has(name)) return run.secretMem.get(name)!;
  const { data, error } = await db.rpc("att_secret", { p_name: name });
  if (error) { run.errors.push(`att_secret(${name}) failed`); return null; }
  const v = typeof data === "string" && data.trim() ? data.trim() : null;
  if (v) SECRET_VALUES.add(v);
  run.secretMem.set(name, v);
  return v;
}
/** Remove secret values and key-like query parameters from a string. */
export function scrubStr(s: string): string {
  let out = s;
  for (const k of SECRET_VALUES) if (k.length >= 4) out = out.split(k).join("***");
  return out.replace(SECRET_PARAM, "$1***");
}
function scrubAny(v: unknown): unknown {
  if (typeof v === "string") return scrubStr(v);
  if (Array.isArray(v)) return v.map(scrubAny);
  if (v && typeof v === "object") {
    const o: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) o[k] = scrubAny(x);
    return o;
  }
  return v;
}
/** SEC hosts (sec.gov and subdomains): the only hosts that receive the owner contact email in the User-Agent. */
export function isSecHost(h: string): boolean { return /(^|\.)sec\.gov$/i.test(h); }
const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
/**
 * User-Agent for a host: the email-free UA everywhere except sec.gov hosts, which get UA + the owner contact email read
 * from Vault at run time (SEC fair-access policy). null = SEC host but no usable contact email (the request is not made).
 */
async function uaFor(run: Run, host: string): Promise<string | null> {
  if (!isSecHost(host)) return UA;
  if (run.secUa === undefined) {
    const e = await attSecret(run, "sec_contact_email");
    run.secUa = e && EMAIL_RE.test(e) ? `ripples-research/0.2 (+${CONTACT_URL}; ${e})` : null;
  }
  return run.secUa;
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

/** Any Wikimedia-family host (quiet window, run caps). */
export function isWikimediaHost(h: string): boolean {
  return /(^|\.)(wikipedia\.org|wikidata\.org|wikimedia\.org)$/.test(h.toLowerCase());
}

/** A redirect target that is a login/visitor wall or bot challenge = DEMARCATION Q2 barrier. */
export function isBarrierUrl(u: URL): boolean {
  if (/^(login|signin|accounts?|auth|sso|id|consent|captcha|challenge)\./i.test(u.hostname)) return true;
  return /(^|\/)(login|log-in|signin|sign-in|sign_in|signup|auth|oauth2?|sso|session|captcha|challenge|consent|cdn-cgi\/challenge-platform)(\/|$|\?|\.|#)/i
    .test(u.pathname);
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
  const ua = await uaFor(run, host);
  if (!ua) return { status: 0, fetched_at: Date.now(), deny_all: true, rules: [] }; // SEC host without contact: not cached
  let entry: RobotsEntry;
  try {
    const res = await serial(host, DEFAULT_SPACING_MS, () =>
      fetch(`${origin}/robots.txt`, { headers: { "User-Agent": ua }, redirect: "manual", signal: AbortSignal.timeout(10_000) }));
    run.count(host, res.status);
    if (res.ok) {
      const txt = (await res.text()).slice(0, 512_000);
      entry = { status: res.status, fetched_at: Date.now(), deny_all: false, rules: parseRobots(txt) };
    } else if (res.status >= 300 && res.status < 400) {
      // robots.txt redirect: follow only to the same host's robots.txt (e.g. http->https, trailing slash); else deny
      const loc = res.headers.get("location");
      await res.body?.cancel();
      const next = loc ? new URL(loc, `${origin}/robots.txt`) : null;
      if (next && next.hostname.toLowerCase() === host.toLowerCase() && next.pathname === "/robots.txt" && !isRed(next)) {
        const r2 = await serial(host, DEFAULT_SPACING_MS, () =>
          fetch(next, { headers: { "User-Agent": ua }, redirect: "manual", signal: AbortSignal.timeout(10_000) }));
        run.count(host, r2.status);
        if (r2.ok) entry = { status: r2.status, fetched_at: Date.now(), deny_all: false, rules: parseRobots((await r2.text()).slice(0, 512_000)) };
        else {
          await r2.body?.cancel();
          entry = { status: r2.status, fetched_at: Date.now(), deny_all: r2.status !== 404 && r2.status !== 410, rules: [] };
          if (r2.status === 401 || r2.status === 403) await killHost(run, host, r2.status, undefined, `robots_${r2.status}`);
          else if (r2.status === 429 || r2.status === 503) await killHost(run, host, r2.status);
        }
      } else {
        entry = { status: res.status, fetched_at: Date.now(), deny_all: true, rules: [] }; // cross-host robots redirect = deny
      }
    } else if (res.status >= 400 && res.status < 500 && ![401, 403, 429].includes(res.status)) {
      await res.body?.cancel();
      entry = { status: res.status, fetched_at: Date.now(), deny_all: false, rules: [] }; // no robots.txt = allowed
    } else {
      await res.body?.cancel();
      entry = { status: res.status, fetched_at: Date.now(), deny_all: true, rules: [] }; // 401/403/429/5xx = deny
      // hard rule 3: a 401/403 (even on robots.txt) stops the host permanently; 429/503 stops it for the UTC day
      if (res.status === 401 || res.status === 403) await killHost(run, host, res.status, undefined, `robots_${res.status}`);
      else if (res.status === 429 || res.status === 503) await killHost(run, host, res.status);
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
  if (!(await hostLease(run, u.hostname.toLowerCase()))) return false;
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
const srcMem = new Map<string, SourceRow | null>(); // cleared at the start of every Run
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

/** Central per-run cap for a source or bucket: min(att_sources.per_run_cap, att_config.run_caps[bucket]). */
export async function runCap(run: Run, sourceOrBucket: string): Promise<number> {
  const s = await sourceInfo(sourceOrBucket).catch(() => null);
  const caps = [s?.per_run_cap, run.runCaps[sourceOrBucket], s?.budget_bucket ? run.runCaps[s.budget_bucket] : undefined]
    .filter((x): x is number => typeof x === "number" && Number.isFinite(x));
  return caps.length ? Math.min(...caps) : Infinity;
}

/** Budget bucket of a source: att_sources.budget_bucket, else the source id (a bare bucket name maps to itself). */
export async function bucketOf(sourceOrBucket: string): Promise<string> {
  const s = await sourceInfo(sourceOrBucket).catch(() => null);
  return s?.budget_bucket ?? sourceOrBucket;
}

/**
 * Draw one unit of a bucket's daily budget into this run. Units are taken from att_take_budget in chunks (row lock)
 * into run.pool; units left in the pool when the run finishes are refunded (att_budget_refund).
 */
async function drawUnit(run: Run, bucket: string, chunk: number): Promise<boolean> {
  if (run.budgetOut.has(bucket)) return false;
  if ((run.pool[bucket] ?? 0) <= 0) {
    const g = await takeBudget(bucket, Math.max(1, Math.floor(chunk)));
    run.granted += g;
    if (g <= 0) { run.budgetOut.add(bucket); run.partial = true; return false; }
    run.pool[bucket] = (run.pool[bucket] ?? 0) + g;
  }
  run.pool[bucket]--;
  return true;
}

/**
 * Per-day budget charged INSIDE politeFetch for every request (hard rule: per_day_cap cannot be bypassed). A unit
 * reserved earlier by budget().take() for the same bucket is used first, so collectors that also call budget() are
 * not charged twice.
 */
async function chargeRequest(run: Run, bucket: string, chunk: number): Promise<boolean> {
  if ((run.reserved[bucket] ?? 0) > 0) { run.reserved[bucket]--; return true; }
  return await drawUnit(run, bucket, chunk);
}

/**
 * Optional look-ahead budget: await b.take() before a request reserves one unit of the day's budget for the next
 * politeFetch in that bucket; false means the day's budget (or this run's cap) is spent, so stop early. politeFetch
 * charges the budget itself in any case. The per-run cap is always enforced centrally (att_sources.per_run_cap /
 * att_config.run_caps); a caller-supplied perRunCap can only lower it.
 */
export function budget(run: Run, bucketOrSource: string, chunk = 25, perRunCap = Infinity) {
  let used = 0;
  let cap: number | null = null;
  let bucket: string | null = null;
  return {
    async take(): Promise<boolean> {
      if (bucket === null) bucket = await bucketOf(bucketOrSource);
      if (cap === null) cap = Math.min(perRunCap, await runCap(run, bucketOrSource), await runCap(run, bucket));
      if (used >= cap) { run.partial = true; return false; }
      if (!(await drawUnit(run, bucket, Math.min(chunk, cap - used)))) return false;
      run.reserved[bucket] = (run.reserved[bucket] ?? 0) + 1;
      used++;
      return true;
    },
    get used() { return used; },
  };
}

// ---------------------------------------------------------------- kill switch
// Module cache of kill lookups with a short TTL; cleared at the start of every Run so a warm isolate always re-reads
// kills written by other invocations.
const killMem = new Map<string, { v: string | null; at: number }>();
export async function hostKilled(run: Run, host: string): Promise<string | null> {
  host = host.toLowerCase();
  if (run.killed.has(host)) return run.killed.get(host)!;
  const m = killMem.get(host);
  if (m && Date.now() - m.at < KILL_CACHE_MS) return m.v;
  const k = await stateGet(`kill:${host}`) as { status: number; until?: string | null; permanent?: boolean } | null;
  const v = k && (k.permanent === true || (k.until != null && Date.parse(k.until) > Date.now()))
    ? `host_killed_${k.status}${k.permanent ? "_permanent" : ""}` : null;
  killMem.set(host, { v, at: Date.now() });
  return v;
}
/**
 * 429/503: stop the host until the next UTC midnight, spend the source's budget, halve tomorrow's cap.
 * 401/403 or a redirect to a login/visitor wall/challenge (reason set): PERMANENT kill until the owner reviews it
 * (hard rule 3 "no retry after 403"; DEMARCATION Q2). Never retried anonymously.
 */
export async function killHost(run: Run, host: string, status: number, source?: string, barrier?: string) {
  host = host.toLowerCase();
  const perm = status === 401 || status === 403 || !!barrier;
  const reason = `host_killed_${status}${perm ? "_permanent" : ""}`;
  run.killed.set(host, reason);
  killMem.set(host, { v: reason, at: Date.now() });
  run.partial = true;
  run.skip(host, barrier ? `${reason}:${barrier}` : reason);
  const { error } = await db.rpc("att_host_kill", { p_host: host, p_status: status, p_source: source ?? null, p_reason: barrier ?? null });
  if (error) run.errors.push(`att_host_kill: ${error.message}`);
}

// ---------------------------------------------------------------- cross-isolate host lease
/**
 * One run per host at a time across every att-* invocation (the serial() queue is per isolate). The lease is held
 * until the run finishes (released in Run.finish) or expires (wall + 15 s). A busy host is skipped for this run.
 */
export async function hostLease(run: Run, host: string): Promise<boolean> {
  host = host.toLowerCase();
  if (run.leases.has(host)) return true;
  if (run.killed.has(host)) return false;
  const ttl = Math.ceil((Math.max(0, run.timeLeft()) + 15_000) / 1000);
  const { data, error } = await db.rpc("att_host_lease_take", { p_host: host, p_run: run.leaseId, p_fn: run.fn, p_ttl_s: ttl });
  if (error || data !== true) {
    const why = error ? "host_lease_error" : "host_busy";
    run.killed.set(host, why); // not a kill: just "do not use this host in this run"
    run.skip(host, why);
    run.partial = true;
    if (error) run.errors.push(`att_host_lease_take: ${error.message}`);
    return false;
  }
  run.leases.add(host);
  return true;
}

// ---------------------------------------------------------------- polite fetch
export interface FetchOpts extends RequestInit {
  source: string;         // REQUIRED att_sources id: enabled check, host check, spacing floor, per-run cap, per-day budget, kill attribution
  robots?: boolean;       // true forces a robots check; false is ignored except on Wikimedia documented APIs
  spacingMs?: number;     // can only RAISE the source's spacing_ms floor (default floor 5000, DEMARCATION Q6)
  timeoutMs?: number;     // default 30 s, capped by the run's remaining wall time
  aqsRetry?: boolean;     // Wikimedia AQS only: at most ONE retry after 5 s on a 429 per run (lead decision §7.3)
}

/** Host h is h0 or a subdomain of h0. */
function hostIn(h: string, list: string[]): boolean {
  h = h.toLowerCase();
  return list.some((x) => { x = x.toLowerCase(); return h === x || h.endsWith("." + x); });
}

/** Headers that must not follow a request to another origin (credentials for keyed sources). */
const SENSITIVE_HEADER = /^(authorization|proxy-authorization|cookie|x-api-key|api-key|apikey|x-auth-token|x-access-token|x-goog-api-key|ocp-apim-subscription-key)$|(key|token|secret|auth|signature)/i;

// ---------------------------------------------------------------- UA contact gate (§7.1 "UA that includes a contact")
interface ContactState { ok: boolean; status: number; checked_at: number }
async function contactOk(run: Run): Promise<boolean> {
  const g = run.contactGate;
  if (!g) return true;
  if (run.contactVerdict !== null) return run.contactVerdict;
  const k = "contact:ua";
  const cached = await stateGet(k).catch(() => null) as ContactState | null;
  const ttl = (cached?.ok ? g.ttl_ok_h : g.ttl_fail_h) * 3600_000;
  if (cached && Date.now() - cached.checked_at < ttl) { run.contactVerdict = cached.ok; return cached.ok; }
  let status = 0;
  try {
    let u = new URL(g.url);
    for (let hop = 0; hop < 4; hop++) {
      const target = u;
      const res = await serial(u.hostname.toLowerCase(), DEFAULT_SPACING_MS, () =>
        fetch(target, { headers: { "User-Agent": UA }, redirect: "manual", signal: AbortSignal.timeout(10_000) }));
      run.count(u.hostname.toLowerCase(), res.status);
      status = res.status;
      await res.body?.cancel();
      if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
        const next = new URL(res.headers.get("location")!, u);
        if (next.hostname.toLowerCase() !== u.hostname.toLowerCase() && !next.hostname.toLowerCase().endsWith("bensunter.com")) break;
        u = next;
        continue;
      }
      break;
    }
  } catch (_e) { status = 0; }
  const ok = status >= 200 && status < 300;
  await stateSet(k, { ok, status, checked_at: Date.now(), url: g.url }).catch(() => undefined);
  run.contactVerdict = ok;
  return ok;
}

function inQuietWindow(run: Run, host: string): boolean {
  const q = run.quiet;
  if (!q || !isWikimediaHost(host)) return false;
  const now = new Date();
  const hm = now.toISOString().slice(11, 16);
  return hm >= q.from && hm < q.to;
}

/** Every check that must pass before a request to u (also re-run on every redirect hop). null = go. */
async function preflight(run: Run, u: URL, o: FetchOpts, src: SourceRow): Promise<string | null> {
  const host = u.hostname.toLowerCase();
  if (u.protocol !== "https:" && u.protocol !== "http:") return "bad_scheme";
  if (isRed(u)) return "red_source";
  const killed = await hostKilled(run, host);
  if (killed) return killed;
  if (inQuietWindow(run, host)) return "wm_quiet_window";
  const g = run.contactGate;
  if (g && (g.scope === "all" || isWikimediaHost(host)) && !(await contactOk(run))) return "ua_contact_unreachable";
  if (!(await hostLease(run, host))) return run.killed.get(host) ?? "host_busy";
  const wm = isWikimediaApi(u);
  // robots: always for non-Wikimedia-API URLs; for Wikimedia APIs only if the source requires it or the caller forces it
  const needRobots = !wm || o.robots === true || src.robots_required === true;
  if (needRobots && !(await robotsAllowed(run, u))) return "robots_disallow";
  return null;
}

/**
 * The only way collectors should make outbound requests. Returns null when the request was not made or must not be
 * used (RED, disabled source, per-run cap, quiet window, host busy/killed, robots disallow, out of time,
 * 401/403/429/503, redirect to a barrier, network error); the reason is recorded in run.
 * Redirects are never followed blindly: each hop is re-checked (RED, kill, lease, robots) and a hop to a login wall or
 * challenge is treated as a barrier (permanent kill of the redirecting host).
 */
export async function politeFetch(run: Run, url: string, o: FetchOpts): Promise<Response | null> {
  let u: URL;
  try { u = new URL(url); } catch { run.errors.push(`bad url ${url}`); return null; }
  // every request is attributed to a registered, enabled source whose hosts include the URL's host
  const source = typeof o?.source === "string" ? o.source : "";
  if (!source) { run.skip(u.hostname, "source_required"); run.errors.push(`politeFetch without source: ${u.hostname}`); return null; }
  const src = await sourceInfo(source);
  if (!src) { run.skip(u.hostname, `unknown_source:${source}`); run.errors.push(`unknown source ${source}`); return null; }
  if (!src.enabled) { run.skip(u.hostname, `source_disabled:${source}`); return null; }
  if (Array.isArray(src.hosts) && src.hosts.length && !hostIn(u.hostname, src.hosts)) {
    run.skip(u.hostname, `host_not_in_source:${source}`); return null;
  }
  const bucket = src.budget_bucket ?? src.source;
  // central per-run cap (source row per_run_cap and att_config.run_caps for the source or its bucket)
  const cap = await runCap(run, source);
  // spacing: the source's configured floor; a caller can only make it slower
  const floor = typeof src.spacing_ms === "number" && Number.isFinite(src.spacing_ms) ? src.spacing_ms : DEFAULT_SPACING_MS;
  const spacing = Math.max(Number.isFinite(o.spacingMs as number) ? (o.spacingMs as number) : 0, floor);
  const headers = new Headers(o.headers ?? {});
  headers.set("User-Agent", UA);
  headers.delete("cookie");
  let method = (o.method ?? "GET").toUpperCase();
  let body = o.body;
  let hops = 0;
  while (true) {
    const host = u.hostname.toLowerCase();
    const wm = isWikimediaApi(u);
    if (wm && u.pathname.startsWith("/w/api.php") && !u.searchParams.has("maxlag")) u.searchParams.set("maxlag", "5");
    // per hop: the contact email goes only to sec.gov hosts; any other host (incl. a redirect off SEC) gets the plain UA
    const ua = await uaFor(run, host);
    if (!ua) { run.skip(host, "sec_contact_missing"); return null; }
    headers.set("User-Agent", ua);
    const why = await preflight(run, u, o, src);
    if (why) { run.skip(host, why); return null; }
    if (wm) headers.set("Api-User-Agent", ua); else headers.delete("Api-User-Agent");
    const remaining = run.timeLeft() - 1500;
    if (remaining <= 0) { run.partial = true; return null; }
    // per-run cap and per-day budget are charged for EVERY request made (redirect hops and the AQS retry included)
    const n = run.reqBySource[source] ?? 0;
    if (n >= cap) { run.partial = true; run.skip(host, `per_run_cap:${source}`); return null; }
    if (!(await chargeRequest(run, bucket, Math.min(25, Math.max(1, cap - n))))) {
      run.partial = true; run.skip(host, `daily_budget_spent:${bucket}`); return null;
    }
    const timeout = Math.min(o.timeoutMs ?? 30_000, remaining);
    let res: Response;
    try {
      const target = u;
      res = await serial(host, spacing, () =>
        fetch(target, { ...o, method, body, headers, redirect: "manual", signal: AbortSignal.timeout(timeout) }));
    } catch (e) {
      run.count(host, 0);
      run.errors.push(`${host}: ${errMsg(e)}`);
      return null;
    }
    run.count(host, res.status);
    run.reqBySource[source] = (run.reqBySource[source] ?? 0) + 1;
    if (res.status >= 300 && res.status < 400 && res.status !== 304) {
      const loc = res.headers.get("location");
      await res.body?.cancel();
      if (!loc) { run.errors.push(`${host}: ${res.status} without location`); return null; }
      let next: URL;
      try { next = new URL(loc, u); } catch { run.errors.push(`${host}: bad redirect`); return null; }
      if (isBarrierUrl(next)) { await killHost(run, host, res.status, source, "redirect_to_barrier"); return null; }
      if (++hops > MAX_REDIRECTS) { run.skip(host, "too_many_redirects"); run.partial = true; return null; }
      if (u.protocol === "https:" && next.protocol !== "https:") { run.skip(host, "insecure_redirect"); return null; }
      if (res.status === 303 || ((res.status === 301 || res.status === 302) && method === "POST")) { method = "GET"; body = undefined; }
      if (next.origin !== u.origin) {
        // never forward credentials to another origin
        for (const k of [...headers.keys()]) if (k !== "user-agent" && SENSITIVE_HEADER.test(k)) headers.delete(k);
      }
      u = next;
      continue; // re-run preflight (RED, kill, lease, robots) on the new URL
    }
    if (res.status === 429 && o.aqsRetry && host === "wikimedia.org" && !run.aqsRetried) {
      await res.body?.cancel();
      run.aqsRetried = true; // §7.3: one retry after 5 s, once per run; the next 429 stops the host
      await sleep(5000);
      continue;
    }
    if (res.status === 429 || res.status === 503 || res.status === 403 || res.status === 401) {
      await res.body?.cancel();
      await killHost(run, host, res.status, source);
      return null;
    }
    return res;
  }
}

/** MediaWiki Action API JSON (maxlag=5 added automatically). A maxlag/ratelimit error stops the host for this run. */
export async function wikiApiJson(run: Run, url: string, source = "wikidata.api"): Promise<any | null> {
  // Serial requests (API:Etiquette) at >= 1.1 s; robots exemption applies automatically to /w/api.php (§7.1).
  const res = await politeFetch(run, url, { source, spacingMs: 1100 });
  if (!res) return null;
  if (!res.ok) { await res.body?.cancel(); run.errors.push(`${new URL(url).hostname} http ${res.status}`); return null; }
  const j = await res.json().catch(() => null);
  const code = j?.error?.code;
  if (code === "maxlag" || code === "ratelimited") {
    run.killed.set(new URL(url).hostname.toLowerCase(), `wikimedia_${code}`);
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
  killed = new Map<string, string>();   // hosts not to use for the rest of this run (kills, busy leases)
  leases = new Set<string>();           // hosts this run holds a lease on (released in finish)
  leaseId: number;
  reqBySource: Record<string, number> = {};
  runCaps: Record<string, number> = {};
  pool: Record<string, number> = {};      // budget units taken from att_take_budget, not yet spent (refunded in finish)
  reserved: Record<string, number> = {};  // units handed out by budget().take(), consumed by the next politeFetch
  budgetOut = new Set<string>();          // buckets whose daily budget is spent
  aqsRetried = false;                     // §7.3 AQS 429 retry used (once per run)
  contactGate: { url: string; scope: string; ttl_ok_h: number; ttl_fail_h: number } | null = null;
  contactVerdict: boolean | null = null;
  quiet: { from: string; to: string } | null = null;
  secretMem = new Map<string, string | null>(); // Vault secrets read this run (values never persisted)
  secUa: string | null | undefined = undefined; // UA with the SEC contact email (sec.gov hosts only); null = unavailable
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
    this.leaseId = -Math.floor(1 + Math.random() * 1e12); // replaced by run_id once att_run_start returns
    // a warm isolate must not reuse kill/source lookups from an earlier invocation
    killMem.clear();
    srcMem.clear();
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
    if (!error) { this.runId = Number(data); this.leaseId = this.runId; }
    try {
      const rc = await configGet("run_caps");
      if (rc && typeof rc === "object") this.runCaps = rc as Record<string, number>;
      const q = await configGet("wm_quiet_utc") as { from?: string; to?: string } | null;
      if (q?.from && q?.to) this.quiet = { from: q.from, to: q.to };
      const cg = await configGet("contact_gate") as { enabled?: boolean; url?: string; scope?: string; ttl_ok_h?: number; ttl_fail_h?: number } | null;
      this.contactGate = cg?.enabled === false ? null : {
        url: cg?.url ?? CONTACT_URL, scope: cg?.scope ?? "wikimedia",
        ttl_ok_h: Number(cg?.ttl_ok_h ?? 24), ttl_fail_h: Number(cg?.ttl_fail_h ?? 1),
      };
    } catch (e) {
      this.errors.push(`config: ${errMsg(e)}`);
      this.quiet = { from: "06:30", to: "07:20" }; // fail safe
      this.contactGate = { url: CONTACT_URL, scope: "wikimedia", ttl_ok_h: 24, ttl_fail_h: 1 };
    }
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
  /** Remove key material from everything finish() persists or returns. */
  scrub() {
    this.errors = this.errors.map(scrubStr);
    this.skipped = this.skipped.map((s) => ({ host: scrubStr(s.host), reason: scrubStr(s.reason) }));
    this.extra = scrubAny(this.extra) as Record<string, unknown>;
    this.sources = scrubAny(this.sources) as SourceReport[];
    this.rejected = scrubAny(this.rejected) as unknown[];
    this.nextCursor = scrubAny(this.nextCursor);
    if (this.dryRows.length) this.dryRows = scrubAny(this.dryRows) as unknown[];
  }
  async finish() {
    // give back budget units taken in a chunk (or reserved by budget().take()) but never spent on a request
    for (const b of new Set([...Object.keys(this.pool), ...Object.keys(this.reserved)])) {
      const left = (this.pool[b] ?? 0) + (this.reserved[b] ?? 0);
      if (left > 0) {
        const { error } = await db.rpc("att_budget_refund", { p_bucket: b, p_n: left });
        if (error) this.errors.push(`att_budget_refund: ${error.message}`); else this.granted -= left;
        this.pool[b] = 0;
      }
      this.reserved[b] = 0;
    }
    if (this.leases.size) {
      const { error } = await db.rpc("att_host_lease_release", { p_run: this.leaseId });
      if (error) this.errors.push(`att_host_lease_release: ${error.message}`);
      this.leases.clear();
    }
    this.scrub();
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
