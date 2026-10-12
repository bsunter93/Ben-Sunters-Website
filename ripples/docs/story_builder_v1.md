# The story builder (Oct 12, 2026)

Owner, Oct 12: "build the auto story builder." Until now every study story on the page was built by hand: the numbers
pulled from the paper, a chart chosen, a why line written, the note and the dates set. Discovery v5 produced 57
defensible findings in one run; the page had 48 study stories. The builder turns a verified finding into a story the
page can show, and nothing ships unless a script has checked it against the paper.

## Stages (`ripples/engine/build/`)

1. **select** (`stories.py select`): a run's defensible findings, the owner's rated ones by default, with the evidence
   verification read, the paper's record and the author why line from `enrich/judged.py inputs --candidates`.
2. **texts** (`enrich/fulltext.py --targets`): each paper's full text from PubMed Central or an open copy (never SSRN),
   else its abstract. A paper with no DOI is looked up by its OpenAlex id.
3. **words** (judged, `build/story_prompt.txt`): the title, the stone's sentence and date, the headline, the short form,
   the design, the effect sentence and the passage holding its numbers, the note's quote, the window. No reasons.
4. **numbers** (judged, `enrich/fx_prompt.txt`, unchanged): the chart's numbers and their quote.
5. **assemble** (`stories.py assemble`): the checks below. The source line, DOI, grade and working-paper label come
   from the paper's record and the verification verdict, never from the judged step.
6. **preview** (`stories.py preview`): the page as one file with every draft in it.
7. **apply** (`stories.py apply --checked`): ships the drafts a rule allows into a chains file and the page's data.

## The checks (a draft fails; nothing is repaired)

- the step skipped it, or a field is missing or too long (label 5 words, headline 12, short 4, design 20, effect 30)
- an em dash anywhere shown, or a semicolon outside the paper's own quoted words
- a date that does not parse, a window that runs backwards or past today, a stone after the paper
- the effect passage or the note's quote is not in the abstract or full text word for word (whitespace collapsed)
- a number in the headline, the effect or the big number that is not in the effect passage (the headline may round to
  a whole number)
- a slug already taken
- an effect chart whose unit is a ratio is dropped (no zero to grow a bar from); the story keeps a result card

When the texts date the stone but give no study window, the window is the stone's year and the step's note says so.

## The ship rule

`owner-good-peer`: the owner rated the finding good (surprise 4 or more on the claim alone, belief 4 or more after the
evidence) and it is a peer-reviewed article. Working papers, theses and repository copies stay drafts. `--ids` ships
exactly the drafts named.

## The page

A built story has no hand-written line in the page's story list. `autoLeads()` gives it one from its own fields (the
title's name, an arrow, the finding's short form) and files it with the other study findings, so the shelf, the
search and the headline find it. A share of 100 that falls (a drop in turnout) draws a bar, not a grid of 100 with
nothing lit.

## First run: discovery v5 (Oct 12)

Selected: the owner's 30 rated findings. Full text for 9, abstracts for 20, nothing reachable for 1 (its harvested
abstract was used).

| Result | Count |
|---|---|
| Drafts that passed | 25 of 30 (15 with an effect chart, 10 with a result card; 14 with an author why line) |
| Failed: no date anywhere in the texts | 5 (Medellín soccer, two Tinder findings, Uber wages, the autumn clock change) |
| Shipped by the rule (batch 20) | 2 |

Shipped: `study-mexico-quake-sexual-abuse` (Feminist Economics, 2024: sexual abuse up 11% and rape up 12% after the
September 2017 earthquakes) and `study-japan-quake-political-groups` (Journal of East Asian Studies, 2019: 6% more
participation in political groups in the regions the 2011 disaster hit hardest). The third good finding, violent
tornadoes and higher wages, is a University of Kentucky dissertation and stays a draft.

Read by a person before shipping: both shipped stories, against their abstracts. Fixed in the builder from that read:
a paper title stored in capitals is cased the way a journal prints it, and a label that already holds its year is not
followed by the year again.

Known gaps: the words step fills a missing window inconsistently (some batches leave it blank, some use the stone's
year); the next prompt version should say which. Five findings fail only for want of a date that a person could look up.
