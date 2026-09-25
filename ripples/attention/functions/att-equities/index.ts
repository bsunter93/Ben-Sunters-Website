// att-equities — Ripple Map v6 (WS-A, OWNER D-10) US equities / ETF daily abnormal volume + abnormal return, DERIVED ONLY.
// ORANGE* (DEMARCATION §1.3), owner-approved 2026-09-25: documented keyed APIs, keys issued to the owner, calls inside
// the free-tier quota and purpose. Rules (D-10): stay within each provider's free quota and terms; store derived z only;
// never store or republish raw price or volume series; no tickers in open-data files.
//
// What is stored (attention_obs via att_ingest; source = provider row, geo US, key = symbol):
//   metric 'volz'  robust z of ln(volume_t) against the symbol's own trading days t-70..t-11 (median / 1.4826*MAD,
//                  >= 40 baseline days).                                         aux = baseline days used
//   metric 'retz'  robust z of the market-model abnormal log return ar_t = r_t - (a + b*r_SPY,t), a/b fitted by OLS on
//                  t-130..t-11 (>= 60 days; SPY itself: raw return), scaled by 1.4826*MAD of ar over the same window.
//                                                                                  aux = b (market beta)
// Raw bars live only in memory for the run.
//
// Modes:
//   twelvedata   Twelve Data /time_series (1day). Daily: outputsize 160 for symbols with history (z for the last 10
//                trading days). Symbols without history get the full backfill (outputsize 5000 from params.from /
//                2018-06-01). One credit per call; budget 400/day (<= 50% of 800), 1 call / 15 s (<= 50% of 8/min).
//   alphavantage Alpha Vantage TIME_SERIES_DAILY compact (100 days) for att_config.equities.av_symbols (second route,
//                12 calls/day <= 50% of 25). Rate-limit notes ("Note"/"Information") stop the host for the UTC day.
//   backfill     = twelvedata with full history for params.symbols (or every symbol lacking history).
//   ping         no requests.
// Every mode reads its key via public.att_secret at run time. Without the key the mode reports `no_key` and makes NO
// request (the collector stays idle until the owner adds the Vault secret). Test hook: params.simulate_missing_key.
import { addDays, db, errMsg, ingest, killHost, type ObsRow, politeFetch, type Run, serve, stateGet, stateSet } from "./att.ts";
import { mad, median, r4, secret, todayUtc, wrap } from "./wsa.ts";

export const EQUITIES_VERSION = "2026-09-25.q1";

interface Bar { d: string; c: number; v: number }
interface Cfg { etfs: string[]; td_max_symbols: number; td_daily_outputsize: number; bf_from: string; av_symbols: string[]; recent_days: number }
const DEFAULTS: Cfg = {
  etfs: ["SPY", "XLE", "XLU", "XLK", "SMH", "XHB", "XRT", "JETS", "ITB", "KRE", "XLF", "XLV", "XLI", "XLB", "XLP", "XLY", "XLC",
    "XLRE", "IYT", "XOP", "KIE", "IGV", "XME", "PEJ", "ICLN", "TAN", "USO", "UNG", "CIBR", "IBB"],
  td_max_symbols: 60, td_daily_outputsize: 160, bf_from: "2018-06-01", av_symbols: ["XLE", "XLU", "SMH", "JETS", "KRE", "XRT"],
  recent_days: 10,
};
async function cfg(): Promise<Cfg> {
  const { data } = await db.rpc("att_config_get", { p_key: "equities" });
  return { ...DEFAULTS, ...((data ?? {}) as Partial<Cfg>) };
}
const SYM = /^[A-Z][A-Z0-9.\-]{0,9}$/;

