# What else should be true: implications v1, results

Run Oct 5, 2026 under `docs/implications_plan_v1.md`, registered and pushed in commit `ff867c6` (Oct 5, 07:27:45 UTC;
the plan's header says 07:40, which was written ahead of the commit; the commit time is the registration). Code:
`lab/implications_check.py`, which calls the checker's own functions unchanged (`chain_check.wiki_test`, `fred`,
`series_test`, `ssa_test`, `verdict`). Data: `docs/results/implications_v1.json`. No source refused during the run.

## Headline

**52 implications over 20 ripples: 20 held, 20 failed, 12 untestable.** Of the 40 that could be tested, half held.
The ripples split cleanly into three groups.

| Group | Ripples | What the implications said |
|---|---|---|
| **Strengthened** (every testable implication held) | Mr Bates -> the Horizon scandal (3 of 3), Webb's first images (2 of 2), The Queen's Gambit (2 of 2), Thailand floods -> disk-drive prices (2 of 2), Remote work (1 of 1) | Mr Bates' companions held and so did its sibling: Toxic Town sent readers to the Corby toxic waste case at 1,822 times its baseline (p = 0.004). The floods cut US imports from Thailand (p = 0.021) and left the semiconductor price index flat (p = 0.98), so the disk-drive price rise is specific. The first black-hole image moved Black hole as Webb moved astronomy. |
| **Mostly held** | GameStop (2 of 3), Cash for Clunkers (2 of 3), Chernobyl (1 of 2), The Daily Show -> Zadroga (1 of 2), the advisory -> alcohol and cancer (1 of 3) | The two specificity tests that bear on measured links held: new-car prices did not rise with used-car prices (p = 0.19), and the Jan 2025 rise in Alcohol and cancer beat the same detector at Jan 2024 (no rise) and Jan 2023 (3.1x) with 4.2x. |
| **Weakened** | Ocean -> bottom trawling (0 of 3), Squid Game -> ddakji (0 of 3), Tiger King -> big cats (1 of 3), Toilet paper -> bidets (0 of 2), Barbie -> Barbiecore (see below), Frozen -> Elsa (1 of 2), Wordle (0 of 1), Pokémon GO (0 of 1) | Detailed next. |

No implication could be tested for the headphone jack or TikTok: their stones predate the checker's placebo history
(pageviews start Jul 2015) or their companion is a new article.

## The failures, and what each weakens

- **Ocean -> bottom trawling (measured, 4.6x, p = 0.004) is weakened directly.** The same series did not respond beyond
  chance to the sibling film Seaspiracy (3.1x, p = 0.094), and neither companion moved (Marine protected area after
  Ocean; Marine plastic pollution after Blue Planet II: no sustained rise). The measured link stands as one film's
  echo, not as a mechanism the series shows twice.
- **Squid Game -> ddakji (measured) is narrowed.** Season 2 lifted Ddakji 92 times its baseline but at p = 0.052, one
  hair over the line, so the dose implication fails as registered. Vans and the Korean Wave did not move. The ripple is
  the games themselves, nothing wider.
- **Tiger King -> big cats (measured, 5.1x) is weakened as a general mechanism, not as a lockdown-era fact.** Tiger
  King 2 did not move Big cat or Exotic pet, and The Elephant Whisperers did not move Indian elephant. The specificity
  test held, narrowly: Giraffe, an animal the show never shows, also rose 2.9 times at the same date, within chance
  (p = 0.17). Lockdown lifted animal pages; Tiger King lifted big cats beyond that.
- **Toilet paper -> bidets: the adoption reading fails.** Bidet's mean daily views in Mar to Dec 2021 were 1.14 times
  those of 2019 (the bar was 1.5). The measured spike of Mar 2020 stands; the chain's later steps (installs, plumbers,
  new homes) assume an adoption the attention data do not show. Toilets in Japan rose 2.5 times, within chance.
- **Barbie -> Barbiecore (timed) rests on too little.** BB-1 held by its registered rule (the late level was 65% of the
  peak), but the peak 30-day mean was 7.5 views a day; the article drew under 10 views a day at its height and has since
  been merged into Barbie. A held test on that series carries no weight, and the sibling (Wednesday -> Gothic fashion)
  failed. The timed link dates an article's creation, not a fashion change.
- **Frozen -> Elsa (measured, 2014): a fad, not repeated.** The name fell from 1,107 in 2014 to 368 in 2017, as a
  film-driven fad should (held), but Frozen 2 did not move it: 312 in 2019, 241 in 2020 (p = 0.89). The 2014 surge
  reads as a one-time response to a new character.
