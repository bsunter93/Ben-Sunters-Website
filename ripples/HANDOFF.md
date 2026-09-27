# Ripple Map — handoff (updated 2026-09-27 04:25 UTC, session 2)

Read this first. It is everything a new chat needs to continue: who the owner is and what they want, the rules, how the
system is built, exactly what is running right now, and the runbook for the next steps.

Repo `bsunter93/Ben-Sunters-Website`. Session 1 worked on `claude/admiring-goldberg-u36vlz` (merged to `main` through
PR #15, plus b7 + b8 SQL and this file on the branch). Session 2 works on `claude/funny-ride-8tiy11` (starts from
session 1's branch; draft PR, not merged). Live site: https://bensunter.com/ripples/ → `/ripples/pond/` (GitHub Pages
from `main`). Supabase project `kffkasnzqcddpystszch` (Pro plan), schema `ripples`.

**Section 0 supersedes sections 6 and 7** (kept below as the session-1 record).

---

## 0. Session 2 (2026-09-27 03:45–04:25 UTC): what was done, what is running, what is next

### Done (runbook steps 1–5), each change disclosed in the ledger before the step it affects
- **Historical catalog (b7 input)**: 20/20 OpenFEMA declaration years fetched, none stopped. Before building, the raw rows
  showed two contaminations, fixed in `39_att_b7_b8_prefreeze_amendments.sql` part A (ledger 1214):
  Katrina 2005 covered 47 states (evacuee-sheltering EMs: titles with EVACU, plus late EM-only states ID/KY/PA), and
  the 2001-09-11 "FIRES AND EXPLOSIONS" declarations (NY, NJ, VA), a 2009 PR refinery explosion and a 2011 OK plant
  fire were typed "Fire" and would have entered as wildfires. Built: **1,829 library_hist events** (storm 574 incl. 63
  named, wildfire 1,023, flood 119, cold 83, quake 12). Katrina now AL FL LA MS; Sandy 13 states; Harvey LA TX.
- **b6** panels built (7 FRED supersectors start 2005-06, not 2000; eduh/fire 47 states, trad 50, mfg 49; CDC deaths
  2014-01..2026-07), disclosure 1216, **frozen 1217** (112 pairs, 3,452 explore rows).
- **b7** claims panels rebuilt from 2010-01; disclosure 1218 (panel starts, hist counts, magnitude caveat, the 2019
  catalog-composition shift: pre-2019 events are FEMA-only, 2019+ also NOAA cold snaps / USGS felt quakes), **frozen
  1219** (234 pairs, 41,545 explore rows vs b4's 1,500: library_hist was read).
- **Decoys**: the runbook omitted `att_fx63_decoy_seed(batch)`, which nothing calls automatically; without it a batch
  can never finish. b6 seeded (19,748 dx rows; 7,868 draws found no clean placebo date because the mask is denser now).
  b7 is seeded by the one-off cron job `att-fx63-seed-b7` (started 04:09, unschedules itself).
- **Finisher hazard fixed** (39 part C): steps are unscheduled only when no other frozen batch is unfinished; each batch
  has its own finisher job `att-fx63-finisher-<batch>`, which removes itself at the end.
- **b8 amended before start** (39 part B, ledger 1215 and 1220): weekly fake shocks shifted by round(s × 52.1775) weeks
  (no calendar drift); confirmation now needs BH q ≤ 0.05 across the promoted list + empirical p ≤ 0.05 on 400 draws +
  enrichment ≥ 1.2 (was p ≤ 0.05 each, uncorrected); a tail-calibration count for the normal approximation; the tick
  runs ~45 s of tasks per call and traps statement timeouts (task → `timeout` → one slow retry in `att-anom-b8-slow` →
  `failed`); duplicate engine-6.2 claims panels (`dol.claims:ic/cw`) dropped from the scan.
  **Started** 04:08 (ledger 1221: 21 panels, 10,243 anomalies, 273 screen tasks), `anom_go = true`.
- **Story layer v2.2** (`40_att_story_honesty.sql`), then explorer rebuilt and snapshot refreshed: engine-6.2 "strong
  pattern" world rules no longer shown as Confirmed; "expected, not yet tested" → "predicted, not yet tested"; a
  'likely' move that more than 1 in 10 ordinary days match is listed as didn't-move (CPI → inflation expectations,
  10 of 36); no group is both "too early" and "no sign"; "absorbed" says how many things were measured.
