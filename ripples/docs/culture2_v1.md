# Culture discovery v2: results

Plan: `docs/culture2_plan_v1.md` (registered in 716d20a before any search; addendum 1 in 2f8b5d7 added a backlink
generator after seeing G1 to G3's recall, labeled not blind).

## Against the registered bar

| Part | Bar | Result |
|---|---|---|
| Recall of the 25 known ripples (G1 to G3) | at least 10 | **6** (strict; 7 counting a different Child's Play 3 mark): Mortal Kombat to the ESRB, Star Trek to the Enterprise, the Pokemon episode to flashing-image guidelines, quidditch, Jurassic Park to the Raptors, Dear Zachary. **Missed** |
| Good rate (surprising and believable, simulated panel) | at least 25% | **19.8%** (24 of 121), against 12% for the engine's earlier marks. **Missed** |
| New good cultural ripples | at least 15 | **24. Met** |
| Planted controls | below the bar | obvious pairs surprise index 1.03; fabricated pairs believable 1.54. **Met** |

The yield nearly doubled by aiming at one pattern (an institution reacting to culture). Recall failed because the link
is often told in the institution's own article (Smokey Bear, Kmart, SeaWorld, Keiko, the Hobbit law), which the fixed
phrases did not match and the forward reading never opened; G4 (backlinks) was added for that.

## What shipped (PR #130)

33 stones and 35 marks, each read against its live Wikipedia source (38 of 39 selected sentences matched the live text
exactly; Mortal Kombat's ESRB link is quoted from the ESRB article instead). Dropped at the read: a court injunction about
a book itself, a study whose record date is not the outcome's date (Sesame Street), a Comics Code revision whose order
against the comic could not be confirmed, a mark with no dated record (the Pokemon guidelines), bans of a work itself,
and a forum rule. Panel picks and editor's picks are both in; the panel's strict surprise index rates famous ripples low
because its raters already know them.

## Generators

| | Read | Kept after a strict read |
|---|---|---|
| G1 reverse phrases | 168 queries, 8,614 hits | 53 |
| G2 impact sections | 1,945 works, 546 sentences | 44 (25 from the registered lexicon; the rest from a mid-run expansion, labeled by tier) |
| G3 effects articles | 745 articles, 1,938 sentences | 29 |

## Limits

- The panel is simulated (five language-model raters, one model family); real raters replace it after launch.
- One reader made the strict call on every kept sentence.
- G2's lexicon expansion and G4's design came after seeing early results; both are labeled.

## G4 (backlinks, addendum 1; not blind)

702 works, 72,643 unique backlink pages, 7,989 typed as institutions, 767 pairs read, 40 kept. Simulated panel on the 40
(fresh run, same controls): obvious pairs surprise index 1.05, fabricated pairs believable 1.52 (valid); **good rate 27.5%
(11 of 40)**, above the registered 25%, but G4 was designed after seeing G1 to G3, so this is not counted toward the bar.
Recall adds Bambi to Smokey Bear: 7 of 25 overall with G4 (6 blind). Across all four generators: 35 good of 161 (21.7%).

PR #133 shipped ten of G4's pairs, each matched word for word against its live source: Bambi to Smokey Bear, Tamagotchi
to the Sega and Bandai merger called off, Titanic to Carnival buying Cunard ("in part"), Abbey Road to the studio's name,
The Dark Side of the Moon to the Canada Cup trophy, Angry Birds to NASA's Mighty Eagle lander, Brave New World to the
Brave New Workshop, Nineteen Eighty-Four to the Big Brother Awards, Born This Way to its foundation, Braveheart to the
Falkirk Center ("in part"). Left out: bans of a work itself, undated namings (the Jungle Book's Cub Scout titles,
Festivus, Lulbegrud Creek), statues and memorials of a work, and a 2025 political controversy that is not a work.
