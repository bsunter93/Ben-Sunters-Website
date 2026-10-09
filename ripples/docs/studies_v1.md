# Study-backed ripples (Oct 8, 2026)

## What this is

The shelf was mostly laws. This pilot looked for published studies that measured what a film, a show, a broadcast,
a celebrity moment or a public event changed in how people live. The verified finds now ship as 40 stories under
Engine leads, group "From published studies". Stories whose claimed link is busted or disputed sit in a new shelf
group, "Myths, checked".

## The pilot

**Plan:** registered before any harvest request, 10/08/2026 8:39 PM PT. sha256
`00bc825363875dd853d410b019818da2b51f1cd3df4157c50a8b07a954406379` (`docs/studies_plan_v1.md`, the registered file
itself). A supplemental round (Crossref and two PubMed queries for families OpenAlex never answered) was written down at
9:01 PM, after the main harvest (`docs/studies_plan_v1_addendum.md`). Its finds are reported apart and do not count
toward the bars.

**Sources:** OpenAlex (main), PubMed for health families, Crossref as backup. 64 frozen query families. A link exists
only when the paper itself names the stone. A study with a comparison design (difference in differences, interrupted
time series, natural experiment, regression discontinuity, synthetic control, panel, randomized trial) grades
Measured. A plain before and after grades On the record.

| Bar | Result | Met |
|---|---|---|
| 40 or more distinct (stone, outcome) links | 58 qualifying; 53 shipped after verification | yes |
| 60% or more outside law and government | 47 of 53 (89%) | yes |
| 20 or more links relevant to many (reach 4 or 5) | 40 | yes |
| Every shipped candidate verified on its own page | 53 of 56 ranked links verified; 3 unverified held back; 2 dropped by verification | yes |
| Stone dates from sources other than Wikipedia | every date from the paper or a second paper; one period newspaper check (1889) | partly |

**Counts:** 5,204 records harvested (4,877 unique, 4,246 with abstracts), about 85 qualifying papers, 58 qualifying
links, 53 shipped by the pilot, 4 of them contested in print. 15 busted or disputed claims, 14 verified.

## What verification changed

- The Ramayan diet claim is absent from the current NBER abstract. Dropped.
- The TikTok and Universal Music paper reversed its sign between versions. The current version finds that pulling
  the catalog lowered Spotify demand. Moved to the disputed list.
- The Super Bowl ads and Oprah papers say different things in their published versions than in the working papers.
  Both were rewritten to the published claims.
- OpenAlex returned 429 at query 98 of 101 and was stopped for the day; the 4 lost queries ran on Crossref. Five
  publisher hosts returned 403 and were stopped for the day. One rule slip (2 extra requests to a blocked host through
  a redirect) is logged and fixed in the pilot's fetcher.

## What ships, and what was left out

Of the 53 verified links and 14 verified busted rows:

| Group | Stories |
|---|---|
| Measured, with a lasting mark (Behavior: births, names, school, smoking and other habits) | 9 |
| Measured, no lasting mark | 21 |
| On the record (a descriptive count in a published study) | 2 |
| Busted or disputed ("Myths, checked") | 8 |
| **Total** | **40** |

Left out, and why:

- **Suicide, self-harm and overdose (8 links, 4 busted rows).** The owner ruled on Oct 5 that the 13 Reasons Why
  suicide ripple does not ship. The ruling applies to the whole class: the deaths of Diana, Robin Williams, Kate Spade
  and Anthony Bourdain, three K-pop singers and Lee Eun-ju; 13 Reasons Why (two links); Pokémon Go and self-harm; and
  the busted rows on Squid Game, 13 Reasons Why, Robin Williams abroad and Crown Prince Rudolf.
- **Party votes and vote shares (2 links).** Fox News and Republican votes; Ramayan and BJP state election wins.
- **No usable date in the inputs (9 links, 2 busted rows).** Every date comes from the pilot's files and the papers'
  own pages. These rows give no year for the stone: Super Bowl ads ("annual"), Oprah's book picks, cable TV in Indian
  villages, NFL upset losses and family violence, Mohamed Salah and hate crimes, MTV Shuga in Nigeria, and the busted
  rows on telenovela product placement and Universal Music leaving TikTok. Fox News and local budgets has a stone date
  but no outcome window. West German TV in East German homes (fertility and crimes against refugees) is dated only
  "before 1990".
