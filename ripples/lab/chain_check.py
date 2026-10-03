"""Chain check v1: deterministic, step-by-step checks of supplied ripple chains (ripples/chains/*.json).

Every step is one of:
  wiki    daily Wikipedia views of one or more articles. Sustained onset (editor_trail.onset) searched from 30 days
          before the reference date; specificity against the article's own history (every 14th day a pseudo-event,
          p = (1 + hits) / (1 + N)). New articles (no baseline) report their first recorded day instead.
  fred    a FRED series (fredgraph.csv, no key); stackex: monthly Stack Overflow question counts (Stack Exchange
          API, no key); zillow: Zoom-town minus US home-value growth; arxiv: monthly astro-ph submissions. All go through
          the same series test: effect = mean of the next h periods minus mean of the previous h periods (log or level),
          in the claimed direction, against every other admissible date as a placebo; onset = first period from 2h
          before the reference where the series leaves its pre-trend (linear fit on the 4h periods before that) by more
          than 2 residual SDs for 2 periods running.
  ssa     annual US baby-name counts (from ripples.att_e9_names, supplied inline): the year's log change against
          every other year's.
  wayback the earliest Wayback Machine capture of a URL (CDX API): the thing was online by that date. An upper bound on
          when it began; ordered like a timed step. Options: url, matchType (exact|prefix), from (YYYY).
  record  a dated public record with a source. Not measured by us.
  none    not testable with free data, with the reason; an optional "range" places the claim at its midpoint.
Ordering rule (ledger 1497): each step's reference date is the previous counted step's date (onset or record),
starting from the event date. A step that moved but began before its reference is "wrong order".
Anonymous, honest UA, polite spacing, stop on refusal. Output: ripples/docs/results/chain_check_v1.json.
"""
from __future__ import annotations

import csv
import datetime as dt
import glob
import io
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import editor_trail as et  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "docs", "results", "chain_check_v1.json")
UA = et.UA


def fetch(url, delay=1.0, raw=False):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "identity"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            body = r.read()
    except urllib.error.HTTPError as e:
        if e.code in (403, 429, 503):
            raise et.Stop(f"HTTP {e.code} at {url[:60]}")
        return None
    except Exception:  # noqa: BLE001
        return None
    finally:
        time.sleep(delay)
    return body if raw else body.decode("utf-8", "replace")


D = lambda s: dt.date.fromisoformat(s)  # noqa: E731


