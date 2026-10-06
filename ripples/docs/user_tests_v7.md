# Ripple, round seven: the guess, the search and three more strangers (Oct 5, 2026)

A simulation, plus one real note. The real note came from a visitor through the owner: "the search bar should be more
visible." The three testers are simulated and fictional, as every tester in this project is: **Gloria**, 67, a retired
newspaper copy editor on an iPad (820×1180, touch); **Marcus**, 41, a high-school debate coach on a school Chromebook
(1366×768, mouse); **Priya**, 29, an ER nurse on a phone during a break (390×844, touch, one hand). Each one's item was
measured before they spoke, in headless Chromium through Playwright, one context per tester, on the build of this change
(main at e2d3222 plus the search change; standalone md5 34548688389efbd62d588ab03769f13e, then 4beee527bcc50fc4b1c7f603011bf3fd
after the fixes below).

## The real note: search

Before this change the search box sat inside the story chooser, so nobody saw it until they opened "Change story".
Now the box is in the header bar beside "Change story" on laptops and tablets, with a magnifier and the count ("Search
236 stories"); typing opens the results. A phone keeps its pond where it was: a round search button sits at the top
right of the header and opens the chooser with the box focused. `tools/qa/search_test.js` checks it at eight sizes and
two stories: on screen at load, clear of the title (answered, line by line), the tagline, the wordmark and the tally,
and typing a word shows results. 16 of 16 pass.

## Part 1: measurements, before anyone speaks

| Tester | What was checked | Measurement | Pass? |
|---|---|---|---|
| Gloria (820×1180, touch) | Reading load at load and at the reveal; the guess chips for a fingertip | Smallest text on screen **11.5 px**, the key's note "Measured: beat a placebo test…"; on screen at load: Measured, Timed, Reported, Plausible, "lasting mark", **placebo**; guess chips **27 px** tall | Fails on the note and the chips |
| Marcus (1366×768, mouse) | Find a story he knows by name and use it in class; something to cite | Search box at the top right, 200×40, on screen at load; "jungle" and Enter opened The Jungle → the FDA in 1.5 s; first card 638 to 757 on a 768-px screen; 7 source links on the cards; **0 "Copy citation" links** (they exist only on Engine leads) | Search passes; citation fails |
| Priya (390×844, touch, one hand) | The guess within reach of a thumb; time to the payoff; the verdict on screen when it lands | Chips at **y 90**, 28 px tall, at the top of the screen; the title answered **25.4 s** after her tap; the verdict "Right. A law or rule: Big Cat Act becomes law." on screen at the reveal | Verdict passes; reach and wait are weak |

## Fixes made in the hour, re-measured

| Finding | Fix | After |
|---|---|---|
| Search hidden in the chooser (the real note) | Header search box; a phone search button | On screen at load at 8 sizes, 0 overlaps |
| Gloria: "placebo" and 11.5-px type in the key's note | The note says "the rise beat the same test run on fake dates"; 12.8 px | Smallest note text 12.8 px |
| Gloria and Priya: small guess chips | Each chip answers a taller touch area with no change to the row | Tap height **41 px** on the iPad (was 27); **35 px** on a phone (was 28), where the pond begins right under the row |

## Part 2: one line and a number each

**Gloria:** "It asks me a question before it tells me anything, and I like being asked. The words under the water read
like a caption a person wrote. The little note under the pond used a word I had to look up, and now it doesn't." **8**
(7.5 before the fixes)

**Marcus:** "I typed 'jungle' and I was in the story before I finished my coffee. The chain from a novel to the FDA is a
debate round by itself. What I need next is one button that gives my students the claim, the date and the source in a
line they can paste; the share link isn't a citation." **8**

**Priya:** "I got the question right and the page told me so, which felt good. It took about half a minute to get there,
and I had to reach up to the top of the screen with my thumb to answer. On a break I'd rather tap at the bottom and get
the answer sooner." **7.5**

| Tester | Rating |
|---|---|
| Gloria, copy editor | 8 |
| Marcus, debate coach | 8 |
| Priya, nurse | 7.5 |
| **Average** | **7.8** |

Round six (Theo, Marisol, Kwame) averaged 8.0 on the reveal build. This round measured the guess for the first time.
Nobody missed the guess or misread it; the two complaints are where it sits on a phone and how long a phone waits for it.

## Open, and what was built the same night

- **Built:** a "Copy citation" line on every card that shows a source (Marcus). It reads the stone, the step, its date,
  the grade, the lasting mark if any, the source and its link, the reader's own access date and a link back to the step.
  Coverage measured: Prohibition 25 of 25 cards, Sputnik 9 of 9, Frozen 4 of 4, Cathy Come Home 18 of 18, an Engine lead
  1 of 1, Tiger King 7 of 8 (the license card shows no source line, so it gets no citation).
- **Built:** on a phone the guess sits in a row under the pond, above the controls (Priya). Chips at y 434 of 844 and
  425 of 667 (was 90), tap height 43 px (was 28); the header keeps one line ("What changed after this? Guess below."),
  so the pond starts at 126 px (was 160). The verdict shows in the same row. Laptops and tablets keep the guess in the
  header.
- 25 s to the reveal on a phone (Priya). The pace was set by the owner on Oct 4 ("way too fast"); not changed here.

Builder's rating after this round: **8.5**, unchanged. The search answers the real note. The round's two open items are
real and cheap enough for the next pass.
