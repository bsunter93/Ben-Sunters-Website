// att-world — Ripples v5 attention layer, WORLD / REAL-ECONOMY collector (W7).
// Spec: ATTENTION_STACK §1 (#11-16, #33, #34), §3.3 (att-world row), §3.4 (cron 06:21), §3.6 (backfill), §4 (discovery
// candidates for usgs.eq / gdacs / fema.decl), §6.1 (physical sources use a same-weekday baseline downstream).
// Budgets: DEMARCATION Q6 as stored in att_sources (1 req / 5 s per host; IEM 1 req / 10 s). Every HTTP request goes
// through politeFetch (registered source + host list, RED list, kill switch, host lease, robots.txt, spacing floor,
// per-run cap, per-day budget). No NWS api.weather.gov (RED in att.ts): IEM is the documented substitute.
//
// Modes (body.mode):
//   tsa        TSA checkpoint travel numbers. Current year from /travel/passenger-volumes; earlier years from the
//              /travel/passenger-volumes/<year> pages (2019..). Series tsa.pax / n / US / 'checkpoint' (travellers).
//   usgs       USGS ComCat (fdsnws event query, geojson). Two queries per window: minfelt=1 (Did-You-Feel-It) and
//              minmagnitude=4.5. Daily series (geo ALL): 'felt' (sum of DYFI responses of the day's events, aux = number
//              of felt events), 'm45' (M4.5+ count, aux = max magnitude), 'sig' (events with sig >= 600, aux = max sig);
//              per-event 'ev:<id>' / metric 'felt' (DYFI responses, aux = magnitude) for events with felt >= 25.
//              The daily run re-reads the last 30 days because DYFI counts keep growing after an event.
//   iem        Iowa Environmental Mesonet /api/1/vtec/sbw_interval.json: storm-based warnings issued per UTC day,
//              counted per VTEC phenomena.significance (distinct wfo/phenomena/significance/eventid/year), key = ph_sig
//              (e.g. 'TO.W', 'SV.W', 'FF.W'), '__total__' = all warnings (significance W). Geo US. <= 1 request / 10 s.
//   fema       OpenFEMA DisasterDeclarationsSummaries v2. Per declaration day: distinct disasters for 'all', 'DR', 'EM',
//              'FM' and 'it:<incidentType>' (aux = designated areas). Geo US. Attribution: the OpenFEMA notice (source row).
//   gdacs      GDACS RSS snapshot: current events per type (EQ, TC, FL, VO, DR, WF, '__all__'): metric 'n' (aux = orange
//              + red), metric 'pop' (population exposed in orange/red events); per-event 'ev:<type><id>' / 'alert'
//              (alert score, aux = population) for orange/red events. No history exists (warm-up source).
//   mta        MTA daily ridership via NY Open Data Socrata (sayj-mze2): key = mode (subway, bus, lirr, mnr, sir, aar,
//              bt ...), geo US-NY.
//   citibike   Citi Bike monthly trip archive (tripdata S3 bucket, virtual-host URL). The Jersey City files (JC-YYYYMM,
//              1-3 MB) are unzipped in memory and counted per local start day: key 'jc' (value = trips, aux = member
//              trips), geo US-NJ. The NYC monthly files are ~1 GB, far beyond the 110 s / CPU budget: reported partial.
//   hiringlab  Indeed Hiring Lab job postings index (GitHub raw CSV, CC BY 4.0). Conditional GET (If-None-Match with the
//              stored ETag): the 12 MB sector file is downloaded only when upstream changed. Keys = sector slug, metric
//              'total' | 'new'; '__total__' from the aggregate file (value = SA index, aux = NSA).
//   all        The modes above in sequence (params.only to restrict), each skipped when the wall budget runs low.
//   backfill   History (>= 400 days; TSA from 2019, MTA from 2020-03): params.source (att_sources id) or params.only.
//              Resumable (att_state 'world.bf.<source>'); partial runs report next_cursor and are re-run by the job queue.
//   ping       No outbound requests.
// Only counts, levels and indices are stored. Response bodies are read transiently (e.g. IEM rows carry forecaster
// names and FEMA rows carry county names: never stored). Discovery candidate labels are place / event names only.
import {
  addDays, configGet, errMsg, ingest, ingestCandidates, type ObsRow, politeFetch, type Run, serve, stateGet, stateSet,
} from "./att.ts";

export const WORLD_VERSION = "2026-09-25.w1";

type Sub = "tsa" | "usgs" | "iem" | "fema" | "gdacs" | "mta" | "hiringlab" | "citibike";
const SUBS: Sub[] = ["tsa", "usgs", "iem", "fema", "gdacs", "mta", "hiringlab", "citibike"];
const SRC: Record<Sub, string> = {
  tsa: "tsa.pax", usgs: "usgs.eq", iem: "iem.warn", fema: "fema.decl", gdacs: "gdacs", mta: "mta.ridership",
  hiringlab: "hiringlab.postings", citibike: "citibike.trips",
};
const SUB_OF: Record<string, Sub> = Object.fromEntries(SUBS.map((s) => [SRC[s], s]));

// ------------------------------------------------------------------ config (att_config 'world' overrides these)
interface Cfg {
  backfill_days: number;
  tsa: { first_year: number };
  mta: { history_from: string; daily_days: number };
  usgs: { daily_days: number; window_days: number; felt_event_min: number; cand_felt: number; cand_sig: number; cand_days: number };
  iem: { window_days: number; keys: string[] };
  fema: { daily_days: number; cand_days: number };
  gdacs: { cand_days: number };
  hiringlab: { daily_days: number };
  citibike: { max_zip_mb: number; files_per_run: number; systems: string[]; min_day_of_month: number };
}
const DEFAULTS: Cfg = {
  backfill_days: 420,
  tsa: { first_year: 2019 },
  mta: { history_from: "2020-03-01", daily_days: 21 },
  usgs: { daily_days: 30, window_days: 105, felt_event_min: 25, cand_felt: 50, cand_sig: 600, cand_days: 3 },
  iem: { window_days: 30, keys: ["TO.W", "SV.W", "FF.W", "EW.W", "SQ.W", "MA.W", "DS.W", "FL.W", "FA.Y"] },
  fema: { daily_days: 30, cand_days: 3 },
  gdacs: { cand_days: 10 },
  hiringlab: { daily_days: 60 },
  citibike: { max_zip_mb: 40, files_per_run: 2, systems: ["JC"], min_day_of_month: 6 },
};
async function cfg(): Promise<Cfg> {
  let c: Record<string, any> = {};
  try { c = ((await configGet("world")) ?? {}) as Record<string, any>; } catch { /* defaults */ }
  const out: any = { ...DEFAULTS };
  for (const k of Object.keys(DEFAULTS) as (keyof Cfg)[]) {
    const d = (DEFAULTS as any)[k];
    out[k] = d && typeof d === "object" && !Array.isArray(d) ? { ...d, ...(c[k] ?? {}) } : (c[k] ?? d);
  }
  return out as Cfg;
}