# ---------- sources ----------
def fred(sid):
    t = fetch(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={sid}")
    if not t or "," not in t:
        return None
    rows = list(csv.reader(io.StringIO(t)))[1:]
    out = [(D(r[0]), float(r[1])) for r in rows if len(r) > 1 and r[1] not in (".", "")]
    return out or None


def stackex(a="2018-01", b="2025-06"):
    out = []
    y, m = map(int, a.split("-"))
    while f"{y}-{m:02d}" <= b:
        y2, m2 = (y + 1, 1) if m == 12 else (y, m + 1)
        f = int(dt.datetime(y, m, 1, tzinfo=dt.timezone.utc).timestamp())
        g = int(dt.datetime(y2, m2, 1, tzinfo=dt.timezone.utc).timestamp())
        t = fetch(f"https://api.stackexchange.com/2.3/questions?site=stackoverflow&fromdate={f}&todate={g}&filter=total", 1.5)
        if t:
            out.append((dt.date(y, m, 1), float(json.loads(t)["total"])))
        y, m = y2, m2
    return out or None


ZHVI = "https://files.zillowstatic.com/research/public_csvs/zhvi/Metro_zhvi_uc_sfrcondo_tier_0.33_0.67_sm_sa_month.csv"


def zillow(towns):
    t = fetch(ZHVI)
    if not t:
        return None
    rows = {r["RegionName"]: r for r in csv.DictReader(io.StringIO(t))}
    us = rows.get("United States")
    ms = sorted(k for k in us if re.match(r"\d{4}-\d{2}-\d{2}", k))
    out = []
    for k in ms:
        j = f"{int(k[:4]) - 1}{k[4:]}"
        if j not in us or not us[k] or not us[j]:
            continue
        gs = [100 * (float(rows[c][k]) / float(rows[c][j]) - 1) for c in towns if c in rows and rows[c].get(k) and rows[c].get(j)]
        if gs:
            out.append((D(k[:7] + "-01"), float(np.mean(gs)) - 100 * (float(us[k]) / float(us[j]) - 1)))
    return out or None


def arxiv(a=2017, b=2024):
    """A refusal from arXiv (503 means 'retry later') stops calls to arXiv only; the step reports no data."""
    try:
        return _arxiv(a, b)
    except et.Stop as e:
        print("arxiv refused:", e, flush=True)
        return None


def _arxiv(a, b):
    out = []
    for y in range(a, b + 1):
        for m in range(1, 13):
            s, e = f"{y}{m:02d}010000", f"{y + (m == 12)}{m % 12 + 1:02d}010000"
            q = urllib.parse.quote(f"cat:astro-ph* AND submittedDate:[{s} TO {e}]")
            t = fetch(f"http://export.arxiv.org/api/query?search_query={q}&max_results=0", 3.0)
            n = re.search(r"totalResults[^>]*>(\d+)<", t or "")
            if n:
                out.append((dt.date(y, m, 1), float(n.group(1))))
    return out or None


def wayback_first(url, match="exact", frm=None):
    """Earliest 200 capture of a URL in the Wayback Machine, as YYYY-MM-DD, or None."""
    q = {"url": url, "output": "json", "limit": 1, "fl": "timestamp,statuscode", "filter": "statuscode:200", "matchType": match}
    if frm:
        q["from"] = frm
    t = fetch(f"https://web.archive.org/cdx/search/cdx?{urllib.parse.urlencode(q)}", delay=1.5)
    try:
        rows = json.loads(t or "[]")
        ts = rows[1][0] if len(rows) > 1 else None
    except (ValueError, IndexError):
        ts = None
    return f"{ts[:4]}-{ts[4:6]}-{ts[6:8]}" if ts and len(ts) >= 8 else None


# ---------- tests ----------
def series_test(pts, ref, direction, h, transform):
    dates = [d for d, _ in pts]
    y = np.array([math.log(v) if transform == "log" and v > 0 else v for _, v in pts], dtype=float)
    # the reference period is the one that contains the reference date (a monthly point dated the 1st covers its month)
    r = max((i for i, d in enumerate(dates) if d <= ref), default=None)
    if r is None or r < 4 * h + 2 * h or r + h > len(y):
        return {"result": "not enough data around the reference date"}
    s = 1 if direction == "up" else -1

    def eff(i):
        return float(y[i:i + h].mean() - y[i - h:i].mean()) if i - h >= 0 and i + h <= len(y) else None
    obs = eff(r)
    pool = [eff(i) for i in range(h, len(y) - h + 1) if abs(i - r) > 2 * h and eff(i) is not None]
    p = (1 + sum(1 for x in pool if s * x >= s * obs)) / (1 + len(pool))
    # onset: leave the pre-trend by > 2 residual SDs for 2 periods, searched from 2h before the reference
    a = r - 2 * h
    xs = np.arange(a - 4 * h, a)
    coef = np.polyfit(xs, y[a - 4 * h:a], 1)
    sd = float(np.std(y[a - 4 * h:a] - np.polyval(coef, xs))) or 1e-9
    dev = s * (y - np.polyval(coef, np.arange(len(y)))) / sd
    period = int(np.median(np.diff([d.toordinal() for d in dates])))
    run, thr = (3, 2.5) if period <= 7 else (2, 2.0)  # daily and weekly data are noisier: a longer, larger departure
    on = next((i for i in range(a, min(len(y) - run + 1, r + 3 * h)) if all(dev[i + k] > thr for k in range(run))), None)
    show = [[d.isoformat(), round(float(v), 3)] for d, v in pts[max(0, r - 6 * h):r + 4 * h]]
    return {"effect": round(obs, 4), "p": round(p, 3), "n_placebo": len(pool), "period_days": period,
            "onset": dates[on].isoformat() if on is not None else None, "points": show}


def wiki_test(articles, ref, lag=150):
    end = min(ref + dt.timedelta(days=lag + 30), dt.date.today() - dt.timedelta(days=2))
    v, found = None, {}
    for a in articles:
        s = et.series(a, end)
        found[a] = bool(s)
        if s:
            x = et.to_array(s, end)
            v = x if v is None else np.nan_to_num(v) + np.nan_to_num(x)
    if v is None:
        return {"found": found, "result": "no article"}
    ri = (ref - et.DAY0).days
    weekly = [[(et.DAY0 + dt.timedelta(days=k)).isoformat(), int(np.nan_to_num(v[k:k + 7]).sum())]
              for k in range(max(0, ri - 84), len(v) - 6, 7)]
    if not et.valid(v, ri - 30):
        first = int(np.flatnonzero(~np.isnan(v))[0])
        return {"found": found, "new_article": (et.DAY0 + dt.timedelta(days=first)).isoformat(), "weekly": weekly,
                "onset": (et.DAY0 + dt.timedelta(days=first)).isoformat()}
    f = et.onset(v, ri - 30, 0, min(lag, len(v) - ri - 8))
    if not f:
        return {"found": found, "result": "no sustained rise", "weekly": weekly}
    i, ratio, med = f
    hits = n = 0
    for e in range(130, ri - 200, 14):
        if et.valid(v, e):
            n += 1
            g = et.onset(v, e, 0, lag)
            hits += bool(g and g[1] >= ratio)
    return {"found": found, "onset": (et.DAY0 + dt.timedelta(days=i)).isoformat(), "ratio": round(ratio, 1),
            "baseline": round(med, 1), "p": round((1 + hits) / (1 + n), 3) if n >= 20 else None, "weekly": weekly}


def ssa_test(counts, year):
    ys = sorted(int(k) for k in counts)
    ch = {y: math.log(counts[str(y)] / counts[str(y - 1)]) for y in ys if str(y - 1) in counts}
    obs = ch.get(year)
    pool = [v for y, v in ch.items() if y != year]
    p = (1 + sum(1 for v in pool if v >= obs)) / (1 + len(pool))
    return {"effect": round(obs, 3), "p": round(p, 3), "n_placebo": len(pool), "onset": f"{year}-01-01",
            "points": [[f"{y}-01-01", counts[str(y)]] for y in ys]}


CACHE: dict = {}


def run_step(st, ref):
    t = st["test"]
    k = t["type"]
    if k == "record":
        return {"onset": t["date"], "source": t.get("source")}
    if k == "none":  # an undated claim with an approximate range is placed at the range's midpoint
        if st.get("range"):
            a, b = D(st["range"][0]), D(st["range"][1])
            return {"reason": t["reason"], "range": st["range"], "onset": (a + (b - a) / 2).isoformat(), "approx": True}
        return {"reason": t["reason"]}
    if k == "wiki":
        return wiki_test(t["articles"], ref, t.get("lag", 150))
    if k == "wayback":
        d = wayback_first(t["url"], t.get("matchType", "exact"), t.get("from"))
        return {"onset": d, "archive_first": d, "url": t["url"]} if d else {"result": "no capture found"}
    if k == "ssa":
        return ssa_test(t["counts"], t["year"])
    key = (k, json.dumps(t.get("id") or t.get("towns") or ""))
    if key not in CACHE:
        CACHE[key] = {"fred": lambda: fred(t["id"]), "stackex": stackex, "zillow": lambda: zillow(t["towns"]),
                      "arxiv": arxiv}[k]()
    pts = CACHE[key]
    if not pts:
        return {"result": f"no data for {t.get('id', k)}"}
    r = series_test(pts, ref, t.get("direction", "up"), t.get("h", 3), t.get("transform", "log"))
    r["series"] = t.get("id", k)
    return r


def verdict(st, r, ref):
    k = st["test"]["type"]
    if k == "none":
        return st["test"].get("verdict", "not testable")
    if k == "record":
        return "reported" if D(r["onset"]) >= ref else "reported, before the step it is said to follow"
    if r.get("result"):
        return "no movement" if "rise" in r["result"] else "no data"
    if r.get("new_article"):
        return "timed (new article)" if D(r["onset"]) >= ref - dt.timedelta(days=3) else "wrong order"
    if r.get("archive_first"):
        return "timed (online by)" if D(r["onset"]) >= ref - dt.timedelta(days=3) else "wrong order"
    if r.get("p") is None and r.get("onset"):  # a sustained rise, but too little history for a placebo test
        return "timed (short history)" if D(r["onset"]) >= ref - dt.timedelta(days=3) else "wrong order"
    moved = r.get("p") is not None and r["p"] <= 0.05
    if not moved:
        return "no movement"
    tol = max(3, r.get("period_days", 0))  # a monthly point dated the 1st covers the whole month
    if r.get("onset") and D(r["onset"]) < ref - dt.timedelta(days=tol):
        return "moved, wrong order"
    return "measured"


def main() -> int:
    rep = {"protocol": "ripples/lab/chain_check.py", "run": dt.date.today().isoformat(), "chains": []}
    try:
        for path in sorted(glob.glob(os.path.join(ROOT, "chains", "*.json"))):
            for ch in json.load(open(path)):
                ref = D(ch["date"])
                out = {k: ch.get(k) for k in ("slug", "title", "date", "batch", "vertical")}
                out["steps"] = []
                onsets = {}
                for st in ch["steps"]:
                    # a step follows the step named in "after" (or the event itself for a branch), else the main chain's latest step
                    if st.get("ref"):
                        sref = D(st["ref"])
                    elif st.get("after"):
                        sref = onsets.get(st["after"], D(ch["date"]))
                    else:
                        sref = D(ch["date"]) if st.get("branch") else ref
                    try:
                        r = run_step(st, sref)
                    except et.Stop:
                        raise
                    except Exception as e:  # noqa: BLE001
                        r = {"result": f"error: {str(e)[:120]}"}
                    v = verdict(st, r, sref)
                    out["steps"].append({"n": st["n"], "claim": st["claim"], "test": {k: st["test"][k] for k in st["test"] if k != "counts"},
                                         "ref": sref.isoformat(), "verdict": v, "note": st.get("note"),
                                         "link": st.get("link"), "link_why": st.get("link_why"), "branch": st.get("branch", False),
                                         "vertical": st.get("vertical"), "after": st.get("after"), "slice": st.get("slice"), "short": st.get("short"), "mark": st.get("mark"), **r})
                    print(ch["slug"], st["n"], v, {k: r.get(k) for k in ("onset", "p", "effect", "series", "found", "result")}, flush=True)
                    if v in ("measured", "reported", "timed (short history)") and r.get("onset"):
                        onsets[st["n"]] = D(r["onset"])
                    if v in ("measured", "reported", "timed (short history)") and r.get("onset") and not st.get("branch") and not st.get("after"):
                        # a new article's creation date dates the article, not the phenomenon: it does not move the reference
                        ref = max(ref, D(r["onset"]))
                rep["chains"].append(out)
                json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    except et.Stop as e:
        rep["stopped"] = str(e)
    json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
