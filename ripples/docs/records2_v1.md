# Records 2, result v1: the Federal Register as a cited-cause record; court opinions not run

*Run Oct 4, 2026 (local; 06:18 to 06:42 UTC Oct 5) under `docs/records2_plan_v1.md`, registered in commit 903fc6e
before any search. Runner `lab/records2.py`; queries `docs/results/records2_queries_v1.json`; every text read
`docs/results/records2_raw_v1.json`; my labels `docs/results/records2_hand_v1.json`; the pairs `docs/results/records2_v1.json`.*

## In one paragraph

**The registered bar is met on its own terms, and the result is narrower than the bar suggests.** Final rules in the
Federal Register name 14 of the stones as a reason for a rule the product did not have: **48 new stone → rule pairs**
survive the strict hand read (distinct stone and rulemaking; the bar was 5), **28** of them rules that are not
temporary by their own terms, and **15** that set a standing rule beyond the stone's own aftermath. **0 of 49 famous
films** passed the strict automated rule, and none passed my read. But every one of those pairs comes from an event
or a court decision (Hurricane Sandy, Katrina, September 11, Fukushima, Dobbs, Takata, the Oklahoma City bombing).
**Of 146 cultural works, 32 returned at least one final rule for their query, 5 sentences survived the guards, and 0
named the work as a reason.** The Federal Register is an events instrument, as the Wikipedia reverse hop was. For works,
Hansard and the Congressional Record are still the records route. **Court opinions:** not searched on Oct 4 for want of
a token; the owner created an account on Oct 5, and the first daily run (51 of 146 works) found no court pair: 74
sentences survived the guards, all context or aside (section "Court opinions" below).

## What each source allowed

| Source | What the documentation says | What happened |
|---|---|---|
| CourtListener REST API v4.7 | "Authentication is necessary"; authenticated limits 5 a minute, 50 an hour, 125 a day; anonymous use appears only in the FAQ, as a sign of a broken token | Not run on Oct 4. From Oct 5, a daily workflow with the owner's token (plan, section 9 and the Oct 5 addendum): 99 requests on day one, no refusal |
| Federal Register API v1 | No key. The documentation page answered the project's agent with an access-request (CAPTCHA) page that says programs should use the API; it was not passed or worked around | 965 requests at 1.1 s, no refusal during the run. Afterward, the first request of a corrective rescan got **HTTP 429**: stopped for the day, no retry (968 requests in all) |

## Numbers against the bar

| | Result | Bar |
|---|---|---|
| Stones searched | 235 (146 works, 63 events, 26 things); 10 skipped as duplicates or unsearchable | |
| Stones with any final rule matching the query | 79 (works 32, events 43, things 4) | |
| Final-rule texts read | 599 for stones, 63 for decoys (15 at most per stone) | |
| Sentences that survived the guards | 245 for stones (works 5, events 210, things 30); 2 for decoys | |
| Hand labels, stones | 67 reason, 120 context, 58 aside | |
| **New stone → rule pairs, hand label reason (registered count)** | **48** distinct stone and rulemaking pairs, from 14 stones | **at least 5: met** |
| Of those, not temporary by their own terms (stricter, after the fact) | **28** | |
| Of those, a standing rule beyond the stone's own aftermath (strictest) | **15** | |
| Cultural works with a reason pair | **0 of 146** | (not a bar; the question the run was meant to answer) |
| **Decoys passing the strict automated rule** | **0 of 49** | **0: met** |
| Decoys passing my read | 0 (two temporary safety zones for filming Transformers 3, a different film, read as asides) | |
| cite_score against my labels (stones) | precision .36, recall .78 (52 agree on reason, 92 it calls reason that I do not, 15 it misses) | |

The registered count includes temporary rules (a safety zone, an emergency fishery closure, a deadline extension),
because the plan defined the mark as any final rule. A temporary rule is not a lasting mark, so the stricter counts
leave them out; that cut was decided after the run and is disclosed as such. It only lowers the number.

## The pairs

