# Data sources v3: sources for surprising, defensible ripples

**Date:** 2026-10-08. **Question:** which free sources would let the engine find links that are both surprising and defensible, beyond laws found in text? The last run found 12 of 102 finds that were both surprising and believable. 87 of the 102 were laws.

**Scope.** This file covers sources not already in `data_sources_v2.md` or the known list (pageviews, SSA names, Trends, NYT, TMDB, Open States, CourtListener, Federal Register, Congress.gov, EDGAR, PatentsView, FEC, EIA, NASS, GDELT, Media Cloud, CDC WONDER, NPS, QCEW, NEISS, FARS, openFDA, Regulations.gov, Netflix Top 10).

**How it was checked.** Documentation pages were read directly. Data requests sent the user agent `ripple-research (bensunter.com)`. I made at most two requests per host and stopped on any 4xx. The full log is at the end. Probe queries and results were kept outside the repo. Where a cell says "web search only", nothing on that host was requested. The facts in that cell come from search results and should be confirmed before building.

**Reading the tables.** "Siblings" is the number of parallel categories a candidate is ranked against in the same period. That rank is the placebo. Every example pair is a hypothesis. None has been tested.

---

## Need 1. Outcome-first scans with a cross-sectional placebo

| Source | URL | One row is | First year | Granularity | Siblings | Geography | Key / account | License / terms | Bulk size | Verified how | Example stone -> outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|
| INSEE Fichier des prénoms (France) | https://www.insee.fr/fr/statistiques/8595130 | first name x sex x year x area: births (rounded to 5) | 1900 (to 2025) | yearly | tens of thousands of names (the list of names given 3+ times since 1900 is published; the page gives no total) | nation, region, department (lightweight department file from 2000) | none | INSEE open data. The page names no licence; INSEE's general reuse terms apply (free reuse, cite source). Confirm. | national 4 MB, department 17 MB, everything as Parquet 18 MB | doc page read (200) | Hypothesis: *Le Grand Bleu* (1988) -> boys named Enzo, with a larger rise in coastal departments than inland ones |
| Other national name files | SSB table 10467: https://www.ssb.no/en/statbank1/table/10467/ ; NRS: https://www.nrscotland.gov.uk/statistics-and-data/statistics/statistics-by-theme/vital-events/names/babies-first-names ; ONS: https://www.ons.gov.uk/peoplepopulationandcommunity/birthsdeathsandmarriages/livebirths/datasets/babynamesinenglandandwalesfrom1996 ; Quebec and BC on open.canada.ca | name x sex x year: births | Norway 1880, Scotland 1974, England and Wales 1996, Quebec 1980, BC about 1915 | yearly | thousands of names each | national; Quebec and BC are provinces | none | Norway NLOD (credit SSB); ONS OGL v3 (stated by third parties); BC Open Government Licence; Quebec likely CC BY (not confirmed); NRS terms not confirmed | small (MB) | web search only | Hypothesis: *Game of Thrones* (2011) -> Arya rose in England and Wales, Scotland and Norway in the same years, ranked against each country's other names |
| Lichess open database | https://database.lichess.org/ | one rated game (PGN) with `ECO` and `Opening` tags, Elo, clock | 2013-01 | monthly files; game timestamps | about 500 ECO codes; a few thousand named lines in lichess-org/chess-openings (count not verified) | none in the PGN | none for downloads | **CC0** (stated on the page) | 2.6 TB total, 165 files, 8.2 billion games. Jan 2013 is 17.8 MB (121k games); Sep 2026 is 29.2 GB (89.6 M games). A partial download can be decompressed, so the first N GB of each month gives a sample. | doc page read (200) | Hypothesis: *The Queen's Gambit* (Oct 2020) -> the share of games opening 1.d4 d5 2.c4 rose more in Nov to Dec 2020 than any sibling opening's share |
| Lichess opening explorer (precomputed monthly counts) | `https://explorer.lichess.org/lichess?fen=...&since=YYYY-MM&until=YYYY-MM&history=true` | per position: white wins, draws, black wins; `history=true` adds monthly history | 2013-01 (default `since` is 1952-01) | monthly | any position, so every named opening | none | **OAuth2 token required** per the current API spec: free Lichess account, personal token at https://lichess.org/account/oauth/token | data from the CC0 database; the explorer code is AGPL-3.0; the API asks for no parallel requests and backoff on 429 | one request per opening (a few thousand calls) | API spec read on raw.githubusercontent.com (200); lichess.org/api renders in JS and returned nothing | Same test, done in an afternoon instead of streaming terabytes |
| FIDE rating lists | https://ratings.fide.com/download.phtml | one rated player per list: ID, federation, sex, birth year, title, rating | Jan 2001 (every 4 months to 2009, quarterly 2010 to mid-2012, monthly since July 2012) | per list | about 200 federations x sex x age band; new IDs per list = new rated players | country (federation) | none | FIDE site terms not found; check before bulk use | one zip per list (size not verified) | web search only | Hypothesis: *The Queen's Gambit* -> more new female rated players per list from Nov 2020, larger where the show ranked higher in Netflix Top 10 by country |
| Google Books Ngram v3 (20200217) | https://storage.googleapis.com/books/ngrams/books/datasetsv3.html | ngram x year: match count, volume count | reliable from 1800; ends 2019 | yearly | millions of words and phrases | none, but separate corpora (American English, British English, French, German, Spanish, others) | none | **CC BY 3.0** (stated on the page) | 1-gram size not stated on the page read; 2- to 5-grams are much larger | doc page read (200) | Hypothesis: *La Dolce Vita* (1960) -> "paparazzi" breaks from trend in English books in the 1960s, ranked against all 1-grams' breaks that decade |
| Seattle Public Library, Checkouts by Title | https://data.seattle.gov/d/tmmm-ytt6 | title x month: checkouts, with Subjects, MaterialType, Creator, PublicationYear | 2005-04 | monthly | millions of titles; subject headings in the tens of thousands (not counted) | Seattle only (no gradient) | none (Socrata app token optional) | **Public Domain** (dataset metadata) | 51.8 M rows; updated 2026-09-06 | metadata request (200) | Hypothesis: *Chernobyl* (HBO, May 2019) -> checkouts of nuclear-power subject titles other than the Chernobyl books, against all subjects' monthly breaks |
| USPTO Trademark Case Files Dataset | https://www.uspto.gov/ip-policy/economic-research/research-datasets/trademark-case-files-dataset | one application or registration: filing date, mark text, classes, owner, events | 1870 (through March 2024; daily XML after that) | daily filing dates | 45 Nice classes; every word in mark text as a sibling | owner state or country | none stated; links are now temporary signed URLs, also in the USPTO Open Data Portal bulk directory | no licence stated (US government work); USPTO asks for a citation of Graham, Marco and Miller (2018) | 12.7 M records; full CSV 4.33 GB; `case_file` table 414 MB | doc page read (200) | Hypothesis: a viral phrase -> applications containing it within weeks (e.g. "covfefe", May 2017), ranked against every word's monthly filing count |
| NCES IPEDS Completions by CIP | https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx ; crosswalks https://nces.ed.gov/ipeds/cipcode/resources.aspx?y=56 | institution x 6-digit CIP x award level x sex x race: awards | Data Center files from 1980-81; HEGIS before 1986-87. The first Completions year was not confirmed. | yearly (academic year) | about 1,500 to 2,000 six-digit CIP codes per edition (not counted) | institution, so state and county | none | public domain (US government) | tens of MB per year (not verified) | CIP resources page read (200); start year from search | Hypothesis: *CSI* (Oct 2000) -> bachelor's degrees in forensic science (43.0106) grew more from 2003 to 2008 than all sibling CIP codes |
| Census County Business Patterns (and Nonemployer Statistics) | https://www.census.gov/programs-surveys/cbp/data/datasets.html | county x industry: establishments, employment, payroll, size classes | county 1986, MSA 1993, ZIP 1994 | yearly | about 1,000 six-digit NAICS (from 1998; SIC before; from Census documentation, not the page read) x 3,100 counties | county, ZIP, metro | none for files (Census API key optional: https://api.census.gov/data/key_signup.html) | public domain | tens to hundreds of MB per year | doc page read (200) | Hypothesis: *Fixer Upper* (HGTV, 2013) -> accommodation and retail establishments in McLennan County, Texas, ranked against all counties of similar size |
| NCCS Unified BMF (history of IRS exempt organizations) | https://nccs.urban.org/nccs/catalogs/catalog-bmf.html | one EIN with first and last month seen, NTEE code, location | monthly snapshots 1989-06 to 2026-07 (irregular months) | monthly | several hundred NTEE codes; name words | address, so state and county | none (direct S3 links) | no licence stated on the page; the underlying IRS data is public. NTEE-V2 columns were corrected 2026-09-15. | not stated | doc page read (200) | Hypothesis: *Blackfish* (2013) -> new animal-protection nonprofits (NTEE D) in 2014 and 2015, more than sibling NTEE codes |
| IRS EO Business Master File (current) | https://www.irs.gov/charities-non-profits/exempt-organizations-business-master-file-extract-eo-bmf | one currently listed exempt organization (field list in an info-sheet PDF) | ruling dates go back decades, but only for organizations still listed | monthly refresh (posted 2026-09-08) | NTEE codes | state files; filing address | none | no terms on the page | 1,964,958 records, CSV by state and region | page read (200); the info-sheet URL I tried returned 404, so I stopped on irs.gov | Use only with NCCS history. On its own it has survivorship bias: dissolved organizations are missing. |
| NYC Dog Licensing | https://data.cityofnewyork.us/d/nu7n-tubp | one active license-year: dog name, breed, birth year, ZIP, issue date | licenses from 2014-09; birth years go further back | yearly extract | hundreds of breeds; tens of thousands of names | ZIP | none | NYC Open Data terms (no licence field set) | 819,323 rows; updated 2026-07-15 | metadata request (200) | Hypothesis: *Game of Thrones* -> Siberian Husky share of NYC dogs born 2012 to 2016, ranked against all breeds by birth cohort |
| Austin Animal Center Intakes | https://data.austintexas.gov/d/wter-evkm | one intake: breed, intake type (owner surrender, stray), date, found location | 2013-10 (frozen at 2025-05-05) | daily | hundreds of breeds | found location in Travis County | none | **Public Domain** | 173,812 rows | metadata request (200) | Weak for GoT: data begins two years after the show began, so there is no pre-period. Usable for stones after 2014. |
| UK Kennel Club breed registrations | https://www.thekennelclub.org.uk/media-centre/breed-registration-statistics | breed x year: registrations | 2015 in the 10-year PDFs (older files not found) | yearly, quarterly | about 220 breeds | UK | none | site terms not checked | PDFs by breed group | web search only | Hypothesis: *Bluey* (UK from 2019) -> Australian Cattle Dog registrations, ranked against all breeds |
| OpenAlex | https://openalex.org | one scholarly work: year, topics, institutions | 1800s; dense from the 1950s | yearly (exact dates) | about 4,500 topics (count not verified) | institution country | optional: no key needed for basic use; a free key gives 10x the budget (account at https://openalex.org, key at https://openalex.org/settings/api) | data is free; CC0 per OpenAlex docs (not on the page read) | snapshot is large (not verified) | doc page read (301 to help.openalex.org, 200) | Hypothesis: *Lorenzo's Oil* (1992) -> papers on adrenoleukodystrophy 1993 to 1996, ranked against sibling rare-disease topics |
| NIH RePORTER / ExPORTER | https://reporter.nih.gov/exporter | one funded project-year: title, abstract, terms, organization | FY1985 (CRISP legacy files FY1970 to FY2009) | fiscal year | spending categories and terms | organization state | none for the API (third-party sources) | public domain | about 2 GB (ICPSR mirror, largest zip 1.8 GB) | page is a JS shell (200, no content); facts from search | Same Lorenzo's Oil test on funding rather than papers |
| BLS OEWS (occupations) | https://www.bls.gov/oes/tables.htm | occupation x area: employment, wages | 1997 | yearly (May) | about 800 detailed occupations | state, metro | none for files | public domain | small | not probed (bls.gov often refuses non-browser agents) | Hypothesis: *CSI* -> forensic science technicians (19-4092) grew more from 2002 to 2008 than other occupations |
| Recreation.gov RIDB historical reservations | https://ridb.recreation.gov/download | one reservation: facility, dates, group size, customer ZIP or country | 2006 (per a research proposal; CRS warns FY2014 to FY2018 came from a different contractor) | daily | thousands of federal facilities | facility location and **visitor home ZIP** | none for downloads; API key free at https://ridb.recreation.gov | CC BY (data.gov listing) | several GB (not verified) | web search only | Hypothesis: *Yellowstone* (Paramount, 2018) -> reservations at Montana federal sites from ZIPs in high-viewing states |
| MLA Language Enrollment Database | https://apps.mla.org/flsurvey_search (URL not verified) | institution x language x survey year: enrollments | 1958 to 2021 | irregular survey years (about every 3 to 5 years) | over 100 languages (not counted) | institution, so state | none; bulk download not confirmed | not checked | unknown | web search only | Hypothesis: the Korean Wave -> Korean +13.7% (2013 to 2016) and +38.3% (2016 to 2021) while most languages fell. These are MLA's figures; the cause is the hypothesis. Too few time points to date a stone. |