interface Ctx { cfg: Cfg; backfill: boolean; from: string; to: string }

// ------------------------------------------------------------------ helpers
const todayUtc = () => new Date().toISOString().slice(0, 10);
function days(from: string, to: string): string[] {
  const out: string[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) out.push(d);
  return out;
}
const minD = (a: string, b: string) => (a < b ? a : b);
const maxD = (a: string, b: string) => (a > b ? a : b);
const slug = (s: string) => s.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/&/g, " and ")
  .replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 60);
function titleCase(s: string): string {
  return s.toLowerCase().replace(/\b([a-z])/g, (m) => m.toUpperCase()).replace(/\s+/g, " ").trim();
}

/** GET through politeFetch; returns the response only for 2xx/304 (else records the status and returns null). */
async function get(run: Run, source: string, url: string, headers: Record<string, string> = {}, timeoutMs = 60_000): Promise<Response | null> {
  const res = await politeFetch(run, url, { source, headers, timeoutMs });
  if (!res) return null;
  if (res.status === 304 || res.ok) return res;
  await res.body?.cancel();
  run.errors.push(`${source}: http ${res.status} ${new URL(url).pathname}`);
  return null;
}

/** Call f for every line of a (large) text response without building a line array; CPU-lean indexOf scanning. */
async function eachLine(res: Response, f: (line: string) => void, stream?: ReadableStream<any>): Promise<number> {
  const body: ReadableStream<any> | null = stream ?? res.body;
  if (!body) return 0;
  const reader = body.pipeThrough(new TextDecoderStream()).getReader();
  let rest = "", n = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    const buf = rest + value;
    let start = 0, i: number;
    while ((i = buf.indexOf("\n", start)) >= 0) {
      const end = i > start && buf.charCodeAt(i - 1) === 13 ? i - 1 : i;
      f(buf.slice(start, end)); n++;
      start = i + 1;
    }
    rest = buf.slice(start);
  }
  if (rest) { f(rest); n++; }
  return n;
}

async function bfState(src: string): Promise<Record<string, any>> {
  return ((await stateGet(`world.bf.${src}`).catch(() => null)) ?? {}) as Record<string, any>;
}
async function bfSave(run: Run, src: string, v: Record<string, any>) {
  if (!run.dryRun) await stateSet(`world.bf.${src}`, { ...v, at: new Date().toISOString(), version: WORLD_VERSION });
}

async function write(run: Run, rows: ObsRow[]) {
  const r = await ingest(run, rows);
  return r.rows;
}

// ------------------------------------------------------------------ TSA
function parseTsa(html: string): Array<[string, number]> {
  const out: Array<[string, number]> = [];
  const re = /<td[^>]*>\s*(\d{1,2})\/(\d{1,2})\/(\d{4})\s*<\/td>\s*<td[^>]*>\s*([\d,]+)\s*<\/td>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html))) {
    const day = `${m[3]}-${m[1].padStart(2, "0")}-${m[2].padStart(2, "0")}`;
    const v = Number(m[4].replaceAll(",", ""));
    if (Number.isFinite(v) && v > 1000) out.push([day, v]);
  }
  return out;
}
async function subTsa(run: Run, c: Ctx) {
  const t0 = Date.now(), src = "tsa.pax";
  const curYear = Number(todayUtc().slice(0, 4));
  const st = c.backfill ? await bfState(src) : {};
  const doneYears = new Set<number>(st.done_years ?? []);
  const years: number[] = [];
  if (c.backfill) {
    for (let y = Math.min(curYear, Number(c.from.slice(0, 4))); y <= curYear; y++) if (!doneYears.has(y) || y === curYear) years.push(y);
  } else {
    years.push(curYear);
    if (Number(todayUtc().slice(5, 7)) === 1 && Number(todayUtc().slice(8, 10)) <= 10) years.push(curYear - 1);
  }
  let rows = 0, pages = 0, latest = "";
  for (const y of years.sort((a, b) => b - a)) {
    if (run.outOfTime(12_000)) { run.partial = true; break; }
    const url = y === curYear ? "https://www.tsa.gov/travel/passenger-volumes" : `https://www.tsa.gov/travel/passenger-volumes/${y}`;
    const res = await get(run, src, url);
    if (!res) { if (c.backfill) run.partial = true; continue; }
    const lo = c.backfill ? c.from : addDays(c.to, -13); // daily: re-write the last two weeks only
    const pts = parseTsa(await res.text()).filter(([d]) => d >= lo && d <= c.to && d.startsWith(String(y)));
    pages++;
    const obs: ObsRow[] = pts.map(([day, v]) => ({ source: src, key: "checkpoint", geo: "US", metric: "n", day, value: v }));
    rows += await write(run, obs);
    for (const [d] of pts) if (d > latest) latest = d;
    if (pts.length) doneYears.add(y);
  }
  if (c.backfill) {
    const complete = years.every((y) => doneYears.has(y)) && !run.partial;
    await bfSave(run, src, { done_years: [...doneYears].sort(), complete });
    if (!complete) run.nextCursor = { source: src, done_years: [...doneYears] };
  }
  run.source({ source: src, status: pages ? (run.partial && c.backfill ? "partial" : "ok") : "http_error", keys: 1, rows, ms: Date.now() - t0,
    note: `${pages} page(s), latest ${latest || "-"}` });
  run.extra.tsa_latest = latest || null;
}

