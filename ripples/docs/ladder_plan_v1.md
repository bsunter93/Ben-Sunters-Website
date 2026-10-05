# Evidence ladder v1: placebo-date tests for the engine's marks (pre-registered)

*Written Oct 4, 2026, before any outcome value was fetched. The test code, `ripples/lab/ladder.py`, is committed with
this file. Results will go to `ripples/docs/results/ladder_v1.json` and `ripples/docs/ladder_v1.md`. Two owner
additions arrived before this commit and are part of the registration: the comparison rung built from matched control
stones (section 7) and the negative-space list (section 10).*

## 1. Question

All 102 engine-found marks in `ripples/demo/discovered_wiki.json` are graded *reported*: a public record names the link.
None is measured. For every mark whose own outcome has a data series, can the placebo-date test move it up the ladder?

- **measured:** the change after the stone is unusual against the series' own history (p ≤ .05) and in order.
- **timed:** the outcome began to move inside the window the record names, after the stone, but the change was not
  unusual enough to pass the placebo test.
- **busted:** the rise began before the stone.
- Otherwise the mark stays **reported**: the citation still stands, the series did not move, and the result is recorded
  in the negative-space list.

A grade from this test says only that an unusual rise happened, in the right order. It does not say the stone caused
it. Attention (Wikipedia pageviews) is never used to grade a behavior mark.

## 2. What was read before this registration (metadata only)

Every request used the project's user agent at least 1 second apart. None returned an outcome value.

| Time (local, Oct 4, 2026) | Request | Status | What it showed |
|---|---|---|---|
| 23:05 | `data.ssb.no/api/v0/en/table/08403` | 200 | table structure only (guest nights by purpose; not by residence) |
| 23:05 | `data.ssb.no/api/v0/en/table/?query=...` (twice) | 200 | the table list; 08402 is hotels by guests' country of residence, 1985M01 to 2019M12 |
| 23:05 | `data.ssb.no/api/v0/en/table/08402` | 200 | variable codes: region (0 = whole country; 12 Hordaland, 14 Sogn og Fjordane, 15 Møre og Romsdal), residence (00000 total, ccc foreign total), months |
| 23:05 | `www.gov.uk/api/content/.../family-food-datasets` | 200 | the attachment list; "UK - household purchases" is an .ods file (not downloaded) |
| 23:06 | `comtradeapi.un.org/public/v1/getDA/C/A/HS?reporterCode=842` | 200 | US annual HS data are available from 1991 |
| 23:06 | `www.ucas.com/...end-cycle-data-resources-2018` | **404** | a guessed page address; under the project's stop rule (any 4xx or 5xx) no further UCAS request today |
| 23:07 | `hansard-api.parliament.uk/search/contributions/Spoken.json` (term "Speaker", Jan 2000) | **500** | a coverage probe; stopped, no same-day retry |
| 23:10 | `www.wikidata.org/w/api.php?action=wbgetentities` | 200 | US release dates of three control films (Mean Girls, The Devil Wears Prada, Ratatouille) |

The onset rule in section 4.3 was adjusted after a dry run on **synthetic** series (random noise with a seasonal shape),
before any real outcome value was read. Section 4.3 gives the reason and the calibration.

## 3. Inventory: which of the 102 marks have a series that measures the mark's own outcome

| Decision | Marks |
|---|---|
| Testable and run in this registration | 3 (Frozen → Norway tours; The Great British Bake Off → baking sales; Finding Nemo → demand for reef fish) |
| Testable, registered now, blocked today | 2 (Blue Planet II → marine biology applications; Blue Planet II → the plastics turn) |
| A dated record (law, regulation, treaty, institution, policy, ruling, launch), not a series | 87 |
| No reachable series that measures the mark's outcome | 4 (carbon offsets, Dalmatian sales, the Sideways effect, the Top Gun claim) |
| No reachable series, and the window falls in an excluded period | 1 (chess-set sales) |
| The window falls in an excluded period | 1 (the suit revival, 2008) |
| A share or a level, not a change | 3 (Northern Ireland tourism; Bethel Woods visitors; Paris tourism, also in the closure months) |
| Needs an owner action first | 1 (13 Reasons Why: CDC WONDER requires accepting data-use terms) |
| **Total** | **102** |

