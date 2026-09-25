# Ripples v5 attention layer: core (W7 att-core)

Everything the attention collectors build on: the `ripples.att_*` schema, the service-only RPCs, the topic registry
(active topics + the frozen placebo panel), the job queue and tick, and the shared edge-function runtime `att.ts`.
Spec: `ATTENTION_STACK.md` §3 and §7, with `DEMARCATION.md` §7 lead decisions taking precedence.

## Layout

| Path | What |
|---|---|
| `sql/01_attention_stack_core.sql` | Migration `attention_stack_core`: DDL (§7.1, free-tier profile), `att_config`, the 70-row `att_sources` seed, RLS + revokes |
| `sql/02_attention_stack_core_rpc.sql` | Migration `attention_stack_core_rpc`: ingest, budget, state, run log, registry/key generation, job queue, `att_tick`, public wrappers, grants |
| `sql/03_attention_stack_core_ops.sql` | Migration `attention_stack_core_ops`: `att_source_get`, `att_filter_titles`, cron jobs |
| `sql/04_attention_stack_core_tick_merge.sql` | Migration `attention_stack_core_tick_merge`: `att_tick` also merges queued `resolve` jobs |
| `sql/05_attention_stack_core_definer_helpers.sql` | Migration: the three immutable helpers made SECURITY DEFINER |
| `sql/06_ops_adjustments_2026-09-25.sql` | Operational record (AQS 429, spacing, panel pool) |
| `sql/07_attention_stack_core_hardening.sql` | Migration `attention_stack_core_hardening` (post-verification): permanent 401/403 kills, host lease, 1 job per fn/host in `att_tick`, quiet window for `wikidata`, `run_caps`, meta allow-list, DEMARCATION Q6 budgets |
| `sql/08_attention_stack_core_fixes2.sql` | Migration `attention_stack_core_fixes2` (second verification round): `wikidata.api` source row, `att_budget_refund`, `att_config.contact_gate`, identifier screen `_att_ident_like` on ingest keys / edge keys / candidate labels, `_att_alias_ok`, extended SKIP rules + `att_registry_maintain` retiring SKIP pages |
| `sql/09_att_news.sql` | Migration `att_news_collector` (att-news): budgets for gdelt.gkg / ia.thirdeye / news.sitemap, news.sitemap term keys (+ copy trigger from gdelt.gkg), `att_news_acc` / `att_news_batches` / `att_news_cells`, `att_news_terms`, `att_news_accum`, `att_news_sitemap_merge`, `att_news_edges_accum`, `att_news_candidates_merge` (+ public wrappers, service_role only) |
| `sql/09b_att_news_cron.sql` | Migration `att_news_cron`: cron rows `att-gkg`, `att-thirdeye`, `att-sitemaps` |
| `functions/att-news/index.ts` (+ `att.ts` copy, `README.md`) | News/TV collector: `gkg`, `thirdeye`, `sitemaps`, `backfill` (disabled), `ping` |
| `sql/10_att_social.sql` | Migration(s) for att-social: `att_social_acc` (HLL registers per series bucket), `att_social_tags` (daily facet hashtags, 8-day retention), `_att_hll_merge/_est/_union`, `att_social_keys`, `att_social_accum` (adds counts + merges HLL + saves the Jetstream cursor in one transaction), `att_social_tag_cands`, `att_social_bf_done`, source rows/budgets, cron rows |
| `sql/11_att_social_ops_2026-09-25.sql` | Operational record for att-social (Jetstream buffer replay lane, proc budget, HN re-run, se.api job deferral) |
| `sql/12_att_social_fixes.sql` | Migration `att_social_fixes3`: facet hashtags pass the strict identifier screen before storage (no `*.bsky.social` / personal-domain tags); orphan run closed |
| `sql/17_att_social_fixes4.sql` | Migration `att_social_fixes4`: `att_social_tag_ok` (stored hashtags: no `.` `@` `/` `:` `\\` whitespace/control chars, <= 40 chars) wired into `att_social_accum`, offending tags deleted; `att_social_jet_budget(lane)` (syncs today's bsky.jet `att_budget` cap to `att_sources.per_day_cap`, live-lane reserve = remaining 5-min slots today + 12); today's frozen 288 cap raised to 600 |
| `sql/17b_att_social_jet_cron_gate.sql` | Migration `att_social_jet_cron_gate`: both Jetstream crons call `att_social_jet_budget` first, so no edge call is made when the budget is spent/killed, and the buffer-replay lane only runs above the live reserve |
| `sql/19_att_social_fixes5.sql` | Migrations `att_social_fixes5` + `att_social_fixes5b` (verifier advisories): hashtag k-anonymity floor, a new `att_social_tags` row needs >= 3 distinct authors (HLL) in the run, existing rows below it or without a sketch deleted; bsky.jet `per_day_cap` 600 -> 432 (288 scheduled per ATTENTION_STACK 3.5 + 144 catch-up, recorded as a deviation in `att_sources.reason`); triggers on `att_state` copy any kill of one Jetstream host to its sister host (no failover after 401/403/429/503), never let a day kill replace a permanent one, and lift copies when the killed host is unkilled; `att_social_jet_budget` refuses while any bsky.jet host has an active kill |
| `functions/att-social/index.ts` (+ `att.ts` copy) | Social collector (SOCIAL_VERSION 2026-09-25.s4): `jetstream`, `mastodon`, `hn`, `stackex`, `backfill` (hn.algolia, se.api), `ping`. s4: backfill dispatches whose host is closed for the UTC day (daily budget spent, day/permanent kill) requeue their jobs for 00:10 UTC next day instead of +1 h |
| `sql/14_att_market.sql` | Migration `att_market_support` (att-market): source row `finra.api` (FINRA Query API, DEMARCATION Q3 channel), `att_config.market`, meta keys, `att_topic_terms`, `att_series_stats` (+ public wrappers, service_role only), usasp.spend / sec.efts term keys for non-people topics, the FINRA file backfill job |
| `sql/14b_att_market_jobs.sql` | Migration `att_market_jobs`: `att_market_jobs(ids)` (per-job keys for per-key completion of merged backfill jobs) |
| `sql/14e_att_market_fixes2.sql` | Migrations `att_market_fixes2` / `att_market_fixes2b`: seed `usasp.bfgap` with windows lost to timeouts before m8 and requeue those keys' jobs, close orphan run 525, queued att-market jobs to 10:05 UTC |
| `sql/14c_att_market_cron.sql` | Migration `att_market_cron`: `att-finra` 06:02, `att-predmkts` 06:03, `att-kalshi` 06:04 (+ `att-kalshi-2/3/4` 06:06/06:08/06:10), `att-usasp` 07:27, `att-edgar` 07:26 (inactive), `att_fn_live('att-market')`; plus the ops record of the first-day changes (config, budget row, clean-ups, temporary FINRA backfill cron) |
| `sql/14d_att_market_fixes.sql` | Migration `att_market_fixes` (after verification): `att_market_clear_day(source, day)` (poly.mkt / kalshi.mkt vol24h + candidates of one day; service_role only) and removal of the false FINRA ticker zeros before each series' first reported day; m7 change log |
| `functions/att-market/index.ts` (+ `att.ts` copy) | Money / institutional collector (MARKET_VERSION 2026-09-25.m8, deploy v10): `finra`, `polymarket`, `kalshi`, `usaspending`, `edgar` (disabled), `backfill`, `ping`. See "att-market" below |
| `sql/15_att_charts.sql` | Migration `att_charts_collector` (att-charts): `att_config.charts` (per-mode settings, free/pro list sizes, npm/pypi reference panels), meta keys `kind/feed/score/n_geos/list`, `att_charts_prev` (previous snapshot per metric/geo), `att_charts_series_info` (+ public wrappers, service_role only) |
| `sql/15b_att_charts_cron.sql` | Migrations `att_charts_cron` + `att_charts_cron2`: `att-apple-1..6` 06:10/12/14/16/18/20, `att-steamspy` 06:12, `att-hf` 06:13, `att-github` 06:14, `att-openlibrary` 06:15, `att-anilist` 06:17, `att-npm` 06:18, `att-pypi` 06:19, `att-tranco` 06:19 |
| `sql/15c_att_charts_ops_2026-09-25.sql` | Operational record for att-charts (tranco caps, ChatGPT SDK keys, Apple robots cache fix, `att_fn_live('att-charts')`) |
| `sql/15d_att_budget_refund_fix.sql` | Migration `att_budget_refund_fix` (core fix found by att-charts): `att_budget.killed`; `att_budget_refund` refuses refunds only for kill-spent buckets (it used to refuse whenever used = cap, so a chunk that took the whole day's cap was never refunded); `att_host_kill` sets `killed` |
| `sql/15e_att_ident_npm_scoped.sql` | Migration `att_ident_npm_scoped`: `_att_ident_like` no longer rejects scoped npm package keys (`@scope/name`, source `npm.dl` only) as handles |
| `sql/15f_att_charts_fixes.sql` | Migration `att_charts_fixes_c8`: `att_charts_prune` (+ public wrapper, service_role only) deletes same-day rows of items that dropped off a snapshot list on a re-run; converts `att_state['charts.tranco.top']` from a readable top-1000 domain list to 12-hex SHA-256 digests |
| `sql/15g_att_charts_ledger_npm_gaps.sql` | Migration `att_charts_ledger_npm_gaps`: `att_config.charts.npm.days` 7 -> 30 (same request count); seeds `att_state['charts.npm.gaps']` (npm outage days of `__total__`); ops ledger `att_state['ledger:att-charts.ops']` (the 15c robots-cache deletion, the 15c/15d budget recounts, the c1 anilist spacing shortfall; policy: no further manual robots/budget edits) |
| `functions/att-charts/index.ts` (+ `att.ts` copy) | Charts / builder / consumption collector (CHARTS_VERSION 2026-09-25.c9): `apple`, `steamspy`, `github`, `hf`, `anilist`, `openlibrary`, `tranco`, `npm`, `pypi`, `backfill` (npm.dl, pypi.dl, anilist, gh.stars), `ping`. See "att-charts" below |
| `sql/16_att_world.sql` | Migration `att_world_sources` (att-world): DEMARCATION Q6 budgets / hosts / `backfill_fn` for tsa.pax, usgs.eq, iem.warn, fema.decl, gdacs, mta.ridership, citibike.trips (virtual-host bucket `tripdata.s3.amazonaws.com`), hiringlab.postings (`raw.githubusercontent.com` only) |
| `sql/16b_att_world_cron.sql` | Migration `att_world_cron`: `att-world` 06:21 (tsa, usgs, iem, fema, gdacs, mta), `att-world-files` 06:22 (hiringlab, citibike), `att-world-pm` 13:41 (tsa, mta), `att_fn_live('att-world')` |
| `sql/16c_att_world_fixes.sql` | Migration `att_world_fixes`: self-removing cron `att-world-citibike-cap` (`7,27,47 * * * *`) resets `citibike.trips` per_day_cap 30 -> 4 (and today's `att_budget` row) once `world.bf.citibike.trips` is complete (at the latest 2026-09-28); Citi Bike virtual-host ledger entry (`att_sources.license_note`, `att_state['ledger:citibike.trips']`); run 599 relabelled `budget_exhausted` |
| `sql/16d_att_world_citibike_done.sql` | Data-only fix (execute_sql): `citibike.trips` reason text after the Citi Bike JC backfill completed (13 months, JC-202508..JC-202608) |
| `functions/att-world/index.ts` (+ `att.ts` copy) | World / real-economy collector (WORLD_VERSION 2026-09-25.w3): `tsa`, `usgs`, `iem`, `fema`, `gdacs`, `mta`, `citibike`, `hiringlab`, `all`, `backfill`, `ping`. See "att-world" below |
| `sql/16_att_wiki.sql` | Migrations `att_wiki_collector` + `att_wiki_plan_signal_history` (att-wiki): wiki.* source rows (1 req/s, `wiki.media` hosts + `wikipedia.org`, `wiki.cs` in the `wikimedia` bucket, robots required), `att_config.wiki`, planners `att_wiki_pv_plan` / `att_wiki_media_plan`, `att_wiki_mirror_signals`, `att_wiki_topcc_reach` / `_prev`, `att_wiki_media_keys`, `att_wiki_jobs(_sweep)`, `att_wiki_calls_today`, `att_wiki_progress` (+ public wrappers, service_role only) |
| `sql/16b_att_wiki_cron.sql` | Migration `att_wiki_cron`: `att-topcc` 06:23 (+09:23, 13:23), `att-wiki-pv-1/2/3` 07:21/24/27, `att-wiki-pv-pm` :07 10-23, `att-media` 07:30 (+12:37), `att-clickstream` 10:31 on the 7th; `att_fn_live('att-wiki')` |
| `sql/16c_att_wiki_fixes.sql` | Migration `att_wiki_fixes_coverage_media_daycap` (att-wiki verifier fixes): coverage-based `att_wiki_pv_plan` (gappy series re-fetched), `att_wiki_progress.with_400d_complete`, `att_wiki_media_plan` + `qid`, `wiki.media` hosts = wikimedia.org + www.wikidata.org, `att_config.wiki.action_api_ok = false`, `_att_bucket('src:<source>')` = per-source day cap |
| `functions/att-wiki/index.ts` (+ `att.ts` copy) | Wikimedia collector (WIKI_VERSION 2026-09-25.w2): `top_country`, `pageviews`, `mediarequests`, `clickstream_small`, `backfill` (wiki.pv), `ping`. See "att-wiki" below |
| `functions/_shared/att.ts` | Canonical shared runtime for every `att-*` edge function |
| `functions/att-registry/index.ts` (+ `att.ts` copy) | Topic registry function: `resolve`, `bootstrap`, `panel`, `ping` |

## IMPORTANT: how collectors ship att.ts

The Supabase MCP `deploy_edge_function` uploads **only the files listed in that call's `files` array**; a
`../_shared/att.ts` import is not resolvable on the server. So every collector deploys **its own copy** of the shared
file as `./att.ts` next to `index.ts`:

```ts
import { serve, politeFetch, budget, ingest, watchlist, type Run } from "./att.ts";
```

```json
files: [ {"name":"index.ts","content":"..."}, {"name":"att.ts","content":"<exact copy of functions/_shared/att.ts>"} ]
```

Keep copies byte-identical to `functions/_shared/att.ts` (`ATT_VERSION` is logged in every `att_runs.detail`).
Deploy with `verify_jwt: false`; auth is the `x-collector-token` check done by `serve()`.
After a collector is deployed and tested, add it to the tick's allow-list so queued jobs are dispatched to it:
`select ripples.att_fn_live('att-social');` (unlisted functions never receive `att_tick` jobs, so no 404 storms).

## Hard rules implemented in att.ts (ATT_VERSION 2026-09-25.3)

* UA `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)` on every request (and `Api-User-Agent` for
  Wikimedia). No email anywhere. Cookies are stripped; Deno fetch has no cookie jar; no proxies.
* **robots.txt** honoured for every URL that is not a Wikimedia documented API (DEMARCATION §7.1: `wikimedia.org`,
  `api.wikimedia.org`, `stream.wikimedia.org`, and `/w/api.php` + `/api/rest_v1/` on wiki hosts). The `robots:false`
  option is ignored everywhere else, and `att_sources.robots_required=true` forces the check. Cached 24 h in
  `att_state['robots:<origin>']`; 401/403/429/5xx/unreachable robots = deny; 404/410 = allow; a robots.txt redirect is
  followed only to the same host's `/robots.txt`. A **401/403 on robots.txt permanently kills the host** (hard rule 3);
  a 429/503 on robots.txt stops it for the UTC day.
* **RED denylist** in `isRed()`: the ATTENTION_STACK §0 rule-6 list, the Google Trends internal endpoints, SEC (no
  owner email), and every R row of the DEMARCATION §3 matrix (Goodreads, Pinterest Trends, X/Twitter, YouTube
  `/feed/trending`, Bluesky `searchPosts`, legacy iTunes RSS/search, Shazam, Deezer, Netflix Top 10, `files.tmdb.org`,
  Trakt, Letterboxd, Chess.com, Lichess `/api/`, BoardGameGeek, Fortnite API, NWS `api.weather.gov`, `data.indeed.com`,
  `data.commoncrawl.org`, NewsAPI, GNews, Weibo, Zhihu, Bilibili, Yandex, Wikidata SPARQL, Wikipedia `/w/index.php`).
* **Redirects are never followed blindly** (`redirect:"manual"`): every hop re-runs RED, kill, lease and robots checks
  (max 5 hops). A hop to a login/visitor wall or challenge (`isBarrierUrl`) is a DEMARCATION Q2 barrier: the
  redirecting host is killed permanently.
* **Kill switch.** 429/503: host stopped until the next UTC midnight, the source's budget for today spent, tomorrow's
  cap halved. **401/403 or a barrier redirect: permanent kill** (`att_state['kill:<host>'].permanent=true`), never
  retried automatically; the owner reviews and clears it with `select ripples.att_host_unkill('<host>');`.
  The only in-run retry is AQS (`aqsRetry`): one retry after 5 s on a 429, **once per run** (§7.3); the next 429
  stops the host. Kill lookups are cached for at most
  30 s and the module caches are cleared at the start of every Run, so a warm isolate always sees kills written by
  other invocations.
* **One request stream per host.** `serial()` spaces requests within an isolate; the cross-isolate **host lease**
  (`ripples.att_host_lease`, `att_host_lease_take/_release`) lets only one run use a host at a time (held until the run
  finishes, TTL = wall + 15 s). A busy host is skipped for the run (`host_busy`, run marked partial so jobs requeue).
  `att_tick` additionally dispatches at most **1 running job per function** (`tick.max_inflight_per_fn`) and never two
  running jobs whose sources share a host.
* **Every request needs a registered source.** `politeFetch` refuses a call without `source`
  (`source_required`), an unknown source (`unknown_source:<id>`), a disabled one, and a URL whose host is not in the
  source's `att_sources.hosts` (`host_not_in_source:<id>`; redirect hops may leave the list and are re-checked).
  Registry lookups use the `wikidata.api` source (bucket `wikidata`).
* **Spacing floor:** spacing is `max(opts.spacingMs, att_sources.spacing_ms)`; a caller can only slow down.
* **Per-day budget is charged inside `politeFetch`** for every request made (redirect hops and the AQS retry
  included): units are taken from `att_take_budget(bucket)` in chunks of up to 25 (never more than the run cap left)
  and any unspent units are given back in `Run.finish()` through `att_budget_refund` (a bucket spent by a kill stays
  spent). `budget(run, bucketOrSource).take()` is now an optional look-ahead that reserves a unit which the next
  `politeFetch` in that bucket consumes, so nothing is charged twice.
* **Credentials never cross origins:** on a cross-origin redirect `Authorization`, `Proxy-Authorization`, cookies and
  any header whose name contains key/token/secret/auth/signature are dropped; an https -> http redirect is refused.
* **UA contact gate** (`att_config.contact_gate`, DEMARCATION §7.1 "UA that includes a contact"): before any request
  to a Wikimedia host (scope `wikimedia`; set `scope:'all'` to cover every host) the contact URL in the UA must answer
  2xx. The verdict is cached in `att_state['contact:ua']` (24 h when OK, 1 h when failing). As of 2026-09-25 04:56 UTC
  it answers **404**, so Wikimedia requests are refused (`ua_contact_unreachable`) until the page is published.
* **Budgets (DEMARCATION Q6 overrides ATTENTION_STACK §3.5):** <= 50% of any published limit; **1 request / 5 s per
  host where none is published** (`DEFAULT_SPACING_MS=5000`). Values and rationale are in `att_sources.spacing_ms`,
  `per_run_cap`, `per_day_cap`, `reason`. Per-day: `att_take_budget` (row lock). **Per-run caps are enforced centrally**
  in `politeFetch` (per source) and `budget()` (per source or bucket) from `att_sources.per_run_cap` and
  `att_config.run_caps` (`wikimedia` 500, `wikidata` 150); a caller can only lower them.
* **Wikimedia quiet window** 06:30-07:20 UTC (puzzle build): `att_take_budget` returns 0 for the `wikimedia` and
  `wikidata` buckets, and `politeFetch` refuses any wikipedia/wikidata/wikimedia host in that window.
* MediaWiki Action API: `maxlag=5` appended automatically; serial at >= 1.1 s; a `maxlag`/`ratelimited` error stops the
  host for the run.
* Wall budget 110 s (`Run.timeLeft()` / `outOfTime()`); CPU-lean `lines()` streaming reader (gzip optional).
* Only counts/ranks/indices go to `att_ingest`; `HLL` gives distinct counts without storing identifiers.
  `att_ingest` / `att_ingest_edges` / `att_ingest_candidates` pass `meta` through `ripples._att_clean_meta`: only keys
  in `att_config.meta_allow`, scalar values, strings <= 40 chars without `@`/URLs, <= 512 bytes total.
  `ripples._att_ident_like(text, source, strict)` screens **series keys** in `att_ingest` (reject reason
  `identifier_like_key`), edge keys and candidate labels: URLs, `did:plc:`/`did:web:`, e-mail/fediverse `user@host`,
  `*.bsky.social|app`, leading-`@` handles (Wikipedia titles such as `@` are exempt), and, for `bsky.*`/`masto.*`
  labels, bare-domain handles (`alice.example.com`, `name.dev`).

## Ledger overrides (record in the DEMARCATION §6.7 ledger; the owner confirms)

* **Citi Bike trip archive via `tripdata.s3.amazonaws.com`** (att-world, 2026-09-25): the virtual-host address of the
  public bucket (robots.txt 404) instead of path-style `s3.amazonaws.com` (robots.txt 403 AccessDenied, S3's generic
  answer for the bucket-less root). Full entry in `att_state['ledger:citibike.trips']`; see "att-world" below.

* **Wikidata `wbgetentities` (`www.wikidata.org/w/api.php`)** is used by `att-registry` under the DEMARCATION §7.1
  lead decision (GREEN with conditions: honest UA with a contact URL, `maxlag=5`, serial requests, no retry after
  429/503). ATTENTION_STACK §0 rule 5 still lists it as policy-D1-pending and the §3 matrix row still says R; §7.1
  overrides both. If the owner overrules §7.1, switch `fetchFacts` to `Special:EntityData/{QID}.json` (robots-allowed)
  and title lookups to the pagelinks/`page_props` dumps.
* **Budgets:** DEMARCATION §1.1 Q6 (<= 50% of the published limit; 1 req / 5 s otherwise) overrides the ATTENTION_STACK
  §3.5 figures. The seeded rows were rewritten in `sql/07` with the rationale in `att_sources.reason`.

## Free tier vs Pro

`ripples.att_config`: `profile='free'`, `panel_size=300`, `hourly_active_only=true`, `db_cap_mb=400`
(`att_ingest` refuses writes once the whole DB is within 10 MB of the cap). Switch with
`select ripples.att_set_profile('pro');` (panel 1000, hourly for all, cap 7 GB) and then rebuild the panel with
`call_collector('att-registry','{"mode":"panel","params":{"rebuild":true}}')`.

## Cron (UTC)

| Job | Schedule | Command |
|---|---|---|
| `att-tick-hops-a` | `33-59 7 * * *` | `select ripples.att_tick('hops')` |
| `att-tick-hops-b` | `0-18 8 * * *` | `select ripples.att_tick('hops')` |
| `att-backfill` | `*/2 10-23 * * *` | `select ripples.att_tick('backfill')` (backfill + resolve jobs, off-peak) |
| `att-registry` | `52 9 * * *` | `att_registry_maintain()` (30-day idle trends -> dormant) + `att-registry {"mode":"bootstrap"}` |

Collector crons (§3.4) are owned by the collector builders.

att-social crons: `att-jetstream` `1-56/5 * * * *` (live lane; skipped when `att_social_jet_budget('live')` says the
bsky.jet budget is spent/killed); `att-jetstream-catchup` `* * * * *` (no edge call unless the live cursor lags > 30 min
with budget left, or the one-off buffer replay lane `jet.bf` is unfinished and the budget left exceeds the live reserve); `att-mastodon-1/2/3` `5/11/17 6,18 * * *`
(three key slices); `att-hn` `6 0-8/2 * * *`; `att-stackex` `8 6 * * *`. HN / Stack Exchange 400-day backfills run through
`att_tick('backfill')` (`att-backfill`).

## Owner actions

1. **Publish `https://bensunter.com/ripples/methods/`** (the UA contact URL; owned by the main build per SPEC §
   `/ripples/methods/`). It returns 404 today, so the contact gate blocks every Wikimedia request (Wikidata lookups,
   AQS) until it resolves; the gate re-checks hourly. The UA string itself is fixed by the hard rules and was not
   changed. Emergency only: `update ripples.att_config set value = value || '{"enabled": false}' where key = 'contact_gate';`
   (not recommended: §7.1 requires a working contact).
2. Review any permanent kill (`select k, v from ripples.att_state where k like 'kill:%' and v->>'permanent' = 'true'`)
   and clear it only after review: `select ripples.att_host_unkill('<host>');`.
3. Provide a contact email to enable SEC EDGAR (UA, `att_sources.enabled`, and the `isRed()` SEC entry all change).
4. Confirm the ledger overrides above (Wikidata wbgetentities, budgets, Citi Bike virtual-host bucket).

## Probe functions to delete (owner action)

These were redeployed as tiny `410 Gone` stubs (no token required, no outbound calls). Delete them in the Supabase
dashboard (Edge Functions) when convenient:

* `probe-att-search`, `probe-att-social`, `probe-att-charts`, `probe-att-money`, `probe-att-world`, `probe-att-news`
* `probe-holes-free-keys`, `probe-holes-archives`, `probe-holes-global`, `probe-holes-fandom-consumption`

(`probe-og`, `probe-og2`, `probe-sources`, `probe-cors` belong to other workstreams and were not touched. Note for
the lead/W4: `probe-sources` v4 is still ACTIVE (token-gated) and contains RED calls: Reddit, Google News RSS, Yahoo,
Stooq, YouTube trending, NWS, GDELT DOC, and Google Trends explore/widgetdata/batchexecute with cookie reuse. It should be
stubbed or deleted like the probes above.)

## State after the core build (2026-09-25 ~04:10 UTC)

* `att_sources`: 71 rows (36 enabled ship-now sources; `sec.efts` disabled "needs owner contact email";
  `wiki.eventstreams` GREEN but no collector yet; 9 key, 6 policy-D1, 17 paid, 1 manual rows disabled with reasons).
* `att_topics`: 419 active (77 v4 hop/cascade articles from `public.signals` + 342 current trending from
  `public.wiki_top`), 300 frozen panel topics (`in_panel`, 30 per enwiki baseline decile, round-robin over 16
  categories; 52 of them are also active). Seed `panel-2026Q4`; summary in `att_state['panel.build']`.
* AQS returned 429 at ~4 req/s during panel sizing, so `wikimedia.org` is stopped until 2026-09-26 00:00 UTC and
  tomorrow's `wikimedia` cap is 750 (kill switch working as designed). Wikimedia (AQS) spacing is now 500 ms.
  To lift early (owner/lead decision only): `delete from ripples.att_state where k = 'kill:wikimedia.org';`
* Second verification round (~04:56 UTC): `att_sources` 72 rows / 37 enabled (+`wikidata.api`); 6 active topics
  retired by the extended SKIP rules (September 21/22/23, Deaths in 2026, States and union territories of India,
  List of Mushoku Tensei characters) -> 413 active; the panel is unchanged (300). Generic single-word aliases were
  dropped from term keys (`_att_alias_ok`), e.g. `cookie` for HTTP cookie and `left` for Die Linke.
* ~2,000 backfill jobs are queued for `att-social`, `att-wiki`, `att-charts`, `att-market`; they are dispatched only
  after each builder runs `select ripples.att_fn_live('<fn>')`.

## Contract changes in ATT_VERSION 2026-09-25.3 (collector builders)

* `FetchOpts.source` is **required** and must be an enabled `att_sources` row whose `hosts` contain the URL's host
  (subdomains match). Add your hosts to the row before deploying.
* `spacingMs` can only raise the source's `spacing_ms`.
* `politeFetch` charges the per-day budget itself (new skip reason `daily_budget_spent:<bucket>`); calling
  `budget().take()` first is optional and is not double-charged. Unspent chunk units are refunded at `finish()`.
* New skip reasons: `source_required`, `unknown_source:<id>`, `host_not_in_source:<id>`, `insecure_redirect`,
  `ua_contact_unreachable`, `daily_budget_spent:<bucket>`.
* New exports: `bucketOf(sourceOrBucket)`, `CONTACT_URL`. `wikiApiJson(run, url, source = "wikidata.api")`.
* `Run` gained `pool`, `reserved`, `budgetOut`, `aqsRetried`, `contactGate`, `contactVerdict`.
* New RPC (service_role only): `att_budget_refund(p_bucket text, p_n int) -> int`. `att_ingest` has the new reject
  reason `identifier_like_key`.

## Contract changes in ATT_VERSION 2026-09-25.2 (collector builders)

* `politeFetch(run, url, opts)` now also refuses: disabled sources (`source_disabled:<src>`), the per-run cap
  (`per_run_cap:<src>`), the Wikimedia quiet window (`wm_quiet_window`), a host leased by another run (`host_busy`), and
  barrier redirects. It always uses `redirect:"manual"` (caller `redirect` is ignored). Always pass `source`.
* Default spacing without a source row is 5000 ms (`DEFAULT_SPACING_MS`).
* New exports: `hostLease(run, host)`, `runCap(run, sourceOrBucket)`, `isWikimediaHost(host)`, `isBarrierUrl(url)`,
  `DEFAULT_SPACING_MS`. `killHost(run, host, status, source?, barrier?)` gained the `barrier` argument.
* `Run` gained `leases`, `leaseId`, `reqBySource`, `runCaps`, `quiet`; `Run.finish()` releases leases.
* New RPCs (service_role only): `att_host_kill(p_host, p_status, p_source=null, p_reason=null)` (4-arg; the 3-arg
  form was dropped), `att_host_lease_take(p_host, p_run, p_fn, p_ttl_s) -> boolean`,
  `att_host_lease_release(p_run) -> int`; SQL only: `ripples.att_host_unkill(host)`, `ripples.att_host_killed(host)`,
  `ripples._att_clean_meta(jsonb)`.
* `att_ingest*` sanitise `meta` (allow-list `att_config.meta_allow`; add keys there if a collector needs one).

## att-market (W7 money + institutional collector, 2026-09-25, MARKET_VERSION 2026-09-25.m8)

**Sources and what is stored** (counts / volumes / prices only; titles are used transiently for topic matching and as
`att_trend_candidates` labels; nothing raw is published; Storage bucket `att-raw` is private, no storage policies):

| Mode (cron UTC) | Source rows | Series (source / metric / key) | Notes |
|---|---|---|---|
| `finra` (06:02) | fetch `finra.api`, ingest `finra.shvol` | `finra.shvol/n/<TICKER>` value = total off-exchange volume (all TRF facilities), aux = short share; `__total__` (aux = market short share, meta coverage = tickers) | Previous trading day (NYSE holiday calendar 2024-2027) from the FINRA Query API `regShoDaily` (~28.5k rows = 6 pages of 5,000, sorted by symbol/facility/market). Consolidated day mirrored to `att-raw/finra/YYYYMMDD.txt.gz` (CNMS layout `Date|Symbol|ShortVolume|ShortExemptVolume|TotalVolume|Market`). Rolling baseline `att-raw/finra/_ring.bin` (90 trading days x ~19k tickers, float32). Abnormal-volume top 50: robust z of ln(1+v) vs the ticker's own t-77..t-15 trading days (>= 28 obs, median >= 50k shares), ratio >= 3 and z >= 4 -> `att_trend_candidates(source finra.shvol, geo US, label = ticker, meta {k:ticker, z, ratio})`. Active once 28 baseline days exist (i.e. after ~43 mirrored trading days) |
| `backfill` `{source:'finra.api', files:true}` (job `finra:files`) | same | same, per mirrored day | Up to 400 trading days newest first, 3 days (18 requests) per run, requeued 60 s later; 10:05 UTC next day once the daily budget (500) is spent (att-backfill only runs 10:00-23:58 UTC). The Query API keeps only ~1 year (first day 2025-09-25): empty days are kept in `finra.state.nodata` for the whole window (never re-requested) and when the 3 trading days right below the oldest mirrored day are empty, `finra.state.floor` is set and the job finishes (~250 trading days) |
| `backfill` `{source:'finra.shvol', keys}` | same | ticker series, 400 days | One date-range API query per 3 tickers (new registry tickers get history at once). Zeros are written only from the ticker's own first reported day on (never before the API's retention edge); META: 251 trading days 2025-09-25..2026-09-24 |
| `polymarket` (06:03) | `poly.mkt` | `m:<id>/vol24h` (aux liquidity), `e:<event id>/vol24h` (aux openInterest), `topic:<topic_id>/vol24h` (aux OI, meta n_mkts), `__total__`, `m:<id>/p` (CLOB daily price, topic-linked) | Gamma `/markets` by volume24hr, 100 per page (API cap), 15 pages, down to $1k; sports/esports excluded (sportsMarketType, gameStartTime, sports fee type, event league/gameId, league/game regex); recurring short-horizon markets (open -> end < 2 days) excluded; a complete snapshot replaces the day's earlier vol24h rows (one snapshot per day, `att_market_clear_day`); topic match = whole-word registry terms (`att_topic_terms`); CLOB `prices-history` full history once per mapped market, then 1 week |
| `kalshi` (06:04, 06:06, 06:08, 06:10) | `kalshi.mkt` | `ev:<event_ticker>/vol24h` (aux open interest, meta n_mkts), `m:<market ticker>/vol24h`, `topic:<id>`, `__total__` | `/events?status=open&with_nested_markets=true`: ~14.6k open events = ~73 pages of 200 (~270 MB JSON) - too much CPU for one worker (one HTTP 546), so the crawl is split into 25-page runs with cursor + day sums in `att_state['kalshi.crawl']`. A same-day crawl whose last chunk is > 2 h old is not continued: it restarts from page 1 and first clears that day's kalshi.mkt vol24h rows and candidates (`att_market_clear_day`), so a day is never stitched from snapshots hours apart. Category Sports and short-horizon events skipped; `*_fp` strings parsed; per run the 80 busiest events and 40 busiest markets |
| `usaspending` (07:27) | `usasp.spend` | `<term>/usd` monthly obligations (day = 1st of month, meta monthly[, partial]) | spending_over_time by keyword over the current + 2 previous months; fiscal months mapped to calendar months; each of the 51 keys every 7 days (<= 12 per run); a keyword that times out (55 s) is skipped until its next turn, 2 timeouts end the run, and 3 timeouts in one UTC day (all runs, `att_state['usasp.slow']`) stop the host until the next UTC day (treated like a 503). Backfill jobs walk 3-month windows back 24 months; a window that times out is kept in `att_state['usasp.bfgap']` and retried first on the key's next backfill pass (the job stays open until it is fetched or has failed 3 times, then it is a logged gap, `extra.usasp_backfill.gave_up`) |
| `edgar` (07:26, cron inactive) | `sec.efts` (DISABLED) | `<term>/n` monthly filing counts | Implemented; refused while `sec.efts.enabled=false` and while att.ts lists sec.gov as RED (needs owner contact email) |

Discovery candidates (poly/kalshi): event volume24hr >= 3 x trailing 7-day mean of our own saved series, or an event
opened in the last 3 days with >= $250k (Kalshi: >= 250k contracts) and no history; evidence = clamp(log10 ratio).

**DEMARCATION Q3 decision (ledger):** `cdn.finra.org/robots.txt` answers 403 (S3-style), which Q3 treats as
disallowing; att.ts killed the host permanently on 2026-09-25 15:14 UTC. Q3: "the operator documents another channel ->
use that channel and grade it separately": the FINRA Query API (`api.finra.org`, robots.txt 404, anonymous access to
the public `regShoDaily` dataset) is row `finra.api` (yellow, 1 req / 5 s, 20 per run, 500 per day). Nothing uses
`cdn.finra.org` any more; leave it killed.

**Jobs:** merged backfill jobs are settled per key by the function (`att_market_jobs` + `att_jobs_done`), so a partial
run is retried within minutes instead of att.ts's 1 h requeue, and a host that is closed for the day (budget spent or
killed) waits until 10:05 UTC next day: budgets and day kills reset at 00:00 UTC, but `att-backfill`
(`att_tick('backfill')`) only runs `*/2 10-23`, so that is the first time the job can run. The `finra:files` job has priority 6 so ticker / USAspending jobs (5) go first.

