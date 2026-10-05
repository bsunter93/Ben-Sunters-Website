# Shape v1: results

Run Oct 4, 2026 under `docs/shape_plan_v1.md`, registered and pushed in commit `03eb5aa` before any real stone was
read. Final run on code `187859f` (the registered code plus the disclosed deviations below). Data:
`docs/results/shape_v1.json` (every series), `docs/results/lag_priors_v1.json` (families, held-out test),
`docs/results/shape_placebo_v1.json` (the calibration). Reproduce from the repository root with no network:
`python3 ripples/lab/discovery/shape.py placebo` then `python3 ripples/lab/discovery/shape.py real`.

## Against the registered bar

| Bar | Result | Verdict |
|---|---|---|
| Shape classes stable under truncation: at least 80% of series keep their class from 13 to 21 weeks | **86.9%** (338 of 389; planted placebo reference 95.5%) | **Passed** |
| Lag priors beat fixed windows: held-out hit rate strictly above the best of 7, 30 and 90 days at 5% false positives on decoy dates | priors **84.1%**, 30 days **84.1%**, 7 days 79.5%, 90 days 77.3% (44 steps; McNemar p = 1.0) | **Failed (a tie)** |
| Secondary: the same at 1% false positives | priors 63.6%, 30 and 90 days 68.2%, 7 days 65.9% | priors lose by 2 steps |

The shape classifier is stable enough to use. The lag priors, as built from this repository's confirmed steps, add
nothing over a plain 30-day window: almost every confirmed step responds within days, so any window that starts at
day 0 catches it. That is a finding about the catalog as much as about the method (see "Why the priors tied").

## Deviations (disclosed; none changed a threshold, rule or bar)

1. **Map series were weekly means, not totals.** `lab/map_builder.py` stores each week as the mean daily views; every
   other source stores weekly totals. Found when the map's timed "chess sets" step read as no response (its peak week
   added fewer than 140 views because the values were a seventh of the totals). The loader now multiplies map weeks by
   7. Before the fix: truncation 87.1% (338 of 388), held-out 81.8% for both the priors and 30 days at 5%; both
   verdicts were the same.
2. **A catalyst that did not exist yet.** Ocean with David Attenborough's article was created on Jul 22, 2025, 75 days
   after the release, so its catalyst series is zero from week -12 to week 3 and read as a "weak" catalyst; the first
   run flagged its two bottom-trawling outcomes as outsized on that basis. A stone whose own article has no views
   anywhere in weeks -12 to 3 is now "not measurable" and its flags are withheld.
3. **Wording only.** The plain-words line says "from almost nothing" when a baseline is under 10 views a day, and
   rounds multipliers (the first run printed "26113.5 times its old level" for ChatGPT, whose article did not exist).
4. A checker-graded series too small to classify (peak week under 20 views a day) now carries a `why` note.

## What was classified

848 stored series, 800 after duplicates. 454 have a shape, 316 show no response, 30 are not classified (26 monthly or
annual official series and library checkouts, which the weekly rules are not calibrated for, and 4 owner-chain windows
too short). The response decision follows the plan: 183 of the 454 were graded a response by the checker but fall
under the pooled gate (`gate_bypassed`). Where both exist, the checker and the pooled gate agree on 491 of 708 series;
the pooled gate is stricter (188 checker yeses it rejects, 29 checker nos it accepts), because the decoy articles are
bursty.

### The shape mix (454 unique classified series, 21-week window)

| Shape | Series | Share | Plain words |
|---|---|---|---|
| Pulse and decay | 163 | 36% | "a jump that faded over 9 weeks" |
| Immediate spike (days) | 106 | 23% | "a spike that was mostly gone within 2 weeks" |
| Multiple waves | 66 | 15% | "came in 2 waves" |
| Delayed spike (2 to 8 weeks) | 56 | 12% | "a spike that arrived 5 weeks later" |
| Late spike (after 8 weeks) | 36 | 8% | "a spike 12 weeks later; that far out it may belong to another story" |
| Gradual ramp (months) | 15 | 3% | "a slow climb that peaked after about 4 months" |
| Step change (a new normal) | 12 | 3% | "a new normal: about 2.6 times the old level, still there 13 weeks on" |

