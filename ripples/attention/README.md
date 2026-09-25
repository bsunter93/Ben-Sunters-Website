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
| `functions/att-social/index.ts` (+ `att.ts` copy) | Social collector (SOCIAL_VERSION 2026-09-25.s4): `jetstream`, `mastodon`, `hn`, `stackex`, `backfill` (hn.algolia, se.api), `ping`. s4: backfill dispatches whose host is closed for the UTC day (daily budget spent, day/permanent kill) requeue their jobs for 00:10 UTC next day instead of +1 h |
| `sql/14_att_market.sql` | Migration `att_market_support` (att-market): source row `finra.api` (FINRA Query API, DEMARCATION Q3 channel), `att_config.market`, meta keys, `att_topic_terms`, `att_series_stats` (+ public wrappers, service_role only), usasp.spend / sec.efts term keys for non-people topics, the FINRA file backfill job |
| `sql/14b_att_market_jobs.sql` | Migration `att_market_jobs`: `att_market_jobs(ids)` (per-job keys for per-key completion of merged backfill jobs) |
| `sql/14c_att_market_cron.sql` | Migration `att_market_cron`: `att-finra` 06:02, `att-predmkts` 06:03, `att-kalshi` 06:04 (+ `att-kalshi-2/3/4` 06:06/06:08/06:10), `att-usasp` 07:27, `att-edgar` 07:26 (inactive), `att_fn_live('att-market')`; plus the ops record of the first-day changes (config, budget row, clean-ups, temporary FINRA backfill cron) |
| `functions/att-market/index.ts` (+ `att.ts` copy) | Money / institutional collector (MARKET_VERSION 2026-09-25.m6): `finra`, `polymarket`, `kalshi`, `usaspending`, `edgar` (disabled), `backfill`, `ping`. See "att-market" below |
| `sql/15_att_charts.sql` | Migration `att_charts_collector` (att-charts): `att_config.charts` (per-mode settings, free/pro list sizes, npm/pypi reference panels), meta keys `kind/feed/score/n_geos/list`, `att_charts_prev` (previous snapshot per metric/geo), `att_charts_series_info` (+ public wrappers, service_role only) |
| `sql/15b_att_charts_cron.sql` | Migrations `att_charts_cron` + `att_charts_cron2`: `att-apple-1..6` 06:10/12/14/16/18/20, `att-steamspy` 06:12, `att-hf` 06:13, `att-github` 06:14, `att-openlibrary` 06:15, `att-anilist` 06:17, `att-npm` 06:18, `att-pypi` 06:19, `att-tranco` 06:19 |
| `sql/15c_att_charts_ops_2026-09-25.sql` | Operational record for att-charts (tranco caps, ChatGPT SDK keys, Apple robots cache fix, `att_fn_live('att-charts')`) |
| `sql/15d_att_budget_refund_fix.sql` | Migration `att_budget_refund_fix` (core fix found by att-charts): `att_budget.killed`; `att_budget_refund` refuses refunds only for kill-spent buckets (it used to refuse whenever used = cap, so a chunk that took the whole day's cap was never refunded); `att_host_kill` sets `killed` |
| `sql/15e_att_ident_npm_scoped.sql` | Migration `att_ident_npm_scoped`: `_att_ident_like` no longer rejects scoped npm package keys (`@scope/name`, source `npm.dl` only) as handles |
| `functions/att-charts/index.ts` (+ `att.ts` copy) | Charts / builder / consumption collector (CHARTS_VERSION 2026-09-25.c7): `apple`, `steamspy`, `github`, `hf`, `anilist`, `openlibrary`, `tranco`, `npm`, `pypi`, `backfill` (npm.dl, pypi.dl, anilist, gh.stars), `ping`. See "att-charts" below |
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

att-social crons: `att-jetstream` `1-56/5 * * * *` (live lane); `att-jetstream-catchup` `* * * * *` (no-op unless the
live cursor lags > 30 min or the one-off buffer replay lane `jet.bf` is unfinished); `att-mastodon-1/2/3` `5/11/17 6,18 * * *`
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
4. Confirm the two ledger overrides above.

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

## att-market (W7 money + institutional collector, 2026-09-25, MARKET_VERSION 2026-09-25.m6)

**Sources and what is stored** (counts / volumes / prices only; titles are used transiently for topic matching and as
`att_trend_candidates` labels; nothing raw is published; Storage bucket `att-raw` is private, no storage policies):

| Mode (cron UTC) | Source rows | Series (source / metric / key) | Notes |
|---|---|---|---|
| `finra` (06:02) | fetch `finra.api`, ingest `finra.shvol` | `finra.shvol/n/<TICKER>` value = total off-exchange volume (all TRF facilities), aux = short share; `__total__` (aux = market short share, meta coverage = tickers) | Previous trading day (NYSE holiday calendar 2024-2027) from the FINRA Query API `regShoDaily` (~28.5k rows = 6 pages of 5,000, sorted by symbol/facility/market). Consolidated day mirrored to `att-raw/finra/YYYYMMDD.txt.gz` (CNMS layout `Date|Symbol|ShortVolume|ShortExemptVolume|TotalVolume|Market`). Rolling baseline `att-raw/finra/_ring.bin` (90 trading days x ~19k tickers, float32). Abnormal-volume top 50: robust z of ln(1+v) vs the ticker's own t-77..t-15 trading days (>= 28 obs, median >= 50k shares), ratio >= 3 and z >= 4 -> `att_trend_candidates(source finra.shvol, geo US, label = ticker, meta {k:ticker, z, ratio})`. Active once 28 baseline days exist (i.e. after ~43 mirrored trading days) |
| `backfill` `{source:'finra.api', files:true}` (job `finra:files`) | same | same, per mirrored day | 400 trading days newest first, 3 days (18 requests) per run, requeued 60 s later; 00:10 UTC next day once the daily budget (500) is spent |
| `backfill` `{source:'finra.shvol', keys}` | same | ticker series, 400 days | One date-range API query per 3 tickers (new registry tickers get history at once); META done (275 trading days) |
| `polymarket` (06:03) | `poly.mkt` | `m:<id>/vol24h` (aux liquidity), `e:<event id>/vol24h` (aux openInterest), `topic:<topic_id>/vol24h` (aux OI, meta n_mkts), `__total__`, `m:<id>/p` (CLOB daily price, topic-linked) | Gamma `/markets` by volume24hr, 100 per page (API cap), 15 pages, down to $1k; sports/esports excluded (sportsMarketType, gameStartTime, sports fee type, event league/gameId, league/game regex); recurring short-horizon markets (open -> end < 2 days) excluded; topic match = whole-word registry terms (`att_topic_terms`); CLOB `prices-history` full history once per mapped market, then 1 week |
| `kalshi` (06:04, 06:06, 06:08, 06:10) | `kalshi.mkt` | `ev:<event_ticker>/vol24h` (aux open interest, meta n_mkts), `m:<market ticker>/vol24h`, `topic:<id>`, `__total__` | `/events?status=open&with_nested_markets=true`: ~14.6k open events = ~73 pages of 200 (~270 MB JSON) - too much CPU for one worker (one HTTP 546), so the crawl is split into 25-page runs with cursor + day sums in `att_state['kalshi.crawl']`. Category Sports and short-horizon events skipped; `*_fp` strings parsed; per run the 80 busiest events and 40 busiest markets |
| `usaspending` (07:27) | `usasp.spend` | `<term>/usd` monthly obligations (day = 1st of month, meta monthly[, partial]) | spending_over_time by keyword over the current + 2 previous months; fiscal months mapped to calendar months; each of the 51 keys every 7 days (<= 12 per run); a keyword that times out (55 s) is skipped until its next turn, 2 timeouts end the run. Backfill jobs walk 3-month windows back 24 months |
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
killed) waits until 00:10 UTC. The `finra:files` job has priority 6 so ticker / USAspending jobs (5) go first.

