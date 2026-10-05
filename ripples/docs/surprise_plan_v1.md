# Surprise score v1: pre-registration (October 5, 2026)

*Written and committed before any surprise score exists for a labeled pair. The scorer is
`ripples/lab/discovery/surprise.py`, committed with this plan; the commit that adds both is the registration. Results
will be `docs/results/surprise_v1.json` and `docs/surprise_v1.md`; deviations from this plan will be listed there.*

## Why

The owner's bar for a ripple is "surprising AND defensible". Evidence is graded by the checker; surprise is judged by
reading. In the first blind round the owner found 14 of 15 engine pairs interesting and only 4 strictly non-obvious;
later screens tagged 14 of 51 marks (discovery v1.1) and 9 of about 30 (the culture shelf) as non-obvious. Learning 9
of the brief says regex filtering of obvious links is weak and that surprise should come from the mechanism graph and
domain distance. This test asks whether a score built only from public structure (Wikipedia's text, categories and link
graph) ranks the pairs a person called non-obvious above the rest.

`docs/discovery_engine.md` says surprise is "an editorial filter, never a fake-precision score" and that the human
check "can't be automated honestly". This score does not replace that check. It is a ranking aid that decides which
candidates a person reads first; it is never shown in the product as a number, and nothing is published on its say-so.

## The score

For a stone S and a mark M (a law, institution or durable change), six features in two halves:

| | Feature | Definition | Missing when |
|---|---|---|---|
| **D, domain distance** | d1, text distance | 1 − cosine similarity of TF-IDF vectors: S's lead plus its visible category names, against M's lead plus its visible category names, or against the evidence sentence when M has no article of its own. The full name of S (its title without the parenthetical, the record's label, and its multiword redirect titles) is deleted from M's text as a phrase first, so the mark naming its cause counts as linkage, not topic. Lowercase words, a fixed stopword list, words of three letters or more, a plural-s stemmer; IDF over every document in the run | never |
| | d2, link-neighborhood distance | 1 − Jaccard of the two articles' out-links (main namespace; S and M themselves removed) | M has no article |
| **U, unlinkedness** | u1, direct links | 1 − (number of directions in which the two articles link each other, counting links to redirects) / 2 | M has no article |
| | u2, stone's lead | 0 if S's lead names M (M's title without the parenthetical, its multiword redirect titles, or the record's label when that label appears in the evidence sentence), or, for a mark found in S's own article, if the evidence sentence shares a six-word run with S's lead; else 1 | never |
| | u3, mark's lead | 0 if M's lead names S (multiword names case-insensitive, one-word names case-sensitive, a leading "The" optional); else 1 | M has no article |
| | u4, co-citation | 1 − (articles linking to both) / (the smaller of the two backlink counts), from CirrusSearch `linksto:` counts | M has no article |

**Formula.** Each feature becomes a mid-rank percentile in (0, 1) over every unique pair scored in the run that has the
feature; d1 is ranked within its document type (mark article or evidence sentence), so a short sentence is not "far"
because it is short. D = mean of the available d percentiles; U = mean of the available u percentiles;
**surprise = (D + U) / 2**. Higher means more surprising. Equal weights; nothing is fit on any label.

**Choices made before scoring, and why.**

- *No Wikidata class distance in the formula.* Inside the blind round every pair is a creative work and a law, so a
  P31/P279 path is the same for all twelve; in the pooled set it would separate events from works, not obvious from
  non-obvious. Each article's P31 classes are fetched and reported for reading only.
- *Mechanism specificity stays out of surprise.* Whether the mark is a named statute or institution (its own article =
  1, a named law or institution without one = 0.5, a generic behavior or industry change = 0) is a property of
  defensibility. It is reported per pair, tested alone as an exploratory feature, and used in the ranking proposal
  with evidence, not in the score.
- *The two halves are equal* because the hypothesis in learning 9 names both (domain distance; the mechanism graph,
  which u1 and u4 measure as direct and two-hop linkage).

## Data and politeness

Wikipedia's API (leads by `prop=extracts`, visible categories, out-links, redirects, Wikidata ids) and CirrusSearch
`linksto:` totals; Wikidata's API for P31 labels. The honest user agent
`ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`, at most one request a second, a stop on any HTTP
error, refusal or timeout with no same-day retry (a stop marker in the cache and a dated line in
`lab/discovery/surprise_blocked_dates.txt`). Aggregate page data only. Raw responses are cached outside the repository
and not committed (several megabytes of link lists); the committed JSON holds every feature value, so the score can be
recomputed from it without the network, and the features themselves can be refetched (Wikipedia changes; the run
date is recorded).

## The pairs scored (the universe for the percentiles)

1. **The 102 engine marks** in `demo/discovered_wiki.json` (58 stones). Stone article and mark article as recorded;
   a mark whose recorded article is the stone's own article is treated as having none.
2. **The blind round** (12 pairs, below) and six fill candidates (sensitivity only).
3. **Unscreened pools:** the 67 ordered, causal, non-news, non-reversed pairs of `docs/results/mark_first_v1_1.json`
   (work article → law article) and the 78 ordered work → Act pairs of `docs/results/bill_act_v1.json` (the Act's
   article where one exists, else the Hansard sentence as its text). A pool pair that repeats a labeled or engine
   pair is scored once.

## Evaluation sets

**1. The blind round (primary).** On Oct 3, 2026 fifteen work → law names went to the owner. The record says 14
interesting, 4 strictly non-obvious (Victim, The Daily Show, Ocean, Manhunt), 9 "medium", 13 worth chasing, and
Rangila Rasul and Holy Deadlock left out (the brief's status table; the commit message of PR #65). The per-pair list of
the fifteen was not recorded anywhere in the repository or the PR. Twelve are reconstructed:

| Stone | Mark article used | Grade | How it is known |
|---|---|---|---|
| Victim (1961 film) | Sexual Offences Act 1967 | 2 strict | status table |
| The Daily Show | James Zadroga 9/11 Health and Compensation Act | 2 strict | status table |
| Ocean with David Attenborough | High Seas Treaty | 2 strict | status table |
| Manhunt (video game) | Digital Economy Act 2010 | 2 strict | status table |
| Cathy Come Home | Homelessness Reduction Act 2017 | 1 medium | chain built in the same pass (batch 13) |
| Quincy, M.E. | Orphan Drug Act of 1983 | 1 medium | chain built in the same pass (batch 13) |
| My Octopus Teacher | Animal Welfare (Sentience) Act 2022 | 1 medium | chain built in the same pass (batch 13) |
| 60 Minutes | STOCK Act | 1 medium | chain built in the same pass (batch 13) |
| The West Wing | Racial and Religious Hatred Act 2006 | 1 medium | "from the blind round" (batch 14 commit) |
| Silent Spring | National Environmental Policy Act | 1 medium | "from the blind round" (batch 14 commit) |
| Rangila Rasul | Section 295A of the Indian Penal Code | 0 left out | status table and commit |
| Holy Deadlock | Matrimonial Causes Act 1937 | 0 left out | status table and commit |

The mark article follows a fixed rule: the named law's own article; else the law step of the chain built from the pair
(Manhunt: the British Board of Film Classification accountability bill has no article, so the chain's Digital Economy
Act 2010); else the top exact-phrase search hit that is not the stone's own article (Cathy Come Home: the Housing
(Homeless Persons) Act 1977 has no article, top hit Homelessness Reduction Act 2017; Ocean: the Biodiversity Beyond
National Jurisdiction Act 2026 has no article, top hit High Seas Treaty). The two left-out pairs are taken as the
third level of the grade (4 + 9 + 2 = 15 is the only split the record allows). Three medium names cannot be identified.

Known weaknesses of this set, stated now: n = 12 with 4 positives, so each of the 32 positive-against-negative
comparisons is worth .03 of AUC; the four medium pairs from batch 13 are inferred, not recorded; and the brief's
learnings (section 3, "Surprise is a higher bar than interest") describe the four as "a 1961 film, a comedian, a
documentary → crab welfare, a game", where crab welfare points to My Octopus Teacher, not Ocean. The
primary analysis follows the status table (Ocean strict, Octopus medium); the alternatives are registered sensitivity
checks.

**2. The pooled screen tags (primary).** The engine marks put into the product by discovery v1.1 (52 marks) and the
culture shelf (24 marks; Top Gun's 500% recruitment claim is excluded because the screen kept it as Disputed, not as
a mark): 76 pairs. Positive = named as non-obvious in the result documents.

- v1.1 (`docs/discovery_corpus1_v1_1.md`): the document says "the non-obvious fourteen" and names sixteen marks on
  thirteen stones; all sixteen are positive: Enron → 409A and → the Companies (Audit, Investigations and Community
  Enterprise) Act 2004; MeToo → Indonesia's Sexual Violence Crime Act; Bhopal → the International Medical Commission;
  Challenger → NASA's Office of Safety; Chernobyl → the Early Notification Convention and the Joint Convention; Boston
  Marathon → One Boston Day; Oklahoma City → the Victim Allocution Clarification Act; Parkland → the death-penalty
  unanimity repeal; the Camp Fire → Chico's price-gouging ordinance and AB 1054; Love Canal → LCARA; Dear Zachary →
  Bill C-464; Cambridge Analytica → Social Science One; Flint → the Child Lead Exposure Elimination Commission.
- Culture (`docs/discovery_culture_v1.md`): the nine: Sideways → the Merlot and Pinot effect; Bake Off → baking sales;
  Furby → the NSA ban; Jurassic Park → the Raptors' name; Blue Planet II → marine biology applications; An Inconvenient
  Truth → carbon-offset purchases; Pokémon Go → New York's parole rule and Iran's ban; Hamilton → the Education Program.
  Blue Planet II's "plastics turn" is named in the same sentence but is not counted in the nine; it is negative in the
  primary analysis.

These tags were the builder's, not the owner's, and were made while screening for real marks, so "non-obvious" there
may mean "a mark I would not have guessed" more than "an odd mechanism". That is why they form a separate primary set
with a lower bar.

**3. Secondary (reported, no bar).** Each of the two pooled runs alone; discovery v1's builder tags on its 25 marks in
the product (non-obvious: The West Wing → the Racial and Religious Hatred Act 2006, Columbine → New Jersey's
anti-bullying law, Fukushima → Korea's Nuclear Safety and Security Commission); all tags together.

## Metrics and the bar

- **Blind round:** rank AUC of the 4 strictly non-obvious pairs against the other 8 (ties count one half).
  **Bar: AUC ≥ .75.** Also Spearman correlation between surprise and the owner's 3-level grade (2, 1, 0), reported.
- **Pooled tags:** rank AUC of the 25 tagged pairs against the other 51. **Bar: AUC ≥ .70.**
- **The bar is met only if both point estimates clear it.** Each AUC is reported with a one-sided permutation p-value
  (20,000 label shuffles) and a 95% bootstrap interval (2,000 resamples within each class), seed 20261005. These are
  reported, not part of the bar. A miss is reported as a miss, with the diagnosis.

## Sensitivity checks (registered; not part of the verdict)

1. My Octopus Teacher strict instead of Ocean; and both strict (5 positives).
2. The three unidentified medium names: every triple drawn from six candidates found in the same searches and having
   a law article (JFK → the JFK Records Act; A Nation of Immigrants → Hart-Celler; Adolescence → the Children's
   Wellbeing and Schools Act 2026; McMafia → the Sanctions and Anti-Money Laundering Act 2018; The Descent of Man →
   the Butler Act; The Caine Mutiny → the Twenty-fifth Amendment), each added as a non-positive: the minimum, median and
   maximum AUC over the 20 triples.
3. Pooled with Blue Planet II's plastics turn positive; with Top Gun's disputed claim as a negative; with Cathy Come
   Home → Crisis and Flint → BlueConduit positive (v1's forward screen called both non-obvious).

## Exploratory (registered as exploratory)

Each half (D, U) and each feature alone, and specificity, as AUCs on both primary sets; the median surprise of the
bill-act pool by citation label (reason, context, aside), to show what surprise does to junk pairs; ranks of all 102
engine marks and both pools.

## What the result is for

If the bar is met, `docs/surprise_v1.md` proposes ranking candidates by surprise times evidence, behind an evidence
gate (a sentence naming both, the ordering rule passed, an enacted or lasting mark), because a pure surprise score
rises for pairs that are unrelated, which is the opposite of defensible. If it is missed, the same document says which
half failed on which set and what the next version should test; nothing in the product changes either way.

## Disclosure

The label lists above are published in the result documents, and the designer read them before writing the features,
so the design is not blind to the labels. The scores are: before this commit no feature was computed for any labeled
pair. The scorer was tested on four pairs in no labeled set (WarGames → the Computer Fraud and Abuse Act, Sesame
Street → the Children's Television Act, Steamboat Willie → the Copyright Term Extension Act, and an invented sentence
on Jaws) to confirm that the requests, caching and arithmetic work.
