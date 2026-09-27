// att-charts — Ripples v5 attention layer, CHARTS / BUILDER / CONSUMPTION collector (W7).
// Spec: ATTENTION_STACK §1 (#8, #9, #10, #20, #27-29, #32, #35), §3.3 (att-charts row), §3.4 (cron), §3.6 (backfill),
// §4 (discovery candidates), §6.5 (rank-list evidence). Budgets: DEMARCATION Q6 as seeded in att_sources (they override
// §3.5: e.g. Apple 1 req / 5 s, not 3 s). Every HTTP request goes through politeFetch (registered source, RED list,
// kill switch, host lease, robots.txt, spacing floor, per-run cap, per-day budget).
//
// Modes (body.mode):
//   apple        Apple Marketing Tools RSS: apps top-free / top-paid, music most-played songs, podcasts top, books
//                top-free x us, gb, in, br, jp (25 feeds). Resumable across runs (att_state 'charts.apple'), because 25
//                feeds at the 5 s floor do not fit one 110 s run. Rank series per item (metric = feed, geo = storefront).
//   steamspy     SteamSpy top100in2weeks (1 request): yesterday's peak CCU per appid (metric 'ccu', aux = rank).
//   github       GitHub search: repos created in the last 7 days by stars (gh.search 'new7d' rank + 'stars' level,
//                keyed by numeric repo id; owner handles are never stored), and stargazers_count for registered repos
//                (gh.stars 'total', with 'n' = stars gained when yesterday's total exists). Authenticated with the
//                read-only PAT (Vault 'github_token', read at run time) sent ONLY to api.github.com; budgets stay under
//                the authenticated limits (search 25/min of 30, core ~4000/h of 5000; spacing in att_sources).
//   hf           Hugging Face trending models / spaces / datasets (sort=trendingScore): rank, aux = trendingScore,
//                keyed by the opaque Hub object id.
//   anilist      AniList GraphQL: TRENDING_DESC lists for anime and manga (isAdult:false; rank, aux = trending) and the
//                per-media daily `mediaTrends` for registered titles and today's top trending titles (metric 'n' =
//                daily trending activity, aux = popularity).
//   openlibrary  Open Library trending/daily (rank).
//   tranco       Tranco daily top-1M zip (list download only; /api is disallowed): streamed through a zip local-header
//                parser + DecompressionStream('deflate-raw'); keeps ranks only for registered domains and the top-1k
//                movers (new to the top 1k, or a rank jump >= max(20, 25%)) against the previous top-1k, which att_state keeps
//                only as one-way 12-hex SHA-256 digests in rank order (no readable domain list is stored).
//   npm          npm downloads: bulk range (<= 128 unscoped packages per call; scoped packages one by one) for the last
//                30 days (charts.npm.days) for registered + reference packages, the all-packages '__total__' normaliser
//                (its outage days listed in att_state 'charts.npm.gaps'), and a 400-day single-package backfill for any
//                key without history.
//   pypi         pypistats overall?mirrors=false (180 days per call) for registered + reference packages.
//   backfill     Merged backfill jobs from att_tick: params.source in npm.dl | pypi.dl | anilist | gh.stars.
//   ping         No outbound requests.
// Discovery (§4 step 1): rank-list evidence e = 1 - ln(rank)/ln(N+1). Level charts (apple, steamspy, tranco) emit
// 'new' entries and rank 'jump's >= 20 against the previous snapshot; velocity lists (github new repos, hf trending,
// anilist trending, openlibrary trending) also emit their top 10 ('top'). Candidate labels are item names only.
// Only ranks, counts and indices are stored; no descriptions, artwork, authors' handles or personal data.
import {
  addDays, ATT_VERSION, attSecret, configGet, db, errMsg, type FetchOpts, ingest, ingestCandidates, type ObsRow,
  politeFetch, type Run, serve, sleep, sourceInfo, stateGet, stateSet, watchlist, type WatchKey,
} from "./att.ts";

const FN = "att-charts";
export const CHARTS_VERSION = "2026-09-25.c10";

// ------------------------------------------------------------------ helpers
type Cfg = Record<string, any>;
interface Ctx { cfg: Cfg; pro: boolean }
async function ctx(): Promise<Ctx> {
  let cfg: Cfg = {};
  let pro = false;
  try { cfg = ((await configGet("charts")) ?? {}) as Cfg; } catch { /* defaults below */ }
  try { pro = (await configGet("profile")) === "pro"; } catch { /* free */ }
  return { cfg, pro };
}
function lim(c: Ctx, x: any, dflt: number): number {
  const v = Number(c.pro ? x?.pro : x?.free);
  return Number.isFinite(v) && v > 0 ? Math.floor(v) : dflt;
}
const unixDay = (d: string) => Math.floor(Date.parse(d + "T00:00:00Z") / 1000);
const dayOfUnix = (s: number) => new Date(s * 1000).toISOString().slice(0, 10);

/**
 * Pacing on top of politeFetch: att.ts already enforces a start-to-start gap >= att_sources.spacing_ms per host; this
 * collector additionally waits spacing_ms from the END of the previous response on the same host before the next call
 * (end-to-start, stricter), and records the smallest idle gap per source as evidence ("spacing respected").
 */
const pace = new WeakMap<Run, Map<string, number>>();
async function paceWait(run: Run, source: string, host: string): Promise<number | null> {
  const m = pace.get(run) ?? new Map<string, number>();
  pace.set(run, m);
  const s = await sourceInfo(source).catch(() => null);
  const sp = typeof s?.spacing_ms === "number" ? s.spacing_ms : 5000;
  const last = m.get(host);
  if (last !== undefined) {
    const wait = last + sp - Date.now();
    if (wait > 0) {
      if (run.timeLeft() - wait < 5000) { run.partial = true; return null; } // no time left to wait: stop, never rush
      await sleep(wait);
    }
  }
  return sp;
}
function paceDone(run: Run, source: string, host: string, tStart: number, sp: number) {
  const m = pace.get(run)!;
  const last = m.get(host);
  const tm = ((run.extra.timing ??= {}) as Record<string, { n: number; spacing_ms: number; min_idle_gap_ms: number | null }>);
  const e = (tm[source] ??= { n: 0, spacing_ms: sp, min_idle_gap_ms: null });
  if (last !== undefined) {
    const gap = tStart - last;
    e.min_idle_gap_ms = e.min_idle_gap_ms === null ? gap : Math.min(e.min_idle_gap_ms, gap);
  }
  e.n++;
  m.set(host, Date.now());
}

