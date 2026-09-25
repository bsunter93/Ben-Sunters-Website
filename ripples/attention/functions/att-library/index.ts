// att-library — Ripple Map v6 (WS-A): the event library (ENGINE_SPEC §5.8) and the positive-control history (§5.6.4).
// Writes past family events through public.att_library_upsert (role 'library', reconstructed) and backfills the outcome
// history the controls need, reusing the exact series semantics of the collectors that own those sources.
//
// Modes (body.mode):
//   fema        OpenFEMA DisasterDeclarationsSummaries by declaration year (newest first; cursor att_state 'lib.fema'):
//               (a) national daily keys all / DR / EM / FM / it:<incident type> = distinct disasters declared that day
//                   (aux = designated areas), exactly as att-world, only for days before att-world's own first day;
//               (b) state keys st:<XX> = distinct disasters declared in that state that day (aux = areas), zero-filled;
//               (c) library events: NAMED STORMS (any title naming a hurricane / tropical storm / typhoon, incl.
//                   'Remnants of ...', 'Post-Tropical ...') -> one event per (storm name, year), canonical slug
//                   storm-<name>-<year>, merged across runs and with GDACS (att_library_upsert merge); other declarations
//                   grouped by (incident type, title, incident begin dates <= 7 days apart) -> one event with its states
//                   (hazard.storm / flood / wildfire / cold / quake; biological, chemical etc. skipped).
//                   defined_by fema.decl: the INST channel is the proposing channel of these events (ENGINE §2.4).
//               params.daily=true: last 30 days only (st:XX keys + events), for the daily cron.
//   usgs        USGS FDSN events with >= params.min_felt (1000) "Did You Feel It?" reports since 2019 in the U.S.
//               -> hazard.quake events (about 50 a year; felt >= 50 gave ~400 a year, too many for a family library).
//               defined_by usgs.eq; no quake template tests usgs.eq (quake_felt_reports was removed: circular).
//   gdacs       GDACS Orange/Red tropical cyclones (all countries: named storms merge with FEMA by name and year),
//               earthquakes, floods, wildfires (outside the U.S.; the U.S. is covered by FEMA) since 2019. defined_by gdacs.
//   iem_bf      IEM storm-based warnings per UTC day (att-world's iem semantics and key set) for the control windows
//               before att-world's history (default 2024-01-01 .. its first day), one 30-day window per run.
//   npm_bf      npm daily downloads (att-charts semantics: zero = not computed for busy packages) for the control
//               packages from 2022-06-01 up to each series' first stored day, <= 540 days per request.
//   hn_bf       HN Algolia strict daily mention counts (att-social's exact query parameters) for the control terms and
//               windows, plus '__total__' for those days; resumable per term. Daily cap HN_BF_DAY_CAP = 300 requests
//               across all runs of a UTC day (ENGINE §9 "HN 300" for new series; att_state 'lib.bf.hn.day'), on top of
//               the shared hn.algolia bucket.
//   ping        no requests.
// Every request goes through politeFetch with the owning source (hosts, robots, budgets, kill switch).
import { addDays, db, ingest, type ObsRow, politeFetch, type Run, serve, stateGet, stateSet } from "./att.ts";
import { getJson, todayUtc, wrap } from "./wsa.ts";

export const LIBRARY_VERSION = "2026-09-25.l4";

// ------------------------------------------------------------------ helpers
async function st<T>(k: string, dflt: T): Promise<T> { return ((await stateGet(k).catch(() => null)) ?? dflt) as T; }
async function stSet(run: Run, k: string, v: unknown) { if (!run.dryRun) await stateSet(k, v).catch((e) => run.errors.push(`state ${k}: ${String(e)}`)); }
function days(from: string, to: string): string[] {
  const out: string[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) out.push(d);
  return out;
}
const minD = (a: string, b: string) => (a < b ? a : b);
const maxD = (a: string, b: string) => (a > b ? a : b);
const slugify = (s: string, n = 60) => s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, n).replace(/-+$/, "");
const titleCase = (s: string) => s.toLowerCase().replace(/\b([a-z])/g, (m) => m.toUpperCase());
async function firstDay(source: string, key: string, metric: string | null = null): Promise<string | null> {
  const { data } = await db.rpc("att_series_first_day", { p_source: source, p_key: key, p_metric: metric });
  return typeof data === "string" ? data : null;
}
async function upsertLibrary(run: Run, rows: Record<string, unknown>[]): Promise<Record<string, unknown> | null> {
  if (!rows.length || run.dryRun) return null;
  const out: Record<string, number> = {};
  for (let i = 0; i < rows.length; i += 200) {
    const { data, error } = await db.rpc("att_library_upsert", { p_rows: rows.slice(i, i + 200) });
    if (error) { run.errors.push(`att_library_upsert: ${error.message}`); continue; }
    for (const k of ["new", "updated", "topics_new", "skipped"]) out[k] = (out[k] ?? 0) + Number((data as any)?.[k] ?? 0);
  }
  return out;
}

