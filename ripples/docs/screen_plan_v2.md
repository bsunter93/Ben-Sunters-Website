# Screen plan v2: the written definitions, plus a dating step (registered Oct 5, 2026)

Follows `docs/screen_v1.md` (the bar was not met: precision 0.86, recall 0.56, 0 decoys). The owner ruled on Oct 5 that
**the project's written definitions of a lasting mark govern**. Hand keeps that violate them are disregarded: relief
funds, temporary measures, country bans of the work itself, tourism and the stone's own company. This plan is committed
and pushed before any v2 lookup or label. Deviations will be disclosed in `docs/screen_v2.md`.

## What v2 is

**Rubric v2 = rubric v1 (`lab/discovery/screen_rubric.md`, unchanged) plus a dating step.** No v1 judgment is
revised. `is_mark`, `link_label`, `disputed`, the reason codes, the flags and the scores are the v1 labels as pushed in
`8f41b92`. Only `date_ok` changes, and only through the dating step:

1. **Who is dated.** Every candidate whose v1 label failed only for the date: `is_mark` true, `link_label` reason,
   `disputed` false, reason code `undated`. That is 64 of the 583 evaluation candidates and 25 of the 192 in the
   never-screened pool.
2. **The mark's record.** For each one, the labeler has named the mark's own record: a Wikipedia article title, or
   null when the mark has none (a behavior change, an unnamed law, a local rule). The list is
   `docs/results/screen_dating_inputs_v2.json`, committed with this plan, before any lookup: 30 named, 59 null, each
   null with its reason.
3. **The lookup** (`lab/discovery/screen_date.py`). The Wikipedia API under the honest user agent
   `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)`, at most one request a second, and a stop on any
   403, 429 or 5xx with no same-day retry. Redirects are followed. A redirect to a page whose title shares no word of
   four or more letters with the named title is a different subject, and the mark stays unresolved.
4. **The date.** The order of `lab/discovery/order.py` without its lead fallback, because v1 found lead dating wrong
   for Acts that recount their history. First the first year in the title. Otherwise the first year in an infobox
   field: enacted, signed, royal assent, ratified, adopted, formed, founded, established, effective, passed, formation,
   inception, start date, created or opened, plus a taxon's authority year for a species naming. For a statute that
   yields no year this way, the fallback is govinfo (US) or legislation.gov.uk (UK) under the same agent and limits. The
   source of every resolved date is recorded: page, field and year.
5. **The ordering rule on the resolved date.** Resolved year at or after the stone's year: `date_ok` true. Before:
   `date_ok` false, reason code `bad_timing`. Unresolved or null record: unchanged, `undated`.
6. **The gate** is recomputed exactly as in v1. A newly passing candidate that states a mark an earlier accepted
   candidate in the same set and stone already states is a `duplicate`, judged by the labeler and listed. Duplicates
   still count as gate passes in the metrics, as in v1.

## The ground truth: hand keeps minus those that violate the written definitions

The v1 matching (`lab/discovery/screen_compare.py`) is kept, mark units and judged matches included. The marks below
are removed from the kept set. Their candidates become rejections, and their units leave the recall denominator.