**Notes for Need 1**

- **New category codes look like breaks.** CIP, NAICS, NTEE and ECO-name lists add codes when a field grows. The placebo must drop a code's first year, or the scan will "find" every revision. Check whether CIP 43.0106 existed before CIP 2000. CSI premiered in October 2000, so if the code first appeared in that edition, the CSI test needs the 1990 predecessor code from the crosswalk.
- **Lags differ.** Names and trademarks respond within weeks. Checkouts and chess respond within a month. Degrees take 2 to 4 years. Books (Ngram) take 1 to 3 years. Each source needs its own window, set before the scan.
- **Survivorship.** The current IRS file, the NYC dog file and the Austin file hold only what survives or is active. Use NCCS history for nonprofits, and dog birth cohorts rather than license years.
- **Single-city sources** (Seattle, NYC, Austin) have no gradient. They pass rung 2 (ghosts) and stop there unless a second city replicates.

---

## Need 2. Records where institutions cite culture as a reason

| Source | URL | One row is | First year | Granularity | Siblings | Geography | Key / account | License / terms | Bulk size | Verified how | Example stone -> outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|
| UK Parliament petitions | https://petition.parliament.uk (append `.json` to a petition URL) | one petition: dates, signature count, government response, debate, signatures by constituency, country and region | 2010-2015 archive onward | daily timestamps | about 650 constituencies for the gradient | UK | none | **OGL v3** (stated on the help page) | one JSON per petition; paged listings | help page (200); one archived petition JSON (200). Fields confirmed. The 2012 petition had an empty constituency list, so the breakdown may start with the 2015 parliament. | Hypothesis: *Blue Planet II* (Dec 2017) -> plastic petitions that drew a government response, with signature rates by constituency tested against an exposure measure fixed beforehand |
| Legistar Web API (city and county councils) | https://webapi.legistar.com/Home/Examples | one matter (ordinance, resolution): title, intro date, history, votes | varies by city (mostly 2000s) | daily | n/a | each client is one city or county | none for many clients; some require a token | no terms stated; only public items are returned | 1,000 rows per page; OData `$filter` | examples page read (200) | Hypothesis: *Pokémon Go* (Jul 2016) -> Milwaukee County's 2017 permit rule for location-based games |
| LegiScan | https://legiscan.com/datasets | one bill: text, status, sponsors, votes | about 2009 to 2010 for all states (not verified) | daily actions; weekly dataset snapshots | n/a | 50 states plus Congress | free API key, login required: https://legiscan.com/legiscan (30,000 queries a month) | **CC BY 4.0** | per state-session zips; the 119th Congress JSON is 52.7 MB | web search only | Hypothesis: *13 Reasons Why* (Mar 2017) -> state bills on school suicide prevention whose findings name the series |
| GovInfo Congressional Hearings (CHRG) | https://www.govinfo.gov/help/chrg | one hearing transcript (text and PDF) | selected hearings from 1958 or earlier; dense from 1995 | hearing date | n/a | n/a | api.data.gov key (free: https://api.data.gov/signup/); DEMO_KEY allows only 30 an hour and 50 a day | public domain | about 46,000 hearings (third-party estimate) | web search only | Hypothesis: *The China Syndrome* (Mar 1979) cited in nuclear-safety hearings after Three Mile Island |
| ParlaMint 5.0 | https://www.clarin.si/repository/xmlui/handle/11356/2004 (English MT: 11356/2006) | one speech with speaker, party, date, CAP topic, sentiment | mostly 2015 to mid-2022 (some to 2024) | sitting date | CAP topics | 29 European parliaments and regions | none | CC BY 4.0 on the 4.x records; the 5.0 rights field was not shown | over 1.2 billion words | web search only | Hypothesis: *Chernobyl* (HBO, 2019) cited in 2019 nuclear-policy debates in Ukraine or Lithuania |
| NSF Awards | https://www.nsf.gov/awardsearch/download.jsp | one award: title, abstract, program, institution, dates | about 1959 to 1960 (historical bundle, no abstracts); abstracts from about 1976 | fiscal year | NSF programs | institution state | none (Awards API at api.nsf.gov needs no key) | public domain (NSF says abstracts are not copyrighted) | zipped JSON per fiscal year (JSON since Jan 2025) | web search only | Hypothesis: *The Day After Tomorrow* (2004) named in award abstracts for climate outreach 2004 to 2006 |
| PubMed / MEDLINE | https://pubmed.ncbi.nlm.nih.gov/download/ | one citation: title, abstract, MeSH terms, date | 1946 (MEDLINE) | publication date | about 30,000 MeSH descriptors (a sibling set for Need 1 too) | affiliation country | none; optional NCBI key for 10 requests a second (https://account.ncbi.nlm.nih.gov/) | NLM data is free; some abstracts are publisher copyright, so count, do not republish | annual baseline, tens of GB of XML | not probed (well documented) | Hypothesis: titles that name a show (e.g. *13 Reasons Why*) as the reason for a study; MeSH counts per year as an outcome-first scan |
| UK Charity Commission register extract | https://register-of-charities.charitycommission.gov.uk/en/register/full-register-download | one charity: registration and removal dates, objects text, classifications | registration dates go back decades (not verified) | daily extract (an NCVO guide says monthly) | classification codes; objects text | England and Wales; area of operation | none | OGL v3 according to third parties; the regulator's page returned **403** to the fetcher, so I stopped | not known | 403 (stopped); facts from search | Hypothesis: *Blue Planet II* -> new marine charities registered in 2018 whose objects text names plastic. Removed charities keep their history, so there is no survivorship bias. |
| PEN America Index of School Book Bans | https://pen.org/book-bans/ | one ban: title, district, state, date, type | school year 2021-22 | school year | about 1,500 to 4,000 titles a year | district, state | none | **no licence found; ask before reuse** | spreadsheet per year (2024-25 split into three) | web search only | Low priority. Bans react to culture but are already widely reported. |

