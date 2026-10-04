# Ripple: handoff for a new session (Oct 4, 2026)

This is the runbook for picking Ripple up in a fresh chat on any machine, cloud or not. It says what the product is,
what the technical approach is, where everything lives, how to build, test and ship, the rules that never change, where
the work stands, and what to do next, in order. The companion brief, `docs/ripple_Map_context.md`, holds the vision in
the owner's words, the full status table, the learnings and the pitfalls; read it second. `docs/REVIEW_GUIDE.md` is the
map for an outside reviewer. The previous handoff (Sep 27, the attention engine in Supabase) is archived at
`docs/archive/handoff_2026-09-27.md`; that generation of the product is parked and nothing below depends on it.

Everything here is portable: the demo is one HTML file with no framework and no server, the data is JSON in the
repository, the fetchers run on GitHub Actions, and the browser checks, cards and clips are scripts in `tools/qa/`.

---

## 1. What Ripple is

**Live:** https://bensunter.com/ripples/demo/ (GitHub Pages from `main`). **Repo:** `bsunter93/Ben-Sunters-Website`,
everything under `ripples/`.

You throw a stone (a show, a film, a disaster, a discovery) into a pond. The ripples spread out in time; each one is
something that changed afterward, placed where it began. Every link is graded for how sure we can honestly be:

| Grade | Meaning | How it is earned |
|---|---|---|
| **measured** | a sustained rise in a data series that began after the step before it | the checker's placebo test: the rise after the step beats the same test run at random dates in that series' own past (an empirical p-value), and the order holds |
| **timed** | right order, not tested against chance | dated steps in order |
| **reported** | a credible source makes the link | for laws, usually the debate itself: a Congressional Record or Hansard sentence that names the work |
| **plausible** | it happened; the link is unproven | a dated step with no source for the link |
| **busted** | it started before its supposed cause, or there is no evidence it happened | the ordering rule, or a failed record check |

A ripple's payoff is a **lasting mark**: a law, an institution, infrastructure, jobs, public health, a durable change in
behavior. Attention, growth and crazes are intermediate steps, never the endpoint. The title's arrow ("Tiger King → the
Big Cat Act") is drawn from the weakest link on the path to the mark (solid, dashed or dotted), the subtitle says it in
words, and under it one editorial sentence, "It wasn't the only reason: …", names the other things going on. Timing
shows order, not proof of cause, and the product says so three ways.

**The owner's vision, verbatim core:** "The entire point of the app is uncovering hidden impacts from upstream events,
regardless of where that impact shows up. Attribution and traceability with statistical rigor are key." Obvious links
are worthless; one shock has many outcomes; resilience is a finding; it must work for a 12-year-old with the statistics
one click deeper; serious and beautiful, not cartoony; honest confidence beats sparse certainty. The full statement and
its history are in the brief, sections 1 to 1c.

## 2. The technical approach, in one page

1. **Chains are data.** `chains/batch*.json` holds 79 stories. Each step has a claim, a date, a source line, a `test`
   (`wiki` daily pageviews, `fred`, `ssa`, `stackex`, `zillow`, `arxiv`, `file` for an official series, `dose` for the
   one dose-response design, `record` for a dated fact, `none`), optional `wiki` hints naming the exact article, an
   optional `mark` (the kind of lasting mark), `must_precede` for catalyst claims, and `slice` for the pond's sectors.
   `maps/out/*.json` holds 11 generated maps (a stone, its attention and library steps, and the law where there is one).
   The look since Oct 4 10:30 is recorded in `docs/styling_pass_v2.md`; where section 1b-ii of the brief or the bullets
   below describe gradients, a vignette, rim capitals, label boxes or an opening screen, that record wins.
