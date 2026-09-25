// Knock-On v5 / W2 shared runtime for ripples-collect, ripples-resolve and ripples-expand.
// Deployed as a byte-identical copy next to each function's index.ts (the MCP deploy only uploads listed files).
//
// Rules implemented here (SPEC §5.1, DEMARCATION §7 lead decisions):
//  * every request sends User-Agent (and Api-User-Agent on Wikimedia) "KnockOn/5.0 (https://bensunter.com/ripples/methods/)"
//  * every Wikimedia request is counted against the job's budget (<=100 per job; the tick also enforces the
//    ripples.config.wm_daily_cap per as_of through ripples.runs.wm_calls)
//  * 429/503: AQS (wikimedia.org REST) gets one retry after 5 s; everything else stops the source for this run
//    (no retry within the run). A stopped job reports failure and is requeued by SQL after a pause.
//  * MediaWiki Action API (/w/api.php): maxlag=5, one request at a time (callers await each call), a maxlag or
//    ratelimited error stops the host for the run.
//  * auth: x-collector-token checked with public.check_collector_token (verify_jwt is off by design).
import { createClient } from "jsr:@supabase/supabase-js@2";

export const KN_VERSION = "2026-09-25.1";
export const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
export const UA = "KnockOn/5.0 (https://bensunter.com/ripples/methods/)";
const WM = /(^|\.)(wikipedia\.org|wikimedia\.org|wikidata\.org)$/i;

export class Stop extends Error {}          // rate limited / maxlag: stop this source for the run
export class OutOfBudget extends Error {}

