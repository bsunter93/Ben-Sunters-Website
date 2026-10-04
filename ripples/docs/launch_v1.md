# Ripple v1: launch kit (Oct 3, 2026)

Live: https://bensunter.com/ripples/demo/ · Methods and misses: https://bensunter.com/ripples/discover/ · Code: https://github.com/bsunter93/Ben-Sunters-Website/tree/main/ripples

Assets in `ripples/launch/` (re-cut Oct 4 on the current build; the lead story is now Tiger King → the Big Cat Act, a US show and a US law, after two of three US testers did not know Mr Bates): `ripple-tiger-king-1200.mp4` (16 s, 1200×675, LinkedIn and Reddit), `ripple-tiger-king-square.mp4` (1080×1080), `ripple-tiger-king.gif`, and stills `ripple-tiger-king-2400x1260.png`, `ripple-mr-bates-2400x1260.png`, `ripple-prohibition-2400x1260.png`. The Mr Bates clips remain as the alternate: `ripple-mr-bates-1200.mp4` (20 s, 1200×744, for LinkedIn and Reddit), `ripple-mr-bates-square.mp4` (1080×1080), `ripple-mr-bates.gif` (800 px, 14 s), and three 2400×1260 stills (Mr Bates, Prohibition, Tiger King). Every featured story has its own share page at `/ripples/demo/s/<slug>/` with a preview image, so a link to one story unfurls with its own pond.

Before posting: open https://bensunter.com/ripples/demo/ (it opens on Tiger King) and https://bensunter.com/ripples/demo/?c=mr-bates-horizon on a phone and a laptop once Pages has rebuilt (a few minutes after merge), and paste the link into LinkedIn's post box to see the preview image load.

---

## LinkedIn (personal; the clip or the Mr Bates still attached)

I've been fascinated by the butterfly effect for as long as I can remember.

Not the movie version. The quiet version: the sense that the world we live in is balanced on a long chain of small outputs, and that if one of them had come out a little differently, almost nothing downstream would look the same. Some days it feels like a house of cards. Most days it just feels like the most interesting thing there is to think about: the decisions we make, the things we watch, the accidents we have, all setting up a future none of us could have drawn in advance.

So I built a thing to follow the thread.

It's called Ripple. You throw a stone (a show, a film, a disaster, a discovery) into a pond, and the ripples spread out in time. Each ripple is something that changed afterward, placed where it began. And every link is rated for how sure we can honestly be: measured against the data, timed in the right order, reported by a credible source, or just plausible. Some are busted, because the "effect" turns out to have started before its "cause".

The one that got me: a four-night ITV drama in January 2024. Within a week, attention to the Post Office scandal was 370 times its normal level. Within nine days the Prime Minister announced a law. In March, MPs stood up in the Commons and credited the drama by name. In May it was an Act of Parliament, and hundreds of wrongful convictions were quashed. The engine found the citation in Hansard on its own; a person checked it; the pond shows you the order.

It also shows you what doesn't hold. Prohibition to Gen Z drinking less is a century-long chain, and every popular "catalyst" for the recent decline (phones, Dry January, legal cannabis) turns out to have arrived decades after the decline began. Order is a strict judge.

Ripple is a v1 and an honest one. Timing shows order, not proof of cause. The tests, the misses and the methods are all published alongside it.

I'd love to know which stone you'd throw.

https://bensunter.com/ripples/demo/

---

## Reddit

**r/InternetIsBeautiful** (title, link post to the demo)

> Ripple: throw a stone (a show, a disaster, a discovery) into a pond and watch what it changed, in the order it happened, with every link rated for how sure we can be

First comment (post this yourself right after submitting):

> Builder here. I've always been drawn to the butterfly-effect side of history, the sense that so much of what we live inside rests on a chain of small outputs that could have gone another way. This is my attempt to follow the thread honestly.
>
> Each ripple is placed where it began in time. Links are rated measured (a placebo-tested rise in data), timed (right order, not tested against chance), reported (a source makes the link), plausible (it happened; link unproven) or busted (wrong order, or no evidence). The "busted" ones are my favorites: a lot of viral causal stories fall apart the moment you date both ends.
>
> Favorite map so far: *Mr Bates vs The Post Office* → the Offences Act 2024 in five months, with the moment MPs credited the drama in Hansard. Favorite busted claim: that smartphones or Dry January *started* the decline in teen drinking (it began around 1980).
>
> It's a v1. Methods, misses and raw results are published; happy to answer anything.

**r/dataisbeautiful** ([OC], the 20-second clip or the Mr Bates still)

> [OC] A TV drama to an Act of Parliament in five months: the ripples of Mr Bates vs The Post Office, each placed where it began, each link rated for how sure we can be

Required source/tool comment:

> Tool: Ripple, which I built (vanilla JS + SVG; the checker is Python on GitHub Actions). Data: daily Wikipedia pageviews (Wikimedia REST API) for attention, with a placebo test against the page's own history; Hansard's API for the parliamentary citations; legislation.gov.uk for Royal Assent dates; change.org and press reports for the dated steps. Every step and its rating: https://bensunter.com/ripples/demo/?c=mr-bates-horizon · methods: https://bensunter.com/ripples/discover/

---

## Hacker News (Show HN)

Title (under 80 characters):

> Show HN: Ripple – throw a stone into history, see what it changed, with every link rated

First comment:

> I've long been fascinated by how much of the present rests on a chain of small, datable events, and by how badly most "butterfly effect" stories survive contact with a calendar. Ripple is a v1 attempt to do it honestly.
>
> What it is: a pond. The stone is an event (a show, a film, a disaster, a discovery). Each ripple is something that changed afterward, placed at the time it began. Every link carries a rating:
>
> - measured: a sustained rise in a series (mostly daily Wikipedia views, some official series) that beats a placebo test run at random dates in that series' own past, and that began after the step before it
> - timed: right order, not tested against chance
> - reported: a credible source makes the link (for laws, usually the debate itself: a Hansard or Congressional Record sentence that names the work)
> - plausible: it happened; the link is unproven
> - busted: it started before its supposed cause, or there's no evidence it happened
>
> The ordering rule only falsifies; nothing here is proof of cause, and the UI says so. A measured step is association plus order with an empirical p-value, not mechanism.
>
> The engine side: a records route reads every Hansard contribution / Congressional Record item that names a work, resolves the bill under debate to the Act it became (UK Parliament Bills API + legislation.gov.uk; GovInfo for the US), and a small rule-based scorer labels each citation as a reason, context or an aside. A person still screens the output; the scorer's precision is .73 on the first hand-graded set and that number is published. One dose-response design (retail-cannabis states vs not, young-adult drinking, difference-in-differences with permutation inference) came back within chance and is shown as such.
>
> Stack: a single HTML file, SVG, no framework; Python fetchers on GitHub Actions committing JSON results back to the repo; GitHub Pages. Everything (chains, protocols, results, misses) is in the repo.
>
> Things I know are weak: most pre-2015 steps rest on reported links because free daily attention data starts in 2015; the citation scorer is rules, not a model; the US law route has two pairs so far. Would value pushback on the statistics framing most of all.

---

## Posting order and timing

1. Merge, wait for Pages, check the live link on a phone.
2. LinkedIn first (the clip plays inline; the personal post carries it).
3. Show HN mid-morning US Eastern on a weekday, with the first comment ready to paste within a minute of submitting.
4. Reddit the same day or the next: r/InternetIsBeautiful as a link post; r/dataisbeautiful with the clip and the required source comment.
5. Reply to every substantive comment with the specific map or test it concerns; link the share page for that story so the preview carries its pond.
