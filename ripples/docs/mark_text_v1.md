# Mark-text search v1: cultural works named inside legal and parliamentary records (explore stage)

*Written Oct 3, 2026, before the run. Explore stage under explore-then-confirm (ledger 1466).*

**Why.** The mark-first search reads Wikipedia's articles about laws. The records themselves say more: explanatory
notes name the drama that prompted a bill, a minister cites the documentary at second reading, a rule's preamble cites
the series that raised the complaints. This run reads those records directly. No keys, except an optional one.

**Sources.**
1. **UK Parliament Hansard API** (spoken contributions, 2010 onward in the API): contributions that use a marker
   phrase; the debate section is the mark when it is a Bill, Act or statutory instrument, otherwise "debate".
2. **legislation.gov.uk** (Atom search feed over legislation and explanatory notes): items matching a marker phrase;
   the explanatory notes' text for up to eight items per phrase.
3. **Federal Register** (rules, proposed rules, notices): full-text search per marker phrase, context from excerpts and,
   for up to twelve documents per phrase, the raw text.
4. **GovInfo** (public laws, bills, Congressional Record, hearings): only if `DATA_GOV_KEY` is set (a free api.data.gov
   key in GitHub secrets). Otherwise logged as skipped.

**Marker phrases (fixed):** Netflix, HBO, ITV drama, BBC drama, television drama, television series, TV series,
docuseries, documentary film, the documentary, miniseries, motion picture, feature film, the novel, best-selling book,
video game, viral video, social media challenge, TikTok, podcast, 60 Minutes, Dateline, Panorama programme, Dispatches
programme, Channel 4 documentary, reality television; plus named works: Super Size Me, Blackfish, Tiger King, Mr Bates,
The Jungle, Silent Spring, Unsafe at Any Speed, WarGames, Cathy Come Home, Thirteen Reasons Why, Squid Game, Stranger
Things, Baby Reindeer, Adolescence.

**Method.** Around each marker (±320 characters) a title is extracted by pattern (quoted titles after series/film/
novel; "the Netflix series X"; "the 1983 film X"). The title is resolved on Wikipedia (search, redirects) to a Wikidata
item whose class names a creative work, with its earliest publication date. The record's date is the mark date; order
is work before record; causal words in the window are counted with the mark-first lexicon.

**Tiers.** `law` (legislation.gov.uk, GovInfo public laws), `rule` (Federal Register rules), `bill`, `bill debate`
(Hansard, section names a Bill or Act), `notice`, `debate`, `record`. Only law, rule, bill and bill debate count below.

**Success rule.** v1 passes if at least 5 time-ordered pairs in the counted tiers resolve to a real work and a named
law, bill or rule, and at least 2 are new to the project. Mr Bates → Post Office (Horizon System) Offences Act 2024 is
the expected positive control (Hansard, March–May 2024). If GovInfo runs, Tiger King → Big Cat Public Safety Act is a
second control (Congressional Record, 2020–2022). Pass → the pairs join the blind round with mark-first's; fail →
the text route needs entity resolution beyond regex (a records assistant), and that is the next design.

**Politeness.** Honest UA, one request a second, stop on 403/429/503, resume from the saved file. A probe step logs
each endpoint's first response so a dead source is visible in the job log.

**Output.** `ripples/docs/results/mark_text_v1.json`. Budget 150 minutes.
