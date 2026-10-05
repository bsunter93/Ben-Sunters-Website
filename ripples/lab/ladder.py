"""Evidence ladder v1: climb the engine's marks from reported to timed or measured, where the mark's own outcome has a
series. Pre-registered in ripples/docs/ladder_plan_v1.md before any outcome value was fetched.

For every mark in ripples/demo/discovered_wiki.json, SPECIAL and RECORD_KINDS below say whether a series that measures the mark's
own outcome exists and is reachable, and why not when it is not. Each testable mark gets:
  1. the placebo-date test: the change over the outcome window (mean of the next h periods minus mean of the previous h
     periods, in logs) against every window of the same length in the series' own history before the stone; empirical
     p = (1 + placebo effects at least as large) / (1 + N). Windows that touch an excluded period (the 2008-09
     financial crisis, the 2020-21 closure months) or span a definition break are dropped.
  2. the ordering rule: onset = the first period, searched from 2h before the reference, where the series departs from
     its pre-trend by more than 2 SDs for 2 periods running (onset() gives the monthly and annual forms). A rise that
     began before the stone is busted.
  3. the comparison rung (counterfactual catalysts): the same change after matched control stones from the repo's
     culture list (same kind, release year within 10 years, no link to the outcome); reported beside the grade.
  4. an exposure gradient where the same table carries one (Frozen: the western fjord counties against the rest).
  5. decoys: the same test run with the mark's series and a wrong engine stone's date.
Grade map: measured if p <= .05 and in order; timed if in order only (an onset inside the outcome window, the change
in the claimed direction); busted if the rise began before the stone; otherwise the mark stays reported and the
result joins the negative-space list.
Honest UA, at least 1 s between requests, a host is stopped for the run on any 4xx or 5xx, no retries, no keys.
Output: ripples/docs/results/ladder_v1.json.
"""
from __future__ import annotations

import datetime as dt
import io
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
WIKI = os.path.join(ROOT, "demo", "discovered_wiki.json")
OUT = os.path.join(ROOT, "docs", "results", "ladder_v1.json")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
D = dt.date.fromisoformat

# ---------- network: honest UA, spacing, stop a host on any refusal ----------
STOPPED: dict = {}
REQUESTS: list = []


def fetch(url, data=None, headers=None, delay=1.1):
    host = urllib.parse.urlparse(url).netloc
    if host in STOPPED:
        return None
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, **(headers or {})})
    code, body = None, None
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            code, body = r.status, r.read()
    except urllib.error.HTTPError as e:
        code = e.code
        STOPPED[host] = f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001
        code = f"error: {str(e)[:80]}"
    finally:
        REQUESTS.append({"url": url[:240], "status": code, "at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")})
        print(code, url[:160], flush=True)
        time.sleep(delay)
    return body


# ---------- periods ----------
EXCLUDED = [(D("2008-09-15"), D("2009-06-30"), "2008-09 financial crisis"), (D("2020-02-15"), D("2021-06-30"), "pandemic closure months")]


def month_excluded(d):
    end = (d.replace(day=28) + dt.timedelta(days=4)).replace(day=1) - dt.timedelta(days=1)
    return any(not (end < a or d > b) for a, b, _ in EXCLUDED)


def year_excluded(y, fiscal=False):
    a, b = (D(f"{y}-04-01"), D(f"{y + 1}-03-31")) if fiscal else (D(f"{y}-01-01"), D(f"{y}-12-31"))
    return any(not (b < x or a > z) for x, z, _ in EXCLUDED)


class Series:
    """dates (first day of each period), values, an excluded flag per period, breaks (index b: the change from b-1 to b
    is not comparable), period length in days, and whether to fit month-of-year terms."""

    def __init__(self, dates, values, excluded, breaks=(), period_days=31, seasonal=False, labels=None, fit_breaks=None):
        self.dates, self.values = list(dates), np.array(values, dtype=float)
        self.excluded, self.breaks = np.array(excluded, dtype=bool), set(breaks)
        self.fit_breaks = set(breaks if fit_breaks is None else fit_breaks)  # breaks a pre-trend fit may not reach back across
        self.period_days, self.seasonal = period_days, seasonal
        self.labels = labels or [d.isoformat() for d in self.dates]
        self.y = np.log(np.where(self.values > 0, self.values, np.nan))

    def index_of(self, d):
        """the period that contains date d (for an annual series, the period labeled with d's year, or None)"""
        if self.period_days >= 300:
            return next((i for i, x in enumerate(self.dates) if x.year == d.year), None)
        return max((i for i, x in enumerate(self.dates) if x <= d), default=None)


