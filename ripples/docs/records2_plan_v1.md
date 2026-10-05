# Records 2: court opinions and the Federal Register as cited-cause records (plan v1)

*Registered Oct 4, 2026, before any search was run. Item 6 of the discovery program (HANDOFF section 8, "Data").*

The records route's strongest finds come from records that name a work as a reason: Hansard and the Congressional
Record ("the work was in the room when the law was made"), resolved to the Act that passed (`lab/mark_text.py`,
`lab/bill_act.py`, `docs/results/bill_act_v1.json`). This plan adds two US record types and fixes every rule before a
single search: the Federal Register's final rules, and US court opinions. Nothing below has been searched yet. The
runner is `lab/records2.py`; the query for every stone is `docs/results/records2_queries_v1.json`, written by
`python3 ripples/lab/records2.py plan` and committed with this file.

## 1. What each source allows (read before registering)

**CourtListener (court opinions).** The v4.7 REST API documentation (courtlistener.com/help/api/rest/ redirects to
wiki.free.law) says, under Authentication: "Authentication is necessary to monitor and control the system." The
documented rate limits are for authenticated users only: 5 requests a minute, 50 an hour, 125 a day. The throttling FAQ
mentions usage "recorded as anonymous" as a sign of a broken token, not as a supported mode. A token comes with an
account, and this project creates no accounts. **CourtListener is therefore not run.** Its design is registered in
section 9 so a later run, with a token the owner creates and stores as a GitHub secret, needs no new plan. Scraping the
site's HTML search instead would be a way around the authentication rule and is not done.

**Federal Register.** The API (`https://www.federalregister.gov/api/v1/`) needs no key; the Oct 4 probe used it.
Fetching the developer documentation page with the project's agent returned an access-request page with a CAPTCHA
("programmatic access to these sites is limited to access to our extensive developer APIs"). That page was not passed or
worked around; it says the API is the sanctioned route for programs, and the API is what this plan uses. No published
rate limit could be read, so the project's own limit applies, with margin: one request every 1.1 seconds. If the API
itself answers with that access page, the run stops for the day (section 7).

## 2. What counts as a record and as a lasting mark

**Federal Register.** The record is a final rule's preamble (the text before "List of Subjects" or "For the reasons
stated in the preamble", where the regulatory text begins). The **mark is the final rule itself** (API type `RULE`,
which includes interim final rules), dated by its effective date, or by its publication date when the API carries no
effective date. Not marks, and not read: corrections, correcting and technical amendments, delays of an effective
date, stays, withdrawals, comment-period or compliance-date extensions, confirmations of an effective date. Proposed
rules and notices are not read (one diagnostic in section 5 excepted). A work named only in the regulatory text or a
reference list is not a preamble citation.

