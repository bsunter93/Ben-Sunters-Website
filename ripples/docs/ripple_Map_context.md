# Ripple Map: context brief (updated 2026-10-03, evening)

Standalone context for anyone (person or new chat) picking up Ripple Map. It covers the vision, the current status,
what we learned, pitfalls, open gaps and next steps. The operational runbook with exact commands is
`ripples/HANDOFF.md`, and the experiments plan is `ripples/docs/experiments.md`.

- Live site:
  - https://bensunter.com/ripples/demo/: the product prototype, branded **Ripple** since 2026-10-03.
  - https://bensunter.com/ripples/discover/: every test and its evidence.
  - https://bensunter.com/ripples/discover/maps/: 11 generated ripple maps.
  - https://bensunter.com/ripples/pond/: the original explorer, parked.
- Repo: `bsunter93/Ben-Sunters-Website`
- Database: Supabase project `kffkasnzqcddpystszch`, schema `ripples`. The compute tier went from nano to micro on
  2026-09-27.

---

## 1. Vision (owner, verbatim core)

> "What did that thing everyone remembers change?" A ripple's payoff is a lasting mark: "something that leaves a mark,
> has a lasting impact." (owner, Oct 3)

> "The entire point of the app is uncovering hidden impacts from upstream events — regardless of where that impact
> shows up. Attribution and traceability with statistical rigor are key."

- **Obvious links are worthless.** "Storm → energy demand" is not a product. The product is the link nobody would guess.
- **One shock, many outcomes.** A shock is one-to-many, not one-to-one.
- **Resilience is a finding.** A shock that dies out (for example, Florida absorbing a hurricane) is worth showing, but
  only against a counterfactual.
- **Anomaly-first, not list-first.** Start from whatever moved unusually and work backwards to causes.
- **Decade scale.** Compare old shocks' long-run outcomes with recent ones.
- **Audience.** A 12-year-old must get it. Statistics sit behind links, with short plain summaries.
- **Design.** Serious, sleek, not cartoony. The pond must feel like water. Outcomes are not on a perimeter, and rings
  are not always visible.
- **Honesty.** Report blunt results, including "nothing survived".

## 1. Governing direction (D-26, 2026-09-27)

`ripples/docs/discovery_engine.md` is the governing direction and wins over older text below.
- **Thesis:** "What did that thing everyone remembers change?" Memorable cultural stone → surprising, defensible
  landing spot. Frozen → Elsa is the canonical ripple.
- **One engine, not seven products.** A creative discovery layer runs competing methods: D1 event fingerprints, D2
  outcome-first anomalies, D3 exposure gradients, D4 ghost events. A conservative verification layer stays unchanged.
- **Research program:** Q1 rediscover known ripples → Q2 improve candidate generation at a fixed false-discovery rate
  → Q3 an unknown discovery survives held-out confirmation.
- **Benchmark:** how often the engine produces a relationship that is both genuinely surprising and independently
  defensible.
- **Disasters and economic shocks** are proving grounds and secondary content, not the identity.

## 1a. Product thesis (revised 2026-09-27)

**Anchor on the trends people remember; use every other dataset as the places a ripple could land.**

The owner's user story:
- Fifty Shades of Gray was a huge wave in 2011–2016.
- Did it measurably change how people talk about sex, and did that carry on into #MeToo-era conversation, the rise of
  OnlyFans, or legislation?
- It doesn't need to be the primary or only driver. The interesting question is whether a trend people remember had a
  *measurable* impact on downstream behaviors and outcomes.

What that means:
- **The stone is a relatable social or cultural trend:** a book, a show, a film, a movement, a viral moment. Disasters
  and economic releases stay as a second shelf and as a proving ground for the method.
- **The ripples can land anywhere we measure:**
  - what people search and read (Wikipedia pageviews, search interest)
  - what they name their children (SSA names)
  - what they buy (BLS spending, product categories)
  - health and social outcomes (CDC)
  - work and money (QCEW, claims)
  - the law (legislation timelines)
- **The claim is contribution, not cause.** Plain labels:
  - "moved at the same time"
  - "moved more where more people were exposed"
  - "measurably contributed to"
  - "didn't move"

  The product never says "caused".
- **Why it can be a hit:** the stone is relatable and the landing spot is surprising. That pairing is the share object
  ("Frozen changed what parents named their daughters, then it reversed").
