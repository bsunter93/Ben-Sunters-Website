# Dose-response v1: legal cannabis and youth drinking, state by state (explore stage, pre-registered)

*Written Oct 3, 2026, before the run. The first rung above timing on the evidence ladder (D-14): exposure varies, so
the outcome can be compared where the cause arrived and where it did not.*

**Question.** In the Prohibition throughline, legal recreational cannabis is one of the popular catalysts for the
decline in young people's drinking. It arrived too late to start the decline (1981). Did it accelerate the decline
where it arrived?

**Data (free, fetched in CI).** CDC Youth Risk Behavior Surveillance System, state surveys, biennial 1991–2023: the
share of high-school students who drank alcohol in the past 30 days (total). Found by Socrata catalog search on
data.cdc.gov / chronicdata.cdc.gov; the probe logs the dataset and its columns. Exposure: the month retail
recreational cannabis sales began, by state (fixed list in `series_fetch.py`: CO 2014-01, WA 2014-07, OR 2015-10,
AK 2016-10, NV 2017-07, CA 2018-01, MA 2018-11, MI 2019-12, IL 2020-01, ME 2020-10, AZ 2021-01, MT 2022-01, NJ
2022-04, NM 2022-04, VT 2022-10, RI 2022-12, NY 2022-12, CT 2023-01, MO 2023-02, MD 2023-07). States with no retail
sales by 2023 are controls, whatever their medical status.

**Estimand.** For each legalizing state: the change in prevalence from the last survey before retail sales to the
second survey after (about four years), minus the mean change in control states over the same two survey years.
The reported effect is the mean of these differences over legalizing states with both surveys (percentage points).

**Inference.** Permutation: 2,000 draws assign each legalizing state's start date to a random state (with the same
survey availability), recompute the effect, and p is the share of draws with an effect at least as negative as the
observed one (one-sided: cannabis lowers drinking). The two-sided p is reported too.

**Pre-trend.** The same statistic for the two surveys *before* retail sales (placebo in time); its permutation p must
exceed 0.10 for the result to be called measured.

**Verdict rule (in the checker).** `measured` if p ≤ 0.05 and the pre-trend p > 0.10; `no movement` if p > 0.05;
`moved, pre-trend` otherwise. Any failure of the fetch is logged and the step stays `no data`.

**Also fetched.** NIAAA apparent per-capita ethanol consumption (gallons per person 14+, 1934–present) if the
published text file is reachable, so repeal's effect on drinking can be tested as a series (`file` test); otherwise
logged as missing.

**Output.** `ripples/docs/results/series_v1.json` with `series` (key → [[date, value]]) and `dose` (key → effect, p,
two-sided p, pre-trend p, n treated, n control, per-state rows, design, source).

## Addendum, Oct 3 (run 1 discarded)

The first CI run found a dataset by catalog search and used it without checking its name: it was the BRFSS adult
survey ("Adults who have had at least one drink of alcohol within the past 30 days"), with Yes and No rows and every
breakout mixed together. Its numbers were not the pre-registered outcome and are discarded. The NIAAA parser also read
state and beverage codes as values. Run 2 names the YRBS high-school dataset first, filters to state totals, keeps
only values between 0 and 100, and reads the United States all-beverage rows of the NIAAA file. The design, the
retail-start dates and the permutation scheme are unchanged.

## Addendum 2, Oct 3 (youth outcome unavailable; young adults added)

Run 4 read the right YRBS table (DASH high school, 46 states, 1991–2017). It cannot carry the design: the state
tables end in 2017, and Colorado and Washington, the first two retail states, do not take part in the state YRBS at
all. With two post-opening surveys required, no treated state qualifies, so the youth result is reported as
"not enough overlapping surveys" and stands as the pre-registered outcome's honest failure.

The same design is therefore also run on the nearest annual outcome that covers every state: BRFSS adults aged
18–24 who had at least one drink in the past 30 days (crude prevalence, 2011 to the latest year), with all adults
(Overall) as a secondary. Everything else is unchanged: retail start dates, last survey before to second survey
after, control states that never opened retail sales, 2,000 random assignments for p, and the two-surveys-before
placebo for the pre-trend. The Prohibition map's dose-response step reads the 18–24 result. Written before run 5.