There are no baby-name marks among the 102 (the culture shelf left the name marks out because the record left them
undated), so the SSA files, the easiest series to test, have nothing to grade here.

### Marks with a possible outcome series or a special reason (17)

| Stone | Mark (id) | Kind | Dated | Decision | Reason |
|---|---|---|---|---|---|
| An Inconvenient Truth | Carbon-offset purchases (w2) | Behavior | 2006 | no reachable series | the 2011 study used purchase records by zip code that are not public; the voluntary carbon market's annual volumes begin in 2005-06 and are published as reports, with no history before the film |
| Deepwater Horizon | GuLF Study (w1) | Public health | 2010-06 | a dated record | the GuLF Study's founding is a dated record, not a series |
| Frozen | Norway tours (w0) | Behavior | 2014 | testable | Statistics Norway table 08402: foreign guests' hotel nights, monthly since 1985 |
| Game of Thrones | Northern Ireland tourism (w0) | Behavior | 2019 | a share, not a change | the record states a share of tourists in one year (2019); a change test needs a window the claim does not give |
| Finding Nemo | Demand for reef fish (w0) | Behavior | 2003 | testable | UN Comtrade: US imports of live ornamental fish (HS 030110), annual since 1991 |
| 101 Dalmatians | Dalmatian sales (w0) | Behavior | 1997 | no reachable series | the American Kennel Club publishes breed ranks, not a registration-count series; no official puppy-sales series exists |
| Sideways | The Sideways effect (w0) | Industry | 2005 | no reachable series | wine sales by variety are scanner data (proprietary); the public California grape crush report measures grape supply and prices, not wine sales, so it is a different mark |
| The Queen's Gambit | Chess set sales (w0) | Industry | 2020 | no reachable series; excluded period | no public series of chess-set sales; the stone (Oct 2020) and its window fall inside the pandemic closure months |
| Top Gun | The 500% recruitment claim (w0) | Behavior | 1986 | no reachable series | no public series of naval aviator applications; the mark stays disputed |
| Avatar | 3D televisions (w0) | Industry | 2010 | a dated record | a product launch (3D televisions at CES 2010) is a dated record; a new product category has no history before the stone |
| Mad Men | The suit revival (w0) | Industry | 2008 | excluded period | the mark's year (2008) falls inside the 2008-09 financial crisis, which the project excludes; the nearest series (men's clothing store sales) is broader than suits |
| The Great British Bake Off | Baking sales (w0) | Industry | 2011 | testable | Defra Family Food: UK household purchases of flour per person per week, annual since 1974 |
| Woodstock | Bethel Woods visitors (w0) | Industry | 2006 | a level, not a change | the record states a visitor count for a venue that opened in 2006, 37 years after the stone; there is no series before the stone |
| 13 Reasons Why | Teen suicide study (w0) | Public health | 2017-04 | needs owner action | the monthly youth suicide series (CDC WONDER) can be queried only after accepting CDC's data-use terms, which this run may not do on the owner's behalf; the published study is already disputed |
| Blue Planet II | Marine biology applications (w0) | Education | 2018 | testable, blocked today | UCAS applications by detailed subject (section 6.1) |
| Blue Planet II | The plastics turn (w1) | Policy | 2020 | testable, blocked today | Hansard spoken contributions: political interest as a record count, not pageviews (section 6.2) |
| Emily in Paris | Paris tourism (w0) | Behavior | 2024 | a share, not a change; excluded period | the record states a survey share (2024), and the stone (Oct 2020) falls inside the pandemic closure months |

### Dated records, not series (85)

Reason for every mark below: a dated public record, not a series. The record itself dates the mark, and there is no
outcome series to test.

