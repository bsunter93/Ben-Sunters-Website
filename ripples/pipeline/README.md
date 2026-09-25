# Knock-On v5 pipeline (W2): collect, resolve, expand, test, build

Automatic discovery for the daily puzzle (SPEC §5). Supabase project `kffkasnzqcddpystszch`. Everything writes to
the W1 contract shapes (`../contract/*.schema.json`) and never touches v4 objects.

## Layout

| Path | What |
|---|---|
| `functions/_shared/kn.ts` | shared edge runtime (auth, UA, pacing, budgets, 429 handling, AQS series, SPEC §5.2 statistics, Wikidata facts). Deployed as a byte-identical `kn.ts` copy next to each `index.ts` |
| `functions/ripples-collect/index.ts` | `{"mode":"trends"}` Google Trends RSS (8 geos, serial 1/s) + Bluesky `getTrends`; `{"mode":"daily"}` top-per-country (10) + featured feed; `{"mode":"date"}` backfill (adds per-project top for 10 languages) |
| `functions/ripples-resolve/index.ts` | titles/queries -> enwiki title, QID, short description, P31, P570, sitelinks; unknown classes -> labels + P279 |
| `functions/ripples-expand/index.ts` | job kinds `screen`, `expand`, `history`, `split`, `refresh` (the statistics run here) |
| `sql/01..09_*.sql`, `sql/12..17_*.sql` | the migrations in the order they were applied. Replaying them on a W1 database reproduces the deployed W2 functions (`tools/fn_md5.py` prints the md5 of every function body; compare with the query in its docstring) |
| `sql/10_seed_data.sql` | category-map seed (231 verified classes), blocklist class QIDs, config keys |
| `sql/11_cron.sql` | the three pg_cron jobs |
| `sql/12_ripples_v5_pipeline_yield.sql` | decoy reserve (`candidates.extra`), monotone pooling of fluke bins, description-based safety patterns, seed baseline floor |
| `sql/13_ripples_v5_pipeline_warmup.sql` | fluke meter "warming up" until `config.pipeline.fluke_warm_min_decoy` pooled decoy tests (set back to the SPEC's 500 by sql/18) |
| `sql/14_ripples_v5_pipeline_run_day.sql` | `ripples_run_day`: reset also clears the unpublished practice puzzle; a finished day is reported, not rerun |
| `sql/15_ripples_v5_pipeline_delayed_row.sql` | a rebuild that ends `delayed` removes the unpublished practice row / marks a `built` live row `delayed` |
| `sql/16_ripples_v5_pipeline_decoy_quality.sql` | decoys must read "views normal" (window multiple >= 0.67); flattest recent series preferred |
| `sql/17_ripples_v5_pipeline_stop_flag.sql` | `shared_trigger_stop` only on the round where the chain actually stopped |
| `sql/18_ripples_v5_pipeline_verifier_fixes.sql` | fixes after the independent verifier: SPEC fluke warm-up (500), safety re-check of humans inside every run (stage `recheck`, `ripples._fresh`), dispatch order (live first, depth 1 of seeds and decoys before deeper beams), seed reuse per run kind, flat 90-day decoy sparklines, Board belly-flop rule, `spiked_alongside` badge and neutral headline, EXECUTE revoked from PUBLIC on all helpers. Applied as two migrations (`ripples_v5_pipeline_verifier_fixes`, `..._b`); the three large functions are patched in place, whitespace-tolerant |
| `sql/test_acceptance.sql` | the acceptance queries |
| `category-map.json` | the seeded class -> category / safety-flag map (labels fetched from Wikidata) |

All edge functions are deployed with `verify_jwt: false` and check `x-collector-token` against the vault secret
through `public.check_collector_token`. SQL calls them only through `public.call_collector(fn, payload)`.

## Flow (one `ripples.runs` row per `as_of`)

```
collect_daily -> resolve -> screen -> seeds -> expand -> recheck -> build -> done | delayed | failed
```

* **collect_daily** (live: from 06:10 UTC) one `collect` job: top-per-country for `as_of` (live: a country whose list
  is still 404 at 06:10 falls back to `as_of-1`, inside the 3-day seed window; and, for practice/backfill
  runs, per-project top for 10 languages) + `feed/featured` for `as_of` and `as_of+1`. The Google Trends "Trending
  Now" internal endpoint is never called (DEMARCATION §7.2 graded it RED; RSS is the official path).
* **resolve** (live: from 06:25, after v4's `wiki-top-daily`) enqueues `resolve` jobs for every unresolved title in
  the seed sources of `[as_of-2, as_of+1]` (top-per-country ranks <= 100, en <= 200; per-project top <= 60;
  featured; `public.wiki_top`) and every Google Trends query.
* **screen** 130-day series for the top 240 seed-source articles (by number of sources, then rank) plus up to 80
  decoy-pool titles (calm candidates of the last 7 days, else steady en top-per-country ranks 101-200): onset test and
  the 14-day calm check.
* **seeds** first a safety re-check (`resolve` job with `{"recheck":[QIDs],"phase":"seeds"}`): Wikidata P31/P570/sitelinks
  and the enwiki short description of every human seed candidate are re-fetched regardless of age (2 requests per 50
  QIDs). Then `ripples_pick_seeds(as_of)`: 12 real seeds (onset, peak multiple >= 3, safe, re-checked, not a seed of a
  puzzle of the same kind (live / practice) in the 30 days before `as_of`, not a Main-Page-only spike) and up to 8 decoy epicenters (|z| < 1 over the last 14 days, matched on baseline-median decile
  and category). Depth-1 `expand` jobs for both roles (identical code), one `history` job.
* **expand** jobs; after every finished depth the tick enqueues `split` checks for pre-eligible hops and a beam of 2
  deeper parents per root (real only, depth <= 4). With the budget left after the fixed candidate set, a real
  parent's job also tests a **decoy reserve**: up to 30 other outlinks of the same parent whose 60-day median is
  within about 0.5-2x of a promising hop's (pass_raw, p_time <= 0.05) baseline median, with the identical hop test.
  They are stored with `candidates.extra = true`, never counted in fluke rates, never a hop, beam parent,
  shared-trigger witness or Board wake neighbour (`set_rank` is null); they can only be picked as calm decoys.
* **recheck** (live: when the expand queue is empty and it is >= 06:58, or at the 07:16 expand cut-off) the same
  safety re-check for every human that can be shown: real seeds, calm or passing candidates, reserve-bank pages. At
  the 07:20 hard deadline (practice: 26 min) the build starts regardless; `ripples._fresh(qid, as_of)` makes a human
  whose facts were not re-fetched during this run ineligible as seed, option, Call It option or Board row.
* **build** `ripples_update_fluke`, `ripples_build_puzzle`, `ripples_resolve_calls(current_date)`.

Dispatch: `ripples._dispatch` runs **one job at a time** (`config.pipeline.max_running_total = 1`) and chains the
next job from `ripples_job_done`, so the pipeline is serial. Order: today's live run first (while it is active no
practice/backfill job starts), then the newest `as_of`, then stage (collect, resolve, screen, history, split, expand),
then **depth** (depth 1 of every real seed and every decoy epicenter before any deeper beam, SPEC 5.5), real before
decoy within a depth; `ripples_tick` (cron) is the watchdog: it advances
stages, requeues jobs stuck in `running` for > 5 minutes (at most 3 attempts) and dispatches up to 6 per call.
Every job gets a Wikimedia budget of <= 100 requests, capped so that `runs.wm_calls` never passes
`config.wm_daily_cap` (6,000); calls are counted from `ripples_job_done`.

## Politeness (SPEC §5.1, DEMARCATION §7)

* `User-Agent: KnockOn/5.0 (https://bensunter.com/ripples/methods/)` (+ `Api-User-Agent`) on every request.
* AQS (wikimedia.org REST): <= 5 requests/s (`aqs_spacing_ms` 200), one retry after 5 s on 429/503, then the job
  stops and is requeued 3 minutes later. Action API (`/w/api.php`, Wikipedia and Wikidata): `maxlag=5`, one request
  at a time with a 600 ms gap (`api_spacing_ms`, floor 300); any 429/503/maxlag stops the job (no retry in the run).
* The shared Supabase egress IP was rate-limited by AQS and the Action API when two jobs overlapped (first test run);
  with one job at a time and the spacing above the second test run had no 429s.

## Statistics (SPEC §5.2, in `kn.ts`)

`x = ln(1+views)`; baseline for day t = median/MAD of `x[t-111..t-21]`, `s = max(0.1, 1.4826·MAD)`. Seed onset = first
day in `[as_of-10, as_of]` with z >= 3 (baseline for that day) in a run of z >= 3 days reaching z >= 5. Hop test at the
parent onset `tp`: S = max z over `[tp, min(tp+3, as_of)]`, onset = first z >= 3 day in `[tp-7, tp+3]`,
`multiple = max views / e^m - 1`, `pass_raw = S >= 3 and multiple >= 1.5 and lag >= 0`; time-shift placebo at
`tp - 7k` (k >= 3 while the fake baseline fits in the 400-day series, 38 placebos typically),
`p_time = (1 + #{S' >= S}) / (1 + K)`; calm = max |z| over `[tp-7, as_of]` < 1 and multiple < 1.25.
Split: multiples of the desktop series and of (all-access - desktop). Fluke rate per S-bin pooled over 90 days
(`fluke_rates`: `d_*` = the day's own counts, the rest pooled).
Adjacent S-bins that violate "a stronger spike is no more fluky" (or have no real passes) are pooled by summing
their counts (pool-adjacent-violators); `fluke_rates.fluke_bins` records the pooled range (e.g. `6-10..10+`).
The meter is "warming up" while the pooled decoy pool has fewer than `config.pipeline.fluke_warm_min_decoy` tests
(500, SPEC 5.2). While warming a hop needs p_time <= 0.05 and the reveal shows `fluke_warming: true`, `fluke: null`;
afterwards the measured rate is printed and the SPEC gates apply (answer f <= 0.10, shown f <= 0.20).
`config.pipeline.fluke_gate_fallback` (default 0) is a LEAD-ONLY switch for the SPEC 13 fallback: at 1 the answer gate
f <= 0.10 is dropped (p_time <= 0.05 still applies) and the reveal prints the measured fluke rate, never "warming up".

Safety (SPEC §5.4) is `ripples._safe` + `ripples._fresh` + `articles.blocked`: class flags (category_map / blocklist class QIDs), title
patterns, and `blocklist.desc_pattern` on the enwiki short description (people known for killing or violent crime,
murder / massacre / terrorism / suicide topics, pornographic performers), deaths within 60 days (month/year-precision P570 counts as the
last day of that month/year; a human whose short description ends in a death year within the window counts as
recently deceased even before Wikidata has P570), living people with no
other-language article and < 20 views/day. Every human that can be shown must have been re-checked during the run. Seeds also need a baseline median >= `config.pipeline.seed_min_median` (50).

## Puzzle composition (`ripples_build_puzzle`)

Answer-eligible = pass_raw, p_time <= 0.05, f <= 0.10 (or warming), split_ok, not a Main Page feature within ±1 day,
linked, safe (no sensitive topics), no shared trigger at depth >= 2; usable as a round only with 3 calm, linked,
safe siblings (median 0.5-2x the answer's, different title stem, >= 2 of 3 in the answer's category, and window
multiple >= `config.pipeline.decoy_min_multiple` 0.67 so a page in post-hype decay is never shown as "views normal";
the whole 90-day sparkline shown after the reveal must read flat: no day above
min(`config.pipeline.decoy_max_spark_ratio` 2.0, the answer's multiple) x the decoy's baseline median (SPEC 12.3);
same-category first, then the flattest spark, then the closest median). Chains are
ranked by length, Σ log10(1/f) (p_time while warming), category jumps, biggest-in-days, onset recency.
>= 3-hop chain -> the chain (<= 4 rounds); 2-hop -> + 1-2 fresh ripples; else 3-4 fresh ripples; else the reserve
bank (unused compositions from the last 14 days, `from_date` set); else `delayed` (no puzzle row).
Evidence badge: `flowed` (clickstream top-20 edge), else `spiked_alongside` for lag 0, else `spiked_after`. Template
headline "{seed}: which linked pages also spiked?" (no order implied). Template copy (`source = 'template'`) is written to `ripples.copy`; W1's overlay lets W6's AI copy replace it.
All `cross` arrays are `[]` (the attention layer fills them later).

Call It: 4 calm, linked, safe depth-1 neighbours of round 1's seed with median >= 2,000/day, not options, <= 2 per
category; `model_p = config.callit_climatology (0.08) × config.callit_cs_mult[top5|top20|none] (1.0)`; window
`puzzle_date + config.callit_window_offset (0)` .. +6.

## Running a past day (W3 backfill, tests)

```sql
select public.ripples_run_day('2026-09-24', 'practice');          -- returns at once
select stage, wm_calls, errors, detail from ripples.runs where as_of = '2026-09-24';   -- poll
select public.ripples_run_day('2026-09-24', 'practice', true);    -- p_reset: wipe that day's pipeline rows (and its
                                                                  -- unpublished practice puzzle) and rerun; without it a
                                                                  -- finished day is only reported
```
`ripples_run_day` registers the run and starts the transient pg_cron job `ripples-run-day` (every 20 s,
`select public.ripples_tick()`), which unschedules itself once no practice run is active. Practice n =
`as_of - epoch` (negative); dates on or after the epoch are rejected. Run backfill days one at a time, oldest first
(a day's pooled fluke rates use the days before it). Between 05:40 and 07:35 UTC a new or reset practice run is not
started: the call returns `{"deferred": true, ...}` (the live run has priority); call again after 07:35. A reset
returns `stale_later_days`: later days whose pooled fluke rates included the old counts (rerun them to reproduce).

## Cron

| job | schedule | command |
|---|---|---|
| `ripples-trends-hourly` | `7 * * * *` | `select public.call_collector('ripples-collect', '{"mode":"trends"}'::jsonb)` |
| `ripples-tick` | `* 6-8 * * *` | `select public.ripples_tick()` |
| `ripples-retention` | `50 3 * * *` | `select public.ripples_retention()` |
| `ripples-run-day` | `20 seconds` (transient) | `select public.ripples_tick()` |

## Service functions (EXECUTE revoked from public, anon, authenticated; granted to service_role)

`ripples_tick()`, `ripples_pick_seeds(date)`, `ripples_update_fluke(date)`, `ripples_build_puzzle(date, text)`,
`ripples_resolve_calls(date)`, `ripples_retention()`, `ripples_run_day(date, text, boolean)`,
`ripples_ingest_candidates(bigint, jsonb)`, `ripples_ingest_seed_history(bigint, jsonb)`,
`ripples_ingest_articles(jsonb)`, `ripples_ingest_trends(jsonb)`, `ripples_job_done(bigint, boolean, text, int, jsonb)`.
`ripples._grant_audit()` returns zero rows.

## Verified runs (2026-09-25)

| as_of | n | took | Wikimedia calls | jobs (failed) | result |
|---|---|---|---|---|---|
| 2026-09-24 | -1 | 15 m 42 s | 2,224 | 45 (0) | built: 3 rounds (Resident Evil (2026 film) -> Army of the Dead -> Sucker Punch · fresh ripple Cindy Crawford -> Gia Carangi), 4 Call It options, Board of 12 |
| 2026-09-23 | -2 | 22 m 03 s (practice deadline) | 1,164 | 33 (0; 8 skipped at the deadline) | delayed: every usable hop came from one seed; AQS was slow after four full runs that day |

The exported puzzle, reveal, board and Call It JSON of n = -1 pass `../contract/tools/validate.py` (schemas and
`--wording`) with md5s equal to the RPC output (`validate.py --md5`).
