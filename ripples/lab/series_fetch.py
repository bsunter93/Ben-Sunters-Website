"""Official series and a dose-response design, fetched in CI (ripples/docs/dose_response_v1.md).

1. CDC YRBS state surveys: share of high-school students who drank alcohol in the past 30 days, by state and year,
   found by Socrata catalog search (the dataset id is not hard-coded; the probe logs what it found).
2. Dose-response: legal recreational cannabis (retail start, by state) against the change in youth drinking,
   difference-in-differences with staggered adoption, permutation inference, pre-trend check.
3. NIAAA apparent per-capita ethanol consumption, if its text file is reachable.
Writes ripples/docs/results/series_v1.json. Honest UA, 1 s between requests, stop on refusal.
"""
from __future__ import annotations

import collections
import csv
import datetime as dt
import io
import json
import os
import random
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(__file__))
import mark_first as mf  # noqa: E402  (get: honest UA, delays, stop on refusal)

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "docs", "results", "series_v1.json")
RETAIL = {"CO": "2014-01", "WA": "2014-07", "OR": "2015-10", "AK": "2016-10", "NV": "2017-07", "CA": "2018-01", "MA": "2018-11",
          "MI": "2019-12", "IL": "2020-01", "ME": "2020-10", "AZ": "2021-01", "MT": "2022-01", "NJ": "2022-04", "NM": "2022-04",
          "VT": "2022-10", "RI": "2022-12", "NY": "2022-12", "CT": "2023-01", "MO": "2023-02", "MD": "2023-07"}
NIAAA_URLS = ["https://www.niaaa.nih.gov/sites/default/files/pcyr1970-2022.txt", "https://www.niaaa.nih.gov/sites/default/files/pcyr1970-2021.txt",
              "https://pubs.niaaa.nih.gov/publications/surveillance120/pcyr1970-2021.txt"]


def jget(url):
    body = mf.get(url, headers={"Accept": "application/json"})
    try:
        return json.loads(body) if body else None
    except ValueError:
        return None


# ---------- YRBS via Socrata ----------
KNOWN_YRBS = [("chronicdata.cdc.gov", "q6p7-56au"), ("data.cdc.gov", "q6p7-56au")]  # DASH YRBSS high school; tried first, then the catalog


def find_yrbs():
    """Candidate Socrata datasets on CDC domains whose name says youth risk behavior; returns [(domain, id, name)].
    The BRFSS adult survey also matches a loose search (the Oct 3 run used it by mistake), so the name must say youth."""
    out = list(KNOWN_YRBS)
    for domain in ("data.cdc.gov", "chronicdata.cdc.gov"):
        q = urllib.parse.urlencode({"domains": domain, "q": "Youth Risk Behavior Surveillance", "limit": 30})
        d = jget(f"https://api.us.socrata.com/api/catalog/v1?{q}")
        for r in (d or {}).get("results", []):
            res = r.get("resource", {})
            if res.get("type") == "dataset" and re.search(r"youth|YRBS", res.get("name") or "", re.I) and (domain, res.get("id")) not in out:
                out.append((domain, res.get("id")))
    return out


def columns_of(domain, sid):
    """Column names from the table's metadata. (A sample row is not enough: Socrata leaves null fields out of the JSON,
    so on Oct 3 the YRBS tables' value column was missing from their first row and the tables were rejected.)"""
    meta = jget(f"https://{domain}/api/views/{sid}.json")
    cols = [c.get("fieldName", "").lower() for c in (meta or {}).get("columns", []) if c.get("fieldName")]
    if cols:
        return cols, {"name": (meta or {}).get("name")}
    rows = jget(f"https://{domain}/resource/{sid}.json?$limit=1")
    return ([k.lower() for k in rows[0].keys()] if rows else []), (rows[0] if rows else {})


