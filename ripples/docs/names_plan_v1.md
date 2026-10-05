# Names v1: the anomaly-first route on US baby names (registered Oct 5, 2026, before any matching)

Item 7 of the discovery program: D2 in `discovery_engine.md`. Start from sharp, unusual moves in a series that measures
behavior (what parents named their children), then look back for the cultural stone. The canonical ripple is Frozen to
Elsa, and then the reversal. This plan is fixed before the anomaly scan has been run and before any candidate's stone
match has been looked at. Code: `ripples/lab/discovery/names/names_v1.py`, committed with this plan; its constants are
the numbers below. Deviations will be disclosed in `names_v1.md`.

## 1. Data, and what was refused

- **ssa.gov refused the honest user agent** on Oct 5, 2026 at 05:59 UTC: one request for
  `https://www.ssa.gov/oact/babynames/names.zip` returned HTTP 403 (an "Access Denied" page from the site's edge
  network). Per the rules there is no retry today, no other user agent and no mirror.
- **The counts used are the ones the project already holds:** `ripples.att_e9_names`, loaded on Sep 28, 2026 for E9
  phase 1 by `ripples/tools/bq/e9_names.py` (national totals per name, sex and year, summed from the SSA state files as
  published in the public BigQuery copy). Nothing new was fetched from any names source. The table was exported through
  the existing `att_e9_export` RPC by `export_names.py` (workflow `ripples-names-export.yml`) and is committed as
  `ripples/lab/discovery/names/names_national_1995_2021.csv` (97,108 rows, 3,737 name-sex pairs, 1995 to 2021,
  sha256 `0d93e74c...e074ff`). The owner should rule on whether this held extract is acceptable; if not, every result
  of this plan is void and will be labeled so.
- **What this extract can and cannot see:**
  - Years 1995 to 2021 only. Persistence two to five years later is observable for onsets up to 2016 to 2019.
  - Only names with at least 500 births over 2000 to 2010 (plus Arya, Elsa and Khaleesi). Names that did not exist
    before their stone (Katniss, Kylo, Renesmee, Daenerys, Anakin, Moana, Cataleya) are absent. The route therefore
    tests established names, which is also where an own-history test means something.
  - Counts are sums of state counts, and each state suppresses a name with fewer than 5 births that year, so totals run
    a little below the SSA national file (Elsa 2014: 1,107 here). A missing year is treated as 0.

## 2. Exposure before registration (disclosed)

- Elsa's 1995 to 2021 series (it is in `chains/batch1.json`) and E9 phase 1's synthetic-control results for Arya and
  Elsa.
- The first five rows of the salmon v1 anomaly list (`docs/results/salmon_names_v1.json`): Jaheim (M, 2001), Tenley
  (F, 2010), Ermias (M, 2019), Jaslene (F, 2007), Cataleya (F, 2012), all with empty candidate lists, and the salmon
  benchmark row for Elsa. Pairs found for these five names will be reported but **do not count toward the new-pair bar**.
- A coverage check (which of about 140 names are in the extract and in how many years; no counts) and a load check of
  Elsa's 2013, 2014 and 2021 counts against the chain.
- The scan, the statistics on any real name and the Wikidata look-back have not been run.

## 3. Statistics (per-year scaling, own history, year-matched placebo)

For each name N (by sex) and year t, with n the count:

- **Change:** d(N,t) = ln(n_t + 5) minus ln(n_(t-1) + 5), for t = 1996 to 2021.
- **Year-adjusted change (per-year scaling):** e(N,t) = d(N,t) minus the median of d over all names of the same sex in
  year t. This removes the year-wide shifts (falling births after 2008, the long drift toward rarer names) that made
  all-year nulls anti-conservative before (brief section 3, learning 3).
- **Own-history p:** p_own(N,t) = (1 + number of other years with e at least e(N,t)) / (1 + number of other years).
  With 26 changes, p_own <= 0.05 means the largest move in the name's own record. Falls use the mirror (at most).
- **Own scale:** s(N,t) = 1.4826 times the median absolute deviation of e(N,y) over all years except t to t+5, floored at
  0.05; u(N,t) = e(N,t) / s(N,t).
- **Year-matched p:** p_year(N,t) = (1 + number of other names of the same sex with u at least u(N,t) in the same year t)
  / (1 + number of other names). Every name is compared only with names in the same year, never with other years.