- **What keeps it honest:** culture has no footprint, and everything trends together. Every cultural claim therefore
  needs at least one of the following, and the method must first recover known effects (E9 phase 1) before any new
  trend is tested:
  - sharp timing tested against placebo dates
  - uneven exposure (country, state, release stagger)
  - a comparison title of similar size without the theme

## 1b. Design concept and direction (revised 2026-09-27)

The pond language stays. What changes is what goes in it and how the evidence reads.

- **Find is a shelf of things you remember,** grouped by year ("2013: Frozen, Harlem Shake, Breaking Bad finale"). Each
  card shows the trend and one teaser of where it rippled ("…and 3 places you wouldn't guess"). Disasters sit on a
  second shelf.
- **Trend page = the pond:**
  - The stone drops at the trend's date.
  - Rings spread over months and years, not days.
  - Outcomes that moved bob and send their own small ripple. Their distance from the stone is surprise (domain
    distance), so obvious echoes sit close and quiet, and far landings are the story.
  - Outcomes that didn't move are shown as still water, because "it didn't change X" is a finding too.
- **Ghost stone:** the comparison title is drawn faint beside the real one ("Fifty Shades vs. the other #1 bestseller of
  2012"). Where the ghost's rings match the real one's, it says so; that is the honesty device a 12-year-old can see.
- **Exposure map:** where exposure varied (states, countries), a small map shows "more exposure → bigger move". That is
  the strongest visual proof we can give.
- **Evidence ladder behind a link:**
  - timing (moved right after the date)
  - comparison (moved more than the ghost)
  - exposure (moved more where more people were exposed)
  - replicated (seen after similar trends)

  Each rung is a plain sentence. The statistics stay one click deeper.
- **Headline pattern:** "[Trend] measurably contributed to [surprising outcome]. It wasn't the only reason: [the other
  things going on]." Or: "[Trend] was everywhere, and it didn't change [thing you'd expect]." Both are shareable.
- **Tone:** serious and sleek, not cartoony, with water that feels like water. No outcomes on the rim; rings appear as
  the wave reaches them.
- **Order of work:**
  1. E9 phase 1 (method on known ripples).
  2. Phase 2 screen.
  3. The first trend pages built only for trends with a result.
  4. The share card built around the ghost stone and the surprising landing.

## 1b-ii. The look (2026-10-03): Ripple

The demo is **Ripple**: "Throw a stone. See what it changed." Design rules fixed on 2026-10-03, after the owner asked
for something that "looks like a piece of art you can play with rather than a dashboard", intuitive for a child and
deep enough for an adult to browse rabbit holes.

- **The pond is the page.** Dark water at dusk runs behind everything; reading happens on warm paper. Two
  temperatures, so the eye knows where to play and where to read.
- **Three colors mean something and nothing else uses them:** ember for the stone's lasting marks, moss for measured
  links, coral for busted links. Everything else is water and paper.
- **One stone, one splash.** A small mossy river rock falls in. Each outcome is a ripple of its own: an arc that
  spreads out to its moment in time and stays, styled by how sure we are, with a living crest that lifts and falls.
  No dots, no connector lines; the thread back to the stone appears only when you tap a ripple.
- **Lasting marks are pebbles** resting on the water, lit from beneath: the only stones on the pond are the one
  thrown and the things that stuck.
- **Time runs along a thread** on the right-hand axis, with ticks at a week, a year, ten years.
- **Type:** Fraunces for names and the big year; IBM Plex Sans for reading. The wordmark is lowercase *ripple*, the
  *i* the stone, rings spreading from the second *p*.
- **Depth:** tap a ripple for its card, "How sure?" in plain words and the source; "Same stone, other ponds" links
  stories that share a stone; a ripple that is itself a stone links to its own pond.
- **Quiet extras:** an opening screen on still water, hover previews on desktop, a drop sound that is off by default,
  a share card for every featured story.

## 1c. Aspirations (what "great" looks like; updated 2026-10-03)

1. **Surprising, multi-hop, cross-industry ripples** that end in a **lasting mark** (a law, an institution,
   infrastructure, jobs, public health, a durable behavior change). Not growth for its own sake, and not one-hop
   curiosity.
2. **Found by the engine, not hand-assembled.** Repeatable discovery of non-obvious links, judged by how often a link is
   both genuinely surprising and independently defensible (D-24, D-26).
3. **Honest about certainty.** Every link rated (measured, timed, reported, plausible, busted); invented steps never
   shown; nulls and busted claims shown as findings ("resilience is a finding", D-18).
