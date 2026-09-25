// Mock test suite for att-wiki (fake fetch + in-memory RPC stub). Run: node --experimental-transform-types test.mts
import { gzipSync } from "node:zlib";
let handler: ((req: Request) => Promise<Response>) | null = null;
(globalThis as any).Deno = { env: { get: () => "http://x" }, serve: (h: any) => { handler = h; } };
const S: any = await import("./stub.mts");
await import("./index.mts");
const A: any = await import("./att.mts");

type H = (url: string, init: any) => Response | Promise<Response>;
const log: Array<{ url: string; t: number; method: string; headers: Record<string, string> }> = [];
let route: H = () => new Response("", { status: 404 });
(globalThis as any).fetch = async (u: any, init: any) => {
  const url = String(u);
  log.push({ url, t: Date.now(), method: String(init?.method ?? "GET"), headers: Object.fromEntries(new Headers(init?.headers ?? {}).entries()) });
  return route(url, init);
};
const results: Array<[string, boolean, string]> = [];
const check = (name: string, ok: boolean, info = "") => { results.push([name, ok, info]); };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });

const base = { enabled: true, grade: "green", per_day_cap: null, budget_bucket: "wikimedia", robots_required: false, reason: null, needs_secret: null, value_kind: "count", grain: "day" };
function resetSources(spacing = 1000) {
  S.sources["wiki.topcc"] = { ...base, source: "wiki.topcc", per_run_cap: 60, spacing_ms: spacing, hosts: ["wikimedia.org"], value_kind: "rank" };
  S.sources["wiki.pv"] = { ...base, source: "wiki.pv", per_run_cap: 200, spacing_ms: spacing, hosts: ["wikimedia.org"] };
  S.sources["wiki.media"] = { ...base, source: "wiki.media", per_run_cap: 150, spacing_ms: spacing, hosts: ["wikimedia.org", "wikipedia.org"] };
  S.sources["wiki.cs"] = { ...base, source: "wiki.cs", per_run_cap: 3, spacing_ms: 100, hosts: ["dumps.wikimedia.org"], robots_required: true };
}
function reset(budget = 1500, spacing = 1000) {
  for (const k of Object.keys(S.state)) delete S.state[k];
  for (const o of [S.taken, S.refunded, S.rpcData]) for (const k of Object.keys(o)) delete o[k];
  for (const a of [S.ingested, S.cands, S.edges, S.jobsDone, S.calls, log]) a.length = 0;
  S.budgets.wikimedia = budget;
  S.config.wm_quiet_utc = null; S.config.contact_gate = { enabled: false };
  S.config.wiki = { countries: ["US", "GB", "DE", "JP", "XX"], topcc_max_tries: 3, topcc_hist_days: 3, topcc_cand_max_rank: 200,
    topcc_cand_min_ratio: 2, pv_days: 420, pv_max_articles: 400, media_day_cap: 200, cs_wikis: ["ptwiki"], cs_max_mb: 8 };
  resetSources(spacing);
}
async function call(body: any) {
  const res = await handler!(new Request("http://x/att-wiki", { method: "POST", headers: { "x-collector-token": "t" }, body: JSON.stringify(body) }));
  return await res.json();
}
const wmCalls = () => log.filter((l) => /(^https:\/\/wikimedia\.org\/|wikipedia\.org\/w\/api\.php)/.test(l.url));
const budgetOk = () => (S.taken.wikimedia ?? 0) - (S.refunded.wikimedia ?? 0) === wmCalls().length;

// ------------------------------------------------------------ fixtures
const DAY = "2026-09-24";
function topList(cc: string) {
  const arts: any[] = [];
  const special: Record<number, [string, string]> = {
    1: ["Main_Page", "en.wikipedia"], 3: ["Spike_X", "en.wikipedia"], 4: ["Registry_A", "en.wikipedia"],
    6: ["東京", "ja.wikipedia"], 7: ["List_of_things", "en.wikipedia"], 8: ["Evergreen_Y", "en.wikipedia"], 9: ["Some_File", "commons.wikimedia"],
  };
  for (let r = 1; r <= 1000; r++) {
    const [a, p] = special[r] ?? [`T_${cc}_${r}`, "en.wikipedia"];
    arts.push({ article: a, project: p, views_ceil: Math.round(200000 / r) + 100, rank: r });
  }
  return { items: [{ country: cc, access: "all-access", year: "2026", month: "09", day: "24", articles: arts }] };
}
const prevSnap = (cc: string) => ({ thr: 300, t: ["en|Main_Page", "en|Evergreen_Y", "en|Registry_A", `en|T_${cc}_2`], v: [190000, 26000, 40000, 100000] });