def window_ok(s, i, h):
    if i - h < 0 or i + h > len(s.y):
        return False
    if s.excluded[i - h:i + h].any() or np.isnan(s.y[i - h:i + h]).any():
        return False
    return not any(i - h < b <= i + h - 1 for b in s.breaks)


def eff(s, i, h):
    return float(s.y[i:i + h].mean() - s.y[i - h:i].mean()) if window_ok(s, i, h) else None


def placebo_test(s, r, stone_i, h, direction):
    """the change at reference period r against every admissible window that ends before the stone's period"""
    sign = 1 if direction == "up" else -1
    obs = eff(s, r, h)
    if obs is None:
        return {"result": "the outcome window touches an excluded period, a break or missing data"}
    pool = [e for e in (eff(s, i, h) for i in range(h, len(s.y) - h + 1) if i + h <= stone_i and abs(i - r) > 2 * h) if e is not None]
    n = len(pool)
    p = (1 + sum(1 for x in pool if sign * x >= sign * obs)) / (1 + n) if n else None
    return {"effect": round(obs, 4), "p": round(p, 4) if p is not None else None, "n_placebo": n,
            "p_floor": round(1 / (1 + n), 4) if n else None}


def onset(s, r, h, direction):
    """The ordering rule's onset, adapted from chain_check for 12-month windows (calibrated on synthetic noise only, before
    any outcome value was read; ladder_plan_v1.md section 4):
      monthly: z = the year-over-year log change; baseline = mean and SD of z over the 48 admissible months before the
               search starts; onset = the first month, from 2h before the reference, where z exceeds the baseline mean by
               more than 2 SDs (in the claimed direction) for 2 admissible months running.
      annual:  chain_check's rule (log level against a linear pre-trend, 2 residual SDs, 2 periods running) with the trend
               fitted on the 10 admissible years before the search starts (not 4), never reaching back across a survey
               break.
    The search runs to 3h after the reference, as in chain_check."""
    sign = 1 if direction == "up" else -1
    a = r - 2 * h
    run, thr = 2, 2.0
    stop = min(len(s.y) - run + 1, r + 3 * h)
    if s.period_days < 300:
        lag = 12
        z = np.full(len(s.y), np.nan)
        for i in range(lag, len(s.y)):
            if not s.excluded[i] and not s.excluded[i - lag]:
                z[i] = s.y[i] - s.y[i - lag]
        base = [i for i in range(0, a) if np.isfinite(z[i])][-48:]
        if len(base) < 24:
            return {"onset": None, "onset_note": "too few admissible months for the baseline"}
        mu, sd = float(np.mean(z[base])), float(np.std(z[base])) or 1e-9
        dev = sign * (z - mu) / sd
        fit_lab = [s.labels[base[0]], s.labels[base[-1]]]
    else:
        floor = max([b for b in s.fit_breaks if b <= a] or [0])
        fit = [i for i in range(floor, a) if not s.excluded[i] and np.isfinite(s.y[i])][-10:]
        if len(fit) < 5:
            return {"onset": None, "onset_note": "too few admissible years to fit the pre-trend"}
        coef = np.polyfit(fit, s.y[fit], 1)
        sd = float(np.std(s.y[fit] - np.polyval(coef, fit))) or 1e-9
        dev = sign * (s.y - np.polyval(coef, np.arange(len(s.y)))) / sd
        fit_lab = [s.labels[fit[0]], s.labels[fit[-1]]]
    for i in range(max(a, 0), stop):
        if all((not s.excluded[j]) and np.isfinite(dev[j]) and dev[j] > thr for j in range(i, i + run)):
            return {"onset": s.dates[i].isoformat(), "onset_label": s.labels[i], "fit_periods": fit_lab}
    return {"onset": None, "fit_periods": fit_lab}


