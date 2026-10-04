# Data sources v2: thirteen candidates for measured steps

**Date:** 2026-10-04. **Question:** can each source give `chain_check.py` a dated, aggregate series that `series_test` can score against its own placebo history, and which of the 79 chains (55 before pageviews begin in August 2015; 350 `record` steps, 92 `none`) gain a testable step?

## Probe results

One request per endpoint from this container, project user agent, 20-second limit. **Every request failed at the proxy (`CONNECT tunnel failed, response 403`; data.gdeltproject.org: "Host not in allowlist").** That is this environment's egress policy, not a site refusal: no host saw our agent. The real probes must run on GitHub Actions (`ripples-source-probe.yml`). The BigQuery REST calls reached Google and returned 401, expected without the workflow's token.

| # | Source | Here | Earliest; updates | Key / terms |
|---|---|---|---|---|
| 1 | Regulations.gov v4 | blocked | 2003 (dense from ~2010); daily | api.data.gov key; public domain |
| 2 | CourtListener v4 | blocked | opinions to the 1700s, RECAP dockets 2009; daily | free token; attribution asked |
| 3 | Congress.gov v3 | blocked | 1973; daily | api.data.gov key; the website 403s our agent, the API host is separate |
| 4 | openFDA | blocked | FAERS/CAERS 2004, MAUDE 1991, recalls 2012; quarterly | no key to 1,000/day; CC0 |
| 5 | CPSC | blocked | recalls 1973, NEISS files 1997; yearly | no key; files, not an API |
| 6 | NHTSA | blocked | recalls 1966, complaints ~1995, FARS 1975; yearly | no key |
| 7 | SEC EDGAR | blocked | full-text 2001, XBRL facts 2009; daily | no key; SEC wants a contact email in the UA, 10 req/s |
| 8 | PatentsView | blocked | grants 1976, applications 2001; quarterly | free key by form; CC BY 4.0 |
| 9 | FEC | blocked | itemized 1979, clean by date from 2001; weekly | api.data.gov key |
| 10 | EIA v2 | blocked | gasoline 1990, Henry Hub 1997, MER 1949; weekly | free key |
| 11 | USDA NASS | blocked | annual to 1866, monthly prices 1908; annual | free key |
| 12 | GDELT DOC API | blocked | 2017-01; 15 min | no key, 1 req/5 s; **runners already get 429** (`RESULTS.md`) |
| 13 | GDELT on BigQuery | 401 | events 1979 (coded, no text), GKG 2015-02, TV n-grams 2009-07; daily | sandbox only, no billing |

## What each gives, and which steps move

| # | Series for the checker | Steps upgraded (slug · n) | Days |
|---|---|---|---|
| 1 | Comments per week on a docket | flint-lead-pipes 8, flint-lead-pipes 10, planet-earth 4 | 1.5 |
| 2 | Opinions or dockets per month matching a term | liebeck-hot-coffee 4 (citations per year), dobbs 5, exxon-valdez-opa90 7 | 2 |
| 3 | Cosponsors added per day; actions and hearings per month | sixty-minutes-stock-act 2 (9 → 100 cosponsors, daily), daily-show-zadroga 2, tiger-king 3, planet-earth 5, gamestop 3 | 2 |
| 4 | Adverse-event or recall reports per month | none today (Tylenol 1982, Viagra 1998 predate FAERS) | 1.5 |
| 5 | NEISS injury estimates per year by product code | planet-earth 3 (TV and furniture tip-overs) | 2.5 |
| 6 | FARS deaths per year by state (`dose`: belt-law states vs the rest) | unsafe-at-any-speed 9, unsafe-at-any-speed 10 | 3 |
| 7 | Filings per month whose text mentions a term | chatgpt 2 ("generative AI" in 10-Ks), ever-given 5 ("just-in-time"), covid-remote 1, svb 5, gamestop 4 | 1.5 |
| 8 | Grants or applications per quarter by CPC class or term | tylenol 4 (tamper-evident packaging, from 1976), jwst 5, airpods 3 | 2 |
| 9 | Receipts per day to a class of committees | columbine 2 (gun-control PACs, 1999–2000); a new dobbs step (abortion-rights PACs, 2022) | 2 |
| 10 | Weekly prices, monthly production and capacity | three-mile-island-nrc 7 (nuclear capacity), ethanol-tortilla 2; winter-storm-uri 2 is already FRED | 1 |
| 11 | Annual acres, yields, tons crushed and prices by crop and variety | sideways 3, 4, 5 (California grape crush, Merlot vs Pinot Noir), ethanol-tortilla 2, haber-nitrogen 5, dust-bowl-soil 5 | 1.5 |
| 12 | Articles per day matching a phrase, 2017 on | a second attention series for mr-bates-horizon 2, adolescence-schools 2, ocean-attenborough 2 | 1 |
| 13 | See below | the 2009 TV n-grams are already a Q6 lens | 0 |

