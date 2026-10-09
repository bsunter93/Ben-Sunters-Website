# UI pass, the ripple chart (Oct 9, 2026)

The owner asked for the chart view to be more readable, more intuitive and quieter on a laptop and a phone. Each change
below was measured on the same 241 stories before and after, every story at rest at 1440x900 and 390x844. The lake, the
stacked lines, the grades and every story are unchanged.

## 1. Stories with no line

197 of 241 stories have no attention line. Each of their rows drew a full-width baseline with one dot on it, on a log clock,
with no words. The plot looked empty and the time between steps could not be read.

Now each step hops from the step before it. The hop drops from the earlier mark and runs right to the new one, to scale on
the calendar, and the time it took is written on it ("4 weeks", "24 years"). A study step shows its window as a pale band
and its effect beside the mark ("+18%"). A busted step says "busted" beside its red cross. When every step sits on the
stone's own date (22 stories, most of them single studies), the chart drops the clock and its grid and shows the two marks
one under the other. The rows animate as hops when the story plays.

| | Before | After |
|---|---|---|
| Rows that were a baseline with one dot | 624 | 0 |
| Stories with no line that write the time between steps on the chart | 0 of 197 | 176 of 197 |
| Words on the chart for gaps, effects and busted steps | 0 | 422 |

Stories with lines keep their stacked lines on one shared scale.

## 2. The clock

Every story ran on log time since the stone. A study from 1946 to 1970 gave most of its width to the first weeks.

The clock is now picked from the story. A story with lines and a span under 8 years keeps log time since the stone, since
its lines sit in the first weeks (Tiger King, Squid Game, Chernobyl). Every other story runs on the calendar, with ticks at
round dates: years for long spans ("1950", "1960"), months for spans under about two years ("Dec 2011", "Jan 2012", "Feb")
and days for spans of a few weeks ("Apr 15").

| | Before | After |
|---|---|---|
| Stories on log time / calendar / no clock | 241 / 0 / 0 | 38 / 181 / 22 |
| Share of the width given to the first year, median over the 70 stories that span 8 years or more | 61% | 4% |

## 3. The caption

The kicker stacked up to six facts ("Where it landed · Dec 20, 2022 · 2 years 9 months after · a lasting mark"). It now says
the date and one fact: the time since the stone, the peak of readers, the study's effect, "busted" or "unproven". The small
mark before the headline is the row's own mark on the chart: a hexagon for a lasting mark, a red cross for a busted claim, a
short line in the row's color for a line.

| | Before | After |
|---|---|---|
| Facts in the kicker, mean (max) | 3.98 (6) | 2.0 (2) |

## 4. The controls

The footer held five controls: Next, Share, Play again, and "New to you? Yes / I knew it". Next is now the one amber button
and Share the one outlined button. Replay (Skip while the story plays) is a small control at the top right of the chart.
"New to you?" appears once the play ends, as one line of plain text buttons. The arrow after "Next: The Jungle" is gone.

| | Before | After |
|---|---|---|
| Controls in the footer while the story plays | 5 | 2 |
| Controls in the footer at the end | 5 | 2, and the "New to you?" line |

## 5. The header

"Change story · Lasting marks" opened the list of every story and named a tab inside it. The button now reads "All
stories" and is outlined, so Next is the only amber control on the page. The search is unchanged. The chooser it opens got
the same type sizes and 44 px targets.

## 6. The shelf

The shelf showed eight cards in each of five groups. It now shows one row of four on a laptop and three on a phone, with
"Show all" for the rest. The group names are plain: Everyday life, Myths, checked, Things built, Laws and rules, Nothing
lasting yet. A card's grade sits on the left of its last line and the time to the mark on the right. On a phone each card
puts the year beside the stone's name.

| | Before | After |
|---|---|---|
| Cards shown | 40 | 20 (laptop), 15 (phone) |
| Shelf height, 1440x900 | 2,198 px | 1,450 px |
| Shelf height, 390x844 | 4,233 px | 2,561 px |

## 7. Type, contrast and targets

One scale now runs through the view: 13 px for chart labels, dates and counts, 15 px for body text and controls, 17 px
under the title, and the display sizes for the caption and the title. Dates and numbers use tabular figures. The light
gray on the paper (`--paper-ink-3`) went from 3.1:1 to 4.9:1, the amber words on the paper from 4.0:1 to 5.6:1, and the
peak numbers take their line's color mixed toward the ink (4.6:1 or more, was 2.6:1 to 4.8:1).

| Tiger King at 1440x900 | Before | After |
|---|---|---|
| Visible text under 13 px | 94 | 0 |
| Text below 4.5:1 | 21 | 0 |
| Controls under 44 px tall or wide | 12 of 54 | 0 of 34 |

The wordmark is left out of the contrast count. It is drawn on the dark header, and the audit read it against the paper.

## 8. The Super Bowl story

Its title said "A Super Bowl team (1974)" for an effect measured over the 1974 to 2009 seasons. It now reads "Super Bowl
teams (1974 to 2009)", and the stone shows "1974 to 2009" where it showed "1974". A stone's step can carry a `window`, and
the page shows it in place of the year.

## Smaller fixes

- The key's amber swatch shared a class name with the header bar and picked up its top margin. It has its own name now.
- Shelf cards no longer lift on hover.
- The answer under "New to you?" is one line.

## Checks

`tools/qa/answer_test.js` changed with the caption: it no longer looks for "Where it landed". It now also checks that the
caption shows at most two facts, that "New to you?" stays hidden until the play ends, and that no chart label sits outside
the panel for any story, and it prints how many stories without a line write the time between steps and which clock each
story uses. The other six scripts are unchanged. All seven pass against a local server.

## Left for later

- Sparse charts need data: daily readers for every step that has its own Wikipedia page
  (`docs/ripple_chart_v1.md`, "The gap this shows").
- Stories on log time (Tiger King and 37 others) do not write the gap between their steps, since a log clock does not draw
  it to scale.
- Six long stories with lines moved to the calendar (Prohibition, Haber's ammonia, Three Mile Island, Columbine, Flint,
  The Daily Show and Zadroga). Their lines start in 2015, so they draw as thin spikes near the right edge.
- A story with many lasting marks draws many amber bars (September 11 has eight). A thinner bar for marks other than the
  answer would quiet it.
- The chooser sorts stories as Lasting marks, Fact-checks and Engine leads, and the shelf sorts them by what they left
  behind. One scheme would be easier to learn.
- The search box counted 274 stories and the chart view draws 241. Fixed Oct 9: the box counts the 241 stories the search reaches.
- The older views (`?view=chain`, `?view=pond`) were not touched. The pond view's phone search button is 40 px.
