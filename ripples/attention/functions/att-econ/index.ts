// att-econ — Ripple Map v6 (WS-A) OUTCOME collector: energy, rates/FX/claims, jobs, prices, weather, business formation.
// Spec: ENGINE_SPEC §1.1 (channels PHYS/ECON/JOBS), §3.1 (level / rate transforms), §3.6 + §7 (release looks),
// §9 (API budget), §10.3 (edge-function additions); OWNER_DECISIONS D-7 (keys via public.att_secret only), D-9 (NOAA).
//
// Modes (body.mode):
//   fred        FRED series/observations for the configured national series (rates, FX, commodities, claims) and the
//               51 <ST>ICLAIMS state initial-claims series (50 states + DC; FRED has no PRICLAIMS). Daily series every
//               day; weekly series on Thu/Fri or when stale. Daily market series (not revised): source fred, output_type=1,
//               meta.vintage = realtime_start. Weekly series (revised): FIRST-RELEASE values only (ALFRED output_type=4),
//               sources fred.claims (ICSA, ICNSA, CCSA, <ST>ICLAIMS) / fred.weekly (GASREGW, GASDESW), meta.rt = 'first',
//               meta.vintage = meta.released = first-release date. Third-party series (Cboe VIX, S&P 500, ICE BofA,
//               Freddie Mac) are never requested.
//   calendar    FRED release/dates for CPI, Employment Situation, UI weekly claims, GDP, PCE (past + scheduled) and the
//               FOMC meeting calendar from federalreserve.gov -> ripples.att_release_dates (release looks, calendar).
//   eia_930     EIA-930 Hourly Electric Grid Monitor keyless six-month bulk CSVs (www.eia.gov): local-day demand (MWh)
//               per balancing authority (metric demand), net generation per BA (metric netgen, incl. generation-only
//               BAs) and a lower-48 demand sum (key US48). Daily = current half-year file; backfill = one file per run
//               from 2015 H2 (api.eia.gov is not used: its robots.txt answered 403 -> host killed, DEMARCATION Q3).
//               Energy prices (WTI, Brent, Henry Hub, jet fuel, retail gasoline/diesel) come through their FRED mirrors.
//               e7 (ENGINE 6.3 second blind batch): net generation from SOLAR and WIND per BA from the same files, kept as
//               WEEKLY sums (week-ending Saturday, >= 4 complete days) under metrics ng_solar / ng_wind (storage: ~2 MB, not
//               ~25 MB of daily rows); the backfill state version is bumped to v3 so every file is re-read once.
//   bls_ces     BLS CES all-employee SA series (supersectors + ~260 industries), monthly, via their FRED mirrors
//               (api.bls.gov robots.txt disallows "/": the keyed BLS API is ORANGE* and unused). FIRST-RELEASE values
//               (ALFRED output_type=4; meta.rt = 'first', meta.released = first-release date): reconstructed release-look
//               tests never read benchmark or seasonal-factor revisions. The daily mode only refreshes series the
//               backfill already holds, once per release window. Series stored before e4 (revised values, relabelled
//               meta.rt = 'latest') are re-read once as first releases by the backfill drain (state econ.bls.ces.rt).
//   bls_cpi     ~45 BLS CPI-U item indexes (SA where published, NSA fallback), monthly, via FRED mirrors, first releases.
//   dol_claims  DOL ETA ar539.csv: weekly state initial claims (ic) and continued weeks claimed (cw), plus key US (sum of
//               the 50 states + DC, the regional-demeaning aggregate).
//   noaa        NOAA CDO v2 GHCN-Daily TMAX/TMIN (metric temp: value = TMAX degC, aux = TMIN degC) and PRCP (mm) for
//               ~70 first-order stations; daily update (last 14 days) or backfill (params.from, default 2019-01-01).
//   census_bfs  Census Business Formation Statistics weekly business applications (BA_NSA, national + state) from the
//               weekly CSVs listed in att_config.econ.bfs_urls (Year/Week rows -> week-ending Saturday).
//   fred_state  ENGINE 6.3 regional outcome panels (source fred.state): monthly state series republished by FRED from BLS
//               (CES state supersectors <ST>LEIH leisure & hospitality, <ST>CONS construction; LAUS <ST>UR unemployment
//               rate), Census (<ST>BPPRIV private housing units authorized by building permits) and the annual DOL state
//               minimum wage (STTMINWG<ST>, rate as of January 1, source U.S. Department of Labor). 50 states + DC. FIRST-
//               RELEASE values (ALFRED output_type=4), from att_config.econ.fred_from. Resumable cursor att_state
//               'econ.fred.state' {fetched: {id: day}, missing: [id]}; a series is re-read when > 32 days old (monthly
//               release cadence) or with params.force. Budget: the shared 'fred' bucket, host lease, per-run cap.
//   backfill    params.source in (fred | fred_rt | eia.930 | bls.ces | bls.cpi_items | dol.claims | noaa.ghcnd |
//               census.bfs): resumable full history (att_state 'econ.bf.<source>'). fred_rt re-reads the weekly series
//               once as first releases (one call each; att_state 'econ.fred.rt').
//   probe       params.url (+ params.source, params.key_param): one GET through politeFetch, returns status + a short
//               scrubbed head. For endpoint discovery only.
//   ping        no requests.
// Every request goes through politeFetch (registered source, hosts, robots.txt, budget, kill switch, host lease).
// Keys: public.att_secret(<name>) at run time only; scrubbed from everything written to att_runs (wsa.ts).
import { addDays, db, errMsg, ingest, type ObsRow, politeFetch, type Run, serve, stateGet, stateSet } from "./att.ts";
import { getJson, getText, r4, scrubStr, secret, todayUtc, wrap } from "./wsa.ts";

