# Evidence ladder v1: results (Oct 4, 2026)

Registered in `ripples/docs/ladder_plan_v1.md` at commit `cd10fdf`, before any outcome value was fetched. Code:
`ripples/lab/ladder.py`. Data: `ripples/docs/results/ladder_v1.json`. Deviations are in the plan's Addendum 1.

## The answer

| | Marks |
|---|---|
| Engine marks | 102 |
| A series measures the mark's own outcome | 5 |
| Run today | 2 |
| Moved up | 1 (Bake Off → baking sales: **measured**, and fragile) |
| Timed | 0 |
| Busted | 0 |
| Stayed reported, recorded as negative space | 1 (Frozen → Norway tours) |
| Registered, not run (host refused the first request) | 3 (Finding Nemo; Blue Planet II, two marks) |
| No testable series | 97 |

Most of the engine's marks cannot climb this ladder. 87 of the 102 are dated records (laws, rulings, treaties,
institutions, bans, a product launch): the record dates the mark, and there is no series to test. Of the other 15
(behavior, industry, health, education), 5 have a reachable series that measures the mark's own outcome. The other 10 have no public series,
state a share or a level instead of a change, fall in an excluded period, or need the owner to accept a data-use
agreement first.

## Bake Off → "UK shops report sharp rises in sales of baking ingredients" (2011): measured, fragile

**What was measured:** flour bought by UK households in 2011 against 2010, compared with every year-on-year change from
1975 to 2007 (Defra Family Food, grams per person per week).

| | 2010 | 2011 | 2012 | 2013 |
|---|---|---|---|---|
| Flour, g per person per week | 57.7 | 71.3 | 73.0 | 57.3 |

- Change 2010 to 2011: **+23.5%**. No year-on-year change from 1975 to 2007 was as large; the biggest were +20.1%
  (1996) and +20.4% (2000). p = .031 on 31 placebo years, the smallest p this pool allows.
- Onset 2011, after the first series (Aug 2010): in order. Grade by the registered map: **measured**.
- The rise lasted two years and was gone by 2013.

Three registered checks say this measured result is weak:

- **Decoys.** The same test on the same series, run at 19 wrong-stone dates, grades 3 of them measured: the 1996 jump
  (Oklahoma City bombing), the 2000 jump (Columbine) and the 2017-18 jump (Pulse, Pokémon Go). That is a 16% false
  rate where the design expects 5%. The flour series has one-year swings of 20% to 36% that often reverse the next year, and
  Defra rates the latest flour estimate's relative standard error as High (10% to 20%).
- **Comparison rung.** Against ten TV series from the culture list, the Bake Off's change ranks 4th of 11
  (p_comparison = .36). The three series from 2016 (The Crown, Stranger Things, Fleabag) share a window that holds the
  2017-18 jump of +35.6%.
