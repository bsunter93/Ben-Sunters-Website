# Effect charts on study stories (Oct 11, 2026)

Most study stories are one hop: a stone and one finding. The chart drew them as a dot and the study's window on a
calendar, which showed when but not how much. A study story whose finding has numbers now draws the effect itself.

Three kinds, set in the study step's `test.fx`:

| Kind | Bars | Example |
|---|---|---|
| `pct` | what was expected (gray, with a dashed line through every row) against each finding's percent change | Super Bowl teams: +18% flu deaths over 65 |
| `levels` | the level before or without (gray) against the level after | A radio soap: family planning use from 19% to 28% |
| `groups` | the effect itself by group, from zero, in the paper's unit; a share is drawn out of 100 | Turnout: about +10 points in the nearest blocks, +3 to 4 a little farther |

A range ("15% to 20% fewer") is a solid bar to the smaller number and a light bar to the larger. The key under the
chart says what the bars measure. During the play the gray bar comes in with the stone and the finding's bars grow
when the study's row speaks. Every bar starts at zero.

## Where the numbers come from

Each `fx` keeps a `quote`: one passage copied word for word from the story's own effect text, its note or the
paper's abstract. Every number on a bar appears in that quote; only the sign changes for "fewer", "lower" or
"drop". The numbers were drafted by a fixed prompt (`effect_chart_v1`), checked by script against the quotes, and
read one by one.

21 of the 49 one-study stories have a chart. The other 28 keep the calendar row: their text and abstract give a
direction but no number (Sesame Street, the telenovelas, Fox News and sentencing), or the only numbers are a
disputed claim (16 and Pregnant, England against Argentina). Their numbers would have to come from the papers' full
text. The album and iPhone stories keep the charts they already had.