// ------------------------------------------------------------------ FEMA
const US_STATES = ["AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD","MA",
  "MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","PR","RI","SC","SD","TN","TX","UT","VT",
  "VA","WA","WV","WI","WY"];
const FEMA_FAMILY: Record<string, string> = {
  "hurricane": "hazard.storm", "tropical storm": "hazard.storm", "typhoon": "hazard.storm", "tropical depression": "hazard.storm",
  "coastal storm": "hazard.storm", "severe storm": "hazard.storm", "severe storm(s)": "hazard.storm", "tornado": "hazard.storm",
  "straight-line winds": "hazard.storm",
  "flood": "hazard.flood", "dam/levee break": "hazard.flood", "mud/landslide": "hazard.flood",
  "fire": "hazard.wildfire",
  "winter storm": "hazard.cold", "severe ice storm": "hazard.cold", "snowstorm": "hazard.cold", "freezing": "hazard.cold",
  "earthquake": "hazard.quake",
};
const femaSlugType = (it: string) => it.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
// Named-storm detection (same pattern as ripples.att_storm_name in SQL): one storm = one event across FEMA titles
// ('Hurricane X', 'Tropical Storm X', 'Remnants of Hurricane X', 'Post-Tropical Cyclone X', 'Super Typhoon X') and GDACS
// ('Tropical Cyclone X-yy').
const STORM_RE = /(?:POST-TROPICAL (?:STORM|CYCLONE)|REMNANTS OF(?: (?:HURRICANE|TROPICAL STORM|TROPICAL DEPRESSION|TYPHOON|SUPER TYPHOON))?|HURRICANE|TROPICAL STORM|TROPICAL DEPRESSION|SUPER TYPHOON|TYPHOON|TROPICAL CYCLONE)\s+([A-Z]{3,})\b/;
const STORM_STOP = new Set(["AND","THE","OF","SEASON","SEVERE","STORMS","STORM","FLOODING","WINDS","REMNANTS","HURRICANE","TROPICAL",
  "DEPRESSION","CYCLONE","TYPHOON","SUPER","POST"]);
export function stormName(title: string): string | null {
  const m = STORM_RE.exec(title.toUpperCase());
  if (!m || STORM_STOP.has(m[1])) return null;
  return m[1].toLowerCase();
}
const stormKind = (titles: string[]) => titles.some((t) => /HURRICANE/i.test(t)) ? "Hurricane"
  : titles.some((t) => /TYPHOON/i.test(t)) ? "Typhoon" : "Tropical storm";
