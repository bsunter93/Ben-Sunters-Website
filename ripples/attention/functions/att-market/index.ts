// att-market — money and institutional attention collector for the Ripples v5 attention layer (W7).
// Modes (§3.3 / §7.3):
//   finra        FINRA Reg SHO daily short-sale volume for the previous US trading day, read from the FINRA Query API
//                (api.finra.org regShoDaily, all TRF facilities consolidated = the CNMSshvol file). cdn.finra.org is not
//                used: its robots.txt answers 403, which DEMARCATION Q3 treats as disallow (the host is killed); Q3 then
//                says to use the operator's documented channel, graded separately as source finra.api.
//                The consolidated day is mirrored gzipped to the PRIVATE bucket att-raw/finra/YYYYMMDD.txt.gz, registry
//                and panel tickers are ingested (finra.shvol: value = total volume, aux = short share) with a '__total__'
//                normaliser, a rolling per-ticker baseline (att-raw/finra/_ring.bin, last 90 trading days) is updated,
//                and the all-ticker abnormal-volume top 50 (ratio >= 3 and robust z >= 4 vs each ticker's own
//                t-77..t-15 trading-day baseline) are written as discovery candidates.
//   polymarket   Gamma /markets by volume24hr (non-sports, non-esports): per market volume24hr (aux liquidity), per event
//                volume24hr (aux openInterest), per registry topic (title term match) summed volume, a '__total__' and
//                CLOB daily price history for mapped markets; discovery candidates (>= 3x trailing 7-day mean, or new
//                event over $250k).
//   kalshi       trade-api v2 /events with nested markets (category != Sports): per event volume_24h (aux open
//                interest), per busy market, per topic, '__total__' (the *_fp fields are strings and are parsed).
//   usaspending  USAspending spending_over_time by keyword, 3-month windows (monthly obligations), rotating keys
//                (each key every 7 days).
//   edgar        SEC EDGAR full-text search counts per month. Implemented but DISABLED (sec.efts.enabled=false and the
//                att.ts RED list blocks sec.gov): SEC requires an owner contact email in the User-Agent.
//   backfill     att_jobs: {params:{source:'finra.api', files:true}} mirrors up to 400 trading days (newest first);
//                {params:{source:'finra.shvol'}, keys} backfills tickers with one API query per 3 tickers;
//                {params:{source:'usasp.spend'}, keys} walks 3-month windows back 24 months per key.
//   ping         no outbound calls.
// Stored: counts, volumes, prices and indices only. Market titles are used transiently for topic matching and as
// discovery-candidate labels (att_trend_candidates), never as series data. Nothing raw is published.
import {
  addDays, configGet, db, errMsg, hostLease, ingest, ingestCandidates, type ObsRow, politeFetch, type Run, serve,
  sourceInfo, stateGet, stateSet, watchlist, type WatchKey, ymd,
} from "./att.ts";

const FN = "att-market";
const MARKET_VERSION = "2026-09-25.m2";
const BUCKET = "att-raw";
const FINRA_URL = "https://api.finra.org/data/group/otcMarket/name/regShoDaily";
const FINRA_FIELDS = ["tradeReportDate", "securitiesInformationProcessorSymbolIdentifier", "shortParQuantity",
  "shortExemptParQuantity", "totalParQuantity", "reportingFacilityCode", "marketCode"];
const GAMMA = "https://gamma-api.polymarket.com";
const CLOB = "https://clob.polymarket.com";
const KALSHI = "https://api.elections.kalshi.com/trade-api/v2";
const USASP_URL = "https://api.usaspending.gov/api/v2/search/spending_over_time/";
const EFTS_URL = "https://efts.sec.gov/LATEST/search-index";

// ------------------------------------------------------------ config
const DEFAULTS = {
  poly_page: 100, poly_max_pages: 15, poly_min_vol24: 1000, poly_max_markets: 300, poly_max_events: 150,
  poly_clob_max: 60, poly_new_usd: 250000,
  kalshi_page: 200, kalshi_max_pages: 100, kalshi_max_events: 200, kalshi_max_markets: 100,
  kalshi_min_mkt_vol24: 1000, kalshi_new_contracts: 250000,
  cand_ratio: 3, cand_top: 30,
  finra_page: 5000, finra_days: 400, finra_ring_days: 90, finra_liq_floor: 50000,
  finra_cand_ratio: 3, finra_cand_z: 4, finra_cand_top: 50, finra_bf_days_per_run: 3,
  usasp_rotation_days: 7, usasp_max_keys: 12, usasp_backfill_months: 24,
  edgar_rotation_days: 7, edgar_max_keys: 40,
};
type Cfg = typeof DEFAULTS;
async function mcfg(run: Run): Promise<Cfg> {
  const c = await configGet("market").catch(() => null) as Partial<Cfg> | null;
  const out = { ...DEFAULTS, ...(c ?? {}) } as Cfg;
  for (const k of Object.keys(DEFAULTS) as (keyof Cfg)[]) {
    if (run.params?.[k] !== undefined && Number.isFinite(Number(run.params[k]))) (out as any)[k] = Number(run.params[k]);
  }
  return out;
}