**Platform note:** `public.call_collector` goes through pg_net, which here dispatches the next batch only after the
current one returns; a 110 s run therefore delays other queued collector calls by up to ~2 min. All att-market modes
stay within the 110 s wall budget.

## att-charts (W7 charts / builder / consumption collector, 2026-09-25, CHARTS_VERSION 2026-09-25.c9)

Stores ranks and counts only (labels = item / repo / package names for `att_trend_candidates`; no owners, handles or
text). List sizes come from `att_config.charts.<mode>.limit.{free,pro}` under `att_config.profile`.

| Mode (cron UTC) | Source (spacing, run/day cap) | Series | Discovery |
|---|---|---|---|
| `apple` (06:10-06:20, 6 slots) | `apple.rss` (5 s, 20/35) | rank per item (metric = feed, key = Apple id, geo = storefront us/gb/in/br/jp); 25 feeds (apps top-free/top-paid, music most-played, podcasts top, books top-free), 50 each | `new` + `jump` (>= 20 places) vs the previous snapshot; from day 2 |
| `steamspy` (06:12) | `steamspy` (2 s, 5/5) | top100in2weeks: yesterday's peak CCU per appid (metric `ccu`, aux = rank) | `new` / `jump`, from day 2 |
| `github` (06:14) | `gh.search` (12 s, 8/8), `gh.stars` (5 s, 25/25), unauthenticated | new repos (created in the last 7 days) by stars, keyed by numeric repo id; stargazer counts for registered repos | top 10 + velocity; stars/forks > 50 halves the evidence (star-farm guard) |
| `hf` (06:13) | `hf.trending` (1.5 s, 60/100) | trending models / spaces / datasets, keyed by `_id` (label without owner) | top 10 per list |
| `anilist` (06:17) | `anilist` (4 s, 25/150) | TRENDING_DESC anime + manga (isAdult:false; rank, aux = trending); per-media `mediaTrends` (metric `n`) for registered titles and the top 10 (8 aliases per query) | top 10 |
| `openlibrary` (06:15) | `ol.trending` (5 s, 5/5) | trending daily | top 10 |
| `tranco` (06:19) | `tranco.rank` (5 s, 2/2: list download + its redirect hop; /api never used) | streams the daily top-1M zip (local-header parser + `DecompressionStream('deflate-raw')`); keeps ranks for registered domains only | top-1k movers (new to the top 1k, or a jump >= max(20, 25%)) vs the previous top 1k, which `att_state` keeps only as one-way 12-hex SHA-256 digests in rank order (no readable domain list); from day 2 |
| `npm` (06:18) | `npm.dl` (5 s, 20/80) | range downloads; bulk for unscoped, one call per scoped package; 400-day backfill jobs | - |
| `pypi` (06:19) | `pypi.dl` (5 s, 20/30) | pypistats `overall?mirrors=false`, 180 days per call | - |
| `backfill` (via `att_tick`) | as above | npm.dl, pypi.dl, anilist, gh.stars (stargazer timestamps only for repos with <= 2000 stars) | - |

