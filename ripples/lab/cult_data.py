"""Cultural lab substrate (direction D-26, Q2): daily en.wikipedia pageviews for a broad article panel + the event catalog.

Panel: the ~1,000 level-3 Vital Articles (Wikipedia's list of core topics), read from the MediaWiki API. These are
broad outcome topics (Chess, Marriage, Tobacco, ...), not the catalog titles themselves, so a planted ripple lands on
the kind of series a real one would. Views: Wikimedia REST pageviews API, per article, daily, user agent only,
2015-07-01 to the last full month. Events: public.att_cult_catalog (Wikidata catalog, 2015+), via the service role.

Writes $LAB_CACHE/pv.npz (articles, days as ordinals, views float32 with NaN for missing), $LAB_CACHE/events.json, and
$LAB_CACHE/ev_pv.npz (each event's own English Wikipedia article views, titles resolved through Wikidata sitelinks).
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


BACKOFF_429 = os.environ.get("ALLOW_429_BACKOFF") == "1"  # owner-approved: honor Retry-After, max 2 retries


def get(url: str, _tries: int = 0) -> dict:
    headers = {"User-Agent": UA, "Accept": "application/json"}
    token = os.environ.get("WIKIMEDIA_API_TOKEN", "").strip()
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 429 and BACKOFF_429 and _tries < 2:
            # Wikimedia etiquette: wait as long as the server asks (capped at 120 s), then retry, serially
            try:
                wait = min(120, max(5, int(e.headers.get("Retry-After", "60"))))
            except ValueError:
                wait = 60
            print(f"HTTP 429: waiting {wait} s as asked (retry {_tries + 1} of 2)", flush=True)
            time.sleep(wait)
            return get(url, _tries + 1)
        if e.code in (403, 429, 503):
            raise Stop(f"HTTP {e.code}") from None
        if e.code == 404:
            return {}
        raise


def page_links(title: str, ns: str) -> list[str]:
    out, cont = [], {}
    while True:
        q = {"action": "query", "format": "json", "redirects": "1", "titles": title, "prop": "links", "plnamespace": ns,
             "pllimit": "max"} | cont
        j = get("https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(q))
        for p in (j.get("query") or {}).get("pages", {}).values():
            out += [l["title"] for l in p.get("links", [])]
        if "continue" not in j:
            return out
        cont = j["continue"]
        time.sleep(0.5)


def titles_with_redirects(title: str, cap: int = 100) -> list[str]:
    """The article's current title plus every title that redirects to it (namespace 0). Pageviews are stored under
    the title at view time, so an article renamed after an event keeps its early views under the old title, which
    is now a redirect. Summing over all of them recovers the full attention series."""
    out, cont, canon = [], {}, None
    while True:
        q = {"action": "query", "format": "json", "redirects": "1", "titles": title, "prop": "redirects",
             "rdnamespace": "0", "rdlimit": "max"} | cont
        j = get("https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(q))
        for p in (j.get("query") or {}).get("pages", {}).values():
            if "missing" in p:
                continue
            canon = p.get("title", canon)
            out += [r["title"] for r in p.get("redirects", [])]
        if "continue" not in j:
            break
        cont = j["continue"]
        time.sleep(0.5)
    return ([canon] if canon else []) + sorted(set(out))[:cap]


def vital_articles() -> list[str]:
    """Level-3 Vital Articles. The list has moved between page layouts over the years, so try the known ones in
    order: the level-3 page ("Level 3"; "Level/3" redirects to it as of 2026-09), then level-3 subpages linked from
    the main page, then the main page."""
    for title in ("Wikipedia:Vital articles/Level 3", "Wikipedia:Vital articles/Level/3"):
        got = set(page_links(title, "0"))
        if len(got) >= 500:
            return sorted(got)
    subs = sorted({t for src in ("Wikipedia:Vital articles", "Wikipedia:Vital articles/Level/3")
                   for t in page_links(src, "4") if t.startswith(("Wikipedia:Vital articles/Level/3/",
                                                                     "Wikipedia:Vital articles/Level 3/"))})
    got = set()
    for t in subs:
        got |= set(page_links(t, "0"))
        time.sleep(0.5)
    if len(got) < 500:
        got |= set(page_links("Wikipedia:Vital articles", "0"))
    return sorted(got)


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


def enwiki_titles(qids: list[str]) -> dict[str, str]:
    """Wikidata QID -> English Wikipedia article title, 50 ids per request."""
    out = {}
    for k in range(0, len(qids), 50):
        q = {"action": "wbgetentities", "format": "json", "ids": "|".join(qids[k:k + 50]), "props": "sitelinks",
             "sitefilter": "enwiki"}
        j = get("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode(q))
        for qid, ent in (j.get("entities") or {}).items():
            t = ((ent.get("sitelinks") or {}).get("enwiki") or {}).get("title")
            if t:
                out[qid] = t
        time.sleep(0.5)
    return out


def event_views(end: dt.date, D: int) -> None:
    """Each catalog event's own daily attention (its English Wikipedia article), for attention-coupling methods.
    Writes ev_pv.npz: qids, titles, views[E, D] on the same day grid as pv.npz."""
    path = os.path.join(CACHE, "events.json")
    if not os.path.exists(path):
        return
    ev = json.load(open(path))
    tmap_f = os.path.join(CACHE, "ev_titles.json")
    if not os.path.exists(tmap_f):
        wd = [e["qid"] for e in ev if e["qid"].startswith("Q")]
        tmap = enwiki_titles(wd)
        tmap |= {e["qid"]: e["title"] for e in ev if not e["qid"].startswith("Q") and e.get("title")}
        json.dump(tmap, open(tmap_f, "w"))
    tmap = json.load(open(tmap_f))
    os.makedirs(os.path.join(CACHE, "evpv"), exist_ok=True)
    print(f"event articles: {len(tmap)} of {len(ev)}", flush=True)
    for n, (qid, t) in enumerate(sorted(tmap.items())):
        f = os.path.join(CACHE, "evpv", urllib.parse.quote(qid, safe="") + ".json")
        if os.path.exists(f):
            continue
        json.dump(views(t, end), open(f, "w"))
        time.sleep(0.5)
        if n % 100 == 0:
            print(f"events {n}/{len(tmap)}", flush=True)
    qids, titles, rows = [], [], []
    for qid, t in sorted(tmap.items()):
        f = os.path.join(CACHE, "evpv", urllib.parse.quote(qid, safe="") + ".json")
        if not os.path.exists(f):
            continue
        s = json.load(open(f))
        if not s:
            continue
        row = np.full(D, np.nan, np.float32)
        for k, v in s.items():
            i = (dt.date(int(k[:4]), int(k[4:6]), int(k[6:8])) - START).days
            if 0 <= i < D:
                row[i] = v
        qids.append(qid)
        titles.append(t)
        rows.append(row)
    if rows:
        np.savez_compressed(os.path.join(CACHE, "ev_pv.npz"), qids=np.array(qids), titles=np.array(titles),
                            views=np.stack(rows))
    print(json.dumps({"event_series": len(rows)}), flush=True)


def main() -> int:
    os.makedirs(os.path.join(CACHE, "pv"), exist_ok=True)
    events()
    today = dt.date.today()
    end = today.replace(day=1) - dt.timedelta(days=1)
    lst = os.path.join(CACHE, "vital_l3.json")
    stop = None
    try:
        if not os.path.exists(lst):
            json.dump(vital_articles(), open(lst, "w"))
        titles = json.load(open(lst))
        print(f"panel: {len(titles)} articles", flush=True)
        if len(titles) < 500:
            os.remove(lst)
            sys.exit(f"article list too small ({len(titles)}); the Vital Articles page layout changed")
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
    if stop is None:
        try:
            event_views(end, D)
        except Stop as e:
            print(f"event views stopped: {e}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