50 more carry the **raised floor** flag: the spike faded but the late level stayed at least 1.5 times the old one and
at least 15% of the peak (Murder on the Dancefloor after Saltburn: "a spike that arrived 5 weeks later, then settled at
about 15 times its old level"). Running Up That Hill does not qualify: it ends 8 times its old level, but that is 7%
of its peak.

What the mix says:

- **Attention is mostly transient.** The median half-life over 325 spikes and pulses is 10.7 days (product cards 12.6,
  engine candidates 11.2, attention checks on dated records 3.7). A true new normal is rare: 12 of 454.
- **Link types have shapes.** Of the confirmed steps, news -> search is almost all immediate spikes (9 of 11);
  media -> search spreads over pulses (14), immediate spikes (7), delayed spikes (6), waves (5) and one step;
  launch -> adoption is a ramp (ChatGPT, TikTok, AirPods and Wordle ramp; Pokemon Go is the one spike). A launch that
  "spiked" would be the surprise.
- **Stones have shapes too.** Shows decay over 3 to 12 weeks (The Queen's Gambit 12, The Last of Us 11, Chernobyl and
  Squid Game 5); news events, Pokemon Go and Tiger King are spikes gone within 1 to 3 weeks; Stranger Things 4 came in two waves
  (its two volumes); My Octopus Teacher is the one stone with a new normal.
- **Pre-date buildup.** 109 outcomes have a weekly onset in week -1 or -2: they were already at 10% of their peak
  excess before the date. 100 of them the checker graded as responses on its own daily onset, which needs five days over a
  higher threshold, so this is mostly buildup (trailers, premieres before the official date), not a broken ordering rule. The
  ordering rule should keep using the checker's daily date; the weekly flag is for the narration ("it began rising
  before the date").

### Truncation, class by class

| Class at 13 weeks | Kept at 21 weeks |
|---|---|
| Gradual ramp | 10 of 10 |
| Pulse and decay | 147 of 153 |
| Immediate spike | 76 of 81 |
| Multiple waves | 39 of 45 |
| Delayed spike | 48 of 56 |
| Late spike | 14 of 17 |
| **Step change** | **4 of 27** |

Every class but one is stable. "Step change" at 13 weeks is usually a slow pulse that has not finished decaying (9
became pulse and decay, 5 delayed spike, 4 late spike). **The product should not call a new normal before 21 weeks.**
22 responses appeared only after week 13 and 15 classified at 13 weeks were gone by 21.

## Lag families

Lag = the response's onset (the checker's daily date) minus the parent's date; 58 unique confirmed steps.

| Family | n | Median | Middle half | Prior window (registered rule) |
|---|---|---|---|---|
| media -> search | 33 | 3 days | 2 to 9 | 1 to 20 days (10th to 90th percentile) |
| subject of the work (catalog and map steps) | 16 | 2 days | | 10th to 90th: -0.5 to 14 days |
| spillover (engine leads: songs, places, backlists) | 17 | 4 days | | 10th to 90th: 2 to 28 days |
| news -> search | 11 | 0 days | 0 to 1.5 | 0 to 2 days |
| launch -> adoption | 5 | 5 days | 3 to 23 | 2 to 76 days |
| search -> search (second hop) | 3 | 6 days | | 3 to 15 days (min to max) |
| shock -> prices and purchases (monthly) | 3 | 0 days | | -10 to 15 days (monthly points) |
| event -> new term (a new article) | 2 | 19 and 394 days | | none; borrows the pooled window |
| culture -> naming (SSA) | 1 | 35 days (annual data) | | none; borrows the pooled window |
| pooled | 58 | 3 days | 1 to 14 | 0 to 23 days |

