# Ripple: launch kit v2 (Oct 4, 2026, the release build)

Live: https://bensunter.com/ripples/demo/ · Methods and misses: https://bensunter.com/ripples/discover/ · Code: https://github.com/bsunter93/Ben-Sunters-Website/tree/main/ripples

Cut on the release build (main after PR #82): the ten-second trailer, the weakest-link arrow in the title, the "It wasn't the only reason" line, the pond's glyphs, the phone's first screen and the statute links are all in frame. Supersedes `archive/launch_v1.md`.

## Assets in `ripples/launch/`

| File | What | Where it goes |
|---|---|---|
| `ripple-tiger-king-1200.mp4` | 16:9, 1200×676, 12 s: the ten-second trailer and the rest state with the law | LinkedIn, Reddit, X |
| `ripple-tiger-king-square.mp4` | 1080×1080 | Instagram feed, LinkedIn mobile |
| `ripple-tiger-king-vertical.mp4` | 1080×1920, 12 s, the story centered in a phone frame | Reels, Shorts, TikTok, Stories |
| `ripple-tiger-king.gif` | 800 px, for places that will not play video | Reddit comments, email |
| `ripple-sputnik-1200.mp4` | 16:9, 1200×676, 13 s: five lasting marks in ten seconds, the US history lead | r/dataisbeautiful, teachers |
| `ripple-sputnik-vertical.mp4` | 1080×1920, 13 s |
| `ripple-sputnik-square.mp4`, `ripple-sputnik.gif` | 1080×1080; 800 px | Instagram; comments and email | Reels, Shorts |
| `ripple-<story>-2400x1260.png` | Stills: tiger-king, tiger-king-act, sputnik, prohibition, mr-bates, the-jungle, dust-bowl | Open Graph fallback, slides, email |

Every featured story also has a share page at `/ripples/demo/s/<slug>/` whose preview image is its own pond, and any single step has a link (`?c=<slug>&s=<step>`) that opens stopped on that ripple.

## Before posting

1. Wait for Pages to rebuild after the merge (a few minutes), then open https://bensunter.com/ripples/demo/ on a phone: the pond should be the first thing after the title, with the tally and "Change story" under it.
2. Open https://bensunter.com/ripples/demo/?c=sputnik-nasa-arpa and click a Space Act card's source: it should land on govinfo's page scan of 72 Stat. 426.
3. Paste https://bensunter.com/ripples/demo/s/tiger-king/ into LinkedIn's post box and watch the preview image load.
4. Have the first comment for HN and the source comment for r/dataisbeautiful in a text file, ready to paste within a minute of submitting.

---

## LinkedIn (personal; the 16:9 clip attached)

I've been fascinated by the butterfly effect for as long as I can remember. Not the movie version. The quiet version: the sense that the world we live in rests on a long chain of small outputs, and that if one had come out a little differently, almost nothing downstream would look the same.

So I built a thing to follow the thread, and to be honest about how sure we can be at each step.

It's called Ripple. You throw a stone (a show, a film, a disaster, a discovery) into a pond. The ripples spread out in time; each one is something that changed afterward, placed where it began. Every link is graded: measured against data with a placebo test, timed in the right order, reported by a source, or just plausible. Some are busted, because the "effect" started before its "cause".

The one it opens on: Tiger King. Netflix, March 2020. Within weeks, attention to exotic pets and the wildlife trade ran several times its normal level; library checkouts followed. In December 2022, the Big Cat Public Safety Act became law. The title draws an arrow from the show to the law, and the arrow is dotted, because the weakest link on the way is only plausible. Under it, one sentence I think every story like this owes you: it wasn't the only reason. The bill had been introduced in 2017 and campaigned for by animal-welfare groups for years.

Try Sputnik: five lasting marks in ten seconds (ARPA, the Space Act, the Education Act, NASA, ARPANET), each law linked to the statute itself. Try Prohibition, where every popular "catalyst" for Gen Z drinking less turns out to have arrived decades after the decline began. Order is a strict judge.

Ripple is a v1 and an honest one. Timing shows order, not proof of cause. The tests, the misses and the methods are published alongside it, and so is the sentence about what else was going on.

I'd love to know which stone you'd throw.

https://bensunter.com/ripples/demo/

---

## Reddit

**r/InternetIsBeautiful** (link post to the demo)

> Ripple: throw a stone (a show, a disaster, a discovery) into a pond and watch what it changed, in the order it happened, with every link graded for how sure we can be, and a line about what else was going on

First comment (post it yourself right after submitting):

> Builder here. I've always been drawn to the butterfly-effect side of history, the sense that so much of what we live inside rests on a chain of small, datable events. This is my attempt to follow the thread honestly.
>
> Each ripple is placed where it began in time. Links are graded measured (a placebo-tested rise in data), timed (right order, not tested against chance), reported (a source makes the link), plausible (it happened; link unproven) or busted (wrong order, or no evidence). The arrow in the title is drawn from the weakest link, so a title can't promise more than the worst card. Every story also carries one sentence, "It wasn't the only reason," naming the other things going on, because the honest version of any of these stories has that sentence in it.
>
> Favorites: Sputnik → ARPA, NASA, the Education Act and ARPANET, each law linked to the statute on govinfo. Favorite busted claim: that smartphones or Dry January *started* the decline in teen drinking (it began around 1980).
>
> It's a v1. Methods, misses and raw results are published; happy to answer anything.

**r/dataisbeautiful** ([OC], the Sputnik clip)

> [OC] Sputnik to NASA, ARPA and the Education Act in a year: each ripple placed where it began, each link graded for how sure we can be

Required source/tool comment:

> Tool: Ripple, which I built (vanilla JS + SVG; the checker is Python on GitHub Actions). Data: daily Wikipedia pageviews for attention since 2015, with a placebo test against the page's own history; the Congressional Record and Hansard for the moments a legislature named the work; govinfo for the statutes (each link confirmed against the law's first page); legislation.gov.uk for UK Royal Assent dates. Every step and its grade: https://bensunter.com/ripples/demo/?c=sputnik-nasa-arpa · methods: https://bensunter.com/ripples/discover/