Each line: the stone, the rule (agency, publication date, citation), why it counts, and the sentence (trimmed). Every
link is a reported link: the record names the stone as a reason. It does not show the stone caused the rule.

**Standing rules (15), the strictest reading:**

1. **The Oklahoma City bombing → the closure of Pennsylvania Avenue at the White House** (Secret Service, May 26,
   1995, 60 FR 27882). "This urgency has been accelerated by recent events, including the bombing of a Federal building
   in Oklahoma City." The least expected pair in the run: a domestic bombing that ended car traffic in front of the White House.
2. **The Takata airbag recall → EPA's Safe Management of Recalled Airbags** (EPA, Nov 30, 2018, 83 FR 61552). Issued
   without delay "by facilitating the urgent removal of dangerously defective Takata airbag inflators from vehicles,
   and by preventing defective Takata airbag inflators from scrap vehicles from being reused".
3. **Hurricane Sandy → SBA's disaster loan credit and collateral rule** (SBA, Apr 25, 2014 interim, 79 FR 22859;
   final Sept 15, 2016). "SBA is amending its disaster loan program regulations in response to Hurricane Sandy Rebuilding
   Task Force recommendations."
4. **Hurricane Sandy → FTA's Emergency Relief Program rule** (FTA, Mar 29, 2013, 78 FR 19136). Issued immediately, "in
   order to implement the Emergency Relief Program and to provide information regarding the application procedures for
   Emergency Relief Program grants in response to Hurricane Sandy."
5. **Hurricane Katrina → the FCC's rules from the Katrina panel** (FCC, July 11, 2007, 72 FR 37655; reconsideration
   Oct 11, 2007). The rule's title is the finding: "Recommendations of the Independent Panel Reviewing the Impact of
   Hurricane Katrina on Communications Networks" (47 CFR part 12).
6. **Hurricane Katrina → the Biloxi drawbridge rule removed** (Coast Guard, May 5, 2006, 71 FR 26414). "The bridge
   was destroyed by Hurricane Katrina and will be replaced with a fixed bridge." Small and permanent.
7. **September 11 → FAA screening and aircraft searches for certain operators** (FAA, Oct 4, 2001, 66 FR 50531).
   "This action is being taken to counter possible threats in the wake of the September 11, 2001 terrorist attacks."
8. **Fukushima → the NRC's Mitigation of Beyond-Design-Basis Events rule** (NRC, Aug 9, 2019, 84 FR 39684). The rule
   carries out the actions the staff prioritized "in Response to Fukushima Lessons Learned".
9. **Dobbs v. Jackson → VA reproductive health services** (VA, interim Sept 9, 2022, 87 FR 55287; final Mar 4, 2024).
   "Following the Dobbs decision, States began to ban or restrict abortion services and veterans living in those States
   were losing access to such medical care." **Rescinded** by a VA final rule of Dec 31, 2025, effective Jan 30, 2026.
10. **Dobbs v. Jackson → HHS's information-blocking exception for reproductive care** (HHS, Dec 17, 2024, 89 FR 102512).
    "In the wake of the decision in Dobbs ... some states have newly enacted or are newly enforcing restrictions on access
    to reproductive health care."
11. **The Boeing 737 MAX groundings → the airworthiness directive that returned the MAX to service** (FAA, Nov 20,
    2020, 85 FR 74560). "These actions create the opportunity for operators to safely return the 737 MAX to service,
    following a fleet-wide grounding lasting over twenty months."
12. **The Exxon Valdez → driving-record checks for merchant mariners** (Coast Guard, Dec 19, 1995, 60 FR 65478), via
    the Oil Pollution Act: the conference report "explains that alcohol impairment may have played a role in the Exxon
    Valdez incident", the reason the Act requires the check this rule carries out.
13. **Bhopal → EPA's 2024 Risk Management Program rule** (EPA, Mar 11, 2024, 89 FR 17622), via the Clean Air Act: "Both
    the Senate and the House committee reports on the CAAA specifically identify the Union Carbide-Bhopal incident as one
    that demonstrated the need for the accidental release prevention provision." The rule has been under EPA reconsideration since 2025.
