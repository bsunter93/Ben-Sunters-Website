# Mark-first search v1: from lasting marks upstream to the events that caused them (explore stage)

*Written Oct 3, 2026, before the run. Explore stage under explore-then-confirm (ledger 1466): nothing from this run is
shown as measured.*

**Why.** The owner's rule (D-30): a ripple's payoff is a lasting mark, such as a law, a regulation, an institution,
infrastructure, jobs or public health. Attention data never finds marks (Clickstream, editor-trail one hops and
attention second hops all returned curiosity). So this run inverts the engine: start from records of marks and swim
upstream to the cultural events they cite. A law that names its trigger in its own article is the strongest kind of
reported link.

**Sources (free, no keys).**
1. **Wikidata causal statements.** Items whose "has cause" (P828), "has immediate cause" (P1478) or "has contributing
   factor" (P1479) is a creative work, plus works with "has effect" (P1542). One query each.
2. **Laws → works, via Wikipedia.** Every law, act, statute, executive order and regulation with an English Wikipedia
   article (Wikidata classes under "law", plus a curated list). For each, the article's links that land on a creative
   work: film, documentary, TV film, TV series, miniseries, TV program, web series, book, novel, video game, internet
   meme or podcast, from a works set built by Wikidata year chunks. For each pair, the sentence of the law's article
   that contains the link and the section it sits in.
3. **Federal Register full text.** Rules, proposed rules and notices mentioning each catalog event by name, and
   generic markers ("Netflix series", "documentary", "viral video", "social media challenge").

**Qualification (automatic, then by hand).**
- **Order:** the work's date must be before the mark's date (Wikidata dates; a year parsed from the article lead as a
  fallback, flagged).
- **Causal language** in the sentence: in response to, following, in the wake of, prompted, inspired, spurred, led to,
  as a result of, outcry, public pressure, named after. Score = count of matches.
- **Section:** a link found under "In popular culture", "Legacy", "Media", "See also" or similar counts the other way
  (the law influenced the work) and is set aside.
- **By hand, afterwards:** is the work the cause or an illustration? Was the bill introduced before the work (the
  Tiger King case)?

**Recall set (fixed before the run).** Five documented work → law pairs that a Wikipedia-based search should find:
1. Mr Bates vs The Post Office → Post Office (Horizon System) Offences Act 2024
2. Tiger King → Big Cat Public Safety Act
3. The Jungle → Pure Food and Drug Act, or Federal Meat Inspection Act
4. Unsafe at Any Speed → National Traffic and Motor Vehicle Safety Act
5. WarGames → Computer Fraud and Abuse Act, or National Security Decision Directive 145

**Success rule.** v1 passes if (a) at least 3 of the 5 recall pairs appear with causal language and the right order,
and (b) at least 5 further time-ordered pairs with causal language are new to this project. If it passes, the new
pairs (15 at most, names only) go to a blind owner round under the owner's rule (at least 5 interesting, non-obvious,
not-searched; at least 1 worth chasing), and survivors become maps with the law as the lasting mark. If it fails, the
Wikipedia route is dropped and the next attempt uses legislative text APIs (Congress.gov, Federal Register, Open
States).

**Politeness.** Honest UA, one request a second to Wikipedia and Wikidata, two seconds between SPARQL queries, stop
on 403/429/503. Results are saved as the run goes and the run resumes from them.

**Known limits.** It finds marks someone documented on Wikipedia; it misses links through redirect titles; songs are
left out of the works set (volume); institutions (charities, agencies, rating boards founded in response) are v2.
