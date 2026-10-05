# Screen v1: a language model in place of the hand screen (Oct 5, 2026)

The result of `docs/screen_plan_v1.md` (registered in commit `57ae1d3`, before any label existed). A language model
applied the rubric `lab/discovery/screen_rubric.md` v1 to 583 candidates from the discovery runs, blind, from their text
fields alone. The labels were committed and pushed in `8f41b92` before any hand decision was opened. This doc compares
them with the person's decisions.

**Verdict: the bar is not met.** Precision clears it (0.86 against 0.61) and no decoy passed, but recall of the
person's kept marks is 0.56 against 0.80. Under rubric v1 the screen cannot replace the person for the first pass. What
it can do now is cut the person's reading by six sevenths with almost nothing false in what it passes. It would also
miss 44% of the marks the person kept.

## What ran

| Step | What | Where |
|---|---|---|
| Rubric v1 | is_mark, link_label, date_ok, disputed, a gate, one reason code from the owner's list, flags, four scores | `lab/discovery/screen_rubric.md` |
| Frozen sets | 583 candidates, candidate fields only | `docs/results/screen_candidates_v1.json` (`lab/discovery/screen_sets.py`) |
| Blind labels | one pass, one labeler (a language model in a working session, no API) | `docs/results/screen_labels_v1.json` |
| Comparison | hand decisions matched, metrics, confusion lists | `docs/results/screen_compare_v1.json` (`lab/discovery/screen_compare.py`) |
| Labeled corpus | every candidate: decision, reason code, flags, scores, and the person's decision | `docs/results/screen_corpus_v1.json` |
| Automation | the same rubric through an API, **not run** | `lab/discovery/screen.py` |

## Against the registered bar (pooled over E1 to E4)

| Bar | Registered | Result | |
|---|---|---|---|
| Precision | at least 0.61 | **0.863** (63 of 73 passes were kept) | met |
| Recall on kept marks | at least 0.80 | **0.562** (59 of 105 kept marks) | **not met** |
| Decoys passed (E5) | 0 | **0 of 33** (and 0 of 11 in E6) | met |

Agreement with the person, candidate by candidate: 0.84, Cohen's kappa 0.51 (516 candidates). Sentence-level recall:
0.46 (63 of 136 kept sentences).

### By set

| Set | Candidates | Person kept | Screen passed | Precision | Recall (marks) | Kappa |
|---|---|---|---|---|---|---|
| E1 strict reverse pairs | 23 | 14 | 13 | 1.00 | 0.93 (13 of 14) | 0.91 |
| E2 held-out forward | 47 | 13 | 8 | 1.00 | 0.73 (8 of 11) | 0.70 |
| E3 v1.1, sixty stones | 213 | 79 | 43 | 0.81 | 0.57 (31 of 54) | 0.42 |
| E4 culture shelf | 233 | 30 | 9 | 0.78 | 0.27 (7 of 26) | 0.32 |

### By class (secondary verdicts)

| Class | Precision | Recall (marks) | Decoys | Verdict |
|---|---|---|---|---|
| Events | 0.86 | 0.63 (45 of 71) | n/a | not met |
| Culture | 0.88 | 0.41 (14 of 34) | 0 of 33 | not met |

### On the candidates the labeler did not recognize from the docs

The docs read before labeling quote many of the kept marks, so 82 of the 516 candidates were flagged `seen_in_docs`. On
the other 434: precision **0.71**, recall **0.43** (21 of 49 marks), kappa 0.40. Events: 0.74 and 0.54. Culture: 0.50
and 0.14 (2 of 14). Both readings fail the recall bar. The unseen subset is not a random sample: the docs mostly quote
kept marks, so it leans toward rejections. It is still the fairest view of how the rubric does on text it has not met.

### Two checks that do not depend on the judgment matches

24 candidates were matched to a kept mark by hand rather than by sentence (each one listed in `screen_compare_v1.json`,
`judged_matches`; for example, WF006, which states the Homeland Security Act that the product cites through another
sentence). With only the mechanical sentence matches: precision 0.85, recall 0.54. The verdict does not move.

E1 with "weak" counted as kept: 13 of 15 recalled (0.87).

## Why recall failed: the misses by reason code

73 kept sentences failed the gate. Their reason codes:

| Code | Misses | What happened |
|---|---|---|
| `undated` | 36 | The sentence carries no year for the mark. The rubric forbids supplying one; the person dated every mark from the mark's own article. |
| `not_a_mark` | 21 | The person kept things the written definitions exclude: relief funds, temporary measures, bans of the work itself, the stone's own company, one chamber's passage (and one cut-off sentence). |
| `context` | 9 | A law in a neutral section, with the stone unnamed in the sentence. The person read the paragraph around it. |
| `attention_only` | 5 | Tourism and interest, which the definitions call attention. |
| `aside` | 2 | Junk or off-topic sentences (an image caption, a list of precursor reports) standing for a real mark. |

**1. Dating (36 misses, half the gap).** Examples: "Shortly after the attacks, the September 11th Victim Compensation
Fund was created by an Act of Congress" (WF005). "They created the Convention on Early Notification of a Nuclear
Accident ..." (WF025). "After the film's U.S. release in October 2004, Merlot sales dropped 2% while Pinot noir sales
increased 16%" (C020); there the year belongs to the release, not to the change. "In the state of New York, sex
offenders are banned from using the application while on parole" (C034). Each is a real mark that the person dated with a
second lookup. The rubric's rule ("if the sentence does not date the mark, the mark is undated, whatever you know")
was written to keep a model from inventing dates, and it did that. The cost is half the recall.

**2. The person's practice is looser than the project's written definitions (25 misses; one more, C222, is a sentence cut off before it states its finding).** The rubric mirrors
`HANDOFF.md` ("Attention, growth and crazes are intermediate steps, never the endpoint"), `discovery_corpus1_v1_1.md`
(what the filter "still lets through: immediate operational response ..., funds that were a company's own relief
effort, bans on a film in one country") and `roundtable_v2.md` ("Country bans are a thin mark class"). The product,
built by hand the same day, keeps:

- relief funds: One Fund Boston (WF071), the OneOrlando campaign (WF109), the PG&E Fire Victim Trust (WF138);
- temporary measures: Chico's six-month price-gouging ordinance (WF136), BP's temporary contracting ban (H26, H35);
- bans of the work itself: Iran's bans of Pokémon Go (C039) and Zumba (C176), Malaysia's of Fifty Shades (C076), seven Indian states' of The Da Vinci Code (C078), Switzerland's of Volkswagen diesels (WF159);
- the stone's own business: "The Tetris Company was established to manage rights and licensing" (C152);
- one chamber's passage: the Bipartisan Safer Communities Act's House and Senate votes (WF102, WF103);
- tourism and interest: Norway tours after Frozen (C004), Northern Ireland's Game of Thrones visitors (C005), Emily in Paris tourists (C229), the plastics "interest" study (C226), 3D televisions after Avatar (C067);
- a court ruling about the film's own use in schools: the Dimmock ruling (H06, C223).

This is not a labeling error in either direction. It is a disagreement between the project's written rule and the
owner's own keep decisions. It needs the owner's ruling before a v2 rubric. Either the definitions widen (a ban of the
work counts as a government act; a standing relief fund counts as an institution) or the product drops these marks.

**3. Context lives outside the sentence (9 misses).** "Congress]] passed the Antiterrorism and Effective Death Penalty
Act of 1996, which limited access to habeas corpus" (WF076, the lead, the bombing unnamed in the sentence). "... the
California state wildfire insurance fund established by AB 1054 ..." (WF137, in a bankruptcy timeline). The person
read the paragraph; the screen saw one sentence.

## The ten false passes

| Id | Stone | What the screen passed | Comment |
|---|---|---|---|
| WF119 | Murder of George Floyd | "Chokeholds and other neck restraints were banned or restricted by at least 17 state legislatures in the year after Floyd's murder." | A real, dated, cited mark. The stone never shipped. |
| WF020 | Chernobyl | "A commission was established later in the day to investigate the accident." | An investigating commission, which the rubric counts. |
| WF083 | Oklahoma City | June 1995 legislation requiring chemical taggants in explosives | Dated and in order. Whether it was enacted is worth checking. |
| WF084 | Virginia Tech | 32 endowment funds, each in honor of a victim (June 2007) | Permanent, but a local memorial gift |
| WF087 | Virginia Tech | A youth chapter named for a victim (Nov 2008) | A naming, but trivial |
| WF112 | Pulse | The 2025 state budget funded the Pulse National Memorial | A memorial, obvious |
| WR06 | Grenfell | The Grenfell Tower Memorial (Expenditure) Act 2026 | Passed on the Act's title; the sentence is about earlier fires |
| WR13 | Jeffrey Epstein | The Epstein Files Transparency Act (2025) | Passed on the title; the sentence is link markup |
| C071 | Fifty Shades of Grey | Emergency-room injuries up over 50% in the year after publication | Correlational; flagged confounded, evidence scored 35 |
| C149 | Minecraft | MinecraftEdu, founded 2011 to bring the game into schools | Close to the game's own distribution |

Several of these are arguably marks the person would keep if shown them again (WF119, WF020, WF083). Two show a rubric
reading that should not survive: passing a reverse pair on the mark's title alone when the sentence is junk (WR06,
WR13). Under the registered bar all ten count as false.

