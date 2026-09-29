"""Salmon search v1 (ripples/docs/salmon_protocol_v1.md): start from an unusual outcome and swim upstream.

Outcome lens: US baby names (national, SSA via BigQuery; ripples/tools/bq/salmon_names.py writes the CSV).

1. Anomalies: for each (name, sex, year t), s = [log(n_t + 20) - log(n_{t-1} + 20)] minus the median of the same yearly
   change over t-5..t-1 (a break from the name's own trend). Floor: n_t >= 100 and s >= log(1.5). Each name keeps its
   strongest onset; the top 200 names by s are the starting points.
2. Proposer (Wikidata): items whose English label or alias starts with the name (EntitySearch), then the dated
   creative works they are present in (P1441; characters) or that they are (P577; works titled with the name).
3. Score per work: match x timing x prominence.
   - match 1.0 when the name is the item's whole label or first word (label or alias), 0.6 when a later word; else
     the item is dropped.
   - timing on lag = t - year(first publication date): 0-2 -> 1.0, 3-5 -> 0.5, 6-10 -> 0.2, >10 -> 0.05, negative
     (after the onset) -> excluded (time order).
   - prominence min(1, log10(sitelinks + 1) / 2).
4. Chance-match rate: the same linker on 200 placebo name-years (names with no anomaly, random year with n >= 100),
   and on the anomaly name's own non-anomalous years. Reported as (1 + #placebo >= observed) / (1 + #placebo).
5. Roles: the work is the proposed origin shock (earliest visible cause), a character carrying the name is the relay,
   the name-year is the outcome. Every link is labelled speculative.
6. Benchmark (pre-registered): 9 known name ripples; hit@1 and hit@3 of the known work, plus whether the anomaly scan
   detected the name-year. Pass rule: hit@1 >= 6 of 9.

Wikidata etiquette: honest UA, 1 s between queries, results cached; a refusal (403/429) or a gateway error stops the
run and is recorded. A query-level 500 (query timeout) is recorded for that name and the run continues.
"""
from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
CACHE = os.path.join(os.path.expanduser(os.environ.get("LAB_CACHE", "~/.cache/ripples-lab")), "salmon_wd")
SEED = 20260929
TOP = 200
N_PLACEBO = 200
FLOOR_N, FLOOR_S = 100, math.log(1.5)
PAUSE = 1.0

BENCHMARK = [  # (name, sex, onset year, acceptable work label pattern)
    ("Elsa", "F", 2014, r"\bFrozen\b"),
    ("Khaleesi", "F", 2012, r"Game of Thrones|Song of Ice and Fire"),
    ("Arya", "F", 2012, r"Game of Thrones|Song of Ice and Fire"),
    ("Daenerys", "F", 2012, r"Game of Thrones|Song of Ice and Fire"),
    ("Katniss", "F", 2012, r"Hunger Games"),
    ("Kylo", "M", 2016, r"Star Wars|Force Awakens"),
    ("Renesmee", "F", 2009, r"Twilight|Breaking Dawn"),
    ("Moana", "F", 2017, r"\bMoana\b"),
    ("Anakin", "M", 1999, r"Star Wars|Phantom Menace"),
]

QUERY = """SELECT ?item ?kind ?work ?workLabel ?date ?links WHERE {
  hint:Query hint:optimizer "None" .
  VALUES ?item { %s }
  { ?item wdt:P1441 ?work . ?work wdt:P577 ?date . ?work wikibase:sitelinks ?links . BIND("character" AS ?kind) }
  UNION
  { ?item wdt:P577 ?date . ?item wikibase:sitelinks ?links . BIND(?item AS ?work) BIND("work" AS ?kind) }
  OPTIONAL { ?work rdfs:label ?workLabel FILTER(LANG(?workLabel) = "en") }
}"""


class Stop(Exception):
    pass


# ---------- names and anomalies ----------

def load_names(path):
    d = {}
    for r in csv.DictReader(open(path)):
        d.setdefault((r["name"], r["sex"]), {})[int(r["year"])] = int(r["n"])
    return d


def scores(series, y0, y1):
    """s_t for t in y0..y1 (needs t-6..t); returns {t: (s, n_t, excess births)}."""
    L = {y: math.log(series.get(y, 0) + 20) for y in range(y0 - 6, y1 + 1)}
    out = {}
    for t in range(y0, y1 + 1):
        g = [L[y] - L[y - 1] for y in range(t - 5, t)]
        base = float(np.median(g))
        s = (L[t] - L[t - 1]) - base
        expected = (series.get(t - 1, 0) + 20) * math.exp(base) - 20
        out[t] = (s, series.get(t, 0), series.get(t, 0) - expected)
    return out


def anomalies(names, y0, y1):
    best = {}
    for (name, sex), ser in names.items():
        for t, (s, n, ex) in scores(ser, y0, y1).items():
            if n >= FLOOR_N and s >= FLOOR_S:
                if name not in best or s > best[name]["s"]:
                    best[name] = {"name": name, "sex": sex, "year": t, "s": round(s, 4), "n": n,
                                  "n_prev": ser.get(t - 1, 0), "excess_births": round(ex)}
    ranked = sorted(best.values(), key=lambda a: -a["s"])
    return ranked[:TOP], set(best)


