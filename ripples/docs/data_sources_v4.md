# Data sources v4 (Oct 8, 2026): beyond Wikipedia

Each source was probed once on Oct 8 with the user agent "ripple-research (bensunter.com)". Status is the HTTP code.
The catalog before this one is `docs/data_sources_v3.md`.

## Need an account or key (the owner offered to create them)

| Source | Unlocks | Terms seen | Status |
|---|---|---|---|
| Reddit Data API (script app) | r/todayilearned: upvotes as real surprise scores; posts cite sources | not verified (reddit.com returned 403 unauthenticated) | 403 |
| api.data.gov key | govinfo (Congressional Record, Federal Register), FBI crime data, Regulations.gov, FDA | signup page | 200 |
| Merriam-Webster Dictionary API | first-known-use dates: the record for word ripples | free if noncommercial, 1,000 queries a day per key | 200 |
| Guardian Open Platform | article text since 1999, UK and world records | free noncommercial, 1 call a second, 500 calls a day | 200 |
| Google Fact Check Tools API | fact-checkers' verdicts: busted ripples | Google Cloud key | 200 |
| Spotify Charts (account) | daily and weekly charts by country: song revivals | login to download | 200 |
| BoardGameGeek XML API | board games and chess sets after shows | now needs registration | 401, then a Cloudflare 403 |
| Stack Apps key | Stack Exchange quota from 300 to 10,000 a day | optional | 200 |

## No account (all answered on Oct 8)

Skeptics Stack Exchange API (voted answers to "did X cause Y"), Hacker News Algolia, Library of Congress Chronicling
America (to 1963), Internet Archive advanced search, UK Hansard API, ListenBrainz stats, Billboard Hot 100 weekly JSON
since Aug 4, 1958 (GitHub mhollingshead/billboard-hot-100), Discogs CC0 dumps, Open Library (first publish year,
reading-log counts), ClinicalTrials.gov API v2, GDELT TV API (needs a station parameter), SteamSpy, Web Robots
Kickstarter dumps, AO3 selective data dump, Common Crawl News, GSS, NFHS participation archive, College Board AP data
archive, UCAS undergraduate statistics, NTTO I-94 arrivals, ALVA attraction visits, BLS API v1, USDA ERS food
availability. OpenAlex, PubMed and Crossref are in use by the studies pilot (`docs/studies_v1.md`).

## Refused on Oct 8 (retry another day)

OpenPrescribing 403, NHS Digital cervical screening 403, BoardGameGeek 403. A Stats NZ page returned 404 from a wrong URL.