---

## Hacker News (Show HN)

Title (under 80 characters):

> Show HN: Ripple – throw a stone into history, see what it changed, every link graded

First comment:

> I've long been fascinated by how much of the present rests on a chain of small, datable events, and by how badly most "butterfly effect" stories survive contact with a calendar. Ripple is a v1 attempt to do it honestly.
>
> What it is: a pond. The stone is an event. Each ripple is something that changed afterward, placed at the time it began. Every link carries a grade:
>
> - measured: a sustained rise in a series (mostly daily Wikipedia views, some official series) that beats a placebo test run at random dates in that series' own past, and that began after the step before it
> - timed: right order, not tested against chance
> - reported: a credible source makes the link (for laws, usually the debate itself: a Congressional Record or Hansard sentence that names the work)
> - plausible: it happened; the link is unproven
> - busted: it started before its supposed cause, or there's no evidence it happened
>
> The ordering rule only falsifies; nothing here is proof of cause, and the UI says so three ways: the arrow in the title is drawn from the weakest link on the path to the mark, the subtitle says it in words, and every story carries an editorial line naming the other things going on.
>
> Two things I checked before shipping that I'd want to know as a reader. First, whether grades drift: the placebo windows are drawn from the page's history before the step, and re-running the 13 measured grades with the data truncated at three cutoffs flipped none; each measured card carries the run date and checker commit. Second, the statutes: 22 US law steps link to govinfo's page scan, and each was confirmed by reading "Public Law N-M" off the PDF's first page (seven pre-1951 scans have no text layer, so those are confirmed by the granule boundary and the docs say so).
>
> The engine side: a records route reads every Hansard contribution / Congressional Record item that names a work, resolves the bill to the Act, and a rule-based scorer labels each citation as a reason, context or an aside (precision .73 on the first hand-graded set, published). A person still screens the output. One dose-response design (retail-cannabis states vs not, young-adult drinking) came back within chance and is shown as such.
>
> Stack: a single HTML file, SVG, no framework; Python fetchers on GitHub Actions committing JSON back to the repo; GitHub Pages. Everything (chains, protocols, results, misses, the twelve simulated-tester rounds) is in the repo.
>
> Things I know are weak: most pre-2015 steps rest on reported links because free daily attention data starts in 2015; the citation scorer is rules, not a model; the "it wasn't the only reason" lines are one author's and have not had a second reader. Would value pushback on the statistics framing most of all.

