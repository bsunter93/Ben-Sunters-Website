"""Sensors v1 analysis (ripples/docs/sensors_plan_v1.md): the checker's attention test applied to independent sensors,
the convergence rule, decoy-date calibration and catalyst detection.

Inputs: ripples/lab/sensors_queries_v1.json (the registered queries), ripples/docs/results/sensors_mediacloud_v1.json
(Media Cloud daily counts, written by the workflow), GDELT DOC and TV daily counts when present
(ripples/docs/results/sensors_gdelt_v1.json, written by sensors_gdelt.py), Wikipedia pageviews for catalyst entities
(fetched here, honest agent, 1 request a second, cached), and the hand check of catalyst candidates
(ripples/lab/sensors_handcheck_v1.json). Output: ripples/docs/results/sensors_v1.json.

The test is chain_check.wiki_test with editor_trail.onset on each sensor's daily share of its own volume, with a raw
floor in place of Wikipedia's +20 views (3 items a day for news, 2 clips for television), a 90% valid-baseline rule for
outage days, and a sparse-baseline rule that mirrors the checker's new-article rule. See the plan, section 4.
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
import zlib

import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
REG = os.path.join(ROOT, "lab", "sensors_queries_v1.json")
MC = os.path.join(ROOT, "docs", "results", "sensors_mediacloud_v1.json")
GD = os.path.join(ROOT, "docs", "results", "sensors_gdelt_v1.json")
HAND = os.path.join(ROOT, "lab", "sensors_handcheck_v1.json")
OUT = os.path.join(ROOT, "docs", "results", "sensors_v1.json")
WCACHE = os.environ.get("WIKI_CACHE") or os.path.join(ROOT, "..", ".cache_sensors_wiki")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
D = dt.date.fromisoformat
FLOOR = {"doc": 3.0, "mc": 3.0, "tv": 2.0}
PASS = "beyond chance in order"
SCAN_FROM, SCAN_TO = dt.date(2017, 1, 1), dt.date(2026, 9, 30)
SPAN_FROM = {"A": dt.date(2015, 7, 1), "A2": dt.date(2015, 7, 1), "C": dt.date(2015, 7, 1), "D": dt.date(2009, 7, 2)}
UNTESTABLE = ("not run", "not testable: no coverage for the baseline", "not testable: window runs past the data")


# ---------------------------------------------------------------- series
class Series:
    """A daily series: raw matching count, the day's total volume, and the share; NaN where the source has no coverage."""

    def __init__(self, first: dt.date, raw, total, unit_scale=1.0):
        self.first = first
        self.raw = np.asarray(raw, dtype=float)
        self.total = np.asarray(total, dtype=float)
        n = len(self.raw)
        # outage days: total under a quarter of the 28-day rolling median total, or no total at all
        med = np.full(n, np.nan)
        t = self.total
        for i in range(n):
            w = t[max(0, i - 14):i + 14]
            w = w[~np.isnan(w) & (w > 0)]
            med[i] = np.median(w) if w.size else np.nan
        bad = np.isnan(t) | (t <= 0) | np.isnan(med) | (t < 0.25 * med) | np.isnan(self.raw)
        self.raw[bad] = np.nan
        self.total[bad] = np.nan
        self.share = np.where(bad, np.nan, self.raw / np.where(bad, 1, self.total)) * unit_scale
        self.unit_scale = unit_scale
        ok = np.flatnonzero(~bad)
        self.start = int(ok[0]) if ok.size else None
        self.end = int(ok[-1]) if ok.size else None

    def idx(self, d: dt.date) -> int:
        return (d - self.first).days

    def date(self, i: int) -> str:
        return (self.first + dt.timedelta(days=int(i))).isoformat()

    def __len__(self):
        return len(self.raw)

    def window(self, a: dt.date, b: dt.date) -> "Series":
        """The same series cut to the days a..b (the catalyst scan's span), outage rule recomputed on the cut."""
        i, j = max(0, self.idx(a)), min(len(self), self.idx(b) + 1)
        tot = self.total.copy()
        raw = self.raw.copy()
        return Series(self.first + dt.timedelta(days=i), raw[i:j], tot[i:j], self.unit_scale)


