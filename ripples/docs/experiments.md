# Ripple Map — modelling experiments (registered 2026-09-27)

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

## E2 — Spillovers: does the ripple travel?

The vision is "wherever the impact shows up". Test undeclared **neighbouring** counties (and the next ring out) for
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

## Order and cost

E1 first (it decides which estimator every later test uses), then E4 + E2 (cheap once NFIP and county adjacency are
loaded), then E3 (needs IRS migration and LODES, both keyless), E5, E6, E7, E8. Each real-data application gets its own
ledger pre-registration; method benchmarks are registered once here (ledger entry "experiments-program").