- **Frontend** (`ripples/pond/`): honest status line on Find; unfolding shocks no longer say "absorbed/settled";
  outcome list counts known causes, not rows being checked; flow labels no longer clipped; saved copy paints after
  0.9 s when the RPC is slow (was 3.5 s blank) and upgrades to live in place; "How" visible on phones; Absorbed /
  Expected only / Surprise defined on How it works; `aria-live` removed from `<main>`.

### Outage 04:24–05:24 UTC and the slower schedule (read `41_att_ops_after_disk_exhaustion.sql`)
Session 2's jobs exhausted the instance's disk-IO burst budget and the database stopped answering until the owner
restarted it. Nothing committed was lost. Jobs now run slowly and staggered. **b7's finisher is deliberately off** until
every b7 grid has decoy rows; the re-arm command is in file 41. Never run more than one heavy every-minute job or write
more than ~20k rows in one transaction on this instance.

### Running at the session-2 handoff (04:20 UTC, superseded by the outage note above)
- `att-fx63-step-1`, `-step-2` (every minute, ~650 rows each per run), `att-fx63-finisher-fx63-b6-unexpected`,
  `att-fx63-finisher-fx63-b7-decade`, `att-fx63-seed-b7` (one-off). Expect b6 to finish in ~1 h and b7 in ~6–8 h
  (41.5k explore + ~330k decoy rows).
- `att-anom-b8` (every minute) and `att-anom-b8-slow` (every 10 minutes, only when a task timed out). 80/273 screen
  tasks done at 04:17. After the screen: BH promotion (ledger freeze) → confirmation (400 draws) → verdicts → `done`.
  Note: every few minutes a tick returns "SET" in ~0.1 s instead of running tasks; harmless (the next tick runs), cause
  not yet found.
- DB 562 MB of 6,000.

### Results (07:40 UTC)
- **b6: nothing survived** (0/12; decoys clean). **b8: nothing surprising survived.** Its 5 claims "confirmations" were a
  year confound (see ledger 1229); the one remaining confirmation (cold → electricity demand) is the obvious link.
- Lesson for b9: confirmation nulls must be year-matched (fake shocks drawn inside the confirmation period) or anomalies
  scaled per year; extend the claims regime exclusion through 2022; use empirical p (more draws), not the normal tail.
- b7 still running (decoys seeding 3 grids per run; re-arm its finisher when all 234 grids have dx rows, file 41).

### Next (runbook steps 6–7, unchanged in substance)
1. b6 / b7: when each finisher reports `all_done`, read `att_fx63_select` (decoy_set 0, selected) and the decoy
   calibration; for any confirmation run the seasonal check (median `p_time` of held-out rows in `att_fx_event`, role
   `confirm`, decoy_set 0, and the count with `p_time` ≤ 0.1); if it fails, set status `withheld` + ledger note.
2. b8: `select * from ripples.att_anom_hyp where run = 'b8-anomaly-first' and stage = 'explore' and promoted`; verdicts
   `confirmed%` (rows "(positive control)" are FEMA-defined, never findings); report the `normal_tail_calibration`
   object in the verdicts ledger entry (share of null draws with z ≥ 2.326 should be ≈ 0.01).
3. `select ripples.att_explorer_build();`, refresh `data/explorer.json` (base64 of `public.rm_explorer()` with an md5
   check), report plainly to the owner, commit. Merge only when the owner says so.

### Environment notes learned this session
- An MCP `execute_sql` call that passes 60 s returns a timeout error **but keeps running server-side** (check
  `pg_stat_activity`). Long work (freeze, decoy seed, `att_anom_start`) is safer as a one-off cron job.
