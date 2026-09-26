// att-infra — Ripple Map ENGINE 6.3 (v1 inputs the owner requires): grid sub-regions, electric disturbances, work stoppages.
//
// Modes (body.mode):
//   eia_subregion  EIA-930 Hourly Electric Grid Monitor SUB-REGION six-month bulk CSVs (www.eia.gov, keyless, same host
//                  and source as att-econ's eia.930 balance files): hourly demand per balancing-authority sub-region
//                  (CISO, ERCO, ISNE, MISO, NYIS, PJM, SWPP zones and others). Stored as WEEKLY MEAN daily demand (MWh/day)
//                  per sub-region, week ending Saturday, >= 4 complete local days (>= 20 hours) — never daily rows (storage
//                  budget: ~28k rows instead of ~180k). source eia.930, metric sub_demand, key '<BA>-<SUBREGION>', geo US,
//                  meta {weekly: true}. Treated sets for the 'sub' geo kind come from ripples.att_eia_subregion_map
//                  (zone -> states; lineage note in ENGINE_63.md §2). Backfill: one file per run, newest first, from
//                  2018 H2 (the first sub-region file); cursor att_state 'infra.bf.eia.sub' {done: [file]}. Daily: the
//                  current half-year file.
//   bls_wsp        BLS Work Stoppages monthly listing (www.bls.gov/web/wkstp/monthly-listing.xlsx): major stoppages
//                  (>= 1,000 workers) -> library events, family labor.stoppage, states from the "States" column. The
//                  request goes through politeFetch: robots.txt decides, a 403 kills the host permanently (no bypass),
//                  and a refused host is written to the 6.3 kill log by the caller. XLSX is parsed with SheetJS.
//   ping           no requests.
// OE-417 (DOE electric disturbance events) is NOT collected here: www.oe.netl.doe.gov/robots.txt is unreachable for the
// collector (policy: unreachable = deny) and the energy.gov landing pages answer 404 (probed 2026-09-26); recorded in the
// 6.3 kill log (attack 'source_unavailable') rather than bypassed.
// Every request goes through politeFetch (registered source, hosts, robots.txt, budget, kill switch, host lease).
import { addDays, db, errMsg, ingest, type ObsRow, type Run, serve, stateGet, stateSet } from "./att.ts";
import { getText, todayUtc, wrap } from "./wsa.ts";

export const INFRA_VERSION = "2026-09-26.i1";

async function st<T>(k: string, dflt: T): Promise<T> { return ((await stateGet(k).catch(() => null)) ?? dflt) as T; }
async function stSet(run: Run, k: string, v: unknown) { if (!run.dryRun) await stateSet(k, v).catch((e) => run.errors.push(`state ${k}: ${errMsg(e)}`)); }