4. **Entertainment-grade experience.** A pond that feels like water, ripples that ride out from the stone, a story you
   can follow by tapping. Works for a 12-year-old; the statistics sit one click deeper (D-21). Apple/Robinhood/Uber
   design bar (D-29).
5. **Live mode.** "Watch the ripples arrive": maps that fill in as a new event unfolds (the Trends archive has been
   collecting since Sep 29).
6. **Any event.** Type an event and get its map.
7. **Shareable.** A clip and a post for LinkedIn now; share cards (the ghost-stone comparison, the surprising landing)
   later.
8. **A verify mode.** Paste any viral "butterfly effect" claim and get it checked link by link. This already works.

## 2. Current status (one screen, 2026-10-03)

**In one line:** the demo shows ripples that left a lasting mark, with every link rated, and the engine checks any
chain. Discovery finds one-hop leads but cannot yet find the second hop on its own.

**What a ripple is now:**
- **A time-ordered chain of outcomes** (the ordering rule, ledger 1497).
- **Every link is rated:** measured, timed, reported, plausible or busted.
- **Its payoff is a lasting mark** (owner, Oct 3): a law, an institution, infrastructure, jobs, public health, or a
  durable change in behavior. Growth, attention, valuations and crazes are intermediate steps, never the endpoint.

