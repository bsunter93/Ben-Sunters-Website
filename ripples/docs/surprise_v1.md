# Surprise score v1: the result (October 5, 2026)

Registered in `docs/surprise_plan_v1.md` at commit `2c86cd2910879378c5c9c7ad66ebd1aa82444f85`, pushed before any
labeled pair was scored. Scorer: `lab/discovery/surprise.py`. Data: `docs/results/surprise_v1.json` (251 scored pairs:
every feature, percentile, half, score and rank, plus the evaluation block).

## Verdict: not met

| Set | Bar | AUC | 95% interval | One-sided p | Result |
|---|---|---|---|---|---|
| Blind round, 4 strictly non-obvious against 8 | ≥ .75 | **.625** | .25 to .91 | .28 | **miss** |
| Blind round, Spearman with the owner's 3-level grade | reported | .397 | | | |
| Pooled screen tags, 25 against 51 | ≥ .70 | **.574** | .45 to .71 | .15 | **miss** |

Both numbers are on the score **without u4** (co-citation), a deviation forced by a stop (next section). The registered
six-feature score could not be completed today. It can still be completed on a later UTC day by rerunning the same
command, and that result will replace this one as the registered result. For it to clear the blind-round bar,
co-citation alone would have to separate the owner's four, which none of the three other linkage features did (u1 .50,
u2 .50, u3 .56).

The score does one useful thing and fails at the one that matters. It finds the *obvious*: both left-out pairs rank
10th and 11th of 12, and the famous 9/11 marks (the Patriot Act, Homeland Security, the TSA) sit in the lower half of
the 76. It does not find what the owner calls strictly non-obvious, and on the culture shelf it does worse than chance.

## What happened in the run (deviations)

1. **A stop.** The registered run made about 430 requests to Wikipedia between 06:18 and 06:28 UTC and received HTTP 429
   from the search API during the backlink counts (CirrusSearch `linksto:`, the input to u4), after 125 searches
   at one a second. The scorer wrote its stop marker and a dated line in `lab/discovery/surprise_blocked_dates.txt` and
   exited; there was no retry. Leads, categories, out-links and redirects for all 285 articles had already been
   fetched. The score was then computed offline from the cache with u4 dropped for every pair
   (`--offline --no-cocite`; U = mean of u1, u2, u3) and nothing else changed. The Wikidata class labels, which were
   for reading only, were not fetched, so the class columns are empty.
2. **A defect, found after the run.** The registered plural stemmer turns "octopuses" into "octopuse", so My Octopus
   Teacher and the Animal Welfare (Sentience) Act share no word and d1 is 1.000. Rerun post hoc with an "-es" rule,
   d1 falls to .969 and both AUCs are unchanged (.625 and .574). The registered result stands; the defect did not cause
   the miss.
3. The JSON leaves out the evidence sentences; they are in `demo/discovered_wiki.json`, `mark_first_v1_1.json` and
   `bill_act_v1.json` under the ids the rows carry.

## The blind round, pair by pair

| Rank of 12 | Stone → mark article | Owner | Surprise | D | U | What the structure says |
|---|---|---|---|---|---|---|
| 1 | My Octopus Teacher → Animal Welfare (Sentience) Act 2022 | medium | .810 | .96 | .66 | no link either way, no shared out-link: the tie lives in Hansard, not Wikipedia |
| 2 | Manhunt → Digital Economy Act 2010 | **strict** | .621 | .58 | .66 | no direct link; a game against an Act mostly about online copyright |
| 3 | Ocean with David Attenborough → High Seas Treaty | **strict** | .610 | .56 | .66 | no direct link |
| 4 | The West Wing → Racial and Religious Hatred Act 2006 | medium | .605 | .66 | .55 | linked one way |
| 5 | Quincy, M.E. → Orphan Drug Act of 1983 | medium | .598 | .64 | .55 | linked one way |
| 6 | 60 Minutes → STOCK Act | medium | .558 | .73 | .38 | the Act's lead names the program |
| 7 | Cathy Come Home → Homelessness Reduction Act 2017 | medium | .550 | .44 | .66 | close in topic (homelessness) |
| 8 | The Daily Show → James Zadroga 9/11 Health and Compensation Act | **strict** | .506 | .58 | .44 | linked both ways |
| 9 | Victim → Sexual Offences Act 1967 | **strict** | .474 | .51 | .44 | linked both ways |
| 10 | Holy Deadlock → Matrimonial Causes Act 1937 | left out | .415 | .39 | .44 | a divorce novel and a divorce law; linked both ways |
| 11 | Rangila Rasul → Section 295A of the Indian Penal Code | left out | .409 | .38 | .44 | a pamphlet and the blasphemy section it prompted; linked both ways |
| 12 | Silent Spring → National Environmental Policy Act | medium | .409 | .27 | .55 | the closest pair in topic |

