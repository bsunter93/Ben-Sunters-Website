# Q4 named-subject test v1 (registered 2026-09-28, before any data for it is fetched)

- **Question:** does each event move attention to its own owner-named subject? For example, does The Queen's Gambit
  move attention to chess, Chernobyl to the Chernobyl disaster, and God of War to Norse mythology?
- **Why it matters:** this is the product's core claim ("event → downstream effect") tested directly. The outcome is
  fixed in advance for every event, so there is no search over outcomes and no penalty for one.

## Events and subjects

- **File:** `ripples/corpus/q4_subjects_v1.tsv`, 197 events in four families:

  | Family | Events |
  |---|---|
  | q4_drama_subjects (series premieres) | 116 |
  | q4_film_subjects (true-story wide releases) | 49 |
  | q4_game_subjects | 16 |
  | q4_death_subjects (deaths of people tied to a specific subject) | 16 |

- **Source:** the owner batch (`events_taxonomy_batch1.csv`) in the window 2016-09-01 to 2026-04-30.
- **Subject rule:** each subject is the most specific element of the owner's `discovery_subject` that someone could
  look up, mapped to one English Wikipedia article.
- **Exclusions:** subjects that name no single look-up-able topic (e.g. "music", "television", "Los Angeles /
  culture") are left out. There are 141 such events, listed in `q4_subjects_v1_excluded.tsv`.
- **When the mapping was made:** blind, before any views were fetched. Titles that do not exist are skipped and
  reported; nothing is remapped after results are seen.

## Statistic and test

- **Statistic:** discovery v1's onset-coupling statistic (ledger 1283).
- **Event curve:** the event article's views, summed over redirects, as in Q3.
- **Outcome:** the subject article's views, summed over redirects, as log(1 + views) minus the daily median of the
  998-article Wikipedia panel.
- **Per event:** MAD and rank z-scores against 200 placebo dates for that event's own subject. The event's p-value is
  the rank of the real score among its placebos.
- **Per family:** score = sum(z) / sqrt(n), tested against 1,000 worlds in which every event is moved to a random
  admissible date and scored against its own subject again.
- **Success (family):** p ≤ 0.05 for both the MAD and the rank version.
- **Correction:** Benjamini–Hochberg at q = 0.10 across the four families.
- **Per-event reporting:** each event's own p-value is reported. With about 200 events, about 10 will pass p ≤ 0.05 by
  chance alone. Individual events are therefore descriptive, and only the family results are claims.

## Checks

- **Echo:** the subject is often linked from the event article; that is the hypothesis, not a flaw. Whether it is
  linked is recorded for every event.
- **Positive control:** The Queen's Gambit → Chess, found in E9 (ledger 1282), should score high here.
- **Common shock:** events are spread across ten years; clustering is not expected to matter for pre-specified
  outcomes, but event dates are reported.
- **What this can and cannot show:**
  - Success means events of that kind move attention to their named subjects.
  - That is timing and comparison evidence, not proof of cause.
  - A family can pass on a few strong events. The count of events at p ≤ 0.05 is reported against the roughly 5%
    expected by chance.

## Politeness

- As Q3: one Wikimedia request at a time with a 1 s pause, stop on 403/429/5xx with no retry that day.
- Runs only when no other Wikimedia fetcher is running, after the wide-lens fetch and the v3 Wikipedia screen.