# ---------- Wikidata proposer ----------

FAILS = {"consecutive": 0}


def _get(url, accept):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept})
    with urllib.request.urlopen(req, timeout=70) as r:
        return json.load(r)


def sparql(name):
    """v1.2 (deviation 1377): each UNION branch binds from the item ids first (optimizer hint), so the query never
    scans all dated items. v1.1 (deviation 1374, before any result): items from Wikidata's search API (wbsearchentities: English labels and
    aliases, up to 50), then one small SPARQL query on those item ids. A query-level 500/504 is recorded for that name
    and the run continues; a refusal (403/429) or 3 failures in a row stops the run."""
    os.makedirs(CACHE, exist_ok=True)
    f = os.path.join(CACHE, "v12-" + hashlib.md5(name.encode()).hexdigest() + ".json")
    if os.path.exists(f):
        return json.load(open(f))
    try:
        sr = _get("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode(
            {"action": "wbsearchentities", "search": name, "language": "en", "uselang": "en", "type": "item",
             "limit": "50", "format": "json"}), "application/json")
        time.sleep(PAUSE)
        hits = sr.get("search", [])
        labels = {}
        for h in hits:
            labels.setdefault(h["id"], set()).update(
                x for x in [h.get("label"), (h.get("match") or {}).get("text")] + list(h.get("aliases") or []) if x)
        out = []
        if labels:
            q = QUERY % " ".join("wd:" + i for i in labels)
            rows = _get("https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": q, "format": "json"}),
                        "application/sparql-results+json")["results"]["bindings"]
            time.sleep(PAUSE)
            for r in rows:
                d = {k: v["value"] for k, v in r.items()}
                it = d["item"].rsplit("/", 1)[-1]
                for lab in labels.get(it, {it}):
                    out.append(dict(d, lab=lab))
    except urllib.error.HTTPError as e:
        if e.code in (403, 429):
            raise Stop(f"HTTP {e.code}") from None
        FAILS["consecutive"] += 1
        if FAILS["consecutive"] >= 3:
            raise Stop(f"HTTP {e.code} three times in a row") from None
        time.sleep(PAUSE * 5)
        return {"error": f"query failed ({e.code})"}
    except (urllib.error.URLError, TimeoutError) as e:
        FAILS["consecutive"] += 1
        if FAILS["consecutive"] >= 3:
            raise Stop(f"network: {e}") from None
        time.sleep(PAUSE * 5)
        return {"error": f"network ({e})"}
    FAILS["consecutive"] = 0
    json.dump(out, open(f, "w"))
    return out


def match_weight(name, labels):
    nm = name.lower()
    best = 0.0
    for lab in labels:
        words = re.split(r"[\s\-]+", lab.lower().strip())
        if not words:
            continue
        if words[0] == nm or lab.lower().strip() == nm:
            best = max(best, 1.0)
        elif nm in words[1:]:
            best = max(best, 0.6)
    return best


def timing_weight(lag):
    if lag < 0:
        return 0.0
    if lag <= 2:
        return 1.0
    if lag <= 5:
        return 0.5
    if lag <= 10:
        return 0.2
    return 0.05


def candidates(rows, name):
    """Collapse SPARQL rows to per-work candidates (time-independent parts)."""
    if isinstance(rows, dict):
        return []
    items, works = {}, {}
    for r in rows:
        it = r["item"].rsplit("/", 1)[-1]
        items.setdefault(it, {"labels": set(), "kind": r.get("kind")})
        for k in ("lab", "alt"):
            if r.get(k):
                items[it]["labels"].add(r[k])
        w = r["work"].rsplit("/", 1)[-1]
        try:
            y = int(r["date"][:5].lstrip("+")[:4]) if r["date"][0] != "-" else None
        except ValueError:
            y = None
        if y is None:
            continue
        cur = works.setdefault((it, w), {"work": w, "work_label": r.get("workLabel", w), "year": y,
                                         "links": int(r.get("links", 0)), "via": it, "kind": r.get("kind")})
        cur["year"] = min(cur["year"], y)
    out = []
    for (it, w), c in works.items():
        m = match_weight(name, items[it]["labels"])
        if m == 0:
            continue
        c = dict(c)
        c["match"] = m
        c["via_label"] = sorted(items[it]["labels"])[0] if items[it]["labels"] else it
        c["prom"] = min(1.0, math.log10(c["links"] + 1) / 2)
        out.append(c)
    return out


def rank(cands, year):
    best = {}
    for c in cands:
        t = timing_weight(year - c["year"])
        if t == 0:
            continue
        sc = c["match"] * t * c["prom"]
        if c["work"] not in best or sc > best[c["work"]]["score"]:
            best[c["work"]] = dict(c, lag=year - c["year"], timing=t, score=round(sc, 4))
    return sorted(best.values(), key=lambda c: -c["score"])


def top_score(cands, year):
    r = rank(cands, year)
    return r[0]["score"] if r else 0.0