**Courts (registered, not run).** A published opinion that decides a case and names the work in its reasoning is a
record. The mark is the holding only if the case set a lasting rule: a precedent with its own Wikipedia article, or a
statute struck down or construed. A passing mention (a cultural reference, a quotation, an exhibit, a party's name) is
an aside.

## 3. The stones and the decoys

Every stone list already in `lab/discovery/`, deduplicated:

| List | Source | Searched |
|---|---|---|
| Catalog | `docs/results/stones_all.json`, in class | 40 (3 duplicates skipped) |
| Wider | `lab/discovery/wider.py` | 55 (5 duplicates skipped) |
| Held out | `lab/discovery/heldout.py` | 16 (4 duplicates skipped) |
| Culture | `lab/discovery/culture_stones.py` | 124 (8 already listed above) |
| **Stones** | | **235**: 146 works, 63 events, 26 things (toys, fads, programs, a regulation, two court cases) |
| **Decoys** | `lab/discovery/famous_decoys.py`, fifty famous films with no mark the builder knows of | **49** (It (2017) is skipped: a single function word cannot be searched as a phrase) |

Stone dates come from the lists (exact where the catalog or `demo/discovered_wiki.json` has verified one, the year
otherwise).

## 4. The query per stone

Every query is in `docs/results/records2_queries_v1.json`, one or more per stone (298 in all).

1. **The exact title or name in quotes** (`conditions[term]`), less any parenthetical; a handful use the form a US
   document would use ("Harry Potter", "Great British Baking Show", "Lac-Mégantic" and "Lac-Megantic", "Space Shuttle
   Columbia", "anthrax attacks").
2. **Plus one disambiguating word when the phrase is ambiguous** (131 stones). Ambiguous was decided by hand, before
   any search, by one test: could the phrase mean something else in a US government document (ordinary words, a place,
   a person, a company, a product, another event)? "Friends" (Friends of the Earth), "Titanic" (the ship), "Jersey
   Shore" (the coast), "Columbine" (a plant), "Challenger" (a business jet with its own airworthiness directives),
   "Three Mile Island" (a plant with its own license actions), "Sandy Hook" (a national recreation area). The word is
   the work's kind (film, television, documentary, book, game, song, album, musical, podcast, or the network:
   Netflix, HBO, MTV, CBS, BBC) or, for events, the event (shooting, bombing, breach, fire, accident). One word, so the
   query relies only on the search's implicit AND, not on operator syntax this plan could not read.
3. **The disambiguation that decides is in the sentence, not the document.** The "WarGames → NDAA" pair was a document
   that said "wargames" (the exercises) and, elsewhere, "movie". So every occurrence must pass a sentence-level guard:
   - **Ambiguous works:** the title must be introduced as a work (a work word directly before it, "the film Jaws", or
     directly after it, "Blackfish, a 2013 documentary"), carry a creator's possessive ("Rachel Carson's Silent
     Spring"), sit in quotation marks (two words or more), or share its sentence with the stone's own anchor (its
     creator or subject, listed per stone in the query file: Upton Sinclair, SeaWorld, Joe Exotic). A work word
     elsewhere nearby is not enough.
   - **Distinctive works:** any of the above, or a work word within 160 characters.
   - **Ambiguous events and things:** the stone's own event words in the same sentence (for the Las Vegas shooting:
     shooting, massacre, October 1, 2017, gunman, bump).
   - **Works and things fail outright** when the match is the first part of another name: Silent Spring Institute,
     X Foundation, X Road, X Inc. (the full list is `NAMESAKE` in the runner).
   - Matching is case-sensitive on the title as written (or in capitals), with accents and curly quotes folded;
     common-noun things (fidget spinner, ketogenic diet, the anthrax attacks) match in any case.
4. **The ordering rule at the query:** `conditions[publication_date][gte]` is the stone's date (January 1 of its year
   when only the year is known). The API's full text starts in 1994, so older stones are searched from 1994.