def yrbs_alcohol():
    """{state: {year: prevalence}} for current alcohol use, high school, total; plus a note on the source."""
    cands = find_yrbs()
    print("YRBS candidates:", cands, flush=True)
    found, seen = [], set()
    for domain, sid in cands:
        if sid in seen:
            continue  # the same table is mirrored on both domains; a mirror is tried only when the first read failed
        cols, sample = columns_of(domain, sid)
        if not cols:
            print("no columns from", domain, sid, flush=True)
            continue
        seen.add(sid)
        ycol = next((c for c in ("year", "surveyyear", "yearstart") if c in cols), None)
        lcol = next((c for c in ("locationabbr", "area_abbr", "statecode", "state") if c in cols), None)
        vcol = next((c for c in ("greater_risk_data_value", "data_value", "percent", "prevalence", "value") if c in cols), None)
        qcol = next((c for c in ("greater_risk_question", "shortquestiontext", "question", "questioncode", "topic") if c in cols), None)
        if not (ycol and lcol and vcol and qcol):
            print("schema not usable:", sid, cols[:40], flush=True)
            continue
        where = [f"upper({qcol}) like '%ALCOHOL%'"]
        for c in ("sex", "race", "grade", "sexualidentity"):  # YRBS "Total" strata
            if c in cols:
                where.append(f"({c}='Total' OR {c} IS NULL)")
        if "stratificationtype" in cols:
            where.append("stratificationtype='State'")
        if "break_out" in cols:  # BRFSS-style tables
            where.append("break_out='Overall'")
        if "response" in cols:
            where.append("response='Yes'")
        strata = [c for c in ("demographics_type", "demographics_value", "stratificationcategory1", "stratification1") if c in cols]
        params = {"$where": " AND ".join(where), "$select": ",".join([lcol, ycol, qcol, vcol] + strata), "$limit": 50000}
        rows = jget(f"https://{domain}/resource/{sid}.json?{urllib.parse.urlencode(params)}")
        if not rows:
            print("no rows from", sid, flush=True)
            continue
        qs = sorted({r.get(qcol) for r in rows if r.get(qcol)})
        print("questions:", qs[:12], flush=True)
        # the current-drinking question, not binge, not first drink, not ever
        pick = next((q for q in qs if re.search(r"currently drank|current(?:ly)? alcohol|drank alcohol.*(?:30|past month)|had at least one drink", q or "", re.I)
                     and not re.search(r"binge|first|before age|ever|5 or more|4 or more", q or "", re.I)), None)
        if not pick:
            print("no current-drinking question in", sid, flush=True)
            continue
        rows = [r for r in rows if r.get(qcol) == pick and r.get(vcol)]
        if strata:  # keep the whole-population rows: the stratum value that reads as a total, else the most common one
            vals = collections.Counter(tuple(r.get(c) for c in strata) for r in rows)
            total = next((k for k in vals if any(re.fullmatch(r"(total|overall|all( students)?)", str(x) or "", re.I) for x in k)), vals.most_common(1)[0][0])
            print("strata:", vals.most_common(6), "-> using", total, flush=True)
            rows = [r for r in rows if tuple(r.get(c) for c in strata) == total]
        out = {}
        for r in rows:
            st, y = str(r[lcol]), int(str(r[ycol])[:4])
            try:
                v = float(r[vcol])
            except ValueError:
                continue
            if 0 < v < 100 and len(st) == 2:
                out.setdefault(st, {})[y] = v
        name = sample.get("name") or sid
        years = sorted({y for d in out.values() for y in d})
        print("states:", len(out), "years:", years, flush=True)
        if len(out) >= 20 and len(years) >= 2:
            found.append((len(years), len(out), out, {"domain": domain, "dataset": sid, "name": name, "question": pick, "value_column": vcol, "years": years}))
        if len(years) >= 10:
            break  # the full series; no need to read the rest
    if not found:
        return None, None
    found.sort(key=lambda f: (f[0], f[1]), reverse=True)  # the table with the most survey years wins
    return found[0][2], found[0][3]


# ---------- BRFSS (annual, all states, age breakouts) ----------
KNOWN_BRFSS = [("data.cdc.gov", "dttw-5yxu"), ("chronicdata.cdc.gov", "dttw-5yxu")]  # BRFSS Prevalence Data (2011 to present)