/** JSON through politeFetch. soft: a 404/410 is a note (unknown package), not a run error. */
async function getJson(run: Run, url: string, o: FetchOpts & { soft?: boolean }): Promise<any | null> {
  const host = new URL(url).hostname.toLowerCase();
  const sp = await paceWait(run, o.source, host);
  if (sp === null) return null;
  const headers: Record<string, string> = { Accept: "application/json", ...(o.headers as Record<string, string> ?? {}) };
  // GitHub PAT: only for https://api.github.com (politeFetch also strips Authorization on any cross-origin redirect)
  if (host === GH && new URL(url).protocol === "https:") {
    const tok = await attSecret(run, "github_token");
    if (tok) headers.Authorization = `Bearer ${tok}`;
  }
  const tStart = Date.now();
  const res = await politeFetch(run, url, { timeoutMs: 30_000, ...o, headers });
  if (!res) return null;
  // stay below published rate limits: when the provider's remaining quota reaches the reserve, stop using the host
  // for this run (GitHub reports an exhausted limit as 403, which att.ts treats as a permanent kill, so never reach it)
  const rem = res.headers.get("x-ratelimit-remaining");
  const rlLimit = Number(res.headers.get("x-ratelimit-limit") ?? NaN);
  if (host === GH) {
    const gr = ((run.extra.gh_rate ??= {}) as Record<string, unknown>);
    gr[res.headers.get("x-ratelimit-resource") ?? "?"] = { limit: Number.isFinite(rlLimit) ? rlLimit : null, remaining: rem === null ? null : Number(rem),
      authenticated: "Authorization" in headers };
  }
  const reserve = Number.isFinite(rlLimit) && rlLimit >= 1000 ? 100 : 1;
  if (rem !== null && rem !== "" && Number(rem) <= reserve) {
    run.killed.set(host, "ratelimit_reserve");
    run.skip(host, "ratelimit_reserve");
    run.partial = true;
  }
  if (!res.ok) {
    await res.body?.cancel();
    paceDone(run, o.source, host, tStart, sp);
    const msg = `${o.source} ${new URL(url).pathname.slice(0, 80)}: http ${res.status}`;
    if (o.soft && (res.status === 404 || res.status === 410)) note(run, msg); else run.errors.push(msg);
    return null;
  }
  try { return await res.json(); } catch (e) { run.errors.push(`${o.source}: bad json ${errMsg(e)}`); return null; }
  finally { paceDone(run, o.source, host, tStart, sp); }
}
function note(run: Run, s: string) {
  const n = ((run.extra.notes ??= []) as string[]);
  if (n.length < 30) n.push(s);
}
/** true when the source cannot make more requests in this run (per-run cap, budget, kill, lease, robots). */
function blocked(run: Run, host: string): boolean {
  return run.killed.has(host) || run.skipped.some((s) => s.host === host &&
    /^(per_run_cap|daily_budget_spent|robots_disallow|host_killed|host_busy|source_disabled|red_source|ratelimit_reserve|ua_contact)/.test(s.reason));
}

// ------------------------------------------------------------------ discovery candidates (§4 / §6.5)
interface Item { key: string; label: string; rank: number; score?: number | null; farm?: boolean }
interface Cand {
  day: string; source: string; geo: string; label: string; rank: number; value: number | null; evidence: number;
  meta: Record<string, unknown>;
}
const rankEvidence = (rank: number, n: number) =>
  Math.round(Math.max(0, Math.min(1, 1 - Math.log(rank) / Math.log(n + 1))) * 10000) / 10000;

/**
 * prevRank: key -> rank on the previous snapshot of this (metric, geo), or null when no earlier snapshot exists
 * (first collection day: level charts emit nothing; velocity lists still emit their top K).
 */
function discover(run: Run, source: string, geo: string, list: string, items: Item[], prevRank: Map<string, number> | null,
                  o: { velocity: boolean; topK: number; jumpMin: number }): Cand[] {
  const out: Cand[] = [];
  const n = items.length;
  for (const it of items) {
    const label = (it.label ?? "").replace(/\s+/g, " ").trim().slice(0, 200);
    if (!label) continue;
    let kind: string | null = null;
    let rankPrev: number | null = null;
    if (prevRank) {
      const p = prevRank.get(it.key);
      if (p === undefined) kind = "new";
      else if (p - it.rank >= o.jumpMin) { kind = "jump"; rankPrev = p; }
    }
    if (!kind && o.velocity && it.rank <= o.topK) kind = "top";
    if (!kind) continue;
    let e = rankEvidence(it.rank, n);
    if (it.farm) e = Math.round(e * 5000) / 10000; // star-farm guard (§8): stars/forks > 50 halves the evidence
    const meta: Record<string, unknown> = { kind, list };
    if (rankPrev !== null) meta.rank_prev = rankPrev;
    if (it.score !== undefined && it.score !== null && Number.isFinite(it.score)) meta.score = it.score;
    out.push({ day: run.asOf, source, geo, label, rank: it.rank, value: it.score ?? null, evidence: e, meta });
    if (kind === "new") run.extra.new_entries = Number(run.extra.new_entries ?? 0) + 1;
    if (kind === "jump") run.extra.rank_jumps = Number(run.extra.rank_jumps ?? 0) + 1;
  }
  return out;
}

interface PrevRow { metric: string; geo: string; key: string; day: string; value: number; aux: number | null }
async function prevSnap(run: Run, source: string, metrics: string[] | null, lookback = 7): Promise<PrevRow[]> {
  const { data, error } = await db.rpc("att_charts_prev",
    { p_source: source, p_day: run.asOf, p_metrics: metrics, p_lookback: lookback });
  if (error) { run.errors.push(`att_charts_prev: ${error.message}`); return []; }
  return (data ?? []) as PrevRow[];
}
/** Map (metric|geo) -> key -> rank from a previous snapshot; rankOf picks value or aux. */
function prevRanks(rows: PrevRow[], rankOf: (r: PrevRow) => number | null): Map<string, Map<string, number>> {
  const m = new Map<string, Map<string, number>>();
  for (const r of rows) {
    const rk = rankOf(r);
    if (rk === null || !Number.isFinite(rk)) continue;
    const k = `${r.metric}|${r.geo}`;
    if (!m.has(k)) m.set(k, new Map());
    m.get(k)!.set(r.key, rk);
  }
  return m;
}
async function seriesInfo(run: Run, source: string, metric: string, keys: string[]) {
  const out = new Map<string, number>();
  if (!keys.length) return out;
  const { data, error } = await db.rpc("att_charts_series_info", { p_source: source, p_metric: metric, p_keys: keys });
  if (error) { run.errors.push(`att_charts_series_info: ${error.message}`); return out; }
  for (const r of (data ?? []) as Array<{ key: string; n_days: number }>) out.set(r.key, Math.max(out.get(r.key) ?? 0, r.n_days));
  return out;
}
/** First stored day per key (null = no rows). Coverage is judged by span, not by row count: series that drop
 *  uncomputed zero days (npm '__total__') never reach a row-count threshold. */
async function seriesFirst(run: Run, source: string, metric: string, keys: string[]) {
  const out = new Map<string, string | null>();
  if (!keys.length) return out;
  const { data, error } = await db.rpc("att_charts_series_info", { p_source: source, p_metric: metric, p_keys: keys });
  if (error) { run.errors.push(`att_charts_series_info: ${error.message}`); return out; }
  for (const r of (data ?? []) as Array<{ key: string; first_day: string | null }>) {
    const cur = out.get(r.key);
    if (r.first_day && (!cur || r.first_day < cur)) out.set(r.key, r.first_day);
    else if (cur === undefined) out.set(r.key, r.first_day ?? null);
  }
  return out;
}
/**
 * Snapshot lists (one rank list per metric/geo per as_of day): after a successful re-run on the same as_of day, rows
 * written by an earlier run for items that have since dropped off the list are removed, so a day holds exactly one
 * list (no duplicate ranks). keep = every key of the current list; an empty list never prunes.
 */
async function pruneList(run: Run, source: string, metric: string, geo: string, keep: string[]) {
  if (run.dryRun || !keep.length) return 0;
  const { data, error } = await db.rpc("att_charts_prune",
    { p_source: source, p_day: run.asOf, p_metric: metric, p_geo: geo, p_keep: keep });
  if (error) { run.errors.push(`att_charts_prune: ${error.message}`); return 0; }
  const n = Number(data ?? 0);
  if (n > 0) { run.extra.pruned = Number(run.extra.pruned ?? 0) + n; note(run, `${source} ${metric}/${geo}: pruned ${n} stale same-day rows`); }
  return n;
}
/** One candidate per (day, source, geo, label) per run: the same item on two lists (e.g. an HF model and a space, or
 *  an AniList anime and its manga) keeps the higher evidence instead of the later list overwriting it. */