**Where it agrees with the owner.** The two pairs he left out are at the bottom, for the reason a reader would give:
the work and the law are about the same thing and each article names the other. Manhunt and Ocean, two of his four,
are 2nd and 3rd: nothing in Wikipedia ties the game to the Digital Economy Act or the film to the High Seas Treaty.

**Where it disagrees, and why.** The brief records the owner's four as "the ones with an odd mechanism". Victim and
The Daily Show are odd mechanisms (a 1961 film, a comedian) that Wikipedia tells well: the Zadroga Act's article
describes Jon Stewart's episode and links the show, the Sexual Offences Act's history credits Victim, and both stones
link back. The link graph records a story in proportion to how notable it is, so the most famous non-obvious stories
look the most connected. My Octopus Teacher goes the other way: the minister's "profoundly affected" is in Hansard, and
neither article mentions the other, so every linkage feature calls it surprising; the owner called it medium. Prior linkage in
Wikipedia measures whether a link is *documented*, not whether a smart person would have *guessed* it.

## The pooled screen tags

**Agrees** (tagged non-obvious and ranked high, of 76): Hamilton → the Hamilton Education Program (3rd), Pokémon Go →
New York's parole rule (8th), the Camp Fire → Chico's price-gouging ordinance (10th), Chernobyl → the Joint Convention
(12th), Love Canal → LCARA (16th), Enron → section 409A (19th). The obvious 9/11 marks rank low: the TSA 57th, the
Department of Homeland Security 59th, the Patriot Act 62nd.

**Misses, tagged but ranked low:** The Great British Bake Off → baking sales (74th: baking is the show's subject and the
sentence is in the lead); Parkland → the death-penalty unanimity repeal (72nd) and Challenger → NASA's Office of Safety
(68th), both with the sentence in the stone's lead; Bhopal → the International Medical Commission (53rd: named for the
stone, linked both ways); Blue Planet II → marine biology applications (50th); Dear Zachary → Bill C-464 (51st).

**Misses, untagged but ranked high:** the Pulse shooting → the OneOrlando Fund and the OnePulse Foundation (1st and
2nd), Zumba → Iran's ban (4th), Emily in Paris → Paris tourism (5th), Chernobyl → the Shelter Fund (6th), Uvalde →
Texas HB 3 (7th). All six are marks without an article, scored on their evidence sentence. A short sentence that
shares no word with the stone's lead once the stone's name is removed gets the top text-distance percentile, but that
says the sentence does not repeat the lead, not that the mark is far from the stone. 46 of the 76 pooled marks have no
article, and for them the score is only that text distance and the lead test.

By run: discovery v1.1 .646 (16 of 52, p = .046), the culture shelf .422 (9 of 24, worse than chance).

## Secondary and sensitivity checks

