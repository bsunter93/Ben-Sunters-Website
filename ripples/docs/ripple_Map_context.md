# Ripple Map: context brief (updated 2026-10-05, evening UTC)

Standalone context for anyone picking up Ripple. Read `ripples/HANDOFF.md` first: it is the
runbook (what to install, how to build, test and ship, the rules, the next steps); this brief is the
why and the record. It covers the vision, the current status,
what we learned, pitfalls, open gaps and next steps. The operational runbook with exact commands is
`ripples/HANDOFF.md`, and the experiments plan is `ripples/docs/experiments.md`.

- Live site:
  - https://bensunter.com/ripples/demo/: the product, branded **Ripple** since 2026-10-03. It opens on Tiger King → the Big Cat Act. One chooser with three kinds: Lasting marks (maps that end in a law, an institution or a public-health change), Fact-checks (viral and historical chains checked link by link), Engine leads (what the engine found on its own). Every featured story has a share page at `/ripples/demo/s/<slug>/` with its own preview image; `?c=<slug>&s=<step>` opens on one ripple, stopped.
  - `ripples/dist/ripple-standalone.html`: the whole demo in one file for offline review; `ripple-review-kit.zip` beside it.
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

## 1b-ii. The look (2026-10-03, revised 2026-10-04): Ripple

**Revised 2026-10-04 after the owner's review of the live page** ("cartoony wireframe"; "worried about people calling this
AI slop before even giving it a chance"). The record is `styling_pass_v2.md`. In short: one flat desaturated surface, no
gradient, sheen, vignette or glow; the pond has no box, a hairline rim and one faint top light; rim words are italic
print annotations (off on phones), the sector spokes are gone; labels are haloed type, not boxes, with a mark's name in
ember; a matte stone; 6-px controls, small-capital grade badges; the opening screen is retired and the page opens on the
pond. The bullets below describe the Oct 3 look where they conflict with this paragraph; this paragraph wins.

The demo is **Ripple**: "Throw a stone. See what it changed." Design rules fixed on 2026-10-03, after the owner asked
for something that "looks like a piece of art you can play with rather than a dashboard", intuitive for a child and
deep enough for an adult to browse rabbit holes.

- **The pond is the page.** Dark water at dusk runs behind everything; reading happens on warm paper. Two
  temperatures, so the eye knows where to play and where to read.
- **Three colors mean something and nothing else uses them:** ember for the stone's lasting marks, moss for measured
  links, coral for busted links. Everything else is water and paper.
- **One stone, one splash, one wavefront (revised Oct 4).** A matte stone is thrown from the near bank (drag and
  release to throw it yourself) and lands with a splash. One wavefront leaves it and moves outward; each outcome
  blooms where the front is when it happens and stays, so no ripple ever passes another. The pond is an instrument:
  hairline rings labeled 1 day, 1 month, 1 year, 10 years; a vignette for depth; the water's light and caustics
  under a frame budget the engineer-role tester measured.
- **The pond's own glyphs (Oct 4).** A lasting mark is a hexagon with a lit marigold core, on the pond, in the tally,
  the card pill, the caption and the legend. A measured step carries a crosshair; a plausible step a dashed orbit.
  Lit connectors appear only for the ripple you tap, colored by what they lead to. Since Oct 5 every grade badge on a
  card carries a glyph of its own beside the word.