14. **The Virginia Tech shooting → the HIPAA rule that lets covered entities report to NICS** (HHS, Jan 6, 2016, 81 FR
    382), via the NICS Improvement Amendments Act: "Following the shooting at Virginia Tech University in 2007, and other
    tragedies involving the illegal use of firearms, Congress enacted the NICS Improvement Amendments Act".
15. **The Uvalde shooting → ATF's "engaged in the business" rule** (ATF, Apr 19, 2024, 89 FR 28968), via the Bipartisan
    Safer Communities Act: "These BSCA amendments were enacted after tragic mass shootings at a grocery store in Buffalo,
    New York; at an elementary school in Uvalde, Texas; and between Midland and Odessa, Texas."

**Lasting, but scoped to the stone's own aftermath (13):** Silicon Valley Bank → the FDIC's special assessment (Nov 29,
2023) and its collection rule (Dec 19, 2025); the Exxon Valdez → income averaging for settlement income (Dec 15, 2010,
under Public Law 110-343); Deepwater Horizon → the RESTORE Act spill impact allocation (Dec 15, 2015); Hurricane Sandy →
FEMA's force account labor rule for debris removal (2012, 2014); Hurricane Katrina → royalty relief for Gulf lessees (Sept
29, 2005) and the Katrina housing deduction regulations (2009); September 11 → compensation procedures for air carriers
(Oct 29, 2001), the travel agency size standard for September 11 disaster loans (2002), immediate relatives to include
victims' widows and children (2003), special immigrant status for victims' beneficiaries (2003), the 9/11 Heroes Stamp
program (2005), and World Trade Center Health Program eligibility for Pentagon and Shanksville responders (Sept 11, 2024).

**Temporary (20 more in the registered count):** safety zones, emergency fishery closures, deadline extensions and
waivers after Deepwater Horizon, Katrina, Sandy and September 11.

**Already in the product, not new:** the Las Vegas shooting → ATF's bump-stock rule (Dec 26, 2018), which
`demo/discovered_wiki.json` carries; vacated by the Supreme Court in Garland v. Cargill on June 14, 2024.

## What the works produced

Five sentences survived for cultural works, and each is an aside or context: a 2008 60 Minutes segment on e-waste in
the EPA CRT rule's reference list (not the 2011 episode that is the stone); a commenter recalling a West Wing episode
about Indiana's time zones; a commenter's quip about falcons in a Harry Potter movie, in the falconry rule; Fortnite as an
example of in-game voice chat in the Truth in Caller ID rule; homebrew games for the Wii as evidence in a copyright
exemption. The guards screened out the rest (Friends of the Earth, specific gravity, "Grease Removers", Sing Sing, Booz
Allen Hamilton). The registered queries for The Jungle, Silent Spring, Unsafe at Any Speed, Super Size Me, Blackfish,
Tiger King and Fast Food Nation returned no final rule after their dates. The one Federal Register citation of a work
known in advance is a history paragraph in a proposed rule (the diagnostic below).

## Diagnostics and expectations

- **Known positive: passed.** The query `"The Jungle"` (proposed rules, 1995) returned 95-2366, and the matcher passed its
  sentence: "In 1906, the graphic picture of insanitary conditions in meat-packing establishments described in Upton
  Sinclair's novel The Jungle outraged the U.S. public." cite_score calls it context, which is right for a 1990s rule.
- **Known negative: passed.** "Silent Spring" in the 2022 Toxic Release Inventory rule was screened out three times as
  the Silent Spring Institute.
- **Expectations written down before the run** (not scored): Fukushima and the beyond-design-basis rule, and Las Vegas
  and the bump-stock rule, were recovered as reasons. The anthrax attacks appear in every select agent rule, but as an
  example of costs (context). The Lead and Copper Rule revisions matched Flint, but the passing occurrence kept was a
  reference-list title. BSEE's well control rule and the SEC's 2009 custody rule were not among the 15 texts read for
  their stones (emergency and temporary rules filled the relevance list). The Lac-Mégantic rules were found and not
  read correctly (next section).

