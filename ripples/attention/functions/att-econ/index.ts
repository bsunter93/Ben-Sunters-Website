// att-econ — Ripple Map v6 (WS-A) OUTCOME collector: energy, rates/FX/claims, jobs, prices, weather, business formation.
// Spec: ENGINE_SPEC §1.1 (channels PHYS/ECON/JOBS), §3.1 (level / rate transforms), §3.6 + §7 (release looks),
// §9 (API budget), §10.3 (edge-function additions); OWNER_DECISIONS D-7 (keys via public.att_secret only), D-9 (NOAA).
//
// Modes (body.mode):
//   fred        FRED series/observations for the configured national series (rates, FX, commodities, claims) and all
//               53 <ST>ICLAIMS state initial-claims series. Daily series every day; weekly series on Thu/Fri or when
//               stale. Stored: source fred / metric rate|level|count / geo US|US-XX / key = FRED id; meta.vintage =
//               realtime_start of the value held; weekly series also meta.released = first-release date
//               (output_type=4). Third-party series (Cboe VIX, S&P 500, ICE BofA, Freddie Mac) are never requested.
//   calendar    FRED release/dates for CPI, Employment Situation, FOMC press release, UI weekly claims, GDP, PCE
//               (past + scheduled) -> ripples.att_release_dates (release looks, att_family_calendar).
//   eia_930     EIA API v2 electricity/rto/daily-region-data, type D (demand, MWh) for every respondent (~65 balancing
//               authorities + regions + US48), each in its local timezone. Backfill from 2015-07-01.
//   eia_prices  EIA API v2: WTI / Brent / jet fuel spot (daily), Henry Hub spot (daily), retail regular gasoline by PADD
//               and on-highway diesel (weekly).
//   bls_ces     BLS API v2: CES all-employee SA series (supersectors + ~260 industries), monthly.
//   bls_cpi     BLS API v2: ~45 CPI-U item indexes (SA where published, NSA fallback), monthly.
//   dol_claims  DOL ETA ar539.csv: weekly state initial claims (ic) and continued weeks claimed (cw).
//   noaa        NOAA CDO v2 GHCN-Daily TMAX/TMIN (metric temp: value = TMAX degC, aux = TMIN degC) and PRCP (mm) for
//               ~70 first-order stations; daily update (last 14 days) or backfill (params.from, default 2019-01-01).
//   census_bfs  Census Business Formation Statistics weekly business applications (national + state), CSV route.
//   backfill    params.source in (fred | eia.930 | eia.prices | bls.ces | bls.cpi_items | dol.claims | noaa.ghcnd |
//               census.bfs): resumable full history (att_state 'econ.bf.<source>').
//   probe       params.url (+ params.source, params.key_param): one GET through politeFetch, returns status + a short
//               scrubbed head. For endpoint discovery only.
//   ping        no requests.
// Every request goes through politeFetch (registered source, hosts, robots.txt, budget, kill switch, host lease).
// Keys: public.att_secret(<name>) at run time only; scrubbed from everything written to att_runs (wsa.ts).
import { addDays, db, errMsg, ingest, type ObsRow, politeFetch, type Run, serve, stateGet, stateSet } from "./att.ts";
import { getJson, getText, r4, scrubStr, secret, todayUtc, wrap } from "./wsa.ts";

export const ECON_VERSION = "2026-09-25.e1";

// ------------------------------------------------------------------ series catalogues
type Kind = "rate" | "level" | "count";
interface FredS { id: string; kind: Kind; weekly?: boolean; geo?: string }
const FRED_NATIONAL: FredS[] = [
  { id: "DGS3MO", kind: "rate" }, { id: "DGS2", kind: "rate" }, { id: "DGS5", kind: "rate" }, { id: "DGS10", kind: "rate" },
  { id: "DGS30", kind: "rate" }, { id: "T10YIE", kind: "rate" }, { id: "T5YIE", kind: "rate" }, { id: "T10Y2Y", kind: "rate" },
  { id: "DFF", kind: "rate" }, { id: "SOFR", kind: "rate" },
  { id: "DEXUSEU", kind: "level" }, { id: "DEXJPUS", kind: "level" }, { id: "DEXUSUK", kind: "level" },
  { id: "DEXCAUS", kind: "level" }, { id: "DEXMXUS", kind: "level" }, { id: "DEXCHUS", kind: "level" },
  { id: "DTWEXBGS", kind: "level" },
  { id: "DCOILWTICO", kind: "level" }, { id: "DCOILBRENTEU", kind: "level" }, { id: "DHHNGSP", kind: "level" },
  { id: "ICSA", kind: "count", weekly: true }, { id: "ICNSA", kind: "count", weekly: true }, { id: "CCSA", kind: "count", weekly: true },
  { id: "GASREGW", kind: "level", weekly: true },
];
export const STATES = ["AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
  "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","PR","RI","SC","SD","TN","TX","UT",
  "VT","VA","WA","WV","WI","WY"];
const FRED_ALL: FredS[] = [...FRED_NATIONAL, ...STATES.map((s) => ({ id: `${s}ICLAIMS`, kind: "count" as Kind, weekly: true, geo: `US-${s}` }))];
const FRED_RELEASES: Record<string, { id: number; name: RegExp }> = {
  cpi: { id: 10, name: /consumer price index/i },
  jobs: { id: 50, name: /employment situation/i },
  fomc: { id: 101, name: /fomc/i },
  claims: { id: 180, name: /unemployment insurance weekly claims/i },
  gdp: { id: 53, name: /gross domestic product/i },
  pce: { id: 54, name: /personal income and outlays/i },
};

const CES_TOP = ["CES0000000001","CES0500000001","CES1000000001","CES2000000001","CES3000000001","CES3100000001","CES3200000001",
  "CES4000000001","CES4142000001","CES4200000001","CES4300000001","CES4422000001","CES5000000001","CES5500000001","CES6000000001",
  "CES6500000001","CES7000000001","CES8000000001","CES9000000001","CES9091000001","CES9092000001","CES9093000001"];
