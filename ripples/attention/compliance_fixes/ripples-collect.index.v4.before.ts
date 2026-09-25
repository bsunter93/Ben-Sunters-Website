// ripples-collect (Knock-On v5 / W2). verify_jwt = false; gated by x-collector-token.
//  {"mode":"trends"}                 hourly: Google Trends RSS for 8 geos (serial, 1 request/s) + Bluesky getTrends
//  {"mode":"daily","date":"YYYY-MM-DD","job":{...}}
//                                    06:10 stage collect_daily: Wikimedia top-per-country (10 countries) for `date`
//                                    (= as_of; a country whose list is still 404 falls back to as_of-1) and
//                                    feed/featured for as_of and as_of+1 ("yesterday and today").
//                                    The Google Trends "Trending Now" internal endpoint is NOT called: DEMARCATION
//                                    §7.2 graded it RED, so it is always skipped (RSS is the official path).
//  {"mode":"date","date":"YYYY-MM-DD","job":{...}}
//                                    backfill: top-per-country + per-project top (10 languages) for the date and
//                                    feed/featured for date and date+1. No Google, no Bluesky.
import { addDays, Budget, kfetch, norm, rpc, serve, sleep, SKIP_TITLE } from "./kn.ts";

const RSS_GEOS: Record<string, string> = { US: "en", GB: "en", IN: "en", BR: "pt", DE: "de", JP: "ja", MX: "es", NG: "en" };
const COUNTRIES = ["US", "GB", "IN", "CA", "AU", "DE", "FR", "BR", "MX", "JP"];
const PROJECTS = ["en", "es", "de", "fr", "ja", "pt", "it", "ru", "zh", "hi"];
const KEEP_RANK = 200;

const ent = (s: string) => s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
  .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
  .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
  .replace(/&amp;/g, "&").trim();
const tag = (x: string, t: string) => { const m = x.match(new RegExp(`<${t}>([\\s\\S]*?)</${t}>`)); return m ? ent(m[1]) : null; };

