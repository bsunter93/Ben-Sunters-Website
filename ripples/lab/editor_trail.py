"""Editor trail v1 (ripples/docs/editor_trail_v1.md): discovery of non-obvious ripples, explore stage.

Idea: when an event really moves something, Wikipedia editors write it into the article that moved ("the song
re-entered the charts after its use in ..."). So the articles that link TO an event's article contain its documented
ripples, mixed with cast, episodes and navbox noise. For each event:
  1. Backlinks (namespace 0, no redirects) to the event's article(s), via the MediaWiki API.
  2. Wikidata P31 typing: drop people, TV/film works, episodes, seasons, characters, awards, lists, and titles that
     contain the event's own name (same franchise). What is left is grouped: music, material, place, other.
  3. Daily Wikipedia views for each candidate, July 2015 to 150 days after the event (one request per article).
  4. Ordering rule (ledger 1497): the candidate's sustained rise must begin on or after the event's own attention
     onset and within 120 days of the event. Onset = first day the 7-day mean stays above the baseline threshold
     (median of days -120..-15 plus 5 MAD, at least 1.5x the median and +20 views) for 5 days running, and at least a
     fifth of the way to the window's peak.
  5. Specificity: the same detector is run at every 14th day of the candidate's own history (pseudo-events). A
     pseudo-event "hits" if it finds an onset whose peak ratio is at least the observed one. p = (1 + hits) / (1 + N).
     Candidates with p <= 0.05 are "unusual"; a hit in the same window one year earlier flags "seasonal".
Anonymous, honest UA, 1 s between requests, stop on 403/429/503. Output: ripples/docs/results/editor_trail_v1.json.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "docs", "results", "editor_trail_v1.json")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
WP = "https://en.wikipedia.org/w/api.php"
WD = "https://www.wikidata.org/w/api.php"
PV = ("https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/"
      "{t}/daily/20150701/{b}")
CAP = int(os.environ.get("CAP", "260"))          # candidates fetched per event
BUDGET_MIN = float(os.environ.get("BUDGET_MIN", "200"))
LAG_MAX = 120

# (slug, event articles, date, own-name stems to drop, known documented ripples used only to score recall)
EVENTS = [
    ("stranger-things-4", ["Stranger Things season 4", "Stranger Things"], "2022-05-27", ["stranger things"],
     ["running up that hill", "master of puppets"]),
    ("wednesday", ["Wednesday (TV series)"], "2022-11-23", ["wednesday", "addams"],
     ["bloody mary (lady gaga", "goo goo muck"]),
    ("saltburn", ["Saltburn (film)"], "2023-11-17", ["saltburn"], ["murder on the dancefloor"]),
    ("squid-game", ["Squid Game season 1", "Squid Game"], "2021-09-17", ["squid game"], ["dalgona"]),
    ("the-bear", ["The Bear (TV series)"], "2022-06-23", ["the bear"], ["italian beef"]),
    ("bridgerton", ["Bridgerton"], "2020-12-25", ["bridgerton"], []),
    ("top-gun-maverick", ["Top Gun: Maverick"], "2022-05-27", ["top gun"], []),
    ("barbie", ["Barbie (film)"], "2023-07-21", ["barbie"], []),
    ("queens-gambit", ["The Queen's Gambit (miniseries)"], "2020-10-23", ["queen's gambit"], ["chess"]),
    ("chernobyl", ["Chernobyl (miniseries)"], "2019-05-06", ["chernobyl (mini"], ["pripyat"]),
    ("tiger-king", ["Tiger King"], "2020-03-20", ["tiger king"], ["big cat"]),
    ("the-last-of-us", ["The Last of Us (TV series)"], "2023-01-15", ["the last of us"], ["cordyceps"]),
    ("euphoria-s2", ["Euphoria season 2", "Euphoria (American TV series)"], "2022-01-09", ["euphoria"], []),
    ("shogun", ["Shōgun (2024 TV series)"], "2024-02-27", ["shōgun", "shogun"], []),
]

DROP_P31 = {"Q5", "Q5398426", "Q21191270", "Q3464665", "Q11424", "Q24856", "Q95074", "Q15632617", "Q15773347",
            "Q618779", "Q13406463", "Q4167410", "Q1983062", "Q1261214", "Q63952888", "Q526877", "Q202866",
            "Q29168811", "Q117467246", "Q15416", "Q7725310", "Q196600", "Q1371849", "Q17537576", "Q20937557",
            "Q506240", "Q130232", "Q24862", "Q93204", "Q4502142", "Q1107", "Q581714", "Q1569167", "Q15711870",
            "Q14514600", "Q2085381", "Q215380", "Q43099500", "Q3331189", "Q1004", "Q838795"}
MUSIC_P31 = {"Q134556", "Q7366", "Q105543609", "Q208569", "Q2188189"}
MATERIAL_P31 = {"Q4830453", "Q783794", "Q891723", "Q6881511", "Q43229", "Q163740", "Q431289", "Q2424752", "Q10929058",
                "Q7397", "Q620615", "Q11016", "Q8148", "Q268592", "Q11173", "Q79529", "Q113145171", "Q7748",
                "Q820655", "Q8142", "Q13479982", "Q11691", "Q317088", "Q12140", "Q2095", "Q746549", "Q349",
                "Q35127", "Q3220391", "Q28640", "Q12737077", "Q131436", "Q11422", "Q11446", "Q17210", "Q2424752",
                "Q1778821", "Q1792379", "Q16521", "Q7889", "Q11410", "Q1047113", "Q178706", "Q15284"}
PLACE_P31 = {"Q515", "Q486972", "Q3957", "Q532", "Q41176", "Q570116", "Q1549591", "Q15284", "Q23413", "Q839954",
             "Q33506", "Q22698", "Q16970", "Q2977", "Q44782", "Q1248784", "Q1802963", "Q5084", "Q1637706"}


class Stop(Exception):
    pass


T0 = time.time()


def get(url):
    if (time.time() - T0) / 60 > BUDGET_MIN:
        raise Stop("time budget reached")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            out = json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (403, 429, 503):
            raise Stop(f"HTTP {e.code}")
        out = None
    time.sleep(1)
    return out


def resolve(title):
    q = urllib.parse.urlencode({"action": "query", "titles": title, "redirects": 1, "format": "json"})
    d = get(f"{WP}?{q}") or {}
    pages = d.get("query", {}).get("pages", {})
    for p in pages.values():
        if "missing" not in p:
            return p["title"]
    return None


def backlinks(title):
    out, cont = [], {}
    while True:
        q = {"action": "query", "list": "backlinks", "bltitle": title, "blnamespace": 0, "bllimit": 500,
             "blfilterredir": "nonredirects", "format": "json", **cont}
        d = get(f"{WP}?{urllib.parse.urlencode(q)}") or {}
        out += [b["title"] for b in d.get("query", {}).get("backlinks", [])]
        if "continue" not in d or len(out) > 6000:
            return out
        cont = d["continue"]


def kinds(titles):
    res = {}
    for i in range(0, len(titles), 50):
        batch = titles[i:i + 50]
        q = urllib.parse.urlencode({"action": "wbgetentities", "sites": "enwiki", "props": "claims|sitelinks|descriptions",
                                    "languages": "en", "sitefilter": "enwiki", "format": "json", "titles": "|".join(batch)})
        d = get(f"{WD}?{q}") or {}
        for ent in d.get("entities", {}).values():
            t = ent.get("sitelinks", {}).get("enwiki", {}).get("title")
            if not t:
                continue
            p31 = {c.get("mainsnak", {}).get("datavalue", {}).get("value", {}).get("id")
                   for c in ent.get("claims", {}).get("P31", [])} - {None}
            res[t] = {"p31": sorted(p31), "desc": ent.get("descriptions", {}).get("en", {}).get("value", "")}
    return res


def group(p31):
    if p31 & MUSIC_P31:
        return "music"
    if p31 & PLACE_P31:
        return "place"
    if p31 & MATERIAL_P31:
        return "material"
    return "other"


def series(title, end):
    d = get(PV.format(t=urllib.parse.quote(title.replace(" ", "_"), safe=""), b=end.strftime("%Y%m%d")))
    if not d:
        return None
    return {i["timestamp"][:8]: i["views"] for i in d.get("items", [])}


DAY0 = dt.date(2015, 7, 1)


def to_array(s, end):
    n = (end - DAY0).days + 1
    v = np.full(n, np.nan)
    for k, x in s.items():
        i = (dt.date(int(k[:4]), int(k[4:6]), int(k[6:8])) - DAY0).days
        if 0 <= i < n:
            v[i] = x
    ok = np.flatnonzero(~np.isnan(v))
    if ok.size:  # the API omits zero-view days: zeros after the article's first recorded day
        v[ok[0]:] = np.nan_to_num(v[ok[0]:], nan=0.0)
    return v


def trail7(v):
    c = np.concatenate([[0.0], np.cumsum(np.nan_to_num(v, nan=0.0))])
    out = np.zeros(len(v))
    out[6:] = (c[7:] - c[:-7]) / 7
    return out


def valid(v, e):
    return e - 120 >= 0 and not np.isnan(v[e - 120:e - 14]).any()


def onset(v, e, lo, hi):
    """Sustained onset in v between e+lo and e+hi (indices), baseline days e-120..e-15. Returns (index, ratio, med)."""
    if not valid(v, e) or e + hi + 7 > len(v):
        return None
    pre = v[e - 120:e - 14]
    med = float(np.median(pre))
    mad = 1.4826 * float(np.median(np.abs(pre - med)))
    w = trail7(v)
    seg = w[e + lo:e + hi + 7]
    peak = float(seg.max())
    thr = max(med + 5 * mad, 1.5 * med, med + 20, med + 0.2 * (peak - med))
    run = 0
    for i in range(e + lo, e + hi + 1):
        run = run + 1 if w[i] > thr else 0
        if run >= 5:
            return i - 4, peak / max(med, 1.0), med
    return None


def analyze(title, v, ev_i, on_i):
    found = onset(v, ev_i, on_i - ev_i, LAG_MAX)
    if not found:
        return None
    i, ratio, med = found
    if i < on_i:
        return {"title": title, "excluded": "rose before attention to the event"}
    hits, n = 0, 0  # pseudo-events with a full baseline only
    for e in range(130, ev_i - 140, 14):
        if not valid(v, e):
            continue
        f = onset(v, e, 0, LAG_MAX)
        n += 1
        if f and f[1] >= ratio:
            hits += 1
    ly = onset(v, ev_i - 365, on_i - ev_i, LAG_MAX)
    w = np.nan_to_num(v, nan=0.0)
    excess = float(np.clip(w[i:i + 60] - med, 0, None).sum())
    weekly = [[(DAY0 + dt.timedelta(days=int(k))).isoformat(), int(w[k:k + 7].sum())]
              for k in range(ev_i - 84, min(len(w) - 7, ev_i + 147), 7)]
    return {"title": title, "onset": (DAY0 + dt.timedelta(days=int(i))).isoformat(), "lag": int(i - ev_i),
            "ratio": round(ratio, 1), "baseline": round(med, 1), "excess_60d": int(excess),
            "p": round((1 + hits) / (1 + n), 3) if n >= 20 else None, "n_pseudo": n, "seasonal": bool(ly and ly[1] >= ratio / 2),
            "weekly": weekly}


def main() -> int:
    rep = json.load(open(OUT)) if os.path.exists(OUT) else {"protocol": "ripples/docs/editor_trail_v1.md", "events": {}}
    stop = None
    for slug, arts, date, stems, known in EVENTS:
        if slug in rep["events"] and rep["events"][slug].get("done"):
            continue
        ev = dt.date.fromisoformat(date)
        end = ev + dt.timedelta(days=150)
        row = {"date": date, "articles": [], "known": known}
        try:
            resolved = [r for r in (resolve(a) for a in arts) if r]
            row["articles"] = resolved
            if not resolved:
                row.update(done=True, skip="event article not found")
                rep["events"][slug] = row
                continue
            ev_v = np.zeros((end - DAY0).days + 1)
            for a in resolved:
                ev_v += np.nan_to_num(to_array(series(a, end) or {}, end))
            ev_i = (ev - DAY0).days
            f = onset(ev_v, ev_i, -14, 30)
            on_i = min(f[0], ev_i) if f else ev_i
            row["event_onset"] = (DAY0 + dt.timedelta(days=on_i)).isoformat()
            bl = sorted(set(sum((backlinks(a) for a in resolved), [])) - set(resolved))
            bl = [t for t in bl if not re.match(r"(List of|Lists of|\d{4} in |\d{4}s? )", t)
                  and not any(s in t.lower() for s in stems)]
            row["backlinks"] = len(bl)
            kd = kinds(bl)
            keep = []
            for t in bl:
                k = kd.get(t)
                p31 = set(k["p31"]) if k else set()
                if not k or p31 & DROP_P31:
                    continue
                keep.append((t, group(p31), k["desc"]))
            order = {"music": 0, "material": 1, "place": 2, "other": 3}
            keep.sort(key=lambda x: order[x[1]])
            row["typed"] = len(keep)
            row["fetched"] = min(CAP, len(keep))
            cands, excluded = [], 0
            for t, g, desc in keep[:CAP]:
                s = series(t, end)
                if not s:
                    continue
                r = analyze(t, to_array(s, end), ev_i, on_i)
                if not r:
                    continue
                if "excluded" in r:
                    excluded += 1
                    continue
                r.update(group=g, desc=desc)
                cands.append(r)
            cands.sort(key=lambda r: (r["p"] is None or r["p"] > 0.05, r["seasonal"], -np.log2(r["ratio"]) - 0.4 * np.log10(1 + r["excess_60d"])))
            row["rose_before"] = excluded
            row["candidates"] = cands[:40]
            row["unusual"] = sum(1 for r in cands if r["p"] is not None and r["p"] <= 0.05 and not r["seasonal"])
            top = [r["title"].lower() for r in cands if r["p"] is not None and r["p"] <= 0.05][:15]
            row["recall"] = {k: any(k in t for t in top) for k in known}
            row["done"] = True
        except Stop as e:
            stop = str(e)
            row["stopped"] = stop
        rep["events"][slug] = row
        json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
        print(slug, {k: row.get(k) for k in ("backlinks", "typed", "fetched", "unusual", "recall", "stopped")}, flush=True)
        for r in row.get("candidates", [])[:12]:
            print(f"   {r['p'] if r['p'] is not None else '-':<6} {'S' if r['seasonal'] else ' '} +{r['lag']:>3}d x{r['ratio']:<6} {r['group']:<8} {r['title']} — {r['desc'][:60]}")
        if stop:
            break
    rep["stopped"] = stop
    json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
