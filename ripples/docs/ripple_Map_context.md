# Ripple Map: context brief (updated 2026-09-27 18:10 UTC)

Standalone context for anyone (person or new chat) picking up Ripple Map. It covers the vision, the current status,
what we learned, pitfalls, open gaps and next steps. The operational runbook with exact commands is
`ripples/HANDOFF.md`, and the experiments plan is `ripples/docs/experiments.md`.

- Live site: https://bensunter.com/ripples/pond/
- Repo: `bsunter93/Ben-Sunters-Website`
- Database: Supabase project `kffkasnzqcddpystszch`, schema `ripples`. The compute tier went from nano to micro on
  2026-09-27.

---

## 1. Vision (owner, verbatim core)

> "The entire point of the app is uncovering hidden impacts from upstream events — regardless of where that impact
> shows up. Attribution and traceability with statistical rigor are key."

- **Obvious links are worthless.** "Storm → energy demand" is not a product. The product is the link nobody would guess.
- **One shock, many outcomes.** A shock is one-to-many, not one-to-one.
- **Resilience is a finding.** A shock that dies out (for example, Florida absorbing a hurricane) is worth showing, but
  only against a counterfactual.
- **Anomaly-first, not list-first.** Start from whatever moved unusually and work backwards to causes.
- **Decade scale.** Compare old shocks' long-run outcomes with recent ones.
- **Audience.** A 12-year-old must get it. Statistics sit behind links, with short plain summaries.
- **Design.** Serious, sleek, not cartoony. The pond must feel like water. Outcomes are not on a perimeter, and rings
  are not always visible.
- **Honesty.** Report blunt results, including "nothing survived".

## 1a. Product thesis (revised 2026-09-27)

**Anchor on the trends people remember; use every other dataset as the places a ripple could land.**

The owner's user story:
- Fifty Shades of Grey was a huge wave in 2011–2016.
- Did it measurably change how people talk about sex, and did that carry on into #MeToo-era conversation, the rise of
  OnlyFans, or legislation?
- It doesn't need to be the primary or only driver. The interesting question is whether a trend people remember had a
  *measurable* impact on downstream behaviours and outcomes.

What that means:
- **The stone is a relatable social or cultural trend:** a book, a show, a film, a movement, a viral moment. Disasters
  and economic releases stay as a second shelf and as a proving ground for the method.
- **The ripples can land anywhere we measure:**
  - what people search and read (Wikipedia pageviews, search interest)
  - what they name their children (SSA names)
  - what they buy (BLS spending, product categories)
  - health and social outcomes (CDC)
  - work and money (QCEW, claims)
  - the law (legislation timelines)
- **The claim is contribution, not cause.** Plain labels:
  - "moved at the same time"
  - "moved more where more people were exposed"
  - "measurably contributed to"
  - "didn't move"

  The product never says "caused".
- **Why it can be a hit:** the stone is relatable and the landing spot is surprising. That pairing is the share object
  ("Frozen changed what parents named their daughters, then it reversed").
- **What keeps it honest:** culture has no footprint, and everything trends together. Every cultural claim therefore
  needs at least one of the following, and the method must first recover known effects (E9 phase 1) before any new
  trend is tested:
  - sharp timing tested against placebo dates
  - uneven exposure (country, state, release stagger)
  - a comparison title of similar size without the theme

## 1b. Design concept and direction (revised 2026-09-27)

The pond language stays. What changes is what goes in it and how the evidence reads.

- **Find is a shelf of things you remember,** grouped by year ("2013: Frozen, Harlem Shake, Breaking Bad finale"). Each
  card shows the trend and one teaser of where it rippled ("…and 3 places you wouldn't guess"). Disasters sit on a
  second shelf.
- **Trend page = the pond:**
  - The stone drops at the trend's date.
  - Rings spread over months and years, not days.
  - Outcomes that moved bob and send their own small ripple. Their distance from the stone is surprise (domain
    distance), so obvious echoes sit close and quiet, and far landings are the story.
  - Outcomes that didn't move are shown as still water, because "it didn't change X" is a finding too.