**Work basis:** each source is one fetcher in `series_fetch.py` writing keys into `series_v1.json`, scored by the existing `file` step type; the days cover the fetcher, the CI secret, a dry run, the methods note and a registered re-run. NEISS and FARS are yearly bulk files with codebooks. EDGAR needs the owner to approve a sec.gov-only UA with a contact address.

## BigQuery and the no-billing rule

The project already queries BigQuery keylessly under the sandbox cap (204.8 GiB a day; Google's free allowance is 1 TiB a month). `gdelt-bq.full.events` (1979 on) is CAMEO-coded actors and actions with no text, so it cannot count attention to a film or a term. `gdeltv2.gkg` (February 2015 on) carries names and themes, but one chain's placebo window scans tens to hundreds of GiB, and it reaches nothing before 2015. `gdeltv2.iatv_1gramsv2` (TV captions, July 2009 on) is the one GDELT table older than pageviews, already in use (`q6_lenses_protocol.md`). Verdict: the free tier covers the events table and the TV n-grams, not GKG term searches; paying would break the rule. No new step type; extend the Q6 lens.

## Ranking

**Most measured steps per day of work**

1. **USDA NASS Quick Stats** (1.5 days, 6 steps). The grape crush report tests the whole Sideways chain; corn and fertilizer reach the 2007 and 1960s chains. Annual data means small placebo pools (n ≈ 40), reported as such.
2. **Congress.gov** (2 days, 5 steps). Cosponsor dates turn "9 to 100 within weeks" into a daily series with the bill's own history as placebo; actions and hearings date the law steps the engine finds.
3. **SEC EDGAR full-text search** (1.5 days, 5 steps). Corporate language is a behavior, not attention: "just-in-time" after Ever Given, "generative AI" after ChatGPT. PatentsView (2 days, 3 steps, a 1976 baseline) is a close fourth.

**A pre-2015 attention baseline.** None of the thirteen is a general public-attention series before 2015: GDELT DOC starts in 2017, the GKG in 2015, and the event files are coded, not textual. The list offers attention in particular arenas with long histories: courts (CourtListener), Congress (1973), inventors (PatentsView, 1976), donors (FEC, 1979) and public companies (EDGAR, 2001). Each is a fair "did anyone act on it" series for a pre-2015 chain, labeled by arena, never dressed as public attention. The general baseline must come from outside this list (the repo's NYT Archive and Books Ngram tools, the 2009 TV n-grams).

**Skip, for now**

- **openFDA**: no catalog step falls inside its history; keep for a future drug chain.
- **EIA**: FRED already mirrors what the chains use.
- **GDELT DOC**: 429 for runners and 2017-only; the weekly retry is enough.
- **GDELT GKG on BigQuery**: outside the free tier for term counts.
- **FEC**, **Regulations.gov**: narrow, two or three steps each; add when a chain needs them.
- **CPSC**, **NHTSA**: one chain each; NHTSA first, since the FARS belt-law design would be a second rung-three test.

**Next step:** run the thirteen probes from `ripples-source-probe.yml`, one request each, and record the real statuses here before any fetcher is written.