const candSeen = new WeakMap<Run, Map<string, number>>();
async function writeCands(run: Run, all: Cand[]) {
  const seen = candSeen.get(run) ?? new Map<string, number>();
  candSeen.set(run, seen);
  const cands: Cand[] = [];
  for (const c of all) {
    const k = `${c.day}|${c.source}|${c.geo}|${c.label}`;
    const prev = seen.get(k);
    if (prev !== undefined && prev >= c.evidence) continue;
    seen.set(k, c.evidence);
    cands.push(c);
  }
  if (!cands.length) return;
  const r = await ingestCandidates(run, cands as unknown as Record<string, unknown>[]);
  run.extra.candidates = Number(run.extra.candidates ?? 0) + (r.rows ?? 0);
}

// ------------------------------------------------------------------ apple (apple.rss)
// Apple's current feed host. The legacy rss.applemarketingtools.com 301-redirects everything (robots.txt included) to it,
// and att.ts treats a cross-host robots.txt redirect as a deny, so the canonical host is used directly. Overridable via
// att_config charts.apple.host (must be one of att_sources['apple.rss'].hosts, which politeFetch enforces anyway).
const APPLE_HOSTS = ["rss.marketingtools.apple.com", "rss.applemarketingtools.com"];
async function modeApple(run: Run) {
  const t0 = Date.now();
  const c = await ctx();
  const ac = c.cfg.apple ?? {};
  const APPLE_HOST: string = APPLE_HOSTS.includes(ac.host) ? ac.host : APPLE_HOSTS[0];
  const geos: string[] = run.params.geos ?? ac.geos ?? ["us", "gb", "in", "br", "jp"];
  const allFeeds: Array<{ code: string; path: string; type: string }> = ac.feeds ?? [];
  const feeds = Array.isArray(run.params.feeds) ? allFeeds.filter((f) => run.params.feeds.includes(f.code)) : allFeeds;
  const n = lim(c, ac.limit, 50);
  const dc = c.cfg.discovery ?? {};
  const st = ((await stateGet("charts.apple")) ?? {}) as { day?: string; done?: string[]; tries?: Record<string, number> };
  const done = new Set<string>(st.day === run.asOf ? st.done ?? [] : []);
  const tries: Record<string, number> = st.day === run.asOf ? { ...(st.tries ?? {}) } : {};
  const maxTries = Number(ac.max_tries ?? 2);
  const save = async () => { if (!run.dryRun) await stateSet("charts.apple", { day: run.asOf, done: [...done], tries }); };
  const prev = prevRanks(await prevSnap(run, "apple.rss", feeds.map((f) => f.code)), (r) => r.value);
  let rows = 0, fed = 0, cands = 0, failStreak = 0;
  const todo = geos.flatMap((g) => feeds.map((f) => ({ g, f })));
  for (const { g, f } of todo) {
    const id = `${g}/${f.code}`;
    if (done.has(id)) continue;
    if (run.outOfTime(9000) || blocked(run, APPLE_HOST)) { run.partial = true; break; }
    // two failures in a row (5xx / timeout) = the feed service is struggling: leave it alone for the rest of this run
    if (failStreak >= 2) { run.partial = true; run.skip(APPLE_HOST, "server_errors_backoff"); break; }
    const url = `https://${APPLE_HOST}/api/v2/${g}/${f.path}/${n}/${f.type}.json`;
    const errsBefore = run.errors.length;
    const j = await getJson(run, url, { source: "apple.rss", soft: true, timeoutMs: 45_000 });
    if (!j) {
      if (blocked(run, APPLE_HOST)) { run.partial = true; break; }
      if (run.outOfTime(9000)) { run.partial = true; break; }
      // 404 (feed not offered in this storefront): done for the day. Network error / timeout: retried by a later run
      // (not a 429/503/403, so not a retry storm), at most charts.apple.max_tries attempts per feed per day.
      const transient = run.errors.length > errsBefore;
      if (transient) failStreak++;
      tries[id] = (tries[id] ?? 0) + 1;
      if (!transient || tries[id] >= maxTries) { done.add(id); note(run, `apple ${id}: no data (${transient ? "gave up after " + tries[id] + " tries" : "not offered"})`); }
      else note(run, `apple ${id}: transient failure, retry next run`);
      await save();
      continue;
    }
    const results: any[] = Array.isArray(j?.feed?.results) ? j.feed.results : [];
    const geo = g.toUpperCase();
    const items: Item[] = results.slice(0, n).map((r, i) => ({ key: String(r?.id ?? ""), label: String(r?.name ?? ""), rank: i + 1 }))
      .filter((x) => /^\d+$/.test(x.key));
    const obs: ObsRow[] = items.map((x) => ({ source: "apple.rss", metric: f.code, geo, key: x.key, day: run.asOf, value: x.rank }));
    const r = await ingest(run, obs);
    rows += r.rows;
    if (items.length && r.rows >= obs.length) await pruneList(run, "apple.rss", f.code, geo, items.map((x) => x.key));
    const cs = discover(run, "apple.rss", geo, f.code, items, prev.get(`${f.code}|${geo}`) ?? null,
      { velocity: false, topK: 0, jumpMin: dc.jump_min ?? 20 });
    await writeCands(run, cs);
    cands += cs.length;
    fed++;
    failStreak = 0;
    done.add(id);
    await save();
  }
  const left = todo.length - done.size;
  if (left > 0) { run.partial = true; run.nextCursor = { remaining: left }; }
  run.extra.feeds_done_today = done.size;
  run.extra.feeds_total = todo.length;
  run.source({ source: "apple.rss", status: left ? "partial" : "ok", keys: fed, rows, ms: Date.now() - t0,
    note: `${fed} feeds this run, ${done.size}/${todo.length} today, ${cands} candidates` });
}

// ------------------------------------------------------------------ steamspy
async function modeSteamspy(run: Run) {
  const t0 = Date.now();
  const c = await ctx();
  const n = lim(c, c.cfg.steamspy?.limit, 100);
  const j = await getJson(run, "https://steamspy.com/api.php?request=top100in2weeks", { source: "steamspy", timeoutMs: 40_000 });
  if (!j || typeof j !== "object") { run.source({ source: "steamspy", status: "http_error", ms: Date.now() - t0 }); return; }
  const apps = Object.values(j as Record<string, any>)
    .filter((a) => a && /^\d+$/.test(String(a.appid)) && Number.isFinite(Number(a.ccu)))
    .sort((a, b) => Number(b.ccu) - Number(a.ccu)).slice(0, n);
  const items: Item[] = apps.map((a, i) => ({ key: String(a.appid), label: String(a.name ?? ""), rank: i + 1, score: Number(a.ccu) }));
  const obs: ObsRow[] = items.map((x) => ({ source: "steamspy", metric: "ccu", key: x.key, day: run.asOf, value: x.score!, aux: x.rank }));
  const r = await ingest(run, obs);
  if (r.rows >= obs.length) await pruneList(run, "steamspy", "ccu", "ALL", items.map((x) => x.key));
  const prev = prevRanks(await prevSnap(run, "steamspy", ["ccu"]), (p) => p.aux);
  const cs = discover(run, "steamspy", "ALL", "top100in2weeks", items, prev.get("ccu|ALL") ?? null,
    { velocity: false, topK: 0, jumpMin: c.cfg.discovery?.jump_min ?? 20 });
  await writeCands(run, cs);
  run.source({ source: "steamspy", status: "ok", keys: items.length, rows: r.rows, ms: Date.now() - t0, note: `${cs.length} candidates` });
}