- **Smaller narrowings.** The Daily Show's testimony moved the Victim Compensation Fund (35x, p = 0.012) but not the
  World Trade Center Health Program (4.2x, p = 0.17). The advisory moved Alcohol and cancer but not Alcohol and health,
  and Canada's 2023 guidance moved it 3.1 times, within chance (p = 0.14). Wordle's purchase did not move The New York
  Times crossword. Pokémon GO did not revive its 1996 games' page. The Days did not move the Fukushima accident's page.
  GameStop's May 2024 return moved its page 3.6 times, within chance (p = 0.28).
- **Cash for Clunkers' sales jump failed by the ordering rule** (a move beyond chance, p = 0.003, but the series test
  dates its onset to Mar 2009, the recovery from the trough, four months before the rebates). The pull-forward dip from
  Sep 2009 held (p = 0.007) and the specificity test held, so the measured used-car link is untouched; monthly sales
  cannot separate the rebates from the rebound.

## Every implication

**Frozen -> Elsa**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| FZ-1 | dose (a second stone, same outcome) | Frozen 2 (Nov 22, 2019) moves the name again: Elsa rises in 2020 beyond chance against every other year. | **failed** (effect -0.258, p = 0.885) | log change -0.258, p = 0.885 |
| FZ-2 | sibling stone, same mechanism | Encanto (Nov 24, 2021) moves the name Mirabel in 2022. | **untestable** | ssa.gov refused the request (HTTP 403 to the honest user agent, Oct 5, 2026); per the rules no retry and no other route today |
| FZ-3 | persistence (a fad, not a trend) | If the film caused the 2014 rise, the name falls back as the film fades: Elsa in 2017 is below Elsa in 2014. | **held** | 2017: 368 against 2014: 1107 |

**Tiger King -> big cats**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| TK-1 | dose (a second stone, same outcome) | Tiger King 2 (Nov 17, 2021) moves Big cat and Exotic pet again, beyond chance; secondary: by less than the first season's 5.1x. | **failed** | no sustained rise |
| TK-2 | sibling stone, same mechanism | The Elephant Whisperers (Netflix, Dec 8, 2022) sends readers to the Indian elephant. | **failed** | no sustained rise |
| TK-3 | specificity (the lockdown confound) | An animal Tiger King never shows does NOT rise at the same date: Giraffe is flat after Mar 20, 2020. | **held** (2.9x, p = 0.168, onset 2020-03-28) | no rise beyond chance |