- The repo SQL is not always identical to the live functions (e.g. `att_explorer_build`'s world-rule tier line differs
  from file 34). Always anchor patches on `pg_get_functiondef`, never on the repo text.

---

## 1. The owner and the vision

**Core vision (owner, verbatim):** "The entire point of the app is uncovering hidden impacts from upstream events —
regardless of where that impact shows up. Attribution and traceability with statistical rigor are key."

What the owner has said, and what it means for the work:

- **Obvious links are worthless.** "Everyone already knows storm = energy demand." "The inflation report probably moved
  inflation expectations … this is a joke and obvious." The product is the link nobody would guess.
- **One shock, many outcomes.** "You can't really link it one to one. It's more like one to many." Caveat several possible
  outcomes rather than forcing a single story.
- **Resilience is a finding.** Florida is built to absorb hurricanes, so the first ripple may just die out there
  ("less power use → absorbed by the grid"). Look well beyond power and gas for unintuitive behaviours and outcomes
  traced to the same shock, in Florida and elsewhere.
- **Anomaly-first, not list-first** (latest direction): "it can't be based on a rigid list, the chance of the overlap
  is too small. Start at the anomalies, whatever they might be, and see if there are links you can draw and
  attribution that can be made." / "just work backwards from what the data tells you."
- **Decade scale:** look at shocks from a decade ago and the population-level outcomes they produced, and compare recent
  shocks with how historical shocks played out ("feasible?" — yes, being built as b7, with phase 2 still to do).
- **Audience and UX:** it must work for a 12-year-old. Keep statistics behind links (Why it happens / How sure are we /
  See the evidence). Synthesize the signals into a short qualitative summary. No walls of numbers.
- **Design:** serious, professional, sleek, beautiful; not cartoony. The page should guide the user to (1) find a ripple
  and (2) explore it, upstream cause and downstream impact. The pond must feel like water: an earlier design was rejected
  as looking like "planet orbits / chemistry valence diagrams". Outcomes must not sit on the perimeter as if a ripple
  goes one direction, and rings must not be always visible.
- **Style:** direct, blunt feedback. Report outcomes honestly, including "nothing survived". Short status updates while
  working.
- The owner said "merge it and make it live" for PR #13/#14/#15. Opening PRs (as drafts) needs no go-ahead (owner,
  2026-09-27: "I dont care if you make PRs without my go ahead"). **Merging** still waits for the owner's explicit go-ahead.

Earlier binding decisions D-1..D-16 (story layer, information-exploration game, share objects) still hold. They are in
`ripples/docs/` and the older sql headers.

## 2. Hard rules (security and ethics, still in force)

- Keys live only in Supabase Vault (`public.att_secret('<name>')`, service role) or GitHub secrets. Never print, log,
  commit or paste them. That includes the FRED key, the YouTube key (`youtube_api_key`) and the service-role key.
  Grep for leaked keys before every commit (`eyJ…`, `sb_secret`, `api_key=`). The publishable key in
  `ripples/pond/explorer.js` is public by design.
- Collection: honest UA `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`. Respect robots.txt. Stop on
  429/503 with no retry that day. No bypassing blocks, CAPTCHAs or bot walls. No spoofed UA, proxies or IP rotation.
  Aggregate counts only; no personal data. The SEC contact email goes only to sec.gov.
- Statistics: every test is pre-registered in the hash-chained ledger (`ripples.att_ledger_append(day, kind, ref,
  payload)`) **before** any result exists. Deviations are disclosed as ledger entries, and late disclosures are labelled
  as late. Confirmations must also pass the seasonal robustness check, otherwise they are withheld. Public RPCs exclude
  withheld / not testable / superseded batches.

## 3. Environment gotchas (cloud container)

