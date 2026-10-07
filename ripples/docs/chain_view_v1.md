# The chain view (Oct 7, 2026)

## Why

A stranger on Reddit, Oct 7: "I think the UI is a bit confusing and hard to read, but overall this is a really cool
concept!" The owner agreed. The first week of the engagement instruments (`docs/engagement_protocol_v1.md`) says the
same thing in numbers.

**First reading, GA4, Oct 1 to 6, counted in visitors** (each visitor opened 4.7 stories on average, so event counts
overweight a few heavy users):

| Measure | As reported | Without the review runs | Bar (per 100 starts) |
|---|---|---|---|
| Started a story | 56 | about 47 | |
| Reached the reveal | 21 (38%) | about 12 (26%) | worry under 40 |
| Reached the end | 22 (39%) | about 15 (32%) | fine 20 to 35 |
| Tapped a ripple | 7 (13%) | 7 (15%) | worry under 15 |
| Guessed | 2 | probably 0 | none set |

The review runs: eight scripted plays on Oct 6 (04:50 to 05:05 UTC) under a custom user agent, which the headless
filter did not catch, and about five loads from one reviewer's browser. All of them reached the reveal, so they
inflate it. With about 47 starts, the reveal rate is likely between 15 and 40 per 100 (95% interval). The owner's own
visits are still in the counts; they would push it lower.

What the reading cannot say: whether people left because the page was hard to read or because the answer came 26 s in.
The leave event carries the clock position, but its parameters were not yet registered as custom dimensions, so the
fall-off point is not readable for this week.

## What changed

1. **The list is the reading surface.** The story reads top to bottom as rows in date order on a rail: the date and
   how long after the stone, the grade, the sentence, the sparkline where there is one. A lasting mark is an amber
   diamond on the rail; the row the title names is marked "the answer". A busted step is a hollow dot.
2. **The water stays, with no words on it.** Beside the list on a wide screen (above it on a phone) the stone is thrown
   and each ripple lands as the list fills in. Labels, the time grid, the rim words, the crest date and the route lines
   are off; the pond no longer has to be decoded.
3. **The last row carries the investigation.** While the answer is withheld it reads "Something lasting changed after
   this" and how many steps the answer is away; after the reveal, the check (order, weakest link, "Order doesn't prove
   cause"); at rest, what stayed and the next stone. The line under the pond is off in this view.
4. **Faster beats.** Every row stays on screen, so a beat no longer holds until it is read. Tiger King's answer lands
   at 14.5 s from load (26 s on the pond); Sputnik's at 14.6 s.
5. **The list follows the story** while it plays, unless the reader scrolled in the last 4 seconds.
6. `?view=pond` brings the pond back for the session; reels and share cards keep the pond.

Fixed in the same change: the guess closes when the answer shows (a phone kept its chips, and a tap logged a guess that
was never scored); on the pond, a phone places the answer's label first and lets another mark with no clear spot speak
on its beat (Tiger King's two mark labels overlapped by 39%); the ring labels wait out the phone's close splash ("1 yea"
was cut at the edge); a browser a script drives (`navigator.webdriver`) never sends an event.

## How it will be read

- `ripple_story_start` now carries `view` (`chain` or `pond`).
- Register these as event-scoped custom dimensions before reading anything (GA4 does not backfill): `t`,
  `reveal_reached`, `slug`, `via`, `nth_story`, `seconds_in_story`, `view`.
- The comparison is the week after the merge against Oct 1 to 6, in visitors, by the protocol's bars. The layout and
  the pace changed together, so the comparison cannot say which one moved the number; at about 50 visitors a week it
  could not anyway.
- Forecast, logged before any data: the reveal rate leaves "worry" (40 or more per 100 starts), probability 0.6.

## Checks

`tools/qa/chain_test.js` plays Tiger King at 375, 390, 768, 1024 and 1440 wide and Sputnik at 390 and 1440, and checks
the question row, the answer time (18 s and 24 s allowed), no words on the pond, no overlapping rows, nothing scrolling
sideways, no guess chips after the answer, the end row and its next stone, and that `?view=pond` still opens the pond.
The older checks (tap, header, chart, pace, fold, search) now run on the pond and all pass.
