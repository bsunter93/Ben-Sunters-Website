# Multi-hop ripples v1: results (Oct 5, 2026)

The plan, `docs/multihop_plan_v1.md`, was registered at commit `efe9cf8` before any search. The question: can the engine
compose a stone, an intermediate and a lasting mark into one chain, each hop graded and in order, without composing
chains for stones that never moved the intermediate?

**Verdict: the bar failed.** Both known positives were recovered. One new two-hop chain survived the strict hand check
(Sputnik → the Sputnik crisis → the European Space Agency) against a bar of three. Decoys: 3 of 124 wrong-stone
pairs passed hop 1, and 3 of 50 famous films yielded an automated chain, against a bar of zero. The run is also
incomplete. On the morning of Oct 5 the UK Parliament's Hansard API and Bills API and legislation.gov.uk each returned
a 5xx and were stopped for the day under the rules. The Hansard leg ran for 194 of the 477 survivors, and for none of
the famous decoys.

## Against the bar

| | Bar | Result | |
|---|---|---|---|
| Known positives recovered | at least 1 of 2 | **2 of 2** (K1 and K2) | met |
| New two-hop chains surviving the hand check | at least 3 | **1** | not met |
| D1: wrong-stone pairs passing hop 1 | 0 | **3 of 124** | not met |
| D2: famous films yielding an automated chain | 0 | **3 of 50** (a lower bound: Hansard did not run for them) | not met |

Beside the bar, as registered: the one new chain also reaches a mark the repository did not hold for its stone (1 of 1).

## The chains that survived

All three carry "reported" as the weakest link, because hop 2 is a record making the link. The "It wasn't the only
reason" note is left blank for an editor. The renderable file is `docs/results/multihop_v1.json`.

**1. Tiger King → Joe Exotic → the Big Cat Public Safety Act (K2, recovered).**
- **Stone:** Tiger King, released Mar 20, 2020.
- **Hop 1 (measured):** daily Wikipedia views of Joe Exotic rose from a small baseline, with a sustained onset on Mar 31,
  2020. The checker's attention test gives p = .015 against 66 placebo dates in the page's own history.
- **Hop 2 (reported):** House floor debate on the bill, Jul 28, 2022, in the Congressional Record: "the TV series
  'Tiger King' showed us that there is a dark and dangerous side to keeping lions, tigers, and other big cats in
  captivity. In fact, Joe Exotic from that series is in jail for violating the Lacey Act and the Endangered Species Act."
- **Mark:** the Act was signed Dec 20, 2022 (Pub. L. 117-243).
- The record names the series and the intermediate in the same breath, so this chain is the existing one-hop pair with
  its mechanism exposed. It is not a new mark.

**2. Mr Bates vs The Post Office → the British Post Office scandal → the Post Office (Horizon System) Offences Act 2024
(K1, recovered).**
- **Stone:** the drama, first broadcast Jan 1, 2024.
- **Hop 1 (measured):** views of the scandal's article rose 370-fold from Jan 2 (p = .023, 43 placebo dates).
- **Hop 2 (reported):** at the bill's second reading (Hansard, Mar 20, 2024), the minister said it "will quash the
  convictions of those affected by the Post Office Horizon scandal" and clear the names of those "whose lives were
  ruined because of the Horizon scandal".
- **Mark:** Royal Assent May 24, 2024.
- Paula Vennells also passed hop 1 (views up 1,879-fold, p = .006). Neither Hansard sentence that names her gives her as
  a reason for an Act, so her chains failed the hand check.

**3. Sputnik → the Sputnik crisis → the European Space Agency (new).**
- **Stone:** Sputnik 1, launched Oct 4, 1957.
- **Hop 1 (reported):** the Sputnik 1 article says the launch "precipitated the American Sputnik crisis".
- **Hop 2 (reported):** the European Space Agency article: "In 1958, only months after the Sputnik shock, Edoardo Amaldi
  (Italy) and Pierre Auger (France) ... met to discuss the foundation of a common Western European space agency."