- The container **cannot reach** supabase.co, bensunter.com, api.stlouisfed.org, data.cdc.gov or fema.gov over HTTP.
  Use the Supabase MCP (`execute_sql`) for everything in the database. For outside APIs, call them **from the database**
  with `pg_net` (`net.http_get(url, params, headers, timeout_ms)`, then read `net._http_response`), putting the key in the
  URL server-side via `public.att_secret` and never selecting it back.
- Large query outputs: pad the result (`repeat('x', 40000)`) so the MCP saves it to a tool-results file, then parse that
  file with python. For example, the snapshot refresh base64-encodes `public.rm_explorer()`.
- Edge-function deploys via MCP need the **full source** of every file. `att-library` (~86 KB with shared files) and
  `att-econ` (~114 KB) are too big to redeploy casually, so logic was moved into SQL instead. `att-downstream` is small
  (currently version `2026-09-27.d5`).
- PL/pgSQL gotcha: an `IF` condition ends at the first `THEN`, so never put a `CASE` inside an IF condition. Avoid
  variable names that match column names or keywords (`n`, `m`, `out`, `rows`, `begin`). Patch live functions with
  anchor-checked `replace()` on `pg_get_functiondef` inside a `DO` block, raising if the anchor is missing. A
  multi-statement MCP call is one transaction, so any error rolls everything back.
- Chromium and Playwright are at `/opt/node22/lib/node_modules/playwright` for screenshots
  (`python3 -m http.server` from the repo root; the page falls back to `data/explorer.json` when it can't reach
  Supabase).
- GitHub check "Pages are whole" (`.github/workflows/assets.yml`) fails if any HTML references a missing local asset.

## 4. System map

**Database (schema `ripples`), key objects**

- Events: `att_events` (roles `library`, `positive_control`, `library_hist` [new, 2000–2018, read only by
  `engine63.hist_batches`]), `att_topics` (meta: state[], ba[], storm), `att_family_events`, `att_families`.
  Upsert via `att_library_upsert(jsonb)`.
- Series: `att_series` + `attention_obs`, ingest via `public.att_ingest(jsonb)` (rejects unknown sources; db-size cap in
  `att_config.db_cap_mb`, now 6000). Engine panels: `att_fx_panel` (per source/metric/geo_kind: `days[]`, `regions[]`,
  prefix sums `ps[region][i]` and counts `pc`), built by `att_fx63_panel_build(source, metric, geo_kind, agg,
  value_kind, weekly)` with per-panel starts in `engine63.panel_from`.
- Engine 6.3: `att_fx63_grid_spec(set)`, `att_fx63_freeze(batch, set)`, `att_fx63_step(50)` (workers),
  `att_fx63_finisher(batch)`, `att_fx63_select` (verdicts), `att_fx63_batch` (status), `att_fx_event`,
  `att_fx63_fam_events` (clean-control mask, rebuilt by `att_fx63_fam_events_build()`), and config
  `att_config key='engine63'`: `split_date` 2024-01-01, `regime_exclusions` (pandemic 2020-02-15..2021-06-30 and the
  2008-09-01..2009-06-30 financial crisis), `hist_batches`, `panel_from`, `anom_go`.
- Story layer: `34_att_story_explorer.sql` (v2), `35_att_story_surprise.sql` (v2.1). `att_explorer_shock(slug)` returns
  `story` = surprise | absorbed | expected | unfolding | none. Each impact carries `expected` (from
  `att_plain_groups.obvious_for`, a regex on family), and the headline leads with the surprising link.
  `att_explorer_build()` writes the `att_explorer` table (cron 08:52 daily). Public RPC `public.rm_explorer()` (anon).
  Plain-language tables: `att_plain_groups`, `att_plain_why`, `att_plain_family`, `att_plain_places`.
- Anomaly-first lane (b8): `att_anom`, `att_anom_hyp`, `att_anom_queue`, and functions `att_anom_scan`, `att_anom_link`,
  `att_anom_start`, `att_anom_tick` (file `38_att_anomaly_first.sql`).
