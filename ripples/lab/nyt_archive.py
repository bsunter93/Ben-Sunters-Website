"""NYT Archive API: daily article counts per NYT index tag, for the cultural lab (direction D-26; D2 outcome-first).

One request per month returns metadata for every article NYT published that month. From each article only the date
and its index keywords (subject, persons, organizations, glocations, creative_works) are read. What is kept is
counts, never text: for each month, articles per day, and articles per day per tag ("subject:Chess",
"creative_works:Frozen (Movie)", ...). Headlines, abstracts, bylines and URLs are discarded in memory.

Output: $LAB_CACHE/nyt/YYYY-MM.json.gz, one file per month, kept in the Actions cache (not the database). Resumable:
months already on disk are skipped, except the current month, which is refetched.

Politeness and terms: honest UA, one request every 13 s (NYT allows 5 per minute and 500 per day), at most
--max-months per run, stop on 401/403/429/503 with no retry. Key from the NYT_API_KEY environment variable (GitHub
secret), never logged; if it is unset, the script exits cleanly without doing anything.
"""
from __future__ import annotations

import argparse
import datetime as dt
import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
API = "https://api.nytimes.com/svc/archive/v1/{y}/{m}.json"
TAGS = {"subject", "persons", "organizations", "glocations", "creative_works"}


def months(start: str, end: dt.date):
    y, m = map(int, start.split("-"))
    while (y, m) <= (end.year, end.month):
        yield y, m
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)


def fetch(y: int, m: int, key: str) -> list[dict]:
    url = API.format(y=y, m=m) + "?" + urllib.parse.urlencode({"api-key": key})
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return (json.load(r).get("response") or {}).get("docs") or []


def aggregate(docs: list[dict]) -> dict:
    days: Counter = Counter()
    kw: dict[str, Counter] = defaultdict(Counter)
    for d in docs:
        day = (d.get("pub_date") or "")[:10]
        if len(day) != 10:
            continue
        days[day] += 1
        seen = set()
        for k in d.get("keywords") or []:
            if k.get("name") in TAGS and k.get("value"):
                seen.add(f"{k['name']}:{k['value'].strip()}")
        for t in seen:
            kw[t][day] += 1
    return {"days": dict(sorted(days.items())), "kw": {t: dict(c) for t, c in kw.items()}}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", default="2001-01")
    ap.add_argument("--max-months", type=int, default=450)
    ap.add_argument("--pause", type=float, default=13.0)
    a = ap.parse_args()
    key = os.environ.get("NYT_API_KEY", "")
    if not key:
        print("NYT_API_KEY is not set; nothing to do", flush=True)
        return 0
    out = os.path.join(os.environ.get("LAB_CACHE", ".lab-cache"), "nyt")
    os.makedirs(out, exist_ok=True)
    today = dt.date.today()
    res = {"fetched": 0, "skipped": 0, "articles": 0, "stop": None}
    for y, m in months(a.start, today):
        path = os.path.join(out, f"{y}-{m:02d}.json.gz")
        if os.path.exists(path) and (y, m) != (today.year, today.month):
            res["skipped"] += 1
            continue
        if res["fetched"] >= a.max_months:
            break
        if res["fetched"]:
            time.sleep(a.pause)
        try:
            docs = fetch(y, m, key)
        except urllib.error.HTTPError as e:
            if e.code in (401, 403, 429, 503):
                res["stop"] = f"HTTP {e.code} at {y}-{m:02d}"
                break
            print(f"{y}-{m:02d}: HTTP {e.code}", flush=True)
            continue
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            print(f"{y}-{m:02d}: {type(e).__name__}", flush=True)
            continue
        agg = aggregate(docs)
        with gzip.open(path + ".tmp", "wt", encoding="utf-8") as f:
            json.dump(agg, f, separators=(",", ":"))
        os.replace(path + ".tmp", path)
        res["fetched"] += 1
        res["articles"] += len(docs)
        print(f"{y}-{m:02d}: {len(docs)} articles, {len(agg['kw'])} tags", flush=True)
    print(json.dumps(res), flush=True)
    s = os.environ.get("GITHUB_STEP_SUMMARY")
    if s:
        with open(s, "a", encoding="utf-8") as f:
            f.write("### NYT archive\n```\n" + json.dumps(res, indent=1) + "\n```\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