// ------------------------------------------------------------------ github (gh.search, gh.stars)
const GH = "api.github.com";
const GH_HEADERS = { Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" };
async function modeGithub(run: Run) {
  const c = await ctx();
  const gc = c.cfg.github ?? {};
  const dc = c.cfg.discovery ?? {};
  // 1) new repos by stars (gh.search)
  let t0 = Date.now();
  const n = lim(c, gc.limit, 50);
  const since = addDays(run.asOf, -((gc.window_days ?? 7) - 1));
  const q = encodeURIComponent(`created:>=${since}`);
  const j = await getJson(run, `https://${GH}/search/repositories?q=${q}&sort=stars&order=desc&per_page=${n}`,
    { source: "gh.search", headers: GH_HEADERS });
  if (j && Array.isArray(j.items)) {
    const farmRatio = dc.star_farm_ratio ?? 50;
    const items: Item[] = [];
    const obs: ObsRow[] = [];
    j.items.slice(0, n).forEach((r: any, i: number) => {
      if (!Number.isFinite(Number(r?.id))) return;
      const key = String(r.id);
      const stars = Number(r.stargazers_count ?? 0), forks = Number(r.forks_count ?? 0);
      items.push({ key, label: String(r.name ?? ""), rank: i + 1, score: stars, farm: stars / Math.max(1, forks) > farmRatio });
      obs.push({ source: "gh.search", metric: "new7d", key, day: run.asOf, value: i + 1, aux: stars });
      obs.push({ source: "gh.search", metric: "stars", key, day: run.asOf, value: stars, aux: forks });
    });
    const r = await ingest(run, obs);
    if (r.rows >= obs.length) for (const m of ["new7d", "stars"]) await pruneList(run, "gh.search", m, "ALL", items.map((x) => x.key));
    const prev = prevRanks(await prevSnap(run, "gh.search", ["new7d"]), (p) => p.value);
    const cs = discover(run, "gh.search", "ALL", "new7d", items, prev.get("new7d|ALL") ?? null,
      { velocity: true, topK: dc.top_k ?? 10, jumpMin: dc.jump_min ?? 20 });
    await writeCands(run, cs);
    run.source({ source: "gh.search", status: "ok", keys: items.length, rows: r.rows, ms: Date.now() - t0,
      note: `total_count ${j.total_count ?? "?"}, ${cs.length} candidates` });
  } else run.source({ source: "gh.search", status: blocked(run, GH) ? "partial" : "http_error", ms: Date.now() - t0 });

  // 2) registered repos: stargazers_count (gh.stars 'total') and daily gain 'n'
  t0 = Date.now();
  const keys = (await watchlist(run, "gh.stars", 500)).filter((k) => /^[\w.-]+\/[\w.-]+$/.test(k.key));
  if (!keys.length) { run.source({ source: "gh.stars", status: "ok", keys: 0, rows: 0, ms: 0, note: "no registered repos" }); return; }
  const prevTot = new Map<string, number>();
  for (const p of await prevSnap(run, "gh.stars", ["total"], 1)) if (p.day === addDays(run.asOf, -1)) prevTot.set(p.key, p.value);
  const obs: ObsRow[] = [];
  let done = 0;
  for (const k of keys) {
    if (run.outOfTime(8000) || blocked(run, GH)) { run.partial = true; break; }
    const r = await getJson(run, `https://${GH}/repos/${k.key}`, { source: "gh.stars", headers: GH_HEADERS, soft: true });
    if (!r || !Number.isFinite(Number(r.stargazers_count))) continue;
    const tot = Number(r.stargazers_count);
    obs.push({ source: "gh.stars", metric: "total", key: k.key, day: run.asOf, value: tot, topic_id: k.topic_id });
    const p = prevTot.get(k.key);
    if (p !== undefined && tot >= p) obs.push({ source: "gh.stars", key: k.key, day: run.asOf, value: tot - p, topic_id: k.topic_id });
    done++;
  }
  const r = await ingest(run, obs);
  run.source({ source: "gh.stars", status: done < keys.length ? "partial" : "ok", keys: done, rows: r.rows, ms: Date.now() - t0 });
}

// ------------------------------------------------------------------ hugging face (hf.trending)
function fnv(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, "0");
}
async function modeHf(run: Run) {
  const c = await ctx();
  const hc = c.cfg.hf ?? {};
  const n = lim(c, hc.limit, 50);
  const dc = c.cfg.discovery ?? {};
  const lists: string[] = run.params.lists ?? hc.lists ?? ["models", "spaces", "datasets"];
  const prev = prevRanks(await prevSnap(run, "hf.trending", lists), (p) => p.value);
  for (const list of lists) {
    const t0 = Date.now();
    if (run.outOfTime(8000) || blocked(run, "huggingface.co")) { run.partial = true; break; }
    const j = await getJson(run, `https://huggingface.co/api/${list}?sort=trendingScore&direction=-1&limit=${n}`,
      { source: "hf.trending" });
    if (!Array.isArray(j)) { run.source({ source: "hf.trending", status: "http_error", note: list, ms: Date.now() - t0 }); continue; }
    const items: Item[] = j.slice(0, n).map((m: any, i: number) => {
      const id = String(m?.id ?? m?.modelId ?? "");
      // key: the opaque Hub object id (never the owner/name path, whose first part is a user handle)
      const key = typeof m?._id === "string" && /^[0-9a-f]{24}$/.test(m._id) ? m._id : `h${fnv(id)}`;
      return { key, label: id.includes("/") ? id.split("/").slice(1).join("/") : id, rank: i + 1,
        score: Number.isFinite(Number(m?.trendingScore)) ? Number(m.trendingScore) : null };
    }).filter((x: Item) => x.label);
    const obs: ObsRow[] = items.map((x) => ({ source: "hf.trending", metric: list, key: x.key, day: run.asOf, value: x.rank, aux: x.score ?? null }));
    const r = await ingest(run, obs);
    if (r.rows >= obs.length) await pruneList(run, "hf.trending", list, "ALL", items.map((x) => x.key));
    const cs = discover(run, "hf.trending", "ALL", list, items, prev.get(`${list}|ALL`) ?? null,
      { velocity: true, topK: dc.top_k ?? 10, jumpMin: dc.jump_min ?? 20 });
    await writeCands(run, cs);
    run.source({ source: "hf.trending", status: "ok", keys: items.length, rows: r.rows, ms: Date.now() - t0, note: `${list}: ${cs.length} candidates` });
  }
}

