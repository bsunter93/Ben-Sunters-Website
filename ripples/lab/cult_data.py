"""Cultural lab substrate (direction D-26, Q2): daily en.wikipedia pageviews for a broad article panel + the event catalog.

Panel: the ~1,000 level-3 Vital Articles (Wikipedia's list of core topics), read from the MediaWiki API. These are
broad outcome topics (Chess, Marriage, Tobacco, ...), not the catalog titles themselves, so a planted ripple lands on
the kind of series a real one would. Views: Wikimedia REST pageviews API, per article, daily, user agent only,
2015-07-01 to the last full month. Events: public.att_cult_catalog (Wikidata catalog, 2015+), via the service role.

Writes $LAB_CACHE/pv.npz (articles, days as ordinals, views float32 with NaN for missing) and $LAB_CACHE/events.json.
Per-article downloads are cached under $LAB_CACHE/pv/, so a rerun resumes. Aggregate public counts only.

Politeness: honest UA, one request at a time with a 0.5 s pause (well under Wikimedia's published limits), stop on
403/429/503 with no retry. The pv.npz is built from whatever was downloaded (articles with no data are dropped).
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

import numpy as np

CACHE = os.path.expanduser(os.environ.get("LAB_CACHE", "~/.cache/ripples-lab"))
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
START = dt.date(2015, 7, 1)


class Stop(Exception):
    pass


def get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (403, 429, 503):
            raise Stop(f"HTTP {e.code}") from None
        if e.code == 404:
            return {}
        raise


def vital_articles() -> list[str]:
    out, cont = [], {}
    while True:
        q = {"action": "query", "format": "json", "titles": "Wikipedia:Vital articles", "prop": "links",
             "plnamespace": "0", "pllimit": "max"} | cont
        j = get("https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(q))
        for p in (j.get("query") or {}).get("pages", {}).values():
            out += [l["title"] for l in p.get("links", [])]
        if "continue" not in j:
            break
        cont = j["continue"]
        time.sleep(0.5)
    return sorted(set(out))


def views(title: str, end: dt.date) -> dict[str, int]:
    t = urllib.parse.quote(title.replace(" ", "_"), safe="")
    url = (f"https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/{t}/daily/"
           f"{START:%Y%m%d}00/{end:%Y%m%d}00")
    return {it["timestamp"][:8]: int(it["views"]) for it in get(url).get("items", [])}


def events() -> None:
    path = os.path.join(CACHE, "events.json")
    if os.path.exists(path) or not os.environ.get("SUPABASE_SERVICE_ROLE_KEY"):
        return
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools", "bq"))
    from common import Supabase
    cat = Supabase().rpc("att_cult_catalog", {"p_from": "2015-01-01"}) or []
    ev = [{k: e.get(k) for k in ("qid", "typ", "title", "released", "links")} for e in cat]
    json.dump(ev, open(path, "w"))
    print(f"events: {len(ev)}", flush=True)


def main() -> int:
    os.makedirs(os.path.join(CACHE, "pv"), exist_ok=True)
    events()
    today = dt.date.today()
    end = today.replace(day=1) - dt.timedelta(days=1)
    lst = os.path.join(CACHE, "vital.json")
    stop = None
    try:
        if not os.path.exists(lst):
            json.dump(vital_articles(), open(lst, "w"))
        titles = json.load(open(lst))
        print(f"panel: {len(titles)} articles", flush=True)
        for n, t in enumerate(titles):
            f = os.path.join(CACHE, "pv", urllib.parse.quote(t, safe="") + ".json")
            if os.path.exists(f):
                continue
            json.dump(views(t, end), open(f, "w"))
            time.sleep(0.5)
            if n % 100 == 0:
                print(f"{n}/{len(titles)}", flush=True)
    except Stop as e:
        stop = str(e)
        print(f"stopped: {stop}", flush=True)
    titles = json.load(open(lst)) if os.path.exists(lst) else []
    D = (end - START).days + 1
    arts, rows = [], []
    for t in titles:
        f = os.path.join(CACHE, "pv", urllib.parse.quote(t, safe="") + ".json")
        if not os.path.exists(f):
            continue
        s = json.load(open(f))
        if len(s) < D * 0.9:
            continue
        row = np.full(D, np.nan, np.float32)
        for k, v in s.items():
            i = (dt.date(int(k[:4]), int(k[4:6]), int(k[6:8])) - START).days
            if 0 <= i < D:
                row[i] = v
        arts.append(t)
        rows.append(row)
    if rows:
        days = np.array([(START + dt.timedelta(days=i)).toordinal() for i in range(D)])
        np.savez_compressed(os.path.join(CACHE, "pv.npz"), articles=np.array(arts), days=days, views=np.stack(rows))
    print(json.dumps({"articles": len(arts), "days": D, "stop": stop}), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
