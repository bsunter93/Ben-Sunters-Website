// att-downstream — state-level "downstream" panels for engine 6.3 batch b3 (Ripple Map).
//
// Why a separate function: att-econ's fred_state mode holds the 6.3 panels (minwage, leih, cons, ur, bppriv). b3 needs
// series further down the chain from a shock — housing inventory and total jobs — and this small function adds them
// without redeploying att-econ. Rows are written exactly as fred_state writes them (source 'fred.state', geo 'US-XX',
// first-release values via ALFRED output_type=4 where the series is revised), so att_fx63_panel_build reads them with no change.
//
// Series (FRED, one call per state per series, monthly):
//   ACTLISCOU{ST}   Realtor.com active listing count        metric 'listings'   (from 2016-07; latest values, see SERIES)
//   NEWLISCOU{ST}   Realtor.com new listing count           metric 'newlist'    (from 2016-07)
//   MEDDAYONMAR{ST} Realtor.com median days on market       metric 'dom'        (from 2016-07)
//   {ST}NA          BLS total nonfarm employment            metric 'nonfarm'
//   {ST}SRVO/EDUH/FIRE/GOVT/PBSV/TRAD/MFG  BLS CES state supersector jobs (batch b6, "unexpected places"), first releases
//                   from 2000: other services (repair, personal care), private education & health, financial activities
//                   (insurance), government, professional & business services, trade/transport/utilities, manufacturing
//
// mode "cdc" (batch b6): CDC/NCHS weekly all-cause deaths by state (keyless Socrata API on data.cdc.gov), source
// 'cdc.deaths' metric 'all': 2014-2019 from 3yf8-kanr (final), 2020+ from r8kw-7aab (provisional, group "By Week").
// New York City is reported separately and is added into New York. Weeks ending within 8 weeks of the file's
// data_as_of are NOT ingested (death reporting lags; recent weeks are incomplete); recent weeks are re-read daily.
//
// Demarcation (same rules as att-econ): key read at run time from Vault via public.att_secret and never logged; honest
// UA; serial requests with >= 1.1 s spacing (FRED allows 120/min); STOP for the run on 429/503; a missing id (400/404)
// is recorded once and never retried; aggregate public statistics only. Auth: x-collector-token checked against Vault.
import { createClient } from "jsr:@supabase/supabase-js@2";

const VERSION = "2026-09-27.d4";
const UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)";
const FRED = "https://api.stlouisfed.org/fred/series/observations";
const STATES = ["AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
  "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT",
  "VT","VA","WA","WV","WI","WY"];
const SERIES = [
  // Realtor.com inventory: ALFRED first-release vintages only reach back to 2020-03 (the series were re-issued), which
  // leaves too few pre-split events. Listing counts are not revised in any material way, so these read latest values
  // (output_type 1) from 2016-07 and say so in meta.rt. Nonfarm jobs are revised (benchmarks): first releases only.
  { id: (s: string) => `ACTLISCOU${s}`, metric: "listings", first: false },
  { id: (s: string) => `NEWLISCOU${s}`, metric: "newlist", first: false },
  { id: (s: string) => `MEDDAYONMAR${s}`, metric: "dom", first: false },
  { id: (s: string) => `${s}NA`, metric: "nonfarm", first: true, from: "2000-01-01" }, // long history for batch b4
  // batch b6: where else does a shock land? CES supersectors, first releases, long history
  ...["SRVO", "EDUH", "FIRE", "GOVT", "PBSV", "TRAD", "MFG"].map((m) =>
    ({ id: (s: string) => `${s}${m}`, metric: m.toLowerCase(), first: true, from: "2000-01-01" })),
];
const CDC = "https://data.cdc.gov/resource";
const CDC_KEY = "cdc.deaths";
const NAME2ST: Record<string, string> = { "Alabama":"AL","Alaska":"AK","Arizona":"AZ","Arkansas":"AR","California":"CA","Colorado":"CO",
  "Connecticut":"CT","Delaware":"DE","District of Columbia":"DC","Florida":"FL","Georgia":"GA","Hawaii":"HI","Idaho":"ID","Illinois":"IL",
  "Indiana":"IN","Iowa":"IA","Kansas":"KS","Kentucky":"KY","Louisiana":"LA","Maine":"ME","Maryland":"MD","Massachusetts":"MA",
  "Michigan":"MI","Minnesota":"MN","Mississippi":"MS","Missouri":"MO","Montana":"MT","Nebraska":"NE","Nevada":"NV","New Hampshire":"NH",
  "New Jersey":"NJ","New Mexico":"NM","New York":"NY","New York City":"NY","North Carolina":"NC","North Dakota":"ND","Ohio":"OH",
  "Oklahoma":"OK","Oregon":"OR","Pennsylvania":"PA","Rhode Island":"RI","South Carolina":"SC","South Dakota":"SD","Tennessee":"TN",
  "Texas":"TX","Utah":"UT","Vermont":"VT","Virginia":"VA","Washington":"WA","West Virginia":"WV","Wisconsin":"WI","Wyoming":"WY" };