// ------------------------------------------------------------------ MTA (Socrata)
async function subMta(run: Run, c: Ctx) {
  const t0 = Date.now(), src = "mta.ridership";
  const from = c.backfill ? minD(c.from, c.cfg.mta.history_from) : addDays(c.to, -(c.cfg.mta.daily_days - 1));
  const qs = new URLSearchParams({
    "$select": "date,mode,count", "$where": `date >= '${from}T00:00:00' AND date <= '${c.to}T00:00:00'`,
    "$order": "date", "$limit": "50000",
  });
  const res = await get(run, src, `https://data.ny.gov/resource/sayj-mze2.json?${qs.toString().replaceAll("+", "%20")}`, { accept: "application/json" }, 90_000);
  if (!res) { run.source({ source: src, status: "http_error", ms: Date.now() - t0 }); if (c.backfill) run.partial = true; return; }
  const data = await res.json().catch(() => null) as Array<{ date?: string; mode?: string; count?: string }> | null;
  if (!Array.isArray(data)) { run.errors.push("mta: bad json"); run.source({ source: src, status: "http_error", ms: Date.now() - t0 }); return; }
  const obs: ObsRow[] = [];
  const modes = new Set<string>();
  let latest = "";
  for (const r of data) {
    const day = String(r.date ?? "").slice(0, 10);
    const v = Number(r.count);
    const key = slug(String(r.mode ?? ""));
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !key || !Number.isFinite(v) || v < 0) continue;
    obs.push({ source: src, key, geo: "US-NY", metric: "n", day, value: v });
    modes.add(key);
    if (day > latest) latest = day;
  }
  const rows = await write(run, obs);
  if (c.backfill) await bfSave(run, src, { complete: true, from, rows: obs.length });
  run.source({ source: src, status: "ok", keys: modes.size, rows, ms: Date.now() - t0, note: `${[...modes].join(",")}; latest ${latest || "-"}` });
  run.extra.mta_latest = latest || null;
}

// ------------------------------------------------------------------ USGS ComCat
interface Quake { id: string; day: string; t: number; mag: number; felt: number; sig: number; alert: string | null; place: string }
async function usgsQuery(run: Run, from: string, to: string, extra: string): Promise<Quake[] | null> {
  const url = `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&eventtype=earthquake&orderby=time-asc&limit=20000` +
    `&starttime=${from}T00:00:00&endtime=${addDays(to, 1)}T00:00:00&${extra}`;
  const res = await get(run, "usgs.eq", url, { accept: "application/json" }, 90_000);
  if (!res) return null;
  const j = await res.json().catch(() => null) as { features?: any[] } | null;
  if (!j || !Array.isArray(j.features)) { run.errors.push("usgs: bad json"); return null; }
  if (j.features.length >= 20000) run.errors.push(`usgs: window ${from}..${to} hit the 20000 limit`);
  const out: Quake[] = [];
  for (const f of j.features) {
    const p = f?.properties ?? {};
    const t = Number(p.time);
    if (!f?.id || !Number.isFinite(t)) continue;
    out.push({ id: String(f.id), t, day: new Date(t).toISOString().slice(0, 10), mag: Number(p.mag ?? NaN),
      felt: Number(p.felt ?? 0) || 0, sig: Number(p.sig ?? 0) || 0, alert: p.alert ?? null, place: String(p.place ?? "") });
  }
  return out;
}
function quakeRegion(place: string): string {
  const m = /\bof\s+(.+)$/.exec(place);
  return (m ? m[1] : place).replace(/\s+/g, " ").trim();
}
async function usgsWindow(run: Run, c: Ctx, from: string, to: string): Promise<{ rows: number; ok: boolean; felt: Quake[] }> {
  const u = c.cfg.usgs;
  const felt = await usgsQuery(run, from, to, "minfelt=1");
  const big = await usgsQuery(run, from, to, "minmagnitude=4.5");
  const obs: ObsRow[] = [];
  const span = days(from, to);
  if (felt) {
    const sum = new Map<string, number>(), cnt = new Map<string, number>();
    for (const q of felt) {
      sum.set(q.day, (sum.get(q.day) ?? 0) + q.felt);
      cnt.set(q.day, (cnt.get(q.day) ?? 0) + 1);
      if (q.felt >= u.felt_event_min && q.day >= from && q.day <= to) {
        obs.push({ source: "usgs.eq", key: `ev:${q.id}`, geo: "ALL", metric: "felt", day: q.day, value: q.felt,
          aux: Number.isFinite(q.mag) ? q.mag : null });
      }
    }
    for (const d of span) obs.push({ source: "usgs.eq", key: "felt", geo: "ALL", metric: "n", day: d, value: sum.get(d) ?? 0, aux: cnt.get(d) ?? 0 });
  }
  if (big) {
    const cnt = new Map<string, number>(), mx = new Map<string, number>();
    for (const q of big) {
      cnt.set(q.day, (cnt.get(q.day) ?? 0) + 1);
      if (Number.isFinite(q.mag)) mx.set(q.day, Math.max(mx.get(q.day) ?? 0, q.mag));
    }
    for (const d of span) obs.push({ source: "usgs.eq", key: "m45", geo: "ALL", metric: "n", day: d, value: cnt.get(d) ?? 0, aux: mx.get(d) ?? null });
  }
  if (felt && big) {
    const seen = new Map<string, Quake>();
    for (const q of [...felt, ...big]) seen.set(q.id, q);
    const cnt = new Map<string, number>(), mx = new Map<string, number>();
    for (const q of seen.values()) {
      if (q.sig < u.cand_sig) continue;
      cnt.set(q.day, (cnt.get(q.day) ?? 0) + 1);
      mx.set(q.day, Math.max(mx.get(q.day) ?? 0, q.sig));
    }
    for (const d of span) obs.push({ source: "usgs.eq", key: "sig", geo: "ALL", metric: "n", day: d, value: cnt.get(d) ?? 0, aux: mx.get(d) ?? null });
  }
  const rows = await write(run, obs);
  return { rows, ok: !!felt && !!big, felt: [...(felt ?? []), ...(big ?? [])] };
}
async function subUsgs(run: Run, c: Ctx) {
  const t0 = Date.now(), src = "usgs.eq", u = c.cfg.usgs;
  let rows = 0, windows = 0, ok = true;
  let quakes: Quake[] = [];
  if (!c.backfill) {
    const r = await usgsWindow(run, c, addDays(c.to, -(u.daily_days - 1)), c.to);
    rows += r.rows; windows++; ok = r.ok; quakes = r.felt;
  } else {
    const st = await bfState(src);
    // walk windows newest -> oldest; cursor = oldest day already done
    let cursorTo = typeof st.done_from === "string" && st.to === c.to ? addDays(st.done_from, -1) : c.to;
    while (cursorTo >= c.from) {
      if (run.outOfTime(25_000)) { run.partial = true; break; }
      const wFrom = maxD(c.from, addDays(cursorTo, -(u.window_days - 1)));
      const r = await usgsWindow(run, c, wFrom, cursorTo);
      rows += r.rows; windows++;
      if (!r.ok) { ok = false; run.partial = true; break; }
      await bfSave(run, src, { to: c.to, from: c.from, done_from: wFrom, complete: wFrom <= c.from });
      cursorTo = addDays(wFrom, -1);
    }
    if (cursorTo >= c.from) run.nextCursor = { source: src, next_to: cursorTo };
  }
  // discovery candidates (daily only): strongly felt / significant / PAGER orange-red events of the last few days
  if (!c.backfill && quakes.length) {
    const since = addDays(c.to, -(u.cand_days - 1));
    const best = new Map<string, Record<string, unknown>>();
    for (const q of quakes) {
      if (q.day < since || q.day > c.to) continue;
      const alert = q.alert === "orange" || q.alert === "red";
      if (!(q.felt >= u.cand_felt || q.sig >= u.cand_sig || alert)) continue;
      const region = quakeRegion(q.place);
      if (!region) continue;
      const label = `${region} earthquake`;
      const evidence = Math.min(1, Math.max(Math.log10(q.felt + 1) / 3, q.sig / 1000, alert ? 0.8 : 0));
      const prev = best.get(label);
      if (!prev || Number(prev.evidence) < evidence) {
        best.set(label, { day: c.to, source: src, geo: "ALL", label, value: q.felt, evidence: Math.round(evidence * 1000) / 1000,
          meta: { k: q.id, score: q.sig, kind: "quake" } });
      }
    }
    if (best.size) await ingestCandidates(run, [...best.values()]);
    run.extra.usgs_candidates = best.size;
  }
  run.source({ source: src, status: ok ? (run.partial && c.backfill ? "partial" : "ok") : "http_error", keys: 3, rows, ms: Date.now() - t0, note: `${windows} window(s)` });
}

