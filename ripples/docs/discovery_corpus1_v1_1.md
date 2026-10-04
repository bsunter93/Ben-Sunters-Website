# Discovery, corpus 1, v1.1: sixty more stones and the product surface (Oct 4, 2026, evening)

Follows `discovery_corpus1_v1.md`. The owner's direction: complete the discovery work on Oct 4 and build it into the
prototype; ship Monday, Oct 5.

## What changed from v1

- **The enacted-thing filter, fixed before the run:** a forward sentence counts only if it carries a causal connective
  and an enactment word (passed, enacted, signed, established, founded, created, ruled, banned, adopted, formed, set
  up, launched, became law, royal assent, ratified, mandated, required) and no year earlier than the stone.
- **The reverse rule from v1's refinement:** the mark-titled article's sentence must name the stone and a distinctive
  word of the mark's own title; the mark is dated from its title or infobox and busted if it precedes the stone.
- **Sixty new stones** the catalog never touched, chosen before the run: disasters, attacks, scandals, leaks, movements
  and nineteen films, series and books (`lab/discovery/wider.py`).

## The run (`docs/results/wider_v1_1.json`)

| | Candidates | Real marks on the blind screen | Share |
|---|---|---|---|
| Reverse pairs, in order | 15 | 9 (2 more true with a weak sentence) | 60% |
| Forward sentences | 198 | about 70 state a lasting mark that followed | 35% (v1: 26%) |
| Unique marks across the sixty stones | | **51** | |
| Non-obvious among them | | 14 | |

The non-obvious fourteen: Enron → Internal Revenue Code section 409A (2004) and the UK Companies (Audit, Investigations
and Community Enterprise) Act 2004; MeToo → Indonesia's Sexual Violence Crime Act (2022); Bhopal → the International
Medical Commission on Bhopal (1993); Challenger → NASA's Office of Safety, Reliability, and Quality Assurance (1986);
Chernobyl → the Early Notification Convention (1986) and the Joint Convention (1997); the Boston Marathon → One Boston
Day (2015); Oklahoma City → the Victim Allocution Clarification Act (1997); Parkland → Florida's end of the death-penalty
unanimity rule (2023); the Camp Fire → Chico's price-gouging ordinance (2018) and California's AB 1054 wildfire fund
(2019); Love Canal → the Love Canal Area Revitalization Agency (1980); Dear Zachary → Canada's Bill C-464 (2010);
Cambridge Analytica → Social Science One (2018); Flint → the Child Lead Exposure Elimination Commission (2017).

What the filter still lets through: immediate operational response (shelters, task forces, curfews: Hurricane Katrina
and Camp Fire produce a dozen each), proposals and bills that passed one chamber, bans on a film in one country, and
funds that were a company's own relief effort. Films remain thin: of nineteen works, Dear Zachary and Cathy Come Home
produced a mark; Jaws, Bowling for Columbine, Food, Inc., The Thin Blue Line and Kony 2012 produced none the screen kept.
The ordering rule caught Cathy Come Home → Shelter ("by coincidence, a few days after"), which is the kind of sentence
a reader would have believed.

## Into the product

`demo/discovered_wiki.json` now carries **36 stones and 77 marks**, every one hand-screened: the 14 stones and 25 marks
of v1 plus 22 stones and 52 marks from this run. Every date was verified against the mark's article or the stone's
article under the honest user agent (year and month for day- and month-dated marks); 10 marks are held to month or year
precision because the record carries no day. Each stone has an "It wasn't the only reason" line. The kind is `wiki`
(`?w=<slug>`), first under Engine leads, every link reported, none measured.

## Against the bar, after v1.1

Not met as "7 in 10 engine pairs survive the screen" on films; met in spirit for events and disasters: the strict reverse
rule at 60 to 61% clean on two sets, the forward reading at 35% with the filter, and a person keeping one sentence in
three with a glance. The screen of 213 candidates took the builder about forty minutes; writing 51 marks from scratch
would have taken a day and found fewer of the non-obvious ones. Builder's estimate after v1.1: about 55% that a month of
work makes events-and-disasters discovery curate-only at the registered bar; about 35% for cultural works.

## Next

Famous-but-markless decoys (box-office lists); a third filter that drops operational response (shelter, curfew, task
force, perimeter) and one-chamber passage; the namesake-statute class as its own kind; the Federal Register and EDGAR
passes from a workflow; the automated evidence ladder on every pair with an attention series.
