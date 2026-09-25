// att-wikidata — Ripple Map v6 (WS-A): Wikidata claims for the typed mechanism graph (ENGINE_SPEC §2.1 WD / MAP edges).
// Fetches whitelisted claims of topic QIDs (+ U.S. state seeds and depth-1 neighbours) into ripples.att_wd_claims; the
// graph builder (att_build_graph) turns them into WD edges and identifier MAP edges.
//
// Modes (body.mode):
//   claims   next QIDs from public.att_wd_queue (geography seeds -> topics never fetched / older than 90 days ->
//            depth-1 neighbours), fetched with the documented Action API wbgetentities (<= 50 ids per request,
//            props labels|claims|sitelinks, en only, maxlag=5, serial >= 1.1 s; att.ts adds Api-User-Agent and applies
//            the Wikimedia contact gate: while the UA contact page is unreachable no Wikimedia request is made).
//            Claims kept: QID values of 'wd' / 'map' / 'fact' properties (att_wd_props), strings for identifiers,
//            dates for P577/P585/P580/P571 (day precision or better only), P414 with its P249 ticker qualifier.
//            Deprecated-rank statements are dropped. Labels: English label + enwiki title only (no descriptions).
//   ping     no requests.
// Special:EntityData is not used: Wikimedia robots.txt disallows /wiki/Special:, the Action API is the documented route.
import { db, type Run, serve, wikiApiJson } from "./att.ts";
import { wrap } from "./wsa.ts";

export const WIKIDATA_VERSION = "2026-09-25.w1";

// must match ripples.att_wd_props (18_att_mech_graph.sql)
const PROPS_WD = ["P176","P452","P17","P131","P127","P1056","P361","P527","P178","P170","P272","P449","P1830","P355","P749",
  "P2283","P138","P1344","P710","P1891","P3320","P8047"];
const PROPS_STR = ["P249","P1324","P856","P1733","P8729","P300"];
const PROPS_TIME = ["P577","P585","P580","P571"];
const PROPS_FACT_Q = ["P31"];
const MAX_VALUES = 50;

function snakValue(s: any): unknown {
  const dv = s?.datavalue;
  if (!dv || s?.snaktype !== "value") return null;
  if (dv.type === "wikibase-entityid") {
    const id = dv.value?.id ?? (dv.value?.["numeric-id"] ? `Q${dv.value["numeric-id"]}` : null);
    return typeof id === "string" && /^Q\d+$/.test(id) ? id : null;
  }
  if (dv.type === "string") return typeof dv.value === "string" ? dv.value.slice(0, 300) : null;
  if (dv.type === "time") {
    const t = String(dv.value?.time ?? ""), p = Number(dv.value?.precision ?? 0);
    const m = /^([+-])(\d{4,})-(\d{2})-(\d{2})T/.exec(t);
    if (!m || m[1] !== "+" || p < 11) return null; // day precision (11) or finer only
    return `${m[2].slice(-4)}-${m[3]}-${m[4]}`;
  }
  return null;
}
function extract(ent: any): Record<string, unknown[]> {
  const out: Record<string, unknown[]> = {};
  const claims = ent?.claims ?? {};
  const add = (p: string, v: unknown) => {
    if (v === null || v === undefined) return;
    const a = (out[p] ??= []);
    if (a.length < MAX_VALUES && !a.some((x) => JSON.stringify(x) === JSON.stringify(v))) a.push(v);
  };
  for (const p of [...PROPS_WD, ...PROPS_FACT_Q, ...PROPS_STR, ...PROPS_TIME]) {
    for (const c of Array.isArray(claims[p]) ? claims[p] : []) {
      if (c?.rank === "deprecated") continue;
      add(p, snakValue(c?.mainsnak));
    }
  }
  // P414 stock exchange with its P249 ticker qualifier(s)
  for (const c of Array.isArray(claims.P414) ? claims.P414 : []) {
    if (c?.rank === "deprecated") continue;
    const v = snakValue(c?.mainsnak);
    const qs = Array.isArray(c?.qualifiers?.P249) ? c.qualifiers.P249 : [];
    for (const q of qs) { const t = snakValue(q); if (typeof v === "string" && typeof t === "string") add("P414", { v, t: t.slice(0, 12) }); }
    if (!qs.length && typeof v === "string") add("P414", { v });
  }
  return out;
}

async function modeClaims(run: Run) {
  const t0 = Date.now();
  const limit = Math.max(1, Math.min(250, Number(run.params.limit ?? 150)));
  const { data: q, error } = await db.rpc("att_wd_queue", { p_limit: limit });
  if (error) { run.errors.push(`att_wd_queue: ${error.message}`); return; }
  const queue = (Array.isArray(q) ? q : []) as Array<{ qid: string; depth: number }>;
  const depthOf = new Map(queue.map((x) => [x.qid, Number(x.depth ?? 0)]));
  let fetched = 0, stored = 0, calls = 0;
  const status: Record<string, number> = {};
  for (let i = 0; i < queue.length; i += 50) {
    if (run.outOfTime(8000) || run.skipped.some((s) => s.host === "www.wikidata.org")) { run.partial = true; break; }
    const ids = queue.slice(i, i + 50).map((x) => x.qid).filter((x) => /^Q\d+$/.test(x));
    if (!ids.length) continue;
    const u = new URL("https://www.wikidata.org/w/api.php");
    for (const [k, v] of Object.entries({ action: "wbgetentities", ids: ids.join("|"), props: "labels|claims|sitelinks",
      languages: "en", sitefilter: "enwiki", format: "json", formatversion: "2" })) u.searchParams.set(k, v);
    const j = await wikiApiJson(run, u.toString(), "wikidata.entity");
    calls++;
    if (!j) { run.partial = true; break; }
    const ents: Record<string, any> = j.entities ?? {};
    const rows: Record<string, unknown>[] = [];
    for (const id of ids) {
      let ent = ents[id];
      let redirectTo: string | null = null;
      if (!ent) {
        ent = Object.values(ents).find((e: any) => e?.redirects?.from === id);
        if (ent) redirectTo = String(ent.id ?? "");
      } else if (ent?.redirects?.to) redirectTo = String(ent.redirects.to);
      const depth = depthOf.get(id) ?? 0;
      if (!ent || ent.missing !== undefined) { rows.push({ qid: id, status: "missing", depth }); status.missing = (status.missing ?? 0) + 1; continue; }
      const st = redirectTo && redirectTo !== id ? "redirect" : "ok";
      rows.push({ qid: id, status: st, redirect_to: st === "redirect" ? redirectTo : null, depth,
        label_en: ent?.labels?.en?.value ?? null, enwiki: ent?.sitelinks?.enwiki?.title ?? null, claims: extract(ent) });
      status[st] = (status[st] ?? 0) + 1;
      fetched++;
    }
    if (!run.dryRun && rows.length) {
      const { data, error: e2 } = await db.rpc("att_wd_claims_upsert", { p_rows: rows });
      if (e2) run.errors.push(`att_wd_claims_upsert: ${e2.message}`); else stored += Number(data ?? 0);
    }
  }
  if (queue.length && fetched < queue.length) run.partial = true;
  run.extra.wikidata = { queue: queue.length, calls, fetched, stored, status };
  run.source({ source: "wikidata.entity", status: run.partial ? "partial" : "ok", keys: fetched, rows: stored, ms: Date.now() - t0,
    note: "wbgetentities, <= 50 ids per call" });
}

serve("att-wikidata", {
  claims: wrap(modeClaims),
  ping: wrap(async (r) => { r.extra.version = WIKIDATA_VERSION; }),
});