interface FemaRec { num: number; day: string; type: string; it: string; title: string; state: string; begin: string }
async function femaFetch(run: Run, from: string, to: string): Promise<FemaRec[] | null> {
  const out: FemaRec[] = [];
  for (let skip = 0; skip < 60_000; skip += 10_000) {
    const qs = new URLSearchParams({
      "$select": "disasterNumber,declarationDate,declarationType,incidentType,declarationTitle,state,incidentBeginDate",
      "$filter": `declarationDate ge '${from}T00:00:00.000Z' and declarationDate le '${to}T23:59:59.999Z'`,
      "$orderby": "declarationDate", "$top": "10000", "$skip": String(skip),
    });
    const j = await getJson(run, "fema.decl", `https://www.fema.gov/api/open/v2/DisasterDeclarationsSummaries?${qs.toString().replaceAll("+", "%20")}`, {}, 90_000);
    if (!j) return null;
    const page = j?.DisasterDeclarationsSummaries;
    if (!Array.isArray(page)) { run.errors.push("fema: bad json"); return null; }
    for (const r of page) {
      const day = String(r?.declarationDate ?? "").slice(0, 10), num = Number(r?.disasterNumber);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(num)) continue;
      out.push({ num, day, type: String(r?.declarationType ?? "").toUpperCase(), it: String(r?.incidentType ?? "Other"),
        title: String(r?.declarationTitle ?? ""), state: String(r?.state ?? "").toUpperCase(),
        begin: String(r?.incidentBeginDate ?? r?.declarationDate ?? "").slice(0, 10) });
    }
    if (page.length < 10_000) break;
  }
  return out;
}
function femaSeries(recs: FemaRec[], from: string, to: string, natTo: string | null, types: Set<string>): ObsRow[] {
  const dis = new Map<string, Map<string, Set<number>>>(), areas = new Map<string, Map<string, number>>();
  for (const r of recs) {
    // incident-type keys: only the types att-world maintains (world.fema.types), so no series stops at the hand-over day
    const itKey = `it:${femaSlugType(r.it)}`;
    const keys = ["all", r.type, ...(types.has(itKey) ? [itKey] : [])].filter((k) => /^(all|DR|EM|FM|it:[a-z0-9_]+)$/.test(k));
    if (/^[A-Z]{2}$/.test(r.state)) keys.push(`st:${r.state}`);
    const dm = dis.get(r.day) ?? new Map<string, Set<number>>(); dis.set(r.day, dm);
    const am = areas.get(r.day) ?? new Map<string, number>(); areas.set(r.day, am);
    for (const k of keys) {
      const s = dm.get(k) ?? new Set<number>(); dm.set(k, s); s.add(r.num);
      am.set(k, (am.get(k) ?? 0) + 1);
    }
  }
  const natKeys = ["all", "DR", "EM", "FM", ...[...types].sort()];
  const stKeys = US_STATES.map((s) => `st:${s}`);
  const obs: ObsRow[] = [];
  for (const d of days(from, to)) {
    const keys = natTo && d <= natTo ? [...natKeys, ...stKeys] : stKeys;
    for (const k of keys) {
      obs.push({ source: "fema.decl", key: k, geo: k.startsWith("st:") ? `US-${k.slice(3)}` : "US", metric: "n", day: d,
        value: dis.get(d)?.get(k)?.size ?? 0, aux: areas.get(d)?.get(k) ?? 0 });
    }
  }
  return obs;
}
function femaEvents(recs: FemaRec[]): Record<string, unknown>[] {
  // Named storms: one event per (storm name, year) whatever the incident type / title variant. Other declarations: one
  // event per (incident type, title) and cluster of incident begin dates no more than 7 days apart (a storm declared state
  // by state carries a slightly different begin date in each state); onset = earliest begin date.
  type G = { it: string; title: string; titles: string[]; storm: string | null; begin: string; last: string; states: Set<string>;
             nums: Set<number>; areas: number; types: Set<string> };
  const byKey = new Map<string, G[]>();
  const sorted = recs.filter((r) => FEMA_FAMILY[r.it.toLowerCase()] && /^\d{4}-\d{2}-\d{2}$/.test(r.begin) && r.begin >= "2019-01-01")
    .sort((a, b) => (a.begin < b.begin ? -1 : a.begin > b.begin ? 1 : 0));
  for (const r of sorted) {
    const storm = stormName(r.title);
    const k = storm ? `storm|${storm}|${r.begin.slice(0, 4)}` : `${r.it}|${r.title.toUpperCase().trim()}`;
    const list = byKey.get(k) ?? []; byKey.set(k, list);
    let g = list[list.length - 1];
    if (!g || (!storm && r.begin > addDays(g.last, 7))) {
      g = { it: r.it, title: r.title, titles: [], storm, begin: r.begin, last: r.begin, states: new Set<string>(), nums: new Set<number>(),
            areas: 0, types: new Set<string>() };
      list.push(g);
    }
    if (r.begin > g.last) g.last = r.begin;
    if (/^[A-Z]{2}$/.test(r.state)) g.states.add(r.state);
    g.nums.add(r.num); g.areas++; g.types.add(r.type); g.titles.push(r.title);
  }
  const groups = [...byKey.values()].flat();
  return groups.map((g) => {
    const ref = `${[...g.types].sort().join("/")}-${[...g.nums].sort((a, b) => a - b).slice(0, 8).join(",")}`;
    const base = { onset: g.begin, states: [...g.states].sort(), magnitude: Math.round(Math.log(1 + g.areas) * 1000) / 1000, merge: true,
      source: "OpenFEMA DisasterDeclarationsSummaries", ref, defined_by: ["fema.decl"] };
    if (g.storm) {
      const kind = stormKind(g.titles);
      return { ...base, slug: `storm-${g.storm}-${g.begin.slice(0, 4)}`, storm: g.storm, family: "hazard.storm",
        label: `${kind} ${titleCase(g.storm)} (${g.begin.slice(0, 4)})`, label_weak: kind === "Tropical storm" };
    }
    return { ...base, slug: `fema-${slugify(g.title || g.it, 60)}-${g.begin}`,
      label: `${titleCase(g.title || g.it)} (${g.it}, ${g.begin})`.slice(0, 200), family: FEMA_FAMILY[g.it.toLowerCase()] };
  });
}
async function modeFema(run: Run) {
  const t0 = Date.now();
  const today = todayUtc(), yday = addDays(today, -1);
  const worldFirst = await firstDay("fema.decl", "all", "n");
  const natTo = worldFirst ? addDays(worldFirst, -1) : null; // national keys only before att-world's own history
  const types = new Set<string>(((await stateGet("world.fema.types").catch(() => null)) ?? []) as string[]);
  let rows = 0, events = 0;
  const lib: Record<string, unknown>[] = [];
  if (run.params.daily === true) {
    const from = addDays(yday, -29);
    const recs = await femaFetch(run, from, yday);
    if (!recs) { run.source({ source: "fema.decl", status: "http_error", ms: Date.now() - t0 }); return; }
    const obs = femaSeries(recs, from, yday, null, types);
    rows += (await ingest(run, obs)).rows;
    lib.push(...femaEvents(recs));
  } else {
    const y0 = Number(String(run.params.from ?? "2019-01-01").slice(0, 4));
    const cur = await st<{ next?: number; done?: boolean }>("lib.fema", {});
    if (cur.done && run.params.force !== true) { run.source({ source: "fema.decl", status: "ok", note: "history complete" }); return; }
    let y = cur.next ?? new Date().getUTCFullYear();
    while (y >= y0) {
      if (run.outOfTime(20_000)) { run.partial = true; break; }
      const from = `${y}-01-01`, to = minD(`${y}-12-31`, yday);
      const recs = await femaFetch(run, from, to);
      if (!recs) { run.partial = true; break; }
      const obs = femaSeries(recs, from, to, natTo, types);
      rows += (await ingest(run, obs)).rows;
      lib.push(...femaEvents(recs));
      y--;
      await stSet(run, "lib.fema", { next: y, done: y < y0 });
      if (run.params.one_year !== false) break; // one declaration year per run (fema.decl budget: 10/day shared)
    }
    if (y >= y0) { run.partial = true; run.nextCursor = { year: y }; }
  }
  const up = await upsertLibrary(run, lib);
  events = lib.length;
  run.extra.fema = { rows, events, library: up, national_before: natTo, types: types.size };
  run.source({ source: "fema.decl", status: run.partial ? "partial" : "ok", rows, keys: events, ms: Date.now() - t0 });
}

