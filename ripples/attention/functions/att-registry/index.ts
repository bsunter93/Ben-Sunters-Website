// att-registry — topic registry for the Ripples v5 attention layer (W7 att-core).
// Modes:
//   resolve   {items:[{title?,qid?,lang?,origin?,status?,category?,in_panel?}]}  Wikidata -> QID, labels, aliases,
//             category, tickers/repos/packages/appids/domains; registers topics + keys via att_register_topics.
//   bootstrap register v4 hop-0/hop articles (public.signals) + current top trending (public.wiki_top, last 3 days,
//             top 50 en / top 20 other langs, SKIP-filtered) as 'active'. Resumable; returns remaining.
//   panel     build the frozen placebo panel (free tier: 300 topics) stratified by category x enwiki baseline decile
//             (median >= 100 views/day). Resumable state machine in att_state 'panel.build'.
// Wikidata: Action API wbgetentities (GREEN per DEMARCATION §7.1: maxlag=5, serial, honest UA, no retry after 429/503).
// Pageviews: Wikimedia AQS REST (no robots.txt on wikimedia.org), budget bucket 'wikimedia'.
import {
  addDays, budget, compact, configGet, db, ingest, politeFetch, type Run, serve, stateGet, stateSet,
  wikiApiJson, type ObsRow,
} from "./att.ts";

const FN = "att-registry";
const WD = "https://www.wikidata.org/w/api.php";
const AQS = "https://wikimedia.org/api/rest_v1/metrics/pageviews";
const US_EXCHANGES = new Set(["Q13677", "Q82059"]); // New York Stock Exchange, Nasdaq (FINRA covers US listings)

// ------------------------------------------------------------ categories (P31 / P106 -> stratum)
const P31_CAT: Record<string, string> = {
  Q11424: "film_tv", Q5398426: "film_tv", Q24856: "film_tv", Q202866: "film_tv", Q581714: "film_tv", Q1259759: "film_tv",
  Q21191270: "film_tv", Q3464665: "film_tv", Q15416: "film_tv", Q1366112: "film_tv", Q24862: "film_tv", Q506240: "film_tv",
  Q482994: "music", Q134556: "music", Q7366: "music", Q215380: "music", Q5741069: "music", Q105543609: "music",
  Q208569: "music", Q169930: "music", Q182832: "music", Q2088357: "music", Q9212979: "music",
  Q7889: "games", Q7058673: "games", Q865493: "games", Q21125433: "games",
  Q476028: "sports", Q12973014: "sports", Q27020041: "sports", Q16510064: "sports", Q18536594: "sports",
  Q13406554: "sports", Q500834: "sports", Q15991303: "sports", Q847017: "sports", Q1478437: "sports", Q46190676: "sports",
  Q4830453: "business", Q783794: "business", Q6881511: "business", Q891723: "business", Q167037: "business",
  Q431289: "business", Q2424752: "business", Q43229: "business", Q210167: "business", Q1331793: "business",
  Q7397: "tech", Q35127: "tech", Q9143: "tech", Q1668024: "tech", Q166142: "tech", Q11016: "tech",
  Q620615: "tech", Q17155032: "tech", Q341: "tech", Q218616: "tech", Q3966: "tech", Q1172284: "tech",
  Q188860: "tech", Q1330336: "tech", Q783866: "tech", Q9135: "tech",
  Q6256: "places", Q515: "places", Q1549591: "places", Q3624078: "places", Q35657: "places", Q5119: "places",
  Q486972: "places", Q1637706: "places", Q107390: "places", Q10864048: "places", Q8502: "places", Q23397: "places",
  Q4022: "places", Q1093829: "places", Q532: "places", Q41176: "places", Q570116: "places", Q33506: "places",
  Q40231: "politics", Q7278: "politics", Q858439: "politics", Q4164871: "politics", Q820655: "politics",
  Q49773: "politics", Q1076105: "politics", Q7188: "politics", Q484652: "politics", Q15238777: "politics",
  Q12136: "science_health", Q16521: "science_health", Q11173: "science_health", Q12140: "science_health",
  Q7187: "science_health", Q523: "science_health", Q3863: "science_health", Q18123741: "science_health",
  Q929833: "science_health", Q8054: "science_health", Q113145171: "science_health", Q2465832: "science_health",
  Q1190554: "events", Q1656682: "events", Q8065: "events", Q7944: "events", Q178561: "events", Q198: "events",
  Q645883: "events", Q8092: "events", Q2223653: "events", Q3839081: "events", Q141022: "events", Q132821: "events",
  Q7725634: "books_media", Q571: "books_media", Q47461344: "books_media", Q8274: "books_media", Q1107: "books_media",
  Q63952888: "books_media", Q1004: "books_media", Q41298: "books_media", Q1110794: "books_media", Q11032: "books_media",
  Q14406742: "books_media", Q277759: "books_media", Q21198342: "books_media", Q1667921: "books_media",
};
const P106_CAT: Record<string, string> = {
  Q2066131: "people_sport", Q937857: "people_sport", Q3665646: "people_sport", Q10833314: "people_sport",
  Q11513337: "people_sport", Q19204627: "people_sport", Q10871364: "people_sport", Q11774891: "people_sport",
  Q13381863: "people_sport", Q10843402: "people_sport", Q13141064: "people_sport", Q15117302: "people_sport",
  Q12299841: "people_sport", Q378622: "people_sport", Q11338576: "people_sport", Q10873124: "people_sport",
  Q33999: "people_ent", Q10800557: "people_ent", Q10798782: "people_ent", Q177220: "people_ent", Q639669: "people_ent",
  Q36834: "people_ent", Q488205: "people_ent", Q245068: "people_ent", Q2526255: "people_ent", Q3282637: "people_ent",
  Q2405480: "people_ent", Q130857: "people_ent", Q753110: "people_ent", Q947873: "people_ent", Q17125263: "people_ent",
  Q2259451: "people_ent", Q183945: "people_ent", Q855091: "people_ent", Q4610556: "people_ent", Q55960555: "people_ent",
  Q82955: "people_politics", Q193391: "people_politics", Q116: "people_politics", Q30461: "people_politics",
  Q372436: "people_politics", Q16533: "people_politics", Q40348: "people_politics", Q189290: "people_politics",
};
function categorize(p31: string[], p106: string[]): string {
  if (p31.includes("Q5")) {
    for (const o of p106) if (P106_CAT[o]) return P106_CAT[o];
    return "people_other";
  }
  for (const c of p31) if (P31_CAT[c]) return P31_CAT[c];
  return "other";
}