## Disputed

The one hand-Disputed mark, Top Gun's 500% recruitment claim (C023), carries `disputed: true` and fails the gate. The
screen and the person agree. 13 Reasons Why's teen-suicide study (C217) passed the gate, since its own sentence does not
question it. The product shows it with a note that later analyses disputed it. The neighboring sentence that does
question it (C216) failed the gate as `not_a_mark`.

## The four scores against the owner's keep or reject

Area under the ROC curve for each score as a predictor of the person's keep (0.5 is no relation):

| Score | All candidates (E1 to E4) | Events | Culture | Among sentences the screen called a mark |
|---|---|---|---|---|
| interest | 0.90 | 0.92 | 0.92 | 0.71 |
| surprise | 0.82 | 0.80 | 0.89 | **0.51** |
| evidence | 0.90 | 0.89 | 0.92 | **0.83** |
| novelty | 0.80 | 0.75 | 0.88 | **0.48** |

Over everything, all four separate kept from rejected, because junk scores low on everything. The informative column is
the last one: among the 165 sentences that state a lasting mark, the owner's keeps track **evidence** (0.83) and
**interest** (0.71), and do not track **surprise** (0.51) or **novelty** (0.48) at all. Mean kept vs rejected among them:
evidence 58 vs 37, interest 55 vs 43, surprise 38 vs 37, novelty 39 vs 39. The hand screen kept obvious marks (the
Rogers Commission, the inquiry after Deepwater Horizon) as readily as odd ones. That matches the brief's own learning,
"Surprise is a higher bar than interest", and the plan's split of first-pass screen from the editorial surprise check.
If the product wants surprising ripples, surprise has to be a separate filter after the screen. The person's keep
decision does not supply it. On E1, mean evidence by hand label: mark 61, context 20, wrong 12, weak 5.

## Sensitivity lines (registered, not part of the bar)

- Against the person's looser counts in the docs: v1.1's "about 70" forward sentences that state a mark against the
  screen's 34 forward passes (0.49); the culture shelf's "about 30" real marks against 9 passes (0.30).
