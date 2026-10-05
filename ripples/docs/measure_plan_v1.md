# Measure v1: a series catalog, the standard test v2, and an outcome-first scan (pre-registered)

*Written Oct 5, 2026, before any outcome value was fetched. The code is committed with this file:
`ripples/lab/ladder2.py` (the test), `ripples/lab/measure_registry.py` (every stone, pool, unit and group, frozen),
`ripples/lab/measure_v1.py` (fetch, run, decoys) and `ripples/lab/series_catalog.py` (the catalog). It builds on the
evidence ladder (`ripples/lab/ladder.py`, PR #119) and reuses its code unchanged. Results
will go to `ripples/docs/results/measure_v1.json`, `ripples/docs/measure_v1.md`, `ripples/docs/results/series_catalog_v1.json`
and `ripples/docs/series_catalog_v1.md`.*

## 1. Why

87 of the engine's 102 marks are laws and institutions: verifiable records, not measurable series. Of the other 15,
the ladder could test 2, and the one mark that climbed to measured (The Great British Bake Off → UK household flour,
p = .031) is fragile: it ranks 4th of 11 against matched TV controls and 3 of 19 decoy windows on the same series also
pass. A measured grade needs (a) outcome series with enough history and resolution to have power, (b) a test that asks
more than "unusual and in order", and (c) a scan that starts from the strongest outcome series instead of from the marks.

## 2. What was read before this registration (metadata only)

Every request used the project's user agent, at least 1 second apart. None returned an outcome value. Times are UTC on
Oct 5, 2026.

| Time | Request | Status | What it gave |
|---|---|---|---|
| 07:04 | `wonder.cdc.gov/wonder/help/wonder-api.html` | 200 | API rules: POST `request_xml`, consent parameter, national data only, one query at a time about 2 minutes apart |
| 07:04 | `raw.githubusercontent.com/alipphardt/cdc-wonder-api/master/README.md` | 200 | parameter names for D76 (month is `D76.V1-level2`, single-year ages `D76.V52`) |
| 07:05 | `wonder.cdc.gov/wonder/help/api-examples/D76_Example2-req.xml` | 200 | a valid D76 request (injury intent, single-year ages); the example *response* was not read |
| 07:05 | `wonder.cdc.gov/datause.html` | 200 | the data use restrictions (section 6.2) |
| 07:05 | `irmaservices.nps.gov/v3/rest/Stats/help` and `.../FetchVisitation` | 200, 200 | the visitation operation and its parameters; the response format is not documented |
| 07:05 | `www.ssa.gov/oact/babynames/limits.html` | **403** | SSA refused the project's agent; www.ssa.gov is stopped for the day (section 8) |
| 07:15 to 07:16 | `www.wikidata.org/w/api.php?action=wbgetentities` (14 requests, 6 of them rejected for a parameter error) | 200 | release and death dates for the registry (below) |
| 07:17 | `raw.githubusercontent.com/wiki/alipphardt/cdc-wonder-api/...` | 404 | a guessed page; not called again |
| 07:18 | `socdatar.github.io/wonderapi/articles/D76codebook.html` | 200 | D76 value codes: injury intent 2 = Suicide; mechanism GRINJ-017 = Suffocation |

**Date check.** 275 registry dates (stones, control pools, deaths) were compared with Wikidata. 220 agree within 31
days. The 55 flagged are year-only precision in Wikidata, festival or foreign premieres earlier than the US release,
first performances before a Broadway opening, or a different work with the same article title. No registry date was
changed. The registered convention is the US release (first US theatrical release, TV premiere, Broadway opening night)
or the date of death.

**Calibration on synthetic data only (no real outcome value).** The v2 code was dry-run end to end on synthetic series
(`MEASURE_DRY=1`). On 300 synthetic monthly series per row with an AR(1) noise term, the placebo-date test at nominal
.05 fired at 4.7% (white noise), 6.6% (AR .5), 6.3% (AR .8) and 6.7% (AR .95). On synthetic park-like series the full v2
test graded 71 and 72 of 1,500 decoy windows measured in two dry runs (4.7% and 4.8%), against about 100 that passed
rung (i) alone (6.7%). On noise the
controls and the gradient remove little, because a noise spike in one series is independent of other dates and other
units; they are there for confounds (a series-wide surge, a shared shock), which synthetic noise does not have.

## 3. The series catalog: rule

A series enters `series_catalog_v1.json` if it is (1) a behavior outcome (what people do: visit, buy, name, enroll,
work, travel, die by a cause) or is explicitly marked as attention; (2) public and aggregate; (3) reachable with no key
and no account (a series behind a key is listed and marked excluded); (4) dated at a known frequency with a known start.
For each: frequency, start year, geography and the number of units, unit, access URL, access terms, and power.

**Power.** An outcome window is tested against windows of the same shape in the series' own history before the stone,
so the smallest p a series can give is 1/(N+1), with N the admissible placebo windows. An annual national series with
N admissible years can reach only 1/(N+1). The catalog counts N for a stone in 2015 with the shortest window each
frequency allows, minus the excluded periods, and states that overlapping windows make N an upper bound. Geography
is counted separately: it is what rung (iii) needs.

**Ranking.** Behavior series that are eligible, first by whether they have at least 10 geographic units (a gradient is
possible), then by the p floor, then by the number of units. The scan below uses the top reachable ones.

**Probe.** One request per host to a landing or documentation page, never an outcome value, run after measure_v1.py so
no probe can stop a host the scan needs. A host the scan already called takes its status from the scan.

## 4. The standard test v2

A mark is **measured** only if all three rungs pass.

1. **Own series, in order.** The change over the outcome window is unusual against every admissible window of the same
   shape in the series' own history before the stone: empirical p = (1 + placebo effects at least as large) / (1 + N)
   ≤ .05, the change is in the claimed direction, and no departure began before the stone (the ladder's onset rule,
   section 4.3 of `ladder_plan_v1.md`; a rise that began first is **busted**).
2. **Matched control stones.** The same change, on the same series, after the nearest control stones of the same kind:
   similar size (drawn from a registered pool of major works of that kind), similar timing (the 19 nearest in date),
   none linked to the outcome, none whose window touches the mark's own window. Rank p = (1 + controls at least as
   large) / (1 + n) ≤ .10, with n ≥ 9. With 9 to 18 controls the mark must beat every one; with 19 it may tie or lose to
   one.