const CES_DETAIL = `CES1011330001 CES1021110001 CES1021210001 CES1021220001 CES1021230001 CES1021310001 CES2023610001 CES2023620001
CES2023710001 CES2023720001 CES2023730001 CES2023790001 CES2023810001 CES2023820001 CES2023830001 CES2023890001 CES3132110001
CES3132120001 CES3132190001 CES3132710001 CES3132720001 CES3132730001 CES3132740001 CES3132790001 CES3133110001 CES3133120001
CES3133130001 CES3133140001 CES3133150001 CES3133210001 CES3133220001 CES3133230001 CES3133240001 CES3133250001 CES3133260001
CES3133270001 CES3133280001 CES3133290001 CES3133310001 CES3133320001 CES3133330001 CES3133340001 CES3133350001 CES3133360001
CES3133390001 CES3133410001 CES3133420001 CES3133440001 CES3133450001 CES3133510001 CES3133520001 CES3133530001 CES3133590001
CES3133610001 CES3133620001 CES3133630001 CES3133640001 CES3133650001 CES3133660001 CES3133690001 CES3133710001 CES3133720001
CES3133790001 CES3133910001 CES3133990001 CES3231110001 CES3231120001 CES3231130001 CES3231140001 CES3231150001 CES3231160001
CES3231170001 CES3231180001 CES3231190001 CES3231310001 CES3231320001 CES3231330001 CES3231410001 CES3231490001 CES3232210001
CES3232220001 CES3232310001 CES3232410001 CES3232510001 CES3232520001 CES3232530001 CES3232540001 CES3232550001 CES3232560001
CES3232590001 CES3232610001 CES3232620001 CES4142310001 CES4142320001 CES4142330001 CES4142340001 CES4142350001 CES4142360001
CES4142370001 CES4142380001 CES4142390001 CES4142410001 CES4142420001 CES4142430001 CES4142440001 CES4142450001 CES4142460001
CES4142470001 CES4142480001 CES4142490001 CES4142510001 CES4244110001 CES4244120001 CES4244130001 CES4244410001 CES4244420001
CES4244510001 CES4244520001 CES4244530001 CES4348110001 CES4348120001 CES4348210001 CES4348310001 CES4348320001 CES4348410001
CES4348420001 CES4348510001 CES4348520001 CES4348530001 CES4348540001 CES4348550001 CES4348590001 CES4348610001 CES4348620001
CES4348690001 CES4348710001 CES4348720001 CES4348790001 CES4348810001 CES4348820001 CES4348830001 CES4348840001 CES4348850001
CES4348890001 CES4349210001 CES4349220001 CES4349310001 CES4422110001 CES4422120001 CES4422130001 CES5051210001 CES5051220001
CES5051730001 CES5051740001 CES5051790001 CES5051820001 CES5051910001 CES5552110001 CES5552210001 CES5552220001 CES5552230001
CES5552310001 CES5552320001 CES5552390001 CES5552410001 CES5552420001 CES5553110001 CES5553120001 CES5553130001 CES5553210001
CES5553220001 CES5553230001 CES5553240001 CES5553310001 CES6054110001 CES6054120001 CES6054130001 CES6054140001 CES6054150001
CES6054160001 CES6054170001 CES6054180001 CES6054190001 CES6056110001 CES6056120001 CES6056130001 CES6056140001 CES6056150001
CES6056160001 CES6056170001 CES6056190001 CES6056210001 CES6056220001 CES6056290001 CES6561110001 CES6561130001 CES6561140001
CES6561150001 CES6561160001 CES6561170001 CES6562110001 CES6562120001 CES6562130001 CES6562140001 CES6562150001 CES6562160001
CES6562190001 CES6562210001 CES6562220001 CES6562230001 CES6562310001 CES6562320001 CES6562330001 CES6562390001 CES6562410001
CES6562420001 CES6562430001 CES6562440001 CES7071110001 CES7071120001 CES7071130001 CES7071140001 CES7071150001 CES7071210001
CES7071310001 CES7071320001 CES7071390001 CES7072110001 CES7072120001 CES7072130001 CES7072230001 CES7072240001 CES7072250001
CES8081110001 CES8081120001 CES8081130001 CES8081140001 CES8081210001 CES8081220001 CES8081230001 CES8081290001 CES8081310001
CES8081320001 CES8081330001 CES8081340001 CES8081390001`.split(/\s+/).filter(Boolean);
const CES_ALL = [...CES_TOP, ...CES_DETAIL];
// CPI-U item codes (U.S. city average). SA prefix CUSR0000, NSA fallback CUUR0000.
const CPI_ITEMS = ["SA0","SA0L1E","SAF11","SAF111","SAF112","SEFC","SEFF","SEFG","SEFH","SEFJ","SAF113","SEFK","SEFL","SEFP01",
  "SEFR","SAF116","SEFV","SAH1","SEHA","SEHC","SEHB","SEHF01","SEHF02","SEHE","SEHG","SAH3","SAA","SETA01","SETA02","SETB01",
  "SETD","SETE","SETG01","SETC","SAM","SEMC01","SEMD","SAR","SERA01","SERB","SEEB01","SEEE01","SAG1","SEGA","SS47014","SEHF"];

// NOAA first-order stations (GHCND:USWxxxxxxxx), 1-3 per state. Wrong / closed ids are reported (no data) and skipped.
export const NOAA_STATIONS: Array<[string, string]> = [
  ["USW00013876","AL"],["USW00026451","AK"],["USW00023183","AZ"],["USW00023160","AZ"],["USW00013963","AR"],
  ["USW00023174","CA"],["USW00023234","CA"],["USW00093193","CA"],["USW00023232","CA"],["USW00003017","CO"],["USW00014740","CT"],
  ["USW00013781","DE"],["USW00013743","DC"],["USW00012839","FL"],["USW00012842","FL"],["USW00012815","FL"],["USW00013889","FL"],
  ["USW00013874","GA"],["USW00022521","HI"],["USW00024131","ID"],["USW00094846","IL"],["USW00014819","IL"],["USW00093819","IN"],
  ["USW00014933","IA"],["USW00003928","KS"],["USW00093821","KY"],["USW00012916","LA"],["USW00014764","ME"],["USW00093721","MD"],
  ["USW00014739","MA"],["USW00094847","MI"],["USW00014922","MN"],["USW00003940","MS"],["USW00013994","MO"],["USW00003947","MO"],
  ["USW00024033","MT"],["USW00014942","NE"],["USW00023169","NV"],["USW00023185","NV"],["USW00014745","NH"],["USW00014734","NJ"],
  ["USW00023050","NM"],["USW00094728","NY"],["USW00014732","NY"],["USW00014733","NY"],["USW00014735","NY"],["USW00013881","NC"],
  ["USW00013722","NC"],["USW00003812","NC"],["USW00014914","ND"],["USW00014820","OH"],["USW00014821","OH"],["USW00093814","OH"],
  ["USW00013967","OK"],["USW00013968","OK"],["USW00024229","OR"],["USW00013739","PA"],["USW00094823","PA"],["USW00011641","PR"],
  ["USW00014765","RI"],["USW00013880","SC"],["USW00013883","SC"],["USW00014944","SD"],["USW00013897","TN"],["USW00013893","TN"],
  ["USW00012960","TX"],["USW00003927","TX"],["USW00013904","TX"],["USW00012921","TX"],["USW00023044","TX"],["USW00024127","UT"],
  ["USW00014742","VT"],["USW00013740","VA"],["USW00013737","VA"],["USW00024233","WA"],["USW00024157","WA"],["USW00013866","WV"],
  ["USW00014839","WI"],["USW00024018","WY"],
];

