# Multi-hop ripples v1: the plan (registered Oct 4, 2026, before any search)

**The question.** Can the engine compose a stone, an intermediate and a lasting mark into one chain, stone →
intermediate → mark, with each hop graded and in order, and do it without composing chains for stones that never moved
the intermediate?

**Why now.** The engine finds one-hop pairs (stone → mark): the records route (`lab/mark_text.py`, `lab/bill_act.py`)
and Wikipedia read as a cited-cause record (`docs/discovery_corpus1_v1.md`). The vision asks for "the link nobody would
guess", which usually takes two hops. Two things already failed and shape this design (brief, section 3): attention
second hops returned related topics, not outcomes ("curiosity is not consequence, three times over"), and "records beat
attention for lasting marks". So hop 1 may use attention, because it only has to show that the stone moved a specific
thing; hop 2 must be a record that names that thing as a reason for a lasting mark. Attention never reaches the mark.

Nothing below has been run. Before this commit the only network calls were endpoint probes on unrelated pages
(Wikipedia page properties for Euclid and Pythagoras, one pageviews call for Euclid, one Wikidata query for Euclid, the
Hansard API's own documentation, the Bills API's first bill). No stone, candidate or record was queried.

## 1. Stones

**Main set (fixed).** The union of every stone the engine already holds, deduplicated by article:
- `docs/results/stones_all.json`: the catalog's stones that are a work or an event and carry a date;
- `demo/discovered.json`: the fourteen attention-lead stones;
- `demo/discovered_wiki.json`: the 58 stones under Engine leads;
- `lab/discovery/heldout.py`: the twenty held-out stones.

That is 114 articles. Two corrections, made now: the catalog's `chernobyl-zone` stone is the 2019 miniseries but its
article was recorded as "Chernobyl" (the city), so it merges into "Chernobyl (miniseries)"; "Top Gun: Maverick" is on the
famous-decoy list and has no lead with an outcome, so it leaves the main set and stays a decoy. **112 stones.**

**Dates.** The date already recorded in those files. The held-out stones carry only a year: their date is the earliest
Wikidata publication, start or point-in-time date (P577, P580, P585) inside that year, else year precision.

## 2. Stage A: candidate intermediates

**Generation.** The stone's Wikipedia article, read as wikitext: the lead and every section whose heading does not match
the plot, cast and production list in `lab/discovery/legacy2.py` (`SKIP`). Every wikilink there, redirects resolved,
is a candidate. The stone's attention leads in `demo/discovered.json` (for example the Greater Wynnewood Exotic Animal
Park for Tiger King) are added. Candidates keep their order of first appearance; the attention leads go first.

**The specificity filter (Wikidata), all four must hold:**
1. *An instance, not a class.* The item has no "subclass of" (P279) statement. Generic topics are classes: an exotic
   pet, a big cat, chess.
2. *Not a generic kind.* It has an "instance of" (P31), and no P31 label matches:
   `taxon|species|genus|group of organisms|concept|academic discipline|field of study|branch of|occupation|profession|position|
   genre|style|technique|ideology|religion|ethnic group|language|country|sovereign state|city|town|village|human settlement|
   municipality|county|state of|province|region|continent|island|river|lake|sea|ocean|mountain|administrative|territory|
   Wikimedia|disambiguation|list|film|television series|TV series|miniseries|episode|season|song|single|album|book|novel|
   literary work|written work|video game|podcast|fictional|character|work of art|painting|chemical|compound|disease|food|
   dish|sandwich|beverage|drink|cuisine|sport|game|holiday|calendar|year|decade|century|color|symbol|award|prize`.
   People, companies, charities, agencies, commissions, inquiries, zoos, prisons, plants, scandals, cases, trials,
   campaigns and named events pass.
3. *Not a direct echo of the stone.* Not the stone itself; not a value of the stone's director, screenwriter, producer,
   composer, author, creator, production company, original broadcaster, distributor, editor, cinematographer, presenter,
   performer, series, part-of or has-part (P57, P58, P162, P86, P50, P170, P272, P449, P750, P1040, P344, P371, P175,
   P179, P361, P527); nobody whose occupation (P106) is an acting one (Q33999, Q10800557, Q10798782, Q2259451, Q2405480);
   and not a title that contains, or is contained in, the stone's title (parentheticals dropped), so "Silicon Valley
   Bank" is not an intermediate of the bank's collapse. Real people a documentary is about are not echoes.
