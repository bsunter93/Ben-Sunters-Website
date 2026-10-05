# Sensors v1: independent attention sensors for the checker (pre-registration)

**Registered:** Oct 4, 2026, before any request to GDELT or Media Cloud. **Queries:** `ripples/lab/sensors_queries_v1.json`
(the exact query for every step and sensor; the tables below are generated from it). **Results will go to:**
`ripples/docs/results/sensors_v1.json`, `ripples/docs/results/sensors_mediacloud_v1.json` and `ripples/docs/sensors_v1.md`.

## 1. Why

Almost every *measured* link in Ripple rests on one sensor: daily Wikipedia pageviews, which begin in July 2015. One
sensor cannot tell a real rise in public attention from something peculiar to Wikipedia (a Main Page slot, a bot, a
search-engine change), and nothing before mid-2015 can be measured at all. This pass adds three sensors that do not share
Wikipedia's plumbing and asks three questions:

1. **Convergence.** Of the 13 measured Wikipedia attention steps, how many also rise beyond chance, in order, on an
   independent sensor? How many are Wikipedia-only?
2. **Reach.** Which dated steps before August 2015 become testable for the first time?
3. **Catalysts.** Can an abrupt change in an entity's coverage, judged against the entity's own history, propose new
   stones?

## 2. Sensors and what each source allows (from its documentation, read Oct 4, 2026)

| Family | Sensor | Coverage | Unit per day | Limits we keep |
|---|---|---|---|---|
| W | Wikipedia pageviews (already in the repository) | Jul 1, 2015 on | views of the named articles | no new fetch; the stored results in `chain_check_v1.json` and `demo/discovered.json` are the comparison |
| N | GDELT DOC 2.0, `timelinevolraw` | Jan 1, 2017 on (the debut post: data "back to January 1, 2017"); daily steps for spans over a week | matching English-language online news articles, with the day's total monitored articles | no key; one request every 6 s (GDELT asks for no more than one every 5 s); run locally |
| T | GDELT TV 2.0 over Internet Archive closed captions, `timelinevol` (percent of monitored 15-second clips) and `timelinevolnorm` (total clips) | Jul 2, 2009 on (BBC News from Jan 1, 2017); daily steps only for spans under 3 years, so a long history is fetched in chunks under 3 years | percent of monitored 15-second caption clips on the chosen stations, and the derived clip count | no key; one request every 6 s; run locally |
| N | Media Cloud online news, `search/count-over-time` | from when each source's feed was first collected; coverage is read from the daily totals the API returns, not assumed | matching stories in a national collection, with the collection's total stories that day | the repository secret only, used only by the workflow `ripples-sensors.yml`; requests paced at the slower of the server's declared rate and 2 a minute (the FAQ: "Certain API endpoints are rate-limited to 2 requests per minute"); at most 2,000 requests for this task |

The GDELT Global Knowledge Graph (themes and named entities; GKG 2.1 began Feb 18, 2015) lives in BigQuery for history.
The project rule is no Google billing, so BigQuery is not used. The DOC API already searches the full text that the GKG is
built from, so no raw 15-minute files are needed for this pass.

**Families and independence.** Wikipedia (W), online news (N) and television (T) are three families with separate
collection. GDELT DOC and Media Cloud are both online news and are not independent of each other: GDELT DOC is the
primary news sensor; Media Cloud is reported as a replication, and counts for the news family only where GDELT DOC is not
testable for that step.

**Stations and collections.** A US step is read on the three US cable news channels in the archive since 2009 (CNN,
MSNBC, Fox News) and in Media Cloud's "United States - National" collection (34412234). A UK step (Mr Bates, Ocean,
Adolescence, Saltburn, Bridgerton's Ranger's House) is read on the BBC News channel and in Media Cloud's "United Kingdom -
National" collection, found by name in the directory by the workflow; if no collection has that exact name, UK steps use
the US collection and are flagged. GDELT DOC is read across all English-language sources for every step (suffix
`sourcelang:english`).

