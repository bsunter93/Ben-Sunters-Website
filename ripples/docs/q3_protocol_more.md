# Q3 further lenses: daily extras, weekly and monthly outcomes (registered 2026-09-28, before any is run)

Why: the engine should see ripples wherever they land, not only in page views. Three more outcome panels are scored
with the 14 screen v2 families (`ripples/corpus/q3_families_v2.tsv`, 115 events). The families are unchanged.

## Common to all three lenses

- **Method:** discovery v1 (ledger 1283): same statistic, placebo calibration, 1,000 moved-date worlds, family-wise
  maximum over outcomes, both-z rule at p ≤ 0.05, leave-one-member-out.
- **Correction:** Benjamini–Hochberg at q = 0.10 across the 14 families, **within each lens**. Lenses are reported
  separately; nothing is pooled across lenses.
- **Event curves:** from Wikipedia with redirect-summed views, as in screen v2. On weekly and monthly grids, the event
  curve is the mean of log daily views within each period.
- **Coverage rule:** an outcome gets no score for an event when less than 80% of that event's window has data. Its
  rank score is taken against the placebo dates that do have data (as in `q3_protocol_econ.md`).
- **Builder:** `ripples/lab/more_panels.py`, from the read-only export `att_q3_export`
  (`ripples/attention/sql/51_att_q3_export.sql`). All transforms are fixed here, before any event is scored.

## Lens 1: daily extras (`daily2_pv.npz`)

- **Series:**
  - Hacker News story mentions for about 1,000 topics, plus all stories (2022-08 on);
  - npm downloads for 13 packages and the total (2022-06 on);
  - NYC transit ridership, 9 modes (2020-03 on);
  - FEMA disaster declarations by type and state (2019 on).
- **Transform:** log(1 + count), with gaps up to 4 days carried forward. Then subtract the median of the same weekday
  over the previous 8 weeks.
- **Dates:** placebo and moved dates keep each event's weekday.
- **Coverage:** these series start late, so many events before 2022 get no score for Hacker News or npm outcomes by the
  coverage rule. The lens effectively tests the later members of each family.
- **Echo flag:** Hacker News topics are names, so the name-matching echo flag applies to them (as for NYT tags).

## Lens 2: weekly (`weekly_pv.npz`)

- **Series:** initial and continuing jobless claims by state, weekly business applications by state, weekly deaths
  from all causes by state, and weekly gasoline and diesel prices.
- **Grid:** weeks starting Sunday, 2015-07-05 to 2026-08-30. A week-ending-Saturday value belongs to the week that
  ends that day.
- **Transform:** log of levels, minus the median of the same week in the previous three years (at least two
  available). This removes the yearly cycle using only the past.
- **Event window:** −2..+13 weeks. Pre-period: 9 weeks.
- **Admissible range:** from week 61, to 18 weeks before the end.

## Lens 3: monthly (`monthly_pv.npz`)

- **Series:**
  - For each state: unemployment rate; jobs total and by sector; building permits; active and new home listings;
    days on market; minimum wage.
  - National jobs by industry (BLS CES) and consumer prices by item (CPI).
- **Transform:** log of levels; unemployment rates stay in percentage points. Then subtract the median of the same
  month in the previous three years (at least two available).
- **Event window:** −1..+3 months. Pre-period: 2 months.
- **Admissible range:** from month 15, to 5 months before the end.

## What this can and cannot show

- **Validity:** each lens's moved-date null is built on its own panel, so its false-family rate stays nominal.
- **Power:** unmeasured. Weekly and monthly lenses have few points per event window, and the daily extras cover few
  events, so null results are weak evidence of no ripple.
- **Candidates:** every candidate is checked by hand for an obvious direct mechanism. For example, a disaster family
  moving jobless claims in the struck state is an expected positive, not a discovery.
- **Status:** candidates only. Each needs its own held-out confirmation.
