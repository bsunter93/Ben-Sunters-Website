#!/usr/bin/env python3
"""Names v1 (ripples/docs/names_plan_v1.md): the anomaly-first route (D2) on US baby names.

Start from sharp, unusual moves in what parents named their children, then look back for a cultural stone released 0
to 2 years before the onset that carries exactly that name. Every number here follows the registered plan; the
thresholds are the constants below and must not change after registration without a disclosed deviation.

  python names_v1.py scan       statistics, anomaly scan, Wikidata look-back, matching, decoys, known positives
                                -> ripples/docs/results/names_v1_candidates.json (before the hand check)
  python names_v1.py finalize   merges the hand check (names_v1_handcheck.json) -> ripples/docs/results/names_v1.json

Data: ripples/lab/discovery/names/names_national_1995_2021.csv (export_names.py). Wikidata: honest user agent, at most
one request a second, SPARQL 500/504 retried up to three times, any 403/429 or other refusal stops the run.
"""
from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import random
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RIPPLES = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DATA = os.path.join(HERE, "names_national_1995_2021.csv")
CACHE = os.environ.get("NAMES_CACHE", os.path.join(HERE, ".cache"))
RESULTS = os.path.join(RIPPLES, "docs", "results")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
SPARQL = "https://query.wikidata.org/sparql"
WDAPI = "https://www.wikidata.org/w/api.php"

# ---------------------------------------------------------------- registered constants (names_plan_v1.md)
SEED = 20261005
Y0, Y1 = 1995, 2021            # data years; changes exist from 1996
SMOOTH = 5                     # d = ln(n_t + 5) - ln(n_{t-1} + 5)
SCAN = (1998, 2021)            # years scanned for anomalies
CAND_P_YEAR = 0.005            # candidate: year-matched p
CAND_P_OWN = 0.10              # candidate: own-history p
TEST_P_YEAR = 0.0033           # measured: 0.01 / 3 (the look-back window has up to three years)
TEST_P_OWN = 0.05              # measured: the largest move in the name's own record
RUN_P_YEAR = 0.05              # a year belongs to a rise (or fall) run if its year-matched p <= 0.05
MIN_N = 100                    # materiality: at least 100 births in the larger year
MIN_DELTA = 50                 # materiality: at least 50 more (or fewer) births than the year before
BASE_YEARS, BASE_N = 5, 20     # established name: at least 5 years with >= 20 births before the onset
S_FLOOR = 0.05                 # floor of the own-history robust scale
LOOKBACK = 2                   # stones released 0..2 years before the onset (and up to the peak year, to catch busts)
SHIFTS = (4, 7, 10)            # look-back window placebo: the same window moved back k years
SL_WORK, SL_HUMAN, SL_BORN, SL_STORM, SL_THING = 20, 20, 10, 5, 50
N_DECOY_NAMES = 20
N_FAKE = 300
GHOST_SHIFTS = (5, 6, 7, 8, 9, 10)

GIVEN_CLASSES = ("Q202444", "Q11879590", "Q12308941", "Q3409032")
FEMALE = {"Q6581072", "Q43445", "Q1052281"}
MALE = {"Q6581097", "Q44148", "Q2449503"}
STORM_PREFIX = ("Hurricane ", "Tropical Storm ", "Typhoon ", "Cyclone ")

# Known positives, fixed before any result (plan section 6). sign +1 = rise, -1 = fall.
KNOWN = [
    # tier A: established names, can be measured
    {"id": "A1", "name": "Elsa", "sex": "F", "sign": 1, "years": [2014, 2014], "stone": r"^Frozen$", "date": "2013-11-27", "tier": "A"},
    {"id": "A2", "name": "Arya", "sex": "F", "sign": 1, "years": [2011, 2013], "stone": r"Game of Thrones", "date": "2011-04-17", "tier": "A"},
    {"id": "A3", "name": "Shiloh", "sex": "F", "sign": 1, "years": [2006, 2007], "stone": r"Shiloh Jolie-Pitt", "date": "2006-05-27", "tier": "A"},
    {"id": "A4", "name": "Maci", "sex": "F", "sign": 1, "years": [2009, 2011], "stone": r"Maci Bookout|16 and Pregnant|Teen Mom", "date": "2009-06-11", "tier": "A"},
    {"id": "A5", "name": "Katrina", "sex": "F", "sign": -1, "years": [2005, 2007], "stone": r"Hurricane Katrina", "date": "2005-08-29", "tier": "A"},
    {"id": "A6", "name": "Isis", "sex": "F", "sign": -1, "years": [2014, 2016], "stone": r"Islamic State", "date": "2014-06-29", "tier": "A"},
    {"id": "A7", "name": "Alexa", "sex": "F", "sign": -1, "years": [2015, 2017], "stone": r"Amazon Alexa|Amazon Echo", "date": "2014-11-06", "tier": "A"},
    {"id": "A8", "name": "Elsa", "sex": "F", "sign": -1, "years": [2015, 2016], "stone": r"^Frozen$", "date": "2013-11-27", "tier": "A"},
    # tier B: new or barely used names before the stone; the own-history test cannot apply, so timed at most
    {"id": "B1", "name": "Khaleesi", "sex": "F", "sign": 1, "years": [2011, 2013], "stone": r"Game of Thrones", "date": "2011-04-17", "tier": "B"},
    {"id": "B2", "name": "Miley", "sex": "F", "sign": 1, "years": [2006, 2008], "stone": r"Hannah Montana|Miley Cyrus", "date": "2006-03-24", "tier": "B"},
    {"id": "B3", "name": "Suri", "sex": "F", "sign": 1, "years": [2006, 2007], "stone": r"Suri Cruise", "date": "2006-04-18", "tier": "B"},
]
# Seen before registration (salmon v1 top rows); found pairs with these names do not count toward the new-pair bar.
SEEN = {("Jaheim", "M"), ("Tenley", "F"), ("Jaslene", "F"), ("Ermias", "M"), ("Cataleya", "F")}