- Historical FEMA (b7): `att_hist_fema_req` (queue), `att_hist_fema` (raw), `att_hist_fema_tick()` (cron
  `att-hist-fema`, every 2 minutes), `att_hist_fema_build()` (file `37_att_engine_63_b7_decade.sql`).

**SQL files** in `ripples/attention/sql/`: 32 (engine 6.3), 33 (b3–b5 downstream, panel starts, 6.3.5-m), 34/35 (story
layer), 36 (b6), 37 (b7), 38 (b8). Each file header documents its pre-registration.

**Edge functions** in `ripples/attention/functions/`:
- `att-downstream` (FRED state series plus CDC mode; crons `att-downstream-drain`, `-daily`, `-cdc`).
- `att-library` (live TS still has a 2019 floor; the historical backfill is done in SQL instead).
- `att-econ`, `att-world` and others.

**Frontend** in `ripples/pond/`:
- `index.html`, `explorer.js`, `explorer.css`, `data/explorer.json` (snapshot fallback), and share stubs at
  `r/<slug>/index.html`.
- Views: Find, Shock (canvas water pond `Pond(s, host, ui)` with scrubber, "Drop again" and reduced-motion still),
  Outcome (upstream/downstream flow), Watching, How it works.
- The old app is at `ripples/legacy/pond-v1/`; the methods/contact page at `ripples/methods/`.
- Load order: `window.__RM_EXPLORER`, then the `rm_explorer` RPC (3.5 s timeout), then the snapshot.
- Refresh the snapshot after story-layer changes: base64 of `public.rm_explorer()`, decode into `data/explorer.json`.

## 5. Results so far (honest)

Every confirmed link to date is first-order and expected. The page now says so: "Hurricane Milton was absorbed. Only the
expected ripple: electricity demand moved within a week. It died out there." Every shock in the catalog reads absorbed,
expected, or unfolding. **No surprising link has survived yet.**

| batch | what | status | ledger |
|---|---|---|---|
| fx63-2026-09-27 (b1/b2) | first-order panels | confirmed (expected links only) | — |
| fx63-b3-downstream | housing/jobs, 2016+ | not testable (degenerate monthly null) | 1191, 1195, 1196 |
| fx63-b4-longhistory | jobs/permits back to 2005 | withheld: wildfire → leisure & hospitality jobs −0.6% passed weakly, then failed the seasonal check (median in-time p 0.42; 2/154) | 1197, 1204–1207, 1210 |
| fx63-b5-housing-space | housing, in-space null | withheld (seasonal check) | 1198, 1200–1203 |
| fx63-b6-unexpected | 7 industry job panels plus weekly CDC deaths | **done: nothing survived.** 12 selected → 0 confirmed (6 inconclusive, 6 contradicted; best: flood → finance jobs months 6–11, q 0.32). Decoys: 31 decoy selections, 0 false confirmations | 1209, 1216, 1217, 1222, 1226 |
| fx63-b7-decade | historical shocks 2000–2018, year-after window, 14 outcomes | catalog amended, **frozen, running** (session 2) | 1211, 1214, 1218, 1219 |
| b8-anomaly-first | anomaly scan, work back to shocks vs season-matched fake shocks | **done.** 1,344 screened → 50 promoted → 6 "confirmed" + positive control; **5 of the 6 withheld** (all on weekly initial claims: 2024+ claims anomalies run 3–4× the pre-2020 rate, and fake shocks were not year-matched). Survivor: cold snap → electricity demand up weeks 2–4 (expected). Normal-approximation tail is anti-conservative (2.7% at nominal 1%) | 1212–1215, 1220, 1221, 1225, 1227–1229 |

Why the engine only found obvious links (diagnosis given to the owner):
1. It only measured first-order things, about 15 outcomes (now widened by b6 and b8).
2. The shock catalog started in 2019 (b7 fixes this, but for jobs outcomes the usable window is effectively 2011–2023,
   because first-release data starts in 2005 and 2008–09 and the pandemic are excluded).
