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

## Hard rules implemented in att.ts

* UA `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)` on every request (and `Api-User-Agent` for Wikimedia). No email anywhere.
* robots.txt honoured for every host except Wikimedia documented APIs (DEMARCATION §7.1): cached 24 h in
  `att_state['robots:<origin>']`; 401/403/429/5xx/unreachable robots = deny; 404 = allow.
* RED denylist in `isRed()` (Reddit, trends24/getdaytrends, TikTok, Google/Bing/DDG/Amazon/eBay suggest, Google News,
  Yahoo, Stooq, Nasdaq, Google Finance, CNN F&G, Cboe, Spotify, Billboard, BoxOfficeMojo, Google Play, FlixPatrol,
  Stocktwits, OpenSky, Cloudflare Radar, Google Trends internal endpoints, GDELT DOC API, and SEC while it has no
  owner email). `politeFetch` refuses these before any network call.
* Per-host serial queue with spacing (`att_sources.spacing_ms`, default 1 s). No cookies, no proxies.
* 429/503/403: no retry; host stopped until next UTC midnight (`att_state['kill:<host>']`), the source's budget for
  today is spent, and tomorrow's cap is halved (429/503). The only exception is AQS (`aqsRetry`): one retry after 5 s.
* MediaWiki Action API: `maxlag=5` is appended automatically; a `maxlag`/`ratelimited` error stops the host for the run.
* Budgets: `att_take_budget(source_or_bucket, n)`. Wikimedia sources share bucket `wikimedia` (1,500/day), which
  returns 0 between 06:30 and 07:20 UTC (puzzle build window). `wikidata` bucket: 300/day.
* Wall budget 110 s (`Run.timeLeft()` / `outOfTime()`); CPU-lean `lines()` streaming reader (gzip optional).
* Only counts/ranks/indices go to `att_ingest`; `HLL` gives distinct counts without storing identifiers.

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

## Probe functions to delete (owner action)

These were redeployed as tiny `410 Gone` stubs (no token required, no outbound calls). Delete them in the Supabase
dashboard (Edge Functions) when convenient:

* `probe-att-search`, `probe-att-social`, `probe-att-charts`, `probe-att-money`, `probe-att-world`, `probe-att-news`
* `probe-holes-free-keys`, `probe-holes-archives`, `probe-holes-global`, `probe-holes-fandom-consumption`

(`probe-og`, `probe-og2`, `probe-sources`, `probe-cors` belong to other workstreams and were not touched.)

## State after the core build (2026-09-25 ~04:10 UTC)

* `att_sources`: 71 rows (36 enabled ship-now sources; `sec.efts` disabled "needs owner contact email";
  `wiki.eventstreams` GREEN but no collector yet; 9 key, 6 policy-D1, 17 paid, 1 manual rows disabled with reasons).
* `att_topics`: 419 active (77 v4 hop/cascade articles from `public.signals` + 342 current trending from
  `public.wiki_top`), 300 frozen panel topics (`in_panel`, 30 per enwiki baseline decile, round-robin over 16
  categories; 52 of them are also active). Seed `panel-2026Q4`; summary in `att_state['panel.build']`.
* AQS returned 429 at ~4 req/s during panel sizing, so `wikimedia.org` is stopped until 2026-09-26 00:00 UTC and
  tomorrow's `wikimedia` cap is 750 (kill switch working as designed). Wikimedia spacing is now 250 ms.
  To lift early (owner/lead decision only): `delete from ripples.att_state where k = 'kill:wikimedia.org';`
* ~2,000 backfill jobs are queued for `att-social`, `att-wiki`, `att-charts`, `att-market`; they are dispatched only
  after each builder runs `select ripples.att_fn_live('<fn>')`.