// ============================================================ 1. top_country
{
  reset();
  S.rpcData.att_watchlist = () => [{ key: "Registry_A", geo: "en.wikipedia", metric: "n", match: {}, series_id: null, topic_id: 11, key_type: "title" },
                                   { key: "東京", geo: "ja.wikipedia", metric: "n", match: {}, series_id: null, topic_id: 12, key_type: "title" }];
  S.rpcData.att_wiki_topcc_prev = (a: any) => ["US", "GB", "DE", "JP"].flatMap((cc) => [1, 2, 3].map((k) => ({ cc, day: `2026-09-2${4 - k}`, v: prevSnap(cc) })));
  let reachArgs: any = null;
  S.rpcData.att_wiki_topcc_reach = (a: any) => { reachArgs = a; return { rows: 2 }; };
  route = (u) => {
    const m = /top-per-country\/([A-Z]{2})\/all-access\/2026\/09\/24$/.exec(u);
    if (m && m[1] !== "XX") return json(topList(m[1]));
    return json({ type: "not found" }, 404);
  };
  const out = await call({ mode: "top_country", as_of: DAY });
  const tc = log.filter((l) => l.url.includes("top-per-country"));
  const gaps = tc.slice(1).map((l, i) => l.t - tc[i].t);
  check("topcc: 5 countries requested, serial, >= 1 s apart", tc.length === 5 && gaps.every((g) => g >= 990), `n=${tc.length} gaps=${gaps.join(",")}`);
  check("topcc: honest UA + Api-User-Agent, no robots on AQS", tc.every((l) => l.headers["user-agent"] === A.UA && l.headers["api-user-agent"] === A.UA) && !log.some((l) => l.url.endsWith("robots.txt")));
  const rk = S.ingested.filter((r: any) => r.source === "wiki.topcc");
  check("topcc: rank rows only for registry titles (4 countries x 2)", rk.length === 8 && rk.every((r: any) => r.metric === "rank" && ["en:Registry_A", "ja:東京"].includes(r.key) && r.aux > 0 && r.topic_id),
    JSON.stringify(rk.slice(0, 2)));
  check("topcc: rank value + geo = country", rk.some((r: any) => r.key === "en:Registry_A" && r.value === 4 && r.geo === "US" && r.day === DAY));
  const labels = new Set(S.cands.map((c: any) => c.label));
  check("topcc: spike is a candidate (new, ratio >= 2)", labels.has("Spike X") && S.cands.find((c: any) => c.label === "Spike X").meta.new === true);
  check("topcc: evergreen / main page / list / non-wikipedia excluded", !labels.has("Evergreen Y") && !labels.has("Main Page") && !labels.has("List of things") && !labels.has("Some File") && !labels.has("Registry A"),
    [...labels].slice(0, 8).join("|"));
  check("topcc: candidate evidence in [0,1], geo per country, rank <= 200", S.cands.every((c: any) => c.evidence >= 0 && c.evidence <= 1 && /^[A-Z]{2}$/.test(c.geo) && c.rank <= 200));
  check("topcc: snapshot saved per country", ["US", "GB", "DE", "JP"].every((cc) => S.state[`topcc.snap:${cc}:${DAY}`]?.t?.length === 999) && S.state[`topcc.snap:US:${DAY}`].thr === 300);
  check("topcc: reach computed with coverage 4", reachArgs?.p_coverage === 4 && reachArgs?.p_day === DAY);
  check("topcc: 404 country recorded unavailable, run partial with cursor", S.state[`topcc.day:${DAY}`].unavailable.XX === 1 && out.partial === true && out.next_cursor?.countries?.[0] === "XX");
  check("topcc: budget charged = requests made (unspent refunded)", budgetOk(), `taken=${S.taken.wikimedia} refunded=${S.refunded.wikimedia} calls=${wmCalls().length}`);
  check("topcc: extra.wikimedia_calls", out.wikimedia_calls === 5 && out.countries_done === 4, JSON.stringify({ c: out.wikimedia_calls, d: out.countries_done }));
  // second run: only the unavailable country is retried
  log.length = 0;
  const out2 = await call({ mode: "top_country", as_of: DAY });
  check("topcc: resume retries only missing countries", log.filter((l) => l.url.includes("top-per-country")).length === 1 && out2.countries_done === 4);
  // day 1 without history: no candidates
  reset(); S.rpcData.att_watchlist = () => []; S.rpcData.att_wiki_topcc_prev = () => [];
  route = (u) => json(topList("US"));
  S.config.wiki.countries = ["US"];
  const out3 = await call({ mode: "top_country", as_of: DAY });
  check("topcc: no prior snapshot -> no candidates (evergreen filter needs history)", S.cands.length === 0 && out3.candidates_no_history > 0);
}

