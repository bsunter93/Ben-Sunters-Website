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
//
// Compliance gate for the non-Wikimedia hosts of mode "trends" (added 2026-09-25 by the attention compliance audit,
// ATTENTION_STACK §0 hard rules 2 and 3, DEMARCATION §7.3):
//   * robots.txt is checked before trends.google.com / public.api.bsky.app are called (24 h cache in att_state
//     'kn.robots:<origin>'; robots.txt that answers 401/403/429/5xx or cannot be reached = deny);
//   * the shared att kill switch (att_state 'kill:<host>') is honoured;
//   * a 429/503 stops the host for the rest of the run AND the UTC day (att_host_kill), a 401/403 stops it permanently
//     until the owner clears it (no retry after 403). Previously the loop moved on to the next geo on the same host.
import { addDays, Budget, db, kfetch, norm, rpc, serve, sleep, SKIP_TITLE, Stop, UA } from "./kn.ts";

export const COLLECT_GATE_VERSION = "2026-09-25.g1";
const ROBOTS_TOKEN = "knockon";
const ROBOTS_TTL_MS = 24 * 3600 * 1000;
type Rule = [boolean, string];

function parseRobots(txt: string): Rule[] {
  type G = { agents: string[]; rules: Rule[] };
  const groups: G[] = [];
  let cur: G | null = null;
  let lastAgent = false;
  for (const raw of txt.split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, "").trim();
    const i = line.indexOf(":");
    if (!line || i < 0) continue;
    const k = line.slice(0, i).trim().toLowerCase();
    const v = line.slice(i + 1).trim();
    if (k === "user-agent") {
      if (!cur || !lastAgent) { cur = { agents: [], rules: [] }; groups.push(cur); }
      cur.agents.push(v.toLowerCase());
      lastAgent = true;
      continue;
    }
    lastAgent = false;
    if (cur && (k === "allow" || k === "disallow") && v !== "") cur.rules.push([k === "allow", v]);
  }
  const mine = groups.filter((g) => g.agents.some((a) => a !== "*" && a.split("/")[0] === ROBOTS_TOKEN));
  return (mine.length ? mine : groups.filter((g) => g.agents.includes("*"))).flatMap((g) => g.rules);
}
function robotsAllows(rules: Rule[], pathAndQuery: string): boolean {
  let best = -1, allow = true;
  for (const [a, p] of rules) {
    const anchored = p.endsWith("$");
    const body = anchored ? p.slice(0, -1) : p;
    const re = "^" + body.split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*") + (anchored ? "$" : "");
    let hit = false;
    try { hit = new RegExp(re).test(pathAndQuery); } catch { hit = false; }
    if (hit && (p.length > best || (p.length === best && a))) { best = p.length; allow = a; }
  }
  return allow;
}