## Court opinions (CourtListener): the first daily run, Oct 5

Run under the plan's section 9 and the Oct 5 addendum, which was committed (729bc5b) before any court query. The token
lives only in the repository secret and the workflow (`.github/workflows/ripples-courts.yml`, `lab/records2_courts.py`).
Raw results `docs/results/records2_courts_v1.json` (written by the workflow, `[skip ci]`); my labels
`docs/results/records2_courts_hand_v1.json`.

| | Day one (Oct 5, 07:04 to 09:16 UTC) | Bar |
|---|---|---|
| Requests | 99 counted (51 searches, 48 opinion texts) plus one usage check, which has its own throttle; 80 s apart; no refusal. The account had used 3 requests before the run; the day ended at 102 of 125 | under 125 a day and 50 an hour |
| Stones searched | **51 of 146 works** (the catalog's, the wider and held-out lists' works, and the first five of the culture list); 0 decoys, 0 events, 0 things | |
| Works with any published opinion | 41 | |
| Sentences that survived the guards | 74, from 21 works (48 read in full, 26 from snippets over the per-stone cap) | |
| Hand labels | **0 reason**, 26 context, 48 aside | |
| **New work → holding pairs** | **0 so far** | at least 5: not met on day one |
| Decoys passing the strict automated rule | not yet searched | 0 |
| cite_score's reason label | 17 sentences; none is a reason on my read | |

**What courts do with works.** When a work reaches an opinion, it is usually the case itself (Nichols v. Moore, the
defamation suit over Bowling for Columbine; Warner Bros. v. RDR Books, over a Harry Potter lexicon; a school's refusal to
show Schindler's List), which is the law acting on the work and does not count. Otherwise it is evidence (two New Jersey
appellate courts on experts who relied on Silent Spring), an example (Unsafe at Any Speed as muckraking that "forced
reforms on the automobile industry", in a libel case), history (The Jungle opening the Ninth Circuit's 2018 ag-gag
decision), or a fact in the record (a juror's views of Making a Murderer). The nearest misses: General Motors v. Volpe (D. Del.
1970), a vehicle safety case, cites Unsafe at Any Speed, but the stored sentence is the bare citation, so it is
labeled context; and Highfields Capital v. SeaWorld, a securities case about statements made "in the wake of the 2013
documentary Blackfish". The guard let through a company name (Leonetti's Frozen Foods) and a different work (The Jungle
Book); both are asides.

**What remains:** 95 works, 49 decoys, 63 events and 26 things, about three more daily runs. The court numbers here are
partial and will be replaced as the runs finish.

## Deviations and incidents, in the order they happened

