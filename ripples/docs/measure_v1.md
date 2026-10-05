# Measure v1: results (Oct 5, 2026)

Registered in `ripples/docs/measure_plan_v1.md` at commit `01b0a09`, before any outcome value was fetched. One late
addendum (`0cc1935`): the NPS parser read JSON and the API answers in XML; the fix changed the parser only, and run 2 read
every response from run 1's cache with no new request. Code: `ripples/lab/ladder2.py` (the test),
`ripples/lab/measure_v1.py`, `ripples/lab/measure_registry.py`. Data: `ripples/docs/results/measure_v1.json`. The
catalog is in `ripples/docs/series_catalog_v1.md`.

*This document reports suicide statistics in aggregate. If you or someone you know is struggling, call or text 988 (the
988 Suicide and Crisis Lifeline, United States).*

## The answer

| Part of the bar | Result | Met |
|---|---|---|
| Recover at least 1 published positive under v2 | 2 of 2: 13 Reasons Why → youth suicide (Bridge et al. 2020; Niederkrotenthaler et al. 2019) and the death of Robin Williams → suicide (Fink et al. 2018), both measured | yes |
| At least 2 new measured marks under v2 | 2 of 25 runnable scan marks: The Civil War (Ken Burns, 1990) → visits to the ten major Civil War battlefield parks; Lewis & Clark (Ken Burns, 1997) → visits to Fort Clatsop | yes |
| Decoy pass rate at or under nominal (5%) | 38 of 1,186 decoy windows graded measured (3.2%); rung (i) alone passed 48 (4.0%) | yes |

The bar is met. The documented positive Hamilton → Hamilton Grange is also measured (it counts toward neither part).
The ladder's two marks drop under v2: the Bake Off from measured to **timed** (it does not beat its controls), and
Frozen → Norway stays **reported** (the change was ordinary).

What v2 adds over the ladder: a mark must also beat the same change after 9 to 19 comparable stones on the same series
(rank p ≤ .10), and where exposure varies, the more exposed group must change more. All five measured marks beat every
one of their controls and point the right way on exposure.

## The ladder's two marks under v2

| Mark | What was measured | Raw | Change, p | Controls | Gradient | v2 grade |
|---|---|---|---|---|---|---|
| The Great British Bake Off → baking sales | UK household flour (Defra Family Food), 2011 against 2010 | 57.7 to 71.3 g per person per week | +23.5%, p = .031 (floor .031, 31 years) | rank 5 of 20 against the 19 nearest TV series (p = .25); the ladder's own 10 controls: rank 4 of 11 (p = .36) | n/a (no exposure measure) | **timed** (was measured in ladder v1) |
| Frozen → Norway tours | Foreign guests' hotel nights in Norway, Dec 2013 to Nov 2014 against the 12 months before | 5,063,450 to 5,387,329 | +5.4%, p = .22 (278 windows) | rank 4 of 20 films (p = .20) | fjord counties +11.3% against the rest of Norway +4.7%: right way | **no movement**: stays reported |

The ladder's Nov 2013 reference gives +5.6%, p = .21; the v2 reference rule (a stone on or after the 25th starts its
window the next month) moved it one month and changed nothing.

## Arm A: CDC WONDER, monthly deaths (the published positives)

