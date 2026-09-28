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

## Addendum 1 (registered 2026-09-28, ledger 1369, before Q4 v1 or anything below has run)

The owner's validation pack (`ripples/corpus/validation_pack_1.csv`) adds named subjects for older corpus events and
held-out drama premieres. The statistic, test, correction rule and politeness rules above are unchanged.

### Q4 v1b: 43 more events in three families (`ripples/corpus/q4_subjects_v1b.tsv`)

| Family | Events | Examples |
|---|---|---|
| q4b_culture_subjects (films, series, games) | 14 | Black Panther → Wakanda, Money Heist → Royal Mint of Spain, Elden Ring → George R. R. Martin |
| q4b_science_tech_subjects | 15 | ChatGPT → Large language model, DART → Dimorphos, Casgevy → CRISPR gene editing |
| q4b_news_subjects (sport, business, civic) | 14 | 2016 World Series → Chicago Cubs, Suez Canal obstruction → Suez Canal, SVB → Bank run |

- **Correction:** Benjamini–Hochberg at q = 0.10 across these three families, separately from v1's four.
- **Rows left out of the pack's 76 named-subject rows** (33 rows):
  - **Before the window** (before 2016-09-01): E551, E552, E601, E637, E701, E726, E751, E753, E759, E803, E925,
    E972, E974, E977.
  - **Date flagged by the owner** ("needs verification" or an emergence window): E801, E817, E825, E836, E965, E984,
    E988.
  - **Date in doubt:** E574 Fleabag (premiered 2016-07-21 on BBC Three, not 2016-09-21).
  - **Already in Q4 v1** (same event): E563, E571, E577, E580, E581, E584, E616, E618.
  - **Duplicate row:** E710 (same event as E708).
  - **No single article for the subject:** E560 Parasite (class inequality in South Korea), E866 (the subject is the
    invasion itself).
- **Subjects that differ from v1's exclusions:** Breath of the Wild, Fortnite, Animal Crossing and Elden Ring were
  left out of v1 because the batch named no specific subject for them. The pack names one (Hyrule, battle royale,
  life simulation, George R. R. Martin), so they are tested here.

### Held-out confirmation for q4_drama_subjects (`ripples/corpus/q4_heldout_drama_v1.tsv`)

- **Events:** 8 premieres not in any earlier test: Industry, Painkiller, We Own This City, A Gentleman in Moscow,
  The Act, The New Pope, The Luminaries and A Very English Scandal.
- **Left out:** HO008 The English (already T10123 in v1) and HO009 The Essex Serpent (in the owner batch; its subject
  is too broad for one article).
- **Rule:** the held-out set is scored with the same statistic. It confirms the drama result only if
  q4_drama_subjects passes in v1 **and** the held-out family score has p ≤ 0.05 for both the MAD and the rank
  version. If v1's drama family does not pass, the held-out result is reported as descriptive only.
- **Caveat:** 8 events give little power, so a miss is weak evidence against the family. More held-out premieres
  would help.

### Order

The Q4 workflow runs v1, then v1b, then the held-out set, in one job. Any refusal (403/429/5xx) stops all three for
the day.
