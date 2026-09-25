# att-news (W7 attention layer: news and TV)

Edge function `att-news` (verify_jwt false, `x-collector-token` via `serve()` in `att.ts`, ATT_VERSION 2026-09-25.3).
Sources: `gdelt.gkg` (G), `ia.thirdeye` (Y), `news.sitemap` (Y). Every request goes through `politeFetch` (honest UA,
robots.txt checked on every host, host lease, kill switch on 401/403/429/503, per-run and per-day budgets).
Never calls the GDELT DOC API (RED for us, DEMARCATION §0.6; it is also on the att.ts RED path list).
Stored: counts, ranks and indices only. No headline, chyron or article text, and no URLs.

## Modes

| Mode | Requests | What is written |
|---|---|---|
| `gkg` | `lastupdate.txt` + up to 2 files per run (the walk's next file, then a due parked-file retry) | For every watched term (`att_news_terms('gdelt.gkg')`: active + panel): documents in the 15-min file whose V1Persons / V1Organizations / V1Locations (feature name) / AllNames mention the term (whole-word, aliases included; `theme` keys match V1Themes). Daily rows for every term (zeros included), hourly rows for active topics only (free-tier profile). `aux` = distinct source countries (ccTLD of SourceCommonName; generic TLDs not counted). `__total__` = documents in the file(s). Co-mention edges (`att_edges`, day grain): active term x co-mentioned person/org/name, top 25 per term with >= 2 shared documents, `meta.total` = documents mentioning the entity, `pmi` recomputed from the running daily totals. Discovery: top 200 entities by burst z = (n - e) / sqrt(e + 1), where e = the entity's EWMA share of documents (per 1000 documents per file; alpha 0.05, 4000 names in `att_state['gkg.ewma']`, `unit: per1k`) times this file's document count, n >= 5, z >= 3, after a 4-file warm-up -> `att_trend_candidates` (evidence = clamp(z/8, 0, 1), strongest of the day kept). |
| `thirdeye` | 1 (`third-eye.php?last=2`, widened to 3 when an hour was missed) | Terms that are a TV network's own name (CNN, Fox News, MSNBC, BBC News, ...: `TV_BRANDS`) are not counted: the name is on screen all day. Chyron-minutes per term per channel for every **complete** hour in the window (distinct minutes whose chyron OCR text mentions the term). Daily: `geo=ALL` value = sum over channels, `aux` = channels that aired it; per-channel daily rows (`geo` = channel code) only where > 0; `__total__` per channel and overall. Hourly (active topics + `__total__`): overwritten per complete hour. Same-hour co-occurrence edges (tv family): shared minutes = sum over channels of min(minutes_a, minutes_b). |
| `sitemaps` | 4 (BBC, NYT, Guardian, Fox news sitemaps, one after another) | Headlines per term per publication day (title + `news:keywords`), cross-outlet sum with `aux` = outlets; per-outlet `__total__` (geo = outlet) and overall `__total__`. Sitemaps are 48 h rolling windows, so per-outlet cells merge with greatest() (`att_news_cells`, 4-day retention) and the daily value is the sum over outlets. `meta.coverage` = outlets seen that day. Newsroom co-mention edges (two registry terms in one headline, one side active; `meta.q` = outlets). Candidates: `news:keywords` seen in >= 2 outlets (keywords or headlines) and >= 2 headlines, top 50, rank-list evidence 1 - ln(rank)/ln(N+1). |
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
| `att-gkg` | `10,25,40,55 * * * *` | `att-news {"mode":"gkg"}` |
| `att-thirdeye` | `12 * * * *` | `att-news {"mode":"thirdeye","params":{"last":2}}` |
| `att-sitemaps` | `22 0,6,12,18 * * *` | `att-news {"mode":"sitemaps"}` |

## Budgets (att_sources)

| Source | Per run | Per day | Spacing | Hosts |
|---|---|---|---|---|
| gdelt.gkg | 3 | 300 | 5 s | data.gdeltproject.org (robots.txt 404 = allowed) |
| ia.thirdeye | 2 | 48 | 5 s | archive.org (robots.txt allows /services/) |
| news.sitemap | 8 | 32 | 5 s per host | www.bbc.com, www.nytimes.com, www.theguardian.com, www.foxnews.com (robots.txt allows the sitemap paths) |

## Known limits

- GKG source-country breadth uses the outlet's ccTLD, so .com/.org outlets are not counted (breadth is a lower bound).
- GKG counts come from the English GKG stream only (`lastupdate.txt`); the translingual stream is not read.
- Third Eye text is on-screen OCR, which can include tickers and network branding. Network names are excluded
  (n3); other on-screen furniture (e.g. show names) can still match short or generic terms.
- Tone is not stored (free-tier size); the Tone-shift index needs a `tone_sum` metric later.
- The EWMA discovery baseline is per 15-minute file, not the §6.5 same-hour-of-day 7-day baseline.

## GKG file walk (NEWS_VERSION 2026-09-25.n2 and later)

`lastupdate.txt` can list a GKG file before its zip is served, and the zip URL can then answer 404 for 45-60 minutes
(2026-09-25: 7 of about 40 files; the old walk stalled 3-4 runs on each). The walk now:

- never requests a file less than 8 minutes past its timestamp (the cron runs 10 minutes after each file);
- on a 404, parks the file in `att_state['gkg.state'].pending` (`{first, last, n}`) and moves on to the next file;
- (n4) takes the walk's next file first and uses the run's spare slot for a parked file whose retry is due: the file is
  at least 39 minutes old and its last 404 was at least 14 minutes ago (29 minutes once it has had three 404s). Parked
  files seen on 2026-09-25 were served 49-64 minutes after their timestamp whenever they were first asked for, so
  retries now land at about +40 and +55 minutes (the n2/n3 rule, 50 minutes after the last 404, meant about +70-85);
- drops a parked file after 4 hours and counts it in `gkg.state.gaps`;
- (n4) reports `partial` only when listed files old enough to fetch are still unread. Waiting for a file younger than
  8 minutes, or for a parked file GDELT has not served yet, is not partial (`extra.pending` lists parked files).

Every file is one idempotent batch (`gkg:<file>`), so a parked file counted late adds to the right day and hour.

## Sitemaps budget

The four sitemap requests run one after another. When they ran in parallel, each request took a budget chunk of 8
before any was spent, so the whole day's 32 units went at once, and `att_budget_refund` keeps a bucket at its cap
spent. Migration `att_news_gkg_parking` (sql/13) moves the GKG cron and resets 2026-09-25's `news.sitemap` row to the
requests actually made.

## NEWS_VERSION 2026-09-25.n3

- GKG discovery baseline is now each entity's share of the file (documents per 1000). Files range from about 900 to
  1500 documents, and the per-file count baseline flagged every big name (United States, New York) in every big file.
  The old per-file state converts itself on the first n3 file. The 2026-09-25 `gdelt.gkg` candidates written before n3
  (2,276 rows) were deleted so the day is rebuilt with the new baseline.
- Third Eye skips terms that are a network's own name. The `cnn` Third Eye rows written before n3 (3 daily, 10 hourly,
  18 edges) were deleted.