Five queries to D76 (Underlying Cause of Death, 1999-2020), national, about 2 minutes apart, each with
`accept_datause_restrictions=true` (the owner accepted CDC WONDER's data use restrictions on Oct 5, 2026). Every count
below is above nine. Source: Centers for Disease Control and Prevention, National Center for Health Statistics. National
Vital Statistics System, Mortality 1999-2020 on CDC WONDER Online Database, released in 2021. Powered by CDC WONDER.

### 13 Reasons Why (Mar 31, 2017) → suicide among 10 to 17 year olds: measured

**What was measured:** suicide deaths among 10 to 17 year olds in April to June 2017 against April to June 2016,
compared with the same three-month year-over-year change at every earlier month from 2000 to 2016.

| | Apr to Jun 2016 | Apr to Jun 2017 | Change |
|---|---|---|---|
| Ages 10 to 17 | 340 | 487 | +44.3% |
| Ages 18 to 29 | | | +11.3% |
| Ages 30 to 64 | | | +5.4% |

- (i) p = .0056 on 177 earlier windows, the floor: no earlier three-month change was as large. A departure from the
  series' own pattern began in June 2017, after the release. In order.
- (ii) Rank 1 of 20 against the 19 nearest teen-audience premieres (p = .05). The largest control change was +22.8%
  (The End of the F***ing World, January 2018).
- (iii) The change falls with age, the show's audience first: Spearman rho = 1.0.
- Yearly totals, ages 10 to 17: 1,528 (2016), 1,773 (2017), 1,825 (2018).
- Secondary, registered, not graded: ages 10 to 19, +34.0%, p = .0056 (605 to 804); April alone, +43.9%, p = .011 (132
  to 190); the ladder's 12-month design, +23.7%, p = .0066 (1,529 to 1,870, April 2016 to March 2017 against April 2017
  to March 2018).

The published estimates are smaller (Bridge et al.: +28.9% above forecast in April 2017; Niederkrotenthaler et al.:
about +13% for ages 10 to 19 over April to June). Part of the gap is the base: April to June 2016 was a low quarter, and
a year-over-year comparison carries that. The finding is disputed (Romer 2020 attributes part of the rise to the
existing trend). A measured grade here says the rise was unusual for this series, larger than after 19 comparable
premieres, and concentrated in the show's audience. It does not settle whether the show caused it.

### The death of Robin Williams (Aug 11, 2014) → suicide, all ages: measured

**What was measured:** suicide deaths, all ages, in August to December 2014 against August to December 2013, compared
with the same five-month year-over-year change at every earlier month from 2000 to 2013.

- 16,815 to 18,701: +11.1%. p = .0071 on 139 windows, the floor. Departure from August 2014. In order.
- (ii) Rank 1 of 20 against the 19 nearest deaths of widely known public figures not by suicide (p = .05). The largest
  control change was +9.4% (Leonard Nimoy, February 2015).
- (iii) The method category reported in coverage of his death (WONDER mechanism group GRINJ-017) rose 29.9%; all other
  categories together rose 4.7%. Right way.
- Secondary: the ladder's 12-month design, +9.6%, p = .0084 (40,864 to 44,832).
- Published: Fink, Santaella-Tenorio and Keyes (2018) estimated 9.85% more suicides than expected in the same months.

"All ages" is the sum of WONDER's published mechanism cells. WONDER withholds national cells of fewer than 10, so the
sum can run a few dozen deaths a year below the official total (2014: 42,750 here).

## Arm B: NPS monthly recreation visits (the scan)

Every unit's monthly series from January 1979: one request per unit code (112 codes, alternatives included) and one
request for the 1977 totals; all 113 answered 200. Window: 12
months from the stone against the 12 before, as twelve year-over-year pairs. Gradient: the featured unit against every
other unit of its group (battlefields, historic sites, national parks).