// ------------------------------------------------------------------ anilist
const ANI = "https://graphql.anilist.co";
async function aniQuery(run: Run, query: string, variables: Record<string, unknown> = {}): Promise<any | null> {
  const j = await getJson(run, ANI, {
    source: "anilist", method: "POST", body: JSON.stringify({ query, variables }),
    headers: { "Content-Type": "application/json" },
  });
  if (j?.errors?.length) { run.errors.push(`anilist: ${String(j.errors[0]?.message ?? "error").slice(0, 120)}`); }
  return j?.data ?? null;
}
/** mediaTrends for up to `batch` media per request (GraphQL aliases). Returns rows metric 'n'. */
async function aniTrends(run: Run, ids: Array<{ id: string; topic_id: number | null }>, fromDay: string, perPage: number, page = 1): Promise<{ rows: ObsRow[]; more: Set<string> }> {
  const parts = ids.map((m) =>
    `m${m.id}: Page(page:${page}, perPage:${perPage}){ pageInfo{hasNextPage} mediaTrends(mediaId:${Number(m.id)}, date_greater:${unixDay(fromDay) - 1}, sort:DATE_DESC){ date trending popularity } }`);
  const data = await aniQuery(run, `query{ ${parts.join("\n")} }`);
  const rows: ObsRow[] = [];
  const more = new Set<string>();
  if (!data) return { rows, more };
  for (const m of ids) {
    const pg = data[`m${m.id}`];
    for (const t of (pg?.mediaTrends ?? []) as any[]) {
      if (!Number.isFinite(Number(t?.date)) || !Number.isFinite(Number(t?.trending))) continue;
      const day = dayOfUnix(Number(t.date));
      if (day > run.asOf) continue;
      rows.push({ source: "anilist", key: m.id, day, value: Number(t.trending),
        aux: Number.isFinite(Number(t.popularity)) ? Number(t.popularity) : null, topic_id: m.topic_id });
    }
    if (pg?.pageInfo?.hasNextPage) more.add(m.id);
  }
  return { rows, more };
}
async function modeAnilist(run: Run) {
  const c = await ctx();
  const ac = c.cfg.anilist ?? {};
  const n = Math.min(50, lim(c, ac.limit, 50));
  const dc = c.cfg.discovery ?? {};
  const topK = dc.top_k ?? 10;
  const prev = prevRanks(await prevSnap(run, "anilist", ["trending_anime", "trending_manga"]), (p) => p.value);
  const extraIds = new Map<string, number | null>();
  for (const type of ["ANIME", "MANGA"]) {
    const t0 = Date.now();
    if (run.outOfTime(8000) || blocked(run, "graphql.anilist.co")) { run.partial = true; break; }
    const metric = `trending_${type.toLowerCase()}`;
    const data = await aniQuery(run,
      `query($t:MediaType,$n:Int){Page(page:1,perPage:$n){media(sort:TRENDING_DESC,type:$t,isAdult:false){id title{romaji english} trending popularity}}}`,
      { t: type, n });
    const media: any[] = data?.Page?.media ?? [];
    if (!media.length) { run.source({ source: "anilist", status: "http_error", note: metric, ms: Date.now() - t0 }); continue; }
    const items: Item[] = media.map((m, i) => ({ key: String(m.id), label: String(m?.title?.english || m?.title?.romaji || ""),
      rank: i + 1, score: Number.isFinite(Number(m.trending)) ? Number(m.trending) : null })).filter((x) => /^\d+$/.test(x.key));
    const obs: ObsRow[] = items.map((x) => ({ source: "anilist", metric, key: x.key, day: run.asOf, value: x.rank, aux: x.score ?? null }));
    const r = await ingest(run, obs);
    if (r.rows >= obs.length) await pruneList(run, "anilist", metric, "ALL", items.map((x) => x.key));
    const cs = discover(run, "anilist", "ALL", metric, items, prev.get(`${metric}|ALL`) ?? null,
      { velocity: true, topK, jumpMin: dc.jump_min ?? 20 });
    await writeCands(run, cs);
    for (const x of items.slice(0, topK)) extraIds.set(x.key, null);
    run.source({ source: "anilist", status: "ok", keys: items.length, rows: r.rows, ms: Date.now() - t0, note: `${metric}: ${cs.length} candidates` });
  }
  // per-media daily trends (metric 'n'): registered titles first, then today's top trending titles (built-in baseline)
  const t0 = Date.now();
  const reg = await watchlist(run, "anilist", 300);
  const ids = new Map<string, number | null>();
  for (const k of reg) if (/^\d+$/.test(k.key)) ids.set(k.key, k.topic_id ?? null);
  for (const [k, v] of extraIds) if (!ids.has(k)) ids.set(k, v);
  const list = [...ids].map(([id, topic_id]) => ({ id, topic_id }));
  const batch = Math.max(1, Math.min(10, Number(ac.trend_batch ?? 8)));
  let rows = 0, doneN = 0;
  for (let i = 0; i < list.length; i += batch) {
    if (run.outOfTime(8000) || blocked(run, "graphql.anilist.co")) { run.partial = true; break; }
    const part = list.slice(i, i + batch);
    const { rows: obs } = await aniTrends(run, part, addDays(run.asOf, -7), 10);
    const r = await ingest(run, obs);
    rows += r.rows;
    doneN += part.length;
  }
  run.source({ source: "anilist", status: doneN < list.length ? "partial" : "ok", keys: doneN, rows, ms: Date.now() - t0,
    note: `mediaTrends (last 8 days) for ${reg.length} registered + ${list.length - reg.length} top trending titles` });
}