Search -> purchase and attention -> legislation have no measured or timed step in the repository. As context only (a
citation is reported, never measured), the chains' reported lags from a stone to its lasting mark: **laws** 41 steps,
median 598 days (middle half 285 to 3,534); **institutions** 13, median 1,857; **regulations** 11, median 1,863;
**policies** 4, median 95 days. A ripple to a law takes years; no 90-day window will ever see one.

### Why the priors tied

- 44 confirmed steps had the 13 post weeks the test needs. 30 of them respond within 10 days of their parent, so the 7,
  30 and 90-day windows and the priors all start on top of them.
- A narrower window has a lower decoy threshold, which is the priors' only edge: the news -> search window (days 0 to
  2) caught the small astronomy spike after Webb's first image that the 30 and 90-day windows' higher thresholds missed.
- The media -> search prior (about 1 to 20 days) missed Master of Puppets (36 days, the second volume of Stranger
  Things) that the 30-day window's extra week caught. One each way: a tie.
- 77% of held-out lags (34 of 44) fell inside their prior window. Of the 10 outside, 7 came later than the window
  (Zoom towns at 394 days, Wordle at 112, Bloody Mary at 46, Master of Puppets at 36, Voices from Chernobyl at 23,
  the Korean language at 21, the GameStop squeeze at 15 against a 0 to 2-day news window) and 3 earlier (Barbie the doll
  and J. Robert Oppenheimer rose before release; Pokemon Go at 2 days against a 3 to 112-day launch window).
- Where priors should matter (launches, new terms, naming, legislation), the families have 1 to 5 confirmed steps. The
  engine can use the windows above as a starting point, with the 30-day window as the default for media -> search;
  this test does not show that the priors raise the hit rate.

## Catalyst vs outcome

Catalyst strength is the peak of the stone's own attention in weeks -2 to 3 over its baseline. 22 stones have a stored
catalyst; 21 are measurable (Ocean is not). Every measurable catalyst except GDPR (5.2 times, 98th decoy percentile)
is above the 99th percentile of decoy dates. Classes: 13 strong (100 times or more), 7 moderate (Barbie 28, Stranger
Things 4 29, Webb 30, Oppenheimer 31, Shogun 34, The Last of Us 40, Wordle 41), 1 weak (GDPR).

A caveat that shapes every flag: lift is measured against the stone's own pre-period, so a release whose article was
already busy (trailers, a well-known franchise) reads as a moderate catalyst. All the outsized cases below come from
moderate catalysts. Read "outsized" as "the spillover drew more new readers, relative to its own normal, than the
stone's article did."

### Outsized responses worth a human look (a modest catalyst, a stronger outcome)

| Stone (catalyst lift) | Outcome | Outcome lift | Shape | Where it sits |
|---|---|---|---|---|
| Webb's first images (30x) | Carina Nebula | 123x | immediate spike | product: the picture's subject outdrew the telescope |
| Stranger Things 4 (29x) | Running Up That Hill | 106x | pulse and decay | product |
| Stranger Things 4 (29x) | Lukiskes Prison (the Vilnius set) | 33x | multiple waves | product |
| Barbie (28x) | Barbie, the doll | 33x | pulse and decay | product |
| Barbie (28x) | Double feature; July 21 | 40x; 42x | immediate spikes | engine candidates: the Barbenheimer double bill, a spillover larger than the film's own article |
| Shogun (34x) | Hatamoto; Japan-Portugal relations | 85x; 55x | pulse; spike | engine candidates: the real history outdrew the show |
| The Last of Us (40x) | Never Let Me Down Again; Ophiocordyceps | 54x; 44x | spikes | engine candidates: the episode-one song and the real fungus |
| Barbie (28x) | Earring Magic Ken; Bild Lilli doll | 31x; 29x | pulses | engine candidates |
| Stranger Things 4 (29x) | Blush (Maya Hawke album) | 35x | multiple waves | engine candidate |

Flagged but probably not ripples: Beth Harmon, Dark Souls, Northland Village Mall, Closer to Fine and We Were the Lucky
Ones have baselines under 10 views a day (`low_baseline`), and We Were the Lucky Ones and Under the Bridge are other
spring 2024 series that share Shogun's article links, not responses to it.

