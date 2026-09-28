# Q3 county jobs lens (registered 2026-09-28, before it is run)

- **What:** the 14 screen v2 families (`ripples/corpus/q3_families_v2.tsv`) scored with discovery v1 (ledger 1283)
  against monthly county employment.
- **Series:** QCEW employment for about 3,290 US county areas, in two series each: all industries (code 10) and
  financial activities (code 1023). About 6,500 series, 2012 through 2026-03.
- **Source:** `att_q3_qcew_export`, `ripples/attention/sql/53_att_q3_qcew_export.sql`.
- **Builder:** `ripples/lab/more_panels.py county`.
- **Transform, grid and window:** log employment, minus the median of the same month in the previous three years (at
  least two available). Calendar months; event window −1..+3 months; coverage rule 0.8. This is the monthly setting of
  `q3_protocol_more.md`.
- **Coverage:** QCEW ends 2026-03, so events after about 2025-11 get no score by the coverage rule.
- **Analysis:** moved-date null with the family-wise maximum over all 6,500 series; both-z rule at p ≤ 0.05;
  leave-one-member-out.
- **Correction:** Benjamini–Hochberg at q = 0.10 across the 14 families.
- **Reading:**
  - This is the most local economic lens.
  - A disaster family moving jobs in struck counties is an expected positive, not a discovery.
  - A ripple in counties far from the events would be the interesting kind, and needs a mechanism check by hand.
  - With so many series, each one needs a stronger signal to pass the family-wise test.
  - Power is unmeasured.
- **Status:** candidates only. Each needs its own held-out confirmation.