# ---------------------------------------------------------------- data and statistics
def load():
    cnt: dict = {}
    with open(DATA) as f:
        for r in csv.DictReader(f):
            cnt.setdefault((r["name"], r["sex"]), {})[int(r["year"])] = int(r["n"])
    keys = sorted(cnt)
    N = np.zeros((len(keys), Y1 - Y0 + 1))
    for i, k in enumerate(keys):
        for y, n in cnt[k].items():
            N[i, y - Y0] = n
    return keys, N


def ge_rank(v):
    """For each element, (number of elements >= it, itself included) / len: the empirical p of a value against the
    others, (1 + #others >= x) / (1 + #others)."""
    s = np.sort(v)
    return (len(v) - np.searchsorted(s, v, side="left")) / len(v)


class Stats:
    def __init__(self, keys, N):
        self.keys, self.N = keys, N
        self.idx = {k: i for i, k in enumerate(keys)}
        self.sex = np.array([k[1] for k in keys])
        ny = N.shape[1]
        L = np.log(N + SMOOTH)
        d = np.full(N.shape, np.nan)
        d[:, 1:] = L[:, 1:] - L[:, :-1]
        e = np.full(N.shape, np.nan)
        for s in "FM":
            m = self.sex == s
            e[m, 1:] = d[m, 1:] - np.median(d[m, 1:], axis=0)
        S = np.full(N.shape, np.nan)
        for j in range(1, ny):
            mask = np.zeros(ny, bool)
            mask[1:] = True
            mask[j:j + 6] = False
            sub = e[:, mask]
            med = np.median(sub, axis=1, keepdims=True)
            S[:, j] = np.maximum(1.4826 * np.median(np.abs(sub - med), axis=1), S_FLOOR)
        self.d, self.e, self.S = d, e, S
        self.u = e / S
        self.p_year = {1: np.full(N.shape, np.nan), -1: np.full(N.shape, np.nan)}
        self.p_own = {1: np.full(N.shape, np.nan), -1: np.full(N.shape, np.nan)}
        for sign in (1, -1):
            for s in "FM":
                rows = np.where(self.sex == s)[0]
                for j in range(1, ny):
                    self.p_year[sign][rows, j] = ge_rank(sign * self.u[rows, j])
            for i in range(N.shape[0]):
                self.p_own[sign][i, 1:] = ge_rank(sign * e[i, 1:])

    def j(self, y):
        return y - Y0

    def n(self, i, y):
        return int(self.N[i, y - Y0]) if Y0 <= y <= Y1 else None

    def material(self, i, y, sign):
        a, b = self.N[i, y - Y0 - 1], self.N[i, y - Y0]
        return (b >= MIN_N and b - a >= MIN_DELTA) if sign > 0 else (a >= MIN_N and a - b >= MIN_DELTA)

    def run_start(self, i, t, sign):
        t0 = t
        while t0 - 1 >= Y0 + 1 and self.p_year[sign][i, t0 - 1 - Y0] <= RUN_P_YEAR:
            t0 -= 1
        return t0

    def established(self, i, t0):
        return int(sum(1 for y in range(Y0, t0) if self.N[i, y - Y0] >= BASE_N)) >= BASE_YEARS

    def counts(self, i, a, b):
        return {str(y): self.n(i, y) for y in range(max(Y0, a), min(Y1, b) + 1)}


def r_eff(R, month):
    """The first year with at least half a year of exposure; an unknown month counts as the second half."""
    return R if (month and month <= 6) else R + 1


def test_pair(st: Stats, i, R, month, sign):
    """The registered stone-anchored test (plan section 5)."""
    Re = r_eff(R, month)
    W = [y for y in range(Re, R + 3) if Y0 + 1 <= y <= Y1]
    if not W:
        return {"grade": "out of range"}
    py = st.p_year[sign]
    t_hat = min(W, key=lambda y: (py[i, y - Y0], y))
    jj = t_hat - Y0
    p_y, p_o = float(py[i, jj]), float(st.p_own[sign][i, jj])
    moved = p_y <= RUN_P_YEAR
    t0 = st.run_start(i, t_hat, sign) if moved else t_hat
    in_order = t0 >= Re
    mat = bool(st.material(i, t_hat, sign))
    est = st.established(i, t0)
    stat = p_y <= TEST_P_YEAR and p_o <= TEST_P_OWN and mat and est
    if not moved:
        grade = "no move"
    elif not in_order:
        grade = "busted"
    elif stat:
        grade = "measured"
    else:
        grade = "timed"
    return {"grade": grade, "t_hat": t_hat, "onset": t0, "r_eff": Re, "window": W, "p_year": round(p_y, 5),
            "p_own": round(p_o, 4), "material": mat, "established": est, "u": round(float(st.u[i, jj]), 3),
            "e": round(float(st.e[i, jj]), 4)}