export const ECON_VERSION = "2026-09-26.e8";

// ------------------------------------------------------------------ series catalogues
type Kind = "rate" | "level" | "count";
/** src = the att_sources id the rows are stored under (weekly series: week-grain sources, first-release values). */
interface FredS { id: string; kind: Kind; weekly?: boolean; geo?: string; src?: "fred" | "fred.claims" | "fred.weekly" }
const FRED_NATIONAL: FredS[] = [
  { id: "DGS3MO", kind: "rate" }, { id: "DGS2", kind: "rate" }, { id: "DGS5", kind: "rate" }, { id: "DGS10", kind: "rate" },
  { id: "DGS30", kind: "rate" }, { id: "T10YIE", kind: "rate" }, { id: "T5YIE", kind: "rate" }, { id: "T10Y2Y", kind: "rate" },
  { id: "DFF", kind: "rate" }, { id: "SOFR", kind: "rate" },
  { id: "DEXUSEU", kind: "level" }, { id: "DEXJPUS", kind: "level" }, { id: "DEXUSUK", kind: "level" },
  { id: "DEXCAUS", kind: "level" }, { id: "DEXMXUS", kind: "level" }, { id: "DEXCHUS", kind: "level" },
  { id: "DTWEXBGS", kind: "level" },
  { id: "DCOILWTICO", kind: "level" }, { id: "DCOILBRENTEU", kind: "level" }, { id: "DHHNGSP", kind: "level" },
  { id: "DJFUELUSGULF", kind: "level" }, { id: "GASDESW", kind: "level", weekly: true, src: "fred.weekly" },
  { id: "ICSA", kind: "count", weekly: true, src: "fred.claims" }, { id: "ICNSA", kind: "count", weekly: true, src: "fred.claims" },
  { id: "CCSA", kind: "count", weekly: true, src: "fred.claims" },
  { id: "GASREGW", kind: "level", weekly: true, src: "fred.weekly" },
];
export const STATES = ["AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
  "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","PR","RI","SC","SD","TN","TX","UT",
  "VT","VA","WA","WV","WI","WY"];
// FRED carries no Puerto Rico claims series (PRICLAIMS answers 400): PR state claims come from dol.claims only.
const FRED_STATES = STATES.filter((s) => s !== "PR");
const FRED_ALL: FredS[] = [...FRED_NATIONAL,
  ...FRED_STATES.map((s) => ({ id: `${s}ICLAIMS`, kind: "count" as Kind, weekly: true, geo: `US-${s}`, src: "fred.claims" as const }))];