def brfss_drinking(break_out="18-24"):
    """{state: {year: % who drank in the past 30 days}} for one BRFSS breakout (an age group, or 'Overall'), 2011 on.
    The YRBS state tables end in 2017 and Colorado and Washington do not take part, so the dose-response design needs
    an annual outcome that covers every state: BRFSS adults 18–24 is the nearest to the youth question."""
    for domain, sid in KNOWN_BRFSS:
        cols, meta = columns_of(domain, sid)
        if not cols:
            continue
        where = ["upper(question) like '%DRINK%ALCOHOL%'", "response='Yes'"]
        if break_out == "Overall":
            where.append("break_out='Overall'")
        else:
            where += ["break_out_category='Age Group'", f"break_out='{break_out}'"]
        if "data_value_type" in cols:
            where.append("data_value_type='Crude Prevalence'")
        params = {"$where": " AND ".join(where), "$select": "locationabbr,year,question,data_value", "$limit": 50000}
        rows = jget(f"https://{domain}/resource/{sid}.json?{urllib.parse.urlencode(params)}")
        if not rows:
            print("BRFSS: no rows from", domain, sid, flush=True)
            continue
        qs = collections.Counter(r.get("question") for r in rows)
        pick = next((q for q in qs if re.search(r"at least one drink", q or "", re.I) and not re.search(r"binge|heavy", q or "", re.I)), None)
        print("BRFSS questions:", qs.most_common(4), "->", pick, flush=True)
        if not pick:
            continue
        out = {}
        for r in rows:
            if r.get("question") != pick or not r.get("data_value"):
                continue
            st, y = str(r["locationabbr"]), int(str(r["year"])[:4])
            try:
                v = float(r["data_value"])
            except ValueError:
                continue
            if 0 < v < 100 and len(st) == 2:
                out.setdefault(st, {})[y] = v
        years = sorted({y for d in out.values() for y in d})
        print("BRFSS", break_out, "states:", len(out), "years:", years, flush=True)
        if len(out) >= 40 and len(years) >= 8:
            return out, {"domain": domain, "dataset": sid, "name": meta.get("name") or sid, "question": pick, "break_out": break_out, "years": years}
    return None, None


def did(data, treat, k_before=1, k_after=2, pre=False):
    """Mean over treated states of (own change) - (control mean change) between the survey k_before before start and
    k_after after; with pre=True the two surveys before start (placebo in time). Returns (effect, n_treated, rows)."""
    controls = [s for s in data if s not in RETAIL]
    rows = []
    for st, start in treat.items():
        if st not in data:
            continue
        years = sorted(data[st])
        y0 = int(start[:4])
        before = [y for y in years if y < y0]
        after = [y for y in years if y > y0 + 0.5]
        if pre:
            if len(before) < 3:
                continue
            a, b = before[-3], before[-1]
        else:
            if len(before) < 1 or len(after) < k_after:
                continue
            a, b = before[-1], after[k_after - 1]
        own = data[st][b] - data[st][a]
        ctrl = [data[c][b] - data[c][a] for c in controls if a in data[c] and b in data[c]]
        if len(ctrl) < 8:
            continue
        rows.append({"state": st, "start": start, "from": a, "to": b, "own": round(own, 2), "control": round(sum(ctrl) / len(ctrl), 2), "n_control": len(ctrl)})
    if not rows:
        return None, 0, rows
    eff = sum(r["own"] - r["control"] for r in rows) / len(rows)
    return round(eff, 3), len(rows), rows


