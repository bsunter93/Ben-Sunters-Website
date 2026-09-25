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
