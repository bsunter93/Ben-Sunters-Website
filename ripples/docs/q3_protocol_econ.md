# Q3 real-world lens: screen v2 families against electricity demand, markets and air travel (registered 2026-09-28, before it is run)

Why: attention ripples are only half the question. This lens asks whether the same event families move things people
do or pay for, measured daily.

## Design

- **Method:** discovery v1 (ledger 1283): same statistic, placebo calibration, 1,000 moved-date worlds, family-wise
  maximum over outcomes, both-z rule at p ≤ 0.05, leave-one-member-out, and Benjamini–Hochberg at q = 0.10 across the 14
  families. Everything not stated here follows `q3_protocol_v2.md`.
- **Event curves:** from Wikipedia with redirect-summed views, as in screen v2.
- **Families:** the 14 screen v2 families (`ripples/corpus/q3_families_v2.tsv`, 115 events), unchanged.
- **Outcome panel:** `ripples/lab/econ_panel.py`, from `att_q3_econ_export` (`ripples/attention/sql/50_att_q3_econ_export.sql`),
  2015-07-01..2026-08-31. There are 169 daily series:
  - electricity demand for 59 balancing authorities and 88 subregions (EIA-930);
  - 21 FRED daily market series: oil, gas and jet fuel prices, exchange rates, Treasury yields, policy rates,
    breakevens;
  - TSA checkpoint passengers (2019 on).
  Supply-side grid series (generation, wind, solar) are left out: they follow weather, not people.
- **Transform (fixed before scoring):**
  - Levels are logged; rates stay in percentage points.
  - Gaps of up to 4 days are carried forward.
  - Demand and passengers have the median of the same weekday over the previous 8 weeks removed.
  - No cross-series median is removed: the series are too different for one.
- **Three changes from the Wikipedia screen, because these series have weekly cycles and gaps:**
  - **Weekday-matched dates.** Placebo dates and moved dates keep each event's weekday (`--same-weekday`), so an event
    family that falls on Sundays is compared with other Sundays.
  - **Coverage rule.** An outcome gets no score for an event when less than 80% of the event's window (days −15..+90)
    has data (`--min-coverage 0.8`). Its rank score is taken against the placebo dates that do have data. For example,
    TSA data before 2019 is missing.
  - **No echo flag.** No series here is a Wikipedia article, so nothing is flagged; every candidate is checked by hand
    for an obvious direct mechanism (for example, a storm cutting power demand).

## What this can and cannot show

- **Validity:** the moved-date null is built on this panel with the same weekday matching, so the false-family rate
  stays nominal.
- **Power:** unmeasured here. Daily demand and markets are noisy and driven by weather and macro news; a null result is
  weak evidence of no effect.
- **Expected positives (not discoveries):** disasters_shocks may move regional electricity demand (outages), and
  finance_shocks may move yields or the dollar. They show the lens works.
- **Status:** candidates only. Each needs its own held-out confirmation.
- **Weekly and monthly series:** state unemployment claims, business applications, deaths and monthly state
  economics need a weekly version of the method. That is registered separately.
