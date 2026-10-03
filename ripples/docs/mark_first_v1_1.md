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
