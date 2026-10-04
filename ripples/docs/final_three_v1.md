# The three fixes before release (Oct 4, 2026)

The three items named as the gap between an 8 and a 9: the phone's first screen, the statute links, and a confounders line per story. All three shipped the same morning.

## 1. The phone's first screen

Before, a phone saw 245 to 290 px of header before the pond (brand, title, a three-line subtitle, the tally and the story chooser). Now the tally and the chooser live under the pond beside the controls, the brand drops its tagline, and the subtitle shows two lines until tapped.

| Story, 390×844 | Pond top before | Pond top after |
|---|---|---|
| Squid Game | 290 px | 145 px |
| Sputnik (two-line title) | 332 px | 167 px |
| Tiger King (map) | 309 px | 145 px |

On a 375×667 phone the pond's top is at the same 145 to 167 px. Opening the chooser scrolls it into view. On a desktop nothing moves.

## 2. The statutes

Twenty-two law steps link to the law on govinfo; each link was confirmed against the PDF it resolves to. Details and the honest split (fourteen by text, seven by page structure, one by the public-law link itself) are in `sources_pass_v1.md`.

## 3. "It wasn't the only reason"

Every story (79 chains and 11 maps) now carries one editorial sentence under its title naming the other things going on when the mark was made, in `demo/context.json`. It is a claim about context, not data from the checker, and it is written to be checkable: a prior campaign, a law already introduced, a crisis the mark also answered. The share text carries it too, so a shared link never travels as "the show caused the law" alone.

## Also in this pass

A tap on a dense pond answers to the nearest ripple, not the one drawn last (the final roundtable's one defect), and a tap on the caption body puts the pond back.