const FRED_WEEKLY = FRED_ALL.filter((s) => s.weekly);
const FRED_RELEASES: Record<string, { id: number; name: RegExp }> = {
  cpi: { id: 10, name: /consumer price index/i },
  jobs: { id: 50, name: /employment situation/i },
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
// FRED publishes the CES supersector totals under mnemonic ids, not their BLS ids (checked 2026-09-25: the BLS ids answer
// 400 "series does not exist"). Stored under the BLS id with meta.ref = 'fred:<id>'.
const CES_FRED_ALIAS: Record<string, string> = {
  CES0000000001: "PAYEMS", CES0500000001: "USPRIV", CES1000000001: "USMINE", CES2000000001: "USCONS", CES3000000001: "MANEMP",
  CES3100000001: "DMANEMP", CES3200000001: "NDMANEMP", CES4000000001: "USTPU", CES4142000001: "USWTRADE", CES4200000001: "USTRADE",
  CES5000000001: "USINFO", CES5500000001: "USFIRE", CES6000000001: "USPBS", CES6500000001: "USEHS", CES7000000001: "USLAH",
  CES8000000001: "USSERV", CES9000000001: "USGOVT",
};
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
/** One FRED series. Weekly (revised) series: first-release values only (one output_type=4 call). Daily market series:
 *  output_type=1 (they are not revised). */
async function fredOne(run: Run, key: string, s: FredS, from: string): Promise<number | null> {
  const first = s.weekly === true;
  const obs = await fredObs(run, key, s.id, from, first);
  if (obs === null) return null;
  const rows: ObsRow[] = [];
  for (const o of obs) {
    const v = num(o?.value);
    if (!isDay(o?.date) || v === null) continue; // "." = missing (holiday)
    const rs = isDay(o?.realtime_start) ? String(o.realtime_start) : "";
    const meta: Record<string, unknown> = first ? { rt: "first", vintage: rs, released: rs } : { vintage: rs };
    rows.push({ source: s.src ?? "fred", key: s.id, metric: s.kind, geo: s.geo ?? "US", day: o.date, value: v, meta });
  }
  await ingest(run, rows);
  return rows.length;
}
/** Backfill 'fred_rt': re-read every weekly series once as first releases (rows stored before 2026-09-25 e4 held the
 *  latest revised values). One call per series; cursor att_state 'econ.fred.rt' {id: day}. */
async function modeFredRt(run: Run) {
  const t0 = Date.now();
  const key = await secret(run, "fred_api_key");
  if (!key) return noKey(run, "fred.claims", "fred_api_key");
  const cfg = await cfgEcon();
  const state = await st<Record<string, string>>("econ.fred.rt", {});
  let done = 0, rows = 0, fails = 0;
  for (const s of FRED_WEEKLY) {
    if (state[s.id] && run.params.force !== true) continue;
    if (run.outOfTime(8000) || run.skipped.some((x) => x.host === "api.stlouisfed.org")) { run.partial = true; break; }
    const n = await fredOne(run, key, s, String(cfg.fred_from ?? "2016-01-01"));
    if (n === null) { fails++; continue; }
    state[s.id] = todayUtc(); done++; rows += n;
    await stSet(run, "econ.fred.rt", state);
  }
  const left = FRED_WEEKLY.filter((s) => !state[s.id]).length;
  if (left) { run.partial = true; run.nextCursor = { source: "fred_rt", left }; }
  run.extra.fred_rt = { fetched: done, rows, fails, left, of: FRED_WEEKLY.length };
  run.source({ source: "fred.claims", status: fails && !done ? "http_error" : run.partial ? "partial" : "ok", keys: done, rows, ms: Date.now() - t0 });
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
  // FOMC meeting (decision) dates: FRED's "FOMC Press Release" release is daily, so the Board's own calendar page is
  // parsed (source fed.fomc; decision day = last day of each meeting). Past and scheduled meetings as published.
  if (!run.outOfTime(15_000)) {
    const res = await getText(run, "fed.fomc", "https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm", { accept: "text/html" }, 30_000);
    if (res) {
      const html = await res.text();
      const months = ["january","february","march","april","may","june","july","august","september","october","november","december"];
      const rows: Array<{ release: string; date: string }> = [];
      const secs = html.split(/(?=\b(20\d{2}) FOMC Meetings)/);
      for (const sec of secs) {
        const y = /^(20\d{2}) FOMC Meetings/.exec(sec)?.[1];
        if (!y) continue;
        const re = /fomc-meeting__month[^>]*>\s*(?:<strong>)?\s*([A-Za-z\/]+)\s*(?:<\/strong>)?\s*<\/div>\s*<div[^>]*fomc-meeting__date[^>]*>\s*([0-9]{1,2}(?:\s*-\s*[0-9]{1,2})?)/g;
        let m: RegExpExecArray | null;
        while ((m = re.exec(sec))) {
          const mon = m[1].toLowerCase().split("/").pop()!;
          const mi = months.findIndex((x) => x.startsWith(mon.slice(0, 3)));
          const last = Number(m[2].split("-").pop()!.trim());
          if (mi < 0 || !(last >= 1 && last <= 31)) continue;
          rows.push({ release: "fomc", date: `${y}-${String(mi + 1).padStart(2, "0")}-${String(last).padStart(2, "0")}` });
        }
      }
      if (rows.length && !run.dryRun) {
        const { data, error } = await db.rpc("att_release_upsert", { p_rows: rows });
        if (error) run.errors.push(`att_release_upsert(fomc): ${error.message}`); else total += Number(data ?? 0);
      }
      out.fomc = { meetings: rows.length, first: rows.map((r) => r.date).sort()[0] ?? null, last: rows.map((r) => r.date).sort().at(-1) ?? null };
    }
  }
  if (!run.dryRun) {
    const { data, error } = await db.rpc("att_econ_apply_releases");
    if (error) run.errors.push(`att_econ_apply_releases: ${error.message}`); else out.applied = data;
  }
  run.extra.calendar = out;
  run.source({ source: "fred", status: run.partial ? "partial" : "ok", keys: Object.keys(out).length, rows: total, ms: Date.now() - t0, note: "release calendars" });
}

// ================================================================== EIA-930 (keyless six-month bulk files on www.eia.gov)
// api.eia.gov answered 403 on robots.txt (2026-09-25) -> treated as disallow (DEMARCATION Q3) and killed permanently by
// att.ts. Q3: "the operator documents another channel -> use that channel": EIA publishes the Hourly Electric Grid
// Monitor as keyless six-month CSVs (www.eia.gov/electricity/gridmonitor/sixMonthFiles/, robots allowed). One file per
// half-year, one row per BA-hour; we keep only the local-day sum of hourly demand per BA (MWh), preferring EIA's
// "Demand (MW) (Adjusted)" column when the file has it. Days with < 20 reported hours are dropped.
const EIA_BULK = "https://www.eia.gov/electricity/gridmonitor/sixMonthFiles";
function halves(fromY: number, fromH: 1 | 2, to: Date): string[] {
  const out: string[] = [];
  const toY = to.getUTCFullYear(), toH = to.getUTCMonth() < 6 ? 1 : 2;
  for (let y = fromY, h = fromH; y < toY || (y === toY && h <= toH); h === 1 ? (h = 2) : (h = 1, y++)) {
    out.push(`EIA930_BALANCE_${y}_${h === 1 ? "Jan_Jun" : "Jul_Dec"}.csv`);
  }
  return out;
}
/** Fields 0..maxIdx of a CSV line (quotes honoured, thousands separators inside quotes kept). */
function csvFields(line: string, maxIdx: number): string[] {
  const out: string[] = [];
  let i = 0;
  const n = line.length;
  while (i <= n && out.length <= maxIdx) {
    if (line.charCodeAt(i) === 34) {
      const j = line.indexOf('"', i + 1);
      const e = j < 0 ? n : j;
      out.push(line.slice(i + 1, e));
      i = line.indexOf(",", e) < 0 ? n + 1 : line.indexOf(",", e) + 1;
    } else {
      const j = line.indexOf(",", i);
      const e = j < 0 ? n : j;
      out.push(line.slice(i, e));
      i = e + 1;
    }
  }
  return out;
}
async function eiaBulkFile(run: Run, name: string): Promise<{ rows: number; ok: boolean; bas: number; gen_bas?: number; days: number; col: string; fuel_weeks?: number; fuel_cols?: number[]; fuel_days?: number }> {
  const res = await getText(run, "eia.930", `${EIA_BULK}/${name}`, { accept: "text/csv,*/*" }, 100_000);
  if (!res || !res.body) return { rows: 0, ok: false, bas: 0, days: 0, col: "" };
  const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
  const sums = new Map<string, number>(), hours = new Map<string, number>();
  const gsum = new Map<string, number>(), ghours = new Map<string, number>();
  const fsum = new Map<string, number>(), fhours = new Map<string, number>(); // key `${fuel}|${ba}|${date}` (solar / wind)
  let buf = "", header: string[] | null = null, iBa = 0, iDate = 1, iDem = -1, iAdj = -1, iNg = -1, iNgAdj = -1, iSol = -1, iWind = -1, maxIdx = 0, complete = true;
  const handle = (line: string) => {
    if (!line) return;
    if (!header) {
      header = csvFields(line, 200).map((h) => h.trim().toLowerCase());
      iBa = header.indexOf("balancing authority"); iDate = header.indexOf("data date");
      iDem = header.indexOf("demand (mw)"); iAdj = header.indexOf("demand (mw) (adjusted)");
      iNg = header.indexOf("net generation (mw)"); iNgAdj = header.indexOf("net generation (mw) (adjusted)");
      const pick = (fuel: string) => { const a = header!.indexOf(`net generation (mw) from ${fuel} (adjusted)`); return a >= 0 ? a : header!.indexOf(`net generation (mw) from ${fuel}`); };
      iSol = pick("solar"); iWind = pick("wind");
      maxIdx = Math.max(iBa, iDate, iDem, iAdj, iNg, iNgAdj, iSol, iWind);
      return;
    }
    const f = csvFields(line, maxIdx);
    const ba = f[iBa], dt = f[iDate];
    if (!ba || !dt) return;
    const k = `${ba}|${dt}`;
    // net generation (every BA, including generation-only BAs that report no demand)
    const gRaw = (iNgAdj >= 0 && f[iNgAdj]) ? f[iNgAdj] : (iNg >= 0 ? f[iNg] : "");
    if (gRaw) {
      const g = Number(gRaw.replace(/,/g, ""));
      if (Number.isFinite(g)) { gsum.set(k, (gsum.get(k) ?? 0) + g); ghours.set(k, (ghours.get(k) ?? 0) + 1); }
    }
    for (const [fuel, idx] of [["solar", iSol], ["wind", iWind]] as Array<[string, number]>) {
      if (idx < 0 || !f[idx]) continue;
      const x = Number(f[idx].replace(/,/g, ""));
      if (!Number.isFinite(x)) continue; // night-time solar is reported as small negatives (station load): keep the hour, sum the value
      const fk = `${fuel}|${k}`;
      fsum.set(fk, (fsum.get(fk) ?? 0) + x); fhours.set(fk, (fhours.get(fk) ?? 0) + 1);
    }
    const raw = (iAdj >= 0 && f[iAdj]) ? f[iAdj] : f[iDem];
    if (!raw) return;
    const v = Number(raw.replace(/,/g, ""));
    if (!Number.isFinite(v) || v < 0) return;
    sums.set(k, (sums.get(k) ?? 0) + v);
    hours.set(k, (hours.get(k) ?? 0) + 1);
  };
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += value;
    let i: number, start = 0;
    while ((i = buf.indexOf("\n", start)) >= 0) { handle(buf.slice(start, i).replace(/\r$/, "")); start = i + 1; }
    buf = buf.slice(start);
    if (run.outOfTime(15_000)) { complete = false; await reader.cancel().catch(() => undefined); break; }
  }
  if (buf && complete) handle(buf.replace(/\r$/, ""));
  if (!header || iBa < 0 || iDate < 0 || iDem < 0) { run.errors.push(`eia.930 ${name}: unexpected header`); return { rows: 0, ok: false, bas: 0, days: 0, col: "" }; }
  if (!complete) { run.partial = true; return { rows: 0, ok: false, bas: 0, days: 0, col: "" }; }
  const out: ObsRow[] = [];
  const bas = new Set<string>(), days = new Set<string>();
  const us = new Map<string, { v: number; n: number }>();
  for (const [k, v] of sums) {
    const h = hours.get(k) ?? 0;
    if (h < 20) continue;
    const [ba, dt] = k.split("|");
    const day = parseUsDate(dt);
    if (!day || !/^[A-Z0-9]{2,6}$/.test(ba)) continue;
    out.push({ source: "eia.930", key: ba, metric: "demand", geo: "US", day, value: Math.round(v), aux: h });
    bas.add(ba); days.add(day);
    const u = us.get(day) ?? { v: 0, n: 0 }; u.v += v; u.n++; us.set(day, u);
  }
  // Lower-48 aggregate for regional demeaning (ENGINE §3.5): sum over BAs of local-day demand, only days where >= 90% of
  // the file's BAs reported (local-day boundaries differ by up to 3 h across timezones: an approximation, stated in meta).
  // Key 'US48' = the aggregate key WS-B's att_engine_source_map expects (agg_key); it is this BA sum, not EIA's own US48 region row.
  const nBa = bas.size;
  for (const [day, u] of us) if (u.n >= 0.9 * nBa) out.push({ source: "eia.930", key: "US48", metric: "demand", geo: "US", day, value: Math.round(u.v), aux: u.n, meta: { method: "sum_ba_local_days" } });
  // Net generation per BA-day (>= 20 hours). Days with a non-positive daily total are skipped (log-level series); rare
  // and limited to small generation-only BAs.
  const gbas = new Set<string>();
  for (const [k, g] of gsum) {
    const h = ghours.get(k) ?? 0;
    if (h < 20 || !(g > 0)) continue;
    const [ba, dt] = k.split("|");
    const day = parseUsDate(dt);
    if (!day || !/^[A-Z0-9]{2,6}$/.test(ba)) continue;
    out.push({ source: "eia.930", key: ba, metric: "netgen", geo: "US", day, value: Math.round(g), aux: h });
    gbas.add(ba);
  }
  // Net generation from solar / wind per BA: daily sums (>= 20 hours) rolled up to WEEKLY sums (week-ending Saturday, >= 4 days).
  const wk = new Map<string, { v: number; n: number }>();
  for (const [fk, v] of fsum) {
    if ((fhours.get(fk) ?? 0) < 20) continue;
    const [fuel, ba, dt] = fk.split("|");
    const day = parseUsDate(dt);
    if (!day || !/^[A-Z0-9]{2,6}$/.test(ba)) continue;
    const d = new Date(day + "T00:00:00Z");
    const sat = new Date(d.getTime() + ((6 - d.getUTCDay() + 7) % 7) * 86400000).toISOString().slice(0, 10);
    const wkey = `${fuel}|${ba}|${sat}`;
    const w = wk.get(wkey) ?? { v: 0, n: 0 }; w.v += v; w.n++; wk.set(wkey, w);
  }
  const fout: ObsRow[] = [];
  for (const [wkey, w] of wk) {
    if (w.n < 4 || !(w.v > 0)) continue;
    const [fuel, ba, sat] = wkey.split("|");
    fout.push({ source: "eia.930", key: ba, metric: `ng_${fuel}`, geo: "US", day: sat, value: Math.round(w.v), aux: w.n, meta: { weekly: true, method: "sum_ba_local_days_week_ending_sat" } });
  }
  await ingest(run, out, 2000);
  await ingest(run, fout, 2000);
  return { rows: out.length + fout.length, ok: true, bas: nBa, gen_bas: gbas.size, days: days.size, col: iAdj >= 0 ? "adjusted" : "demand", fuel_weeks: fout.length, fuel_cols: [iSol, iWind], fuel_days: fsum.size };
}
async function modeEia930(run: Run, backfill = false) {
  const t0 = Date.now();
  const now = new Date();
  const all = halves(2015, 2, now);
  // v3: files are re-read once so that solar / wind net generation (added in e7) is backfilled too
  const bf = await st<{ done?: string[]; v?: number }>("econ.bf.eia.930", {});
  const done = new Set(bf.v === 3 ? (bf.done ?? []) : []);
  let todo: string[];
  if (backfill) todo = all.filter((f) => !done.has(f)).reverse(); // newest first: positive controls (2023-2024) early
  else {
    todo = [all[all.length - 1]];
    const dayOfHalf = (now.getTime() - Date.UTC(now.getUTCFullYear(), now.getUTCMonth() < 6 ? 0 : 6, 1)) / 86400000;
    if (dayOfHalf < 14 && all.length > 1) todo.unshift(all[all.length - 2]);
  }
  const files: unknown[] = [];
  let rows = 0;
  for (const f of todo) {
    if (run.outOfTime(60_000)) { run.partial = true; break; }
    const r = await eiaBulkFile(run, f);
    files.push({ file: f, ...r });
    rows += r.rows;
    if (!r.ok) { run.partial = true; break; }
    if (backfill || f !== all[all.length - 1]) { done.add(f); await stSet(run, "econ.bf.eia.930", { v: 3, done: [...done].sort() }); }
    if (backfill) break; // one ~100 MB file per run (CPU budget)
  }
  const left = all.filter((f) => !done.has(f)).length;
  if (backfill && left) { run.partial = true; run.nextCursor = { source: "eia.930", files_left: left }; }
  run.extra.eia930 = { files, left: backfill ? left : undefined };
  run.source({ source: "eia.930", status: run.partial ? "partial" : "ok", rows, ms: Date.now() - t0 });
}