| Class of violation | Written definition | Removed mark units (candidates) |
|---|---|---|
| Relief funds: money or aid for the stone's victims, from a charity, a company or a statute | Owner's ruling, Oct 5. Rubric v1, section 1: "a relief appeal ... does not". `discovery_corpus1_v1_1.md`: "funds that were a company's own relief effort" | September 11th Victim Compensation Fund (WF005); UN Chernobyl Trust Fund, "to help victims" (WF022); Chernobyl Children International, "to help those economically affected" (WF027); One Fund Boston (WF071); OneOrlando (WF109); PG&E Fire Victim Trust (WF138); the Sandy aid law, a one-time relief appropriation (WF002, WF001) |
| Temporary measures | Owner's ruling. `discovery_corpus1_v1_1.md`: "immediate operational response" | BP's federal contracting ban, "temporarily banned" (H26, H35); Chico's price-gouging ordinance, "for six months" (WF136) |
| Country bans of the work itself, and government acts on the work's own distribution | Owner's ruling. `discovery_corpus1_v1_1.md`: "bans on a film in one country". `roundtable_v2.md`: "Country bans are a thin mark class" | Iran's ban of Pokémon Go (C039); Iran's ban of Zumba (C176); Malaysia's ban of Fifty Shades (C076); seven Indian states' bans of The Da Vinci Code (C078); Switzerland's ban of the scandal's own cars (WF159, WF166); the Dimmock ruling on showing An Inconvenient Truth in schools (H06, C223) |
| Tourism | Owner's ruling. `HANDOFF.md` section 1: "Attention, growth and crazes are intermediate steps, never the endpoint" | Norway tours after Frozen (C004); Northern Ireland's Game of Thrones visitors (C005); Paris tourists citing Emily in Paris (C229) |
| The stone's own company | Owner's ruling | The Tetris Company (C154, C152) |
| Attention, growth or crazes (not in the owner's list; the same written sentence) | `HANDOFF.md` section 1, as above | 3D televisions after Avatar, "an increase in popularity of 3D films" (C067); the Blue Planet II plastics "interest" study (C226) |

That removes 22 of the 105 kept mark units and leaves 83.

**Reviewed and retained:**

- **Woodstock's Bethel Woods (C200).** The product labels it as visitors, but the sentence states 172 jobs, and jobs
  are a written mark.
- **Retained as institutions:** the Hamilton Education Program, the Climate Reality Project, Crisis, Never Again MSD,
  the Challenger Center and the OnePulse Foundation (a memorial foundation, not relief).
- **California's AB 1054 wildfire fund:** a standing fund for future claims, not relief to the stone's victims.
- **FRA Emergency Order 28:** a binding order, not temporary by the sentence's terms.
- **Retained as written marks:** the bump-stock ban, the 13 Reasons Why study (a health outcome), and the purchase
  shifts (Sideways, chess sets, Dalmatians, reef fish, baking, suits), which are behavior marks.

**Disclosed:** the labeler who wrote this list had already seen every v1 hand decision and every v1 confusion case. The
list applies the owner's ruling, and the last row extends it by the same written sentence. Sensitivity line (a) below
drops that extension.

## The bar (unchanged from v1)

All three, pooled over E1 to E4:

1. **Precision at least 0.61.**
2. **Recall at least 0.80 on kept marks** (mark level, against the 83 units above).
3. **0 decoys passed** in E5, the famous films (E6 reported beside it).

Reported per set and per class (events, culture), with the confusion cases quoted. A failed bar is reported as failed,
with the diagnosis.

## Registered sensitivity lines (not part of the bar)

- (a) The owner's five named classes only: the Dimmock ruling, Avatar's 3D televisions and the Blue Planet II
  plastics study stay kept.
- (b) The v1 ground truth with the v2 labels: what the dating step alone does.
- (c) Mechanical sentence matches only (the 24 judged matches dropped).
- (d) The unseen-in-docs subset, as in v1.
- Dating-step counts: lookups made, resolved (by title, infobox or statute site), busted by the ordering rule,
  unresolved, null, and the source of every date.

## New pools (exploratory; no hand comparison)

1. **The never-screened catalog pool** (192 sentences, `screen_new_v1.json`): the v1 labels plus the dating step.
2. **The Federal Register pool of records 2** (`docs/results/records2_v1.json` on the records 2 branch, `eng-records`, its
   `screened` list of 247 rule sentences, decoys included). Only candidate fields are read: work, work date, stone
   type, group, agency, rule title, action, publication date, sentence, URL and document number. The hand labels in
   that file are not opened. Each candidate is labeled under rubric v2. The mark is the rule the sentence belongs to,
   dated by its own publication date, so no lookup is needed and no request goes to the Federal Register, which is
   under a 429 stop for the day.

Passes from both go to `docs/results/screen_new_v2.json`, labeled "screened by a language model, not by a person".
Nothing enters the product from it without a person.

## Not blind, said plainly

v1's labels were blind. v2 is a mechanical transformation of them, through a lookup whose inputs are fixed above,
against a ground truth that its author wrote after seeing the v1 results. Every judgment in v2 is listed: the record
titles, the removals and any duplicates. The Federal Register pool is labeled without its hand labels, but by a labeler
who has read the records 2 result summary.
