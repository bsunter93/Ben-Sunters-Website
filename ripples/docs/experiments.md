# Ripple Map — modeling experiments (registered 2026-09-27)

> **Direction (D-26, 2026-09-27):** the product is cultural ripples. The research program is now organized around three
> questions in `discovery_engine.md`:
> - Q1: rediscover known cultural ripples (E9 phase 1).
> - Q2: improve candidate generation without more false discoveries (the cultural lab, with methods D1–D4).
> - Q3: an unknown discovery survives held-out confirmation.
>
> E1–E8 below are disaster/economic proving-ground experiments. They still inform the shared machinery (estimators,
> calibration, pooling), but they are not the product.

Goal: find a way to uncover **surprising** shock → outcome links **repeatably**, without giving up the rigor rules
(pre-registration, decoys, held-out confirmation, withholding). Eight batches so far confirmed only obvious links, and the
one real lead (floods → finance jobs) failed only on power. The problem is method power and data resolution, not
imagination, so the first experiment measures which methods can actually find a modest effect in this data.

## Ground rule for every experiment

Method experiments never look at real treated units. They run on **placebo units** (donor counties given fake
treatment) with **injected effects** of known size. A method is judged by *recall* (how often it finds an injected
effect of size δ) at a fixed *false-positive rate* (how often it "finds" something at δ = 0). Only after a method wins
on placebo data is it applied to real shocks, under a fresh pre-registration with held-out confirmation.

## E1 — Method bake-off on injected effects (first; needs the b9 county data)

- Data: the b9 county panel (QCEW finance + total private), real flood event dates and real state structure, but the
  "treated" set is replaced by randomly chosen donor counties (same state, same dates). The real designated counties
  are excluded from E1 entirely.
- Injection: δ ∈ {0, −0.5%, −1%, −2%, −3%} added to pseudo-treated counties' log employment in months 13–24.
- Methods compared:
  - M1 same-state mean difference (the registered b9 design).
  - M2 precision-weighted (counties weighted by the inverse of their own pre-period volatility).
  - M3 matched donors (the 10 donors whose pre-period path best matches each treated county).
  - M4 pooled/shrunk event effects (empirical-Bayes random effects across events instead of a plain mean).
  - M5 dose-weighted (weight events by a size measure: designated-county count now; flood-insurance dollars later).
- Output: a power curve per method (recall by δ) with the false-positive rate at δ = 0 held at ≤ 5%. Winner = best
  recall at −1% and −2% with calibrated false positives. Runs outside the database from an exported, placebo-only
  extract, so it adds no load.

### E1 result (2026-09-27, ledger 1278; `ripples/docs/results/e1_bakeoff_2026-09-27.json`)

56 usable flood events (placebo donors only), 1,000 replicates. Two findings:

1. **Analytic p-values over-reject.** At a nominal p ≤ 0.05 with no real effect, every method "found" something too
   often: M1 7.5%, M2 9.8%, M3 17.2%, M4 9.2%, M5 7.1%. Every real test must use a permutation or placebo null (as b9
   did) or a placebo-calibrated cutoff.
2. **Pooling wins.** Recall at an honest 5% false-positive rate:

