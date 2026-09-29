# Ripple Map: context brief (updated 2026-09-29 05:40 UTC)

Standalone context for anyone (person or new chat) picking up Ripple Map. It covers the vision, the current status,
what we learned, pitfalls, open gaps and next steps. The operational runbook with exact commands is
`ripples/HANDOFF.md`, and the experiments plan is `ripples/docs/experiments.md`.

- Live site: https://bensunter.com/ripples/pond/ (explorer) and https://bensunter.com/ripples/discover/ (discovery
  engine prototype: what the engine found and the evidence behind each result)
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

## 2. Current status (one screen, 2026-09-29)

**In one line:** the engine recovers known ripples and has found one small real one. Tight event families and a
direct event → subject test run today. Our planned next step is to follow reader paths (Wikipedia Clickstream)
instead of relying only on timing.

**What works**
- **Calibration (E9, ledger 1282):** told where to look, the engine recovers known ripples: The Queen's Gambit →
  Chess, Stranger Things 4 → Kate Bush, Game of Thrones → the baby name Arya, Frozen → Elsa.
- **One discovery that replicated:** space events → Wikipedia views of "Speed of light". After big space moments
  (landings, first images, launches), more people than usual read "Speed of light". It passed two held-out
  confirmations on 8 and then 12 new space events (ledger 1286, 1288, 1292). It is real but small: a one-step
  curiosity effect, not a headline.
- **Rigor:** every test is pre-registered in the hash-chained ledger (now 1,371 entries). Decoy and placebo nulls,
  BH correction and held-out confirmation are all in place.

**Discovery v1 (ledger 1283).** For a family of 10-20 similar events, it looks for outcomes that change more than usual in
the days after each event (onset-coupled day-to-day changes over days −14..+90). Each outcome is calibrated against 200
placebo dates, and each family against 1,000 moved-date worlds. Candidates must pass BH at q = 0.10 and a
leave-one-event-out check.

**Lenses (places a ripple can land), all loaded**

| Lens | Size |
|---|---|
| Wikipedia pageviews | 998 curated articles, plus 10,000 Level-4 Vital Articles (wide lens, ~83% fetched) |
| NYT coverage by tag | 1,289 tags |
| Real world, daily | electricity demand (EIA), markets (FRED), air travel (TSA): 161 series |
| Tech and city, daily | Hacker News, npm, NYC transit, FEMA |
| Weekly | jobless claims, business applications, deaths, fuel |
| Monthly | state economies, jobs by industry, CPI |
| Seattle library checkouts | 493 subjects |
| County jobs | QCEW, 3,290 counties |

**Screens so far**
- **v1 and v2 (13 broad families, all lenses):** no candidates apart from space → speed of light. One false alarm was
  explained: "pandemic crazes → state unemployment" was COVID (ledger 1303).
- **Diagnosis:** broad families average single-event ripples away. Nine different streaming shows diluted The Queen's
  Gambit → Chess to nothing.

**Queued for today, 2026-09-29, one Wikimedia job at a time**
1. **Wide lens:** finish the fetch (~1,550 articles left), then screen.
2. **Screen v3 (taxonomy v3):** 24 tight, mechanism-first families, 321 events, on all 8 lenses (ledger 1365, 1366,
   1369).
3. **Named-subject test (Q4):** does each event move attention to its own named subject?
   - v1: 197 events from the owner's batch (ledger 1367).
   - v1b: 43 older corpus events from the owner's validation pack (ledger 1369).
   - A 22-show held-out drama set that confirms the drama family only if it passes (ledger 1369-1371).
4. A check-in (09:30 UTC) collects results, hand-checks candidates, updates /ripples/discover/ and reports.

**Expectation, stated in advance**
- Named subjects for dramas and films: likely to pass (the effect is direct). That shows the mechanism, not surprise.
- Tight families: perhaps 1-3 candidates, some with a boring explanation (seasonality, echo, common shock).
- Real-world lenses: most likely nothing. One cultural event rarely moves national economic series detectably.

