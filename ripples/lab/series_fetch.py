"""Official series and a dose-response design, fetched in CI (ripples/docs/dose_response_v1.md).

1. CDC YRBS state surveys: share of high-school students who drank alcohol in the past 30 days, by state and year,
   found by Socrata catalog search (the dataset id is not hard-coded; the probe logs what it found).
2. Dose-response: legal recreational cannabis (retail start, by state) against the change in youth drinking,
   difference-in-differences with staggered adoption, permutation inference, pre-trend check.
3. NIAAA apparent per-capita ethanol consumption, if its text file is reachable.
Writes ripples/docs/results/series_v1.json. Honest UA, 1 s between requests, stop on refusal.
"""
from __future__ import annotations

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
def find_yrbs():
    """Candidate Socrata datasets on CDC domains whose name says YRBS; returns [(domain, id, name)]."""
    out = []
    for domain in ("data.cdc.gov", "chronicdata.cdc.gov"):
        q = urllib.parse.urlencode({"domains": domain, "q": "Youth Risk Behavior Surveillance", "limit": 20})
        d = jget(f"https://api.us.socrata.com/api/catalog/v1?{q}")
        for r in (d or {}).get("results", []):
            res = r.get("resource", {})
            if res.get("type") == "dataset":
                out.append((domain, res.get("id"), res.get("name"), [c.lower() for c in res.get("columns_field_name", [])]))
    return out


def yrbs_alcohol():
    """{state: {year: prevalence}} for current alcohol use, high school, total; plus a note on the source."""
    cands = find_yrbs()
    print("YRBS candidates:", [(c[0], c[1], c[2][:60]) for c in cands], flush=True)
    for domain, sid, name, cols in cands:
        need = {"year", "locationabbr", "data_value"}
        if not need <= set(cols):
            continue
        qcol = "question" if "question" in cols else "questioncode" if "questioncode" in cols else None
        if not qcol:
            continue
        where = f"upper({qcol}) like '%ALCOHOL%'"
        if "stratificationcategory1" in cols:
            where += " AND stratificationcategory1='Total'"
        elif "sex" in cols:
            where += " AND sex='Total'"
        params = {"$where": where, "$select": f"locationabbr,year,{qcol},data_value", "$limit": 50000}
        rows = jget(f"https://{domain}/resource/{sid}.json?{urllib.parse.urlencode(params)}")
        if not rows:
            print("no rows from", sid, flush=True)
            continue
        qs = sorted({r.get(qcol) for r in rows})
        print("questions:", qs[:12], flush=True)
        # the current-drinking question, not binge, not first drink, not ever
        pick = next((q for q in qs if re.search(r"currently drank|current(?:ly)? alcohol|drank alcohol.*(?:30|past month)|had at least one drink", q or "", re.I)
                     and not re.search(r"binge|first|before age|ever|5 or more|4 or more", q or "", re.I)), None)
        if not pick:
            print("no current-drinking question in", sid, flush=True)
            continue
        out = {}
        for r in rows:
            if r.get(qcol) != pick or not r.get("data_value"):
                continue
            st, y = r["locationabbr"], int(str(r["year"])[:4])
            try:
                out.setdefault(st, {})[y] = float(r["data_value"])
            except ValueError:
                pass
        if len(out) >= 20:
            return out, {"domain": domain, "dataset": sid, "name": name, "question": pick}
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
    for u in NIAAA_URLS:
        t = mf.get(u)
        if not t or len(t) < 500:
            continue
        pts = []
        for line in t.splitlines():
            m = re.match(r"\s*(\d{4})\s+([\d.]+)", line)
            if m and 1900 < int(m.group(1)) < 2100:
                pts.append([f"{m.group(1)}-01-01", float(m.group(2))])
        if len(pts) > 30:
            print("NIAAA from", u, len(pts), "years", flush=True)
            return pts, u
    print("NIAAA file not reachable at the known paths", flush=True)
    return None, None


def main() -> int:
    state = json.load(open(OUT)) if os.path.exists(OUT) else {"protocol": "ripples/docs/dose_response_v1.md", "started": dt.date.today().isoformat(), "series": {}, "dose": {}}
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
            state["series"]["yrbs_us_median_current_alcohol"] = [[f"{y}-07-01", round(sorted(v)[len(v) // 2], 2)] for y, v in sorted(us.items())]
            state["dose"]["cannabis_youth_alcohol"] = {**dose_response(data), "source": f"CDC YRBS state surveys ({src['dataset']}), question: {src['question']}"}
            print(json.dumps({k: v for k, v in state["dose"]["cannabis_youth_alcohol"].items() if k not in ("rows", "pretrend_rows", "points")}, indent=1), flush=True)
        else:
            state["yrbs"] = {"result": "no usable dataset found"}
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