const STATE_KEY = "econ.fred.downstream";
const MAX_CALLS = 60, SPACING_MS = 1100, WALL_MS = 100_000;

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const today = () => new Date().toISOString().slice(0, 10);
const addDays = (d: string, n: number) => new Date(Date.parse(d + "T00:00:00Z") + n * 864e5).toISOString().slice(0, 10);
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { "content-type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const tok = req.headers.get("x-collector-token") ?? "";
  const { data: okTok } = tok ? await db.rpc("check_collector_token", { t: tok }) : { data: false };
  if (okTok !== true) return json({ error: "unauthorized" }, 401);
  const body = await req.json().catch(() => ({}));
  const force = body?.params?.force === true;
  const t0 = Date.now();
  const errors: string[] = [];
  if (body?.params?.mode === "cdc") return json(await cdc(force, errors, t0));

  const { data: keyData } = await db.rpc("att_secret", { p_name: "fred_api_key" });
  const key = typeof keyData === "string" ? keyData.trim() : "";
  if (!key) return json({ ok: false, version: VERSION, error: "fred_api_key not configured" });
  const scrub = (s: string) => s.split(key).join("***");

  const { data: st0 } = await db.rpc("att_state_get", { p_k: STATE_KEY });
  const st = (st0 ?? {}) as { fetched?: Record<string, string>; missing?: string[] };
  const fetched = st.fetched ?? {}, missing = new Set(st.missing ?? []);
  const save = () => db.rpc("att_state_set", { p_k: STATE_KEY, p_v: { fetched, missing: [...missing].sort() } });

  let calls = 0, rows = 0, done = 0, stop: string | null = null;
  outer: for (const s of SERIES) {
    for (const stc of STATES) {
      const id = s.id(stc);
      if (missing.has(id) && !force) continue;
      const last = fetched[id];
      if (last && last >= addDays(today(), -32) && !force) continue;
      if (calls >= MAX_CALLS || Date.now() - t0 > WALL_MS) { stop = "run_cap"; break outer; }
      if (calls > 0) await sleep(SPACING_MS);
      calls++;
      const q = new URLSearchParams({ series_id: id, api_key: key, file_type: "json", limit: "100000",
        observation_start: last ? addDays(today(), -400) : ("from" in s && s.from ? s.from : "2015-01-01") });
      if (s.first) { q.set("output_type", "4"); q.set("realtime_start", "1776-07-04"); q.set("realtime_end", "9999-12-31"); }
      let res: Response;
      try {
        res = await fetch(`${FRED}?${q}`, { headers: { "user-agent": UA, accept: "application/json" }, signal: AbortSignal.timeout(30_000) });
      } catch (e) { errors.push(scrub(`${id}: ${e instanceof Error ? e.message : String(e)}`)); continue; }
      if (res.status === 429 || res.status === 503) { await res.body?.cancel(); stop = `host_killed_${res.status}`; break outer; }
      if (res.status === 400 || res.status === 404) { await res.body?.cancel(); missing.add(id); continue; }
      if (!res.ok) { await res.body?.cancel(); errors.push(`${id}: http ${res.status}`); continue; }
      const j = await res.json().catch(() => null);
      const out: Record<string, unknown>[] = [];
      for (const o of Array.isArray(j?.observations) ? j.observations : []) {
        const v = Number(o?.value);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(o?.date)) || o?.value === "." || !Number.isFinite(v)) continue;
        const rs = /^\d{4}-\d{2}-\d{2}$/.test(String(o?.realtime_start)) ? String(o.realtime_start) : "";
        out.push({ source: "fred.state", key: id, metric: s.metric, geo: `US-${stc}`, day: o.date, value: v,
          meta: s.first ? { rt: "first", vintage: rs, released: rs, monthly: true, via: "att-downstream" }
                        : { rt: "latest", vintage: rs, monthly: true, via: "att-downstream" } });
      }
      if (out.length) {
        const { data: r, error } = await db.rpc("att_ingest", { p_rows: out });
        if (error) { errors.push(`att_ingest ${id}: ${error.message}`); continue; }
        rows += Number((r as { rows?: number } | null)?.rows ?? out.length);
      }
      fetched[id] = today(); done++;
      if (done % 10 === 0) await save();
    }
  }
  await save();
  const total = SERIES.length * STATES.length;
  const left = total - Object.keys(fetched).length - missing.size;
  return json({ ok: true, version: VERSION, calls, series_fetched: done, rows, left, n_missing: missing.size,
    stop, errors: errors.slice(0, 10), ms: Date.now() - t0 });
});