**Notes for Need 2**

- Laws are already 87 of 102 finds. LegiScan and GovInfo add more of the same class. Rank them below sources that land on names, words, businesses, degrees and named things.
- The petition JSON is the one source here with a built-in gradient (signatures by constituency) and a built-in institutional response (the 10,000 and 100,000 thresholds).

---

## Need 3. "Named after" and "inspired by" marks

**Wikidata test.** I ran two SPARQL queries on query.wikidata.org. The first timed out with no status. The second (counts by target class) returned 200 in 23 s. Then I ran two on the QLever Wikidata mirror (qlever.dev; the old qlever.cs.uni-freiburg.de host redirects there with 308), each about 4 s. 

Items with **P138 (named after)** pointing at a direct instance of each class, with the share that carry any date (P571, P575, P577, P580 or P585):

| Target class | Items | With a date |
|---|---|---|
| fictional human | 2,112 | 891 |
| literary work | 1,406 | 816 |
| film | 549 | 398 |
| comics character | 501 | 211 |
| TV series | 175 | 126 |
| video game | 150 | 100 |
| fictional character | 64 | 28 |

What kind of thing was named (top item types, 10 target classes incl. novel, animated series, TV character): TV episodes 650, **streets 305**, **taxa 243** (plus 18 fossil taxa, e.g. *Medusaceratops lokii*), literary works 179, animated episodes 144, **asteroids 130**, bands 130, films 122, **islands 39**, **impact craters 35 plus craters 22** (e.g. Vader Crater), **businesses 29** (e.g. Falstaff Brewing), **mountains 25**, **squares 24**, **awards 77**, **movie theaters 20**. Example taxon: *Spockia*, named after Spock.

