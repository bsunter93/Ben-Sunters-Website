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
//
// Demarcation (same rules as att-econ): key read at run time from Vault via public.att_secret and never logged; honest
// UA; serial requests with >= 1.1 s spacing (FRED allows 120/min); STOP for the run on 429/503; a missing id (400/404)
// is recorded once and never retried; aggregate public statistics only. Auth: x-collector-token checked against Vault.
import { createClient } from "jsr:@supabase/supabase-js@2";

const VERSION = "2026-09-26.d2";
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
  { id: (s: string) => `${s}NA`, metric: "nonfarm", first: true },
];
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
        observation_start: last ? addDays(today(), -400) : "2015-01-01" });
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