// ============================================================ 2. guards: quiet window, kill, contact gate, budget
{
  reset(); S.config.wm_quiet_utc = { from: "00:00", to: "23:59" };
  S.rpcData.att_watchlist = () => []; route = (u) => json(topList("US"));
  const o = await call({ mode: "top_country", as_of: DAY });
  check("quiet window: no Wikimedia request, stop reason", wmCalls().length === 0 && o.stop === "wm_quiet_window" && (S.taken.wikimedia ?? 0) === 0, JSON.stringify(o.skipped));
}
{
  reset(); S.state["kill:wikimedia.org"] = { status: 429, until: new Date(Date.now() + 3600e3).toISOString() };
  S.rpcData.att_watchlist = () => []; route = (u) => json(topList("US"));
  const o = await call({ mode: "top_country", as_of: DAY });
  check("kill switch (429 earlier today): no request", wmCalls().length === 0 && /^host_killed_429/.test(o.stop ?? ""), o.stop);
}
{
  reset(); S.config.contact_gate = { enabled: true, url: "https://bensunter.com/ripples/methods/", scope: "wikimedia", ttl_ok_h: 24, ttl_fail_h: 1 };
  S.rpcData.att_watchlist = () => []; route = (u) => u.startsWith("https://bensunter.com") ? new Response("nf", { status: 404 }) : json(topList("US"));
  const o = await call({ mode: "top_country", as_of: DAY });
  check("contact gate (methods page 404): no Wikimedia request", wmCalls().length === 0 && o.stop === "ua_contact_unreachable" && log.length === 1, JSON.stringify(log.map((l) => l.url)));
}
{
  reset(2, 50);
  S.rpcData.att_wiki_pv_plan = () => ["a", "b", "c", "d"].map((k) => ({ key: k, geo: "en.wikipedia", topic_id: 1, series_id: 1, from_day: "2026-09-22", kind: "incr", prio: 1, last_day: "2026-09-21", first_day: "2025-07-01", act: true }));
  route = (u) => json({ items: [{ timestamp: "2026092400", views: 5 }] });
  const o = await call({ mode: "pageviews", as_of: DAY });
  check("daily budget: stops at the cap (2 of 4), nothing refunded twice", wmCalls().length === 2 && /^daily_budget_spent/.test(o.stop ?? "") && budgetOk() && S.budgets.wikimedia === 0,
    `calls=${wmCalls().length} stop=${o.stop} taken=${S.taken.wikimedia} ref=${S.refunded.wikimedia ?? 0}`);
}

