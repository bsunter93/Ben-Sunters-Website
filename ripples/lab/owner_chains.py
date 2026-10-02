"""Owner chains v1: deterministic checks of five owner-supplied ripple chains (Oct 2, 2026).

For every step that has a measurable Wikipedia article, find the first sustained rise (editor_trail.onset: 7-day
mean above median + 5 MAD, 1.5x the median and +20 views, for 5 days running, at least a fifth of the way to the
window's peak) between `start` and `end`, and compare it with the step's reference date (the ordering rule, ledger
1497: a step must start on or after the step before it). Articles created inside the window have no baseline; for
them the first recorded day and the first week at 20% of the window's peak are reported instead. Anonymous, honest
UA, 1 s apart, stop on refusal. Output: ripples/docs/results/owner_chains_v1.json.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import editor_trail as et  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "results", "owner_chains_v1.json")
# (chain, step, label, articles, reference date and what it is, search window)
TESTS = [
    ("tiger-king", 2, "Attention to the Big Cat Public Safety Act", ["Big Cat Public Safety Act"],
     ("2020-03-20", "Tiger King release"), ("2020-02-01", "2023-03-01")),
    ("tiger-king", 2, "Attention to exotic pets", ["Exotic pet"], ("2020-03-20", "Tiger King release"), ("2020-02-15", "2020-08-01")),
    ("tiger-king", 5, "Attention to big-cat sanctuaries", ["Big Cat Rescue", "Turpentine Creek Wildlife Refuge"],
     ("2022-12-20", "Big Cat Act signed"), ("2022-11-01", "2024-06-01")),
    ("pokemon-go", 1, "Attention to Pokémon Go", ["Pokémon Go"], ("2016-07-06", "US launch"), ("2016-06-20", "2016-09-01")),
    ("pokemon-go", 3, "Attention to augmented reality", ["Augmented reality"], ("2016-07-06", "US launch"), ("2016-06-20", "2016-10-01")),
    ("wordle", 2, "Attention to Wordle (the viral spread)", ["Wordle"], ("2021-10-01", "public release, Oct 2021"), ("2021-10-15", "2022-03-01")),
    ("wordle", 4, "Attention to Wordle spin-offs", ["Quordle", "Heardle", "Worldle", "Nerdle", "Absurdle", "Dordle", "Octordle", "Semantle"],
     ("2022-01-31", "NYT acquisition"), ("2021-12-01", "2022-06-01")),
    ("barbie", 1, "Attention to the Barbie film", ["Barbie (film)"], ("2023-07-21", "release"), ("2022-03-01", "2023-09-01")),
    ("barbie", 4, "Attention to Barbiecore", ["Barbiecore"], ("2023-07-21", "release"), ("2022-03-01", "2023-12-01")),
    ("barbie", 4, "Attention to the color pink", ["Pink"], ("2023-07-21", "release"), ("2023-03-01", "2023-10-01")),
    ("jwst", 2, "Attention to the James Webb Space Telescope", ["James Webb Space Telescope"], ("2022-07-11", "first image"), ("2022-06-15", "2022-09-01")),
    ("jwst", 2, "Attention to astronomy", ["Astronomy", "Galaxy", "Universe"], ("2022-07-11", "first image"), ("2022-06-15", "2022-09-01")),
    ("gamestop", 1, "Attention to the GameStop squeeze", ["GameStop short squeeze", "GameStop"], ("2021-01-13", "first big jump"), ("2020-12-15", "2021-03-01")),
    ("gamestop", 3, "Attention to payment for order flow", ["Payment for order flow"], ("2021-01-28", "Robinhood buy restrictions"), ("2021-01-01", "2021-04-01")),
    ("gamestop", 4, "Attention to options", ["Option (finance)", "Call option"], ("2021-01-28", "Robinhood buy restrictions"), ("2021-01-01", "2021-04-01")),
    ("covid-remote", 1, "Attention to remote work", ["Remote work"], ("2020-03-13", "US national emergency"), ("2020-02-01", "2020-05-01")),
    ("covid-remote", 2, "Attention to Zoom towns", ["Zoom town"], ("2020-03-13", "US national emergency"), ("2020-03-01", "2022-01-01")),
]
ARXIV = "http://export.arxiv.org/api/query?search_query={q}&max_results=0"
ZHVI = "https://files.zillowstatic.com/research/public_csvs/zhvi/Metro_zhvi_uc_sfrcondo_tier_0.33_0.67_sm_sa_month.csv"
ZOOM = ["Boise City, ID", "Bozeman, MT", "Bend, OR", "Coeur d'Alene, ID", "Austin, TX", "Knoxville, TN", "Asheville, NC"]
HUBS = ["United States", "San Francisco, CA", "New York, NY", "San Jose, CA"]


def arxiv():
    """astro-ph submissions per month, all and those mentioning JWST in the abstract (arXiv API, 3 s apart)."""
    import re, time, urllib.parse, urllib.request
    out = {}
    for y in range(2019, 2025):
        for m in range(1, 13):
            a = f"{y}{m:02d}010000"
            b = f"{y + (m == 12)}{(m % 12) + 1:02d}010000"
            row = {}
            for k, q in (("all", f"cat:astro-ph* AND submittedDate:[{a} TO {b}]"),
                         ("jwst", f"cat:astro-ph* AND (abs:JWST OR abs:\"James Webb\") AND submittedDate:[{a} TO {b}]")):
                req = urllib.request.Request(ARXIV.format(q=urllib.parse.quote(q)), headers={"User-Agent": et.UA})
                try:
                    with urllib.request.urlopen(req, timeout=60) as r:
                        t = r.read().decode()
                    row[k] = int(re.search(r"<opensearch:totalResults[^>]*>(\d+)<", t).group(1))
                except Exception as e:  # noqa: BLE001
                    row[k] = None
                    print("arxiv", y, m, str(e)[:80], flush=True)
                time.sleep(3)
            out[f"{y}-{m:02d}"] = row
    return out


def zillow():
    import csv, io, urllib.request
    req = urllib.request.Request(ZHVI, headers={"User-Agent": et.UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        rows = list(csv.DictReader(io.StringIO(r.read().decode())))
    out = {}
    for row in rows:
        if row["RegionName"] in ZOOM + HUBS:
            ms = sorted(k for k in row if k[:2] == "20" and "2017-01" <= k <= "2023-12")
            v = {k[:7]: float(row[k]) for k in ms if row[k]}
            yoy = {k: round(100 * (v[k] / v[j] - 1), 1) for k in v for j in [f"{int(k[:4]) - 1}{k[4:7]}"] if j in v}
            out[row["RegionName"]] = {"zhvi": v, "yoy": yoy}
    return out


def idx(d):
    return (dt.date.fromisoformat(d) - et.DAY0).days


def run(articles, start, end):
    endd = dt.date.fromisoformat(end)
    per, v = {}, None
    for a in articles:
        s = et.series(a, endd)
        per[a] = bool(s)
        if s:
            x = et.to_array(s, endd)
            v = x if v is None else np.where(np.isnan(v), 0, v) + np.where(np.isnan(x), 0, x)
    if v is None:
        return {"found": per, "result": "no article"}
    i0, i1 = idx(start), idx(end)
    hi = i1 - i0 - 8
    w = et.trail7(v)
    peak_i = i0 + int(np.argmax(w[i0:i1]))
    out = {"found": per, "peak_week": (et.DAY0 + dt.timedelta(days=peak_i - 6)).isoformat(),
           "weekly": [[(et.DAY0 + dt.timedelta(days=k)).isoformat(), int(np.nan_to_num(v[k:k + 7]).sum())]
                      for k in range(i0, i1 - 6, 7)]}
    f = et.onset(v, i0, 0, hi)
    if f:
        out.update(onset=(et.DAY0 + dt.timedelta(days=f[0])).isoformat(), ratio=round(f[1], 1), baseline=round(f[2], 1))
    elif et.valid(v, i0):
        out["result"] = "no sustained rise in the window"
    else:
        first = int(np.flatnonzero(~np.isnan(v))[0])
        pk = float(w[i0:i1].max())
        k20 = next(k for k in range(max(first, i0), i1) if w[k] >= 0.2 * pk)
        out.update(created=(et.DAY0 + dt.timedelta(days=first)).isoformat(),
                   onset=(et.DAY0 + dt.timedelta(days=k20)).isoformat(), onset_kind="first week at 20% of peak (new article)")
    return out


def main() -> int:
    rep = {"protocol": "ripples/lab/owner_chains.py", "tests": []}
    for chain, step, label, arts, (ref, ref_what), (a, b) in TESTS:
        try:
            r = run(arts, a, b)
        except et.Stop as e:
            rep["stopped"] = str(e)
            break
        r.update(chain=chain, step=step, label=label, ref=ref, ref_what=ref_what)
        if r.get("onset"):
            lag = (dt.date.fromisoformat(r["onset"]) - dt.date.fromisoformat(ref)).days
            r.update(lag_days=lag, order_ok=lag >= 0)
        rep["tests"].append(r)
        print(chain, step, label, {k: r.get(k) for k in ("found", "onset", "onset_kind", "created", "lag_days", "order_ok", "ratio", "peak_week", "result")}, flush=True)
    for k, f in (("zillow", zillow), ("arxiv", arxiv)):
        try:
            rep[k] = f()
        except Exception as e:  # noqa: BLE001
            rep[k] = {"error": str(e)[:200]}
        print(k, "done", flush=True)
    json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
