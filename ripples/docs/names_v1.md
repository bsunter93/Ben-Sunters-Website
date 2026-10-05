# Names v1: the anomaly-first route on US baby names (results, Oct 5, 2026)

Plan: `names_plan_v1.md`, registered at commit `ba589ce` before any matching, with two disclosed deviations before any
result (the Wikidata search API refused with a 429, so that route was dropped for every name; a date query was
reshaped after it timed out) and one addendum (generated hypotheses, committed before they were tested). Code:
`ripples/lab/discovery/names/`. Data: `results/names_v1.json` (graded pairs), `results/names_v1_candidates.json` (every
episode, match, decoy and known positive before the hand check), `results/names_v1_handcheck.json` (every hand-check
decision with its reason), `results/names_v1_followup.json` (siblings, hypotheses, lag).

## The answer in one paragraph

**The route did not pass its bar.** It found 4 measured pairs, against a bar of 5. It recovered none of the 8 known
positives as measured, against a bar of 3. The decoys stayed under 1%. Two pairs look like real, lasting ripples:
*Creed* to Adonis (sons) and *Glee* to Quinn (daughters). *The Princess and the Frog* to Tiana was measured, then
reversed. *The Dark Knight Rises* to Alfred passed the test but is probably chance, because a principal character named
Alfred turns up in every placebo window too. The canonical case, *Frozen* to Elsa, grades **timed**: Elsa's 2014 jump
was the 8th largest of the extract's 2,120 girls' names that year (p = 0.0038), just short of the registered 0.0033. The method's
weakness is the match, not the test. Before the hand check, automatic stone matches were as common in fake look-back
windows as in the real one (enrichment 1.04).

## Numbers against the bar

| bar | needed | result | verdict |
|---|---|---|---|
| B1 known positives recovered (tier A) | 3 of 8 | **0 of 8** | failed |
| B2 new measured pairs after the strict hand check | 5 | **4** (Adonis, Quinn, Tiana, Alfred) | failed |
| B3 decoy names (2,300 tests) | <= 1% | 0.22% (5; Wilson upper 0.51%) | passed |
| B3 ghost stones, the real stone moved back 5 to 10 years (488) | <= 1% | 0% (Wilson upper 0.78%) | passed |
| B3 fake stones, random name and release (600) | <= 1% | 0.33% (2; Wilson upper 1.21%) | passed |
| Ruth at every known positive's date (11) | | 0 passed | |

**Overall: not passed.** Two decoy passes are worth knowing about. Ryan (girls) passed at Frozen's date, while Elsa did
not. Caitlyn passed at the date of *The Flash*, whose character is Caitlin; that one is a spelling sibling, not noise.

## What the scan saw

- 3,737 name-sex pairs, 1995 to 2021. **230 episodes**: 152 sharp rises and 78 sharp falls, each in the top 0.5% of
  its year after per-year scaling and among the two largest moves in the name's own record.
- The look-back covered all 202 names in those episodes, and no name failed at the query service. 57 episodes had at
  least one automatic stone match in the true window, giving 131 stone-name pairs. 120 of those moved in the window
  (the rest were "no move"). **36 passed the hand check (34 distinct pairs once duplicate character items for one film
  are merged); 84 were dropped.** 70 of the 84 drops failed
  H2 (not principal, or a person born in the window who was not famous from birth). The people shelves supplied 49 of
  the 84 drops.
- After the hand check: **4 measured, 20 timed, 7 busted** (distinct names and directions). 173 of the 230 episodes
  had no stone at all.

### The look-back is the weak link (window placebo)

| window | episodes passing the statistics (70) with an automatic match | with a match that passes the hand check (post hoc) |
|---|---|---|
| true (0 to 2 years before onset) | 16 (22.9%) | 6 (Adonis, Alfred, Alice, Quinn, Raya, Tiana) |
| moved back 4 years | 12 (17.1%) | 4 |
| moved back 7 years | 15 (21.4%) | 3 |
| moved back 10 years | 19 (27.1%) | 2 |

