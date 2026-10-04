# Ripple, round five: the stranger's first ten seconds (Oct 4, 2026)

A simulation. The same twelve simulated testers as rounds four and the roundtable. Nine are fictional (Dani, Priya, Walter, Marcus, Yuki, Earl, Aisha, Tom, Lena); three are simulated personas modeled on the public roles of Thomas Kurian, Elon Musk and Mark Zuckerberg, labeled as such wherever they appear, not those people's words. This round asks one question the earlier rounds did not: what does a stranger see in the first ten seconds, before anyone explains anything, on the build after the owner's review (PRs #86 to #89: the chart bug, the beat schedule, the reel cut, the look).

Build: `ripple-standalone.html` from main at 76df3f07. Measurements ran in headless Chromium through Playwright, one context per viewport, scripted in `stranger_probe.js` (session scratchpad), screenshots at 0, 3 and 10 s.

## Part 1: measurements, before anyone speaks

| Viewport (persona) | Opening screen | Pond top / height / on the first screen | Header above the pond | First narration line | Labels on at 10 s | Smallest pond text |
|---|---|---|---|---|---|---|
| 390×844 touch (Dani) | none; the story plays | 148 / 183 px / 100% | 103 px, 67 words | 3.1 s | 2 | 11.0 px |
| 360×800 touch (Marcus) | none | 148 / 167 / 100% | 103 px, 67 words | 3.2 s | 2 | 11.0 px |
| 375×667 touch (Lena) | none | 149 / 175 / 100% | 103 px, 67 words | 3.1 s | 2 | 11.0 px |
| 1440×900 mouse (Aisha) | none | 363 / 343 / 100% | 299 px, 94 words | 3.1 s | 2 | 13.0 px |
| 1093×614 at 1.25 (Earl) | none | 363 / 300 / **84%** | 299 px, 94 words | 3.1 s | 2 | 13.0 px |
| 1280×720 (Yuki's projector) | none | 364 / 343 / 100% | 299 px, 94 words | 3.1 s | 2 | 13.0 px |
| 820×1180 touch (Walter) | none | 382 / 403 / 100% | 327 px, 94 words | 3.2 s | 2 | 14.0 px |

Also checked: `tap_test` 0 wrong taps on four phone ponds; `header_test` pond top 145 to 167 px; `chart_test` 0.0 px over its column, no animation; `pace_test` Tiger King 31.6 s, Sputnik 38.4 s, Prohibition 78.8 s, no two beats under 3.0 s apart. The intro screen is gone on every viewport. Rim words are off on the three phones (by design since #89) and italic annotations on the rest.

Two findings from the table:

1. **The desktop header costs a third of the first screen.** 299 px and 94 words before the pond; on Earl's laptop at 125% the pond's lower sixth, and the narration line with it, sit below the fold while the story plays. The second header paragraph ("What followed and stayed … Order, not proof of cause.") is the cost. Fix proposed: one line that expands on tap, as the phone already does with the subtitle.
2. **At 10 s a stranger sees two labels.** That is the beat schedule doing its job (the second beat lands at 6.4 s), not a defect; but a reader who does not wait sees a quiet pond. The first beat is named at 2.4 s, which is inside the window.

## Part 2: one line and a number each

**Dani (16, phone):** "It just starts. No splash screen asking me to click a thing, the stone goes in, and three seconds later it tells me what the first ring is. 8."

**Marcus (warehouse, Android):** "I can read it. The words are on the water, not in little boxes, and nothing's glowing at me. 8."

**Lena (student, iPhone SE):** "It fits my screen now and it doesn't look like every other dark-mode app. The small type is still small. 8."

**Aisha (data journalist, laptop):** "It looks like a graphic my desk would run, not a dashboard. The header still says four things before the picture; cut it to two. 8."

**Earl (dispatcher, colorblind, laptop at 125%):** "Flat and legible, and the lines still mean what the legend says. On my screen the bottom of the pond is under the fold while it plays. 7."

**Yuki (history teacher, projector):** "Thirty seconds a story is right for a room; I can talk over it. The narration line is what the back row reads. 9."

**Tom (retired machinist, iPad):** "Serious now. It stopped trying to be pretty and got better looking. 9."

**Priya (product manager):** "The first screen finally leads with the product. The header is the last thing that reads like a brief. 8."

**Walter (retired internist, tablet):** "It waits and it speaks. One name every three seconds I can follow. 9."

**Kurian persona (simulated persona modeled on the public role of Thomas Kurian; not his words):** "The look matches the rigor now; the pipeline still runs on branches. 7."

**Musk persona (simulated persona modeled on the public role of Elon Musk; not his words):** "Less to render, more to read. Fine. 7."

**Zuckerberg persona (simulated persona modeled on the public role of Mark Zuckerberg; not his words):** "No interstitial, play on load, a share link on every step: the loop is as short as it gets. 8."

| | Round four | Final (Oct 4, 05:00) | **Round five** |
|---|---|---|---|
| All twelve, average | 7.2 | 8.2 | **8.0** |

The average is a tenth lower than the final roundtable because the question changed: these are first-ten-second scores on a build none of them had seen, not re-ratings after fixes. Nobody scored it below 7.

**Builder's own rating after this round: 7.5**, up from 6.5 on pickup. What moves it: the header fold (a fix), a stranger's sentence (release), and the clips cut on this look.

## Actions

| Finding | Action | Status |
|---|---|---|
| Desktop header 299 px before the pond | Second header paragraph becomes one line, expands on tap | open, next pass |
| Pond bottom under a 614-px fold at 125% | Same fix; re-measure Earl's viewport | open |
| Small type on the SE | Unchanged from round four; the caption and cards carry the text | accepted |
| Clips | Record and encode on this look (HANDOFF section 5) | after the discovery sprint |