def chain(name, year, c):
    roles = {"outcome": f"US babies named {name}, {year}", "origin": f"{c['work_label']} ({c['year']})",
             "label": "Possible link (speculative)"}
    if c["kind"] == "character":
        roles["relay"] = f"{c['via_label']} (character)"
    else:
        roles["echo"] = "the work's own title carries the name"
    return roles


# ---------- main ----------

def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "names_national.csv"
    names = load_names(path)
    years = sorted({y for s in names.values() for y in s})
    y1 = years[-1]
    y0 = max(1996, years[0] + 6)
    anoms, anom_names = anomalies(names, y0, y1)
    report = {"protocol": "ripples/docs/salmon_protocol_v1.md", "seed": SEED, "years": [y0, y1],
              "names_rows": sum(len(s) for s in names.values()), "anomalies": [], "benchmark": [], "placebo": {}}
    rng = np.random.default_rng(SEED)
    stopped = None

    # placebo name-years: names never anomalous, random year with n >= 100
    pool = sorted({(nm, sx) for (nm, sx), s in names.items() if nm not in anom_names and
                   any(s.get(y, 0) >= FLOOR_N for y in range(y0, y1 + 1))})
    idx = rng.permutation(len(pool))
    placebo, pscores = [], []
    for i in idx:
        if len(placebo) >= N_PLACEBO:
            break
        nm, sx = pool[i]
        yrs = [y for y in range(y0, y1 + 1) if names[(nm, sx)].get(y, 0) >= FLOOR_N]
        placebo.append((nm, sx, int(rng.choice(yrs))))
    cand_cache = {}

    failed = []

    def cands_for(nm):
        if nm not in cand_cache:
            rows = sparql(nm)
            if isinstance(rows, dict):
                failed.append(nm)
            cand_cache[nm] = candidates(rows, nm)
        return cand_cache[nm]

    try:
        for nm, sx, y in placebo:
            pscores.append(top_score(cands_for(nm), y))
        P = np.array(pscores)
        report["placebo"] = {"n": len(P), "share_with_any_match": round(float((P > 0).mean()), 3),
                             "quantiles": {q: round(float(np.quantile(P, q)), 4) for q in (0.5, 0.9, 0.95, 0.99)}}

        def chance(sc):
            return round((1 + int((P >= sc).sum())) / (1 + len(P)), 4)

        def same_name_chance(nm, year, sc):
            ys = [y for y in range(y0, y1 + 1) if abs(y - year) >= 3]
            if not ys:
                return None
            v = np.array([top_score(cands_for(nm), y) for y in ys])
            return round(float((v >= sc).mean()), 3)

        for a in anoms:
            r = rank(cands_for(a["name"]), a["year"])[:5]
            for c in r:
                c["chance_match"] = chance(c["score"])
                c["chain"] = chain(a["name"], a["year"], c)
            if r:
                r[0]["same_name_other_years"] = same_name_chance(a["name"], a["year"], r[0]["score"])
            report["anomalies"].append(dict(a, candidates=r))

        det = {(a["name"], a["year"]) for a in anoms}
        hits1 = hits3 = 0
        for nm, sx, yr, pat in BENCHMARK:
            r = rank(cands_for(nm), yr)[:5]
            pos = next((i for i, c in enumerate(r) if re.search(pat, c["work_label"])), None)
            hits1 += pos == 0
            hits3 += pos is not None and pos < 3
            ser = names.get((nm, sx), {})
            sc = scores(ser, yr, yr).get(yr) if ser else None
            report["benchmark"].append({
                "name": nm, "sex": sx, "year": yr, "known": pat, "rank_of_known": None if pos is None else pos + 1,
                "detected_in_top200": (nm, yr) in det, "s": None if not sc else round(sc[0], 4),
                "n": ser.get(yr), "top": [{k: c[k] for k in ("work_label", "year", "score", "via_label")} for c in r[:3]],
                "chance_match_of_known": None if pos is None else chance(r[pos]["score"])})
        report["benchmark_summary"] = {"hit_at_1": hits1, "hit_at_3": hits3, "of": len(BENCHMARK),
                                       "pass": hits1 >= 6}
    except Stop as e:
        stopped = str(e)
        report["stopped"] = stopped
        print(f"stopped: {e}", flush=True)
    report["n_queries_cached"] = len(cand_cache)
    report["failed_queries"] = failed
    report["version"] = "v1.2"
    out = os.environ.get("SALMON_OUT", "salmon_names_v1.json")
    json.dump(report, open(out, "w"), indent=1, default=str)
    print(json.dumps(report.get("benchmark_summary"), default=str), flush=True)
    print(f"anomalies {len(report['anomalies'])}, placebo {report['placebo']}", flush=True)
    for a in report["anomalies"][:40]:
        c = a["candidates"][0] if a["candidates"] else None
        print(f"{a['name']:>12} {a['sex']} {a['year']} s={a['s']:.2f} n={a['n']:>6} +{a['excess_births']:>6} | "
              + (f"{c['work_label']} ({c['year']}) via {c['via_label']} score {c['score']} chance {c['chance_match']}"
                 if c else "no candidate"), flush=True)
    return 0 if not stopped else 0


if __name__ == "__main__":
    sys.exit(main())