| Stone | Unit | Raw, 12 months before to after | Change | p (windows) | Controls: rank (p) | Featured vs comparison median | Grade |
|---|---|---|---|---|---|---|---|
| The Civil War, Ken Burns (Sep 23, 1990) | 10 battlefields | 5,307,766 to 6,094,666 | +14.5% | .0095 (104) | 1 of 20 (.05) | +14.5% vs -2.6% | **measured** |
| Son of the Morning Star (Feb 3, 1991) | LIBI | 230,737 to 293,458 | +27.4% | .082 (109) | 4 of 20 (.20) | +27.4% vs +5.6% | timed |
| Gettysburg (Oct 8, 1993) | GETT | 1,355,421 to 1,644,857 | +15.4% | .056 (141) | 1 of 20 (.05) | +15.4% vs +0.9% | no movement |
| Andersonville (Mar 3, 1996) | ANDE | 143,932 to 171,666 | +20.2% | .053 (170) | 1 of 20 (.05) | +20.2% vs -3.2% | timed |
| Lewis & Clark, Ken Burns (Nov 4, 1997) | LEWI | 188,894 to 241,623 | +39.2% | .0052 (190) | 1 of 20 (.05) | +39.2% vs +1.6% | **measured** |
| The Patriot (Jun 28, 2000) | COWP | 199,992 to 219,768 | +8.4% | .39 (222) | 6 of 20 (.30) | +8.4% vs +1.2% | no movement |
| Gods and Generals (Feb 21, 2003) | FRSP | 467,237 to 439,537 | -7.6% | .87 (253) | 19 of 20 | -7.6% vs -5.6% | no movement |
| Cold Mountain (Dec 25, 2003) | PETE | 162,547 to 158,167 | +1.2% | .25 (264) | 10 of 20 | +1.2% vs -1.2% | no movement |
| National Treasure (Nov 19, 2004) | INDE | 3,971,844 to 3,986,606 | +7.2% | .22 (274) | 4 of 20 | +7.2% vs -0.5% | **busted**: the rise began in Feb 2004 |
| Grizzly Man (Aug 12, 2005) | KATM | 56,232 to 59,522 | -1.1% | .65 (252) | 11 of 20 | -1.1% vs +0.5% | no movement |
| Into the Wild (Sep 21, 2007) | DENA | 454,671 to 444,357 | -40.9% | .96 (308) | 20 of 20 | -40.9% vs +0.3% | no movement |
| The War, Ken Burns (Sep 23, 2007) | WWII | 4,110,048 to 4,332,971 | +5.8% | .071 (13) | 8 of 20 | +5.8% vs +1.2% | no movement |
| 127 Hours (Nov 5, 2010) | CANY | 438,161 to 470,123 | +8.9% | .34 (333) | 10 of 20 | +8.9% vs -2.6% | no movement |
| Red Tails (Jan 20, 2012) | TUAI | 16,244 to 23,716 | +43.1% | .17 (53) | 5 of 20 | +43.1% vs +6.0% | no movement |
| Lincoln (Nov 9, 2012) | FOTH | 667,379 to 631,063 | -3.7% | .68 (337) | 10 of 20 | -3.7% vs -3.1% | no movement |
| Lincoln (Nov 9, 2012) | LIHO | 266,486 to 209,818 | -19.1% | .97 (337) | 20 of 20 | -19.1% vs -3.1% | no movement |
| Bears, Disneynature (Apr 18, 2014) | KATM | 28,666 to 30,896 | +6.5% | .44 (321) | 5 of 20 | +6.5% vs +10.0% | no movement |
| The Roosevelts, Ken Burns (Sep 14, 2014) | 5 Roosevelt units | 215,610 to 222,048 | +0.0% | .48 (295) | 8 of 20 | +0.0% vs +2.5% | no movement |
| Hamilton, Broadway (Aug 6, 2015) | HAGR | 22,587 to 70,448 | +225.7% | .0047 (214) | 1 of 12 (.083) | +225.7% vs +7.0% | **measured** (documented positive) |
| The Vietnam War, Ken Burns (Sep 17, 2017) | VIVE | 5,127,352 to 4,849,484 | -6.3% | .62 (343) | 17 of 20 | -6.3% vs -8.1% | no movement |
| Yellowstone (Jun 20, 2018) | YELL | 4,086,390 to 4,064,676 | +6.9% | .25 (404) | 2 of 20 (.10) | +6.9% vs -1.8% | no movement |
| Free Solo (Sep 28, 2018) | YOSE | 3,639,949 to 4,054,020 | +5.2% | .32 (408) | 8 of 20 | +5.2% vs -0.9% | timed |

Not graded: Jazz (New Orleans Jazz NHP's series begins in July 2000, too late for a placebo window before January
2001); Pearl Harbor (no series under VALR or USAR); Selma (no series for the trail); United 93 (the Flight 93 series
begins in January 2007, after the film); the
five registered for the record (National Treasure: Book of Secrets, John Adams, Twilight, The National Parks, Harriet:
each window touches the 2008-09 crisis or the pandemic months). Close Encounters → Devils Tower did not run: the API's
1977 totals came back empty, so the annual design had no data.