4. *A name that can be searched.* The title less any parenthetical, or one of its redirects, passes the name guard: at
   least two words, or one word of five letters or more that is not in the system word list (`/usr/share/dict/words`).
   "Crisis" and "Horizon" fail; "Fujitsu", "SeaWorld" and "Paula Vennells" pass. A candidate with no guarded name can
   still be matched by wikilink in Wikipedia text, but never searched in Hansard or the Record.

## 3. Stage B: hop 1, stone → intermediate

- **Measured.** The checker's own attention test (`lab/chain_check.py`, `wiki_test`) on the candidate's article, with
  the stone's date as the reference and a 45-day lag: daily views, a sustained onset, and the empirical p against
  placebo windows every 14th day of the page's own history. A pass needs p ≤ .05 with at least 20 placebo windows and an
  onset on or after the stone's date. An onset before the stone is **busted** by the ordering rule. Runs only for stones
  dated after Aug 1, 2015 and at least 45 days before today, on at most **20 candidates per stone**, in candidate order.
  An article created at the stone has no baseline and is not measured.
- **Reported.** A sentence in the stone's article (the same sections as above) that links the candidate or names it by
  a guarded name, and has a causal word from `mark_first.CAUSAL` (in response to, following, after, prompted, led to,
  outcry, lobbied, campaigned …). A sentence whose years are all earlier than the stone's year is dropped. The step's
  date is the earliest year in the sentence at or after the stone's year (year precision), else the stone's date.
- **To hop 2:** per stone, at most 4 measured candidates (highest ratio first) and at most 3 reported ones (most
  qualifying sentences first, then candidate order).

## 4. Stage C: hop 2, intermediate → lasting mark

Each survivor is searched under its names: the title less any parenthetical and up to two of its shortest redirects,
every one passing the name guard.

- **H1, Hansard (UK Parliament API).** Spoken contributions with each name as an exact phrase, from the hop-1 date to six
  years after, oldest first, at most 200 per name. Kept when the debate section names a Bill, the 440 characters
  around the name score "reason" on `lab/cite_score.py` with that name in place of the work, and the bill resolves to an
  Act through `bill_act.resolve` (the Bills API, then legislation.gov.uk) with Royal Assent on or after the debate.
  The mark is the Act; its date is Royal Assent.
- **H2, the Wikipedia reverse hop.** Articles that link to the intermediate and carry a legal or institutional title
  (`hop3.MARKT`, not `hop3.NOT`), at most 1,000 backlinks read, at most 12 such articles, those whose title year is at or
  after the hop-1 year first, then those with no year in the title. Kept: a sentence in the mark's article that links
  the intermediate (or a redirect to it) or names it by a guarded name, has a causal word from `mark_first.CAUSAL`, and
  names the mark itself (a distinctive word of its title, as in `famous_decoys.py`). The mark is dated as in
  `order.mark_year` (title year, then infobox, then lead) from the text already fetched; an undated mark is dropped.