- **Not verified by the pilot (3 links, 1 busted row).** Violent video games, the UK digital TV switchover, the
  Korean Wave and tourism, and Harry Potter and the Indonesian owl trade.
- **Merged.** Two measured links are disputed in print, and the pilot's busted list carries the dispute: 16 and
  Pregnant (a 2018 reanalysis) and England's 1998 penalty loss (a 2010 study of Italy and a review). Each ships as one
  story, graded Disputed, with both papers on its source line.

## How a study reads on the page

- **The grade says who measured it.** A step from a study reads "Measured in a published study (difference in
  differences): ..." with its effect, and its source link is the paper's DOI. Our own measured grades keep their
  wording. The How sure text says we did not rerun the study.
- **The chart.** A study step is a dot. Where the paper gives its window as years, a pale band shows the window. The
  caption's kicker carries the effect when the paper gives one ("+18%", "+64%").
- **Dates.** A stone known only by its year or month shows only that. A recurring stone (each Super Bowl, each World
  Cup) is dated to the first year of the study's window, and the step text says so.
- **Myths, checked.** The shelf group holds every story whose claimed link is busted or disputed, placed after "Stones
  that changed how people live". Two older stories moved there with the new ones: Top Gun's recruitment claim and the
  ethanol law's tortilla riots.
- **The checker.** `lab/chain_check.py` has a new test type, `study`: dated by the start of the study's own window,
  graded from the chain (measured, reported, busted, disputed), held to the same order rule as every step.

## The shipped list