Evidence for discovery = 1 - ln(rank)/ln(N+1). Candidates are deduplicated per run (max evidence). **Pacing** is
end-to-start: the run records `detail.timing[source].min_idle_gap_ms`. A host whose `x-ratelimit-remaining` drops to
<= 1 is dropped for the run, so GitHub never reaches a 403 (a permanent kill). **Reference panels:** npm (12 packages)
and pypi (8 packages) are stored as normaliser series with no topic link. **npm gap days:** npm reports days it has
not computed yet as 0 for every package; zeros are not stored for `__total__` or for packages whose p75 > 100.
**npm backfill coverage (c8):** a key needs its 400-day fetch only while its first stored day is later than window
start + 30 days AND it was not backfilled in the last 30 days (`att_state['charts.npm.backfilled']`). c7 counted rows,
so `__total__` (349 rows after dropping zero days) was refetched over 400 days on every run.
**npm outage days (c9):** the daily window is 30 days (`charts.npm.days`; same number of requests as 7), so a day npm
recomputes late is refilled. Days older than the 3-day lag on which npm's all-packages total is 0 are npm outages; they
are listed (days only) in `att_state['charts.npm.gaps']` so the share transform skips them rather than dividing by a
missing normaliser. The list was seeded from stored data (48 days in the 400-day window, e.g. 2026-08-30..09-04,
09-07/08, 09-15, 09-17).
**Ops ledger:** manual interventions are recorded in `att_state['ledger:att-charts.ops']` (15g). Policy from c9: no
hand edits of robots cache entries or `att_budget` rows; an unavoidable override is appended to the ledger first.
**One list per day (c8):** apple, steamspy, gh.search, hf, anilist trending and openlibrary are snapshot lists; after a
fully ingested re-run on the same as_of day, `att_charts_prune` deletes that day's rows for items no longer on the list
(c7 left a stale gh.search row: 51 series for a top 50 on 2026-09-24).