// ------------------------------------------------------------------ derived statistics (pure)
function olsBeta(y: number[], x: number[]): { a: number; b: number } {
  const n = y.length, mx = x.reduce((s, v) => s + v, 0) / n, my = y.reduce((s, v) => s + v, 0) / n;
  let sxy = 0, sxx = 0;
  for (let i = 0; i < n; i++) { sxy += (x[i] - mx) * (y[i] - my); sxx += (x[i] - mx) ** 2; }
  const b = sxx > 0 ? sxy / sxx : 1;
  return { a: my - b * mx, b };
}
/** z rows for the last `keep` bars (or all bars from `fromDay`), bars ascending by date. */
export function deriveZ(source: string, sym: string, bars: Bar[], spy: Map<string, number> | null, fromDay: string | null, keep: number): ObsRow[] {
  const out: ObsRow[] = [];
  const lv = bars.map((b) => (b.v > 0 ? Math.log(b.v) : NaN));
  const r = bars.map((b, i) => (i > 0 && bars[i - 1].c > 0 && b.c > 0 ? Math.log(b.c / bars[i - 1].c) : NaN));
  const start = fromDay ? bars.findIndex((b) => b.d >= fromDay) : Math.max(0, bars.length - keep);
  if (start < 0) return out;
  for (let t = Math.max(start, 71); t < bars.length; t++) {
    const d = bars[t].d;
    // abnormal volume
    const base = lv.slice(t - 70, t - 10).filter(Number.isFinite);
    if (base.length >= 40 && Number.isFinite(lv[t])) {
      const m = median(base), s = 1.4826 * mad(base, m);
      if (s > 0) out.push({ source, key: sym, metric: "volz", geo: "US", day: d, value: r4((lv[t] - m) / s), aux: base.length });
    }
    // abnormal return (market model vs SPY)
    if (t >= 131 && Number.isFinite(r[t])) {
      const ys: number[] = [], xs: number[] = [];
      for (let k = t - 130; k < t - 10; k++) {
        const mk = spy?.get(bars[k].d);
        if (!Number.isFinite(r[k])) continue;
        if (spy && sym !== "SPY") { if (mk === undefined || !Number.isFinite(mk)) continue; xs.push(mk); } else xs.push(0);
        ys.push(r[k]);
      }
      if (ys.length < 60) continue;
      const isMkt = !spy || sym === "SPY";
      const { a, b } = isMkt ? { a: 0, b: 0 } : olsBeta(ys, xs);
      const ar = ys.map((y, i) => y - (a + b * xs[i]));
      const m = median(ar), s = 1.4826 * mad(ar, m);
      const mt = isMkt ? 0 : spy!.get(d);
      if (s > 0 && mt !== undefined && Number.isFinite(mt)) {
        out.push({ source, key: sym, metric: "retz", geo: "US", day: d, value: r4((r[t] - (a + b * mt) - m) / s), aux: r4(b) });
      }
    }
  }
  return out;
}