async function trends(b: Budget) {
  const rows: any[] = [];
  const out: Record<string, unknown> = {};
  const today = new Date().toISOString().slice(0, 10);
  let first = true;
  for (const [geo, lang] of Object.entries(RSS_GEOS)) {
    if (!first) await sleep(1000);            // serial, 1 request/s
    first = false;
    try {
      const res = await kfetch(b, `https://trends.google.com/trending/rss?geo=${geo}`);
      if (!res.ok) { out[geo] = `http ${res.status}`; await res.body?.cancel(); continue; }
      const xml = await res.text();
      const items = xml.split("<item>").slice(1).map((s) => s.split("</item>")[0]);
      items.forEach((it, i) => {
        const q = tag(it, "title");
        if (!q) return;
        const traffic = Number((tag(it, "ht:approx_traffic") ?? "").replace(/[^0-9]/g, "")) || null;
        const pub = tag(it, "pubDate");
        const day = pub && !isNaN(Date.parse(pub)) ? new Date(Date.parse(pub)).toISOString().slice(0, 10) : today;
        const news = it.split("<ht:news_item>").slice(1).map((n) => ({
          title: tag(n, "ht:news_item_title"), source: tag(n, "ht:news_item_source"), url: tag(n, "ht:news_item_url"),
        })).filter((n) => n.title && n.url && /^https:\/\//.test(n.url)).slice(0, 3);
        rows.push({ day, source: "gtrends", geo, lang, query: q.slice(0, 300), traffic, rank: i + 1, news });
      });
      out[geo] = items.length;
    } catch (e) { out[geo] = "error: " + (e instanceof Error ? e.message : String(e)); }
  }
  try {
    await sleep(1000);
    const res = await kfetch(b, "https://public.api.bsky.app/xrpc/app.bsky.unspecced.getTrends?limit=25");
    if (res.ok) {
      const j = await res.json();
      (j.trends ?? []).forEach((t: any, i: number) => {
        const q = String(t.displayName ?? t.topic ?? "").trim();
        if (q) rows.push({ day: today, source: "bsky", geo: null, lang: null, query: q.slice(0, 300), traffic: Number(t.postCount) || null, rank: i + 1, news: null });
      });
      out.bsky = (j.trends ?? []).length;
    } else { out.bsky = `http ${res.status}`; await res.body?.cancel(); }
  } catch (e) { out.bsky = "error: " + (e instanceof Error ? e.message : String(e)); }
  const inserted = rows.length ? await rpc("ripples_ingest_trends", { p_rows: rows }) : 0;
  return { mode: "trends", inserted, sources: out };
}

function wikiRows(arts: any[], source: string, geo: string, day: string, projectFilter?: string) {
  const rows: any[] = [];
  for (const a of arts) {
    const proj: string = a.project ?? projectFilter ?? "";
    const m = proj.match(/^([a-z-]+)\.wikipedia$/);
    if (!m) continue;
    const title = norm(String(a.article ?? ""));
    if (!title || SKIP_TITLE.test(title) || SKIP_TITLE.test(String(a.article))) continue;
    if (rows.length >= KEEP_RANK) break;
    rows.push({ day, source, geo, lang: m[1], query: title, traffic: a.views_ceil ?? a.views ?? null, rank: rows.length + 1, news: null });
  }
  return rows;
}

async function featured(b: Budget, date: string, rows: any[], out: Record<string, unknown>) {
  const [y, mo, d] = date.split("-");
  const res = await kfetch(b, `https://api.wikimedia.org/feed/v1/wikipedia/en/featured/${y}/${mo}/${d}`);
  if (!res.ok) { out[`featured ${date}`] = `http ${res.status}`; await res.body?.cancel(); return; }
  const j = await res.json();
  const push = (section: string, day: string, title: unknown, rank: number, traffic: number | null = null) => {
    const t = norm(String(title ?? ""));
    if (t && !SKIP_TITLE.test(t)) rows.push({ day, source: "featured", geo: section, lang: "en", query: t, traffic, rank, news: null });
  };
  let n = 0;
  if (j.tfa?.titles?.normalized || j.tfa?.title) { push("tfa", date, j.tfa.titles?.normalized ?? j.tfa.title, 1); n++; }
  const mrDay = (j.mostread?.date ?? "").slice(0, 10) || addDays(date, -1);
  (j.mostread?.articles ?? []).forEach((a: any, i: number) => { push("mostread", mrDay, a.titles?.normalized ?? a.title, i + 1, a.views ?? null); n++; });
  let r = 0;
  for (const item of j.news ?? []) for (const l of item.links ?? []) { push("news", date, l.titles?.normalized ?? l.title, ++r); n++; }
  r = 0;
  for (const ev of j.onthisday ?? []) for (const p of ev.pages ?? []) { push("onthisday", date, p.titles?.normalized ?? p.title, ++r); n++; }
  r = 0;
  for (const it of j.dyk ?? []) { const t = it.title ?? it.titles?.normalized; if (t) { push("dyk", date, t, ++r); n++; } }
  out[`featured ${date}`] = n;
}

async function daily(b: Budget, date: string, backfill: boolean, trendingNow: boolean) {
  const rows: any[] = [];
  const out: Record<string, unknown> = {};
  const [y, mo, d] = date.split("-");
  // Google Trends "Trending Now" internal RPC: RED under DEMARCATION §7.2 -> never called; RSS is the official path.
  out.trending_now = backfill ? "skipped (backfill)" : `skipped (RED under DEMARCATION §7.2; flag=${trendingNow})`;
  for (const c of COUNTRIES) {
    try {
      let day = date;
      let res = await kfetch(b, `https://wikimedia.org/api/rest_v1/metrics/pageviews/top-per-country/${c}/all-access/${y}/${mo}/${d}`, {}, { aqs: true });
      if (res.status === 404 && !backfill) {
        // live 06:10: some countries' lists for yesterday are published late. Fall back to the day before (still inside
        // the 3-day seed window, SPEC 5.2); the per-project lists (public.wiki_top) and the featured feed cover the rest.
        await res.body?.cancel();
        day = addDays(date, -1);
        const [y2, m2, d2] = day.split("-");
        res = await kfetch(b, `https://wikimedia.org/api/rest_v1/metrics/pageviews/top-per-country/${c}/all-access/${y2}/${m2}/${d2}`, {}, { aqs: true });
      }
      if (!res.ok) { out[c] = `http ${res.status}`; await res.body?.cancel(); continue; }
      const j = await res.json();
      const r = wikiRows(j.items?.[0]?.articles ?? [], "topcountry", c, day);
      rows.push(...r);
      out[c] = r.length;
      if (day !== date) out[`${c} day`] = day;
    } catch (e) { out[c] = "error: " + (e instanceof Error ? e.message : String(e)); if (b.stopped) break; }
  }
  if (backfill) {
    for (const p of PROJECTS) {
      try {
        const res = await kfetch(b, `https://wikimedia.org/api/rest_v1/metrics/pageviews/top/${p}.wikipedia/all-access/${y}/${mo}/${d}`, {}, { aqs: true });
        if (!res.ok) { out[`top ${p}`] = `http ${res.status}`; await res.body?.cancel(); continue; }
        const j = await res.json();
        const r = wikiRows(j.items?.[0]?.articles ?? [], "wikitop", p, date, `${p}.wikipedia`);
        rows.push(...r);
        out[`top ${p}`] = r.length;
      } catch (e) { out[`top ${p}`] = "error: " + (e instanceof Error ? e.message : String(e)); if (b.stopped) break; }
    }
  }
  for (const fd of [date, addDays(date, 1)]) {
    try { await featured(b, fd, rows, out); } catch (e) { out[`featured ${fd}`] = "error: " + (e instanceof Error ? e.message : String(e)); }
  }
  let inserted = 0;
  for (let i = 0; i < rows.length; i += 1000) inserted += Number(await rpc("ripples_ingest_trends", { p_rows: rows.slice(i, i + 1000) }));
  const wikiOk = COUNTRIES.some((c) => typeof out[c] === "number" && (out[c] as number) > 0);
  if (!wikiOk) throw new Error("no top-per-country list for " + date + ": " + JSON.stringify(out).slice(0, 300));
  return { mode: backfill ? "date" : "daily", date, inserted, sources: out };
}

serve(async (body, b) => {
  const mode = String(body?.mode ?? "trends");
  if (mode === "trends") return await trends(b);
  const date = String(body?.date ?? new Date(Date.now() - 86400000).toISOString().slice(0, 10));
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("bad date");
  return await daily(b, date, mode === "date", body?.trending_now === true);
});
