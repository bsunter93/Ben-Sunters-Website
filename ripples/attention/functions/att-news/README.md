# att-news (W7 attention layer: news and TV)

Edge function `att-news` (verify_jwt false, `x-collector-token` via `serve()` in `att.ts`, ATT_VERSION 2026-09-25.3).
Sources: `gdelt.gkg` (G), `ia.thirdeye` (Y), `news.sitemap` (Y). Every request goes through `politeFetch` (honest UA,
robots.txt checked on every host, host lease, kill switch on 401/403/429/503, per-run and per-day budgets).
Never calls the GDELT DOC API (RED for us, DEMARCATION §0.6; it is also on the att.ts RED path list).
Stored: counts, ranks and indices only. No headline, chyron or article text, and no URLs.

## Modes

| Mode | Requests | What is written |
|---|---|---|
| `gkg` | 1 file per run (+ `lastupdate.txt` when not catching up) | For every watched term (`att_news_terms('gdelt.gkg')`: active + panel): documents in the 15-min file whose V1Persons / V1Organizations / V1Locations (feature name) / AllNames mention the term (whole-word, aliases included; `theme` keys match V1Themes). Daily rows for every term (zeros included), hourly rows for active topics only (free-tier profile). `aux` = distinct source countries (ccTLD of SourceCommonName; generic TLDs not counted). `__total__` = documents in the file(s). Co-mention edges (`att_edges`, day grain): active term x co-mentioned person/org/name, top 25 per term with >= 2 shared documents, `meta.total` = documents mentioning the entity, `pmi` recomputed from the running daily totals. Discovery: top 200 entities by burst z = (n - b) / sqrt(b + 1) against an EWMA baseline per file (alpha 0.05, 4000 names in `att_state['gkg.ewma']`), n >= 5, z >= 3, after a 4-file warm-up -> `att_trend_candidates` (evidence = clamp(z/8, 0, 1), strongest of the day kept). |
| `thirdeye` | 1 (`third-eye.php?last=2`, widened to 3 when an hour was missed) | Chyron-minutes per term per channel for every **complete** hour in the window (distinct minutes whose chyron OCR text mentions the term). Daily: `geo=ALL` value = sum over channels, `aux` = channels that aired it; per-channel daily rows (`geo` = channel code) only where > 0; `__total__` per channel and overall. Hourly (active topics + `__total__`): overwritten per complete hour. Same-hour co-occurrence edges (tv family): shared minutes = sum over channels of min(minutes_a, minutes_b). |
| `sitemaps` | 4 (BBC, NYT, Guardian, Fox news sitemaps, one per host, in parallel) | Headlines per term per publication day (title + `news:keywords`), cross-outlet sum with `aux` = outlets; per-outlet `__total__` (geo = outlet) and overall `__total__`. Sitemaps are 48 h rolling windows, so per-outlet cells merge with greatest() (`att_news_cells`, 4-day retention) and the daily value is the sum over outlets. `meta.coverage` = outlets seen that day. Newsroom co-mention edges (two registry terms in one headline, one side active; `meta.q` = outlets). Candidates: `news:keywords` seen in >= 2 outlets (keywords or headlines) and >= 2 headlines, top 50, rank-list evidence 1 - ln(rank)/ln(N+1). |
| `backfill` | 0 | GKG history sampling is not enabled on the free tier: jobs are marked `skipped`. GKG enters the score at 28 days like the other warm-up sources (§3.6 item 4 allows this). |
| `ping` | 0 | Liveness. |

Params: `gkg {"file":"YYYYMMDDHHMMSS"}` (a specific file; re-processing a file is a no-op because every file is one
idempotent batch), `thirdeye {"last":2,"peek":true}` (`peek` returns column names and per-column length stats only),
`sitemaps {"outlets":["bbc","nyt","guardian","fox"]}`. `dry_run: true` writes nothing.

## Why the accumulation RPCs

`att_ingest` overwrites a (series, day|hour) cell. GKG publishes 96 files a day, and Third Eye is read one complete
hour at a time, so the daily value is a sum of parts. `att_news_accum(p_run, p_batch, p_rows)` adds each part exactly
once (the batch id `gkg:<file>` / `thirdeye:<hour>` is recorded in `att_news_batches`; a repeat is a no-op), keeps the
distinct member sets (source countries, channels) in `att_news_acc` so `aux` is an exact union count, and then writes
the running totals through `ripples.att_ingest` (all of its checks apply: enabled source, identifier screen, meta
allow-list, hourly-active-only, 400 MB guard). `meta.coverage` = number of parts added so far (files or hours), so a
scorer can tell a complete day (96 GKG files, 24 Third Eye hours) from a partial one. `att_news_acc` keeps 3 days.

## Cron (UTC)

| Job | Schedule | Call |
|---|---|---|
| `att-gkg` | `4,19,34,49 * * * *` | `att-news {"mode":"gkg"}` |
| `att-thirdeye` | `12 * * * *` | `att-news {"mode":"thirdeye","params":{"last":2}}` |
| `att-sitemaps` | `22 0,6,12,18 * * *` | `att-news {"mode":"sitemaps"}` |

## Budgets (att_sources)

| Source | Per run | Per day | Spacing | Hosts |
|---|---|---|---|---|
| gdelt.gkg | 2 | 200 | 5 s | data.gdeltproject.org (robots.txt 404 = allowed) |
| ia.thirdeye | 2 | 48 | 5 s | archive.org (robots.txt allows /services/) |
| news.sitemap | 8 | 32 | 5 s per host | www.bbc.com, www.nytimes.com, www.theguardian.com, www.foxnews.com (robots.txt allows the sitemap paths) |

## Known limits

- GKG source-country breadth uses the outlet's ccTLD, so .com/.org outlets are not counted (breadth is a lower bound).
- GKG counts come from the English GKG stream only (`lastupdate.txt`); the translingual stream is not read.
- Third Eye text is on-screen OCR, which can include tickers and network branding, so a term such as "cnn" also
  matches on-screen mentions on other channels.
- Tone is not stored (free-tier size); the Tone-shift index needs a `tone_sum` metric later.
- The EWMA discovery baseline is per 15-minute file, not the §6.5 same-hour-of-day 7-day baseline.