// ------------------------------------------------------------------ IEM storm-based warnings
async function iemWindow(run: Run, c: Ctx, from: string, to: string, known: Set<string>): Promise<{ rows: number; ok: boolean; counts: Map<string, Map<string, number>> }> {
  const url = `https://mesonet.agron.iastate.edu/api/1/vtec/sbw_interval.json?begints=${from}T00:00:00Z&endts=${addDays(to, 1)}T00:00:00Z`;
  const res = await get(run, "iem.warn", url, { accept: "application/json" }, 90_000);
  const counts = new Map<string, Map<string, number>>(); // day -> ph_sig -> n
  if (!res) return { rows: 0, ok: false, counts };
  const j = await res.json().catch(() => null) as { data?: any[] } | null;
  if (!j || !Array.isArray(j.data)) { run.errors.push("iem: bad json"); return { rows: 0, ok: false, counts }; }
  const seen = new Set<string>();
  for (const r of j.data) {
    const issue = String(r?.utc_issue ?? r?.utc_polygon_begin ?? "");
    const day = issue.slice(0, 10);
    const ph = String(r?.phenomena ?? ""), sg = String(r?.significance ?? "");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day < from || day > to || !/^[A-Z]{2}$/.test(ph) || !/^[A-Z]$/.test(sg)) continue;
    const id = `${r?.wfo}|${ph}|${sg}|${r?.eventid}|${r?.year ?? day.slice(0, 4)}`;
    if (seen.has(id)) continue; // one count per VTEC event (the issuance)
    seen.add(id);
    const k = `${ph}.${sg}`;
    known.add(k);
    const m = counts.get(day) ?? new Map<string, number>();
    counts.set(day, m);
    m.set(k, (m.get(k) ?? 0) + 1);
    if (sg === "W") m.set("__total__", (m.get("__total__") ?? 0) + 1);
  }
  const obs: ObsRow[] = [];
  for (const d of days(from, to)) {
    const m = counts.get(d) ?? new Map<string, number>();
    for (const k of [...known, "__total__"]) obs.push({ source: "iem.warn", key: k, geo: "US", metric: "n", day: d, value: m.get(k) ?? 0 });
  }
  return { rows: await write(run, obs), ok: true, counts };
}
async function subIem(run: Run, c: Ctx) {
  const t0 = Date.now(), src = "iem.warn";
  const known = new Set<string>(c.cfg.iem.keys);
  const ks = ((await stateGet("world.iem.keys").catch(() => null)) ?? []) as string[];
  for (const k of ks) known.add(k);
  let rows = 0, windows = 0, ok = true;
  if (!c.backfill) {
    const r = await iemWindow(run, c, c.to, c.to, known);
    rows = r.rows; windows = 1; ok = r.ok;
    const m = r.counts.get(c.to);
    if (m) run.extra.iem_today = Object.fromEntries([...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8));
  } else {
    const st = await bfState(src);
    let cursorTo = typeof st.done_from === "string" && st.to === c.to ? addDays(st.done_from, -1) : c.to;
    while (cursorTo >= c.from) {
      if (run.outOfTime(30_000)) { run.partial = true; break; }
      const wFrom = maxD(c.from, addDays(cursorTo, -(c.cfg.iem.window_days - 1)));
      const r = await iemWindow(run, c, wFrom, cursorTo, known);
      rows += r.rows; windows++;
      if (!r.ok) { ok = false; run.partial = true; break; }
      await bfSave(run, src, { to: c.to, from: c.from, done_from: wFrom, complete: wFrom <= c.from });
      cursorTo = addDays(wFrom, -1);
    }
    if (cursorTo >= c.from) run.nextCursor = { source: src, next_to: cursorTo };
  }
  if (!run.dryRun) await stateSet("world.iem.keys", [...known].sort()).catch(() => undefined);
  run.source({ source: src, status: ok ? (run.partial && c.backfill ? "partial" : "ok") : "http_error", keys: known.size + 1, rows, ms: Date.now() - t0, note: `${windows} window(s)` });
}

