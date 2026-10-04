# Ripple, round six: three more strangers meet the reveal (Oct 5, 2026)

A simulation. Three net-new simulated testers who have never seen the product, chosen to cover the rule set on day one
that a 12-year-old must get it: **Theo**, 12, on a school iPad (820×1180, touch); **Marisol**, 52, an AP Government
teacher on a classroom Chromebook (1366×768, mouse); **Kwame**, 29, a product designer at a consumer app (MacBook Pro,
1728×1117 at 2×). Fictional, as every tester in this project is. Measurements ran on production
(bensunter.com/ripples/demo, main at cdd4bd38) in headless Chromium through Playwright, one context per persona
(`rt3_new.js` in the session scratchpad), before anyone spoke. Fixes from the measurements were made the same hour
and re-measured on the build.

## Part 1: measurements, before anyone speaks

| Persona | What was checked | Measurement | Pass? |
|---|---|---|---|
| Theo (820×1180, touch) | No instructions: the first screen, the reading load of the narration, the reveal, a tap on a mark, the Change story button | Title "Tiger King → ?", subtitle "Something changed after this. Follow the water.", tally "? lasting marks"; the button 243×39 px in marigold; reveal at 15.6 s; a tap dead-center on the law hit the law (31-px target). **Narration lines averaged 29 words, the verification line 57, and the clue line carried "p = 0.013"** | Reveal and taps pass; the reading load fails the 12-year-old rule |
| Marisol (1366×768, mouse) | Prohibition at rest for a lesson; the chooser's layers; the Engine leads tab | 5 labels at rest, 0 overlapping; 4 busted-claim cards, each with a glyph beside "Busted"; chooser opens to three kind cards with no chips showing; Engine leads grouped ("From attention", "From Parliament and Congress", "From Wikipedia's record · 1950s" …), 72 chips. **The pond's foot at 795 px and the legend at 881 on a 768-px screen**: the short-screen rule began at 700 px, and the classroom Chromebook is 768 | Legibility passes; the fold fails |
| Kwame (1728×1117 at 2×) | The design bar: proportions, type, motion, affordances | Pond 1,067 px against a 560-px card column (1.91:1); title 46 px; 4 running animations during play, 3 at rest; "Learn more" on 9 of 10 cards, a glyph on 10 of 10 grade badges; reveal at 15.4 s with the title's resolve animation running and the arrow dotted for a plausible weakest link; 7 labels at rest, 0 overlaps | Pass |

## Fixes made in the hour, re-measured

| Finding | Fix | After |
|---|---|---|
| Statistics on the narration line; long lines | The lower third drops p-values and placebo counts (they stay on the card, one click deeper); the verification line is one short sentence per grade plus "Order, not proof of cause", and its context clause is cut at 110 characters | Clue line: "Clue 1 of 4 · Mar 2020 · +3 days · The zoo at the center of the show · Measured · Attention 1280× normal · A lasting mark is 4 ripples away"; lines average 27 words, the longest 47 (was 57) |
| Chromebook fold | The short-screen rule (pond letterboxed, legend as a corner panel) now applies up to 820 px tall | Pond's foot at **694**, legend at **435**, on a 768-px screen |

## Part 2: one line and a number each

**Theo:** "It asked me a question and then it showed me clues, so I waited to see what the answer was. The law came up and
the title finished itself, which was cool. The words under the water were a lot to read on the first try." **8**

**Marisol:** "I could run a whole period on Prohibition from this: four claims my students believe, each one marked
busted with a reason, and the question of what 'in order' proves. On my cart's Chromebooks the bottom of the pond was
cut off, which would have killed it in a classroom; it fits now." **8** (7 before the fold fix)

**Kwame:** "The reveal is the product. Withholding the title and resolving it when the law lands is the one idea here
that a competitor would copy. The rest is disciplined: one accent, glyphs that mean something, the pond nearly twice
the notes. Nine identical 'Learn more' rectangles down the right side is the one place it looks like a template." **8**

| Persona | Rating |
|---|---|
| Theo, 12 | 8 |
| Marisol, teacher | 8 |
| Kwame, designer | 8 |
| **Average** | **8.0** |

The previous three strangers (Rosa, Dev, Jaz, Oct 4) averaged 7.3 on the build before the reveal and the readability
pass. Their three complaints then were the late payoff, the wall of chips and the gray grades; none of the three new
testers raised the first two.

## Open

Kwame's row of identical "Learn more" buttons; the title's answer and the first mark are sometimes different things
(Tiger King resolves to the Act when the license lands); the engine's grades remain reported by nature. Builder's
rating after this round: **8.3**.