The registered measure is the automatic one: **enrichment 1.04, estimated coincidence share 0.96.** By the plan's own
rule (above 0.25), this route's matches are close to chance, and the hand check carries the weight. The right-hand
column is a post hoc diagnostic, not registered: the same hand check applied to the placebo windows. It gives
enrichment 2.0, so about half of the hand-checked matches would be expected by chance. Alfred and Alice match a
principal character in every window, because Batman films and *Alice* adaptations appear every few years. Without those
two names the enrichment is 4 (4 against a mean of 1.0).

## The measured pairs (raw counts beside every result)

| name | stone (release) | counts: year before release, then onset year | p_year | p_own | 2 to 5 years later | lasting? |
|---|---|---|---|---|---|---|
| **Adonis** (sons) | *Creed* (Nov 25, 2015) | 287 (2014), 322 (2015), **756 (2016)** | 0.0025 | 0.038 | 855, 1,527, 1,651, 1,699 | yes; it kept growing after *Creed II* |
| **Quinn** (daughters) | *Glee* (premiered May 19, 2009) | 565 (2008), 593 (2009), **1,257 (2010)** | 0.0028 | 0.038 | 2,099, 2,638, 2,541, 3,092 | yes; it kept growing |
| **Tiana** (daughters) | *The Princess and the Frog* (Nov 25, 2009) | 441 (2008), 466 (2009), **942 (2010)** | 0.0024 | 0.038 | 684, 499, 509, 441 | **no**; back below the pre-film level by 2013 |
| **Alfred** (sons) | *The Dark Knight Rises* (Jul 20, 2012) | 158 (2011), 157 (2012), 150 (2013), **234 (2014)** | 0.0019 | 0.038 | 193, 206, 193, 231 | half kept; **probably chance** (see above) |

Plain lines, as the product would show them:
- Parents named 469 more sons Adonis in 2016 than in 2014.
- Parents named 692 more daughters Quinn in 2010 than in 2008.
- Parents named 501 more daughters Tiana in 2010 than in 2008; by 2013 the count was back below its 2006 to 2008 average.
- Parents named 76 more sons Alfred in 2014 than in 2011.

The product rule says a ripple's payoff is a lasting mark. Adonis and Quinn persisted. Tiana is an Elsa-shaped spike:
a measured rise, then a reversal. Alfred should not be published. It is the kind of match the window placebo warns
about, and its blind hypotheses failed (below).

## Known positives (tier A: 0 of 8 recovered)

| id | case | scan found the episode | look-back found the stone | test at the documented date | grade | why it missed |
|---|---|---|---|---|---|---|
| A1 | Elsa rise, *Frozen* | yes (2014) | yes | p_year 0.0038, p_own 0.038 | **timed** | 8th of 2,120 that year; the bar was 0.0033 |
| A2 | Arya rise, *Game of Thrones* | no | yes (in the catalog) | p_year 0.021 (2012) | timed | a steady climb (211, 344, 724, 1,117, 1,546); never the year's sharpest jump against a history that was already rising |
| A3 | Shiloh rise, Shiloh Jolie-Pitt | no | no | p_year 0.0076 (2007) | timed (direct) | test short; no matching person in Wikidata by the rule |
| A4 | Maci rise, *16 and Pregnant* | yes (2010) | **no** | **measured** (p_year 0.0019) | look-back miss | 420 (2009) to 1,339 (2010); Wikidata does not link Maci Bookout by given name or show cast |
| A5 | Katrina fall, Hurricane Katrina | yes (2006) | yes | p_year 0.0033, p_own 0.077 | **timed** | 2007's fall (826 to 458) was steeper than 2006's (1,303 to 826) |
| A6 | Isis fall, Islamic State | yes (2015) | **no** | **measured** (p_year 0.0005) | look-back miss | 347 (2014) to 73 (2015); Wikidata dates the group to 1999 (inception), as the plan warned |
| A7 | Alexa fall, Amazon Alexa | no | no | no move (p 0.050) | miss | Alexa rose in 2015 (6,034) and then declined slowly over five years |
| A8 | Elsa fall, *Frozen* | no | yes | p_year 0.022 (2015) | timed | 1,107 to 618 was steep, but not extreme for a name that had just doubled |

