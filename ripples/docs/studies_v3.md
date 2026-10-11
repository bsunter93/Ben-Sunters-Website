# Three study stories from the owner's ratings (Oct 11, 2026)

The owner rated 50 findings blind: surprise on the claim alone, then belief and "would you tell someone" with the
evidence. Of the findings he rated 4 or more on surprise and belief, these three are peer reviewed, passed the v4
checks (quote, date order, design) and were not on the site. Each is in `chains/batch19.json` under "From published
studies".

| Story | Paper | Finding |
|---|---|---|
| `study-shootings-turnout` | Science Advances, 2025 (doi 10.1126/sciadv.adx5418) | Almost 10 points higher turnout in the census blocks nearest a public mass shooting before the 2016 or 2020 election, 3 to 4 points a little farther out; no change in presidential vote choice. |
| `study-shootings-alcohol` | PNAS Nexus, 2024 (doi 10.1093/pnasnexus/pgae570) | Weekly alcohol sales in the three-digit ZIP area rose 3.5% for two years after a mass shooting (p = 0.048 across all shootings), 5.5% after public shootings, none after shootings in homes. Marked Behavior: the paper finds the rise still in its third year. |
| `study-chile-dst-crashes` | Health Economics, 2025 (doi 10.1002/hec.4936) | 2.7% fewer car accidents under daylight saving time in Chile, 2002 to 2018, though 6% more in the first week after the clocks go forward. |

Numbers come from the full text for the two open-access papers (PubMed Central) and from the abstract for the Chile
paper. Each carries the authors' own reason, quoted from its abstract (`docs/why_lines_v1.md`). The alcohol paper's
weekly figure has about 480 overlapping points with their ranges, too dense to read back honestly, so all three draw
the standard study row: the study's window and its headline number.

## Layout fix in the same change

The lake header had a fixed height (330 px, 260 on a phone) and the sheet below it overlaps it by 46 and 30 px. A long
headline plus a why line ran under the sheet on phones and was cut mid-sentence. The header now grows with its words,
the phone header keeps 44 px clear at the bottom, and the water redraws when the header changes size.
`tools/qa/why_test.js` now also checks that the sheet starts below the why line; it fails 24 of 62 cases on the old
layout and passes all of them now.