def trail(x, k=7, minp=4):
    ok = ~np.isnan(x)
    c = np.concatenate([[0.0], np.cumsum(np.where(ok, x, 0.0))])
    m = np.concatenate([[0], np.cumsum(ok)])
    out = np.full(len(x), np.nan)
    if len(x) >= k:
        s = c[k:] - c[:-k]
        n = m[k:] - m[:-k]
        out[k - 1:] = np.where(n >= minp, s / np.maximum(n, 1), np.nan)
    return out


def valid(S: Series, e: int) -> bool:
    if e - 120 < 0 or e - 14 > len(S):
        return False
    seg = S.share[e - 120:e - 14]
    return seg.size == 106 and np.mean(~np.isnan(seg)) >= 0.9


def onset(S: Series, e: int, lo: int, hi: int, floor: float, cache=None):
    """editor_trail.onset on the share, with the raw floor. Returns (index, ratio, median share) or None."""
    if not valid(S, e) or e + hi + 7 > len(S):
        return None
    pre = S.share[e - 120:e - 14]
    pre = pre[~np.isnan(pre)]
    med = float(np.median(pre))
    mad = 1.4826 * float(np.median(np.abs(pre - med)))
    rp = S.raw[e - 120:e - 14]
    rawmed = float(np.median(rp[~np.isnan(rp)]))
    tp = S.total[e - 120:e - 14]
    unit = S.unit_scale / float(np.median(tp[~np.isnan(tp)]))  # the share of one item on a median day
    if cache is None:
        w, wr = trail(S.share), trail(S.raw)
    else:
        w, wr = cache
    seg = w[e + lo:e + hi + 7]
    if np.all(np.isnan(seg)):
        return None
    peak = float(np.nanmax(seg))
    thr = max(med + 5 * mad, 1.5 * med, med + 0.2 * (peak - med))
    run = 0
    for i in range(e + lo, e + hi + 1):
        run = run + 1 if (w[i] > thr and wr[i] > rawmed + floor) else 0
        if run >= 5:
            return i - 4, peak / max(med, unit), med
    return None


def sparse(S: Series, e: int) -> bool:
    seg = S.raw[max(0, e - 14 - 365):e - 14]
    return int(np.sum(seg[~np.isnan(seg)] > 0)) < 5


def step_test(S: Series | None, ref: dt.date, lag: int, floor: float, cache=None) -> dict:
    """chain_check.wiki_test on one sensor's series."""
    if S is None or S.start is None:
        return {"verdict": "not run"}
    ri = S.idx(ref)
    e = ri - 30
    if cache is None:
        cache = (trail(S.share), trail(S.raw))
    if not valid(S, e):
        return {"verdict": "not testable: no coverage for the baseline", "coverage_from": S.date(S.start)}
    hi = min(lag + 30, len(S) - e - 8)
    if hi < 30 or (S.end is not None and S.end < ri + min(lag, 14)):
        return {"verdict": "not testable: window runs past the data", "coverage_to": S.date(S.end)}
    out = {"coverage_from": S.date(S.start), "sparse": sparse(S, e)}
    raw = np.nan_to_num(S.raw)
    out["weekly"] = [[S.date(k), int(raw[k:k + 7].sum())] for k in range(max(0, ri - 84), min(len(S) - 6, ri + lag + 1), 7)]
    pre = S.raw[e - 120:e - 14]
    out["baseline_raw_median"] = float(np.median(pre[~np.isnan(pre)]))
    f = onset(S, e, 0, hi, floor, cache)
    if not f:
        out["verdict"] = "no sustained rise"
        return out
    i, ratio, med = f
    od = S.first + dt.timedelta(days=int(i))
    out.update({"onset": od.isoformat(), "ratio": round(ratio, 1), "baseline_share": med})
    in_order = od >= ref - dt.timedelta(days=3)
    if out["sparse"]:
        out["verdict"] = "timed (sparse)" if in_order else "wrong order (sparse)"
        return out
    hits = n = 0
    beat = {}
    for e2 in range(130, ri - 200, 14):
        if valid(S, e2):
            n += 1
            g = onset(S, e2, 0, lag + 30, floor, cache)
            if g and g[1] >= ratio:
                hits += 1
                beat[S.date(g[0])] = max(beat.get(S.date(g[0]), 0), round(g[1], 1))
    out["n_placebo"] = n
    out["placebo_hits"] = sorted(beat.items())  # the onsets in the series' own past that matched or beat the step
    out["p"] = round((1 + hits) / (1 + n), 3) if n >= 20 else None
    if out["p"] is None:
        out["verdict"] = "rose, no placebo history" if in_order else "wrong order (no placebo history)"
    elif out["p"] <= 0.05:
        out["verdict"] = PASS if in_order else "moved, wrong order"
    else:
        out["verdict"] = "within chance"
    return out