// ------------------------------------------------------------------ USGS (felt >= 50, U.S.)
const STATE_NAMES: Record<string, string> = {
  alabama: "AL", alaska: "AK", arizona: "AZ", arkansas: "AR", california: "CA", colorado: "CO", connecticut: "CT", delaware: "DE",
  florida: "FL", georgia: "GA", hawaii: "HI", idaho: "ID", illinois: "IL", indiana: "IN", iowa: "IA", kansas: "KS", kentucky: "KY",
  louisiana: "LA", maine: "ME", maryland: "MD", massachusetts: "MA", michigan: "MI", minnesota: "MN", mississippi: "MS",
  missouri: "MO", montana: "MT", nebraska: "NE", nevada: "NV", "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM",
  "new york": "NY", "north carolina": "NC", "north dakota": "ND", ohio: "OH", oklahoma: "OK", oregon: "OR", pennsylvania: "PA",
  "puerto rico": "PR", "rhode island": "RI", "south carolina": "SC", "south dakota": "SD", tennessee: "TN", texas: "TX", utah: "UT",
  vermont: "VT", virginia: "VA", washington: "WA", "west virginia": "WV", wisconsin: "WI", wyoming: "WY", "washington, d.c.": "DC",
};
function usState(place: string): string | null {
  const tail = place.split(",").pop()?.trim() ?? "";
  if (/^[A-Z]{2}$/.test(tail) && US_STATES.includes(tail)) return tail;
  if (tail === "CA") return "CA";
  return STATE_NAMES[tail.toLowerCase()] ?? null;
}
async function modeUsgs(run: Run) {
  const t0 = Date.now();
  const y0 = Number(String(run.params.from ?? "2019-01-01").slice(0, 4)), y1 = new Date().getUTCFullYear();
  const cur = await st<{ next?: number }>("lib.usgs", {});
  let y = run.params.daily === true ? y1 : (cur.next ?? y0);
  const lib: Record<string, unknown>[] = [];
  const minFelt = Math.max(50, Number(run.params.min_felt ?? 1000));
  let calls = 0;
  while (y <= y1 && calls < 3) {
    if (run.outOfTime(15_000)) { run.partial = true; break; }
    const q = new URLSearchParams({ format: "geojson", starttime: `${y}-01-01`, endtime: `${y + 1}-01-01`, minfelt: String(minFelt), orderby: "time-asc", limit: "20000" });
    const j = await getJson(run, "usgs.eq", `https://earthquake.usgs.gov/fdsnws/event/1/query?${q}`, {}, 60_000);
    calls++;
    if (!j) { run.partial = true; break; }
    for (const f of Array.isArray(j.features) ? j.features : []) {
      const p = f?.properties ?? {};
      const stc = usState(String(p.place ?? ""));
      const felt = Number(p.felt), mag = Number(p.mag), t = Number(p.time);
      if (!stc || !Number.isFinite(felt) || felt < minFelt || !Number.isFinite(t)) continue;
      const day = new Date(t).toISOString().slice(0, 10);
      if (day < "2019-01-01" || day >= todayUtc()) continue;
      lib.push({ slug: `quake-${String(f.id ?? "").toLowerCase().replace(/[^a-z0-9]/g, "")}`,
        label: `M${Number.isFinite(mag) ? mag.toFixed(1) : "?"} earthquake, ${String(p.place ?? "").slice(0, 120)}`,
        family: "hazard.quake", onset: day, states: [stc], magnitude: Math.round(Math.log(felt) * 1000) / 1000,
        source: `USGS FDSN (felt >= ${minFelt})`, ref: `felt ${felt}`, defined_by: ["usgs.eq"] });
    }
    if (run.params.daily !== true) { y++; await stSet(run, "lib.usgs", { next: y }); } else break;
  }
  const up = await upsertLibrary(run, lib);
  if (y <= y1 && run.params.daily !== true) { run.partial = true; run.nextCursor = { year: y }; }
  run.extra.usgs = { events: lib.length, library: up };
  run.source({ source: "usgs.eq", status: run.partial ? "partial" : "ok", keys: lib.length, ms: Date.now() - t0 });
}