def episodes(st: Stats, sign):
    out = []
    for i, k in enumerate(st.keys):
        yrs = [y for y in range(SCAN[0], SCAN[1] + 1)
               if st.material(i, y, sign) and st.p_year[sign][i, y - Y0] <= CAND_P_YEAR
               and st.p_own[sign][i, y - Y0] <= CAND_P_OWN]
        groups, cur = [], []
        for y in yrs:
            if cur and y != cur[-1] + 1:
                groups.append(cur)
                cur = []
            cur.append(y)
        if cur:
            groups.append(cur)
        for g in groups:
            ts = min(g, key=lambda y: (st.p_year[sign][i, y - Y0], y))
            t0 = st.run_start(i, ts, sign)
            out.append({"name": k[0], "sex": k[1], "i": i, "sign": sign, "onset": t0, "peak": ts, "years": g,
                        "p_year": round(float(st.p_year[sign][i, ts - Y0]), 5),
                        "p_own": round(float(st.p_own[sign][i, ts - Y0]), 4)})
    return out


# ---------------------------------------------------------------- polite network layer
class Stop(Exception):
    pass


_last = [0.0]
LOG: list = []


def http_get(url, accept):
    wait = 1.05 - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept})
    try:
        with urllib.request.urlopen(req, timeout=75) as r:
            body = r.read()
            code = r.status
    except urllib.error.HTTPError as e:
        code, body = e.code, e.read()
    except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as e:
        code, body = 0, str(e).encode()
    _last[0] = time.time()
    return code, body


def cached(kind, key, fn):
    os.makedirs(CACHE, exist_ok=True)
    p = os.path.join(CACHE, kind + "_" + hashlib.sha1(key.encode()).hexdigest()[:20] + ".json")
    if os.path.exists(p):
        with open(p) as f:
            return json.load(f)
    v = fn()
    if v is not None:
        with open(p, "w") as f:
            json.dump(v, f)
    return v


def sparql(q):
    def go():
        for attempt in range(4):
            code, body = http_get(SPARQL + "?" + urllib.parse.urlencode({"query": q, "format": "json"}),
                                  "application/sparql-results+json")
            if code == 200:
                return json.loads(body)["results"]["bindings"]
            LOG.append({"service": "sparql", "code": code, "attempt": attempt + 1})
            if code in (500, 504, 0) and attempt < 3:
                time.sleep(3 * (attempt + 1))
                continue
            if code in (500, 504, 0):
                return None
            raise Stop(f"Wikidata query service HTTP {code}")
        return None
    return cached("sparql", q, go)


def wbsearch(name):
    def go():
        url = WDAPI + "?" + urllib.parse.urlencode({"action": "wbsearchentities", "search": name, "language": "en",
                                                     "uselang": "en", "type": "item", "limit": 50, "format": "json"})
        code, body = http_get(url, "application/json")
        if code != 200:
            LOG.append({"service": "wbsearchentities", "code": code})
            raise Stop(f"Wikidata API HTTP {code}")
        return [{"id": r["id"], "label": r.get("label", "")} for r in json.loads(body).get("search", [])]
    return cached("search", name, go)


def val(b, k):
    return b[k]["value"] if k in b else None


def qid(uri):
    return uri.rsplit("/", 1)[-1] if uri else None