- Discovery candidates (GKG and sitemap keywords) whose label is on `att_config('news_candidate_stoplist')` (wire
  credits, copyright lines, share buttons) are dropped by `att_news_candidates_merge` (migration
  `att_news_candidate_stoplist`, sql/14). Extend the list in `att_config`; no deploy needed.
- `meta.expected` on GKG candidates is not on the core `meta_allow` list, so `_att_clean_meta` drops it; `meta.q` (z) and
  `meta.n_docs` are kept.

## NEWS_VERSION 2026-09-25.n4 to n7: entity minimisation (GKG candidates, edges, baseline)

GKG names come from news text, so the raw entity lists include journalists (bylines, contributor lines), photographers
(photo credits), syndication credits and site furniture. None of these may become a discovery candidate, a co-mention
edge endpoint or a key in the EWMA baseline. In `gkgFile`, every entity is screened per file:

| Rule | Signal | Threshold |
|---|---|---|
| byline | name in any document's Extras `<PAGE_AUTHORS>` | any |
| credit | name within 60 characters (AllNames offsets) of a credit marker (`AP Photo`, `Getty Images`, `Tribune Content Agency`, ...) | > 25% of its documents |
| ghost (n5) | V1Persons/V1Organizations name that no AllNames name in the document contains, or an AllNames name that is the leading words of one (a photo credit: V1Persons `julia demaree nikhinson`, AllNames `Julia Demaree`) | > 30% of its documents (n7; n5 used 50%) |
| tail (n7) | among the last 4 AllNames names within 200 characters of the last one, in an article with >= 8 AllNames names (contributor lines: "Associated Press writers ... contributed") | > 60% of its documents |
| junk | label pattern (`JUNK_LABEL`: photo/image/getty, content agency, `... writer`, share buttons, "website access", doubled names) or a credit marker itself | any |
| breadth | distinct outlets (SourceCommonName) in the file | candidates and person-like edge endpoints >= 3; organisation edge endpoints >= 2 |