// ============================================================ 3. pageviews
{
  reset(1500, 50);
  let mirrored = false;
  S.rpcData.att_wiki_mirror_signals = () => { mirrored = true; return { rows: 5 }; };
  S.rpcData.att_wiki_jobs_sweep = () => 3;
  S.rpcData.att_wiki_pv_plan = () => [
    { key: "A/B", geo: "en.wikipedia", topic_id: 1, series_id: null, from_day: "2025-07-31", kind: "first", prio: 0, last_day: null, first_day: null, act: true },
    { key: "Inc", geo: "de.wikipedia", topic_id: 2, series_id: 9, from_day: "2026-09-20", kind: "incr", prio: 1, last_day: "2026-09-19", first_day: "2025-07-31", act: true },
    { key: "Gone", geo: "en.wikipedia", topic_id: 3, series_id: null, from_day: "2025-07-31", kind: "first", prio: 0, last_day: null, first_day: null, act: true }];
  route = (u) => {
    if (u.includes("/A%2FB/")) return json({ items: [{ timestamp: "2025080100", views: 7 }, { timestamp: "2026092400", views: 9 }] });
    if (u.includes("/Inc/")) return json({ items: [{ timestamp: "2026092100", views: 3 }, { timestamp: "2026092400", views: 4 }] });
    return json({ type: "not_found" }, 404);
  };
  const o = await call({ mode: "pageviews", as_of: DAY });
  const a = S.ingested.filter((r: any) => r.key === "A/B"), inc = S.ingested.filter((r: any) => r.key === "Inc");
  check("pv: title URL-encoded (slash), all-access/user/daily", log.some((l) => l.url === "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/A%2FB/daily/2025073100/2026092400"));
  check("pv: first sight = full 421-day history, zero-filled", a.length === 421 && a.find((r: any) => r.day === "2025-08-01").value === 7 && a.find((r: any) => r.day === "2025-08-02").value === 0 && a[0].topic_id === 1, `n=${a.length}`);
  check("pv: incremental from last_day+1 with zeros", inc.length === 5 && inc.map((r: any) => r.value).join(",") === "0,3,0,0,4" && inc.every((r: any) => r.geo === "de.wikipedia"), inc.map((r: any) => r.day + ":" + r.value).join(","));
  check("pv: 404 on first sight -> nodata (retry later), no rows", S.ingested.every((r: any) => r.key !== "Gone") && S.state["wiki.pv.nodata"]?.["en.wikipedia|Gone"] === DAY);
  check("pv: signals mirrored in SQL + jobs swept", mirrored && o.jobs_swept === 3 && o.fetched_first === 1 && o.fetched_incr === 1);
  check("pv: budget = requests", budgetOk() && wmCalls().length === 3);
}

// ============================================================ 4. backfill job settlement + AQS 429 retry once then kill
{
  reset(1500, 50);
  S.rpcData.att_wiki_mirror_signals = () => ({ rows: 0 });
  S.rpcData.att_wiki_jobs_sweep = () => 0;
  S.rpcData.att_wiki_pv_plan = (a: any) => [
    { key: "K1", geo: "en.wikipedia", topic_id: 1, series_id: null, from_day: "2025-07-31", kind: "first", prio: 0, last_day: null, first_day: null, act: true },
    { key: "K2", geo: "en.wikipedia", topic_id: 2, series_id: 5, from_day: null, kind: "done", prio: 9, last_day: DAY, first_day: "2025-07-31", act: false },
    { key: "K3", geo: "en.wikipedia", topic_id: null, series_id: null, from_day: null, kind: "inactive", prio: 9, last_day: null, first_day: null, act: false }];
  S.rpcData.att_wiki_jobs = () => [{ id: 101, keys: [{ key: "K1", geo: "en.wikipedia" }] }, { id: 102, keys: [{ key: "K2", geo: "en.wikipedia" }] }, { id: 103, keys: [{ key: "K3", geo: "en.wikipedia" }] }];
  route = () => new Response("slow down", { status: 429 });
  const t0 = Date.now();
  const o = await call({ mode: "backfill", as_of: DAY, params: { source: "wiki.pv" }, keys: [{ key: "K1", geo: "en.wikipedia" }, { key: "K2", geo: "en.wikipedia" }, { key: "K3", geo: "en.wikipedia" }], job_id: 101, job_ids: [101, 102, 103] });
  const aqs = wmCalls();
  check("aqs 429: exactly one retry after ~5 s, then the host is stopped for the day", aqs.length === 2 && aqs[1].t - aqs[0].t >= 4900 && !!S.state["kill:wikimedia.org"]?.until && /^host_killed_429/.test(o.stop ?? ""), `n=${aqs.length} dt=${aqs[1]?.t - aqs[0]?.t}`);
  const done = S.jobsDone.find((j: any) => j.p_status === "done"), rq = S.jobsDone.find((j: any) => j.p_status === "requeue");
  const nb = rq ? new Date(rq.p_not_before) : null;
  check("backfill: jobs settled per key (K2 done, K3 inactive -> done, K1 requeued to tomorrow 10:05 UTC)",
    done?.p_jobs?.join(",") === "102,103" && rq?.p_jobs?.join(",") === "101" && !!nb && nb.getUTCHours() === 10 && nb.getUTCMinutes() === 5 && nb.getTime() > Date.now(),
    JSON.stringify(S.jobsDone));
  check("backfill: att.ts finish() did not re-settle the jobs", S.jobsDone.length === 2);
  check("backfill: budget = requests (retry charged too)", budgetOk(), `taken=${S.taken.wikimedia} ref=${S.refunded.wikimedia}`);
  void t0;
}
{
  reset(1500, 50);
  S.rpcData.att_wiki_jobs = () => [{ id: 7, keys: [] }];
  const o = await call({ mode: "backfill", as_of: DAY, params: { source: "wiki.media" }, job_ids: [7] });
  check("backfill: non-wiki.pv job skipped, no request", log.length === 0 && S.jobsDone[0]?.p_status === "skipped" && S.jobsDone.length === 1, JSON.stringify(o.sources));
}