**Pokémon GO's launch**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| PG-1 | companion outcome | The launch sends readers to Ingress, Niantic's earlier game whose portals became PokeStops. | **untestable** (35.5x, p = None, onset 2016-07-08) | too short a history: no placebo is possible |
| PG-2 | companion outcome | The launch revives the franchise's first games: Pokemon Red, Blue, and Yellow rises beyond chance. | **failed** | no sustained rise |
| PG-3 | companion outcome (behavior) | Players walk more in the first weeks and fall back (the chain's step 2 rests on Howe et al., BMJ 2016). | **untestable** | step counts are in the paper, not in a free series |

**Wordle**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| WD-1 | companion outcome | After the purchase (Jan 31, 2022), readers look up The New York Times crossword. | **failed** | no sustained rise |
| WD-2 | companion outcome | Subscriptions to the paper's games rise after the purchase. | **untestable** | company reports only; no free series |

**Barbie -> Barbiecore**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| BB-1 | persistence (a pivot, not a spike) | If fashion pivoted, the term outlived the film: views of the title Barbiecore in Jul 21 to Aug 19, 2024 are at least 15% of its highest 30-day mean between Jul 21, 2023 and Jan 31, 2024 (shape v1's raised-floor share). | **held** | late mean 5 a day is 64.7% of the peak 30-day mean (7) |
| BB-2 | sibling stone, same mechanism | Wednesday (Netflix, Nov 23, 2022) sends readers to Gothic fashion. | **failed** | no sustained rise |

**Chernobyl -> the real disaster**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| CH-1 | companion outcome | The series sends readers to Acute radiation syndrome, which it depicts in detail. | **held** (36.1x, p = 0.013, onset 2019-05-10) | a sustained rise beyond chance, in order |
| CH-2 | sibling stone, same mechanism | The Days (Netflix, Jun 1, 2023) sends readers to the Fukushima nuclear accident. | **failed** | no sustained rise |
| CH-3 | companion outcome (behavior) | Zone visitors rise in 2019 beyond the trend. | **untestable** | the State Agency's figures are a record, not a free series |

**Mr Bates -> the Horizon scandal**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| MB-1 | companion outcome | The drama sends readers to Fujitsu, which built Horizon. | **held** (11.2x, p = 0.005, onset 2024-01-03) | a sustained rise beyond chance, in order |
| MB-2 | companion outcome | The drama sends readers to Post Office Limited. | **held** (111.2x, p = 0.045, onset 2024-01-04) | a sustained rise beyond chance, in order |
| MB-3 | sibling stone, same mechanism | Toxic Town (Netflix, Feb 27, 2025) sends readers to the Corby toxic waste case. | **held** (1821.5x, p = 0.004, onset 2025-02-27) | a sustained rise beyond chance, in order |

**The Daily Show -> the Zadroga Act**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| DZ-1 | companion outcome | The testimony (Jun 11, 2019) sends readers to the September 11th Victim Compensation Fund. | **held** (35.2x, p = 0.012, onset 2019-06-11) | a sustained rise beyond chance, in order |
| DZ-2 | companion outcome | The testimony sends readers to the World Trade Center Health Program. | **failed** (4.2x, p = 0.173, onset 2019-06-12) | a rise within chance |
| DZ-3 | sibling stone, same mechanism | Stewart's Capitol speech for the burn-pit bill (Jul 28, 2022) sends readers to the Honoring our PACT Act of 2022. | **untestable** | a new article (first day 2022-08-07): no placebo is possible |

**Ocean -> bottom trawling**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| OC-1 | sibling stone, same outcome | Seaspiracy (Netflix, Mar 24, 2021) moved the same series: Bottom trawling rises beyond chance. | **failed** (3.1x, p = 0.094, onset 2021-04-04) | a rise within chance |
| OC-2 | companion outcome | The film sends readers to Marine protected area, the policy its campaign named. | **failed** | no sustained rise |
| OC-3 | sibling stone, same mechanism | Blue Planet II (BBC, Oct 29, 2017) sends readers to Marine plastic pollution. | **failed** | no sustained rise |

**The advisory -> alcohol and cancer**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| AL-1 | seasonal check | The Jan 2025 rise is the advisory, not January: the same detector at Jan 3, 2024 and Jan 3, 2023 finds a smaller rise or none. | **held** | 4.2x against 1.0x, 3.1x |
| AL-2 | sibling stone, same outcome | Canada's Guidance on Alcohol and Health (Jan 17, 2023) moved the same series beyond chance. | **failed** (3.1x, p = 0.143, onset 2023-01-17) | a rise within chance |
| AL-3 | companion outcome | The advisory sends readers to Alcohol and health as well. | **failed** | no sustained rise |

**Remote work -> Zoom towns**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| RW-1 | companion outcome | If knowledge workers untethered from offices, Digital nomad rises beyond chance within a year of Mar 13, 2020. | **held** (3.9x, p = 0.01, onset 2021-01-06) | a sustained rise beyond chance, in order |
| RW-2 | place with more exposure | Counties around the named Zoom towns gain population faster in 2020 to 2022 than their 2015 to 2019 trend. | **untestable** | county estimates need the Census API (keyed for bulk use) or FRED county series not loaded here |

**Webb's first images -> astronomy**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| JW-1 | sibling stone, same mechanism | The first image of a black hole (Apr 10, 2019) sends readers to Black hole. | **held** (38.1x, p = 0.013, onset 2019-04-10) | a sustained rise beyond chance, in order |
| JW-2 | companion outcome | The images send readers to the Hubble Space Telescope, the instrument they are compared with. | **held** (7.7x, p = 0.025, onset 2022-07-12) | a sustained rise beyond chance, in order |

**The GameStop squeeze**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| GS-1 | companion outcome | The squeeze spreads to the second meme stock: AMC Theatres rises beyond chance. | **held** (20.8x, p = 0.008, onset 2021-01-27) | a sustained rise beyond chance, in order |
| GS-2 | companion outcome | The trading restrictions (Jan 28, 2021) send readers to Robinhood Markets. | **held** (81.9x, p = 0.008, onset 2021-01-28) | a sustained rise beyond chance, in order |
| GS-3 | dose (a second stone, same outcome) | The May 13, 2024 return of the squeeze's best-known trader moves GameStop short squeeze again; secondary: by less than 215x. | **failed** (3.6x, p = 0.281, onset 2024-05-15) | a rise within chance |

**The headphone jack -> earbuds**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| AP-1 | companion outcome | Removing the jack sends readers to Phone connector (audio). | **untestable** (4.0x, p = None, onset 2016-09-07) | too short a history: no placebo is possible |
| AP-2 | companion outcome | Removing the jack sends readers to Lightning (connector), the port that replaced it. | **untestable** (6.7x, p = None, onset 2016-09-07) | too short a history: no placebo is possible |

**TikTok's takeoff**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| TT-1 | companion outcome | The takeoff sends readers to ByteDance within the chain's own year-long window. | **untestable** | a new article (first day 2018-06-15): no placebo is possible |
| TT-2 | companion outcome | Hit songs get shorter after 2018 faster than before. | **untestable** | Billboard and streaming data are not free as series; Spotify's API needs a key |

**Thailand floods -> disk-drive prices**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| TH-1 | companion outcome | The floods cut US imports of goods from Thailand beyond chance from Oct 2011. | **held** (effect -0.1814, p = 0.021, onset 2011-11-01) | a move beyond chance, in order |
| TH-2 | specificity | The price shock is specific to disk drives: the producer price index for semiconductors does NOT rise beyond chance at the same date. | **held** (effect -0.04, p = 0.976, onset 2011-05-01) | no movement |
| TH-3 | place with more exposure | Thailand's industrial production falls more than its neighbors' in Q4 2011. | **untestable** | the OECD production series for Thailand is not on FRED (404 on Oct 5, 2026) |

**Cash for Clunkers -> used-car prices**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| CC-1 | companion outcome | The rebates pull sales forward: total vehicle sales jump beyond chance in Jul to Aug 2009. | **failed** (effect 0.2511, p = 0.003, onset 2009-03-01) | moved, wrong order |
| CC-2 | specificity | Scrappage removes used supply only: the CPI for new vehicles does NOT rise beyond chance at the same date. | **held** (effect 0.0214, p = 0.188, onset 2009-05-01) | no movement |
| CC-3 | predicted lag (the pull-forward dip) | Sales borrowed from the future leave a hole: total vehicle sales fall beyond chance from Sep 2009. | **held** (effect -0.263, p = 0.007) | a move beyond chance, in order |

**The Queen's Gambit -> chess**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| QG-1 | companion outcome | The show sends readers to Grandmaster (chess). | **held** (7.3x, p = 0.034, onset 2020-10-25) | a sustained rise beyond chance, in order |
| QG-2 | companion outcome | The show sends readers to the opening it is named for, the Queen's Gambit. | **held** (89.5x, p = 0.009, onset 2020-10-25) | a sustained rise beyond chance, in order |

**Toilet paper panic -> bidets**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| TP-1 | persistence (adoption, not curiosity) | If people adopted bidets, interest stayed raised: Bidet's mean daily views for Mar 1 to Dec 31, 2021 are at least 1.5 times those for Mar 1 to Dec 31, 2019. | **failed** | 1413 against 1242 a day: 1.14x |
| TP-2 | companion outcome | The panic sends readers to Toilets in Japan (the washlet). | **failed** (2.5x, p = 0.21, onset 2020-03-13) | a rise within chance |

**Squid Game -> ddakji**

| ID | Kind | Implication | Result | Reading |
|---|---|---|---|---|
| SG-1 | dose (a second stone, same outcome) | Season 2 (Dec 26, 2024) moves Ddakji again; secondary: by less than the first season's 6,500x. | **failed** (92.2x, p = 0.052, onset 2024-12-27) | a rise within chance |
| SG-2 | companion outcome (a product category) | The show sends readers to Vans, the white slip-ons its players wear. | **failed** | no sustained rise |
| SG-3 | place with more exposure (the culture) | The show sends readers to the Korean Wave. | **failed** | no sustained rise |
## Disclosures

- **One classification was corrected to the plan's rule before this report.** The first run scored TT-1 (ByteDance) as
  failed by order, because the checker's verdict for a new article created before the date is "wrong order". The plan
  says a new article is untestable, and the checker's own main loop treats a new article's first day as dating the
  article, not the phenomenon. The code now applies that rule (`lab/implications_check.py`), and the full run was
  repeated; no other result changed.
- **BB-1 is reported as held because the registered rule says so;** the text above explains why it carries no weight.
- **SG-1 misses at p = 0.052.** It is a failure as registered and stays one.
- **Exposure:** candidates whose series already sat in repository result files were dropped before registration (the
  plan lists them). Kept titles that appear in repository files are marked in the plan; none of those files held a
  test at the registered date.
- **Untestable, 12:** 7 by design (no free series: step counts, subscriptions, tourism figures, county population,
  song lengths, Thailand's production index; and Mirabel, because ssa.gov refused the request with a 403 on Oct 5
  and nothing was retried), 3 because the stone predates the placebo history (Pokémon GO, both headphone-jack
  implications), 2 because the companion is a new article (the PACT Act, ByteDance).

## Limits

- Every wiki implication is attention, with the checker's strengths and limits: an unusual rise in the right order, not
  mechanism. A held implication is support from outside the measured series, never proof.
- Companion outcomes were chosen by one author before testing; a different author would choose differently. The
  specificity tests, the seasonal check and the same-outcome sibling are the ones that bear on a measured link
  directly; companions mostly narrow or widen a ripple.
- Siblings vary in size: The Days and Tiger King 2 were far smaller stones than Chernobyl and Tiger King, so their
  failures say "not at that dose" as much as "not that mechanism".
- The name tests use the 27 years of counts already in the Frozen chain; the placebo pool includes the 2014 surge,
  which makes FZ-1 conservative.
