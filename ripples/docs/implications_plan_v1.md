# What else should be true: implications plan v1

Registered Oct 5, 2026, 07:40 UTC, before any test below was run. The commit that adds this file and
`docs/results/implications_plan_v1.json` is the registration. Results will be in `docs/implications_v1.md` and
`docs/results/implications_v1.json`, each implication reported as held, failed or untestable.

**The idea.** A link that is real has consequences beyond the one series that measured it. If Tiger King sent readers
to big cats, a sequel should do it again and a giraffe should not; if the Thailand floods raised disk-drive prices, chip
prices should not have moved with them. An implication that holds out of sample is the second-strongest verification
after a live prediction. An implication that fails is a finding about the ripple, and each one below names the link it
would weaken.

**Scope.** Every catalog chain with a measured or timed link in `docs/results/chain_check_v1.json` (run Oct 5, 2026):
21 chains, 24 links. One is left out: the 2022 chatbot launch chain, whose product name the project's rule keeps out of
pushed files. That leaves **52 implications over 20 ripples, 45 testable now and 7 untestable** with free, keyless
data.

**Kinds.** Companion outcome (27: another outcome the same mechanism implies), sibling stone (10: another stone with
the same mechanism, 2 of them on the very same outcome series), dose (4: a second, smaller stone on the same outcome),
persistence (3: a claimed durable change must outlast the spike), specificity (3: something the mechanism does not
touch must stay flat), place or culture with more exposure (3), a seasonal check (1), a predicted lag (1).

## Tests (existing tools only)

- **wiki:** `chain_check.wiki_test` and `chain_check.verdict`, unchanged: a sustained rise searched from 30 days before
  the date to the lag, a placebo over the page's own history (every 14th day), p <= 0.05, onset no earlier than 3 days
  before the date. **Held** = "measured". **Failed** = no movement, within chance, or wrong order. A new article (no
  history) or too short a history is **untestable**, not held. For a "must NOT rise" implication the reading flips.
- **fred:** `chain_check.fred`, `series_test` and `verdict`, unchanged (the test that measured the Thailand and Clunkers
  links). Held = measured in the stated direction; for "must NOT" implications, held = not measured.
- **Names:** `chain_check.ssa_test` on the Frozen chain's own counts (1995 to 2021, already in `chains/batch1.json`).
- **Seasonal:** the wiki test at the date and at the same date one and two years earlier; held when the date's ratio
  beats each earlier one (no rise counts as 1).
- **Persistence:** means of daily views over the registered windows, against the registered share or factor.

Network: the honest user agent, at least a second between requests, a stop on any 403, 429 or 5xx with no same-day
retry. ssa.gov answered 403 to a single check before registration, so the one implication that needs fresh name data
(FZ-2) is untestable today; nothing was retried.

**Exposure, disclosed.** Before registering, the repository was searched for each title by file name only. Series for
some candidates already sat in result files (Wynnewood, Tiger, Valery Legasov, Stephan's Quintet, Mastermind, Jotto,
Lingo, Walter Tevis, Chess opening, Statues, Gonggi, Pink, Augmented reality, the Korean language); those were dropped
rather than tested in sample. Where a kept title appears in a repository file, the row says which. The title check also
showed that Barbiecore is now a redirect to Barbie, which BB-1 discloses.


### Frozen -> Elsa