// ------------------------------------------------------------------ OpenFEMA
const US_STATES: Record<string, string> = {
  AL: "Alabama", AK: "Alaska", AZ: "Arizona", AR: "Arkansas", CA: "California", CO: "Colorado", CT: "Connecticut", DE: "Delaware",
  FL: "Florida", GA: "Georgia", HI: "Hawaii", ID: "Idaho", IL: "Illinois", IN: "Indiana", IA: "Iowa", KS: "Kansas", KY: "Kentucky",
  LA: "Louisiana", ME: "Maine", MD: "Maryland", MA: "Massachusetts", MI: "Michigan", MN: "Minnesota", MS: "Mississippi",
  MO: "Missouri", MT: "Montana", NE: "Nebraska", NV: "Nevada", NH: "New Hampshire", NJ: "New Jersey", NM: "New Mexico",
  NY: "New York", NC: "North Carolina", ND: "North Dakota", OH: "Ohio", OK: "Oklahoma", OR: "Oregon", PA: "Pennsylvania",
  RI: "Rhode Island", SC: "South Carolina", SD: "South Dakota", TN: "Tennessee", TX: "Texas", UT: "Utah", VT: "Vermont",
  VA: "Virginia", WA: "Washington", WV: "West Virginia", WI: "Wisconsin", WY: "Wyoming", DC: "Washington, D.C.",
  PR: "Puerto Rico", GU: "Guam", VI: "U.S. Virgin Islands", AS: "American Samoa", MP: "Northern Mariana Islands",
};
function femaLabel(title: string, incident: string, state: string, day: string): string {
  const t = title.trim();
  const named = /\b(HURRICANE|TROPICAL STORM|TYPHOON)\s+([A-Z][A-Z'-]+)/.exec(t);
  if (named) return `${titleCase(named[1])} ${titleCase(named[2])}`;
  if (/fire/i.test(incident) && /\bFIRE\b/.test(t) && !/SEVERE|STORM|FLOOD/.test(t)) return titleCase(t.replace(/\s*\(.*\)\s*$/, ""));
  const st = US_STATES[state] ?? state;
  return `${day.slice(0, 4)} ${st} ${incident.toLowerCase()}`.trim();
}
async function subFema(run: Run, c: Ctx) {
  const t0 = Date.now(), src = "fema.decl";
  const from = c.backfill ? c.from : addDays(c.to, -(c.cfg.fema.daily_days - 1));
  const recs: any[] = [];
  let ok = true;
  for (let skip = 0; skip < 60_000; skip += 10_000) {
    const qs = new URLSearchParams({
      "$select": "disasterNumber,declarationDate,declarationType,incidentType,declarationTitle,state",
      "$filter": `declarationDate ge '${from}T00:00:00.000Z' and declarationDate le '${c.to}T23:59:59.999Z'`,
      "$orderby": "declarationDate", "$top": "10000", "$skip": String(skip),
    });
    const res = await get(run, src, `https://www.fema.gov/api/open/v2/DisasterDeclarationsSummaries?${qs.toString().replaceAll("+", "%20")}`,
      { accept: "application/json" }, 90_000);
    if (!res) { ok = false; break; }
    const j = await res.json().catch(() => null) as { DisasterDeclarationsSummaries?: any[] } | null;
    const page = j?.DisasterDeclarationsSummaries;
    if (!Array.isArray(page)) { ok = false; run.errors.push("fema: bad json"); break; }
    recs.push(...page);
    if (page.length < 10_000) break;
  }
  if (!ok) { run.source({ source: src, status: "http_error", ms: Date.now() - t0 }); if (c.backfill) run.partial = true; return; }
  const types = new Set<string>(((await stateGet("world.fema.types").catch(() => null)) ?? []) as string[]);
  const dis = new Map<string, Map<string, Set<number>>>(); // day -> key -> disasters
  const areas = new Map<string, Map<string, number>>();
  const decl = new Map<number, { day: string; type: string; it: string; title: string; state: string; areas: number }>();
  for (const r of recs) {
    const day = String(r?.declarationDate ?? "").slice(0, 10);
    const num = Number(r?.disasterNumber);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(num)) continue;
    const dt = String(r?.declarationType ?? "").toUpperCase();
    const it = String(r?.incidentType ?? "Other");
    const itKey = `it:${slug(it)}`;
    types.add(itKey);
    const keys = ["all", dt, itKey].filter((k) => k && /^(all|DR|EM|FM|it:[a-z0-9_]+)$/.test(k));
    const dm = dis.get(day) ?? new Map<string, Set<number>>(); dis.set(day, dm);
    const am = areas.get(day) ?? new Map<string, number>(); areas.set(day, am);
    for (const k of keys) {
      const s = dm.get(k) ?? new Set<number>(); dm.set(k, s); s.add(num);
      am.set(k, (am.get(k) ?? 0) + 1);
    }
    const d = decl.get(num) ?? { day, type: dt, it, title: String(r?.declarationTitle ?? ""), state: String(r?.state ?? ""), areas: 0 };
    d.areas++;
    decl.set(num, d);
  }
  const allKeys = ["all", "DR", "EM", "FM", ...[...types].sort()];
  const obs: ObsRow[] = [];
  for (const d of days(from, c.to)) {
    for (const k of allKeys) {
      obs.push({ source: src, key: k, geo: "US", metric: "n", day: d, value: dis.get(d)?.get(k)?.size ?? 0, aux: areas.get(d)?.get(k) ?? 0 });
    }
  }
  const rows = await write(run, obs);
  if (!run.dryRun) await stateSet("world.fema.types", [...types].sort()).catch(() => undefined);
  if (c.backfill) await bfSave(run, src, { complete: true, from, records: recs.length });
  // candidates: new declarations in the last few days (the "became an official disaster" hop)
  if (!c.backfill) {
    const since = addDays(c.to, -(c.cfg.fema.cand_days - 1));
    const best = new Map<string, Record<string, unknown>>();
    for (const [num, d] of decl) {
      if (d.day < since) continue;
      const label = femaLabel(d.title, d.it, d.state, d.day);
      const ev = d.type === "DR" ? 0.6 : d.type === "EM" ? 0.45 : 0.3;
      const prev = best.get(label);
      if (!prev || Number(prev.evidence) < ev) {
        best.set(label, { day: c.to, source: src, geo: /^[A-Z]{2}$/.test(d.state) ? `US-${d.state}` : "US", label, value: d.areas,
          evidence: ev, meta: { k: `${d.type}-${num}`, kind: slug(d.it) } });
      }
    }
    if (best.size) await ingestCandidates(run, [...best.values()]);
    run.extra.fema_candidates = best.size;
  }
  run.source({ source: src, status: "ok", keys: allKeys.length, rows, ms: Date.now() - t0, note: `${recs.length} records, ${decl.size} declarations` });
}

// ------------------------------------------------------------------ GDACS RSS
function tag(item: string, t: string): string {
  const open = item.indexOf(`<${t}`);
  if (open < 0) return "";
  const gt = item.indexOf(">", open);
  if (gt < 0 || item[gt - 1] === "/") return "";
  const close = item.indexOf(`</${t}>`, gt);
  return close < 0 ? "" : item.slice(gt + 1, close).trim();
}
function attr(item: string, t: string, a: string): string {
  const open = item.indexOf(`<${t}`);
  if (open < 0) return "";
  const gt = item.indexOf(">", open);
  const m = new RegExp(`\\s${a}="([^"]*)"`).exec(item.slice(open, gt));
  return m ? m[1] : "";
}
const GDACS_TYPES = ["EQ", "TC", "FL", "VO", "DR", "WF"];
const GDACS_NAME: Record<string, string> = { EQ: "earthquake", FL: "floods", VO: "eruption", DR: "drought", WF: "wildfires" };
async function subGdacs(run: Run, c: Ctx) {
  const t0 = Date.now(), src = "gdacs";
  if (c.backfill) { run.source({ source: src, status: "ok", rows: 0, ms: 0, note: "no history available (warm-up source)" }); return; }
  const res = await get(run, src, "https://www.gdacs.org/xml/rss.xml", { accept: "application/rss+xml, application/xml" });
  if (!res) { run.source({ source: src, status: "http_error", ms: Date.now() - t0 }); return; }
  const xml = await res.text();
  const n = new Map<string, number>(), orr = new Map<string, number>(), pop = new Map<string, number>();
  const obs: ObsRow[] = [];
  const cands = new Map<string, Record<string, unknown>>();
  const since = addDays(c.to, -(c.cfg.gdacs.cand_days - 1));
  let items = 0;
  for (let i = xml.indexOf("<item>"); i >= 0; i = xml.indexOf("<item>", i + 6)) {
    const j = xml.indexOf("</item>", i);
    if (j < 0) break;
    const it = xml.slice(i, j);
    items++;
    if (tag(it, "gdacs:iscurrent").toLowerCase() !== "true") continue;
    const type = tag(it, "gdacs:eventtype").toUpperCase();
    if (!/^[A-Z]{2}$/.test(type)) continue;
    const level = tag(it, "gdacs:alertlevel").toLowerCase();
    const score = Number(tag(it, "gdacs:alertscore")) || (level === "red" ? 3 : level === "orange" ? 2 : 1);
    const people = Number(attr(it, "gdacs:population", "value")) || 0;
    const high = level === "orange" || level === "red";
    for (const k of [type, "__all__"]) {
      n.set(k, (n.get(k) ?? 0) + 1);
      if (high) { orr.set(k, (orr.get(k) ?? 0) + 1); pop.set(k, (pop.get(k) ?? 0) + people); }
    }
    if (!high) continue;
    const id = tag(it, "gdacs:eventid");
    if (/^\d+$/.test(id)) obs.push({ source: src, key: `ev:${type}${id}`, geo: "ALL", metric: "alert", day: c.to, value: score, aux: people });
    const fromDate = new Date(tag(it, "gdacs:fromdate"));
    const fd = Number.isFinite(fromDate.getTime()) ? fromDate.toISOString().slice(0, 10) : c.to;
    if (fd < since) continue;
    const country = tag(it, "gdacs:country").split(",")[0].trim();
    const name = tag(it, "gdacs:eventname").replace(/-\d{2}$/, "").trim();
    let label = "";
    if (type === "TC" && name) label = `Cyclone ${titleCase(name)}`;
    else if (type === "VO" && name) label = titleCase(name);
    else if (country) label = `${fd.slice(0, 4)} ${country} ${GDACS_NAME[type] ?? type.toLowerCase()}`;
    if (!label) continue;
    const ev = level === "red" ? 0.9 : 0.6;
    const prev = cands.get(label);
    if (!prev || Number(prev.evidence) < ev) {
      cands.set(label, { day: c.to, source: src, geo: tag(it, "gdacs:iso3") || "ALL", label, value: people, evidence: ev,
        meta: { k: `${type}${id}`, kind: level } });
    }
  }
  for (const k of [...GDACS_TYPES, "__all__", ...[...n.keys()].filter((k) => !GDACS_TYPES.includes(k) && k !== "__all__")]) {
    obs.push({ source: src, key: k, geo: "ALL", metric: "n", day: c.to, value: n.get(k) ?? 0, aux: orr.get(k) ?? 0 });
    obs.push({ source: src, key: k, geo: "ALL", metric: "pop", day: c.to, value: pop.get(k) ?? 0 });
  }
  const rows = await write(run, obs);
  if (cands.size) await ingestCandidates(run, [...cands.values()]);
  run.extra.gdacs = { items, current: n.get("__all__") ?? 0, orange_red: orr.get("__all__") ?? 0, candidates: cands.size };
  run.source({ source: src, status: "ok", keys: n.size, rows, ms: Date.now() - t0, note: `${items} items, ${n.get("__all__") ?? 0} current` });
}

// ------------------------------------------------------------------ Hiring Lab (GitHub raw CSV, conditional GET)
const HL_BASE = "https://raw.githubusercontent.com/hiring-lab/job_postings_tracker/master/US/";
function splitCsv(line: string): string[] {
  if (line.indexOf('"') < 0) return line.split(",");
  const out: string[] = [];
  let cur = "", q = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (q) { if (ch === '"') { if (line[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += ch; }
    else if (ch === '"') q = true;
    else if (ch === ",") { out.push(cur); cur = ""; }
    else cur += ch;
  }
  out.push(cur);
  return out;
}
async function subHiringlab(run: Run, c: Ctx) {
  const t0 = Date.now(), src = "hiringlab.postings";
  const st = ((await stateGet("world.hiringlab").catch(() => null)) ?? {}) as { etag?: Record<string, string>; complete?: boolean; latest?: string };
  const etags: Record<string, string> = { ...(st.etag ?? {}) };
  // first run (no stored ETag) or explicit backfill: full 400+ day window; otherwise the last N days of a changed file
  const full = c.backfill || !st.complete;
  const from = full ? c.from : addDays(c.to, -(c.cfg.hiringlab.daily_days - 1));
  let rows = 0, fetched = 0, unchanged = 0, latest = st.latest ?? "";
  const keys = new Set<string>();
  let ok = true;
  for (const file of ["aggregate_job_postings_US.csv", "job_postings_by_sector_US.csv"]) {
    if (run.outOfTime(20_000)) { run.partial = true; ok = false; break; }
    const hdr: Record<string, string> = { accept: "text/csv, text/plain" };
    if (!full && etags[file]) hdr["if-none-match"] = etags[file];
    const res = await get(run, src, HL_BASE + file, hdr, 90_000);
    if (!res) { ok = false; continue; }
    if (res.status === 304) { await res.body?.cancel(); unchanged++; continue; }
    fetched++;
    const agg = file.startsWith("aggregate");
    let cols: string[] | null = null;
    let iDate = 0, iVal = 2, iAux = -1, iVar = 3, iName = 4;
    const obs: ObsRow[] = [];
    await eachLine(res, (line) => {
      if (!cols) {
        cols = splitCsv(line).map((s) => s.trim().toLowerCase());
        iDate = cols.indexOf("date");
        iVar = cols.indexOf("variable");
        if (agg) { iVal = cols.findIndex((x) => x.endsWith("_sa")); iAux = cols.findIndex((x) => x.endsWith("_nsa")); }
        else { iVal = cols.indexOf("indeed_job_postings_index"); iName = cols.indexOf("display_name"); }
        return;
      }
      const d = line.slice(0, 10);
      if (d < from || d > c.to) return;           // cheap prefilter (date is the first column)
      const f = splitCsv(line);
      const v = Number(f[iVal]);
      if (!Number.isFinite(v)) return;
      const metric = /new/i.test(f[iVar] ?? "") ? "new" : "total";
      const key = agg ? "__total__" : slug(f[iName] ?? "");
      if (!key) return;
      keys.add(key);
      const aux = iAux >= 0 && Number.isFinite(Number(f[iAux])) ? Number(f[iAux]) : null;
      obs.push({ source: src, key, geo: "US", metric, day: d, value: v, aux });
      if (d > latest) latest = d;
    });
    rows += await write(run, obs);
    const et = res.headers.get("etag");
    if (et) etags[file] = et;
  }
  if (!run.dryRun && ok) await stateSet("world.hiringlab", { etag: etags, complete: true, latest, at: new Date().toISOString() });
  if (c.backfill && ok) await bfSave(run, src, { complete: true, from });
  run.extra.hiringlab = { fetched, unchanged, latest: latest || null };
  run.source({ source: src, status: ok ? "ok" : "partial", keys: keys.size, rows, ms: Date.now() - t0,
    note: unchanged === 2 ? "upstream unchanged (304)" : `${fetched} file(s) downloaded; latest ${latest || "-"}` });
}

// ------------------------------------------------------------------ Citi Bike trip archive
async function inflateEntry(buf: Uint8Array, off: number, compSize: number, method: number): Promise<ReadableStream<any>> {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  if (dv.getUint32(off, true) !== 0x04034b50) throw new Error("zip: bad local header");
  const start = off + 30 + dv.getUint16(off + 26, true) + dv.getUint16(off + 28, true);
  const raw: ReadableStream<any> = new Blob([buf.slice(start, start + compSize)]).stream();
  if (method === 0) return raw;
  if (method !== 8) throw new Error(`zip: method ${method}`);
  return raw.pipeThrough(new DecompressionStream("deflate-raw"));
}
function zipEntries(buf: Uint8Array): Array<{ name: string; off: number; comp: number; method: number }> {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 70_000); i--) if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  if (eocd < 0) throw new Error("zip: no end of central directory");
  const count = dv.getUint16(eocd + 10, true);
  let p = dv.getUint32(eocd + 16, true);
  const out = [];
  for (let k = 0; k < count && p + 46 <= buf.length; k++) {
    if (dv.getUint32(p, true) !== 0x02014b50) break;
    const method = dv.getUint16(p + 10, true), comp = dv.getUint32(p + 20, true);
    const nl = dv.getUint16(p + 28, true), xl = dv.getUint16(p + 30, true), cl = dv.getUint16(p + 32, true);
    const off = dv.getUint32(p + 42, true);
    const name = new TextDecoder().decode(buf.subarray(p + 46, p + 46 + nl));
    out.push({ name, off, comp, method });
    p += 46 + nl + xl + cl;
  }
  return out;
}
async function s3List(run: Run, prefix: string): Promise<Array<{ key: string; size: number }> | null> {
  const res = await get(run, "citibike.trips", `https://tripdata.s3.amazonaws.com/?list-type=2&prefix=${encodeURIComponent(prefix)}`, { accept: "application/xml" });
  if (!res) return null;
  const xml = await res.text();
  const out: Array<{ key: string; size: number }> = [];
  const re = /<Key>([^<]+)<\/Key>[\s\S]*?<Size>(\d+)<\/Size>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml))) out.push({ key: m[1], size: Number(m[2]) });
  return out;
}
async function citibikeFile(run: Run, key: string, maxBytes: number): Promise<{ days: Map<string, [number, number]>; bytes: number } | null> {
  const res = await get(run, "citibike.trips", `https://tripdata.s3.amazonaws.com/${encodeURIComponent(key)}`, {}, 60_000);
  if (!res) return null;
  const len = Number(res.headers.get("content-length") ?? 0);
  if (len > maxBytes) { await res.body?.cancel(); run.errors.push(`citibike: ${key} is ${len} bytes > cap`); return null; }
  const buf = new Uint8Array(await res.arrayBuffer());
  const days = new Map<string, [number, number]>();
  for (const e of zipEntries(buf)) {
    if (!/\.csv$/i.test(e.name) || /(^|\/)(__MACOSX|\.)/.test(e.name)) continue;
    const stream = await inflateEntry(buf, e.off, e.comp, e.method);
    let iStart = -1, iMember = -1, header = true;
    await eachLine(res, (line) => {
      if (header) {
        const cols = splitCsv(line).map((s) => s.trim().toLowerCase());
        iStart = cols.findIndex((x) => x === "started_at" || x === "starttime" || x === "start time");
        iMember = cols.findIndex((x) => x === "member_casual" || x === "usertype" || x === "user type");
        header = false;
        return;
      }
      if (!line) return;
      // started_at is the 3rd field in the current layout; ride ids / types never contain commas
      let f: string[] | null = null;
      let startVal: string;
      if (iStart === 2) {
        const a = line.indexOf(","), b = line.indexOf(",", a + 1), c2 = line.indexOf(",", b + 1);
        startVal = line.slice(b + 1, c2 < 0 ? undefined : c2);
      } else { f = splitCsv(line); startVal = f[iStart] ?? ""; }
      startVal = startVal.replace(/^"/, "");
      const d = startVal.slice(0, 10);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return;
      const lastVal = (f ? f[iMember] : line.slice(line.lastIndexOf(",") + 1)) ?? "";
      const member = /member|subscriber/i.test(lastVal) ? 1 : 0;
      const cur = days.get(d) ?? [0, 0];
      cur[0]++; cur[1] += member;
      days.set(d, cur);
    }, stream);
  }
  return { days, bytes: buf.length };
}
async function subCitibike(run: Run, c: Ctx) {
  const t0 = Date.now(), src = "citibike.trips", cc = c.cfg.citibike;
  const st = ((await stateGet("world.citibike").catch(() => null)) ?? {}) as { done?: Record<string, number>; nyc?: Record<string, unknown> };
  const done: Record<string, number> = { ...(st.done ?? {}) };
  const lastMonth = addDays(`${todayUtc().slice(0, 7)}-01`, -1).slice(0, 7); // YYYY-MM of the last complete month
  const want: string[] = [];
  if (c.backfill) {
    for (let m = c.from.slice(0, 7); m <= lastMonth; m = addDays(`${m}-28`, 7).slice(0, 7)) want.push(m);
  } else {
    if (Number(todayUtc().slice(8, 10)) >= cc.min_day_of_month || run.params.force) want.push(lastMonth);
  }
  const todo = want.filter((m) => !done[`JC-${m.replace("-", "")}`]).sort().reverse();
  if (!todo.length) {
    run.source({ source: src, status: "ok", rows: 0, ms: Date.now() - t0, note: c.backfill ? "all months done" : "nothing due (monthly archive; next check after the 6th)" });
    if (c.backfill) await bfSave(run, src, { complete: true, months: Object.keys(done).length });
    return;
  }
  let rows = 0, files = 0;
  const list = await s3List(run, "JC-");
  if (!list) { run.source({ source: src, status: "http_error", ms: Date.now() - t0 }); run.partial = true; return; }
  const byMonth = new Map<string, { key: string; size: number }>();
  for (const o of list) {
    const m = /^JC-(\d{6})-citibike-tripdata(\.csv)?\.zip$/i.exec(o.key);
    if (m) byMonth.set(m[1], o);
  }
  let missing = 0;
  for (const m of todo) {
    const ym = m.replace("-", "");
    const o = byMonth.get(ym);
    if (!o) { missing++; continue; }
    if (files >= cc.files_per_run || run.outOfTime(25_000)) { run.partial = true; break; }
    if (o.size > cc.max_zip_mb * 1024 * 1024) { run.errors.push(`citibike: ${o.key} too large`); continue; }
    const r = await citibikeFile(run, o.key, cc.max_zip_mb * 1024 * 1024);
    if (!r) { run.partial = true; break; }
    files++;
    const obs: ObsRow[] = [];
    for (const [d, [n, mem]] of r.days) {
      if (!d.startsWith(m)) continue; // a month file holds rides started in that month (local time)
      obs.push({ source: src, key: "jc", geo: "US-NJ", metric: "n", day: d, value: n, aux: mem });
    }
    rows += await write(run, obs);
    done[`JC-${ym}`] = obs.length;
  }
  // NYC: record the size of the latest monthly file; it is far beyond the edge-function budget, so it is not fetched
  let nycNote = "";
  const nyc = await s3List(run, `${lastMonth.replace("-", "")}-citibike`);
  if (nyc && nyc.length) {
    const mb = Math.round(nyc[0].size / 1048576);
    nycNote = `NYC ${nyc[0].key} ${mb} MB > ${cc.max_zip_mb} MB cap: not processed (partial)`;
    st.nyc = { key: nyc[0].key, mb, checked: todayUtc() };
  }
  if (!run.dryRun) await stateSet("world.citibike", { done, nyc: st.nyc ?? null });
  const complete = want.every((m) => done[`JC-${m.replace("-", "")}`] || !byMonth.has(m.replace("-", "")));
  if (c.backfill) {
    await bfSave(run, src, { complete, months: Object.keys(done).length });
    if (!complete) { run.partial = true; run.nextCursor = { source: src, months_done: Object.keys(done).length }; }
  }
  run.extra.citibike = { files, months_done: Object.keys(done).length, missing, nyc: st.nyc ?? null };
  run.source({ source: src, status: "partial", keys: 1, rows, ms: Date.now() - t0,
    note: `JC ${files} file(s) this run; ${nycNote || "NYC monthly archive (~1 GB) not processed"}` });
}

// ------------------------------------------------------------------ modes
const HANDLERS: Record<Sub, (run: Run, c: Ctx) => Promise<void>> = {
  tsa: subTsa, usgs: subUsgs, iem: subIem, fema: subFema, gdacs: subGdacs, mta: subMta, hiringlab: subHiringlab, citibike: subCitibike,
};
async function runSubs(run: Run, subs: Sub[], backfill: boolean) {
  const c0 = await cfg();
  run.extra.world_version = WORLD_VERSION;
  const bf = run.body?.backfill ?? {};
  const to = typeof bf.to === "string" && bf.to <= run.asOf ? bf.to : run.asOf;
  for (const s of subs) {
    if (run.outOfTime(8_000)) { run.partial = true; run.source({ source: SRC[s], status: "partial", note: "out of wall time before start" }); continue; }
    let from = typeof bf.from === "string" ? bf.from : addDays(to, -(c0.backfill_days - 1));
    if (s === "tsa" && backfill) from = minD(from, `${c0.tsa.first_year}-01-01`);
    const c: Ctx = { cfg: c0, backfill, from, to };
    try { await HANDLERS[s](run, c); }
    catch (e) { run.errors.push(`${s}: ${errMsg(e)}`); run.source({ source: SRC[s], status: "http_error", note: errMsg(e).slice(0, 200) }); }
  }
}
function pickSubs(run: Run, dflt: Sub[]): Sub[] {
  const only = run.params.only;
  if (Array.isArray(only) && only.length) return dflt.filter((s) => only.includes(s) || only.includes(SRC[s]));
  return dflt;
}
async function modeAll(run: Run) { await runSubs(run, pickSubs(run, SUBS), false); }
async function modeBackfill(run: Run) {
  const s = run.params.source as string | undefined;
  const subs = s ? (SUB_OF[s] ? [SUB_OF[s]] : []) : pickSubs(run, SUBS);
  if (!subs.length) { run.errors.push(`backfill: unknown source '${s}'`); return; }
  await runSubs(run, subs, true);
}
const single = (s: Sub) => async (run: Run) => { await runSubs(run, [s], run.params.backfill === true); };

serve("att-world", {
  all: modeAll,
  backfill: modeBackfill,
  tsa: single("tsa"), usgs: single("usgs"), iem: single("iem"), fema: single("fema"), gdacs: single("gdacs"),
  mta: single("mta"), hiringlab: single("hiringlab"), citibike: single("citibike"),
  ping: async (run: Run) => { run.extra.pong = true; run.extra.world_version = WORLD_VERSION; },
});