- **Ghost stone:** the comparison title is drawn faint beside the real one ("Fifty Shades vs. the other #1 bestseller of
  2012"). Where the ghost's rings match the real one's, it says so; that is the honesty device a 12-year-old can see.
- **Exposure map:** where exposure varied (states, countries), a small map shows "more exposure → bigger move". That is
  the strongest visual proof we can give.
- **Evidence ladder behind a link:**
  - timing (moved right after the date)
  - comparison (moved more than the ghost)
  - exposure (moved more where more people were exposed)
  - replicated (seen after similar trends)

  Each rung is a plain sentence. The statistics stay one click deeper.
- **Headline pattern:** "[Trend] measurably contributed to [surprising outcome]. It wasn't the only reason: [the other
  things going on]." Or: "[Trend] was everywhere, and it didn't change [thing you'd expect]." Both are shareable.
- **Tone:** serious and sleek, not cartoony, with water that feels like water. No outcomes on the rim; rings appear as
  the wave reaches them.
- **Order of work:**
  1. E9 phase 1 (method on known ripples).
  2. Phase 2 screen.
  3. The first trend pages built only for trends with a result.
  4. The share card built around the ghost stone and the surprising landing.

## 2. Current status (one screen)

**Product.** The pond explorer is live. Every shock page reads absorbed, expected or still unfolding. **No surprising
link has passed confirmation yet**, and the pages say so.

**Engine.** Pre-registered, hash-chained ledger (now about 1,274 entries), decoy universes, held-out confirmation, BH
correction, seasonal check and withholding. It works: across b6 and b7, 80 decoy selections produced 0 false
confirmations.

**Batches so far**

| batch | question | result |
|---|---|---|
| b1–b2 | first-order effects | confirmed, but only obvious links (storm → power, and so on) |
| b3–b5 | housing and jobs downstream | not testable, or withheld on the seasonal check |
| b6 | 7 industry job panels + CDC deaths | 0/12 confirmed |
| b7 | historical shocks 2000–2018, year-after window | 0/10 confirmed; **one real lead** (below) |
| b8 | anomaly-first scan | nothing surprising; 5 "confirmations" withheld as a year confound |
| b9 | county-level flood → finance jobs | **not supported** (−0.43%, p 0.37, 91 floods, 1,133 counties; ledger 1277) |

**The one lead (now tested and not supported at county level).** Floods → finance/insurance/real-estate jobs **−3.3%** in months 13–24.
- q 0.030, CI −5.5% to −1.1%, 10 of 11 held-out floods negative.
- It failed only the power gate (power 0.38).
- The same outcome was b6's nearest miss (months 6–11).

b9 tests it at county level with its own pre-registered design:
- Treated counties: FEMA flood-declared counties.
- Controls: same-state counties with no declaration.
- Outcome: QCEW private finance employment, months 13–24.
- Null: in-space permutation.
- Primary threshold: one-sided p ≤ 0.05.

**b9 result (18:45 UTC, ledger 1277): not supported.**
- Primary: finance jobs in flood-declared counties vs same-state undeclared counties, months 13–24: **−0.43%**,
  one-sided p **0.37** (1,000 permutations), 91 floods, 1,133 counties. Half the floods went each way (49.5% negative).
- Secondaries: finance months 6–11 −0.60% (p 0.29); total private jobs −0.38% (p 0.24); finance minus total −0.02%
  (p 0.49). Finance does not move differently from the rest of the local economy.
- Reading: the state-level lead does not replicate at county level. The state result was most likely the kind of
  chance finding the power gate exists to catch. The engine did its job: it refused to confirm a link that doesn't hold.
- Data: QCEW 2001–2026Q1 complete (about 76k rows a year; 2001–2013 from BLS bulk files, ledger 1274).