// ============================================================ 5. mediarequests
{
  reset(1500, 50);
  S.rpcData.att_wiki_pv_plan = () => [{ key: "X", geo: "en.wikipedia", kind: "first", act: true, prio: 0 }];
  const o = await call({ mode: "mediarequests", as_of: DAY });
  check("media: deferred while active pageview histories are missing (no request)", log.length === 0 && /deferred/.test(o.sources?.[0]?.note ?? ""));
}
{
  reset(1500, 50);
  S.rpcData.att_wiki_pv_plan = () => [];
  S.rpcData.att_wiki_calls_today = () => 0;
  let planCall = 0, keysArg: any = null;
  S.rpcData.att_wiki_media_plan = () => (++planCall === 1)
    ? [{ kind: "resolve", topic_id: 21, project: "en.wikipedia", title: "Foo_Bar" }, { kind: "resolve", topic_id: 22, project: "en.wikipedia", title: "No_Image" },
       { kind: "resolve", topic_id: 23, project: "en.wikipedia", title: "Redirect_Src" }]
    : [{ kind: "first", topic_id: 21, key: "commons:Foo bar.jpg", path: "/wikipedia/commons/a/ab/Foo bar.jpg", from_day: "2025-07-31" }];
  S.rpcData.att_wiki_media_keys = (a: any) => { keysArg = a.p_rows; return { keys: 2, none: 1 }; };
  route = (u) => {
    if (u.includes("en.wikipedia.org/w/api.php")) return json({ query: {
      normalized: [{ from: "Foo_Bar", to: "Foo Bar" }, { from: "No_Image", to: "No Image" }, { from: "Redirect_Src", to: "Redirect Src" }],
      redirects: [{ from: "Redirect Src", to: "Target Page" }],
      pages: [{ title: "Foo Bar", original: { source: "https://upload.wikimedia.org/wikipedia/commons/a/ab/Foo%20bar.jpg" } }, { title: "No Image" },
              { title: "Target Page", original: { source: "https://upload.wikimedia.org/wikipedia/en/c/cd/Local.png" } }] } });
    if (u.includes("mediarequests/per-file")) return json({ items: [{ timestamp: "2026092300", requests: 11 }, { timestamp: "2026092400", requests: 12 }] });
    return new Response("", { status: 404 });
  };
  const o = await call({ mode: "mediarequests", as_of: DAY });
  const api = log.find((l) => l.url.includes("/w/api.php"));
  check("media: pageimages lookup uses the Action API with maxlag=5, free images only, 50-title batch, no robots", !!api && new URL(api.url).searchParams.get("maxlag") === "5" && new URL(api.url).searchParams.get("pilicense") === "free" && !log.some((l) => l.url.endsWith("robots.txt")), api?.url);
  check("media: keys registered (commons + local, via normalize/redirect) and no-image remembered",
    JSON.stringify(keysArg) === JSON.stringify([{ topic_id: 21, key: "commons:Foo bar.jpg", path: "/wikipedia/commons/a/ab/Foo bar.jpg" }, { topic_id: 22, none: true }, { topic_id: 23, key: "en:Local.png", path: "/wikipedia/en/c/cd/Local.png" }]),
    JSON.stringify(keysArg));
  const mr = log.find((l) => l.url.includes("mediarequests"));
  check("media: per-file URL encodes the upload path", mr?.url === "https://wikimedia.org/api/rest_v1/metrics/mediarequests/per-file/all-referers/user/%2Fwikipedia%2Fcommons%2Fa%2Fab%2FFoo%20bar.jpg/daily/2025073100/2026092400", mr?.url);
  const rows = S.ingested.filter((r: any) => r.source === "wiki.media");
  check("media: 421 daily rows, zero-filled, topic linked", rows.length === 421 && rows.at(-1).value === 12 && rows.at(-2).value === 11 && rows[0].value === 0 && rows[0].topic_id === 21, `n=${rows.length}`);
  check("media: spacing >= 1.1 s for the Action API call, budget = requests", budgetOk() && o.wikimedia_calls === 2, `calls=${o.wikimedia_calls}`);
}