def grade(res, stone, s, r, h, direction):
    """measured / timed / busted / reported (no movement), by the registered map"""
    if res.get("effect") is None:
        return "reported", "not run: " + res.get("result", "no effect")
    sign = 1 if direction == "up" else -1
    pos = sign * res["effect"] > 0
    tol = dt.timedelta(days=max(3, s.period_days))
    on = D(res["onset"]) if res.get("onset") else None
    end = s.dates[min(r + h - 1, len(s.dates) - 1)]
    if pos and on and on < stone - tol:
        return "busted", "the rise began before the stone"
    if pos and res.get("p") is not None and res["p"] <= 0.05:
        return "measured", "unusual against the series' own history, in order"
    if pos and on and stone - tol <= on <= end:
        return "timed", "a departure began inside the outcome window, in order, but the change was not unusual enough"
    return "reported", "no movement: the change was not unusual and no departure began in the window"


def run_test(s, stone, ref_date, h, direction):
    stone_i, r = s.index_of(stone), s.index_of(ref_date)
    if stone_i is None or r is None:
        return {"result": "the series does not cover the stone"}, "reported", "not run: no coverage"
    res = placebo_test(s, r, stone_i, h, direction)
    if res.get("effect") is not None:
        res.update(onset(s, r, h, direction))
    g, why = grade(res, stone, s, r, h, direction)
    res["window"] = {"before": [s.labels[max(r - h, 0)], s.labels[r - 1]], "after": [s.labels[r], s.labels[min(r + h - 1, len(s.labels) - 1)]]}
    return res, g, why


# ---------- sources ----------
SSB_URL = "https://data.ssb.no/api/v0/en/table/08402"


