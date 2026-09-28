# Q3 NYT lens: screen v2 families with news coverage as the outcome (registered 2026-09-28, before it is run)

Why: Wikipedia page views are one narrow lens on attention. The same event families are scored against a second,
independent outcome panel, NYT coverage, so a ripple can show up (or fail to) in what the press writes about, not only
in what readers look up.

## Design

- **Method:** discovery v1 (ledger 1283), unchanged. The statistic, placebo calibration, 1,000 moved-date worlds,
  family-wise maximum, both-z rule at p ≤ 0.05, leave-one-member-out and Benjamini–Hochberg at q = 0.10 across the
  14 families all follow `q3_protocol_v2.md`.
- **Event curves:** from Wikipedia, with redirect-summed views, as in screen v2. They only set each event's day 0 and
  its attention shape.
- **Families:** the 14 screen v2 families (`ripples/corpus/q3_families_v2.tsv`, 115 events), unchanged.
- **Outcome panel (the only change):** `ripples/lab/nyt_panel.py` builds it from the cached NYT Archive
  (counts only, no text), on the Wikipedia panel's day grid, 2015-07-01..2026-08-31.
  - Series: one per NYT index tag (subject, person, organization, place, creative work).
  - Value: 7-day trailing sum of articles carrying the tag, then log(1 + x) minus the all-tag daily median, as for
    Wikipedia.
  - Tags kept, by a fixed rule set before any event is scored: ≥ 300 articles in the window, present in ≥ 25% of its
    months, and the 1,500 largest by total.
- **Echo flag:** a tag is an echo when its name matches (case-, parenthesis- and "Last, First"-insensitive) the event
  article or any article it links to. Matching is looser than on Wikipedia and can miss renamed or differently worded
  tags, so a non-echo NYT candidate is checked by hand before it is called cross-domain.
- **Internal check:** The Queen's Gambit is in streaming_hits. If a Chess tag appears, it is an echo and shows the lens
  works; it is not a discovery.
- **Politeness:** event views come from the Actions cache left by the Wikipedia run. Anything missing is fetched with
  the standing rules (1 s pause, stop on 403/429/503, no retry). The one-day backoff approval (ledger 1289) does not
  extend to this run.

## What this can and cannot show

- **Validity:** the moved-date null is built on the NYT panel itself, so the false-family rate stays at the nominal
  level whatever the panel's quirks (sparse tags, the paper's own seasonality).
- **Power:** unmeasured on this panel. The lab's power numbers (about 67% at +30% for narrow families) are for
  Wikipedia views. NYT counts are sparser, so a null result here is weak evidence of no ripple.
- **Reading across lenses:** a candidate that appears on both panels for the same family is stronger than one on
  either alone. That is reported descriptively; it is not a registered test.
- **Status:** candidates only. Each needs its own held-out confirmation.
