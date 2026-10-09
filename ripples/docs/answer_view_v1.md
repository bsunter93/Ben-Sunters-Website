# The answer view (Oct 8, 2026)

## Why

The Reddit note of Oct 7 ("I think the UI is a bit confusing and hard to read") led to the chain view the same day
(`docs/chain_view_v1.md`). The owner then chose a bigger change: put the answer first. Three facts point the same way.

- About 26 of 100 story starts reached the reveal in the first week (Oct 1 to 6, the pond view).
- The launch clip on LinkedIn was watched for 6 s on average.
- The answer arrived 14.5 s into the chain view and 26 s into the pond view.

The chain view was live for about a day before this replaced it, so its registered forecast (reveal out of the worry
zone, p 0.6) can't be scored. That week is not readable as a test of the list.

## What changed

1. **The water opens the page and carries no words.** A lake at dusk across the top. The stone is thrown in, lands,
   and rings spread. When the answer shows, a pool of ember lights where it landed.
2. **The question is the title.** "What did Tiger King change?" Four tiles: a law or rule, something built, how
   people live, nothing lasting. A tap shows the answer at once and scores the guess. "Skip the guess and show me"
   shows it without one. Nothing waits on a clock.
3. **The answer panel.** The lasting mark, its date and how long after the stone it came. The guess's verdict. A How
   sure meter with four rungs, set by the weakest link on the way to the mark, and one sentence on what that means.
   "It wasn't the only reason" stays. Then "Did you know this already?", Next and Share.
4. **The route.** The stone at the top and each step below it in date order. The time between steps is written out
   ("1 year 11 months later"). Each link is drawn in the style of its grade, and each step says how we know it with a
   tag and one sentence. Three or more small moves in the first two months fold into one row. A long story stops
   just after its answer. "Show every step" opens the rest, the asides and the checks that didn't count.
   "How we know" under each step holds the card's own account, its chart, its source and Copy citation.
5. **The shelf.** Every story whose title names a landing, grouped by the kind of lasting mark, each card naming
   where the stone landed. A card opens its story with the answer shown, since the card already said it.

The grades and their tests are unchanged. On this view they read in plain words:

| Grade | Tag | What the sentence says |
|---|---|---|
| measured | Measured | what moved and how it compared with random dates; for Wikipedia views, "That counts attention." |
| timed | In order | it rose right after the step before; not tested against chance |
| reported | On the record | the record that names the link |
| plausible | Unproven | it happened; nothing on record ties it to the step before |
| busted | Busted | why it fails |

The meter's rungs run in the order the title's arrow already uses: Unproven, On the record, In order, Measured.

## A fix that reaches every view

`guessOf` counted a "Name" mark as "how people live". Name marks are things named after the stone: a reactor, a
street, a NASA lander, a hockey trophy. Baby names are marked Behavior. A Name mark now counts as "something built",
so a visitor who guessed "something built" for Angry Birds → a NASA lander is now told they were right.

## Instruments

- `ripple_story_start` carries `view: "answer"`.
- `ripple_reveal` carries `via`: `guess`, `skip`, or `known` (a shelf card already named the landing). Read the
  reveal rate on `guess` and `skip` only.
- `ripple_guess` and `ripple_guess_result` as before.
- **New: `ripple_knew`** with `knew` (1 or 0) and `guess`, once per story per browser. It is the first surprise label
  from real visitors. Every surprise number so far came from simulated raters (`docs/results/panel_v1/`).

## How the next two weeks are read

Same protocol (`docs/engagement_protocol_v1.md`), per 100 story starts, in visitors, review runs removed.

| Reading | Bar | Forecast, registered now |
|---|---|---|
| Reveal (guess plus skip) | worry under 40, good over 60 | over 60 (p 0.7) |
| Guess, of reveals | none set | over half (p 0.55) |
| Knew-it answers | none set | at least 30 in two weeks (p 0.4) |
| Shelf or Next opens, per visitor | none set | over 0.5 (p 0.5) |

"Didn't know" share by story, once a story has 10 answers, is the first real ranking of which finds are surprising.

## Flags and tests

`?view=chain` opens the list and `?view=pond` the pond, for the session. Reels and share cards keep the pond.
`tools/qa/answer_test.js` checks the tiles on the first screen, the answer time, the verdict, the route's layout at
four sizes, every story in the catalog, Skip, a shelf card, Next, a shared step, and both older views.