3. The rigor gates favour big direct effects.
4. The data is state-level and monthly, which is coarse.

## 6. What was running at the session-1 handoff (03:34 UTC; superseded by section 0)

- `att-hist-fema` (every 2 minutes): 7 of 20 declaration years done, 12 queued, 1 in flight. It finishes on its own
  around 04:05 UTC.
- The FRED drain is **complete**: 547 fetched plus 14 missing = 561. CDC weekly deaths are complete (51 states,
  2014-01 to 2026-07; the last 8 weeks are never ingested).
- `att-anom-b8` cron is scheduled but idles until `engine63.anom_go = true` **and** `att_anom_start` has queued tasks.
- **No fx63 step or finisher workers are scheduled.** The finisher unschedules them when a batch ends.
- The old chat's 04:15 check-in trigger (`trig_01HEUpAbjUwd5LixsA5JLAgb`) was **disabled** for this handoff. The new
  chat owns the runbook below. Set your own reminders with `send_later` if you want check-ins.
- DB about 516 MB of the 6000 MB cap. The space guard cron `att-fx63-space-guard` unschedules steps above 5800 MB.

## 7. Session-1 runbook (steps 1–5 done in session 2; see section 0)

Historical shocks join the clean-control mask, so build them **before** freezing any batch or starting b8.

1. **Historical catalog (b7 input).**
   - Wait until `select status, count(*) from ripples.att_hist_fema_req group by 1` shows all `done`. If any row is
     `stopped` (429/503), don't retry today.
   - Run `select ripples.att_hist_fema_build();` once.
   - Check `library_hist` events per family and year, and spot-check Katrina 2005, Sandy 2012 and Harvey 2017 for
     plausible states and onsets.
   - **Known caveat to disclose before the b7 freeze:** the SQL fetch did not select `designatedArea`. Declaration rows
     collapse to one per (disaster, state, date, title), so `magnitude = ln(1 + areas)` counts state-declarations rather
     than counties (the live TS collector counts county rows). Magnitude is not used by the tests' selection rule, but
     record it in the ledger.
2. **b6 panels and freeze.**
   - Build: `select ripples.att_fx63_panel_build('fred.state', m, 'state', 'month', 'level')` for m in
     srvo, eduh, fire, govt, pbsv, trad, mfg, and `select ripples.att_fx63_panel_build('cdc.deaths', 'all', 'state',
     'week', 'count', true)`.
   - Record each panel's real start date. Append a pre-freeze disclosure to the ledger (actual first-release start
     dates; the 14 missing FRED ids).
   - Then `select ripples.att_fx63_freeze('fx63-b6-unexpected', 'b6');`.
3. **b7 panels and freeze.**
   - Rebuild `dol.claims` `ic` and `cw` weekly panels (`panel_build('dol.claims', 'ic'|'cw', 'state', 'week', 'count',
     true)`); `panel_from` is now 2010-01-01.
   - Confirm all 14 b7 panels exist. Append a disclosure (panel starts, `library_hist` counts per family, both regime
     exclusions, the magnitude caveat).
   - Then `select ripples.att_fx63_freeze('fx63-b7-decade', 'b7');`. `n_explore_events` should be far above b4's 1500,
     which proves `library_hist` was read.
4. **Workers.** Recreate them:
   `select cron.schedule('att-fx63-step-1', '* * * * *', $$set statement_timeout = '100s'; select ripples.att_fx63_step(50)$$);`
   (same again for `-step-2`), plus a finisher per batch, e.g.
   `select cron.schedule('att-fx63-finisher', '* * * * *', $$set statement_timeout = '100s'; select ripples.att_fx63_finisher('fx63-b6-unexpected')$$);`.
   **Hazard:** when any batch finishes, the finisher unschedules all `att-fx63-step-%` jobs, and it unschedules the job
   named `att-fx63-finisher`. So either run b6 then b7 one after the other, or give the b7 finisher its own job name and
   re-arm the steps after b6 finishes.