- **Institution** (34): Love Canal w0 (ATSDR); Love Canal w1 (LCARA); The Exxon Valdez w0 (Alaska Oil Spill Commission); Flint w1 (Child Lead Exposure Elimination Commission); Flint w2 (BlueConduit); Fukushima w0 (Korea's NSSC); Fukushima w1 (NAIIC); Fukushima w2 (Reconstruction Agency); Fukushima w3 (Nuclear Regulation Authority); An Inconvenient Truth w0 (The Climate Reality Project); Deepwater Horizon w0 (National Commission); Deepwater Horizon w2 (National Ocean Council); Deepwater Horizon w3 (BSEE); September 11 w0 (9/11 Victim Compensation Fund); September 11 w2 (TSA); September 11 w6 (Department of Homeland Security); Chernobyl w1 (UN Chernobyl Trust Fund); Chernobyl w2 (Chernobyl Children International); Chernobyl w3 (Chernobyl Shelter Fund); Bhopal w1 (International Medical Commission on Bhopal); Challenger w0 (Rogers Commission); Challenger w1 (Challenger Center); Challenger w2 (NASA Office of Safety); Parkland w0 (Never Again MSD); The Boston Marathon bombing w0 (One Fund Boston); The Pulse shooting w0 (OneOrlando Fund); The Pulse shooting w1 (OnePulse Foundation); Cambridge Analytica w0 (Social Science One); The Camp Fire w2 (PG&E Fire Victim Trust); Grenfell w0 (Grenfell Tower Memorial Commission); Cathy Come Home w0 (Crisis); Jurassic Park w0 (The Toronto Raptors' name); Hamilton w0 (Hamilton Education Program); Tetris w0 (The Tetris Company).
- **Law** (35): 60 Minutes w0 (STOCK Act); The West Wing w0 (Racial and Religious Hatred Act 2006); Silent Spring w0 (NEPA); Sputnik w0 (National Defense Education Act); The Exxon Valdez w1 (Oil Pollution Act of 1990); Columbine w0 (New Jersey anti-bullying law); The anthrax letters w0 (Patriot Act); Sandy Hook w0 (NY SAFE Act); Sandy Hook w1 (Connecticut's gun law); Sandy Hook w2 (Connecticut FOIA change); September 11 w1 (Patriot Act); September 11 w3 (UK Anti-terrorism, Crime and Security Act); September 11 w4 (Canada's Anti-terrorism Act); September 11 w5 (New Zealand's Terrorism Suppression Act); September 11 w7 (JASTA); Bhopal w0 (Bhopal Gas Leak Disaster Act); Rana Plaza w1 (Factory-inspection law); The Oklahoma City bombing w0 (AEDPA); The Oklahoma City bombing w1 (Victim Allocution Clarification Act); The Virginia Tech shooting w0 (NICS Improvement Amendments Act); Parkland w1 (Florida's MSD Public Safety Act); Parkland w2 (STOP School Violence Act); Parkland w3 (Florida's death-penalty unanimity repeal); Uvalde w0 (New York's age-21 law); Uvalde w1 (Bipartisan Safer Communities Act); Uvalde w2 (Texas training law); Uvalde w3 (Texas HB 3); Enron w0 (Tax code section 409A); Enron w1 (UK Companies (Audit, Investigations and Community Enterprise) Act); MeToo w0 (Indonesia's Sexual Violence Crime Act); The Camp Fire w0 (Chico's price-gouging ordinance); The Camp Fire w1 (California's wildfire fund (AB 1054)); Dear Zachary w0 (Bill C-464); Hurricane Sandy w0 (Sandy aid law); Pokémon Go w0 (New York's parole rule).
- **Legal** (1): An Inconvenient Truth w1 (The Dimmock ruling).
- **Policy** (8): Deepwater Horizon w4 (BP contracting ban); Rana Plaza w0 (The Bangladesh Accord); The Boston Marathon bombing w1 (One Boston Day); Pokémon Go w1 (Iran's ban); Fifty Shades of Grey w0 (Malaysia's ban); The Da Vinci Code w0 (Indian state bans); Furby w0 (The NSA's Furby ban); Zumba w0 (Iran's ban).
- **Regulation** (4): Flint w0 (Lead and Copper Rule revisions); The Las Vegas shooting w0 (Bump-stock ban); Lac-Mégantic w0 (FRA Emergency Order 28); Dieselgate w0 (Switzerland's sales ban).
- **Treaty** (3): The Day After w0 (INF Treaty); Chernobyl w0 (Early Notification Convention); Chernobyl w4 (Joint Convention).

## 4. The test (the same for every mark)

### 4.1 Effect and placebo pool

The series is taken in logs. The **effect** at reference period *r* is the mean of the *h* periods from *r* minus the
mean of the *h* periods before it (chain_check's series test). Monthly series use h = 12, so every window holds one of
each calendar month and seasonality cancels; month-of-year matching of placebos is therefore not needed. Annual series
use h = 1.

- **Reference period.** Monthly: the month that contains the stone's date (chain_check's convention). Annual: the year
  the record dates the change, never earlier than the stone's year (Bake Off 2011, Finding Nemo 2003). The record's own
  year fixes the window before any data is read.
- **Placebo pool.** Every window of the same length that lies wholly before the stone's period and more than 2h periods
  from the reference. This is the wiki test's design (placebos from the series' own history before the step). It
  departs from chain_check's series test, which also draws placebo dates from after the step.