**Older disaster and economy track (b1-b9, E1).** It confirmed only obvious links. The flood → finance jobs lead
did not replicate at county level (b9, ledger 1277). E1 chose random-effects pooling (ledger 1278). This track is
parked as the proving ground (D-26).

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

## 5. Blockers and bottlenecks (2026-09-29)

**Blockers (stop progress until resolved)**
- None hard. Everything queued runs on data and events already in hand, and the owner does not need to supply
  events for the next steps.

**Bottlenecks (slow progress or cap what we can find)**
1. **Method: timing alone rarely finds surprising ripples.** Small effects, noisy outcomes and thousands of outcomes
   tested mean very little survives strict correction. This is the main bottleneck; see the plan below.
2. **Pooling needs 10-20 events of one kind.** Users care about one event, and families need owner-sourced events
   with exact dates. The owner cannot source more right now.
3. **Wikimedia politeness limits throughput.** It allows one fetcher at a time, and any 429/5xx ends that day's
   Wikimedia work. That costs a day per stop. The wide lens still has ~1,550 articles to fetch.
4. **Orchestration friction:**
   - Workflows can't be dispatched directly (push-to-trigger only).
   - A shared concurrency group means strictly sequential runs.
   - Logs truncate at 5,000 lines (worked around with the results table).
5. **Held-out data is thin outside dramas.** The science and news held-out rows supplied so far don't fit their
   families: four or six space missions split into several rows, and disasters rather than sport, business and
   civic events. The drama held-out set is 22 events, some with titles we could not verify.
6. **Real-world lenses have low sensitivity** to single cultural events (national aggregates, monthly or weekly
   resolution).

## 6. Planned approach (next steps, in order)

1. **Today:** run the queue above; resolve every result in the ledger; hand-check candidates; update /ripples/discover/;
   report plainly, including nulls.
2. **Next: follow reader paths with Wikipedia Clickstream** (monthly public dumps since 2017: counts of readers clicking
   from article A to article B, pairs with at least 10 clicks).
   - For one event, build the ripple map as the paths readers took outward from the event article, 2-4 steps, with
     counts before and after the event month. For example: The Queen's Gambit → Beth Harmon → Chess → Sicilian Defence.
   - Discovery flags paths that are new or unusually grown after the event.
   - Verification uses the actual click counts before and after, against the same months in other years and against
     comparison events.
   - First prototype: The Queen's Gambit, Chernobyl and one space event, drawn on /ripples/discover/ as
     click-by-click paths.
   - It works per event, so no family of 10-20 is needed.
   - Pre-register before fetching. The dumps are downloaded from dumps.wikimedia.org one at a time, after the day's
     other Wikimedia work.
   - Limits: monthly resolution; it shows what people read, not what they did.
3. **Chain test: attention → behaviour.** For event → subject pairs that pass Q4 (or show in Clickstream), test only
   that subject in the real-world lenses. For example, chess → Seattle library chess checkouts; a nuclear drama → NYT
   nuclear-power coverage. Testing a handful of pre-chosen outcomes instead of thousands raises power sharply.
4. **If v3 or Q4 produces candidates:** confirm each on held-out events before it goes on the page as more than a
   lead.
5. **If both come back empty:** test longer windows than 90 days and weekly smoothing for the noisy lenses, before
   asking the owner for more events.
6. **Product:** once a path survives, the pond page for that event shows the path, the counts, the comparison and a
   plain sentence per step (evidence ladder). The share card is built around the surprising landing.

**From the owner, when possible (not blocking)**
- More held-out drama premieres that are new to every corpus file (check `events_taxonomy_batch1.csv` first).
- For science and news confirmation: 12-15 distinct events of the same kinds as the family, one row per event,
  spread over years.

## 7. Rules that never change

- Every test is pre-registered in the ledger before any result exists. Deviations are disclosed, and late ones are
  labelled late. Confirmations must pass the seasonal check or be withheld.
- Honest UA `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`. Stop on 429/503 with no same-day retry.
  No bypassing blocks. Aggregate data only, no personal data.
- Keys live only in Supabase Vault or GitHub secrets.
- Claude opens and merges its own PRs (owner direction, 2026-09-28), keeping to the product vision.