`extra.files[].dropped` counts the rejections per rule. Names caught by the first five rules are also deleted from
`att_state['gkg.ewma']` when they appear in a file (n6), so the baseline does not keep journalists' names either.
Candidates carry `meta.method = 'gkg_burst_ewma_v2'`.

Second line of defence in SQL (migration `att_news_entity_screen`, sql/18): `att_news_candidates_merge` and
`att_news_edges_accum` drop labels on `att_config('news_candidate_stoplist')` (wire credits, share buttons, network and
outlet brands, "The", "Media") or matching a pattern in `att_config('news_entity_stop_regex')`. Both lists can be
extended without a deploy.

Dry-run diagnostics: `{"mode":"gkg","dry_run":true,"params":{"file":"YYYYMMDDHHMMSS","probe":["Name", ...]}}` returns,
in `dry_rows` only (never stored in `att_runs`), a candidate and edge preview and, for up to 10 probe names, the
document, outlet, credit, ghost and tail counts and the eligibility verdict.

Validated on real files (dry runs, 2026-09-25): 20260925170000 and 20260925164500 reject the AP photo credit
(ghost 10/17 and 7/17 documents), a PA photo credit (ghost 8/8), AP contributor-line names (tail 8/8, 4/4, 3/4, 3/3)
and a syndicated op-ed author (ghost 20/20), while Donald Trump (ghost 7/147, tail 1/147), Vladimir Putin, Ketanji
Brown Jackson and New Hampshire (tail 5/11) stay eligible. Parse time with the screen: 260-400 ms per file.

Sitemap keywords (n4): outlet and network brands (`TV_BRANDS`, BBC, NYT, Guardian, Fox) and pronouns and bare nouns
("Her", "Age", "Women", "Schools") are no longer keyword candidates.

Cleanup (sql/18b, one-off): every GKG candidate and edge written before the n7 screen was deleted (3,447 + 292 edges,
1,165 + 169 candidates) because the per-file credit and breadth context needed to re-screen them is gone, together with
11 stale sitemap keyword candidates ("The", "Media", "CNN", "MS NOW", ...). GKG edges and candidates for 2026-09-25
therefore cover files from about 18:00 UTC on; counts (`attention_obs`) were not touched.

Residual risk: people named in the body of the news as reporters ("the BBC's ... reports") or quoted officials pass
the screen when they are reported by 3+ outlets. They are public roles in the news itself; the owner can add patterns
to `news_entity_stop_regex` if a class of them shows up.

## n8 / n9 (2026-09-25, deploys v10-v13): registry-term precision and candidate hygiene

