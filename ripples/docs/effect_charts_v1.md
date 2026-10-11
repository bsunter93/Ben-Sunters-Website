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

21 of the 49 one-study stories had a chart from their own text and abstract. The album and iPhone stories keep the
charts they already had.

## From the papers' full text (second pass, same day)

For the other 28, open copies were fetched (PubMed Central, NBER, IZA, university repositories; never SSRN; one retry
on a server error, then the host stops for the day). 12 papers covering 14 stories were reachable; Duke University
Press, the IDB, Wiley and JACR refused (403), and seven are paywalled with no open version found. Six more stories got
a chart: Sesame Street, the telenovelas and family size, the telenovelas and baby names, Ramayan and baby names, the
football upsets and juvenile sentences, and the Jolie op-ed and mastectomies. Each `fx` keeps `text_url`, the copy its
quote comes from, and `from` when that copy is an earlier version than the one cited ("the 2016 NBER working paper");
the chart key says so.

## No number anywhere: a result card

The 22 study stories with no number now show a result card instead of a calendar: the finding in words with its
direction (an arrow, never a length), how the study knows and its window; a busted or disputed story shows what was
claimed, struck through, against what was found. The caption above a result card keeps its date line only, so the
finding is said once. Myths stay on the result card even where the paper gives a null range (Finding Dory's imports
0.4 to 1.4 times expected): "claimed against found" reads more plainly than a range bar.

Open question: the football protests story cites the 2023 journal article, whose abstract singles out close losses;
the 2022 discussion paper version, the only open copy, says close wins raise protests about as much (0.6821 against
0.7152 percentage points). Its chart waits for a read of the published version.

No study story draws the calendar row now: 27 bars, 22 result cards, 2 charts of their own.
