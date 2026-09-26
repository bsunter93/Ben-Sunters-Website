// att-youtube — Ripple Map attention layer: YouTube Data API v3 daily mostPopular charts (CONS channel).
// Documented keyed API only (videos.list, chart=mostPopular): 1 unit/call. Serial requests, honest UA (via att.ts
// politeFetch: robots.txt, host kill switch, budgets, spacing). Stops on 429/403-quotaExceeded/503 for the rest of
// the run (politeFetch's own kill-switch handles this: a 429/403/503 kills the host and every further call in this
// run reports source_disabled/host_killed, never retried).
//
// YouTube API Services Terms ("cached data" rule): raw per-video numbers (view counts) must be refreshed or deleted
// within 30 days. This collector never writes a per-video row to a table at all -- the only raw cache is two
// ripples.att_state rows ('yt.raw.curr' / 'yt.raw.prev'), rotated once per UTC day, so the oldest raw number on disk
// is always < 48h old. Everything kept beyond that is a DERIVED aggregate (view-sum, median velocity, entrant
// count, topic-hit count) written through att_ingest like any other source. No personal data of any kind is read or
// stored (no commenter/viewer identity); video/channel titles are read only in memory for topic matching and topic
// keyword screening, and are never persisted.
//
// Modes:
//   collect  For each of ~40 regionCode x 7 videoCategoryId combos (category '0' = omit videoCategoryId, i.e. the
//            general chart), one videos.list call (part=snippet,statistics, maxResults=50, a `fields` filter to
//            keep the response small). Resumable within the UTC day via att_state 'yt.day' (done combos + the raw
//            id->viewCount cache); a run picks up where the last one left off, so three same-day cron slots always
//            finish the full pass even if one run is slow or partial.
//            Per combo, derived and ingested (source yt.api, geo = regionCode, key = "<region>|<category>"):
//              views_top50     sum of viewCount over the up to 50 chart videos (aux = video count)
//              entrants        count of today's video ids absent from yesterday's snapshot of the same combo
//              velocity_median median view gain (today - yesterday) over ids present in BOTH snapshots
//                              (only when >= 5 matched ids; aux = matched count)
//            Category '0' (general chart) responses are also matched, in memory only, against the small
//            active+in_panel topic panel (ripples.att_yt_topics): per topic, a running count of how many distinct
//            (region, video) chart entries today match its label (word-boundary, case-insensitive) is kept in
//            att_state 'yt.topic.day' and ingested as metric topic_hits (geo GLOBAL, topic_id set).
//   peek     One videos.list call (params.region default US, params.category default '0'); reports status and a
//            scrubbed sample without writing anything. For endpoint / key verification.
//   ping     No requests.
import { db, errMsg, ingest, type ObsRow, type Run, serve, stateGet, stateSet } from "./att.ts";
import { getJson, median, r4, scrubStr, secret, todayUtc, wrap } from "./wsa.ts";

export const YOUTUBE_VERSION = "2026-09-26.a1";

const YT_API = "https://www.googleapis.com/youtube/v3/videos";
const SOURCE = "yt.api";

// 40 regionCode values with a meaningful YouTube "trending" chart, spanning every populated continent.
const REGIONS = [
  "US", "GB", "CA", "AU", "NZ", "IE", "DE", "FR", "IT", "ES", "PT", "NL", "BE", "SE", "NO", "DK", "FI", "PL", "AT",
  "CH", "GR", "TR", "IL", "SA", "AE", "EG", "ZA", "NG", "IN", "ID", "PH", "TH", "VN", "MY", "TW", "HK", "KR", "JP",
  "BR", "MX",
];
// videoCategoryId -> label. "0" = omit videoCategoryId entirely (the general/"all" chart).
const CATEGORIES: Record<string, string> = {
  "0": "all", "10": "Music", "20": "Gaming", "24": "Entertainment", "25": "News & Politics",
  "28": "Science & Technology", "17": "Sports",
};
interface Cfg { regions: string[]; categories: Record<string, string> }
async function cfg(): Promise<Cfg> {
  const { data } = await db.rpc("att_config_get", { p_key: "youtube" });
  const c = (data ?? {}) as Partial<Cfg>;
  return { regions: Array.isArray(c.regions) && c.regions.length ? c.regions : REGIONS,
    categories: c.categories && Object.keys(c.categories).length ? c.categories : CATEGORIES };
}

