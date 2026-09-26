// att-wiki-hist — cold-storage pre-history backfill for wiki.pv (Ripple Map v5 attention layer, W7 companion).
//
// Gives every wiki.pv series >= 3 years of daily Wikipedia pageview history WITHOUT adding ~100 MB to attention_obs
// (~115 bytes/row) and blowing the self-imposed 400 MB DB cap. Wikimedia's per-article AQS endpoint returns an entire
// date range in one call, so the OLD portion of a series' history (everything strictly before its current earliest
// ripples.attention_obs.day) is fetched once in a single call and folded into one ripples.att_hist_arr row (int4[],
// ~4.4 KB for 3 y) instead of ~1,100 attention_obs rows (~126 KB). The engine reads both through
// ripples.att_series_daily(series_id, from, to) (28_att_wiki_hist.sql), which lets attention_obs win on any overlap.
//
// This function does NOT touch ripples.attention_obs, att_ingest, att_tick or any 20-25_att_engine_*.sql object — it
// only reads ripples.att_hist_wiki_plan and writes ripples.att_hist_arr via ripples.att_hist_wiki_upsert.
//
// Uses the SAME series definition as att-wiki's own pageviews/backfill modes (16_att_wiki.sql / att-wiki/index.ts):
// per-article, all-access, agent=user, geo = the att_series.geo project string (e.g. "en.wikipedia"), key = the
// article title exactly as stored. Old and new history are one continuous timeline for the same series.
//
// Demarcation (owner-approved, same as att-wiki): honest UA + contact via att.ts politeFetch (no new UA); serial,
// >= 1 s spacing (source 'wiki.pv': spacing_ms 1000); STOP on 429/503 for the rest of this run (politeFetch already
// kills the host for the UTC day; no retry here); shared 'wikimedia' budget bucket; no proxies/IP rotation;
// aggregate counts only. Per att_sources.per_run_cap (200) is the ceiling anyway, but this function additionally caps
// itself at HIST_MAX_CALLS (60) per run so a run finishes in ~1 minute at 1 req/s, well inside the 110 s wall clock,
// leaving headroom for att-wiki's own scheduled runs against the same shared budget.
import { serve, politeFetch, db, addDays, compact, type Run } from "./att.ts";

const WIKI_HIST_VERSION = "2026-09-26.1";
const AQS = "https://wikimedia.org/api/rest_v1/metrics";
const HIST_MAX_CALLS = 60;                 // <= 1 min at 1 req/s serial, well inside WALL_MS (110 s)
const HIST_TARGET_YEARS_DAYS = 3 * 365 + 30; // 3y + 30d buffer, per spec

const isoDay = (ts: string) => `${ts.slice(0, 4)}-${ts.slice(4, 6)}-${ts.slice(6, 8)}`;
const isStop = (x: unknown): x is { stop: string } => !!x && typeof x === "object" && "stop" in (x as object);
const isSoft = (x: unknown): x is { soft: string } => !!x && typeof x === "object" && "soft" in (x as object);
/** Reasons that end all further work on the host this run (mirrors att-wiki/index.ts HARD_STOP): a 429/503 kill,
 *  the shared budget spent, the run's own per-run cap, or anything else that means "do not send another request". */
const HARD_STOP = /^(host_killed|host_busy|host_lease_error|wm_quiet_window|ua_contact_unreachable|daily_budget_spent|per_run_cap|source_disabled|unknown_source|host_not_in_source|robots_disallow|red_source|wikimedia_(maxlag|ratelimited))/;

interface PlanRow { series_id: number; geo: string; key: string; topic_id: number | null; from_day: string; to_day: string }

/** One request through politeFetch; classifies the outcome the same way att-wiki/index.ts's get() does. */
async function get(run: Run, url: string): Promise<Response | { stop: string } | { soft: string }> {
  const nSkip = run.skipped.length, nErr = run.errors.length;
  const host = new URL(url).hostname.toLowerCase();
  const res = await politeFetch(run, url, { source: "wiki.pv", aqsRetry: host === "wikimedia.org" });
  if (res) return res;
  const skip = run.skipped.slice(nSkip).map((s) => s.reason).find((r) => HARD_STOP.test(r));
  if (skip) return { stop: skip };
  if (run.killed.has(host)) return { stop: run.killed.get(host)! };
  if (run.timeLeft() < 2000) return { stop: "out_of_time" };
  return { soft: run.errors.slice(nErr).join("; ") || "request_failed" };
}

