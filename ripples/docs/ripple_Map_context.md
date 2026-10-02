# Ripple Map: context brief (updated 2026-10-02)

Standalone context for anyone (person or new chat) picking up Ripple Map. It covers the vision, the current status,
what we learned, pitfalls, open gaps and next steps. The operational runbook with exact commands is
`ripples/HANDOFF.md`, and the experiments plan is `ripples/docs/experiments.md`.

- Live site: https://bensunter.com/ripples/discover/ (every test and its evidence),
  https://bensunter.com/ripples/discover/queens-gambit/ (the first full ripple map) and
  https://bensunter.com/ripples/pond/ (the original explorer, parked)
- Repo: `bsunter93/Ben-Sunters-Website`
- Database: Supabase project `kffkasnzqcddpystszch`, schema `ripples`. The compute tier went from nano to micro on
  2026-09-27.

---

## 1. Vision (owner, verbatim core)

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
- Fifty Shades of Grey was a huge wave in 2011–2016.
- Did it measurably change how people talk about sex, and did that carry on into #MeToo-era conversation, the rise of
  OnlyFans, or legislation?
- It doesn't need to be the primary or only driver. The interesting question is whether a trend people remember had a
  *measurable* impact on downstream behaviours and outcomes.

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

## 2. Current status (one screen, 2026-10-02)

**In one line:** the engine verifies obvious ripples well, as dated, time-ordered chains, and has published its first
full map (The Queen's Gambit). It has not yet found a surprising ripple. The next step is automating the map builder.

**What a ripple is now (owner rule, ledger 1497):** an approximate cause-and-effect chain. Every step is an outcome
measured in its own data (attention, behaviour, real world), and every step starts after the step before it. A step
whose rise began before the event is dropped.

| Layer | Status | Evidence |
|---|---|---|
| Event → attention to its named subject | Works | Every family passes on Wikipedia with weekday-matched placebos; holds on US TV news for films, deaths, news and science/tech (ledger 1458, 1470) |
| Attention → behaviour | Works for obvious chains | Seattle library borrowing: The Queen's Gambit → chess books, Barbie → Barbie books, after the event (2 of 13; ledger 1501, 1504) |
| Less obvious behaviour chains | Not yet | 0 of 10 (ledger 1503, 1504) |
| A whole map | Prototype | The Queen's Gambit: release → chess attention +3 days → chess sets and Chess.com +19/+25 days → library borrowing Nov 2020 → NPD chess-set sales +87% (ledger 1505) |
| Discovering surprise | Not yet | Broad screens, eight lenses, reader paths (two blind rounds: 1 and 0 of 5 needed) and less obvious chains found only obvious links, artefacts or nothing |

**Since 29 Sep:** reader paths showed ripple traffic reaches Wikipedia mostly from search (direct clicks 1–3%); a daily
Google Trends archive started (ripples.att_gt_terms); the named-subject test was re-run on TV news and Hacker News; the
reader-path "discovery funnel" was tried and dropped after two blind owner ratings; the ordering rule was adopted; two
Tiger King results were withdrawn as library-closure artefacts (ledger 1504).

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
    COVID artefact.

**New since 29 Sep:**
- Search is the front door: ripple traffic reaches Wikipedia mostly from search, so Wikipedia views stand in for search.
- Clickstream is a curiosity graph (what readers look up next), not a consequence graph; it produced related topics,
  not outcomes.
- The ordering rule is the most useful single filter: it rejected Oppenheimer → atomic-bomb books (rise began before the
  film), which the statistics alone passed.
- Check raw counts before calling a pass: normalising against a collapsing panel (2020 library closure) manufactures
  rises.
- One well-built map explains the product better than any table.

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

## 5. Blockers and bottlenecks (2026-10-02)

**Blockers**
1. **No surprising content yet.** Verification works; discovery of non-obvious ripples does not.
2. **Behaviour data is thin and local.** The only free behaviour series with history is one city's library (monthly)
   and annual baby names. National sales, sign-ups and enrolment are not free.
3. **No automation.** The first map was assembled by hand.

**Bottlenecks**
1. **BigQuery sandbox cap:** 204.8 GiB a day, not adjustable without billing (owner: no billing).
2. **Wikimedia politeness and GDELT refusal** limit high-volume fetching from GitHub runners.
3. **Monthly behaviour data** cannot order steps that move in the same month.
4. **Owner rating time:** blind rounds should be 15 items or fewer.

## 6. Immediate next steps (in order)

1. **Map builder.** One script: event (title, date) → daily attention for the event, its named subject and a fixed set
   of follow-on topics → onsets and the ordering check → behaviour step from library borrowing where a heading exists
   (closure months excluded, raw counts shown) → optional public-record step (dated, sourced) → the same page as The
   Queen's Gambit, generated.
2. **Ten maps** for events whose first step is already verified (Chernobyl, Barbie, Oppenheimer, a death, a science
   event, …). Publish those that pass the ordering rule.
3. **Later steps from search, not reader paths:** rising searches after the event (Google Trends archive, usable for
   events from October 2026 on) and Wikipedia topics whose rise follows the subject's (lead–lag over a fixed candidate
   set), time order enforced.
4. **Live mode:** run the builder on new events as they happen, so maps fill in over the following weeks.
5. **Short blind rounds (≤ 15 items)** on the later steps, with the owner's rule.

**Decision points:** if fewer than 5 of the 10 maps carry a measured behaviour step, behaviour becomes "where
available" and maps lead with attention. If two short rounds miss the owner's rule, the product is verified maps of big
events (obvious but real, well told), not hidden ripples.

## 7. Rules that never change

- Every test is pre-registered in the ledger before any result exists. Deviations are disclosed, and late ones are
  labelled late. Confirmations must pass the seasonal check or be withheld.
- Honest UA `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`. Stop on 429/503 with no same-day retry.
  No bypassing blocks. Aggregate data only, no personal data.
- Keys live only in Supabase Vault or GitHub secrets.
- Claude opens and merges its own PRs (owner direction, 2026-09-28), keeping to the product vision.
- Explore freely, confirm by registration (owner, 2026-09-29): exploration needs no registration; anything shown as
  measured comes from a registered test.
- The ordering rule (owner, 2026-09-30, ledger 1497): every step an outcome in its own data, every step later than the
  one before.
- Show raw counts beside every behaviour result; exclude closure months.