### No echo worth a human look (a strong catalyst, a flat claimed outcome)

| Stone (catalyst lift) | Claimed outcome, tested at its own date | Outcome lift |
|---|---|---|
| ChatGPT (8,582x) | "Essay cheating crisis in schools" (Turnitin, GPTZero, academic dishonesty) | 1.3x |
| ChatGPT | "Return of blue books and oral exams" | 1.7x |
| My Octopus Teacher (1,351x) | "Attention to octopus intelligence rises" (the checker also found no movement) | 2.5x |
| Tiger King (42,453x) | "Surrendered cats overwhelm sanctuaries"; Big cat attention when the Act passed | 3.4x; 1.2x |
| Squid Game (75,064x) | "Duolingo reports a jump in new Korean learners"; MrBeast's real-life Squid Game | 1.05x; 3.9x |
| Mr Bates vs The Post Office (3,910x) | attention at the Offences Act and at its second reading | 1.25x; 1.0x |
| Adolescence (551x) | attention to "incel" when the sex education guidance named the show | 2.5x |
| Chernobyl (182x) | the zone's record visitor year; Ukraine making the zone an official attraction | 1.2x; 0.9x |

Most of these claims are tested at their own later dates, so "no echo" there means the stone's attention had already
spent itself by that step, not that the stone did nothing. The ChatGPT and octopus rows are the sharp ones: a claimed
attention consequence that never shows in the attention data. Among engine candidates, strong catalysts leave most
backlinks flat (The Queen's Gambit 23 of 50, Squid Game 20 of 53, Tiger King 9 of 28, Chernobyl 3 of 58), which is
expected: a backlink is not a claim. The Queen's Gambit's chess clock, Chess.com and chess set series also read as no
echo under the pooled gate (about 3 to 5 times their baseline) although the checker measured chess itself; that is
the pooled gate's strictness, not a contradiction.

## How the product could show shape

One plain line per ripple, generated from the class and its measurements (`plain` in `shape_v1.json`), for the card's
face or the narration line:

- Running Up That Hill: "a jump that faded over 10 weeks"
- Murder on the Dancefloor after Saltburn: "a spike that arrived 5 weeks later, then settled at about 15 times its old
  level"
- Ddakji after Squid Game: "a spike that was mostly gone within 3 weeks"
- Master of Puppets: "a spike that arrived 5 weeks later"
- Chess after The Queen's Gambit: "a new normal: about 2.6 times the old level, still there 13 weeks on" (13 weeks of
  data: by the truncation result this is the one label to hold back until 21 weeks)
- ChatGPT: "a slow climb that peaked after about 4 months, then settled well above where it started"
- Stranger Things 4's Kate Bush: "came in 2 waves"
- Oppenheimer's J. Robert Oppenheimer: "a spike that was mostly gone within 3 weeks (it began rising before the date)"

Three uses beyond the line:

1. **Shape as a lasting-mark screen.** A step change or a raised floor is a candidate durable change in behavior, the
   kind of ripple the product's payoff rule asks for; a spike is attention. 12 step changes and 50 raised floors out of
   454 are the short list.
2. **Shape as a surprise signal.** A launch that spikes, a show that ramps, or news that echoes in waves breaks its link
   type's usual shape and is worth a look.
3. **Wait before "new normal".** Hold the step-change label until 21 weeks of data; every other label is safe at 13.

## Limits

- The decoy pool is 15 articles from two stones' topics, with overlapping windows; the pooled gate is strict and the
  false-positive rates are estimates from a thin base.
- Confirmed steps are strong by selection (found with 45 to 150-day windows), which favors a tie in the held-out test.
- Weekly bins blur anything under a week; "immediate spike (days)" means the excess halves within 10 days.
- Families outside media -> search and news -> search are too small for a prior to be tested; the reported
  stone-to-mark lags are context, not priors.
- Catalyst lift penalizes anticipated releases; a stone with an existing, busy article reads as moderate.
- Everything here is attention (Wikipedia views standing in for search) except the 26 official series, which are not
  classified.