def ssb_08402():
    """Norway, hotels: guest nights by region and guests' country of residence, monthly 1985-2019 (json-stat2)"""
    q = {"query": [{"code": "Region", "selection": {"filter": "item", "values": ["0", "12", "14", "15"]}},
                   {"code": "Landkoder2", "selection": {"filter": "item", "values": ["00000", "ccc"]}},
                   {"code": "ContentsCode", "selection": {"filter": "item", "values": ["Overnattinger"]}}],
         "response": {"format": "json-stat2"}}
    body = fetch(SSB_URL, data=json.dumps(q).encode(), headers={"Content-Type": "application/json"})
    if not body:
        return None
    js = json.loads(body)
    ids, size, val = js["id"], js["size"], js["value"]
    cats = {d: js["dimension"][d]["category"]["index"] for d in ids}
    pos = {d: (sorted(cats[d], key=cats[d].get) if isinstance(cats[d], dict) else cats[d]) for d in ids}
    strides = [int(np.prod(size[k + 1:])) for k in range(len(ids))]
    out = {}
    for flat, v in enumerate(val):
        key, rem = {}, flat
        for k, d in enumerate(ids):
            key[d], rem = pos[d][rem // strides[k]], rem % strides[k]
        out[(key["Region"], key["Landkoder2"], key["Tid"])] = v
    months = sorted({k[2] for k in out})
    return out, months


DEFRA_PAGE = "https://www.gov.uk/government/statistical-data-sets/family-food-datasets"
DEFRA_API = "https://www.gov.uk/api/content/government/statistical-data-sets/family-food-datasets"
NS = {"table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0", "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0",
      "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0"}


def ods_tables(raw):
    """{sheet name: [[cell text or float]]} from an .ods file, standard library only"""
    xml = zipfile.ZipFile(io.BytesIO(raw)).read("content.xml")
    root = ET.fromstring(xml)
    T = "{%s}" % NS["table"]
    O = "{%s}" % NS["office"]
    out = {}
    for tab in root.iter(T + "table"):
        rows = []
        for row in tab.iter(T + "table-row"):
            cells = []
            for c in row:
                if c.tag not in (T + "table-cell", T + "covered-table-cell"):
                    continue
                rep = min(int(c.get(T + "number-columns-repeated", "1")), 200)
                if c.get(O + "value-type") in ("float", "percentage", "currency"):
                    v = float(c.get(O + "value"))
                else:
                    v = " ".join("".join(p.itertext()) for p in c.iter("{%s}p" % NS["text"])).strip()
                cells.extend([v] * rep)
            while cells and cells[-1] == "":
                cells.pop()
            rows.append(cells)
        out[tab.get(T + "name")] = rows
    return out


YEAR_LABEL = re.compile(r"^\s*((?:19|20)\d\d)(?:\s*[-/]\s*(\d{2,4}))?\s*$")
FLOUR_LABEL = re.compile(r"^\s*flour\s*(\([^)]*\))?\s*$", re.I)


def defra_flour():
    """UK household purchases of flour (Family Food), one value per survey year; fiscal years YYYY-YY are year YYYY"""
    meta = fetch(DEFRA_API)
    if not meta:
        return None
    url = next((a["url"] for a in json.loads(meta)["details"]["attachments"] if a.get("title", "").strip().lower() == "uk - household purchases"), None)
    if not url:
        return {"error": "attachment 'UK - household purchases' not found"}
    raw = fetch(url)
    if not raw:
        return None
    for name, rows in ods_tables(raw).items():
        header = None
        for ri, row in enumerate(rows):
            # a year header cell is text such as 1974, 2001-02 or 2015/16, or a whole number between 1970 and 2030
            cells = [str(int(c)) if isinstance(c, float) and c.is_integer() and 1970 <= c <= 2030 else c for c in row]
            yrs = [(ci, YEAR_LABEL.match(c)) for ci, c in enumerate(cells) if isinstance(c, str) and YEAR_LABEL.match(c)]
            if len(yrs) >= 10:
                header = (ri, yrs)
                break
        if not header:
            continue
        for row in rows[header[0] + 1:]:
            lab = next((c for c in row[:6] if isinstance(c, str) and FLOUR_LABEL.match(c)), None)
            if lab:
                unit = next((c for c in row[:8] if isinstance(c, str) and re.search(r"\bg\b|gram|ml|kg", c, re.I)), None)
                pts = []
                for ci, m in header[1]:
                    if ci < len(row) and isinstance(row[ci], float):
                        pts.append((int(m.group(1)), bool(m.group(2)), m.group(0).strip(), row[ci]))
                return {"sheet": name, "label": lab, "unit": unit, "points": pts, "url": url}
    return {"error": "no row labeled Flour under a year header", "url": url}


COMTRADE = "https://comtradeapi.un.org/public/v1/preview/C/A/HS"


def comtrade_us_imports(cmd, years):
    """US imports from the world, annual, by HS code, from the UN Comtrade public preview (no key)"""
    out = {}
    for k in range(0, len(years), 6):
        chunk = years[k:k + 6]
        q = urllib.parse.urlencode({"reporterCode": 842, "partnerCode": 0, "partner2Code": 0, "flowCode": "M", "cmdCode": cmd,
                                    "customsCode": "C00", "motCode": 0, "period": ",".join(map(str, chunk)), "includeDesc": "true"})
        body = fetch(f"{COMTRADE}?{q}")
        if body is None:
            return out or None
        for row in json.loads(body).get("data", []):
            if str(row.get("cmdCode")) == cmd and row.get("primaryValue") is not None:
                out[int(row["period"])] = {"value_usd": row["primaryValue"], "net_kg": row.get("netWgt"), "qty": row.get("qty"),
                                           "qty_unit": row.get("qtyUnitAbbr"), "classification": row.get("classificationCode")}
    return out or None


# ---------- the registered marks ----------
CULTURE_FILMS = {"Finding Nemo": "2003-05-30", "Mean Girls": "2004-04-30", "Sideways": "2004-10-22", "The Devil Wears Prada": "2006-06-30",
                 "Ratatouille": "2007-06-29", "Black Panther": "2018-02-16"}
CONTROLS = {
    # same kind, release year within 10 years, no link to the outcome, window inside coverage and clear of the real one
    ("frozen-culture", "w0"): [(t, d) for t, d in CULTURE_FILMS.items()],
    ("bake-off", "w0"): [("American Idol", 2002), ("Peaky Blinders", 2013), ("Love Island", 2015), ("Narcos", 2015), ("The Crown", 2016),
                         ("Stranger Things", 2016), ("Fleabag", 2016), ("13 Reasons Why", 2017), ("Money Heist", 2017), ("Dark", 2017)],
    ("finding-nemo", "w0"): [("Jurassic Park", 1993), ("The Lion King", 1994), ("Toy Story", 1995), ("Babe", 1995), ("Clueless", 1995),
                             ("Titanic", 1997), ("The Blair Witch Project", 1999), ("The Devil Wears Prada", 2006), ("Ratatouille", 2007),
                             ("The Hunger Games", 2012), ("Frozen", 2013)],
}
DECOY_LINKED = {
    # engine stones left out of a mark's decoys because they have a link to that outcome (named before any data)
    ("frozen-culture", "w0"): {"september-11": "a direct shock to international travel", "anthrax": "same month as September 11"},
    ("bake-off", "w0"): {},
    ("finding-nemo", "w0"): {"blue-planet-ii": "marine life", "deepwater-horizon": "Gulf marine life and fisheries", "fukushima": "the fish trade"},
}
BLOCKED = {
    ("blue-planet-ii", "w0"): {"series": "UCAS end-of-cycle applications to the detailed subject group that holds marine biology",
                               "status": "registered, not run: the first request to www.ucas.com on Oct 4, 2026 returned HTTP 404; under the stop rule no further UCAS request was made that day"},
    ("blue-planet-ii", "w1"): {"series": "UK Parliament Hansard: monthly spoken contributions containing \"plastic pollution\", over contributions containing \"Government\"",
                               "status": "registered, not run: the first request to hansard-api.parliament.uk on Oct 4, 2026 returned HTTP 500; under the stop rule no retry that day"},
}

RECORD_KINDS = {"Law", "Institution", "Policy", "Regulation", "Treaty", "Legal"}
REASON_RECORD = "a dated public record, not a series: the record itself dates the mark, and there is no outcome series to test"
SPECIAL = {
    ("an-inconvenient-truth", "w2"): ("no reachable series", "the 2011 study used purchase records by zip code that are not public; the voluntary carbon market's annual volumes begin in 2005-06 and are published as reports, with no history before the film"),
    ("frozen-culture", "w0"): ("testable", "Statistics Norway table 08402: foreign guests' hotel nights, monthly since 1985"),
    ("game-of-thrones", "w0"): ("a share, not a change", "the record states a share of tourists in one year (2019); a change test needs a window the claim does not give"),
    ("finding-nemo", "w0"): ("testable", "UN Comtrade: US imports of live ornamental fish (HS 030110), annual since 1991"),
    ("101-dalmatians", "w0"): ("no reachable series", "the American Kennel Club publishes breed ranks, not a registration-count series; no official puppy-sales series exists"),
    ("sideways", "w0"): ("no reachable series", "wine sales by variety are scanner data (proprietary); the public California grape crush report measures grape supply and prices, not wine sales, so it is a different mark"),
    ("queens-gambit", "w0"): ("no reachable series; excluded period", "no public series of chess-set sales; the stone (Oct 2020) and its window fall inside the pandemic closure months"),
    ("top-gun", "w0"): ("no reachable series", "no public series of naval aviator applications; the mark stays disputed"),
    ("avatar-2009", "w0"): ("a dated record", "a product launch (3D televisions at CES 2010) is a dated record; a new product category has no history before the stone"),
    ("mad-men", "w0"): ("excluded period", "the mark's year (2008) falls inside the 2008-09 financial crisis, which the project excludes; the nearest series (men's clothing store sales) is broader than suits"),
    ("bake-off", "w0"): ("testable", "Defra Family Food: UK household purchases of flour per person per week, annual since 1974"),
    ("woodstock", "w0"): ("a level, not a change", "the record states a visitor count for a venue that opened in 2006, 37 years after the stone; there is no series before the stone"),
    ("13-reasons-why", "w0"): ("needs owner action", "the monthly youth suicide series (CDC WONDER) can be queried only after accepting CDC's data-use terms, which this run may not do on the owner's behalf; the published study is already disputed"),
    ("blue-planet-ii", "w0"): ("testable, blocked today", "UCAS applications by detailed subject (ladder_plan_v1.md section 6.1)"),
    ("blue-planet-ii", "w1"): ("testable, blocked today", "Hansard spoken contributions: political interest as a record count, not pageviews (ladder_plan_v1.md section 6.2)"),
    ("emily-in-paris", "w0"): ("a share, not a change; excluded period", "the record states a survey share (2024), and the stone (Oct 2020) falls inside the pandemic closure months"),
    ("deepwater-horizon", "w1"): ("a dated record", "the GuLF Study's founding is a dated record, not a series"),
}

TESTS = {
    ("frozen-culture", "w0"): {"freq": "M", "h": 12, "direction": "up",
                               "series": "Norway, hotels: guest nights by guests resident abroad (all countries), monthly",
                               "what": "Foreign guests' hotel nights in Norway in the 12 months from Frozen's release, against every earlier 12-month change since 1986"},
    ("bake-off", "w0"): {"freq": "A", "h": 1, "direction": "up",
                         "series": "UK household purchases of flour, grams per person per week, by survey year",
                         "what": "Flour bought by UK households in 2011 against 2010, compared with every year-on-year change from 1975 to 2007"},
    ("finding-nemo", "w0"): {"freq": "A", "h": 1, "direction": "up",
                             "series": "US imports of live ornamental fish (HS 030110), trade value in US dollars, annual",
                             "what": "The value of live ornamental fish imported into the US in 2003 against 2002, compared with each earlier year-on-year change since 1992"},
}


def monthly_series(vals_by_month, months):
    dates = [dt.date(int(m[:4]), int(m[5:7]), 1) for m in months]
    return Series(dates, [vals_by_month.get(m) or np.nan for m in months], [month_excluded(d) for d in dates], period_days=31, seasonal=True, labels=months)


def defra_series(pts):
    pts = sorted(pts)
    years = [p[0] for p in pts]
    dates = [dt.date(y, 1, 1) for y in years]
    fiscal = [p[1] for p in pts]
    # definition breaks: the National Food Survey to the Expenditure and Food Survey (2001-02), fiscal to calendar years
    # (2006), calendar to fiscal years (2015-16): a change across a switch in fiscal/calendar status is not comparable
    breaks = {i for i in range(1, len(pts)) if fiscal[i] != fiscal[i - 1] or years[i] - years[i - 1] != 1}
    # the survey break (National Food Survey to the Expenditure and Food Survey, first fiscal year 2001-02) also bounds
    # pre-trend fits; the fiscal/calendar switches inside one survey do not
    survey = {i for i in range(1, len(pts)) if fiscal[i] and not fiscal[i - 1] and years[i] <= 2002} | {i for i in breaks if years[i] - years[i - 1] != 1}
    return Series(dates, [p[3] for p in pts], [year_excluded(y, f) for y, f in zip(years, fiscal)], breaks=breaks, period_days=365,
                  labels=[p[2] for p in pts], fit_breaks=survey)


def annual_series(by_year):
    years = sorted(by_year)
    gaps = {i for i in range(1, len(years)) if years[i] - years[i - 1] != 1}
    return Series([dt.date(y, 1, 1) for y in years], [by_year[y] for y in years], [year_excluded(y) for y in years], breaks=gaps,
                  period_days=365, labels=[str(y) for y in years])


def ref_for(test, stone, mark_date):
    """monthly: the stone's date; annual: the year the record dates the change (never earlier than the stone's year)"""
    if test["freq"] == "M":
        return stone
    y = max(stone.year, int(mark_date[:4]))
    return dt.date(y, 1, 1)


def lag_years(stone, mark_date):
    return max(stone.year, int(mark_date[:4])) - stone.year


def comparison(s, test, controls, stone, mark_date, real):
    """the same change after each matched control stone; p = (1 + controls at least as large) / (1 + n)"""
    sign = 1 if test["direction"] == "up" else -1
    rows = []
    for title, when in controls:
        if test["freq"] == "M":
            ref = D(when)
        else:
            ref = dt.date(int(when) + lag_years(stone, mark_date), 1, 1)
        r = s.index_of(ref)
        e = eff(s, r, test["h"]) if r is not None else None
        rows.append({"control": title, "date": str(when), "effect": round(e, 4) if e is not None else None,
                     "dropped": None if e is not None else "window outside coverage or touches an excluded period or break"})
    ok = [x["effect"] for x in rows if x["effect"] is not None]
    if real is None or not ok:
        return {"controls": rows, "p_comparison": None}
    p = (1 + sum(1 for e in ok if sign * e >= sign * real)) / (1 + len(ok))
    return {"controls": rows, "n": len(ok), "rank": 1 + sum(1 for e in ok if sign * e > sign * real), "p_comparison": round(p, 4)}


def decoys(s, test, wiki, slug, mid, stone, mark_date):
    """the mark's series, tested at every other engine stone's date that the series can test, deduplicated by window"""
    h, real_r = test["h"], s.index_of(ref_for(test, stone, mark_date))
    lag = lag_years(stone, mark_date)
    linked = DECOY_LINKED.get((slug, mid), {})
    seen, rows = {}, []
    linked_windows = set()
    for oslug, st in wiki["stones"].items():
        if oslug in linked:
            d0 = D(st["date"])
            linked_windows.add(s.index_of(d0 if test["freq"] == "M" else dt.date(d0.year + lag, 1, 1)))
    for oslug, st in sorted(wiki["stones"].items(), key=lambda kv: kv[1]["date"]):
        if oslug == slug or oslug in linked:
            continue
        d0 = D(st["date"])
        ref = d0 if test["freq"] == "M" else dt.date(d0.year + lag, 1, 1)
        r = s.index_of(ref)
        if r is None or r in linked_windows or r - 6 * h < 0 or r + h > len(s.y):
            continue
        if not window_ok(s, r, h) or abs(r - real_r) < 2 * h:  # the decoy's window must not touch the real one
            continue
        if r in seen:
            seen[r]["stones"].append(st["stone"])
            continue
        res, g, why = run_test(s, d0, ref, h, test["direction"])
        row = {"stones": [st["stone"]], "date": st["date"], "effect": res.get("effect"), "p": res.get("p"), "n_placebo": res.get("n_placebo"),
               "onset": res.get("onset"), "grade": g}
        seen[r] = row
        rows.append(row)
    counts = {}
    for x in rows:
        counts[x["grade"]] = counts.get(x["grade"], 0) + 1
    return {"windows": len(rows), "stones": sum(len(x["stones"]) for x in rows), "grades": counts, "rows": rows,
            "linked_left_out": linked}


def raw_block(s, r, h):
    """raw values beside the result: the sums (monthly) or values (annual) before and after, and the series itself"""
    if s.period_days < 300:
        before = float(np.nansum(s.values[r - h:r])) if r - h >= 0 else None
        after = float(np.nansum(s.values[r:r + h])) if r + h <= len(s.values) else None
        by_year = {}
        for d, v in zip(s.dates, s.values):
            if np.isfinite(v):
                by_year[d.year] = by_year.get(d.year, 0) + v
        return {"sum_12_months_before": before, "sum_12_months_after": after,
                "by_year": {str(k): round(v) for k, v in sorted(by_year.items()) if sum(1 for d in s.dates if d.year == k) == 12}}
    return {"before": s.values[r - 1].item() if r >= 1 else None, "after": s.values[r].item() if r < len(s.values) else None,
            "by_period": [[lab, (v.item() if np.isfinite(v) else None)] for lab, v in zip(s.labels, s.values)]}


def main() -> int:
    wiki = json.load(open(WIKI))
    rep = {"protocol": "ripples/docs/ladder_plan_v1.md", "code": "ripples/lab/ladder.py", "run": dt.date.today().isoformat(),
           "registered_sha": os.environ.get("LADDER_PLAN_SHA", ""), "user_agent": UA, "marks": {}, "negative_space": [], "decoys": {},
           "requests": REQUESTS, "stopped_hosts": STOPPED}
    series = {}
    # ---- fetch (each source once) ----
    ssb = ssb_08402()
    if ssb:
        vals, months = ssb
        foreign = {m: vals.get(("0", "ccc", m)) for m in months}
        total = {m: vals.get(("0", "00000", m)) for m in months}
        fjord = {m: sum(vals.get((rg, "ccc", m)) or 0 for rg in ("12", "14", "15")) or None for m in months}
        rest = {m: (foreign[m] - fjord[m]) if foreign[m] and fjord[m] else None for m in months}
        series["frozen-culture/w0"] = (monthly_series(foreign, months), SSB_URL)
        series["frozen-culture/w0/broader"] = (monthly_series(total, months), SSB_URL)
        gm = monthly_series({m: (fjord[m] / rest[m]) if fjord[m] and rest[m] else None for m in months}, months)
        series["frozen-culture/w0/gradient"] = (gm, SSB_URL)
        series["frozen-culture/w0/fjord"] = (monthly_series(fjord, months), SSB_URL)
        series["frozen-culture/w0/rest"] = (monthly_series(rest, months), SSB_URL)
    fl = defra_flour()
    if fl and fl.get("points"):
        series["bake-off/w0"] = (defra_series(fl["points"]), fl["url"])
        rep["defra_parse"] = {k: fl[k] for k in ("sheet", "label", "unit", "url")}
    elif fl:
        rep["defra_parse"] = fl
    years = list(range(1991, 2017))
    fish = comtrade_us_imports("030110", years)
    if fish:
        series["finding-nemo/w0"] = (annual_series({y: v["value_usd"] for y, v in fish.items()}), COMTRADE + "?reporterCode=842&cmdCode=030110&flowCode=M")
        rep["comtrade_030110"] = {str(k): v for k, v in sorted(fish.items())}
    ch3 = comtrade_us_imports("03", years)
    if ch3:
        series["finding-nemo/w0/broader"] = (annual_series({y: v["value_usd"] for y, v in ch3.items()}), COMTRADE + "?reporterCode=842&cmdCode=03&flowCode=M")

    # ---- every mark ----
    for slug, st in wiki["stones"].items():
        stone = D(st["date"])
        rep["marks"][slug] = {}
        for m in st["marks"]:
            key, cur = (slug, m["id"]), (m.get("grade") or "reported")
            kind = m.get("kind")
            cat, reason = SPECIAL.get(key) or (("a dated record", REASON_RECORD) if kind in RECORD_KINDS else ("unclassified", "no series identified"))
            row = {"label": m["label"], "kind": kind, "mark_date": m["date"], "current_grade": cur, "testable": key in TESTS or key in BLOCKED,
                   "category": cat, "reason": reason, "proposed_grade": cur}
            if key in BLOCKED:
                row.update(BLOCKED[key])
            if key in TESTS:
                t = TESTS[key]
                sk = f"{slug}/{m['id']}"
                row.update({"series": t["series"], "what_was_measured": t["what"], "test": f"placebo-date test, h={t['h']} {'months' if t['freq'] == 'M' else 'year'}, direction {t['direction']}"})
                if sk not in series:
                    row.update({"status": "not run: the source could not be fetched or parsed", "source_url": None})
                else:
                    s, src = series[sk]
                    ref = ref_for(t, stone, m["date"])
                    res, g, why = run_test(s, stone, ref, t["h"], t["direction"])
                    r = s.index_of(ref)
                    row.update({"source_url": src, "status": "run", "p": res.get("p"), "onset": res.get("onset"), "effect_log": res.get("effect"),
                                "effect_pct": round(100 * (math.exp(res["effect"]) - 1), 1) if res.get("effect") is not None else None,
                                "n_placebo": res.get("n_placebo"), "p_floor": res.get("p_floor"), "window": res.get("window"),
                                "onset_fit": res.get("fit_periods"), "proposed_grade": g, "grade_reason": why, "raw": raw_block(s, r, t["h"])})
                    row["comparison"] = comparison(s, t, CONTROLS[key], stone, m["date"], res.get("effect"))
                    if f"{sk}/gradient" in series:
                        gs = series[f"{sk}/gradient"][0]
                        gres = placebo_test(gs, gs.index_of(ref), gs.index_of(stone), t["h"], "up")
                        fj, rs = series[f"{sk}/fjord"][0], series[f"{sk}/rest"][0]
                        row["gradient"] = {"design": "log(foreign nights in Hordaland, Sogn og Fjordane and More og Romsdal) minus log(foreign nights in the rest of Norway); the same window and placebo pool",
                                           **gres, "fjord_raw": raw_block(fj, fj.index_of(ref), t["h"]), "rest_raw": raw_block(rs, rs.index_of(ref), t["h"])}
                    if f"{sk}/broader" in series:
                        bs = series[f"{sk}/broader"][0]
                        bres, bg, _ = run_test(bs, stone, ref, t["h"], t["direction"])
                        row["broader"] = {"series": "all guest nights in Norwegian hotels (residents and foreigners)" if t["freq"] == "M" else "US imports of all fish and crustaceans (HS chapter 03)",
                                          "effect_log": bres.get("effect"), "p": bres.get("p"), "onset": bres.get("onset"), "grade_if_it_were_the_mark": bg}
                    rep["decoys"][sk] = decoys(s, t, wiki, slug, m["id"], stone, m["date"])
                    if g == "reported":
                        rep["negative_space"].append({"stone": st["stone"], "slug": slug, "mark_id": m["id"], "mark": m["title"],
                                                      "expected": f"the record says this rose ({m['date'][:4]})", "found": why,
                                                      "effect_pct": row["effect_pct"], "p": row["p"], "broader": row.get("broader")})
            rep["marks"][slug][m["id"]] = row
            json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    tested = [(s, i) for s in rep["marks"] for i, r in rep["marks"][s].items() if r.get("status") == "run"]
    rep["summary"] = {"marks": sum(len(v) for v in rep["marks"].values()),
                      "testable": sum(1 for s in rep["marks"] for r in rep["marks"][s].values() if r["testable"]),
                      "run": len(tested),
                      "grades": {g: sum(1 for s, i in tested if rep["marks"][s][i]["proposed_grade"] == g) for g in ("measured", "timed", "busted", "reported")}}
    json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    print(json.dumps(rep["summary"]), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