// ================================================================== EIA-930 sub-regions
const EIA_BULK = "https://www.eia.gov/electricity/gridmonitor/sixMonthFiles";
function halves(fromY: number, fromH: 1 | 2, to: Date): string[] {
  const out: string[] = [];
  const toY = to.getUTCFullYear(), toH = to.getUTCMonth() < 6 ? 1 : 2;
  for (let y = fromY, h = fromH; y < toY || (y === toY && h <= toH); h === 1 ? (h = 2) : (h = 1, y++)) {
    out.push(`EIA930_SUBREGION_${y}_${h === 1 ? "Jan_Jun" : "Jul_Dec"}.csv`);
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
function parseUsDate(s: string): string | null {
  const t = s.trim().replace(/^"|"$/g, "");
  if (/^\d{4}-\d{2}-\d{2}/.test(t)) return t.slice(0, 10);
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(t);
  return m ? `${m[3]}-${m[1].padStart(2, "0")}-${m[2].padStart(2, "0")}` : null;
}
const satOf = (day: string) => { const d = new Date(day + "T00:00:00Z"); return new Date(d.getTime() + ((6 - d.getUTCDay() + 7) % 7) * 86400000).toISOString().slice(0, 10); };

async function subregionFile(run: Run, name: string): Promise<{ rows: number; ok: boolean; subs: number; days: number; weeks: number }> {
  const res = await getText(run, "eia.930", `${EIA_BULK}/${name}`, { accept: "text/csv,*/*" }, 100_000);
  if (!res || !res.body) return { rows: 0, ok: false, subs: 0, days: 0, weeks: 0 };
  const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
  const sums = new Map<string, number>(), hours = new Map<string, number>(); // `${ba}-${sub}|${date}`
  let buf = "", header: string[] | null = null, iBa = -1, iSub = -1, iDate = -1, iDem = -1, maxIdx = 0, complete = true;
  const handle = (line: string) => {
    if (!line) return;
    if (!header) {
      header = csvFields(line, 100).map((h) => h.trim().toLowerCase());
      iBa = header.indexOf("balancing authority"); iDate = header.indexOf("data date");
      iSub = header.findIndex((h) => h === "sub-region" || h === "subregion" || h === "sub region");
      iDem = header.indexOf("demand (mw)");
      maxIdx = Math.max(iBa, iSub, iDate, iDem);
      return;
    }
    const f = csvFields(line, maxIdx);
    const ba = f[iBa], sub = f[iSub], dt = f[iDate], raw = f[iDem];
    if (!ba || !sub || !dt || !raw) return;
    const v = Number(raw.replace(/,/g, ""));
    if (!Number.isFinite(v) || v < 0) return;
    const k = `${ba}-${sub}|${dt}`;
    sums.set(k, (sums.get(k) ?? 0) + v); hours.set(k, (hours.get(k) ?? 0) + 1);
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
  if (!header || iBa < 0 || iSub < 0 || iDate < 0 || iDem < 0) { run.errors.push(`eia.930 ${name}: unexpected sub-region header`); return { rows: 0, ok: false, subs: 0, days: 0, weeks: 0 }; }
  if (!complete) { run.partial = true; return { rows: 0, ok: false, subs: 0, days: 0, weeks: 0 }; }
  // local-day sums (>= 20 hours) -> weekly MEAN daily demand (>= 4 days), week ending Saturday
  const wk = new Map<string, { v: number; n: number }>();
  const subs = new Set<string>(), days = new Set<string>();
  for (const [k, v] of sums) {
    if ((hours.get(k) ?? 0) < 20) continue;
    const [key, dt] = k.split("|");
    const day = parseUsDate(dt);
    if (!day || !/^[A-Z0-9]{2,6}-[A-Z0-9]{2,8}$/.test(key)) continue;
    subs.add(key); days.add(day);
    const wkey = `${key}|${satOf(day)}`;
    const w = wk.get(wkey) ?? { v: 0, n: 0 }; w.v += v; w.n++; wk.set(wkey, w);
  }
  const out: ObsRow[] = [];
  for (const [wkey, w] of wk) {
    if (w.n < 4 || !(w.v > 0)) continue;
    const [key, sat] = wkey.split("|");
    out.push({ source: "eia.930", key, metric: "sub_demand", geo: "US", day: sat, value: Math.round(w.v / w.n), aux: w.n, meta: { weekly: true, method: "mean_local_day_demand_week_ending_sat" } });
  }
  await ingest(run, out, 2000);
  return { rows: out.length, ok: true, subs: subs.size, days: days.size, weeks: out.length };
}
async function modeSubregion(run: Run, backfill = false) {
  const t0 = Date.now();
  const now = new Date();
  const all = halves(2018, 2, now);
  const bf = await st<{ done?: string[] }>("infra.bf.eia.sub", {});
  const done = new Set(bf.done ?? []);
  let todo: string[];
  if (backfill) todo = all.filter((f) => !done.has(f)).reverse();
  else {
    todo = [all[all.length - 1]];
    const dayOfHalf = (now.getTime() - Date.UTC(now.getUTCFullYear(), now.getUTCMonth() < 6 ? 0 : 6, 1)) / 86400000;
    if (dayOfHalf < 14 && all.length > 1) todo.unshift(all[all.length - 2]);
  }
  const files: unknown[] = [];
  let rows = 0;
  for (const f of todo) {
    if (run.outOfTime(60_000)) { run.partial = true; break; }
    const r = await subregionFile(run, f);
    files.push({ file: f, ...r });
    rows += r.rows;
    if (!r.ok) { run.partial = true; break; }
    if (backfill || f !== all[all.length - 1]) { done.add(f); await stSet(run, "infra.bf.eia.sub", { done: [...done].sort() }); }
    if (backfill) break; // one file per run
  }
  const left = all.filter((f) => !done.has(f)).length;
  if (backfill && left) { run.partial = true; run.nextCursor = { source: "eia.930", files_left: left }; }
  run.extra.eia_sub = { files, left: backfill ? left : undefined };
  run.source({ source: "eia.930", status: run.partial ? "partial" : "ok", rows, ms: Date.now() - t0, note: "sub-regions (weekly means)" });
}

// ================================================================== BLS work stoppages (monthly listing xlsx)
const BLS_WSP = "https://www.bls.gov/web/wkstp/monthly-listing.xlsx";
const STATE_CODES: Record<string, string> = { alabama: "AL", alaska: "AK", arizona: "AZ", arkansas: "AR", california: "CA", colorado: "CO",
  connecticut: "CT", delaware: "DE", "district of columbia": "DC", florida: "FL", georgia: "GA", hawaii: "HI", idaho: "ID", illinois: "IL",
  indiana: "IN", iowa: "IA", kansas: "KS", kentucky: "KY", louisiana: "LA", maine: "ME", maryland: "MD", massachusetts: "MA", michigan: "MI",
  minnesota: "MN", mississippi: "MS", missouri: "MO", montana: "MT", nebraska: "NE", nevada: "NV", "new hampshire": "NH", "new jersey": "NJ",
  "new mexico": "NM", "new york": "NY", "north carolina": "NC", "north dakota": "ND", ohio: "OH", oklahoma: "OK", oregon: "OR",
  pennsylvania: "PA", "rhode island": "RI", "south carolina": "SC", "south dakota": "SD", tennessee: "TN", texas: "TX", utah: "UT",
  vermont: "VT", virginia: "VA", washington: "WA", "west virginia": "WV", wisconsin: "WI", wyoming: "WY", "puerto rico": "PR" };
const CODE_SET = new Set(Object.values(STATE_CODES));
function statesOf(text: string): string[] {
  const out = new Set<string>();
  const t = String(text ?? "").toLowerCase();
  for (const [name, code] of Object.entries(STATE_CODES)) if (new RegExp(`\\b${name}\\b`).test(t)) out.add(code);
  for (const m of String(text ?? "").matchAll(/\b([A-Z]{2})\b/g)) if (CODE_SET.has(m[1])) out.add(m[1]);
  return [...out].sort();
}
function excelDate(v: unknown): string | null {
  if (typeof v === "number" && Number.isFinite(v)) return new Date(Math.round((v - 25569) * 86400000)).toISOString().slice(0, 10);
  const s = String(v ?? "").trim();
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})/.exec(s);
  return m ? `${m[3]}-${m[1].padStart(2, "0")}-${m[2].padStart(2, "0")}` : null;
}
const slugify = (s: string, n = 60) => s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, n).replace(/-+$/, "");
async function modeBlsWsp(run: Run) {
  const t0 = Date.now();
  const res = await getText(run, "bls.wsp", BLS_WSP, { accept: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,*/*" }, 60_000);
  if (!res) { run.source({ source: "bls.wsp", status: run.skipped.some((s) => s.host === "www.bls.gov") ? "refused" : "http_error", ms: Date.now() - t0, note: run.skipped.map((s) => s.reason).join(",") || null }); return; }
  const bytes = new Uint8Array(await res.arrayBuffer());
  const XLSX = await import("npm:xlsx@0.18.5");
  const wb = XLSX.read(bytes, { type: "array", cellDates: false });
  const ws = wb.Sheets[wb.SheetNames[0]];
  const rowsA: unknown[][] = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: null }) as unknown[][];
  // header row = the first row that names the organisation and the start date
  let hi = -1, cols: string[] = [];
  for (let i = 0; i < Math.min(rowsA.length, 30); i++) {
    const c = (rowsA[i] ?? []).map((x) => String(x ?? "").trim().toLowerCase());
    if (c.some((x) => x.includes("organization")) && c.some((x) => x.includes("start"))) { hi = i; cols = c; break; }
  }
  if (hi < 0) { run.errors.push("bls.wsp: header row not found"); run.source({ source: "bls.wsp", status: "parse_error", ms: Date.now() - t0 }); return; }
  const ix = (re: RegExp) => cols.findIndex((c) => re.test(c));
  const cOrg = ix(/organization/), cState = ix(/^state/), cStart = ix(/start/), cEnd = ix(/end/), cWorkers = ix(/workers|number/), cInd = ix(/industry|naics/);
  const minWorkers = Number(run.params.min_workers ?? 1000);
  const lib: Record<string, unknown>[] = [];
  let seen = 0;
  for (const r of rowsA.slice(hi + 1)) {
    const org = String(r[cOrg] ?? "").trim();
    const start = excelDate(r[cStart]);
    if (!org || !start) continue;
    seen++;
    const workers = Number(String(r[cWorkers] ?? "").replace(/,/g, ""));
    if (!(workers >= minWorkers)) continue;
    const states = statesOf(String(r[cState] ?? ""));
    if (!states.length) continue;
    const end = cEnd >= 0 ? excelDate(r[cEnd]) : null;
    lib.push({ slug: `wsp-${slugify(org, 40)}-${start}`, family: "labor.stoppage", onset: start, label: `${org} work stoppage (${start})`,
      magnitude: Math.round(Math.log10(workers) * 1000) / 1000, states, source: "BLS Work Stoppages monthly listing",
      ref: `${start}..${end ?? "open"}; ${workers} workers; ${String(r[cInd] ?? "").slice(0, 60)}`, defined_by: ["bls.wsp"] });
  }
  let up: Record<string, number> = {};
  if (lib.length && !run.dryRun) {
    for (let i = 0; i < lib.length; i += 200) {
      const { data, error } = await db.rpc("att_library_upsert", { p_rows: lib.slice(i, i + 200) });
      if (error) { run.errors.push(`att_library_upsert: ${error.message}`); continue; }
      for (const k of ["new", "updated", "topics_new", "skipped"]) up[k] = (up[k] ?? 0) + Number((data as any)?.[k] ?? 0);
    }
  }
  run.extra.bls_wsp = { rows_seen: seen, events: lib.length, min_workers: minWorkers, header: cols.slice(0, 12), upsert: up, sample: lib.slice(0, 3).map((x) => x.slug) };
  run.source({ source: "bls.wsp", status: "ok", rows: lib.length, ms: Date.now() - t0 });
}

serve("att-infra", {
  eia_subregion: wrap((r) => modeSubregion(r, false)),
  eia_subregion_bf: wrap((r) => modeSubregion(r, true)),
  bls_wsp: wrap(modeBlsWsp),
  ping: wrap(async (r) => { r.extra.version = INFRA_VERSION; }),
});
