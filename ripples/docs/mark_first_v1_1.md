# Mark-first search v1.1: the coverage fixes, pre-registered (explore stage)

*Written Oct 3, 2026, after v1 and before the v1.1 run. Explore stage under explore-then-confirm (ledger 1466).*

**Why a v1.1.** v1 (`mark_first_v1.md`) failed its recall rule: 1 of 5 strict. Every miss was a set-membership or
vocabulary gap, not a missing signal: the Big Cat Public Safety Act, the Post Office (Horizon System) Offences Act and
the National Traffic and Motor Vehicle Safety Act were not in the marks set; *Unsafe at Any Speed* (nonfiction) was not
in the works set; *The Jungle*'s sentence ("foremost among such exposés", section "Historical motivation for enactment")
had no word in the causal list; the Post Office Compensation Act carried a bill date, not its Royal Assent. The method
found six documented pairs where coverage reached (Quincy, M.E. → Orphan Drug Act; 60 Minutes → STOCK Act; Victim →
Sexual Offences Act 1967; The Daily Show → Zadroga Act; The West Wing → the Racial and Religious Hatred Bill defeat;
Rangila Rasul → Section 295A). The owner chose one more run with the fixes before switching routes.

**What changes (and nothing else).**
1. **Mark classes:** the P279* closure under both "law" (Q7748) and "legislation" (Q49371), floor 5 articles, list of
   200; plus the P31 classes of the five recall marks, resolved at run time. The classes are added, never the items.
2. **Works:** v1's classes plus written work (Q47461344), documentary series (Q1146215, Q17517379) and TV season; plus
   the P31 classes of the five recall works.
3. **Mark dates:** the infobox's enactment date (royal assent, signed, enacted, passed, effective) first; then an
   enactment-like Wikidata date (P577, P7588, P1619); then inception-like (P571, P585, P580); then the lead's year.
4. **Causal lexicon:** v1's list plus exposé, motivation, galvanized, credited, helped pass, gained popularity,
   testified, impetus, momentum, lobbied, campaign, publicity, public attention, calls for, influenced, pressure on,
   precipitated, hastened, accelerated, brought attention.
5. **Flags:** `news` (daily news programs and reference works cited as sources: News, Breakfast, Today, Tonight,
   Halsbury, Gazette, Hansard, encyclopedias) and `reversed` (the law acted on the work: banned, pulled, prosecuted,
   charged under, test case, costumes, stopped selling). Flagged pairs stay in the file and leave the top list.

**Unchanged.** Sources, politeness, the recall set, and the success rule: v1.1 passes if (a) at least 3 of the 5
recall pairs appear with causal language in the right order and (b) at least 5 further time-ordered causal pairs are
new to the project. Pass → blind owner round (≤15 names) → maps. Fail → the Wikipedia route is dropped for the text
route (`mark_text_v1.md`), which runs in parallel either way.

**Output.** `ripples/docs/results/mark_first_v1_1.json` (fresh state; v1's file is kept as the record of v1).

## Addendum, before the second v1.1 attempt (Oct 3, 07:50 UTC)

The first v1.1 attempt (run 37101630919, 93 minutes) produced a thinner result than v1 and its file was lost to a
workflow bug (the commit step added v1's filename). Its log shows why it was thin: Wikidata's SPARQL endpoint answered
500/504 to a third of the queries. Stage 0 returned nothing; the class-closure query failed, leaving 8 classes and
4,289 laws (v1 had 13,374); 20 of 57 works year-chunks failed, among them the 1900s (*The Jungle*) and 2020 (*Tiger
King*). Recall 1 of 5 again, for reasons of reachability rather than method. Two recall titles also redirect: the
Offences Act to "British Post Office scandal", the Big Cat Act to "Lacey Act of 1900", which pulled "political scandal"
and "miscarriage of justice" into the mark classes.

**Reliability and scoping fixes, nothing else:**
1. Every SPARQL query is tried up to three times (10 s, then 30 s between attempts).
2. Works are queried per year chunk in two groups (screen and other works; written works on their own); a failed
   multi-year chunk is split into single years; failures are listed in the file.
3. The mark classes can never fall below v1's 69 (read from `mark_first_v1.json`); the closure query adds to them.
4. Recall-mark classes are added only when law-like (act, law, statute, legislation, bill, regulation, order, decree,
   ordinance, directive, code, treaty, amendment).
5. Recall matching accepts the article that holds the law: "Lacey Act of 1900" for the Big Cat Public Safety Act, and
   the Compensation Act 2024 beside the Offences Act (the Offences Act has no article of its own, so this pair is
   structurally out of reach of a Wikipedia route; the denominator stays 5).

The success rule is unchanged.

## Result of the second attempt (Oct 3, 12:10 UTC; run 37107094668, 270 minutes, no failed chunks)

13,371 marks (69 classes), 289,960 works (20 classes), 13,976 pairs, 1,205 with a sentence, 3,842 time-ordered, 2,498
flagged news, 36 reversed, 46 ordered with causal language. **Recall 2 of 5 strict** (WarGames → CFAA; The Jungle →
Pure Food and Drug Act and Federal Meat Inspection Act, now caught by "exposés"). Tiger King, Mr Bates and Unsafe at
Any Speed are still missed: the first two have no article of their own to carry the link, the third's Act article does
not link the book. **Rule (a) fails** (2 < 3); **rule (b) passes** with new time-ordered causal pairs beyond v1's six:
JFK (1991 film) → President John F. Kennedy Assassination Records Collection Act of 1992 (the review board "partially
credited" the film); Silent Spring → National Environmental Policy Act; A Nation of Immigrants → Hart-Celler Act; Holy
Deadlock → Matrimonial Causes Act 1937; The Descent of Man → the Butler Act (a law against a book's idea; direction to
be judged by hand); The Caine Mutiny → the Twenty-fifth Amendment (cited in the disability debate; weak).

**Decision.** By the letter the Wikipedia route is dropped as the primary discovery route; the records route
(`mark_text_v1_2.md`) passed its rule the same morning and becomes primary. The mark-first pairs file stays as a
secondary source for maps: its hits with causal language are read by hand, never re-run as is.