// ================================================================== BLS series via their FRED mirrors
// api.bls.gov/robots.txt is "Disallow: /" (checked 2026-09-25) -> the keyed BLS API is ORANGE* and not used without an
// owner decision + a runtime override. FRED republishes the BLS CES / CPI series under the same ids (public domain), so
// bls.ces / bls.cpi_items are fetched through the FRED API (fetch source fred, bucket fred) and stored under their BLS
// source ids. Monthly series are refreshed only once per release window (att_release_dates) or when > 35 days stale, so
// the FRED bucket stays within 300 calls/day. meta.released = the ALFRED first-release date (the SQL release calendar is
// only a fallback for rows without it).
async function modeBls(run: Run, which: "ces" | "cpi", backfill = false) {
  const t0 = Date.now();
  const source = which === "ces" ? "bls.ces" : "bls.cpi_items";
  const key = await secret(run, "fred_api_key");
  if (!key) return noKey(run, source, "fred_api_key");
  const cfg = await cfgEcon();
  const today = todayUtc();
  const stKey = `econ.bls.${which}`;
  const s = await st<{ fetched?: Record<string, string>; nsa?: string[]; missing?: string[]; rt?: string[] }>(stKey, {});
  const fetched = s.fetched ?? {}, nsa = new Set(s.nsa ?? []), missing = new Set(s.missing ?? []);
  // rt = ids whose FULL history was read as first releases (e5). Series fetched before e4 hold revised values
  // (meta.rt = 'latest'); the backfill drain re-reads them once as first releases.
  const rt = new Set(s.rt ?? []);
  // release window: the day of and the 2 days after a jobs (CES) / CPI release
  const rel = which === "ces" ? "jobs" : "cpi";
  const { data: near, error: nerr } = await db.rpc("att_release_near", { p_release: rel, p_days: 2 });
  if (nerr) run.errors.push(`att_release_near: ${nerr.message}`);
  const inWindow = near === true;
  const ids = which === "ces" ? CES_ALL : CPI_ITEMS.map((c) => (nsa.has(c) ? `CUUR0000${c}` : `CUSR0000${c}`));
  // CES: FRED mirrors only part of the CES detail. One series/search call per page (<= 4 pages, refreshed every 30 days)
  // lists the CES "all employees" ids FRED carries, so absent ids cost no request (budget: fred bucket).
  let avail: Set<string> | null = null;
  if (which === "ces") {
    const av = await st<{ at?: string; ids?: string[] }>("econ.bls.ces.avail", {});
    if (av.at && av.at >= addDays(today, -30) && Array.isArray(av.ids) && av.ids.length) avail = new Set(av.ids);
    else if (!run.skipped.some((x) => x.host === "api.stlouisfed.org")) {
      const found: string[] = [];
      let ok = true;
      for (let off = 0; off < 4000; off += 1000) {
        const q = new URLSearchParams({ search_text: "CES*01", search_type: "series_id", api_key: key, file_type: "json", limit: "1000", offset: String(off) });
        const j = await getJson(run, "fred", `${FRED}/series/search?${q}`);
        if (!j) { ok = false; break; }
        const ss = Array.isArray(j.seriess) ? j.seriess : [];
        for (const x of ss) { const sid = String(x?.id ?? ""); if (/^CES\d{8}01$/.test(sid)) found.push(sid); }
        if (ss.length < 1000) break;
      }
      if (ok && found.length) { avail = new Set(found); await stSet(run, "econ.bls.ces.avail", { at: today, ids: [...avail].sort(), n: avail.size }); }
    }
  }
  let rows = 0, done = 0, wanted = 0, notOnFred = 0;
  for (const id of ids) {
    const alias = which === "ces" ? CES_FRED_ALIAS[id] : undefined;
    if (alias && missing.has(id)) missing.delete(id); // recorded missing before the alias map existed
    if (!alias && avail && !avail.has(id)) { if (!missing.has(id)) { missing.add(id); notOnFred++; } continue; }
    if (missing.has(id) && run.params.force !== true) continue;
    const last = fetched[id];
    if (!backfill && !last && run.params.force !== true) continue; // never fetched: left to the budget-guarded backfill drain
    const stale = !last || last < addDays(today, -35);
    if (!backfill && !stale && !(inWindow && last < addDays(today, -3)) && run.params.force !== true) continue; // once per release window
    if (backfill && last && rt.has(id) && run.params.force !== true) continue;
    wanted++;
    if (run.outOfTime(8000) || run.skipped.some((x) => x.host === "api.stlouisfed.org")) { run.partial = true; continue; }
    const from = backfill || !last ? String(cfg.fred_from ?? "2016-01-01") : addDays(today, -400);
    // first releases only (ALFRED output_type=4): value as first published + its release date
    const q = new URLSearchParams({ series_id: alias ?? id, api_key: key, file_type: "json", observation_start: from, limit: "100000",
      output_type: "4", realtime_start: "1776-07-04", realtime_end: "9999-12-31" });
    const res = await politeFetch(run, `${FRED}/series/observations?${q}`, { source: "fred", headers: { accept: "application/json" }, timeoutMs: 30_000 });
    if (!res) { run.partial = true; continue; }
    if (res.status === 400 || res.status === 404) {
      await res.body?.cancel();
      // SA CPI item not on FRED -> try the NSA id next run; a CES id without a FRED mirror is recorded as missing
      if (which === "cpi" && id.startsWith("CUSR")) nsa.add(id.slice(8)); else missing.add(id);
      continue;
    }
    if (!res.ok) { await res.body?.cancel(); run.errors.push(`fred(${source}) ${id}: http ${res.status}`); continue; }
    const j = await res.json().catch(() => null);
    const out: ObsRow[] = [];
    for (const o of Array.isArray(j?.observations) ? j.observations : []) {
      const v = num(o?.value);
      if (!isDay(o?.date) || v === null) continue;
      const rs = isDay(o?.realtime_start) ? String(o.realtime_start) : "";
      out.push({ source, key: id, metric: which === "ces" ? "emp" : "index", geo: "US", day: o.date, value: v,
        meta: { rt: "first", vintage: rs, released: rs, sa: !id.startsWith("CUUR") && !id.startsWith("CEU"), ...(alias ? { ref: `fred:${alias}` } : {}) } });
    }
    rows += (await ingest(run, out)).rows;
    fetched[id] = today; done++;
    if (from <= String(cfg.fred_from ?? "2016-01-01")) rt.add(id);
    await stSet(run, stKey, { fetched, nsa: [...nsa].sort(), missing: [...missing].sort(), rt: [...rt].sort() });
  }
  await stSet(run, stKey, { fetched, nsa: [...nsa].sort(), missing: [...missing].sort(), rt: [...rt].sort() });
  if (!run.dryRun) {
    const { error } = await db.rpc("att_econ_apply_releases");
    if (error) run.errors.push(`att_econ_apply_releases: ${error.message}`);
  }
  const pending = wanted - done;
  if (pending > 0) { run.partial = true; run.nextCursor = { source, pending }; }
  run.extra[`bls_${which}`] = { rows, fetched_now: done, pending, nsa: [...nsa], missing: [...missing].slice(0, 40), n_missing: missing.size,
    not_on_fred_now: notOnFred, fred_ces_ids: avail ? avail.size : undefined, n_fetched: Object.keys(fetched).length,
    n_first_release_full: rt.size, via: "FRED mirror" };
  run.source({ source, status: run.partial ? "partial" : "ok", keys: done, rows, ms: Date.now() - t0 });
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
  // 'US' = sum over the 50 states + DC (PR / VI excluded), weeks where all 51 reported: the aggregate key of
  // att_engine_source_map (regional demeaning, ENGINE §3.5).
  const agg = new Map<string, { v: number; n: number }>();
  for (const r of out) {
    if (r.key === "PR" || r.key === "VI") continue;
    const k = `${r.metric}|${r.day}`;
    const a = agg.get(k) ?? { v: 0, n: 0 }; a.v += r.value; a.n++; agg.set(k, a);
  }
  let nUs = 0;
  for (const [k, a] of agg) {
    if (a.n < 51) continue;
    const [metric, day] = k.split("|");
    out.push({ source: "dol.claims", key: "US", metric, geo: "US", day, value: a.v, aux: a.n, meta: { method: "sum_50_states_dc" } });
    nUs++;
  }
  await ingest(run, out);
  run.extra.dol = { header: hdr.slice(0, 30), lines, rows: out.length, us_rows: nUs, from, columns: { ic: "c3", cw: "c8" } };
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
  const list: Array<[string, string]> = Array.isArray(cfg.noaa_stations) && cfg.noaa_stations.length ? cfg.noaa_stations : NOAA_STATIONS;
  const stateOf = new Map(list);
  const all = list.map(([s]) => s);
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
function bfsWeekEnd(y: number, w: number): string | null {
  if (!(y >= 2000 && y <= 2100 && w >= 1 && w <= 53)) return null;
  const jan1 = Date.UTC(y, 0, 1);
  const firstSat = jan1 + ((6 - new Date(jan1).getUTCDay() + 7) % 7) * 86400000;
  return new Date(firstSat + (w - 1) * 7 * 86400000).toISOString().slice(0, 10);
}
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
    const txt = (await res.text()).replace(/^\uFEFF/, "");
    const lines = txt.split(/\r?\n/).filter((l) => l.trim());
    const split = (l: string) => l.match(/("([^"]|"")*"|[^,]*)(,|$)/g)!.map((x) => x.replace(/,$/, "").replace(/^"|"$/g, "").trim()).slice(0, -1);
    const hdr = split(lines[0]).map((h) => h.toLowerCase());
    notes.push({ url_path: new URL(u).pathname, header: hdr.slice(0, 12), n: lines.length - 1 });
    const iDate = hdr.findIndex((h) => /week.*end|date|period|time/.test(h));
    const iYear = hdr.indexOf("year"), iWeek = hdr.indexOf("week");
    const iGeo = hdr.findIndex((h) => /^(geo|state|geography|region)$/.test(h));
    const iVal = hdr.findIndex((h) => /^(ba|value|business applications|ba_nsa|ba_ba)$/.test(h));
    const out: ObsRow[] = [];
    for (const l of lines.slice(1)) {
      const f = split(l);
      // weekly files carry Year + Week (no date): day = week-ending Saturday, week 1 = the week ending on the year's first
      // Saturday (Census BFS weekly convention as we read it; meta.ref keeps year-week so the mapping can be audited)
      const yw = iDate < 0 && iYear >= 0 && iWeek >= 0 ? bfsWeekEnd(Number(f[iYear]), Number(f[iWeek])) : null;
      const day = yw ?? parseUsDate(f[iDate] ?? "") ?? (isDay(f[iDate]) ? f[iDate] : null);
      if (!day || day < from) continue;
      const ref = yw ? { ref: `${f[iYear]}-W${f[iWeek]}` } : undefined;
      if (iVal >= 0) {
        const g = iGeo >= 0 ? (f[iGeo] ?? "").toUpperCase() : "US"; const v = num(f[iVal]);
        if (v === null || !/^([A-Z]{2}|US)$/.test(g)) continue;
        out.push({ source: "census.bfs", key: g, metric: "ba", geo: g === "US" ? "US" : `US-${g}`, day, value: v, meta: ref });
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

// ================================================================== FRED state panels (ENGINE 6.3, source fred.state)
// One FRED call per (state, series); every value is the first-released one (ALFRED output_type=4). Order: minimum wage
// first (annual, 51 calls: the policy.min_wage event family), then the monthly panels. Missing ids (400/404) are
// recorded once and never retried without params.force.
interface StS { suffix?: string; prefix?: string; metric: string; kind: Kind; annual?: boolean }
const FRED_STATE_SERIES: StS[] = [
  { prefix: "STTMINWG", metric: "minwage", kind: "level", annual: true },
  { suffix: "LEIH", metric: "leih", kind: "level" },
  { suffix: "CONS", metric: "cons", kind: "level" },
  { suffix: "UR", metric: "ur", kind: "rate" },
  { suffix: "BPPRIV", metric: "bppriv", kind: "count" },
];
function fredStateId(s: StS, st: string): string { return s.prefix ? `${s.prefix}${st}` : `${st}${s.suffix}`; }
async function modeFredState(run: Run) {
  const t0 = Date.now();
  const key = await secret(run, "fred_api_key");
  if (!key) return noKey(run, "fred.state", "fred_api_key");
  const cfg = await cfgEcon();
  const today = todayUtc();
  const st0 = await st<{ fetched?: Record<string, string>; missing?: string[] }>("econ.fred.state", {});
  const fetched = st0.fetched ?? {}, missing = new Set(st0.missing ?? []);
  const only: string[] | null = Array.isArray(run.params.metrics) ? run.params.metrics.map(String) : null;
  const from0 = String(cfg.fred_state_from ?? cfg.fred_from ?? "2015-01-01");
  let rows = 0, done = 0, wanted = 0, fails = 0;
  outer: for (const s of FRED_STATE_SERIES) {
    if (only && !only.includes(s.metric)) continue;
    for (const stc of FRED_STATES) {
      const id = fredStateId(s, stc);
      if (missing.has(id) && run.params.force !== true) continue;
      const last = fetched[id];
      const stale = !last || last < addDays(today, s.annual ? -120 : -32);
      if (!stale && run.params.force !== true) continue;
      wanted++;
      if (run.outOfTime(8000) || run.skipped.some((x) => x.host === "api.stlouisfed.org")) { run.partial = true; break outer; }
      const from = !last ? from0 : addDays(today, s.annual ? -800 : -400);
      const q = new URLSearchParams({ series_id: id, api_key: key, file_type: "json", observation_start: from, limit: "100000",
        output_type: "4", realtime_start: "1776-07-04", realtime_end: "9999-12-31" });
      const res = await politeFetch(run, `${FRED}/series/observations?${q}`, { source: "fred.state", headers: { accept: "application/json" }, timeoutMs: 30_000 });
      if (!res) { run.partial = true; break outer; }
      if (res.status === 400 || res.status === 404) { await res.body?.cancel(); missing.add(id); continue; }
      if (!res.ok) { await res.body?.cancel(); run.errors.push(`fred.state ${id}: http ${res.status}`); fails++; continue; }
      const j = await res.json().catch(() => null);
      const out: ObsRow[] = [];
      for (const o of Array.isArray(j?.observations) ? j.observations : []) {
        const v = num(o?.value);
        if (!isDay(o?.date) || v === null) continue;
        const rs = isDay(o?.realtime_start) ? String(o.realtime_start) : "";
        out.push({ source: "fred.state", key: id, metric: s.metric, geo: `US-${stc}`, day: o.date, value: v,
          meta: { rt: "first", vintage: rs, released: rs, ...(s.annual ? { annual: true, ref: "dol:state-minimum-wage-history" } : { monthly: true }) } });
      }
      rows += (await ingest(run, out)).rows;
      fetched[id] = today; done++;
      await stSet(run, "econ.fred.state", { fetched, missing: [...missing].sort() });
    }
  }
  await stSet(run, "econ.fred.state", { fetched, missing: [...missing].sort() });
  const pending = Math.max(0, wanted - done - fails);
  if (pending > 0) { run.partial = true; run.nextCursor = { source: "fred.state", pending }; }
  run.extra.fred_state = { fetched_now: done, rows, fails, pending, n_fetched: Object.keys(fetched).length, n_missing: missing.size,
    of: FRED_STATE_SERIES.length * FRED_STATES.length };
  run.source({ source: "fred.state", status: fails && !done ? "http_error" : run.partial ? "partial" : "ok", keys: done, rows, ms: Date.now() - t0 });
}

// ================================================================== probe / backfill dispatch
async function modeProbe(run: Run) {
  const url = String(run.params.url ?? "");
  const source = String(run.params.source ?? "");
  if (!url || !source) { run.errors.push("probe needs params.url and params.source"); return; }
  let u = url;
  const kp = run.params.key_param ? String(run.params.key_param) : null;
  const kn: Record<string, string> = { fred: "fred_api_key",
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
    case "fred_rt": return await modeFredRt(run);
    case "eia.930": return await modeEia930(run, true);
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
  bls_ces: wrap((r) => modeBls(r, "ces", false)),
  bls_cpi: wrap((r) => modeBls(r, "cpi", false)),
  dol_claims: wrap((r) => modeDol(r, false)),
  noaa: wrap((r) => modeNoaa(r, false)),
  census_bfs: wrap((r) => modeBfs(r, false)),
  fred_state: wrap(modeFredState),
  backfill: wrap(modeBackfill),
  probe: wrap(modeProbe),
  ping: wrap(async (r) => { r.extra.version = ECON_VERSION; r.extra.wsa = "ok"; }),
});