**P941 (inspired by)**: the top 30 item types hold 1,756 items, and nearly all are work-to-work (literary work 265, video game 224, film 191, characters). No place, institution or organism appears in the top 30. **Verdict: P941 is low yield for lasting marks. P138 is useful only after filtering to lasting item types**, which leaves several hundred candidates worldwide (only direct P31 classes were counted, so this is a lower bound).

| Source | URL | One row is | First year | Granularity | Siblings | Geography | Key / account | License / terms | Bulk size | Verified how | Example stone -> mark |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Wikidata P138, filtered to lasting item types | https://query.wikidata.org ; mirror https://qlever.dev/api/wikidata | one item with its named-after target | varies; 40 to 75% dated | date of naming or inception when present | item types (street, taxon, asteroid, crater, island, business, award) | coordinates for places | none | **CC0** | query results; the full dump is over 100 GB | 4 queries (see above) | Hypothesis: *Star Trek* -> the genus *Spockia*; *Star Wars* -> Vader Crater on Charon |
| JPL Small-Body Database API (asteroid naming citations) | https://ssd-api.jpl.nasa.gov/doc/sbdb.html (`discovery=1`) | one numbered asteroid: IAU naming citation text (`citation`) and its source (`cref`) | citations exist for many named asteroids; many older names lack one | citation reference date | n/a | n/a | none stated | NASA/JPL; no terms in the doc | one call per object; the SBDB Query API lists objects in bulk | doc page read (200) | Hypothesis: asteroids whose citation names a TV show or film; the citation is the "reported" evidence |
| USGS Gazetteer of Planetary Nomenclature | https://planetarynames.wr.usgs.gov | one IAU-approved feature: name, target body, type, approval date, origin | early IAU approvals (not verified) | approval date (searchable) | feature types | 50 bodies | none | USGS; no terms on the pages read (US government work is normally public domain) | shapefile and KML per body, rebuilt nightly; attribute list not confirmed | 2 pages read (200) | Hypothesis: Charon features approved in 2018 for fictional travelers (Vader, Kirk, Spock, Organa); origin text names the work |
| NCES Common Core of Data, school directory | https://nces.ed.gov/ccd/files.asp | one public school per year: name, address, district | 1986-87 | yearly | every word in school names | address, so county | none | public domain | about 100,000 schools a year, tens of MB | web search only | Hypothesis: the *Challenger* disaster (Jan 1986) -> schools named after Christa McAuliffe first appearing 1987 to 1995, ranked against all name words' first appearances |
| Wiktionary via kaikki.org (wiktextract) | https://kaikki.org | one word sense with etymology text and expanded templates | undated; pair with Ngram for dating | n/a | about a million English entries (not counted) | n/a | none | Wiktionary is CC BY-SA and GFDL; kaikki's own notice not checked | several GB of JSONL | web search only | Hypothesis: words whose etymology cites a film or novel (paparazzi, catch-22, Stepford, Pollyanna, grinch), then dated and measured in Ngram |
| NCCS / IRS names, UK charity objects, USPTO marks | see Need 1 and 2 rows | organization or mark names containing a character or title | as above | as above | as above | as above | as above | as above | as above | as above | Hypothesis: nonprofits or charities whose names or objects cite a documentary, founded the year after it aired |