// EIA-930 respondents: local timezone for the daily aggregate (EIA publishes daily sums per timezone). Default Eastern.
const EIA_TZ: Record<string, string> = {
  ERCO: "Central", TEX: "Central", MISO: "Central", MIDW: "Central", SWPP: "Central", CENT: "Central", SPA: "Central",
  AECI: "Central", TVA: "Central", TEN: "Central", EEI: "Central", SOCO: "Central",
  CISO: "Pacific", CAL: "Pacific", BANC: "Pacific", LDWP: "Pacific", IID: "Pacific", TIDC: "Pacific", BPAT: "Pacific",
  NW: "Pacific", PACW: "Pacific", PGE: "Pacific", PSEI: "Pacific", SCL: "Pacific", TPWR: "Pacific", AVA: "Pacific",
  CHPD: "Pacific", DOPD: "Pacific", GCPD: "Pacific", GRID: "Pacific", AVRN: "Pacific", NEVP: "Pacific",
  PACE: "Mountain", PSCO: "Mountain", WACM: "Mountain", IPCO: "Mountain", NWMT: "Mountain", WAUW: "Mountain",
  EPE: "Mountain", PNM: "Mountain", GWA: "Mountain", WWA: "Mountain",
  AZPS: "Arizona", SRP: "Arizona", TEPC: "Arizona", WALC: "Arizona", DEAA: "Arizona", HGMA: "Arizona", GRIF: "Arizona",
  GRMA: "Arizona", SW: "Arizona",
};
const EIA = "https://api.eia.gov/v2";
const EIA_PRICE_ROUTES: Array<{ route: string; freq: "daily" | "weekly"; series: string[]; geo: Record<string, string> }> = [
  { route: "petroleum/pri/spt", freq: "daily", series: ["RWTC", "RBRTE", "EER_EPJK_PF4_RGC_DPG"], geo: {} },
  { route: "natural-gas/pri/fut", freq: "daily", series: ["RNGWHHD"], geo: {} },
  { route: "petroleum/pri/gnd", freq: "weekly",
    series: ["EMM_EPMR_PTE_NUS_DPG", "EMM_EPMR_PTE_R10_DPG", "EMM_EPMR_PTE_R20_DPG", "EMM_EPMR_PTE_R30_DPG",
      "EMM_EPMR_PTE_R40_DPG", "EMM_EPMR_PTE_R50_DPG", "EMM_EPMR_PTE_SCA_DPG", "EMD_EPD2D_PTE_NUS_DPG"],
    geo: { R10: "PADD1", R20: "PADD2", R30: "PADD3", R40: "PADD4", R50: "PADD5", SCA: "US-CA" } },
];

// ------------------------------------------------------------------ small helpers
const isDay = (s: unknown) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s);
const num = (v: unknown) => { const x = typeof v === "number" ? v : Number(String(v ?? "").replace(/,/g, "")); return Number.isFinite(x) ? x : null; };
async function st<T>(k: string, dflt: T): Promise<T> { return ((await stateGet(k).catch(() => null)) ?? dflt) as T; }
async function stSet(run: Run, k: string, v: unknown) { if (!run.dryRun) await stateSet(k, v).catch((e) => run.errors.push(`state ${k}: ${errMsg(e)}`)); }
function noKey(run: Run, source: string, name: string) {
  run.source({ source, status: "no_key", note: `Vault secret '${name}' is absent: nothing requested (collector stays idle until it exists)` });
}
async function cfgEcon(): Promise<Record<string, any>> {
  const { data } = await db.rpc("att_config_get", { p_key: "econ" });
  return (data ?? {}) as Record<string, any>;
}
const isoDow = (d: Date) => ((d.getUTCDay() + 6) % 7) + 1; // Mon=1..Sun=7