// ------------------------------------------------------------------ GDACS (Orange/Red, outside the U.S.)
const GDACS_FAMILY: Record<string, string> = { TC: "hazard.storm", EQ: "hazard.quake", FL: "hazard.flood", WF: "hazard.wildfire" };
async function modeGdacs(run: Run) {
  const t0 = Date.now();
  const y0 = Number(String(run.params.from ?? "2019-01-01").slice(0, 4)), y1 = new Date().getUTCFullYear();
  const cur = await st<{ next?: number }>("lib.gdacs", {});
  let y = run.params.daily === true ? y1 : (cur.next ?? y0);
  const lib: Record<string, unknown>[] = [];
  if (y <= y1) {
    const q = new URLSearchParams({ eventlist: "TC;EQ;FL;WF", fromDate: `${y}-01-01`, toDate: minD(`${y}-12-31`, addDays(todayUtc(), -1)), alertlevel: "Orange;Red" });
    const j = await getJson(run, "gdacs", `https://www.gdacs.org/gdacsapi/api/events/geteventlist/SEARCH?${q}`, {}, 60_000);
    if (!j) run.partial = true;
    else {
      for (const f of Array.isArray(j.features) ? j.features : []) {
        const p = f?.properties ?? {};
        const et = String(p.eventtype ?? ""), fam = GDACS_FAMILY[et];
        const iso = String(p.iso3 ?? "").toUpperCase();
        const day = String(p.fromdate ?? "").slice(0, 10);
        if (!fam || !/^\d{4}-\d{2}-\d{2}$/.test(day)) continue;
        const name = String(p.name ?? p.eventname ?? `${et} ${p.country ?? ""}`).trim();
        // tropical cyclones: canonical named-storm event (merges with FEMA's declarations of the same storm); U.S. storms
        // included. Other U.S. hazards come from FEMA only (no duplicate events).
        const tc = et === "TC" ? /\b([A-Z]{3,})-\d{2}\b/.exec(`${p.eventname ?? ""} ${p.name ?? ""}`.toUpperCase()) : null;
        if (tc && !STORM_STOP.has(tc[1])) {
          lib.push({ slug: `storm-${tc[1].toLowerCase()}-${day.slice(0, 4)}`, storm: tc[1].toLowerCase(), merge: true, label_weak: true,
            label: `Tropical cyclone ${titleCase(tc[1])} (${day.slice(0, 4)})`, family: "hazard.storm", onset: day,
            source: "GDACS event list (Orange/Red)", ref: `${et}${p.eventid ?? ""}/${iso}`, defined_by: ["gdacs"] });
          continue;
        }
        if (iso === "USA") continue;
        lib.push({ slug: `gdacs-${et.toLowerCase()}-${String(p.eventid ?? "").replace(/[^0-9]/g, "")}-${day}`,
          label: `${name} (${String(p.alertlevel ?? "")} alert, ${String(p.country ?? iso).slice(0, 60)})`.slice(0, 200),
          family: fam, onset: day, source: "GDACS event list (Orange/Red)", ref: `${et}${p.eventid ?? ""}/${iso}`, defined_by: ["gdacs"] });
      }
      if (run.params.daily !== true) { y++; await stSet(run, "lib.gdacs", { next: y }); }
    }
  }
  const up = await upsertLibrary(run, lib);
  if (y <= y1 && run.params.daily !== true) { run.partial = true; run.nextCursor = { year: y }; }
  run.extra.gdacs = { events: lib.length, library: up };
  run.source({ source: "gdacs", status: run.partial ? "partial" : "ok", keys: lib.length, ms: Date.now() - t0 });
}

