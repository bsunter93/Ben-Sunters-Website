# Engagement protocol v1 (registered Oct 5, 2026, before any visitor)

The owner's question: can we measure engagement, fall-off points, points of confusion and stickiness, toward "a novel
and really fun interface for exploring causality"? Simulated testers cannot answer it; strangers can. This protocol
fixes what is measured, how, and what counts as good, before the first visitor arrives. Deviations will be disclosed.

## Instruments (in `demo/index.html`, `track()`)

Events go to the site's existing Google Analytics 4 property (`G-5DBXQV4RT2`, the same one the homepage has carried
since September), as aggregate counts with no personal data, IP anonymized. Nothing is sent from a local file, a share
card render, a reel recording, a QA run (`&nointro=1`) or a headless browser. Every event carries `seconds_on_page`.

| Event | When | Parameters |
|---|---|---|
| `ripple_story_start` | a story opens | kind, slug, `via` (landing, known, chip, search, next), `nth_story` |
| `ripple_reveal` | the first lasting mark resolves the title | slug, `seconds_in_story` |
| `ripple_verify` | the verification beat | slug |
| `ripple_complete` | the story reaches its end | slug, `seconds_in_story` |
| `ripple_play`, `ripple_pause`, `ripple_replay` | the play button | slug, `t` (clock position, 0 to 100) |
| `ripple_tap` | a ripple is tapped or clicked | slug, step, grade, mark, `nth_tap` |
| `ripple_learn_more` | a card is opened | slug |
| `ripple_chooser_open`, `ripple_kind` | the chooser, and a kind chosen | slug; tab |
| `ripple_share`, `ripple_cite` | a share (story or step), a citation copied | slug, what, step |
| `ripple_step_mode`, `ripple_scrub` | Step toggled; the first scrub of a story | slug |
| `ripple_leave` | the tab is hidden or the page unloads | slug, `t`, `reveal_reached`, `stories`, `taps`, `playing` |

## What each question is read from

- **Fall-off.** `ripple_leave` by `t` in ten buckets, split by `reveal_reached`. A pile of leaves before the reveal at
  the same `t` is a fall-off point; a pile right after it means the reveal did its job and the rest did not.
- **Confusion.** The ratio of `pause` + `scrub` + `chooser_open` within the first 10 seconds to `story_start`: a reader
  who reaches for the controls before anything has happened did not understand what was happening. Also `tap` with
  `nth_tap` = 1 arriving before `reveal`: readers who could not wait.
- **Engagement.** Taps per start; `learn_more` per start; `verify` reached per start; `complete` per start.
- **Stickiness.** `nth_story` ≥ 2 per session (a second story), `via` = next against chip (did the product carry them
  or did they have to go looking); GA4's own returning-user count for the demo path, week over week.
- **Sharing.** `share` and `cite` per 100 starts, and GA4 referrals from the share pages.

## Thresholds fixed now (per 100 story starts, first two weeks)

| Measure | Worry | Fine | Good |
|---|---|---|---|
| Reach the reveal | under 40 | 40 to 60 | over 60 |
| Complete a story | under 20 | 20 to 35 | over 35 |
| Tap at least one ripple | under 15 | 15 to 30 | over 30 |
| Open a second story | under 15 | 15 to 30 | over 30 |
| Leave before the first clue (t under 10) | over 40 | 20 to 40 | under 20 |
| Share or cite | under 1 | 1 to 3 | over 3 |

If the first hundred starts land in "worry" on reaching the reveal, the first fix is the clock before the first mark,
not the reveal itself. If completions are fine and second stories are in "worry", the end card needs a next stone, not
the story.

## Three engagement mechanics to test after the first data, not before

1. **A guess before the reveal.** During the suspicion beat, the question line offers the sectors ("Which did it
   change? Law · Health · Money · Tourism"); a tap records a guess (`ripple_guess`, right or wrong) and the reveal
   answers it. Turns the reveal into a payoff the reader has a stake in. Risk: a wrong guess can read as a quiz.
2. **A next stone on the end card.** "Same stone, another pond" and a surprising stranger ("Try: Furby → the NSA")
   on the card itself, with a 10-second auto-advance that a tap cancels. Measured by `via` = next.
3. **Surprise me.** A button that opens the non-obvious engine finds first (Sideways, Furby, Enron → 409A), since the
   owner's blind round rated non-obvious pairs as the product's reason to exist.

Each is a registered A/B only in the sense this project can afford: ship one at a time, compare the week's numbers to
the week before, and say so.

## Reading it

GA4 → Explore → Funnel: `ripple_story_start` → `ripple_reveal` → `ripple_verify` → `ripple_complete`. Free-form:
`ripple_leave` with dimension `t` and breakdown `reveal_reached`. The homepage's own traffic analysis (brief, Sep 16)
applies: the owner's sessions and datacenter hits must be excluded before any of this is read as audience data; an
internal-traffic filter on the property is the first thing to configure.

## Oct 5 addendum: the guess shipped before first data

Mechanic 1 shipped on Oct 5 at the owner's direction, ahead of the first 100 starts. The question line offers four
kinds instead of sectors, so every story has a fair answer: "A law or rule", "Something built", "How people live" and
"Nothing lasting" (right for a story with no lasting mark). Two events record it: `ripple_guess` (`pick`) on the tap and
`ripple_guess_result` (`pick`, `right`) when the answer first shows. One guess a story a visit; the running score lives
in the visitor's browser only. Localhost no longer sends events. Readings that span the release are split at the merge
commit of this change; the funnel before it is the baseline, and the comparison is the week after against the week
before, as above.

## Oct 7 addendum: the first reading and a change of view

The first week (Oct 1 to 6) landed in "worry" on reaching the reveal: about 12 of 47 visitors who started a story
(26%) once the review runs are removed, 21 of 56 as reported. Deviation disclosed: the protocol said nothing is sent
from a headless browser, but eight scripted review runs under a custom user agent were counted; the filter now also
drops any browser a script drives (`navigator.webdriver`). The parameters of `ripple_leave` were not registered as
custom dimensions, so the fall-off point could not be read. The response, the chain view, changes the layout and the
pace together; `docs/chain_view_v1.md` has the reading, the change, how the next week will be compared and a forecast.

## Oct 8 addendum: the answer view

The page now opens on the answer view (`docs/answer_view_v1.md`): a guess or "Skip the guess" shows the answer at
once. `ripple_story_start` carries `view: "answer"`; `ripple_reveal` carries `via` (`guess`, `skip`, `known` when a
shelf card already named the landing); the reveal rate is read on `guess` and `skip`. New event `ripple_knew`
(`knew` 1 or 0, `guess`), once per story per browser: the first surprise label from real visitors. The chain view ran
about a day, too short to score its forecast. Register `via`, `view`, `knew` and `guess` as custom dimensions before
reading.
