"""Predict check v1: scores the live predictions registered in ripples/docs/results/predictions_v1.json
(ripples/docs/predictions_v1.md, registered Oct 5, 2026, commit 04b2ab1) when each falls due.

A prediction is scored once, on the first run on or after its due date when its data are published, and its verdict is
then frozen: a later run never rescored it. Test types (the registration fixes every threshold; this file only implements them):
  wiki_level            daily Wikipedia views in a window against the pre-stone baseline, a placebo over the page's own
                        history, a seasonal check against the same dates in earlier years, and the checker's onset for the
                        ordering rule (editor_trail.onset, as in chain_check.wiki_test)
  library_month         Seattle Public Library monthly checkouts (data.seattle.gov tmmm-ytt6) for a title and author
  hansard_mention       UK Parliament Hansard API: spoken contributions naming a term inside the window
  uk_bill_first_reading UK Parliament Bills API: bills whose short title matches, dated by their first stage's first sitting
Public, keyless sources only. Honest user agent, at least 1.1 s between requests, and any HTTP status of 400 or above
stops the run for the week (no retry, no other agent); predictions not reached stay pending and are tried next week.
Output: ripples/docs/results/predictions_scored_v1.json. `--selftest` scores four past cases unrelated to the registered
set (a known attention surge, a known library surge, a Hansard window, a bill) and writes nothing.
"""
from __future__ import annotations

import datetime as dt
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

sys.path.insert(0, os.path.dirname(__file__))
import editor_trail as et  # noqa: E402  (pure helpers only: DAY0, to_array, valid, onset)

ROOT = os.path.join(os.path.dirname(__file__), "..")
REG = os.path.join(ROOT, "docs", "results", "predictions_v1.json")
OUT = os.path.join(ROOT, "docs", "results", "predictions_scored_v1.json")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
WP = "https://en.wikipedia.org/w/api.php"
PV = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/{t}/daily/20150701/{b}"
SPL = "https://data.seattle.gov/resource/tmmm-ytt6.json"
HAN = "https://hansard-api.parliament.uk/search/contributions/Spoken.json"
BILLS = "https://bills-api.parliament.uk/api/v1"
FINAL = {"hit", "miss", "bust", "void"}
D = dt.date.fromisoformat
TODAY = D(os.environ["PREDICT_TODAY"]) if os.environ.get("PREDICT_TODAY") else dt.date.today()


class Stop(Exception):
    pass


class Pending(Exception):
    pass


class Void(Exception):
    pass


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            body = r.read()
    except urllib.error.HTTPError as e:
        raise Stop(f"HTTP {e.code} from {urllib.parse.urlsplit(url).netloc}")
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise Stop(f"no response from {urllib.parse.urlsplit(url).netloc}: {type(e).__name__}")
    finally:
        time.sleep(1.1)
    return json.loads(body)


# ---------- wiki_level ----------
def canonical(title):
    """The article must exist under the registered title (not missing, not a redirect), or the prediction is void."""
    d = get_json(f"{WP}?{urllib.parse.urlencode({'action': 'query', 'titles': title, 'redirects': 1, 'format': 'json'})}")
    q = d.get("query") or {}
    if q.get("redirects"):
        return None
    pages = list((q.get("pages") or {}).values())
    return pages[0]["title"] if pages and "missing" not in pages[0] else None


def views(title, end):
    d = get_json(PV.format(t=urllib.parse.quote(title.replace(" ", "_"), safe=""), b=end.strftime("%Y%m%d")))
    return {i["timestamp"][:8]: i["views"] for i in d.get("items", [])}


def ratio_at(v, e, a, b):
    """window mean over days e+a..e+b and baseline median over days e-120..e-15, or None when incomplete"""
    if e - 120 < 0 or e + b >= len(v) or not et.valid(v, e):
        return None
    w = v[e + a:e + b + 1]
    if np.isnan(w).any():
        return None
    base = float(np.median(v[e - 120:e - 14]))
    m = float(w.mean())
    return m / max(base, 1.0), m, base


