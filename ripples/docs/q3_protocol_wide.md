# Q3 library and wide Wikipedia lenses (registered 2026-09-28, before either is run)

Two more outcome panels for the 14 screen v2 families (`ripples/corpus/q3_families_v2.tsv`, 115 events, unchanged).

## Common to both lenses

- **Method:** discovery v1 (ledger 1283): same statistic, placebo calibration, 1,000 moved-date worlds, family-wise
  maximum over outcomes, both-z rule at p ≤ 0.05, leave-one-member-out.
- **Correction:** Benjamini–Hochberg at q = 0.10 across the 14 families, within each lens.
- **Event curves:** Wikipedia views summed over redirects.
- **Status:** candidates only. Each needs its own held-out confirmation.

## Library lens (`library_pv.npz`)

- **Series:** Seattle Public Library checkouts by subject, monthly, about 435 subjects, 2012 on
  (`att_q3_sea_export`, `ripples/attention/sql/52_att_q3_sea_export.sql`; builder `more_panels.py library`).
- **Transform:** log(1 + checkouts), minus the median of the same month in the previous three years (at least two
  available).
- **Grid and window:** calendar months; event window −1..+3 months, the same monthly settings as `q3_protocol_more.md`.
- **Coverage rule:** 0.8.
- **Echo flag:** subjects are names, so the name-matching echo flag applies.
- **Reading:** a ripple here is behaviour, not just reading about something online. It is one city's library, so a
  null result says little about the country.

## Wide Wikipedia lens (`pv_l4.npz`)

- **Series:** daily views of the Level-4 Vital Articles (about 10,000), together with the Level-3 articles of the
  current panel. The list is fixed the first time it is fetched (`$LAB_CACHE/vital_l4.json`).
- **Fetch:** `ripples/lab/l4_panel.py`, with the standing Wikimedia rules: one request at a time with a 1 s pause,
  honest User-Agent, stop on 403/429/503 with no retry that day, resuming on a later day.
- **Articles kept:** views on at least 90% of the days in the window 2015-07-01..2026-08-31.
- **When it runs:** once, when the panel is at least 90% complete and has at least 5,000 articles. This was amended
  from 95% on 2026-09-29 (ledger 1376), before any wide-lens result existed: the fetch stopped on a 429 at 9,033 of
  10,016 articles.
- **Analysis:** exactly screen v2 (`q3_protocol_v2.md`): the same outcome transform (log(1 + views) minus the all-series
  daily median), with no weekday matching and no coverage rule.
- **Why:**
  - **More reach:** ten times as many possible landing places for a ripple.
  - **The cost:** the family-wise maximum is taken over ten times as many outcomes, so each single outcome needs a
    stronger signal to pass.
  - **Validity:** the null accounts for this exactly.
  - **Power:** differs from the lab's figures for the 998-article panel, and is unmeasured here.
