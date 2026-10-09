# The ripple chart (Oct 8, 2026)

## Why

The answer view (`docs/answer_view_v1.md`) went live on Oct 8. The owner's read the same day: it is extremely text
heavy, and the page should be visual again. The stacked interest lines of the pond view were the best part, because
they showed how big each downstream move was next to the others. He asked to spoon feed the reader and to drop the
guess, which he found annoying. He kept the lake at the top.

On the answer view a stranger met about ten blocks of words before the route: a kicker, the mark, its date, a verdict,
"Also lasting", a four-rung meter with a sentence, "It wasn't the only reason", a question and two buttons. The route
added a tag and a sentence to every step.

## What changed

1. **The answer is the title from the first frame.** "Tiger King → the Big Cat Act", the stone's date above it and one
   line under it: "2 years 9 months later: the Big Cat Public Safety Act becomes law." No guess and no wait.
2. **One chart tells the story.** One row per step in date order, the stone at the top, all on one clock (a short lead
   for the four weeks before the stone, then log time since it). A row with an attention series draws that page's
   weekly Wikipedia readers against its own normal (the median before the step), on one log scale shared by every row,
   with its peak written beside it (1,266×, 726×, 2.4×, 4.6× on Tiger King). Rows with lines are taller, so every line
   stays inside its own row. A step from a record is a dot on its day. A lasting mark is an amber hexagon with an amber
   bar that runs on to today. An unproven step is a hollow dot and a busted one a red cross.
3. **It plays row by row.** One caption above the chart speaks for the row that just appeared: a kicker of facts
   (date, time after the stone, the peak, "a lasting mark") and the step's title. The rows still to come show as faint
   names. About 10 s on Tiger King. At rest the caption names where the stone landed, with a "How we know" link to that
   step's full account. A tap or hover on any row stops the play and shows that row. "Skip to the end" and "Play again"
   sit by the buttons. Reduced motion gets the resting chart at once. The lake's ember lights when the play ends.
4. **Words that stay:** one key line (what a line means, what the amber bar means, "How sure" with the old sentence on
   hover), "Not the only reason" when the story has one, Next, Share, and "New to you? Yes / I knew it".
5. **The route folds under the chart.** "Every step and how we know it" opens the answer view's route unchanged: every
   step, its grade in plain words, its source, its chart and Copy citation. A shared step link (`&s=`) opens it there.
6. **The shelf leads with everyday life.** Groups run: how people live, something built, a law or rule, nothing
   lasting yet. Each card draws its ripple on one clock shared by every card (up to a century): the stone, its steps,
   the mark and its amber bar. A 13-day ripple and a 113-year ripple now look different at a glance.

The grades and their tests are unchanged.

## The gap this shows

Of 201 stories in the catalog, **44 draw at least one line; 157 draw dots only.** Across the 150 stories on the shelf,
47 of 433 steps carry an attention series, and 101 are single-hop Wikipedia pairs (a stone and one mark). Pageviews begin in July 2015, so most
historical stories can never have a contemporary line.

The next data job, in order of reach:

1. Daily Wikipedia pageviews for every stone and every step that has its own article, in a window around the step,
   for steps after July 2015. This gives the law rows of Tiger King (the Big Cat Public Safety Act has an article) a
   line of their own, so the record steps can be compared with the early spikes.
2. For steps before 2015, a yearly line from Google Books Ngram for the step's key term (CC BY 3.0, 1800 to 2019).
3. Stones with no line at all stay as dots and bars. That is the honest picture.

## Instruments

- `ripple_story_start` carries `view: "chart"`.
- `ripple_reveal` is no longer sent from this view: the answer is in the title, so a reveal rate means nothing here.
- **New: `ripple_chart_end`** with `via`: `play` (watched to the end), `skip` or `tap` (cut it short), plus `rows` and
  `seconds_in_story`. Once per story start.
- `ripple_knew` as before, now with no guess (`guess` is "none").
- `ripple_learn_more` with `view: "chart"` when "How we know" is tapped from the caption.

## How the next two weeks are read

Same protocol (`docs/engagement_protocol_v1.md`), per 100 story starts, in visitors, review runs removed.

| Reading | Bar | Forecast, registered now |
|---|---|---|
| `chart_end` via play, of story starts | none set | over 50 (p 0.5) |
| Next or a shelf card, per visitor | none set | over 0.5 (p 0.5) |
| `knew` answers | none set | at least 30 in two weeks (p 0.35) |

Register `via` (already a dimension) and `rows` before reading.

## Flags and tests

`?view=chain` and `?view=pond` keep the earlier views for the session. Reels and share cards keep the pond.
`tools/qa/answer_test.js` now checks this view: no guess controls, the title and chart on the first screen, the play
reaching the landing row, row names that never overlap, nothing outside the panel or sideways at four sizes, every
story in the catalog at a laptop and a phone size, Skip, Play again, a tap on a row, a shelf card, Next, a shared step,
and both older views. `fold_test.js` no longer reads the story before the page has one (it failed 1 run in 3).