def dose_response(data):
    eff, n, rows = did(data, RETAIL)
    if eff is None:
        return {"result": "not enough overlapping surveys"}
    states = sorted(data)
    rng = random.Random(1466)
    draws = []
    for _ in range(2000):
        fake = dict(zip(rng.sample(states, len(RETAIL)), RETAIL.values()))
        e, m, _ = did(data, fake)
        if e is not None and m >= max(5, n // 2):
            draws.append(e)
    p1 = (1 + sum(1 for e in draws if e <= eff)) / (1 + len(draws))
    p2 = (1 + sum(1 for e in draws if abs(e) >= abs(eff))) / (1 + len(draws))
    pre_eff, pre_n, pre_rows = did(data, RETAIL, pre=True)
    pre_draws = []
    for _ in range(1000):
        fake = dict(zip(rng.sample(states, len(RETAIL)), RETAIL.values()))
        e, m, _ = did(data, fake, pre=True)
        if e is not None and m >= 5:
            pre_draws.append(e)
    pre_p = (1 + sum(1 for e in pre_draws if abs(e) >= abs(pre_eff or 0))) / (1 + len(pre_draws)) if pre_eff is not None else None
    ctrl_n = len([s for s in data if s not in RETAIL])
    return {"effect": eff, "p": round(p1, 4), "p_two_sided": round(p2, 4), "n_draws": len(draws), "pretrend_effect": pre_eff, "pretrend_p": round(pre_p, 4) if pre_p else None,
            "n_treated": n, "n_control": ctrl_n, "rows": rows, "pretrend_rows": pre_rows,
            "design": "difference-in-differences, staggered adoption; change from the last survey before retail sales to the second after, minus control states' change; permutation p over 2,000 random assignments",
            "points": [[f"{r['to']}-07-01", round(r["own"] - r["control"], 2)] for r in sorted(rows, key=lambda r: r["to"])]}


# ---------- NIAAA ----------
def niaaa():
    """US per-capita ethanol (gallons, population 14+, all beverages) by year from the NIAAA surveillance text file.
    Rows are whitespace fields: year, state code (99 = United States), beverage type (4 = all), gallons of beverage,
    gallons of ethanol, population 14+, per-capita ethanol 14+ in ten-thousandths of a gallon, decile, population 21+, ..."""
    for u in NIAAA_URLS:
        t = mf.get(u)
        if not t or len(t) < 500:
            continue
        pts, sample = [], None
        lines = [ln for ln in t.splitlines() if ln.strip()]
        for line in lines:
            f = re.split(r"[,\t]+|\s+", line.strip())
            # observed Oct 3: "2022 99 4 <gallons> <ethanol> <pop 14+> <per capita 14+ x 10000> <decile> <pop 21+> <per capita 21+ x 10000> ..."
            if len(f) >= 7 and re.fullmatch(r"\d{4}", f[0]) and f[1].lstrip("0") == "99" and f[2] == "4":
                try:
                    pts.append([f"{f[0]}-01-01", round(float(f[6]) / 10000, 4)])
                    sample = sample or line.strip()
                except ValueError:
                    pass
        if len(pts) > 30:
            print("NIAAA from", u, len(pts), "years; sample row:", sample, flush=True)
            return sorted(pts), u
        print("NIAAA file read but no US all-beverage rows parsed from", u, "; first lines:", lines[:4], "; a late line:", lines[-3:-1], flush=True)
    print("NIAAA file not reachable at the known paths", flush=True)
    return None, None


def main() -> int:
    state = {"protocol": "ripples/docs/dose_response_v1.md", "started": dt.date.today().isoformat(), "series": {}, "dose": {}}  # rebuilt each run
    try:
        data, src = yrbs_alcohol()
        if data:
            state["yrbs"] = {"source": src, "states": len(data), "years": sorted({y for s in data.values() for y in s})}
            for st in ("US", "XX"):
                data.pop(st, None)
            us = {}
            for st, d in data.items():
                for y, v in d.items():
                    us.setdefault(y, []).append(v)
            state["series"]["yrbs_us_median_current_alcohol"] = [[f"{y}-07-01", round(sorted(v)[len(v) // 2], 2)] for y, v in sorted(us.items()) if len(v) >= 10]
            state["dose"]["cannabis_youth_alcohol"] = {**dose_response(data), "source": f"CDC YRBS state surveys ({src['dataset']}), question: {src['question']}"}
            print(json.dumps({k: v for k, v in state["dose"]["cannabis_youth_alcohol"].items() if k not in ("rows", "pretrend_rows", "points")}, indent=1), flush=True)
        else:
            state["yrbs"] = {"result": "no usable dataset found"}
        for key, bo in (("cannabis_young_adult_alcohol", "18-24"), ("cannabis_adult_alcohol", "Overall")):
            data, src = brfss_drinking(bo)
            if not data:
                state["dose"][key] = {"result": "no usable BRFSS table"}
                continue
            for st in ("US", "UW", "GU", "PR", "VI"):
                data.pop(st, None)
            us = {}
            for st, d in data.items():
                for y, v in d.items():
                    us.setdefault(y, []).append(v)
            state["series"][f"brfss_median_current_drinking_{bo.replace('-', '_').lower()}"] = [[f"{y}-07-01", round(sorted(v)[len(v) // 2], 2)] for y, v in sorted(us.items()) if len(v) >= 10]
            state["dose"][key] = {**dose_response(data), "source": f"CDC BRFSS state prevalence ({src['dataset']}), {src['break_out']}: {src['question']}"}
            print(key, json.dumps({k: v for k, v in state["dose"][key].items() if k not in ("rows", "pretrend_rows", "points")}, indent=1), flush=True)
        pts, u = niaaa()
        if pts:
            state["series"]["niaaa_percapita_ethanol"] = pts
            state["niaaa_source"] = u
    except mf.Stop as e:
        state["stopped"] = str(e); print("stopped:", e, flush=True)
    json.dump(state, open(OUT, "w"), ensure_ascii=False, indent=0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