5. `conditions[type][]=RULE`, `order=relevance`, 20 results a query. Up to **15 final-rule texts per stone**, in
   relevance order across its queries (the first query's list first), each read in full from the `raw_text_url` the
   API returns. Every occurrence in the preamble is guarded; the passing occurrence with the highest citation score is
   the one kept (ties: the earlier one).

## 5. Labels, order, known positives and negatives

**The automated label** is `lab/cite_score.py` unchanged: reason (2 or more), context (1), aside (0 or less), computed
on the sentence before, the sentence and the sentence after (about the 600-character windows `bill_act_v1.json` scored).

**The hand label** is mine, strict, on every surviving sentence (every occurrence that passes the guards in a final rule
after the stone), stones and decoys alike:
- **reason:** the preamble names the stone as a cause of this rulemaking ("following", "in response to", "led the
  agency to", "demonstrated the need for this rule"), or as the cause of the statute this rule implements when the
  same passage ties the rule to that statute. The second kind is tagged *via statute*.
- **context:** the stone is evidence, an example, a data point or history in the rule's justification, without being
  named as why this rule or its statute exists. A history paragraph that credits the work with an older law (The
  Jungle and the 1906 Act in a 1990s meat rule) is context for the rule; the older law is noted, not counted.
- **aside:** a passing mention: a reference-list entry, a namesake, a place, a commenter, the stone's own program
  named by its own implementing rule, or a different referent.

**The ordering rule:** the record comes after the stone. Publication date after the stone's date; where the stone's
date is only a year and the rule is from the same year, the stone's exact date is looked up before the pair can count.

**Known positive (diagnostic).** No final rule is known in advance to name a work as a reason. The one known Federal
Register citation of a work is FSIS's Pathogen Reduction / HACCP proposed rule (Feb 3, 1995, document 95-2366: "the
graphic picture of insanitary conditions in meat-packing establishments described in Upton Sinclair's The Jungle").
Before the main run, one query (`"The Jungle"`, proposed rules, 1995) must return 95-2366, and the matcher must pass
that sentence from its text. If either fails, the matcher is broken and the run does not proceed until it is fixed and
the fix disclosed. Whether the July 25, 1996 final rule repeats the sentence is unknown; the main run will show it.

**Known negative.** The Oct 4 run counted "Silent Spring" in the Nov 30, 2022 Toxic Release Inventory final rule
(document 2022-25946). It was the Silent Spring Institute, a commenter. The matcher must screen it out (the namesake rule).

**Expectations, not scored.** Events where a final rule is likely to name the stone as its reason, written down so a
reader can judge recall afterward: Lac-Mégantic and PHMSA's high-hazard flammable train rule (2015); Deepwater
Horizon and BSEE's well control rule (2016); the Las Vegas shooting and ATF's bump-stock rule (2018); Flint and EPA's
Lead and Copper Rule revisions (2021); Fukushima and the NRC's beyond-design-basis events rule (2019); the anthrax
attacks and the select agent rules; Madoff and the SEC custody rule (2009 to 2010).

**Decoys.** The same queries, guards and labels. A decoy **passes** if the strict automated rule produces at least one
pair for it: a final rule, after the film's release, an occurrence that passes the guards, cite_score reason. My hand
read of decoy sentences is reported beside it.

## 6. The bar (both must hold)

1. **At least 5 new, real stone → rule pairs that survive the strict hand read** (hand label reason, ordered).
   Counted as distinct (stone, rulemaking) pairs, a rulemaking identified by its RIN (the document number when there is
   none). New means the pair is not already in the chains, the maps, `demo/discovered_wiki.json`,
   `docs/results/bill_act_v1.json` or `docs/results/mark_text_v1_3.json` as that stone → that mark.
2. **Decoy pass rate 0 of 49 under the strict automated rule.**

Reported beside the bar, with no threshold: works against events and things; direct against via statute; cite_score's
precision and recall against the hand labels; the two diagnostics; how many stones had any final rule at all.

## 7. Politeness and stops

The honest user agent `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`; 1.1 seconds between requests;
a budget of 1,500 requests. A **stop for the day** on any 401, 403, 429 or 5xx, on a timeout, or on a redirect to the
access-request page: no retry, no other agent, and no other host for the same text. **Deviation from Oct 4, disclosed
in advance:** a 404 on one document's text is logged as "no text" and that document is skipped. The task's stop list is
401, 403, 429 and 5xx; a 404 is a missing file, not a refusal (the Oct 4 probe stopped the host for the day on one).

## 8. What is stored

Aggregate data only. For a Federal Register rule: the stone, the rule's title, agency, document number, RIN,
citation, dates, the one sentence, the three-sentence window the score read (700 characters at most), the labels and
the URL. For a court opinion (future): only the work, the case name, the court, the date, the one sentence and the URL,
because opinions name people. No keys anywhere.

**Output:** `docs/results/records2_raw_v1.json` (every text read, every surviving sentence), `docs/results/records2_hand_v1.json`
(my labels, one line of reason each), `docs/results/records2_v1.json` (the pairs, in the shape of `bill_act_v1.json`'s
pairs: work, work_date, bill, debated, act, royal_assent, sentence, debate_url, act_url, cite_score, cite_label, plus
rule fields and empty court fields), and `docs/records2_v1.md` (numbers against the bar, the pairs quoted, the limits).

## 9. CourtListener, registered for a later run (needs a token)

- Endpoint `GET /api/rest/v4/search/?type=o` (case law; published opinions are the default), `highlight=on`.
- Query per stone: the same phrase in quotes; for ambiguous stones `AND (film OR movie OR television OR documentary OR
  novel OR book)` for works, or the stone's event words for events (CourtListener documents boolean syntax, so the
  grouped form is safe there).
- Ordering: `filed_after` the stone's date. Read the opinion text only for hits whose snippet passes the same guard.
- Labels as in section 5; the holding is the mark only under section 2's rule (its own Wikipedia article, or a statute
  struck down or construed), checked by hand.
- Budget: 284 searches at the documented 5 a minute and 125 a day is three days of searches before any opinion text;
  the run belongs in a scheduled workflow with the token as a secret, or under a Free Law Project membership.

## 10. Not used, and why

OpenStates (state bills, a key) and regulations.gov (comments and dockets, a key) are next steps, not used here. GovInfo's
court opinions collection (USCOURTS) needs the project's `DATA_GOV_KEY`, which may only be used from a workflow.
