# Ripple Map: context brief (updated 2026-10-03, 17:00 UTC)

Standalone context for anyone (person or new chat) picking up Ripple Map. It covers the vision, the current status,
what we learned, pitfalls, open gaps and next steps. The operational runbook with exact commands is
`ripples/HANDOFF.md`, and the experiments plan is `ripples/docs/experiments.md`.

- Live site:
  - https://bensunter.com/ripples/demo/: the product prototype, branded **Ripple** since 2026-10-03. Three tabs: Lasting marks (maps that end in a law, an institution or a public-health change), Fact-checks (viral and historical chains checked link by link), Engine leads (what the engine found on its own).
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

## 2. Current status (one screen, 2026-10-03, 17:00 UTC)

**In one line:** the engine now finds work → law trails on its own from the records (Hansard, the Federal Register,
the Congressional Record), dated to the day with the sentence that makes the link; the demo is Ripple, with a dozen
new maps that end in a law; verification lags discovery, and a person still screens the finds. Rating: 6.5 of 10 (was
5.5 on Oct 2, 4 on Oct 1); the agreed target is 7.5.

**What a ripple is:**
- **A time-ordered chain of outcomes** (the ordering rule, ledger 1497).
- **Every link is rated:** measured, timed, reported, plausible or busted.
- **Its payoff is a lasting mark** (owner, Oct 3): a law, an institution, infrastructure, jobs, public health, or a
  durable change in behavior. Growth, attention, valuations and crazes are intermediate steps, never the endpoint.
- **How sure, honestly:** *measured* is a reproducible placebo test (association plus order, an empirical p-value that
  is honest about chance, not about mechanism); *timed* is order only; *reported* is a source making the link;
  *plausible* is that it happened. The ordering rule falsifies, it never proves. A drama → an Act is not statistically
  verifiable by anyone; it is shown as reported, never dressed as measured.