- **p** = (1 + placebo effects at least as large, in the claimed direction) / (1 + N).

### 4.2 Excluded periods and breaks

- Excluded: the 2008-09 financial crisis (Sep 15, 2008 to Jun 30, 2009) and the pandemic closure months (Feb 15,
  2020 to Jun 30, 2021). A month is excluded if it touches either span; a year (or fiscal year) is excluded if any of
  its days do. A window that touches an excluded period is dropped from the placebo pool. A real window that touches one
  is not tested (that is why Mad Men, The Queen's Gambit and Emily in Paris are untestable).
- Breaks: a change across a definition break is not comparable, so a window that spans one is dropped. For Defra's
  Family Food file, a change between a calendar year and a fiscal year is a break: the survey change from the National
  Food Survey to the Expenditure and Food Survey (1974-2000 to 2001-02), fiscal to calendar years (2005-06 to 2006),
  and calendar to fiscal years (2014 to 2015-16). A fiscal year "YYYY-YY" is assigned to year YYYY. A missing year in
  any annual series is also a break.

### 4.3 Onset and the ordering rule

The ordering rule (ledger 1497) needs an onset: the first period, searched from 2h before the reference to 3h after
it, where the series departs from its pre-trend by more than 2 SDs for 2 periods running, in the claimed direction.

chain_check fits a linear trend to the 4h periods before the search starts. With h = 12 on a seasonal monthly series,
that means a 48-month fit with month terms, extrapolated up to 60 months. On synthetic decoys (noise plus a seasonal
shape) it flagged a false onset (busted or timed) at about a third of random dates. The rule is therefore registered in
two forms, chosen on synthetic data only:

- **Monthly:** z = the year-over-year log change. Baseline = the mean and SD of z over the 48 admissible months before
  the search starts. Onset = the first month where z exceeds the baseline mean by more than 2 SDs for 2 admissible
  months running. A level shift appears in z for 12 months from its first month, so the onset is dated to its start.
- **Annual:** chain_check's rule (log level against a linear pre-trend, 2 residual SDs, 2 years running), with the
  trend fitted on the 10 admissible years before the search starts instead of 4. The fit never reaches back across a
  survey break (for Defra, the 2001-02 survey change; the fiscal and calendar switches inside one survey do not bound the
  fit).

Calibration on synthetic noise (400 random dates per row; no real data):

| Synthetic series | measured | timed | busted |
|---|---|---|---|
| monthly, AR(0.5) noise, seasonal | 6.2% | 1.7% | 7.3% |
| monthly, AR(0.8) noise, seasonal | 5.5% | 6.1% | 12.2% |
| annual, AR(0.5) noise | 2.8% | 4.0% | 4.0% |
| annual, AR(0.8) noise | 2.2% | 5.0% | 5.2% |

These are the rule's false rates when nothing happened. The decoys in section 9 measure the same rates on the real series.

**Tolerance** (chain_check's): one period. An onset earlier than the stone's date minus one period (31 days for
monthly, 365 days for annual, with points dated the first day of the period) began before the stone.

### 4.4 Grade map (applied in this order)

1. **busted:** the effect is in the claimed direction and the onset is before the stone (after tolerance), whatever p is.
2. **measured:** the effect is in the claimed direction and p ≤ .05 (the onset is after the stone, or none was found;
   chain_check's convention).
3. **timed:** the effect is in the claimed direction, p > .05, and an onset falls inside the outcome window: from the
   stone (after tolerance) to the window's last period.
4. Otherwise the mark stays **reported** and joins the negative-space list.

Nothing is shown as measured unless it comes from this test. The grade does not change the product in this pull
request: `ladder_v1.json` proposes grades, and promoting any of them on the page is a separate step for the owner.

### 4.5 Power floor

With N placebo windows the smallest possible p is 1/(N + 1). Below N = 19 a mark cannot reach p ≤ .05 and can at best
be timed. Finding Nemo has about 9 windows (US annual trade data begin in 1991), so it cannot be measured by this
design however large its rise. That is stated now so that a "timed" Nemo is not read as a near miss.

## 5. The marks run now

### 5.1 Frozen → "Tour operators add Norway tours to meet demand" (2014)

- **Series:** Statistics Norway table 08402, hotels and similar establishments, guest nights, region "The whole
  country" (0), country of residence "Foreign national, total" (ccc), monthly, 1985M01 to 2019M12.
  Source: `https://data.ssb.no/api/v0/en/table/08402` (one POST, json-stat2).
- **Window:** reference Nov 2013 (release Nov 27, 2013). Nov 2013 to Oct 2014 against Nov 2012 to Oct 2013. Up.
- **Placebo pool:** every month from Jan 1986 to Sep 2007 and from Jul 2010 to Oct 2011 (windows touching the crisis
  dropped): N = 277 if no month is missing.
- **Onset:** the monthly form. Busted if the onset is Oct 2013 or earlier; timed if it falls between Nov 2013 and Oct 2014.
- **Broader context (not graded):** all guest nights in Norwegian hotels (residents and foreigners), the same test.
- **Exposure gradient (not graded):** section 8.
- **What else was going on:** the Norwegian krone weakened in 2014; the gradient compares regions inside Norway, which
  share the currency.

### 5.2 The Great British Bake Off → "UK shops report sharp rises in sales of baking ingredients and equipment" (2011)

- **Series:** Defra Family Food datasets, "UK - household purchases" (.ods), the row whose label is "Flour" (a unit in
  parentheses is allowed) under the first header row that carries at least 10 year labels; quantity purchased per person
  per week, one value per survey year. Located through `https://www.gov.uk/api/content/government/statistical-data-sets/family-food-datasets`.
  Flour is the registered baking ingredient: it is bought almost only for home baking. Equipment has no series.
- **Window:** 2011 against 2010 (first series Aug 17, 2010; the record dates the rise to 2011). Up.
- **Placebo pool:** every year-on-year change from 1975 to 2007 except the two that span a break (2001-02 against 2000;
  2006 against 2005-06); 2008 and 2009 are excluded. N = 31 if every year from 1974 is present.
- **Onset:** the annual form; the trend is fitted on 2001-02 to 2007 (2008 excluded, the survey break bounds the fit).
  Busted if the onset is 2009 or earlier. 2009 is excluded, so in practice the ordering check starts in 2010. This is a
  known limit, stated now. Timed if the onset is 2010 or 2011.
- **Broader context:** none registered. The same file has no total quantity across foods.

### 5.3 Finding Nemo → "Demand for tropical aquarium fish rises after the film" (2003)

- **Series:** UN Comtrade public preview (no key), reporter USA (842), partner World (0), imports, HS 030110 (live
  ornamental fish), customs code C00, mode of transport 0, annual, 1991 to 2016, trade value in US dollars. Source:
  `https://comtradeapi.un.org/public/v1/preview/C/A/HS`. Net weight and quantity are kept as raw values beside it. HS
  030110 is unchanged from HS 1988/92 through HS 2012. It was split in 2017, which is outside every window used here.
- **Window:** 2003 against 2002 (release May 30, 2003; the record dates the rise to 2003). Up.
- **Placebo pool:** year-on-year changes from 1992 to 2000. N = 9; the floor is p = 0.1 (section 4.5).
- **Onset:** the annual form; the trend is fitted on 1991 to 2000. Busted if the onset is 2002 or earlier; timed if it is 2003.
- **Broader context (not graded):** US imports of HS chapter 03 (all fish and crustaceans), the same test.
- **Known counter-record:** the mark's own note cites a 2019 study of sales after Finding Dory that found no increase.

## 6. Registered now, run later (hosts stopped today)

These two designs are fixed now. They run on a later day under this registration. Before any value is read, an addendum
will name the exact table (UCAS) or confirm the endpoint (Hansard), without changing the design.

### 6.1 Blue Planet II → "British universities see a sudden rise in marine biology applications" (2018)

- **Series:** UCAS undergraduate end-of-cycle applications to the detailed subject group that holds marine biology
  (JACS C160 or its successor group), UK domicile, annual application cycles.
- **Window:** the 2018 cycle against the 2017 cycle (broadcast from Oct 29, 2017). Up. Annual form of the onset rule.
- **Placebo pool:** every earlier cycle's change. The addendum states its size, and so the floor, before any value is
  read. If N < 19, timed is the best possible grade.
- **Controls (section 7):** Forks Over Knives (2011), Cowspiracy (2014), Planet Earth II (2016), What the Health (2017).

### 6.2 Blue Planet II → "lasting political and public interest in plastic pollution" (2020 study)

- **Series:** UK Parliament Hansard API, spoken contributions (both Houses) per month containing the phrase "plastic
  pollution", divided by contributions per month containing "Government" (a denominator that follows sitting days,
  recesses and elections), Jan 2005 to Dec 2019. Only the political half of the mark is tested. Public interest would
  mean attention data, which this ladder does not use.
- **Window:** reference Oct 2017, h = 12, up; monthly form of the onset rule; placebo pool as in 4.1.
- **Controls:** the four documentaries in 6.1.

## 7. Comparison rung: counterfactual catalysts (owner addition)

For each tested mark, the same effect is computed after each matched **control stone**: a stone already in the repo
(`ripples/lab/discovery/culture_stones.py`, the 132 stones chosen as recognizable to a very large population, so
popularity is matched by construction) of the same kind, released within 10 years of the real stone, with no link to
the outcome. A control's window must lie inside the series, be clear of excluded periods and breaks, and not overlap the
real window. Otherwise the control is dropped and the drop is reported. Annual controls use the real pair's lag (Bake
Off: the year after release; Nemo: the release year). Monthly controls use their US release date.

**p_comparison** = (1 + controls with an effect at least as large) / (1 + n), with the real stone's rank. It is shown
beside the grade and does not change it. Controls released in the same year share one window on an annual series, so
this rung is a placebo-in-time test at comparable stones' dates. It is a weak test, and the report will say so.

| Mark | Controls (kind; date) | Left out, and why |
|---|---|---|
| Frozen → Norway | feature films: Finding Nemo (May 30, 2003), Mean Girls (Apr 30, 2004), Sideways (Oct 22, 2004), The Devil Wears Prada (Jun 30, 2006), Ratatouille (Jun 29, 2007), Black Panther (Feb 16, 2018) | Twilight (2008) and Avatar (2009): windows touch the crisis; The Hunger Games (2012): overlaps Frozen's window; Barbie (2023): after the series ends; Titanic (1997): more than 10 years away; books are a different kind |
| Bake Off → flour | TV series: American Idol (2002), Peaky Blinders (2013), Love Island (2015), Narcos (2015), The Crown (2016), Stranger Things (2016), Fleabag (2016), 13 Reasons Why (2017), Money Heist (2017), Dark (2017) | Chef's Table, Salt Fat Acid Heat, The Bear: food link; Survivor (2000): window spans a break; Mad Men, Keeping Up with the Kardashians, Breaking Bad, Jersey Shore: windows touch the crisis; Downton Abbey, Game of Thrones: overlap the real window; 2018-2020 series: windows touch the closure months |
| Finding Nemo → reef fish | feature films: Jurassic Park (1993), The Lion King (1994), Toy Story (1995), Babe (1995), Clueless (1995), Titanic (1997), The Blair Witch Project (1999), The Devil Wears Prada (2006), Ratatouille (2007), The Hunger Games (2012), Frozen (2013) | Free Willy (1993): marine-animal link; Mean Girls, Sideways (2004): overlap the real window; Twilight, Avatar: crisis |

## 8. Exposure gradient (Frozen)

The record's tours sell Norway's fjord landscape. The fjord sightseeing counties are Hordaland, Sogn og Fjordane and
Møre og Romsdal (table 08402 regions 12, 14 and 15). If the film drew foreign visitors, their nights should rise more
there than in the rest of Norway. Statistic: the same 12-month change in log(foreign nights in the three counties /
foreign nights in the rest of Norway), against the same pre-stone placebo pool. Reported with raw nights for both parts,
not graded. Currency and other national shocks hit both parts. No other tested mark has a gradient in the same table.

## 9. Decoys: the marks paired with wrong stones

Each tested mark's series is re-tested at the date of every other engine stone in `discovered_wiki.json` that the
series can test. The decoy reference uses the same rule as the real one (monthly: the decoy's date; annual: the decoy's
year plus the real pair's lag). The decoy window must leave 6h periods before it for the trend, fit inside the series,
be clear of excluded periods and breaks, and not overlap the real window. Decoys with the same window are counted once.
Engine stones with a link to the outcome are left out, named now:

- Norway tourism: September 11 (a direct shock to international travel) and the anthrax letters (same month).
- Flour: none.
- Ornamental fish: Blue Planet II (marine life), Deepwater Horizon (Gulf marine life and fisheries), Fukushima (the fish
  trade). Engine stones in the same year as a left-out stone share its window and are dropped too.

From the series coverage known now, the expected decoy windows are about 27 for Norway (29 stones), 19 for flour
(36 stones) and 11 for ornamental fish (21 stones). The realized lists depend on which periods the files contain and
are reported in full. Every decoy gets the full grade map. The report gives the share of decoys graded measured, timed
and busted, next to the synthetic false rates in 4.3. A decoy graded measured is a false confirmation of this design.

## 10. Negative space (owner addition)

A tested mark that stays reported, meaning the record says the outcome rose and the series did not move beyond its own
history, is a finding, not a failure. Each one goes in a separate `negative_space` list in `ladder_v1.json` with the
effect, p, raw values and, where registered, the broader series beside it. That shows whether the mark's own outcome was
flat while a broader one rose (Norway: all hotel nights; Nemo: all fish imports). The blocked and untestable marks are
not negative space. They were not tested.

## 11. Outputs

- `ripples/docs/results/ladder_v1.json`: `marks[slug][id]` for all 102 marks. Fields: testable, category, reason,
  current_grade, proposed_grade. For a tested mark it also holds series, source_url, test, p, n_placebo, p_floor,
  onset, effect (log and percent), window, raw values, comparison, gradient, broader, and a one-line
  `what_was_measured`. Top-level lists: `negative_space`, `decoys` (per mark), every request made with its status,
  `stopped_hosts`, and a summary.
- `ripples/docs/ladder_v1.md`: how many of 102 were testable, how many moved, how many busted, the decoys, and the limits.
- Run: `python3 ripples/lab/ladder.py` with `LADDER_PLAN_SHA` set to this commit.

## 12. Deviations

Any change after this commit is written in an addendum below, dated, with its reason. A change to how a file is read is
allowed only if it does not change the series, the window, the placebo pool or the grade map, and it is disclosed. A
failed fetch or parse is reported as a failure for that mark. No series is swapped after the data are seen.

## Addendum 1, Oct 4, 2026, 23:30 PDT (after run 1, before the final run)

Registration commit: `cd10fdf` (23:21 PDT). Everything below came after it and is disclosed as a deviation. None of it
changes a real mark's series, window, placebo pool or grade map.

1. **Run 1** (the registered code, about 23:22 PDT): Statistics Norway POST 200; gov.uk content API 200; the Defra .ods
   200; UN Comtrade preview **400** on its first request. The Comtrade host was stopped for the day under the rule
   (any 4xx or 5xx), so Finding Nemo was not run. Frozen: p = .2122, stays reported. Bake Off: p = .0312, measured.
2. **Parse gap, fixed.** Defra writes fiscal years from 2015-16 on as six digits ("201516"). The registered pattern read
   only "YYYY-YY" and "YYYY/YY", so run 1's flour series stopped at 2015. The file also has a calendar 2015 column
   before 2015-16; section 4.2 assumed the switch ran 2014 to 2015-16. The fix reads six-digit labels as fiscal years.
   The code's existing break rule (a fiscal/calendar switch, or a year that does not follow the one before) puts a
   break between calendar 2015 and fiscal 2015-16. The real window (2010 to 2011), its 31 placebo changes (1975 to 2007)
   and its trend fit (2001-02 to 2007) do not touch those years: p, onset and grade are identical in run 1 and the
   final run. The fix restores the controls and decoys after 2015 that section 7 lists.
3. **One more definition break, from the file's own notes:** "Weighting changed to all expenditure from 202324
   onwards." A change into 2023-24 is treated as not comparable. It affects one decoy window only (Uvalde), which is
   dropped.
4. **Diagnostic request:** one re-download of the .ods at 23:23 PDT to read its header row and notes.
5. **Correction to section 5.1's context sentence.** The plan said the krone weakened in 2014. FRED series EXNOUS
   (one request, 23:24 PDT) shows about 6.0 kroner per dollar from Jan 2013 to Aug 2014 (5.55 to 6.20), then a fall
   from Sep 2014 to 8.70 by Dec 2015. Frozen's outcome window (Nov 2013 to Oct 2014) is mostly before the fall. The large
   rise in foreign nights in 2015 and 2016 coincides with it.
6. **Late and exploratory, not graded:** `late_check_both_sides` gives p with chain_check's own series-test pool, which
   also draws placebo windows from after the stone. It was added after run 1 because the flour series swings more after
   2011 than before. It changes no grade.
7. **Display only:** `decoy_calibration` copies each tested mark's decoy counts beside its result.
8. **Runs 2 and 3.** Run 2 (23:25 PDT) fetched the Statistics Norway table and the gov.uk listing again (2 requests,
   both 200) and read the .ods from the local copy. Run 3 made no request: all three bodies came from the local copy
   of that day's responses. Run 3 is the run in `ladder_v1.json`. Comtrade, UCAS and Hansard received no request after
   their first refusal.
9. **For the next run of Finding Nemo** (another day, under this registration): the 400 most likely came from a
   parameter the preview endpoint rejects for these years (the extended partner2, customs and transport filters, or six
   periods in one call). The next attempt will make one request per year without those filters. That is the same
   series (US imports from the world, HS 030110, trade value) and the same design. An addendum will be committed before
   it runs.
