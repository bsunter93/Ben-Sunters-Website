# Ripple Lab run log

| date | design | false discoveries / run (no plant) | recall 1% / 2% / 3% | notes |
|---|---|---|---|---|
| 2026-09-27 | synthetic smoke test | 0.00 | — | pipeline check only; empirical p resolution fixed by null-standardized p |

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
