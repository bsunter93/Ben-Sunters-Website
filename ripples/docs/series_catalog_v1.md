# Series catalog v1: behavior outcome series a measured grade can stand on (Oct 5, 2026)

Built under the rule registered in `ripples/docs/measure_plan_v1.md` section 3. Code: `ripples/lab/series_catalog.py`.
Data: `ripples/docs/results/series_catalog_v1.json`.

## The answer

- **28 series catalogued; 24 are eligible behavior series** (public, aggregate, no key, no account). One needs a key and
  is excluded (FBI Crime Data Explorer). Two are attention, not behavior, and can serve only as exposure measures (Books
  Ngram, Wikipedia pageviews). One is a platform that mirrors others (FRED).
- **Top by power** (at least 10 geographic units, then the p floor): NHTSA FARS (monthly from 1975, 51 states), NPS
  visitor use (monthly from 1979, about 420 park units), Statistics Norway hotel nights (monthly from 1985, 19 counties by
  residence country), BLS state and metro jobs (monthly from 1990, about 450 areas), BTS T-100 air passengers (monthly
  from 1990, about 400 airports), FBI NICS background checks (monthly from 1998, 51 states).
- **Reachable today:** NPS, Statistics Norway, BLS, BTS, CDC WONDER and most others answered 200. Three hosts refused
  the project's agent with 403 and are stopped for the day with no retry: www.ssa.gov (baby names), crashviewer.nhtsa.dot.gov
  (FARS) and www.fbi.gov (NICS). So the longest monthly state series (FARS), NICS, and both baby-name files could not
  be used today.

## Power, in one line per frequency

The smallest p a series can give is 1/(N+1), where N is the number of admissible placebo windows before the stone.

- **Annual, national.** With N admissible years, the floor is 1/(N+1). Defra flour (1974 on) gives 38 windows for a
  2015 stone (floor .026); ONS baby names (1996 on) give 16 (floor .059), which cannot reach p ≤ .05 at all; BRFSS
  (2011 on) gives 1.
- **Monthly.** A one-month year-over-year change gives about 12 windows a year of history: CDC WONDER deaths (1999 on)
  give 158 for a 2015 stone (floor .006), NPS (1979 on) 398 (floor .0025). These windows overlap, so N overstates the
  independent information; the floor is still the hard limit.
- **Geography** is power of a different kind: it is what the exposure gradient (test v2 rung iii) needs. NPS park units,
  BLS areas, QCEW counties (about 3,200), airports, INSEE departements (about 100) and the state files all carry it.
  CDC WONDER does not through the API (national data only), so its exposure dimensions are age and cause categories.

## The catalog