// ================================================================== FRED
const FRED = "https://api.stlouisfed.org/fred";
async function fredObs(run: Run, key: string, id: string, from: string, initial: boolean): Promise<any[] | null> {
  const q = new URLSearchParams({ series_id: id, api_key: key, file_type: "json", observation_start: from, limit: "100000" });
  if (initial) { q.set("output_type", "4"); q.set("realtime_start", "1776-07-04"); q.set("realtime_end", "9999-12-31"); }
  const j = await getJson(run, "fred", `${FRED}/series/observations?${q}`);
  if (!j) return null;
  return Array.isArray(j.observations) ? j.observations : [];
}
async function fredOne(run: Run, key: string, s: FredS, from: string): Promise<number | null> {
  const obs = await fredObs(run, key, s.id, from, false);
  if (obs === null) return null;
  const released = new Map<string, string>();
  if (s.weekly) {
    const ini = await fredObs(run, key, s.id, from, true);
    for (const o of ini ?? []) if (isDay(o?.date) && isDay(o?.realtime_start)) released.set(o.date, o.realtime_start);
  }
  const rows: ObsRow[] = [];
  for (const o of obs) {
    const v = num(o?.value);
    if (!isDay(o?.date) || v === null) continue; // "." = missing (holiday)
    const meta: Record<string, unknown> = { vintage: String(o.realtime_start ?? "") };
    if (released.has(o.date)) meta.released = released.get(o.date);
    rows.push({ source: "fred", key: s.id, metric: s.kind, geo: s.geo ?? "US", day: o.date, value: v, meta });
  }
  await ingest(run, rows);
  return rows.length;
}
async function modeFred(run: Run, backfill = false) {
  const t0 = Date.now();
  const key = await secret(run, "fred_api_key");
  if (!key) return noKey(run, "fred", "fred_api_key");
  const cfg = await cfgEcon();
  const state = await st<Record<string, string>>("econ.fred.fetched", {});
  const today = todayUtc();
  const dow = isoDow(new Date());
  const only: string[] | null = Array.isArray(run.params.series) ? run.params.series.map(String) : null;
  const list = FRED_ALL.filter((s) => !only || only.includes(s.id));
  let done = 0, rows = 0, fails = 0, wanted = 0;
  const skippedFresh: string[] = [];
  for (const s of list) {
    const last = state[s.id];
    if (backfill && last && run.params.force !== true) continue; // already holds full history
    if (!backfill && last) {
      if (last === today && run.params.force !== true) { skippedFresh.push(s.id); continue; }
      if (s.weekly && !(dow === 4 || dow === 5) && last >= addDays(today, -6) && run.params.force !== true) { skippedFresh.push(s.id); continue; }
    }
    wanted++;
    if (run.outOfTime(8000)) { run.partial = true; continue; }
    if (run.skipped.some((x) => x.host === "api.stlouisfed.org")) { run.partial = true; continue; } // cap/budget/kill: stop
    const from = !last || backfill ? String(cfg.fred_from ?? "2016-01-01") : addDays(last, s.weekly ? -91 : -14);
    const n = await fredOne(run, key, s, from);
    if (n === null) { fails++; continue; }
    state[s.id] = today; done++; rows += n;
    await stSet(run, "econ.fred.fetched", state);
  }
  const pending = wanted - done - fails;
  if (pending > 0) { run.partial = true; run.nextCursor = { source: "fred", pending }; }
  run.extra.fred = { fetched: done, rows, fails, pending, fresh_skipped: skippedFresh.length };
  run.source({ source: "fred", status: fails && !done ? "http_error" : run.partial ? "partial" : "ok", keys: done, rows, ms: Date.now() - t0 });
}

async function modeCalendar(run: Run) {
  const t0 = Date.now();
  const key = await secret(run, "fred_api_key");
  if (!key) return noKey(run, "fred", "fred_api_key");
  const out: Record<string, unknown> = {};
  let total = 0;
  for (const [code, r] of Object.entries(FRED_RELEASES)) {
    if (run.outOfTime(6000)) { run.partial = true; break; }
    const info = await getJson(run, "fred", `${FRED}/release?${new URLSearchParams({ release_id: String(r.id), api_key: key, file_type: "json" })}`);
    const name = String(info?.releases?.[0]?.name ?? "");
    if (!r.name.test(name)) { out[code] = { id: r.id, name, skipped: "release name does not match" }; continue; }
    const q = new URLSearchParams({ release_id: String(r.id), api_key: key, file_type: "json", realtime_start: "2015-01-01",
      realtime_end: "9999-12-31", include_release_dates_with_no_data: "true", sort_order: "asc", limit: "10000" });
    const j = await getJson(run, "fred", `${FRED}/release/dates?${q}`);
    const dates = (Array.isArray(j?.release_dates) ? j.release_dates : []).map((x: any) => String(x?.date)).filter(isDay);
    const rows = [...new Set(dates)].map((d) => ({ release: code, date: d, fred_release_id: r.id }));
    if (rows.length && !run.dryRun) {
      const { data, error } = await db.rpc("att_release_upsert", { p_rows: rows });
      if (error) run.errors.push(`att_release_upsert: ${error.message}`); else total += Number(data ?? 0);
    }
    out[code] = { id: r.id, name, dates: rows.length, first: rows[0]?.date ?? null, last: rows.at(-1)?.date ?? null };
  }
  if (!run.dryRun) {
    const { data, error } = await db.rpc("att_econ_apply_releases");
    if (error) run.errors.push(`att_econ_apply_releases: ${error.message}`); else out.applied = data;
  }
  run.extra.calendar = out;
  run.source({ source: "fred", status: run.partial ? "partial" : "ok", keys: Object.keys(out).length, rows: total, ms: Date.now() - t0, note: "release calendars" });
}