Tier B (new names; timed at most by rule): Khaleesi (0, 5, 111, 180 from 2010 to 2013) and Miley (0, 141, 1,214, 2,640
from 2005 to 2008) were found and matched to *Game of Thrones* and *Hannah Montana*, both timed. Suri was found but not
matched.

The test alone, at the documented dates, measures 2 of 8 (Maci, Isis), and the look-back misses both. The look-back
alone finds the right stone for Elsa, Arya and Katrina, and the test grades them timed. **No known positive passes
both halves.** E9's synthetic-control design measured Elsa (p = 0.010) and Arya (p = 0.013). That design compares a
name against a weighted set of donor names; this one compares a single year's jump against every name that year and
the name's own history. This test is stricter, and it is blind to slow climbs.

## Timed and busted (in order but short of the test; or the move began first)

- **Timed, with the strongest raw moves:** *Dawson's Creek* to Dawson (141 in 1997 to 1,883 in 1998); *The Matrix* to
  Trinity (447 to 1,462 in 1999, then 4,280); *Austin Powers* to a fall in Austin (23,477 in 1998 to 15,945 in 2000).
  These cannot be measured for a structural reason: the data start in 1995, so no onset before 2000 has five earlier
  years, and the established-name rule needs five. *Pretty Little Liars* to Aria, *Legally Blonde* to Elle, *Raya and
  the Last Dragon* to Raya (222 to 594 in 2021; too recent for persistence), *Logan* to Logan, *Chuck* to Ellie and
  *The Dark Knight* to Harvey also grade timed.
- **Busted (the rise began before the release), the ordering rule doing its job:** *Alice in Wonderland* (2010) to
  Alice (the rise began in 2009); *Suits* and *Gotham* to Harvey (rising since 2009); *Ice Age: Dawn of the Dinosaurs*
  to Ellie; *The Golden Compass* (Dec 2007) to Lyra (rising in 2007); Kanye West's first album (Feb 2004) to Kanye
  (rising in 2003); Rihanna's first album (Aug 2005) to Rihanna. The last two show the person route's dating
  weakness. Rihanna's first single came out in May 2005, but the rule dates her by the album.

## Owner additions

**1. Event siblings.** No family generalizes.

| confirmed stone | sibling pairs tested | measured | verdict |
|---|---|---|---|
| *The Dark Knight Rises* | 104 | 0 | isolated |
| *Creed* | 20 | 0 | isolated |
| *Glee* | 195 | 1 (Tiana, *The Princess and the Frog*, through the shared musical genre) | partial |
| *The Princess and the Frog* | 156 | 1 (Quinn, *Glee*, through the same link) | partial |

No other character of the same work was measured: Talia in *The Dark Knight Rises* is timed at best, and so are
Brittany and Rory in *Glee*. The one cross-link is two 2009 musicals whose lead girls'
names both doubled in 2010. The timed counts in the follow-up file are before the H1 check; some come through middle
names. Only the measured siblings were hand-checked, and both pass.

**2. Generated hypotheses** (written before testing; "visible" means the main output had already shown it).

| pair | held | failed | not testable |
|---|---|---|---|
| Adonis / *Creed* | no reversal (blind); lag 2016 (visible); persisted (visible); *Creed II* second rise (visible) | | companion, sex |
| Quinn / *Glee* | **Quinn for boys did not move (blind; p 0.22)**; **season 2 brought a second rise, 1,257 to 1,676 (blind; p 0.016)**; no reversal (blind); lag 2010; persisted | | companion |
| Tiana / *The Princess and the Frog* | reversal, predicted (partly visible; 2013 p 0.013); lag 2010 | **Tianna and Tyana did not move (blind)**; did not persist | sex, sequel |
| Alfred / *The Dark Knight Rises* | persisted, barely (0.52) | **Alfredo did not move (blind)**; **a fall in 2015 that was not predicted (blind; 234 to 170)**; lag (2014, not 2013) | sex, sequel |
| Elsa / *Frozen* (reference) | reversal; lag 2014 | did not persist (below the pre-film level by 2016); no second rise after *Frozen II* (312, 241, 214) | companion, sex |
| Arya / *Game of Thrones* (reference) | Aria rose too (p 0.004); season 2 second rise; persisted; lag 2012 | Arya for boys "rose" (38 to 78 in 2011, tiny counts) | |