**Registry-term counts (`attention_obs`, gdelt.gkg) now pass a per-document screen.** Before n8 a term counted every
document where any name contained its words, so `julia` (topic 232, the 1977 film) counted AP photo credits
("Julia Demaree Nikhinson") and every "Julia X"; `victoria` (Queen Victoria) counted the Australian state; `cnn` counted
CNN's own pages. Now, per document:
- names that are the document's own `<PAGE_AUTHORS>`, the outlet's own brand (`cnn` on cnn.com, `fox news` on
  foxnews.com), credit markers, names that only occur within 60 characters of a credit marker, or names that only occur
  in the closing contributor lines are not matched;
- a V1-only ("ghost") name is set aside and decided at the end of the file: it drops the hit only if it is a multi-word
  name that is a credit across the file (photo credits). Acronyms ("CNN") and forms like "United States" that AllNames
  omits still count (n9; n8 dropped them, which cost cnn 10/10 and united states 25/297 in a test file);
- the registry kind (`match.kind`, added by `ripples.att_news_terms`, sql/26) decides which names may match: a one-word
  pattern of a person, work or organisation must be the whole name and not the short form of a longer V1Persons name in
  the same document; places never match through V1Persons names ("Jordan" in "Michael Jordan"); persons, works and
  organisations never match through V1Locations features ("Victoria", Australia). Unknown kinds keep the phrase match.

Dry run on 20260925190000 (1,546 documents), pre-n8 -> stored: julia 20 -> 0, victoria 5 -> 0, cnn 10 -> 10,
united states 297 -> 297, india 104 -> 103, russia 53 -> 53, xi jinping 21 -> 20, vladimir putin 14 -> 14.
`extra.files[].term_screen` reports the documents removed per reason (`byline`, `self`, `credit`, `ghost`, `tail`) and
the ghost hits kept (`ghost_kept`). Dry runs also return `term_screen` (top terms: stored vs pre-n8, with reasons) and,
with `params.terms`, `term_screen_selected`.

**Candidates and edges.**
- Entity kind is a vote across V1Persons / V1Organizations / V1Locations; a name that is a V1Locations feature in a fifth
  of its documents is a place ("Los Angeles" was tagged person).
- Junk labels now include phrase fragments (verbs such as has/is/was/said, or 7+ words: "Biggest Protests Ireland Has
  Ever Seen"), bare titles ("Prime Minister") and anonymous roles ("... Resident", "... Spokesperson"); title stubs
  ("Sir Mark", "Police Commissioner Sir Mark", "Republican President George"; royal and papal names are kept) and
  title-prefixed duplicates of a name present on its own ("Justice Minister Naomi Long" when "Naomi Long" is there).
- Person-like names (V1Persons or AllNames-only) need 5 outlets and, in addition, either 10 outlets or 2 source
  countries (ccTLDs). This keeps a private individual in a syndicated local story out ("Melissa Premaratne": 8 UK
  outlets, 1 country -> dropped as `local`), while Dolly Parton (16 outlets, 2 countries) and Masoud Pezeshkian
  (10 outlets) stay. It applies to edge endpoints too.
- Cold start: an entity outside the EWMA baseline is expected at max(0.25 per 1000 documents, lowest kept baseline), so
  its z no longer equals its raw count; such candidates carry `meta.method = 'gkg_burst_ewma_v3_cold'`, the rest
  `gkg_burst_ewma_v3`. `EWMA_KEEP` 4000 -> 6000 (the baseline was full, so common names fell out of it).
- The SQL second screen (`news_entity_stop_regex`, sql/26b) carries the fragment, bare-title and anonymous-role patterns.

Cleanup (sql/26c, one-off): today's GKG candidates (512) and edges (849) written before n9 were deleted and are rebuilt
by n9 runs from 19:55 UTC. `attention_obs` rows for 2026-09-25 mix pre-n8 and n9 counts (the day is a warm-up day for
the 28-day baseline anyway).

Tests: 61 mock checks (`t.mjs` 37, `t8.mjs` 24) and `tsc --strict` against the real `att.ts`.