2. **The checker grades every step.** `lab/chain_check.py` runs on GitHub Actions (`.github/workflows/ripples-chain-check.yml`,
   on pushes to `claude/**` and `main` that touch chains or the checker, weekly on Monday 06:17 UTC, and by `workflow_dispatch`) and commits
   `docs/results/chain_check_v1.json` back. A measured grade is a placebo test whose windows are drawn from the page's
   history *before* the step, so a grade does not drift as time passes; the truncation test (`lab/truncation_test.py`,
   `docs/truncation_v1.md`: 13 measured grades, 3 cutoffs, 0 flips) established that, and every measured card carries
   the run date and checker commit.
3. **The ordering rule falsifies.** Every step must be an outcome in its own data and later than the step before it. A
   claimed catalyst that arrives after the trend it is said to start is busted and shown as such (Prohibition's
   smartphone, Dry January and cannabis claims).
4. **The records route finds marks.** `lab/mark_text.py` reads every Hansard contribution, Federal Register rule and
   Congressional Record item that names a work; `lab/bill_act.py` resolves the bill to the Act or public law it became;
   `lab/cite_score.py` labels each citation reason / context / aside (precision .73 on the first hand-graded set). A
   person still screens the finds. A citation is a reported link, never measured.
5. **Sources are verified, and the statute outranks the article.** `tools/build_sources.py` builds `demo/sources.json`
   from the chains' `wiki` hints, a curated list, and `STATUTE` / `PLAW` tables that link US law steps to govinfo's page
   scan; every statute link was confirmed against the PDF (`docs/sources_pass_v1.md`, `tools/qa/statutes.py`).
6. **Context is editorial.** `demo/context.json` holds one "It wasn't the only reason" sentence per story, keyed
   `kind:slug`. It is written to be checkable, kept in one file, and never generated.
7. **The demo is one file.** `demo/index.html`: HTML, CSS and JS, no framework. It fetches `docs/results/chain_check_v1.json`,
   `demo/discovered.json`, `docs/results/bill_act_v1.json`, `demo/sources.json`, `demo/context.json` and the maps. The
   pond is an SVG instrument: one wavefront, hairline rings labeled 1 day / 1 month / 1 year / 10 years, a matte stone,
   a hexagon with a lit core for a mark, a crosshair for measured, a dashed orbit for plausible. Playback is a beat
   schedule (`BEAT`, `makeTimeline`): a throw, then for every ripple a travel while the date rolls and a hold while it
   blooms lit with a narration line at the foot of the pond (2.6 s; 4 s for a mark or a measured step; holds shrink to
   fit a 95-s cap), then a short run-out. Tiger King runs about 32 s, Sputnik 38 s, Prohibition 79 s. The ten-second
   trailer was retired on Oct 4 at the owner's direction ("way too fast"). Since Oct 5 play from the start is an
   investigation (`setMystery`, the verification beat; `docs/reveal_v1.md`). Step walks every step;
   deep links `?c=<slug>`, `?m=<slug>`, `?e=<slug>`, `?a=<work>` skip the intro; `&s=<step>` opens on one ripple, stopped;
   `&card=1` renders the 1200×630 share card; `&reel=1` plays stories back to back for recording; `&nointro=1` for tests.
8. **Portable builds.** `tools/build_portable.py` inlines the fonts and every data file into `dist/ripple-standalone.html`
   (opens from a laptop with no server) and zips a review kit. The QA scripts test that file by default.

## 3. Where things live