def wiki_level(t):
    e_date, (a, b) = D(t["stone_date"]), t["offsets_days"]
    w1 = e_date + dt.timedelta(days=b)
    last = TODAY - dt.timedelta(days=2)
    if last < w1:
        raise Pending(f"window ends {w1}; views published through about {last}")
    for art in t["articles"]:
        if canonical(art) != art:
            raise Void(f"article missing or renamed: {art}")
    end = min(last, w1 + dt.timedelta(days=10))
    v = None
    for art in t["articles"]:
        s = views(art, end)
        # to_array turns unpublished days into zeros, so the window must already be in the data
        if not s or D(f"{max(s)[:4]}-{max(s)[4:6]}-{max(s)[6:8]}") < w1 - dt.timedelta(days=3):
            raise Pending(f"views for {art} not yet published through {w1}")
        x = et.to_array(s, end)
        v = x if v is None else np.nan_to_num(v) + np.nan_to_num(x)
    e = (e_date - et.DAY0).days
    obs = ratio_at(v, e, a, b)
    if obs is None:
        raise Void("baseline or window incomplete (a new or sparse article)")
    r, m, base = obs
    pool = [x[0] for x in (ratio_at(v, k, a, b) for k in range(130, e - 200, 14)) if x]
    if len(pool) < 20:
        raise Void(f"only {len(pool)} placebo windows (20 needed)")
    p = (1 + sum(1 for x in pool if x >= r)) / (1 + len(pool))
    seas = [x[0] for x in (ratio_at(v, e - 365 * k, a, b) for k in (1, 2, 3)) if x]
    seasonal_ok = (r > max(seas)) if seas else None
    material = (m - base >= 20) and r >= 1.5
    moved = p <= 0.05 and material and seasonal_ok is not False
    f = et.onset(v, e - 30, 0, min(b + 30, len(v) - (e - 30) - 8))
    onset = (et.DAY0 + dt.timedelta(days=int(f[0]))).isoformat() if f else None
    order_ok = onset is None or D(onset) >= e_date - dt.timedelta(days=3)
    weekly = [[(et.DAY0 + dt.timedelta(days=k)).isoformat(), int(np.nan_to_num(v[k:k + 7]).sum())]
              for k in range(max(0, e - 84), min(len(v) - 6, e + b + 8), 7)]
    # a flag for the reader, never an input to the verdict: a page move leaves the new title's earlier series near zero
    flags = ["baseline under 5 views a day: check the article's history for a page move"] if base < 5 else []
    return {"moved": bool(moved), "order_ok": bool(order_ok), "strong": bool(p <= 0.01 and r >= 10), "flags": flags,
            "ratio": round(r, 2), "window_mean": round(m, 1), "baseline": round(base, 1), "p": round(p, 3), "n_placebo": len(pool),
            "seasonal_ratios": [round(x, 2) for x in seas], "seasonal_ok": seasonal_ok, "material": bool(material),
            "onset": onset, "window": [(e_date + dt.timedelta(days=a)).isoformat(), w1.isoformat()], "weekly": weekly}


# ---------- library_month ----------
def soql_quote(s):
    return s.replace("'", "''")


def spl_latest_month(year):
    q = {"$select": "max(checkoutmonth) as m", "$where": f"checkoutyear={year} AND title like 'Harry Potter%'"}
    d = get_json(f"{SPL}?{urllib.parse.urlencode(q)}")
    try:
        return int(float(d[0]["m"]))
    except (IndexError, KeyError, TypeError, ValueError):
        return 0


def spl_counts(prefixes, creator, since=2012):
    titles = " OR ".join(f"title like '{soql_quote(p)}%'" for p in prefixes)
    q = {"$select": "checkoutyear,checkoutmonth,sum(checkouts) as n",
         "$where": f"({titles}) AND upper(creator) like '%{soql_quote(creator.upper())}%' AND checkoutyear>={since}",
         "$group": "checkoutyear,checkoutmonth", "$order": "checkoutyear,checkoutmonth", "$limit": "5000"}
    rows = get_json(f"{SPL}?{urllib.parse.urlencode(q)}")
    return {(int(r["checkoutyear"]), int(r["checkoutmonth"])): float(r["n"]) for r in rows}