def lit(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"@en'


# ---------------------------------------------------------------- Wikidata look-back
def seeds_for(name):
    up = name.upper()
    storms = " ".join(lit(p + name) for p in STORM_PREFIX)
    gcls = " ".join("wd:" + c for c in GIVEN_CLASSES)
    q1 = f"""SELECT DISTINCT ?item ?kind WHERE {{
  {{ VALUES ?gcls {{ {gcls} }} ?item rdfs:label {lit(name)} ; wdt:P31 ?gcls . BIND("given" AS ?kind) }}
  UNION {{ {{ ?item rdfs:label {lit(name)} }} UNION {{ ?item skos:altLabel {lit(name)} }} UNION {{ ?item skos:altLabel {lit(up)} }}
          FILTER EXISTS {{ {{ ?item wdt:P1441 [] }} UNION {{ [] wdt:P674 ?item }} }} BIND("char" AS ?kind) }}
  UNION {{ {{ ?item rdfs:label {lit(name)} }} UNION {{ ?item skos:altLabel {lit(name)} }} UNION {{ ?item skos:altLabel {lit(up)} }}
          ?item wikibase:sitelinks ?sl . FILTER(?sl >= {SL_WORK})
          FILTER EXISTS {{ {{ ?item wdt:P577 [] }} UNION {{ ?item wdt:P580 [] }} UNION {{ ?item wdt:P571 [] }} }} BIND("dated" AS ?kind) }}
  UNION {{ VALUES ?lab {{ {storms} }} ?item rdfs:label ?lab . BIND("storm" AS ?kind) }}
}} LIMIT 3000"""
    rows = sparql(q1)
    failed = rows is None
    items = {}
    gn = []
    for b in rows or []:
        q, kind = qid(val(b, "item")), val(b, "kind")
        if kind == "given":
            gn.append(q)
        else:
            items.setdefault(q, set()).add(kind)
    for r in wbsearch(name):
        first = re.split(r"[\s,]+", r["label"].strip())[0] if r["label"] else ""
        if first == name and r["label"] != name:
            items.setdefault(r["id"], set()).add("prefix")
    if gn:
        vals = " ".join("wd:" + g for g in gn)
        q2 = f"""SELECT DISTINCT ?item WHERE {{ VALUES ?gn {{ {vals} }} ?item wdt:P735 ?gn .
  FILTER EXISTS {{ {{ ?item wdt:P1441 [] }} UNION {{ [] wdt:P674 ?item }} }} }} LIMIT 3000"""
        r2 = sparql(q2)
        failed = failed or r2 is None
        for b in r2 or []:
            items.setdefault(qid(val(b, "item")), set()).add("char_gn")
        q3 = f"""SELECT DISTINCT ?item ?sl WHERE {{ VALUES ?gn {{ {vals} }} ?item wdt:P735 ?gn ; wdt:P31 wd:Q5 ;
  wikibase:sitelinks ?sl . FILTER(?sl >= {SL_BORN}) }} ORDER BY DESC(?sl) LIMIT 300"""
        r3 = sparql(q3)
        failed = failed or r3 is None
        for b in r3 or []:
            items.setdefault(qid(val(b, "item")), set()).add("human_gn")
    return {"given": gn, "items": {k: sorted(v) for k, v in items.items()}, "failed": failed}


def chunks(xs, n):
    xs = list(xs)
    for a in range(0, len(xs), n):
        yield xs[a:a + n]


def details(qids):
    """Basics for every item: label, sitelinks, English article, sex, human/storm flags, given-name labels, aliases."""
    out = {}
    for ch in chunks(sorted(qids), 80):
        vals = " ".join("wd:" + q for q in ch)
        q = f"""SELECT ?item ?label ?sl ?en ?sex ?human (GROUP_CONCAT(DISTINCT ?gnl; SEPARATOR="|") AS ?gns)
  (GROUP_CONCAT(DISTINCT ?al; SEPARATOR="|") AS ?als) WHERE {{
  VALUES ?item {{ {vals} }}
  OPTIONAL {{ ?item rdfs:label ?label . FILTER(LANG(?label) = "en") }}
  OPTIONAL {{ ?item wikibase:sitelinks ?sl }}
  OPTIONAL {{ ?en schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> }}
  OPTIONAL {{ ?item wdt:P21 ?sex }}
  OPTIONAL {{ ?item wdt:P31 wd:Q5 . BIND(true AS ?human) }}
  OPTIONAL {{ ?item wdt:P735 ?gn . ?gn rdfs:label ?gnl . FILTER(LANG(?gnl) = "en") }}
  OPTIONAL {{ ?item skos:altLabel ?al . FILTER(LANG(?al) = "en") }}
}} GROUP BY ?item ?label ?sl ?en ?sex ?human"""
        rows = sparql(q)
        if rows is None:
            for x in ch:
                out.setdefault(x, {"failed": True})
            continue
        for b in rows:
            x = qid(val(b, "item"))
            d = out.setdefault(x, {"qid": x, "label": val(b, "label") or "", "sitelinks": int(val(b, "sl") or 0),
                                   "enwiki": val(b, "en"), "sex": None, "human": bool(val(b, "human")),
                                   "given": [g for g in (val(b, "gns") or "").split("|") if g],
                                   "aliases": [a for a in (val(b, "als") or "").split("|") if a]})
            s = qid(val(b, "sex"))
            if s in FEMALE:
                d["sex"] = "F"
            elif s in MALE:
                d["sex"] = d["sex"] or "M"
    return out


def works_of(chars):
    """Works each character is in (P1441 or the work's P674), and adaptations of those works (P144 / P4969)."""
    out = {}
    for ch in chunks(sorted(chars), 60):
        vals = " ".join("wd:" + q for q in ch)
        q = f"""SELECT DISTINCT ?item ?w ?a WHERE {{
  VALUES ?item {{ {vals} }}
  {{ ?item wdt:P1441 ?w }} UNION {{ ?w wdt:P674 ?item }}
  OPTIONAL {{ {{ ?a wdt:P144 ?w }} UNION {{ ?w wdt:P4969 ?a }} }}
}} LIMIT 20000"""
        rows = sparql(q)
        for b in rows or []:
            x, w, a = qid(val(b, "item")), qid(val(b, "w")), qid(val(b, "a"))
            d = out.setdefault(x, {})
            d.setdefault(w, set())
            if a:
                d[w].add(a)
    return {k: {w: sorted(a) for w, a in v.items()} for k, v in out.items()}


def dates_of(qids):
    """Every P577 / P580 / P571 / P569 / P585 statement with its precision."""
    out = {}
    branches = " UNION ".join(
        f'{{ ?item p:{p}/psv:{p} ?v . BIND("{p}" AS ?p) }}' for p in ("P577", "P580", "P571", "P569", "P585"))
    for ch in chunks(sorted(qids), 120):
        vals = " ".join("wd:" + q for q in ch)
        q = f"""SELECT ?item ?p ?t ?prec WHERE {{
  VALUES ?item {{ {vals} }}
  {branches}
  ?v wikibase:timeValue ?t ; wikibase:timePrecision ?prec .
}}"""
        rows = sparql(q)
        for b in rows or []:
            t = val(b, "t")
            m = re.match(r"^\+?(-?\d{1,4})-(\d\d)-(\d\d)", t or "")
            if not m:
                continue
            out.setdefault(qid(val(b, "item")), []).append(
                {"p": val(b, "p"), "y": int(m.group(1)), "m": int(m.group(2)), "d": int(m.group(3)),
                 "prec": int(val(b, "prec"))})
    return out


def debuts_of(humans):
    """Notable works (sitelinks >= 20) with the person as cast, performer, voice actor or author, with dates."""
    out = {}
    for ch in chunks(sorted(humans), 40):
        vals = " ".join("wd:" + q for q in ch)
        q = f"""SELECT ?item ?w ?sl WHERE {{
  VALUES ?item {{ {vals} }}
  ?w wdt:P161|wdt:P175|wdt:P725|wdt:P50 ?item . ?w wikibase:sitelinks ?sl . FILTER(?sl >= {SL_WORK})
}} LIMIT 20000"""
        rows = sparql(q)
        for b in rows or []:
            out.setdefault(qid(val(b, "item")), {})[qid(val(b, "w"))] = int(val(b, "sl"))
    return out


def first_date(ds, props=("P577", "P580", "P571")):
    """The earliest date among the first property that has one (P577, then P580, then P571), year precision or better."""
    for p in props:
        c = [x for x in ds or [] if x["p"] == p and x["prec"] >= 9 and 1800 <= x["y"] <= 2030]
        if c:
            b = min(c, key=lambda x: (x["y"], x["m"] if x["prec"] >= 10 else 13))
            return {"y": b["y"], "m": b["m"] if b["prec"] >= 10 else None, "d": b["d"] if b["prec"] >= 11 else None}
    return None


def fmt_date(dt):
    if not dt:
        return None
    if dt["m"] and dt["d"]:
        return f"{dt['y']:04d}-{dt['m']:02d}-{dt['d']:02d}"
    if dt["m"]:
        return f"{dt['y']:04d}-{dt['m']:02d}"
    return f"{dt['y']:04d}"


def stones_for(name, sex, seed, D, W, T, H):
    """Every stone the registered matching rule allows for this name, with the auto-strict flag (plan section 4)."""
    out = []
    nl = name.lower()

    def name_ok(it):
        lab = it.get("label") or ""
        first = re.split(r"[\s,]+", lab.strip())[0] if lab else ""
        return (name in it.get("given", []) or lab == name or first == name or name in it.get("aliases", []))

    def sex_ok(it):
        return it.get("sex") in (None, sex)

    for q, kinds in seed["items"].items():
        it = D.get(q)
        if not it or it.get("failed"):
            continue
        lab = it["label"]
        if any(lab == p + name for p in STORM_PREFIX):
            dt = first_date(T.get(q), ("P580", "P585", "P577", "P571"))
            if dt:
                out.append({"shelf": "storm", "stone_qid": q, "stone": lab, "date": dt, "via": None, "via_qid": None,
                            "sitelinks": it["sitelinks"], "strict": bool(it["enwiki"]) and it["sitelinks"] >= SL_STORM})
            continue
        if it["human"]:
            if not name_ok(it):
                continue
            born = first_date(T.get(q), ("P569",))
            if born and born["y"] >= 1993:
                out.append({"shelf": "person (born)", "stone_qid": q, "stone": lab, "date": born, "via": lab,
                            "via_qid": q, "sitelinks": it["sitelinks"],
                            "strict": bool(it["enwiki"]) and it["sitelinks"] >= SL_BORN and sex_ok(it)})
            deb = []
            for w, wsl in (H.get(q) or {}).items():
                dt = first_date(T.get(w))
                if dt:
                    deb.append((dt["y"], dt["m"] or 13, w, dt, wsl))
            if deb:
                y, _, w, dt, wsl = min(deb)
                wi = D.get(w, {})
                out.append({"shelf": "person (debut)", "stone_qid": q, "stone": lab, "date": dt, "via": lab,
                            "via_qid": q, "debut_work": wi.get("label") or w, "debut_qid": w,
                            "sitelinks": it["sitelinks"],
                            "strict": bool(it["enwiki"]) and it["sitelinks"] >= SL_HUMAN and sex_ok(it)})
            continue
        if q in W:  # a character
            if not name_ok(it):
                continue
            for w, adapts in W[q].items():
                for s in [w] + list(adapts):
                    si = D.get(s)
                    if not si or si.get("failed"):
                        continue
                    dt = first_date(T.get(s))
                    if not dt:
                        continue
                    out.append({"shelf": "character", "stone_qid": s, "stone": si["label"] or s, "date": dt,
                                "via": lab, "via_qid": q, "via_adaptation": s != w, "sitelinks": si["sitelinks"],
                                "strict": bool(it["enwiki"]) and bool(si["enwiki"]) and si["sitelinks"] >= SL_WORK
                                and sex_ok(it)})
            continue
        dt = first_date(T.get(q))
        if not dt:
            continue
        if lab.lower() == nl and it["sitelinks"] >= SL_WORK:
            out.append({"shelf": "title", "stone_qid": q, "stone": lab, "date": dt, "via": lab, "via_qid": q,
                        "sitelinks": it["sitelinks"], "strict": bool(it["enwiki"])})
        elif any(a.lower() == nl for a in it["aliases"]) and it["sitelinks"] >= SL_THING:
            out.append({"shelf": "named thing", "stone_qid": q, "stone": lab, "date": dt, "via": name, "via_qid": q,
                        "sitelinks": it["sitelinks"], "strict": bool(it["enwiki"])})
    # one row per (shelf, stone, via)
    seen, uniq = set(), []
    for s in sorted(out, key=lambda s: -s["sitelinks"]):
        k = (s["shelf"], s["stone_qid"], s.get("via_qid"))
        if k not in seen:
            seen.add(k)
            uniq.append(s)
    return uniq


def lookback(names):
    """Wikidata look-back for every (name) in the list. Returns per-name stones and a failure list."""
    seeds, failed, streak = {}, [], 0
    for k, name in enumerate(sorted(names)):
        try:
            s = seeds_for(name)
        except Stop:
            raise
        seeds[name] = s
        if s["failed"]:
            failed.append(name)
            streak += 1
            if streak >= 3:
                raise Stop("three names in a row failed at the query service")
        else:
            streak = 0
        if k % 25 == 0:
            print(f"  look-back {k + 1}/{len(names)} {name}", flush=True)
    allitems = set()
    for s in seeds.values():
        allitems |= set(s["items"])
    print(f"  details for {len(allitems)} items", flush=True)
    D = details(allitems)
    chars = {q for q, d in D.items() if not d.get("failed") and not d.get("human")
             and any(k in ("char", "char_gn", "prefix") for k in sum((s["items"].get(q, []) for s in seeds.values()), []))}
    print(f"  works for {len(chars)} characters", flush=True)
    W = works_of(chars)
    humans = {q for q, d in D.items() if d.get("human")}
    print(f"  notable works for {len(humans)} people", flush=True)
    H = debuts_of(humans)
    extra = set()
    for v in W.values():
        for w, a in v.items():
            extra.add(w)
            extra |= set(a)
    for v in H.values():
        extra |= set(v)
    extra -= set(D)
    print(f"  details for {len(extra)} works", flush=True)
    D.update(details(extra))
    print(f"  dates for {len(D)} entities", flush=True)
    T = dates_of(set(D))
    return seeds, D, W, T, H, failed


# ---------------------------------------------------------------- the run
def wilson(k, n, z=1.96):
    if n == 0:
        return None
    p = k / n
    den = 1 + z * z / n
    c = p + z * z / (2 * n)
    r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return round((c + r) / den, 4)


def plain(name, sex, sign, n_before, y_before, n_after, y_after):
    kids = "daughters" if sex == "F" else "sons"
    diff = abs(n_after - n_before)
    word = "more" if n_after >= n_before else "fewer"
    return f"Parents named {diff:,} {word} {kids} {name} in {y_after} than in {y_before}."


def persistence(st, i, t_hat, R, sign):
    pre_years = [y for y in range(R - 3, R) if Y0 <= y <= Y1]
    pre = float(np.mean([st.N[i, y - Y0] for y in pre_years])) if pre_years else None
    peak = float(st.N[i, t_hat - Y0])
    out = {"pre_level": round(pre, 1) if pre is not None else None, "peak_level": peak, "later": {}}
    ratios = []
    for k in range(2, 6):
        y = t_hat + k
        if y > Y1:
            break
        n = float(st.N[i, y - Y0])
        out["later"][str(y)] = int(n)
        if pre is not None and peak != pre:
            ratios.append((n - pre) / (peak - pre))
    out["share_of_jump_kept"] = [round(r, 3) for r in ratios]
    out["mean_share_kept"] = round(float(np.mean(ratios)), 3) if ratios else None
    out["persisted"] = (None if not ratios else bool(np.mean(ratios) >= 0.5))
    out["years_observed"] = len(ratios)
    return out


def pair_record(st, ep, s):
    i, sign = ep["i"], ep["sign"]
    R, M = s["date"]["y"], s["date"]["m"]
    t = test_pair(st, i, R, M, sign)
    rec = {"name": ep["name"], "sex": ep["sex"], "direction": "rise" if sign > 0 else "fall",
           "stone": {"title": s["stone"], "date": fmt_date(s["date"]), "wikidata": s["stone_qid"],
                     "shelf": s["shelf"], "via": s.get("via"), "via_qid": s.get("via_qid"),
                     "via_adaptation": s.get("via_adaptation", False), "debut_work": s.get("debut_work"),
                     "sitelinks": s["sitelinks"]},
           "episode": {"onset": ep["onset"], "peak": ep["peak"], "years": ep["years"]},
           "test": t, "stat_grade": t["grade"]}
    if t.get("t_hat"):
        th = t["t_hat"]
        rec["counts"] = st.counts(i, R - 3, min(Y1, th + 5))
        rec["counts_before_after"] = {"year_before_release": R - 1, "n_before": st.n(i, R - 1),
                                      "onset_year": t["onset"], "peak_year": th, "n_peak": st.n(i, th)}
        rec["persistence"] = persistence(st, i, th, R, sign)
        rec["plain"] = plain(ep["name"], ep["sex"], sign, st.n(i, R - 1), R - 1, st.n(i, th), th)
        rec["lag_years"] = {"onset_minus_release": t["onset"] - R, "peak_minus_release": th - R}
    rec["seen_before_registration"] = (ep["name"], ep["sex"]) in SEEN
    return rec


def scan():
    keys, N = load()
    st = Stats(keys, N)
    rng = random.Random(SEED)
    eps = episodes(st, 1) + episodes(st, -1)
    print(f"{len(keys)} name-sex pairs; {sum(1 for e in eps if e['sign'] > 0)} rise episodes, "
          f"{sum(1 for e in eps if e['sign'] < 0)} fall episodes", flush=True)
    names = sorted({e["name"] for e in eps} | {k["name"] for k in KNOWN})
    stop_reason = None
    try:
        seeds, D, W, T, H, failed = lookback(names)
    except Stop as e:
        stop_reason = str(e)
        print("STOP:", stop_reason, flush=True)
        json.dump({"stopped": stop_reason, "log": LOG}, open(os.path.join(RESULTS, "names_v1_stop.json"), "w"), indent=1)
        return 1
    stones = {}
    for nm in names:
        for sx in "FM":
            stones[(nm, sx)] = stones_for(nm, sx, seeds[nm], D, W, T, H)

    # matching in the true window and in the shifted (placebo) windows
    pairs, win = [], {k: {"episodes": 0, "with_match": 0, "stat_pass_episodes": 0, "stat_pass_with_match": 0}
                      for k in (0,) + SHIFTS}
    for ep in eps:
        i, sign = ep["i"], ep["sign"]
        stat_ok = (ep["p_year"] <= TEST_P_YEAR and ep["p_own"] <= TEST_P_OWN and st.established(i, ep["onset"]))
        strict = [s for s in stones[(ep["name"], ep["sex"])] if s["strict"]]
        for k in (0,) + SHIFTS:
            lo, hi = ep["onset"] - LOOKBACK - k, ep["peak"] - k
            hit = [s for s in strict if lo <= s["date"]["y"] <= hi]
            win[k]["episodes"] += 1
            win[k]["with_match"] += bool(hit)
            win[k]["stat_pass_episodes"] += stat_ok
            win[k]["stat_pass_with_match"] += bool(hit) and stat_ok
            if k == 0:
                for s in hit:
                    pairs.append(pair_record(st, ep, s))
    for k, v in win.items():
        v["share"] = round(v["with_match"] / v["episodes"], 4) if v["episodes"] else None
        v["share_stat_pass"] = (round(v["stat_pass_with_match"] / v["stat_pass_episodes"], 4)
                                if v["stat_pass_episodes"] else None)
    shifted = [win[k]["share_stat_pass"] for k in SHIFTS if win[k]["share_stat_pass"] is not None]
    t0s = win[0]["share_stat_pass"]
    win_summary = {"windows": {str(k): v for k, v in win.items()},
                   "true_share_stat_pass": t0s,
                   "mean_shifted_share_stat_pass": round(float(np.mean(shifted)), 4) if shifted else None,
                   "enrichment": (round(t0s / np.mean(shifted), 2) if shifted and np.mean(shifted) > 0 and t0s else None),
                   "estimated_coincidence_share": (round(float(np.mean(shifted)) / t0s, 3) if shifted and t0s else None)}

    # known positives: through the scan, and the direct stone-anchored test at the documented date
    kp = []
    for k in KNOWN:
        i = st.idx.get((k["name"], k["sex"]))
        row = {**{x: k[x] for x in ("id", "name", "sex", "tier", "years", "stone", "date")},
               "direction": "rise" if k["sign"] > 0 else "fall"}
        if i is None:
            row["status"] = "not in data"
            kp.append(row)
            continue
        y, m = int(k["date"][:4]), int(k["date"][5:7])
        row["direct_test"] = test_pair(st, i, y, m, k["sign"])
        row["counts"] = st.counts(i, y - 3, min(Y1, y + 6))
        ep = [e for e in eps if e["i"] == i and e["sign"] == k["sign"] and k["years"][0] <= e["peak"] <= k["years"][1]]
        row["scan_found"] = bool(ep)
        row["scan_episode"] = ({x: ep[0][x] for x in ("onset", "peak", "years", "p_year", "p_own")} if ep else None)
        hits = [p for p in pairs if p["name"] == k["name"] and p["sex"] == k["sex"]
                and p["direction"] == row["direction"] and re.search(k["stone"], p["stone"]["title"])
                and (not ep or p["episode"]["peak"] == ep[0]["peak"])]
        row["matched_expected_stone"] = bool(hits)
        row["matched_pairs"] = [{"stone": h["stone"]["title"], "date": h["stone"]["date"], "stat_grade": h["stat_grade"],
                                 "via": h["stone"]["via"]} for h in hits]
        allm = [s for s in stones[(k["name"], k["sex"])] if re.search(k["stone"], s["stone"])]
        row["expected_stone_in_catalog"] = [{"stone": s["stone"], "date": fmt_date(s["date"]), "shelf": s["shelf"],
                                             "strict": s["strict"], "via": s.get("via")} for s in allm[:5]]
        kp.append(row)

    # decoys
    def eligible_decoys(i, R, exclude):
        base = st.N[i, R - 1 - Y0]
        sx = st.sex[i]
        cand = [j for j in range(len(keys)) if st.sex[j] == sx and j != i and keys[j][0] not in exclude]
        lr = lambda j: abs(math.log((st.N[j, R - 1 - Y0] + SMOOTH) / (base + SMOOTH)))
        el = [j for j in cand if lr(j) <= math.log(1.25)]
        if len(el) < N_DECOY_NAMES:
            el = sorted(cand, key=lr)[:N_DECOY_NAMES]
        return el

    dn, dg = [], []
    seen_stone = set()
    for p in pairs:
        if p["stat_grade"] in ("no move", "out of range"):
            continue
        i = st.idx[(p["name"], p["sex"])]
        sign = 1 if p["direction"] == "rise" else -1
        R = int(p["stone"]["date"][:4])
        M = int(p["stone"]["date"][5:7]) if len(p["stone"]["date"]) >= 7 else None
        key = (p["stone"]["wikidata"], p["name"], p["sex"], sign)
        if key in seen_stone or R - 1 < Y0:
            continue
        seen_stone.add(key)
        stone_names = {q["name"] for q in pairs if q["stone"]["wikidata"] == p["stone"]["wikidata"]}
        el = eligible_decoys(i, R, stone_names)
        r2 = random.Random(f"{SEED}-{p['stone']['wikidata']}-{p['name']}-{sign}")
        for j in r2.sample(el, min(N_DECOY_NAMES, len(el))):
            t = test_pair(st, j, R, M, sign)
            dn.append({"stone": p["stone"]["wikidata"], "real_name": p["name"], "decoy": keys[j][0], "grade": t["grade"]})
        for g in GHOST_SHIFTS:
            Rg = R - g
            if Rg < Y0 + 1:
                continue
            t = test_pair(st, i, Rg, M, sign)
            dg.append({"stone": p["stone"]["wikidata"], "name": p["name"], "ghost_year": Rg, "grade": t["grade"]})
    fake = []
    pool = [j for j in range(len(keys))]
    for _ in range(N_FAKE):
        j = rng.choice(pool)
        R = rng.randint(1997, 2019)
        M = rng.randint(1, 12)
        for sign in (1, -1):
            t = test_pair(st, j, R, M, sign)
            fake.append({"name": keys[j][0], "sex": keys[j][1], "release": f"{R}-{M:02d}", "direction": sign,
                         "grade": t["grade"]})
    ruth = []
    iR = st.idx.get(("Ruth", "F"))
    for k in KNOWN:
        if iR is None:
            break
        t = test_pair(st, iR, int(k["date"][:4]), int(k["date"][5:7]), k["sign"])
        ruth.append({"at": k["id"], "date": k["date"], "direction": k["sign"], "grade": t["grade"]})

    def rate(rows):
        n = len(rows)
        kk = sum(1 for r in rows if r["grade"] == "measured")
        return {"n": n, "passed": kk, "rate": round(kk / n, 4) if n else None, "wilson_upper": wilson(kk, n)}

    decoys = {"decoy_names": rate(dn), "ghost_stones": rate(dg), "fake_stones": rate(fake), "ruth": rate(ruth),
              "fake_stones_rise": rate([f for f in fake if f["direction"] > 0]),
              "fake_stones_fall": rate([f for f in fake if f["direction"] < 0]),
              "decoy_names_passing": [r for r in dn if r["grade"] == "measured"],
              "ghost_stones_passing": [r for r in dg if r["grade"] == "measured"],
              "fake_stones_passing": [r for r in fake if r["grade"] == "measured"]}

    out = {"version": "names_v1", "plan": "ripples/docs/names_plan_v1.md", "seed": SEED,
           "data": {"file": "ripples/lab/discovery/names/names_national_1995_2021.csv", "name_sex_pairs": len(keys),
                    "years": [Y0, Y1]},
           "episodes": {"rise": sum(1 for e in eps if e["sign"] > 0), "fall": sum(1 for e in eps if e["sign"] < 0)},
           "episode_list": [{k: e[k] for k in ("name", "sex", "sign", "onset", "peak", "years", "p_year", "p_own")}
                            for e in eps],
           "lookback": {"names": len(names), "failed_names": failed, "requests_logged": LOG},
           "window_placebo": win_summary, "known_positives": kp, "decoys": decoys,
           "pairs": pairs}
    os.makedirs(RESULTS, exist_ok=True)
    with open(os.path.join(RESULTS, "names_v1_candidates.json"), "w") as f:
        json.dump(out, f, indent=1)
    with open(os.path.join(CACHE, "stones_by_name.json"), "w") as f:
        json.dump({f"{a}|{b}": v for (a, b), v in stones.items()}, f)
    print(f"pairs {len(pairs)}; window placebo {win_summary}; decoys "
          f"{ {k: v for k, v in decoys.items() if not k.endswith('passing')} }", flush=True)
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if cmd == "scan":
        sys.exit(scan())
    sys.exit(f"unknown command {cmd}")