| # | Story | Grade | Mark | Paper (DOI) | Slug |
|---|---|---|---|---|---|
| 1 | Oklahoma City bombing → more babies in Oklahoma County | Measured | Behavior | 10.1353/dem.2005.0034 | `study-okc-births` |
| 2 | Sesame Street → more kids at the right grade for their age | Measured | Behavior | 10.1257/app.20170300 | `study-sesame-school` |
| 3 | Television → about 11 million more smokers | Measured | Behavior | 10.1093/jcr/ucz024 | `study-tv-smoking` |
| 4 | Brazil's telenovelas → smaller families | Measured | Behavior | 10.1257/app.4.4.1 | `study-globo-family-size` |
| 5 | Brazil's telenovelas → babies named after characters | Measured | Behavior | 10.1257/app.4.4.1 | `study-globo-names` |
| 6 | Zanzibar's month-long blackout → a baby boom | Measured | Behavior | 10.1007/s13524-014-0316-7 | `study-zanzibar-blackout` |
| 7 | Ramayan on TV → more traditionally Hindu baby names | Measured | Behavior | 10.3386/w33417 | `study-ramayan-names` |
| 8 | A Tanzanian radio soap → more family planning | Measured | Behavior | 10.1080/10810730050131398 | `study-twende-family-planning` |
| 9 | Sideways → wine buyers moved from Merlot to Pinot Noir | Measured | Behavior | 10.1017/s193143610000081x | `study-sideways-wine` |
| 10 | Super Bowl → more flu deaths among seniors | Measured |  | 10.1162/ajhe_a_00036 | `study-superbowl-flu` |
| 11 | Pokémon Go → players walked more | Measured |  | 10.2196/jmir.6759 | `study-pokemon-steps` |
| 12 | Katie Couric's colonoscopy → more colonoscopies | Measured |  | 10.1001/archinte.163.13.1601 | `study-couric-colonoscopy` |
| 13 | Violent blockbusters → fewer assaults that night | Measured |  | 10.1162/qjec.2009.124.2.677 | `study-violent-movies` |
| 14 | Angelina Jolie's op-ed → more BRCA gene tests | Measured |  | 10.1136/bmj.i6357 | `study-jolie-brca` |
| 15 | Game of Thrones → more tourists in Dubrovnik | Measured |  | 10.1002/jtr.2142 | `study-got-dubrovnik` |
| 16 | Fox News → longer sentences from elected judges | Measured |  | 10.1093/ej/uead108 | `study-fox-sentences` |
| 17 | Ice Bucket Challenge → a short rise in giving | Measured |  | 10.1016/j.joep.2023.102624 | `study-ice-bucket-giving` |
| 18 | Jade Goody's diagnosis → half a million extra cervical screenings | Measured |  | 10.1258/jms.2012.012028 | `study-goody-screening` |
| 19 | England's World Cup games → more domestic abuse reports | Measured |  | 10.1177/0022427813494843 | `study-worldcup-abuse` |
| 20 | Nazi radio → more denunciations of Jews | Measured |  | 10.1093/qje/qjv030 | `study-nazi-radio` |
| 21 | Kylie Minogue's diagnosis → more breast scans for young women | Measured |  | 10.1093/ije/dyn090 | `study-kylie-scans` |
| 22 | Brazil's telenovelas → more divorce | Measured |  | 10.18235/0010906 | `study-globo-divorce` |
| 23 | Angelina Jolie's op-ed → more preventive mastectomies | Measured |  | 10.1007/s10549-018-4824-9 | `study-jolie-mastectomy` |
| 24 | Brazil's World Cup games → fewer heart attack admissions | Measured |  | 10.14740/cr2271 | `study-brazil-worldcup-heart` |
| 25 | Charlie Sheen's disclosure → HIV test kit sales nearly doubled | Measured |  | 10.1007/s11121-017-0792-2 | `study-sheen-hiv-tests` |
| 26 | Sideways → California growers grew more Pinot Noir | Measured |  | 10.1017/jwe.2021.26 | `study-sideways-vines` |
| 27 | Ramayan on TV → more Hindu-Muslim violence | Measured |  | 10.3386/w33417 | `study-ramayan-violence` |
| 28 | A movie on free TV → more DVD sales | Measured |  | 10.2307/20650294 | `study-movie-tv-dvd` |
| 29 | College football upsets → longer juvenile sentences | Measured |  | 10.1257/app.20160390 | `study-football-judges` |
| 30 | Magic Johnson's announcement → more HIV tests | Measured |  | PubMed 7646947 | `study-magic-hiv-tests` |
| 31 | Chadwick Boseman's death → more colon cancer donations | On the record |  | 10.2196/29387 | `study-boseman-donations` |
| 32 | Blackfish → SeaWorld ends orca breeding | On the record |  | 10.1002/pan3.10221 | `study-blackfish` |
| 33 | Finding Dory → a run on blue tang? | Busted |  | 10.1007/s13280-019-01233-7 | `study-finding-dory` |
| 34 | Harry Potter → a craze for pet owls? | Busted |  | 10.1371/journal.pone.0182368 | `study-potter-owls` |
| 35 | Blue Planet II → less plastic use? | Busted |  | 10.1111/csp2.280 | `study-blue-planet-plastic` |
| 36 | 16 and Pregnant → fewer teen births? | Disputed |  | 10.1080/07350015.2018.1497510 (original estimate: 10.1257/aer.20140012) | `study-sixteen-pregnant` |
| 37 | Hosting the Olympics → a more active country? | Busted |  | 10.1016/s0140-6736(21)01165-x | `study-olympics-sport` |
| 38 | Angelina Jolie's op-ed → more routine mammograms? | Busted |  | 10.1016/j.jacr.2017.03.016 | `study-jolie-mammograms` |
| 39 | England's World Cup loss → more heart attacks? | Disputed |  | 10.1093/ije/dyq007 (original estimate: 10.1136/bmj.325.7378.1439) | `study-england-argentina-heart` |
| 40 | Taylor Swift in the stands → a better Travis Kelce? | Busted |  | 10.1371/journal.pone.0315560 | `study-swift-kelce` |

Each step's quote is the paper's own words, under 25 words. The quotes, effects and dates come from the pilot's
`links.csv`, `busted.csv` and the verified pages.

## Openers to consider

Tiger King stays the opener. By reach, surprise and fame, the strongest new candidates are Super Bowl → more flu deaths
among seniors, Oklahoma City bombing → more babies in Oklahoma County, Television → about 11 million more smokers,
Sesame Street → more kids at the right grade for their age, and Zanzibar's month-long blackout → a baby boom.

## Also on Oct 8

The dog breed, words and degrees pilots: `docs/pilots_oct8.md`. Sources beyond Wikipedia: `docs/data_sources_v4.md`.
