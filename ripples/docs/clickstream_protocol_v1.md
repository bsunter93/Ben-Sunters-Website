# Reader paths v1: Wikipedia Clickstream (registered 2026-09-29, before any Clickstream data is fetched)

**Question:** when an event ripples into another article, do readers actually walk there by clicking from the event
article, or do they arrive some other way (search, other pages)? This is the "why" half of a ripple: the timing tests
say *that* attention moved, reader paths say *how*.

**Source:** Wikimedia's monthly English Clickstream (`dumps.wikimedia.org/other/clickstream/`): counts of
(referrer, article) pairs per month, with pairs under 10 clicks removed by Wikimedia. Aggregate only.

## Fetch (`ripples/lab/clickstream.py`, frozen at this commit)

- 30 monthly files (listed in the script), streamed one at a time with an honest User-Agent.
- Only rows whose referrer or target is one of the focus titles are kept; the full files are never stored.
- 403/429/503 stops the run with no retry; a 404 is recorded as a missing month and the run continues.
- Runs on GitHub Actions (`ripples-clickstream.yml`), its own concurrency group (a different Wikimedia service from
  the pageview API).

## A. Super Bowls → numerals mechanism (Q5 protocol, test 3; ledger 1457)

- For each February 2018–2026: clicks from that year's game article plus the "Super Bowl" article to "Roman numerals"
  and to "Arabic numerals", against August of the same year (for 2026, August 2025).
- **A year supports** if the February clicks are ≥ 10 and the August clicks are at most a quarter of them.
- **Supporting (mechanism)** for Roman numerals if at least two thirds of the usable years support.
- Also reported (descriptive): total inbound clicks to each numerals article, the share from Super Bowl articles, clicks
  from search, the top referrers in February and August, and Roman numerals → Arabic numerals clicks (a two-hop path:
  game → Roman numerals → Arabic numerals would explain why the screened outcome was Arabic numerals).
- **Limit:** Super Bowl 50 (February 2016) predates the monthly English files, so the negative control cannot be read
  here.

## B. Per-event reader paths (ripple-map prototype)

| Event article | Outcome (already tested) | Pre month | Event months |
|---|---|---|---|
| The Queen's Gambit (miniseries) | Chess | 2020-09 | 2020-10, 11, 12 |
| Chernobyl (miniseries) | Chernobyl disaster | 2019-04 | 2019-05, 06 |
| Parker Solar Probe | Speed of light | 2018-07 | 2018-08 |
| Voyager 2 | Speed of light | 2018-11 | 2018-12 |
| Artemis I | Speed of light | 2022-10 | 2022-11 |
| Chandrayaan-3 | Speed of light | 2023-07 | 2023-08 |

- For each event month: clicks event → outcome; a **direct path** if ≥ 10.
- The outcome's total inbound clicks against the pre month, and the share of that change that came directly from the
  event article.
- The referrers whose clicks to the outcome grew most, and the event article's top 25 outbound links (the first ring of
  its ripple map).
- Descriptive only. No p-values; a missing direct path is not evidence against the ripple (readers may search).

## Output

- `clickstream_paths_v1` in `ripples.att_q3_results`, saved as `ripples/docs/results/clickstream_paths_v1.json`.
- Shown on /ripples/discover/ as reader paths, never as "caused".