**Apple feed host.** `rss.marketingtools.apple.com` (robots.txt 200, no rules). The legacy `rss.applemarketingtools.com`
301-redirects robots.txt to another host, which att.ts treats as a deny. Apple answers slowly (~8 s) and sometimes 504;
a failed feed is retried by a later run (max `charts.apple.max_tries` = 3 per day), a run stops after two failures in a
row, and six cron slots (06:10-06:20) cover 25 feeds. Daily cap 35 requests.

**Core fixes made while building att-charts (both att_ objects):** `sql/15d` (budget refunds were refused whenever a
chunk had taken the whole day's cap, which spent gh.search / steamspy / ol.trending / tranco.rank for the day after a
single request) and `sql/15e` (scoped npm packages were rejected as `@handles`).

## att-world (W7 world / real-economy collector, 2026-09-25, WORLD_VERSION 2026-09-25.w3)

Counts, levels and indices only. Response bodies are read transiently (IEM rows carry forecaster names, FEMA rows county
names, Citi Bike rows station names and ride ids): none of it is stored. No NWS `api.weather.gov` call exists (RED in
`isRed()`; IEM is the documented substitute). Attribution strings live in `att_sources.attribution` (FEMA non-endorsement
notice, "Indeed Hiring Lab ... (CC BY 4.0)", "GDACS, European Commission Joint Research Centre", "Iowa Environmental
Mesonet, Iowa State University", "Citi Bike System Data", USGS, TSA, MTA/NY Open Data).

| Mode | Source (spacing, run/day cap) | Endpoint | Series (source / metric / geo / key) | History |
|---|---|---|---|---|
| `tsa` | `tsa.pax` (5 s, 10/20) | `www.tsa.gov/travel/passenger-volumes` (current year) + `/<year>` pages | `tsa.pax / n / US / checkpoint` (travellers screened) | 2019-01-01 onwards (same-weekday baselines) |
| `usgs` | `usgs.eq` (5 s, 8/20) | ComCat `fdsnws/event/1/query` geojson, `minfelt=1` and `minmagnitude=4.5` | `felt` (sum of DYFI responses, aux = felt events), `m45` (count, aux = max mag), `sig` (sig >= 600 count, aux = max sig), `ev:<eventid> / felt` for events with >= 25 DYFI responses (aux = mag); geo ALL | 420 days, 105-day windows; the daily run re-reads 30 days (DYFI counts grow) |
| `iem` | `iem.warn` (10 s, 8/40) | IEM API `/api/1/vtec/sbw_interval.json?begints&endts` | key = VTEC `ph_sig` (`TO.W`, `SV.W`, `FF.W`, `MA.W`, `SQ.W`, `FA.Y` ...) + `__total__` (all warnings), distinct wfo/phen/sig/eventid/year per issuance UTC day; zero-filled; geo US | 420 days, 30-day windows |
| `fema` | `fema.decl` (5 s, 5/10) | OpenFEMA `v2/DisasterDeclarationsSummaries` (`$select`, `$filter`, `$top=10000`) | `all`, `DR`, `EM`, `FM`, `it:<incident type>`: distinct disasters declared per day (aux = designated areas); zero-filled; geo US | 420 days; daily re-reads 30 days |
| `gdacs` | `gdacs` (5 s, 2/4) | `www.gdacs.org/xml/rss.xml` | per type `EQ/TC/FL/VO/DR/WF/__all__`: `n` (current events, aux = orange+red), `pop` (population in orange/red events); `ev:<type><id> / alert` (alert score, aux = population) | none (warm-up) |
| `mta` | `mta.ridership` (5 s, 5/10) | Socrata `data.ny.gov/resource/sayj-mze2.json` | key = mode slug (`subway`, `bus`, `lirr`, `mnr`, `sir`, `aar`, `bt`, `cbd_entries`, `crz_entries`); geo US-NY | 2020-03-01 onwards; daily re-reads 21 days |
| `hiringlab` | `hiringlab.postings` (5 s, 4/8) | `raw.githubusercontent.com/hiring-lab/job_postings_tracker/master/US/{aggregate_job_postings_US,job_postings_by_sector_US}.csv` with `If-None-Match` | sector slug x metric `total`/`new` (index, 2020-02-01 = 100); `__total__` from the aggregate file (value = SA, aux = NSA); geo US | 420 days; afterwards only when upstream changed (304 otherwise), last 60 days re-written |
| `citibike` | `citibike.trips` (5 s, 8/4; 30/day only during the one-off backfill) | `tripdata.s3.amazonaws.com` (bucket listing + `JC-YYYYMM-citibike-tripdata[.csv].zip`) | `jc / n / US-NJ` (trips started per local day, aux = member trips) | 420 days of monthly JC files (2 per run); new month after the 6th |
| `all` | - | the above in sequence (`params.only`) | - | - |
| `backfill` | - | `params.source` = att_sources id | resumable (`att_state['world.bf.<source>']`, `next_cursor`) | - |

**Citi Bike NYC is partial by design.** The NYC monthly archive is ~1 GB per month (977 MB for 2026-08), far beyond the
110 s wall / edge CPU budget, so it is never downloaded; `citibike` always reports `status: partial` with the file size
(`att_state['world.citibike'].nyc`). Jersey City files (1-3 MB) are processed fully in memory (central-directory zip
parse + `DecompressionStream('deflate-raw')`). NYC daily trips need a GitHub Action (stream-unzip) if wanted later.

**Bucket host (ledger decision, 2026-09-25; owner to confirm).** `s3.amazonaws.com/robots.txt` answers 403
AccessDenied (sha256 `c72db483...`): S3's generic response for the bucket-less root of the path-style host, not a bot
barrier, but att.ts would treat it as a permanent kill. The bucket is therefore addressed virtual-host style
(`tripdata.s3.amazonaws.com`), whose `robots.txt` is a normal S3 404 NoSuchKey (sha256 `bf1b20d0...`, allowed). Both
addresses reach the same public bucket that Citi Bike links from its System Data page (DEMARCATION Q3: documented
channel). Terms: Citi Bike Data License Agreement (citibikenyc.com/data-sharing-policy), no use of its trademarks.
Recorded in `att_sources.license_note` and `att_state['ledger:citibike.trips']` (robots snapshots, terms, paths,
decision, re-check 2026-12-24).

**Discovery candidates** (`att_trend_candidates`, day = as_of): USGS events of the last 3 days with felt >= 50, sig >= 600 or
PAGER orange/red (label "<region> earthquake", meta k = event id); FEMA declarations of the last 3 days (named hurricanes /
named fires, otherwise "<year> <State> <incident type>", geo US-<state>); GDACS orange/red current events that started in
the last 10 days ("Cyclone <Name>", volcano name, or "<year> <country> <type>"). IEM warning surges are not emitted as
candidates (their labels would not resolve to articles); att_score can z-score `iem.warn` directly.

**Budgets.** `sql/16` rows (DEMARCATION Q6, 1 request / 5 s where no limit is published, IEM 1 / 10 s); the per-day caps
cover the daily calls plus the one-off backfill (citibike.trips was raised to 30/day on 2026-09-25 for the 13-month JC
backfill; the cron job `att-world-citibike-cap` from `sql/16c` puts the row back to 4/day, lowers that day's
`att_budget` row, and unschedules itself once the backfill is complete, at the latest on 2026-09-28; it fired at 19:07 UTC on 2026-09-25).
**Status labels (w3):** a source stopped by `per_run_cap:<source>` or `daily_budget_spent:<source>` is reported
`budget_exhausted` (note names the cap), never `http_error`; run 599 (IEM backfill) was relabelled in `sql/16c`. Every request goes through `politeFetch`: robots.txt
checked for every host (tsa.gov, fema.gov, data.ny.gov, gdacs.org, mesonet 200 with no matching disallow; usgs.gov,
raw.githubusercontent.com, tripdata bucket 404 = allowed).

**State.** `att_state`: `world.bf.<source>` (backfill cursors), `world.hiringlab` (ETags, latest day), `world.citibike`
(months done, NYC file size), `world.iem.keys`, `world.fema.types` (zero-fill key sets).

**Backfill (2026-09-25, direct `call_collector` runs 593-616):** tsa.pax 2,824 days (2019-01-01..2026-09-24, 8 pages);
mta.ridership 2,398 days x 9 modes (2020-03-01..2026-09-23); fema.decl 420 days x 16 keys (1,989 records); usgs.eq 420 days
(4 windows x 2 queries) + 762 per-event felt series; iem.warn 420 days x 14 keys (14 windows, two runs); hiringlab.postings
414 days x 96 series (2025-08-01..2026-09-18). citibike.trips: complete on 2026-09-25 18:57 UTC, 13 JC months
(JC-202508..JC-202608) = 395 days (2025-08-01..2026-08-31; the 420-day window starts 2025-08-01 and the 2026-09 file is
not published until October); the last 5 months came from direct runs 787, 789 and 791 (2 + 2 + 1 files, 8 requests; day budget 21 used), after which
`world.bf.citibike.trips.complete = true` and the cap cron reset the source to 4/day and unscheduled itself (19:07 UTC).

**Retention caveat.** TSA (2019+) and MTA (2020+) keep more than 400 days on purpose (same-weekday baselines across
years). These series have no topic link; if `att_retention()` trims unlinked series to 400 days it should exempt
`tsa.pax` and `mta.ridership` (not implemented by att-world; `att_retention` does not exist yet).

**Known limitations (att-world w3).** GDACS labels numbered depressions literally ("Cyclone One"); USGS labels use the
ComCat place region ("Sun Valley, Nevada earthquake") and may not resolve to an article; USGS per-event felt series
(felt >= 25) add ~2 series/day (762 for the 420-day backfill); GDACS snapshots are stored under as_of (run date - 1) like
the other snapshot collectors.

## att-wiki (W7 Wikimedia collector, 2026-09-25, WIKI_VERSION 2026-09-25.w2)

Every request goes through `politeFetch` with a `wiki.*` source, so all of them draw on the shared **`wikimedia`
bucket (1,500/day attention share, `att_config.budgets.wikimedia`)**, charged per request (unspent chunk units refunded),
refused 06:30-07:20 UTC (quiet window), refused while the UA contact page is not 2xx (contact gate), serial per host at
>= 1 s (after the 2026-09-25 429 at ~4 req/s from the shared Supabase IP), one AQS 429 retry per run, then the host is
stopped for the UTC day. Only ranks, counts and indices are stored. A source's own `per_day_cap` is enforced as well
when it draws on the shared bucket (`wiki.cs`: 3/day, charged on the per-source bucket `src:wiki.cs`).

| Mode (cron UTC) | Source | What is stored |
|---|---|---|
| `top_country` (06:23, 09:23, 13:23) | `wiki.topcc` | AQS `top-per-country/{CC}/all-access/{y}/{m}/{d}` for the 45 countries in `att_config.wiki.countries` (previous UTC day; resumable in `att_state['topcc.day:<day>']`, a 404 country is retried at most 3 times). Registry titles: `wiki.topcc / rank / <CC> / <lang>:<Title>` (value = rank, aux = `views_ceil`). **Reach** (§6.2): `wiki.topcc / reach / ALL / <lang>:<Title>` = number of fetched countries whose top 1,000 contains the title (aux = summed views_ceil, meta.coverage = countries fetched), written for every registry title incl. zeros (`att_wiki_topcc_reach`). Discovery candidates: rank <= 200, SKIP rules applied, **not evergreen** = views >= 2x the median of the title's level in that country's previous 3 lists (absence counts as that list's rank-1000 threshold, an upper bound): `att_trend_candidates(source wiki.topcc, geo CC, label, rank, value = views_ceil, evidence = 1 - ln(rank)/ln(N+1), meta {lang, ratio, new, method})`. Needs prior snapshots (`att_state['topcc.snap:<CC>:<day>']`, kept 5 days), so candidates start on the second collected day. Rows hidden by Wikimedia's privacy threshold are never reconstructed |
| `pageviews` (07:21, 07:24, 07:27; :07 10-23) | `wiki.pv` | AQS per-article (all-access, agent=user) for registry titles (`att_wiki_pv_plan`): **first sight = one call for 420 days** (zero-filled), then incremental from `last_day + 1`. A series is complete only if it has **every day** from `as_of - 400` to its last day; a gappy series (e.g. mirrored from `public.signal_obs` with holes, or an older core-build series) is re-planned as one full-window AQS call, which zero-fills correctly (holes in `signal_obs` are never zero-filled in SQL, because they may be collection gaps); active topics daily, panel-only every `panel_every_days` (free 2, pro 1); priority active-first > active-incr > panel-first > panel-incr, stalest first. Titles that are `public.signals` rows are **mirrored from `public.signal_obs` in SQL** (no request) once their mirrored history is complete for 400 days. A first-sight 404 is remembered in `att_state['wiki.pv.nodata']` and retried after 7 days. Each run also closes queued backfill jobs that no longer need a fetch (`att_wiki_jobs_sweep`) |
| `backfill` (att_tick, */2 10-23) | `wiki.pv` | Same fetch for the merged job keys (`first` only); jobs are settled per key: done, or requeued to 10:05 UTC next day (budget spent / 429 kill), +6 h (contact gate / permanent kill), +3 min (time, run cap) |
| `mediarequests` (07:30, 12:37) | `wiki.media` | Lead image per active topic (free profile; `media_scope.pro = all` adds the panel) = the topic's Wikidata **P18** claim from `www.wikidata.org/wiki/Special:EntityData/<QID>.json` (a `/wiki/` path, robots.txt checked; body streamed and read only up to the end of the P18 claim; preferred rank first, deprecated ignored; max `entitydata_max_mb`; one call per topic, at most half of the day's media allowance) -> key `commons:<File_name>`, `match.path` = `/wikipedia/commons/<md5[0]>/<md5[0..2]>/<File_name>`. The Action API route (`prop=pageimages`, 50 titles/call, maxlag=5) runs **only if the owner sets `att_config.wiki.action_api_ok = true`** and adds `wikipedia.org` to `att_sources.wiki.media.hosts` (DEMARCATION §7.1 vs §0 / matrix row 200); no free image -> `att_state['wiki.media.none']` (re-checked after 30 days). Then AQS `mediarequests/per-file/all-referers/user/<path>/daily` (420 days on first sight, then every 3 days). **Deferred while any active topic still lacks its pageview history**; soft cap `media_day_cap` = 200 requests/day inside the shared bucket |
| `clickstream_small` (10:31 on the 7th) | `wiki.cs` | HEAD on `dumps.wikimedia.org/other/clickstream/<month>/clickstream-<wiki>-<month>.tsv.gz` (robots.txt checked) for `cs_wikis` (pt, pl, zh). Only a file <= `cs_max_mb` (8 MB compressed) is streamed (edges touching registry titles: top 20 out-edges, `other-*` in-edges, in-edges n >= 50 -> `att_edges` grain month). Every published clickstream file is far larger than that, so in practice each wiki is reported `github_action_only:<wiki>:<MB>` and **clickstream stays GitHub-Action-only** (`ripples-clickstream.yml`, SPEC) |

Progress: `select ripples.att_wiki_progress();` (registry keys by plan state, first-sight backlog, `with_400d_complete` = every
one of the last 400 days present (`with_400d_span_only` for comparison), `gappy_series`, `topcc_countries_latest`,
the wikimedia bucket for today and later, topcc series, media keys). No request is made by it.