- **The reveal (Oct 5, owner's note).** Play from the start is an investigation: the title withholds its answer, the
  beats before the first lasting mark are numbered clues, the first mark resolves the title, a verification beat
  answers "is it real?" and brings in "It wasn't the only reason". `reveal_v1.md`.
- **Density rules (Oct 5, owner's review).** A story over ten ripples names only its marks and measured steps at rest;
  every other ripple is named on its beat, on hover or on a tap, and in the cards. No label sits under the narration
  line. A card's face is a date, a grade, a title and a spark; everything else is behind Learn more. The chooser opens
  in layers. The pond takes 1.8 of 2.8 columns on a desktop.
- **The title carries the grade.** "Stone → mark" in the title is drawn from the weakest link on the way to the mark:
  solid, dashed or dotted, with the subtitle saying it in words, and under it one editorial sentence, "It wasn't the
  only reason: …", naming the other things going on.
- **A beat per ripple (Oct 4, 08:00).** The ten-second trailer is retired: the owner called it "way too fast and not
  visually interesting enough". Playback is a schedule: the throw, then for each ripple a travel while the date rolls
  toward it and a hold while it blooms lit, its path back to the stone drawn, and a lower-third line at the foot of the
  pond says what happened in plain words with its grade (2.6 s; 4 s for a mark or a measured step; a 95-s cap shrinks
  long stories' holds). Tiger King runs 32 s, Sputnik 38 s, Prohibition 79 s. Step still walks every step. The launch
  clips are a separate edit, not a recording of this.
- **Time runs along the rings**, read against the labeled ladder; a pulse chart on each card aligns the spikes.
- **Type:** Fraunces for names and the big year; IBM Plex Sans for reading. The wordmark is lowercase *ripple*, the
  *i* the stone, rings spreading from the second *p*.
- **Depth:** tap a ripple for its card, "How sure?" in plain words and the source; "Same stone, other ponds" links
  stories that share a stone; a ripple that is itself a stone links to its own pond.
- **Quiet extras:** an opening screen on still water (skipped by any deep link), hover previews on desktop, a drop
  sound that is off by default, a share card and a share page for every featured story, "Share this step" on every
  card, a run stamp ("Checked Oct 4, 2026 with checker b0aa6fd") on every measured card.
- **On a phone (Oct 4):** the pond comes first (its top at 145 px on a 390-px phone, down from 290); the tally and the
  story chooser sit under it with the controls; the subtitle shows two lines until tapped; the caption sits over the
  pond and a tap on it puts the pond back; no two tap targets answer for each other.

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
7. **Shareable.** Done for v1: a launch kit (clips, stills, posts) in `ripples/launch/`, a share card and page per
   story, a link to any single step. Later: the ghost-stone comparison card.
8. **A verify mode.** Paste any viral "butterfly effect" claim and get it checked link by link. This already works.

## 2. Current status (one screen, 2026-10-05)

**Oct 8, studies.** 40 study-backed stories and a "Myths, checked" shelf group. Record: `docs/studies_v1.md`.

**Oct 8, second pass.** The owner found the answer view too text heavy and the guess annoying. The page now opens on
the ripple chart: the answer as the title, then one chart that plays the story row by row with one caption. Record:
`docs/ripple_chart_v1.md`.

**Oct 8 update.** Launched Oct 5 (LinkedIn, then Reddit). A Reddit visitor called the page confusing and hard to read;
the chain view (Oct 7) and then the answer view (Oct 8, now the default) followed. The answer view puts the answer one
tap away, says how we know each link in plain words, and adds a "Did you know this already?" tap, the first real
surprise label. Record: `docs/answer_view_v1.md`. The section below is the Oct 5 status.

**In one line:** not launched yet; the owner plans the public launch for Oct 6. Oct 5 turned the pond into a lake you can
read without the cards, put the cards on screen as a timeline, gave Tiger King its floor citation, fixed the launch copy,
and ran twelve pre-registered engine studies. The engine's first measured rate: about one engine mark in eight is both
surprising and believable to a simulated panel.

**The product, Oct 5 (PRs #109 to #117, #122; all live):**
- **Launch fixes (#109):** Tiger King's law hangs from a reported step, Rep. Ed Case citing the show on the House floor
  (Congressional Record, Jul 28, 2022, H7388), as the fact-check chain grades it; the 2020 House bill is an aside off the
  arrow; the law links to Public Law 117-243 on govinfo. Share links only for stories with a page (72 had 404'd). Two wrong
  citation matches skipped. Four measured steps retitled as attention. Launch copy corrected (four lasting marks in a year
  and ARPANET twelve years after Sputnik; 23 US statutes on govinfo; the 13 Wikipedia-measured grades). Executive personas
  renamed by role in every public doc.
- **The lake (#110, #111, #112, #113, #117):** the water look is the default (`?water=1` shows the old instrument pond).
  A WebGL height field under the SVG (`GLW` in `demo/index.html`) drawn in the pond's own coordinates: a wave packet pushes
  out behind the front, the splash sends its own packet, each landed ripple leaves a faint standing ring, wind waves move
  the surface, light is Fresnel reflection of a sky gradient. A dusk sky, two far ridges, a treeline and almost invisible
  clouds sit behind the date row; the shore is reflected in the water (`?scene=0` turns the scenery off). The stone sinks;
  no ring grid at rest; no sonar pulse. Reels, share cards, reduced motion and no-WebGL keep the SVG water.
- **The story on the map (#114, #115):** links stay on the water as curves styled by grade, ember into a lasting mark; the
  month rides the wave's crest; a lasting mark lights a pool of ember as it lands; one sentence at a time beside the step
  being told, and labels under it step aside; the line under the pond keeps only the clue count.
- **Layout (#116, #122):** a full-width pond; the cards run under it as a timeline, left to right in time, each as tall
  as its words, with a rail and a dot per card colored by grade; the pond's height is fitted so the first card is on
  screen at load on a 1440x800 laptop (the owner: the cards are the anchor); the tally and Change story sit on the brand
  row; the key sits under the cards and each word defines itself on hover, focus or tap.

**The engine, Oct 5 (all pre-registered; draft PRs, nothing merged into the product):**

| Study | PR | Result against its registered bar |
|---|---|---|
| Model screen v1 | #118 | Failed: precision .86, recall .56 (bar .80), 0 of 33 decoys. Most misses were undated marks; the rest were hand keeps the written definitions exclude. The owner's keeps tracked evidence (AUC .83), not surprise (.51) or novelty (.48) |
| Evidence ladder | #119 | 87 of 102 engine marks are dated records with no series. Bake Off → UK household flour measured (p .031) but fragile (4th of 11 against matched TV controls; held at reported). Frozen → Norway stays reported (negative space) |
| Time-shape and lag | #120 | Shape classes passed (87% stable under truncation). Lag priors tie a 30-day window (84.1% each). Disproportion cases flagged |
| Surprise score v1 | #121 | Failed: AUC .63 blind round, .57 pooled; .40 Spearman against the panel |
| Federal Register | #123 | 48 new stone → rule pairs, 15 standing rules, all from events; 0 of 146 cultural works; 0 of 49 decoys |
| Surprise panel v1 | #124 | Five simulated raters, 169 items; both validity checks passed. 12 of 102 engine marks and 4 of 38 catalog stories surprising and believable |

Running at the time of writing: model screen v2 (a dating step, the written definitions govern), measurable outcomes
(series catalog, matched controls and exposure gradients as the standard, CDC WONDER), live predictions and implications,
the data-day workflow, two-hop chains, baby names (outcome-first), GDELT and Media Cloud sensors, and court opinions.

**Owner rulings, Oct 5:** the written definition of a lasting mark governs (his hand keeps that break it are set aside);
he accepted the CDC WONDER data-use restrictions; no language-model API key for now (screening runs in sessions);
simulated raters stand in until real people rate after launch. New repository secrets: `MEDIACLOUD_API_KEY` (10,000
requests a week) and `COURT_LISTENER_API`; both for workflows only.

### Record before Oct 5 (2026-10-04, 19:30 UTC)

**In one line:** Ripple is a day from release (Monday morning, Oct 5, the owner's date). The owner reviewed the live page
on the morning of Oct 4 and set a new bar (pacing, look, no "AI slop"); the page now plays a beat per ripple with a
narration line, wears a flat editorial look, and opens on the pond. The same day the engine's discovery layer got its
first measured result and its first product surface: Wikipedia read as a cited-cause record recovers 62% of the
catalog's lasting marks, busts predecessors automatically, and 25 hand-screened engine-found marks now sit first under
Engine leads. The second roundtable scored the build 8.3 (the twelve) and 7.3 (three simulated strangers); after the readability pass
and the reveal, three further strangers scored it 8.0; the builder's rating is 8.3 (6.5 at pickup). Nobody outside the room has used it yet.

**What it can do today (capabilities, Oct 4):**

| Layer | Capability | Where |
|---|---|---|
| Catalog | 79 hand-built, CI-checked chains; 11 generated maps; every link graded measured / timed / reported / plausible / busted; 22 US law steps linked to the statute on govinfo | `chains/`, `maps/out/`, `demo/sources.json` |
| Verification | the checker's placebo test on every step with an attention series; the ordering rule on every step; the truncation test (0 flips) behind the run stamp; one dose-response design | `lab/chain_check.py`, `docs/truncation_v1.md` |
| Discovery, records | work → law citations from Hansard, the Congressional Record and the Federal Register, resolved to the Act or public law (638 pairs, cite_score .73) | `lab/mark_text.py`, `lab/bill_act.py`, Engine leads (acts) |
| **Discovery, Wikipedia (new Oct 4)** | the stone's article and the articles of laws and institutions that link to it, read for sentences that name a lasting change; marks dated from title and infobox; the ordering rule applied; 62% recall, 61% strict precision, 0 of 50 decoys; v1.1's enacted-thing filter at 35% forward precision on sixty held-out stones; the culture shelf's behavior lexicon at 13% on 132 cultural stones; **58 stones and 102 marks screened into the product**, including the first engine-found Disputed link | `lab/discovery/`, `demo/discovered_wiki.json`, Engine leads (wiki, `?w=`) |
| Discovery, attention | post-2015 steps checked against Wikipedia pageviews; attention leads with outcomes | `demo/discovered.json` |
| Product | the pond as an instrument; a beat per ripple (32 to 79 s a story) with a lower-third narration; Step; scrub; deep links to a story or a step; share cards and pages; the weakest-link arrow; "It wasn't the only reason" on every story including the engine-found ones | `demo/index.html` |
| Clips | reel mode plays an edited cut (12 to 15 s: open, throw, up to five shots with a push-in, an end card); nothing recorded yet | `?reel=1`, `tools/qa/reel.js`, `encode.sh` |
| QA | five browser scripts: taps, phone header, chart, pacing, plus the reel probe; a persona round protocol | `tools/qa/` |

**Latest changes (Oct 4, in order):** the `.pulse` class collision fixed (#86); the beat schedule (#87); the reel cut
(#88); the look (#89); round five and the discovery plan (#90); discovery corpus 1 (#91); the engine-found kind in the
product (#92); the desktop header fold (#93, this pass).

**Breakthroughs worth naming:** reading Wikipedia as text rather than as links turned the "structural ceiling" of the
Wikipedia route into a 62%-recall instrument; the ordering rule dated from a law's title and infobox busts predecessors
without a person (33 of 63 reverse pairs); the reverse hop is an events instrument and the forward reading a culture
instrument, which tells the next pass where to look.

**The rating trail (all testers are simulated personas; three are modeled on public executive roles and labeled so):**

| Round | Who | Before → after |
|---|---|---|
| 1 (Oct 3 night) | Dani, Priya, Walter | 4, 5, 5 |
| 2 | Marcus, Yuki, Earl | 5, 6, 6 |
| 3 | Aisha, Tom, Lena | 5, 7, 6 → 6.5, 8, 7 after fixes |
| 4 (Oct 4) | the nine returning; cloud-executive, founder, growth-executive personas | 5.4 → 7.7; 6, 5, 6; all twelve 7.2 |
| Roundtable | all twelve, Founder persona moderating | nine combined ideas, five ranked and built (`roundtable_v1.md`) |
| Final (Oct 4, 05:00) | all twelve | **8.2**, verdict release (`roundtable_final.md`) |
| 5 (Oct 4, 09:00) | the twelve, on a stranger's first ten seconds | **8.0** (`user_tests_v5.md`) |
| 6 (Oct 5) | three new strangers on the reveal build: Theo, 12; Marisol, a teacher; Kwame, a designer | **8.0** (7.3 for the previous three strangers on the build before the reveal); two fixes the same hour: statistics off the narration line, the Chromebook fold (`user_tests_v6.md`) |
| Second roundtable (Oct 4, late) | the twelve, plus Rosa, Dev and Jaz, who had never seen it | the twelve **8.3**, the three strangers 7.3, all fifteen **8.1**; verdict release Monday (`roundtable_v2.md`) |

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
| **Bill → Act resolver v3, now UK and US** | Works | UK Parliament Bills API and legislation.gov.uk: 106 bills, 78 resolved to an Act with its Royal Assent date, 76 ordered pairs (Mr Bates → Offences Act 2024, May 24; Adolescence → Children's Wellbeing and Schools Act 2026; Cathy Come Home → Homelessness Reduction Act 2017 …). **US route (GovInfo public laws):** a bill or floor-debate title resolves to the public law it became; **Tiger King → Big Cat Public Safety Act, enacted Dec 20, 2022, cited as a reason on Jul 28, 2022** is the first engine-found US work → law pair with a date; a short title enacted inside a larger law resolves to that law, named as such. Hearings, resolutions and appropriations are skipped |
| **Mark-text v1.3 (US collections)** | Done; v1.3.2 re-screen running | 638 pairs: Hansard 526, Congressional Record and hearings 96, Federal Register 16. US finds: Tiger King → Big Cat Act debate; Silent Spring → Clean Water Act and TSCA hearings, the Rachel Carson trail bills, the Travel Promotion Act debate; The Jungle → the 1995 HACCP rule; Blackfish → National Orca Protection Month; Unsafe at Any Speed across 25 years of auto-safety hearings. A "WarGames → NDAA" pair reported at first was the word, not the film ("operational exercises, wargames, and table-top exercises"): US records say "program" and "show" about everything, so an ambiguous title there now needs a word that can only mean the work |
| **The citation screen (cite_score v1)** | Works; a transparent floor | A rule scorer labels each citation *reason* / *context* / *aside* from causal words, the clause's subject, a change word, argument form and illustration markers; against the owner's 22 hand grades: precision .73, recall .89. Resolver output carries the score and its reasons; the demo rates an act lead *reported* only when cited as a reason, and prints why. Labels today: 24 reason, 13 context, 43 aside |
| **Dose-response (evidence ladder, rung 3)** | One result, a real negative | Pre-registered design (`ripples/docs/dose_response_v1.md`): states that opened retail cannabis (20) against states that never did (31), change in past-30-day drinking from the last survey before to the second after, 2,000 random assignments for p, pre-trend placebo. The youth outcome (YRBS) could not run: state tables end in 2017 and CO and WA do not take part. Adults 18–24 (BRFSS, annual): −1.2 points against controls, p = 0.10, pre-trend flat (p = 0.34): within chance. All adults −0.4, p = 0.29. The "cannabis replaced drinking" catalyst fails the first rung above timing |
| **Attention checks for every post-2015 step** | Works | 105 dated steps since Aug 2015 had no placebo test of their own. The checker finds each step's Wikipedia article (a strict search on the full claim, or a `wiki` hint the chain author names) and runs the measured-step test at the step's date. With 44 hints: 72 steps take the test; 13 rose beyond chance (Paula Vennells at the petition, 1,708×, p = .006; the Post Office scandal at the law's announcement, 354×; Trigger law at Dobbs, 166×; the Chernobyl Exclusion Zone at the bookings surge, 28×; Adnan Syed at the vacated conviction, 25×; SK Broadband at its suit, 26×; GDPR on its first day, 8.9×; Bottom trawling at the consultation, 4.5×; Alcohol and cancer at the advisory, 4.2× …), 5 within chance, 20 no rise, 11 articles created at the date, 7 rose without placebo history, 33 no article. The step's level does not change; the card shows the result |
| Discovery: the Wikipedia route (mark-first v1, v1.1) | Ran three times; rule failed on recall, passed on new pairs | 13,371 laws × 289,960 works; recall 2 of 5 (two recall laws have no article of their own); new pairs: 60 Minutes → STOCK Act, Quincy → Orphan Drug Act, Victim → Sexual Offences Act 1967, The Daily Show → Zadroga Act, The West Wing → Racial and Religious Hatred Act 2006, JFK (film) → JFK Records Act 1992, Silent Spring → NEPA, Holy Deadlock → Matrimonial Causes Act 1937. Now secondary; read by hand |
| **The first blind round** | Done | 15 names to the owner: 14 interesting, 4 strictly non-obvious (Victim, The Daily Show, Ocean, Manhunt) and 9 "medium", 13 worth chasing. Left out: Rangila Rasul, Holy Deadlock |
| **Maps that end in a law** | 12 new chains (batches 13–15) | Mr Bates → Offences Act 2024; Cathy Come Home → Housing (Homeless Persons) Act 1977; Quincy → Orphan Drug Act; My Octopus Teacher → Sentience Act 2022; 60 Minutes → STOCK Act; Victim → Sexual Offences Act 1967; The Daily Show → Zadroga Act 2011 and the 2019 fund; Manhunt → Byron Review → Digital Economy Act 2010 and statutory PEGI; The West Wing → the 2006 defeat; Silent Spring → EPA and the DDT ban; Ocean with David Attenborough → the trawling consultation (no mark yet; measured 4.1× attention, p = 0.004); **Prohibition → a century of American drinking** (22 steps, 1920–2025) |
| The Prohibition throughline (owner's long-horizon test) | Built; 26 steps, every rung tried | Crime, repeal, drinking's return and the cirrhosis peak, AA and NIAAA, the teen decline (MTF: 72% → 50% → 29%), young adults (Gallup; BRFSS 18–24: 55.5% → 46.0%, 2011–2025), NIAAA per-capita ethanol 1970–2022. Each popular catalyst for the Gen Z decline is a dated step: the claim that it *started* the decline is busted by order against the 1980 onset; legal cannabis fails the dose-response test (within chance); Dry January's January surge is within chance against other Januaries; the Surgeon General's advisory is the one **measured** step (attention to alcohol and cancer 4.2×, p = .035). 17 reported, 4 busted by order, 2 within chance, 1 measured |
| Engine leads in the demo | Two kinds | Attention leads (18 qualified, 6 with outcomes) and **the legislature's citations**: every Act or public law whose debate named a work, one pond per work (Cathy Come Home, Mr Bates, Silent Spring, Adolescence; Tiger King → the Big Cat Public Safety Act from the Congressional Record), with the sentence and links to Hansard or the Record and to legislation.gov.uk or govinfo.gov |
| Two-hop discovery from attention | Not pursued further | Attention second hops found siblings and curiosity; records are the route |
| **Round four and the roundtable (Oct 4)** | Live (PRs #79, #80) | Nine returning testers re-rated the build: 5.4 → 7.7 on average, every one higher; three new simulated executive-role personas (6, 5, 6) asked about reproducibility, engineering cost and the growth loop. A simulated roundtable of all twelve produced nine combined ideas and ranked five (`roundtable_v1.md`). Built the same day: the ten-second trailer (autoplay blooms the marks and measured steps; the rest land quiet), the title's arrow drawn from the weakest link, share-a-step links and `?s=` deep links, a trend's card naming the claims made about it, a proper Not-yet style, Step as a button, run stamps on measured cards. The truncation test (`truncation_v1.md`) ran in CI: 13 measured grades, 0 flips at three cutoffs; the placebo pool is fixed before the step, so grades do not drift. Also fixed: the tap target (the render loop had been shrinking it every frame), the phone caption overlay, deep links opening on the intro, tabs that navigated, idle redraws |
| **Pre-post review fixes (Oct 4, 21:30 UTC)** | Live (PRs #105 to #107) | A second reviewer's two passes on the live page, each claim verified before the fix: a load-order bug that painted one mark over the whole pond (label scale clamped, pond redrawn on a real width change); phone labels colliding and the phone narration moving the controls (dropped when not free; a fixed slot); the corner legend over the rim on short laptops (under the controls); grade counts shown before the reveal (hidden while the answer is withheld); the stone resting on the bank outside the pond (thrown from the rim, on the water); the verification beat ending in an ellipsis (two lines, verdict last); the story ending on "the link is unproven" (an end beat: what stayed, and a Next stone button); rim words under a label (step back). Checked and not possible: no story in the catalog ends on a Measured lasting mark, since marks are laws and institutions and a citation is reported, never measured; Tiger King stays the opener |
| **Engagement instruments and protocol (Oct 5, 07:30 UTC)** | Live (PR #104) | The owner asked for engagement, fall-off, confusion and stickiness to be measured. Thirteen aggregate events to the site's GA4 property (story start with how it was chosen, reveal, verify, complete, play/pause, tap, learn more, chooser and kind, share, cite, step, scrub) and a leave signal carrying the clock position and whether the reveal was reached; nothing personal, nothing from files, cards, reels or QA runs. `engagement_protocol_v1.md` fixes the questions, the readings and the thresholds per 100 starts before any visitor, and names three mechanics to test after the first data (a guess before the reveal, a next stone on the end card, Surprise me) |
| **Round six (Oct 5, 06:30 UTC)** | Live (PR #103) | Three new strangers on the reveal build averaged 8.0 (the previous three, 7.3). Theo, 12, found the question-and-clues structure and the reveal "cool" and the narration long: p-values and placebo counts now stay on the card, the verification line is one sentence per grade, lines average 27 words. Marisol's classroom Chromebook (1366×768) cut off the pond: the short-screen rule now reaches 820 px (pond's foot 694, legend 435). Kwame's design bar passed (1.9:1, glyphs on every badge, the resolve animation) with one note: nine identical Learn more buttons. `user_tests_v6.md` |
| **The reveal: an investigation, not a results page (Oct 5, 05:00 UTC)** | Live (PR #101) | The owner's note: catalyst → suspicion → clue → reveal → verification → consequence. While a story with a mark plays from the start, the title is "Tiger King → ?", the tally "? lasting marks", the subtitle "Something changed after this. Follow the water."; ordinary beats are numbered clues and the promise line does not name the mark; the first mark's beat resolves the title (the arrow draws, the answer fades in, a chime if sound is on); a verification beat follows with the order check, the weakest link and "It wasn't the only reason". Deep links, rest, pause, scrub, Step and a tap show everything. Reel clips carry the same suspense and were re-recorded. `reveal_v1.md` |
| **The owner's readability pass (Oct 5, 03:30 UTC)** | Live (PR #100) | The owner played the demo and sent screenshots: labels piled up on long stories and under the narration, the pond too small for its column, the cards text-heavy, the chooser overwhelming, and the spikes chart worth keeping in view. Built: a long story (over ten ripples) names only its marks and measured steps at rest, the rest on their beat, hover or tap; labels under the lower third step aside; the pond column is 1.8× the cards (1.45× under 1200 px) with a tighter frame, the pond 1,087 px wide at 1920 (was about 760); the spikes chart is sticky above the cards and each series draws in as its ripple lands; a card's face is a date, a grade with a glyph, a title and a spark, the rest behind Learn more; Change story is a marigold button and the chooser opens in layers (six you know, search, three kinds as cards with counts; a kind's list only on a click). Prohibition mid-beat: 4 labels, 0 overlaps, 0 under the narration (was about 20 labels with overlaps). Share cards regenerated. |
| **The second roundtable's feedback, built (Oct 5, 01:30 UTC)** | Live (PR #98) | Every item from the fifteen: the beats before the first lasting mark run tighter and the narration promises the mark from the first beat (first mark 17 → 15 s on a phone, promise at 2 s); the Engine leads shelf grouped by source and decade; the legend as a corner panel inside a 614-px fold; the caption in flow under a small pond; Copy citation on every engine card; one grade map for the engine kind; the checker on main and weekly; fifty famous films as decoys (8% loose, 0% strict). `roundtable_v2.md`, actions table; `tools/qa/fold_test.js` |
| **The culture shelf (Oct 4, 23:30 UTC)** | Live (PR #96) | The owner's ask: recognizable pop-culture and behavioral stones. 132 cultural stones read forward with a behavior lexicon (sales, tourism, names, recruitment, membership …): 234 sentences, about 30 real marks across 22 stones (13%), 9 non-obvious (Sideways → Merlot down and Pinot up; Bake Off → baking sales; Furby → the NSA ban; Jurassic Park → the Raptors; Blue Planet II → marine biology applications; An Inconvenient Truth → carbon offsets near theaters). Top Gun's 500% recruitment claim shown as Disputed; Vietnam's Barbie ban busted by order (before release). 22 stones and 25 marks added: 58 stones, 102 marks under Engine leads. `discovery_culture_v1.md` |
| **Discovery v1.1 (Oct 4, 21:30 UTC)** | Live (PR #95) | Sixty more stones under the enacted-thing filter: 15 reverse pairs (9 real), 198 forward sentences (about 70 real, 35%), 51 unique marks, 14 non-obvious (Enron → tax code 409A; MeToo → Indonesia's Sexual Violence Crime Act; the Camp Fire → AB 1054; Dear Zachary → Bill C-464). 22 stones and 52 marks added to the product, every date verified: 36 stones, 77 marks under Engine leads. Films stay thin; events are rich. `discovery_corpus1_v1_1.md` |
| **The engine-found pairs in the product (Oct 4, 18:30 UTC)** | Live (PR #92) | A fourth story kind, `wiki`: 14 stones, 25 hand-screened marks from the Wikipedia cited-cause run, first under Engine leads. Every link reported, with the sentence, the article and section it came from, and a date verified against the mark's article (two held to month or year precision where the article carries no day). Each stone has its own "It wasn't the only reason" line. `?w=<slug>` deep links; "Same stone, another pond" ties them to the catalog's chains. Release set for Monday morning Oct 5 |
| **Discovery, corpus 1 (Oct 4, 11:00 to 16:30 UTC)** | First result under `discovery_plan_v2.md`; bar not met | Wikipedia read as a cited-cause record. Forward (the stone's own article minus plot and production) plus the reverse hop (law-titled articles that link to the stone, read for the sentence naming it): 62% recall of 91 in-class marks, 22 of 43 stones complete. Strict reverse rule after the ordering rule: 23 unique pairs, 14 real cited marks (61%), 3 wrong; 0 of 50 decoys. Held-out 20 stones: the reverse hop finds only events (Deepwater Horizon, 2 of 2), nothing for films; the forward reading is a 26% candidate generator on both sets and found eleven marks the catalog lacks. The ordering rule busted 33 of 63 reverse pairs automatically. Namesake statutes: 93, 29 name their cause. Federal Register 404 and EDGAR 403 stopped those hosts for the day. `discovery_corpus1_v1.md` |
| **The owner's review of the live page (Oct 4, 07:00 UTC)** | Four PRs (#86 the chart bug, #87 the beat schedule, #88 the reel cut, #89 the look); a persona round on the stranger's first ten seconds and the clips next | The chart above the cards and the pond's ring shared the class `.pulse`, so the chart ran the ring's 7-s scale-and-fade and ballooned 7.5× over the pond (ghost text through the paper, a gray slab on the water); fixed, with `tools/qa/chart_test.js`. The ten-second trailer replaced by a beat schedule with a narration line (`pace_test.js`: 32 / 38 / 79 s, no two beats under 3 s apart). The owner's direction: the clips cannot run that long (cuts, zooms, "videographer stylistics"); the look must stop reading as a cartoony wireframe before strangers see it. Builder's rating on pickup: 6.5 |
| **The three fixes before release (Oct 4, 05:50 UTC)** | Live (PR #82) | The phone's first screen: the tally and the story chooser move under the pond, the pond's top falls from 290 to 145 px on a 390-px phone; twenty-two US law steps link to the statute on govinfo, each confirmed against the PDF; one editorial "It wasn't the only reason" sentence per story in `demo/context.json`, shown under the title and carried in the share text. Final roundtable: 8.2 average, verdict release. See `final_three_v1.md`. |
| **The night of Oct 3–4: three persona rounds, the pond as an instrument, the US catalog** | Live (PRs #74–#78) | Round one (Dani, Priya, Walter) closed in PR #74; round two (Marcus, Yuki, Earl: 5, 6, 6) closed in PRs #75–#76; round three (Aisha the data journalist, Tom the retired machinist, Lena the student: 5, 7, 6 before fixes; 6.5, 8, 7 on the first re-test) drove the last pass. What changed: the pond redrawn as an instrument (a flat field, a labeled log time grid, a matte stone, grade in stroke weight and pattern, a marker and a dated label on every ripple, diamonds for marks, labels that place marks first and may sit over a rim word rather than vanish); the spikes chart above the cards (every attention series aligned at its own step, log y, the checker's baseline, a palette with none of the grade hues); real source links or none (190 record links across 41 chains, the source line on the card's face, engine-found cards linking their article and the pageviews tool); twelve US chains first in the catalog (The Jungle, the Triangle fire, the Dust Bowl, Sputnik, Unsafe at Any Speed, the Cuyahoga fire, Love Canal, Three Mile Island, the Exxon Valdez, the hot-coffee case, Columbine, Flint; 115 steps, every busted claim by design, checked in CI); honest p wording at the floor; "What followed and stayed … order, not proof of cause" under the title; Step mode fixed twice; touch drag fixed; a phone caption and a way back to the pond. Reports verbatim: `user_tests_v1.md`, `user_tests_v2.md`, `user_tests_v3.md` |
| **The demo after the first persona round (PR #74, merged 00:10 UTC)** | Live | One wavefront leaves the stone and moves outward; each ripple blooms where the front is when it happens and stays, so no ripple passes another (the owner's "inner ripples surpass outer ripples" complaint). The stone is thrown from the near bank (drag and release to throw it yourself), lands with a splash and a sound. Header is one bar; the chooser panel holds a "start with one you know" row, tabs and a search box across all tabs. A **Step** button stops the clock at each ripple with its card open. Every card's source line ends in a link (the article or series read, the methods page, or a Wikipedia search for a named record). Labels have a floor in screen pixels on tablets and phones. Three persona reports, verbatim, with an actions table every row of which is now closed: `ripples/docs/user_tests_v1.md`. A second round with three new personas (a 24-year-old warehouse worker on an Android phone; a 42-year-old history teacher on a projector and Chromebooks; a 58-year-old colorblind dispatcher on a 1366×768 laptop at 125%) is running |
| The demo | Live as Ripple | Isometric pond that is the page; a mossy stone; each outcome its own living ripple with a crest; pebbles for lasting marks; paper feed; wordmark and opening screen; two-tone icons; share cards and share pages; "Same stone, other ponds" (PRs #57–#65 and today's branch). Labels now place by priority, keep clear of the rim words, wrap to two lines, and wait for a hover when a pond is crowded, so a 17-ripple century and an 18-Act map read cleanly. Cards explain dose-response steps and carry the attention check. Awaiting the owner's review |

**Since Oct 4, 00:30 (all live on main):**
- **Round two and three fixes** (PRs #75–#78): the pond as an instrument (rings, ladder, matte stone, vignette, one
  pulse every seven seconds), label priority and the text floor, the 44-px tap target, the phone caption over the pond,
  the pulse chart aligned at each step, deep links that skip the intro, the run stamp.
- **The US catalog (batch 16):** twelve US chains from The Jungle to Flint, 185 then 186 source links verified live
  against Wikipedia and the statutes (`sources_pass_v1.md`).
- **Round four** (PR #79): the nine returning testers and three executive-role personas; `user_tests_v4.md`.
- **The roundtable's five ideas** (PR #80): the ten-second trailer, the weakest-link arrow in the title, share a step,
  the run stamp gated on the truncation test (13 measured grades, 3 cutoffs, 0 flips; `truncation_v1.md`), Step
  follows the argument (the claims line on the trend card). Also the water's atmosphere (caustics, vignette, pulse).
- **The pond's glyphs and exclusive taps** (PR #81): hexagon, crosshair and dashed orbit; a tap goes to the nearest
  ripple; the final roundtable; `data_sources_v2.md` (thirteen candidate APIs ranked; all blocked from the container).
- **The three fixes before release** (PR #82): the phone's first screen, the statutes on govinfo, "It wasn't the only
  reason" (`final_three_v1.md`).
- **Launch kit v2** (this pass): re-cut on the release build, with vertical clips for the first time.

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
- **17:00–18:00:** mark-text v1.3's US records read; the US bill → law route and the first US law pair; the stone and
  the pebbles sit in the water.
- **20:00–00:30 (Oct 4):** ocean palette, the lake scene, ripple height and splash; the portable review kit; the
  one-bar header; the first persona round and its fixes (the thrown stone, the wavefront, the scaled clock, phone
  taps, the must-precede rule for catalyst claims); then the open items closed (Step mode, search, source links,
  the text floor). PRs #66–#74 merged.

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
- **Wikipedia's own sentences are a cited-cause record too (Oct 4 evening).** Reading the stone's article as text, not
  links, recovers over half the catalog's marks; the reverse hop to law-titled articles works for events and not for
  films; the ordering rule dated from title and infobox busts predecessors without a person. `discovery_corpus1_v1.md`.
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

**New since Oct 4 (the persona rounds and the release pass):**
- **Verify each persona's own item in the browser before the persona speaks.** The final roundtable's one real find
  (tap targets swallowing their neighbors) came from a measurement, not an opinion. Opinions converged; measurements
  disagreed with them.
- **A tap target's size is not its exclusivity.** 44 px held everywhere and three of eleven taps still went to the
  neighbor on a dense pond. The fix is a nearest-center rule, not a bigger circle.
- **The phone's first screen is a budget.** Header pixels above the pond are the single number the growth-role
  persona watched; moving the tally and the chooser under the pond halved it without losing anything.
- **Drift was a question to settle, not to design around.** The truncation test (0 flips at three cutoffs) made the
  "grade with a history" UI unnecessary; the run stamp is a constant, not a disclaimer.
- **Say what else was going on.** One editorial sentence under the title does more for honesty than any grade color;
  it is also the line a journalist or teacher quotes.
- **The statute beats the article.** govinfo's link service resolves a Statutes at Large cite to the page scan for
  every volume back to 1789; public-law links work only from the 104th Congress. Scans before 1951 have no readable
  text layer, so confirm those by granule boundary and say so.
- **Decoration is the first thing testers cut.** Glass buttons, torn paper and photographic water were all proposed
  and all declined by the same testers who asked for the rigor to show; the icon system was the one thing taken.
- **Simulated executives are useful and must stay labeled.** The three persona reviews asked the reproducibility,
  frame-budget and growth-loop questions no fictional tester asked; every mention names the role ("a cloud-platform executive"), never a real person.

**New since Oct 5:**
- **Laws can be verified, not measured.** 87 of 102 engine marks are dated records. Measured discoveries need outcomes
  that are series: names, travel, health, enrollment, spending. That is where the engine has to hunt.
- **The hand screen selected for evidence, not surprise.** Surprise has to be its own label and its own objective.
- **Public structure is a poor proxy for surprise.** Wikipedia links make famous stories look connected and obscure ones
  look surprising; the score failed twice.
- **Matched controls kill fragile wins.** Bake Off's flour rise passed the placebo test and ranked 4th of 11 against
  similar shows.
- **Records find events, not culture.** Hansard, the Congressional Record and the Federal Register cite disasters and
  rulings; works of culture appear as asides.
- **A planted control set is cheap and decisive.** Ten obvious and ten invented pairs showed the panel could tell the
  difference before any of its ratings were used.

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

**Browser and phone (Oct 4)**
- **One class name, two elements, two stylesheets' worth of meaning.** The paper chart above the cards and the pond's
  expanding ring were both `.pulse`; the ring's `animation: pulse 7s` (scale .3 → 7.5, fade) applied to the chart too,
  which ballooned 7.5× over the pond every seven seconds as ghost text and a gray slab. Found by the owner on the live
  page the morning after release-ready; four tester rounds in headless Chromium had sampled between the beats. The ring
  is `.wake` now and `tools/qa/chart_test.js` samples six times across the cycle. Grep a new class name across the
  whole file before using it; the pond's SVG and the paper's HTML share one stylesheet.
- **A phone caption over the pond absorbs every later tap.** The tap test read "all taps go to the first ripple" until
  the test dismissed the caption; a tap on the caption body now clears it. Test harnesses must clear state between taps.
- **An SVG `<text>` has no `offsetTop`.** Position overlays from `getBoundingClientRect`, and measure a hidden element
  only after `display:block`.
- **A render loop that resets an attribute each frame** (the halo radius) silently undoes a one-time size; give the
  tap target its own element.
- **`quantized time` can skip a stop:** hold the goal on the story (`cur.goal`) instead of recomputing from `t`.
- **Unicode glyphs are not portable** (U+2B22 hexagon); draw the mark inline as SVG.
- **Patch scripts that assert before writing** fail safely but silently; print what was replaced.

**The lake (Oct 5)**
- An SVG element has no `offsetTop`; measure it with `getBoundingClientRect` against its panel. The first canvas lined up
  only by accident and later drew 0 px tall.
- GLSL `smoothstep` with edge0 greater than edge1 is undefined: it zeroed the whole image. Write `1.-smoothstep(a,b,x)`.
- Headless Chromium on SwiftShader can drop a shader effect a real GPU shows (the ember pool). Confirm GL looks in a real
  browser; the Browser pane pauses animation when hidden.
- `maps/out/*.json` is rebuilt by the maps workflow from `maps/<slug>.json`: edit the source, and keep record steps in
  date order or the builder marks them excluded.
- A wide, height-limited pond letterboxes its viewBox: label sizes must follow the drawn scale, not the box width.

**govinfo (Oct 4)**
- `link/statute/{vol}/{page}` redirects to the granule PDF; `link/plaw` returns 400 before the 104th Congress; the
  metadata (`mods.xml`) route returns 500 for old granules; `api.govinfo.gov` with the shared demo key is rate-limited
  (429). The project's `DATA_GOV_KEY` is a GitHub secret and may only be used from a workflow.

## 5. Blockers and bottlenecks (2026-10-05)

**Blockers**
1. **No strangers yet.** The public launch is planned for Oct 6. Everything below is smaller than this.
2. **The clips predate the lake and the reveal fix.** The owner chose to wait while the UI settles; the posts' clip
   attachments must be re-cut before they are used.
3. **The engine verifies far more than it measures.** Laws are records; a measured mark needs a series, matched controls
   and, where possible, an exposure gradient.
4. **Surprise has no human labels.** The simulated panel is a proxy; real raters after launch replace it.

**Bottlenecks**
1. Hosts stopped Oct 5 under the rules: UN Comtrade (400), UCAS (404), Hansard (500 on one call), Wikipedia search (429),
   the Federal Register (429). The data-day workflow resumes them on later days.
2. CourtListener's daily cap (account limits) spreads the court search over several days.
3. No language-model key: the screen runs in sessions, not on a schedule.

## 6. Immediate next steps (in order)

1. **Launch (Oct 6):** the four pre-flight checks in `docs/launch_v2.md`; post from `launch/posts_ready.txt` (the clips
   are stale: post without them or re-cut them); reply to every substantive comment with the story's share page.
2. **Real raters:** put the panel's 169 items in front of people after launch; replace the simulated labels.
3. **Engine:** review each running study's draft PR against its registered bar; merge the studies' docs and data (failures
   included); wire into the product only what passed, with no new UI: a measured grade, a new story under Engine leads.
4. **Measurable hunting:** the series catalog with exposure gradients and matched controls as the standard; the
   outcome-first scans (names, CDC WONDER, park visits) on the highest-power series.
5. **Surprise v2:** train and test against the panel labels; rank leads by evidence first, surprise second.
6. **Live mode:** score the registered predictions as they come due; they are the strongest evidence the engine can make.

## 6a. Open questions (2026-10-04, 06:30 UTC)

- Which of the four release dimensions lands first, and does any land at all? The estimate is about 70% for at least
  one.
- How often is a parliamentary citation a cause rather than an illustration? cite_score v1 is calibrated on 22 grades;
  a second blind round should be scored against it.
- Dose-response: the cannabis catalyst is within chance. Is the Gen Z decline over-determined, or is the exposure that
  matters not state-shaped?
- Should the "It wasn't the only reason" line ever be generated (from the records, from the engine's own second
  stones) rather than written? Today it is editorial by design.
- Is a reported-only map worth leading a tab, or should every lead carry at least one measured ripple?
- Where is the line between "the engine found it" and "we assembled it" in the product's own words?
- Do real raters agree with the simulated panel's one-in-eight? If they find more surprise, the panel was too
  knowledgeable; if less, the engine's culture shelf is weaker than it looks.

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
- Simulated testers are simulated and say so. A persona is named by role, never by a real person.
- No model identifiers in commits, pull requests, code comments or any pushed artifact.
- No Google billing. The private `RIPPLE_MAP_CONTEXT.md` in the session scratchpad is never committed.
- Domains are reached only when the owner has whitelisted them; a 403, 429 or 503 is a stop, never a retry with a
  different user agent.
- The statute outranks the article: a law step links to the law itself where a confirmed link exists.
