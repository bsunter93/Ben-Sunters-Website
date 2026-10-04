# Discovery, corpus 1: Wikipedia as a cited-cause record (Oct 4, 2026)

The first result under `discovery_plan_v2.md`. The question: can the engine produce stone → lasting-mark pairs from
Wikipedia's own text, graded honestly, at a rate where a person curates rather than writes? Registered benchmark:
recall against the catalog's marks, a blind hand screen for precision, decoy stones for the false-discovery rate, and
"reliable" meaning at least 7 of 10 engine pairs survive the screen at a decoy rate under 1 in 10, on held-out stones.

Everything ran from a laptop against the Wikipedia API under the honest user agent, one request a second, with a stop
on any 4xx/5xx (none from Wikipedia). Scripts: `legacy.py`, `legacy2.py`, `hop3.py`, `order.py`, `heldout.py`,
`heldout_fwd.py` in the session scratchpad, to be moved under `lab/` with the next pass.

## The two readings

1. **Forward: the stone's own article.** Every section except plot, cast, production and the like; every sentence that
   is mark-shaped (act, law, agency, founded, banned, regulation, policy …); a causal connective (led to, prompted, in
   response to, following, named after …) raises its score.
2. **Reverse: what links here.** Articles that link to the stone and carry a legal or institutional title (Act, Law,
   Regulation, Commission, Agency, Authority, Treaty …; first names like "Bill" and awards excluded), read for a
   sentence that names the stone with a causal connective. Then the ordering rule: the mark is dated from its title's
   year, its infobox (enacted, royal assent, formed, established …) or the first year in its lead, and a mark dated
   before the stone is busted.

## Recall against the catalog (51 chains with a mark, 103 marks; 43 stones and 91 marks are a work or an event)

| Reading | Marks found | Share |
|---|---|---|
| Strict first pass (legacy-type headings only, connective required) | 27 of 91 | 30% |
| Forward, whole article minus plot and production | 50 of 91 | 55% |
| Reverse hop alone | 33 of 91 | 36% |
| **Either** | **56 of 91** | **62%** |

22 of the 43 stones had every mark found; 16 had none. The misses are mostly marks that neither article names (Quincy
→ "orphan drugs approved", Sputnik → ARPANET, Tylenol → the FDA packaging rule) or whose law has no article of its own
(the Sentience Act 2022, the Sexual Offences Act 1967 behind a disambiguation page), the ceiling the brief's learning
"a Wikipedia route has a structural ceiling" already named.

## Precision on the catalog's stones (hand screen by the builder, Oct 4)

**Forward reading, loose rule** (any causal mark-shaped sentence): a random 50 of 224 sentences. 13 state a real
lasting mark that followed the stone (26%), 6 of them non-obvious (60 Minutes → the EPA's Alar ban; Cathy Come Home →
the charity Crisis; 60 Minutes' McVeigh interview → the Special Confinement Unit media policy; Dobbs → Alabama's IVF
law; Flint → BlueConduit; the Triangle fire → the American Society of Safety Professionals). 17 are true but not a mark
or not enacted; 20 are wrong, 5 of those the wrong direction (the ordering rule catches them) and 5 parse junk or a bad
stone article.

**Reverse hop, strict rule, after the ordering rule:** 63 pairs on 25 stones; 33 busted as predecessors (the Pure Food
and Drug Act before Prohibition; Bayh–Dole before the anthrax letters; the Data Protection Directive before the GDPR),
3 undated, **27 in order, 23 unique**. Screen of the 23: **14 real cited marks** (the STOCK Act, the Racial and
Religious Hatred Act 2006, NEPA, the NDEA, the ATSDR under CERCLA, OPA 90 and its Commission, New Jersey's Anti-Bullying
Bill of Rights, the Reconstruction Agency, the NAIIC, Japan's Nuclear Regulation Authority and Korea's Nuclear Safety
and Security Commission after Fukushima, the Lead and Copper Rule revisions after Flint, the Patriot Act after the
anthrax letters), 1 true with a junk sentence, 5 context hops (Sputnik → the Test Ban Treaty via PSAC; Sputnik → ARPA-H
via ARPA), 3 wrong. **61% clean, 13% wrong.** Under the 70% bar. The five context hops share one shape: the causal
sentence is about something else in the mark's article. A refinement fixed after this screen and disclosed as such:
the sentence must also name the mark itself.

## The false-discovery rate

50 decoy stones (random American films of 2015 and 2007 and television debuts of 2012, from category searches):
the loose forward rule yields a candidate for **15 of 50**; the strict reverse rule yields **0 of 50**. The decoys are
less linked than the catalog's stones (a median of about 250 backlinks against 500 or more), so the strict rate is a
lower bound on what famous-but-markless stones would produce.

## Held-out stones (20 the catalog never touched)

Blackfish, Super Size Me, An Inconvenient Truth, The Day After, Jaws, Roots, Erin Brockovich, Spotlight, 13 Reasons
Why, Making a Murderer, The Social Dilemma, Hurricane Katrina, Deepwater Horizon, Sandy Hook, Chernobyl (miniseries),
Fast Food Nation, Blood Diamond, The China Syndrome, Cosmos, Philadelphia. Stone years given by hand.