// ================================================================== EIA
function eiaUrl(route: string, key: string, p: Array<[string, string]>): string {
  const q = new URLSearchParams([["api_key", key], ...p]);
  return `${EIA}/${route}/data/?${q}`;
}
async function eiaRespondents(run: Run, key: string): Promise<Array<{ id: string; name: string }>> {
  const cached = await st<{ at?: string; list?: Array<{ id: string; name: string }> }>("econ.eia930.respondents", {});
  if (cached.list?.length && cached.at && cached.at >= addDays(todayUtc(), -30)) return cached.list;
  const j = await getJson(run, "eia.930", `${EIA}/electricity/rto/daily-region-data/facet/respondent?${new URLSearchParams({ api_key: key })}`);
  const list = (Array.isArray(j?.response?.facets) ? j.response.facets : [])
    .map((f: any) => ({ id: String(f?.id ?? ""), name: String(f?.name ?? "").slice(0, 80) }))
    .filter((f: { id: string }) => /^[A-Z0-9]{2,6}$/.test(f.id));
  if (list.length) await stSet(run, "econ.eia930.respondents", { at: todayUtc(), list });
  return list;
}
async function eia930Fetch(run: Run, key: string, ids: string[], tz: string, from: string, to: string): Promise<{ rows: number; ok: boolean }> {
  let offset = 0, rows = 0;
  for (let page = 0; page < 20; page++) {
    const p: Array<[string, string]> = [["frequency", "daily"], ["data[0]", "value"], ["facets[type][]", "D"], ["facets[timezone][]", tz],
      ...ids.map((id) => ["facets[respondent][]", id] as [string, string]), ["start", from], ["end", to],
      ["sort[0][column]", "period"], ["sort[0][direction]", "asc"], ["offset", String(offset)], ["length", "5000"]];
    const j = await getJson(run, "eia.930", eiaUrl("electricity/rto/daily-region-data", key, p), {}, 90_000);
    if (!j) return { rows, ok: false };
    const data = Array.isArray(j?.response?.data) ? j.response.data : [];
    const out: ObsRow[] = [];
    for (const d of data) {
      const v = num(d?.value);
      const day = String(d?.period ?? "");
      if (!isDay(day) || v === null || v <= 0) continue; // zero/negative demand = reporting gap, not a value
      out.push({ source: "eia.930", key: String(d.respondent), metric: "demand", geo: "US", day, value: v });
    }
    await ingest(run, out);
    rows += out.length;
    const total = Number(j?.response?.total ?? 0);
    offset += data.length;
    if (!data.length || offset >= total) break;
    if (run.outOfTime(15_000)) { run.partial = true; return { rows, ok: false }; }
  }
  return { rows, ok: true };
}
async function modeEia930(run: Run, backfill = false) {
  const t0 = Date.now();
  const key = await secret(run, "eia_api_key");
  if (!key) return noKey(run, "eia.930", "eia_api_key");
  const cfg = await cfgEcon();
  const resp = await eiaRespondents(run, key);
  if (!resp.length) { run.source({ source: "eia.930", status: "http_error", note: "no respondent list" }); return; }
  const today = todayUtc();
  const bf = await st<Record<string, string>>("econ.bf.eia.930", {});
  let rows = 0, done = 0;
  if (backfill) {
    const from = String(run.params.from ?? cfg.eia930_from ?? "2015-07-01");
    for (const r of resp) {
      if (bf[r.id]) continue;
      if (run.outOfTime(25_000)) { run.partial = true; break; }
      const res = await eia930Fetch(run, key, [r.id], EIA_TZ[r.id] ?? "Eastern", from, today);
      rows += res.rows;
      if (!res.ok) { run.partial = true; break; }
      bf[r.id] = today; done++;
      await stSet(run, "econ.bf.eia.930", bf);
    }
    const left = resp.filter((r) => !bf[r.id]).length;
    if (left) { run.partial = true; run.nextCursor = { source: "eia.930", left }; }
    run.extra.eia930 = { respondents: resp.length, backfilled_now: done, left };
  } else {
    const from = addDays(today, -Number(run.params.days ?? 10));
    const byTz = new Map<string, string[]>();
    for (const r of resp) { const tz = EIA_TZ[r.id] ?? "Eastern"; byTz.set(tz, [...(byTz.get(tz) ?? []), r.id]); }
    for (const [tz, ids] of byTz) {
      if (run.outOfTime(10_000)) { run.partial = true; break; }
      const res = await eia930Fetch(run, key, ids, tz, from, today);
      rows += res.rows; done += ids.length;
      if (!res.ok) run.partial = true;
    }
    run.extra.eia930 = { respondents: resp.length, updated: done };
  }
  run.source({ source: "eia.930", status: run.partial ? "partial" : "ok", keys: done, rows, ms: Date.now() - t0 });
}

async function modeEiaPrices(run: Run, backfill = false) {
  const t0 = Date.now();
  const key = await secret(run, "eia_api_key");
  if (!key) return noKey(run, "eia.prices", "eia_api_key");
  const today = todayUtc();
  const from = backfill ? String(run.params.from ?? "2016-01-01") : addDays(today, -30);
  let rows = 0, calls = 0;
  const seen: Record<string, number> = {};
  for (const r of EIA_PRICE_ROUTES) {
    let offset = 0;
    for (let page = 0; page < 10; page++) {
      if (run.outOfTime(8000)) { run.partial = true; break; }
      const p: Array<[string, string]> = [["frequency", r.freq], ["data[0]", "value"], ...r.series.map((s) => ["facets[series][]", s] as [string, string]),
        ["start", from], ["end", today], ["sort[0][column]", "period"], ["sort[0][direction]", "asc"], ["offset", String(offset)], ["length", "5000"]];
      const j = await getJson(run, "eia.prices", eiaUrl(r.route, key, p), {}, 60_000);
      calls++;
      if (!j) { run.partial = true; break; }
      const data = Array.isArray(j?.response?.data) ? j.response.data : [];
      const out: ObsRow[] = [];
      for (const d of data) {
        const v = num(d?.value), day = String(d?.period ?? ""), s = String(d?.series ?? "");
        if (!isDay(day) || v === null || !r.series.includes(s)) continue;
        const reg = /_(R10|R20|R30|R40|R50|SCA)_/.exec(s)?.[1];
        out.push({ source: "eia.prices", key: s, metric: "usd", geo: reg ? r.geo[reg] : "US", day, value: v });
        seen[s] = (seen[s] ?? 0) + 1;
      }
      await ingest(run, out);
      rows += out.length;
      offset += data.length;
      if (!data.length || offset >= Number(j?.response?.total ?? 0)) break;
    }
  }
  run.extra.eia_prices = { calls, per_series: seen, missing: EIA_PRICE_ROUTES.flatMap((r) => r.series).filter((s) => !seen[s]) };
  run.source({ source: "eia.prices", status: run.partial ? "partial" : "ok", keys: Object.keys(seen).length, rows, ms: Date.now() - t0 });
}