interface DayState { day: string; done: string[]; raw: Record<string, Record<string, number>> }
async function loadDay(run: Run): Promise<{ cur: DayState; prev: { day: string; raw: Record<string, Record<string, number>> } }> {
  const today = todayUtc();
  let cur = (await stateGet("yt.day").catch(() => null)) as DayState | null;
  const prevStored = (await stateGet("yt.raw.prev").catch(() => null)) as { day: string; raw: Record<string, Record<string, number>> } | null;
  let prev = prevStored ?? { day: "", raw: {} };
  if (!cur || cur.day !== today) {
    if (cur?.day && cur.day !== today) {
      prev = { day: cur.day, raw: cur.raw };
      if (!run.dryRun) await stateSet("yt.raw.prev", prev).catch((e) => run.errors.push(`state yt.raw.prev: ${errMsg(e)}`));
    }
    cur = { day: today, done: [], raw: {} };
  }
  return { cur, prev };
}
async function saveDay(run: Run, cur: DayState) {
  if (!run.dryRun) await stateSet("yt.day", cur).catch((e) => run.errors.push(`state yt.day: ${errMsg(e)}`));
}

function noKey(run: Run) {
  run.source({ source: SOURCE, status: "no_key", note: "Vault secret 'youtube_api_key' is absent: nothing requested (collector stays idle until it exists)" });
}
interface Item { id: string; title: string; views: number | null }
function itemsOf(j: any): Item[] {
  const out: Item[] = [];
  for (const it of Array.isArray(j?.items) ? j.items : []) {
    const id = String(it?.id ?? "");
    if (!/^[A-Za-z0-9_-]{5,20}$/.test(id)) continue;
    const v = Number(it?.statistics?.viewCount);
    out.push({ id, title: String(it?.snippet?.title ?? ""), views: Number.isFinite(v) ? v : null });
  }
  return out;
}
async function chartCall(run: Run, key: string, region: string, catId: string): Promise<Item[] | null> {
  const q = new URLSearchParams({
    part: "snippet,statistics", chart: "mostPopular", regionCode: region, maxResults: "50", key,
    fields: "items(id,snippet(title,categoryId),statistics(viewCount))",
  });
  if (catId !== "0") q.set("videoCategoryId", catId);
  const j = await getJson(run, SOURCE, `${YT_API}?${q}`);
  if (j === null) return null;
  return itemsOf(j);
}

// ------------------------------------------------------------------ topic matching (in-memory only; never stores titles)
interface Topic { topic_id: number; label: string; label_key: string; re: RegExp }
function escapeRe(s: string) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
let topicsCache: { at: number; list: Topic[] } | null = null;
async function loadTopics(run: Run): Promise<Topic[]> {
  if (topicsCache && Date.now() - topicsCache.at < 3600_000) return topicsCache.list;
  const { data, error } = await db.rpc("att_yt_topics", { p_limit: 300 });
  if (error) { run.errors.push(`att_yt_topics: ${error.message}`); return topicsCache?.list ?? []; }
  const list: Topic[] = (Array.isArray(data) ? data : []).map((t: any) => ({
    topic_id: Number(t.topic_id), label: String(t.label), label_key: String(t.label_key),
    re: new RegExp(`\\b${escapeRe(String(t.label))}\\b`, "i"),
  })).filter((t) => t.label.length >= 3);
  topicsCache = { at: Date.now(), list };
  return list;
}
async function matchTopics(run: Run, titles: string[], counts: Record<string, number>) {
  const topics = await loadTopics(run);
  if (!topics.length || !titles.length) return;
  for (const t of topics) {
    let n = 0;
    for (const title of titles) if (t.re.test(title)) n++;
    if (n > 0) counts[t.label_key] = (counts[t.label_key] ?? 0) + n;
  }
}
interface TopicDay { day: string; counts: Record<string, number> }
async function loadTopicDay(today: string): Promise<TopicDay> {
  const s = (await stateGet("yt.topic.day").catch(() => null)) as TopicDay | null;
  return s && s.day === today ? s : { day: today, counts: {} };
}