- **Mark:** the same article says ESA "in its current form was founded with the ESA Convention in 1975, when ESRO was
  merged with ELDO."
- This is the weakest kind of reported link: it rests on timing in the agency's own origin story ("only months after"),
  not on a sentence saying "because". The repository held NASA, ARPA, the NDEA and GPS for Sputnik, not ESA.

## What ran

| Stage | Main set | Famous decoys |
|---|---|---|
| Stones | 112 (111 articles read) | 50 |
| Candidate links resolved | 3,552 | 1,033 |
| Passed the specificity filter | 1,965 | 607 |
| Measured tests run (cap 20 a stone; stones after Aug 1, 2015) | 705 on 37 stones | 484 on 26 films |
| Measured passes (p ≤ .05, onset after the stone) | 119 | 36 |
| Candidates with a reported sentence | 1,354 | 135 |
| Survivors sent to hop 2 (cap 4 measured + 3 reported) | 357 (84 measured, 273 reported) | 120 (35, 85) |
| H2, the Wikipedia reverse hop | all 357 | all 120 |
| H1, Hansard | 194 run, 162 pending | 0 run, 120 pending |
| H4, the Congressional Record (workflow) | 293 tied to the US | 120 |
| Automated chains | **112** on 32 stones: Hansard 93, Wikipedia 13, the Record 6 | **3** on 3 films |
| Survived the hand check | **3** | (counted at the automated stage) |

- **Why candidates failed the filter (main set):** a class, not an instance (675); a generic kind (653); an actor (130); a
  creator, broadcaster or series of the stone (48); the stone's own title (27); no instance-of (54).
- **Hop 1:** of 705 measured tests, 119 passed, 310 found no sustained rise, 62 were within chance, 14 rose before the
  stone (busted), and 200 had no usable baseline.
- **Hop 2:**
  - Hansard gave 276 windows that cite_score labels "reason". Of these, 186 were in order on a bill that became an Act,
    54 were on a bill that never became one, 3 were busted by order, and 33 wait on the stopped resolvers.
  - The Wikipedia reverse hop found 131 pairs: 102 busted by the ordering rule with no person involved, 15 undated, 14 in
    order.
  - The Record workflow read 671 windows (1,264 requests, no stop): 8 were in order.
- **Requests:** about 3,850 from the laptop and 1,264 from the workflow.

## Why 109 of 112 automated chains failed the hand check

A chain fails on the first criterion it misses (plan, section 7). The verdicts and their reasons are in
`docs/results/multihop_hand_v1.json`, and the failed chains are kept under `rejected` in `multihop_v1.json`.

