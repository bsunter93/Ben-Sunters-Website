# Attention layer compliance audit

- **Project:** kffkasnzqcddpystszch
- **Audited:** 2026-09-25, 20:10 to 20:40 UTC
- **Checked against:** DEMARCATION.md §1 (tiers and decision test) and §7 (lead decisions), and ATTENTION_STACK.md §0 (hard rules)
- **Scope:** all 33 edge functions were listed. The code of the 12 `att-*` functions and 6 `ripples-*` functions was reviewed. All 14 `probe-*` functions were called live.

## Verdict

**PASS, after three fixes made during this audit.**

The `att-*` layer is compliant. Every outbound request goes through `att.ts` `politeFetch`, which applies:
- the RED denylist;
- a check that the source is enabled and the host belongs to it;
- the kill switch;
- a lease so only one run uses a host at a time;
- robots.txt (a robots.txt that can't be reached counts as a deny);
- per-run caps and daily budgets;
- the Wikimedia quiet window and the UA contact gate.

A 429 or 503 stops the host until the next UTC midnight and halves the next day's cap. A 401 or 403, or a redirect to a login or challenge page, stops the host permanently until the owner clears it. The Jetstream websocket client runs the same checks on its upgrade response.

The violations were all in the older Knock-On `ripples-*` pipeline and in one cron schedule. All three are fixed (see "Fixes applied").

## Fixes applied

1. **`ripples-collect` hourly `trends` mode (v4 → v5, gate `2026-09-25.g1`).**
   - **What was wrong:**
     - It called `trends.google.com/trending/rss` (8 geos) and `public.api.bsky.app` `app.bsky.unspecced.getTrends` without checking robots.txt. That breaks hard rule 2, which covers unkeyed web paths and undocumented endpoints.
     - After a 429 or 503 on one geo, the loop went on to the next geo on the same host.
     - A 401 or 403 was not treated as a stop, so the host was retried on the next geo and again every hour. That breaks hard rule 3 and DEMARCATION §7.3.
   - **What changed:**
     - robots.txt is now checked for both hosts, with a 24 h cache in `att_state` under `kn.robots:<origin>`.
     - The shared kill switch (`kill:<host>`) is honoured.
     - A 429 or 503 now calls `att_host_kill`, which stops the host for the UTC day.
     - A 401 or 403, or a redirect to a login, consent or "sorry" page, is a permanent kill.
     - A redirect to another host skips that host for the run.
     - The Wikimedia modes (`daily` and `date`) and `kn.ts` are unchanged.
   - **Checks:**
     - `tsc --strict` passes on `index.ts`.
     - The robots parser was unit-checked against the live robots.txt files.
     - A live `sync` run fetched all 8 geos plus bsky and inserted 105 rows, with robots cached as allow for both hosts. Current robots.txt: Google disallows only `/explore?` and `/trends/explore?`; bsky has `Allow: /`.
   - **Copies:**
     - `ripples/attention/compliance_fixes/ripples-collect.index.v4.before.ts`
     - `ripples/attention/compliance_fixes/ripples-collect.index.v5.after.ts`
     - `ripples/attention/compliance_fixes/ripples-collect.kn.ts`
     - The source of record is updated in place at `ripples/pipeline/functions/ripples-collect/index.ts`.
2. **`public.ripples_job_done` (the Knock-On dispatcher; migration `compliance_job_done_no_retry`).**
   - **What was wrong:** every failed job was requeued up to 3 times, 30–60 s later. That included jobs that failed on HTTP 401/403 (for example `aqs 403`) or on `rate_limited: <host> 429|503`, so the pipeline retried after a 403 and after a 429 within the same run.
   - **What changed:** those jobs now end as `failed`. A MediaWiki `maxlag` error still requeues, as API:Etiquette asks. The single in-process AQS retry in `kn.ts` (allowed by §7.3) is unchanged.
   - **Checks:**
     - The regex was tested on 10 sample error strings.
     - Grants are unchanged: service_role only, anon cannot execute.
     - Normal days are unaffected: as_of 2026-09-24 had 1,882 Wikimedia calls and 0 errors.
   - **Copy:** `ripples/attention/sql/90_compliance_job_done_no_retry.sql`
3. **Cron `att-wikidata` (jobid 120).**
   - **What was wrong:** the schedule `17 * * * *` fired at 07:17, which is inside the 06:30–07:20 UTC window with no attention Wikimedia calls. `att.ts` already refused those calls through `wm_quiet_utc`, so no request was made, but the schedule broke ATTENTION_STACK §3.4.
   - **What changed:** the schedule is now `17 0-6,8-23 * * *`.
   - **Copy:** `ripples/attention/sql/91_compliance_cron_wikidata.sql`

## Per-host table

**Robots? column:**
- **yes** means robots.txt is enforced in code, and the `att_state` cache shows the status it got.
- **exempt** means a Wikimedia documented API under DEMARCATION §7.1.

**Grades:** G means GREEN, Y means YELLOW, O\* means ORANGE\*.

| Host | Functions | Grade | Robots? | Verdict |
|---|---|---|---|---|
| wikimedia.org (AQS REST) | att-wiki, att-registry, ripples-collect, ripples-expand, ripples-resolve | G | exempt (no robots.txt) | PASS. `kill:wikimedia.org` (429 at 04:05) holds until 00:00 UTC. The att contact gate blocks att calls while the methods page returns 404. |
| api.wikimedia.org (feed, core search) | ripples-collect, ripples-resolve | G | exempt | PASS, but see open issue 1 |
| en.wikipedia.org `/w/api.php` | ripples-expand, ripples-resolve (`kn.ts` `actionApi`: maxlag=5, serial 1.1 s) | G (§7.1, with conditions) | exempt | PASS, but see open issue 1 |
| www.wikidata.org `/w/api.php` | att-registry (wikidata.api), att-wikidata (wikidata.entity), ripples-resolve/expand | G (§7.1) | exempt, except `wikidata.entity`, which has robots_required=true | PASS. See open issue 4. |
| www.wikidata.org `/wiki/Special:EntityData` | att-wiki (wiki.media) | G | yes | PASS |
| dumps.wikimedia.org | att-wiki (clickstream) | G | yes | PASS; not called yet |
| jetstream1/2.us-east.bsky.network | att-social | G | yes (404 = allow) | PASS. Custom WS client with honest UA; 401/403/429/503 on upgrade triggers a kill. |
| hn.algolia.com | att-social, att-library | G | yes (404) | PASS |
| api.stackexchange.com | att-social | Y | yes (400, treated as allow) | PASS. It honours `backoff`, and a throttle violation (502) triggers a kill. |
| mastodon.social, mstdn.jp | att-social | Y | yes (200) | PASS |
| data.gdeltproject.org | att-news | G | yes (404) | PASS. The DOC API (`api.gdeltproject.org/api/v2/doc`) is RED-listed and never called. |
| archive.org (Third Eye) | att-news | Y | yes (200) | PASS |
| www.bbc.com, www.nytimes.com, www.theguardian.com, www.foxnews.com | att-news (sitemaps) | Y | yes (200) | PASS; only headline counts are stored |
| api.finra.org | att-market | Y | yes (404) | PASS. This is the documented alternate channel (DEMARCATION Q3). |
| cdn.finra.org | att-market | Y | yes (403, deny) | STOPPED correctly: permanent kill with `robots_403` |
| gamma-api.polymarket.com, clob.polymarket.com | att-market, att-market-backfill | Y | yes (404) | PASS |
| api.elections.kalshi.com | att-market, att-market-backfill | Y | yes (404) | PASS |
| api.usaspending.gov | att-market | G | yes (404) | PASS. A 503 today set a day kill until 00:00, so the stop rule works. There were 13 network errors (status 0). |
| efts.sec.gov | att-market (edgar) | G (needs contact email) | n/a | PASS. RED-listed in `att.ts`, source disabled, cron inactive. |
| rss.marketingtools.apple.com | att-charts | Y | yes (200) | PASS. The `rss.applemarketingtools.com` robots.txt returns 301, which counts as a deny, so that host is not used. |
| steamspy.com | att-charts | Y | yes | PASS |
| api.github.com | att-charts | G | yes (404) | PASS |
| huggingface.co | att-charts | G | yes | PASS |
| graphql.anilist.co | att-charts | Y (non-commercial above the revenue threshold) | yes | PASS |
| openlibrary.org | att-charts | G | yes | PASS |
| tranco-list.eu | att-charts | Y | yes | PASS |
| api.npmjs.org | att-charts, att-library | G | yes (404) | PASS |
| pypistats.org | att-charts | Y | yes (404) | PASS |
| www.tsa.gov | att-world | G | yes | PASS |
| earthquake.usgs.gov | att-world, att-library | G | yes (404) | PASS |
| mesonet.agron.iastate.edu | att-world, att-library | G | yes | PASS |
| www.fema.gov | att-world, att-library | G | yes | PASS |
| www.gdacs.org | att-world, att-library | G | yes | PASS |
| data.ny.gov | att-world | G | yes | PASS |
| tripdata.s3.amazonaws.com | att-world | G | yes (404) | PASS |
| raw.githubusercontent.com | att-world | G | yes (404) | PASS |
| api.stlouisfed.org (FRED, keyed) | att-econ | G | yes (200) | PASS. BLS series are read through FRED because api.bls.gov robots.txt disallows `/`. |
| www.ncei.noaa.gov (CDO API, keyed) | att-econ | G | yes (only `/data*` etc. disallowed) | PASS |
| www.eia.gov (bulk CSV) | att-econ | G | yes | PASS. api.eia.gov robots.txt returned 403, so that host is permanently killed and `eia.prices` is disabled. |
| oui.doleta.gov, www.federalreserve.gov, www.census.gov | att-econ | G | yes | PASS |
| www.alphavantage.co | att-equities | O\* (owner decision D-10) | yes (404) | PASS |
| api.twelvedata.com | att-equities | O\* | yes (disallow) | PASS. The source is disabled; only robots.txt was fetched. |
| trends.google.com (`/trending/rss` only) | ripples-collect | Y | **now yes** | **FIXED** (fix 1). `/explore`, `/trends/api/`, `batchexecute` and `widgetdata` are RED-listed and never called. |
| public.api.bsky.app (getTrends) | ripples-collect | Y (unspecced) | **now yes** | **FIXED** (fix 1) |
| bsky.social | ripples-bot | own-account posting, not collection | n/a | PASS |
| cdn.jsdelivr.net | ripples-og | asset CDN (fonts, wasm, emoji) | n/a | PASS (sends Deno's default UA) |

## Rule checks

- **RED endpoints:** PASS.
  - The full grep list (suggestqueries, completion.amazon, api.bing.com/osjson, duckduckgo.com/ac, news.google.com, batchexecute, /trends/api/, widgetdata, reddit.com, trends24, getdaytrends, tiktok, yahoo, stooq, nasdaq.com, cnn.io, opensky, radar.cloudflare, api.gdeltproject.org/api/v2/doc) was run over every `att-*` and `ripples-*` source.
  - The only hits are the `att.ts` denylist itself (`RED` and `RED_PATH`), which blocks those hosts, and one news-title junk filter word ("tiktok") in att-news.
  - None of these hosts appears in the 24 h `att_runs` HTTP log.
- **UA honesty:** PASS.
  - att: `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`.
  - Knock-On: `KnockOn/5.0 (https://bensunter.com/ripples/methods/)`, plus `Api-User-Agent` on Wikimedia.
  - Neither contains an email address, a browser UA or a spoofed header. `grep Mozilla|Chrome/` found nothing.
- **Cookies:** PASS.
  - `politeFetch` deletes any outgoing `cookie` header and strips credentials when a redirect crosses origin.
  - No code reads `set-cookie` or calls `getSetCookie`, and Deno fetch keeps no cookie jar.
- **Stop on 429/503:** PASS for att. It was a FAIL for ripples-collect and the job requeue, both now fixed. Evidence from the last 24 h:
  - wikimedia.org 429 set a day kill;
  - api.usaspending.gov 503 set a day kill;
  - cdn.finra.org and api.eia.gov robots 403 set permanent kills.
- **No retry after 403:** PASS for att (permanent kill until `att_host_unkill`). The ripples pipeline previously requeued; now fixed.
- **No PII persisted:** PASS.
  - **`meta` keys on `attention_obs`:** only released, sa, vintage, ref, method, coverage, unit, n_mkts, partial, weekly, est, window and monthly.
  - **`att_trend_candidates.meta` keys:** only kind, list, score, k, ratio, z, method, n_docs, q, n_posts, rank and total.
  - **Pattern search:** no `att_series.key`, `att_social_tags.tag` or candidate label or meta matches an email, a `did:plc:`, a `.bsky.social` handle or a URL.
  - **Bluesky:** DIDs only feed in-memory HyperLogLog sketches and are never stored.
  - **One note:** `ripples.trend_obs.news` keeps up to 3 Google Trends news items (headline, publisher, URL) per query. That is not personal data, but it is third-party list text, graded YELLOW-provenance. Keep it internal, or reduce it to a count.
- **Probes:** PASS.
  - 13 of 14 `probe-*` functions return **410** `{"gone":true}` when called live through pg_net.
  - `probe-cors` answers 401 at the platform JWT gate because it has `verify_jwt=true`. Its deployed code (v2) is `new Response('gone', {status: 410})` and makes no outbound calls.
  - All of them can be deleted from the dashboard.
- **Security advisors:** no ERROR-level findings.
  - The 110 INFO "RLS enabled, no policy" notes are intentional.
  - 12 WARNs are the intentionally public `ripples_*` RPCs.
  - One WARN is the `ripples._att_hll_union` aggregate, whose search_path can be changed. It is low risk: it lives in a non-exposed schema.

## Cron: Wikimedia quiet window (06:30–07:20 UTC)

| Job | Schedule | Wikimedia? | In window? |
|---|---|---|---|
| att-topcc | 06:23 (runs up to 110 s) | yes | no |
| att-wiki-pv-1/2/3 | 07:21, 07:24, 07:27 | yes | no (the first starts 1 min after the window) |
| att-media | 07:30 | yes | no |
| att-wikidata | was `17 * * * *` | yes | **was yes at 07:17. Fixed** to `17 0-6,8-23 * * *` |
| att-registry | 09:52 | yes | no |
| att-backfill (`att_tick`) | every 2 min, 10:00–23:58 | yes (wiki backfill) | no |
| att-wiki-pv-pm, att-clickstream, att-media-pm | 10–23 h, 10:31 on the 7th, 12:37 | yes | no |
| att-tick-hops-a/b | 07:33–08:18 | via `att_tick` | no |
| att-zvec-*, att-engine-tick-*, att-freeze, att-pick-events, att-finalize-engine, att-expand, att-library-run | various | SQL only (no `call_collector` or `net.http`) | n/a |
| All other att-* (market, charts, social, news, world, econ, library, equities) | various | no | n/a |

`att.ts` also enforces the window at run time for the `wikimedia` and `wikidata` buckets (`att_config.wm_quiet_utc`). The window is reserved for the Knock-On `ripples_tick` expand and build stages, which are the Wikimedia calls it protects.

## YouTube Data API v3 (`att-youtube`, source `yt.api`, added 2026-09-26)

**Terms.** Documented, keyed API only: `videos.list` with `chart=mostPopular` (1 unit/call). No `search.list` (100 units) is used. The YouTube API Services Terms "cached data" rule requires raw API data (view counts, etc.) to be refreshed or deleted within 30 days.
- **Compliance:** the collector never writes a per-video row to any table. The only raw cache is two `ripples.att_state` rows (`yt.day` holding today's id→viewCount map, `yt.raw.prev` holding yesterday's), rotated once per UTC day, so the oldest raw number on disk is always under 48 hours old — well inside the 30-day cap. A daily cron (`att-youtube-raw-cleanup`, `ripples.att_yt_raw_cleanup(28)`) is a safety net that deletes any `yt.raw%` state row older than 28 days, in case the rotation ever stalls; in normal operation it deletes 0 rows because the rotation already keeps things far under that.
- Only DERIVED aggregates are kept long-term in `ripples.attention_obs`: per region×category top-50 view-sum (`views_top50`), a new-entrant count (`entrants`), the median per-video view-gain since yesterday's snapshot of the same video ids (`velocity_median`), and a per-topic count of trending-chart title matches (`topic_hits`).
- **No personal data.** No commenter or viewer identity of any kind is read or stored. Video/channel titles are read only in memory (for topic-keyword matching) and are never written to a table, row, or log — `att_runs` and `att_state` were grepped for the API key prefix (`AIza`) after a live run and found clean.

**Demarcation.** Grade GREEN, `yt.api` source row (previously a disabled placeholder, now enabled). Serial requests through `politeFetch` (`spacing_ms=300`); robots.txt for `www.googleapis.com` is checked and cached like every other source. A 429, a 403 (including `quotaExceeded`), or a 503 hits the shared `att.ts` kill switch exactly like any other source: the host is killed for the rest of the run (permanently on 401/403, until UTC midnight on 429/503) and never retried in that run — no YouTube-specific code was needed for this.

**Quota.** 40 regionCodes × 7 videoCategoryId buckets (`0`=all/omit, 10 Music, 20 Gaming, 24 Entertainment, 25 News & Politics, 28 Science & Technology, 17 Sports) = 280 `videos.list` calls/day = 280 quota units/day, verified live (see below). Capped at 3,000/day via `att_config.budgets.youtube` (a dedicated `att_sources.budget_bucket`), far under YouTube's 10,000 units/day project default and under the 3,000/day ceiling the owner set for this build.

**Live verification (2026-09-26, run_id 1201).** `collect` ran all 280 combos in 89.4 s, 280/280 requests OK (`200`), 280 attention_obs rows, 280 new series, `partial:false`. Budget bucket `youtube`: 281/3000 used (includes 1 unit from an earlier `peek` probe). `ripples.att_state` rows `yt.day` (313.8 KB) and `yt.topic.day` (35 B) contained no leaked key material (`AIza` prefix grep = 0 hits), and neither did any `att_runs.detail` row for this function.

**Storage footprint.** Raw cache: two `att_state` rows, ~310 KB each once both `yt.day` and `yt.raw.prev` exist (well under the 5 MB target). Derived series: 280 series rows so far (one per region×category×metric that has fired), growing by up to ~4 metrics × 280 combos + up to 52 topic rows per day as `entrants`/`velocity_median`/`topic_hits` start landing from day 2 onward — small numeric rows in `attention_obs`, the same shape as every other daily source in this system.

## Database size (limit 400 MB)

**307 MB used, which is 77% of the limit.** At the att-news check at 15:14 it was 101 MB. Most of the growth came from today's backfills: att-econ added about 1.19 M rows in the last 2 h (NOAA is done; 7 EIA-930 files are left) and att-library FEMA added about 0.15 M rows.

Top 15 relations:

| Relation | Size | Rows (estimate) |
|---|---|---|
| ripples.attention_obs | 185 MB (115 MB heap, 70 MB index) | 1.67 M |
| ripples.att_zvec | 22 MB | 1.6 k |
| ripples.att_social_tags | 14 MB | 15 k |
| ripples.att_mech_edges | 6.4 MB | 7.9 k |
| net._http_response | 5.6 MB | 980 |
| pg_catalog.pg_statistic | 4.4 MB | 1.6 k |
| ripples.trend_obs | 4.0 MB | 9.1 k |
| ripples.att_social_acc | 3.5 MB | 4.2 k |
| public.wiki_top | 3.4 MB | 16 k |
| public.signal_obs | 2.9 MB | 34 k |
| pg_catalog.pg_proc | 2.7 MB | 3.8 k |
| ripples.att_series | 2.6 MB | 8.6 k |
| ripples.att_hop_candidates | 2.5 MB | 536 |
| ripples.att_keys | 2.4 MB | 6.4 k |
| ripples.att_hop_tests | 2.4 MB | 704 |

**Rows by source in `attention_obs`:**

| Source | Rows |
|---|---|
| noaa.ghcnd | 440 k |
| eia.930 | 324 k |
| hn.algolia | 291 k |
| fema.decl | 142 k |
| wiki.pv | 137 k |
| dol.claims | 94 k |
| fred | 57 k |
| everything else | under 40 k each |

**Projected size once the queued backfills finish:** about 370–390 MB. The queued backfills are:

| Backfill | Rows left |
|---|---|
| EIA | about 150 k |
| wiki.pv (617 keys × 400) | about 250 k |
| se.api (264 jobs) | about 100 k |
| FEMA (2019–2020) | about 50 k |
| iem, hn, npm, citibike | small |

That is inside the limit but with little headroom.

**Rating: WARN, not a violation.** Recommendations:
- Before adding any new all-history source, confirm that `att_retention` or `att_engine_retention` thins `dormant` series as §3.7 specifies.
- Cap `att_zvec` history.
- Watch the size daily. Do not start a new bulk backfill until the size is below 330 MB.

## Open issues for the owner (not fixed; each needs an owner decision)

1. **The UA contact page returns 404.** Both UAs point at `https://bensunter.com/ripples/methods/`, which answers 404.
   - For att, the contact gate refuses all Wikimedia calls until the page returns 2xx.
   - The Knock-On pipeline (`kn.ts`) has no gate. It made 1,882 Wikimedia calls for as_of 2026-09-24 with a contact URL that does not resolve. That misses the DEMARCATION §7.1 condition "an honest User-Agent that includes a contact".
   - **Fix:** publish the methods page, or add an owner contact to both UAs; the latter also unblocks SEC EDGAR.
   - I did not gate the Knock-On pipeline, because doing so would stop the daily puzzle.
2. **The Knock-On pipeline does not read the shared att kill switch for Wikimedia.** Today att-core's backfill got a 429 at 04:05. The Knock-On tick ran 06:00–08:59 against the same IP and got 0 errors. Decide whether one 429 on the shared IP should pause both systems for the rest of the day, which is the strict reading of §7.3.
3. **`kn.ts` AQS retry timing.** It waits for `Retry-After` up to 20 s before its single retry. The lead decision reads "one retry after 5 s at most". This is minor, and the longer wait is the more polite behaviour. Align the text or the code.
4. **`wikidata.entity` has robots_required=true.** Its only URL is `www.wikidata.org/w/api.php`, and robots.txt disallows `/w/`, so `att-wikidata` will get `robots_disallow` on every call once the contact gate opens. This is over-cautious, not a violation. Set it to false under §7.1, or move to `Special:EntityData`.
5. **api.stackexchange.com robots.txt returns 400.** The code treats a 400 as "no robots.txt, allowed". DEMARCATION Q3 only names 401/403/5xx as a deny, so this is compliant, but note it.
6. **Concurrent edits.** Local `att-econ/index.ts` (`ECON_VERSION` e4, modified 20:16) is newer than the last version reported by a run (e3). Other builders were editing while this audit ran. The `att-*` checks above are based on the local sources plus live DB evidence (robots cache, kill records and the HTTP status log), and every deployed `att-*` run reports `ATT_VERSION 2026-09-25.3`. Re-run the RED grep after the final deploys.

**YouTube retention (tightened 2026-09-26):** `views_top50` and `velocity_median` are computed directly from API view counts, so they are treated as API data and deleted after 28 days by `ripples.att_yt_raw_cleanup` (daily 03:11 UTC). Only counts we compute ourselves (`entrants`, `topic_hits`) and the engine's derived scores persist beyond 28 days.
