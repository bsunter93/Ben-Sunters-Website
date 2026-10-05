# Screen v2: the written definitions govern, plus a dating step (Oct 5, 2026)

The result of `docs/screen_plan_v2.md`, registered in commit `80e3151` before any v2 lookup or label. The owner ruled
on Oct 5 that the project's written definitions of a lasting mark govern. v2 keeps the blind v1 labels and adds one
mechanical step: an undated mark is dated from its own record, and the ordering rule is applied to that date. The ground
truth is the person's keeps minus the 22 that violate the written definitions, listed in the plan.

**Verdict: the bar is not met.** Recall of kept marks is 0.75 (62 of 83) against 0.80. Precision is 0.85 against 0.61,
and 0 of 33 famous decoys passed. Events come within one mark of the recall bar (0.79, 48 of 61). Culture does not
(0.64, 14 of 22). The owner's ruling moved recall from 0.56 to 0.70. The dating step moved it from 0.70 to 0.75.

## Against the registered bar (pooled over E1 to E4)

| Bar | Registered | v1 | v2 | |
|---|---|---|---|---|
| Precision | at least 0.61 | 0.863 | **0.852** (69 of 81) | met |
| Recall on kept marks | at least 0.80 | 0.562 (v1 truth) | **0.747** (62 of 83) | **not met** |
| Famous decoys passed (E5) | 0 | 0 of 33 | **0 of 33** (0 of 11 in E6) | met |

Candidate-level agreement: 0.90, Cohen's kappa 0.66 (v1: 0.51).

| Set | Person kept | Screen passed | Precision | Recall (marks) |
|---|---|---|---|---|
| E1 strict reverse pairs | 14 | 13 | 1.00 | 0.93 (13 of 14) |
| E2 held-out forward | 10 | 8 | 1.00 | 0.89 (8 of 9) |
| E3 v1.1, sixty stones | 68 | 50 | 0.82 | 0.76 (34 of 45) |
| E4 culture shelf | 18 | 10 | 0.70 | 0.47 (7 of 15) |

| Class | Precision | Recall (marks) | Verdict |
|---|---|---|---|
| Events | 0.86 | 0.79 (48 of 61) | not met, by one mark |
| Culture | 0.82 | 0.64 (14 of 22) | not met |

### Registered sensitivity lines

| Line | Precision | Recall (marks) |
|---|---|---|
| (a) Only the owner's five named classes removed (Dimmock, Avatar's 3D televisions and the plastics study stay kept) | 0.85 | 0.71 (62 of 87) |
| (b) v1 ground truth, v2 labels: the dating step alone | 0.86 | 0.60 (63 of 105) |
| (c) Mechanical sentence matches only | 0.83 | 0.71 (59 of 83) |
| (d) Candidates the labeler did not recognize from the docs | 0.71 | 0.67 (22 of 33) |
| v1 labels against the v2 truth: the ruling alone | 0.85 | 0.70 (58 of 83) |

The bar fails on every line.

## The dating step

| | Count |
|---|---|
| Candidates eligible (v1 rejected them only as undated) | 64 |
| Mark has no record of its own (null, with a reason, fixed before any lookup) | 43 |
| Records looked up | 21 (27 Wikipedia requests across both pools; no refusal) |
| Resolved | 8: 2 by title year, 6 by an infobox field |
| Busted by the ordering rule | 0 here; 1 in the new pool (the Federal Surplus Relief Corporation, formed 1933, before Black Sunday in 1935) |
| Newly passing | 8, of which 3 are duplicates of marks already passed |

The eight it resolved: section 409A after Enron (American Jobs Creation Act of 2004, title), the Patriot Act (signed
2001), the TSA (formed 2001), JASTA (passed 2016), the Early Notification Convention after Chernobyl (signed 1986),
the NICS Improvement Amendments Act (2007, title), Never Again MSD (formed 2018) and the Tianchisaurus naming after
Jurassic Park (authority 1993). Each source is in `docs/results/screen_dating_v2.json`.

The 13 that did not resolve:

- **No page under the named title (5):** Canada's Anti-terrorism Act, India's Bhopal claims Act, NASA's Office of Safety
  and Mission Assurance, and the OnePulse Foundation (twice).
- **No year in the title or an infobox (6):** the Victim Compensation Fund, the Joint Convention, Chernobyl Children
  International, the Sambhavna clinic, the Rogers Commission Report and the Challenger Center.
- **A redirect judged a different subject by the registered rule (2):** the MSD High School Public Safety Act redirects
  to "Florida Senate Bill 7026", and CERCLA redirects to "Superfund". Both are misfires of that rule, since each is the
  same law. Both marks are recalled through other candidates, so neither changes a number.

## Why recall still fails: the 21 missed marks

| Why | Marks | Examples |
|---|---|---|
| No record of its own to date it (null) | 12 | Culture (7): reef fish demand after Finding Nemo, Dalmatian purchases, the Sideways wine shift, chess set sales, New York's parole rule for Pokémon Go, baking sales after Bake Off, marine biology applications after Blue Planet II. Events (5): Connecticut's FOIA change, the Rana Plaza inspection laws, Florida's unanimity repeal, New York's age-21 law, the bump-stock ban |
| A named record that did not resolve | 5 | Canada's Anti-terrorism Act, the Joint Convention, the Rogers Commission, the Challenger Center, the OnePulse Foundation |
| The sentence does not carry the link | 4 | the Exxon Valdez image caption (S13), the UK Companies Act's list of precursor reports (WR08), AB 1054 in a bankruptcy timeline (WF137), the carbon-offset study cut off mid-sentence (C222) |