| Criterion | Failed | What it looked like |
|---|---|---|
| 4: the record does not name the intermediate as a reason | 52 | Passing mentions in unrelated bills: Rishi Sunak in thirteen (an election anecdote, a former aide's tribute); the European Commission, Facebook and Google in sixteen more. The Horizon scandal used as an example in the Media, Victims and Digital Markets bills. |
| 3: hop 1 does not hold | 39 | The stone did not move the intermediate. Some are later events named in the stone's article (Columbine → Sandy Hook, Challenger → Columbia). Some came first (the anthrax letters → September 11). Others are places and companies named in passing (New York State, the White House, YouTube). |
| 2: not specific, or an echo | 8 | Nielsen and its "Sweeps" redirect, BBC Four as the broadcaster, and "Existential crisis". |
| 7: the hops do not meet | 7 | Anneliese Midgley called for Adolescence in schools, but the Hansard hits are her delivery-workers clause. Raffles's notes on Tambora versus his founding of Singapore. |
| 5: wrong or not a lasting mark | 3 | The bill resolver sent the January 2024 Finance Bill to the Finance Act 2026, and the 2005 Terrorism Bill to the Terrorism Act 2025. |

## The decoys

**D1, intermediates paired with wrong stones.** Hop 1 was re-run for 43 stone-intermediate pairs against 124 wrong stones
(28 tests could use the measured test). Three passed:
- The West Wing's "New York (state)" passed with the 2001 anthrax attacks and with Game of Thrones. The guarded name "New
  York" matched "New York City" and "The New York Times" in causal sentences.
- The SVB collapse's "Signature Bank" passed with Bridgerton (Dec 25, 2020). Signature Bank's views rose 25.8-fold from
  Jan 12, 2021 (p = .01), a rise unrelated to the series. This is the measured test's expected false-positive rate
  showing itself.

All three sit on chains that failed the hand check. Under the registered rule, each is still a false chain.

**D2, famous films.** Three of fifty yielded an automated chain:
- Guardians of the Galaxy → Funko → "Superhuman Law", a She-Hulk episode whose title carries the word Law.
- The Dark Knight → the World Trade Center site → the 2019 Never Forget the Heroes Act. A scene is "reminiscent of" the
  site.
- Bohemian Rhapsody → GLAAD → the Respect for Marriage Act. GLAAD is in a list of endorsers.

All three would fail the hand check (criteria 5, 3 and 4). The Hansard leg never ran for the films, so three is a lower
bound.

## Diagnosis

The design held where the plan expected it to.
- Hop 1 measured the right things on the stones that have them: Joe Exotic, the Post Office scandal, Paula Vennells and
  Signature Bank.
- Records that name an intermediate exist and can be found: the Record for Joe Exotic, Hansard for the scandal.
- The ordering rule busted 102 of 131 Wikipedia pairs without a person.

What broke is the space between "a record mentions X" and "a record names X as a reason":
1. **The citation screen is too generous for intermediates.** cite_score was calibrated on works, where a nearby causal
   word usually means the work was the argument. Around a person or a company in a long Hansard speech, "after",
   "following" and "shows" turn up by chance. 276 Hansard windows scored "reason", 186 of them on a bill that became
   an Act afterward, and one survived.
2. **A reported hop 1 only needs a causal word in the same sentence.** Later events, places and outlets named in a
   stone's article became intermediates. Reported hop 1 produced 94 of the 112 chains and 1 of the 3 survivors;
   measured hop 1 produced 18 chains and 2 survivors.
3. **The name guard lets common strings through.** "9/11" counts as two words and matched Official Report date
   citations ("9/11/04"). "New York" matched inside "The New York Times". "Sweeps" is a redirect that the word list (no
   inflected forms) did not catch.
4. **The mark filter is a title regex.** `hop3.MARKT` accepted an episode titled "Superhuman Law" and filled Joe Exotic's
   twelve reverse-hop slots with 2024 party conventions.
5. **The bill resolver mishandles recurring titles.** A Finance Bill or Terrorism Bill resolves to the latest Act of that
   name.
6. **Up to twenty measured tests a stone at p ≤ .05** will throw up chance passes. Hop 2 is meant to absorb them, and
   D1's Signature Bank pass shows it does not always.

## Deviations and disclosures, in order

1. **The name guard's scope.** Section 2, rule 4 of the plan says all four filter rules must hold, then says a candidate
   with no guarded name is still matched by wikilink. I read rule 4 as deciding what can be searched, not what is a
   candidate. One main-set survivor had no guarded name and was not searched in Hansard or the Record.
2. **Stone data.** The catalog's "Cuyahoga River fire" has no article under that title (111 of 112 stones read).
   "Serial" and "Manhunt" point at pages that yielded no candidates. "Elemental (film)" resolved to a disambiguation
   page. Nothing was re-titled by hand.
3. **One pageview cutoff.** The run crossed midnight, so the cutoff was fixed at the Oct 4 run date (views to Oct 2) for
   every stage.
4. **Raw link targets live beside the cache.** Every stone's link targets feed the D1 exclusion. They are bulky and are
   kept out of the committed stage-1 file. `multihop.py stage1` rebuilds them.
5. **Stops were applied per host.** legislation.gov.uk returned 504 at about 07:30 UTC on Oct 5, the Bills API 500 at
   07:59, and Hansard 500 at 08:02. The plan said a stop ends the run for the day. I applied it to the host, as corpus 1
   did for the Federal Register and EDGAR, so the Wikipedia leg and the composition finished. No stopped host was
   contacted again that day. Hansard hits whose bill could not be resolved are kept as pending (33), and survivors not
   yet searched in Hansard are kept as pending (282). Pending handling arrived at 08:00 UTC. Between the
   legislation.gov.uk stop and then, 24 hits whose resolver call was skipped had been recorded as "no Act". They were
   re-marked as pending before composition. None could have formed a chain either way, because a pending hit is not a
   chain.
6. **Up to three requests in flight.** From 07:48 UTC, stage 2 ran up to three requests at once. One limiter still kept
   request starts at least a second apart across every host, so the plan's one-request-a-second rule held, but the plan
   did not say requests would overlap. The Bills API and Hansard errors came 11 and 14 minutes later, and the overlap may
   have contributed. After them it ran one request at a time.
7. **Redirects are not marks.** A redirect to the intermediate is another name for it, not an article that links to it,
   so the reverse hop never treats one as a mark.
8. **D1 draws depend on the full chain list.** A D1 pass run before the workflow's results arrived (fewer chains, so a
   different draw) also had 3 passes. It is superseded by the final composition counted above.
