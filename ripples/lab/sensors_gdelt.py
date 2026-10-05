"""Sensors v1, GDELT leg (ripples/docs/sensors_plan_v1.md): the DOC 2.0 API (timelinevolraw, English-language online
news, Jan 1, 2017 on) and the TV 2.0 API (timelinevol and timelinevolnorm over closed captions, Jul 2, 2009 on), for
every registered query. Run locally; no key.

Politeness: honest user agent; one request every 6 s (GDELT asks for no more than one every 5 s); a 401, 403, 429, 5xx,
timeout or GDELT's plain-text rate-limit notice writes a stop marker for the UTC day and ends the run; a run refuses to
start while a marker for the current UTC day exists. Raw answers are cached outside the repository; the committed output
holds daily aggregate counts only. Output: ripples/docs/results/sensors_gdelt_v1.json.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..")
REG = os.path.join(ROOT, "lab", "sensors_queries_v1.json")
OUT = os.path.join(ROOT, "docs", "results", "sensors_gdelt_v1.json")
CACHE = os.environ.get("GDELT_CACHE") or os.path.join(ROOT, "..", ".cache_sensors_gdelt")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
DOC = "https://api.gdeltproject.org/api/v2/doc/doc"
TV = "https://api.gdeltproject.org/api/v2/tv/tv"
SPACING = 6.0
D = dt.date.fromisoformat
DOC_START, DOC_END = dt.date(2017, 1, 1), dt.date(2026, 9, 30)
CHUNKS = [(dt.date(2009, 7, 2), dt.date(2012, 5, 31)), (dt.date(2012, 6, 1), dt.date(2015, 4, 30)),
          (dt.date(2015, 5, 1), dt.date(2018, 3, 31)), (dt.date(2018, 4, 1), dt.date(2021, 2, 28)),
          (dt.date(2021, 3, 1), dt.date(2024, 1, 31)), (dt.date(2024, 2, 1), dt.date(2026, 9, 30))]
TV_FROM = {"US": dt.date(2015, 7, 1), "UK": dt.date(2017, 1, 1)}


class Stop(Exception):
    pass


def stop_file(day=None):
    return os.path.join(CACHE, f"STOP_{(day or dt.datetime.now(dt.timezone.utc).date()).isoformat()}")


_last = [0.0]
USED = [0]


def get(base, params):
    os.makedirs(CACHE, exist_ok=True)
    key = hashlib.sha1((base + json.dumps(params, sort_keys=True)).encode()).hexdigest()
    fn = os.path.join(CACHE, key + ".json")
    if os.path.exists(fn):
        return json.load(open(fn))
    if os.path.exists(stop_file()):
        raise Stop("stop marker for today")
    wait = _last[0] + SPACING - time.time()
    if wait > 0:
        time.sleep(wait)
    req = urllib.request.Request(base + "?" + urllib.parse.urlencode(params), headers={"User-Agent": UA})
    _last[0] = time.time()
    USED[0] += 1
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            body = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        if e.code in (401, 403, 429) or e.code >= 500:
            open(stop_file(), "w").write(f"HTTP {e.code} {dt.datetime.now(dt.timezone.utc).isoformat()}\n")
            raise Stop(f"HTTP {e.code}")
        body = json.dumps({"_error": e.code})
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        open(stop_file(), "w").write(f"{type(e).__name__} {dt.datetime.now(dt.timezone.utc).isoformat()}\n")
        raise Stop(type(e).__name__)
    if "limit requests" in body[:300].lower():
        open(stop_file(), "w").write(f"rate-limit notice {dt.datetime.now(dt.timezone.utc).isoformat()}\n")
        raise Stop("rate-limit notice")
    try:
        j = json.loads(body) if body.strip() else {}
    except ValueError:
        j = {"_text": body[:300]}
    json.dump(j, open(fn, "w"))
    return j


def ts(d: dt.date, end=False):
    return d.strftime("%Y%m%d") + ("235959" if end else "000000")


def day_of(s: str) -> dt.date:
    s = str(s)
    return dt.date(int(s[:4]), int(s[4:6]), int(s[6:8]))


def plan(reg):
    docq, tvq = {}, {}
    for it in reg["items"]:
        docq.setdefault(it["q"]["doc"], []).append(it["id"])
        q = it["q"].get("tv")
        if not q:
            continue
        cty = it["country"]
        if it["set"] == "E":
            continue  # television for the panel is fetched only around candidates (sensors_v1 decides; see --panel)
        start = dt.date(2009, 7, 2) if it["set"] == "D" else TV_FROM[cty]
        if cty == "UK":
            start = max(start, dt.date(2017, 1, 1))
        end = min(DOC_END, D(it["ref"]) + dt.timedelta(days=it["lag"] + 30))
        if end <= start:
            continue
        k = (q, cty)
        if k in tvq:
            tvq[k]["start"] = min(tvq[k]["start"], start)
            tvq[k]["end"] = max(tvq[k]["end"], end)
            tvq[k]["ids"].append(it["id"])
        else:
            tvq[k] = {"q": q, "country": cty, "start": start, "end": end, "ids": [it["id"]]}
    return docq, list(tvq.values())


def chunks_for(start, end):
    """Whole fixed chunks (so the per-station totals are fetched once per chunk and shared by every query)."""
    return [(a, b) for a, b in CHUNKS if b >= start and a <= end]


def doc_series(q, suffix):
    j = get(DOC, {"query": q + suffix, "mode": "timelinevolraw", "format": "json",
                  "startdatetime": ts(DOC_START), "enddatetime": ts(DOC_END, True)})
    if "_error" in j or "_text" in j:
        return {"q": q, "error": j.get("_error") or j.get("_text")}
    tl = j.get("timeline") or []
    if not tl:
        return {"q": q, "empty": True}
    data = tl[0].get("data") or []
    n = (DOC_END - DOC_START).days + 1
    cnt, tot = [None] * n, [None] * n
    for p in data:
        i = (day_of(p["date"]) - DOC_START).days
        if 0 <= i < n:
            cnt[i] = int(p.get("value") or 0)
            tot[i] = int(p.get("norm") or 0) or None
    return {"q": q, "first": DOC_START.isoformat(), "counts": cnt, "totals": tot}


def tv_series(q, cty, start, end, stations):
    """Percent of monitored clips per station (timelinevol) times the station's clips that day (timelinevolnorm)."""
    n = (end - start).days + 1
    clips, totals = [0.0] * n, [0.0] * n
    seen = [False] * n
    for a, b in chunks_for(start, end):
        vol = get(TV, {"query": f"{q} {stations}", "mode": "timelinevol", "format": "json", "startdatetime": ts(a), "enddatetime": ts(b, True)})
        nrm = get(TV, {"query": stations, "mode": "timelinevolnorm", "format": "json", "startdatetime": ts(a), "enddatetime": ts(b, True)})
        if any(k in vol for k in ("_error", "_text")) or any(k in nrm for k in ("_error", "_text")):
            return {"q": q, "country": cty, "error": vol.get("_error") or vol.get("_text") or nrm.get("_error") or nrm.get("_text")}
        tot = {}
        for s in nrm.get("timeline") or []:
            for p in s.get("data") or []:
                tot[(s.get("series"), day_of(p["date"]))] = float(p.get("value") or 0)
        pct = {}
        for s in vol.get("timeline") or []:
            for p in s.get("data") or []:
                pct[(s.get("series"), day_of(p["date"]))] = float(p.get("value") or 0)
        for (st, d), t in tot.items():
            i = (d - start).days
            if 0 <= i < n:
                totals[i] += t
                clips[i] += pct.get((st, d), 0.0) / 100.0 * t
                seen[i] = True
    return {"q": q, "country": cty, "first": start.isoformat(),
            "clips": [round(c, 2) if s else None for c, s in zip(clips, seen)],
            "totals": [round(t, 1) if s else None for t, s in zip(totals, seen)]}