- **Established name:** at least 5 years with 20 or more births before the onset. A name without that history cannot be
  measured against its own history; its best grade is timed.
- **Run and onset:** a year is part of a rise run if its p_year (rise) <= 0.05. The onset of a move at year t is the first
  year of the unbroken run of such years that ends at t. Falls use the mirror.

## 4. Anomalies (candidate generation) and the look-back

- **Rise candidate (N, t), t from 1998 to 2021:** p_year <= 0.005 **and** p_own <= 0.10 **and** n_t >= 100 **and**
  n_t minus n_(t-1) >= 50.
- **Fall candidate:** the mirror, with n_(t-1) >= 100 and n_(t-1) minus n_t >= 50.
- Consecutive candidate years of one name and direction form one episode; its **peak** t* is the year with the smallest
  p_year, and its **onset** t0 is the start of the run ending at t*.
- **Look-back window:** stones released (calendar year R) from t0 minus 2 through t*. Stones released after the onset are
  kept on purpose: they are how a busted link is caught.
- **Stone shelves (Wikidata, English labels):**
  1. *Characters:* items that are in a work (P1441, or the work's P674) whose given name (P735) is N, whose English
     label is N or begins with "N ", or that have N as an exact English alias. The stones are those works and their
     adaptations (items with P144 "based on" a work, or the work's P4969). Found through given-name items labeled N,
     exact label and alias lookups, and the Wikidata search API (labels beginning with N).
  2. *Title characters:* works whose English title is exactly N.
  3. *People:* humans with given name N (or English label beginning "N ") and at least 10 sitelinks. Two dated
     stones per person: the birth date if born 1993 or later (famous from birth), and the earliest publication date of
     a notable work (20 or more sitelinks) with the person as cast member, performer, voice actor or author (debut).
  4. *Storms:* items labeled "Hurricane N", "Tropical Storm N", "Typhoon N" or "Cyclone N".
  5. *Named things:* items with N as an exact English label or alias (any case) and at least 50 sitelinks (products,
     organizations), dated by P577, P580 or P571.
- **Release date:** the earliest P577 (publication), else P580 (start), else P571 (inception); for storms P580 or P585.
  This is the earliest date anywhere; a US release can be a few weeks later.
- **Matching rule (automatic, applied identically to the true and the placebo windows):** the name matches as above;
  the stone has an English Wikipedia article and at least 20 sitelinks (people 20 for the debut stone and 10 for the
  birth stone, storms 5, named things 50); a character or person also has an English Wikipedia article; and the
  character's or person's recorded sex, if any, equals the baby's sex.
- **Strict hand check** (each pair, before it is graded; the reason is recorded):
  - H1. N is the character's or person's actual given name, or the name the character is primarily called in the work
    (a surname never counts; Edward Cullen does not explain "Cullen").
  - H2. The character or person is principal: a title, lead or main-cast character, or the person was widely famous at
    the stone date.
  - H3. The stone was released, aired or happened in the US, or was widely available there, in year R.
  - H4. The character's sex matches the baby's sex.
  - H5. Not a homonym: the stone is about someone or something called N, not a word that happens to be spelled N.
  A pair failing any item is dropped as a coincidence and listed with the reason.

## 5. The registered test (stone-anchored)

For a stone released in year R, month m, and name N in a direction (rise or fall):

- **Effective release year:** R_eff = R if m is January to June, else R + 1 (the first year with at least half a year of
  exposure; an unknown month counts as the second half).
- **Window:** the years R_eff through R + 2 (two or three years). t^ is the window year with the smallest p_year.
- **Measured** if all of: p_year(N,t^) <= 0.0033 (that is 0.01 divided by the three window years); p_own(N,t^) <= 0.05;
  n moved by at least 50 births to a level of at least 100 (materiality); the name is established; the onset of the run
  ending at t^ is no earlier than R_eff (the ordering rule: the move began after the release); and the hand check passed.
- **Timed:** in order and p_year(N,t^) <= 0.05, hand check passed, but one of the measured conditions failed.
- **Busted:** p_year(N,t^) <= 0.05 but the run ending at t^ began before R_eff: the move began before the release.
- **No move:** p_year(N,t^) > 0.05. Not reported as a pair.
- **Nominal false-positive rate of "measured" for a random name and stone: at most 1%.**

## 6. Known positives (fixed now, justified from coverage of the SSA releases and the names literature)

Tier A (established names; can be measured). **Recovered** means: the scan finds the episode in the stated years, the
look-back matches the stated stone, and the pair grades measured after the hand check.

| id | name | dir | expected peak | stone (date) | why it is a known positive |
|---|---|---|---|---|---|
| A1 | Elsa (F) | rise | 2014 | Frozen (Nov 27, 2013) | the canonical case; E9 phase 1 positive |
| A2 | Arya (F) | rise | 2011 to 2013 | Game of Thrones (Apr 17, 2011) | widely reported with the 2012 SSA data; E9 positive |
| A3 | Shiloh (F) | rise | 2006 to 2007 | Shiloh Jolie-Pitt (born May 27, 2006) | the most reported celebrity-baby effect of 2006 |
| A4 | Maci (F) | rise | 2009 to 2011 | Maci Bookout, *16 and Pregnant* (Jun 11, 2009) | the reality-TV name effect noted by name analysts |
| A5 | Katrina (F) | fall | 2005 to 2007 | Hurricane Katrina (Aug 2005) | the standard example of a storm sinking a name |
| A6 | Isis (F) | fall | 2014 to 2016 | Islamic State (caliphate declared Jun 29, 2014) | reported fall of the name after 2014 |
| A7 | Alexa (F) | fall | 2015 to 2017 | Amazon Alexa (Nov 6, 2014) | reported fall of the name after the voice assistant |
| A8 | Elsa (F) | fall | 2015 to 2016 | Frozen (Nov 27, 2013) | the reversal: the spike undoes itself |

Tier B (new or barely used names before the stone; by the established-name rule their best grade is timed; reported,
not counted toward the bar): B1 Khaleesi (F, 2011 to 2013, Game of Thrones), B2 Miley (F, 2006 to 2008, Hannah Montana),
B3 Suri (F, 2006 to 2007, Suri Cruise, born Apr 18, 2006).

Each known positive is also run through the test directly at its documented date, so a look-back miss and a test miss
are told apart. Known limits already visible: A6 depends on how Wikidata dates the Islamic State, and A4 on whether
Wikidata links the person to the show; a miss for either is reported as a look-back miss.

## 7. Decoys and placebos

- **Decoy names:** for every stone-name pair the look-back produces (not "no move"), 20 names of the same sex whose count
  the year before the release is within 25% of the real name's (the nearest 20 if fewer), drawn with seed 20261005, run
  through the same test at the same stone date.
- **Decoy stones, ghosts:** the same name with the stone moved back 5 to 10 years (six ghosts each, inside the data).
- **Decoy stones, fake:** 300 fake stones, a uniformly drawn name with a uniformly drawn release (1997 to 2019, month 1
  to 12), each tested as a rise and as a fall.
- **Unrelated name:** Ruth (F) at every known positive's date.
- **Look-back window placebo (coincidence of the match itself):** for every episode, the share with at least one
  auto-matched stone in the true window, against the same window moved back 4, 7 and 10 years, overall and among
  episodes that pass the statistical part of the test. Reported as an enrichment ratio and as an estimated coincidence
  share (shifted share / true share). If that share is above 0.25, the result doc says the route's matches are close to
  chance and the hand check carries the weight.

## 8. The bar

- **B1:** at least 3 of the 8 tier A known positives recovered.
- **B2:** at least 5 new pairs (not a known positive, not one of the five names in section 2) graded measured after the
  strict hand check.
- **B3:** each decoy family (decoy names, ghost stones, fake stones) passes "measured" at or below the nominal 1%; the
  Wilson 95% upper bound is reported beside each.
- The route passes if B1, B2 and B3 all hold. A miss is reported as a miss, with the diagnosis.

## 9. Output

- `ripples/docs/results/names_v1.json`: for each pair, stone {title, date, wikidata}, name, sex, direction, onset and
  peak years, counts before and after (raw counts for R minus 3 through the peak plus 5), p_year and p_own, the grade
  (measured, timed or busted), the hand-check reason, persistence and a plain line ("Parents named N more daughters Arya
  in 2012 than in 2010": the peak year against the year before the release).
- **Persistence:** n two to five years after the peak, against the mean of the three years before the release; the share
  of the jump kept each year. A rise counts as a durable behavior change only if it kept at least half of its jump on
  average over the years observed; fewer than two observed years is reported as "too recent to tell".
- `ripples/docs/names_v1.md`: numbers against the bar, the pairs, the misses, the limits.

## 10. Owner additions (Oct 5, 2026, registered here before any result)

For every pair graded measured (a "confirmed pair"):

1. **Event siblings.** The sibling family is (a) the other characters of the same stone (and its source work or
   adaptations) whose names are in the extract, with the same sex rule; (b) characters of other works by the same
   production company (P272) released within 2 years of the stone, with 30 or more sitelinks; (c) characters of other
   works sharing a genre (P136) released within 1 year, with 60 or more sitelinks (at most 40 works). Each sibling pair
   gets the same test, with the hand check items H1 to H4 applied by the same rule. A family **generalizes** if at least
   2 sibling pairs grade measured and the sibling measured rate is at least five times the decoy-name rate; it is
   **partial** with exactly 1; **isolated** with 0.
2. **Generated hypotheses.** For each confirmed pair, before testing them, write down what else should be true, choosing
   from these templates and naming the specifics (which variant names, which sequel), in an addendum committed before
   the tests run:
   - *persist:* the name kept at least half of its jump two to five years later.
   - *reversal:* a fall with p_year (fall) <= 0.05 within 1 to 4 years after the peak (predicted for a fad, and stated
     per pair as predicted or not predicted).
   - *companion:* at least one spelling variant (same sex, edit distance 1, in the extract) rises with p_year <= 0.05 in
     the same window; the base rate for a random name of similar size is reported beside it.
   - *lag:* the peak falls in the first full calendar year after the release (R + 1; R if released January to March).
   - *sex:* the opposite-sex use of the name, if in the extract, does not rise with p_year <= 0.05 in the window.
   - *sequel:* if the stone has a sequel or later season released by 2020, the name shows another rise with
     p_year <= 0.10 in that sequel's window.
   Each is reported as held or failed.
3. **Lag.** The distribution of release-to-onset and release-to-peak lags (in years, and in months from the release date
   to July 1 of the peak year) across confirmed pairs, and separately across timed pairs, reported as a lag prior for
   this mechanism.

## 11. Politeness

Wikidata query service and API only: the honest user agent `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`,
at most one request a second, every response cached, SPARQL 500/504 retried up to three times with small queries, a
query that still fails is recorded for that name, and any 403, 429 or other refusal stops the run for the day. Aggregate
data only. Wikipedia summaries may be read for the hand check under the same rules.

## Deviation 1 (registered Oct 5, 2026, 06:30 UTC, before any match or result existed)

- **What happened:** the first scan run stopped during the look-back, after 85 of 202 names (alphabetical), when the
  Wikidata action API (`www.wikidata.org/w/api.php`, the `wbsearchentities` search used for labels beginning "N ")
  answered HTTP 429. The run wrote a stop marker (`docs/results/names_v1_stop.json`) and exited. No matching, test,
  decoy or known-positive result was produced, and none of the cached Wikidata responses has been read.
- **What changes:**
  - The action API is not called again today, from anywhere. The search route is **dropped for every name**, including
    the names already searched (their cached search results are ignored), so all 202 names get the same look-back.
  - The look-back continues on the Wikidata query service (`query.wikidata.org`), a separate service with its own
    limits, which has not refused. Spacing is raised from 1 to 2 seconds between requests for the rest of the run; any
    403, 429 or other refusal from it stops the run for the day.
  - Cost: characters whose only link to the name is an English label beginning "N " (no P735 given name, no exact label
    or alias) are no longer found. This lowers recall; it does not loosen any test.
- **Unchanged:** the statistics, the anomaly rule, the window, the matching rule otherwise, the test, the known positives,
  the decoys and the bar.

## Deviation 2 (registered Oct 5, 2026, 07:20 UTC, before any match or result existed): implementation only

- **What happened:** the resumed run reached the last look-back step (publication dates for 12,944 works and items) and
  stalled: the date query timed out at the query service (HTTP 504) on every chunk, because its shape joined every
  time value in Wikidata before the listed items. The run was stopped by hand; no match or result was produced.
- **Fix:** each date property's branch now binds its own time value. A three-item test query returned in 0.2 seconds.
- **Unchanged:** everything that is measured or matched.
