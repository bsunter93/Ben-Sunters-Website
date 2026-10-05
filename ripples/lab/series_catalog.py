"""Series catalog v1: behavior outcome series that are public, aggregate and reachable with no key and no account, with
the statistical power each can give a measured grade. Built under the rule registered in ripples/docs/measure_plan_v1.md
section 3. Output: ripples/docs/results/series_catalog_v1.json (the .md beside it is written by hand from this file).

Power: an outcome window is tested against the windows of the same shape in the series' own history before the stone, so
the smallest p a series can give is 1 / (1 + N), N = admissible placebo windows. N here is counted for a stone in 2015
with the shortest window each frequency allows (annual: a one-year change; monthly: a one-month year-over-year change;
quarterly: one quarter against the same quarter a year earlier; daily: one week), minus the excluded periods (Sep 15,
2008 to Jun 30, 2009; Feb 15, 2020 to Jun 30, 2021, which lie after 2015). Overlapping windows are not independent, so N
is an upper bound on the information; the floor is the hard limit. Geography adds power a different way: it is what the
exposure gradient (test v2 rung iii) needs, and each unit is its own series.

Probe: one request per host to a landing or documentation page (never an outcome value), honest UA, 1.1 s apart, a host
stopped on any 4xx or 5xx. Hosts already called by measure_v1.py today take their status from that run instead.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "docs", "results", "series_catalog_v1.json")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
STONE_YEAR = 2015
EXCL_MONTHS = 10  # Sep 2008 to Jun 2009
EXCL_YEARS = 2    # 2008 and 2009 touch the crisis
USED_IDS = {"cdc_wonder_ucd", "nps_visits", "ssb_hotel_nights", "defra_family_food"}  # queried by measure_v1.py

# id, name, publisher, frequency (A/Q/M/W/D), start year, geography, units, unit, access URL, probe URL, key/account, terms, kind
CATALOG = [
    ("cdc_wonder_ucd", "Underlying cause of death 1999-2020 (D76), by month of death", "CDC NCHS via CDC WONDER", "M", 1999,
     "national through the API (state and county only in the web tool)", 1, "deaths", "https://wonder.cdc.gov/controller/datarequest/D76",
     "https://wonder.cdc.gov/wonder/help/wonder-api.html", "no key, no account; the API requires accepting the data use restrictions (owner accepted Oct 5, 2026)",
     "statistical reporting only; never present 9 or fewer deaths; no attempt to identify anyone; one query at a time, about 2 minutes apart", "health"),
    ("cdc_wonder_ucd_2018", "Underlying cause of death 2018 onward, single race (D158) and provisional (D176)", "CDC NCHS via CDC WONDER", "M", 2018,
     "national through the API", 1, "deaths", "https://wonder.cdc.gov/controller/datarequest/D158", None,
     "as D76", "as D76; extends the D76 months past 2020", "health"),
    ("cdc_wonder_natality", "Natality (D10 1995-2002, D27 2003-2006, D66 2007 onward), births by month", "CDC NCHS via CDC WONDER", "M", 1995,
     "national through the API", 1, "births", "https://wonder.cdc.gov/controller/datarequest/D66", None,
     "as D76", "as D76 (never present 9 or fewer births)", "health"),
    ("nps_visits", "Visitor use statistics: recreation visits by park unit", "National Park Service", "M", 1979,
     "park unit (about 420 units; annual totals from 1904 for the oldest parks)", 420, "recreation visits",
     "https://irmaservices.nps.gov/v3/rest/stats/visitation?unitCodes=YELL&startMonth=1&startYear=1979&endMonth=12&endYear=2024",
     "https://irmaservices.nps.gov/v3/rest/Stats/help", "no key, no account", "public domain; counting methods change by unit and are footnoted", "travel"),
    ("ssa_names_national", "Baby names from Social Security card applications, national", "Social Security Administration", "A", 1880,
     "national", 1, "births given a name (names with 5 or more)", "https://www.ssa.gov/oact/babynames/names.zip",
     "https://www.ssa.gov/oact/babynames/limits.html", "no key, no account", "public; names under 5 in a year are not listed", "naming"),
    ("ssa_names_state", "Baby names from Social Security card applications, by state", "Social Security Administration", "A", 1910,
     "state (50 and DC)", 51, "births given a name (names with 5 or more per state)", "https://www.ssa.gov/oact/babynames/state/namesbystate.zip",
     None, "no key, no account", "public", "naming"),
    ("bls_ces_state", "Current Employment Statistics, state and metro jobs by industry", "Bureau of Labor Statistics", "M", 1990,
     "state and metro area", 450, "jobs (thousands)", "https://api.bls.gov/publicAPI/v1/timeseries/data/SMU06000007072100001",
     "https://www.bls.gov/developers/api_faqs.htm", "no key for the v1 API (25 queries a day, 10 years each)", "public domain", "work"),
    ("bls_qcew", "Quarterly Census of Employment and Wages, county by industry", "Bureau of Labor Statistics", "Q", 1990,
     "county (about 3,200)", 3200, "establishments, jobs, wages", "https://data.bls.gov/cew/data/api/2015/1/area/30067.csv",
     "https://www.bls.gov/cew/additional-resources/open-data/csv-data-slices.htm", "no key, no account", "public domain; small cells suppressed", "work"),
    ("census_mrts", "Monthly retail trade sales by kind of business", "Census Bureau", "M", 1992,
     "national", 1, "US dollars", "https://api.census.gov/data/timeseries/eits/mrts", "https://www.census.gov/data/developers/data-sets/economic-indicators.html",
     "no key up to 500 queries a day", "public domain; also mirrored on FRED", "spending"),
    ("census_cbp", "County Business Patterns: establishments and jobs by industry", "Census Bureau", "A", 1986,
     "county", 3200, "establishments, jobs", "https://api.census.gov/data/2015/cbp", None, "no key up to 500 queries a day",
     "public domain; noise infusion in recent years", "work"),
    ("ipeds_completions", "IPEDS completions by field of study (CIP)", "NCES", "A", 1984,
     "institution (aggregates to state)", 7000, "degrees and certificates awarded", "https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx",
     "https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx", "no key, no account (bulk files)", "public domain; CIP codes change in 1990, 2000, 2010, 2020", "education"),
    ("nhtsa_fars", "Fatality Analysis Reporting System: fatal crashes", "NHTSA", "M", 1975,
     "state and county", 51, "fatal crashes and deaths (aggregated by us from case records)", "https://crashviewer.nhtsa.dot.gov/CrashAPI",
     "https://crashviewer.nhtsa.dot.gov/CrashAPI", "no key, no account", "public; case-level records, so only aggregates are kept", "safety"),
    ("fbi_cde", "Crime Data Explorer: offenses by agency and state", "FBI", "M", 1985,
     "state and agency", 51, "reported offenses", "https://api.usa.gov/crime/fbi/cde/", None,
     "needs an api.data.gov key: excluded under the no-key rule", "public; agency coverage changes with the NIBRS transition", "safety"),
    ("fbi_nics", "NICS firearm background checks by state", "FBI", "M", 1998,
     "state", 51, "background checks (a proxy for sales, not sales)", "https://www.fbi.gov/file-repository/nics_firearm_checks_-_month_year_by_state.pdf/view",
     "https://www.fbi.gov/how-we-can-help-you/more-fbi-services-and-information/nics", "no key, no account (a PDF table)", "public; permit rechecks inflate some states", "safety"),
    ("books_ngram", "Google Books Ngram: term frequency by year", "Google Books", "A", 1800,
     "language corpus", 8, "share of all words that year", "http://storage.googleapis.com/books/ngrams/books/20200217/eng/",
     "https://books.google.com/ngrams/info", "no key, no account (bulk files)", "culture and attention, not behavior; corpus composition shifts", "attention"),
    ("wikipedia_pageviews", "Wikipedia pageviews by article and language edition", "Wikimedia", "D", 2015,
     "language edition (a country-exposure proxy where a language maps to a country)", 300, "pageviews",
     "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/{project}/all-access/user/{article}/daily/{start}/{end}",
     "https://wikimedia.org/api/rest_v1/", "no key, no account", "attention, never a behavior grade; used only as an exposure measure", "attention"),
    ("ssb_hotel_nights", "Hotels: guest nights by county and guests' country of residence (table 08402)", "Statistics Norway", "M", 1985,
     "county by residence country", 19, "guest nights", "https://data.ssb.no/api/v0/en/table/08402", None, "no key, no account", "open (NLOD)", "travel"),
    ("defra_family_food", "Family Food: household purchases per person per week", "Defra (UK)", "A", 1974,
     "UK (regions as three-year averages)", 1, "grams or ml per person per week", "https://www.gov.uk/government/statistical-data-sets/family-food-datasets", None,
     "no key, no account", "Open Government Licence; survey breaks in 2001-02, 2006 and 2015-16", "spending"),
    ("ons_baby_names", "Baby names in England and Wales", "Office for National Statistics", "A", 1996,
     "England and Wales, with regions", 10, "births given a name (3 or more)", "https://www.ons.gov.uk/peoplepopulationandcommunity/birthsdeathsandmarriages/livebirths/datasets/babynamesenglandandwalesbabynamesstatisticsgirls",
     "https://www.ons.gov.uk/peoplepopulationandcommunity/birthsdeathsandmarriages/livebirths", "no key, no account", "Open Government Licence", "naming"),
    ("insee_prenoms", "Fichier des prenoms: first names given in France", "INSEE", "A", 1900,
     "departement (about 100)", 100, "births given a name (3 or more)", "https://www.insee.fr/fr/statistiques/2540004",
     "https://www.insee.fr/fr/statistiques/2540004", "no key, no account", "open licence; rare names pooled", "naming"),
    ("fhwa_tvt", "Traffic Volume Trends: vehicle miles traveled", "FHWA", "M", 1970,
     "national from 1970 (FRED TRFVOLUSM227NFWA); states in the monthly reports (archive years not verified in this pass)", 1, "vehicle miles", "https://www.fhwa.dot.gov/policyinformation/travel_monitoring/tvt.cfm",
     "https://www.fhwa.dot.gov/policyinformation/travel_monitoring/tvt.cfm", "no key, no account (monthly reports; national series on FRED)", "public domain", "travel"),
    ("bts_t100", "T-100 segment data: air passengers by airport and route", "Bureau of Transportation Statistics", "M", 1990,
     "airport", 400, "passengers", "https://www.transtats.bts.gov/Tables.asp?QO_VQ=EEE", "https://www.transtats.bts.gov/",
     "no key, no account (download form)", "public domain", "travel"),
    ("cdc_brfss", "BRFSS prevalence data by state", "CDC", "A", 2011,
     "state", 54, "share of adults", "https://data.cdc.gov/resource/dttw-5yxu.json", "https://data.cdc.gov/", "no key (Socrata, throttled without a token)",
     "public; method change in 2011 (no comparison with earlier years)", "health"),
    ("cdc_yrbs", "Youth Risk Behavior Survey, high school, by state", "CDC", "A", 1991,
     "state (biennial; not every state every wave)", 46, "share of students", "https://chronicdata.cdc.gov/resource/q6p7-56au.json", None,
     "no key (Socrata)", "public; biennial, so N counts survey waves", "health"),
    ("usfws_licenses", "Hunting and fishing license certifications by state", "US Fish and Wildlife Service", "A", 1958,
     "state", 50, "paid license holders", "https://www.fws.gov/wsfrprograms/Subpages/LicenseInfo/LicenseIndex.htm", None,
     "no key, no account (yearly tables)", "public domain", "recreation"),
    ("ntto_i94", "International arrivals to the US by country of residence (I-94)", "National Travel and Tourism Office", "M", 2000,
     "country of residence", 90, "arrivals", "https://www.trade.gov/i-94-arrivals-program", "https://www.trade.gov/i-94-arrivals-program",
     "no key, no account (monthly workbooks)", "public domain", "travel"),
    ("neiss", "National Electronic Injury Surveillance System: injury estimates by product", "CPSC", "A", 1997,
     "national (a probability sample of hospitals)", 1, "weighted emergency visits", "https://www.cpsc.gov/Research--Statistics/NEISS-Injury-Data",
     "https://www.cpsc.gov/Research--Statistics/NEISS-Injury-Data", "no key, no account", "public; case-level sample file, so only weighted aggregates are kept", "safety"),
    ("fred", "FRED: economic series, many by state (fredgraph.csv)", "Federal Reserve Bank of St. Louis", "M", 1947,
     "national and state (series by series)", 51, "varies", "https://fred.stlouisfed.org/graph/fredgraph.csv?id=TRFVOLUSM227NFWA", None,
     "no key for fredgraph.csv", "mirrors many of the sources above; check each series' source terms", "platform"),
]


def windows(freq, start):
    years = STONE_YEAR - start
    if years <= 1:
        return 0
    if freq == "A":
        return max(0, years - 1 - EXCL_YEARS)
    if freq == "Q":
        return max(0, years * 4 - 4 - 4)
    if freq == "M":
        return max(0, years * 12 - 12 - EXCL_MONTHS - 12)
    if freq == "W":
        return max(0, years * 52 - 52)
    if freq == "D":
        return max(0, (years * 365 - 7) // 7)
    return 0


def probe(url, stopped):
    host = urllib.parse.urlparse(url).netloc
    if host in stopped:
        return f"not probed: {host} stopped earlier today ({stopped[host]})"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            code = r.status
    except urllib.error.HTTPError as e:
        code = e.code
        stopped[host] = f"HTTP {code}"
    except Exception as e:  # noqa: BLE001
        code = f"error: {str(e)[:60]}"
    finally:
        time.sleep(1.1)
    return code


def main() -> int:
    stopped = {x.split("|")[0]: x.split("|")[1] for x in os.environ.get("LADDER_SKIP_HOSTS", "").split(",") if "|" in x}
    used = {}
    mpath = os.path.join(ROOT, "docs", "results", "measure_v1.json")
    if os.path.exists(mpath):
        for r in json.load(open(mpath)).get("requests", []):
            used.setdefault(urllib.parse.urlparse(r["url"]).netloc, r["status"])
    cached = json.load(open(os.environ["PROBE_STATUS_FILE"])) if os.environ.get("PROBE_STATUS_FILE") else {}
    rows = []
    for (cid, name, pub, freq, start, geo, units, unit, url, purl, access, terms, kind) in CATALOG:
        n = windows(freq, start)
        host = urllib.parse.urlparse(url).netloc
        if cid in cached:
            status = cached[cid]
        elif host in used:
            status = f"host called by measure_v1.py today: HTTP {used[host]}" + ("" if cid in USED_IDS else " (this database or file was not queried)")
        elif host in stopped:
            status = f"not probed: {host} stopped earlier today ({stopped[host]})"
        elif "key: excluded" in access:
            status = "not probed: needs a key"
        elif purl:
            status = probe(purl, stopped)
            status = f"HTTP {status}" if isinstance(status, int) else status
        else:
            status = "not probed (no landing page registered for a probe)"
        rows.append({"id": cid, "name": name, "publisher": pub, "frequency": {"A": "annual", "Q": "quarterly", "M": "monthly", "W": "weekly", "D": "daily"}[freq],
                     "start_year": start, "geography": geo, "geographic_units": units, "unit": unit, "access_url": url, "access": access,
                     "terms": terms, "kind": kind, "behavior": kind not in ("attention", "platform"), "eligible": "key: excluded" not in access,
                     "power": {"placebo_windows_before_a_2015_stone": n, "p_floor": round(1 / (1 + n), 4) if n else None,
                               "note": ("annual national: with N admissible years the smallest p is 1/(N+1)" if freq == "A" else
                                        "short windows overlap, so N is an upper bound on independent information")},
                     "probe": status})
    elig = [r for r in rows if r["eligible"] and r["behavior"]]
    ranked = sorted(elig, key=lambda r: (-(r["geographic_units"] >= 10), r["power"]["p_floor"] or 1, -r["geographic_units"]))
    out = {"protocol": "ripples/docs/measure_plan_v1.md section 3", "built": dt.date.today().isoformat(), "user_agent": UA,
           "rule": "public, aggregate, reachable with no key and no account; behavior (not attention) unless marked; power counted for a 2015 stone",
           "n": len(rows), "n_eligible_behavior": len(elig), "ranked_by_power": [r["id"] for r in ranked], "series": rows}
    json.dump(out, open(OUT, "w"), indent=1, ensure_ascii=False)
    for r in ranked:
        print(f"{r['id']:22s} {r['frequency']:9s} {r['start_year']} units={r['geographic_units']:5d} N={r['power']['placebo_windows_before_a_2015_stone']:5d} floor={r['power']['p_floor']} {r['probe']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
