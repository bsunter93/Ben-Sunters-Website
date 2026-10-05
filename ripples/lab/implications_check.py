"""Implications check v1: tests the implications registered in ripples/docs/results/implications_plan_v1.json
(ripples/docs/implications_plan_v1.md, registered Oct 5, 2026, commit ff867c6) with the checker's own tools, unchanged:
chain_check.wiki_test, chain_check.fred, chain_check.series_test, chain_check.ssa_test and chain_check.verdict.

Each implication is reported as held, failed or untestable, with the raw result. Network: honest user agent, at least
1 s between requests; any 403, 429 or 5xx stops the run (no retry, no other agent) and leaves the rest untested.
Output: ripples/docs/results/implications_v1.json.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import chain_check as cc  # noqa: E402
import editor_trail as et  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
PLAN = os.path.join(ROOT, "docs", "results", "implications_plan_v1.json")
OUT = os.path.join(ROOT, "docs", "results", "implications_v1.json")
D = dt.date.fromisoformat


def strict_get(url):
    """editor_trail.get with the stop widened to every 5xx (the module stops on 403, 429 and 503 only)."""
    req = urllib.request.Request(url, headers={"User-Agent": et.UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            out = json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (403, 429) or e.code >= 500:
            raise et.Stop(f"HTTP {e.code} at {url[:70]}")
        out = None
    finally:
        time.sleep(1.1)
    return out


def strict_fetch(url, delay=1.1, raw=False):
    req = urllib.request.Request(url, headers={"User-Agent": et.UA, "Accept-Encoding": "identity"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            body = r.read()
    except urllib.error.HTTPError as e:
        if e.code in (403, 429) or e.code >= 500:
            raise et.Stop(f"HTTP {e.code} at {url[:70]}")
        return None
    finally:
        time.sleep(delay)
    return body if raw else body.decode("utf-8", "replace")


et.get = strict_get
cc.fetch = strict_fetch


def wiki(t, flat=False):
    ref = D(t["ref"])
    r = cc.wiki_test(t["articles"], ref, t["lag"])
    v = cc.verdict({"test": {"type": "wiki"}}, r, ref)
    keep = {k: r.get(k) for k in ("onset", "ratio", "baseline", "p", "n_placebo", "new_article", "result", "found")}
    keep["verdict"] = v
    if v == "no data" or r.get("result") == "no article":
        return "untestable", keep, "no article under that title"
    if v.startswith("timed") or r.get("new_article"):
        # a new article's first day dates the article, not the phenomenon (chain_check's own rule), so it is never an order failure
        why = f"a new article (first day {r['new_article']})" if r.get("new_article") else "too short a history"
        return "untestable", keep, f"{why}: no placebo is possible"
    if flat:
        if v == "measured":
            return "failed", keep, "it rose beyond chance, in order"
        return "held", keep, "no rise beyond chance" if v == "no movement" else f"{v}: not credited to the date"
    if v == "measured":
        note = "a sustained rise beyond chance, in order"
        if t.get("secondary"):
            small = r.get("ratio") is not None and r["ratio"] < t["secondary"]["smaller_than"]
            keep["secondary_smaller"] = small
            note += f"; secondary (smaller than {t['secondary']['smaller_than']}x): {'yes' if small else 'no'}"
        return "held", keep, note
    why = "no sustained rise" if r.get("result") else ("a rise within chance" if v == "no movement" else "the rise began before the date")
    return "failed", keep, why


def fred(t, flat=False):
    ref = D(t["ref"])
    st = {"test": {"type": "fred", "id": t["id"], "direction": t["direction"], "h": t["h"], "transform": t["transform"]}}
    r = cc.run_step(st, ref)
    v = cc.verdict(st, r, ref)
    keep = {k: r.get(k) for k in ("effect", "p", "n_placebo", "onset", "period_days", "result", "series")}
    keep["verdict"] = v
    if v == "no data":
        return "untestable", keep, "no data for the series"
    if flat:
        return ("failed", keep, "it moved beyond chance, in order") if v == "measured" else ("held", keep, f"{v}")
    return ("held", keep, "a move beyond chance, in order") if v == "measured" else ("failed", keep, v)


def chain_counts(slug, n):
    import glob
    for path in glob.glob(os.path.join(ROOT, "chains", "*.json")):
        for ch in json.load(open(path)):
            if ch["slug"] == slug:
                return next(s for s in ch["steps"] if s["n"] == n)["test"]["counts"]
    return None


def ssa_repo(t):
    c = chain_counts(t["chain"], t["step"])
    if not c or str(t["year"]) not in c:
        return "untestable", {}, "the year is not in the chain's counts"
    r = cc.ssa_test(c, t["year"])
    keep = {"effect": r["effect"], "p": r["p"], "n_placebo": r["n_placebo"], "count": c[str(t["year"])], "count_before": c.get(str(t["year"] - 1))}
    return ("held" if r["p"] <= 0.05 else "failed"), keep, f"log change {r['effect']}, p = {r['p']}"


def ssa_compare(t):
    c = chain_counts(t["chain"], t["step"])
    a, b = c.get(str(t["later"])), c.get(str(t["peak"]))
    keep = {str(t["peak"]): b, str(t["later"]): a, "series": {k: c[k] for k in sorted(c) if int(k) >= 2010}}
    return ("held" if a < b else "failed"), keep, f"{t['later']}: {a} against {t['peak']}: {b}"


def wiki_seasonal(t):
    ref = D(t["ref"])
    rows = []
    for k in [0] + t["years_back"]:
        d = ref - dt.timedelta(days=365 * k)
        r = cc.wiki_test(t["articles"], d, t["lag"])
        v = cc.verdict({"test": {"type": "wiki"}}, r, d)
        rows.append({"date": d.isoformat(), "ratio": r.get("ratio"), "p": r.get("p"), "onset": r.get("onset"), "verdict": v})
    if rows[0]["ratio"] is None:
        return "untestable", {"years": rows}, "no rise at the date itself"
    base = [x["ratio"] if x["ratio"] is not None else 1.0 for x in rows[1:]]
    held = all(rows[0]["ratio"] > b for b in base)
    return ("held" if held else "failed"), {"years": rows}, f"{rows[0]['ratio']}x against {', '.join(str(b) + 'x' for b in base)}"


def daily(title, end):
    s = et.series(title, end)
    if not s:
        return None
    return et.to_array(s, end)


def mean_between(v, a, b):
    i, j = (D(a) - et.DAY0).days, (D(b) - et.DAY0).days
    w = v[i:j + 1]
    return float(np.nanmean(w)) if w.size and not np.isnan(w).all() else None


def wiki_persist_peak(t):
    end = D(t["late"][1])
    v = None
    for a in t["articles"]:
        x = daily(a, end)
        if x is None:
            return "untestable", {}, f"no views for {a}"
        v = x if v is None else np.nan_to_num(v) + np.nan_to_num(x)
    i, j = (D(t["peak_from"][0]) - et.DAY0).days, (D(t["peak_from"][1]) - et.DAY0).days
    c = np.concatenate([[0.0], np.cumsum(np.nan_to_num(v))])
    peak = max((c[k + 30] - c[k]) / 30 for k in range(i, j - 29))
    late = mean_between(v, *t["late"])
    share = late / peak if peak else None
    keep = {"peak_30day_mean": round(peak, 1), "late_mean": round(late, 1), "share": round(share, 3)}
    return ("held" if share >= t["share"] else "failed"), keep, f"late mean {late:.0f} a day is {100 * share:.1f}% of the peak 30-day mean ({peak:.0f})"


def wiki_persist_ratio(t):
    end = D(t["late"][1])
    v = daily(t["articles"][0], end)
    if v is None:
        return "untestable", {}, "no views"
    late, pre = mean_between(v, *t["late"]), mean_between(v, *t["pre"])
    ratio = late / pre if pre else None
    keep = {"late_mean": round(late, 1), "pre_mean": round(pre, 1), "ratio": round(ratio, 2)}
    return ("held" if ratio >= t["factor"] else "failed"), keep, f"{late:.0f} against {pre:.0f} a day: {ratio:.2f}x"


RUN = {"wiki": wiki, "wiki_flat": lambda t: wiki(t, flat=True), "fred": fred, "fred_flat": lambda t: fred(t, flat=True),
       "ssa_repo": ssa_repo, "ssa_compare": ssa_compare, "wiki_seasonal": wiki_seasonal, "wiki_persist_peak": wiki_persist_peak,
       "wiki_persist_ratio": wiki_persist_ratio}


def main() -> int:
    plan = json.load(open(PLAN))
    rep = {"protocol": "ripples/docs/implications_plan_v1.md", "plan_commit": "ff867c6", "run": dt.date.today().isoformat(),
           "code": "ripples/lab/implications_check.py", "stopped": None, "implications": []}
    for imp in plan["implications"]:
        row = {k: imp[k] for k in ("id", "ripple", "link", "type", "statement", "weakens_if_failed")}
        t = imp["test"]
        if rep["stopped"]:
            row.update(status="untestable", note=f"not run: {rep['stopped']}")
        elif t["type"] == "none":
            row.update(status="untestable", note=t["reason"])
        else:
            try:
                status, result, note = RUN[t["type"]](t)
                row.update(status=status, note=note, result=result)
            except et.Stop as e:
                rep["stopped"] = str(e)
                row.update(status="untestable", note=f"source refused: {e}")
        rep["implications"].append(row)
        print(row["id"], row["status"], row.get("note", ""), flush=True)
        json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    rep["counts"] = {s: sum(1 for r in rep["implications"] if r["status"] == s) for s in ("held", "failed", "untestable")}
    json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    print(rep["counts"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