// ------------------------------------------------------------ small helpers
const pad = (n: number) => String(n).padStart(2, "0");
const num = (x: unknown): number => {
  const v = typeof x === "number" ? x : typeof x === "string" ? Number(x) : NaN;
  return Number.isFinite(v) ? v : 0;
};
const r2 = (x: number) => Math.round(x * 100) / 100;
const clamp01 = (x: number) => Math.max(0, Math.min(1, x));
/** Day a rolling-24h snapshot belongs to: the UTC date of (now - 12 h), i.e. where most of the window lies. */
const snapDay = (run: Run) => (typeof run.body?.as_of === "string" ? run.body.as_of : ymd(new Date(Date.now() - 12 * 3600e3)));
const today = () => ymd(new Date());
function median(a: number[]): number {
  if (!a.length) return NaN;
  const s = [...a].sort((x, y) => x - y);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
async function rpc(run: Run, fn: string, args: Record<string, unknown>): Promise<any> {
  const { data, error } = await db.rpc(fn, args);
  if (error) { run.errors.push(`${fn}: ${error.message}`); return null; }
  return data;
}
function failNote(run: Run, host: string): string {
  const s = run.skipped.filter((x) => x.host === host).map((x) => x.reason).join(",");
  if (/robots/.test(s)) return "robots_disallow";
  if (/host_killed/.test(s)) return s.match(/host_killed_\w+/)?.[0] ?? "host_killed";
  if (/budget|per_run_cap/.test(s)) return "budget_exhausted";
  if (/disabled/.test(s)) return "disabled";
  if (/busy/.test(s)) return "host_busy";
  return s || "http_error";
}
/**
 * Finish merged backfill jobs ourselves (per key) so a partial run is picked up again soon: att.ts would requeue every
 * job with a 1 h delay. Jobs whose payload keys are all in doneKeys are marked done; the rest are requeued after delayS,
 * or at 00:10 UTC tomorrow when the host is closed for the day (daily budget spent, host killed).
 */
async function settleJobs(run: Run, doneKeys: Set<string> | "all", delayS = 90, host?: string) {
  const ids = run.jobIds();
  if (!ids.length || run.dryRun) return;
  if (host && run.skipped.some((x) => x.host === host && /daily_budget_spent|host_killed/.test(x.reason))) {
    const t = new Date();
    delayS = Math.max(delayS, Math.ceil((Date.UTC(t.getUTCFullYear(), t.getUTCMonth(), t.getUTCDate() + 1, 0, 10) - t.getTime()) / 1000));
  }
  let done: number[] = [];
  let rest: number[] = [];
  if (doneKeys === "all") done = ids;
  else {
    const { data } = await db.rpc("att_market_jobs", { p_ids: ids });
    const jobs = (data ?? []) as Array<{ id: number; keys: string[] }>;
    for (const j of jobs) (j.keys.length && j.keys.every((k) => doneKeys.has(k)) ? done : rest).push(j.id);
    const seen = new Set(jobs.map((j) => j.id));
    for (const id of ids) if (!seen.has(id)) rest.push(id);
  }
  if (done.length) await db.rpc("att_jobs_done", { p_jobs: done, p_status: "done", p_error: null, p_not_before: null });
  if (rest.length) {
    await db.rpc("att_jobs_done", { p_jobs: rest, p_status: "requeue", p_error: run.errors.slice(0, 3).join("; ") || null,
      p_not_before: new Date(Date.now() + delayS * 1000).toISOString() });
  }
  run.extra.jobs = { done: done.length, requeued: rest.length };
  run.body.job_ids = []; // handled here; Run.finish must not requeue them again with its 1 h delay
  delete run.body.job_id;
}

// ------------------------------------------------------------ registry term matcher (market titles -> topics)
const normMem = new Map<string, string>();
function norm(s: string): string {
  const c = normMem.get(s);
  if (c !== undefined) return c;
  const v = s.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  if (normMem.size < 100_000) normMem.set(s, v);
  return v;
}
class Matcher {
  private byFirst = new Map<string, Array<[string, number]>>();
  patterns = 0;
  constructor(readonly topics: Array<{ topic_id: number; terms: string[] }>) {
    topics.forEach((t, i) => {
      const seen = new Set<string>();
      for (const raw of t.terms ?? []) {
        const p = norm(String(raw));
        if (p.length < 4 || /^[\d ]+$/.test(p) || seen.has(p)) continue;
        seen.add(p);
        const first = p.split(" ")[0];
        let arr = this.byFirst.get(first);
        if (!arr) { arr = []; this.byFirst.set(first, arr); }
        arr.push([" " + p + " ", i]);
        this.patterns++;
      }
    });
  }
  /** topic_ids whose term occurs as whole words in text */
  match(text: string): number[] {
    const t = norm(text);
    if (!t) return [];
    const padded = " " + t + " ";
    const out = new Set<number>();
    const seenTok = new Set<string>();
    for (const tok of t.split(" ")) {
      if (seenTok.has(tok)) continue;
      seenTok.add(tok);
      const c = this.byFirst.get(tok);
      if (!c) continue;
      for (const [p, i] of c) if (!out.has(i) && (p.length === tok.length + 2 || padded.includes(p))) out.add(i);
    }
    return [...out].map((i) => this.topics[i].topic_id);
  }
}
async function buildMatcher(run: Run): Promise<Matcher> {
  const data = await rpc(run, "att_topic_terms", { p_limit: 5000 });
  return new Matcher(((data ?? []) as Array<{ topic_id: number; terms: string[] }>).filter((t) => Array.isArray(t.terms)));
}

// ------------------------------------------------------------ discovery candidates for market events
interface EvSnap { key: string; title: string; vol: number; created?: string | null; topic_id?: number | null }
async function marketCandidates(run: Run, source: string, day: string, evs: EvSnap[], cfg: Cfg, geo: string, newFloor: number,
  newScale: number) {
  if (!evs.length) return 0;
  const stats = await rpc(run, "att_series_stats", {
    p_source: source, p_metric: "vol24h", p_keys: evs.map((e) => e.key), p_from: addDays(day, -7), p_to: addDays(day, -1),
  }) as Array<{ key: string; n: number; mean: number | null; first_day: string | null }> | null;
  const st = new Map((stats ?? []).map((s) => [s.key, s]));
  const cands: Array<Record<string, unknown>> = [];
  for (const e of evs) {
    if (!e.title || e.vol <= 0) continue;
    const s = st.get(e.key);
    const n = s?.n ?? 0;
    const mean = Number(s?.mean ?? 0);
    const firstDay = s?.first_day ?? null;
    const created = e.created ? String(e.created).slice(0, 10) : null;
    if (n >= 3 && mean > 0) {
      const ratio = e.vol / mean;
      if (ratio >= cfg.cand_ratio) {
        cands.push({ day, source, geo, label: e.title.slice(0, 200), value: r2(ratio), topic_id: e.topic_id ?? null,
          evidence: clamp01(Math.log(ratio) / Math.log(10)), meta: { ratio: r2(ratio), k: "event" } });
      }
    } else if ((!firstDay || firstDay >= addDays(day, -2)) && created && created >= addDays(day, -3) && e.vol >= newFloor) {
      cands.push({ day, source, geo, label: e.title.slice(0, 200), value: Math.round(e.vol), topic_id: e.topic_id ?? null,
        evidence: clamp01(Math.log(e.vol / newScale) / Math.log(10)), meta: { new: true, k: "event" } });
    }
  }
  cands.sort((a, b) => Number(b.evidence) - Number(a.evidence));
  const top = cands.slice(0, cfg.cand_top).map((c, i) => ({ ...c, rank: i + 1 }));
  if (top.length) await ingestCandidates(run, top);
  return top.length;
}

// ------------------------------------------------------------ topic aggregation shared by poly + kalshi
function topicRows(source: string, day: string, evs: Array<{ vol: number; oi: number; title: string }>, m: Matcher,
  withTopic: (i: number, tid: number) => void): ObsRow[] {
  const agg = new Map<number, { vol: number; oi: number; n: number }>();
  evs.forEach((e, i) => {
    for (const tid of m.match(e.title)) {
      withTopic(i, tid);
      const a = agg.get(tid) ?? { vol: 0, oi: 0, n: 0 };
      a.vol += e.vol; a.oi += e.oi; a.n++;
      agg.set(tid, a);
    }
  });
  return [...agg].map(([tid, a]) => ({ source, key: `topic:${tid}`, metric: "vol24h", day, value: r2(a.vol),
    aux: r2(a.oi), topic_id: tid, meta: { n_mkts: a.n } }));
}

// ============================================================ polymarket
const SPORTS_RE = new RegExp("\\b(" + [
  "nfl", "nba", "wnba", "mlb", "nhl", "mls", "ufc", "mma", "boxing", "fifa", "uefa", "premier league", "la liga",
  "serie a", "bundesliga", "ligue 1", "champions league", "europa league", "super bowl", "world series", "stanley cup",
  "grand prix", "formula 1", "f1", "nascar", "pga", "lpga", "atp", "wta", "wimbledon", "french open", "australian open",
  "us open", "ncaa", "march madness", "heisman", "olympics?", "cricket", "ipl", "t20", "rugby", "tennis", "golf",
  "dota", "dota 2", "cs2", "counter strike", "league of legends", "valorant", "esports", "lck", "lpl", "overwatch",
  "rocket league", "ballon d or", "epl", "nfl draft", "nba draft", "playoffs?", "touchdowns?", "goalscorer",
  "moneyline", "over under", "world cup", "euro 2028", "copa america", "cy young", "mvp",
].join("|") + ")\\b", "i");
function isSportsPoly(m: any): boolean {
  if (m?.sportsMarketType || m?.gameStartTime) return true;
  if (typeof m?.feeType === "string" && /sport/i.test(m.feeType)) return true;
  const ev = Array.isArray(m?.events) ? m.events[0] : null;
  if (ev && (ev.gameId || ev.eventMetadata?.league || ev.sport)) return true;
  const t = norm(`${m?.question ?? ""} ${ev?.title ?? ""} ${ev?.seriesSlug ?? ""}`);
  return SPORTS_RE.test(t) || /\b(vs|v)\b/.test(t) && /\b(game|match|map|set|series|win)\b/.test(t);
}
function firstToken(x: unknown): string | null {
  try {
    const a = typeof x === "string" ? JSON.parse(x) : x;
    return Array.isArray(a) && a.length ? String(a[0]) : null;
  } catch { return null; }
}

async function polymarket(run: Run) {
  const t0 = Date.now();
  const cfg = await mcfg(run);
  const day = snapDay(run);
  const src = await sourceInfo("poly.mkt");
  if (!src?.enabled) { run.source({ source: "poly.mkt", status: "disabled", note: src?.reason ?? null }); return; }
  const matcher = await buildMatcher(run);
  type Mk = { id: string; title: string; vol: number; liq: number; token: string | null; ev: string | null };
  type Ev = { id: string; title: string; vol: number; oi: number; created: string | null; sports: boolean };
  const markets: Mk[] = [];
  const events = new Map<string, Ev>();
  let pages = 0, seen = 0, sports = 0, totalVol = 0, fetchedOk = true;
  for (let page = 0; page < cfg.poly_max_pages; page++) {
    if (run.outOfTime(25_000)) { run.partial = true; break; }
    const url = `${GAMMA}/markets?active=true&closed=false&order=volume24hr&ascending=false&limit=${cfg.poly_page}&offset=${page * cfg.poly_page}`;
    const res = await politeFetch(run, url, { source: "poly.mkt", headers: { accept: "application/json" }, timeoutMs: 30_000 });
    if (!res) { fetchedOk = page > 0; break; }
    if (!res.ok) { run.errors.push(`gamma http ${res.status}`); await res.body?.cancel(); fetchedOk = page > 0; break; }
    let arr: any[];
    try { arr = await res.json(); } catch (e) { run.errors.push(`gamma json: ${errMsg(e)}`); break; }
    if (!Array.isArray(arr)) { run.errors.push("gamma: unexpected shape (not an array)"); break; }
    pages++;
    let minVol = Infinity;
    for (const m of arr) {
      seen++;
      const vol = num(m?.volume24hr);
      minVol = Math.min(minVol, vol);
      if (vol < cfg.poly_min_vol24 || !m?.id) continue;
      const ev0 = Array.isArray(m.events) ? m.events[0] : null;
      const sp = isSportsPoly(m);
      if (ev0?.id) {
        const e = events.get(String(ev0.id));
        if (e) e.sports = e.sports || sp;
        else {
          events.set(String(ev0.id), { id: String(ev0.id), title: String(ev0.title ?? m.question ?? ""), vol: num(ev0.volume24hr),
            oi: num(ev0.openInterest), created: ev0.createdAt ?? ev0.creationDate ?? ev0.startDate ?? null, sports: sp });
        }
      }
      if (sp) { sports++; continue; }
      totalVol += vol;
      markets.push({ id: String(m.id), title: String(m.question ?? ""), vol, liq: num(m.liquidityNum ?? m.liquidity),
        token: firstToken(m.clobTokenIds), ev: ev0?.id ? String(ev0.id) : null });
    }
    if (arr.length < cfg.poly_page || minVol < cfg.poly_min_vol24) break;
  }
  if (!pages) {
    run.source({ source: "poly.mkt", status: failNote(run, "gamma-api.polymarket.com"), ms: Date.now() - t0 });
    return;
  }
  const evList = [...events.values()].filter((e) => !e.sports && e.vol > 0).sort((a, b) => b.vol - a.vol);
  // a market in a sports event is sports even if the market itself looked neutral
  const sportsEv = new Set([...events.values()].filter((e) => e.sports).map((e) => e.id));
  const mk = markets.filter((m) => !m.ev || !sportsEv.has(m.ev)).sort((a, b) => b.vol - a.vol);
  const keepMk = mk.slice(0, cfg.poly_max_markets);
  const keepEv = evList.slice(0, cfg.poly_max_events);
  const rows: ObsRow[] = [];
  for (const m of keepMk) rows.push({ source: "poly.mkt", key: `m:${m.id}`, metric: "vol24h", day, value: r2(m.vol), aux: r2(m.liq) });
  // topics: matched on event titles (and on market titles of events not otherwise matched)
  const evTopic = new Map<number, number>();
  const tRows = topicRows("poly.mkt", day, keepEv.map((e) => ({ vol: e.vol, oi: e.oi, title: e.title })), matcher,
    (i, tid) => { if (!evTopic.has(i)) evTopic.set(i, tid); });
  keepEv.forEach((e, i) => rows.push({ source: "poly.mkt", key: `e:${e.id}`, metric: "vol24h", day, value: r2(e.vol),
    aux: r2(e.oi), topic_id: evTopic.get(i) ?? null }));
  rows.push(...tRows);
  rows.push({ source: "poly.mkt", key: "__total__", metric: "vol24h", day, value: r2(totalVol), aux: mk.length,
    meta: { coverage: seen, partial: !fetchedOk || run.partial } });
  const ing = await ingest(run, rows);

  // CLOB daily price history for markets of topic-mapped events (and markets whose own title maps)
  const mappedEv = new Map<string, number>();
  keepEv.forEach((e, i) => { const t = evTopic.get(i); if (t) mappedEv.set(e.id, t); });
  const clobList: Array<{ m: Mk; tid: number }> = [];
  for (const m of mk) {
    let tid = m.ev ? mappedEv.get(m.ev) : undefined;
    if (!tid) tid = matcher.match(m.title)[0];
    if (tid && m.token) clobList.push({ m, tid });
    if (clobList.length >= cfg.poly_clob_max) break;
  }
  let clobOk = 0, clobRows = 0;
  const priceRows: ObsRow[] = [];
  const minDay = addDays(day, -400);
  // full daily history once per market (new price series), afterwards only the last week
  const have = clobList.length ? await rpc(run, "att_series_stats", { p_source: "poly.mkt", p_metric: "p",
    p_keys: clobList.map(({ m }) => `m:${m.id}`), p_from: addDays(day, -7), p_to: day }) as Array<{ key: string; n: number }> | null : [];
  const known = new Set((have ?? []).filter((x) => x.n > 0).map((x) => x.key));
  for (const { m, tid } of clobList) {
    if (run.outOfTime(8000)) { run.partial = true; break; }
    const interval = known.has(`m:${m.id}`) ? "1w" : "max";
    const res = await politeFetch(run, `${CLOB}/prices-history?market=${encodeURIComponent(m.token!)}&interval=${interval}&fidelity=1440`,
      { source: "poly.mkt", headers: { accept: "application/json" }, timeoutMs: 15_000 });
    if (!res) break;
    if (!res.ok) { await res.body?.cancel(); continue; }
    const j = await res.json().catch(() => null);
    const hist = Array.isArray(j?.history) ? j.history : [];
    const byDay = new Map<string, number>();
    for (const h of hist) {
      const t = num(h?.t), p = Number(h?.p);
      if (!t || !Number.isFinite(p)) continue;
      const d = ymd(new Date(t * 1000));
      if (d >= minDay && d <= day) byDay.set(d, p); // last point of the day wins
    }
    for (const [d, p] of byDay) priceRows.push({ source: "poly.mkt", key: `m:${m.id}`, metric: "p", day: d, value: p, topic_id: tid });
    clobOk++;
    clobRows += byDay.size;
  }
  if (priceRows.length) await ingest(run, priceRows);

  const nCand = await marketCandidates(run, "poly.mkt", day,
    keepEv.map((e, i) => ({ key: `e:${e.id}`, title: e.title, vol: e.vol, created: e.created, topic_id: evTopic.get(i) ?? null })),
    cfg, "ALL", cfg.poly_new_usd, cfg.poly_new_usd / 10);
  run.extra.polymarket = { day, pages, seen, sports_skipped: sports, markets: keepMk.length, events: keepEv.length,
    topics: tRows.length, clob_markets: clobOk, price_rows: clobRows, candidates: nCand, matcher_terms: matcher.patterns };
  run.source({ source: "poly.mkt", status: fetchedOk ? "ok" : "partial", keys: keepMk.length + keepEv.length + tRows.length,
    rows: Number(ing?.rows ?? 0) + priceRows.length, ms: Date.now() - t0 });
}

// ============================================================ kalshi
async function kalshi(run: Run) {
  const t0 = Date.now();
  const cfg = await mcfg(run);
  const day = snapDay(run);
  const src = await sourceInfo("kalshi.mkt");
  if (!src?.enabled) { run.source({ source: "kalshi.mkt", status: "disabled", note: src?.reason ?? null }); return; }
  const matcher = await buildMatcher(run);
  type Ev = { ticker: string; title: string; vol: number; oi: number; n: number; created: string | null };
  const evs: Ev[] = [];
  const mkts: Array<{ ticker: string; vol: number; oi: number }> = [];
  let cursor = "", pages = 0, seen = 0, sports = 0, totalVol = 0, complete = false, fetchedOk = true;
  for (let p = 0; p < cfg.kalshi_max_pages; p++) {
    if (run.outOfTime(20_000)) { run.partial = true; break; }
    const url = `${KALSHI}/events?status=open&with_nested_markets=true&limit=${cfg.kalshi_page}` +
      (cursor ? `&cursor=${encodeURIComponent(cursor)}` : "");
    const res = await politeFetch(run, url, { source: "kalshi.mkt", headers: { accept: "application/json" }, timeoutMs: 30_000 });
    if (!res) { fetchedOk = pages > 0; run.partial = true; break; }
    if (!res.ok) { run.errors.push(`kalshi http ${res.status}`); await res.body?.cancel(); fetchedOk = pages > 0; break; }
    let j: any;
    try { j = await res.json(); } catch (e) { run.errors.push(`kalshi json: ${errMsg(e)}`); break; }
    pages++;
    const list = Array.isArray(j?.events) ? j.events : [];
    for (const e of list) {
      seen++;
      if (/sport/i.test(String(e?.category ?? ""))) { sports++; continue; }
      const ms = Array.isArray(e?.markets) ? e.markets : [];
      let vol = 0, oi = 0, created: string | null = null;
      for (const m of ms) {
        const v = num(m?.volume_24h_fp ?? m?.volume_24h);
        const o = num(m?.open_interest_fp ?? m?.open_interest);
        vol += v; oi += o;
        const ct = typeof m?.created_time === "string" ? m.created_time : null;
        if (ct && (!created || ct < created)) created = ct;
        if (v >= cfg.kalshi_min_mkt_vol24 && m?.ticker) mkts.push({ ticker: String(m.ticker), vol: v, oi: o });
      }
      totalVol += vol;
      if (vol <= 0 && oi < 1000) continue;
      evs.push({ ticker: String(e.event_ticker), title: [e.title, e.sub_title].filter(Boolean).join(" "), vol, oi, n: ms.length, created });
    }
    cursor = typeof j?.cursor === "string" ? j.cursor : "";
    if (!cursor || !list.length) { complete = true; break; }
  }
  if (!pages) { run.source({ source: "kalshi.mkt", status: failNote(run, "api.elections.kalshi.com"), ms: Date.now() - t0 }); return; }
  evs.sort((a, b) => b.vol - a.vol || b.oi - a.oi);
  mkts.sort((a, b) => b.vol - a.vol);
  const keepEv = evs.slice(0, cfg.kalshi_max_events);
  const keepMk = mkts.slice(0, cfg.kalshi_max_markets);
  const evTopic = new Map<number, number>();
  const tRows = topicRows("kalshi.mkt", day, keepEv.map((e) => ({ vol: e.vol, oi: e.oi, title: e.title })), matcher,
    (i, tid) => { if (!evTopic.has(i)) evTopic.set(i, tid); });
  const rows: ObsRow[] = [];
  keepEv.forEach((e, i) => rows.push({ source: "kalshi.mkt", key: `ev:${e.ticker}`, metric: "vol24h", day, value: r2(e.vol),
    aux: r2(e.oi), topic_id: evTopic.get(i) ?? null, meta: { n_mkts: e.n } }));
  for (const m of keepMk) rows.push({ source: "kalshi.mkt", key: `m:${m.ticker}`, metric: "vol24h", day, value: r2(m.vol), aux: r2(m.oi) });
  rows.push(...tRows);
  rows.push({ source: "kalshi.mkt", key: "__total__", metric: "vol24h", day, value: r2(totalVol), aux: evs.length,
    meta: { coverage: seen, partial: !complete } });
  const ing = await ingest(run, rows);
  const nCand = await marketCandidates(run, "kalshi.mkt", day,
    keepEv.map((e, i) => ({ key: `ev:${e.ticker}`, title: e.title, vol: e.vol, created: e.created, topic_id: evTopic.get(i) ?? null })),
    cfg, "US", cfg.kalshi_new_contracts, cfg.kalshi_new_contracts / 10);
  run.extra.kalshi = { day, pages, complete, seen, sports_skipped: sports, events: keepEv.length, markets: keepMk.length,
    topics: tRows.length, candidates: nCand, matcher_terms: matcher.patterns };
  run.source({ source: "kalshi.mkt", status: complete && fetchedOk ? "ok" : "partial", keys: rows.length,
    rows: Number(ing?.rows ?? 0), ms: Date.now() - t0 });
}

// ============================================================ FINRA (Query API regShoDaily)
// NYSE full-day closures (no Reg SHO file). Weekends are skipped separately. Unknown closures show up as an empty day.
const NYSE_HOLIDAYS = new Set([
  "2024-01-01", "2024-01-15", "2024-02-19", "2024-03-29", "2024-05-27", "2024-06-19", "2024-07-04", "2024-09-02",
  "2024-11-28", "2024-12-25",
  "2025-01-01", "2025-01-09", "2025-01-20", "2025-02-17", "2025-04-18", "2025-05-26", "2025-06-19", "2025-07-04",
  "2025-09-01", "2025-11-27", "2025-12-25",
  "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19", "2026-07-03", "2026-09-07",
  "2026-11-26", "2026-12-25",
  "2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31", "2027-06-18", "2027-07-05", "2027-09-06",
  "2027-11-25", "2027-12-24",
]);
function isTradingDay(d: string): boolean {
  const wd = new Date(d + "T00:00:00Z").getUTCDay();
  return wd !== 0 && wd !== 6 && !NYSE_HOLIDAYS.has(d);
}
function prevTradingDay(d: string): string { let x = d; while (!isTradingDay(x)) x = addDays(x, -1); return x; }
/** n trading days ending at end (inclusive), newest first */
function tradingDaysBack(end: string, n: number): string[] {
  const out: string[] = [];
  let x = prevTradingDay(end);
  while (out.length < n) { out.push(x); x = prevTradingDay(addDays(x, -1)); }
  return out;
}
/** Latest trading day whose file should be complete: FINRA publishes after the US close (~22:00-23:00 UTC). */
function latestPublished(): string {
  const now = new Date();
  const d = ymd(now);
  const cut = now.getUTCHours() >= 23 ? d : addDays(d, -1);
  return prevTradingDay(cut);
}

interface Agg { s: number; se: number; t: number; f: string }
type DayAgg = Map<string, Agg>;
interface FinraPage { rows: any[]; total: number }
async function finraPage(run: Run, body: Record<string, unknown>): Promise<FinraPage | null> {
  const res = await politeFetch(run, FINRA_URL, {
    source: "finra.api", method: "POST", timeoutMs: 45_000,
    headers: { "content-type": "application/json", accept: "application/json" }, body: JSON.stringify(body),
  });
  if (!res) return null;
  if (res.status === 204) { await res.body?.cancel(); return { rows: [], total: 0 }; }
  if (!res.ok) {
    const t = (await res.text().catch(() => "")).slice(0, 200).replace(/\s+/g, " ");
    run.errors.push(`finra http ${res.status}: ${t}`);
    return null;
  }
  const total = Number(res.headers.get("record-total"));
  const txt = await res.text();
  let rows: any[] = [];
  if (txt.trim()) {
    try { rows = JSON.parse(txt); } catch (e) { run.errors.push(`finra json: ${errMsg(e)}`); return null; }
  }
  if (!Array.isArray(rows)) { run.errors.push("finra: unexpected shape"); return null; }
  return { rows, total: Number.isFinite(total) ? total : NaN };
}
function addRow(agg: DayAgg, seen: Set<string>, r: any) {
  const sym = String(r?.securitiesInformationProcessorSymbolIdentifier ?? "").trim().toUpperCase();
  if (!sym) return;
  const fac = String(r?.reportingFacilityCode ?? "?");
  const k = `${sym}|${fac}|${r?.marketCode ?? ""}|${r?.tradeReportDate ?? ""}`;
  if (seen.has(k)) return; // defensive: paging overlap must not double count
  seen.add(k);
  const a = agg.get(sym) ?? { s: 0, se: 0, t: 0, f: "" };
  a.s += num(r.shortParQuantity); a.se += num(r.shortExemptParQuantity); a.t += num(r.totalParQuantity);
  if (!a.f.split(",").includes(fac)) a.f = a.f ? `${a.f},${fac}` : fac;
  agg.set(sym, a);
}
/** One consolidated trading day (all facilities). null = could not finish (nothing is written for a partial day). */
async function finraDay(run: Run, day: string, cfg: Cfg, st: FinraState): Promise<DayAgg | "empty" | null> {
  const agg: DayAgg = new Map();
  const seen = new Set<string>();
  let offset = 0, total = NaN, pages = 0;
  while (true) {
    const p = await finraPage(run, {
      limit: cfg.finra_page, offset, fields: FINRA_FIELDS,
      compareFilters: [{ compareType: "EQUAL", fieldName: "tradeReportDate", fieldValue: day }],
      sortFields: ["securitiesInformationProcessorSymbolIdentifier", "reportingFacilityCode", "marketCode"],
    });
    if (!p) return null;
    pages++;
    if (Number.isFinite(p.total)) total = p.total;
    for (const r of p.rows) addRow(agg, seen, r);
    offset += p.rows.length;
    if (!p.rows.length || p.rows.length < cfg.finra_page || (Number.isFinite(total) && offset >= total)) break;
  }
  if (!agg.size) return "empty";
  st.pages_per_day = pages;
  if (Number.isFinite(total) && seen.size < total) {
    const d = (run.extra.finra_dupes ??= []) as unknown[];
    d.push({ day, distinct: seen.size, total }); // rows the API repeated across pages (counted once)
  }
  return agg;
}
function pagesNeeded(run: Run, st: FinraState): boolean {
  const need = Math.max(1, st.pages_per_day ?? 8);
  const used = run.reqBySource["finra.api"] ?? 0;
  return used + need <= 20 && run.timeLeft() > need * 5500 + 10_000; // ~5 s spacing per page + ingest/upload
}

// ---- mirror files
async function gzipText(text: string): Promise<Uint8Array> {
  const s = new Blob([text]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(s).arrayBuffer());
}
async function mirrorDay(run: Run, day: string, agg: DayAgg): Promise<boolean> {
  const d8 = day.replaceAll("-", "");
  const lines = ["Date|Symbol|ShortVolume|ShortExemptVolume|TotalVolume|Market"];
  const q = (x: number) => String(Math.round(x * 1e6) / 1e6);
  for (const [sym, a] of [...agg].sort((x, y) => (x[0] < y[0] ? -1 : 1))) lines.push(`${d8}|${sym}|${q(a.s)}|${q(a.se)}|${q(a.t)}|${a.f}`);
  if (run.dryRun) return true;
  const bytes = await gzipText(lines.join("\n") + "\n");
  const { error } = await db.storage.from(BUCKET).upload(`finra/${d8}.txt.gz`, bytes, { contentType: "application/gzip", upsert: true });
  if (error) { run.errors.push(`storage upload ${d8}: ${error.message}`); return false; }
  return true;
}
async function mirroredDays(run: Run): Promise<Set<string>> {
  const out = new Set<string>();
  for (let off = 0; off < 5000; off += 1000) {
    const { data, error } = await db.storage.from(BUCKET).list("finra", { limit: 1000, offset: off, sortBy: { column: "name", order: "desc" } });
    if (error) { run.errors.push(`storage list: ${error.message}`); break; }
    for (const f of data ?? []) {
      const m = /^(\d{4})(\d{2})(\d{2})\.txt\.gz$/.exec(f.name);
      if (m) out.add(`${m[1]}-${m[2]}-${m[3]}`);
    }
    if (!data || data.length < 1000) break;
  }
  return out;
}

// ---- rolling per-ticker baseline (private Storage object; no DB rows for the 12k-ticker panel)
interface Ring { days: string[]; syms: string[]; vals: Float32Array }
const RING_PATH = "finra/_ring.bin";
async function ringLoad(run: Run): Promise<Ring> {
  const empty: Ring = { days: [], syms: [], vals: new Float32Array(0) };
  const { data, error } = await db.storage.from(BUCKET).download(RING_PATH);
  if (error || !data) return empty;
  try {
    const buf = new Uint8Array(await data.arrayBuffer());
    const n = new DataView(buf.buffer, buf.byteOffset, buf.byteLength).getUint32(0, true);
    const h = JSON.parse(new TextDecoder().decode(buf.subarray(4, 4 + n)));
    const off = 4 + n + ((4 - ((4 + n) % 4)) % 4);
    const vals = new Float32Array(buf.slice(off).buffer);
    if (!Array.isArray(h.days) || !Array.isArray(h.syms) || vals.length !== h.days.length * h.syms.length) throw new Error("size mismatch");
    return { days: h.days, syms: h.syms, vals };
  } catch (e) { run.errors.push(`ring decode: ${errMsg(e)}`); return empty; }
}
async function ringSave(run: Run, r: Ring): Promise<boolean> {
  if (run.dryRun) return true;
  const hdr = new TextEncoder().encode(JSON.stringify({ v: 1, days: r.days, syms: r.syms }));
  const off = 4 + hdr.length + ((4 - ((4 + hdr.length) % 4)) % 4);
  const out = new Uint8Array(off + r.vals.byteLength);
  new DataView(out.buffer).setUint32(0, hdr.length, true);
  out.set(hdr, 4);
  out.set(new Uint8Array(r.vals.buffer, r.vals.byteOffset, r.vals.byteLength), off);
  const { error } = await db.storage.from(BUCKET).upload(RING_PATH, out, { contentType: "application/octet-stream", upsert: true });
  if (error) { run.errors.push(`ring upload: ${error.message}`); return false; }
  return true;
}
/** Merge day columns (total volume per ticker) into the ring, keeping the newest W trading days. */
function ringMerge(r: Ring, adds: Array<[string, DayAgg]>, W: number): Ring {
  const daySet = new Set(r.days);
  for (const [d] of adds) daySet.add(d);
  let days = [...daySet].sort();
  if (days.length > W) days = days.slice(days.length - W);
  const dIdx = new Map(days.map((d, i) => [d, i]));
  const symSet = new Set(r.syms);
  for (const [d, m] of adds) if (dIdx.has(d)) for (const s of m.keys()) symSet.add(s);
  const syms = [...symSet].sort();
  const D = days.length, oldD = r.days.length;
  const vals = new Float32Array(syms.length * D).fill(NaN);
  const oldSym = new Map(r.syms.map((s, i) => [s, i]));
  const colMap = r.days.map((d) => dIdx.get(d) ?? -1);
  const keep = new Uint8Array(syms.length);
  syms.forEach((s, i) => {
    const oi = oldSym.get(s);
    if (oi === undefined) return;
    for (let j = 0; j < oldD; j++) {
      const nj = colMap[j];
      const v = r.vals[oi * oldD + j];
      if (nj >= 0 && !Number.isNaN(v)) { vals[i * D + nj] = v; keep[i] = 1; }
    }
  });
  const newSym = new Map(syms.map((s, i) => [s, i]));
  for (const [d, m] of adds) {
    const j = dIdx.get(d);
    if (j === undefined) continue;
    for (const [s, a] of m) { const i = newSym.get(s)!; vals[i * D + j] = a.t; keep[i] = 1; }
  }
  // drop tickers with no value left in the window
  const idx = syms.map((_, i) => i).filter((i) => keep[i]);
  if (idx.length === syms.length) return { days, syms, vals };
  const v2 = new Float32Array(idx.length * D);
  idx.forEach((oi, ni) => v2.set(vals.subarray(oi * D, oi * D + D), ni * D));
  return { days, syms: idx.map((i) => syms[i]), vals: v2 };
}
/** §6.1 robust z of ln(1+volume) vs the ticker's own t-77..t-15 trading-day baseline; top N with ratio/z floors. */
function screen(r: Ring, day: string, cfg: Cfg) {
  const j = r.days.indexOf(day);
  if (j < 0) return { baseline_days: 0, cands: [] as Array<{ sym: string; z: number; ratio: number; v: number }> };
  const lag = new Map(tradingDaysBack(day, 80).map((d, i) => [d, i]));
  const cols: number[] = [];
  r.days.forEach((d, k) => { const l = lag.get(d); if (l !== undefined && l >= 15 && l <= 77) cols.push(k); });
  const D = r.days.length;
  const out: Array<{ sym: string; z: number; ratio: number; v: number }> = [];
  if (cols.length < 28) return { baseline_days: cols.length, cands: out };
  const base: number[] = [];
  for (let i = 0; i < r.syms.length; i++) {
    const v = r.vals[i * D + j];
    if (!(v > 0)) continue;
    base.length = 0;
    for (const k of cols) { const b = r.vals[i * D + k]; if (!Number.isNaN(b)) base.push(b); }
    if (base.length < 28) continue;
    const lam = median(base);
    if (!(lam >= cfg.finra_liq_floor)) continue;
    const xb = base.map((b) => Math.log1p(b));
    const m = median(xb);
    const mad = median(xb.map((x) => Math.abs(x - m)));
    const sigma = Math.max(1.4826 * mad, 1 / Math.sqrt(lam + 1), 0.02);
    const x = Math.log1p(v);
    const z = (x - m) / sigma;
    const ratio = Math.exp(x - m);
    if (ratio >= cfg.finra_cand_ratio && z >= cfg.finra_cand_z) out.push({ sym: r.syms[i], z, ratio, v });
  }
  out.sort((a, b) => b.z - a.z);
  return { baseline_days: cols.length, cands: out.slice(0, cfg.finra_cand_top) };
}
async function finraCandidates(run: Run, ring: Ring, day: string, cfg: Cfg, tickerTopic: Map<string, number>) {
  const s = screen(ring, day, cfg);
  const rows = s.cands.map((c, i) => ({
    day, source: "finra.shvol", geo: "US", label: c.sym, rank: i + 1, value: r2(c.ratio),
    evidence: clamp01(Math.log(c.ratio) / Math.log(10)), topic_id: tickerTopic.get(c.sym) ?? null,
    meta: { k: "ticker", z: r2(c.z), ratio: r2(c.ratio) },
  }));
  if (rows.length) await ingestCandidates(run, rows);
  return { day, baseline_days: s.baseline_days, candidates: rows.length, top: rows.slice(0, 5).map((r) => [r.label, r.meta.z, r.meta.ratio]) };
}
/** registry + panel tickers and the '__total__' normaliser for one consolidated day */
function tickerRows(day: string, agg: DayAgg, keys: WatchKey[]): ObsRow[] {
  const rows: ObsRow[] = [];
  let tt = 0, ts = 0;
  for (const a of agg.values()) { tt += a.t; ts += a.s; }
  rows.push({ source: "finra.shvol", key: "__total__", metric: "n", day, value: Math.round(tt), aux: tt > 0 ? ts / tt : null,
    meta: { coverage: agg.size } });
  for (const k of keys) {
    const a = agg.get(k.key.toUpperCase());
    rows.push({ source: "finra.shvol", key: k.key, metric: k.metric || "n", day, value: a ? Math.round(a.t) : 0,
      aux: a && a.t > 0 ? a.s / a.t : null, topic_id: k.topic_id ?? null });
  }
  return rows;
}
interface FinraState { pages_per_day?: number; nodata?: string[]; last_day?: string; cand_day?: string }

async function finraKeys(run: Run): Promise<WatchKey[]> {
  const { data, error } = await db.rpc("att_watchlist", { p_source: "finra.shvol", p_limit: 5000, p_slice: null, p_nslices: 3 });
  if (error) { run.errors.push(`att_watchlist: ${error.message}`); return []; }
  return ((data ?? []) as WatchKey[]).filter((k) => /^[A-Z0-9.\-]{1,10}$/i.test(k.key));
}

/** Mirror a list of days (newest first) within this run's budget; updates ring, ingests tickers. */
async function mirrorDays(run: Run, days: string[], cfg: Cfg, st: FinraState, keys: WatchKey[], maxDays: number) {
  const done: Array<[string, DayAgg]> = [];
  const empty: string[] = [];
  let rows = 0;
  for (const d of days) {
    if (done.length + empty.length >= maxDays) break;
    if (!pagesNeeded(run, st)) { run.partial = true; break; }
    const agg = await finraDay(run, d, cfg, st);
    if (agg === null) { run.partial = true; break; }
    if (agg === "empty") { empty.push(d); continue; }
    if (!(await mirrorDay(run, d, agg))) break;
    const r = await ingest(run, tickerRows(d, agg, keys));
    rows += Number(r?.rows ?? 0);
    done.push([d, agg]);
  }
  if (empty.length) st.nodata = [...new Set([...(st.nodata ?? []), ...empty])].sort().slice(-50);
  return { done, empty, rows };
}

async function finra(run: Run) {
  const t0 = Date.now();
  const cfg = await mcfg(run);
  const src = await sourceInfo("finra.api");
  if (!src?.enabled) { run.source({ source: "finra.shvol", status: "disabled", note: src?.reason ?? null }); return; }
  // one FINRA writer at a time (ring + files): take the api.finra.org lease before reading shared state
  if (!(await hostLease(run, "api.finra.org"))) { run.source({ source: "finra.shvol", status: "host_busy" }); return; }
  const st = ((await stateGet("finra.state")) ?? {}) as FinraState;
  const want = typeof run.params?.date === "string" ? run.params.date : prevTradingDay(
    typeof run.body?.as_of === "string" ? run.body.as_of : latestPublished());
  const have = await mirroredDays(run);
  const keys = await finraKeys(run);
  const tickerTopic = new Map(keys.map((k) => [k.key.toUpperCase(), k.topic_id]));
  let ring = await ringLoad(run);
  let note = "";
  let mirrored: string[] = [];
  if (have.has(want) && run.params?.force !== true) note = "already mirrored";
  else if ((st.nodata ?? []).includes(want) && run.params?.force !== true) note = "no data for this day";
  else {
    const res = await mirrorDays(run, [want], cfg, st, keys, 1);
    mirrored = res.done.map(([d]) => d);
    if (res.empty.length) note = "no rows yet (holiday or not yet published)";
    if (res.done.length) ring = ringMerge(ring, res.done, cfg.finra_ring_days);
    if (res.done.length) await ringSave(run, ring);
  }
  const cand = (have.has(want) || mirrored.includes(want)) && st.cand_day !== want || run.params?.rescreen === true
    ? await finraCandidates(run, ring, want, cfg, tickerTopic) : null;
  if (cand && cand.baseline_days >= 28) st.cand_day = want;
  if (mirrored.length) st.last_day = [st.last_day ?? "", ...mirrored].sort().at(-1);
  if (!run.dryRun) await stateSet("finra.state", st);
  run.extra.finra = { day: want, mirrored, note, ring_days: ring.days.length, ring_tickers: ring.syms.length,
    registry_tickers: keys.length, screen: cand, stored: mirrored.length ? `${BUCKET}/finra/${want.replaceAll("-", "")}.txt.gz` : null };
  run.source({ source: "finra.shvol", status: mirrored.length || note ? "ok" : failNote(run, "api.finra.org"),
    keys: keys.length + 1, rows: run.rows.obs, ms: Date.now() - t0, note: note || null });
}

async function finraFilesBackfill(run: Run, cfg: Cfg) {
  const t0 = Date.now();
  if (!(await hostLease(run, "api.finra.org"))) { run.source({ source: "finra.shvol", status: "host_busy" }); await settleJobs(run, new Set(), 120); return; }
  const st = ((await stateGet("finra.state")) ?? {}) as FinraState;
  const have = await mirroredDays(run);
  const target = tradingDaysBack(latestPublished(), cfg.finra_days);
  const nodata = new Set(st.nodata ?? []);
  const missing = target.filter((d) => !have.has(d) && !nodata.has(d));
  const keys = await finraKeys(run);
  const tickerTopic = new Map(keys.map((k) => [k.key.toUpperCase(), k.topic_id]));
  let ring = await ringLoad(run);
  const res = await mirrorDays(run, missing, cfg, st, keys, cfg.finra_bf_days_per_run);
  if (res.done.length) { ring = ringMerge(ring, res.done, cfg.finra_ring_days); await ringSave(run, ring); }
  // screen the newest mirrored day once its baseline is long enough (the daily run does this from then on)
  const newest = [...have, ...res.done.map(([d]) => d)].sort().at(-1);
  let cand = null;
  if (newest && st.cand_day !== newest) {
    cand = await finraCandidates(run, ring, newest, cfg, tickerTopic);
    if (cand.baseline_days >= 28) st.cand_day = newest;
  }
  if (!run.dryRun) await stateSet("finra.state", st);
  const left = missing.length - res.done.length - res.empty.length;
  run.extra.finra_backfill = { mirrored: res.done.map(([d]) => d), empty: res.empty, have: have.size + res.done.length,
    missing_left: left, ring_days: ring.days.length, ring_tickers: ring.syms.length, screen: cand, pages_per_day: st.pages_per_day };
  if (left > 0) run.partial = true;
  run.source({ source: "finra.shvol", status: left > 0 ? "partial" : "ok", rows: res.rows, ms: Date.now() - t0,
    note: `${have.size + res.done.length}/${target.length} trading days mirrored` });
  await settleJobs(run, left > 0 ? new Set() : "all", 60, "api.finra.org");
}

async function finraKeysBackfill(run: Run, cfg: Cfg) {
  const t0 = Date.now();
  const keys = (Array.isArray(run.body?.keys) ? run.body.keys : []) as Array<{ key: string; metric?: string; topic_id?: number }>;
  const from = String(run.body?.backfill?.from ?? addDays(today(), -400));
  const to = String(run.body?.backfill?.to ?? addDays(today(), -1));
  const syms = keys.map((k) => String(k.key).toUpperCase()).filter((s) => /^[A-Z0-9.\-]{1,10}$/.test(s));
  const doneKeys = new Set<string>();
  let rows = 0;
  for (let i = 0; i < syms.length; i += 3) {
    const chunk = syms.slice(i, i + 3);
    const agg = new Map<string, Map<string, Agg>>(); // sym -> day -> agg
    const seen = new Set<string>();
    let offset = 0, ok = true;
    while (true) {
      if (run.outOfTime(12_000)) { ok = false; run.partial = true; break; }
      const p = await finraPage(run, {
        limit: cfg.finra_page, offset, fields: FINRA_FIELDS,
        domainFilters: [{ fieldName: "securitiesInformationProcessorSymbolIdentifier", values: chunk }],
        dateRangeFilters: [{ fieldName: "tradeReportDate", startDate: from, endDate: to }],
        sortFields: ["tradeReportDate", "securitiesInformationProcessorSymbolIdentifier", "reportingFacilityCode", "marketCode"],
      });
      if (!p) { ok = false; break; }
      for (const r of p.rows) {
        const sym = String(r?.securitiesInformationProcessorSymbolIdentifier ?? "").toUpperCase();
        const d = String(r?.tradeReportDate ?? "").slice(0, 10);
        if (!sym || !/^\d{4}-\d{2}-\d{2}$/.test(d)) continue;
        let m = agg.get(sym);
        if (!m) { m = new Map(); agg.set(sym, m); }
        const one: DayAgg = new Map([[sym, m.get(d) ?? { s: 0, se: 0, t: 0, f: "" }]]);
        addRow(one, seen, r);
        m.set(d, one.get(sym)!);
      }
      offset += p.rows.length;
      if (!p.rows.length || p.rows.length < cfg.finra_page || (Number.isFinite(p.total) && offset >= p.total)) break;
    }
    if (!ok) break;
    const out: ObsRow[] = [];
    for (const k of keys) {
      const sym = String(k.key).toUpperCase();
      if (!chunk.includes(sym)) continue;
      const m = agg.get(sym) ?? new Map();
      // every trading day in the window gets a value (0 when the ticker had no reported volume)
      for (let d = prevTradingDay(to); d >= from; d = prevTradingDay(addDays(d, -1))) {
        const a = m.get(d);
        out.push({ source: "finra.shvol", key: k.key, metric: k.metric || "n", day: d, value: a ? Math.round(a.t) : 0,
          aux: a && a.t > 0 ? a.s / a.t : null, topic_id: k.topic_id ?? null });
      }
      doneKeys.add(k.key);
    }
    const r = await ingest(run, out);
    rows += Number(r?.rows ?? 0);
  }
  run.extra.finra_keys_backfill = { keys: syms.length, done: doneKeys.size, from, to, rows };
  run.source({ source: "finra.shvol", status: doneKeys.size === syms.length ? "ok" : "partial", keys: syms.length, rows, ms: Date.now() - t0 });
  await settleJobs(run, doneKeys, 120, "api.finra.org");
}

// ============================================================ USAspending
interface MonthVal { day: string; value: number }
function monthStart(d: string, back = 0): string {
  const y = +d.slice(0, 4), m = +d.slice(5, 7) - 1 - back;
  const dt = new Date(Date.UTC(y, m, 1));
  return ymd(dt);
}
function monthEnd(start: string): string { return addDays(monthStart(start, -1), -1); }
async function usaspQuery(run: Run, term: string, start: string, end: string): Promise<MonthVal[] | null> {
  const res = await politeFetch(run, USASP_URL, {
    source: "usasp.spend", method: "POST", timeoutMs: 30_000,
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({ group: "month", filters: { keywords: [term], time_period: [{ start_date: start, end_date: end }] } }),
  });
  if (!res) return null;
  if (!res.ok) {
    const t = (await res.text().catch(() => "")).slice(0, 160).replace(/\s+/g, " ");
    run.errors.push(`usaspending http ${res.status} (${term}): ${t}`);
    return res.status === 400 || res.status === 422 ? [] : null;
  }
  const j = await res.json().catch(() => null);
  if (!Array.isArray(j?.results)) { run.errors.push(`usaspending: unexpected shape (${term})`); return []; }
  const out: MonthVal[] = [];
  for (const r of j.results) {
    // group=month returns FISCAL months: fiscal month 1 = October of fiscal_year - 1
    const fy = Number(r?.time_period?.fiscal_year), fm = Number(r?.time_period?.month);
    if (!fy || !fm) continue;
    const cm = ((fm + 8) % 12) + 1;
    const cy = fm <= 3 ? fy - 1 : fy;
    const day = `${cy}-${pad(cm)}-01`;
    if (day < start.slice(0, 8) + "01" || day > end) continue;
    out.push({ day, value: num(r.aggregated_amount) });
  }
  return out;
}
function usaspRows(k: { key: string; topic_id?: number | null }, vals: MonthVal[], partialMonth: string): ObsRow[] {
  return vals.map((v) => ({ source: "usasp.spend", key: k.key, metric: "usd", day: v.day, value: r2(v.value),
    topic_id: k.topic_id ?? null, meta: v.day === partialMonth ? { monthly: true, partial: true } : { monthly: true } }));
}

async function usaspending(run: Run) {
  const t0 = Date.now();
  const cfg = await mcfg(run);
  const src = await sourceInfo("usasp.spend");
  if (!src?.enabled) { run.source({ source: "usasp.spend", status: "disabled", note: src?.reason ?? null }); return; }
  const d0 = today();
  const keys = (await watchlist(run, "usasp.spend")).filter((k) => k.key.length >= 3);
  const rot = ((await stateGet("usasp.rot")) ?? { last: {} }) as { last: Record<string, string> };
  rot.last ??= {};
  const cutoff = addDays(d0, -cfg.usasp_rotation_days);
  const forced = Array.isArray(run.body?.keys) && run.body.keys.length > 0;
  const due = keys.filter((k) => forced || !rot.last[k.key] || rot.last[k.key] <= cutoff)
    .sort((a, b) => (rot.last[a.key] ?? "").localeCompare(rot.last[b.key] ?? ""));
  const maxKeys = Math.max(1, Math.min(cfg.usasp_max_keys, Math.ceil(keys.length / Math.max(1, cfg.usasp_rotation_days)) + 4));
  const start = monthStart(d0, 2), end = d0, partialMonth = monthStart(d0);
  let rows = 0, fetched = 0;
  for (const k of due.slice(0, forced ? due.length : maxKeys)) {
    if (run.outOfTime(15_000)) { run.partial = true; break; }
    const vals = await usaspQuery(run, k.key, start, end);
    if (vals === null) { run.partial = true; break; }
    fetched++;
    rot.last[k.key] = d0;
    const r = await ingest(run, usaspRows(k, vals, partialMonth));
    rows += Number(r?.rows ?? 0);
  }
  if (!run.dryRun) await stateSet("usasp.rot", rot);
  run.extra.usaspending = { keys: keys.length, due: due.length, fetched, window: [start, end], rows };
  run.source({ source: "usasp.spend", status: fetched ? "ok" : failNote(run, "api.usaspending.gov"), keys: fetched, rows,
    ms: Date.now() - t0 });
}

async function usaspBackfill(run: Run, cfg: Cfg) {
  const t0 = Date.now();
  const src = await sourceInfo("usasp.spend");
  if (!src?.enabled) { await settleJobs(run, "all"); run.source({ source: "usasp.spend", status: "disabled" }); return; }
  const keys = (Array.isArray(run.body?.keys) ? run.body.keys : []) as Array<{ key: string; topic_id?: number }>;
  const d0 = today();
  const floor = monthStart(d0, cfg.usasp_backfill_months);
  const bf = ((await stateGet("usasp.bf")) ?? {}) as Record<string, string>; // key -> oldest window start fetched
  const doneKeys = new Set<string>();
  let rows = 0, calls = 0, stop = false;
  for (const k of keys) {
    if (stop) break;
    let next = bf[k.key] ? monthStart(bf[k.key], 3) : monthStart(d0, 5); // the rotation covers the newest 3 months
    while (next >= floor) {
      if (run.outOfTime(15_000)) { stop = true; run.partial = true; break; }
      const end = monthEnd(monthStart(next, -2));
      const vals = await usaspQuery(run, k.key, next, end);
      if (vals === null) { stop = true; run.partial = true; break; }
      calls++;
      const r = await ingest(run, usaspRows(k, vals, ""));
      rows += Number(r?.rows ?? 0);
      bf[k.key] = next;
      next = monthStart(next, 3);
    }
    if (next < floor) doneKeys.add(k.key);
  }
  if (!run.dryRun) await stateSet("usasp.bf", bf);
  run.extra.usasp_backfill = { keys: keys.length, done: doneKeys.size, calls, rows, floor };
  run.source({ source: "usasp.spend", status: doneKeys.size === keys.length ? "ok" : "partial", keys: keys.length, rows, ms: Date.now() - t0 });
  await settleJobs(run, doneKeys, 300, "api.usaspending.gov");
}

// ============================================================ SEC EDGAR full-text search (DISABLED: needs owner email)
async function edgarCount(run: Run, term: string, start: string, end: string): Promise<number | null> {
  const q = encodeURIComponent(`"${term}"`);
  const res = await politeFetch(run, `${EFTS_URL}?q=${q}&dateRange=custom&startdt=${start}&enddt=${end}`,
    { source: "sec.efts", headers: { accept: "application/json" }, timeoutMs: 20_000 });
  if (!res) return null;
  if (!res.ok) { await res.body?.cancel(); run.errors.push(`efts http ${res.status}`); return null; }
  const j = await res.json().catch(() => null);
  const v = j?.hits?.total?.value;
  return typeof v === "number" ? v : null;
}
async function edgar(run: Run) {
  const t0 = Date.now();
  const cfg = await mcfg(run);
  const src = await sourceInfo("sec.efts");
  if (!src?.enabled) {
    run.source({ source: "sec.efts", status: "disabled", note: src?.reason ?? "needs owner contact email" });
    return;
  }
  const d0 = today();
  const keys = await watchlist(run, "sec.efts");
  const rot = ((await stateGet("edgar.rot")) ?? { last: {} }) as { last: Record<string, string> };
  rot.last ??= {};
  const cutoff = addDays(d0, -cfg.edgar_rotation_days);
  const due = keys.filter((k) => !rot.last[k.key] || rot.last[k.key] <= cutoff).slice(0, cfg.edgar_max_keys);
  const rows: ObsRow[] = [];
  for (const k of due) {
    if (run.outOfTime(10_000)) { run.partial = true; break; }
    for (const back of [1, 0]) { // last complete month, then the current (partial) month
      const s = monthStart(d0, back), e = back ? monthEnd(s) : d0;
      const n = await edgarCount(run, k.key, s, e);
      if (n === null) break;
      rows.push({ source: "sec.efts", key: k.key, metric: "n", day: s, value: n, topic_id: k.topic_id ?? null,
        meta: back ? { monthly: true } : { monthly: true, partial: true } });
    }
    rot.last[k.key] = d0;
  }
  const r = await ingest(run, rows);
  if (!run.dryRun) await stateSet("edgar.rot", rot);
  run.source({ source: "sec.efts", status: "ok", keys: due.length, rows: Number(r?.rows ?? 0), ms: Date.now() - t0 });
}

// ============================================================ backfill router
async function backfill(run: Run) {
  const cfg = await mcfg(run);
  const source = String(run.params?.source ?? "");
  if (source === "finra.api" && run.params?.files) return await finraFilesBackfill(run, cfg);
  if (source === "finra.shvol" || source === "finra.api") return await finraKeysBackfill(run, cfg);
  if (source === "usasp.spend") return await usaspBackfill(run, cfg);
  const note = source === "sec.efts" ? "sec.efts disabled (needs owner contact email)"
    : source === "poly.mkt" || source === "kalshi.mkt" ? "warm-up source: volume has no history (price history is fetched in polymarket mode)"
    : `no backfill for source '${source}'`;
  run.source({ source: source || "?", status: "skipped", note });
  const ids = run.jobIds();
  if (ids.length && !run.dryRun) {
    await db.rpc("att_jobs_done", { p_jobs: ids, p_status: "skipped", p_error: note, p_not_before: null });
    run.body.job_ids = [];
    delete run.body.job_id;
  }
}

serve(FN, {
  finra, polymarket, kalshi, usaspending, edgar, backfill,
  ping: async (run) => { run.extra.version = MARKET_VERSION; },
});
