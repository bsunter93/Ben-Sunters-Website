"""Sensors v1, Media Cloud leg (ripples/docs/sensors_plan_v1.md). Runs only in .github/workflows/ripples-sensors.yml.

For every registered query (ripples/lab/sensors_queries_v1.json) and its collection, one request to Media Cloud's
search/count-over-time: matching stories per day and the collection's total stories per day. Aggregate counts only; no
story lists, no text, no URLs. The key comes from the environment (a repository secret) and is sent only in the
Authorization header; it is never printed, logged or written.

Politeness: honest user agent; one read of the server's declared rate, then requests spaced at the slower of that rate
and 2 a minute; the run stops on the first 401, 403, 429, 5xx or timeout and writes what it has. Hard cap: 400 requests.
Output: ripples/docs/results/sensors_mediacloud_v1.json.
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

ROOT = os.path.join(os.path.dirname(__file__), "..")
QUERIES = os.path.join(ROOT, "lab", "sensors_queries_v1.json")
OUT = os.path.join(ROOT, "docs", "results", "sensors_mediacloud_v1.json")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
BASE = "https://search.mediacloud.org/api/"
PLATFORM = "onlinenews-mediacloud"
CAP = 400
MIN_SPACING = 31.0          # 2 a minute (the FAQ: "Certain API endpoints are rate-limited to 2 requests per minute")
LAST_DAY = dt.date(2026, 9, 30)
STARTS = {"A": dt.date(2015, 7, 1), "A2": dt.date(2015, 7, 1), "C": dt.date(2015, 7, 1), "D": dt.date(2009, 7, 2),
          "E": dt.date(2017, 1, 1)}
D = dt.date.fromisoformat


class Stop(Exception):
    pass


class Client:
    def __init__(self, key: str):
        self._key = key
        self.used = 0
        self.spacing = MIN_SPACING
        self._last = 0.0

    def get(self, endpoint: str, params: dict) -> dict | None:
        if self.used >= CAP:
            raise Stop("request cap reached")
        wait = self._last + self.spacing - time.time()
        if wait > 0:
            time.sleep(wait)
        url = BASE + endpoint + "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json",
                                                   "Authorization": "Token " + self._key})
        self.used += 1
        self._last = time.time()
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                body = r.read()
        except urllib.error.HTTPError as e:
            if e.code in (401, 403, 429) or e.code >= 500:
                raise Stop(f"HTTP {e.code} on {endpoint}")
            print(f"HTTP {e.code} on {endpoint} for one query; recorded and skipped", flush=True)
            return {"_error": e.code}
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            raise Stop(f"{type(e).__name__} on {endpoint}")
        try:
            return json.loads(body)
        except ValueError:
            raise Stop(f"non-JSON answer on {endpoint}")


def plan_requests(reg: dict) -> list[dict]:
    """One request per unique (query, country): the earliest start and latest end its items need."""
    want: dict = {}
    for it in reg["items"]:
        q = it["q"].get("mc")
        if not q:
            continue
        start = STARTS[it["set"]]
        end = LAST_DAY if it["set"] == "E" else min(LAST_DAY, D(it["ref"]) + dt.timedelta(days=it["lag"] + 30))
        k = (q, it["country"])
        if k in want:
            want[k]["start"] = min(want[k]["start"], start)
            want[k]["end"] = max(want[k]["end"], end)
            want[k]["ids"].append(it["id"])
        else:
            want[k] = {"q": q, "country": it["country"], "start": start, "end": end, "ids": [it["id"]]}
    return list(want.values())


def parse_rate(params: dict) -> float | None:
    """Requests per minute the server declares in search/api-params ("query-rate": "N/m"), or None."""
    qr = ((params or {}).get("params") or {}).get("query-rate")
    if isinstance(qr, str) and "/" in qr:
        n, unit = qr.split("/", 1)
        if n.strip().isdigit() and unit.strip() in ("m", "min", "minute"):
            return float(n)
    return None


def main() -> int:
    reg = json.load(open(QUERIES))
    reqs = plan_requests(reg)
    dry = "--dry-run" in sys.argv
    print(f"{len(reqs)} count-over-time requests planned, plus 2 setup requests", flush=True)
    if dry:
        for r in reqs:
            print(r["country"], r["start"], r["end"], r["q"])
        return 0
    key = os.environ.get("MEDIACLOUD_API_KEY", "")
    if not key:
        print("no key in the environment; nothing run", flush=True)
        return 1
    c = Client(key)
    out = {"protocol": "ripples/docs/sensors_plan_v1.md", "script": "ripples/lab/sensors_mediacloud.py",
           "run": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "platform": PLATFORM,
           "collections": {"US": {"name": "United States - National", "id": 34412234}, "UK": None},
           "declared_rate": None, "spacing_s": None, "requests_used": 0, "stopped": None, "errors": [],
           "totals": {}, "queries": []}

    def save():
        out["requests_used"] = c.used
        tmp = OUT + ".tmp"
        json.dump(out, open(tmp, "w"), separators=(",", ":"), ensure_ascii=False)
        os.replace(tmp, OUT)

    try:
        p = c.get("search/api-params", {})
        rate = parse_rate(p)
        out["declared_rate"] = f"{rate:g}/m" if rate else None
        if rate:
            c.spacing = max(MIN_SPACING, 60.0 / rate + 1.0)
        out["spacing_s"] = c.spacing
        print(f"declared rate {out['declared_rate']}; spacing {c.spacing:.0f} s", flush=True)
        d = c.get("sources/collections/", {"name": "United Kingdom - National", "platform": "online_news", "limit": 20})
        uk = next((x for x in (d or {}).get("results", []) if (x.get("name") or "").strip() == "United Kingdom - National"), None)
        if uk:
            out["collections"]["UK"] = {"name": uk["name"], "id": int(uk["id"])}
        else:
            out["collections"]["UK"] = {"name": "United States - National (no exact UK collection found; UK steps flagged)", "id": 34412234}
        print("UK collection:", out["collections"]["UK"], flush=True)
        save()
        for i, r in enumerate(reqs):
            coll = out["collections"][r["country"]]["id"]
            j = c.get("search/count-over-time", {"q": r["q"], "start": r["start"].isoformat(), "end": r["end"].isoformat(),
                                                 "platform": PLATFORM, "cs": coll})
            rec = {"q": r["q"], "country": r["country"], "collection": coll, "start": r["start"].isoformat(),
                   "end": r["end"].isoformat(), "ids": r["ids"]}
            if not j or "_error" in j:
                rec["error"] = (j or {}).get("_error", "empty")
                out["errors"].append({"q": r["q"], "country": r["country"], "error": rec["error"]})
                out["queries"].append(rec)
                save()
                continue
            pts = ((j.get("count_over_time") or {}).get("counts")) or []
            days = [(p["date"][:10], int(p.get("count") or 0), int(p.get("total_count") or 0)) for p in pts]
            days.sort()
            if days:
                first = D(days[0][0])
                gaps = sorted({(D(b[0]) - D(a[0])).days for a, b in zip(days, days[1:])})
                rec["period_days"] = gaps[0] if gaps else 1
                rec["first"] = days[0][0]
                rec["last"] = days[-1][0]
                if rec["period_days"] == 1:
                    n = (D(days[-1][0]) - first).days + 1
                    cnt = [None] * n
                    for ds, k, t in days:
                        cnt[(D(ds) - first).days] = k
                        tot = out["totals"].setdefault(str(coll), {})
                        tot[ds] = t
                    rec["counts"] = cnt
                else:
                    rec["points"] = [[ds, k, t] for ds, k, t in days]
            else:
                rec["period_days"] = None
            out["queries"].append(rec)
            print(f"{i + 1}/{len(reqs)} {r['country']} points={len(days)} sum={sum(x[1] for x in days)}", flush=True)
            if (i + 1) % 10 == 0:
                save()
    except Stop as e:
        out["stopped"] = str(e)
        print("stopped:", e, flush=True)
    # totals as dense arrays per collection (date -> total stories in the collection that day)
    for coll, tot in list(out["totals"].items()):
        if isinstance(tot, dict) and tot:
            ks = sorted(tot)
            first = D(ks[0])
            n = (D(ks[-1]) - first).days + 1
            arr = [None] * n
            for k2, v in tot.items():
                arr[(D(k2) - first).days] = v
            out["totals"][coll] = {"first": ks[0], "totals": arr}
    save()
    print(f"done: {c.used} requests, stopped={out['stopped']}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