def decoys(S: Series | None, ref: dt.date, lag: int, floor: float, step_id: str, cache=None) -> list:
    """Five decoy reference dates in the series' own past (plan, section 4), each run through the identical test."""
    if S is None or S.start is None:
        return []
    ri = S.idx(ref)
    lo, hi = S.start + 610, ri - 180
    if hi <= lo:
        return []
    rng = np.random.default_rng(20261004 + zlib.crc32(step_id.encode()))
    picks = sorted(int(x) for x in rng.integers(lo, hi + 1, size=5))
    res = []
    for d in picks:
        r = step_test(S, S.first + dt.timedelta(days=d), lag, floor, cache)
        res.append({"date": S.date(d), "verdict": r["verdict"], "p": r.get("p")})
    return res


# ---------------------------------------------------------------- loaders
def load_mc():
    if not os.path.exists(MC):
        return {}, None
    m = json.load(open(MC))
    tot = {}
    for coll, t in (m.get("totals") or {}).items():
        if isinstance(t, dict) and "first" in t:
            tot[coll] = (D(t["first"]), np.array([np.nan if v is None else v for v in t["totals"]], dtype=float))
    out = {}
    for r in m.get("queries", []):
        if "counts" not in r:
            continue
        first = D(r["first"])
        cnt = np.array([np.nan if v is None else v for v in r["counts"]], dtype=float)
        f0, tarr = tot.get(str(r["collection"]), (None, None))
        if f0 is None:
            continue
        total = np.full(len(cnt), np.nan)
        off = (first - f0).days
        for i in range(len(cnt)):
            j = i + off
            if 0 <= j < len(tarr):
                total[i] = tarr[j]
        out[(r["q"], r["country"])] = Series(first, cnt, total, unit_scale=1e5)
    return out, m


def load_gdelt():
    if not os.path.exists(GD):
        return {}, {}, None
    g = json.load(open(GD))
    doc, tv = {}, {}
    for r in g.get("doc", []):
        if "counts" in r:
            doc[r["q"]] = Series(D(r["first"]), r["counts"], r["totals"], unit_scale=1e5)
    for r in g.get("tv", []):
        if "clips" in r:
            tv[(r["q"], r["country"])] = Series(D(r["first"]), r["clips"], r["totals"], unit_scale=100.0)
    return doc, tv, g


# ---------------------------------------------------------------- Wikipedia (catalyst convergence only)
PV = ("https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/"
      "{t}/daily/20150701/20260930")
WDAY0 = dt.date(2015, 7, 1)
_wstop = []


