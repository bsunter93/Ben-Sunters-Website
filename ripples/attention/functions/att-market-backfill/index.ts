// att-market-backfill — Ripple Map v6 (WS-A): prediction-market PRICE history (ENGINE_SPEC §1.1 channel PM, §9).
// att-market (not redeployed) keeps collecting volumes; this function adds the price series the PM channel tests.
//
// Modes (body.mode):
//   kalshi      for every topic-linked Kalshi event (kalshi.mkt 'ev:<event>' series with a topic): the event's markets
//               (GET /events/{event}?with_nested_markets=true), top params.per_event (3) by volume, daily candlesticks
//               (GET /series/{series}/markets/{ticker}/candlesticks, period_interval=1440) from the market open (at most
//               400 days back) -> kalshi.mkt key 'm:<ticker>' metric 'p' = close price in dollars (0..1; mid of the
//               yes bid/ask close when no trade), aux = contracts traded that day, topic_id = the event's topic.
//               Markets already backfilled get only the last 10 days while open. Cursor/state: att_state 'mbf.kalshi'.
//   poly_deep   Polymarket price series cut by att-market's 400-day cap (first stored day <= series creation - 395):
//               Gamma /markets/{id} -> CLOB prices-history interval=max fidelity=1440, days before the first stored day.
//   ping        no requests.
// Titles are never stored; only prices / volumes. Requests go through politeFetch under the fetch-only sources
// kalshi.hist / poly.hist (same hosts, own small daily budgets) so this backfill neither starves nor is starved by
// att-market's crawl budget; the series are stored under kalshi.mkt / poly.mkt.
import { addDays, db, ingest, type ObsRow, type Run, serve, stateGet, stateSet } from "./att.ts";
import { getJson, todayUtc, wrap } from "./wsa.ts";

export const MBF_VERSION = "2026-09-25.b3";
const KS = "kalshi.hist", PS = "poly.hist"; // fetch sources (att_sources rows, 19_att_families.sql)
const KALSHI = "https://api.elections.kalshi.com/trade-api/v2";
const GAMMA = "https://gamma-api.polymarket.com";
const CLOB = "https://clob.polymarket.com";

async function st<T>(k: string, dflt: T): Promise<T> { return ((await stateGet(k).catch(() => null)) ?? dflt) as T; }
async function stSet(run: Run, k: string, v: unknown) { if (!run.dryRun) await stateSet(k, v).catch((e) => run.errors.push(`state ${k}: ${String(e)}`)); }
const num = (v: unknown): number | null => { const x = typeof v === "number" ? v : Number(v); return v === null || v === undefined || v === "" || !Number.isFinite(x) ? null : x; };
const dollars = (o: any, k: string): number | null => {
  const d = num(o?.[`${k}_dollars`]);
  if (d !== null) return d;
  const c = num(o?.[k]);
  return c === null ? null : c / 100;
};
async function targets(run: Run, source: string): Promise<Array<{ key: string; topic_id: number; first_day: string | null; created: string }>> {
  const { data, error } = await db.rpc("att_market_bf_targets", { p_source: source });
  if (error) { run.errors.push(`att_market_bf_targets: ${error.message}`); return []; }
  return Array.isArray(data) ? data : [];
}