- S1, the 22 citation grades behind cite_score v1 (**not blind**: the scorer's source hard-codes them): the rubric
  labels 2 as reason, both correct, and misses 7 (precision 1.00, recall 0.22, against cite_score's 0.73 and 0.89).
  The rubric's "reason" means "the mark is presented as a consequence of the stone". The owner's citation grade counts
  a work invoked in the debate as an argument for the bill (Adolescence, Cathy Come Home in 1966, Baby Reindeer, McMafia).
  The two definitions differ, and a records reading needs its own rule.

## Exploratory, after the comparison (not registered)

If an undated mark were held for a dating step instead of rejected, and the step always succeeded, the same labels would
give precision 0.72 and recall 0.78 (28 more false passes, among them the Dubrovnik visitor cap, the husky boom, Women's
Institute membership and the Peaky Blinders baby names, which the culture doc calls true but undated), with still 0
decoys. That is near the bar but not over it. The remaining gap is the definitions question in finding 2.

## What v2 would change (nothing below has been run)

1. **A dating step before the gate.** Fetch the mark's own article (title year, infobox, lead), as `order.py` already
   does for reverse pairs, and pass the year in as a field. An undated mark becomes "held", not rejected.
2. **The owner rules on the definitions** for bans of the work, standing relief funds, temporary measures, tourism and
   the stone's own company. The rubric then mirrors the ruling, and the product follows the same rule.
3. **The paragraph, not the sentence**: the sentence before and after go in as context fields.
4. **No pass on a mark title alone** when the sentence is markup or about something else.
5. **A records reading** for parliamentary citations, with the owner's argument-for-the-bill sense of "reason".

## Automation

`lab/discovery/screen.py` runs the same rubric through a language-model API, one candidate per request. It reads the
key from `RIPPLE_SCREEN_API_KEY`, the model from `RIPPLE_SCREEN_MODEL` and the endpoint from `RIPPLE_SCREEN_ENDPOINT`,
with no defaults. It uses the honest user agent, sends at most one request a second and stops on any 4xx or 5xx. The
model answers the rubric's fields; the gate, the reason code and duplicates are derived in code. **It was not run and
no workflow calls it: the repository's secrets hold no key for such an API.** Its numbers would not be these numbers
either: a different model under the same rubric is a new labeler and needs its own registered run against the same sets.

## Deviations from the plan, disclosed

- The plan said "the twelve marks" for E2. The screen file lists eleven marks. The doc's twelve counts the Connecticut law
  and its registry, and the two BP-ban sentences, separately. Recall uses the eleven marks; sentence-level numbers count
  every sentence that states one.
- Nine readings of the rubric were fixed during labeling, before any hand label was opened. They are recorded in
  `screen_labels_v1.json` (`labeling_notes`): section headings that frame a response count as the link; a mark title
  that names the stone counts as the link; what counts as a stated interval; when a report's year dates a change;
  passage by both chambers counts as enacted; imitators are attention; a cut-off sentence states nothing; duplicates
  are judged within a set; S1's mark is the bill. Three early labels (H09, H42, H43) were revised to the first reading
  during labeling.
- E4 has 233 candidates in the metrics, not 234: the one hand-Disputed mark is reported separately, as registered.

## Limits

- One labeler, one pass. The labeler was also the analyst who matched the hand decisions. The 24 judgment matches are
  listed so they can be checked, and the mechanical-only numbers are given beside them.
- The labeler read the result docs first, and they quote many kept marks. The `seen_in_docs` flag is self-reported.
- The hand decision for E3 and E4 is "shipped to the product", not "judged real". The person kept fewer marks than they
  judged true (the docs' "about 70" and "about 30"). This makes precision look lower than it is and recall look higher.
- The person dated marks with a lookup the screen was not allowed. Part of the recall gap is a difference in inputs, not
  in judgment.
- The four scores are one labeler's editorial judgments, not measurements.

## Candidates no person screened (exploratory, after the comparison)

The catalog stones' forward reading (`legacy2_all.json`) left 224 causal sentences, of which v1 hand-screened a random 50
and recorded only counts. The 192 that survive the ordering rule were run through rubric v1 the same way, and the 24
passes are listed in `docs/results/screen_new_v1.json`. That file is labeled **screened by a language model, not by a
person**. 15 of the 24 are marks the hand-built catalog or the product already holds (the Offences Act 2024, the Housing
(Homeless Persons) Act 1977, ARPA, the Oil Pollution Act, LCARA and others). That is an independent check that what the
screen passes on fresh text is mostly real. Nine are not in the catalog or the product: the Wickersham Commission (1929)
after Prohibition, the American Society of Safety Professionals (1911) after the Triangle fire, the Respect for Marriage
Act (2022) after Dobbs, the California Consumer Privacy Act (2018), the Virginia and Colorado privacy acts (2021) and
China's Personal Information Protection Law (2021) after the GDPR, the Project BioShield Act (2004) after the anthrax
letters, California's 1909 standard fire insurance policy after the 1906 earthquake, and the 1966 Department of
Transportation after Unsafe at Any Speed. None of them enters the product without a person.

## Data the product can use

- `docs/results/screen_corpus_v1.json`: 583 candidates, each with the screen's decision, one reason code, flags, four
  scores and the person's decision. This is the start of a labeled corpus of what a good ripple is (and is not).
- `docs/results/screen_compare_v1.json`: the confusion lists and the judgment matches, for the owner's ruling on finding 2.
- `docs/results/screen_new_v1.json`: nine marks the screen passed that are not in the catalog or the product, for a person to
  check (screened by a language model, not by a person).
- The ten false passes include at least three marks worth a person's second look: chokehold bans in 17 states after
  George Floyd's murder (WF119), the 1995 taggant law after Oklahoma City (WF083) and the Chernobyl commission (WF020).
