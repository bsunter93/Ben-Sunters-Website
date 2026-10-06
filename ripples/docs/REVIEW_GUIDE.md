# Ripple: a guide for reviewers

Everything about Ripple lives in one public repository, `github.com/bsunter93/Ben-Sunters-Website`, under `ripples/`.
This guide is the map. The live demo is at https://bensunter.com/ripples/demo/; the file `ripples/dist/ripple-standalone.html`
is the same demo with its fonts and data inlined, so it opens from a laptop with no server.

## What Ripple is, in four sentences

You throw a stone (a show, a film, a disaster, a discovery) into a pond and the ripples spread out in time. Each ripple is
something that changed afterward, placed where it began. Every link is rated: measured (a placebo-tested rise in data
that began after the step before), timed (right order, not tested against chance), reported (a credible source makes
the link), plausible (it happened; the link is unproven) or busted (wrong order or no evidence). Timing shows order,
not proof of cause, and the product says so.

## Where to look, by interest

| If you want to review… | Open |
|---|---|
| The product as a user sees it | `ripples/demo/index.html` (one file: HTML, CSS, JS, no framework) or the standalone build |
| The design decisions and their reasons | `ripples/docs/ripple_Map_context.md` (the brief: vision, status, learnings, pitfalls, rules) |
| How a link is rated and the statistics behind "measured" | `ripples/lab/chain_check.py`; the methods page at https://bensunter.com/ripples/discover/ |
| The chains themselves (every step, claim, source, test) | `ripples/chains/batch*.json` |
| The checker's verdicts for every step | `ripples/docs/results/chain_check_v1.json` |
| How the engine finds work → law trails in the records | `ripples/lab/mark_text.py` (Hansard, Federal Register, GovInfo), protocols `ripples/docs/mark_text_v1_*.md` |
| How a bill resolves to the Act or public law it became | `ripples/lab/bill_act.py`, results `ripples/docs/results/bill_act_v1.json` |
| The citation screen (cited as a reason / context / aside) | `ripples/lab/cite_score.py`, its hand-graded evaluation `ripples/docs/results/cite_score_v1.json`, the round-2 sheet `ripples/docs/cite_grades_v2.md` |
| The one dose-response design and its two honest failures | `ripples/docs/dose_response_v1.md`, `ripples/lab/series_fetch.py`, `ripples/docs/results/series_v1.json` |
| The Wikipedia-side discovery that was tried and demoted | `ripples/lab/mark_first.py`, `ripples/docs/mark_first_v1_1.md` |
| How the fetchers run (the container cannot reach the sources; CI does) | `.github/workflows/ripples-*.yml` |
| The launch kit (clips, stills, post copy) | `ripples/launch/`, `ripples/docs/launch_v2.md` |
| The browser checks, share cards, clips and statute confirmations | `ripples/tools/qa/` (see `ripples/HANDOFF.md`) |
| The tester rounds and the roundtables (simulated personas, labeled) | `ripples/docs/user_tests_v1.md` to `v7.md`, `roundtable_v1.md`, `roundtable_v2.md`, `roundtable_final.md` |
| Picking the work up | `ripples/HANDOFF.md` |

## How to run things

- The demo: open `ripples/dist/ripple-standalone.html`, or serve the repository root and open `/ripples/demo/`.
- The checker locally: `python ripples/lab/chain_check.py` (needs network to Wikipedia, FRED and the rest; in this
  project it runs on GitHub Actions and commits `chain_check_v1.json` back).
- The records route: `python ripples/lab/mark_text.py` (GovInfo needs `DATA_GOV_KEY` in the environment).
- Share cards: `?card=1` on any story URL renders the 1200×630 card; the reel: `?reel=1`.

## Conventions worth knowing

- Every fetcher sends an honest user agent, waits a second between requests, and stops on a 403, 429 or 503.
- Every search protocol is written before the run, and failures are recorded as addenda rather than rewritten.
- A step's level never rises because of an attention check; the check rides along on the card.
- American English and US dates throughout the product; British sources are quoted as written.

## Questions reviewers have asked

- *Is "measured" causal?* No. It is association plus order with an empirical p-value from a placebo test in the
  series' own past. The ordering rule falsifies; nothing here proves mechanism.
- *Who decides a citation counts?* A rule scorer labels it; a person screens the output; the scorer's precision on
  the first hand-graded set (.73) is published and a second blind set is in the repo.
- *Why so few US law pairs?* The route is new (two pairs); the UK route has 78 because Hansard's API is open and the
  Bills API gives Royal Assent dates directly.