5. **b8 anomaly-first.**
   - After steps 1–3 (all regional panels exist): `select ripples.att_anom_start('b8-anomaly-first');`. This scans every
     regional weekly and monthly panel, queues the tasks and freezes the task list to the ledger.
   - Then `update ripples.att_config set value = value || '{"anom_go":true}' where key = 'engine63';`.
   - The cron then runs about one task a minute: screen → Benjamini–Hochberg promotion (frozen to the ledger) →
     confirmation on held-out 2024+ shocks → verdicts (then a `done` marker).
   - Watch `select stage, status, count(*) from ripples.att_anom_queue where run = 'b8-anomaly-first' group by 1, 2;` and
     `att_anom_hyp` (`promoted`, `verdict`).
6. **Verdicts.**
   - b6 and b7: read `att_fx63_select` (`decoy_set` 0, selected) plus decoy calibration. For any confirmation, run the
     seasonal check: median `p_time` of held-out rows in `att_fx_event` (role `confirm`, `decoy_set` 0) and the count
     with `p_time` ≤ 0.1. If it fails, withhold it: set status `withheld` and append a ledger note.
   - b8: `verdict like 'confirmed%'`. Rows marked "(positive control)" are FEMA-defined and never findings.
   - Then `select ripples.att_explorer_build();`, refresh the snapshot, and report plainly to the owner.
7. Commit SQL and notes on the branch. Merge to `main` only when the owner says so.

## 8. Next product work (agreed direction, not built yet)

- **Wire b8 into the pages.** For a shock, show the anomalies in its footprint afterwards, each labelled "attributed"
  (confirmed link), "consistent with a pattern" (screened only) or "unexplained". This is the core of the owner's
  anomaly-first vision and needs new fields in `att_explorer_shock` plus a UI.
- **Lane 2: national series with no geography** (Wikipedia, news, social, prediction markets, about 12k series). This
  needs a timing-only design: many events plus fake-date nulls. It is weaker evidence than place-based tests and must be
  labelled as such.
- **Decade phase 2:**
  - Annual population outcomes 1–5 years out (IRS migration, County Business Patterns, births, school enrollment).
  - "Analog matching": compare a recent shock's early path with look-alike historical shocks and show what followed,
    labelled as a lead rather than a finding for this shock.
- **Absorbed vs not:** compare the same kind of shock in a resilient place and a non-resilient one (Florida vs North
  Carolina for hurricanes). The owner raised it.
- **Heat history:** there is no pre-2019 heat catalog (it needs a NOAA GHCND station backfill).
- **Open design question:** the pond wave reaches the shock's `reach` (for Milton, about a week) instead of the last
  moved outcome (day 3). It's a one-line change on the `reachD` line in `Pond` if the owner prefers the literal rule.

## 9. Other deliverables from this session

- The newsletter draft and 60-second video script for issue 01 (Hurricane Milton) are in `ripples/docs/handoff/newsletter/`.
- The video render sources (`scene.html`, `render.py`, `stills.py`, `grid.json`) are in `ripples/docs/handoff/video/`.
- The rendered `milton-60s.mp4` (4 MB) lived only in the old chat's scratchpad and is not in the repo. Re-render it from
  the sources if needed.
- Side-income viability was discussed: the newsletter plus video format built around one shock per issue.

## 10. Vision sweep (session 2): where the build falls short of the vision, and what would fix it

Core vision: *hidden impacts from upstream events, wherever they show up, with attribution and traceability under
statistical rigor.* What matches today: the rigor machinery (pre-registration, ledger, decoys, held-out confirmation,
seasonal check, withholding) is real and was honoured; the pond reads as water; statistics sit behind links; the
pages now say plainly that no surprising link has passed. What does not match, most important first:

1. **The scan only looks where we measure, and we measure little.** "Regardless of where the impact shows up" is bounded
   by 20 regional panels, all state-level labor, housing, power, deaths and declarations. The ~12k national series
   (Wikipedia, news, social, markets, npm) are outside every test. Fixes: lane 2 (timing-only design with fake dates,
   labelled weaker); and more regional outcomes with long history: county employment and wages (BLS QCEW), county
   unemployment (LAUS), business counts (CBP), migration (IRS SOI), flood-insurance claims (NFIP), SNAP and Medicaid
   enrolment, births, school enrolment, bankruptcy filings, power outages (EIA-417 / ODIN), air quality (EPA AQS).
2. **State-level data hides local shocks, so "absorbed" may just be dilution.** A storm that wrecks 10 counties
   barely moves a statewide total; Helene's western North Carolina losses are invisible in NC aggregates. The FEMA
   fetch drops `designatedArea`, so county footprints exist in the source but are thrown away. County footprints +
   county outcomes (QCEW, LAUS) is the single biggest lever for both discovery and honest "absorbed" calls.
3. **"Absorbed" has no counterfactual.** It currently means "only the expected thing moved, and fast". To call
   resilience a finding, compare the same shock kind in resilient and non-resilient places (Florida vs North Carolina
   hurricanes), pre-registered as a heterogeneity test.
4. **Too little held-out data for rare effects.** Confirmation uses only 2024+ shocks (~2.7 years). A second split
   (screen on 2000–2015, confirm on 2016–2019 and 2022–2023, pandemic excluded) would roughly double confirmation power
   for b8-style hypotheses. Pre-register it as a new run rather than changing b8.
5. **b8 has no decoy-universe calibration.** Engine 6.3 runs fake shock catalogs through the whole pipeline; b8 only
   has per-hypothesis fake-shock nulls plus the new tail check. Run the full screen → promote → confirm path on 2–4
   random shock catalogs and report false confirmations (target 0).
6. **"Expected" is a hand-written regex** (`att_plain_groups.obvious_for`). Surprise should come from the
   pre-registered mechanism graph and `domain_distance` (engine 6.3 already computes it), not from a regex.
7. **No dose-response.** Magnitude is a declaration count (and for b7, state-declarations only). Damage in dollars
   (NOAA Storm Events), wind speed, burned acres (NIFC) and people affected would give dose-response, one of the
   strongest attribution checks.
8. **The catalog of pages is thin and skewed.** 32 pages: 26 small wildfires stuck on "still unfolding", 6 with
   results; the 1,829 historical shocks and ~2,000 2019+ shocks have no pages. Publish pages for shocks with results
   (Katrina, Sandy, Harvey once b7 reports; decade comparisons) and stop publishing small fire declarations that
   have none.
9. **b8 is not in the pages yet** (section 8, first bullet): per shock, anomalies in its footprint afterwards, labelled
   attributed / consistent with a pattern / unexplained, plus a third Find mode "Something unusual".
10. **Frontend gaps still open:**
    - Share cards (`og/*.png`) show the rejected v1 orbit design with stale numbers ("12 things stayed flat"), and 27
      wildfire pages reuse Milton's card. Regenerate them from the current pond.
    - "Too early" markers sit on the pond rim, the perimeter look the owner rejected.
    - Shock pages have no downstream exploration ("could ripple on to …").
    - "What held steady" is the weakest visual; the grey no-sign dots are unlabelled.
    - The outcome flow diagram is tiny on phones (an SVG with min-width 560 inside a scroller).
    - `--text-3` contrast is 4.39:1, and the canvas time labels are about 1.7:1.
    - The scrubber knob sits between WEEK and MONTH while the text says "about a week".
11. **Newsletter issue 01** leads with Milton → electricity demand, the kind of obvious link the owner called
    worthless, uses the old label set (Measured / Likely / Watching) and stale counts. Reframe it around "absorbed"
    (what didn't move, and why that's interesting), or hold it until b7/b8 report.
12. **Operations:** the repo SQL drifts from the live functions; the handoff runbook missed decoy seeding; the
    finisher could strand a batch; the b8 tick could retry forever. Add an engine status view and a check that
    hashes live function definitions against the repo, and keep a check-in routine while batches run.

