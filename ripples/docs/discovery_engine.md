# Ripple Map discovery engine: direction and research program (owner direction D-26, 2026-09-27)

This is the governing direction. Where it conflicts with older docs, this wins.

## Thesis

**What did that thing everyone remembers change?**

- The stone is a memorable cultural event: a movie, show, book, song, celebrity moment, viral phenomenon or movement.
- The landing spot can be anything measurable: names, searches, reading, buying, talk, health and social behavior,
  work and money, legislation.
- The canonical ripple: *Frozen → Elsa as a baby name.* The user should think "wait, Frozen changed THAT?", then open
  the evidence and believe it.

Disasters and economic shocks stay only as **methodological proving grounds**, secondary content and a source of extra
discoveries. They are not the product's identity. This is one product, not seven: fingerprints, anomalies, synthetic
control, networks and the rest are competing methods inside one engine, each answering "where should we look for the
ripple?"

**North star:** a machine that repeatedly finds relationships a smart human would never have thought to test, then
proves to that same human that the relationship isn't an artifact of the search.

- Discovery (the weak half today) may be creative.
- Verification (the strong half today) stays conservative.

## Architecture

```
DISCOVERY LAYER (creative; competing methods)            VERIFICATION LAYER (conservative; unchanged)
  D1 event fingerprints      ┐                            preregister → placebos → decoys → multiple-testing
  D2 outcome-first anomalies ├→ candidate ripples  ──→    correction → held-out confirmation → replication
  D3 exposure gradients      │   (ranked, few)             → evidence ladder
  D4 ghost (counterfactual)  ┘
     events
```

- **D1 Event fingerprints.** Represent each event by its response across all outcomes (names, pageviews, search, …),
  measured against its ghosts. Compare fingerprints across events to find recurring ripple patterns, unusual outcome
  combinations, and outcomes that respond to a whole class of events.
- **D2 Outcome-first.** Start from unusual population-level movements, then look for memorable events nearby in time
  that could explain them. The machine searches backwards from anomalies humans would never connect to the event.
- **D3 Exposure gradients.** Did places more exposed to the event move more? Exposure must be fixed *before* looking
  at the outcome. Candidate measures:
  - pre-event search or news interest by state
  - release or distribution intensity
  - audience concentration
  - demographic composition
- **D4 Ghost events.** For each event, a set of comparable events: same type, same period, similar prominence. The
  target is interesting only when it exceeds the empirical distribution of its ghosts. This is the product's "ghost
  stone".

**Surprise** is not a p-value. "Taylor Swift → Taylor Swift searches" is significant and worthless.
- Evidence is scored statistically.
- Surprise is an editorial filter, never a fake-precision score. As a mechanical first pass, direct echoes (the title's
  own article, cast, author, soundtrack) are excluded, and a human-surprise check is applied before publishing.

**Evidence ladder** (each rung is one plain sentence in the product):
1. **Timing.** Did the outcome move after the event?
2. **Comparison.** Did it move more than the ghosts?
3. **Exposure.** Did more-exposed places move more?
4. **Replication.** Does it hold in another dataset, geography, event or estimator?
5. **Held-out confirmation.** Does it hold in data not used to discover it?
6. **Caveat.** It was not necessarily the only cause.

## Research program (the only three questions that matter now)

| # | question | how it is answered | status |
|---|---|---|---|
| Q1 | Can the system reliably rediscover known cultural ripples? | E9 phase 1: Queen's Gambit → Chess, Stranger Things → Kate Bush, Game of Thrones → Arya, Frozen → Elsa, plus 200 fake events | **passed 2026-09-28 (ledger 1282)**: 4/4 known ripples recovered, 2/200 fake events passed (1%) |
| Q2 | Can candidate generation improve without more false discoveries? | **Cultural lab**: the Ripple Lab idea applied to cultural data. Fake events on real outcome series, planted responses, and D1–D4 compared head to head on recall of planted ripples at a fixed false-discovery rate. The disaster lab (running now) is the proving ground for the shared machinery. | disaster lab running; cultural lab next |
| Q3 | Can an unknown discovery survive held-out confirmation? | The best Q2 architecture is frozen in the ledger, then run on a catalog of about 30–100 remembered events with ghosts, with held-out confirmation | after Q1 + Q2 |

The single benchmark: **how often the engine produces a relationship that is both genuinely surprising and
independently defensible.** Not the number of datasets, hypotheses or significant results.

## Data: what we have, what's reachable, and the gaps

| need | source | status |
|---|---|---|
| Event catalog with dates, type and prominence (for ghosts) | Wikidata SPARQL (films, TV series, books, songs, albums; sitelink count as prominence) | reachable from the database, keyless; to build |
| Outcome: what people read | Wikipedia pageviews (daily, per article, 2015+; BigQuery for bulk) | have (13 articles); bulk via the existing BigQuery workflow |
| Outcome: what people name their children, **by state** | SSA names (national + state) via BigQuery `usa_names` | workflow merged; needs one run |
| Outcome: what people talk about, **by place** | GDELT news coverage (BigQuery, keyless; also a geographic exposure measure) | reachable via BigQuery |
| Exposure by country (streaming) | Netflix Top 10 by country (public download, 2021+) | timed out from the database; try via GitHub Actions |
| Exposure by metro area (search) | Google Trends (official API, alpha) | applied 2026-09-28, awaiting access |
| Books and bestseller ghosts | NYT Books API (bestseller lists back to 2008) | **gap: free key** |
| Outcome: what the news covered, by topic (D2 spikes) | NYT Archive API: every article's index tags per month, 1851+; kept as daily counts per tag, no text (`ripples/lab/nyt_archive.py`) | built; waits for GitHub secret `NYT_API_KEY` (same key as Books) |
| Film and TV catalog with release dates, genres, popularity | TMDB API | **gap: free key** (Wikidata covers most of it) |
| Legislation outcomes | Open States or LegiScan APIs | **gap: free key** |
| What people buy | — | **gap: no good free source**; BLS categories are too coarse |

## Where the owner can help

1. **Google Trends API (alpha).** Google has announced an official Trends API for approved testers (check that it is still open). State-level search interest
   is the best exposure measure for D3 and the most natural outcome for "what people search". Apply with the Google
   account that owns the `ripple-509716` Cloud project.
   *Status 2026-09-28: owner applied; awaiting access. When granted, store the credential as the GitHub secret
   `GOOGLE_TRENDS_KEY`; first pull = metro-area (DMA) interest around each catalog event and its ghosts.*
2. **NYT API key** (developer.nytimes.com, free; enable Archive, Books, Article Search and Most Popular on it; add it as the GitHub secret `NYT_API_KEY`). Archive gives daily news counts per topic tag back to 1851 for spike detection. Weekly bestseller lists since 2008 give the book catalog and
   ready-made ghosts (other #1 bestsellers the same year), which the Fifty Shades question needs.
3. **TMDB API key** (themoviedb.org, free with attribution). Richer film and TV release dates and popularity for ghost
   matching. Optional, since Wikidata covers most of this.
4. **Open States API key** (openstates.org, free). State legislation by topic and date, for the "legislation" landing
   spot.
5. ~~Run the E9 baby-names workflow~~ (done 2026-09-28).
6. **Editorial surprise check.** Before anything is published, a human (you) answers: "Would you have thought to test
   this?" That is the product's surprise filter, and it can't be automated honestly.
7. **A starter list of ~30 remembered events** you'd most want answered. It seeds Q3 and keeps the catalog anchored
   in what people actually remember. The machine will propose ghosts for each.