export class Budget {
  wm = 0;                 // Wikimedia requests made (incl. retries)
  other = 0;              // non-Wikimedia requests
  stopped: string | null = null;
  constructor(public max: number) {}
  left() { return this.max - this.wm; }
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function kfetch(b: Budget, url: string, init: RequestInit = {}, opts: { aqs?: boolean; timeoutMs?: number } = {}): Promise<Response> {
  const u = new URL(url);
  const wm = WM.test(u.hostname);
  if (wm) {
    if (b.stopped) throw new Stop(b.stopped);
    if (b.wm >= b.max) throw new OutOfBudget(`budget ${b.max} spent`);
    if (u.pathname.startsWith("/w/api.php") && !u.searchParams.has("maxlag")) u.searchParams.set("maxlag", "5");
  }
  const headers = new Headers(init.headers ?? {});
  headers.set("User-Agent", UA);
  if (wm) headers.set("Api-User-Agent", UA);
  for (let attempt = 0; attempt < 2; attempt++) {
    if (wm) b.wm++; else b.other++;
    const res = await fetch(u, { ...init, headers, signal: AbortSignal.timeout(opts.timeoutMs ?? 25_000) });
    if (res.status === 429 || res.status === 503) {
      await res.body?.cancel();
      if (opts.aqs && attempt === 0 && b.wm < b.max) { await sleep(5000); continue; }
      if (wm) b.stopped = `${u.hostname} ${res.status}`;
      throw new Stop(`${u.hostname} ${res.status}`);
    }
    return res;
  }
  throw new Stop(`${u.hostname} 429`);
}

// MediaWiki Action API JSON (formatversion 2); maxlag / ratelimited errors stop the host.
export async function actionApi(b: Budget, host: string, params: Record<string, string>): Promise<any> {
  const u = new URL(`https://${host}/w/api.php`);
  for (const [k, v] of Object.entries({ format: "json", formatversion: "2", ...params })) u.searchParams.set(k, v);
  const res = await kfetch(b, u.toString());
  if (!res.ok) throw new Error(`${host} action api ${res.status}`);
  const j = await res.json();
  const code = j?.error?.code;
  if (code === "maxlag" || code === "ratelimited") { b.stopped = `${host} ${code}`; throw new Stop(`${host} ${code}`); }
  if (code) throw new Error(`${host} api error ${code}`);
  return j;
}

// ------------------------------------------------------------------ dates
export const ymd = (d: Date) => d.toISOString().slice(0, 10);
export const addDays = (s: string, k: number) => ymd(new Date(Date.parse(s + "T00:00:00Z") + k * 86400000));
export const dayDiff = (a: string, b: string) => Math.round((Date.parse(a + "T00:00:00Z") - Date.parse(b + "T00:00:00Z")) / 86400000);
const compact = (s: string) => s.replaceAll("-", "");

// ------------------------------------------------------------------ AQS per-article series
// Daily views, agent=user, all days in [from, to] (missing days = 0). null when the page has no data (404).
export async function series(b: Budget, title: string, from: string, to: string, access = "all-access", project = "en.wikipedia"): Promise<number[] | null> {
  const t = encodeURIComponent(title.replaceAll(" ", "_"));
  const url = `https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/${project}/${access}/user/${t}/daily/${compact(from)}00/${compact(to)}00`;
  const res = await kfetch(b, url, {}, { aqs: true });
  const n = dayDiff(to, from) + 1;
  if (res.status === 404) { await res.body?.cancel(); return null; }
  if (!res.ok) throw new Error(`aqs ${res.status}`);
  const j = await res.json();
  const out = new Array<number>(n).fill(0);
  for (const it of j.items ?? []) {
    const ts: string = it.timestamp;
    const d = `${ts.slice(0, 4)}-${ts.slice(4, 6)}-${ts.slice(6, 8)}`;
    const i = dayDiff(d, from);
    if (i >= 0 && i < n) out[i] = it.views ?? 0;
  }
  return out;
}

// Run tasks with bounded concurrency; the first Stop/OutOfBudget aborts the remaining ones.
export async function pool<T, R>(items: T[], conc: number, fn: (x: T) => Promise<R>): Promise<(R | Error)[]> {
  const out: (R | Error)[] = new Array(items.length);
  let i = 0;
  let halt: Error | null = null;
  async function worker() {
    while (i < items.length && !halt) {
      const k = i++;
      try { out[k] = await fn(items[k]); } catch (e) {
        out[k] = e as Error;
        if (e instanceof Stop || e instanceof OutOfBudget) halt = e as Error;
      }
    }
  }
  await Promise.all(Array.from({ length: Math.max(1, conc) }, worker));
  if (halt) throw halt;
  return out;
}

// ------------------------------------------------------------------ SPEC §5.2 statistics
export function median(a: number[]): number {
  const s = [...a].sort((x, y) => x - y);
  const n = s.length;
  if (!n) return 0;
  return n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
}
export interface Base { m: number; s: number; med: number }
// Baseline for reference day index t: x over [t-111, t-21] (91 days); m = median, s = max(0.1, 1.4826*MAD).
export function baseline(x: number[], t: number): Base | null {
  if (t - 111 < 0 || t - 21 >= x.length) return null;
  const w = x.slice(t - 111, t - 20);
  const m = median(w);
  const mad = median(w.map((v) => Math.abs(v - m)));
  return { m, s: Math.max(0.1, 1.4826 * mad), med: Math.exp(m) - 1 };
}
export const logs = (views: number[]) => views.map((v) => Math.log(1 + v));

export interface Hop {
  median_views: number; s_stat: number; onset_lag: number | null; multiple: number; p_time: number; n_placebo: number;
  pass_raw: boolean; calm: boolean; max_abs_z: number;
}
// Hop test for a candidate series (views aligned so index `a` = as_of) against parent onset index tp.
export function hopTest(views: number[], tp: number, a: number): Hop | null {
  const x = logs(views);
  const bl = baseline(x, tp);
  if (!bl) return null;
  const z = (d: number, b: Base) => (x[d] - b.m) / b.s;
  const end = Math.min(tp + 3, a);
  let S = -Infinity, maxV = 0;
  for (let d = tp; d <= end; d++) { S = Math.max(S, z(d, bl)); maxV = Math.max(maxV, views[d]); }
  let onset: number | null = null;
  for (let d = Math.max(0, tp - 7); d <= end; d++) if (z(d, bl) >= 3) { onset = d; break; }
  const lag = onset === null ? null : onset - tp;
  const multiple = maxV / Math.max(bl.med, 1);
  const pass_raw = S >= 3 && multiple >= 1.5 && lag !== null && lag >= 0;
  // time-shift placebo: fake onsets tp-7k, k = 3.. while the fake baseline window fits in the series
  let K = 0, hits = 0;
  for (let k = 3; ; k++) {
    const t = tp - 7 * k;
    if (t - 111 < 0) break;
    const b2 = baseline(x, t)!;
    let s2 = -Infinity;
    for (let d = t; d <= t + 3; d++) s2 = Math.max(s2, z(d, b2));
    K++;
    if (s2 >= S) hits++;
  }
  const p_time = (1 + hits) / (1 + K);
  let maxAbs = 0;
  for (let d = Math.max(0, tp - 7); d <= a; d++) maxAbs = Math.max(maxAbs, Math.abs(z(d, bl)));
  const calm = maxAbs < 1 && multiple < 1.25;
  return { median_views: bl.med, s_stat: S, onset_lag: lag, multiple, p_time, n_placebo: K, pass_raw, calm, max_abs_z: maxAbs };
}

export interface SeedScreen {
  onset: number | null; z_peak: number | null; peak_multiple: number | null; peak_day: number | null;
  median_views: number; max_abs_z14: number | null; base: number;
}
// Seed onset: first day d in [a-10, a] with z >= 3 (baseline for d) in a run (consecutive z >= 3) that reaches z >= 5.
export function seedScreen(views: number[], a: number): SeedScreen {
  const x = logs(views);
  let onset: number | null = null;
  for (let d = Math.max(111, a - 10); d <= a; d++) {
    const b = baseline(x, d);
    if (!b) continue;
    const zz = (e: number) => (x[e] - b.m) / b.s;
    if (zz(d) < 3) continue;
    let e = d, runMax = -Infinity;
    while (e <= a && zz(e) >= 3) { runMax = Math.max(runMax, zz(e)); e++; }
    if (runMax >= 5) { onset = d; break; }
  }
  const baseIdx = onset ?? a;
  const bl = baseline(x, baseIdx)!;
  let z_peak: number | null = null, peak_multiple: number | null = null, peak_day: number | null = null;
  if (onset !== null) {
    let pk = -1, zp = -Infinity;
    for (let d = onset; d <= a; d++) {
      if (views[d] > pk) { pk = views[d]; peak_day = d; }
      zp = Math.max(zp, (x[d] - bl.m) / bl.s);
    }
    z_peak = zp; peak_multiple = pk / Math.max(bl.med, 1);
  }
  let max_abs_z14: number | null = null;
  const b14 = baseline(x, a - 13);
  if (b14) {
    max_abs_z14 = 0;
    for (let d = a - 13; d <= a; d++) max_abs_z14 = Math.max(max_abs_z14, Math.abs((x[d] - b14.m) / b14.s));
  }
  return { onset, z_peak, peak_multiple, peak_day, median_views: bl.med, max_abs_z14, base: baseIdx };
}

// ------------------------------------------------------------------ Wikidata facts
export interface Facts { qid: string; p31: string[]; date_of_death: string | null; sitelinks: number; enwiki: string | null; label: string | null; desc: string | null }
export function factsFromEntity(e: any): Facts | null {
  if (!e || e.missing !== undefined || !e.id) return null;
  const claims = e.claims ?? {};
  const ids = (p: string) => (claims[p] ?? []).filter((c: any) => c.rank !== "deprecated")
    .map((c: any) => c.mainsnak?.datavalue?.value?.id).filter(Boolean);
  let dod: string | null = null;
  for (const c of claims["P570"] ?? []) {
    const t: string | undefined = c.mainsnak?.datavalue?.value?.time;
    const prec: number | undefined = c.mainsnak?.datavalue?.value?.precision;
    if (t && (prec ?? 11) >= 11) { const m = t.match(/^\+?(\d{4,})-(\d{2})-(\d{2})/); if (m) { dod = `${m[1].slice(-4)}-${m[2]}-${m[3]}`; break; } }
    else if (t) { const m = t.match(/^\+?(\d{4,})-(\d{2})/); if (m) { dod = `${m[1].slice(-4)}-${m[2] === "00" ? "01" : m[2]}-01`; break; } }
  }
  const sl = e.sitelinks ?? {};
  const wikis = Object.keys(sl).filter((k) => /wiki$/.test(k) && !/^(commons|species|meta|wikidata|mediawiki|sources|outreach|abstract)wiki$/.test(k));
  return {
    qid: e.id, p31: ids("P31"), date_of_death: dod, sitelinks: wikis.length,
    enwiki: sl.enwiki?.title ?? null, label: e.labels?.en?.value ?? null, desc: e.descriptions?.en?.value ?? null,
  };
}

export async function wbEntities(b: Budget, params: Record<string, string>): Promise<Record<string, any>> {
  const j = await actionApi(b, "www.wikidata.org", { action: "wbgetentities", ...params });
  return j.entities ?? {};
}

// Fetch Wikidata facts for up to N QIDs (50 per request).
export async function factsFor(b: Budget, qids: string[]): Promise<Map<string, Facts>> {
  const out = new Map<string, Facts>();
  for (let i = 0; i < qids.length; i += 50) {
    const ents = await wbEntities(b, { ids: qids.slice(i, i + 50).join("|"), props: "claims|sitelinks|descriptions|labels", languages: "en" });
    for (const e of Object.values(ents)) { const f = factsFromEntity(e); if (f) out.set(f.qid, f); }
  }
  return out;
}

// Class entities: label + P279 parents; ingest them, then fetch one more level of unknown parents.
export async function resolveClasses(b: Budget, unknown: string[], rounds = 2): Promise<number> {
  let n = 0, todo = [...new Set(unknown)].filter((q) => /^Q\d+$/.test(q));
  for (let r = 0; r < rounds && todo.length && b.left() > 2; r++) {
    const rows: any[] = [];
    for (let i = 0; i < todo.length && b.left() > 1; i += 50) {
      const ents = await wbEntities(b, { ids: todo.slice(i, i + 50).join("|"), props: "labels|claims", languages: "en" });
      for (const e of Object.values(ents) as any[]) {
        if (!e?.id || e.missing !== undefined) continue;
        const parents = ((e.claims?.P279 ?? []) as any[]).map((c) => c.mainsnak?.datavalue?.value?.id).filter(Boolean);
        rows.push({ class_qid: e.id, label: e.labels?.en?.value ?? null, parents });
      }
    }
    if (!rows.length) break;
    const res = await rpc("ripples_ingest_articles", { p_rows: { classes: rows } });
    n += rows.length;
    todo = (res?.unknown_classes ?? []) as string[];
  }
  return n;
}

// ------------------------------------------------------------------ DB helpers
export async function rpc(fn: string, args: Record<string, unknown>): Promise<any> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data;
}

