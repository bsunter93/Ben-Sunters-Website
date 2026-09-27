# Ripple Map — handoff (2026-09-27 03:35 UTC)

Read this first. It is everything a new chat needs to continue: who the owner is and what they want, the rules, how the
system is built, exactly what is running right now, and the runbook for the next steps.

Repo `bsunter93/Ben-Sunters-Website`, working branch `claude/admiring-goldberg-u36vlz` (merged to `main` through PR #15;
later commits are on the branch only: b7 + b8 SQL and this file). Live site: https://bensunter.com/ripples/ →
`/ripples/pond/` (GitHub Pages from `main`). Supabase project `kffkasnzqcddpystszch` (Pro plan), schema `ripples`.

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
- The owner said "merge it and make it live" for PR #13/#14/#15. Otherwise, do **not** open or merge PRs without an
  explicit go-ahead.

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
| fx63-b6-unexpected | 7 industry job panels plus weekly CDC deaths | pre-registered, **not frozen** | 1209 |
| fx63-b7-decade | historical shocks 2000–2018, year-after window, 14 outcomes | pre-registered, **not frozen** | 1211 |
| b8-anomaly-first | anomaly scan, work back to shocks vs season-matched fake shocks | pre-registered; smoke test on the positive control passed (storms → FEMA-declaration spikes 5.2× fake shocks, p<1e-4); **not started** | 1212, 1213 |

Why the engine only found obvious links (diagnosis given to the owner):
1. It only measured first-order things, about 15 outcomes (now widened by b6 and b8).
2. The shock catalog started in 2019 (b7 fixes this, but for jobs outcomes the usable window is effectively 2011–2023,
   because first-release data starts in 2005 and 2008–09 and the pandemic are excluded).
3. The rigor gates favour big direct effects.
4. The data is state-level and monthly, which is coarse.

## 6. What is running right now (as of 03:34 UTC)

- `att-hist-fema` (every 2 minutes): 7 of 20 declaration years done, 12 queued, 1 in flight. It finishes on its own
  around 04:05 UTC.
- The FRED drain is **complete**: 547 fetched plus 14 missing = 561. CDC weekly deaths are complete (51 states,
  2014-01 to 2026-07; the last 8 weeks are never ingested).
- `att-anom-b8` cron is scheduled but idles until `engine63.anom_go = true` **and** `att_anom_start` has queued tasks.
- **No fx63 step or finisher workers are scheduled.** The finisher unschedules them when a batch ends.
- The old chat's 04:15 check-in trigger (`trig_01HEUpAbjUwd5LixsA5JLAgb`) was **disabled** for this handoff. The new
  chat owns the runbook below. Set your own reminders with `send_later` if you want check-ins.
- DB about 516 MB of the 6000 MB cap. The space guard cron `att-fx63-space-guard` unschedules steps above 5800 MB.

## 7. Runbook — do these in order

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