// ------------------------------------------------------------------ Twelve Data
const TD = "https://api.twelvedata.com/time_series";
async function tdSeries(run: Run, key: string, sym: string, size: number, from: string | null): Promise<Bar[] | "stop" | null> {
  const q = new URLSearchParams({ symbol: sym, interval: "1day", outputsize: String(size), order: "ASC", timezone: "America/New_York" });
  if (from) q.set("start_date", from);
  const res = await politeFetch(run, `${TD}?${q}`, { source: "twelvedata", headers: { Authorization: `apikey ${key}`, accept: "application/json" }, timeoutMs: 30_000 });
  if (!res) return "stop";
  const j = await res.json().catch(() => null);
  if (!j) { run.errors.push(`twelvedata ${sym}: bad json`); return null; }
  if (j.status === "error") {
    const code = Number(j.code ?? res.status);
    if (code === 429) { await killHost(run, "api.twelvedata.com", 429, "twelvedata"); return "stop"; }   // quota: stop for the day
    if (code === 401 || code === 403) { await killHost(run, "api.twelvedata.com", code, "twelvedata"); return "stop"; }
    run.errors.push(`twelvedata ${sym}: ${code} ${String(j.message ?? "").slice(0, 120)}`);
    return null;
  }
  const vals = Array.isArray(j.values) ? j.values : [];
  const bars: Bar[] = [];
  for (const v of vals) {
    const d = String(v?.datetime ?? "").slice(0, 10), c = Number(v?.close), vol = Number(v?.volume);
    if (/^\d{4}-\d{2}-\d{2}$/.test(d) && Number.isFinite(c) && Number.isFinite(vol)) bars.push({ d, c, v: vol });
  }
  bars.sort((a, b) => (a.d < b.d ? -1 : a.d > b.d ? 1 : 0));
  return bars;
}
async function symbols(run: Run, c: Cfg): Promise<string[]> {
  const { data, error } = await db.rpc("att_equity_symbols");
  if (error) run.errors.push(`att_equity_symbols: ${error.message}`);
  const mapped = (Array.isArray(data) ? data : []).map(String);
  return [...new Set([...c.etfs, ...mapped].map((s) => s.toUpperCase()).filter((s) => SYM.test(s)))].slice(0, c.td_max_symbols);
}
async function modeTwelve(run: Run, forceBackfill = false) {
  const t0 = Date.now();
  const c = await cfg();
  const key = await secret(run, "twelvedata_api_key");
  if (!key) { run.source({ source: "twelvedata", status: "no_key", note: "Vault secret 'twelvedata_api_key' absent: no request made; collector idle until it exists" }); return; }
  const today = todayUtc();
  const explicit = Array.isArray(run.params.symbols)
    ? run.params.symbols.map((s: unknown) => String(s).toUpperCase()).filter((s: string) => SYM.test(s)) as string[] : null;
  const all = explicit ?? await symbols(run, c);
  const st = ((await stateGet("eq.td").catch(() => null)) ?? {}) as { bf?: Record<string, string>; day?: Record<string, string> };
  const bf = st.bf ?? {}, day = st.day ?? {};
  const order = ["SPY", ...all.filter((s) => s !== "SPY")];
  // A run is either a backfill run (symbols without history; SPY fetched at the same depth) or a daily run.
  const needBf = order.filter((s) => (forceBackfill && explicit) ? true : !bf[s]);
  const bfRun = needBf.length > 0;
  const work = bfRun ? needBf : order.filter((s) => day[s] !== today);
  if (!work.length) { run.source({ source: "twelvedata", status: "ok", note: "all symbols already updated today" }); return; }
  const size = bfRun ? 5000 : c.td_daily_outputsize;
  const from = bfRun ? String(run.params.from ?? c.bf_from) : null;
  let calls = 0, rows = 0, done = 0;
  const failed: string[] = [];
  const spyBars = await tdSeries(run, key, "SPY", size, from);
  calls++;
  if (spyBars === "stop" || !spyBars || spyBars.length < 72) {
    run.partial = true;
    run.extra.twelvedata = { calls, failed: ["SPY"] };
    run.source({ source: "twelvedata", status: "partial", note: "SPY (market model) unavailable", ms: Date.now() - t0 });
    return;
  }
  const spy = new Map(spyBars.map((b, i) => [b.d, i > 0 && spyBars[i - 1].c > 0 ? Math.log(b.c / spyBars[i - 1].c) : NaN]));
  const mark = async (sym: string) => {
    if (bfRun) bf[sym] = today;
    day[sym] = today;
    if (!run.dryRun) await stateSet("eq.td", { bf, day }).catch((e) => run.errors.push(`state: ${errMsg(e)}`));
  };
  const fromZ = bfRun ? addDays(String(from), 1) : null;
  if (work.includes("SPY")) {
    rows += (await ingest(run, deriveZ("twelvedata", "SPY", spyBars, null, fromZ, c.recent_days))).rows;
    done++; await mark("SPY");
  }
  for (const sym of work) {
    if (sym === "SPY") continue;
    if (run.outOfTime(20_000)) { run.partial = true; break; }
    const bars = await tdSeries(run, key, sym, size, from);
    calls++;
    if (bars === "stop") { run.partial = true; break; }
    if (!bars || bars.length < 72) { failed.push(sym); continue; }
    rows += (await ingest(run, deriveZ("twelvedata", sym, bars, spy, fromZ, c.recent_days))).rows;
    done++; await mark(sym);
  }
  const left = bfRun ? order.filter((s) => !bf[s]).length : order.filter((s) => day[s] !== today).length;
  if (left - failed.length > 0) { run.partial = true; run.nextCursor = { left, backfill: bfRun }; }
  run.extra.twelvedata = { symbols: order.length, backfill_run: bfRun, calls, derived_rows: rows, done, failed, left };
  run.source({ source: "twelvedata", status: run.partial ? "partial" : "ok", keys: done, rows, ms: Date.now() - t0 });
}