### The Civil War (Ken Burns, Sep 1990) → battlefield visits: measured

**What was measured:** recreation visits to the ten major Civil War battlefield parks (Gettysburg, Antietam, Manassas,
Vicksburg, Shiloh, Fredericksburg and Spotsylvania, Chickamauga and Chattanooga, Petersburg, Richmond, Stones River),
summed, September 1990 to August 1991 against the 12 months before, compared with every earlier 12-month change from
1980.

- 5,307,766 to 6,094,666: +14.5%. p = .0095 on 104 windows, the floor. No departure began before the series aired.
- Every one of the ten rose (Petersburg +1.3% to Antietam +39.3%); Antietam, Manassas and Richmond each pass alone.
- Rank 1 of 20 against the 19 nearest documentaries (largest +7.5%, Jazz, 2001).
- The ten rose more than the median of the 17 other battlefield units (-2.6%). Six of those 17 rose more than the ten:
  four Revolutionary War battlefields in the Carolinas (Cowpens, Guilford Courthouse, Moores Creek, Kings Mountain),
  Little Bighorn, and Andersonville. Our reading, not tested: the Carolina windows open the week Hurricane Hugo struck
  (Sep 22, 1989), Little Bighorn had Son of the Morning Star (Feb 1991), and Andersonville is a Civil War site the series
  covered.
- Yearly totals: 5,405,687 (1989), 5,404,231 (1990), 6,316,056 (1991), 6,213,295 (1992), 5,678,403 (1993). The rise held
  two years.
- Late check, not graded: without Manassas the family's p rises to .057. The result leans on one unit.

New here means new to Ripple's record. Popular accounts of the series mention rising battlefield visits; it was not
registered as a known positive and no published estimate was used.

### Lewis & Clark (Ken Burns, Nov 1997) → visits to Fort Clatsop: measured

**What was measured:** recreation visits to Lewis and Clark National Historical Park (Fort Clatsop, the expedition's
winter camp), November 1997 to October 1998 against the 12 months before, compared with every earlier 12-month change
from 1980.

- 188,894 to 241,623 (+27.9% in raw visits; +39.2% as the mean of the monthly year-over-year changes, which weights the
  small winter months equally). p = .0052 on 190 windows, the floor. The departure began in November 1997, the month the
  series aired: 5,478 visits in November 1996, 11,764 in November 1997.
- Rank 1 of 20 against the 19 nearest documentaries (largest +21.3%, Roger & Me).
- Above the median of 32 historic units (+1.6%); four rose more (two National Mall memorials, Eleanor Roosevelt, Adams).
- Yearly totals: 176,898 (1996), 199,822 (1997), 234,227 (1998), 211,494 (1999). Part of the rise faded in a year.
- No decoy window on this series graded measured (0 of 58). Undaunted Courage (Ambrose, 1996) raised interest in the
  expedition a year earlier; summer 1997 visits were flat against summer 1996, so the rise starts with the series.

### Hamilton (Broadway, Aug 2015) → visits to Hamilton Grange: measured (documented positive)

22,587 to 70,448 (+225.7%), p = .0047 (214 windows, the floor); departure from October 2015; rank 1 of 12 against the 11
eligible Broadway openings (p = .083); first of 35 historic units. Yearly: 20,943 (2014), 35,446 (2015), 85,348 (2016),
85,603 (2017), 70,752 (2019). The house was closed for long stretches (no complete year from 1993 to 1997 or from 2006
to 2011; it was moved in 2008), so its placebo pool comes mostly from the 1980s, 1998-2005 and 2012-2015.

### Near misses and failures, plainly

- **Gettysburg (1993):** +15.4%, rank 1 of 20, above its comparison units, and p = .056. Graded no movement because no
  departure was detected in the window and p missed .05.
- **Andersonville (1996):** +20.2%, p = .053, rank 1 of 20: timed.
- **National Treasure (2004):** busted. Independence Hall's visits began rising in February 2004, nine months before the
  film; the Liberty Bell Center (Oct 2003) and the National Constitution Center (Jul 2003) had just opened (our reading).