// ================================================================== BLS
async function blsQuery(run: Run, key: string, ids: string[], y0: number, y1: number): Promise<any | null> {
  const res = await politeFetch(run, "https://api.bls.gov/publicAPI/v2/timeseries/data/", {
    source: "bls.ces", method: "POST", timeoutMs: 60_000,
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({ seriesid: ids, startyear: String(y0), endyear: String(y1), registrationkey: key,
      catalog: false, calculations: false, annualaverage: false }),
  });
  if (!res) return null;
  if (!res.ok) { await res.body?.cancel(); run.errors.push(`bls: http ${res.status}`); return null; }
  const j = await res.json().catch(() => null);
  if (!j) { run.errors.push("bls: bad json"); return null; }
  if (j.status !== "REQUEST_SUCCEEDED") run.errors.push(`bls: ${scrubStr(String(j.status))} ${scrubStr(JSON.stringify(j.message ?? []).slice(0, 200))}`);
  return j;
}
function blsRows(j: any, source: string, metric: string): { rows: ObsRow[]; got: Set<string> } {
  const rows: ObsRow[] = [];
  const got = new Set<string>();
  for (const s of Array.isArray(j?.Results?.series) ? j.Results.series : []) {
    const id = String(s?.seriesID ?? "");
    for (const d of Array.isArray(s?.data) ? s.data : []) {
      const m = /^M(0[1-9]|1[0-2])$/.exec(String(d?.period ?? ""));
      const v = num(d?.value);
      if (!m || v === null) continue;
      const prelim = Array.isArray(d?.footnotes) && d.footnotes.some((f: any) => f?.code === "P");
      rows.push({ source, key: id, metric, geo: "US", day: `${d.year}-${m[1]}-01`, value: v, ...(prelim ? { meta: { prelim: true } } : {}) });
      got.add(id);
    }
  }
  return { rows, got };
}
async function modeBls(run: Run, which: "ces" | "cpi", backfill = false) {
  const t0 = Date.now();
  const source = which === "ces" ? "bls.ces" : "bls.cpi_items";
  const key = await secret(run, "bls_api_key");
  if (!key) return noKey(run, source, "bls_api_key");
  const cfg = await cfgEcon();
  const y1 = new Date().getUTCFullYear();
  const y0 = backfill ? Number(cfg.bls_from_year ?? 2016) : y1 - 1;
  const stKey = `econ.bls.${which}`;
  const s = await st<{ nsa?: string[]; missing?: string[]; done_at?: string }>(stKey, {});
  let rows = 0;
  const missing: string[] = [];
  if (which === "ces") {
    for (let i = 0; i < CES_ALL.length; i += 50) {
      if (run.outOfTime(10_000)) { run.partial = true; break; }
      const ids = CES_ALL.slice(i, i + 50);
      const j = await blsQuery(run, key, ids, y0, y1);
      if (!j) { run.partial = true; break; }
      const r = blsRows(j, source, "emp");
      await ingest(run, r.rows);
      rows += r.rows.length;
      for (const id of ids) if (!r.got.has(id)) missing.push(id);
    }
    await stSet(run, stKey, { missing, done_at: todayUtc() });
  } else {
    // SA first; items without SA data are re-requested as NSA (remembered in state)
    const nsa = new Set(s.nsa ?? []);
    const sa = CPI_ITEMS.filter((c) => !nsa.has(c)).map((c) => `CUSR0000${c}`);
    const j = await blsQuery(run, key, sa, y0, y1);
    if (j) {
      const r = blsRows(j, source, "index");
      await ingest(run, r.rows);
      rows += r.rows.length;
      for (const id of sa) if (!r.got.has(id)) nsa.add(id.slice(8));
    } else run.partial = true;
    const nsaIds = [...nsa].map((c) => `CUUR0000${c}`);
    if (nsaIds.length && !run.outOfTime(10_000)) {
      const j2 = await blsQuery(run, key, nsaIds, y0, y1);
      if (j2) {
        const r = blsRows(j2, source, "index");
        await ingest(run, r.rows);
        rows += r.rows.length;
        for (const id of nsaIds) if (!r.got.has(id)) missing.push(id);
      } else run.partial = true;
    }
    await stSet(run, stKey, { nsa: [...nsa].sort(), missing, done_at: todayUtc() });
  }
  if (!run.dryRun) {
    const { error } = await db.rpc("att_econ_apply_releases");
    if (error) run.errors.push(`att_econ_apply_releases: ${error.message}`);
  }
  run.extra[`bls_${which}`] = { rows, missing: missing.slice(0, 60), n_missing: missing.length, years: [y0, y1] };
  run.source({ source, status: run.partial ? "partial" : "ok", keys: which === "ces" ? CES_ALL.length - missing.length : CPI_ITEMS.length - missing.length, rows, ms: Date.now() - t0 });
}

// ================================================================== DOL ETA 539 (weekly claims by state)
function parseUsDate(s: string): string | null {
  const t = s.trim().replace(/^"|"$/g, "");
  if (/^\d{4}-\d{2}-\d{2}/.test(t)) return t.slice(0, 10);
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(t);
  return m ? `${m[3]}-${m[1].padStart(2, "0")}-${m[2].padStart(2, "0")}` : null;
}
async function modeDol(run: Run, backfill = false) {
  const t0 = Date.now();
  const res = await getText(run, "dol.claims", "https://oui.doleta.gov/unemploy/csv/ar539.csv", { accept: "text/csv,*/*" }, 100_000);
  if (!res) { run.source({ source: "dol.claims", status: "http_error", ms: Date.now() - t0 }); return; }
  const from = backfill ? String(run.params.from ?? "2010-01-01") : addDays(todayUtc(), -120);
  const reader = res.body!.pipeThrough(new TextDecoderStream()).getReader();
  let buf = "", header: string[] | null = null, lines = 0;
  const out: ObsRow[] = [];
  const iSt = () => header!.indexOf("st"), iDate = () => header!.indexOf("rptdate");
  let ci = -1, cc = -1, cst = -1, cdt = -1;
  const handle = (line: string) => {
    if (!line.trim()) return;
    const f = line.split(",").map((x) => x.trim().replace(/^"|"$/g, ""));
    if (!header) {
      header = f.map((x) => x.toLowerCase());
      cst = iSt(); cdt = iDate(); ci = header.indexOf("c3"); cc = header.indexOf("c8");
      return;
    }
    lines++;
    const day = parseUsDate(f[cdt] ?? "");
    const stc = (f[cst] ?? "").toUpperCase();
    if (!day || day < from || !/^[A-Z]{2}$/.test(stc)) return;
    const ic = num(f[ci]), cw = num(f[cc]);
    if (ic !== null) out.push({ source: "dol.claims", key: stc, metric: "ic", geo: `US-${stc}`, day, value: ic });
    if (cw !== null) out.push({ source: "dol.claims", key: stc, metric: "cw", geo: `US-${stc}`, day, value: cw });
  };
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += value;
    let i: number;
    while ((i = buf.indexOf("\n")) >= 0) { handle(buf.slice(0, i).replace(/\r$/, "")); buf = buf.slice(i + 1); }
    if (run.outOfTime(20_000)) { run.partial = true; await reader.cancel().catch(() => undefined); break; }
  }
  if (buf) handle(buf);
  const hdr = header as string[] | null;
  if (!hdr || cst < 0 || cdt < 0 || ci < 0) {
    run.errors.push(`dol: unexpected header ${JSON.stringify((hdr ?? []).slice(0, 12))}`);
    run.source({ source: "dol.claims", status: "parse_error", ms: Date.now() - t0 });
    return;
  }
  await ingest(run, out);
  run.extra.dol = { header: hdr.slice(0, 30), lines, rows: out.length, from, columns: { ic: "c3", cw: "c8" } };
  run.source({ source: "dol.claims", status: run.partial ? "partial" : "ok", keys: new Set(out.map((r) => r.key)).size, rows: out.length, ms: Date.now() - t0 });
}