// ------------------------------------------------------------------ Alpha Vantage
async function modeAlpha(run: Run) {
  const t0 = Date.now();
  const c = await cfg();
  const key = await secret(run, "alphavantage_api_key");
  if (!key) { run.source({ source: "alphavantage", status: "no_key", note: "Vault secret 'alphavantage_api_key' absent: no request made; collector idle until it exists" }); return; }
  const today = todayUtc();
  const st = ((await stateGet("eq.av").catch(() => null)) ?? {}) as Record<string, string>;
  const syms = ["SPY", ...c.av_symbols.map((s) => s.toUpperCase()).filter((s) => SYM.test(s) && s !== "SPY")];
  if (syms.slice(1).every((s) => st[s] === today)) { run.source({ source: "alphavantage", status: "ok", note: "already fetched today" }); return; }
  let spy: Map<string, number> | null = null, rows = 0, calls = 0;
  for (const sym of syms) {
    if (sym !== "SPY" && st[sym] === today) continue;
    if (run.outOfTime(20_000)) { run.partial = true; break; }
    const q = new URLSearchParams({ function: "TIME_SERIES_DAILY", symbol: sym, outputsize: "compact", apikey: key });
    const res = await politeFetch(run, `https://www.alphavantage.co/query?${q}`, { source: "alphavantage", headers: { accept: "application/json" }, timeoutMs: 30_000 });
    calls++;
    if (!res) { run.partial = true; break; }
    const j = await res.json().catch(() => null);
    if (!j || j.Note || j.Information || j["Error Message"]) {
      const msg = String(j?.Note ?? j?.Information ?? j?.["Error Message"] ?? "bad json").slice(0, 160);
      if (j?.Note || j?.Information) { await killHost(run, "www.alphavantage.co", 429, "alphavantage"); run.errors.push(`alphavantage rate/plan note: ${msg}`); break; }
      run.errors.push(`alphavantage ${sym}: ${msg}`);
      continue;
    }
    const ts = j["Time Series (Daily)"] ?? {};
    const bars: Bar[] = Object.entries(ts).map(([d, v]: [string, any]) => ({ d, c: Number(v?.["4. close"]), v: Number(v?.["5. volume"]) }))
      .filter((b) => /^\d{4}-\d{2}-\d{2}$/.test(b.d) && Number.isFinite(b.c) && Number.isFinite(b.v))
      .sort((a, b) => (a.d < b.d ? -1 : 1));
    if (sym === "SPY") { spy = new Map(bars.map((b, i) => [b.d, i > 0 ? Math.log(b.c / bars[i - 1].c) : NaN])); st.SPY = today; continue; }
    // compact = 100 bars: abnormal volume z only (the 130-day market-model window needs more history than compact gives)
    const z = deriveZ("alphavantage", sym, bars, spy, null, c.recent_days).filter((r) => r.metric === "volz");
    rows += (await ingest(run, z)).rows;
    st[sym] = today;
  }
  if (!run.dryRun) await stateSet("eq.av", st).catch(() => undefined);
  run.extra.alphavantage = { calls, derived_rows: rows };
  run.source({ source: "alphavantage", status: run.partial ? "partial" : "ok", keys: syms.length, rows, ms: Date.now() - t0 });
}

serve("att-equities", {
  twelvedata: wrap((r) => modeTwelve(r, false)),
  alphavantage: wrap(modeAlpha),
  backfill: wrap((r) => modeTwelve(r, true)),
  ping: wrap(async (r) => { r.extra.version = EQUITIES_VERSION; }),
});