| Rank | Series | Frequency, start | Geography (units) | Unit | Placebo windows before a 2015 stone (p floor) | Access | Probe, Oct 5, 2026 |
|---|---|---|---|---|---|---|---|
| 1 | Fatality Analysis Reporting System: fatal crashes (NHTSA) | monthly, 1975 | state and county (51) | fatal crashes and deaths (aggregated by us from case records) | 446 (0.0022) | no key, no account | HTTP 403 to the landing-page probe (host stopped for the day; no retry) |
| 2 | Visitor use statistics: recreation visits by park unit (National Park Service) | monthly, 1979 | park unit (about 420 units; annual totals from 1904 for the oldest parks) (420) | recreation visits | 398 (0.0025) | no key, no account | host called by measure_v1.py today: HTTP 200 |
| 3 | Hotels: guest nights by county and guests' country of residence (table 08402) (Statistics Norway) | monthly, 1985 | county by residence country (19) | guest nights | 326 (0.0031) | no key, no account | host called by measure_v1.py today: HTTP 200 |
| 4 | Current Employment Statistics, state and metro jobs by industry (Bureau of Labor Statistics) | monthly, 1990 | state and metro area (450) | jobs (thousands) | 266 (0.0037) | no key for the v1 API (25 queries a day, 10 years each) | HTTP 200 |
| 5 | T-100 segment data: air passengers by airport and route (Bureau of Transportation Statistics) | monthly, 1990 | airport (400) | passengers | 266 (0.0037) | no key, no account (download form) | HTTP 200 |
| 6 | NICS firearm background checks by state (FBI) | monthly, 1998 | state (51) | background checks (a proxy for sales, not sales) | 170 (0.0058) | no key, no account (a PDF table) | HTTP 403 to the landing-page probe (host stopped for the day; no retry) |
| 7 | International arrivals to the US by country of residence (I-94) (National Travel and Tourism Office) | monthly, 2000 | country of residence (90) | arrivals | 146 (0.0068) | no key, no account (monthly workbooks) | HTTP 200 |
| 8 | Fichier des prenoms: first names given in France (INSEE) | annual, 1900 | departement (about 100) (100) | births given a name (3 or more) | 112 (0.0088) | no key, no account | HTTP 200 |
| 9 | Baby names from Social Security card applications, by state (Social Security Administration) | annual, 1910 | state (50 and DC) (51) | births given a name (names with 5 or more per state) | 102 (0.0097) | no key, no account | not probed: www.ssa.gov stopped earlier today (HTTP 403) |
| 10 | Quarterly Census of Employment and Wages, county by industry (Bureau of Labor Statistics) | quarterly, 1990 | county (about 3,200) (3200) | establishments, jobs, wages | 92 (0.0108) | no key, no account | HTTP 200 |
| 11 | Hunting and fishing license certifications by state (US Fish and Wildlife Service) | annual, 1958 | state (50) | paid license holders | 54 (0.0182) | no key, no account (yearly tables) | not probed (no landing page registered for a probe) |
| 12 | IPEDS completions by field of study (CIP) (NCES) | annual, 1984 | institution (aggregates to state) (7000) | degrees and certificates awarded | 28 (0.0345) | no key, no account (bulk files) | HTTP 302 (the landing page redirected; not followed further) |
| 13 | County Business Patterns: establishments and jobs by industry (Census Bureau) | annual, 1986 | county (3200) | establishments, jobs | 26 (0.037) | no key up to 500 queries a day | not probed (no landing page registered for a probe) |
| 14 | Youth Risk Behavior Survey, high school, by state (CDC) | annual, 1991 | state (biennial; not every state every wave) (46) | share of students | 21 (0.0455) | no key (Socrata) | not probed (no landing page registered for a probe) |
| 15 | Baby names in England and Wales (Office for National Statistics) | annual, 1996 | England and Wales, with regions (10) | births given a name (3 or more) | 16 (0.0588) | no key, no account | HTTP 200 |
| 16 | BRFSS prevalence data by state (CDC) | annual, 2011 | state (54) | share of adults | 1 (0.5) | no key (Socrata, throttled without a token) | HTTP 200 |
| 17 | Traffic Volume Trends: vehicle miles traveled (FHWA) | monthly, 1970 | national from 1970 (FRED TRFVOLUSM227NFWA); states in the monthly reports (archive years not verified in this pass) (1) | vehicle miles | 506 (0.002) | no key, no account (monthly reports; national series on FRED) | HTTP 200 |
| 18 | Monthly retail trade sales by kind of business (Census Bureau) | monthly, 1992 | national (1) | US dollars | 242 (0.0041) | no key up to 500 queries a day | HTTP 200 |
| 19 | Natality (D10 1995-2002, D27 2003-2006, D66 2007 onward), births by month (CDC NCHS via CDC WONDER) | monthly, 1995 | national through the API (1) | births | 206 (0.0048) | as D76 | host called by measure_v1.py today: HTTP 200 (this database or file was not queried) |
| 20 | Underlying cause of death 1999-2020 (D76), by month of death (CDC NCHS via CDC WONDER) | monthly, 1999 | national through the API (state and county only in the web tool) (1) | deaths | 158 (0.0063) | no key, no account; the API requires accepting the data use restrictions (owner accepted Oct 5, 2026) | host called by measure_v1.py today: HTTP 200 |
| 21 | Baby names from Social Security card applications, national (Social Security Administration) | annual, 1880 | national (1) | births given a name (names with 5 or more) | 132 (0.0075) | no key, no account | not probed: www.ssa.gov stopped earlier today (HTTP 403) |
| 22 | Family Food: household purchases per person per week (Defra (UK)) | annual, 1974 | UK (regions as three-year averages) (1) | grams or ml per person per week | 38 (0.0256) | no key, no account | host called by measure_v1.py today: HTTP 200 |
| 23 | National Electronic Injury Surveillance System: injury estimates by product (CPSC) | annual, 1997 | national (a probability sample of hospitals) (1) | weighted emergency visits | 15 (0.0625) | no key, no account | HTTP 200 |
| 24 | Underlying cause of death 2018 onward, single race (D158) and provisional (D176) (CDC NCHS via CDC WONDER) | monthly, 2018 | national through the API (1) | deaths | 0 (none) | as D76 | host called by measure_v1.py today: HTTP 200 (this database or file was not queried) |
| excluded | Crime Data Explorer: offenses by agency and state (FBI) | monthly, 1985 | state and agency (51) | reported offenses | 326 (0.0031) | needs an api.data.gov key: excluded under the no-key rule | not probed: needs a key |
| attention | Google Books Ngram: term frequency by year (Google Books) | annual, 1800 | language corpus (8) | share of all words that year | 212 (0.0047) | no key, no account (bulk files) | HTTP 200 |
| attention | Wikipedia pageviews by article and language edition (Wikimedia) | daily, 2015 | language edition (a country-exposure proxy where a language maps to a country) (300) | pageviews | 0 (none) | no key, no account | HTTP 200 |
| platform | FRED: economic series, many by state (fredgraph.csv) (Federal Reserve Bank of St. Louis) | monthly, 1947 | national and state (series by series) (51) | varies | 782 (0.0013) | no key for fredgraph.csv | not probed (a platform; used by chain_check) |