| Path | What |
|---|---|
| `demo/index.html` | the product |
| `demo/context.json`, `demo/sources.json`, `demo/discovered.json`, `demo/discovered_wiki.json` | editorial context, verified links, attention leads, the Wikipedia cited-cause pairs (Oct 4; 58 stones, 102 marks; `?w=<slug>`; a mark may carry `grade: disputed` and a `note`) |
| `demo/cards/*.png`, `demo/s/<slug>/index.html` | share cards and share pages (generated by `tools/qa/cards.js`) |
| `chains/batch1..16.json` | the 79 chains (batch 16 is the US history set: The Jungle to Flint) |
| `maps/out/*.json` | the 11 generated maps |
| `lab/` | the checker, the records route, the resolver, the citation screen, the truncation test; `lab/discovery/` the Wikipedia cited-cause scripts of Oct 4 |
| `docs/results/` | CI-written results (`chain_check_v1.json`, `bill_act_v1.json`, `truncation_v1.json`, …) |
| `docs/ripple_Map_context.md` | the brief: vision, status, rating trail, learnings, pitfalls, rules |
| `docs/user_tests_v1..v4.md`, `docs/roundtable_v1.md`, `docs/roundtable_final.md` | the five simulated-tester rounds |
| `docs/final_three_v1.md`, `docs/styling_pass_v1.md`, `docs/sources_pass_v1.md`, `docs/data_sources_v2.md`, `docs/truncation_v1.md` | the release-pass records |
| `docs/launch_v2.md`, `launch/` | the launch kit: clips, stills, posts, emails, posting order |
| `docs/REVIEW_GUIDE.md` | the map for an outside reviewer |
| `docs/archive/` | superseded docs (the Sep 27 handoff, launch v1) |
| `tools/build_portable.py`, `tools/build_sources.py` | the builds |
| `tools/qa/` | browser checks, cards, reels, encoder, statute confirmation (section 5) |
| `.github/workflows/ripples-*.yml` | every fetcher and checker; they commit results back to the branch |
| `methods/`, `discover/` | the public methods page and every test's evidence |

## 4. Setting up on a new machine

```
git clone https://github.com/bsunter93/Ben-Sunters-Website.git
cd Ben-Sunters-Website
python3 --version            # 3.10+; the build scripts use only the standard library
cd ripples/tools/qa && npm install && cd -     # Playwright (downloads Chromium) and ffmpeg for the QA scripts
python3 ripples/tools/build_portable.py        # -> ripples/dist/ripple-standalone.html and the review kit zip
```

Open `ripples/dist/ripple-standalone.html` in a browser, or serve the repository root (`python3 -m http.server 8000`)
and open `http://localhost:8000/ripples/demo/`. No database, no keys and no account are needed for the demo, the
builds or the QA scripts.

Keys: the only secret the project uses is `DATA_GOV_KEY` (govinfo and the Congressional Record), and it lives in
GitHub Actions secrets, used by workflows only. Never put it in a local environment file that could be committed.

Differences from the cloud session this handoff comes from: the cloud container could reach only whitelisted hosts
(Wikipedia, legislation.gov.uk, govinfo's link service, pageviews.wmcloud.org) and nothing else, so fetchers ran in
Actions. A local machine can reach everything, which changes nothing about the rules: the honest user agent, one request
a second, a stop on any 4xx/5xx, no retries with a different agent, aggregate data only.

## 5. Build, test, ship

**Before any push that touches the demo:**

```
node -e "const h=require('fs').readFileSync('ripples/demo/index.html','utf8');new Function(h.match(/<script>([\s\S]*)<\/script>/)[1]);console.log('parse ok')"
python3 ripples/tools/build_portable.py
cd ripples/tools/qa
node tap_test.js        # every ripple's tap target answers to its own ripple on dense phone ponds; exits 1 on a failure
node header_test.js     # the pond's top on a 390 and a 375 phone (145 to 167 px on Oct 4) and whether the tally sits under it
node chart_test.js      # the spikes chart stays inside its column with no animation (the Oct 4 .pulse collision); exits 1 on a failure
node pace_test.js       # when each ripple arrives and how long a story runs (15 to 95 s, beats 2 s apart or more, a narration line per beat); exits 1 on a failure
node fold_test.js       # the legend inside a 614-px laptop fold, the caption clear of a small phone pond, the first lasting mark and its promise on a phone; exits 1 on a failure
node sweep.js           # screenshots of the main screens, desktop and phone, into ./sweep
```

Set `CHROMIUM=/path/to/chromium` to use a specific browser; otherwise Playwright's own is used. Each script takes an
optional page argument (a file path or a URL), so the same checks run against the live site.

**When a chain, a hint or a statute changes:**

```
python3 ripples/tools/build_sources.py                 # rebuilds demo/sources.json (186 links on Oct 4)
python3 ripples/tools/qa/statutes.py 72 426 85-568     # confirm one cite against govinfo before adding it to STATUTE
python3 ripples/tools/qa/statutes.py --all             # re-confirm every cite on the chains' source lines
```

Push the branch; the chain-check workflow grades the chains and commits `chain_check_v1.json` back (pull with
`git pull --rebase` before your next push). A chain is not done until that file carries its grades.

**When the demo's look changes:** regenerate the share cards (`node cards.js`, writes `demo/cards/*.png` and the
`demo/s/<slug>/` stubs from `cards_list.json`) and rebuild the standalone.