| method | −0.5% | −1% | −2% | −3% |
|---|---|---|---|---|
| M1 mean difference (b9's design) | 10% | 17% | 38% | 67% |
| M2 precision-weighted | 11% | 22% | 55% | 87% |
| M3 matched donors | 13% | 23% | 55% | 84% |
| **M4 random-effects pooling** | **15%** | **35%** | **78%** | **98%** |
| M5 dose-weighted (county count) | 12% | 23% | 59% | 88% |

M4 roughly doubles recall at −1% and −2% and is the estimator for E2/E4, always with a calibrated null. Small effects
(−0.5%) stay out of reach with this many events; that needs more events or better outcomes, not a better formula.

## E2 — Spillovers: does the ripple travel?

The vision is "wherever the impact shows up". Test undeclared **neighboring** counties (and the next ring out) for
effects opposite or equal to the hit county: displaced jobs, customers and workers move next door. Surprising links are
likely to live here, and the geography is exactly what a 12-year-old can see on a map.

## E3 — Network propagation: follow the people and the money

Predict **where** a ripple lands from real connection data, then test there: IRS county-to-county migration flows
(where people go after a disaster), Census commuting flows (LODES) and industry input-output links. Hypothesis form:
"counties strongly connected to a hit county show effect X" vs weakly connected counties. This turns "anywhere" into a
testable map and gives each link a mechanism (traceability).

## E4 — Dose-response

Replace yes/no shocks with size: flood-insurance claims paid (OpenFEMA NFIP), individual assistance dollars, NOAA damage.
A monotone effect in dose is far more convincing than a binary difference and needs fewer events.

## E5 — Regression discontinuity on aid eligibility

FEMA Public Assistance uses per-capita damage thresholds. Counties just above vs just below get aid or not, almost at
random. The effect of the **aid itself** (construction, finance, population) is a clean causal ripple, and often a
surprising one.

## E6 — Multi-outcome fingerprints

Test the whole vector of county outcomes jointly (jobs by sector, wages, business counts, unemployment, rents, air
quality) with one permutation statistic, then decompose the ones that move. One joint test replaces dozens of separate
ones, so the multiple-testing penalty stops drowning small effects.

## E7 — Predictive validity

Treat a link as real only if it **predicts**: fit on 2001–2015 shocks, forecast the outcome path for 2016+ shocks,
score against a no-shock baseline. Surprising links that forecast out of sample are the most defensible kind of finding
and the most repeatable.

## E8 — Anomaly-first v2 (b8 fixed)

Re-run the anomaly lane at county level with year-matched fake shocks, empirical p-values and per-year anomaly scaling.

## E9 — Cultural shocks: do well-known social trends leave measurable ripples? (owner direction 2026-09-27)

The product hook: relatable trends people remember (a book, a show, a movement) and whether they measurably changed
anything downstream, *as a contributing driver, not the only one*. Owner's example: did the Fifty Shades wave (2011–2015)
measurably shift how people talk about sex, and on into other outcomes? Culture has no geographic footprint and
everything trends together, so a naive before/after would "confirm" almost anything. E9 therefore runs in two phases,
and phase 2 is registered only if phase 1 passes.

### Phase 1 (registered now): can the method recover known cultural ripples and reject fake ones?

Positive controls (documented effects; each one hypothesis, fixed in advance):

| # | shock (date) | outcome | expected |
|---|---|---|---|
| P1 | The Queen's Gambit on Netflix (2020-10-23) | en.wikipedia pageviews of "Chess" | up, days 1–60 |
| P2 | Stranger Things 4 vol. 1 (2022-05-27) | en.wikipedia pageviews of "Kate Bush" | up, days 1–60 |
| P3 | Game of Thrones premiere (2011-04-17) | US births named Arya (SSA national names) | up, 2012–2016 vs 2006–2010 |
| P4 | Frozen release (2013-11-27) | US births named Elsa (SSA) | up in 2014 vs 2009–2013 |

Designs (identical code for every hypothesis, real or fake):
- **Pageviews (timing design).** Effect = mean log daily views days 1–60 minus days −90..−1. Null 1: the same article
  at 500 placebo dates (outside ±180 days of the real date, same weekday). Null 2: a pre-listed set of 4–6 comparison
  articles on the real date (P1: Checkers, Go (game), Backgammon, Poker, Sudoku; P2: Madonna, Cyndi Lauper, Peter
  Gabriel, Tears for Fears, Depeche Mode). Pass = empirical p ≤ 0.05 against null 1 **and** effect above every
  comparison article.
- **Baby names (synthetic control).** Outcome = log count by year. Donors = names ranked 200–2000 over the pre-period
  with no link to the same title, weighted to match the pre-period path. Null = placebo-in-space over donors. Pass =
  rank p ≤ 0.05.
- **Negative controls.** 200 random (article or name, date) pairs from the same pools run through the same code;
  target false-pass rate ≤ 5% (Wilson upper bound reported). Plus each positive date applied to an unrelated article
  ("Photosynthesis") and unrelated name.

Phase 1 passes if **at least 3 of 4** positive controls pass **and** the negative false-pass rate is ≤ 5%. If it
fails, E9 stops and that is reported plainly; the design gets fixed before any real trend is tested.

### Phase 1 result (2026-09-28, ledger 1282; `ripples/docs/results/e9_phase1_2026-09-28.json`)

**Passed.** All 4 known ripples were recovered, and 2 of 200 fake events passed (1%; upper bound 3.6%).

| # | ripple | effect | p | beat every comparison? |
|---|---|---|---|---|
| P1 | Queen's Gambit → "Chess" pageviews | +1.21 log (≈3.4× views) | 0.002 | yes (next best Go, +0.36) |
| P2 | Stranger Things 4 → "Kate Bush" pageviews | +2.60 log (≈13×) | 0.002 | yes (next best Depeche Mode, +0.47) |
| P3 | Game of Thrones → girls named Arya, 2012–16 | +1.24 log (≈3.5× synthetic control) | 0.013 | n/a |
| P4 | Frozen → girls named Elsa, 2014 | +0.85 log (≈2.3×) | 0.010 | n/a |

- Unrelated controls all failed: Photosynthesis on both show dates, and the name Ruth with both name designs.
- The two false passes were pageview dates for Tears for Fears (2023-05-26) and Cyndi Lauper (2023-12-01). Both
  are music articles, where real news bumps are common. No fake name event passed.
- Details fixed before the run (ledger 1281):
  - The seed (20260928) is set in the script, not this doc. An earlier informal note said "seed 9"; that was never
    registered.
  - The Elsa counts were seen while checking the data load, after the code was written. Nothing changed after that.
- What it means: the verification layer can tell a known ripple from a fake one on these two outcome types. It
  says nothing yet about *finding* ripples nobody named; that is Q2 (the cultural lab) and Q3.
- Caveat: the four ripples are famous and large. Smaller ripples will be harder, and the lab measures that.

### Phase 2 (pre-registered separately after phase 1): the trend screen

- Catalog of about 30 well-known trends since 2010, each with a dated release or peak and a comparison title of similar
  size without the theme (e.g. Fifty Shades vs another same-year mega-bestseller; #MeToo 2017-10-15; Ice Bucket
  Challenge; Serial; Hamilton; Tiger King; Squid Game; Barbie; Eras Tour).
- Outcomes screened with the phase-1 designs: Wikipedia pageviews (topic articles, not the title itself), SSA names,
  and where available state-level variation (Google Trends by state only if a sanctioned route exists; library
  checkout open data; CDC and BLS series) so exposure differences can be tested, not just timing.
- Direct echoes (the title's own article, its author, its actors) are excluded as obvious. BH correction across the
  screen, held-out confirmation on later events of the same kind, and the language "measurably contributed to",
  never "caused".

Data: Wikipedia pageviews from 2015 via the existing BigQuery backfill workflow (P3/P4 need no pageviews); SSA national
and state names files (keyless, public domain).

## Order and cost

E1 first (it decides which estimator every later test uses), then E4 + E2 (cheap once NFIP and county adjacency are
loaded), then E3 (needs IRS migration and LODES, both keyless), E5, E6, E7, E8. E9 phase 1 runs in parallel (different data; no
dependency on the county panel). Each real-data application gets its own
ledger pre-registration; method benchmarks are registered once here (ledger entry "experiments-program").
