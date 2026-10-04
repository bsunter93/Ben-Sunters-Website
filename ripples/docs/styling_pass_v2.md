# Styling pass v2: the look after the owner's review (Oct 4, 2026)

Date: October 4, 2026, 09:00 to 10:30 UTC. Input: the owner's review of the live page on the morning of release-readiness: "weird visual bugs", "the playthrough is WAY too fast and not visually interesting enough", "break this out of the cartoony wireframe look and make it look like a serious, credible app; worried about people calling this AI slop before even giving it a chance." Supersedes nothing in `styling_pass_v1.md`; it removes most of what that pass kept.

## What read as a template, and what replaced it

| Tell | Why it read as generated | Now |
|---|---|---|
| A dusk gradient behind everything, two drifting sheens | The most common generated-landing-page surface on the web: saturated navy-teal, radial glows, a gold pill | One flat, desaturated slate surface (`--stage #0f1c26`); the sheens are gone and so is their idle cost |
| The pond as a boxed, vignetted, radially lit disc | A dashboard widget, lit from beneath | No box: the field is the page's own color; the disc has a hairline rim and one faint top light; no vignette, no radial water glow, no wavefront glow |
| Rim words in letterspaced capitals (REGULATION · WILDLIFE LAW · CHARITY) | A radar screen | Italic Fraunces, sentence case, the size of a print annotation; off entirely on phone ponds, where the labels need the room |
| Dashed sector spokes | Radar again | Gone; the rim word and the position carry the sector |
| Ripple labels in rounded dark boxes, marks in paper boxes | Floating UI chips over a diagram | Plain type with a halo in the water's color so it reads over the rings; a mark's name set in ember, the one color that means it; a hairline box only on the focused label |
| A shaded, highlighted stone | A cartoon rock | A matte disc, one faint highlight |
| A centered hero ("Throw a stone. / See what it changed.") over a glowing gold pill and a "Just look around" link | The template opening screen | Retired. The page opens on the pond and the story plays; the title and the "It wasn't the only reason" line are the first words read |
| Pill-shaped controls, round play and icon buttons, rounded 14 to 18 px corners everywhere | Consumer-app chrome | 6 px corners on controls, 8 px on cards, 10 px on the pond; grade badges are small capitals with a hairline, not pills |
| A ten-second trailer that burned 2.8 years in ten seconds | Nothing landed | A beat per ripple with a narration line (PR #87), and a separate edited cut for clips (PR #88) |

Kept, because they carry meaning: the three colors (ember for marks, moss for measured, coral for busted), the weakest-link arrow in the title, the big Fraunces date, the hairline time rings and their ladder, the paper reading surface for the cards, the hexagon, crosshair and dashed-orbit glyphs, the wordmark.

## Measured

- `tap_test`: 0 wrong taps on four phone ponds (unchanged). `header_test`: pond top 145 to 167 px on a 390 and a 375 (unchanged). `chart_test`: 0.0 px over, no animation. `pace_test`: Tiger King 31.6 s, Sputnik 38.4 s, Prohibition 78.8 s, no two beats under 3.0 s apart.
- Share cards regenerated on the new look (`node cards.js`): 37 cards and stubs.
- The page's idle cost should fall with the two body sheen animations gone (the final roundtable measured them as the whole idle bill at rest); not re-measured in this pass.

## Not done, on purpose

- The clips are not recorded. They are cut once, after this pass lands (`HANDOFF.md`, section 5).
- The header's second paragraph ("What followed and stayed … Order, not proof of cause.") stays. It is the honesty copy and the roundtable's data journalist cited it; it is long, and a later pass may fold it.
- No persona round has seen this look. The next step is one round scored on a stranger's first ten seconds.