// ------------------------------------------------------------------ collect
async function modeCollect(run: Run) {
  const t0 = Date.now();
  const key = await secret(run, "youtube_api_key");
  if (!key) return noKey(run);
  const c = await cfg();
  const { cur, prev } = await loadDay(run);
  const doneSet = new Set(cur.done);
  const today = cur.day;
  const topicDay = await loadTopicDay(today);
  let rows = 0, combos = 0, fails = 0;
  let sinceSave = 0;
  for (const catId of Object.keys(c.categories)) {
    for (const region of c.regions) {
      const comboKey = `${region}|${catId}`;
      if (doneSet.has(comboKey) && run.params.force !== true) continue;
      if (run.outOfTime(8000)) { run.partial = true; break; }
      if (run.skipped.some((x) => x.host === "www.googleapis.com")) { run.partial = true; break; } // kill/budget: stop
      const items = await chartCall(run, key, region, catId);
      combos++;
      if (items === null) { fails++; continue; }

      const prevRaw = prev.raw[comboKey];
      const out: ObsRow[] = [];
      let totalViews = 0, nViews = 0;
      const nowMap: Record<string, number> = {};
      for (const it of items) { if (it.views !== null) { nowMap[it.id] = it.views; totalViews += it.views; nViews++; } }
      if (nViews) out.push({ source: SOURCE, key: comboKey, metric: "views_top50", geo: region, day: today, value: totalViews, aux: nViews });
      if (prevRaw) {
        let entrants = 0;
        const gains: number[] = [];
        for (const [id, v] of Object.entries(nowMap)) {
          if (!(id in prevRaw)) { entrants++; continue; }
          const gain = v - prevRaw[id];
          if (gain >= 0) gains.push(gain);
        }
        out.push({ source: SOURCE, key: comboKey, metric: "entrants", geo: region, day: today, value: entrants, aux: Object.keys(nowMap).length });
        if (gains.length >= 5) out.push({ source: SOURCE, key: comboKey, metric: "velocity_median", geo: region, day: today, value: r4(median(gains)), aux: gains.length });
      }
      rows += (await ingest(run, out)).rows;
      cur.raw[comboKey] = nowMap;
      cur.done.push(comboKey);
      doneSet.add(comboKey);
      sinceSave++;

      if (catId === "0") {
        const titles = items.map((it) => it.title).filter(Boolean);
        await matchTopics(run, titles, topicDay.counts);
      }
      if (sinceSave >= 5) { await saveDay(run, cur); sinceSave = 0; }
    }
    if (run.outOfTime(8000) || run.skipped.some((x) => x.host === "www.googleapis.com")) break;
  }
  await saveDay(run, cur);
  if (!run.dryRun) await stateSet("yt.topic.day", topicDay).catch((e) => run.errors.push(`state yt.topic.day: ${errMsg(e)}`));
  const topicRows: ObsRow[] = Object.entries(topicDay.counts).map(([label_key, n]) => {
    const t = topicsCache?.list.find((x) => x.label_key === label_key);
    return { source: SOURCE, key: label_key, metric: "topic_hits", geo: "GLOBAL", day: today, value: n, topic_id: t?.topic_id ?? null };
  });
  rows += (await ingest(run, topicRows)).rows;

  const total = Object.keys(c.categories).length * c.regions.length;
  const left = total - cur.done.length;
  if (left > 0) { run.partial = true; run.nextCursor = { source: SOURCE, combos_left: left }; }
  run.extra.youtube = { combos_this_run: combos, fails, done_today: cur.done.length, total, left, topics_matched: Object.keys(topicDay.counts).length };
  run.source({ source: SOURCE, status: fails && !combos ? "http_error" : run.partial ? "partial" : "ok", keys: combos, rows, ms: Date.now() - t0 });
}

async function modePeek(run: Run) {
  const key = await secret(run, "youtube_api_key");
  if (!key) return noKey(run);
  const region = typeof run.params.region === "string" ? run.params.region.toUpperCase() : "US";
  const catId = typeof run.params.category === "string" ? run.params.category : "0";
  const items = await chartCall(run, key, region, catId);
  run.extra.peek = items === null
    ? { made: false }
    : { region, category: catId, n: items.length, sample: items.slice(0, 5).map((it) => ({ id: it.id, title: scrubStr(it.title.slice(0, 80)), views: it.views })) };
}

serve("att-youtube", {
  collect: wrap(modeCollect),
  peek: wrap(modePeek),
  ping: wrap(async (r) => { r.extra.version = YOUTUBE_VERSION; }),
});