3. **Exposure gradient,** where the outcome has geography or another exposure dimension and an exposure measure is
   registered for the stone: more exposure, bigger change. Ordered groups: Spearman rho between exposure and the change
   is above 0 and the most exposed group changes more than the least exposed. A featured unit: its change exceeds the
   median change of the registered comparison units (its in-space rank is reported). Where no exposure measure exists,
   rung (iii) is n/a and the record says so.

**Grade map.** Busted if the rise began before the stone. Measured if rungs 1, 2 and 3 pass (3 may be n/a). Timed if
rung 1 passes but 2 or 3 fails, or if rung 1 fails on p but a departure began inside the window, in order. Otherwise no
movement; a mark with a citation keeps its reported grade. A measured grade still means an unusual rise in the right
order that beat comparable stones and pointed the right way across exposure; it does not mean the stone caused it.

**Window shapes.** *standard*: the ladder's (mean of the next h periods minus the mean of the previous h, in logs; h = 12
for monthly series, h = 1 for annual). *paired*: the same 12-month window written as twelve year-over-year pairs, so a
missing month (a zero, a seasonal closure, a registered shutdown month) drops its pair from both halves instead of the
whole window; with all 24 months present it equals standard. *yoy*: h months from the reference against the same h
months a year earlier, for a short window on a seasonal monthly series. A window that touches an excluded period
(Sep 15, 2008 to Jun 30, 2009; Feb 15, 2020 to Jun 30, 2021) is dropped whole, as in the ladder.

**Reference period.** Monthly: the month that contains the stone's date, or the next month when the stone falls on or
after the 25th. Annual: the stone's year, or the next year when the stone falls after June 30.

