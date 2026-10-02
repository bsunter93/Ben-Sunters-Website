# Q6: the named-subject test beyond Wikipedia (registered 2026-09-29, before any lens data is built)

**Why:** every result so far measures attention with Wikipedia page views. The reader-path check (ledger 1463) showed
most ripple traffic reaches Wikipedia from search, so Wikipedia is a downstream proxy. Q6 asks whether the strongest
result, the named-subject test (Q4, ledger 1458: every family passed), holds when attention is measured elsewhere.

## Lenses (all free, all with daily history over the whole panel, 2015-07 to 2026-08)

| Lens | What it counts | Source |
|---|---|---|
| **TV** (primary) | Spoken mentions of the subject on US TV news, per 10 million caption words that day | Internet Archive TV News Archive caption n-grams via GDELT (BigQuery `gdelt-bq.gdeltv2.iatv_1gramsv2`, `iatv_2gramsv2`) |
| **HN** (secondary) | Hacker News stories and comments mentioning the subject, per 10,000 items that day | BigQuery `bigquery-public-data.hacker_news.full` |
| **Wikipedia** (reference) | The subject article's views, as Q4 | Wikimedia pageviews (cached from Q4) |

- **Subject phrase:** the Q4 subject title without any parenthetical, lower case (e.g. "Chess", "Vietnam War").
  Nothing is remapped after data is seen.
- **TV** takes 1- and 2-word phrases only (184 of 262 events; the 3-word table would pass the free-tier budget). HN
  takes any length.
- **Rare subjects:** a subject enters a lens only if it is mentioned on at least 30 days in the panel window.
- **Hacker News is a tech crowd.** It is expected to respond mainly to science, tech and games; it is reported, not
  expected to pass for drama.
- **Not used (and why):** Google Trends in BigQuery keeps only about 30 days (now archived daily from 2026-09-29 for
  future use); Reddit's free archive allows no text search across all of Reddit; GDELT's news API refuses GitHub's
  servers (HTTP 429).

## Statistic and test (Q4's, with one registered change)

- **Event curve:** the event's Wikipedia article views (timing and shape of the event only).
- **Outcome:** the subject in each lens (log(1 + rate)).
- **Change from Q4 v1, applied to every lens including Wikipedia:** placebo and moved dates keep the event's weekday.
  TV and HN have strong weekly cycles, and weekday matching removed the calendar artifact in screen v3 (ledger 1456).
- **Per event:** MAD and rank z against 200 same-weekday placebo dates for its own subject in that lens.
- **Per family:** sum(z)/√n against 1,000 worlds of same-weekday moved dates.
- **Pass (family, per lens):** p ≤ 0.05 for both versions. Families as Q4 (v1 four, v1b three, held-out dramas).
- **Offline check:** on synthetic data, a planted +300% subject response in one family passed (p = 0.005 at 200
  worlds) and three no-effect families did not (p 0.06–0.55).

## Readings

- **Main question:** for each family that passed Q4 on Wikipedia, does it also pass on TV?
- **Agreement:** rank correlation of per-event z between lenses (events scored in both).
- **A ripple the product may show** as measured "beyond Wikipedia" needs its family to pass in Wikipedia and in at
  least one other lens.

## Cost and politeness

- BigQuery: every query dry-run first; the run refuses to go past 900 GiB billed this month (the free tier is 1 TiB).
- No Wikimedia requests beyond cache misses (Q4 already fetched every article), one at a time, stop on refusal.

## Output

- `q6_lenses_v1` in `ripples.att_q3_results`, saved as `ripples/docs/results/q6_lenses_v1.json`.