**Rules for every request.** User agent `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`; at most one
request a second and slower where a source asks; a 401, 403, 429 or any 5xx (or GDELT's plain-text rate-limit notice)
stops that source for the day, with no retry, no other agent and no workaround. Aggregate counts only: no article lists,
no story text, no URLs are stored.

**Fetch plan.** GDELT DOC: one request per unique query, Jan 1, 2017 to Sep 30, 2026 (about 160 requests). Television:
for a step after August 2015, from Jul 1, 2015 (Wikipedia's own start, so the two placebo histories match) through the
step's window; for set D, from Jul 2, 2009; BBC News from Jan 1, 2017; in fixed chunks under 3 years, plus one
`timelinevolnorm` request per station group and chunk for the day's total clips (about 350 requests). For the catalyst
panel, television is fetched only around candidates. Media Cloud: one `count-over-time` request per unique query and
collection over the same spans (about 170 requests), plus one directory lookup and one read of the server's declared rate;
the workflow runs once, writes daily counts and the collection's daily totals to `sensors_mediacloud_v1.json`, and stops on
the first 401, 403, 429 or 5xx. If GDELT DOC refuses dates older than three months (the debut post's original limit),
GDELT DOC is reported as unavailable for history and the news family rests on Media Cloud alone.

## 3. The steps re-tested (the full query tables are in section 9)

| Set | What | Count | Reference date and window |
|---|---|---|---|
| A | every measured (13) or timed (6) Wikipedia attention step in `chain_check_v1.json`; one timed step excluded (step 1 of the Nov 30, 2022 chatbot-launch chain, see the exclusions) | 18 | the step's own reference date and lag, exactly as the checker ran it |
| A2 | record steps whose attention check rose (14 beyond chance, 7 with no placebo history); one excluded: chernobyl-zone 1, whose check measured the article "HBO", not the step's subject | 20 | the step's date, lag 45 (the checker's attention check) |
| C | the attention leads in `demo/discovered.json` | 18 | the stone's date, lag 120 (the editor trail's window) |
| D | dated steps from Jul 2, 2009 to Jul 31, 2015, television's first years (15 excluded with reasons: approximate dates, must-precede claims, steps already measured by FRED or SSA) | 42 | the step's date, lag 45 |
| E | the catalyst panel: 24 recall outcomes, 69 behavior outcomes, 10 decoy entities | 103 | scanned Jan 1, 2017 to Sep 30, 2026 |

**Queries.** Each query is the step's subject as an exact phrase in quotes, plus a disambiguator where the phrase alone
is ambiguous (for example `"wordle" (puzzle OR game OR guess)`, since a 2008 word-cloud tool shared the name;
`"chess" (grandmaster OR tournament OR chessboard ...)` for news, where chess is also a metaphor). Television captions
come in 15-second clips, too short for most disambiguators, so a television query is the phrase alone, and where the
phrase is common speech (Bloody Mary, Long Long Time) the step is not run on television, with the reason recorded.
Galaxy is dropped from the JWST step's query (Samsung's phones), and the step's other articles, astronomy and universe,
are carried by `("astronomy" OR "astronomer" OR "astronomers")`.

## 4. The test, per sensor and step (the checker's test, carried over)

The test is `chain_check.wiki_test` with `editor_trail.onset`, applied to each sensor's daily series. Let *ri* be the
reference date's index.

1. **Series.** GDELT DOC: matching articles divided by the day's total monitored articles. Media Cloud: matching stories
   divided by the collection's total stories that day. Television: the percent of monitored clips that match; the
   derived clip count is that percent times the day's total clips. Days whose total is under a quarter of the 28-day
   rolling median total (outages, missing collection) are missing, not zero.
2. **Onset.** Baseline days *e*-120 to *e*-15 with *e* = *ri*-30; the onset window runs from *e* to *ri* + lag (the checker's
   window). On the trailing 7-day mean of the share (a mean of the days present, at least 4 of 7), the onset is the first
   day of 5 running days above `max(median + 5 MAD, 1.5 x median, median + 0.2 x (window peak - median))`, **and** with
   the trailing 7-day mean of the raw count above the baseline's raw median plus a floor. The floor replaces Wikipedia's
   "+20 views": **3 articles a day** for GDELT DOC and Media Cloud, **2 clips a day** for television. Ratio = window peak
   over the baseline median, with the median floored at the share of one item on a median day (Wikipedia floors it at one
   view).
3. **Placebo (decoy dates in the series' own history).** The same detector at every 14th day of the series from index
   130 to *ri*-200, each with a valid baseline; a hit is an onset whose ratio is at least the observed one;
   p = (1 + hits) / (1 + N), reported only when N >= 20.
4. **Valid baseline.** At least 90% of baseline days present (Wikipedia's rule is 100%; news and television have outage
   days; this is the one change to the checker's test besides the floor).
5. **Sparse baseline.** If fewer than 5 days in the 365 days before the baseline's end carry any raw match, the series is
   *sparse*: the term is new or nearly unused, the placebo is degenerate, and a rise is reported as **timed (sparse)**,
   never beyond chance. This mirrors the checker's "new article" rule.
6. **Verdict.** *Beyond chance in order* = p <= 0.05, onset on or after the reference date minus 3 days, baseline not
   sparse. *Moved, wrong order* = p <= 0.05 with an earlier onset. *Within chance* = p > 0.05. *No sustained rise*,
   *timed (sparse)*, *rose, no placebo history* (N < 20) and *not testable* (no coverage for the baseline, or the window
   runs past the data) are reported as such.

**Calibration on decoy dates (per sensor).** For every step and sensor with a testable series, five decoy reference
dates are drawn (NumPy `default_rng(20261004 + crc32(step id))`, uniform over the days at least 610 days after the series
starts and at least 180 days before the step) and run through the identical test, with the placebo windows taken from
before each decoy. The share of decoys that come out *beyond chance in order* is that sensor's false-pass rate.

## 5. Convergence

- A family **passes** a step when its sensor is beyond chance in order. Wikipedia's verdict is the stored one (a step test
  of "measured", or an attention check of "attention rose"; for leads, p <= 0.05 and an onset after the stone's attention
  onset, as the editor trail ran it). The news family passes on GDELT DOC, or on Media Cloud only where GDELT DOC is not
  testable.
- A step is **confirmed** when at least two families pass. For a measured Wikipedia step that means news or television
  also passes.
- A measured step is **Wikipedia-only** when news and television are both testable and neither passes; **partial**
  when one is testable and fails and the other is not testable; **untested** when neither is testable.
- A sensor whose decoy false-pass rate exceeds 10% is reported, but its passes do not count toward convergence.
- Grades in the product do not change in this pass. A timed step that passes an independent sensor with a non-sparse
  baseline is listed as a candidate for a measured grade, nothing more.

## 6. Steps before August 2015

Set D is tested on television (from Jul 2, 2009) and on Media Cloud where its daily totals show coverage. GDELT DOC begins
Jan 1, 2017, so it adds no step before 2015; its first full placebo history (N >= 20, which needs about 610 days of
series) arrives around September 2018, so GDELT DOC cannot give a p for steps between Jan 2017 and about Aug 2018 either.
Television's first full placebo history arrives around March 2011; steps between Jul 2009 and Mar 2011 can show a rise
but no p. UK steps before 2017 have no British television in the archive and are not testable on television.

## 7. Catalyst detection (proposing new stones)

**Scan.** For each panel entity, the GDELT DOC share series from Jan 1, 2017 to Sep 30, 2026. A scan window starts every
7th day *e*; the detector of section 4 looks for an onset in *e* to *e* + 13 (baseline *e*-120 to *e*-15, the same
thresholds and floor). Onsets within 30 days of each other are one change; it is dated by its earliest onset and scored by
its largest ratio.

**Abrupt, against the entity's own history (decoy dates).** A change is a candidate when its ratio is at least 5, the
baseline is not sparse, and it beats the entity's own decoy dates: the same detector at every 14th day of the entity's
history, excluding days within 60 days of the change; p = (1 + hits) / (1 + N) <= 0.01 with N >= 20.

**Convergence.** A candidate *converges* when another family shows an onset by the same detector within 7 days of the
news onset: the entity's Wikipedia article (pageviews, the editor trail's thresholds with its +20 views floor) or
television (one chunk around the date, US cable, the 2-clip floor). Only candidates are fetched on these sensors.

**Ranking.** Converged candidates first, then p, then ratio; at most 2 candidates per entity; decoy entities are ranked
separately and never enter the top 20.

**Hand check of the top 20.** For each candidate a person looks for the event in the 21 days before the onset (to 3 days
after, since the trailing mean lags the jump by up to 6 days), using the entity's Wikipedia article and its history.
Each is classed: *stone* (a datable public event a reader would recognize: a release, broadcast, publication, viral
moment, disaster, ruling, scandal or launch), *routine* (a scheduled recurring event: holidays, annual awards, a sports
season, seasonal weather), *artifact* (a query collision or a collection change) or *unknown*. A stone is **new** when
the repository has no stone for that entity at that time (chains, maps, `discovered.json`, `discovered_wiki.json`,
`culture_v1.json`).

**Selection disclosure.** The behavior panel was chosen by the registrant, who knew that some of these entities had viral
moments; its hit rate overstates what a blind panel would yield. The decoy entities and the decoy dates are the controls.

## 8. The bar (each part reported as passed or failed)

1. **Convergence:** at least 70% of the measured Wikipedia steps that have at least one testable independent family are
   confirmed.
2. **Calibration:** each sensor's false-pass rate on decoy dates is at most 10%.
3. **Reach:** at least 5 set-D steps (before August 2015) come out beyond chance in order on television or Media Cloud.
4. **Catalysts:** of the top 20 candidates, at least 14 are hand-checked stones that precede their change and at least 5 of
   those are new to the catalog; and at most 1 of the 10 decoy entities yields a candidate.

A failed part is reported as failed, with the diagnosis.

## 9. Registered queries

### Set A: measured and timed Wikipedia attention steps

| Step | Claim | Ref | Lag | Where | GDELT DOC | Media Cloud | Television |
|---|---|---|---|---|---|---|---|
| tiger-king 2 | People look up big cats and exotic pets | 2020-03-20 | 150 | US | `("big cat" OR "big cats" OR "exotic pet" OR "exotic pets")` | `"big cat" OR "big cats" OR "exotic pet" OR "exotic pets"` | `("big cat" OR "big cats" OR "exotic pet" OR "exotic pets")` |
| wordle 2 | People look up Wordle | 2021-10-01 | 150 | US | `"wordle" (puzzle OR game OR guess)` | `wordle AND (puzzle OR game OR guess)` | `"wordle"` |
| chernobyl-zone 2 | Interest in the real disaster surges | 2019-05-06 | 60 | US | `"Chernobyl disaster"` | `"Chernobyl disaster"` | `"chernobyl"` |
| mr-bates-horizon 2 | Attention to the Horizon scandal surges | 2024-01-01 | 30 | UK | `("Post Office scandal" OR "Horizon scandal")` | `"Post Office scandal" OR "Horizon scandal"` | `("post office scandal" OR "horizon scandal")` |
| mr-bates-horizon 9 | Attention to Paula Vennells surges | 2024-01-01 | 30 | UK | `"Paula Vennells"` | `"Paula Vennells"` | `"paula vennells"` |
| daily-show-zadroga 5 | Attention to the Act surges | 2019-06-11 | 30 | US | `"Zadroga"` | `Zadroga` | `"zadroga"` |
| ocean-attenborough 2 | Attention to bottom trawling rises | 2025-05-08 | 45 | UK | `"bottom trawling"` | `"bottom trawling"` | `"bottom trawling"` |
| america-and-alcohol 25 | Attention to alcohol and cancer surges after the Surgeon General's advisory | 2025-01-03 | 45 | US | `"alcohol and cancer"` | `"alcohol and cancer"` | `"alcohol and cancer"` |
| jwst 2 | Public interest in astronomy spikes | 2022-07-11 | 60 | US | `("astronomy" OR "astronomer" OR "astronomers")` | `astronomy OR astronomer OR astronomers` | `("astronomy" OR "astronomer" OR "astronomers")` |
| gamestop 1 | Reddit traders squeeze GameStop | 2021-01-13 | 60 | US | `"GameStop"` | `GameStop` | `"gamestop"` |
| queens-gambit-2 2 | People look up chess and chess sets | 2020-10-23 | 60 | US | `"chess" (grandmaster OR tournament OR chessboard OR "chess set" OR "chess sets")` | `chess AND (grandmaster OR tournament OR chessboard OR "chess set" OR "chess sets")` | `"chess"` |
| toilet-paper 2 | People look up bidets | 2020-03-11 | 60 | US | `("bidet" OR "bidets")` | `bidet OR bidets` | `("bidet" OR "bidets")` |
| squid-game-ripples 12 | Interest in ddakji, the paper-tile game, surges | 2021-09-17 | 60 | US | `("ddakji" OR "ttakji")` | `ddakji OR ttakji` | `("ddakji" OR "ttakji")` |
| pokemon-go 1 | Pokémon GO launches | 2016-07-06 | 60 | US | `"Pokemon Go"` | `"Pokemon Go" OR "Pokémon Go"` | `"pokemon go"` |
| barbie 4 | Fashion pivots to pink ('Barbiecore') | 2023-07-21 | 180 | US | `"barbiecore"` | `barbiecore` | `"barbiecore"` |
| covid-remote 2 | Knowledge workers move to 'Zoom towns' | 2020-03-13 | 600 | US | `("zoom town" OR "zoom towns" OR "zoomtown" OR "zoomtowns")` | `"zoom town" OR "zoom towns" OR zoomtown OR zoomtowns` | `("zoom town" OR "zoom towns")` |
| airpods 2 | Wireless earbuds take off; AirPods dominate | 2016-09-07 | 150 | US | `"AirPods"` | `AirPods` | `("airpods" OR "air pods")` |
| tiktok 1 | TikTok's For You feed takes off | 2018-08-02 | 365 | US | `"TikTok"` | `TikTok` | `("tiktok" OR "tik tok")` |

### Set A2: record steps whose attention check rose

| Step | Claim | Ref | Lag | Where | GDELT DOC | Media Cloud | Television |
|---|---|---|---|---|---|---|---|
| wordle 3 | The New York Times buys Wordle | 2022-01-31 | 45 | US | `"wordle" (puzzle OR game OR guess)` | `wordle AND (puzzle OR game OR guess)` | `"wordle"` |
| haber-nitrogen 7 | World population grows from 1.6 billion to 8 billion | 2022-11-15 | 45 | US | `"world population"` | `"world population"` | `"world population"` |
| chernobyl-zone 3 | Tour operators report bookings up 30–40% | 2019-06-04 | 45 | US | `"exclusion zone" "chernobyl"` | `"exclusion zone" AND chernobyl` | `"exclusion zone"` |
| mr-bates-horizon 3 | A petition to strip Paula Vennells of her CBE passes a million signatures | 2024-01-08 | 45 | UK | `"Paula Vennells"` | `"Paula Vennells"` | `"paula vennells"` |
| mr-bates-horizon 4 | Vennells hands back her CBE | 2024-01-09 | 45 | UK | `"Paula Vennells"` | `"Paula Vennells"` | `"paula vennells"` |
| mr-bates-horizon 5 | The Prime Minister announces a law to quash the convictions | 2024-01-10 | 45 | UK | `("Post Office scandal" OR "Horizon scandal")` | `"Post Office scandal" OR "Horizon scandal"` | `("post office scandal" OR "horizon scandal")` |
| octopus-sentience 3 | The film wins the Academy Award for Documentary Feature | 2021-04-25 | 45 | US | `"My Octopus Teacher"` | `"My Octopus Teacher"` | `"my octopus teacher"` |
| ocean-attenborough 3 | The UK government opens a consultation on banning bottom trawling in 41 marine protected areas | 2025-06-09 | 45 | UK | `"bottom trawling"` | `"bottom trawling"` | `"bottom trawling"` |
| adolescence-schools 1 | Netflix releases Adolescence | 2025-03-13 | 45 | UK | `"adolescence" (Netflix OR series OR drama)` | `adolescence AND (Netflix OR series OR drama)` | `"adolescence"` |
| adolescence-schools 3 | MPs cite the series in the Children's Wellbeing and Schools Bill debate | 2025-03-18 | 45 | UK | `"adolescence" (Netflix OR series OR drama)` | `adolescence AND (Netflix OR series OR drama)` | `"adolescence"` |
| adolescence-schools 4 | The Prime Minister backs showing the series in schools | 2025-03-31 | 45 | UK | `"adolescence" (Netflix OR series OR drama)` | `adolescence AND (Netflix OR series OR drama)` | `"adolescence"` |
| america-and-alcohol 21 | The Surgeon General calls for cancer warnings on alcohol | 2025-01-03 | 45 | US | `"alcohol and cancer"` | `"alcohol and cancer"` | `"alcohol and cancer"` |
| three-mile-island-nrc 10 | Constellation agrees to restart Unit 1 to power Microsoft's data centers | 2024-09-20 | 45 | US | `"Three Mile Island"` | `"Three Mile Island"` | `"three mile island"` |
| serial 4 | Renewed legal momentum; conviction vacated | 2022-09-19 | 45 | US | `"Adnan Syed"` | `"Adnan Syed"` | `"adnan syed"` |
| dobbs 2 | Trigger bans take effect | 2022-07-28 | 45 | US | `("trigger law" OR "trigger laws" OR "trigger ban" OR "trigger bans")` | `"trigger law" OR "trigger laws" OR "trigger ban" OR "trigger bans"` | `("trigger law" OR "trigger laws" OR "trigger ban" OR "trigger bans")` |
| gdpr 1 | GDPR takes effect | 2018-05-25 | 45 | US | `("GDPR" OR "General Data Protection Regulation")` | `GDPR OR "General Data Protection Regulation"` | `("gdpr" OR "general data protection regulation")` |
| ice-bucket 4 | Project MinE helps identify NEK1 | 2016-07-25 | 45 | US | `"NEK1"` | `NEK1` | `"nek1"` |
| queens-gambit-2 1 | The Queen's Gambit is released in lockdown | 2020-10-23 | 45 | US | `"Queen's Gambit"` | `"Queen's Gambit"` | `"queen's gambit"` |
| squid-game-ripples 5 | SK Broadband sues Netflix over network costs, citing the traffic surge | 2021-09-30 | 45 | US | `"SK Broadband"` | `"SK Broadband"` | `"sk broadband"` |
| squid-game-ripples 11 | Netflix launches Squid Game: The Challenge | 2023-11-22 | 45 | US | `"Squid Game" challenge` | `"Squid Game" AND challenge` | `"squid game"` |

### Set C: attention leads

| Step | Claim | Ref | Lag | Where | GDELT DOC | Media Cloud | Television |
|---|---|---|---|---|---|---|---|
| stranger-things-4: Running Up That Hill | A 1985 Kate Bush song returns | 2022-05-27 | 120 | US | `"Running Up That Hill"` | `"Running Up That Hill"` | `"running up that hill"` |
| stranger-things-4: Lukiškės Prison | The Vilnius prison used for filming, now an arts venue | 2022-05-27 | 120 | US | `("Lukiskes" OR "Lukiškės")` | `Lukiskes OR Lukiškės` | `"lukiskes"` |
| stranger-things-4: Master of Puppets (song) | Metallica's 1986 track finds a new audience | 2022-05-27 | 120 | US | `"Master of Puppets"` | `"Master of Puppets"` | `"master of puppets"` |
| wednesday: Bloody Mary (song) | A dance trend revives a 2011 Lady Gaga track | 2022-11-23 | 120 | US | `"Bloody Mary" ("Lady Gaga" OR Gaga)` | `"Bloody Mary" AND Gaga` | not run |
| wednesday: Cantacuzino Castle | The Romanian castle that played Nevermore Academy | 2022-11-23 | 120 | US | `"Cantacuzino"` | `Cantacuzino` | `"cantacuzino"` |
| saltburn: Murder on the Dancefloor | Sophie Ellis-Bextor's 2001 hit returns | 2023-11-17 | 120 | UK | `"Murder on the Dancefloor"` | `"Murder on the Dancefloor"` | `"murder on the dancefloor"` |
| squid-game: Ddakji | The show's playground games become a craze | 2021-09-17 | 120 | US | `("ddakji" OR "ttakji")` | `ddakji OR ttakji` | `("ddakji" OR "ttakji")` |
| squid-game: SK Broadband | Korea's internet provider and Netflix's traffic | 2021-09-17 | 120 | US | `"SK Broadband"` | `"SK Broadband"` | `"sk broadband"` |
| the-bear: Italian beef | Chicago's Italian beef sandwich in the spotlight | 2022-06-23 | 120 | US | `"Italian beef"` | `"Italian beef"` | `"italian beef"` |
| bridgerton: Ranger's House | A Greenwich house that played the Featheringtons' home | 2020-12-25 | 120 | UK | `"Ranger's House"` | `"Ranger's House"` | `"ranger's house"` |
| queens-gambit: The Steps of the Sun | Readers turn to Walter Tevis's other novels | 2020-10-23 | 120 | US | `"The Steps of the Sun"` | `"The Steps of the Sun"` | `"steps of the sun"` |
| chernobyl: Voices from Chernobyl | The oral history behind the series | 2019-05-06 | 120 | US | `"Voices from Chernobyl"` | `"Voices from Chernobyl"` | `"voices from chernobyl"` |
| chernobyl: Ignalina Nuclear Power Plant | The Lithuanian plant that stood in for Chernobyl | 2019-05-06 | 120 | US | `"Ignalina"` | `Ignalina` | `"ignalina"` |
| chernobyl: Chernobyl Children International | A Chernobyl children's charity draws attention | 2019-05-06 | 120 | US | `"Chernobyl Children International"` | `"Chernobyl Children International"` | `"chernobyl children"` |
| tiger-king: Greater Wynnewood Exotic Animal Park | The zoo at the center of the show | 2020-03-20 | 120 | US | `("Greater Wynnewood" OR "G.W. Zoo" OR "GW Zoo")` | `"Greater Wynnewood" OR "G.W. Zoo" OR "GW Zoo"` | `("wynnewood" OR "g.w. zoo")` |
| tiger-king: Big Cat Rescue | Carole Baskin's sanctuary in the spotlight | 2020-03-20 | 120 | US | `"Big Cat Rescue"` | `"Big Cat Rescue"` | `"big cat rescue"` |
| the-last-of-us: Long Long Time | Episode 3 revives a 1970 Linda Ronstadt song | 2023-01-15 | 120 | US | `"Long Long Time" Ronstadt` | `"Long Long Time" AND Ronstadt` | not run |
| shogun: Gai-Jin | Readers turn to James Clavell's other novels | 2024-02-27 | 120 | US | `"Gai-Jin" Clavell` | `"Gai-Jin" AND Clavell` | `"gai-jin"` |

### Set D: dated steps, Jul 2009 to Jul 2015

| Step | Claim | Ref | Lag | Where | GDELT DOC | Media Cloud | Television |
|---|---|---|---|---|---|---|---|
| frozen 1 | Frozen is released; Elsa becomes a phenomenon | 2013-11-27 | 45 | US | `"Frozen" Disney` | `Frozen AND Disney` | `"frozen" disney` |
| sixty-minutes-stock-act 1 | 60 Minutes airs 'Insiders' on members of Congress trading stock | 2011-11-13 | 45 | US | `"insider trading" Congress` | `"insider trading" AND Congress` | `"insider trading" congress` |
| sixty-minutes-stock-act 2 | Cosponsors of the STOCK Act jump from 9 to more than 100 within weeks | 2011-12-15 | 45 | US | `"STOCK Act"` | `"STOCK Act"` | `"stock act"` |
| sixty-minutes-stock-act 3 | The Senate passes the bill 96–3 | 2012-02-02 | 45 | US | `"STOCK Act"` | `"STOCK Act"` | `"stock act"` |
| sixty-minutes-stock-act 4 | The STOCK Act is signed | 2012-04-04 | 45 | US | `"STOCK Act"` | `"STOCK Act"` | `"stock act"` |
| sixty-minutes-stock-act 5 | Members' trades must be disclosed within 45 days | 2012-07-03 | 45 | US | `"STOCK Act"` | `"STOCK Act"` | `"stock act"` |
| daily-show-zadroga 1 | Jon Stewart devotes a full Daily Show to the stalled 9/11 responders' health bill | 2010-12-16 | 45 | US | `"Zadroga"` | `Zadroga` | `"zadroga"` |
| daily-show-zadroga 2 | The Senate passes the bill by unanimous consent six days later | 2010-12-22 | 45 | US | `"Zadroga"` | `Zadroga` | `"zadroga"` |
| daily-show-zadroga 3 | The James Zadroga 9/11 Health and Compensation Act is signed | 2011-01-02 | 45 | US | `"Zadroga"` | `Zadroga` | `"zadroga"` |
| america-and-alcohol 13 | Most US teens have a smartphone | 2015-04-09 | 45 | US | `"smartphone" teens` | `smartphone AND teens` | `"smartphone" teens` |
| america-and-alcohol 15 | Dry January begins as a public campaign | 2013-01-01 | 45 | US | `"Dry January"` | `"Dry January"` | `"dry january"` |
| america-and-alcohol 17 | Legal recreational cannabis begins (Colorado) | 2014-01-01 | 45 | US | `"marijuana" Colorado` | `marijuana AND Colorado` | `"marijuana" colorado` |
| three-mile-island-nrc 8 | No new reactor is licensed for 33 years, until the NRC approves Vogtle 3 and 4 | 2012-02-09 | 45 | US | `"Vogtle"` | `Vogtle` | `"vogtle"` |
| exxon-valdez-opa90 9 | Single-hull tankers are barred from US waters | 2015-01-01 | 45 | US | `"single hull"` | `"single hull" OR "single-hull"` | `"single hull"` |
| liebeck-hot-coffee 10 | HBO's Hot Coffee retells the case and the campaign built on it | 2011-06-27 | 45 | US | `"hot coffee" lawsuit` | `"hot coffee" AND lawsuit` | `"hot coffee" lawsuit` |
| columbine-active-shooter 9 | Colorado's Claire Davis School Safety Act lets families sue schools that fail to take reasonable care against violence | 2015-06-03 | 45 | US | `"Claire Davis"` | `"Claire Davis"` | `"claire davis"` |
| flint-lead-pipes 1 | Flint switches its drinking water to the Flint River | 2014-04-25 | 45 | US | `"Flint" water` | `Flint AND water` | `"flint" water` |
| flint-lead-pipes 2 | General Motors stops using Flint water at its engine plant because it corrodes parts | 2014-10-13 | 45 | US | `"Flint" water` | `Flint AND water` | `"flint" water` |
| serial 1 | Serial season 1 launches | 2014-10-03 | 45 | US | `"Serial" podcast` | `Serial AND podcast` | `"serial" podcast` |
| fukushima 1 | Fukushima Daiichi meltdown | 2011-03-11 | 45 | US | `"Fukushima"` | `Fukushima` | `"fukushima"` |
| fukushima 2 | Germany decides to phase out nuclear | 2011-05-30 | 45 | US | `"Germany" nuclear` | `Germany AND nuclear` | `"germany" nuclear` |
| eyjafjallajokull 1 | Icelandic eruption sends ash over Europe | 2010-04-14 | 45 | US | `"Iceland" volcano` | `Iceland AND volcano` | `"iceland" volcano` |
| eyjafjallajokull 2 | European airspace closes | 2010-04-15 | 45 | US | `"airspace" ash` | `airspace AND ash` | `"airspace" ash` |
| eyjafjallajokull 4 | Kenyan flower exporters destroy stock | 2010-04-19 | 45 | US | `"Kenya" flowers` | `Kenya AND flowers` | `"kenya" flowers` |
| thailand-floods 1 | Floods hit Thailand's industrial estates | 2011-10-08 | 45 | US | `"Thailand" (flood OR floods OR flooding)` | `Thailand AND (flood OR floods OR flooding)` | `"thailand" (flood OR floods OR flooding)` |
| thailand-floods 2 | Hard-drive factories halt | 2011-10-17 | 45 | US | `("hard drive" OR "hard drives") Thailand` | `("hard drive" OR "hard drives") AND Thailand` | `("hard drive" OR "hard drives") thailand` |
| ice-bucket 1 | The Ice Bucket Challenge goes viral | 2014-07-29 | 45 | US | `"ice bucket"` | `"ice bucket"` | `"ice bucket"` |
| ice-bucket 2 | ALS Association raises about $115 million | 2014-08-29 | 45 | US | `"ALS Association"` | `"ALS Association"` | `"als association"` |
| ice-bucket 3 | ALSA funds genetics projects, including Project MinE | 2014-12-01 | 45 | US | `"ALS Association"` | `"ALS Association"` | `"als association"` |
| cash-for-clunkers 1 | CARS rebates begin | 2009-07-24 | 45 | US | `"cash for clunkers"` | `"cash for clunkers"` | `"cash for clunkers"` |
| cash-for-clunkers 2 | About 677,000 trade-ins are destroyed | 2009-12-01 | 45 | US | `"cash for clunkers"` | `"cash for clunkers"` | `"cash for clunkers"` |
| the-dress 1 | The dress photo goes viral | 2015-02-26 | 45 | US | `"the dress" (blue OR gold)` | `"the dress" AND (blue OR gold)` | `"the dress" (blue OR gold)` |
| the-dress 2 | Scientists take notice | 2015-05-14 | 45 | US | `"the dress" (blue OR gold)` | `"the dress" AND (blue OR gold)` | `"the dress" (blue OR gold)` |
| jurassic-park 3 | Poachers smuggle Mongolian dinosaurs | 2012-10-01 | 45 | US | `"dinosaur" Mongolia` | `dinosaur AND Mongolia` | `"dinosaur" mongolia` |
| sony-hack 1 | North Korea hacks Sony Pictures | 2014-12-19 | 45 | US | `"Sony" (hack OR hackers OR hacking)` | `Sony AND (hack OR hackers OR hacking)` | `"sony" (hack OR hackers OR hacking)` |
| sony-hack 2 | Leaked emails show Jennifer Lawrence paid less | 2014-12-12 | 45 | US | `"Jennifer Lawrence" (pay OR paid)` | `"Jennifer Lawrence" AND (pay OR paid)` | `"jennifer lawrence" (pay OR paid)` |
| planet-earth 3 | Old TVs on dressers crush children | 2011-11-01 | 45 | US | `("tip over" OR "tip-over" OR "tipover") (furniture OR television OR dresser)` | `("tip over" OR "tip-over" OR tipover) AND (furniture OR television OR dresser)` | `("tip over" OR "tipover") (furniture OR television OR dresser)` |
| planet-earth 4 | CPSC launches 'Anchor It!' | 2015-06-01 | 45 | US | `"Anchor It"` | `"Anchor It"` | `"anchor it"` |
| gangnam-style 1 | Gangnam Style goes viral | 2012-12-21 | 45 | US | `"Gangnam"` | `Gangnam` | `"gangnam"` |
| gangnam-style 2 | Views approach 2,147,483,647 | 2014-12-01 | 45 | US | `"Gangnam"` | `Gangnam` | `"gangnam"` |
| manhunt-byron 5 | The Digital Economy Act 2010 makes video game ratings legally enforceable | 2010-04-08 | 45 | UK | `"Digital Economy Act"` | `"Digital Economy Act"` | not run |
| manhunt-byron 6 | PEGI becomes the statutory UK rating system | 2012-07-30 | 45 | UK | `"PEGI"` | `PEGI` | not run |

### Set E: catalyst panel

| Entity | Group | GDELT DOC | Media Cloud | Television | Wikipedia article |
|---|---|---|---|---|---|
| big cat | recall | `("big cat" OR "big cats")` | `"big cat" OR "big cats"` | `("big cat" OR "big cats")` | Big cat |
| exotic pet | recall | `("exotic pet" OR "exotic pets")` | `"exotic pet" OR "exotic pets"` | `("exotic pet" OR "exotic pets")` | Exotic pet |
| Big Cat Rescue | recall | `"Big Cat Rescue"` | `"Big Cat Rescue"` | `"big cat rescue"` | Big Cat Rescue |
| bidet | recall | `("bidet" OR "bidets")` | `bidet OR bidets` | `("bidet" OR "bidets")` | Bidet |
| chess | recall | `"chess" (grandmaster OR tournament OR chessboard OR "chess set" OR "chess sets")` | `chess AND (grandmaster OR tournament OR chessboard OR "chess set" OR "chess sets")` | `"chess"` | Chess |
| ddakji | recall | `("ddakji" OR "ttakji")` | `ddakji OR ttakji` | `("ddakji" OR "ttakji")` | Ddakji |
| bottom trawling | recall | `"bottom trawling"` | `"bottom trawling"` | `"bottom trawling"` | Bottom trawling |
| Running Up That Hill | recall | `"Running Up That Hill"` | `"Running Up That Hill"` | `"running up that hill"` | Running Up That Hill |
| Master of Puppets | recall | `"Master of Puppets"` | `"Master of Puppets"` | `"master of puppets"` | Master of Puppets (song) |
| Murder on the Dancefloor | recall | `"Murder on the Dancefloor"` | `"Murder on the Dancefloor"` | `"murder on the dancefloor"` | Murder on the Dancefloor |
| Italian beef | recall | `"Italian beef"` | `"Italian beef"` | `"italian beef"` | Italian beef |
| Paula Vennells | recall | `"Paula Vennells"` | `"Paula Vennells"` | `"paula vennells"` | Paula Vennells |
| Post Office scandal | recall | `("Post Office scandal" OR "Horizon scandal")` | `"Post Office scandal" OR "Horizon scandal"` | `("post office scandal" OR "horizon scandal")` | British Post Office scandal |
| Zadroga | recall | `"Zadroga"` | `Zadroga` | `"zadroga"` | James Zadroga 9/11 Health and Compensation Act |
| Chernobyl disaster | recall | `"Chernobyl disaster"` | `"Chernobyl disaster"` | `"chernobyl"` | Chernobyl disaster |
| astronomy | recall | `("astronomy" OR "astronomers")` | `astronomy OR astronomers` | `("astronomy" OR "astronomers")` | Astronomy |
| trigger law | recall | `("trigger law" OR "trigger laws")` | `"trigger law" OR "trigger laws"` | `("trigger law" OR "trigger laws")` | Trigger law |
| Adnan Syed | recall | `"Adnan Syed"` | `"Adnan Syed"` | `"adnan syed"` | Adnan Syed |
| Three Mile Island | recall | `"Three Mile Island"` | `"Three Mile Island"` | `"three mile island"` | Three Mile Island Nuclear Generating Station |
| alcohol and cancer | recall | `"alcohol and cancer"` | `"alcohol and cancer"` | `"alcohol and cancer"` | Alcohol and cancer |
| Dry January | recall | `"Dry January"` | `"Dry January"` | `"dry january"` | Dry January |
| sober curious | recall | `"sober curious"` | `"sober curious"` | `"sober curious"` | Sober curious |
| Pinot Noir | recall | `"Pinot Noir"` | `"Pinot Noir"` | `"pinot noir"` | Pinot noir |
| Wordle | recall | `"wordle" (puzzle OR game OR guess)` | `wordle AND (puzzle OR game OR guess)` | `"wordle"` | Wordle |
| sourdough | behavior | `"sourdough"` | `sourdough` | `"sourdough"` | Sourdough |
| cranberry juice | behavior | `"cranberry juice"` | `"cranberry juice"` | `"cranberry juice"` | Cranberry juice |
| Dalgona coffee | behavior | `"dalgona"` | `dalgona` | `"dalgona"` | Dalgona coffee |
| Negroni Sbagliato | behavior | `"Negroni Sbagliato"` | `"Negroni Sbagliato"` | `"negroni sbagliato"` | Negroni |
| espresso martini | behavior | `"espresso martini"` | `"espresso martini"` | `"espresso martini"` | Espresso martini |
| Aperol | behavior | `"Aperol"` | `Aperol` | `"aperol"` | Aperol |
| oat milk | behavior | `"oat milk"` | `"oat milk"` | `"oat milk"` | Oat milk |
| Stanley tumbler | behavior | `("Stanley tumbler" OR "Stanley tumblers" OR "Stanley Quencher")` | `"Stanley tumbler" OR "Stanley tumblers" OR "Stanley Quencher"` | `("stanley tumbler" OR "stanley quencher")` | Stanley (drinkware) |
| birria | behavior | `"birria"` | `birria` | `"birria"` | Birria |
| cottage cheese | behavior | `"cottage cheese"` | `"cottage cheese"` | `"cottage cheese"` | Cottage cheese |
| Dubai chocolate | behavior | `"Dubai chocolate"` | `"Dubai chocolate"` | `"dubai chocolate"` | Dubai chocolate |
| pumpkin spice | behavior | `"pumpkin spice"` | `"pumpkin spice"` | `"pumpkin spice"` | Pumpkin spice |
| pickleball | behavior | `"pickleball"` | `pickleball` | `"pickleball"` | Pickleball |
| knitting | behavior | `"knitting"` | `knitting` | `"knitting"` | Knitting |
| Dungeons & Dragons | behavior | `("Dungeons and Dragons" OR "Dungeons & Dragons")` | `"Dungeons and Dragons" OR "Dungeons & Dragons"` | `"dungeons and dragons"` | Dungeons & Dragons |
| Rubik's Cube | behavior | `("Rubik's Cube" OR "Rubiks Cube")` | `"Rubik's Cube" OR "Rubiks Cube"` | `"rubik's cube"` | Rubik's Cube |
| jigsaw puzzle | behavior | `("jigsaw puzzle" OR "jigsaw puzzles")` | `"jigsaw puzzle" OR "jigsaw puzzles"` | `("jigsaw puzzle" OR "jigsaw puzzles")` | Jigsaw puzzle |
| roller skating | behavior | `("roller skating" OR "roller skates")` | `"roller skating" OR "roller skates"` | `("roller skating" OR "roller skates")` | Roller skating |
| archery | behavior | `"archery"` | `archery` | `"archery"` | Archery |
| figure skating | behavior | `"figure skating"` | `"figure skating"` | `"figure skating"` | Figure skating |
| Dubrovnik | behavior | `"Dubrovnik"` | `Dubrovnik` | `"dubrovnik"` | Dubrovnik |
| Hobbiton | behavior | `"Hobbiton"` | `Hobbiton` | `"hobbiton"` | Hobbiton Movie Set |
| Highclere Castle | behavior | `"Highclere"` | `Highclere` | `"highclere"` | Highclere Castle |
| Taormina | behavior | `"Taormina"` | `Taormina` | `"taormina"` | Taormina |
| Koh Samui | behavior | `("Koh Samui" OR "Ko Samui")` | `"Koh Samui" OR "Ko Samui"` | `("koh samui" OR "ko samui")` | Ko Samui |
| Glenfinnan | behavior | `"Glenfinnan"` | `Glenfinnan` | `"glenfinnan"` | Glenfinnan Viaduct |
| Pripyat | behavior | `"Pripyat"` | `Pripyat` | `"pripyat"` | Pripyat |
| Fleetwood Mac | behavior | `"Fleetwood Mac"` | `"Fleetwood Mac"` | `"fleetwood mac"` | Fleetwood Mac |
| Kate Bush | behavior | `"Kate Bush"` | `"Kate Bush"` | `"kate bush"` | Kate Bush |
| Sophie Ellis-Bextor | behavior | `("Sophie Ellis-Bextor" OR "Sophie Ellis Bextor")` | `"Sophie Ellis-Bextor" OR "Sophie Ellis Bextor"` | `"sophie ellis"` | Sophie Ellis-Bextor |
| Linda Ronstadt | behavior | `"Linda Ronstadt"` | `"Linda Ronstadt"` | `"linda ronstadt"` | Linda Ronstadt |
| Jeff Buckley | behavior | `"Jeff Buckley"` | `"Jeff Buckley"` | `"jeff buckley"` | Jeff Buckley |
| naloxone | behavior | `("naloxone" OR "Narcan")` | `naloxone OR Narcan` | `("naloxone" OR "narcan")` | Naloxone |
| melatonin | behavior | `"melatonin"` | `melatonin` | `"melatonin"` | Melatonin |
| cold plunge | behavior | `("cold plunge" OR "ice bath")` | `"cold plunge" OR "ice bath"` | `("cold plunge" OR "ice bath")` | Ice bath |
| sunscreen | behavior | `"sunscreen"` | `sunscreen` | `"sunscreen"` | Sunscreen |
| vaping | behavior | `("vaping" OR "e-cigarette" OR "e-cigarettes")` | `vaping OR "e-cigarette" OR "e-cigarettes"` | `("vaping" OR "e-cigarette")` | Electronic cigarette |
| Ozempic | behavior | `("Ozempic" OR "semaglutide")` | `Ozempic OR semaglutide` | `("ozempic" OR "semaglutide")` | Semaglutide |
| orca | behavior | `("orca" OR "orcas")` | `orca OR orcas` | `("orca" OR "orcas")` | Orca |
| pangolin | behavior | `("pangolin" OR "pangolins")` | `pangolin OR pangolins` | `("pangolin" OR "pangolins")` | Pangolin |
| axolotl | behavior | `("axolotl" OR "axolotls")` | `axolotl OR axolotls` | `("axolotl" OR "axolotls")` | Axolotl |
| capybara | behavior | `("capybara" OR "capybaras")` | `capybara OR capybaras` | `("capybara" OR "capybaras")` | Capybara |
| pygmy hippo | behavior | `("pygmy hippo" OR "pygmy hippopotamus")` | `"pygmy hippo" OR "pygmy hippopotamus"` | `("pygmy hippo" OR "pygmy hippopotamus")` | Pygmy hippopotamus |
| octopus | behavior | `("octopus" OR "octopuses")` | `octopus OR octopuses` | `("octopus" OR "octopuses")` | Octopus |
| manatee | behavior | `("manatee" OR "manatees")` | `manatee OR manatees` | `("manatee" OR "manatees")` | Manatee |
| monarch butterfly | behavior | `("monarch butterfly" OR "monarch butterflies")` | `"monarch butterfly" OR "monarch butterflies"` | `("monarch butterfly" OR "monarch butterflies")` | Monarch butterfly |
| right to repair | behavior | `"right to repair"` | `"right to repair"` | `"right to repair"` | Right to repair |
| four-day week | behavior | `("four-day week" OR "four-day work week" OR "4-day week")` | `"four-day week" OR "four-day work week" OR "4-day week"` | `("four-day week" OR "four day week")` | Four-day week |
| universal basic income | behavior | `"universal basic income"` | `"universal basic income"` | `"universal basic income"` | Universal basic income |
| loot box | behavior | `("loot box" OR "loot boxes")` | `"loot box" OR "loot boxes"` | `("loot box" OR "loot boxes")` | Loot box |
| Section 230 | behavior | `"Section 230"` | `"Section 230"` | `"section 230"` | Section 230 |
| fidget spinner | behavior | `("fidget spinner" OR "fidget spinners")` | `"fidget spinner" OR "fidget spinners"` | `("fidget spinner" OR "fidget spinners")` | Fidget spinner |
| air fryer | behavior | `("air fryer" OR "air fryers")` | `"air fryer" OR "air fryers"` | `("air fryer" OR "air fryers")` | Air fryer |
| Crocs | behavior | `"Crocs" (shoes OR clogs OR footwear)` | `Crocs AND (shoes OR clogs OR footwear)` | `"crocs"` | Crocs |
| Birkenstock | behavior | `"Birkenstock"` | `Birkenstock` | `"birkenstock"` | Birkenstock |
| Tamagotchi | behavior | `"Tamagotchi"` | `Tamagotchi` | `"tamagotchi"` | Tamagotchi |
| Polaroid | behavior | `"Polaroid"` | `Polaroid` | `"polaroid"` | Polaroid Corporation |
| typewriter | behavior | `("typewriter" OR "typewriters")` | `typewriter OR typewriters` | `("typewriter" OR "typewriters")` | Typewriter |
| flip phone | behavior | `("flip phone" OR "flip phones")` | `"flip phone" OR "flip phones"` | `("flip phone" OR "flip phones")` | Flip phone |
| quiet luxury | behavior | `"quiet luxury"` | `"quiet luxury"` | `"quiet luxury"` | Quiet luxury |
| mob wife | behavior | `"mob wife"` | `"mob wife"` | `"mob wife"` | Mob wife aesthetic |
| cottagecore | behavior | `"cottagecore"` | `cottagecore` | `"cottagecore"` | Cottagecore |
| tradwife | behavior | `("tradwife" OR "tradwives")` | `tradwife OR tradwives` | `("tradwife" OR "tradwives")` | Tradwife |
| quiet quitting | behavior | `"quiet quitting"` | `"quiet quitting"` | `"quiet quitting"` | Quiet quitting |
| brat summer | behavior | `"brat summer"` | `"brat summer"` | `"brat summer"` | Brat (album) |
| girl dinner | behavior | `"girl dinner"` | `"girl dinner"` | `"girl dinner"` | Girl dinner |
| rizz | behavior | `"rizz"` | `rizz` | `"rizz"` | Rizz |
| gaslighting | behavior | `"gaslighting"` | `gaslighting` | `"gaslighting"` | Gaslighting |
| very demure | behavior | `"very demure"` | `"very demure"` | `"very demure"` | Jools Lebron |
| stapler | decoy | `("stapler" OR "staplers")` | `stapler OR staplers` | `("stapler" OR "staplers")` | Stapler |
| doormat | decoy | `("doormat" OR "doormats")` | `doormat OR doormats` | `("doormat" OR "doormats")` | Doormat |
| teaspoon | decoy | `"teaspoon"` | `teaspoon` | `"teaspoon"` | Teaspoon |
| paper clip | decoy | `("paper clip" OR "paperclip")` | `"paper clip" OR paperclip` | `("paper clip" OR "paperclip")` | Paper clip |
| shoelace | decoy | `("shoelace" OR "shoelaces")` | `shoelace OR shoelaces` | `("shoelace" OR "shoelaces")` | Shoelaces |
| ceiling fan | decoy | `("ceiling fan" OR "ceiling fans")` | `"ceiling fan" OR "ceiling fans"` | `("ceiling fan" OR "ceiling fans")` | Ceiling fan |
| garden hose | decoy | `("garden hose" OR "garden hoses")` | `"garden hose" OR "garden hoses"` | `("garden hose" OR "garden hoses")` | Garden hose |
| hairbrush | decoy | `("hairbrush" OR "hairbrushes")` | `hairbrush OR hairbrushes` | `("hairbrush" OR "hairbrushes")` | Hairbrush |
| spatula | decoy | `("spatula" OR "spatulas")` | `spatula OR spatulas` | `("spatula" OR "spatulas")` | Spatula |
| bookshelf | decoy | `("bookshelf" OR "bookshelves")` | `bookshelf OR bookshelves` | `("bookshelf" OR "bookshelves")` | Bookcase |

### Excluded, with reasons

- A:the Nov 30, 2022 chatbot-launch chain:1: its subject is a software model's product name, and the project's rule keeps model names out of every pushed file, queries included
- A2:chernobyl-zone:1: the attention check measured the article HBO, not the step's subject (the miniseries); re-testing HBO says nothing about the step
- D:frozen:2: measured already by SSA names (not an attention claim)
- D:frozen:4: approximate date (range midpoint)
- D:america-and-alcohol:14: a claim about a cause (must-precede), not an event with an attention date
- D:america-and-alcohol:16: a claim about a cause (must-precede), not an event with an attention date
- D:america-and-alcohol:18: a claim about a cause (must-precede), not an event with an attention date
- D:flint-lead-pipes:6: a claim about a cause (must-precede), not an event with an attention date
- D:fukushima:3: approximate date (range midpoint)
- D:eyjafjallajokull:3: approximate date (range midpoint)
- D:thailand-floods:3: approximate date (range midpoint)
- D:thailand-floods:4: measured already by FRED (not an attention claim)
- D:thailand-floods:5: approximate date (range midpoint)
- D:cash-for-clunkers:3: approximate date (range midpoint)
- D:cash-for-clunkers:4: measured already by FRED (not an attention claim)
- D:cash-for-clunkers:5: approximate date (range midpoint)
- D:sideways:5: approximate date (range midpoint)

Every GDELT DOC query carries the suffix `sourcelang:english`. Television queries carry `(station:CNN OR station:MSNBC OR station:FOXNEWS)` for a US step and `station:BBCNEWS` for a UK step.

## 10. Amendments (each registered before any result it could affect)

**Oct 5, 2026, 06:37 UTC (before any Media Cloud request and before any GDELT data; the time first read 06:45, a slip corrected on Oct 5; the commit, 11eb8ad at 06:37:52 UTC, is the record).** GDELT answered HTTP 429 to the
first request of this pass (the DOC API at 06:35 UTC), with a notice asking for one request every 5 seconds. Under the
rules this stops `api.gdeltproject.org`, which serves both the DOC and the TV API, until UTC midnight: no further GDELT
request is made on Oct 5 (UTC). One attempt will be made after Oct 6, 00:00 UTC at the registered pace; a second refusal
ends GDELT for this pass. Until then, and for good if GDELT stays closed:

1. The news family rests on Media Cloud, as section 5 already provides where GDELT DOC is not testable.
2. The television family is reported as not run.
3. The catalyst scan of section 7 runs on Media Cloud's US National series for the same panel with the identical rule
   (the scan, thresholds, the 3-story floor, the decoy dates and the ranking); a candidate converges when the entity's
   Wikipedia pageviews show an onset within 7 days of the news onset. If GDELT opens on Oct 6, the registered GDELT DOC
   scan is primary and supplies the top 20; the Media Cloud scan is reported beside it as a replication.
4. Bar part 3 (reach before August 2015) can then be met only by Media Cloud.