**Placebo pool.** Every window of the same shape whose periods all lie before the stone's own period and that starts
more than 2h periods from the reference (the ladder's pool).

## 5. Re-tests of the ladder's two marks under v2

Both use the ladder's fetchers (`defra_flour`, `ssb_08402`) and series builders unchanged.

| Mark | Series | Window | Controls (rung 2) | Gradient (rung 3) |
|---|---|---|---|---|
| The Great British Bake Off → baking sales (Aug 17, 2010) | Defra Family Food, UK household flour, g per person per week | standard, h = 1, reference 2011 | the 19 nearest TV series in `TV_POOL` (governs); the ladder's 10 registered TV controls reported beside it | n/a: no exposure measure is registered (no regional viewing series) |
| Frozen → Norway tours (Nov 27, 2013) | Statistics Norway 08402, foreign guests' hotel nights | standard, h = 12, reference Dec 2013 (the 25th rule) | the 19 nearest films in `FILM_POOL` (governs); the ladder's 6 culture films reported beside it | ordered: the fjord counties (Hordaland, Sogn og Fjordane, Møre og Romsdal; the model for Arendelle) above the rest of Norway |

The Nov 2013 reference the ladder used is reported beside the v2 result.

## 6. Scan arm A: CDC WONDER monthly deaths (the published positives)

### 6.1 Series and requests

D76 (Underlying Cause of Death, 1999-2020), deaths by month of death, United States. The API returns national data only.
Five requests, in this order, about 2 minutes apart: suicide (injury intent 2) at single-year ages 10 to 17; 18 to 29;
30 to 64; all ages by injury mechanism; 10 to 19. "All ages" is the sum over mechanisms; "the reported method category"
is WONDER's GRINJ-017 mechanism group; "all other" is the total minus that group.

### 6.2 Data use (the owner accepted CDC WONDER's restrictions on Oct 5, 2026)

Every query sends `accept_datause_restrictions=true`. These data are used for statistical reporting and analysis only.
Only national aggregate counts are requested. No count of nine or fewer deaths, and no rate built on one, is published
(the code withholds any such cell before writing). No attempt is made to identify anyone, and nothing is linked to other
data. Results credit CDC WONDER and carry its citation. Suicide results are written in aggregate, without method
detail beyond the WONDER category name, and without sensational wording.

### 6.3 Marks

| Mark | Outcome | Window | Controls | Gradient | Known positive |
|---|---|---|---|---|---|
| 13 Reasons Why (Mar 31, 2017) | suicide, ages 10 to 17 | yoy, h = 3: Apr to Jun 2017 against Apr to Jun 2016 | 19 nearest teen-audience TV premieres (`TEEN_TV`) | ordered by audience exposure: ages 10-17 (3), 18-29 (2), 30-64 (1) | Bridge et al. 2020, JAACAP (April 2017, ages 10 to 17, +28.9% above forecast); Niederkrotenthaler et al. 2019, JAMA Psychiatry (Apr to Jun 2017, ages 10 to 19, about +13%); disputed by Romer 2020, PLOS ONE |
| The death of Robin Williams (Aug 11, 2014) | suicide, all ages | yoy, h = 5: Aug to Dec 2014 against Aug to Dec 2013 | 19 nearest deaths of widely known public figures not by suicide (`CELEB_DEATHS`) | ordered: the method category reported in coverage (2) above all others (1), the standard marker of imitation | Fink, Santaella-Tenorio and Keyes 2018, PLOS ONE (+9.85% in Aug to Dec 2014) |

Secondary, reported, not graded: 13 Reasons Why on ages 10 to 19 (yoy, h = 3), April 2017 alone (yoy, h = 1) and the
ladder's 12-month design; Robin Williams on the 12-month design. Linked stones that are never controls or decoys:
13 Reasons Why season 2, Euphoria, and the engine stones listed in `LINKED_A` (school and mass shootings, September 11
and the anthrax letters).

**Decoys.** Each mark's outcome series at the dates of the engine's other stones (`demo/discovered_wiki.json`, not
linked) and of the other arm-A pool (celebrity deaths for the youth series, teen premieres for the all-ages series),
deduplicated by window, never touching the real window, each graded by the full v2 test with the mark's own control
pool and gradient groups.

## 7. Scan arm B: NPS monthly recreation visits (the new marks)

### 7.1 Series

NPS Visitor Use Statistics, monthly recreation visits by park unit, Jan 1979 to Dec 2024, one request per unit
(`irmaservices.nps.gov/v3/rest/stats/visitation`). A month with zero visits, no value, or a federal shutdown (Nov 1995 to
Jan 1996, Oct 2013, Dec 2018 to Jan 2019) is missing. Window: paired, h = 12. A family of units is summed month by
month (a month missing in any unit is missing in the sum). A unit with an alternative code (LEWI/FOCL; JAZZ/NOJA/JELA;
VALR/USAR) uses the first code that returns data.

### 7.2 Marks (31 monthly, 1 annual)

A stone whose featured unit is the setting or the subject of the work. Full list with reasons in `NPS_MARKS`.

| Stone (date) | Kind | Unit(s) | Group |
|---|---|---|---|
| The Civil War, Ken Burns (Sep 23, 1990) | documentary | GETT, ANTI, MANA, VICK, SHIL, FRSP, CHCH, PETE, RICH, STRI (summed) | BATTLE |
| Son of the Morning Star (Feb 3, 1991) | tv | LIBI | BATTLE |
| Gettysburg (Oct 8, 1993) | film | GETT | BATTLE |
| Andersonville (Mar 3, 1996) | tv | ANDE | BATTLE |
| Lewis & Clark, Ken Burns (Nov 4, 1997) | documentary | LEWI | HIST |
| The Patriot (Jun 28, 2000) | film | COWP | BATTLE |
| Jazz, Ken Burns (Jan 8, 2001) | documentary | JAZZ | HIST |
| Pearl Harbor (May 25, 2001) | film | VALR | HIST |
| Gods and Generals (Feb 21, 2003) | film | FRSP | BATTLE |
| Cold Mountain (Dec 25, 2003) | film | PETE | BATTLE |
| National Treasure (Nov 19, 2004) | film | INDE | HIST |
| Grizzly Man (Aug 12, 2005) | documentary | KATM | NP |
| United 93 (Apr 28, 2006) | film | FLNI | HIST |
| Into the Wild (Sep 21, 2007) | film | DENA | NP |
| The War, Ken Burns (Sep 23, 2007) | documentary | WWII | HIST |
| 127 Hours (Nov 5, 2010) | film | CANY | NP |
| Red Tails (Jan 20, 2012) | film | TUAI | HIST |
| Lincoln (Nov 9, 2012) | film | FOTH; and separately LIHO | HIST |
| Bears, Disneynature (Apr 18, 2014) | documentary | KATM | NP |
| The Roosevelts, Ken Burns (Sep 14, 2014) | documentary | HOFR, ELRO, SAHI, THRB, THRO (summed) | HIST |
| Selma (Dec 25, 2014) | film | SEMO | HIST |
| Hamilton (Broadway, Aug 6, 2015) | stage | HAGR | HIST (documented positive) |
| The Vietnam War, Ken Burns (Sep 17, 2017) | documentary | VIVE | HIST |
| Yellowstone (Jun 20, 2018) | tv | YELL | NP |
| Free Solo (Sep 28, 2018) | documentary | YOSE | NP |
| National Treasure: Book of Secrets (Dec 21, 2007); John Adams (Mar 16, 2008); Twilight (Nov 21, 2008); The National Parks (Sep 27, 2009); Harriet (Nov 1, 2019) | | MORU; ADAM; OLYM; YELL+YOSE+GRCA; HATU | expected untestable (excluded periods); run so the reason is recorded |
| Close Encounters of the Third Kind (Nov 16, 1977), annual | film | DETO | conditional: runs only if the API returns per-unit annual values for 1977 (one probe request); documented positive |

**Controls (rung 2).** The 19 nearest stones of the same kind from the registered pools (`FILM_POOL`: one to three of the
top-grossing US films of each year 1970 to 2019, plus the arm's films; `DOC_POOL`; `TV_POOL`; `STAGE_POOL`), excluding
the stone itself and any arm stone that features the same unit.

**Gradient (rung 3).** The featured unit (or family sum) against every unit of its registered group (`NPS_GROUPS`:
BATTLE, HIST, NP) that the stone does not feature: the featured change must exceed the comparison median.

**Decoys.** Each featured unit at the dates of the engine's stones and of the other arm-B stones (those that do not
feature it), deduplicated by window, never touching the real window, each graded by the full v2 test with the mark's
control pool and comparison units.

**Documented positives** (press or the park's own history, not peer-reviewed): Hamilton → Hamilton Grange; Close
Encounters → Devils Tower. They are reported but count toward neither part of the bar below.

## 8. Names: registered as next, not run today

The state baby-name files are the obvious third series (annual, 51 units, from 1910). www.ssa.gov answered the
project's agent with 403 at 07:05 UTC today. Under the rules that is a stop for the day, with no retry, no other agent and
no mirror (the BigQuery copy is out under the no-BigQuery rule). The names design (state gradients from local
relevance, known positives such as Kizzy after Roots in 1977) will be registered in an addendum before it runs on a
later day.

## 9. The bar

The scan passes only if all three hold:

1. **Recover a published positive:** at least one of the two arm-A marks (13 Reasons Why, Robin Williams) is graded
   measured under v2.
2. **Two new measured marks:** at least two arm-B scan marks (every arm-B mark except the two documented positives)
   are graded measured under v2.
3. **Decoys at or under nominal:** of all decoy windows across both arms, at most 5% are graded measured under v2. The
   rung-1-only rate and each mark's decoy count are reported beside it.

A failed part is reported as failed, with the diagnosis. Nothing found here changes the demo page.

## 10. Reporting

- Raw counts beside every behavior result: the window sums (the same months that enter the effect), the pairs dropped,
  and yearly totals. For WONDER, any count of nine or fewer is withheld.
- Every mark gets one plain line: what was measured, the change, p and its floor, the control rank, the gradient.
- Suicide results are reported in aggregate, with care, with the published studies named, and with the 988 Suicide and
  Crisis Lifeline in the results document.
- Network: honest UA, at least 1.1 s between requests (2 minutes between WONDER queries), a host stopped for the run
  on any 4xx or 5xx with no same-day retry (the ladder's fetcher; stops are written to `stopped_hosts`), no keys, no
  accounts, no BigQuery, no paid APIs. `LADDER_SKIP_HOSTS="www.ssa.gov|HTTP 403"` carries today's stop.
- Any change after this commit goes into a dated addendum below, labeled late, before the result it affects is read
  where possible.

## 11. Limits known now

- WONDER through the API is national only, so the suicide marks cannot use a state gradient; age and method category
  are the exposure dimensions. Monthly youth counts are about 100 deaths, so one month moves about 10% by chance.
- The 13 Reasons Why finding is disputed; recovering it under v2 would not settle that dispute.
- NPS counts are partly estimates, and counting methods change by unit and year; a method change in the window can
  look like a rise. The decoys are the check.
- A film's "featured unit" is a judgment fixed here before data; a stone can draw visitors to a nearby place that is not
  an NPS unit.
- Twelve-month windows from 1979 data give 1990s stones about 100 to 200 placebo windows, heavily overlapping.
- Synthetic calibration shows rungs 2 and 3 do little against pure noise; their job is confounds.

## Addendum 1, Oct 5, 2026, 07:55 UTC (late: after run 1, before any NPS value was read)

Run 1 (07:29 to 07:52 UTC, 121 requests, every one answered 200, no host stopped) parsed no NPS unit: the visitation
operation answers in XML (`ArrayOfVisitationData`), and the registered parser read JSON only, so all 32 arm-B marks came
out "not run". Run 1's printed summary showed the arm-A and re-test grades; no arm-B value had been parsed or read.

Fix, parser only: `nps_rows` reads the XML (and still reads JSON). Writing it showed a second parser fault that would
have mattered: each record carries both `NonRecreationVisitors` and `RecreationVisitors`, and the registered key match
("recreation" and "visit" in the name) would have taken the first, the non-recreation count. The match now requires the
name to start with "recreation". The registered outcome (monthly recreation visits) is unchanged.

Run 2 reads every response from run 1's local cache: no new request to any host, except that the conditional Close
Encounters design (section 7.2) now runs if the cached 1977 totals response carries per-unit values, which run 1 could
not read; if it does, run 2 requests the annual totals for 1955 to 1990, as registered. Nothing else changes: stones,
pools, groups, windows, the test, the decoys and the bar are as committed in 01b0a09.