// ---- mode "cdc": weekly all-cause deaths by state -----------------------------------------------------------------
async function cdcGet(path: string): Promise<{ rows?: Record<string, string>[]; stop?: string; err?: string }> {
  let res: Response;
  try {
    res = await fetch(`${CDC}/${path}`, { headers: { "user-agent": UA, accept: "application/json" }, signal: AbortSignal.timeout(60_000) });
  } catch (e) { return { err: e instanceof Error ? e.message : String(e) }; }
  if (res.status === 429 || res.status === 503) { await res.body?.cancel(); return { stop: `host_killed_${res.status}` }; }
  if (!res.ok) { await res.body?.cancel(); return { err: `http ${res.status}` }; }
  const j = await res.json().catch(() => null);
  return Array.isArray(j) ? { rows: j } : { err: "not an array" };
}

async function cdc(force: boolean, errors: string[], t0: number) {
  const { data: st0 } = await db.rpc("att_state_get", { p_k: CDC_KEY });
  const st = (st0 ?? {}) as { hist_done?: boolean; last?: string };
  if (st.last === today() && !force) return { ok: true, version: VERSION, mode: "cdc", skipped: "already ran today" };
  // week_end -> state -> deaths (NY + NYC summed)
  const acc = new Map<string, number>();
  const add = (name: string, day: string, v: number) => {
    const s = NAME2ST[name]; if (!s || !/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(v)) return;
    const k = `${s}|${day}`; acc.set(k, (acc.get(k) ?? 0) + v);
  };
  let stop: string | undefined, calls = 0, asOf = "";
  if (!st.hist_done || force) {
    calls++;
    const r = await cdcGet("3yf8-kanr.json?$select=jurisdiction_of_occurrence,weekendingdate,allcause&$limit=50000");
    if (r.stop) stop = r.stop; else if (r.err) errors.push(`3yf8-kanr: ${r.err}`);
    for (const o of r.rows ?? []) add(String(o.jurisdiction_of_occurrence), String(o.weekendingdate).slice(0, 10), Number(o.allcause));
  }
  if (!stop) {
    await sleep(2000); calls++;
    const since = st.hist_done && !force ? addDays(today(), -210) : "2019-12-01";
    const r = await cdcGet(`r8kw-7aab.json?$select=data_as_of,state,end_date,total_deaths&$where=${encodeURIComponent(`group='By Week' AND end_date >= '${since}'`)}&$limit=50000`);
    if (r.stop) stop = r.stop; else if (r.err) errors.push(`r8kw-7aab: ${r.err}`);
    for (const o of r.rows ?? []) {
      asOf = asOf || String(o.data_as_of ?? "").slice(0, 10);
      if (o.total_deaths == null) continue;
      add(String(o.state), String(o.end_date).slice(0, 10), Number(o.total_deaths));
    }
  }
  const cutoff = asOf ? addDays(asOf, -56) : addDays(today(), -63);
  const out: Record<string, unknown>[] = [];
  for (const [k, v] of acc) {
    const [s, day] = k.split("|");
    if (day > cutoff) continue;
    out.push({ source: "cdc.deaths", key: `cdc_deaths_all_${s}`, metric: "all", geo: `US-${s}`, day, value: v,
      meta: { rt: "latest", provisional: day >= "2020-01-01", as_of: asOf || null, weekly: true, via: "att-downstream" } });
  }
  let rows = 0;
  for (let i = 0; i < out.length; i += 2000) {
    const { data: r, error } = await db.rpc("att_ingest", { p_rows: out.slice(i, i + 2000) });
    if (error) { errors.push(`att_ingest cdc: ${error.message}`); break; }
    rows += Number((r as { rows?: number } | null)?.rows ?? 0);
  }
  if (!stop && !errors.length) await db.rpc("att_state_set", { p_k: CDC_KEY, p_v: { hist_done: true, last: today(), as_of: asOf, cutoff } });
  return { ok: !stop && !errors.length, version: VERSION, mode: "cdc", calls, weeks_states: out.length, rows, cutoff, stop: stop ?? null,
    errors: errors.slice(0, 10), ms: Date.now() - t0 };
}