Link: step 2, Parents name daughters Elsa (measured: SSA 2014, p = 0.038).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| FZ-1 | dose (a second stone, same outcome) | Frozen 2 (Nov 22, 2019) moves the name again: Elsa rises in 2020 beyond chance against every other year. (exposure: the counts are the chain's own (chains/batch1.json, 1995 to 2021); only the list of years was read before registration) | chain counts, name test for 2020 | Frozen -> Elsa: a second Elsa film that did not move the name makes the 2014 rise look like a one-off fashion |
| FZ-2 | sibling stone, same mechanism | Encanto (Nov 24, 2021) moves the name Mirabel in 2022. | untestable: ssa.gov refused the request (HTTP 403 to the honest user agent, Oct 5, 2026); per the rules no retry and no other route today | the culture -> naming mechanism, of which Frozen is the catalog's only measured case |
| FZ-3 | persistence (a fad, not a trend) | If the film caused the 2014 rise, the name falls back as the film fades: Elsa in 2017 is below Elsa in 2014. (exposure: the counts are the chain's own; not read before registration) | chain counts, 2017 below 2014 | Frozen -> Elsa: a name still rising three years on is a trend the film may have joined, not started |

### Tiger King -> big cats

Link: step 2, People look up big cats and exotic pets (measured: 5.1x, p = 0.010).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| TK-1 | dose (a second stone, same outcome) | Tiger King 2 (Nov 17, 2021) moves Big cat and Exotic pet again, beyond chance; secondary: by less than the first season's 5.1x. | views of Exotic pet, Big cat from 2021-11-17, lag 45 days; secondary: below 5.1x | slightly, the dose reading of Tiger King -> big cats (a sequel seen by far fewer may move nothing) |
| TK-2 | sibling stone, same mechanism | The Elephant Whisperers (Netflix, Dec 8, 2022) sends readers to the Indian elephant. | views of Indian elephant from 2022-12-08, lag 60 days | the mechanism 'an animal documentary sends readers to the animal' that Tiger King's step 2 instances |
| TK-3 | specificity (the lockdown confound) | An animal Tiger King never shows does NOT rise at the same date: Giraffe is flat after Mar 20, 2020. | views of Giraffe from 2020-03-20, lag 45: must NOT be measured | Tiger King -> big cats directly: if a giraffe rose too, the measured rise is lockdown attention, not the show |

### Pokémon GO's launch

Link: step 1, Pokemon GO launches (timed, short history).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| PG-1 | companion outcome | The launch sends readers to Ingress, Niantic's earlier game whose portals became PokeStops. | views of Ingress (video game) from 2016-07-06, lag 30 days | narrows the launch's ripple to the game itself; the timed link stands |
| PG-2 | companion outcome | The launch revives the franchise's first games: Pokemon Red, Blue, and Yellow rises beyond chance. | views of Pokémon Red, Blue, and Yellow from 2016-07-06, lag 30 days | narrows the launch's ripple to the game itself; the timed link stands |
| PG-3 | companion outcome (behavior) | Players walk more in the first weeks and fall back (the chain's step 2 rests on Howe et al., BMJ 2016). | untestable: step counts are in the paper, not in a free series | step 2 stays reported |

### Wordle

Link: step 2, People look up Wordle (measured, p = 0.007); step 3, the NYT buys Wordle (reported).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| WD-1 | companion outcome | After the purchase (Jan 31, 2022), readers look up The New York Times crossword. | views of The New York Times crossword from 2022-01-31, lag 30 days | step 3's reading that the purchase mattered to readers |
| WD-2 | companion outcome | Subscriptions to the paper's games rise after the purchase. | untestable: company reports only; no free series | step 3 |

### Barbie -> Barbiecore

Link: step 4, Fashion pivots to pink, 'Barbiecore' (timed, new article).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| BB-1 | persistence (a pivot, not a spike) | If fashion pivoted, the term outlived the film: views of the title Barbiecore in Jul 21 to Aug 19, 2024 are at least 15% of its highest 30-day mean between Jul 21, 2023 and Jan 31, 2024 (shape v1's raised-floor share). (exposure: the title check before registration showed Barbiecore is now a redirect to Barbie (the article was merged); its own title's views still count readers who asked for the word) | Barbiecore: mean 2024-07-21 to 2024-08-19 at least 15% of the peak 30-day mean | Barbie -> Barbiecore (timed): a term that lasted a season is a spike, not a fashion change |
| BB-2 | sibling stone, same mechanism | Wednesday (Netflix, Nov 23, 2022) sends readers to Gothic fashion. | views of Gothic fashion from 2022-11-23, lag 60 days | the screen -> fashion-term mechanism behind Barbie's step 4 |

### Chernobyl -> the real disaster

Link: step 2, Interest in the real disaster surges (measured: 48x, p = 0.013).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| CH-1 | companion outcome | The series sends readers to Acute radiation syndrome, which it depicts in detail. | views of Acute radiation syndrome from 2019-05-06, lag 60 days | narrows Chernobyl -> the disaster to the event itself |
| CH-2 | sibling stone, same mechanism | The Days (Netflix, Jun 1, 2023) sends readers to the Fukushima nuclear accident. | views of Fukushima nuclear accident from 2023-06-01, lag 60 days | the drama -> real disaster mechanism behind Chernobyl's step 2 |
| CH-3 | companion outcome (behavior) | Zone visitors rise in 2019 beyond the trend. | untestable: the State Agency's figures are a record, not a free series | steps 3 and 5 stay reported |

### Mr Bates -> the Horizon scandal

Link: steps 2 and 9, attention to the scandal and to Paula Vennells (measured: 370x, p = 0.023; 1,879x, p = 0.006).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| MB-1 | companion outcome | The drama sends readers to Fujitsu, which built Horizon. (exposure: the title appears in mark_first and mark_text record files (citations, not views)) | views of Fujitsu from 2024-01-01, lag 30 days | narrows the drama's ripple to people over institutions; steps 2 and 9 stand |
| MB-2 | companion outcome | The drama sends readers to Post Office Limited. | views of Post Office Limited from 2024-01-01, lag 30 days | narrows the drama's ripple; steps 2 and 9 stand |
| MB-3 | sibling stone, same mechanism | Toxic Town (Netflix, Feb 27, 2025) sends readers to the Corby toxic waste case. | views of Corby toxic waste case from 2025-02-27, lag 30 days | the UK drama -> real scandal mechanism that Mr Bates is the catalog's flagship for |

### The Daily Show -> the Zadroga Act

Link: step 5, Attention to the Act surges at Stewart's 2019 testimony (measured: 48.7x, p = 0.012).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| DZ-1 | companion outcome | The testimony (Jun 11, 2019) sends readers to the September 11th Victim Compensation Fund. | views of September 11th Victim Compensation Fund from 2019-06-11, lag 30 days | step 5's reading that the testimony moved attention to the program, not only the man |
| DZ-2 | companion outcome | The testimony sends readers to the World Trade Center Health Program. | views of World Trade Center Health Program from 2019-06-11, lag 30 days | step 5, as above |
| DZ-3 | sibling stone, same mechanism | Stewart's Capitol speech for the burn-pit bill (Jul 28, 2022) sends readers to the Honoring our PACT Act of 2022. | views of Honoring our PACT Act of 2022 from 2022-07-28, lag 30 days | the advocate -> attention to the bill mechanism of step 5 (a new article cannot be placebo-tested and is untestable here) |

### Ocean -> bottom trawling

Link: step 2, Attention to bottom trawling rises (measured: 4.6x, p = 0.004).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| OC-1 | sibling stone, same outcome | Seaspiracy (Netflix, Mar 24, 2021) moved the same series: Bottom trawling rises beyond chance. (exposure: Seaspiracy appears in the culture shelf's text files (sentences, not views)) | views of Bottom trawling from 2021-03-24, lag 45 days | Ocean -> bottom trawling: if a sibling film did not move the series, it may answer to policy news rather than films |
| OC-2 | companion outcome | The film sends readers to Marine protected area, the policy its campaign named. | views of Marine protected area from 2025-05-08, lag 45 days | the step 2 -> step 3 path (attention -> the consultation on protected areas) |
| OC-3 | sibling stone, same mechanism | Blue Planet II (BBC, Oct 29, 2017) sends readers to Marine plastic pollution. | views of Marine plastic pollution from 2017-10-29, lag 60 days | the nature documentary -> ocean issue mechanism behind Ocean's step 2 |

### The Surgeon General's advisory -> alcohol and cancer

Link: step 25, Attention to alcohol and cancer after the Surgeon General's advisory (measured: 4.2x, p = 0.035).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| AL-1 | seasonal check | The Jan 2025 rise is the advisory, not January: the same detector at Jan 3, 2024 and Jan 3, 2023 finds a smaller rise or none. | Alcohol and cancer: the detector at 2025-01-03 against the same date 1 and 2 years earlier | step 25 directly: the measured grade would be a January effect (New Year, Dry January), not the advisory |
| AL-2 | sibling stone, same outcome | Canada's Guidance on Alcohol and Health (Jan 17, 2023) moved the same series beyond chance. | views of Alcohol and cancer from 2023-01-17, lag 45 days | step 25's mechanism (an official warning -> attention) |
| AL-3 | companion outcome | The advisory sends readers to Alcohol and health as well. | views of Alcohol and health from 2025-01-03, lag 45 days | narrows step 25 to the cancer framing |

### Remote work -> Zoom towns

Link: step 2, Knowledge workers move to 'Zoom towns' (timed, new article).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| RW-1 | companion outcome | If knowledge workers untethered from offices, Digital nomad rises beyond chance within a year of Mar 13, 2020. | views of Digital nomad from 2020-03-13, lag 365 days | step 2's reading that location became optional (Zoom town is a new article with no placebo) |
| RW-2 | place with more exposure | Counties around the named Zoom towns gain population faster in 2020 to 2022 than their 2015 to 2019 trend. | untestable: county estimates need the Census API (keyed for bulk use) or FRED county series not loaded here | step 2 |

### Webb's first images -> astronomy

Link: step 2, Public interest in astronomy spikes (measured: 2.4x, p = 0.006).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| JW-1 | sibling stone, same mechanism | The first image of a black hole (Apr 10, 2019) sends readers to Black hole. (exposure: the title appears in the q4 and q6 result files (other tests at other dates; not read)) | views of Black hole from 2019-04-10, lag 30 days | the 'a picture from a telescope moves public interest' mechanism behind step 2 |
| JW-2 | companion outcome | The images send readers to the Hubble Space Telescope, the instrument they are compared with. | views of Hubble Space Telescope from 2022-07-11, lag 30 days | narrows step 2 |

### The GameStop squeeze

Link: step 1, Reddit traders squeeze GameStop (measured: 215x, p = 0.008).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| GS-1 | companion outcome | The squeeze spreads to the second meme stock: AMC Theatres rises beyond chance. (exposure: the title appears in editor_trail_v1.json (another event's test; not read)) | views of AMC Theatres from 2021-01-13, lag 60 days | step 1's reading as a retail-trader wave rather than one stock |
| GS-2 | companion outcome | The trading restrictions (Jan 28, 2021) send readers to Robinhood Markets. | views of Robinhood Markets from 2021-01-28, lag 14 days | the step 1 -> step 2 path |
| GS-3 | dose (a second stone, same outcome) | The May 13, 2024 return of the squeeze's best-known trader moves GameStop short squeeze again; secondary: by less than 215x. | views of GameStop short squeeze from 2024-05-13, lag 30 days; secondary: below 215.0x | slightly, the dose reading of step 1 |

### The headphone jack -> wireless earbuds

Link: step 2, Wireless earbuds take off (timed, new article).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| AP-1 | companion outcome | Removing the jack sends readers to Phone connector (audio). | views of Phone connector (audio) from 2016-09-07, lag 30 days | the removal -> earbuds path (step 1 -> step 2) |
| AP-2 | companion outcome | Removing the jack sends readers to Lightning (connector), the port that replaced it. | views of Lightning (connector) from 2016-09-07, lag 30 days | the removal -> earbuds path |

### TikTok's takeoff

Link: step 1, TikTok's For You feed takes off (timed, new article).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| TT-1 | companion outcome | The takeoff sends readers to ByteDance within the chain's own year-long window. (exposure: the title appears in a NYT-count screen and the mark_first lists (not views at this date)) | views of ByteDance from 2018-08-02, lag 365 days | narrows step 1; the timed link stands |
| TT-2 | companion outcome | Hit songs get shorter after 2018 faster than before. | untestable: Billboard and streaming data are not free as series; Spotify's API needs a key | steps 2 to 4 stay not testable |

### Thailand floods -> hard-drive prices

Link: step 4, Hard-drive prices spike (measured: PPI for storage devices, p = 0.036).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| TH-1 | companion outcome | The floods cut US imports of goods from Thailand beyond chance from Oct 2011. | FRED IMP5490 from 2011-10-08, down, h = 3 | step 4's premise that Thai production stopped at scale |
| TH-2 | specificity | The price shock is specific to disk drives: the producer price index for semiconductors does NOT rise beyond chance at the same date. | FRED PCU334413334413 from 2011-10-08, up, h = 3: must NOT be measured | step 4 directly: a general electronics price move would explain the storage-device rise |
| TH-3 | place with more exposure | Thailand's industrial production falls more than its neighbors' in Q4 2011. | untestable: the OECD production series for Thailand is not on FRED (404 on Oct 5, 2026) | step 1 -> step 4 |

### Cash for Clunkers -> used-car prices

Link: step 4, Used-car prices rise (measured: CPI used cars, p = 0.033).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| CC-1 | companion outcome | The rebates pull sales forward: total vehicle sales jump beyond chance in Jul to Aug 2009. | FRED TOTALSA from 2009-07-24, up, h = 2 | step 4's mechanism (trade-ins scrapped -> fewer used cars) starts with the sales the rebates bought |
| CC-2 | specificity | Scrappage removes used supply only: the CPI for new vehicles does NOT rise beyond chance at the same date. | FRED CUSR0000SETA01 from 2009-07-24, up, h = 6: must NOT be measured | step 4 directly: if new-car prices rose too, the used-car rise is general vehicle inflation |
| CC-3 | predicted lag (the pull-forward dip) | Sales borrowed from the future leave a hole: total vehicle sales fall beyond chance from Sep 2009. | FRED TOTALSA from 2009-09-01, down, h = 2 | the pull-forward reading of the program that step 4 rests on |

### The Queen's Gambit -> chess

Link: step 2, People look up chess and chess sets (measured: 3.9x, p = 0.009).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| QG-1 | companion outcome | The show sends readers to Grandmaster (chess). | views of Grandmaster (chess) from 2020-10-23, lag 60 days | narrows step 2 |
| QG-2 | companion outcome | The show sends readers to the opening it is named for, the Queen's Gambit. | views of Queen's Gambit from 2020-10-23, lag 60 days | narrows step 2 |

### Toilet paper panic -> bidets

Link: step 1, Panic buying (measured: grocery sales, p = 0.002); step 2, People look up bidets (measured: 13x, p = 0.010).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| TP-1 | persistence (adoption, not curiosity) | If people adopted bidets, interest stayed raised: Bidet's mean daily views for Mar 1 to Dec 31, 2021 are at least 1.5 times those for Mar 1 to Dec 31, 2019. | Bidet: mean 2021-03-01 to 2021-12-31 at least 1.5x the mean 2019-03-01 to 2019-12-31 | step 2's reading as a durable change in behavior; the measured attention spike stands |
| TP-2 | companion outcome | The panic sends readers to Toilets in Japan (the washlet). | views of Toilets in Japan from 2020-03-11, lag 60 days | narrows step 2 |

### Squid Game -> ddakji

Link: step 12, Interest in ddakji surges (measured: 6,500x, p = 0.008).

| ID | Kind | Implication | Test | If it fails, it weakens |
|---|---|---|---|---|
| SG-1 | dose (a second stone, same outcome) | Season 2 (Dec 26, 2024) moves Ddakji again; secondary: by less than the first season's 6,500x. | views of Ddakji from 2024-12-26, lag 60 days; secondary: below 6499.7x | slightly, the dose reading of step 12 |
| SG-2 | companion outcome (a product category) | The show sends readers to Vans, the white slip-ons its players wear. (exposure: the title appears in the mark_first lists (not views)) | views of Vans from 2021-09-17, lag 60 days | narrows step 12 to the games |
| SG-3 | place with more exposure (the culture) | The show sends readers to the Korean Wave. | views of Korean Wave from 2021-09-17, lag 60 days | narrows step 12 to the games |

## What a result will and will not mean

A held implication is support from outside the measured series, never proof of cause; the same caveat as every
measured grade applies (order and an unusual rise, not mechanism). A failed companion outcome usually narrows a ripple
(readers went to the thing itself and nowhere else) rather than breaking it. A failed specificity test, seasonal check
or same-outcome sibling bears on the measured link directly, and the results file will say so for each one.