---

## X / Threads (a short thread, the vertical or 16:9 clip on the first post)

1. I built a pond. Throw a show, a film, a disaster or a discovery into it and watch what it changed, in the order it happened. Every link graded for how sure we can be. https://bensunter.com/ripples/demo/
2. Tiger King → the Big Cat Act. The arrow is dotted on purpose: the weakest link on the way is only plausible. And under the title: it wasn't the only reason. The bill was introduced in 2017.
3. Sputnik → ARPA, the Space Act, the Education Act, NASA, ARPANET. Five lasting marks in a year. Each law links to the statute itself.
4. Prohibition → Gen Z drinking less. Every popular catalyst (phones, Dry January, cannabis) arrived decades after the decline began. Order is a strict judge.
5. It's a v1. Methods, misses and the tests are published. Which stone would you throw?

---

## Email to a teacher (history, civics, statistics)

Subject: A pond for your students: throw an event in, see what it changed, with every link graded

I built a small free tool your students might like, and I would like to know whether it earns a place in a lesson.

Ripple (https://bensunter.com/ripples/demo/) shows an event as a stone thrown into a pond. Each ripple is something that changed afterward, placed at the time it began. Every link is graded (measured, timed, reported, plausible or busted), the title's arrow is drawn from the weakest link, and every story carries one sentence naming the other things going on, so a class can argue about cause rather than be told it.

Three that work in a room: Sputnik → NASA, ARPA and the Education Act (each law links to the statute itself); The Jungle → the 1906 food laws and the FDA; Prohibition → a century of American drinking, where the popular explanations for teenagers drinking less all arrive decades after the decline began.

It runs on a phone or a projector, needs no account, and a link to any single step opens on that step. The methods and the misses are published alongside. If you try it, I would value one paragraph on what a student did with it.

## Email to a journalist or a newsroom's data desk

Subject: Every link graded: a tool that dates both ends of a "this caused that" story

Ripple (https://bensunter.com/ripples/demo/) is a free tool that takes a cultural event and shows what changed afterward, in time order, with every link graded for how sure we can honestly be: measured against data with a placebo test, timed, reported by a named source, plausible, or busted because the effect began before its cause.

Why it might be useful at a desk: the headline arrow is drawn from the weakest link, so the page cannot promise more than its worst card; every US law links to the statute on govinfo, every measured card carries the run date and checker commit, and every story has a line naming what else was going on. The record of what it got wrong is published next to what it got right.

A story to test it on: Tiger King → the Big Cat Public Safety Act, where the honest version includes a bill introduced in 2017. Another: Prohibition and the Gen Z decline in drinking, where it busts the smartphone, Dry January and cannabis explanations by date. I would welcome a correction more than a link.

---

## Posting order and timing

1. Merge, wait for Pages, run the four checks above.
2. LinkedIn first (the clip plays inline; the personal post carries it).
3. Show HN mid-morning US Eastern on a weekday, first comment pasted within a minute.
4. Reddit the same day or the next: r/InternetIsBeautiful as a link post; r/dataisbeautiful with the Sputnik clip and the source comment.
5. The teacher and newsroom emails the same week, five of each, to people who have written about the subject.
6. Reply to every substantive comment with the specific story or test it concerns, linking the share page so the preview carries its pond. A correction gets a thank-you and a fix in the next push.

## What success looks like in week one

At least one of: a teacher or newsroom using it (the most likely, about 60%); a front page (about 35%); an outside correction or a suggested stone (about 25%); a return visit (about 15%). About 70% for at least one.