def mshift(ym, k):
    i = ym[0] * 12 + ym[1] - 1 + k
    return (i // 12, i % 12 + 1)


def closed(ym):
    return (2020, 3) <= ym <= (2021, 6)


def month_test(c, target, first=(2013, 1)):
    def s(ym):
        prev = [c.get(mshift(ym, -k), 0.0) for k in (1, 2, 3)]
        return math.log(c.get(ym, 0.0) + 1) - math.log(sum(prev) / 3 + 1), c.get(ym, 0.0) - sum(prev) / 3
    obs, excess = s(target)
    pool, same = [], []
    ym, stop = first, mshift(target, -2)
    while ym <= stop:
        if not closed(ym) and not any(closed(mshift(ym, -k)) for k in (1, 2, 3)):
            x = s(ym)[0]
            pool.append(x)
            if ym[1] == target[1]:
                same.append(x)
        ym = mshift(ym, 1)
    p = (1 + sum(1 for x in pool if x >= obs)) / (1 + len(pool))
    seasonal_ok = (obs > max(same)) if same else None
    material = excess >= 10
    return {"s": round(obs, 3), "count": c.get(target, 0.0), "prev3_mean": round(c.get(target, 0.0) - excess, 1), "p": round(p, 3),
            "n_placebo": len(pool), "same_month_prior_max": round(max(same), 3) if same else None, "seasonal_ok": seasonal_ok,
            "material": bool(material), "moved": bool(p <= 0.05 and material and seasonal_ok is not False)}


def library_month(t, deadline=None):
    y, m = map(int, t["month"].split("-"))
    latest = spl_latest_month(y)
    if latest < m:
        if deadline and TODAY > D(deadline):
            raise Void(f"{t['month']} not published by the deadline {deadline}")
        raise Pending(f"{t['month']} not yet published (latest month in {y}: {latest or 'none'})")
    c = spl_counts(t["title_prefixes"], t["creator_contains"])
    cur = month_test(c, (y, m))
    pre = month_test(c, mshift((y, m), -1))
    series = [[f"{k[0]}-{k[1]:02d}", v] for k, v in sorted(c.items()) if k >= mshift((y, m), -24)]
    return {**cur, "order_ok": not pre["moved"], "pre_month": pre, "strong": False, "series": series}


# ---------- records ----------
def hansard_mention(t):
    a, b = t["window"]
    if TODAY < D(b) + dt.timedelta(days=3):
        raise Pending(f"window ends {b}")
    q = urllib.parse.urlencode({"queryParameters.searchTerm": t["term"], "queryParameters.startDate": a, "queryParameters.endDate": b,
                                "queryParameters.take": 100})
    d = get_json(f"{HAN}?{q}")
    rows = [r for r in (d.get("Results") or []) if a <= (r.get("SittingDate") or "")[:10] <= b]
    found = [{"date": r.get("SittingDate", "")[:10], "house": r.get("House"), "section": r.get("DebateSection")} for r in rows]
    return {"total": d.get("TotalResultCount"), "in_window": len(rows), "found": found[:20], "record": len(rows) > 0}


def uk_bill_first_reading(t):
    a, b = t["window"]
    if TODAY < D(b) + dt.timedelta(days=3):
        raise Pending(f"window ends {b}")
    rx = re.compile(t["title_regex"])
    bills = {}
    for term in t["search_terms"]:
        skip = 0
        while True:
            d = get_json(f"{BILLS}/Bills?{urllib.parse.urlencode({'SearchTerm': term, 'Take': 100, 'Skip': skip})}")
            items = d.get("items") or []
            for it in items:
                if rx.search(it.get("shortTitle") or ""):
                    bills[it["billId"]] = it.get("shortTitle")
            skip += 100
            if skip >= (d.get("totalResults") or 0) or not items:
                break
    hits = []
    for bid, title in sorted(bills.items()):
        s = get_json(f"{BILLS}/Bills/{bid}/Stages?Take=100")
        stages = s.get("items") or []
        firsts = [x for x in stages if re.search(r"1st reading", x.get("description") or "", re.I)] or stages
        dates = sorted(sit.get("date", "")[:10] for x in firsts for sit in (x.get("stageSittings") or []) if sit.get("date"))
        if dates and a <= dates[0] <= b:
            hits.append({"bill": title, "first_reading": dates[0], "id": bid})
    return {"bills_matching": len(bills), "in_window": hits, "record": len(hits) > 0}


TESTS = {"wiki_level": wiki_level, "library_month": library_month, "hansard_mention": hansard_mention,
         "uk_bill_first_reading": uk_bill_first_reading}


def verdict(kind, typ, r):
    if typ in ("hansard_mention", "uk_bill_first_reading"):
        return ("hit" if r["record"] else "miss") if kind == "move" else ("miss" if r["record"] else "hit")
    if kind == "move":
        return "miss" if not r["moved"] else ("hit" if r["order_ok"] else "bust")
    if not r["moved"]:  # not move, decoy
        return "hit"
    if not r["order_ok"]:
        return "void"
    return "bust" if r.get("strong") else "miss"


def score(pred):
    t = pred["test"]
    if TODAY < D(pred["due"]):
        return {"status": "pending", "reason": f"due {pred['due']}"}
    deadline = pred.get("deadline") or (D(pred["due"]) + dt.timedelta(days=35)).isoformat()
    try:
        r = library_month(t, deadline) if t["type"] == "library_month" else TESTS[t["type"]](t)
    except Pending as e:
        if TODAY > D(deadline):
            return {"status": "void", "verdict": "void", "reason": f"data not published by {deadline}: {e}"}
        return {"status": "pending", "reason": str(e)}
    except Void as e:
        return {"status": "void", "verdict": "void", "reason": str(e)}
    v = verdict(pred["kind"], t["type"], r)
    return {"status": v, "verdict": v, "scored_on": TODAY.isoformat(), "result": r}


def summarize(rows, preds):
    conf = {p["id"]: p["confidence"] for p in preds}
    kinds = {p["id"]: p["kind"] for p in preds}
    out = {}
    for k in ("move", "not move", "decoy"):
        sel = [r for r in rows if kinds[r["id"]] == k]
        out[k] = {s: sum(1 for r in sel if r["status"] == s) for s in ("hit", "miss", "bust", "void", "pending")}
    final = [r for r in rows if r["status"] in ("hit", "miss", "bust")]
    out["brier"] = round(sum((conf[r["id"]] - (r["status"] == "hit")) ** 2 for r in final) / len(final), 3) if final else None
    out["scored"] = len(final)
    return out


# Written after the registration (Oct 5, 2026); none changes a threshold, window or verdict rule.
SCORER_NOTES = [
    "A wiki_level window is pending until the API has data through the window's end (unpublished days would otherwise read as zeros).",
    "A baseline under 5 views a day carries a flag for the reader (a page move leaves the new title's earlier series near zero); the flag never enters the verdict.",
    "Found by the self-test, after registration: Hydraulic shock (X2) was moved from Water hammer around Mar 2025, so its placebo pool includes a near-zero stretch before the move. Its baseline (Jun to Sep 2026) is after the move. The test runs as registered.",
    "Any HTTP status of 400 or above stops the run for the week; predictions not reached stay pending until their deadline (due date plus 35 days; Jan 31, 2027 for the library).",
]


def main() -> int:
    reg = json.load(open(REG))
    old = {r["id"]: r for r in (json.load(open(OUT)).get("predictions", []) if os.path.exists(OUT) else [])}
    rep = {"protocol": "ripples/docs/predictions_v1.md", "registered": reg["registered_at"], "registration_commit": "04b2ab1",
           "run": TODAY.isoformat(), "checker_sha": os.environ.get("GITHUB_SHA", "")[:7], "stopped": None,
           "scorer_notes": SCORER_NOTES, "predictions": []}
    stop = None
    for p in reg["predictions"]:
        prev = old.get(p["id"])
        if prev and prev.get("status") in FINAL:  # frozen once scored
            rep["predictions"].append(prev)
            continue
        if stop:
            row = {"status": "pending", "reason": f"not reached: the run stopped ({stop})"}
        else:
            try:
                row = score(p)
            except Stop as e:
                stop = str(e)
                row = {"status": "pending", "reason": f"source refused; tried again next week ({stop})"}
        rep["predictions"].append({"id": p["id"], "kind": p["kind"], "stone": p["stone"], "claim": p["claim"], "due": p["due"],
                                   "confidence": p["confidence"], **row})
        print(p["id"], p["kind"], row["status"], row.get("reason", ""), flush=True)
    rep["stopped"] = stop
    rep["summary"] = summarize(rep["predictions"], reg["predictions"])
    json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    print(json.dumps(rep["summary"]))
    return 0


def selftest() -> int:
    """Four past cases, none in the registered set; prints results, writes nothing."""
    global TODAY
    TODAY = dt.date(2026, 10, 5)
    cases = [
        ("wiki_level: Chess after The Queen's Gambit (Oct 23, 2020), days 6 to 20; expect moved",
         lambda: wiki_level({"articles": ["Chess"], "stone_date": "2020-10-23", "offsets_days": [6, 20]})),
        ("wiki_level: Pythagorean theorem, an arbitrary date (Mar 3, 2025), days 6 to 20; expect not moved",
         lambda: wiki_level({"articles": ["Pythagorean theorem"], "stone_date": "2025-03-03", "offsets_days": [6, 20]})),
        ("wiki_level: a window that has not ended; expect Pending with no request",
         lambda: wiki_level({"articles": ["Chess"], "stone_date": "2026-10-01", "offsets_days": [5, 20]})),
        ("library_month: The Queen's Gambit (Tevis), Nov 2020; expect moved",
         lambda: library_month({"month": "2020-11", "title_prefixes": ["The Queen's Gambit", "The queen's gambit"], "creator_contains": "TEVIS"})),
        ("hansard_mention: 'Mr Bates' in Jan 8 to 31, 2024; expect a record",
         lambda: hansard_mention({"term": "Mr Bates", "window": ["2024-01-08", "2024-01-31"]})),
        ("uk_bill_first_reading: Horizon offences bill, Mar 1 to 31, 2024; expect a record",
         lambda: uk_bill_first_reading({"search_terms": ["Horizon System"], "title_regex": "(?i)horizon system", "window": ["2024-03-01", "2024-03-31"]})),
    ]
    for name, fn in cases:
        try:
            r = fn()
            keep = {k: r[k] for k in r if k not in ("weekly", "series", "found", "pre_month")}
            print("OK  ", name, "->", json.dumps(keep)[:400], flush=True)
        except (Pending, Void) as e:
            print("FAIL", name, "->", type(e).__name__, e, flush=True)
        except Stop as e:
            print("STOP", name, "->", e, flush=True)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
