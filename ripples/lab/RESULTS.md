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

## Cultural lab on real pageviews, run 1 (2026-09-28, [Actions run 36363187938](https://github.com/bsunter93/Ben-Sunters-Website/actions/runs/36363187938))

Setup:
- Panel: 998 level-3 Vital Articles, daily user views from 2015-07-01 to 2026-08-31 (4,080 days).
- Events: 893 catalog events since 2015, given random fake dates.
- Each world: 150 fake events, 10 planted pairs, top 50 candidates out of about 150,000 (event, article) pairs; 10
  worlds per design.

| planted lift | naive | ghost | outcome-first | placebo-calibrated | detrended |
|---|---|---|---|---|---|
| +10% | 0.00 | 0.01 | 0.00 | 0.00 | 0.00 |
| +20% | 0.00 | 0.01 | 0.00 | 0.01 | 0.00 |
| +30% | 0.00 | 0.01 | 0.00 | 0.01 | 0.00 |
| +50% | 0.01 | 0.01 | 0.00 | 0.01 | 0.00 |

False "verified" candidates per world: naive 43, ghost 42.5, outcome-first 27.6, placebo 41.3, detrended 34.6.

Lessons (design, not findings):
1. **The search space is the problem.** Real attention spikes in popular articles (deaths, elections, the pandemic)
   fill the top of any list ranked across about 150,000 pairs. A sustained +50% lift never reaches the top 50. The
   known real ripples are much larger (Chess about 3.4×, Kate Bush about 13×; E9 phase 1). Run 2 measures the size
   threshold, and whether a smaller search (15 events per world) helps.
2. **The persistence check verifies almost nothing.** Most false candidates pass it, because real attention shifts in
   real data persist too. As the smoke tests already suggested, verification has to be replication-based (another
   event of the same class, or held-out ghosts), with BH control across all pairs.
3. Implication for D1–D4: blind search over (event × every outcome) can only find very large ripples. Useful
   candidate generation has to narrow the pairs first. Two options: relatedness priors (an outcome's link distance
   from the event's article, or shared Wikidata properties), or pooling across a class of events (D1 fingerprints),
   so that many small responses add up.

### Size threshold, old methods (2026-09-28, [run 36364608408](https://github.com/bsunter93/Ben-Sunters-Website/actions/runs/36364608408); recall in the top 50)

| planted lift | best method, 150 events per world | 15 events per world |
|---|---|---|
| +50% | 0.01 | — |
| +100% | 0.05 (placebo) | 0.38 (placebo) |
| +200% | 0.18 (placebo) | 0.76 (placebo) |
| +500% | 0.54 (placebo) | — |

Blind search needs about a 6× jump to find a single ripple half the time. Cutting the search to a tenth of the events
multiplies recall about 7×. That is the quantitative case for narrowing candidates before testing.

## Cultural lab run 2: event-coupled ripples and family pooling (2026-09-28, [run 36365876242](https://github.com/bsunter93/Ben-Sunters-Website/actions/runs/36365876242))

New in this run:
- **Event attention curves:** 889 of 893 catalog events, from their English Wikipedia views.
- **Coupled plants:** ripples follow the transplanted event's real attention curve (the mean lift over days 1–30 is
  the stated size).
- **Metric:** recall at a fixed false-discovery load. The fake-event null sets the cutoff: 1 or 0.1 false
  discoveries per world, 6 worlds per design.

**Single (event, article) pairs, coupled ripples** (recall at 1 / 0.1 false per world):

| method | +100% | +200% |
|---|---|---|
| naive, ghost, placebo, trend, robust | 0 / 0 | 0 / 0 (anom 0.04 / 0) |
| shape max-statistic | 0 / 0 | 0.02 / 0 |
| coupling (levels) | 0.03 / 0.02 | 0.03 / 0.03 |
| **onset-aligned coupling (day-to-day changes)** | **0.10 / 0.08** | **0.15 / 0.12** |

**Mixed ripple shapes at +100%:** no method finds steps, gradual rises, delayed or slope changes blind at this size.
Onset coupling finds some pulses (0.30) and coupled ripples (0.11).

**Families:** 3 planted families per world, each with 5 events of one type → one article, each member following its
event's curve. Recall at 1 / 0.1 false families per world:

| family pooling | members +30% | members +50% |
|---|---|---|
| **onset coupling, mean over all events of the type** | **0.22 / 0.22** | **0.56 / 0.56** |
| coupling (levels), mean | 0.17 / 0.11 | 0.39 / 0.17 |
| placebo, mean | 0.06 / 0.06 | 0.22 / 0.17 |
| robust, mean | 0 / 0 | 0.11 / 0.06 |
| any top-5 pooling (clip at 4) | 0 / 0 | 0 / 0 |

- Top-5 pooling saturated: many false families hit the clip ceiling (5 × 4 / √5 = 8.94). Some real articles' placebo
  spread (MAD) is far narrower than their real bursts. Run 3 tests rank-calibrated scores and a higher clip.
- On synthetic data the top-5 version was best (0.83). Real data differs, which is why every method is judged on real
  worlds.

Lessons:
1. **The working combination:** onset-aligned coupling plus family pooling. Families of 5 events at +50% per member
   are found about half the time with fewer than 0.1 false families per world. The best single-pair method finds
   15% of ripples three times that size.
2. Real ripples of the kind E9 confirmed (Kate Bush ≈ 13×, Chess ≈ 3.4×) are within single-pair reach only when they
   follow the event's curve.
3. Next:
   - Narrower, owner-defined families: sharper than broad Wikidata types.
   - Rank calibration (run 3).
   - Rival events on the same dates.
   - Exposure gradients, once place-level outcomes exist.

## Cultural lab run 3: fixes for top-k pooling, 3-event families (2026-09-28, [run 36368092528](https://github.com/bsunter93/Ben-Sunters-Website/actions/runs/36368092528))

Recall at 1 / 0.1 false families per world; 6 worlds, 3 planted families each (18 families per design):

| family pooling (onset coupling) | 5 events, +30% | 5 events, +50% | 3 events, +50% |
|---|---|---|---|
| **mean (MAD z, clipped at 4)** | **0.28 / 0.28** | **0.39 / 0.33** | **0.22 / 0.17** |
| mean of rank-calibrated z | 0.22 / 0.22 | 0.33 / 0.28 | 0.17 / 0 |
| top-k, clip 10 | 0.17 / 0.11 | 0.39 / 0.28 | 0.11 / 0 |
| top-k, rank-calibrated | 0.11 / 0.06 | 0.17 / 0 | 0 / 0 |
| top-k, clip 4 | 0 / 0 | 0 / 0 | 0 / 0 |

- Across runs 2 and 3, mean-pooled onset coupling finds about 25% of broad-type families at +30% and about 47% at
  +50%. With 18 families per design, each estimate is uncertain by about ±12 points.
- Top-k statistics fail on real data even when rank-calibrated. Many false families have several extreme members,
  so the cap is reached. Keep mean pooling.
- Single pairs with rank calibration score 0 at a fixed false-discovery load. 200 placebo dates cap each score, and
  too many false pairs tie at the cap.
- The remaining loss is dilution: a planted family is 5 of about 30 events of its type. Run 4 measures narrow,
  pre-defined families, the stand-in for owner-curated families. On synthetic data they reach 92% at +30%.

## Data sources for the cultural lab (2026-09-27)

| source | where | size | status |
|---|---|---|---|
| Google Books Ngram (eng 2020 release, 1990–2019) | Actions cache `ripples-ngram-v1-*` / artifact `ngram` | 173,325 words × 30 years (14 MB) | done in 18.5 min |
| Seattle library checkouts by subject heading | `ripples.att_sea` | 1,500 headings × monthly 2005+ | collecting (1 heading/min) |
| YouTube distinct commenters | `ripples.att_yt_breadth` | 956 videos / 667 events | collecting (≤ 4,000 units/day) |
| Wikipedia distinct editors | `ripples.att_wp_editors` | 1,862 events | starts 2026-09-28 00:10 UTC |
| GDELT news attention | `ripples.att_gdelt_tl` | 669 events since 2016-10 | blocked: HTTP 429 on first request from GitHub runners; weekly retry |
| Bluesky distinct authors per hashtag | `ripples.att_social_tags` | daily since 2026-09-23 | existing collector |