// ------------------------------------------------------------------ open library
async function modeOpenlibrary(run: Run) {
  const t0 = Date.now();
  const c = await ctx();
  const n = lim(c, c.cfg.openlibrary?.limit, 50);
  const dc = c.cfg.discovery ?? {};
  const j = await getJson(run, `https://openlibrary.org/trending/daily.json?limit=${n}`, { source: "ol.trending", timeoutMs: 45_000 });
  const works: any[] = Array.isArray(j?.works) ? j.works : [];
  if (!works.length) { run.source({ source: "ol.trending", status: "http_error", ms: Date.now() - t0 }); return; }
  const items: Item[] = works.slice(0, n).map((w, i) => ({ key: String(w?.key ?? "").replace(/^\/works\//, ""), label: String(w?.title ?? ""), rank: i + 1 }))
    .filter((x) => /^OL\d+W$/.test(x.key));
  const obs: ObsRow[] = items.map((x) => ({ source: "ol.trending", metric: "daily", key: x.key, day: run.asOf, value: x.rank }));
  const r = await ingest(run, obs);
  if (r.rows >= obs.length) await pruneList(run, "ol.trending", "daily", "ALL", items.map((x) => x.key));
  const prev = prevRanks(await prevSnap(run, "ol.trending", ["daily"]), (p) => p.value);
  const cs = discover(run, "ol.trending", "ALL", "daily", items, prev.get("daily|ALL") ?? null,
    { velocity: true, topK: dc.top_k ?? 10, jumpMin: dc.jump_min ?? 20 });
  await writeCands(run, cs);
  run.source({ source: "ol.trending", status: "ok", keys: items.length, rows: r.rows, ms: Date.now() - t0, note: `${cs.length} candidates` });
}

// ------------------------------------------------------------------ tranco (streamed zip)
/** Stream the first entry of a zip (local header parse). sized: stop after compSize bytes (no trailing data). */
async function zipFirstEntry(res: Response): Promise<{ stream: ReadableStream<any>; name: string; sized: boolean }> {
  const reader = res.body!.getReader();
  let buf = new Uint8Array(0);
  const need = async (k: number) => {
    while (buf.length < k) {
      const { value, done } = await reader.read();
      if (done) throw new Error("zip: truncated header");
      const nb = new Uint8Array(buf.length + value.length); nb.set(buf); nb.set(value, buf.length); buf = nb;
    }
  };
  await need(30);
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  if (dv.getUint32(0, true) !== 0x04034b50) throw new Error("zip: bad local header signature");
  const flags = dv.getUint16(6, true), method = dv.getUint16(8, true);
  const comp = dv.getUint32(18, true), nameLen = dv.getUint16(26, true), extraLen = dv.getUint16(28, true);
  await need(30 + nameLen + extraLen);
  const name = new TextDecoder().decode(buf.subarray(30, 30 + nameLen));
  const sized = (flags & 8) === 0 && comp > 0 && comp !== 0xffffffff;
  let left = sized ? comp : Infinity;
  let first: Uint8Array | null = buf.subarray(30 + nameLen + extraLen);
  const raw: ReadableStream<any> = new ReadableStream<Uint8Array>({
    async pull(ctl) {
      if (left <= 0) { ctl.close(); await reader.cancel().catch(() => undefined); return; }
      let chunk: Uint8Array;
      if (first && first.length) { chunk = first; first = null; }
      else {
        first = null;
        const { value, done } = await reader.read();
        if (done) { ctl.close(); return; }
        chunk = value;
      }
      if (chunk.length > left) chunk = chunk.subarray(0, left);
      left -= chunk.length;
      ctl.enqueue(chunk);
    },
    async cancel() { await reader.cancel().catch(() => undefined); },
  });
  if (method === 0) return { stream: raw, name, sized };
  if (method !== 8) throw new Error(`zip: unsupported method ${method}`);
  return { stream: raw.pipeThrough(new DecompressionStream("deflate-raw")), name, sized };
}

/** 12-hex (48-bit) SHA-256 digest of a lower-cased domain: the one-way key of the top-1k snapshot in att_state. */
async function domHash(d: string): Promise<string> {
  const b = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(d.toLowerCase())));
  let s = "";
  for (let i = 0; i < 6; i++) s += b[i].toString(16).padStart(2, "0");
  return s;
}
async function modeTranco(run: Run) {
  const t0 = Date.now();
  const c = await ctx();
  const tc = c.cfg.tranco ?? {};
  const topN = Number(tc.top ?? 1000);
  const keys = await watchlist(run, "tranco.rank", 5000);
  const want = new Map<string, WatchKey>();
  for (const k of keys) want.set(k.key.toLowerCase(), k);
  const sp = (await paceWait(run, "tranco.rank", "tranco-list.eu")) ?? 5000;
  const tStart = Date.now();
  const res = await politeFetch(run, "https://tranco-list.eu/top-1m.csv.zip", { source: "tranco.rank", timeoutMs: 90_000 });
  if (res) paceDone(run, "tranco.rank", "tranco-list.eu", tStart, sp);
  if (!res || !res.ok || !res.body) {
    if (res) { await res.body?.cancel(); run.errors.push(`tranco: http ${res.status}`); }
    run.source({ source: "tranco.rank", status: "http_error", ms: Date.now() - t0 });
    return;
  }
  const top: string[] = [];
  const found = new Map<string, number>();
  let lineNo = 0, bytes = 0, complete = false, entry = "";
  try {
    const z = await zipFirstEntry(res);
    entry = z.name;
    const rd = z.stream.pipeThrough(new TextDecoderStream()).getReader();
    let tail = "";
    const handle = (line: string) => {
      const comma = line.indexOf(",");
      if (comma < 0) return;
      lineNo++;
      const dom = line.slice(comma + 1);
      if (lineNo <= topN) top.push(dom);
      if (want.has(dom) && !found.has(dom)) found.set(dom, Number(line.slice(0, comma)) || lineNo);
    };
    while (true) {
      if (run.outOfTime(6000)) { run.partial = true; break; }
      let r;
      try { r = await rd.read(); } catch (e) {
        // unsized entries (data descriptor) end with trailing zip records; deflate reports junk after the stream end
        if (lineNo > 900_000) { complete = true; break; }
        throw e;
      }
      if (r.done) { complete = true; break; }
      bytes += r.value.length;
      const s = tail + r.value;
      let start = 0, i: number;
      while ((i = s.indexOf("\n", start)) >= 0) { handle(s.charCodeAt(i - 1) === 13 ? s.slice(start, i - 1) : s.slice(start, i)); start = i + 1; }
      tail = s.slice(start);
    }
    if (complete && tail) handle(tail.replace(/\r$/, ""));
    await rd.cancel().catch(() => undefined);
  } catch (e) {
    run.errors.push(`tranco: ${errMsg(e)}`);
  }
  run.extra.tranco = { entry, lines: lineNo, text_bytes: bytes, complete, registered: want.size, found: found.size };
  if (lineNo < topN) { run.source({ source: "tranco.rank", status: "http_error", ms: Date.now() - t0, note: `only ${lineNo} lines` }); return; }

  const obs: ObsRow[] = [];
  for (const [dom, rank] of found) obs.push({ source: "tranco.rank", key: dom, day: run.asOf, value: rank, topic_id: want.get(dom)?.topic_id ?? null });

  // top-1k movers against the previous snapshot. att_state 'charts.tranco.top' = {day, h, prev:{day, h}} where h is the
  // top-1k in rank order as 12-hex SHA-256 digests of the domain (no readable domain list is kept; only the domains
  // that become movers or are registered are stored, as rank series).
  const st = ((await stateGet("charts.tranco.top")) ?? {}) as { day?: string; h?: string; prev?: { day: string; h: string } };
  const base = st.day && st.day < run.asOf && st.h ? { day: st.day, h: st.h } : (st.prev && st.prev.day < run.asOf && st.prev.h ? st.prev : null);
  const topH = await Promise.all(top.map(domHash));
  let movers: Item[] = [];
  if (base) {
    const pr = new Map<string, number>();
    for (let i = 0; i * 12 < base.h.length; i++) { const h = base.h.slice(i * 12, i * 12 + 12); if (!pr.has(h)) pr.set(h, i + 1); }
    const jm = Number(tc.jump_min ?? 20), jf = Number(tc.jump_frac ?? 0.25);
    const all: Array<Item & { mag: number }> = [];
    top.forEach((d, i) => {
      const rank = i + 1, p = pr.get(topH[i]);
      if (p === undefined) all.push({ key: d, label: d, rank, mag: 1e9 - rank });
      else if (p - rank >= Math.max(jm, jf * p)) all.push({ key: d, label: d, rank, mag: (p - rank) / p });
    });
    movers = all.sort((a, b) => b.mag - a.mag).slice(0, Number(tc.max_movers ?? 100)).sort((a, b) => a.rank - b.rank);
    for (const m of movers) if (!found.has(m.key)) obs.push({ source: "tranco.rank", key: m.key, day: run.asOf, value: m.rank });
    const prevMap = new Map<string, number>();
    const hOf = new Map<string, string>(top.map((d, i) => [d, topH[i]]));
    for (const m of movers) { const p = pr.get(hOf.get(m.key) ?? ""); if (p !== undefined) prevMap.set(m.key, p); }
    // discover() treats keys missing from prevMap as 'new' and applies jump_min to the rest (movers already filtered)
    const cs = discover(run, "tranco.rank", "ALL", "top1k", movers, prevMap, { velocity: false, topK: 0, jumpMin: jm });
    await writeCands(run, cs);
  }
  const r = await ingest(run, obs);
  if (!run.dryRun && complete) {
    const keep = st.day === run.asOf ? st.prev : (st.day && st.h ? { day: st.day, h: st.h } : undefined);
    await stateSet("charts.tranco.top", { day: run.asOf, h: topH.join(""), ...(keep ? { prev: keep } : {}) });
  }
  run.extra.movers = movers.length;
  run.source({ source: "tranco.rank", status: complete ? "ok" : "partial", keys: found.size + movers.length, rows: r.rows,
    ms: Date.now() - t0, note: `${lineNo} lines; ${found.size}/${want.size} registered domains ranked; ${movers.length} top-1k movers${base ? "" : " (no previous list yet)"}` });
}

// ------------------------------------------------------------------ npm (npm.dl)
const NPM = "https://api.npmjs.org/downloads/range";
/**
 * npm reports days it has not computed (the last 1-3 days, and occasional outage days) as 0 downloads for every package.
 * A 0 is therefore treated as missing (not stored) for '__total__' and for any package whose 75th percentile in the
 * response is above 100/day; small packages keep genuine zeros. Missing days are refilled by the next runs' window
 * (config npm.days, default 30: the same number of requests as a 7-day window, so a day npm recomputes late is picked up).
 * Days on which '__total__' is 0 inside a fully computed window are npm-side outage days; they are listed (days only, no
 * values) in att_state 'charts.npm.gaps' so share-transform consumers skip them instead of dividing by a missing total.
 */
function npmRows(run: Run, pkg: string, j: any, topic: number | null): ObsRow[] {
  const days = ((j?.downloads ?? []) as any[])
    .filter((d) => typeof d?.day === "string" && Number.isFinite(Number(d?.downloads)) && d.day <= run.asOf);
  const vals = days.map((d) => Number(d.downloads)).sort((a, b) => a - b);
  const p75 = vals.length ? vals[Math.floor(vals.length * 0.75)] : 0;
  const dropZero = pkg === "__total__" || p75 > 100;
  const out: ObsRow[] = [];
  for (const d of days) {
    const v = Number(d.downloads);
    if (v === 0 && dropZero) continue;
    out.push({ source: "npm.dl", key: pkg, day: d.day, value: v, topic_id: topic });
  }
  return out;
}
async function npmKeys(run: Run, c: Ctx): Promise<Map<string, number | null>> {
  const m = new Map<string, number | null>();
  for (const k of await watchlist(run, "npm.dl", 2000)) m.set(k.key, k.topic_id ?? null);
  for (const p of (c.cfg.npm?.reference ?? []) as string[]) if (!m.has(p)) m.set(p, null);
  return m;
}
const validNpm = (p: string) => /^(@[a-z0-9][\w.-]*\/)?[a-z0-9][\w.-]*$/i.test(p) && p.length <= 214;
async function npmBackfillOne(run: Run, pkg: string, topic: number | null, from: string, to: string): Promise<number> {
  const f = from < addDays(to, -540) ? addDays(to, -540) : from; // single-package ranges: at most 18 months per call
  const path = pkg === "__total__" ? `${NPM}/${f}:${to}` : `${NPM}/${f}:${to}/${pkg}`;
  const j = await getJson(run, path, { source: "npm.dl", soft: true });
  if (!j) return -1;
  const r = await ingest(run, npmRows(run, pkg, j, topic));
  return r.rows;
}
/** true when the stored history of a key does not yet reach back to (window start + 30 days) and no 400-day fetch
 *  was made for it in the last 30 days. */
function npmNeedsBackfill(run: Run, firstDay: string | null, lastBackfill: string | undefined, bfDays: number): boolean {
  if (lastBackfill && lastBackfill > addDays(run.asOf, -30)) return false;
  return !firstDay || firstDay > addDays(run.asOf, -(bfDays - 1) + 30);
}
/** Zero days of the '__total__' response that are older than npm's 3-day computing lag = npm outage days. */
function npmTotalGaps(run: Run, j: any): string[] {
  const lag = addDays(run.asOf, -3);
  return ((j?.downloads ?? []) as any[])
    .filter((d) => typeof d?.day === "string" && d.day <= lag && Number(d?.downloads) === 0).map((d) => d.day as string);
}
/** Merge gap days into att_state 'charts.npm.gaps' (sorted, last 400 days); days that now have a value are removed. */
async function npmRecordGaps(run: Run, gaps: string[], filled: string[], winFrom: string) {
  if (run.dryRun) return;
  const st = ((await stateGet("charts.npm.gaps")) ?? {}) as { days?: string[] };
  const keep = new Set((st.days ?? []).filter((d) => typeof d === "string" && d >= addDays(run.asOf, -400)));
  for (const d of filled) keep.delete(d);
  for (const d of gaps) keep.add(d);
  const days = [...keep].sort();
  await stateSet("charts.npm.gaps", { days, as_of: run.asOf, window_from: winFrom,
    note: "npm reported 0 for the all-packages total on these days (source outage, older than the 3-day lag); npm.dl __total__ has no row for them" });
}
function npmPruneState(run: Run, st: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, d] of Object.entries(st)) if (typeof d === "string" && d > addDays(run.asOf, -30)) out[k] = d;
  return out;
}
async function modeNpm(run: Run) {
  const t0 = Date.now();
  const c = await ctx();
  const nc = c.cfg.npm ?? {};
  const keys = await npmKeys(run, c);
  const pkgs = [...keys.keys()].filter(validNpm);
  const days = Math.max(7, Math.min(90, Number(nc.days ?? 30)));
  const from = addDays(run.asOf, -(days - 1)), to = run.asOf;
  let rows = 0, calls = 0;
  const host = "api.npmjs.org";
  const missing = new Set<string>(); // unknown packages: no 400-day backfill call is spent on them
  // 1) '__total__' (all packages) normaliser
  {
    const j = await getJson(run, `${NPM}/${from}:${to}`, { source: "npm.dl" });
    calls++;
    if (j) {
      const tr = npmRows(run, "__total__", j, null);
      rows += (await ingest(run, tr)).rows;
      const gaps = npmTotalGaps(run, j);
      await npmRecordGaps(run, gaps, tr.map((r) => String(r.day)), from);
      run.extra.npm_total_gaps = gaps.length;
    }
  }
  // 2) bulk unscoped (<= 128 per call), then scoped one by one
  const unscoped = pkgs.filter((p) => !p.startsWith("@")), scoped = pkgs.filter((p) => p.startsWith("@"));
  const bulk = Math.max(2, Math.min(128, Number(nc.bulk ?? 128)));
  for (let i = 0; i < unscoped.length; i += bulk) {
    if (run.outOfTime(8000) || blocked(run, host)) { run.partial = true; break; }
    const part = unscoped.slice(i, i + bulk);
    const j = await getJson(run, `${NPM}/${from}:${to}/${part.join(",")}`, { source: "npm.dl" });
    calls++;
    if (!j) continue;
    const obs: ObsRow[] = [];
    if (part.length === 1) obs.push(...npmRows(run, part[0], j, keys.get(part[0]) ?? null));
    else for (const p of part) {
      if (j[p]) obs.push(...npmRows(run, p, j[p], keys.get(p) ?? null));
      else { missing.add(p); note(run, `npm: no data for ${p}`); }
    }
    rows += (await ingest(run, obs)).rows;
  }
  for (const p of scoped) {
    if (run.outOfTime(8000) || blocked(run, host)) { run.partial = true; break; }
    const j = await getJson(run, `${NPM}/${from}:${to}/${p}`, { source: "npm.dl", soft: true });
    calls++;
    if (j) rows += (await ingest(run, npmRows(run, p, j, keys.get(p) ?? null))).rows;
    else if (!blocked(run, host)) missing.add(p);
  }
  // 3) 400-day history for keys that do not have it yet (reference packages; registered keys also get backfill jobs)
  const bfDays = Number(nc.backfill_days ?? 400);
  // Coverage = first stored day, not row count ('__total__' drops npm's uncomputed zero days, so its row count stays
  // below any count threshold and it would be refetched every day). A key counts as covered when its history starts
  // within 30 days of the 400-day window start, or when it was backfilled in the last 30 days (young packages whose
  // history is simply shorter: att_state 'charts.npm.backfilled' = {pkg: day}).
  const first = await seriesFirst(run, "npm.dl", "n", ["__total__", ...pkgs]);
  const bfState = ((await stateGet("charts.npm.backfilled")) ?? {}) as Record<string, string>;
  const need = ["__total__", ...pkgs].filter((p) => !missing.has(p) && npmNeedsBackfill(run, first.get(p) ?? null, bfState[p], bfDays));
  let backfilled = 0;
  for (const p of need) {
    if (run.outOfTime(8000) || blocked(run, host)) { run.partial = true; break; }
    const n = await npmBackfillOne(run, p, keys.get(p) ?? null, addDays(run.asOf, -(bfDays - 1)), run.asOf);
    if (n >= 0) { rows += n; backfilled++; bfState[p] = run.asOf; }
  }
  if (backfilled && !run.dryRun) await stateSet("charts.npm.backfilled", npmPruneState(run, bfState));
  run.extra.npm = { packages: pkgs.length, calls_daily: calls, backfilled, backfill_pending: need.length - backfilled };
  run.source({ source: "npm.dl", status: run.partial ? "partial" : "ok", keys: pkgs.length + 1, rows, ms: Date.now() - t0,
    note: `${unscoped.length} bulk + ${scoped.length} scoped; ${backfilled}/${need.length} 400-day backfills` });
}

