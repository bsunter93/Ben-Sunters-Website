# Discovery, the culture shelf, v1 (Oct 4, 2026, evening)

The owner's ask: "round out our dataset on things that we know will be relevant/recognizable to a very large segment
of populations. how can we inject more pop culture trends or behavioral/cultural trends in general?" Follows
`discovery_corpus1_v1_1.md`.

## The reading

132 recognizable cultural stones chosen before the run (`lab/discovery/culture_stones.py`): the biggest films and series
by decade, best-selling books, number-one songs, toys, games, fads, diets, documentaries. Forward only (the reverse
hop finds nothing for culture, `discovery_corpus1_v1.md`). A sentence counts if it carries a causal connective and
either an enacted-thing word or a **behavior word** (sales, demand, tourism, visitors, recruitment, enrollment,
adoptions, abandonment, popularity, searches, boom, surge, shortage, revival, membership, attendance, subscriptions,
rose, fell, doubled) and no year earlier than the stone (`culture.py`). The behavior lexicon is the change: a culture
stone's lasting mark is what people did, not what a legislature did.

## The result (`docs/results/culture_v1.json`)

| | Count |
|---|---|
| Stones | 132 |
| Stones with nothing kept | 50 |
| Candidate sentences | 234 (148 behavior, 100 law-shaped) |
| Real lasting marks on the blind screen | about 30 (13%) across 22 stones |
| Non-obvious | 9 |

The rate is less than half the events rate (35%), as the held-out set predicted: culture's marks are reported by
journalists in round numbers and often without a date, and half the sentences the lexicon keeps are the stone's own
commercial performance (its sales, its ratings, its sequels), not a change in the world.

The non-obvious nine: Sideways → Merlot sales down 2%, Pinot noir up 16%, with a 2022 Journal of Wine Economics study
behind it; The Great British Bake Off → sharp rises in baking ingredient sales; Furby → banned from NSA property (1999);
Jurassic Park → the Toronto Raptors' name (1995); Blue Planet II → a sudden rise in marine biology applications at
British universities and the lasting turn to plastic pollution; An Inconvenient Truth → carbon-offset purchases up
near the theaters that showed it (a 2011 study); Pokémon Go → New York's parole rule and Iran's ban; Hamilton → the
Hamilton Education Program (2016).

Two honesty results the reading produced on its own:

- **Top Gun → a 500% rise in naval aviator applications** is in the article, with the sentence that its accuracy has
  since been questioned. It is in the product as **Disputed**, the first engine-found busted link, not as a mark.
- **Vietnam's ban of Barbie** is dated July 3, 2023, before the film's release on July 21; the ordering rule busts it
  as a consequence of the film (it was a consequence of the trailer). It is left out.

Also worth recording: Woodstock's "law requiring a permit for any gathering of over 5,000" was passed by Wallkill
before the festival and moved it to Bethel; the filter kept it and the ordering rule dropped it. Finding Nemo's rise
in demand for reef fish is shown beside the 2019 study of Finding Dory that found no rise. 13 Reasons Why's teen
suicide study is shown with the note that later analyses disputed it.

## Into the product

22 culture stones and 25 marks (24 reported, 1 disputed) join `demo/discovered_wiki.json`: **58 stones and 102 marks**
under Engine leads. Every date was verified against the stone's article or the mark's; most culture marks are dated
to the year, because that is how the record states them, and the card says so. Each stone has an "It wasn't the only
reason" line.

## What was left out, and why

Marks whose sentence carried no year and whose mark has no article of its own (Game of Thrones → Dubrovnik's visitor
cap and the husky boom; Bake Off → Women's Institute membership; Peaky Blinders → the names Arthur and Ada; CrossFit →
the HIIT franchises): true in the record, undated by it. The next step is the series that can date them: the ONS and
SSA baby-name files (the checker already runs SSA), national park visitation, and the Official Charts.

## Learnings

- **The lexicon is the lever.** The same reading with a law lexicon found almost nothing for culture; with a behavior
  lexicon it found thirty marks in a hundred and thirty stones.
- **Culture's marks are undated in prose.** Half of what was true could not be dated from the sentence; measurable
  series, not more text, are the way to grade them above reported.
- **The record disputes itself, usefully.** The Top Gun sentence carried its own correction; the engine should keep
  reading for "questioned," "disputed" and "found no" and surface those as Disputed and busted links, which is what
  the product is for.