export async function jobDone(job: number | null | undefined, ok: boolean, err: string | null, b: Budget, result: unknown = null) {
  if (!job) return;
  try {
    await rpc("ripples_job_done", { p_job: job, p_ok: ok, p_err: err ? err.slice(0, 500) : null, p_calls: b.wm, p_result: result });
  } catch (e) { console.error("job_done failed", job, e); }
}

// Standard entry: token check, then run `work` in the background (respond 202 at once so pg_net never times out).
export function serve(work: (body: any, b: Budget) => Promise<unknown>) {
  Deno.serve(async (req) => {
    const token = req.headers.get("x-collector-token") ?? "";
    const { data: ok } = await db.rpc("check_collector_token", { t: token });
    if (!ok) return new Response("forbidden", { status: 403 });
    const body = await req.json().catch(() => ({}));
    const jobId: number | null = body?.job?.id ?? null;
    const b = new Budget(Math.max(1, Math.min(100, Number(body?.budget ?? 100))));
    const task = (async () => {
      try {
        const result = await work(body, b);
        await jobDone(jobId, true, null, b, result ?? null);
        return result;
      } catch (e) {
        const msg = e instanceof Stop ? `rate_limited: ${e.message}` : e instanceof OutOfBudget ? `budget: ${e.message}` : (e instanceof Error ? e.message : String(e));
        console.error("job failed", jobId, msg);
        await jobDone(jobId, false, msg, b, null);
        return { error: msg };
      }
    })();
    if (body?.sync === true) {
      const r = await task;
      return Response.json({ version: KN_VERSION, wm_calls: b.wm, result: r });
    }
    // @ts-ignore EdgeRuntime is provided by the Supabase edge runtime
    EdgeRuntime.waitUntil(task);
    return Response.json({ accepted: true, job: jobId, version: KN_VERSION }, { status: 202 });
  });
}

// ------------------------------------------------------------------ titles
export const SKIP_TITLE = /^(Main_Page|Main Page|Special:|Wikipedia:|Portal:|File:|Help:|Template:|Category:|User:|Talk:|Draft:|Spezial:|Especial:|Spécial:|Speciale:|Служебная:|特別:|Especial:|Hauptseite|Wikipédia:|Página_principal|Página principal|Pagina_principale|Pagina principale|Заглавная_страница|メインページ|-$|Undefined$)/i;
// list / index / date / year articles (SPEC §5.2 candidate exclusions)
export const LIST_TITLE = /^(lists? of|index of|outline of|timeline of|glossary of|deaths in|bibliography of|discography of)\b|\(disambiguation\)$|^\d{1,4}s?( BC| AD| BCE| CE)?$|^\d{4}s? in |^(January|February|March|April|May|June|July|August|September|October|November|December)( \d{1,2})?(,? \d{4})?$|^\d{1,2} (January|February|March|April|May|June|July|August|September|October|November|December)$|^\d{4}–\d{2,4}$|^\d{4} (January|February|March|April|May|June|July|August|September|October|November|December)$/i;
export const norm = (s: string) => s.replaceAll("_", " ").trim();