async function histBackfill(run: Run) {
  const t0 = Date.now();
  const targetStart = addDays(run.asOf, -HIST_TARGET_YEARS_DAYS);
  const limit = Math.min(Number(run.params.max_series ?? HIST_MAX_CALLS), HIST_MAX_CALLS);
  const { data, error } = await db.rpc("att_hist_wiki_plan", { p_target_start: targetStart, p_limit: limit });
  if (error) throw new Error(`att_hist_wiki_plan: ${error.message}`);
  const plan = (data ?? []) as PlanRow[];

  let calls = 0, fetched = 0, nodata = 0, errors = 0, stop: string | null = null;
  let rows: Array<Record<string, unknown>> = [];
  const flush = async () => {
    if (!rows.length || run.dryRun) { rows = []; return; }
    const { data: up, error: e2 } = await db.rpc("att_hist_wiki_upsert", { p_rows: rows });
    if (e2) run.errors.push(`att_hist_wiki_upsert: ${e2.message}`);
    else fetched += Number((up as { rows?: number } | null)?.rows ?? 0);
    rows = [];
  };

  for (const p of plan) {
    if (p.to_day < p.from_day) continue; // already covered / nothing left before the earliest attention_obs day
    if (run.outOfTime(10_000)) { run.partial = true; stop = "out_of_time"; break; }
    const url = `${AQS}/pageviews/per-article/${p.geo}/all-access/user/${encodeURIComponent(p.key)}/daily/${compact(p.from_day)}00/${compact(p.to_day)}00`;
    const r = await get(run, url);
    if (isStop(r)) { stop = r.stop; run.partial = true; break; }
    if (isSoft(r)) { errors++; continue; }
    calls++;
    const nDays = Math.round((Date.parse(p.to_day) - Date.parse(p.from_day)) / 86400000) + 1;
    if (r.status === 404) {
      // No data anywhere in this (past, bounded) range: a real, settled zero — same treatment as att-wiki's own
      // incremental fetches on a 404 (fetchPageviews in att-wiki/index.ts). Not ambiguous with "not fetched yet"
      // because att_hist_arr rows are only ever written for a range we actually asked AQS about.
      await r.body?.cancel();
      const vals = new Array(nDays).fill(0);
      rows.push({ series_id: p.series_id, start_day: p.from_day, vals, meta: { source: "404", wiki_hist_version: WIKI_HIST_VERSION } });
      continue;
    }
    if (!r.ok) { await r.body?.cancel(); run.errors.push(`per-article hist ${p.geo}/${p.key} http ${r.status}`); errors++; continue; }
    const j = await r.json().catch(() => null);
    const byDay = new Map<string, number>();
    for (const it of (j?.items ?? []) as Array<{ timestamp: string; views: number }>) {
      byDay.set(isoDay(String(it.timestamp)), Number(it.views) || 0);
    }
    const vals: (number | null)[] = new Array(nDays);
    for (let i = 0; i < nDays; i++) {
      const dd = addDays(p.from_day, i);
      vals[i] = byDay.get(dd) ?? 0; // AQS omits zero-view days: fill zero, same as att-wiki's own fetchPageviews
    }
    rows.push({ series_id: p.series_id, start_day: p.from_day, vals, meta: { wiki_hist_version: WIKI_HIST_VERSION } });
    if (rows.length >= 20) await flush();
  }
  await flush();

  let autostopped = false, progress: unknown = null;
  if (!run.dryRun) {
    const { data: as, error: e3 } = await db.rpc("att_hist_wiki_autostop");
    if (e3) run.errors.push(`att_hist_wiki_autostop: ${e3.message}`); else autostopped = as === true;
    const { data: pr, error: e4 } = await db.rpc("att_hist_wiki_progress", { p_target_start: targetStart });
    if (e4) run.errors.push(`att_hist_wiki_progress: ${e4.message}`); else progress = pr;
  }

  run.extra = { ...run.extra, wiki_hist_version: WIKI_HIST_VERSION, target_start: targetStart,
    planned: plan.length, wikimedia_calls: calls, series_written: fetched, nodata, request_errors: errors,
    stop, autostopped, progress };
  run.source({ source: "wiki.pv", status: stop ? (stop.startsWith("host_killed_429") || stop.startsWith("host_killed_503") ? "host_killed_429" : "partial") : "ok",
    keys: fetched, rows: fetched, ms: Date.now() - t0, note: stop ?? (autostopped ? "coverage complete: cron unscheduled" : null) });
}

async function ping(run: Run) {
  run.extra = { ...run.extra, wiki_hist_version: WIKI_HIST_VERSION, modes: ["hist_backfill", "ping"], max_calls_per_run: HIST_MAX_CALLS };
  run.source({ source: "wiki.pv", status: "ok", keys: 0, rows: 0, ms: 0, note: "ping (no requests)" });
}

serve("att-wiki-hist", { hist_backfill: histBackfill, ping });