// ------------------------------------------------------------------ IEM (att-world semantics)
const IEM_DEFAULT_KEYS = ["TO.W", "SV.W", "FF.W", "EW.W", "SQ.W", "MA.W", "DS.W", "FL.W", "FA.Y"];
async function modeIemBf(run: Run) {
  const t0 = Date.now();
  const worldFirst = await firstDay("iem.warn", "__total__", "n");
  const floor = String(run.params.from ?? "2024-01-01");
  const top = worldFirst ? addDays(worldFirst, -1) : addDays(todayUtc(), -1);
  const cur = await st<{ to?: string; done?: boolean }>("lib.bf.iem", {});
  if (cur.done && run.params.force !== true) { run.source({ source: "iem.warn", status: "ok", note: "backfill complete" }); return; }
  const to = cur.to ? minD(cur.to, top) : top;
  if (to < floor) { await stSet(run, "lib.bf.iem", { to, done: true }); run.source({ source: "iem.warn", status: "ok", note: "backfill complete" }); return; }
  const from = maxD(floor, addDays(to, -29));
  const known = new Set<string>([...IEM_DEFAULT_KEYS, ...(((await stateGet("world.iem.keys").catch(() => null)) ?? []) as string[])]);
  const url = `https://mesonet.agron.iastate.edu/api/1/vtec/sbw_interval.json?begints=${from}T00:00:00Z&endts=${addDays(to, 1)}T00:00:00Z`;
  const j = await getJson(run, "iem.warn", url, {}, 90_000);
  if (!j || !Array.isArray(j.data)) { run.partial = true; run.source({ source: "iem.warn", status: "http_error", ms: Date.now() - t0 }); return; }
  const counts = new Map<string, Map<string, number>>();
  const seen = new Set<string>();
  for (const r of j.data) {
    const issue = String(r?.utc_issue ?? r?.utc_polygon_begin ?? "");
    const day = issue.slice(0, 10);
    const ph = String(r?.phenomena ?? ""), sg = String(r?.significance ?? "");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day < from || day > to || !/^[A-Z]{2}$/.test(ph) || !/^[A-Z]$/.test(sg)) continue;
    const id = `${r?.wfo}|${ph}|${sg}|${r?.eventid}|${r?.year ?? day.slice(0, 4)}`;
    if (seen.has(id)) continue; // one count per VTEC event (the issuance), as att-world
    seen.add(id);
    const k = `${ph}.${sg}`;
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
  const r = await ingest(run, obs);
  const next = addDays(from, -1);
  await stSet(run, "lib.bf.iem", { to: next, done: next < floor });
  if (next >= floor) { run.partial = true; run.nextCursor = { to: next }; }
  run.extra.iem = { window: [from, to], events: seen.size, keys: known.size + 1, floor };
  run.source({ source: "iem.warn", status: run.partial ? "partial" : "ok", rows: r.rows, ms: Date.now() - t0 });
}

// ------------------------------------------------------------------ npm (att-charts semantics)
const NPM = "https://api.npmjs.org/downloads/range";
async function modeNpmBf(run: Run) {
  const t0 = Date.now();
  const pkgs: string[] = Array.isArray(run.params.packages) ? run.params.packages.map(String) : ["openai", "ollama", "@anthropic-ai/sdk", "langchain", "__total__"];
  const floor = String(run.params.from ?? "2022-06-01");
  const state = await st<Record<string, string>>("lib.bf.npm", {}); // pkg -> oldest day fetched
  let rows = 0, calls = 0;
  const done: string[] = [];
  for (const pkg of pkgs) {
    if (run.outOfTime(8000) || run.skipped.some((s) => s.host === "api.npmjs.org")) { run.partial = true; break; }
    const first = state[pkg] ?? (await firstDay("npm.dl", pkg)) ?? todayUtc();
    if (first <= floor) { done.push(pkg); continue; }
    const to = addDays(first, -1), from = maxD(floor, addDays(to, -539));
    const j = await getJson(run, "npm.dl", pkg === "__total__" ? `${NPM}/${from}:${to}` : `${NPM}/${from}:${to}/${pkg}`);
    calls++;
    if (!j) { run.partial = true; continue; }
    const ds = ((j?.downloads ?? []) as any[]).filter((d) => typeof d?.day === "string" && Number.isFinite(Number(d?.downloads)));
    const vals = ds.map((d) => Number(d.downloads)).sort((a, b) => a - b);
    const p75 = vals.length ? vals[Math.floor(vals.length * 0.75)] : 0;
    const dropZero = pkg === "__total__" || p75 > 100; // att-charts: a 0 on a busy package = not computed -> missing
    const out: ObsRow[] = [];
    for (const d of ds) {
      const v = Number(d.downloads);
      if (v === 0 && dropZero) continue;
      if (d.day < from || d.day > to) continue;
      out.push({ source: "npm.dl", key: pkg, day: d.day, value: v });
    }
    rows += (await ingest(run, out)).rows;
    state[pkg] = from;
    await stSet(run, "lib.bf.npm", state);
    if (from > floor) run.partial = true; else done.push(pkg);
  }
  run.extra.npm = { calls, rows, done, floor };
  run.source({ source: "npm.dl", status: run.partial ? "partial" : "ok", rows, keys: done.length, ms: Date.now() - t0 });
}

