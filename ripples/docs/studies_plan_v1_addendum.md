# Addendum: supplemental round (not pre-registered)

**Written:** 10/08/2026 09:01 PM PDT, after the main harvest, screening and top-30 verification.
**Why:** OpenAlex returned 429 at query 98 of 101 and is stopped for the day. Several frozen families returned no qualifying paper from OpenAlex (F13 Inconvenient Truth, F14 CSI, F15 Scully, F23 Jamie Oliver, F26 Queen's Gambit, F27 Top Gun, F28 baby names, F38 Marie Kondo, F40 medical TV drama, F52 Taylor Swift). This round re-asks those families through Crossref (backup source named in the plan) and adds two PubMed queries for TV storylines.
**Rule:** finds from this round are reported separately and do not count toward the pre-registered bars. Same inclusion rule, extraction, ranking and verification as plan.md.

Crossref (query.bibliographic, rows 10):
1. Al Gore effect An Inconvenient Truth voluntary carbon offsets
2. healthy school meals educational outcomes Jamie Oliver
3. CSI effect forensic science enrollment
4. Game of Thrones baby names
5. Queen's Gambit chess
6. Top Gun Navy recruitment film
7. Marie Kondo decluttering donations
8. Taylor Swift voter registration
9. Super Size Me McDonald's
10. Scully effect X-Files women science
11. Jaws film shark
12. Grey's Anatomy organ donor registration

PubMed (retmax 40):
P1. (storyline[tiab] OR "soap opera"[tiab] OR "television drama"[tiab]) AND (overdose[tiab] OR poisoning[tiab] OR screening[tiab] OR testing[tiab] OR calls[tiab])
P2. (film[tiab] OR movie[tiab] OR documentary[tiab] OR "television series"[tiab]) AND ("interrupted time series"[tiab] OR "natural experiment"[tiab]) AND (sales[tiab] OR prescriptions[tiab] OR admissions[tiab] OR purchases[tiab] OR visits[tiab])