Not probed, worth one look later: OpenStreetMap `name:etymology:wikidata` tags (ODbL, share-alike on the database) for street naming beyond Wikidata's 305 streets; USGS GNIS and Board on Geographic Names decisions for US place renamings, the class Truth or Consequences belongs to.

---

## Need 4. Exposure and the culture calendar

| Source | URL | One row is | First year | Granularity | Siblings | Geography | Key / account | License / terms | Bulk size | Verified how | Use |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Wikimedia pageviews by country (differentially private) | https://analytics.wikimedia.org/published/datasets/country_project_page/00_README.html | page x country x day: noisy pageviews, with Wikidata QID | **2015-07-01** in three releases (to 2017-02-08, 2017-02-09 to 2023-02-05, 2023-02-06 on) | daily | every article above thresholds | country (high-risk countries excluded) | none | not stated in the README; Wikimedia pageview data is normally CC0 | one CSV per day | README read (200) | Exposure by country for any stone with a Wikipedia article, fixed before the outcome. Rows publish only above 90, 550 or 1,000 views by risk tier, so small countries are noisy. Hypothesis: countries with more per-capita views of *The Queen's Gambit* article in Oct to Nov 2020 had larger rises in new female FIDE players. |
| TVmaze API | https://www.tvmaze.com/api | show and episode: air date, network, network country, web channel | many older shows (coverage not measured) | episode air date | n/a | network country; daily schedule by country (past dates work) | none | **CC BY-SA 4.0** (credit TVmaze, share-alike) | crawl `/shows?page=N` (250 per page); 20 calls per 10 s | doc page read (200) | Dates single episodes, e.g. the night an episode about organ donation aired |
| Netflix "What We Watched" engagement reports | https://about.netflix.com/en/news/what-we-watched-a-netflix-engagement-report | title x half-year: hours viewed, views, premiere date, global availability | H1 2023 (to H1 2026; yearly from 2027) | half-year | about 18,000 titles per report | global only | none | Netflix site content; no reuse terms found | one Excel file per report | web search only | Reach for ghost matching among streaming titles |
| Wikidata release dates and box office | https://query.wikidata.org | film: P577 publication date with a P291 place qualifier; P2142 box office | early cinema | day | n/a | country of release | none | CC0 | query results | not probed separately | **Staggered releases are a natural experiment.** A film out in the US months before the UK gives a dated, two-country test. |
| MusicBrainz | https://musicbrainz.org/doc/MusicBrainz_Database | release with date and country | early recordings | day | n/a | release country | none | core data CC0 | dumps of several GB | not probed | Dates songs and albums by country |
| IMDb non-commercial datasets | https://data.imdb.com/non-commercial-datasets/ | title basics, alternate titles by region, ratings with vote counts, episodes | early cinema | daily refresh | n/a | `title.akas` region | none | **personal and non-commercial use only** | several GB | page read (301 to data.imdb.com, 200) | **Flagged.** Ripple is public and tied to a professional portfolio. Use Wikidata instead unless the owner rules otherwise. |
| LUMIERE (European Audiovisual Observatory) | https://lumiere.obs.coe.int | film x market x year: cinema admissions | 1996 | yearly | 92,000 works | 36 European markets | none | free to consult; no bulk route; the site says it is not a ranking tool; searches by producing country are capped at 200 | none | web search only | Manual lookups for a few stones only. **No scraping.** |
| BFI weekend box office | https://www.bfi.org.uk/industry-data-insights/weekend-box-office-figures | film x weekend: UK gross | 2008 or earlier in the listing | weekly | top 15 plus new releases | UK | none | **site terms: personal, non-commercial use; reuse needs BFI authorization** | PDF or XLS per weekend | web search only | **Out** unless the BFI grants permission |
| Box Office Mojo, The Numbers | n/a | n/a | n/a | n/a | n/a | n/a | n/a | **Out.** IMDb's conditions of use forbid data mining (Box Office Mojo is IMDb's); The Numbers sells its data. | n/a | prior knowledge | Use Wikidata P2142 or LUMIERE lookups |