interface Gate { stopped: Map<string, string>; robots: Map<string, { deny_all: boolean; rules: Rule[] }> }
async function stateGet(k: string): Promise<any> {
  const { data, error } = await db.rpc("att_state_get", { p_k: k });
  if (error) throw new Error(`att_state_get: ${error.message}`);
  return data;
}
async function hostKilled(host: string): Promise<string | null> {
  const k = await stateGet(`kill:${host}`).catch(() => ({ permanent: true, status: 0 })); // unreadable = stop (fail safe)
  if (!k) return null;
  if (k.permanent === true || (k.until && Date.parse(k.until) > Date.now())) return `host_killed_${k.status ?? "?"}`;
  return null;
}
async function killHost(g: Gate, host: string, status: number, source: string) {
  g.stopped.set(host, `stopped_${status}`);
  const reason = status === 401 || status === 403 ? `http_${status}` : null;
  const { error } = await db.rpc("att_host_kill", { p_host: host, p_status: status, p_source: source, p_reason: reason });
  if (error) console.error("att_host_kill failed", host, error.message);
}
async function robotsOk(g: Gate, b: Budget, u: URL): Promise<boolean> {
  let e = g.robots.get(u.origin);
  if (!e) {
    const key = `kn.robots:${u.origin}`;
    const cached = await stateGet(key).catch(() => null);
    if (cached && Date.now() - Number(cached.fetched_at ?? 0) < ROBOTS_TTL_MS) e = cached;
    else {
      let status = 0, entry = { deny_all: true, rules: [] as Rule[] };
      try {
        b.other++;
        const res = await fetch(`${u.origin}/robots.txt`, { headers: { "User-Agent": UA }, redirect: "manual", signal: AbortSignal.timeout(10_000) });
        status = res.status;
        if (res.ok) entry = { deny_all: false, rules: parseRobots((await res.text()).slice(0, 512_000)) };
        else {
          await res.body?.cancel();
          // no robots.txt (404/410/other 4xx) = allowed; 401/403/429/3xx/5xx = deny (DEMARCATION Q3)
          entry = { deny_all: !(status >= 400 && status < 500 && ![401, 403, 429].includes(status)), rules: [] };
        }
      } catch (_e) { entry = { deny_all: true, rules: [] }; }
      e = entry;
      const { error } = await db.rpc("att_state_set", { p_k: key, p_v: { ...entry, status, fetched_at: Date.now() } });
      if (error) console.error("att_state_set failed", key, error.message);
    }
    g.robots.set(u.origin, e!);
  }
  return !e!.deny_all && robotsAllows(e!.rules, u.pathname + u.search);
}
/** kfetch for a non-Wikimedia host with robots, kill switch and stop rules. null = not fetched / host stopped. */
async function gatedFetch(g: Gate, b: Budget, url: string, source: string): Promise<{ res: Response | null; why?: string }> {
  const u = new URL(url);
  const host = u.hostname.toLowerCase();
  if (g.stopped.has(host)) return { res: null, why: g.stopped.get(host) };
  const killed = await hostKilled(host);
  if (killed) { g.stopped.set(host, killed); return { res: null, why: killed }; }
  if (!(await robotsOk(g, b, u))) { g.stopped.set(host, "robots_disallow"); return { res: null, why: "robots_disallow" }; }
  let res: Response;
  try { res = await kfetch(b, url); } catch (e) {
    if (e instanceof Stop) {
      const m = String(e.message).match(/\b(429|503)\b/);
      await killHost(g, host, m ? Number(m[1]) : 429, source);
      return { res: null, why: g.stopped.get(host) };
    }
    throw e;
  }
  if (res.status === 401 || res.status === 403) {
    await res.body?.cancel();
    await killHost(g, host, res.status, source);
    return { res: null, why: g.stopped.get(host) };
  }
  if (res.redirected) {
    // a redirect off the host, or to a login / consent / "sorry" page, is a barrier (DEMARCATION Q2): stop permanently
    const f = new URL(res.url);
    const barrier = /(^|\/)(login|signin|sign-in|accounts?|consent|sorry|captcha|challenge)(\/|$|\?|\.)/i.test(f.pathname) ||
      /^(accounts|consent|login|signin)\./i.test(f.hostname);
    if (barrier || f.hostname.toLowerCase() !== host) {
      await res.body?.cancel();
      if (barrier) await killHost(g, host, 403, source); else g.stopped.set(host, "cross_host_redirect");
      return { res: null, why: barrier ? "redirect_to_barrier" : "cross_host_redirect" };
    }
  }
  return { res };
}

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
  const g: Gate = { stopped: new Map(), robots: new Map() };
  out.gate = COLLECT_GATE_VERSION;
  let first = true;
  for (const [geo, lang] of Object.entries(RSS_GEOS)) {
    if (g.stopped.has("trends.google.com")) { out[geo] = `skipped: ${g.stopped.get("trends.google.com")}`; continue; }
    if (!first) await sleep(1000);            // serial, 1 request/s
    first = false;
    try {
      const { res, why } = await gatedFetch(g, b, `https://trends.google.com/trending/rss?geo=${geo}`, "gt.rss");
      if (!res) { out[geo] = `skipped: ${why}`; continue; }
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
    const { res, why } = await gatedFetch(g, b, "https://public.api.bsky.app/xrpc/app.bsky.unspecced.getTrends?limit=25", "bsky.trends");
    if (!res) out.bsky = `skipped: ${why}`;
    else if (res.ok) {
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