// ------------------------------------------------------------------ pypi (pypi.dl)
const validPypi = (p: string) => /^[a-z0-9][a-z0-9._-]*$/i.test(p) && p.length <= 100;
async function pypiOne(run: Run, pkg: string, topic: number | null, fromDay: string | null): Promise<number> {
  const j = await getJson(run, `https://pypistats.org/api/packages/${encodeURIComponent(pkg.toLowerCase())}/overall?mirrors=false`,
    { source: "pypi.dl", soft: true });
  if (!j) return -1;
  const obs: ObsRow[] = [];
  for (const d of (j?.data ?? []) as any[]) {
    if (d?.category !== "without_mirrors" || typeof d?.date !== "string" || !Number.isFinite(Number(d?.downloads))) continue;
    if (d.date > run.asOf || (fromDay && d.date < fromDay)) continue;
    obs.push({ source: "pypi.dl", key: pkg.toLowerCase(), day: d.date, value: Number(d.downloads), topic_id: topic });
  }
  return (await ingest(run, obs)).rows;
}
async function modePypi(run: Run) {
  const t0 = Date.now();
  const c = await ctx();
  const pc = c.cfg.pypi ?? {};
  const keys = new Map<string, number | null>();
  for (const k of await watchlist(run, "pypi.dl", 2000)) keys.set(k.key.toLowerCase(), k.topic_id ?? null);
  for (const p of (pc.reference ?? []) as string[]) if (!keys.has(p.toLowerCase())) keys.set(p.toLowerCase(), null);
  const pkgs = [...keys.keys()].filter(validPypi);
  const info = await seriesInfo(run, "pypi.dl", "n", pkgs);
  const from = addDays(run.asOf, -((pc.days ?? 7) - 1));
  let rows = 0, done = 0;
  for (const p of pkgs) {
    if (run.outOfTime(8000) || blocked(run, "pypistats.org")) { run.partial = true; break; }
    // one call returns 180 days: keep all of it until the series has history, then only the recent window
    const n = await pypiOne(run, p, keys.get(p) ?? null, (info.get(p) ?? 0) >= 150 ? from : null);
    if (n >= 0) { rows += n; done++; }
  }
  run.source({ source: "pypi.dl", status: done < pkgs.length ? "partial" : "ok", keys: done, rows, ms: Date.now() - t0 });
}

