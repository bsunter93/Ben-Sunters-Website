# The reveal, v1: from "here are the results" to an investigation (Oct 5, 2026)

The owner's note, Oct 5: inject "magic" by changing the reveal mechanics, not the discovery or the polish. "Right now the
prototype is primarily structured like an interactive research visualization: catalyst → ripple → evidence → outcome.
I'd experiment with making it feel more like investigation / discovery: catalyst → suspicion → clue → reveal →
verification → consequence."

## What was true before

The title printed the answer at second zero ("Tiger King → the Big Cat Act"), the tally counted the marks, and the
subtitle disclaimed before anything had happened. The three strangers in the second roundtable said it without the
vocabulary: "nothing I'd screenshot had happened by the time I'd normally leave."

## The choreography, as built

| Beat | What the page does | When (Tiger King, 1440×900) |
|---|---|---|
| Catalyst, suspicion | The title shows the stone and a question mark ("Tiger King → ?"), the tally "? lasting marks", the subtitle one italic line: "Something changed after this. Follow the water." The stone is thrown. | 0 to 2 s |
| Clues | Each ordinary beat before the first lasting mark is "Clue 1 of 4 · …" in the narration, and the promise line says "A lasting mark is 3 ripples away" without naming it. | 2 to 15 s |
| Reveal | The first lasting mark lands lit while the pond dims; the title resolves in place (the arrow draws in its weakest-link style, the answer fades in), the tally's "?" becomes the count, a chime plays if sound is on. | 15.3 s |
| Verification | A beat of its own with no new ripple: "Checked · Tiger King came first, Mar 20, 2020; License suspended 5 months later · weakest link plausible", one sentence on what the weakest grade means, and "It wasn't the only reason" arriving here, under the title as well. | 19.4 s, 3.4 s long |
| Consequence | The end card as before: the span, what stayed, the arrow from the weakest link. | 28 s |

Rules kept: nothing is hidden from a reader who arrives at the answer. A deep link to a step, the rest state, a pause,
a scrub, Step mode and a tap on a ripple all show the full title, tally and subtitle at once. Share pages and cards
carry the full title. The reel cut withholds the title until its first mark shot, then resolves it, so the clips carry
the same suspense (re-recorded on this build).

Where the title names a later mark than the first (Tiger King's title is the Act; its first mark is the license), the
reveal still happens at the first mark: the question "did anything stick?" is answered there, and the title's answer is
the bigger one still to come.

## Measured

`fold_test.js` (phone, 390×844): the first lasting mark at 15.3 s, the promise line at 2.2 s. `pace_test.js`: Tiger King
28 s, Sputnik 35 s, Prohibition 76 s with the verification beat included. Deep link with a step: full title, stopped.
Pause at 3 s: full title. Reel: "Sideways → ?" at 1.5 s, resolved by 6.5 s. All five QA scripts pass.

## Not yet

The reveal has no sound of its own beyond the existing ping; the title's resolve is a fade, not a draw; the three
strangers have not seen it. Those are the next round's questions.
