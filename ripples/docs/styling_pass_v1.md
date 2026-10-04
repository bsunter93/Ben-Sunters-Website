# Styling pass v1: what was taken from the owner's mockups

Date: October 4, 2026. Inputs: an HTML styling mockup (abyss background, caustic overlay, glass buttons, a 24×24 icon system, a paper badge) and a drawn screen mockup of Tiger King → the Big Cat Act.

## Taken

- **The icon system, as the pond's own glyphs.** A lasting mark is now a hexagon with a lit marigold core, on the pond, in the tally, in the card pill, in the caption and in the legend. A measured step carries a crosshair. A plausible step carries a dashed orbit. The glyphs are plain SVG, no filters, so they cost nothing per frame and read at 2× on a phone. The ◆ text glyph is gone; the hexagon is drawn inline so no platform has to own a Unicode symbol.
- **A legend entry for the lasting mark.** The legend explained the five line styles but never the mark; it does now.

## Already there

- Layered radial depth (`#vig`, `#water`, `#shine`), the caustic overlay and the water light were built in the roundtable pass. The mockup's abyss gradient is the same idea with bluer values; the pond keeps its values because the five-grade palette was tuned against them.

## Declined, and why

- **Glass buttons** (`backdrop-filter: blur(16px)`). The engineer-role tester measured filters as the frame-budget problem, and three testers asked for less decoration. The controls stay flat.
- **Torn-paper feed edges and the paper badge.** Decoration the testers would read as "cheesy", the word the owner asked us to retire.
- **Blue origin stone and a blue-only palette.** The stone is matte basalt so the marigold mark and the green measured line stay the only warm and cool accents; a blue palette would drown the grade colors.
- **Category labels placed around the pond** (Regulation, Wildlife law, Movement). The map kind already draws its slice labels; a linear chain has no slices, and inventing them would be a claim about the data we have not checked.
- **"Origin stone" caption under the stone.** The stone already carries the story's name; a second line under it collides with the 1-day ring on a phone.

## The second mockup (the photographic pond)

A rendered pond: real water, a mossy stone, rings in ember, moss and coral, a data panel at the left, a US "exposure map", a week / a year / ten years axis, far-off outcomes that bob and send their own small ripple, drop sound off by default.

Already in the product: the time axis (1 day, 1 month, 1 year, 10 years on the rings), rings colored by grade, a tap opening a card with "How sure?", sound off by default, the far ripple's own pulse every seven seconds, the mark named in the title.

Taken from it: nothing further tonight. Two ideas are worth a later pass and are recorded here:

- **"It wasn't the only reason: [the other things going on]."** A one-line confounders sentence per story. It needs an editorial field per chain, not styling, and it is the most honest line in either mockup. Candidate for the next content pass.
- **The exposure map.** A US choropleth of "more exposure, bigger move" would need per-state attention or outcome data the catalog does not hold. Not buildable from what we have; noted so the idea is not lost.

Declined: the photographic water. The pond is an instrument drawn to scale (the rings are the dates), and a photograph under it would turn a measurement back into a picture, which is the "cheesy" problem in reverse. The ember-lit stone for a lasting mark is lovely in a still and reads as a second origin on a moving pond; the hexagon with the lit core carries the same "lit from beneath" idea at marker size.