**Reverse hop with the refined rule:** 8 pairs, 6 busted as predecessors, **2 in order, both Deepwater Horizon**
(the Bureau of Safety and Environmental Enforcement, 2011; the National Commission, 2010), both real, both obvious.
**Zero for any film or documentary.** A law rarely has its own article that links back to the film; the reverse hop
is an events-and-disasters instrument.

**Forward reading on the same twenty:** see the table below (filled from `heldout_fwd.py`).

| | Count |
|---|---|
| Mark-shaped sentences across the twenty | 208 |
| With a causal connective | 50 |
| In order by the years in the sentence | 47 |
| **Real lasting marks on the blind screen** | **12 (26%)** |
| Of which non-obvious | 5 |

The twelve: the Climate Reality Project and the Dimmock ruling after An Inconvenient Truth; the INF Treaty after The
Day After (reported, by Reagan's own diary); the GuLF Study, Executive Order 13547 creating the National Ocean Council,
the National Commission and BP's federal contracting ban after Deepwater Horizon; Connecticut's Freedom of Information
Act change, the NY SAFE Act, Connecticut's April 2013 gun law with the first dangerous-weapon offender registry, and the
memorial after Sandy Hook. Blackfish's two California and New York orca bills appear as introduced, not enacted; the
2016 Orca Protection Act is not in the article's sentence. Hurricane Katrina's twelve causal sentences are operational
response (shelters, task forces), which the filter cannot yet tell from a lasting mark. The screen is
`docs/results/discovery_corpus1_screen.json`; the sentences are `docs/results/heldout_fwd.json`.

## Corpus 2, 4 and 6 probes, same day

- **Namesake statutes (corpus 2).** "List of laws named after people" turned out to be Amdahl's law and Sturgeon's law;
  the legislation list plus the US, UK, Brazil and Canada sections of the other gives 93 statutes, 80 with an article.
  The lead names its cause with a connective in 29 (36%); about 20 of those are event-named (Clare's Law, Lucy's Law,
  the Adam Walsh Act, Martyn's Law, Emily's Law, the Dima Yakovlev Law, the Maria da Penha Law), the rest are named for
  their sponsor (the Hatch Act). A small, clean, fully dated class.
- **Federal Register (corpus 4).** The documented API answers exact-phrase searches: Dobbs 26 documents, Winter Storm
  Uri 19, Love Canal 15, Silent Spring 13, GDPR 40, the Exxon Valdez 253; common words (Flint, Serial, Prohibition) are
  useless without a disambiguating phrase. The first full-text fetch of an old document's body returned 404, which under
  the rules stopped that host for the day before any causal sentence was read.
- **EDGAR full-text search (corpus 6).** 403 on the first request under the project's user agent with a contact
  address appended. Stopped for the day; the SEC's declared-agent rule needs reading before a second attempt, from a
  workflow, not a laptop.

## Verdict against the bar

**Not met tonight, and closer than the morning.** The bar was 7 of 10 engine pairs surviving a blind screen at a decoy
rate under 1 in 10, on held-out stones.

- The strict reverse rule meets the decoy half (0 of 50) and reaches 61% clean on the catalog, with 2 of 2 on held-out
  events; it finds nothing for films and documentaries, because their laws rarely have an article of their own.
- The forward reading reaches 62% recall with the reverse hop and 26% precision as a candidate generator, on the
  catalog and on held-out stones alike. One sentence in four is a lasting mark a person would keep; the rest is
  context the person discards in seconds. That is "curate from candidates", not "curate instead of write", and it
  already produced eleven marks the catalog did not have.
- The ordering rule, dated from title and infobox, busted 33 of 63 reverse pairs and 3 of 50 forward sentences with
  no human, which is the part of the method that transfers to every other corpus.

The next lever, fixed now for v1.1 and not applied to any result above: a forward sentence counts only if it names an
enacted or established thing (passed, enacted, signed, established, founded, created, ruled, banned) with a year at or
after the stone, and the thing has an article or a statute cite; on the two screens that filter keeps 10 of the 13 and
11 of the 12 marks and drops most of the 37 context sentences. Builder's estimate after tonight: about 50% that within
a month the engine produces lasting-mark chains at a curate-only rate for events and disasters, about 35% for cultural
works, where the law is named in the work's article or nowhere free.

## Learnings

- **Consequence lives in records that name their cause, and Wikipedia is one.** The forward reading of a stone's own
  article recovers over half the catalog's marks, and the hand screen found six non-obvious marks the catalog did not
  have, in 50 random sentences.
- **The ordering rule earns its keep immediately.** 33 of 63 reverse-hop pairs were predecessors (the thing the stone
  later changed, not the thing it caused), and dating from the title and the infobox busted them without a human.
- **The reverse hop is a disaster-and-event instrument, not a culture instrument.** Laws that follow films seldom have
  their own article; the film's article is where they are named.
- **Dating by the first year in a lead is wrong for Acts whose lead recounts their history** (the Racial and Religious
  Hatred Act 2006 read as 2001); the title year and the infobox come first.
- **Decoys must match the stone's fame.** Obscure films give a lower bound; the next run needs famous films without
  marks (box-office lists) as decoys.