// ------------------------------------------------------------------ backfill (merged att_tick jobs)
async function modeBackfill(run: Run) {
  const t0 = Date.now();
  const source = String(run.params.source ?? "");
  const bf = run.body?.backfill ?? {};
  const to = typeof bf.to === "string" && bf.to <= run.asOf ? bf.to : run.asOf;
  const from = typeof bf.from === "string" ? bf.from : addDays(to, -399);
  const keys: WatchKey[] = Array.isArray(run.body?.keys) ? await watchlist(run, source) : [];
  if (!keys.length) { run.source({ source: source || "?", status: "ok", keys: 0, rows: 0, ms: 0, note: "no keys" }); return; }
  const span = Math.round((Date.parse(to) - Date.parse(from)) / 86400000) + 1;
  let rows = 0, done = 0, skipped = 0;
  const c = await ctx();
  if (source === "npm.dl") {
    const first = await seriesFirst(run, source, "n", keys.map((k) => k.key));
    const bfState = ((await stateGet("charts.npm.backfilled")) ?? {}) as Record<string, string>;
    const reach = addDays(from, Math.min(30, Math.max(0, span - 1)));
    for (const k of keys) {
      const f0 = first.get(k.key) ?? null;
      const recent = bfState[k.key] && bfState[k.key] > addDays(run.asOf, -30);
      if ((f0 && f0 <= reach) || recent) { skipped++; continue; }
      if (!validNpm(k.key)) { note(run, `npm: invalid package ${k.key}`); skipped++; continue; }
      if (run.outOfTime(8000) || blocked(run, "api.npmjs.org")) { run.partial = true; break; }
      const n = await npmBackfillOne(run, k.key, k.topic_id ?? null, from, to);
      if (n >= 0) { rows += n; done++; bfState[k.key] = run.asOf; }
    }
    if (done && !run.dryRun) await stateSet("charts.npm.backfilled", npmPruneState(run, bfState));
  } else if (source === "pypi.dl") {
    const info = await seriesInfo(run, source, "n", keys.map((k) => k.key.toLowerCase()));
    for (const k of keys) {
      if ((info.get(k.key.toLowerCase()) ?? 0) >= 150) { skipped++; continue; }
      if (!validPypi(k.key)) { skipped++; continue; }
      if (run.outOfTime(8000) || blocked(run, "pypistats.org")) { run.partial = true; break; }
      const n = await pypiOne(run, k.key, k.topic_id ?? null, from);
      if (n >= 0) { rows += n; done++; }
    }
  } else if (source === "anilist") {
    const pages = Number(c.cfg.anilist?.backfill_pages ?? 8);
    const info = await seriesInfo(run, source, "n", keys.map((k) => k.key));
    for (const k of keys) {
      if (!/^\d+$/.test(k.key)) { skipped++; continue; }
      if ((info.get(k.key) ?? 0) >= 60) { skipped++; continue; }
      let page = 1, more = true;
      while (more && page <= pages) {
        if (run.outOfTime(8000) || blocked(run, "graphql.anilist.co")) { run.partial = true; break; }
        const r = await aniTrends(run, [{ id: k.key, topic_id: k.topic_id ?? null }], from, 50, page);
        rows += (await ingest(run, r.rows)).rows;
        more = r.more.has(k.key);
        page++;
      }
      if (run.partial) break;
      done++;
    }
  } else if (source === "gh.stars") {
    const maxStars = Number(c.cfg.github?.max_backfill_stars ?? 2000);
    for (const k of keys) {
      if (!/^[\w.-]+\/[\w.-]+$/.test(k.key)) { skipped++; continue; }
      if (run.outOfTime(8000) || blocked(run, GH)) { run.partial = true; break; }
      const repo = await getJson(run, `https://${GH}/repos/${k.key}`, { source: "gh.stars", headers: GH_HEADERS, soft: true });
      if (!repo) continue;
      const stars = Number(repo.stargazers_count ?? 0);
      if (stars > maxStars) { note(run, `gh.stars ${k.key}: ${stars} stars > ${maxStars}: history left to GH Archive (att-gharchive)`); skipped++; done++; continue; }
      const perDay = new Map<string, number>();
      let ok = true;
      for (let page = 1; page <= Math.ceil(stars / 100); page++) {
        if (run.outOfTime(8000) || blocked(run, GH)) { run.partial = true; ok = false; break; }
        const arr = await getJson(run, `https://${GH}/repos/${k.key}/stargazers?per_page=100&page=${page}`,
          { source: "gh.stars", headers: { ...GH_HEADERS, Accept: "application/vnd.github.star+json" } });
        if (!Array.isArray(arr)) { ok = false; break; }
        // only the timestamp is read; the stargazer's user object is discarded unread
        for (const s of arr) {
          const d = typeof s?.starred_at === "string" ? s.starred_at.slice(0, 10) : null;
          if (d && d >= from && d <= to) perDay.set(d, (perDay.get(d) ?? 0) + 1);
        }
        if (arr.length < 100) break;
      }
      if (!ok) break;
      const obs: ObsRow[] = [];
      for (let d = from; d <= to; d = addDays(d, 1)) obs.push({ source: "gh.stars", key: k.key, day: d, value: perDay.get(d) ?? 0, topic_id: k.topic_id ?? null });
      rows += (await ingest(run, obs)).rows;
      done++;
    }
  } else {
    run.errors.push(`backfill: unsupported source '${source}'`);
  }
  run.source({ source, status: run.partial ? "partial" : "ok", keys: done, rows, ms: Date.now() - t0,
    note: `${done} backfilled, ${skipped} skipped (history present / out of scope), window ${from}..${to}` });
}

// ------------------------------------------------------------------ serve
function wrap(fn: (run: Run) => Promise<void>) {
  return async (run: Run) => {
    run.extra.charts_version = CHARTS_VERSION;
    await fn(run);
  };
}
serve(FN, {
  apple: wrap(modeApple),
  steamspy: wrap(modeSteamspy),
  github: wrap(modeGithub),
  hf: wrap(modeHf),
  anilist: wrap(modeAnilist),
  openlibrary: wrap(modeOpenlibrary),
  tranco: wrap(modeTranco),
  npm: wrap(modeNpm),
  pypi: wrap(modePypi),
  backfill: wrap(modeBackfill),
  ping: async (run: Run) => { run.extra.charts_version = CHARTS_VERSION; run.extra.att_version = ATT_VERSION; },
});
