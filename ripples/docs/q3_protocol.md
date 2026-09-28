# Q3 protocol v1: first real discovery screen (registered 2026-09-28, before any outcome is examined)

**Question (D-26 Q3):** does the frozen discovery method find candidate ripples in real event families that survive a
family-wise null?

**Method:** discovery v1 (ledger 1283), exactly as validated in the cultural lab (`ripples/lab/RESULTS.md`, runs 1–4).

**Status of results:** anything this screen produces is a **candidate**, not a finding. Candidates go to the evidence
engine: a separately registered confirmation on data this screen does not use.

## Events and families

- **Source:** the owner's 500-event corpus (`ripples/corpus/events_500.txt`).
- **Eligible events:** an event day on or after 2016-09-01, and an English Wikipedia article that carries the event's
  attention. The daily pageview panel starts 2015-07-01, and v1 was validated with a year of history before each
  event.
- **Families:** 9 families, 42 events (`ripples/corpus/q3_families_v1.tsv`). They follow the owner's family labels,
  merged only where a label had fewer than four eligible members.
- **Event day:** the listed date. Where the corpus gives only a period, it is the day of peak views of the event's
  own article within a stated window. Outcomes are never used to set the date.
- **Duplicates and same-day events:**
  - Duplicates in the corpus (E479 = E143, E488 = E140, E499 = E248) are merged.
  - Barbie and Oppenheimer (E490, E491) share E100's date and are represented by E100 (Barbenheimer).
- **Eligible but left out**, because the family would be too small, the date too vague, or it would be a third
  same-day member:
  - Small families: the Ever Given, Notre-Dame and Key Bridge landmark shocks; Brat and the Oasis reunion (music
    moments); the 2023 strikes.
  - Too vague: Barbiecore, the Stanley tumbler, girl dinner, AI images, AI music, AI agents, commercial space,
    semiconductors, generative AI as a category.
  - Same-day members: Barbie, Oppenheimer.

## Outcomes

- **Panel:** the fixed panel of 998 level-3 Vital Articles, daily user pageviews, 2015-07-01 to 2026-08-31. It was
  chosen before the events, and is the same panel the lab used.
- **Direct echoes:** an outcome is an echo when it is linked from an event's own article, or is that article itself.
  Echoes are tested like any other outcome but reported separately as obvious. They are never presented as surprising.

## Analysis (identical to the lab)

1. Market adjustment: log(1 + views) minus the all-article daily median.
2. Event curve per member:
   - log views of the event article on days −14..+90, minus its median over days −60..−1.
   - If fewer than 20 of those pre days exist, the 10th percentile of the window is used instead.
   - Clipped at 0, scaled so that the mean over days 1–30 is 1.
3. Onset-aligned coupling statistic per (member, outcome): the least-squares loading of the outcome's day-to-day
   changes on the curve's day-to-day changes over days −14..+90.
4. Per-member calibration: the same statistic at 200 placebo days (seed 20260929, drawn uniformly over the admissible
   range, the lab's rule). It gives a MAD z (clipped at ±4) and a rank z.
5. Family score per outcome: the sum of member z divided by √(members), for each z version.
6. **Family-wise null:**
   - 1,000 null worlds, in which every member keeps its own curve but moves to a random admissible day.
   - p for (family, outcome) = (1 + number of null worlds whose maximum family score over all 998 outcomes is at least
     the observed score) / 1,001.
   - This pays for searching all outcomes within a family (the max-statistic), separately for each z version.
7. **Candidate rule:**
   - Both z versions give p ≤ 0.05.
   - The family's smallest p passes Benjamini–Hochberg at q = 0.10 across the 9 families.
   - Leave-one-member-out stable: with any single member removed, the MAD score stays above the 95th percentile of
     that reduced family's null maximum.
8. **Report:**
   - Every family's top 10 outcomes, with both p values and echo flags.
   - Candidates listed separately.
   - Everything, including families with nothing, goes to the ledger (resolve).

## What happens next

- **Confirmation (registered separately):** each candidate is tested on new members of the same family added to the
  corpus later, or on an independent outcome source (Google Trends by state, the NYT archive, news tags), with the
  design frozen in the ledger first.
- **Story layer:** only after that. An owner "would you have tested this?" rating is collected on the candidate list
  before any confirmation result is shown.
