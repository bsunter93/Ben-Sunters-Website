# Q3 protocol v3: tight families across all lenses (registered 2026-09-28, before any v3 family is scored)

- **Families:** `ripples/corpus/q3_families_v3.tsv`, 11 runnable families with 128 events, built by the rules in
  `ripples/docs/family_taxonomy_v3.md`.
- **Method:** discovery v1 (ledger 1283), unchanged: onset-coupling statistic, per-outcome placebo calibration (200
  dates), 1,000 moved-date worlds, family-wise maximum over outcomes, both-z rule at p ≤ 0.05, leave-one-member-out
  stability.
- **Correction:** Benjamini–Hochberg at q = 0.10 across the 11 families, within each lens.
- **Event curves:** from Wikipedia, with views summed over redirects.

## Lenses

Each lens runs exactly as registered for screen v2:

| Lens | Registered settings |
|---|---|
| Wikipedia views, 998 articles | 1286 |
| NYT coverage | 1290 |
| Real-world daily | 1291: weekday-matched dates, coverage rule 0.8 |
| Tech and city daily | 1294: weekday-matched dates, coverage rule 0.8 |
| Weekly | 1294 |
| Monthly | 1294 |
| Library | 1295 |
| County jobs | 1296 |
| Wide Wikipedia | 1295, once its panel is complete |

## Checks registered now

- **Common shock:** a candidate carried by members within 30 days of each other is reported as common-shock risk.
  This mostly affects hurricanes, because landfalls cluster within seasons.
- **Annual and seasonal families** (academy_awards, super_bowls, hurricanes): every candidate is hand-checked for a
  plain seasonal explanation, recorded before any confirmation.
- **Second looks, labelled as such:**
  - ai_model_releases shares 8 events with v2 ai_models. Its leading v2 outcome, Computer, is known.
  - spacex_milestones shares Falcon Heavy, Crew Dragon Demo-2 and Starship flight test 1 with confirmation 1 of the
    space → Speed of light ripple. Speed of light, Telescope and Solar System are known outcomes for those events.
- **Echo flag:** as before.
- **Invalid event titles:** an event whose article title is missing on Wikipedia gets no views and is skipped with a
  reason. Skips are reported; nothing is replaced after results are seen.

## After the screen

1. Candidates go to the owner for a "would you have tested this?" rating.
2. Confirmation needs held-out events of the same family: owner additions (see the taxonomy's request list),
   registered before they are scored.

## Politeness

- Event views are fetched from Wikimedia with the standing rules: one request at a time, a 1 s pause, stop on
  403/429/5xx with no retry that day.
- This runs only when no other Wikimedia fetcher is running (the wide-lens fetch goes first).
- The 2026-09-28 retry-after-rate-limit permission (1289) has been removed from the workflow.