async function modeKalshi(run: Run) {
  const t0 = Date.now();
  const perEvent = Math.max(1, Math.min(5, Number(run.params.per_event ?? 3)));
  const maxCalls = Math.max(2, Math.min(120, Number(run.params.max_calls ?? 40)));
  const today = todayUtc();
  const evs = await targets(run, "kalshi.mkt");
  const state = await st<{ markets?: Record<string, { last?: string; series?: string; topic?: number; closed?: boolean }>; ev_checked?: Record<string, string> }>("mbf.kalshi", {});
  const markets = state.markets ?? {}, evChecked = state.ev_checked ?? {};
  let calls = 0, rows = 0, candles = 0;
  const out: ObsRow[] = [];
  // 1) resolve markets of events not checked in the last 7 days
  for (const e of evs) {
    if (calls >= maxCalls || run.outOfTime(15_000)) { run.partial = true; break; }
    const ev = e.key.slice(3);
    if (evChecked[ev] && evChecked[ev] >= addDays(today, -7)) continue;
    const j = await getJson(run, KS, `${KALSHI}/events/${encodeURIComponent(ev)}?with_nested_markets=true`);
    calls++;
    if (!j) { if (run.skipped.some((s) => s.host === "api.elections.kalshi.com")) break; continue; }
    const event = j.event ?? j;
    const series = String(event?.series_ticker ?? ev.split("-")[0]);
    const ms = (Array.isArray(event?.markets) ? event.markets : Array.isArray(j.markets) ? j.markets : [])
      .map((m: any) => ({ ticker: String(m?.ticker ?? ""), vol: num(m?.volume_fp ?? m?.volume) ?? 0, status: String(m?.status ?? "") }))
      .filter((m: any) => m.ticker)
      .sort((a: any, b: any) => b.vol - a.vol).slice(0, perEvent);
    for (const m of ms) markets[m.ticker] = { ...(markets[m.ticker] ?? {}), series, topic: e.topic_id, closed: /closed|settled|finalized|determined/.test(m.status) };
    evChecked[ev] = today;
  }
  // 2) candlesticks: full history once, then the last 10 days while the market is open
  const now = Math.floor(Date.now() / 1000);
  for (const [ticker, m] of Object.entries(markets)) {
    if (calls >= maxCalls || run.outOfTime(10_000)) { run.partial = true; break; }
    if (!m.series || !m.topic) continue;
    if (m.last && (m.last >= addDays(today, -1) || m.closed)) continue;
    const start = m.last ? now - 10 * 86400 : now - 400 * 86400;
    const q = new URLSearchParams({ start_ts: String(start), end_ts: String(now), period_interval: "1440" });
    const j = await getJson(run, KS, `${KALSHI}/series/${encodeURIComponent(m.series)}/markets/${encodeURIComponent(ticker)}/candlesticks?${q}`);
    calls++;
    if (!j) { if (run.skipped.some((s) => s.host === "api.elections.kalshi.com")) break; m.last = today; continue; }
    const cs = Array.isArray(j.candlesticks) ? j.candlesticks : [];
    for (const c of cs) {
      const end = num(c?.end_period_ts);
      if (end === null) continue;
      const day = new Date((end - 1) * 1000).toISOString().slice(0, 10);
      if (day >= today) continue;
      let p = dollars(c?.price, "close");
      if (p === null) {
        const b = dollars(c?.yes_bid, "close"), a = dollars(c?.yes_ask, "close");
        p = b !== null && a !== null ? (a + b) / 2 : null;
      }
      if (p === null || p < 0 || p > 1) continue;
      out.push({ source: "kalshi.mkt", key: `m:${ticker}`, metric: "p", day, value: Math.round(p * 1e4) / 1e4,
        aux: num(c?.volume_fp ?? c?.volume), topic_id: m.topic });
      candles++;
    }
    m.last = today;
  }
  if (out.length) rows = (await ingest(run, out)).rows;
  await stSet(run, "mbf.kalshi", { markets, ev_checked: evChecked });
  run.extra.kalshi = { events: evs.length, markets: Object.keys(markets).length, calls, candles, rows };
  run.source({ source: "kalshi.mkt", status: run.partial ? "partial" : "ok", keys: Object.keys(markets).length, rows, ms: Date.now() - t0 });
}

async function modePolyDeep(run: Run) {
  const t0 = Date.now();
  const maxMk = Math.max(1, Math.min(40, Number(run.params.max_markets ?? 20)));
  const all = await targets(run, "poly.mkt");
  const cut = all.filter((t) => t.first_day && t.first_day <= addDays(t.created, -395));
  const done = await st<Record<string, string>>("mbf.poly", {});
  let rows = 0, n = 0;
  for (const t of cut) {
    if (n >= maxMk || run.outOfTime(10_000)) { run.partial = true; break; }
    if (done[t.key]) continue;
    const id = t.key.slice(2);
    const g = await getJson(run, PS, `${GAMMA}/markets/${encodeURIComponent(id)}`);
    n++;
    if (!g) { run.partial = true; if (run.skipped.some((s) => s.host === "gamma-api.polymarket.com")) break; continue; } // retry next run
    let tok: string | null = null;
    try { const ids = typeof g?.clobTokenIds === "string" ? JSON.parse(g.clobTokenIds) : g?.clobTokenIds; tok = Array.isArray(ids) && ids[0] ? String(ids[0]) : null; } catch { tok = null; }
    if (!tok) { done[t.key] = "no_token"; continue; }
    const j = await getJson(run, PS, `${CLOB}/prices-history?market=${encodeURIComponent(tok)}&interval=max&fidelity=1440`);
    if (!j) continue;
    const byDay = new Map<string, number>();
    for (const h of Array.isArray(j.history) ? j.history : []) {
      const ts = num(h?.t), p = num(h?.p);
      if (ts === null || p === null) continue;
      const d = new Date(ts * 1000).toISOString().slice(0, 10);
      if (d < t.first_day!) byDay.set(d, p);
    }
    const out: ObsRow[] = [...byDay].map(([d, p]) => ({ source: "poly.mkt", key: t.key, metric: "p", day: d, value: p, topic_id: t.topic_id }));
    rows += (await ingest(run, out)).rows;
    done[t.key] = todayUtc();
  }
  await stSet(run, "mbf.poly", done);
  run.extra.poly_deep = { price_series: all.length, cut_at_400d: cut.length, fetched: n, rows };
  run.source({ source: "poly.mkt", status: run.partial ? "partial" : "ok", keys: n, rows, ms: Date.now() - t0 });
}

serve("att-market-backfill", {
  kalshi: wrap(modeKalshi),
  poly_deep: wrap(modePolyDeep),
  ping: wrap(async (r) => { r.extra.version = MBF_VERSION; }),
});