- **Strongly seasonal parks** (Denali, Katmai, Yellowstone): the mean of monthly log changes weights each calendar month
  equally, so the near-empty winter months dominate. Into the Wild shows -40.9% on that measure while raw visits fell 2.3%.
  None of these is near a measured grade either way.

## Decoys

Each mark's own series at the dates of wrong stones (the engine's other stones and the other scan stones), deduplicated
by window, never touching the real window, graded by the full v2 test.

| | Windows | Measured | Rate | Rung (i) alone |
|---|---|---|---|---|
| Arm A (WONDER) | 82 | 2 | 2.4% | 4 |
| Arm B (NPS) | 1,104 | 36 | 3.3% | 44 |
| All | 1,186 | 38 | **3.2%** | 48 (4.0%) |

The false measured grades cluster where a real event sat in the wrong stone's window (our reading, not tested): 8 at
Civil War units in 2011, the first year of the Civil War sesquicentennial; 4 at the Roosevelt units in 2011-12; 6 at
Cowpens and Tuskegee Airmen in 2007; 3 in December 1984 (Katmai twice, Gettysburg once); 2 at Katmai in August 2010; 2 on
the youth series in the 2013-15 rise; Yosemite after its January 1997 flood. Decoys within a mark overlap, so the 1,186
windows are fewer independent tests than they look.

## Late checks, not graded

Computed after the graded run (`exploratory_late` in the JSON):

- A placebo pool from both sides of the stone (chain_check's convention) leaves every measured mark under p = .006. Only
  the battlefield family has a later window at least as large (May 2011, the sesquicentennial).
- 13 Reasons Why with the reference one month earlier or later: +31.4% (March) and +45.0% (May), both at the floor.
- Battlefield family, leaving out one unit at a time: p stays .0095 for nine units and is .057 without Manassas.

## Limits

- **Two arms, not three.** The state baby-name files were the planned third series; www.ssa.gov refused the project's
  agent today. FARS and NICS, the strongest state series after NPS, refused the catalog probe. No retry today.
- **No state gradient for deaths.** The WONDER API is national only, so the suicide marks use age and method category.
- **Counting methods.** NPS counts are partly estimates and methods change by unit; the decoy clusters show what that
  and real coincident events can do. A measured park mark is a strong timing result on one counting record.
- **Contribution, not cause.** Each measured mark had other things going on: the battlefields had a growing preservation
  movement, Fort Clatsop had a bestselling book, 13 Reasons Why had a rising youth suicide trend. The product says
  "moved, more than comparable stones, more where exposure was higher", never "caused".
- **The window shape.** The mean of monthly log changes overweights off-season months in seasonal parks; a visits-weighted
  measure would be better for v3.
- **Lasting.** A measured grade is about the link. Whether the change lasted is separate: Hamilton Grange stayed above
  three times its 2014 level through 2019; the battlefields held two years; Fort Clatsop faded within a year.

## What the product would read

`ripples/docs/results/measure_v1.json`: `marks[]` (each with `grade_v2`, `why`, `line`, `own`, `controls`, `gradient`,
`raw`, `decoys` by id), `retests` (the ladder's two marks), `decoys`, `summary`, `exploratory_late`, `runs`, `requests`,
`stopped_hosts`. Proposed changes, not made: the engine's 13 Reasons Why mark (w0) from reported to measured; the Bake
Off mark at timed, not the ladder's measured; three new park marks (the battlefields, Fort Clatsop, Hamilton Grange) as
candidates for the record screen. The demo page and the chains are unchanged.

## Next

1. Names on a later day: register the SSA state design (local-relevance gradients; known positives such as Kizzy after
   Roots, 1977) in an addendum, then run it if www.ssa.gov answers.
2. A visits-weighted window for seasonal series, tested on synthetic data first.
3. The catalog's next series: BLS state jobs and QCEW counties (jobs after a show or a disaster), BTS air passengers
   (travel after a destination appears on screen), FARS and NICS when their hosts answer.
