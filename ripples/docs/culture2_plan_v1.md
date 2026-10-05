# Culture discovery v2: plan (registered before any search)

Registered Oct 5, 2026 (evening, US), before any generator ran.

## Why

The surprise panel v1 (simulated raters, `docs/panel_v1.md`) found that surprise concentrates in one pattern: an
institution reacting to a piece of culture (the NSA banning Furbies, Iran banning Zumba, a parole rule for Pokemon Go,
an NBA team named after Jurassic Park). Disasters followed by their own law are believable and never surprising. This run
aims the engine at that pattern.

## Generators (three, in parallel)

- **G1 reverse:** Wikipedia search for institution, law, rule, standard, organization and policy articles whose text
  names a cultural work as the reason ("in response to the film", "named after the series", "after the episode", "the
  game prompted", and similar phrases fixed in the G1 script before it runs).
- **G2 forward:** the impact, legacy, influence, cultural impact and controversy sections of the most-linked cultural
  works on Wikidata (films, TV series, video games, songs and albums, books, toys; ranked by sitelinks), read for
  sentences that pair the work with an institutional verb (banned, prohibited, founded, established, created, renamed,
  named after, amended, passed, adopted, ruled, released, ended) and a lasting-mark object (law, rule, agency,
  organization, standard, guideline, league or team, policy, court ruling).
- **G3 effects:** Wikipedia articles about named media effects ("X effect") and lists of works tied to legislation or
  policy, read the same way.

Every candidate carries: the stone and its date, the mark and its date (from the mark's own record), the sentence, the
article and section, and the ordering check. The written definition of a lasting mark governs (owner, Oct 5): a law, an
institution, infrastructure, jobs, public health, or a durable change in behavior. Sales spikes, attention and tourism
are intermediate steps, not marks.

## Recall test (frozen now; the generators do not see this list)

Known, documented cultural ripples the engine should find on its own:

1. Mortal Kombat and Night Trap, the 1993 Senate hearings, the ESRB (1994)
2. Prince's "Darling Nikki", the PMRC, the Parental Advisory label (1985)
3. Bambi, the Forest Service fire-prevention campaign, Smokey Bear (1944)
4. Star Trek, the fan letter campaign, the Space Shuttle Enterprise named (1976)
5. WarGames, NSDD-145, the first presidential directive on computer security (1984)
6. The Hobbit's production, New Zealand's Employment Relations (Film Production Work) Amendment Act 2010
7. Pokemon's "Electric Soldier Porygon" episode, Japanese broadcasters' flashing-image guidelines (1998)
8. Harry Potter, the sport of quidditch and its governing bodies
9. Jurassic Park, the Toronto Raptors' name (1995)
10. Bowling for Columbine, Kmart stops selling handgun ammunition (2001)
11. Blackfish, SeaWorld ends orca breeding and the California Orca Protection Act (2016)
12. Kony 2012, the Department of State Rewards Program Update and Technical Corrections Act of 2012
13. Law & Order: Special Victims Unit, the Joyful Heart Foundation, rape kit backlog laws
14. The Thin Blue Line, Randall Dale Adams released (1989)
15. Blue Planet II, England's ban on plastic straws, stirrers and cotton buds (2020)
16. Sideways, the fall in Merlot and rise in Pinot Noir sales
17. Free Willy, Keiko returned to Iceland (1998)
18. Child's Play 3, the 1994 video-classification amendment (a disputed premise)
19. Grand Theft Auto: San Andreas "Hot Coffee", the FTC consent order (2006)
20. Super Size Me, McDonald's drops the Super Size option (2004, disputed)
21. Paradise Lost, the West Memphis Three released (2011)
22. The Jinx, Robert Durst arrested (2015)
23. 13 Reasons Why, Netflix removes the suicide scene (2019)
24. Dear Zachary, Canada's Bill C-464
25. Cathy Come Home, the charity Crisis founded (1967)

## Screen

1. Strict read of every candidate sentence: is it a lasting mark under the definition, is the work given as a cause (not
   an aside), is the order right. Dates resolved from the mark's own record.
2. Simulated surprise panel (five raters, the v1 protocol, fresh planted obvious and fabricated controls in every batch).
   The batch counts only if the controls behave (obvious mean surprise index at most 2.5; fabricated mean believable at
   most 2.5).
3. Good = surprise index at least 3.5 and believable at least 3.5 and passes the strict read.

## Bar

- Recall: at least 10 of the 25 known ripples found by a generator.
- Yield: the good rate among strictly-read candidates at least 25% (panel v1 engine rate: 12%), and at least 15 new good
  cultural ripples.
- Decoys: the fabricated controls stay below the bar.

## Product

Survivors join Engine leads as data (the existing `wiki` kind), graded reported (or disputed where the record disputes
it), each with its sentence and source; no new interface. The kind's description says how they were found and checked,
and does not claim a person screened them.