---

## Ranked shortlist: expected surprising-and-defensible finds per day of work

The ranking favors sources that land outside law. Law is already 87 of 102 finds. "Days" means one fetcher, a dry run, and a methods note.

1. **INSEE prénoms, plus SSB, NRS and ONS** (0.5 to 1 day; needs the owner's ruling first: names ripples are capped at two in the product, Oct 5). The baby-name method already works. France adds 125 years and about 100 departments for an exposure gradient, so European stones become testable.
2. **Wikidata P138 filtered to lasting types, plus JPL citations and USGS planetary names** (1 day). These are named marks where the naming body's own citation names the work: "reported" evidence that is easy to defend and often surprising (*Spockia*, Vader Crater).
3. **Google Books Ngram with Wiktionary etymologies** (2 days). "A film put a word into English", tested against every word's break. This reaches 1900 to 2019 culture, which nothing else on the list covers.
4. **Census County Business Patterns** (2 days). Place-based stones (a show set in a town) ranked against 3,100 sibling counties, landing on jobs and businesses, which are lasting marks.
5. **USPTO Trademark Case Files** (1.5 days). Viral phrases turn into filings within weeks. Daily dates, every word as a sibling, owner state for a gradient.
6. **Lichess explorer `history=true`** (1 day once a token exists). It tests The Queen's Gambit cleanly against every sibling opening, and meme openings (Bongcloud, Botez Gambit) give more stones.
7. **Seattle Public Library checkouts by subject** (1 day). Monthly from 2005, public domain, no key. It catches spillover to subjects next to the stone. It is a single city, and a reading spike may not count as lasting.
8. **NCCS Unified BMF** (1.5 days). Nonprofits founded by NTEE code and by name since 1989: "this documentary started institutions." No survivorship bias.

Next tier: IPEDS (3 days because of CIP revisions; best lasting-mark class, but slow lags and new-code artifacts), UK petitions (1 day; institutional response plus a constituency gradient), Wikimedia per-country pageviews (1 day; an enabler for rung 3 rather than a finder), FIDE lists, NYC dog licensing, OpenAlex, RePORTER, OEWS. Set aside: USFWS licenses (state x year, only two categories, and labeled by apportionment year, which lags the license year), FAA airmen statistics and OPTN (few siblings), AKC (ranks only, no counts), Austin intakes for GoT (no pre-period), BFI and Box Office Mojo (terms).

---

## Things only the owner can do

**Keys and accounts (free; nothing was created)**
- Lichess account and personal API token for the explorer: https://lichess.org/account/oauth/token (no scopes needed). Without it, stream partial PGN files instead.
- LegiScan API key (log in first): https://legiscan.com/legiscan
- api.data.gov key for GovInfo, if the existing Congress.gov key is not already one: https://api.data.gov/signup/
- Optional: OpenAlex key (https://openalex.org/settings/api), NCBI key (https://account.ncbi.nlm.nih.gov/), Census API key (https://api.census.gov/data/key_signup.html), RIDB API key (https://ridb.recreation.gov).

**Downloads blocked to the fetcher or behind a person**
- UK Charity Commission extract returned 403. Download it in a browser and confirm the licence statement.
- MLA enrollment database: confirm whether a bulk download exists.

**Permission requests (each one is a message he sends)**
- BFI (weekend box office reuse), the European Audiovisual Observatory (LUMIERE bulk), PEN America (index licence), the Kennel Club (registrations before 2015), FIDE (bulk use of rating lists).

**Rulings: which marks count as lasting**
- A word entered the language (Ngram break plus an etymology that names the work).
- A species, asteroid, crater, street or business was named after a work or character.
- A field's degrees jumped (and for how many years it must stay up).
- Trademark filings spiked (filings, or only registrations that issued?).
- Nonprofits or charities were founded (and whether they must survive N years).
- A petition passed 10,000 or 100,000 signatures and drew a response or debate.
- A town or place was renamed (the Truth or Consequences class).
- An opening's share in online chess rose and stayed up 12 months later.
- A reading spike in library checkouts (or only a level still higher a year later).
- Whether Ripple counts as "non-commercial" for IMDb data (recommendation: avoid IMDb, use Wikidata).
- Whether figures derived from Netflix's engagement reports may be shown (no reuse terms found).

**One fact to settle before the CSI test**
- Whether CIP 43.0106 (forensic science) existed before CIP 2000. Use the NCES new-codes index or the 1990 to 2000 crosswalk.

---

## Probe log

| Host | Requests | Status |
|---|---|---|
| database.lichess.org | 1 (page read in three slices from cache) | 200 |
| lichess.org | 1 (API docs) | 200, JS shell, no content |
| github.com | 1 (lila-openingexplorer README) | 200 |
| raw.githubusercontent.com | 1 (explorer API spec) | 200 |
| www.irs.gov | 2 | 200; then 404 on the info sheet, stopped |
| www.census.gov | 1 | 200 |
| nces.ed.gov | 1 | 200 |
| nccs.urban.org | 1 | 200 |
| docs.openalex.org, help.openalex.org | 1 each | 301, then 200 |
| reporter.nih.gov | 1 | 200, JS shell |
| www.uspto.gov | 1 | 200 |
| storage.googleapis.com | 1 | 200 |
| data.seattle.gov | 1 (metadata) | 200 |
| www.insee.fr | 1 | 200 |
| query.wikidata.org | 2 | timeout (no status), then 200 |
| qlever.cs.uni-freiburg.de | 2 | 308 redirect to qlever.dev |
| qlever.dev | 2 | 200, 200 |
| data.cityofnewyork.us | 1 (metadata) | 200 |
| data.austintexas.gov | 1 (metadata) | 200 |
| dogsaustralia.org.au | 1 | 404, stopped |
| petition.parliament.uk | 2 | 200, 200 |
| webapi.legistar.com | 1 | 200 |
| register-of-charities.charitycommission.gov.uk | 1 | 403, stopped |
| planetarynames.wr.usgs.gov | 2 | 200, 200 |
| ssd-api.jpl.nasa.gov | 1 | 200 |
| analytics.wikimedia.org | 1 | 200 |
| www.tvmaze.com | 1 | 200 |
| developer.imdb.com, data.imdb.com | 1 each | 301, then 200 |
| example.com | 1 (network check) | 200 |

All other facts come from web search results. Those rows say "web search only" and should be confirmed by a doc read before any fetcher is written.