| Layer | Status | Evidence |
|---|---|---|
| Event → attention to its subject | Works | Every family passes on Wikipedia (ledger 1458, 1470) |
| Checking supplied chains | Works | 54 chains, 228 links after the event: 10 measured, 3 timed, 107 reported, 64 plausible or not testable, 44 busted (`chain_check_v1.json`) |
| One-hop discovery | Works as leads | The editor trail rediscovered 4 of 6 documented quirky ripples; 18 of 137 leads qualified by hand, 6 with a documented outcome |
| Two-hop discovery | Not yet | Attention second hops (16 seeds) found siblings and curiosity, not consequences |
| The demo | Live as Ripple | Three tabs; each outcome its own living ripple; pebbles for lasting marks; isometric pond; paper feed; share cards (PRs #57–#60) |
| Mark-text search v1.2 | Ran; rule passed | Cultural works named inside Hansard debates and Federal Register rules: 547 pairs, 138 in bill debates and rules; the control (Mr Bates → Post Office (Horizon System) Offences Bill, second reading, Mar 20, 2024) and nine more real work → bill citations (Cathy Come Home → housing bills 1966 and 2016; My Octopus Teacher → Animal Welfare (Sentience) Bill; Adolescence → Children's Wellbeing and Schools Bill; McMafia → Sanctions Bill; Manhunt → BBFC bill; Ocean → BBNJ Bill). A citation is a reported link; the hand screen separates cause from illustration (`mark_text_v1_2.md`) |
| Mark-first search v1 | Ran; rule failed on coverage | 13,374 laws × 272,453 works → 12,996 link pairs, 3,252 time-ordered, 35 with causal language. Recall 1 of 5 strict (misses were mark/work class coverage and a narrow causal lexicon). Six documented new work → law pairs: Quincy, M.E. → Orphan Drug Act; 60 Minutes → STOCK Act; Victim (1961) → Sexual Offences Act 1967; The Daily Show → Zadroga Act; The West Wing → the 2006 Racial and Religious Hatred Bill defeat; Rangila Rasul → Section 295A (`mark_first_v1.json`) |

**Since Oct 2:**
- Map builder merged.
- The demo, through four versions.
- The chain checker.
- The editor trail, with hand qualification and a second hop.
- American English across the project.
- The lasting-mark rule.
- The mark-first search, built and launched.
- The demo became Ripple: seven design iterations in two days (see 1b-ii).

## 3. Learnings

1. **The rigor machinery works, and it is strict.** Decoys produce no false confirmations. The cost is that small real
   effects fail the power gate, so better data and designs, not looser gates, are the way forward.
2. **Resolution is the bottleneck, not imagination.** State-monthly data dilutes local shocks. A storm that wrecks 10
   counties barely moves a state total, so "absorbed" can just mean diluted. County footprints plus county outcomes
   are the biggest lever.
3. **Nulls must match the treated units' years.** b8's 5 "confirmations" came from 2024+ claims anomalies running
   3–4× the pre-2020 rate against fake shocks drawn from all years. Use year-matched or in-space permutation nulls,
   empirical p-values, and per-year anomaly scaling.
4. **The normal tail approximation is anti-conservative:** 2.7% at a nominal 1%. Prefer empirical p from many draws.
5. **Catalog contamination is real.** Katrina evacuee declarations spanned 47 states, and 9/11, a refinery explosion
   and a plant fire were typed as "Fire" (wildfire). Always inspect raw event rows before freezing a batch.
6. **Regime breaks must be excluded:** the pandemic (2020-02-15 to 2021-06-30) and the 2008–09 financial crisis.
   Claims data is still abnormal through 2022.
7. **One lead repeated across two independent batches:** flood → finance jobs. Repetition across designs is the
   strongest signal we have. The b9 county test existed because of it, and it did not hold (ledger 1277): even
   repetition across two state-level batches was not enough, so county-level confirmation stays mandatory.
8. **Choose methods on placebo data, never on real treated units.** That is how E1 is built, so choosing a method
   cannot peek at the answer.
9. **Obvious-link filtering by regex is weak.** Surprise should come from the mechanism graph and domain distance.
10. **Family pooling dilutes single-event ripples.** Broad families (v2 "streaming hits") erased The Queen's Gambit →
    Chess. Families must be tight and mechanism-first (taxonomy v3), and a single-event method is still needed.
11. **Timing alone is weak evidence and has low power.** Correlated timing over thousands of outcomes is the hardest
    way to find a small effect. Direct evidence of the path (where readers actually went) is much stronger.
12. **Real-world series barely register cultural events.** Across 7 non-Wikipedia lenses, v2 found nothing except a
    COVID artifact.

**New since 29 Sep:**
- Search is the front door: ripple traffic reaches Wikipedia mostly from search, so Wikipedia views stand in for search.
- Clickstream is a curiosity graph (what readers look up next), not a consequence graph; it produced related topics,
  not outcomes.
- The ordering rule is the most useful single filter: it rejected Oppenheimer → atomic-bomb books (rise began before the
  film), which the statistics alone passed.
- Check raw counts before calling a pass: normalizing against a collapsing panel (2020 library closure) manufactures
  rises.
- One well-built map explains the product better than any table.

**New since Oct 2:**
- **Curiosity is not consequence, three times over.** Clickstream, editor-trail one hops and attention second hops all
  return things related to the show. Consequences live in records: charts, filings, laws, employment, health.
- **The ordering rule busts confident claims.** It busted 44 of 228 links. Examples: the ethanol law (corn and
  tortilla prices rose first) and the Barbie paint shortage (a year before release).
- **AI-written "butterfly effect" chains** get steps 1–2 right; steps 4–5 are usually invented, misdated or folklore.
  Historical invention and policy lineages are the strongest content.
- **Honest confidence beats sparse certainty**, provided invented steps never show as links.
- **A ripple worth showing leaves a lasting mark.** Growth alone is not a ripple's "so what".

## 4. Pitfalls (operational, learned the hard way)

**Database load**
- **Disk-IO burst budget.** Session 2's jobs exhausted it and the database stopped answering for about an hour.
- Rules: never more than one heavy every-minute job, never more than about 20k rows in one transaction, and stagger
  schedules.

**Tooling**
- **MCP `execute_sql` past 60 s** returns an error but **keeps running server-side**. Run long work as one-off cron
  jobs.
- **Repo SQL drifts from live functions.** Patch by anchoring on `pg_get_functiondef`, never on the repo text.
- **PL/pgSQL traps:**
  - Never put a `CASE` inside an `IF` condition.
  - Avoid variable names that clash with columns or keywords.
  - A multi-statement MCP call is one transaction.

**Engine**
- **Decoy seeding is manual** (`att_fx63_decoy_seed`). Without it a batch never finishes.
- Grids with no clean decoy date can loop forever; this is now tracked per grid.
- **Finishers** must not unschedule shared workers while another batch is unfinished. Each batch now has its own
  finisher.

**Network and APIs**
- The cloud container cannot reach most government APIs directly. The database (pg_net) can reach some. HUD and EPA
  refuse the database network, so they run on GitHub Actions.
- **API coverage surprises.** The QCEW open-data API only serves 2014+. HUD rate-limits at about 60 requests a minute.
  Always dry-run and read the logs before a real run.
- **Scheduled jobs must resume.** A job that restarts from year 1 every run never gets past its row cap. The fix was
  done-year tracking in `att_state`.

**Security**
- Keys never appear in logs or URLs that are printed. Grep for leaked keys before every commit.

**GitHub**
- Workflow dispatch and cancel from this integration return 403. Runs are started by a one-line comment push to the
  workflow file on the `claude/**` branch (with its `paths` trigger). Other pushes use `[skip ci]`.
- The Q3/Q4 workflows share the concurrency group `ripples-q3`. A new pending run cancels an older pending one, so
  start them one at a time.
- The job-log API keeps only the last 5,000 lines, and artifact hosts return 403 from the sandbox. Reports go to
  `ripples.att_q3_results` via `att_q3_result_put` (q3_upload.py).

**Wikimedia**
- On 2026-09-28 a 429 stopped the wide fetch. A second run was queued by a push and kept fetching that day, a breach
  that is disclosed (ledger 1300, 1364). `l4_panel.py` now writes a stop marker on any 403/429/5xx or timeout and
  refuses same-day fetches.
- The sandbox proxy blocks en.wikipedia.org, so title checks can't run there. Missing titles are skipped at run
  time, never remapped.

## 5. Blockers and bottlenecks (2026-10-03)

**Blockers**
1. **Second hops are not automated.** Lasting marks are in records, not attention data.
2. **Free outcome data is patchy.** Charts, book sales, tourism and app downloads are mostly paid or scattered.
3. **Curation load.** The best maps are assembled from dated records, and lead qualification is editorial.

**Bottlenecks**
1. BigQuery sandbox cap (204.8 GiB a day; no billing).
2. Wikimedia politeness, and per-title pageviews that do not follow renames. arXiv returns 503 under load.
3. The container cannot reach Wikipedia or FRED. All fetching runs on GitHub Actions.

## 6. Immediate next steps (in order)

1. **Mark-first search.** Work backwards from lasting marks and ask which followed each event, and whether a dated path
   connects them. Sources:
   - laws: Congress.gov, state legislatures, Korea's National Assembly open API;
   - rules: the Federal Register;
   - institutions;
   - employment: BLS;
   - health statistics.
2. **Second hops from records.** For each qualified lead, pull outcome data:
   - chart records for music;
   - heritage visitor statistics for filming locations;
   - the NYT Books API for publishing;
   - FRED/BLS series where an industry series exists.
3. **A records assistant.** It proposes dated outcomes with citations; the checker verifies the dates and the order.
4. **A slope test** for gradual changes (ChatGPT → Stack Overflow).
5. **Mark-first, the decision.** The pre-registered rule failed on recall, so by protocol the Wikipedia route gives
   way to legislative text APIs; the diagnosis says every miss was coverage (mark and work classes, the causal
   lexicon, a bill date used as the law's date), and the route found six documented pairs. Proposed: one v1.1 run with
   those fixes under a new pre-registration before switching. The six pairs go to a blind round and then to maps.
6. **Look and feel, remaining:** a shelf of live story thumbnails; label collisions on crowded slices; then the
   LinkedIn reel (`?reel`) and post, held until the owner signs off on the look.

## 6a. Open questions (2026-10-03)

- Can a records search (laws, rules, filings, employment, health) find lasting marks downstream of cultural events
  often enough to fill maps, or are marks rare for pop culture and common for policy and invention?
- How much curation is acceptable in the product? Where is the line between "the engine found it" and "we
  assembled it"? The demo labels the difference; the pitch must too.
- Which free outcome sources per mark type are reliable enough to automate?
- Is live mode compelling before marks have had time to form?

## 7. Rules that never change

- Every test is pre-registered in the ledger before any result exists. Deviations are disclosed, and late ones are
  labeled late. Confirmations must pass the seasonal check or be withheld.
- Honest UA `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`. Stop on 429/503 with no same-day retry.
  No bypassing blocks. Aggregate data only, no personal data.
- Keys live only in Supabase Vault or GitHub secrets.
- Claude opens and merges its own PRs (owner direction, 2026-09-28), keeping to the product vision.
- Explore freely, confirm by registration (owner, 2026-09-29): exploration needs no registration; anything shown as
  measured comes from a registered test.
- The ordering rule (owner, 2026-09-30, ledger 1497): every step an outcome in its own data, every step later than the
  one before.
- Show raw counts beside every behavior result; exclude closure months.
- Every link shows how sure we are: measured, timed, reported, plausible or busted. Invented steps never appear as
  links. A step that began before its cause is busted.
- One-hop leads are qualified, not capped: a material endpoint, a plausible path and timing that points to the event,
  with the reason recorded for every lead left out.
- A ripple's payoff is a lasting mark. Growth, attention and hype are intermediate steps.
- American English and US date formats throughout.
- On the pond, the metaphor is literal: one stone, one splash, each outcome its own ripple, no dots and no connector
  lines unless asked for. Ember, moss and coral are reserved for marks, measured and busted.