**Platform note:** `public.call_collector` goes through pg_net, which here dispatches the next batch only after the
current one returns; a 110 s run therefore delays other queued collector calls by up to ~2 min. All att-market modes
stay within the 110 s wall budget.

## att-charts (W7 charts / builder / consumption collector, 2026-09-25, CHARTS_VERSION 2026-09-25.c7)

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
| `tranco` (06:19) | `tranco.rank` (5 s, 2/2: list download + its redirect hop; /api never used) | streams the daily top-1M zip (local-header parser + `DecompressionStream('deflate-raw')`); keeps ranks for registered domains only | top-1k movers (new to the top 1k, or a jump >= max(20, 25%)) vs the previous list in `att_state`, from day 2 |
| `npm` (06:18) | `npm.dl` (5 s, 20/80) | range downloads; bulk for unscoped, one call per scoped package; 400-day backfill jobs | - |
| `pypi` (06:19) | `pypi.dl` (5 s, 20/30) | pypistats `overall?mirrors=false`, 180 days per call | - |
| `backfill` (via `att_tick`) | as above | npm.dl, pypi.dl, anilist, gh.stars (stargazer timestamps only for repos with <= 2000 stars) | - |

Evidence for discovery = 1 - ln(rank)/ln(N+1). Candidates are deduplicated per run (max evidence). **Pacing** is
end-to-start: the run records `detail.timing[source].min_idle_gap_ms`. A host whose `x-ratelimit-remaining` drops to
<= 1 is dropped for the run, so GitHub never reaches a 403 (a permanent kill). **Reference panels:** npm (12 packages)
and pypi (8 packages) are stored as normaliser series with no topic link. **npm gap days:** npm reports days it has
not computed yet as 0 for every package; c7 does not store zeros for `__total__` or for packages whose p75 > 100.

**Apple feed host.** `rss.marketingtools.apple.com` (robots.txt 200, no rules). The legacy `rss.applemarketingtools.com`
301-redirects robots.txt to another host, which att.ts treats as a deny. Apple answers slowly (~8 s) and sometimes 504;
a failed feed is retried by a later run (max `charts.apple.max_tries` = 3 per day), a run stops after two failures in a
row, and six cron slots (06:10-06:20) cover 25 feeds. Daily cap 35 requests.

**Core fixes made while building att-charts (both att_ objects):** `sql/15d` (budget refunds were refused whenever a
chunk had taken the whole day's cap, which spent gh.search / steamspy / ol.trending / tranco.rank for the day after a
single request) and `sql/15e` (scoped npm packages were rejected as `@handles`).