Rank orders the eligible behavior series: first those with at least 10 geographic units, then by the p floor, then by
units. Start years are the first year of the series as published; N is counted for a 2015 stone with the shortest
window each frequency allows, minus the excluded periods (2008-09 crisis months; the pandemic months lie after 2015).

## Notes

- **CDC WONDER.** The API needs consent to the data use restrictions on every query (the owner accepted them on Oct 5,
  2026). Use is for statistical reporting only, no count of nine or fewer births or deaths may be presented, and no
  attempt may be made to identify anyone. The API returns national data only; the web tool's state and county data
  cannot be reached by the API. WONDER asks for one query at a time, about 2 minutes apart.
- **NPS.** Monthly recreation visits since 1979 for every unit. Counting methods change by unit and year, and a
  method change looks like a rise. The visitation operation answers in XML by default.
- **SSA names.** The national file (1880 on) and the state files (1910 on) are the obvious series for naming marks
  (Peaky Blinders → Arthur and Ada). www.ssa.gov refused the project's agent today (403) and the database network on
  Sep 27; the BigQuery copy is out under the no-BigQuery rule. INSEE (France, by departement, 1900 on) and ONS (England
  and Wales, 1996 on) are reachable alternatives for non-US naming marks.
- **FARS and NICS** are the strongest monthly state series after NPS. Both hosts refused the landing-page probe today.
  FARS is case-level, so only aggregates would be kept. NICS counts background checks, not sales, and permit rechecks
  inflate some states.
- **Attention series** (Ngram, pageviews) never grade a behavior mark. Pageviews by language edition are an exposure
  measure for country gradients after July 2015.

## What it changes

Of the engine's 15 non-record marks, the ladder found series for 5. This catalog lists series for kinds of marks the
engine has not yet produced: park visits after films and documentaries, deaths by cause after media events, jobs and
establishments by county after a show or a disaster, air travel after a destination appears on screen, enrollment by
field after a documentary. `ripples/docs/measure_v1.md` runs the first two.