// ------------------------------------------------------------ Wikidata facts
export interface Facts {
  qid: string; label: string; label_en: string | null; title: string | null; title_en: string | null; lang: string;
  aliases: string[]; tickers: string[]; repos: string[]; npm: string[]; pypi: string[]; domains: string[];
  steam: string[]; anilist: string[]; apple: string[]; category: string; p31: string[];
}
const us = (t: string) => t.replaceAll(" ", "_");
const sp = (t: string) => t.replaceAll("_", " ");

function extract(e: any, lang: string): Facts {
  const lbl = (l: string): string | null => e.labels?.[l]?.value ?? null;
  const als = (l: string): string[] => (e.aliases?.[l] ?? []).map((a: any) => a.value).filter(Boolean);
  const claims = (p: string): any[] => (e.claims?.[p] ?? []).filter((c: any) => c.rank !== "deprecated");
  const vals = (p: string): any[] => claims(p).map((c) => c.mainsnak?.datavalue?.value).filter((v) => v != null);
  const ids = (p: string): string[] => vals(p).map((v) => v?.id).filter(Boolean);
  const strs = (p: string): string[] => vals(p).filter((v) => typeof v === "string");
  const p31 = ids("P31");
  const category = categorize(p31, ids("P106"));
  const tickers: string[] = [];
  for (const c of claims("P414")) {
    const ex = c.mainsnak?.datavalue?.value?.id;
    if (!US_EXCHANGES.has(ex) || c.qualifiers?.P582) continue; // listed on a US exchange, not delisted
    for (const q of c.qualifiers?.P249 ?? []) {
      const t = q?.datavalue?.value;
      if (typeof t === "string" && /^[A-Z.\-]{1,6}$/.test(t)) tickers.push(t);
    }
  }
  const repos = strs("P1324").map((u) => /github\.com\/([^/\s]+\/[^/#?\s]+)/i.exec(u)?.[1]?.replace(/\.git$/, ""))
    .filter((x): x is string => !!x);
  // official website -> registrable host: preferred rank first, then English-language (P407=Q1860), then shortest host
  const sites = (e.claims?.P856 ?? []).filter((c: any) => c.rank !== "deprecated" && typeof c.mainsnak?.datavalue?.value === "string")
    .map((c: any) => {
      let host = "";
      try { host = new URL(c.mainsnak.datavalue.value).hostname.replace(/^www\./, "").toLowerCase(); } catch { /* skip */ }
      const en = (c.qualifiers?.P407 ?? []).some((q: any) => q?.datavalue?.value?.id === "Q1860");
      return { host, score: (c.rank === "preferred" ? 0 : 10) + (en ? 0 : 5) + host.length / 100 };
    }).filter((x: any) => x.host).sort((a: any, b: any) => a.score - b.score);
  const domains = category.startsWith("people") ? [] : sites.slice(0, 1).map((x: any) => x.host);
  const title = e.sitelinks?.[`${lang}wiki`]?.title ?? null;
  const titleEn = e.sitelinks?.enwiki?.title ?? null;
  const labelEn = lbl("en");
  const aliases = [...als("en"), ...(lang !== "en" ? [lbl(lang), ...als(lang)] : [])].filter((a): a is string => !!a);
  return {
    qid: e.id, label: labelEn ?? lbl(lang) ?? sp(title ?? titleEn ?? e.id), label_en: labelEn,
    title: title ? us(title) : null, title_en: titleEn ? us(titleEn) : null, lang,
    aliases: [...new Set(aliases)].slice(0, 12), tickers: [...new Set(tickers)].slice(0, 3), repos: repos.slice(0, 3),
    npm: strs("P8262").slice(0, 3), pypi: strs("P5568").slice(0, 3), domains,
    steam: strs("P1733").slice(0, 2), anilist: strs("P8729").slice(0, 2), apple: strs("P3861").slice(0, 2),
    category, p31: p31.slice(0, 5),
  };
}

/** wbgetentities in batches of 20 (serial, maxlag=5). Returns Map key -> Facts|null where key = "lang:Title" or QID. */
async function fetchFacts(run: Run, lang: string, titles: string[], qids: string[]): Promise<Map<string, Facts | null>> {
  const out = new Map<string, Facts | null>();
  const jobs: Array<{ kind: "titles" | "ids"; list: string[] }> = [];
  for (let i = 0; i < titles.length; i += 20) jobs.push({ kind: "titles", list: titles.slice(i, i + 20) });
  for (let i = 0; i < qids.length; i += 20) jobs.push({ kind: "ids", list: qids.slice(i, i + 20) });
  const b = budget(run, "wikidata", Math.max(1, Math.min(10, jobs.length)));
  for (const j of jobs) {
    if (run.outOfTime(8000) || !(await b.take())) { run.partial = true; break; }
    const p = new URLSearchParams({
      action: "wbgetentities", format: "json", formatversion: "2", maxlag: "5",
      props: "labels|aliases|claims|sitelinks", languages: lang === "en" ? "en" : `en|${lang}`,
      sitefilter: lang === "en" ? "enwiki" : `enwiki|${lang}wiki`,
    });
    if (j.kind === "titles") { p.set("sites", `${lang}wiki`); p.set("titles", j.list.map(sp).join("|")); }
    else p.set("ids", j.list.join("|"));
    const res = await wikiApiJson(run, `${WD}?${p}`);
    if (!res) break;
    const seen = new Set<string>();
    for (const e of Object.values(res.entities ?? {}) as any[]) {
      if (e.missing !== undefined) continue;
      const f = extract(e, lang);
      out.set(f.qid, f);
      if (f.title) { out.set(`${lang}:${f.title}`, f); seen.add(f.title); }
    }
    if (j.kind === "titles") for (const t of j.list) if (!seen.has(us(t)) && !out.has(`${lang}:${us(t)}`)) out.set(`${lang}:${us(t)}`, null);
  }
  return out;
}

interface Item { title?: string; qid?: string; lang?: string; origin?: string; status?: string; category?: string; in_panel?: boolean; meta?: Record<string, unknown> }

async function registerItems(run: Run, items: Item[]): Promise<{ registered: number; missing: number; done: number }> {
  const byLang = new Map<string, Item[]>();
  for (const it of items) {
    const lang = it.lang || "en";
    if (!byLang.has(lang)) byLang.set(lang, []);
    byLang.get(lang)!.push(it);
  }
  let registered = 0, missing = 0, done = 0;
  for (const [lang, its] of byLang) {
    if (run.outOfTime(8000)) { run.partial = true; break; }
    const titles = its.filter((i) => !i.qid && i.title).map((i) => us(i.title!));
    const qids = its.filter((i) => i.qid).map((i) => i.qid!);
    const facts = await fetchFacts(run, lang, titles, qids);
    const reg: any[] = [];
    for (const it of its) {
      const key = it.qid ?? `${lang}:${us(it.title ?? "")}`;
      if (!facts.has(key)) continue; // not fetched (budget/time): leave for next run
      const f = facts.get(key);
      done++;
      const origin = it.origin ?? "manual";
      if (f) {
        reg.push({
          qid: f.qid, label: f.label, origin, category: it.category ?? f.category, facts: f, status: it.status ?? null,
          lang, title: f.title ?? f.title_en ?? us(f.label), in_panel: it.in_panel ?? false,
          meta: { resolved: "wikidata", p31: f.p31, title_en: f.title_en, ...(it.meta ?? {}) },
        });
      } else {
        if (!it.title) continue;
        missing++;
        reg.push({
          qid: null, label: sp(it.title ?? ""), origin, category: it.category ?? null, facts: {}, status: it.status ?? null,
          lang, title: us(it.title ?? ""), in_panel: it.in_panel ?? false, meta: { resolved: "miss", ...(it.meta ?? {}) },
        });
      }
    }
    for (let i = 0; i < reg.length; i += 50) {
      if (run.dryRun) { registered += reg.slice(i, i + 50).length; continue; }
      const { data, error } = await db.rpc("att_register_topics", { p_items: reg.slice(i, i + 50) });
      if (error) { run.errors.push(`att_register_topics: ${error.message}`); continue; }
      registered += (data as any)?.registered ?? 0;
      for (const e of ((data as any)?.errors ?? []).slice(0, 5)) run.errors.push(`register: ${e.error}`);
    }
  }
  return { registered, missing, done };
}

// ------------------------------------------------------------ modes
async function modeResolve(run: Run) {
  const items: Item[] = Array.isArray(run.body?.items) ? run.body.items : [];
  const t0 = Date.now();
  const r = await registerItems(run, items.slice(0, 400));
  run.source({ source: "wikidata", status: run.partial ? "partial" : "ok", keys: items.length, rows: r.registered, ms: Date.now() - t0 });
  run.extra.registered = r.registered;
  run.extra.missing = r.missing;
  if (r.done < items.length) run.partial = true;
}

async function modeBootstrap(run: Run) {
  const { data, error } = await db.rpc("att_bootstrap_candidates", { p_what: "active", p_limit: 2000 });
  if (error) throw new Error(error.message);
  const cands = (data ?? []) as Array<{ lang: string; title: string; origin: string; rnk: number }>;
  const max = Number(run.params.max ?? 400);
  const t0 = Date.now();
  const r = await registerItems(run, cands.slice(0, max).map((c) => ({
    title: c.title, lang: c.lang, origin: c.origin === "cascade" ? "cascade" : "trend", status: "active",
    meta: { boot: c.origin, boot_rank: c.rnk },
  })));
  run.source({ source: "wikidata", status: run.partial ? "partial" : "ok", keys: cands.length, rows: r.registered, ms: Date.now() - t0 });
  run.extra.candidates = cands.length;
  run.extra.registered = r.registered;
  run.extra.missing = r.missing;
  run.extra.remaining = Math.max(0, cands.length - r.done);
  if (cands.length - r.done > 0) run.partial = true;
}

// ---- panel
interface PanelState {
  phase: "pool" | "fetch" | "resolve" | "select" | "done"; seed: string; as_of: string; size: number;
  pool: string[]; idx: number; med: Record<string, number>; sig: Record<string, number>;
  facts: Record<string, Facts | null>; summary?: Record<string, unknown>;
}
const fnv = (s: string) => { let h = 0x811c9dc5; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; } return h; };
const median = (xs: number[]) => { if (!xs.length) return 0; const s = [...xs].sort((a, b) => a - b); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };

async function panelPool(run: Run, st: PanelState) {
  const wm = budget(run, "wikimedia", 12);
  const titles = new Set<string>();
  for (let k = 0; k < 12; k++) {
    if (!(await wm.take())) return;
    const d = addDays(st.as_of, -(20 + 30 * k));
    const [y, m, dd] = d.split("-");
    const res = await politeFetch(run, `${AQS}/top/en.wikipedia/all-access/${y}/${m}/${dd}`, { source: "wiki.pv", aqsRetry: true });
    if (!res) return;
    if (!res.ok) { await res.body?.cancel(); continue; }
    const j = await res.json();
    for (const a of j.items?.[0]?.articles ?? []) titles.add(String(a.article));
  }
  const { data, error } = await db.rpc("att_bootstrap_candidates", { p_what: "panel", p_limit: 20000 });
  if (error) throw new Error(error.message);
  for (const c of (data ?? []) as Array<{ title: string; origin: string; rnk: number | null }>) {
    titles.add(c.title);
    if (c.origin === "signal" && c.rnk != null) st.sig[c.title] = c.rnk;
  }
  const { data: kept, error: e2 } = await db.rpc("att_filter_titles", { p_titles: [...titles] });
  if (e2) throw new Error(e2.message);
  const pool = ((kept ?? []) as string[]).sort((a, b) => fnv(st.seed + a) - fnv(st.seed + b));
  const nFetch = Math.ceil(st.size * 1.6);
  st.pool = pool.slice(0, nFetch);
  st.summary = { pool_total: pool.length, fetch_n: st.pool.length };
  st.phase = "fetch";
  st.idx = 0;
}

async function panelFetch(run: Run, st: PanelState) {
  const wm = budget(run, "wikimedia", 25);
  const end = st.as_of;
  const start = addDays(end, -420);
  const baseFrom = addDays(end, -111), baseTo = addDays(end, -21);
  let rows: ObsRow[] = [];
  while (st.idx < st.pool.length) {
    if (run.outOfTime(12000)) { run.partial = true; break; }
    const t = st.pool[st.idx];
    if (st.sig[t] != null) { st.med[t] = st.sig[t]; st.idx++; continue; }
    if (!(await wm.take())) break;
    const url = `${AQS}/per-article/en.wikipedia/all-access/user/${encodeURIComponent(t)}/daily/${compact(start)}00/${compact(end)}00`;
    const res = await politeFetch(run, url, { source: "wiki.pv", aqsRetry: true });
    if (!res) break;
    if (!res.ok) { await res.body?.cancel(); st.med[t] = 0; st.idx++; continue; }
    const j = await res.json();
    const byDay = new Map<string, number>();
    for (const it of j.items ?? []) {
      const ts = String(it.timestamp);
      byDay.set(`${ts.slice(0, 4)}-${ts.slice(4, 6)}-${ts.slice(6, 8)}`, Number(it.views) || 0);
    }
    const base: number[] = [];
    for (let d = baseFrom; d <= baseTo; d = addDays(d, 1)) base.push(byDay.get(d) ?? 0);
    const m = median(base);
    st.med[t] = m;
    if (m >= 100) for (const [day, v] of byDay) rows.push({ source: "wiki.pv", geo: "en.wikipedia", key: t, day, value: v });
    st.idx++;
    if (rows.length >= 6000) { await ingest(run, rows); rows = []; await stateSet("panel.build", st); }
  }
  if (rows.length) await ingest(run, rows);
  if (st.idx >= st.pool.length) st.phase = "resolve";
}

async function panelResolve(run: Run, st: PanelState) {
  const need = st.pool.filter((t) => (st.med[t] ?? 0) >= 100 && !(t in st.facts));
  for (let i = 0; i < need.length; i += 60) {
    if (run.outOfTime(10000)) { run.partial = true; return; }
    const chunk = need.slice(i, i + 60);
    const f = await fetchFacts(run, "en", chunk, []);
    let got = 0;
    for (const t of chunk) if (f.has(`en:${t}`)) { st.facts[t] = f.get(`en:${t}`) ?? null; got++; }
    if (got < chunk.length) { run.partial = true; return; }
  }
  st.phase = "select";
}

async function panelSelect(run: Run, st: PanelState) {
  const elig = st.pool.filter((t) => (st.med[t] ?? 0) >= 100 && st.facts[t]);
  const byQid = new Map<string, string>();
  for (const t of elig) { const q = st.facts[t]!.qid; if (!byQid.has(q)) byQid.set(q, t); }
  const uniq = [...byQid.values()];
  const sorted = [...uniq].sort((a, b) => st.med[a] - st.med[b]);
  const n = sorted.length;
  const cuts = Array.from({ length: 9 }, (_, i) => st.med[sorted[Math.floor(((i + 1) * n) / 10)]] ?? Infinity);
  const decile = (t: string) => { let d = 0; while (d < 9 && st.med[t] >= cuts[d]) d++; return d + 1; };
  const quota = Math.floor(st.size / 10);
  const chosen: string[] = [];
  const leftovers: string[] = [];
  for (let d = 1; d <= 10; d++) {
    const inD = uniq.filter((t) => decile(t) === d).sort((a, b) => fnv(st.seed + a) - fnv(st.seed + b));
    const byCat = new Map<string, string[]>();
    for (const t of inD) { const c = st.facts[t]!.category; if (!byCat.has(c)) byCat.set(c, []); byCat.get(c)!.push(t); }
    const cats = [...byCat.keys()].sort((a, b) => fnv(st.seed + a) - fnv(st.seed + b));
    const pick: string[] = [];
    while (pick.length < quota && cats.some((c) => byCat.get(c)!.length)) {
      for (const c of cats) { const l = byCat.get(c)!; if (l.length && pick.length < quota) pick.push(l.shift()!); }
    }
    chosen.push(...pick);
    for (const c of cats) leftovers.push(...byCat.get(c)!);
  }
  leftovers.sort((a, b) => fnv(st.seed + a) - fnv(st.seed + b));
  while (chosen.length < st.size && leftovers.length) chosen.push(leftovers.shift()!);
  const items = chosen.map((t) => {
    const f = st.facts[t]!;
    const d = decile(t);
    return {
      qid: f.qid, label: f.label, origin: "panel", category: f.category, facts: f, status: "panel", lang: "en",
      title: f.title ?? t, in_panel: true,
      meta: { resolved: "wikidata", p31: f.p31, title_en: f.title_en, median_views: Math.round(st.med[t]), decile: d,
              stratum: `${f.category}|d${d}`, panel: st.seed },
    };
  });
  let registered = 0;
  for (let i = 0; i < items.length; i += 50) {
    const { data, error } = await db.rpc("att_register_topics", { p_items: items.slice(i, i + 50) });
    if (error) { run.errors.push(`att_register_topics: ${error.message}`); continue; }
    registered += (data as any)?.registered ?? 0;
  }
  const { data: cleaned } = await db.rpc("att_panel_cleanup");
  const catCounts: Record<string, number> = {};
  for (const it of items) catCounts[it.category] = (catCounts[it.category] ?? 0) + 1;
  st.summary = { ...(st.summary ?? {}), eligible: n, chosen: chosen.length, registered, decile_cuts: cuts,
                 categories: catCounts, orphan_series_deleted: cleaned, frozen_at: new Date().toISOString() };
  st.phase = "done";
  // drop the bulky working set; keep the summary
  st.pool = []; st.facts = {}; st.med = {}; st.sig = {};
}

async function modePanel(run: Run) {
  let st = (await stateGet("panel.build")) as PanelState | null;
  if (!st || run.params.rebuild === true) {
    const size = Number(await configGet("panel_size") ?? 300);
    st = { phase: "pool", seed: String(run.params.seed ?? "panel-2026Q4"), as_of: run.asOf, size, pool: [], idx: 0,
           med: {}, sig: {}, facts: {} };
  }
  if (st.phase === "done") { run.extra.panel = { phase: "done", summary: st.summary, note: "frozen; pass params.rebuild=true to rebuild" }; return; }
  try {
    if (st.phase === "pool") await panelPool(run, st);
    if (st.phase === "fetch") await panelFetch(run, st);
    if (st.phase === "resolve") await panelResolve(run, st);
    if (st.phase === "select" && !run.outOfTime(20000)) await panelSelect(run, st);
  } finally {
    await stateSet("panel.build", st);
  }
  if ((st.phase as string) !== "done") run.partial = true;
  run.extra.panel = { phase: st.phase, idx: st.idx, pool: st.pool.length, summary: st.summary };
}

serve(FN, {
  resolve: modeResolve,
  bootstrap: modeBootstrap,
  panel: modePanel,
  ping: async (run) => { run.extra.pong = true; },
});