**Launch clips:** in reel mode (`?reel=1`) the page plays an edited cut, not the playthrough: a still open, the throw,
up to five shots (the marks and measured steps) as hard cuts with a camera push-in on the arriving ripple, a fast date
roll where years pass, and a wide end card with the marks and "It wasn't the only reason" (`CUT`, `makeReelCut`,
`applyCam`). Tiger King 12.5 s, Sputnik 14.6 s. `node reel.js` records the stills and four raw clips into `./reel` and
prints each cut's length; then `./encode.sh tiger-king reel/vid/tiger-king-wide.webm wide 0.3 12.8` and the vertical
the same. **Do not record the kit until the look pass has landed**; the Oct 4 06:00 clips in `launch/` predate both
the pacing and the cut and are stale.

**Git:**

- Work on a `claude/<name>` branch (the Oct 4 session used `claude/funny-ride-8tiy11`). Every push to `claude/**` that
  touches chains or the checker triggers the chain-check workflow.
- Commit messages describe the change in plain words. No model names or identifiers in commits, pull requests, code
  comments or anything pushed.
- Grep the diff for keys before every commit.
- Open a draft pull request, wait for the `assets` check (it fails if any page references a missing local asset), mark
  it ready, squash-merge, then reset the branch onto `main` (`git fetch origin main && git checkout -B <branch>
  origin/main && git push -u origin <branch> --force-with-lease`). The owner's standing direction (Sep 28) is that Claude
  opens and merges its own pull requests, keeping to the product vision. Pages rebuilds a few minutes after a merge.

## 6. Rules that never change

- Honest user agent `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`. A 403, 429 or 503 is a stop for
  the day, never a retry with a different agent, a proxy or a workaround. No bypassing blocks. Aggregate data only.
- Keys only in GitHub secrets (or Supabase Vault for the parked engine). Never printed, logged, committed or pasted.
- Every test is pre-registered before any result exists; deviations are disclosed. Explore freely, confirm by registration:
  anything shown as *measured* comes from a registered test.
- The ordering rule: every step an outcome in its own data, every step later than the one before.
- Every link shows its grade. Invented steps never appear as links. A citation is reported, never measured. Nothing is
  dressed as more certain than its test.
- A ripple's payoff is a lasting mark. Attention and growth are intermediate.
- The statute outranks the article where a confirmed link exists.
- Simulated testers are simulated and say so; a persona modeled on a public figure is labeled "simulated persona modeled
  on the public role of …; not his words" wherever it appears.
- American English and US date formats throughout.
- No Google billing (BigQuery stays inside the sandbox cap). The private `RIPPLE_MAP_CONTEXT.md` of the cloud session was
  scratch and is never committed; the public brief carries everything that matters.
- Report honestly: a failed rule is reported as failed, with the diagnosis; "nothing survived" is a result.

## 7. Where the work stands (Oct 4, 2026, 08:30 UTC)