Quinn is the strongest pair: every blind prediction held, including the specificity check (girls only) and the
later-season dose. Alfred failed every blind prediction.

**3. Lag prior** (release to onset). Confirmed pairs (4): 1 year for three, 2 years for one (Alfred). From release to
the middle of the peak year: 8, 8, 14 and 24 months (median 11). Timed pairs (21): onset 0 years after release for 8,
1 year for 8, 2 years for 5; peak median 1 year; months to the middle of the peak year range from 3 to 26 (median 11).
**Prior for this mechanism: the first full calendar year after release. 8 of the 21 timed moves began in the release
year itself, all after releases in January to June.**

## Limits

- **Data provenance.** ssa.gov refused (403). The counts are the project's held extract (`att_e9_names`, from the public
  BigQuery copy of the SSA state files, loaded Sep 28). The owner should rule on it. If the extract is ruled out, these
  results are void.
- **Coverage.** The extract has only names with 500 or more births over 2000 to 2010, from 1995 to 2021. It cannot see
  names born with their stone (Katniss, Kylo, Renesmee), measure onsets before 2000, or show persistence after 2021.
- **Annual resolution.** "A year after release" is as fine as the timing gets.
- **The match is the bottleneck.** Wikidata recall is uneven. It missed Maci Bookout, Shiloh Jolie-Pitt and the
  Islamic State's 2014 date. Items labeled only in the new multilingual ("mul") label slot are invisible to an English
  exact-label seed. The search route was lost to the 429. The people shelves mostly produced noise.
- **The hand check is one reader's call.** Every decision and its reason is in `names_v1_handcheck.json`. The working
  rules: main cast means the infobox "Starring" list or a series regular; a person must be a US household name by the
  end of the stone's year. Those rules decided two close cases: Kendrick Lamar (dropped) and Rosie Huntington-Whiteley
  (dropped).
- **A one-year jump statistic misses slow climbs** (Arya, Aria). A multi-year statistic is the obvious v2. It needs its
  own registration and decoys.
- **It wasn't the only reason.** A measured pair shows an unusual rise in the right order after a principal
  character's release. It does not show cause. Quinn and Adonis both kept rising for years, which also fits a wider
  fashion that the show rode.

## What to do with it

- **Product:** *Glee* to Quinn and *Creed* to Adonis are candidates for the culture shelf as **measured** with lasting
  marks, after the owner's surprise check. *The Princess and the Frog* to Tiana fits the Elsa template: a measured
  spike, then a reversal. *Frozen* to Elsa stays timed under this test; E9's measured grade comes from a different
  registered design and should be cited as such. Do not publish Alfred.
- **Engine:** the next gain is in the look-back, not the test. Stone dates should come from a release table (TMDB or a
  US-release qualifier). Stones should be matched by character prominence, not just existence. The anomaly statistic
  should get a slow-climb variant. Each change needs a new registration, and the hand-checked window placebo should
  become a registered metric.

## Changes after registration (disclosed)

- Before any result: deviation 1 (the search route dropped after the 429; 2 seconds between requests) and deviation 2
  (the date query reshaped), both in the plan.
- After the scan, none of which changes a grade or a p value:
  - The plain line now compares a stone released before 1996 with 1995, the first data year. It used to crash.
  - The earliest release date is now chosen to the day, not just the month (*Frozen* shows as Nov 10, 2013, the
    earliest date Wikidata records; *The Dark Knight Rises* as Jul 20, 2012). Grades depend only on the month, and all
    were checked unchanged.
  - Items with only a multilingual label get their label back for display.
  - In the follow-up, the sequel window is the two years from the sequel's effective year, as the addendum states. The
    first draft used one year, and no verdict changed.