**Other data now flowing**
- HUD Fair Market Rents by county: GitHub Actions job. 2017–2020 verified; the rate-limit fix is merged (PR #21).
- EPA daily AQI by county, reduced to weekly: GitHub Actions job, about 100k rows a year. It resumes by year from 2010.
- Keys stored in Vault: Census, BLS, FRED, api.data.gov (FBI crime data), EPA AQS + email, USDA NASS, HUD, OpenAQ.

**Experiments program** (`ripples/docs/experiments.md`, ledger 1272)

| # | experiment | status |
|---|---|---|
| E1 | method bake-off on placebo counties with injected effects | tooling built; runs when b9 data is complete |
| E2 | spillovers to neighbouring counties | planned |
| E3 | network propagation (IRS migration, LODES commuting, input-output) | planned |
| E4 | dose-response (NFIP claims dollars) | planned |
| E5 | regression discontinuity at FEMA aid thresholds | planned |
| E6 | multi-outcome fingerprints (one joint test) | planned |
| E7 | predictive validity (fit 2001–2015, forecast 2016+) | planned |
| E8 | anomaly-first v2 at county level, year-matched | planned |
| E9 | cultural shocks: known ripples first (phase 1), then a trend screen (phase 2) | phase 1 registered (ledger 1275) |

## 3. Learnings

1. **The rigor machinery works, and it is strict.** Decoys produce no false confirmations. The cost is that small real
   effects fail the power gate, so better data and designs, not looser gates, are the way forward.
2. **Resolution is the bottleneck, not imagination.** State-monthly data dilutes local shocks. A storm that wrecks 10
   counties barely moves a state total, so "absorbed" can just mean diluted. County footprints plus county outcomes
   are the biggest lever.
3. **Nulls must match the treated units' years.** b8's 5 "confirmations" came from 2024+ claims anomalies running
   3–4× the pre-2020 rate against fake shocks drawn from all years. Use year-matched or in-space permutation nulls,
   empirical p-values, and per-year anomaly scaling.
4. **The normal tail approximation is anti-conservative:** 2.7% at a nominal 1%. Prefer empirical p from many draws.
5. **Catalog contamination is real.** Katrina evacuee declarations spanned 47 states, and 9/11, a refinery explosion
   and a plant fire were typed as "Fire" (wildfire). Always inspect raw event rows before freezing a batch.
6. **Regime breaks must be excluded:** the pandemic (2020-02-15 to 2021-06-30) and the 2008–09 financial crisis.
   Claims data is still abnormal through 2022.
7. **One lead repeated across two independent batches:** flood → finance jobs. Repetition across designs is the
   strongest signal we have. The b9 county test existed because of it, and it did not hold (ledger 1277): even
   repetition across two state-level batches was not enough, so county-level confirmation stays mandatory.
8. **Choose methods on placebo data, never on real treated units.** That is how E1 is built, so choosing a method
   cannot peek at the answer.
9. **Obvious-link filtering by regex is weak.** Surprise should come from the mechanism graph and domain distance.

## 4. Pitfalls (operational, learned the hard way)

**Database load**
- **Disk-IO burst budget.** Session 2's jobs exhausted it and the database stopped answering for about an hour.
- Rules: never more than one heavy every-minute job, never more than about 20k rows in one transaction, and stagger
  schedules.

**Tooling**
- **MCP `execute_sql` past 60 s** returns an error but **keeps running server-side**. Run long work as one-off cron
  jobs.
- **Repo SQL drifts from live functions.** Patch by anchoring on `pg_get_functiondef`, never on the repo text.
- **PL/pgSQL traps:**
  - Never put a `CASE` inside an `IF` condition.
  - Avoid variable names that clash with columns or keywords.
  - A multi-statement MCP call is one transaction.

**Engine**
- **Decoy seeding is manual** (`att_fx63_decoy_seed`). Without it a batch never finishes.
- Grids with no clean decoy date can loop forever; this is now tracked per grid.
- **Finishers** must not unschedule shared workers while another batch is unfinished. Each batch now has its own
  finisher.

**Network and APIs**
- The cloud container cannot reach most government APIs directly. The database (pg_net) can reach some. HUD and EPA
  refuse the database network, so they run on GitHub Actions.
- **API coverage surprises.** The QCEW open-data API only serves 2014+. HUD rate-limits at about 60 requests a minute.
  Always dry-run and read the logs before a real run.
- **Scheduled jobs must resume.** A job that restarts from year 1 every run never gets past its row cap. The fix was
  done-year tracking in `att_state`.

**Security**
- Keys never appear in logs or URLs that are printed. Grep for leaked keys before every commit.

**GitHub**
- Workflow dispatch from this integration returns 403, so the owner runs workflows. A new workflow only appears in
  Actions after its PR is merged to `main`.

## 5. Open gaps (most important first)

1. **No surprising link confirmed yet.** b9 (the one lead) did not hold at county level. Everything now depends on the
   experiments (E1–E9), above all the cultural-trends direction (E9), producing one that holds up.
2. **Measurement is narrow.** The scan only covers about 20 regional panels plus county QCEW. About 12k national series
   (Wikipedia, news, social, markets) are outside every test; they need a timing-only design (lane 2), labelled weaker.
3. **"Absorbed" has no counterfactual.** It needs a pre-registered resilient-versus-not comparison (Florida vs North
   Carolina hurricanes).
4. **No dose-response yet.** Candidate dose measures are NFIP claims dollars, NOAA damage, wind speed and burned acres.
5. **Too little held-out data.** Confirmation uses only 2024+ shocks. A second split (screen 2000–2015, confirm
   2016–2019 and 2022–2023) would roughly double power.
6. **b8 has no full decoy-universe calibration**, and its results are not wired into the pages ("Something unusual"
   mode).
7. **The page catalog is thin and skewed:** 26 small wildfires stuck on "unfolding", and no pages for historical shocks.
8. **Frontend debt:**
   - Share cards still show the rejected v1 design.
   - "Too early" markers sit on the pond rim.
   - No downstream "could ripple on to" exploration.
   - The flow diagram is tiny on phones.
   - Contrast is low in places.
9. **Newsletter issue 01** leads with an obvious link. Reframe it around what did not move, or hold it for a real
   finding.
10. **Operations:** there is no engine status view and no automated check that live functions match the repo.
11. **Viability:** the product only has a hook once one surprising, repeatable, explainable link exists. Until then it
    is an honest "nothing yet" machine.

## 6. Next steps

0. **E9 phase 1:** load SSA names and the 2015+ Wikipedia pageviews for the control articles, then run the four positive
   controls and 200 negative controls.
2. **E1:** export the placebo-only extract (`att_e1_extract`) and run `ripples/tools/experiments/e1_bakeoff.py`. Pick
   the estimator with the best recall at a calibrated false-positive rate.
3. **E4 and E2:** load NFIP claims and county adjacency. Pre-register dose-response and spillover tests using the E1
   winner.
4. **E3:** load IRS county migration and LODES commuting flows; test "connected counties" against weakly connected
   ones.
5. **Owner:** run the HUD + EPA job for real (untick dry run, EPA first year 2010). The weekly schedule then continues
   it.
6. Product work after the first real finding: wire anomaly results into the pages, add a resilience comparison, and
   regenerate the share cards.

## 7. Rules that never change

- Every test is pre-registered in the ledger before any result exists. Deviations are disclosed, and late ones are
  labelled late. Confirmations must pass the seasonal check or be withheld.
- Honest UA `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`. Stop on 429/503 with no same-day retry.
  No bypassing blocks. Aggregate data only, no personal data.
- Keys live only in Supabase Vault or GitHub secrets.
- The owner merges PRs. Claude opens them without asking.