**Not released. The owner saw the live page on the morning of Oct 4 and set a new bar before release:** the playthrough
was "way too fast and not visually interesting enough", the look "cartoony wireframe", and the worry is that strangers
call it AI slop before giving it a chance. Two things have landed since: the `.pulse` class collision that ballooned
the chart over the pond (PR #86), the beat schedule that replaced the ten-second trailer (PR #87), the reel cut for
clips (PR #88, mechanism only, nothing recorded) and the look pass (PR #89, `docs/styling_pass_v2.md`: flat surface,
no gradient or glow, rim words as print annotations, label boxes gone, matte stone, opening screen retired, share cards
regenerated). Round five ran (8.0; `docs/user_tests_v5.md`). The owner then set a new bar for the evening of Oct 4: crack
discovery so the engine reliably identifies causal chains. `docs/discovery_plan_v2.md` registers the program;
`docs/discovery_corpus1_v1.md` is the first result (Wikipedia as a cited-cause record: 62% recall of the catalog's
marks, 61% clean on the strict reverse rule, 0 of 50 decoys, 26% precision as a forward candidate generator on held-out
stones; the bar of 7 in 10 not met; scripts in `lab/discovery/`, results in `docs/results/`). The screened pairs are in the
product (PR #92): a fourth story kind, `wiki`, built by `fromWiki` from `demo/discovered_wiki.json`, 14 stones and 25
marks first under Engine leads, every link reported with its sentence and source, each stone with a context line; deep
link `?w=<slug>`. The desktop header fold landed (#93: the second header paragraph folds to one line until clicked; header 299 → 243
px, the pond's foot inside a 614-px fold). Discovery v1.1 ran over sixty more stones and 22 stones / 52 marks
were screened into the product (PR #95; `docs/discovery_corpus1_v1_1.md`; 36 stones, 77 marks under Engine leads).
The clips are cut and the launch kit is current (PR #94; `launch/posts_ready.txt`). The culture shelf ran over 132
recognizable stones with a behavior lexicon and 22 stones / 25 marks joined the product, including the first Disputed
engine-found link (PR #96; `docs/discovery_culture_v1.md`): **58 stones, 102 marks under Engine leads.** The second
roundtable (`docs/roundtable_v2.md`: the twelve at 8.3, three new strangers at 7.3) voted release. Still to do: release
Monday morning Oct 5 (section 8), the owner's date; the pre-flight checks 1 to 3 already pass on production. Round six (three more strangers on the reveal build, 8.0; `docs/user_tests_v6.md`) led to two fixes: statistics off the
narration line, the short-screen rule up to 820 px for classroom Chromebooks (PR #103). The owner then
asked for the reveal to feel like an investigation (PR #101, `docs/reveal_v1.md`: the title withholds its answer, numbered
clues, the first mark resolves the title, a verification beat; clips re-recorded). Before that he
played the demo and sent a readability review (PR #100: long stories name only marks and measured steps at rest, labels step
aside under the narration, the pond column is 1.8× the cards, the spikes chart is sticky and draws in, cards fold behind
Learn more, the chooser opens in layers). The room's
items were all built the same night (PR #98; the actions table in `docs/roundtable_v2.md`): tighter beats before the
first mark and a promise line, the shelf grouped by source and decade, the legend as a corner panel on short screens, the
caption in flow under small ponds, Copy citation on engine cards, one grade map for the engine kind, the checker on main
and weekly, fifty famous films as decoys (8% loose, 0% strict).
The text below is the state the previous session left.

Release-ready as of 06:30. Five rounds of simulated testers took the product from 5.5 to **8.2** and voted to release; the
builder's own rating is **8.5** (the trail: 4 on Oct 1, 5.5 on Oct 2, 6.5 on Oct 3, 7.5 on the morning of Oct 4, 8 after
the final roundtable's fix, 8.5 after the three release fixes). Everything is merged to `main` through PR #83.

What shipped on Oct 4 alone: the pond as an instrument; the ten-second trailer; the weakest-link arrow in the title;
share a step; the run stamp gated on the truncation test; the pond's glyphs; exclusive tap targets; the phone's first
screen (pond top 290 → 145 px); 22 statute links; "It wasn't the only reason" on every story; the US history catalog
(batch 16); 186 verified source links; launch kit v2 with vertical clips; this handoff and the QA tools.

The honest gaps, none blocking: strangers have not used it; the context sentences are one author's; pre-2015 marks rest
on records because no free attention series reaches back; the checker runs on branches, not on main or a schedule;
"Not yet" is a regular expression in the page rather than a checker grade; the trailer costs about 107 ms/s of task
time in headless Chromium; the legend sits under a 614-px fold; the caption covers most of a 375-px pond.

## 8. Next steps, in order

1. **Release.** Follow `docs/launch_v2.md`: the four pre-flight checks, LinkedIn with the clip, Show HN mid-morning
   Eastern on a weekday with the first comment ready, Reddit the same day, five teacher and five newsroom emails that
   week. Reply to every substantive comment with the story's share page. A correction gets a thank-you and a fix.
2. **Watch week one** with the engagement instruments (`docs/engagement_protocol_v1.md`: a GA4 funnel
   story_start → reveal → verify → complete, leaves by clock position, taps and second stories per start; configure the
   internal-traffic filter first) and against the four named dimensions: a teacher or newsroom using it (about 60%), a front page
   (35%), an outside correction or a suggested stone (25%), a return visit (15%). About 70% for at least one.
3. **First-week fixes from the final roundtable:** the legend under a 614-px fold; the caption's height on a 375-px
   phone; quiet trailer dots on a projector; the claims line on the decline cards as well as the peak; Tylenol's links
   and the 1983 Act; the Mr Bates premise sentence.
4. **Governance:** run the checker on `main` and on a schedule; make "Not yet" a checker grade; a govinfo API pass from a
   workflow (with `DATA_GOV_KEY`) to confirm the seven pre-1951 statute links by title.
5. **Data:** USDA NASS (six steps measurable, about 1.5 days), Congress.gov (five, 2 days), SEC EDGAR full-text search
   (five, 1.5 days), in that order; see `docs/data_sources_v2.md` for what each gives and what it does not.
6. **Content:** a second reader for `demo/context.json`; Prohibition's label density; a suggest-a-stone box and a stone
   of the day once there are visitors.
7. **Engine:** round two of the citation grades (`docs/cite_grades_v2.md`); a second dose-response; nested stones
   (Prohibition's marks as chains of their own); live mode on new events once marks have had time to form.

## 9. How a tester round is run (so the next one matches the last five)

Build the standalone, note its md5. For each persona, open the page in Playwright at that persona's viewport, scale and
input mode (phone 390×844 touch, tablet 820×1180, desktop 1440×900 mouse, the deuteranopia emulation via CDP for the
color-blind persona). Verify each persona's own item with a measurement before the persona speaks (tap exclusivity,
pond top, label overlaps, task time, link targets). Write the round as `docs/user_tests_vN.md`: a verification table,
the session, one line and a number per persona, a before/after table. The personas are fictional, and the three modeled
on public executive roles are labeled as such on every mention. The scripts of the Oct 4 rounds are the ancestors of
`tools/qa/*.js`; the method is in `docs/roundtable_final.md`, part 1.

## 10. A starter prompt for the new chat

The full prompt, with the mission, the owner's working style and the first message expected back, is
`docs/session_prompt_v1.md`. The short form:

> Read `ripples/HANDOFF.md`, then `ripples/docs/ripple_Map_context.md` sections 2, 5 and 6, in the repository
> `bsunter93/Ben-Sunters-Website`. Work on a `claude/<name>` branch; open and squash-merge your own pull requests after
> the `assets` check passes; reset the branch onto `main` after each merge. Keep the rules in HANDOFF section 6
> exactly. Start with HANDOFF section 8, step 1, and send me a short synopsis when something lands.