1. **A matcher bug found during the run.** The Federal Register's raw text writes accented letters as GPO codes
   ("Lac-M[eacute]gantic"), so all seven Lac-Mégantic rules the search found (PHMSA's high-hazard flammable train rule,
   FRA's securement rule, the crew size rule and four more) produced no match. One diagnostic request confirmed it, the
   matcher now decodes the codes (`fold`, with a self-test), and a rescan of those seven texts was started. **The host
   answered the rescan's first request with 429**, so the rescan stopped for the day. Lac-Mégantic contributes nothing to
   any count here. No other stone has an accented or curly-quoted phrase with a final rule found.
2. **Not-a-mark wording the runner missed.** Its exclusion list did not catch "Delay of Effective and Compliance Dates",
   petition denials, notices, circulars, guidance, an emergency order and a proposed rule filed under the rule type. I
   marked each "not a mark" in the hand file; none counts.
3. **Temporary rules,** counted in the registered number and left out of the stricter ones (above).
4. **Four sentences the window cut short** (the Coast Guard's 1995 drug testing rule and the Exxon Valdez, OPM's 2012
   health benefits rule and Sandy, the SEC's 2013 broker-dealer rule and Madoff, the FAA's 2024 safety management rule
   and the 737 MAX) needed the paragraph around them. The 429 ruled out reading it today, so each is labeled context,
   the strict reading, with "probable reason" in the note. None counts.
5. **Stone dates for same-year rules:** Katrina's landfall (Aug 29, 2005), the 737 MAX grounding (Mar 13, 2019) and the
   Equifax disclosure (Sept 7, 2017), from the rules' own texts, decided order for rules from the same year.
6. **A rule's own title is part of its record.** Where the title names the stone as the rule's subject ("... for
   Housing Hurricane Katrina Displaced Individuals"), the title decided the label even when the kept sentence was a header.
7. **Privacy:** one aside quoted an Entity List entry with private names and addresses; it is replaced in the stored
   files with a one-line description.

## Limits

- **Selection by score.** For each rule the runner kept the passing occurrence with the highest cite_score. When that is
  a footnote or a reference (the HIPAA reproductive health privacy rule, the Lead and Copper Rule revisions), the hand
  label is context even if the rule elsewhere names the stone as its reason. The counts are a floor.
- **Relevance and the cap.** 15 texts per stone, in the search's relevance order. For big events, temporary rules
  crowded out the rulemakings that matter (BSEE's well control rule).
- **Obvious links.** Most standing pairs are the consequence a reader would guess (a disaster, then the agency's rule).
  The surprises are small: Pennsylvania Avenue, the Biloxi bridge, Exxon Valdez settlement income, mariners' driving
  records. "New" means new to Ripple's data, not new to the world.
- **Status was not checked systematically.** Known changes are noted (the VA rule rescinded, the bump-stock rule vacated,
  the FDA's laboratory-developed test rule, a context row, vacated by a court in 2025, the 2024 RMP rule under reconsideration).
- **cite_score transfers badly.** It was calibrated on Hansard (.73 precision) and reaches .36 here: rule preambles are
  full of "following", "after", "in response to" and change words in sentences that are not about why the rule exists.
  It is a candidate screen for this source, not a label.
- **Coverage:** the API's full text starts in 1994, so the 1980s rules that followed Three Mile Island, the Tylenol
  poisonings or Love Canal are not in it; the 1990s and later rules that cite those events are, mostly as history.
- **Not wired into the demo.** `records2_v1.json` uses the shape of `bill_act_v1.json`'s pairs (work, work_date, bill,
  debated, act, royal_assent, sentence, debate_url, act_url, cite_score, cite_label), plus rule fields (kind "rule",
  source, agency, document_number, fr_citation, rin, effective_on, hand_label, via, scope, status) and empty court fields
  (court, case_name, date_filed, opinion_url, holding_mark). Wiring it in should read `hand_label`, not cite_score, and
  label the links "Federal Register", since `fromActs` names every US link "Congressional Record". `demo/index.html`
  was not changed. "bill" holds the rulemaking's RIN, and "royal_assent" the rule's effective date (its publication
  date when the API has none).

## Next steps

1. **CourtListener, days two to four:** one push a day to `.github/workflows/ripples-courts.yml` (any edit to the file,
   such as its header comment) starts the next run; it resumes from the done list: 95 works, then the 49 decoys, the
   63 events and the 26 things. The data-day workflow can take this job over once it exists on the remote.
2. **Lac-Mégantic rescan** (seven texts, the fixed matcher) from a workflow on another day, and the four paragraphs in
   deviation 4.
3. **For works, stay with the legislatures.** The Congressional Record and Hansard name works; final rules do not.
   Proposed rules may (the HACCP history paragraph); they are records, not marks.
4. **Keyed sources, not used here:** OpenStates (state bills), regulations.gov (dockets and public comments), and GovInfo's
   court opinions collection with the project's `DATA_GOV_KEY`, from a workflow.
5. **For events, read the rulemaking, not the first 15 hits:** search by agency and by RIN once a stone has one reason
   pair, and exclude temporary rules at the query.
