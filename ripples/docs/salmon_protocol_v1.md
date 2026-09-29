# Salmon search v1: swimming upstream from baby-name surges (registered 2026-09-29, before any data is fetched)

**Idea (owner, 2026-09-29):** reverse the discovery chain. Start from an outcome that moved unusually, then look
upstream for the events that could plausibly have caused it. Be open about why each link was surfaced and how it was
scored, and label every link as speculative.

**Why baby names first:**
- The data is complete, national and annual.
- Names connect to their causes through text (a character or title carries the name).
- Famous known cases exist to test the linker on.

## What is rigorous and what is speculative

| Step | Status |
|---|---|
| The anomaly (a name broke from its own trend) | Measured. It is a fact about the data. |
| The proposed upstream cause | **Speculative.** It is surfaced by a transparent score and labelled "Possible link (speculative)", with the chance-match rate beside it. |
| Cause and effect | Never claimed. A link becomes "tested" only after a separate pre-registered test. |

## Data

- **Names:** US baby names, national counts per (name, sex, year), 1985 onward, names with at least 5 births in a year
  (the SSA floor). Source: `bigquery-public-data.usa_names.usa_1910_current` (`ripples/tools/bq/salmon_names.py`).
  Only aggregates are used, and nothing is stored in the database.
- **Upstream candidates:** Wikidata, through the query service.
  - EntitySearch on the name (English labels and aliases, up to 50 items).
  - For each item, the dated creative works it is present in (P1441; characters), or the item itself when it is a
    dated work (P577; works titled with the name).
  - Each work's first publication year and its sitelink count (a measure of prominence).

## Method (`ripples/lab/salmon.py`, frozen at this commit)

1. **Anomalies.**
   - For each (name, sex, year t), the break score is s = [log(n_t + 20) − log(n_(t−1) + 20)] minus the median of
     that yearly change over t−5..t−1.
   - A name-year qualifies if n_t ≥ 100 and s ≥ log 1.5.
   - Each name keeps its strongest onset.
   - The top 200 names by s are the starting points.
   - Years are 1996 to the last year in the data.
   - Excess births = n_t minus the trend-expected count.
2. **Candidate works:** as in Data above. An item counts only if the name is its whole label or first word, in the
   label or an alias (match 1.0), or a later word (match 0.6).
3. **Score** = match × timing × prominence.
   - **Timing:** lag = t − first publication year.

     | Lag (years) | Weight |
     |---|---|
     | 0–2 | 1.0 |
     | 3–5 | 0.5 |
     | 6–10 | 0.2 |
     | more than 10 | 0.05 |
     | negative (after the onset) | excluded; the time order must hold |

   - **Prominence:** min(1, log10(sitelinks + 1) / 2).
   - The top 5 works per anomaly are reported, with the character (relay) they came through.
4. **Chance-match rate.**
   - The same linker is run on 200 placebo name-years: names that never qualify as an anomaly, each at a random year
     with n ≥ 100 (seed 20260929).
   - A link's chance-match rate = (1 + number of placebos scoring at least as high) / 201.
   - Also reported: the share of the same name's other years (at least 3 years away) where the linker finds a match
     this strong.
5. **Roles** (the upstream taxonomy, first version):
   - **Origin:** the work, meaning the earliest cause we can see, not "the root cause".
   - **Relay:** the character that carries the name.
   - **Echo:** the work's own title carries the name.
   - **Outcome:** the name-year.
   - Common drivers and amplifiers are not modelled in v1.

## Benchmark (fixed now, before any result)

These are 9 well-known name ripples. The linker is scored at the listed year whether or not the anomaly scan
detected it; detection is reported separately.

| Name | Sex | Year | Known cause (accepted work labels) |
|---|---|---|---|
| Elsa | F | 2014 | Frozen |
| Khaleesi | F | 2012 | Game of Thrones / A Song of Ice and Fire |
| Arya | F | 2012 | Game of Thrones / A Song of Ice and Fire |
| Daenerys | F | 2012 | Game of Thrones / A Song of Ice and Fire |
| Katniss | F | 2012 | The Hunger Games |
| Kylo | M | 2016 | Star Wars / The Force Awakens |
| Renesmee | F | 2009 | Twilight / Breaking Dawn |
| Moana | F | 2017 | Moana |
| Anakin | M | 1999 | Star Wars / The Phantom Menace |

- **Metrics:**
  - hit@1 and hit@3 of the known work;
  - the known link's chance-match rate;
  - whether the scan detected the name-year.
- **Pass rule: hit@1 ≥ 6 of 9.**
- **If the linker fails:** the feed is still saved, but it is not shown as a discovery list on /ripples/discover/.
  The failure is reported and the linker is revised under a new version.

## Known limits of v1

- **Only fiction and titled works** are proposers. Name surges driven by real people (celebrities, athletes, royal
  babies) get no candidate or a weak one. Proposers for people, and Wikipedia pageview lead–lag, come in v2.
- **The benchmark is famous.** The linker's weights were chosen with these cases in mind (not tuned on their data),
  so the benchmark checks mechanics rather than proving generality. The discovery list is judged by chance-match
  rates and by the owner's surprise check.
- **The years are annual.** "Frozen (Nov 2013) → Elsa 2014" is lag 1. Timing is coarse.

## Politeness

- **BigQuery:** a public dataset, dry-run under a 2 GiB cap.
- **Wikidata query service:** honest User-Agent, 1 s between queries, results cached, and a stop on 403/429 or a
  gateway error. A query-level 500 is recorded for that name and the run continues.
- It runs on GitHub Actions (`ripples-salmon.yml`) alongside the pageview fetch. This is a different Wikimedia
  service at a low rate, run concurrently per the owner's 2026-09-29 direction to stop waiting.

## Output

- `salmon_names_v1` in `ripples.att_q3_results`, saved as `ripples/docs/results/salmon_names_v1.json`.
- Shown on /ripples/discover/ as "What moved, and what might explain it" if the benchmark passes.

## Deviation 1 (registered 2026-09-29, before any result existed): v1.1 query implementation

- **What happened:** the first run (Actions run 36530730042) stopped within its first minute. The Wikidata query
  service returned HTTP 504, a gateway timeout: the single SPARQL query (EntitySearch inside SPARQL plus the label
  service) was too heavy. No anomaly, placebo or benchmark result was produced or seen.
- **Changes:**
  - Items are now found with Wikidata's search API (`wbsearchentities`: English labels and aliases, up to 50).
  - Those item ids go into one small SPARQL query for works (P1441), dated works (P577), dates, sitelinks and English
    work labels.
  - A query-level 500/504 for one name is recorded in `failed_queries`, and that name gets no candidates (a benchmark
    name counts as a miss).
  - The run still stops on 403/429 or after 3 failures in a row.
- **Unchanged:** scoring, anomalies, placebos, benchmark and pass rule.