- **H4, the Congressional Record (GovInfo).** The key lives in Actions secrets, so this runs as a GitHub workflow
  (`.github/workflows/ripples-multihop-gov.yml`), triggered by **one push** carrying the stage-B survivors; no other
  run is triggered. For survivors where the intermediate or the stone is tied to the United States in Wikidata (P27,
  P17, P495, or the country of P159): the first guarded name as an exact phrase in the CREC collection, newest first, 50
  results; items dated on or after the hop-1 date (and after Jan 1, 1995) whose title is bill-shaped (an Act, a bill, an
  H.R. or S. number); at most 5 text fetches per name; the window scores "reason"; the title resolves through
  `bill_act.us_resolve` to a public law enacted on or after the item. Four seconds between requests (the key's hourly cap).
- A hop-2 sentence may also name the stone. It is flagged (`names_stone`), not dropped.

**An automated chain** is a stone, a hop-1 pass and a hop-2 pass in order: stone ≤ hop-1 step ≤ record ≤ mark, compared
at the coarser of the two precisions (a year against a day compares years, so equal years pass and are checked by hand).

**Grades.** Hop 1 is measured or reported. Hop 2 is reported: a record making the link, never measured. The chain's
weakest link is therefore reported, and nothing in it is shown as more certain than that.

## 5. Decoys

- **D1, intermediates paired with wrong stones.** For every automated chain, three wrong stones drawn with seed
  20261004 from the main set, excluding the true stone, stones within 60 days of it, stones dated after the mark, and
  stones whose own stage-A candidates include the intermediate. If the true hop 1 was measured, the draw is limited to
  stones the measured test can run on for that article; otherwise any stone. Hop 1 is re-run for the intermediate
  against each wrong stone (measured where it can run, and reported). Hop 2 is the intermediate's own and would pass
  unchanged, so any hop-1 pass is a false chain.
- **D2, famous stones.** The fifty high-grossing films in `lab/discovery/famous_decoys.py`, dated like the held-out
  stones, through stages A to C under identical rules and caps (including the workflow). Any automated chain is a
  false chain.

## 6. Known positives to recover

- **K1.** Mr Bates vs The Post Office (Jan 1, 2024) → Paula Vennells, the British Post Office scandal or Horizon (IT
  system) → the Post Office (Horizon System) Offences Act 2024 (Royal Assent May 24, 2024).
- **K2.** Tiger King (Mar 20, 2020) → Joe Exotic or Carole Baskin → the Big Cat Public Safety Act (signed Dec 20, 2022).

Recovered means an automated chain along that path that survives the hand check.

## 7. The hand check (strict)

Every automated chain from the main set is read by hand, and fails on the first criterion it misses:

1. **The stone is right:** the article and the date.
2. **The intermediate is specific and not an echo:** not the stone's creator, cast, broadcaster, subject-as-title, or
   the stone under another name.
3. **Hop 1 holds.** Measured: the weekly series shows a real sustained rise after the stone, not an artifact (a page
   move, a redirect, an article created then). Reported: the sentence says the stone moved the intermediate, with the
   stone as the cause, dated after it.
4. **Hop 2 holds.** The record names the intermediate, or what happened to it, as a reason for this mark; not an aside,
   not an illustration, not the mark acting on the intermediate, not a predecessor, not a sentence about something
   else in the same document.
5. **The mark is lasting and real:** an enacted law, an established institution, a rule in force. Not a bill that died,
   a hearing, a lawsuit or an announcement.
6. **Order holds** at the precision the sources carry: stone ≤ hop 1 ≤ record ≤ mark.
7. **The hops meet:** the thing the stone moved is the thing the record cites, in the same sense (not a namesake).

## 8. The bar (all three, or the bar fails)

1. **At least 1 of the 2 known positives recovered.**
2. **At least 3 new two-hop chains survive the hand check.** New: not K1 or K2, and not already a catalog chain through
   the same intermediate to the same mark. Reported beside it, outside pass or fail: how many survivors reach a mark the
   repository did not already hold for that stone (catalog chains, `demo/discovered_wiki.json`,
   `docs/results/bill_act_v1.json`).
3. **0 decoys:** no D1 wrong-stone pair passes hop 1, and no D2 famous film yields an automated chain. Decoys are
   counted at the automated stage, before any hand check; what they were is reported either way.

A failed bar is reported as failed, with the diagnosis.

## 9. Output

- `docs/results/multihop_stage1_v1.json`: stones, candidates, the filter's reasons, hop-1 results (main and D2).
- `docs/results/multihop_gov_v1.json`: the workflow's Congressional Record hop 2.
- `docs/results/multihop_raw_v1.json`: every automated chain, the D1 and D2 results, request counts and stops.
- `docs/results/multihop_v1.json`: the chains in a shape the demo can render. For each chain: `stone {title, date}`;
  `steps [{title, date, grade, source_label, source_url, sentence}]` (hop 1 the intermediate, hop 2 the mark);
  `mark {title, date, kind, source_label, source_url}`; `weakest`; `context: ""` (the "It wasn't the only reason"
  note, left blank for a human editor); the hand check's verdict. Chains that fail the check are kept apart with the
  criterion they failed.
- `docs/multihop_v1.md`: the numbers against the bar, the chains, the failures and the limits.

## 10. Politeness and rules

The honest user agent `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`. From the laptop: one process,
one limiter across every host, at most one request a second. A 403, 429 or any 5xx stops that run for the day with no
same-day retry and no change of agent; a 404 (a missing article or series) is a skip. The workflow spaces GovInfo
requests by four seconds and stops on the same codes. Keys stay in Actions secrets and never reach code, logs or
commits. Aggregate data only. Scripts: `lab/discovery/multihop.py` (stages A to D) and
`lab/discovery/multihop_gov.py` (H4).

Any change after this commit is disclosed in `docs/multihop_v1.md` with the reason and the time.