def wiki_views(title: str):
    os.makedirs(WCACHE, exist_ok=True)
    fn = os.path.join(WCACHE, urllib.parse.quote(title, safe="") + ".json")
    if os.path.exists(fn):
        d = json.load(open(fn))
    else:
        if _wstop:
            return None
        req = urllib.request.Request(PV.format(t=urllib.parse.quote(title.replace(" ", "_"), safe="")), headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                d = json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (401, 403, 429) or e.code >= 500:
                _wstop.append(f"HTTP {e.code}")
                return None
            d = {"items": []}
        except (urllib.error.URLError, TimeoutError, OSError):
            _wstop.append("network")
            return None
        finally:
            time.sleep(1.1)
        json.dump(d, open(fn, "w"))
    n = (dt.date(2026, 9, 30) - WDAY0).days + 1
    v = np.full(n, np.nan)
    for it in d.get("items", []):
        k = it["timestamp"][:8]
        i = (dt.date(int(k[:4]), int(k[4:6]), int(k[6:8])) - WDAY0).days
        if 0 <= i < n:
            v[i] = it["views"]
    ok = np.flatnonzero(~np.isnan(v))
    if not ok.size:
        return None
    v[ok[0]:] = np.nan_to_num(v[ok[0]:])
    return v


def wiki_onset_near(v, day: dt.date, tol=7):
    """editor_trail.onset (its thresholds and +20 views floor) searched within tol days of the news onset."""
    sys.path.insert(0, os.path.dirname(__file__))
    import editor_trail as et  # noqa: E402
    e = (day - WDAY0).days - tol
    if v is None or e - 120 < 0 or e + 2 * tol + 7 > len(v):
        return None
    f = et.onset(v, e, 0, 2 * tol)
    if not f:
        return None
    return {"onset": (WDAY0 + dt.timedelta(days=int(f[0]))).isoformat(), "ratio": round(float(f[1]), 1)}


# ---------------------------------------------------------------- catalyst scan
def scan(S: Series, floor: float):
    """Plan section 7: a scan window every 7th day, onsets within 30 days merged, ratio >= 5, not sparse, and
    p <= 0.01 against the entity's own decoy dates (every 14th day, excluding 60 days around the change)."""
    if S is None or S.start is None:
        return []
    cache = (trail(S.share), trail(S.raw))
    found = []
    for e in range(max(120, S.start + 120), len(S) - 13 - 7, 7):
        f = onset(S, e, 0, 13, floor, cache)
        if f:
            found.append((f[0], f[1], f[2], e))
    found.sort()
    clusters = []
    for x in found:
        if clusters and x[0] - clusters[-1][-1][0] <= 30:
            clusters[-1].append(x)
        else:
            clusters.append([x])
    # decoy-date ratios, computed once per entity
    dec = []
    for e2 in range(130, len(S) - 13 - 7, 14):
        if valid(S, e2):
            g = onset(S, e2, 0, 13, floor, cache)
            dec.append((e2, g[1] if g else 0.0))
    out = []
    for cl in clusters:
        i0 = cl[0][0]
        e0 = cl[0][3]
        ratio = max(x[1] for x in cl)
        sp = sparse(S, e0)
        pool = [r for e2, r in dec if abs(e2 - i0) > 60]
        n = len(pool)
        hits = sum(1 for r in pool if r >= ratio)
        p = round((1 + hits) / (1 + n), 4) if n >= 20 else None
        raw = np.nan_to_num(S.raw)
        cand = {"onset": S.date(i0), "ratio": round(float(ratio), 1), "baseline_share": cl[0][2], "sparse": sp,
                "p": p, "n_decoy_dates": n, "raw_week_before": int(raw[max(0, i0 - 7):i0].sum()),
                "raw_week_after": int(raw[i0:i0 + 7].sum()),
                "weekly": [[S.date(k), int(raw[k:k + 7].sum())] for k in range(max(0, i0 - 56), min(len(S) - 6, i0 + 57), 7)]}
        cand["candidate"] = bool(ratio >= 5 and not sp and p is not None and p <= 0.01)
        out.append(cand)
    return out


# ---------------------------------------------------------------- main
def wiki_pass(it) -> bool:
    w = it.get("wikipedia") or {}
    if it["set"] == "A":
        return it.get("chain_verdict") == "measured"
    if it["set"] == "A2":
        return w.get("verdict") == "attention rose"
    if it["set"] == "C":
        return (w.get("p") or 1) <= 0.05
    return False


def classify(it, wpass, n, t):
    fams = {"W": wpass, "N": n["verdict"] == PASS, "T": t["verdict"] == PASS}
    passed = [k for k, v in fams.items() if v]
    n_ok = n["verdict"] not in UNTESTABLE
    t_ok = t["verdict"] not in UNTESTABLE
    res = {"families_passed": passed, "confirmed": len(passed) >= 2}
    if wpass:
        if res["confirmed"]:
            res["class"] = "confirmed"
        elif n_ok and t_ok:
            res["class"] = "Wikipedia-only"
        elif n_ok or t_ok:
            res["class"] = "partial"
        else:
            res["class"] = "untested"
    else:
        res["class"] = ("measured on " + "+".join(passed)) if passed else "not measured"
    return res


def main() -> int:
    reg = json.load(open(REG))
    mc, mcraw = load_mc()
    doc, tv, graw = load_gdelt()

    def cache_for(S):  # trailing means for one step's own series (each windowed series is a new object)
        return None if S is None else (trail(S.share), trail(S.raw))

    steps = []
    for it in reg["items"]:
        if it["set"] == "E":
            continue
        ref, lag, cty = D(it["ref"]), it["lag"], it["country"]
        S_doc = doc.get(it["q"]["doc"])
        S_mc = mc.get((it["q"]["mc"], cty))
        S_tv = tv.get((it["q"]["tv"], cty)) if it["q"].get("tv") else None
        # a query shared across sets is fetched once over the union of spans; each test reads its own registered span
        # (Jul 1, 2015 on for sets A, A2 and C, matching Wikipedia's history; Jul 2, 2009 on for set D)
        span0 = SPAN_FROM[it["set"]]
        S_mc = S_mc.window(max(span0, S_mc.first), S_mc.first + dt.timedelta(days=len(S_mc) - 1)) if S_mc is not None else None
        S_tv = S_tv.window(max(span0, S_tv.first), S_tv.first + dt.timedelta(days=len(S_tv) - 1)) if S_tv is not None else None
        r = {"id": it["id"], "set": it["set"], "slug": it["slug"], "n": it.get("n"), "lead": it.get("lead"), "claim": it.get("claim"),
             "ref": it["ref"], "lag": lag, "country": cty, "chain_verdict": it.get("chain_verdict"), "wikipedia": it.get("wikipedia"),
             "wikipedia_pass": wiki_pass(it), "sensors": {}}
        for name, S, fl in (("gdelt_doc", S_doc, FLOOR["doc"]), ("mediacloud", S_mc, FLOOR["mc"]), ("gdelt_tv", S_tv, FLOOR["tv"])):
            if name == "gdelt_tv" and not it["q"].get("tv"):
                res = {"verdict": "not run", "why": it.get("tv_untestable")}
            elif S is None:
                res = {"verdict": "not run"}
            else:
                c = cache_for(S)
                res = step_test(S, ref, lag, fl, c)
                if res["verdict"] not in UNTESTABLE:
                    res["decoys"] = decoys(S, ref, lag, fl, it["id"], c)
            r["sensors"][name] = res
        news = r["sensors"]["gdelt_doc"] if r["sensors"]["gdelt_doc"]["verdict"] not in UNTESTABLE else r["sensors"]["mediacloud"]
        r["news_sensor"] = "gdelt_doc" if news is r["sensors"]["gdelt_doc"] else "mediacloud"
        r.update(classify(it, r["wikipedia_pass"], news, r["sensors"]["gdelt_tv"]))
        steps.append(r)
        print(it["id"], r["class"], {k: v["verdict"] for k, v in r["sensors"].items()}, flush=True)

    # calibration on decoy dates, per sensor
    calib = {}
    for name in ("gdelt_doc", "mediacloud", "gdelt_tv"):
        ds = [d for s in steps for d in s["sensors"][name].get("decoys", [])]
        k = sum(1 for d in ds if d["verdict"] == PASS)
        calib[name] = {"decoys": len(ds), "passed": k, "rate": round(k / len(ds), 3) if ds else None}

    # catalyst scan: GDELT DOC if present (registered), else Media Cloud (amendment, Oct 5)
    hand = json.load(open(HAND)) if os.path.exists(HAND) else {}
    panel = [it for it in reg["items"] if it["set"] == "E"]
    scans = {}
    for src in ("gdelt_doc", "mediacloud"):
        allc = []
        for it in panel:
            S = doc.get(it["q"]["doc"]) if src == "gdelt_doc" else mc.get((it["q"]["mc"], "US"))
            if S is None:
                continue
            S = S.window(SCAN_FROM, SCAN_TO)  # plan section 7: the scan covers Jan 1, 2017 to Sep 30, 2026 on either source
            for c in scan(S, FLOOR["doc"] if src == "gdelt_doc" else FLOOR["mc"]):
                c.update({"entity": it["entity"], "group": it["group"], "wiki_article": it["wiki_article"]})
                allc.append(c)
        scans[src] = allc
    primary = "gdelt_doc" if scans["gdelt_doc"] else "mediacloud"
    cands = [c for c in scans[primary] if c["candidate"]]
    for c in cands:  # convergence: Wikipedia pageviews (and television, when present) within 7 days
        v = wiki_views(c["wiki_article"]) if c.get("wiki_article") else None
        c["wikipedia"] = wiki_onset_near(v, D(c["onset"])) if v is not None else None
        S_tv = tv.get((next(it["q"]["tv"] for it in panel if it["entity"] == c["entity"]), "US"))
        c["television"] = None
        if S_tv is not None:
            i = S_tv.idx(D(c["onset"]))
            f = onset(S_tv, i - 7, 0, 14, FLOOR["tv"])
            c["television"] = {"onset": S_tv.date(f[0]), "ratio": round(f[1], 1)} if f else None
        c["converged"] = bool(c["wikipedia"] or c["television"])
        h = hand.get(f'{c["entity"]}|{c["onset"]}')
        if h:
            c["hand_check"] = h
    real = [c for c in cands if c["group"] != "decoy"]
    real.sort(key=lambda c: (not c["converged"], c["p"], -c["ratio"]))
    top, per = [], {}
    for c in real:
        if per.get(c["entity"], 0) >= 2:
            continue
        per[c["entity"]] = per.get(c["entity"], 0) + 1
        top.append(c)
        if len(top) == 20:
            break
    decoy_c = [c for c in cands if c["group"] == "decoy"]
    rep = {
        "protocol": "ripples/docs/sensors_plan_v1.md", "script": "ripples/lab/sensors_v1.py",
        "run": dt.date.today().isoformat(),
        "sources": {"mediacloud": {k: (mcraw or {}).get(k) for k in ("run", "requests_used", "stopped", "declared_rate", "spacing_s", "collections")} if mcraw else None,
                    "gdelt": {k: (graw or {}).get(k) for k in ("run", "requests_used", "stopped")} if graw else {"stopped": "HTTP 429 on the first request, Oct 5, 06:35 UTC"},
                    "wikipedia_catalyst_fetch_stopped": _wstop[0] if _wstop else None},
        "calibration": calib,
        "steps": steps,
        "catalysts": {"scan_source": primary, "top20": top, "decoy_entity_candidates": decoy_c,
                      "n_candidates": len(cands), "n_changes": len(scans[primary]),
                      "replication": {s: [c for c in scans[s] if c["candidate"]] for s in scans if s != primary and scans[s]}},
    }
    json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    print("calibration", calib)
    print("candidates", len(cands), "decoy-entity candidates", len(decoy_c))
    return 0


if __name__ == "__main__":
    sys.exit(main())