// ================================================================== NOAA CDO GHCN-Daily
const CDO = "https://www.ncei.noaa.gov/cdo-web/api/v2";
async function cdoPage(run: Run, token: string, stations: string[], from: string, to: string, offset: number): Promise<{ results: any[]; count: number } | null> {
  const q = new URLSearchParams([["datasetid", "GHCND"], ...stations.map((s) => ["stationid", `GHCND:${s}`] as [string, string]),
    ["datatypeid", "TMAX"], ["datatypeid", "TMIN"], ["datatypeid", "PRCP"], ["startdate", from], ["enddate", to],
    ["units", "metric"], ["limit", "1000"], ["offset", String(offset)]]);
  const j = await getJson(run, "noaa.ghcnd", `${CDO}/data?${q}`, { token }, 60_000);
  if (j === null) return null;
  return { results: Array.isArray(j?.results) ? j.results : [], count: Number(j?.metadata?.resultset?.count ?? 0) };
}
function cdoRows(results: any[], stateOf: Map<string, string>): ObsRow[] {
  const byKey = new Map<string, { tmax?: number; tmin?: number; prcp?: number }>();
  for (const r of results) {
    const stn = String(r?.station ?? "").replace(/^GHCND:/, "");
    const day = String(r?.date ?? "").slice(0, 10);
    const v = num(r?.value);
    if (!isDay(day) || v === null || !stateOf.has(stn)) continue;
    if (typeof r?.attributes === "string" && r.attributes.split(",")[1]) continue; // quality flag set -> failed QC, skip
    const k = `${stn}|${day}`;
    const o = byKey.get(k) ?? {};
    if (r.datatype === "TMAX") o.tmax = v; else if (r.datatype === "TMIN") o.tmin = v; else if (r.datatype === "PRCP") o.prcp = v;
    byKey.set(k, o);
  }
  const rows: ObsRow[] = [];
  for (const [k, o] of byKey) {
    const [stn, day] = k.split("|");
    const geo = `US-${stateOf.get(stn)}`;
    if (o.tmax !== undefined) rows.push({ source: "noaa.ghcnd", key: stn, metric: "temp", geo, day, value: o.tmax, aux: o.tmin ?? null });
    if (o.prcp !== undefined) rows.push({ source: "noaa.ghcnd", key: stn, metric: "prcp", geo, day, value: o.prcp });
  }
  return rows;
}
async function modeNoaa(run: Run, backfill = false) {
  const t0 = Date.now();
  const token = await secret(run, "noaa_cdo_token");
  if (!token) return noKey(run, "noaa.ghcnd", "noaa_cdo_token");
  const cfg = await cfgEcon();
  const stateOf = new Map(NOAA_STATIONS);
  const all = NOAA_STATIONS.map(([s]) => s);
  let rows = 0, pages = 0;
  if (!backfill) {
    const to = todayUtc(), from = addDays(to, -Number(run.params.days ?? 14));
    for (let g = 0; g < all.length; g += 25) {
      const grp = all.slice(g, g + 25);
      for (let off = 1; off < 20_000; off += 1000) {
        if (run.outOfTime(8000)) { run.partial = true; break; }
        const p = await cdoPage(run, token, grp, from, to, off);
        pages++;
        if (!p) { run.partial = true; break; }
        const r = cdoRows(p.results, stateOf);
        await ingest(run, r); rows += r.length;
        if (off + 1000 > p.count) break;
      }
    }
  } else {
    // cursor: {year, group, offset}; one station group (5 stations) x one calendar year at a time, 1000 results per page
    const y0 = Number(String(run.params.from ?? cfg.noaa_from ?? "2019-01-01").slice(0, 4));
    const y1 = new Date().getUTCFullYear();
    const cur = await st<{ year?: number; group?: number; offset?: number; complete?: boolean; empty?: string[] }>("econ.bf.noaa.ghcnd", {});
    if (cur.complete && run.params.force !== true) { run.source({ source: "noaa.ghcnd", status: "ok", note: "backfill complete" }); return; }
    let year = cur.year ?? y0, group = cur.group ?? 0, offset = cur.offset ?? 1;
    const G = 5;
    while (year <= y1) {
      if (run.outOfTime(12_000)) { run.partial = true; break; }
      const grp = all.slice(group * G, group * G + G);
      if (!grp.length) { year++; group = 0; offset = 1; continue; }
      const to = year === y1 ? todayUtc() : `${year}-12-31`;
      const p = await cdoPage(run, token, grp, `${year}-01-01`, to, offset);
      pages++;
      if (!p) { run.partial = true; break; }
      const r = cdoRows(p.results, stateOf);
      await ingest(run, r); rows += r.length;
      if (offset + 1000 <= p.count) offset += 1000; else { group++; offset = 1; }
      await stSet(run, "econ.bf.noaa.ghcnd", { year, group, offset, complete: false });
    }
    if (year > y1) await stSet(run, "econ.bf.noaa.ghcnd", { year, group: 0, offset: 1, complete: true });
    run.nextCursor = year > y1 ? null : { year, group, offset };
  }
  run.extra.noaa = { pages, rows, stations: all.length };
  run.source({ source: "noaa.ghcnd", status: run.partial ? "partial" : "ok", keys: all.length, rows, ms: Date.now() - t0 });
}