| Check | AUC |
|---|---|
| v1.1 tags alone | .646 |
| Culture tags alone | .422 |
| Discovery v1 builder tags (3 of 25: The West Wing, Columbine → New Jersey, Fukushima → Korea's commission) | .879 (p = .018; 3 positives) |
| All builder tags (28 of 101) | .628 (p = .026) |
| Blind round, My Octopus Teacher strict instead of Ocean | .688 |
| Blind round, both strict (5 positives) | .771 |
| Blind round with the three unidentified names filled, 20 triples | .455 to .682, median .591 |
| Pooled, Blue Planet II's plastics turn positive | .585 |
| Pooled, Top Gun's disputed claim as a negative | .576 |
| Pooled, Crisis and BlueConduit positive (v1's forward screen) | .568 |

Only the "both strict" reading of the brief's ambiguity clears .75, and that reading counts a pair the score ranked 1st
for the wrong reason (the stemmer defect plus a link that lives outside Wikipedia). It is not a pass.

## Exploratory, and what it suggests (looked at after the result; not evidence)

- **Features alone.** On the blind round nothing beats .625 (d2); D alone .50, U alone .56. On the pooled set the three
  features that need a mark article reach .75 to .78 on the 30 pairs that have one (8 tagged: d2 .778, u3 .761, u1
  .753), while d1 and u2, the only features for marks without an article, sit at .53. The link graph tracks the
  builder's tags where it exists; the sentence-only features do not. Specificity has no relation to either label (.47,
  .50).
- **Surprise rewards junk.** In the bill-act pool the median surprise of citations the screen labels *aside* is .717,
  against .649 for *context* and .643 for *reason*. The top of the mark-first pool is 1News → the UNRWA law and Twenty
  Thousand Leagues Under the Seas → the Fourteen Points. Unrelated pairs are maximally distant and unlinked by
  construction.

## How surprise should combine with evidence

1. **Gate first, then rank.** Surprise is only meaningful among pairs that already clear an evidence gate: a sentence
   or record naming both, the ordering rule passed, an enacted or lasting mark, and for parliamentary records a citation
   labeled *reason*. Without the gate a surprise score floats the asides to the top, as the bill-act pool shows.
2. **Within the gate, rank by surprise percentile times the evidence ladder weight** (measured 1.0, timed .8, reported
   .6, plausible .3, disputed or busted 0), with specificity as a tiebreak, since a named statute is easier to defend
   and specificity showed no relation to surprise.
3. **With v1 as it stands, use the score only as a reading order for the human screen, never to drop a candidate.** It
   reliably pushes the obvious down (both left-out pairs, the 9/11 headline laws); it does not reliably pull the
   non-obvious up.

## What v2 should test (to be registered fresh)

- **The messenger, not the documentation.** The owner's four share an unexpected messenger for the mark's domain (a
  comedian for a health law, a game for a ratings law, an old film for a criminal law). That is a class pairing, the
  stone's genre (Wikidata P136, the article's genre categories) against the mark's subject, which v1 left out because
  inside the blind round every pair is a work and a law. A comedy program → a health law is rare; an environmental book
  → an environmental law is common. Base rates of genre-to-subject pairs over the 16,125 mark-first pairs would give
  that rarity without any label.
- **Score a mark without an article by what its sentence links to**, not by the sentence's words against the lead.
- **A record outside Wikipedia is not surprise.** Treat "found only in Hansard" as a separate flag, not as maximal
  unlinkedness.
- **A larger owner-graded set, recorded per pair.** Twelve pairs cannot validate a bar at .75 (the interval runs from
  .25 to .91), and the first round's per-pair list was never written down. The next blind round should commit each
  name and grade to the repository.
- **Co-citation at a slower pace.** CirrusSearch throttled `linksto:` at one a second; one every five seconds is within
  the rule and would make the full count about 40 minutes.

## Completing the registered run

On a later UTC day, the same command without the deviation flag resumes from the cache and fetches only the missing
backlink counts, co-citations and class labels:

```
python3 ripples/lab/discovery/surprise.py --cache /path/to/the/same/cache
```

Its numbers replace these and are reported as the registered result. A fresh cache costs about 1,000 requests.