def main() -> int:
    if os.path.exists(stop_file()):
        print("stop marker for today exists; refusing to run:", open(stop_file()).read().strip())
        return 1
    reg = json.load(open(REG))
    docq, tvq = plan(reg)
    only = sys.argv[1] if len(sys.argv) > 1 else "all"
    out = json.load(open(OUT)) if os.path.exists(OUT) else {"protocol": "ripples/docs/sensors_plan_v1.md", "doc": [], "tv": []}
    out["run"] = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    have_doc = {r["q"] for r in out["doc"] if "counts" in r}
    have_tv = {(r["q"], r["country"]) for r in out["tv"] if "clips" in r}
    out["stopped"] = None
    try:
        if only in ("all", "doc"):
            for i, q in enumerate(docq):
                if q in have_doc:
                    continue
                r = doc_series(q, reg["doc_suffix"])
                out["doc"] = [x for x in out["doc"] if x["q"] != q] + [r]
                print(f"doc {i + 1}/{len(docq)}", q, "points" if "counts" in r else r, flush=True)
        if only == "panel-tv":  # plan section 7: television only around catalyst candidates (from sensors_v1.json)
            res = json.load(open(os.path.join(ROOT, "docs", "results", "sensors_v1.json")))
            cands = [c for c in res["catalysts"]["top20"]] + [c for c in res["catalysts"].get("decoy_entity_candidates", [])]
            cands += [c for c in res["catalysts"].get("all_candidates", []) if c not in cands]
            tvq = {it["entity"]: it["q"]["tv"] for it in reg["items"] if it["set"] == "E"}
            want = {}
            for c in cands:
                d = D(c["onset"])
                k = (tvq[c["entity"]], "US")
                a, b = d - dt.timedelta(days=150), d + dt.timedelta(days=30)
                if k in want:
                    want[k] = (min(want[k][0], a), max(want[k][1], b))
                else:
                    want[k] = (a, b)
            prev = {(x["q"], x.get("country")): x for x in out["tv"] if "clips" in x}
            for i, ((q, cty), (a, b)) in enumerate(want.items()):
                if (q, cty) in prev:  # a step already holds this query: widen to cover both (whole chunks are cached)
                    x = prev[(q, cty)]
                    a = min(a, D(x["first"]))
                    b = max(b, D(x["first"]) + dt.timedelta(days=len(x["clips"]) - 1))
                r = tv_series(q, cty, max(a, dt.date(2009, 7, 2)), min(b, DOC_END), reg["tv_stations"][cty])
                out["tv"] = [x for x in out["tv"] if (x["q"], x.get("country")) != (q, cty)] + [r]
                print(f"panel tv {i + 1}/{len(want)}", q, "ok" if "clips" in r else r, flush=True)
        if only in ("all", "tv"):
            for i, t in enumerate(tvq):
                if (t["q"], t["country"]) in have_tv:
                    continue
                r = tv_series(t["q"], t["country"], t["start"], t["end"], reg["tv_stations"][t["country"]])
                out["tv"] = [x for x in out["tv"] if (x["q"], x.get("country")) != (t["q"], t["country"])] + [r]
                print(f"tv {i + 1}/{len(tvq)}", t["q"], t["country"], "ok" if "clips" in r else r, flush=True)
    except Stop as e:
        out["stopped"] = f"{e} at {dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}"
        print("stopped:", e, flush=True)
    out["requests_used"] = out.get("requests_used", 0) + USED[0]
    json.dump(out, open(OUT, "w"), separators=(",", ":"), ensure_ascii=False)
    print("requests this run:", USED[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