// ------------------------------------------------------------------ HN Algolia (att-social strict query, verbatim)
const HN = "https://hn.algolia.com/api/v1/search_by_date";
const DAY_S = 86400;
const dayTs = (d: string) => Math.floor(Date.parse(d + "T00:00:00Z") / 1000);
const tsDay = (s: number) => new Date(s * 1000).toISOString().slice(0, 10);
interface HnRes { nbHits: number; times: number[]; exhaustive: boolean }
function hnTerm(term: string): string {
  const t = term.replace(/["“”]/g, " ").replace(/^[-\s]+/, "").replace(/\s+/g, " ").trim();
  return `"${t}"`;
}
async function hnQuery(run: Run, term: string | null, a: number, b: number, hitsPerPage: number): Promise<HnRes | null> {
  const q = new URLSearchParams({
    tags: "(story,comment)", numericFilters: `created_at_i>=${a},created_at_i<${b}`, hitsPerPage: String(hitsPerPage),
    typoTolerance: "false", advancedSyntax: "true", queryType: "prefixNone", ignorePlurals: "false",
    removeStopWords: "false", removeWordsIfNoResults: "none", attributesToRetrieve: "created_at_i",
    restrictSearchableAttributes: "title,story_text,comment_text,url",
    attributesToHighlight: "", attributesToSnippet: "",
    analytics: "false",
  });
  q.set("query", term === null ? "" : hnTerm(term));
  const res = await politeFetch(run, `${HN}?${q}`, { source: "hn.algolia" });
  if (!res) return null;
  if (!res.ok) { run.errors.push(`hn.algolia http ${res.status}`); await res.body?.cancel(); return null; }
  const j = await res.json().catch(() => null);
  if (!j || typeof j.nbHits !== "number") { run.errors.push("hn.algolia bad json"); return null; }
  const times = Array.isArray(j.hits) ? j.hits.map((h: any) => Number(h?.created_at_i)).filter((x: number) => Number.isFinite(x)) : [];
  return { nbHits: j.nbHits, times, exhaustive: j.exhaustiveNbHits !== false && j.exhaustive?.nbHits !== false };
}
async function hnCount(run: Run, term: string, a: number, b: number, maxCalls: number) {
  const counts = new Map<string, number>();
  const est = new Set<string>();
  let calls = 0;
  let doneFrom = b;
  const stack: Array<{ a: number; b: number; exp: number | null }> = [{ a, b, exp: null }];
  let complete = true;
  while (stack.length) {
    const w = stack.pop()!;
    const nd = Math.round((w.b - w.a) / DAY_S);
    if (calls >= maxCalls || run.outOfTime(4000)) { complete = false; break; }
    const dense1 = nd <= 1 && w.exp !== null && w.exp > 1000;
    const r = await hnQuery(run, term, w.a, w.b, dense1 ? 0 : 1000);
    calls++;
    if (!r) { complete = false; break; }
    if (!dense1 && r.nbHits <= r.times.length) {
      for (let d = w.a; d < w.b; d += DAY_S) counts.set(tsDay(d), 0);
      for (const t of r.times) if (t >= w.a && t < w.b) { const d = tsDay(t); counts.set(d, (counts.get(d) ?? 0) + 1); }
      doneFrom = w.a;
      continue;
    }
    if (nd <= 1) {
      counts.set(tsDay(w.a), r.nbHits);
      if (!r.exhaustive) est.add(tsDay(w.a));
      doneFrom = w.a;
      continue;
    }
    const k = Math.min(nd, Math.max(2, Math.ceil(r.nbHits / 700)));
    const step = Math.max(1, Math.floor(nd / k));
    const parts: Array<{ a: number; b: number; exp: number }> = [];
    for (let s = w.a; s < w.b; s += step * DAY_S) {
      const e = Math.min(w.b, s + step * DAY_S);
      parts.push({ a: s, b: e, exp: (r.nbHits * (e - s)) / (w.b - w.a) });
    }
    for (const p of parts) stack.push(p);
  }
  for (const d of [...counts.keys()]) if (dayTs(d) < doneFrom) counts.delete(d);
  return { counts, est, doneFrom, complete: complete && doneFrom <= a, calls };
}
const HN_WINDOWS: Array<{ term: string; from: string; to: string }> = [
  { term: "chatgpt", from: "2022-08-01", to: "2023-01-31" },
  { term: "llama", from: "2024-01-10", to: "2024-06-15" },
  { term: "deepseek", from: "2024-10-15", to: "2025-03-15" },
];
const HN_BF_DAY_CAP = 300; // ENGINE §9: HN 300 requests/day for new-series backfills
async function modeHnBf(run: Run) {
  const t0 = Date.now();
  const today = new Date().toISOString().slice(0, 10);
  const day = await st<{ day?: string; calls?: number }>("lib.bf.hn.day", {});
  const usedToday = day.day === today ? Number(day.calls ?? 0) : 0;
  const maxCalls = Math.max(0, Math.min(Number(run.params.max_calls ?? 60), HN_BF_DAY_CAP - usedToday));
  if (maxCalls <= 0) {
    run.extra.hn = { calls: 0, used_today: usedToday, day_cap: HN_BF_DAY_CAP, note: "daily cap reached; resumes next UTC day" };
    run.source({ source: "hn.algolia", status: "skipped", rows: 0, note: `hn_bf daily cap ${HN_BF_DAY_CAP} reached (${usedToday} used)` });
    return;
  }
  try {
    await hnBfBody(run, t0, maxCalls, (n) => stSet(run, "lib.bf.hn.day", { day: today, calls: usedToday + n }));
  } finally {
    run.extra.hn_day = { day: today, used_before: usedToday, day_cap: HN_BF_DAY_CAP };
  }
}
async function hnBfBody(run: Run, t0: number, maxCalls: number, saveCalls: (n: number) => Promise<void>) {
  const state = await st<Record<string, { done_from?: number; complete?: boolean }>>("lib.bf.hn", {});
  let calls = 0, rows = 0;
  const report: Record<string, unknown> = {};
  // pass 1: term counts of every window (what the controls need), pass 2: '__total__' denominators
  for (const w of HN_WINDOWS) {
    if (calls >= maxCalls || run.outOfTime(6000)) { run.partial = true; break; }
    const a = dayTs(w.from), b0 = dayTs(w.to) + DAY_S;
    const s = state[w.term] ?? {};
    if (s.complete) continue;
    const b = s.done_from && s.done_from > a ? s.done_from : b0;
    const r = await hnCount(run, w.term, a, b, maxCalls - calls);
    calls += r.calls;
    const out: ObsRow[] = [...r.counts].map(([d, n]) => ({ source: "hn.algolia", key: w.term, day: d, value: n, ...(r.est.has(d) ? { meta: { est: true } } : {}) }));
    rows += (await ingest(run, out)).rows;
    state[w.term] = { done_from: r.doneFrom, complete: r.complete };
    await stSet(run, "lib.bf.hn", state);
    await saveCalls(calls);
    report[w.term] = { calls: r.calls, days: r.counts.size, complete: r.complete };
    if (!r.complete) run.partial = true;
  }
  for (const w of HN_WINDOWS) {
    if (calls >= maxCalls || run.outOfTime(6000)) { run.partial = true; break; }
    const a = dayTs(w.from), b0 = dayTs(w.to) + DAY_S;
    const s = state[w.term] ?? {};
    if (!s.complete) continue; // term counts first
    void a;
    // '__total__' for the window (one call per day, newest first)
    const tk = `__total__:${w.term}`;
    const ts = state[tk] ?? {};
    if (!ts.complete) {
      let d = ts.done_from ? tsDay(ts.done_from - DAY_S) : w.to;
      const out: ObsRow[] = [];
      while (d >= w.from && calls < maxCalls && !run.outOfTime(5000)) {
        const r = await hnQuery(run, null, dayTs(d), dayTs(d) + DAY_S, 0);
        calls++;
        if (!r) break;
        out.push({ source: "hn.algolia", key: "__total__", day: d, value: r.nbHits, ...(r.exhaustive ? {} : { meta: { est: true } }) });
        d = addDays(d, -1);
      }
      rows += (await ingest(run, out)).rows;
      const doneFrom = out.length ? dayTs(out[out.length - 1].day!) : (ts.done_from ?? b0);
      state[tk] = { done_from: doneFrom, complete: d < w.from };
      await stSet(run, "lib.bf.hn", state);
      await saveCalls(calls);
      report[tk] = { days: out.length, complete: d < w.from };
      if (d >= w.from) run.partial = true;
    }
  }
  await saveCalls(calls);
  run.extra.hn = { calls, rows, windows: report };
  run.source({ source: "hn.algolia", status: run.partial ? "partial" : "ok", rows, ms: Date.now() - t0 });
}

serve("att-library", {
  fema: wrap(modeFema),
  usgs: wrap(modeUsgs),
  gdacs: wrap(modeGdacs),
  iem_bf: wrap(modeIemBf),
  npm_bf: wrap(modeNpmBf),
  hn_bf: wrap(modeHnBf),
  ping: wrap(async (r) => { r.extra.version = LIBRARY_VERSION; }),
});