9. **Quoted records.** Em dashes inside quoted records are set as en dashes. Nothing else in a quote is changed.

## Limits

- **The Hansard leg is unfinished.** 162 main-set and 120 famous-decoy survivors wait for it. Finishing it can only add
  chains to check and chances for decoys, so the bar's verdict cannot improve on the decoy side. To finish it after
  07:00 UTC on Oct 6 (midnight in Seattle, so no same-day retry by either clock): `multihop.py resolve`, then
  `stage2 all`, `compose`, a hand check of the new chains, and `build`.
- **Wikidata gaps let creators through.** The Mr Bates item has no director or screenwriter statement, so both passed
  the echo rule (their chains found no record).
- **The title rule drops some real subjects.** It removes the real subject of a biopic named after them: Erin Brockovich
  the person, for the film.
- **The reverse hop is narrow.** It reaches only laws whose article links back to the intermediate. The two known
  positives came from the records, not from Wikipedia.
- **Reported is the ceiling.** No chain is stronger than its record, and a record naming a reason shows the intermediate
  was in the room when the mark was made, not that it caused it.
- **The hand check is one person's**, read with knowledge of which chains were known positives. It is not blind.

## What a v2 would change (to be registered before it runs)

1. **Hop 1 reported:** the stone must be the subject of the causal clause, or the intermediate's own article must name
   the stone.
2. **Hop 2 Hansard:** the window must name the bill or say "this Bill", and a window whose only causal word is "after"
   or "following" scores context, not reason.
3. **The name guard:** no numeric tokens, a proper-noun match, and single words stemmed before the word-list check.
4. **The mark filter:** a Wikidata class check (legislation, organization) instead of a title regex.
5. **The resolver:** match recurring bill titles by parliamentary session.
6. **Finish the pending Hansard leg** under v1 first, so the two versions compare on the same survivors.

## Files

- `docs/multihop_plan_v1.md`: the registered plan.
- `lab/discovery/multihop.py`, `multihop_compose.py`, `multihop_gov.py`, and `.github/workflows/ripples-multihop-gov.yml`:
  the scripts and the workflow (one push, one run, Oct 5, 07:19 to 08:58 UTC).
- `docs/results/multihop_stage1_v1.json`: stones, candidates, filter reasons, hop 1.
- `docs/results/multihop_hop2_v1.json` and `multihop_gov_v1.json`: hop 2 from the laptop and from the workflow.
- `docs/results/multihop_raw_v1.json`: every automated chain, D1 and D2.
- `docs/results/multihop_hand_v1.json`: the hand check.
- `docs/results/multihop_v1.json`: the three chains in a shape the demo can render, and the 109 rejected with why.
