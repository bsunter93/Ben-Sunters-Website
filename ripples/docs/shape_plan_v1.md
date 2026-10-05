# Shape plan v1: the shape and timing of a response, lag families, catalyst vs outcome strength

Registered Oct 4, 2026, before any shape, lag prior or strength statistic was computed on a real stone. Code:
`ripples/lab/discovery/shape.py` (mode `placebo` already run; mode `real` runs after this file is pushed). Calibration record:
`ripples/docs/results/shape_placebo_v1.json`. Results will go to `ripples/docs/results/shape_v1.json`,
`ripples/docs/results/lag_priors_v1.json` and `ripples/docs/shape_v1.md`.

## Why

Today a ripple is judged as "did Y rise after X". Two ripples with the same yes can be different findings: a spike
that faded in a week and a new level that is still there five months later. The engine also searches fixed windows
(the cultural lab's `car7`, `car30`, `car90`) whatever the link type, and it does not say whether a response was
large or small for the size of the shock that started it. This plan adds three things, using only series already in
the repository and no new data:

1. a transparent time-shape classifier for every stored response series aligned at its parent;
2. empirical lag distributions per link type from confirmed steps, as priors the engine can use instead of fixed
   windows;
3. catalyst strength against outcome strength per stone, with flags for disproportionate responses.

## Learning 8, and what the author has seen

Methods are chosen on placebo data only (brief, section 3, learning 8). Every threshold below was chosen in
`shape.py placebo`, which reads only the two long daily files (`queens_gambit_attention.json`,
`tiger_king_attention.json`, 15 series, Dec 1, 2019 to Jun 30, 2023) and uses only windows that end at least 30 days
before that file's stone or whose baseline starts more than 365 days after it. No real stone's window entered any
choice.

Disclosed: while inventorying the files the author printed the structure of each source, which showed some stored
onset dates and lags (for example the discovered leads' `lag` field and the checker's `ref` and `onset` per measured
step) and one raw weekly series (Running Up That Hill). A structure-only run (`shape.py count`) counted the records
each loader yields (848 records, 48 duplicates). No shape, no gate statistic, no lag quantile and no strength was
computed on any real series. The family table below assigns link types from each step's claim text, not its lag.

## Data: every stored response series

| Source | Series | Aligned at | Baseline / post weeks |
|---|---|---|---|
| `docs/results/editor_trail_v1.json` candidates | 487 weekly | the stone | 12 / 21 |
| `docs/results/editor_trail_hop2.json` candidates | 153 weekly | the first-hop lead's onset | 12 / 21 |
| `demo/discovered.json` links (shown as measured) | 18 weekly | the stone | 12 / 21 |
| `maps/out/*.json` steps | 28 weekly (11 catalysts) | the stone, or step 1 for the three map steps with a parent | about 10 / 30 |
| `docs/results/chain_check_v1.json` wiki steps | 32 weekly | the step before (`ref`) | 12 / 8 to 90 |
| `docs/results/chain_check_v1.json` attention checks | 73 weekly | the step's own date | 12 / 10 |
| `docs/results/owner_chains_v1.json` | 17 weekly, uneven windows | the step before | varies |
| the two long daily files | 15 daily, rebinned to weeks at the stone | the stone | 12 (plus more) / 30 |
| chain official series (FRED, SSA, files) and map library checkouts | monthly or annual | listed with lag only | not classified |

Monthly and annual series are not classified: the rules are calibrated on weekly attention and these series have too
few points around the step. They still enter the lag families.

Duplicates (same stone, same first article, same parent date) keep one record, in this order: checked chain, map,
discovered lead, attention check, owner chain, engine candidate, second hop, long file. Summary counts use unique
records; every record stays in the output with `duplicate_of`.

## The weekly reduction

- Week 0 is the stored weekly bin that starts at, or contains, the parent date. Weeks are totals of daily views.
- `x = log10(weekly + 70)` (a floor of 10 views a day, so a near-empty article does not read as a huge lift).
- Baseline: weeks -12 to -3 (the two weeks before the parent are left out for trailers and anticipation); at least 6
  baseline weeks are required. `m` = median of `x` over the baseline; `pmax` = its highest week; the baseline level in
  views is `10^m - 70`; excess in any week = weekly views minus the baseline level.
- Post window: weeks 0 to W-1, W = 21 (147 days) for the headline class, 13 (91 days) for the truncation test, and the
  full stored window where it is longer than 21. At least 8 post weeks are required.

## The response gate (chosen on placebo dates)

Three statistics were compared at exactly 5% false positives on 1,122 unplanted decoy windows (15 series at 7-day
spacing): z (log lift over the baseline median in units of the baseline's robust spread, floor 0.05 or 0.08), plain
log lift, and **exceed** (log10 of the peak week over the highest baseline week). Each was scored by its power on the
same windows with one planted shape each (peak daily excess drawn log-uniform from 1 to 100 times the daily
baseline):

| Statistic | Threshold at 5% | Mean power | Immediate | Delayed | Ramp | Step | Pulse | Waves |
|---|---|---|---|---|---|---|---|---|
| **exceed** | **0.7053** | **.511** | .419 | .471 | .608 | .580 | .536 | .455 |
| z, floor 0.05 | 12.71 | .493 | .408 | .457 | .570 | .567 | .507 | .446 |
| log lift | 0.9254 | .474 | .373 | .436 | .579 | .533 | .509 | .415 |
| z, floor 0.08 | 10.88 | .426 | .342 | .398 | .508 | .473 | .453 | .383 |

Registered gate: a series responded in the window when the peak week is at least 10^0.7053 = 5.07 times its highest
baseline week **and** the peak week adds at least 140 views (20 a day, the checker's "median + 20") over the baseline
level. For the 13-week truncation window the threshold is 0.6188 (5% on the same decoys).

The decoys are bursty (random dates in these topic articles often show two to four times their baseline within 21
weeks), so this gate is strict. It is a pooled gate; the checker's own per-article placebo test is the better test
where it exists. The response decision is therefore:

- a series the checker already graded as a response (chain verdict measured, timed, or moved in the wrong order;
  attention check "attention rose", "article created then" or "rose, no placebo history"; map evidence tested or timed;
  an engine candidate or lead with p at or below .05) is classified even below the pooled gate, and the record says
  `gate_bypassed: true`;
- a series the checker found flat, or never tested, is classified only if it passes the pooled gate;
- the pooled gate's result is reported for every series.

## The shape rules (in this order; thresholds chosen on planted placebo windows)

Measurements, all inside the post window: peak week `kp` (the highest week); peak excess `Ep`; **onset**: the first
week of the run that carries the peak, every week in the run at 10% of `Ep` or more, allowed back to week -2;
**half-life**: weeks from the peak until the excess first falls to half of `Ep`, interpolated on a log scale between
the two bracketing weeks, reported in days; **fade**: weeks until the excess first falls to 20% of `Ep`; **late
fraction**: median excess over the last four weeks divided by `Ep`; **late lift**: the late window's median level over
the baseline median; **waves**: a wave starts when the excess reaches 40% of `Ep`, ends when it falls below 30% of `Ep`,
and a later return to 40% is a new wave; **max jump**: the largest one-week rise up to the peak, as a share of `Ep`.

1. **Multiple waves**: two or more waves.
2. **Gradual ramp (months)**: the peak is in week 8 or later, no single week adds more than half of `Ep`, and the
   first three post weeks stay at or below half of `Ep`.
3. **Step change**: late fraction at least 0.4 and late lift at least 1.5 (a new baseline that persists).
4. **Late spike**: onset after week 8 (more than about two months).
5. **Delayed spike (2 to 8 weeks)**: onset in weeks 2 to 8.
6. **Immediate spike (days)**: half-life at most 10 days.
7. **Pulse and decay**: everything else (a jump that decays over weeks).

A secondary flag, **raised floor**, marks a series that is not a step change but whose late level is still at least
1.5 times the baseline and at least 15% of the peak excess ("a spike that faded but left a higher floor").

The grid searched: onset fraction 0.1/0.2/0.3; spike half-life 7/10 days; step late fraction 0.4/0.5/0.6; ramp peak
week 6/8; ramp max jump 0.35/0.5; wave trough 0.3/0.5; wave start 0.4/0.6 (288 combinations). The objective was the
balanced accuracy over the six planted shapes, among planted windows the gate detects. Planted profiles (daily, start
day t0): immediate spike, t0 0 to 3, half-life 1 to 4 days; pulse and decay, t0 0 to 6, half-life 14 to 42 days;
delayed spike, t0 14 to 56, half-life 1 to 14 days; gradual ramp, t0 0 to 14, linear rise over 56 to 140 days then
flat; step change, t0 0 to 6, a persistent level with an initial overshoot of 0 to 60% that halves in a week; multiple
waves, two spikes 28 to 98 days apart, the second 0.6 to 1.2 times the first, half-lives 2 to 10 days. Seed 20261004.

Placebo result of the chosen rules: balanced accuracy **91.6%** (immediate 87.7%, delayed 91.9%, ramp 92.8%, step
94.8%, pulse 90.0%, waves 92.4%); the top ten combinations all score 91.2% to 91.6%. On unplanted windows the rules say
"no response" on 1,065 of 1,122 (94.9%); the rest are 28 late spikes, 21 delayed spikes, 5 immediate spikes, 2 step
changes and 1 multiple waves. Planted truncation stability (class at 13 weeks equal to the class at 21 weeks, where both
detect): **95.5%** of 3,352 pairs; the main flip is a spike at 13 weeks that becomes multiple waves at 21 when the
second wave lands after week 13.

## Lag families and priors

A **confirmed step** is one of: a checked chain step graded measured or timed (23); a map attention step with evidence
tested or timed (16); a discovered lead shown as measured (18); an attention check whose verdict is "attention rose"
with its onset no more than 3 days before the step's date (the checker's ordering tolerance). Its **lag** is the
response's onset as the checker dated it (daily resolution) minus the parent's date: the step before for a chain step,
the stone or the parent step for a map step, the stone for a discovered lead, the step's own date for an attention
check. Duplicates (same stone, first article and parent date) count once, in the source order above.

Families (assigned from the claim; every discovered lead is media -> search, sub-tagged "spillover"; map and chain
steps in media -> search are sub-tagged "subject"):

| Family | Units |
|---|---|
| media -> search | `chain:tiger-king:2`, `chain:chernobyl-zone:2`, `chain:mr-bates-horizon:2`, `chain:mr-bates-horizon:9`, `chain:ocean-attenborough:2`, `chain:queens-gambit-2:2`, `chain:squid-game-ripples:12`, `map:barbie:1`, `map:chernobyl:1`, `map:oppenheimer:1`, `map:queens-gambit:1`, `map:shogun:1`, `map:squid-game:1`, `map:squid-game:2`, `map:stranger-things-4:1`, `map:stranger-things-4:2`, `map:the-last-of-us:1`, `map:tiger-king:1`, `map:wordle:1`, and the 18 discovered leads |
| search -> search (second hop) | `map:chernobyl:2`, `map:queens-gambit:2`, `map:tiger-king:2` |
| news -> search | `chain:daily-show-zadroga:5`, `chain:america-and-alcohol:25`, `chain:jwst:2`, `chain:gamestop:1`, `chain:toilet-paper:2`, `map:jwst-first-images:1`, `attn:haber-nitrogen:7`, `attn:america-and-alcohol:21`, `attn:three-mile-island-nrc:10`, `attn:serial:4`, `attn:squid-game-ripples:5`, `attn:gdpr:1` |
| launch -> adoption | `chain:pokemon-go:1`, `chain:wordle:2`, `chain:chatgpt:1`, `chain:airpods:2`, `chain:tiktok:1` |
| event -> new term (a new article) | `chain:barbie:4`, `chain:covid-remote:2` |
| culture -> naming | `chain:frozen:2` |
| shock -> prices and purchases | `chain:thailand-floods:4`, `chain:cash-for-clunkers:4`, `chain:toilet-paper:1` |

Search -> purchase and attention -> legislation have no measured or timed step in the repository: every law in the
catalog is a reported link. Their lags are listed separately as **reported stone-to-mark lags** (chain steps with a
`mark` and the verdict reported, days from the stone), labeled context, never a prior.

**Prior window rule**: with five or more lags, the 10th to 90th percentile of the family's lags; with three or four,
their minimum to maximum; with fewer than three, the pooled window (all confirmed lags, 10th to 90th percentile).

## Held-out test of the lag priors

- Units: confirmed steps with a weekly series, at least 6 baseline weeks and at least 13 post weeks.
- For each unit, the prior is rebuilt **leaving out every confirmed step from the same stone**.
- A window of days [a, b] tests weeks floor(a/7) to floor(b/7) + 1 (the checker's extra seven days for the peak),
  clipped to weeks -1 to 20 and to the unit's stored weeks. The fixed windows are days 0 to 6, 0 to 29 and 0 to 89.
- Detection in a window: the exceed statistic over the window's weeks is at or above that window's threshold, and the
  peak week in the window adds at least 140 views. Each window's threshold is the 95th (primary) or 99th (secondary)
  percentile of the same statistic over the same weeks on the 1,122 unplanted decoy windows (`window_tau` in the
  calibration file). Every method is therefore held at the same false-positive rate on decoy dates.
- Paired comparison of the prior against the best of the three fixed windows: exact two-sided McNemar p.

## Catalyst vs outcome strength

- **Catalyst**: the stone's own attention, aligned at the stone (the long daily file for Tiger King and The Queen's
  Gambit; the map's event series for Chernobyl, Squid Game, Stranger Things 4, The Last of Us, Shogun, Barbie,
  Oppenheimer, Webb's first images and Wordle; the chain's first-step series for Mr Bates, My Octopus Teacher, Ocean,
  Adolescence, SVB, Ever Given, GDPR, Pokemon Go, GameStop, ChatGPT and TikTok). **Catalyst strength**: the peak of
  weeks -2 to 3 over the baseline median (lift, "times normal") and the exceed statistic over the same weeks with its
  percentile among the decoy windows (how unusual the initial shock was against its own history). Classes by lift:
  weak under 10 times, moderate 10 to 100, strong 100 or more.
- **Outcomes**: every other unique weekly series of the same stone, aligned at its own parent, except the stone's own
  article(s). **Outcome strength**: the peak of weeks 0 to 20 over its baseline median (lift) and the exceed statistic.
  An outcome **responded** if it passes the pooled gate or the checker graded it a response; it is **flat** if neither.
- **Flags**: *outsized response* (a weak catalyst with a strong outcome): the outcome responded and either its lift is
  at least the catalyst's lift, or the catalyst is weak and the outcome's lift is at least 10. *No echo* (a strong
  catalyst with a flat outcome): the catalyst is strong and the outcome is flat. A baseline under 10 views a day is
  flagged `low_baseline`, since a lift from near zero says more about the floor than the response. Elasticity (log
  outcome lift over log catalyst lift) is reported for reading, not flagged.

## What counts as useful (the registered bar)

1. **Shapes are stable**: among unique series with at least 21 post weeks that are classified at both 13 and 21 weeks,
   at least **80%** keep the same class (planted reference 95.5%).
2. **Lag priors beat fixed windows**: on the held-out confirmed steps, the family priors' hit rate is **strictly
   higher** than the best of the 7, 30 and 90-day windows, every method at 5% false positives on the decoy dates. The
   1% level and the McNemar p are reported alongside; a tie is a failure.

Both are reported plainly, pass or fail. The catalyst vs outcome flags have no bar; they are a list for a person.

## Limits stated in advance

- The decoy pool is 15 series from two stones' topics (chess; big cats and the Tiger King cast), and consecutive
  decoy windows overlap, so the effective number of independent decoys is far smaller than 1,122. Later news in those
  articles (Tiger King 2 in Nov 2021, the Big Cat Act in Dec 2022, the 2022 chess news) sits inside the decoy windows
  and makes the gate stricter.
- Confirmed steps were found by the checker's own windows (45 to 150 days) and are strong by selection, so every
  window may detect most of them; the held-out test can tie.
- Weekly bins blur anything shorter than a week; "immediate spike (days)" means the excess halves within 10 days.
- Families are small outside media -> search; a family with fewer than three lags borrows the pooled window.

Deviations, if any, will be listed in `shape_v1.md` with the reason.
