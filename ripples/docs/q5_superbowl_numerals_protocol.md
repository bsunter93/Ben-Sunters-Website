# Confirmation: Super Bowls → numerals (registered 2026-09-29, before any data for it is fetched)

**Candidate:** screen v3's same-weekday re-run (ledger 1456) found super_bowls → Wikipedia "Arabic numerals".

| | |
|---|---|
| Members pushing it up | 8 of 10 (z > 1.8) |
| p, both z versions | 0.001 / 0.001 |
| Leave-one-out | stable |
| Proposed mechanism | Super Bowls are named in Roman numerals (Super Bowl LVIII), so viewers look up how to read them |

**The weakness this test targets:** every member falls in the same weeks of early February. A calendar or seasonal
driver has not been ruled out.

## Tests (all registered now)

1. **Local-season test (primary).**
   - Outcomes, fixed in advance:
     - "Roman numerals": new, not examined in any screen.
     - "Arabic numerals": the screened outcome, now tested under a stricter null.
   - Events: the same 10 Super Bowls (LI–LX, 2017–2026).
   - Statistic: discovery v1's onset-coupled statistic for each (event, outcome).
   - **Placebo dates:** only Sundays within ±21 days of that year's Super Bowl, excluding the game day itself (6
     dates per year, 60 in all). A seasonal driver would score as high on nearby Sundays as on game day.
   - Family score: sum of per-event z / √10, against 10,000 draws that swap each game day for one of its own year's
     placebo Sundays.
   - **Pass:** p ≤ 0.05 for "Roman numerals" in this local-season test. "Arabic numerals" is reported alongside.
2. **Negative control:** Super Bowl 50 (2016-02-07).
   - That year the NFL branded the game "Super Bowl 50" instead of "Super Bowl L".
   - The mechanism predicts a smaller numerals effect for it than the median of LI–LX.
   - This is reported as supporting or not supporting. With a single event it is not a pass/fail gate.
3. **Reader paths (Wikipedia Clickstream, monthly, English):** clicks from each Super Bowl article (and the "Super
   Bowl" article) to "Roman numerals" and "Arabic numerals", in February against the same pairs in other months.
   - **Supporting:** the pair appears (≥ 10 clicks) in the February files and is absent or much smaller in other months.
   - It runs when the Clickstream fetch is built. It is descriptive, not a gate.

## Verdicts

| Verdict | Condition |
|---|---|
| Confirmed (timing) | Test 1 passes for Roman numerals |
| Supported (mechanism) | Test 1 passes and test 3 shows the reader path |
| Not confirmed | Test 1 fails; the candidate is labelled a likely seasonal effect |

- The discover page shows the verdict and never says "caused".

## Data and politeness

- **New fetches:** the "Roman numerals" article views (with redirects) and "Super Bowl 50" event views. Everything else
  is cached.
- **Fetch rules:** the owner's identity-only Wikimedia token, honest User-Agent, 1 s pause, stop on refusal.
- **When:** after the Q4 run and the v3 lens runs finish (one Wikimedia job at a time).
