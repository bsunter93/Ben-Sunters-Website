# Ripple Lab run log

| date | design | false discoveries / run (no plant) | recall 1% / 2% / 3% | notes |
|---|---|---|---|---|
| 2026-09-27 | synthetic smoke test | 0.00 | — | pipeline check only; empirical p resolution fixed by null-standardized p |
| 2026-09-27 | run 1: dl pooling, time split (screen < 2016, confirm 2016+), 11 supersectors × 3 windows × 6 groups, 60 worlds, 300 null draws | **0.017** (calibration 4.9%) | 5% / 20% / 48% | 450 usable events (storm 228/40, flood 56/40, winter 24/12, hurricane 29/2, fire 14/1, quake 4/0 screen/confirm): the confirm period is starved. Positive controls: hurricane → leisure q1–2 found in screen (−1.15%, p 0.02); **hurricane → construction not found** (−0.8% / −1.7%, wrong sign) |

| 2026-09-27 | run 2a: dl, time split (same as run 1) | 0.017 | 5% / 20% / 48% | reproducible |
| 2026-09-27 | run 2b: dl, **random-half split** | 0.017 | 3% / 22% / 33% | more confirm events (hurricane 18/13, storm 150/118) but half the screen events; no net gain. Positive controls: hurricane → construction still negative in both halves (−0.7%, −2.8%); hurricane → leisure q1–2 −1.0% in both halves (p 0.10, 0.13) |
| 2026-09-27 | run 2c: **mean** estimator, random split | **0.067** (over target) | 1% / 12% / 21% | worse on both counts; random-effects pooling stays |

**Where the disaster proving ground stands after runs 1–2:** verification is calibrated (false discoveries ≤ 0.02 per
run with DL pooling). Recall is bounded by the event universe: only 450 FEMA state-events survive the clean-donor rule
and the windows, whatever the split. The construction positive control failing in every design means county
designation is a poor measure of exposure: many designated counties are barely hit. That is the same lesson D3 (exposure
gradients) is built on. Per D-26 the engine's event universe now moves to cultural and social events (catalog:
`ripples.att_cult_events`), with ghost comparisons against same-time events rather than a time split, so year-wide moods
(for example the 2016 election) cancel instead of confounding.

## Cultural lab (`cultural_lab.py`), synthetic smoke tests only (300 articles × 1,100 days, random walk + weekly cycle + unrelated spikes; 440 catalog-shaped events; 150 fake events per world, 10 planted pairs, top-50 candidates)

| planted lift | naive | ghost | outcome-first | placebo-calibrated | detrended |
|---|---|---|---|---|---|
| +30% | recall 0.00–0.04 | 0.00–0.06 | 0.00 | 0.00 | 0.00 |
| +100% | 0.65 (verified 0.45) | 0.35 (0.30) | 0.00 | 0.35 (0.28) | 0.05 |
| +300% | 0.90 (0.50) | 0.85 (0.50) | 0.08 (0.05) | 0.93 (0.50) | 0.28 |

False "verified" candidates per world: 6–30 across methods. Lessons (for design, not findings):
1. The persistence check (response still present in days 31–60) rejects every decaying ripple (half the plants), and
   cultural ripples usually decay. Verification must be replication-based (another event of the same kind, another
   dataset, or held-out time), not "still there later".
2. The outcome-first method as written (largest 7-day jumps, split across events in the prior 14 days) is weak; it
   needs break detection against each article's own placebo distribution.
3. Verification thresholds are too loose (false verified per world 6–30); they need BH-style control over all
   (event, article) pairs.
4. Real calibration needs the real pageview panel (Vital Articles, daily, 2016+), fetched from 2026-09-28 because
   Wikimedia is paused for 2026-09-27 after a 429.