Quoted, from the first row: "Demand for tropical fish skyrocketed after the film's release, causing reef species
decimation in Vanuatu" (C016). "In the state of New York, sex offenders are banned from using the application while on
parole" (C034). Each is a real, written mark whose only record is the sentence itself. A Wikipedia infobox cannot date a
behavior. **This is the culture gap, and the dating step as specified cannot close it.** It needs dated series (the
SSA and ONS name files, wine and toy sales, UCAS applications) or the date of the sentence's own citation.

If the five unresolved records had resolved, recall would be 67 of 83 (0.81). That figure is not a result: getting there
would mean renaming records after seeing which ones failed, which the plan does not allow.

## The twelve false passes

Ten carry over from v1: the title-only reverse pairs for Grenfell and Epstein (WR06, WR13), the Chernobyl investigating
commission (WF020), the 1995 taggant law (WF083), the Virginia Tech endowment funds and youth chapter (WF084, WF087),
the Pulse memorial funding (WF112), chokehold bans in 17 states (WF119), the Fifty Shades injury rise (C071) and
MinecraftEdu (C149). Two are new:

- **WF022, the UN Chernobyl Trust Fund, "created in 1991 by the United Nations to help victims".** It was a hand keep
  and a v1 pass. Under the ruling it is a relief fund, so the pass now counts as false. Rubric v1 lists "fund" as an
  institution and does not separate relief funds; a v3 rubric would.
- **C064, the Tianchisaurus naming.** The dating step dated it (1993, the film's year), but the person did not keep it.

## New pools (exploratory; screened by a language model, not by a person)

`docs/results/screen_new_v2.json` lists 47 passes. None enter the product without a person.

**The never-screened catalog pool (192 sentences): 26 accepted.**

- The 24 v1 passes stand.
- The dating step adds the FDA after The Jungle (formed 1906) and the UC Training School for Nurses after the 1906
  earthquake (established 1907).
- It busts the Federal Surplus Relief Corporation as a Black Sunday mark: formed 1933, before the stone.

**The Federal Register pool of records 2 (247 rule sentences, hand labels not read): 21 accepted, 0 of 2 decoys.** Every
pass is an event; the three culture sentences (Harry Potter, Fortnite, the Wii) are asides. Most rejections are the
stone used as history, an example or a citation (143), or a document that is not a lasting rule: a petition, notice, guidance, temporary rule or relief (65). Passes not in the
catalog include:

- the 1995 closure of Pennsylvania Avenue by the White House, whose "urgency has been accelerated by recent events,
  including the bombing of a Federal building in Oklahoma City" (F156);
- income averaging for Exxon Valdez settlement income (F022);
- National Driver Register checks for mariner licenses after the Exxon Valdez (F034);
- EPA's RCRA exemption to speed removal of Takata inflators (F183);
- a Biloxi drawbridge replaced by a fixed bridge after Katrina (F225).

## Deviations from the plan, disclosed

1. **Two bugs in the dating script, found on its first run and fixed before any metric was computed.** Infobox field
   names written without underscores ("signeddate", "effective date") and with digits ("passeddate2") did not match,
   and the first script carried an unregistered field ("date_drafted"), which is now dropped. The first run resolved 10
   records, the corrected run 13. The three added (the Patriot Act, JASTA and the Pure Food and Drug Act) are all
   duplicates of marks already passed, so the fix changes no number in this doc. The first run's output is described
   here, not committed.
2. **The registered govinfo and legislation.gov.uk fallback was not run.** It applied only to CERCLA, a US statute whose
   record the redirect rule set aside. Its mark is recalled through another candidate, and in the new pool it would be a
   duplicate. No request went to either site.
3. **A branch path in the plan** was shortened after registration. Nothing else in the plan changed.
4. **The Federal Register pool needed a reading of the rubric for rules.** It is recorded in `screen_new_v2.json`
   (`labeling_notes`), and it was fixed before those labels were written. "Reason" means the sentence gives the stone
   as the reason for the rule or for the standing requirement it sets or amends. A rule that removes a stone-born
   requirement, or implements a statute the stone caused, is context.

## Limits

- **v2 is not blind.** Its labels are the blind v1 labels moved by a lookup, but the ground truth's removals, the record
  titles and the duplicate calls are the labeler's, made after seeing every v1 result. All of them are listed.
- **The ground truth extends the owner's five classes by one row.** "Attention, growth or crazes" removes Avatar's 3D
  televisions and the Blue Planet II plastics study. Line (a) drops that extension: recall 0.71.
- **Wikipedia infoboxes are uneven.** Six named records had none with a year. The redirect rule misfired twice.
- **The Federal Register labels are one labeler's.** That labeler read the records 2 summary first, which reports that
  the source finds events, not works.

## Files

- `docs/results/screen_dating_inputs_v2.json`: record titles, fixed before any lookup.
- `docs/results/screen_dating_v2.json`: every resolved date and its source.
- `docs/results/screen_labels_v2.json`: the v2 labels and the dating log.
- `docs/results/screen_compare_v2.json`: metrics, sensitivity lines, confusion lists and the removed units.
- `docs/results/screen_corpus_v2.json`: the labeled corpus with v2 decisions. Removed hand keeps are marked rejected
  with the class of violation.
- `docs/results/screen_new_v2.json`: 47 passes from the two new pools, screened by a language model, not by a person.
- `lab/discovery/screen_date.py` and `lab/discovery/screen_v2.py`: the scripts.