// ============================================================ 6. clickstream_small
{
  reset(1500, 50);
  route = (u, init) => {
    if (u === "https://dumps.wikimedia.org/robots.txt") return new Response("User-agent: *\nDisallow: /private/\n", { status: 200 });
    if (init?.method === "HEAD") return new Response(null, { status: 200, headers: { "content-length": String(60 * 1048576) } });
    return new Response("should not be downloaded", { status: 200 });
  };
  const o = await call({ mode: "clickstream_small", as_of: DAY, params: { month: "2026-08" } });
  check("clickstream: large file -> HEAD only, GitHub-Action-only, robots checked", log.filter((l) => l.method === "GET" && !l.url.endsWith("robots.txt")).length === 0 &&
    log.some((l) => l.url.endsWith("robots.txt")) && o.wikis?.ptwiki?.action === "github_action_only" && o.skipped.some((s: any) => /^github_action_only:ptwiki:60MB/.test(s.reason)), JSON.stringify(o.wikis));
}
{
  reset(1500, 50);
  S.rpcData.att_watchlist = () => [{ key: "Foo", geo: "pt.wikipedia", metric: "n", match: {}, series_id: null, topic_id: 31, key_type: "title" }];
  const gz = gzipSync(Buffer.from("other-search\tFoo\texternal\t500\nFoo\tBar\tlink\t120\nX\tFoo\tlink\t10\nFoo\tBaz\tlink\t60\nA\tB\tlink\t999\n"));
  route = (u, init) => {
    if (u.endsWith("robots.txt")) return new Response("User-agent: *\nAllow: /\n", { status: 200 });
    if (init?.method === "HEAD") return new Response(null, { status: 200, headers: { "content-length": String(gz.length) } });
    return new Response(gz, { status: 200 });
  };
  const o = await call({ mode: "clickstream_small", as_of: DAY, params: { month: "2026-08" } });
  const e = S.edges.map((x: any) => `${x.from_key}>${x.to_key}:${x.n}`).sort().join(",");
  check("clickstream: small file streamed, only registry edges kept", e === "Foo>Bar:120,Foo>Baz:60,other-search>Foo:500" && S.edges.every((x: any) => x.period === "2026-08-01" && x.grain === "month" && x.geo === "pt.wikipedia"), e);
}

// ============================================================ 7. ping + auth
{
  reset();
  const o = await call({ mode: "ping" });
  check("ping: no request, version reported", log.length === 0 && /^2026-09-25\.w/.test(o.wiki_version));
}

let pass = 0;
for (const [n, ok, info] of results) { if (ok) pass++; console.log(`${ok ? "PASS" : "FAIL"} ${n}${ok ? "" : "  :: " + info}`); }
console.log(`${pass}/${results.length} passed`);
process.exit(pass === results.length ? 0 : 1);