- **Late check, not graded.** A placebo pool that also includes years after the stone (chain_check's own convention)
  gives p = .054. The 2017-18 rise is larger than 2011's.

**Reading.** The registered test says measured, and that is the result. The decoys say this series cannot separate a
real one-year rise from survey noise at the rate the grade implies. Recommendation: hold it at reported on the page
until a second series confirms it (a retail panel or an ONS sales index for flour). If it is shown as measured, it
should carry the decoy line.

## Frozen → "Tour operators add Norway tours to meet demand" (2014): stays reported, negative space

**What was measured:** foreign guests' hotel nights in Norway in the 12 months from Frozen's release, against every
earlier 12-month change since 1986 (Statistics Norway table 08402).

| | Nov 2012 to Oct 2013 | Nov 2013 to Oct 2014 | Change |
|---|---|---|---|
| Foreign hotel nights, all of Norway | 5,038,034 | 5,363,149 | +5.6% |
| Foreign nights, fjord counties (Hordaland, Sogn og Fjordane, Møre og Romsdal) | 1,113,478 | 1,235,725 | +11.0% |
| Foreign nights, rest of Norway | 3,924,556 | 4,127,424 | +5.2% |

- p = .21 on 277 placebo windows. No departure from trend began in the window. Grade: stays **reported**.
- Every rung points the same way, and none is unusual. The change is the largest of the seven films compared: the six
  controls ranged from +0.6% (Finding Nemo) to +5.3% (Mean Girls, The Devil Wears Prada). p_comparison = .14, the
  floor with six controls.
- The fjord counties gained 10.1% relative to the rest of Norway (p = .12). All hotel nights, Norwegians included,
  rose 2.2% (p = .63).
- The large rise came later: 5.43 million foreign nights in 2014, 6.03 million in 2015, 6.63 million in 2016. The krone
  fell from about 6.0 to 8.7 per dollar between Sep 2014 and Dec 2015 (FRED EXNOUS).
- Decoys: 0 of 27 wrong-stone windows moved. The test is well calibrated on this series, so the null is informative.

**Finding.** Foreign visits to Norway rose in Frozen's year, more in the fjord counties and more than after other
films. The rise stayed within the range of ordinary years. The record's tours may be real. The series shows no unusual
rise at the time, and the real boom came a year later with a cheap krone.

## Not run today

- **Finding Nemo → demand for reef fish (2003).** UN Comtrade's public preview returned HTTP 400 to the first data
  request. The host was stopped for the day with no retry. Even when it runs, this design cannot reach measured: US
  annual trade data begin in 1991, which leaves 9 placebo years and a floor of p = .1. Timed is the most it can show.
- **Blue Planet II → marine biology applications (2018).** The first request to UCAS returned 404 (a guessed page
  address). Under the stop rule, no further UCAS request was made today.
- **Blue Planet II → the plastics turn (2020).** The Hansard API returned 500 to a coverage probe. No retry today.

All three designs are registered and will run on a later day, each after a short addendum that names the exact
request and changes nothing in the design.

## Decoys

| Series | Decoy windows (stones) | Measured | Timed | Busted |
|---|---|---|---|---|
| Norway, foreign hotel nights | 27 (29) | 0 | 0 | 0 |
| UK household flour | 19 (36) | 3 | 1 | 0 |

Synthetic noise gives this design 2% to 6% measured. Norway sits at the low end. Flour is far above it, and that is
the main reason the Bake Off result is called fragile.

## Negative space

One entry: Frozen's foreign hotel nights. The record says demand rose in 2014. The series rose 5.6%, which is ordinary
for that series, while the broader all-guests series rose 2.2%. The list is in `ladder_v1.json` under `negative_space`.

## Limits

- **Coverage.** 2 of 102 marks were tested. The ladder cannot move laws or institutions; their grade is the record's.
- **Power.** Annual series with short histories cannot reach p ≤ .05 (Finding Nemo: floor .1). The design reports the
  floor beside every p.
- **Noise.** One survey series (flour) produced false measured results at three times the expected rate. A measured
  grade from one noisy annual series needs a second source.
- **Pool choice.** The registered pool uses only years before the stone. A trending or newly noisy series can look
  calm before the stone and swing after it. The late both-sides check exists to show that.
- **Ordering at annual resolution.** For the Bake Off, 2009 is excluded (the 2008-09 crisis), so the ordering check
  effectively starts in 2010.
- **Comparison rung.** On one national series, matched control stones are placebo dates chosen by comparable releases.
  Controls released in the same year share one window, and six to ten controls give a floor of .09 to .14.
- **Contribution, not cause.** A measured grade means an unusual rise in the right order. It does not rule out another
  cause in the same year. Norway's later boom coincides with the krone's fall.
- **No product change.** `ladder_v1.json` proposes grades. `discovered_wiki.json` and the demo page are unchanged.

## What the product would read

`ripples/docs/results/ladder_v1.json`, `marks[slug][id]` for all 102 marks: `testable`, `category`, `reason`,
`current_grade`, `proposed_grade`. Tested marks also carry `what_was_measured`, `p`, `p_floor`, `n_placebo`, `onset`,
`effect_pct`, `window`, `raw` (the counts), `comparison`, `decoy_calibration`, `late_check_both_sides`, `source_url`,
plus `gradient` and `broader` for Frozen. Top level: `negative_space`, `decoys`, `stopped_hosts`, `summary`.

## Next

1. Run Finding Nemo with one Comtrade request per year (addendum first).
2. Find the UCAS detailed-subject table that holds marine biology; retry Hansard on another day.
3. The most testable marks are the ones the culture shelf left out because the record left them undated: the baby
   names (Peaky Blinders → Arthur and Ada) against the SSA and ONS name files. A dated series is exactly what those
   marks lack.
4. 13 Reasons Why needs the owner to accept CDC WONDER's data-use terms before its series can be read.