| Layer | Status | Evidence |
|---|---|---|
| Event → attention to its subject | Works | Every family passes on Wikipedia (ledger 1458, 1470) |
| Checking supplied chains | Works | 67 chains after batches 13–15 (54 before Oct 3): per link measured / timed / reported / plausible / busted (`chain_check_v1.json`); 17 measured steps after the window fix (Mr Bates 370×, p = .023; Zadroga 48.7×, p = .012; Ocean 4.6×, p = .004; Alcohol and cancer 4.2×, p = .035). New step types: `file` (official series from `series_v1.json`: NIAAA per-capita ethanol 1970–2022; BRFSS drinking medians 2011–2025) and `dose` |
| **Discovery: the records route (mark-text v1.2 → v1.3)** | **Works; rule passed** | Every Hansard contribution naming a work (574 for Mr Bates, 1,058 for Adolescence, back to the 1960s), Federal Register rules, and with the owner's key the Congressional Record: both controls found (Mr Bates → Post Office (Horizon System) Offences Bill, second reading, Mar 20, 2024; Tiger King → Big Cat Public Safety Act, Jul 28, 2022); 547 UK/FR pairs, 138 in bill debates and rules; nine more real work → bill citations by hand screen. v1.3 (US collections queried properly) running |
| **Bill → Act resolver v3** | Works | UK Parliament Bills API and legislation.gov.uk: 106 bills, 78 resolved to an Act with its Royal Assent date, 76 ordered pairs (Mr Bates → Offences Act 2024, May 24; Adolescence → Children's Wellbeing and Schools Act 2026; Cathy Come Home → Homelessness Reduction Act 2017 …). Cross-year matches fixed; bills keyed by name and year |
| **The citation screen (cite_score v1)** | Works; a transparent floor | A rule scorer labels each citation *reason* / *context* / *aside* from causal words, the clause's subject, a change word, argument form and illustration markers; against the owner's 22 hand grades: precision .73, recall .89. Resolver output carries the score and its reasons; the demo rates an act lead *reported* only when cited as a reason, and prints why. Labels today: 24 reason, 13 context, 43 aside |
| **Dose-response (evidence ladder, rung 3)** | One result, a real negative | Pre-registered design (`ripples/docs/dose_response_v1.md`): states that opened retail cannabis (20) against states that never did (31), change in past-30-day drinking from the last survey before to the second after, 2,000 random assignments for p, pre-trend placebo. The youth outcome (YRBS) could not run: state tables end in 2017 and CO and WA do not take part. Adults 18–24 (BRFSS, annual): −1.2 points against controls, p = 0.10, pre-trend flat (p = 0.34): within chance. All adults −0.4, p = 0.29. The "cannabis replaced drinking" catalyst fails the first rung above timing |
| **Attention checks for every post-2015 step** | Built; first full run landing | 113 dated steps since 2015 had no placebo test of their own. The checker now finds each step's Wikipedia article by search and runs the measured-step test at the step's date; the step's level does not change, the card shows the result |
| Discovery: the Wikipedia route (mark-first v1, v1.1) | Ran three times; rule failed on recall, passed on new pairs | 13,371 laws × 289,960 works; recall 2 of 5 (two recall laws have no article of their own); new pairs: 60 Minutes → STOCK Act, Quincy → Orphan Drug Act, Victim → Sexual Offences Act 1967, The Daily Show → Zadroga Act, The West Wing → Racial and Religious Hatred Act 2006, JFK (film) → JFK Records Act 1992, Silent Spring → NEPA, Holy Deadlock → Matrimonial Causes Act 1937. Now secondary; read by hand |
| **The first blind round** | Done | 15 names to the owner: 14 interesting, 4 strictly non-obvious (Victim, The Daily Show, Ocean, Manhunt) and 9 "medium", 13 worth chasing. Left out: Rangila Rasul, Holy Deadlock |
| **Maps that end in a law** | 12 new chains (batches 13–15) | Mr Bates → Offences Act 2024; Cathy Come Home → Housing (Homeless Persons) Act 1977; Quincy → Orphan Drug Act; My Octopus Teacher → Sentience Act 2022; 60 Minutes → STOCK Act; Victim → Sexual Offences Act 1967; The Daily Show → Zadroga Act 2011 and the 2019 fund; Manhunt → Byron Review → Digital Economy Act 2010 and statutory PEGI; The West Wing → the 2006 defeat; Silent Spring → EPA and the DDT ban; Ocean with David Attenborough → the trawling consultation (no mark yet; measured 4.1× attention, p = 0.004); **Prohibition → a century of American drinking** (22 steps, 1920–2025) |
| The Prohibition throughline (owner's long-horizon test) | Built; first verdicts in | Crime, repeal, drinking's return and the cirrhosis peak, AA and NIAAA, the teen decline (MTF: 72% → 50% → 29%), young adults (Gallup). Each popular catalyst for the Gen Z decline (smartphones, Dry January, legal cannabis, sober curious, the Surgeon General) is a dated step; the claim that it *started* the decline is busted by order against the 1980 onset; as accelerants after 2013 they stay plausible |
| Engine leads in the demo | Two kinds | Attention leads (18 qualified, 6 with outcomes) and, new, **Parliament's citations**: every Act whose debate named a work, one pond per work (Cathy Come Home, Mr Bates, Silent Spring, Adolescence), with the sentence and links to Hansard and legislation.gov.uk |
| Two-hop discovery from attention | Not pursued further | Attention second hops found siblings and curiosity; records are the route |
| The demo | Live as Ripple | Isometric pond that is the page; a mossy stone; each outcome its own living ripple with a crest; pebbles for lasting marks; paper feed; wordmark and opening screen; two-tone icons; share cards and share pages; "Same stone, other ponds" (PRs #57–#65 and today's branch). Labels now place by priority, keep clear of the rim words, wrap to two lines, and wait for a hover when a pond is crowded, so a 17-ripple century and an 18-Act map read cleanly. Cards explain dose-response steps and carry the attention check. Awaiting the owner's review |

**Since Oct 3 morning:**
- The records route built, debugged four times by reading one known case each time, and passed.
- The Wikipedia route run twice more and demoted to secondary.
- The blind round graded by the owner.
- Twelve maps that end in a law, as checked chains; the Prohibition throughline as the long-horizon test.
- The Bill → Act resolver; Parliament's citations as engine-found maps in the demo.
- The checker's attention-window bug found and fixed.
- Ripple's look: palette, paper, wordmark, intro, stone, crests, quiet pond.
- **16:00–17:00:** the citation screen, the dose-response design (five runs to a clean result), `file` and `dose`
  step types, attention checks for every post-2015 step, and the label pass that makes crowded maps readable.

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

**New since Oct 3 (the records route):**
- **Records beat attention for lasting marks.** The parliamentary record names the work that moved a debate, on the
  day, in the member's own words. Nothing in attention data does that.
- **Read the sentences before trusting the counts.** Four bugs in one day were each found by looking at one known case
  (Mr Bates, The Jungle, Tiger King, the Horizon surge): a missing quote mark in the title regex, a recency cap, a
  double space from a highlight tag, a search window that ended on the step's own day.
- **A citation is a reported link, never more.** "The work was in the room when the law was made" is the honest
  sentence; cause remains the hand screen's call.
- **Surprise is a higher bar than interest.** The owner found 14 of 15 pairs interesting but only 4 strictly
  non-obvious: the ones with an odd mechanism (a 1961 film, a comedian, a documentary → crab welfare, a game → a
  statutory rating system).
- **The ordering rule earns its keep on long horizons.** In the Prohibition throughline it busts every popular
  catalyst for the Gen Z decline as the *origin* (the decline began in 1981) while leaving them standing as
  accelerants; that is a finding, not a failure.
- **A Wikipedia route has a structural ceiling:** a law without its own article (the Offences Act, the Big Cat Act)
  cannot be reached through article links at all.

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

**Workflows and CI (Oct 3)**
- A workflow's commit step must add the *versioned* results filename; v1.1's first run was lost to `git add
  mark_first_v1.json`. Both searches now add `*_v1*.json`.
- Read job logs through the GitHub MCP `get_job_logs` tool; the built-in `gh` refuses the blob redirect. Logs of a
  running job are not available.
- Wikidata SPARQL answers 500/504 under load: retry three times, keep queries small (per class group, per year),
  and carry a class floor from the last good run.
- A push to a workflow's paths cancels its in-progress run (chain check); the cancelled run still commits what it had.
- After a squash merge the working branch diverges from main; reset it onto `origin/main` and cherry-pick.
- The Hansard API highlights the match with `<em>` tags: collapse whitespace before matching text.
- legislation.gov.uk's title feed answers across years: check the Act's own year in its id.

## 5. Blockers and bottlenecks (2026-10-03, 17:00 UTC)

**Blockers**
1. **Verification lags discovery, less than this morning.** Every dated post-2015 step now gets an attention check
   where an article exists; marks older than 2015 still rest on records, and outcome series beyond attention are
   scarce (the youth drinking tables stop in 2017).
2. **A person still screens the finds, with a scorer beside them.** cite_score v1 labels citations with .73
   precision and .89 recall on 22 grades; the product says "cited as a reason" or "mentioned in passing" from it. A
   model-based classifier would be the next step and needs a key the project does not hold.
3. **Free outcome data is patchy** for charts, sales, tourism and app downloads.

**Bottlenecks**
1. Wikidata SPARQL reliability; Wikimedia politeness; per-title pageviews that do not follow renames.
2. legislation.gov.uk explanatory notes: the paths tried return 404 for everything but recent primary Acts; the Atom
   title feed is the only working door.
3. The container cannot reach Wikipedia, Wikidata, FRED, parliament.uk or GovInfo; all fetching runs on GitHub Actions,
   so each fix costs a run (15–90 minutes).
4. BigQuery sandbox cap (204.8 GiB a day; no billing).

## 6. Immediate next steps (in order)

1. **The owner's review** of the branch: the readable maps, the citation reasons, the dose-response step, the
   attention checks; then merge and the LinkedIn asset.
2. **Read the attention-check run:** how many of the 113 steps found an article, how many rose beyond chance; fix
   bad article matches by adding a `wiki` hint to the step.
3. **More rungs:** a Bill → Public Law resolver for the US (GovInfo "related"); a second dose-response (Dry January
   by country; the Surgeon General advisory by state attention); a second blind round scored against cite_score.
4. **The screen beyond rules:** a second grade set from the owner (30 citations), then a model-based classifier if
   a key becomes available.
5. **Nested stones:** Prohibition's marks (the 21st Amendment, AA, NIAAA) as chains of their own, so the throughline
   links down into them.
6. **The look to sign-off, then LinkedIn:** living crests and the stone; the reel (`?reel`) and the post, led by a
   lasting-mark chain plus one busted viral claim.
7. **Live mode** on new events with the Trends archive and the records route (Hansard is live within a day).

## 6a. Open questions (2026-10-03, 17:00 UTC)

- How often is a parliamentary citation a cause rather than an illustration? The owner's 22 grades calibrate
  cite_score v1 (24 reason / 13 context / 43 aside across 80 pairs); a second blind round should be scored against it.
- Dose-response: the cannabis catalyst is within chance for young adults and all adults. Is the Gen Z decline
  over-determined, or is the exposure that matters not state-shaped (phones, prices, health messaging)?
- Where is the line between "the engine found it" and "we assembled it" in the product's own words? Today: the
  engine finds and dates the citations; a person keeps the real ones and writes the chain.
- Is a reported-only map (no measured step) worth showing at all, or should every map carry at least one measured
  ripple before it leads a tab?
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
- A citation in a record is a reported link, never measured. Measured means a placebo test on data; it shows an unusual
  rise in the right order, not cause. Nothing is dressed as more certain than its test.
- Every search runs under a rule fixed before it starts; a failed rule is reported as failed, with the diagnosis.