// ================================================================== Census BFS (weekly business applications)
// Weekly CSVs published with each Thursday release. The file layout is discovered from the header: a date/week column
// plus one column per geography (or long format geo,value). Only counts of business applications (BA) are stored.
async function modeBfs(run: Run, backfill = false) {
  const t0 = Date.now();
  const cfg = await cfgEcon();
  const urls: string[] = Array.isArray(cfg.bfs_urls) ? cfg.bfs_urls : [];
  if (!urls.length) {
    run.source({ source: "census.bfs", status: "not_configured", note: "att_config.econ.bfs_urls is empty: set the weekly BFS CSV URLs (discovered with mode probe)" });
    return;
  }
  const from = backfill ? String(cfg.bfs_from ?? "2016-01-01") : addDays(todayUtc(), -120);
  let rows = 0;
  const notes: unknown[] = [];
  for (const u of urls) {
    if (run.outOfTime(10_000)) { run.partial = true; break; }
    const res = await getText(run, "census.bfs", u, { accept: "text/csv,*/*" });
    if (!res) { run.partial = true; continue; }
    const txt = (await res.text()).replace(/^﻿/, "");
    const lines = txt.split(/\r?\n/).filter((l) => l.trim());
    const split = (l: string) => l.match(/("([^"]|"")*"|[^,]*)(,|$)/g)!.map((x) => x.replace(/,$/, "").replace(/^"|"$/g, "").trim()).slice(0, -1);
    const hdr = split(lines[0]).map((h) => h.toLowerCase());
    notes.push({ url_path: new URL(u).pathname, header: hdr.slice(0, 12), n: lines.length - 1 });
    const iDate = hdr.findIndex((h) => /week.*end|date|period|time/.test(h));
    const iGeo = hdr.findIndex((h) => /^(geo|state|geography|region)$/.test(h));
    const iVal = hdr.findIndex((h) => /^(ba|value|business applications|ba_nsa|ba_ba)$/.test(h));
    const out: ObsRow[] = [];
    for (const l of lines.slice(1)) {
      const f = split(l);
      const day = parseUsDate(f[iDate] ?? "") ?? (isDay(f[iDate]) ? f[iDate] : null);
      if (!day || day < from) continue;
      if (iGeo >= 0 && iVal >= 0) {
        const g = (f[iGeo] ?? "").toUpperCase(); const v = num(f[iVal]);
        if (v === null || !/^([A-Z]{2}|US)$/.test(g)) continue;
        out.push({ source: "census.bfs", key: g, metric: "ba", geo: g === "US" ? "US" : `US-${g}`, day, value: v });
      } else {
        hdr.forEach((h, i) => {
          if (i === iDate) return;
          const g = h.toUpperCase(); const v = num(f[i]);
          if (v === null || !/^([A-Z]{2}|US)$/.test(g)) return;
          out.push({ source: "census.bfs", key: g, metric: "ba", geo: g === "US" ? "US" : `US-${g}`, day, value: v });
        });
      }
    }
    await ingest(run, out);
    rows += out.length;
  }
  run.extra.bfs = notes;
  run.source({ source: "census.bfs", status: run.partial ? "partial" : rows ? "ok" : "parse_error", rows, ms: Date.now() - t0 });
}

// ================================================================== probe / backfill dispatch
async function modeProbe(run: Run) {
  const url = String(run.params.url ?? "");
  const source = String(run.params.source ?? "");
  if (!url || !source) { run.errors.push("probe needs params.url and params.source"); return; }
  let u = url;
  const kp = run.params.key_param ? String(run.params.key_param) : null;
  const kn: Record<string, string> = { "eia.930": "eia_api_key", "eia.prices": "eia_api_key", fred: "fred_api_key",
    "census.bfs": "census_api_key", "noaa.ghcnd": "noaa_cdo_token" };
  const headers: Record<string, string> = {};
  if (kp || run.params.key_header) {
    const k = await secret(run, kn[source] ?? "");
    if (!k) { run.errors.push("probe: no key for source"); return; }
    if (kp) u += (u.includes("?") ? "&" : "?") + `${kp}=${encodeURIComponent(k)}`;
    if (run.params.key_header) headers[String(run.params.key_header)] = k;
  }
  const res = await politeFetch(run, u, { source, headers, timeoutMs: 60_000 });
  if (!res) { run.extra.probe = { made: false }; return; }
  const ct = res.headers.get("content-type");
  const reader = res.body?.getReader();
  let head = "", bytes = 0;
  const grep = run.params.grep ? new RegExp(String(run.params.grep), "i") : null;
  const hits: string[] = [];
  if (reader) {
    const dec = new TextDecoder();
    let carry = "";
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.length;
      const s = dec.decode(value, { stream: true });
      if (head.length < 1500) head += s.slice(0, 1500 - head.length);
      if (grep) {
        const parts = (carry + s).split(/[\n,{}]/); carry = parts.pop() ?? "";
        for (const p of parts) if (grep.test(p) && hits.length < 40) hits.push(p.slice(0, 200));
      }
      if (bytes > 30_000_000 || run.outOfTime(5000) || (!grep && bytes > 200_000)) { await reader.cancel().catch(() => undefined); break; }
    }
  }
  run.extra.probe = { status: res.status, content_type: ct, bytes, head: scrubStr(head), hits: hits.map(scrubStr) };
}

async function modeBackfill(run: Run) {
  const src = String(run.params.source ?? "");
  switch (src) {
    case "fred": return await modeFred(run, true);
    case "eia.930": return await modeEia930(run, true);
    case "eia.prices": return await modeEiaPrices(run, true);
    case "bls.ces": return await modeBls(run, "ces", true);
    case "bls.cpi_items": return await modeBls(run, "cpi", true);
    case "dol.claims": return await modeDol(run, true);
    case "noaa.ghcnd": return await modeNoaa(run, true);
    case "census.bfs": return await modeBfs(run, true);
    default: run.errors.push(`backfill: unsupported source '${src}'`);
  }
}

serve("att-econ", {
  fred: wrap((r) => modeFred(r, false)),
  calendar: wrap(modeCalendar),
  eia_930: wrap((r) => modeEia930(r, false)),
  eia_prices: wrap((r) => modeEiaPrices(r, false)),
  bls_ces: wrap((r) => modeBls(r, "ces", false)),
  bls_cpi: wrap((r) => modeBls(r, "cpi", false)),
  dol_claims: wrap((r) => modeDol(r, false)),
  noaa: wrap((r) => modeNoaa(r, false)),
  census_bfs: wrap((r) => modeBfs(r, false)),
  backfill: wrap(modeBackfill),
  probe: wrap(modeProbe),
  ping: wrap(async (r) => { r.extra.version = ECON_VERSION; r.extra.wsa = "ok"; }),
});
