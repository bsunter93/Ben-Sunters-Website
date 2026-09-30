"""Tiger King ripple map (ripples/docs/tiger_king_map.md): daily Wikipedia attention for each step, to date it.

Fetches daily views (all agents -> user agent only) for a fixed list of articles from the Wikimedia pageviews API, one
request per article, anonymous, honest User-Agent, 1 s apart, stop on 403/429/503. Computes each article's onset: the
first day from 14 days before the release on which the 7-day mean exceeds the pre-period median (days -90..-15) by
5 MAD and by at least 50%. Output: tiger_king_attention.json (daily series 2019-12-01..2023-06-30 and onsets).
"""
from __future__ import annotations

import datetime as dt
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
API = ("https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/"
       "{t}/daily/20191201/20230630")
MAPS = {
    "tiger_king": (dt.date(2020, 3, 20), {  # Netflix release
        "event": ["Tiger_King", "Tiger_King:_Murder,_Mayhem_and_Madness"],
        "Joe_Exotic": ["Joe_Exotic"], "Carole_Baskin": ["Carole_Baskin"], "Big_Cat_Rescue": ["Big_Cat_Rescue"],
        "Exotic_pet": ["Exotic_pet"], "Wildlife_trade": ["Wildlife_trade"],
        "Big_Cat_Public_Safety_Act": ["Big_Cat_Public_Safety_Act"]}),
    "queens_gambit": (dt.date(2020, 10, 23), {  # Netflix release
        "event": ["The_Queen's_Gambit_(miniseries)"], "Beth_Harmon": ["Beth_Harmon"],
        "Chess": ["Chess"], "Queen's_Gambit": ["Queen's_Gambit"], "Chess_opening": ["Chess_opening"],
        "Chess_clock": ["Chess_clock"], "Chess.com": ["Chess.com"], "Chess_set": ["Chess_set"]}),
}
MAP = sys.argv[2] if len(sys.argv) > 2 else "tiger_king"
EVENT, ARTICLES = MAPS[MAP]


def fetch(title):
    req = urllib.request.Request(API.format(t=urllib.parse.quote(title, safe="")), headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return {i["timestamp"][:8]: i["views"] for i in json.load(r)["items"]}
    except urllib.error.HTTPError as e:
        if e.code in (403, 429, 503):
            raise SystemExit(f"stop: HTTP {e.code} on {title}")
        return {}


def main() -> int:
    days = [dt.date(2019, 12, 1) + dt.timedelta(days=i) for i in range((dt.date(2023, 6, 30) - dt.date(2019, 12, 1)).days + 1)]
    keys = [d.strftime("%Y%m%d") for d in days]
    e0 = days.index(EVENT)
    out = {"event_day": EVENT.isoformat(), "series": {}, "onsets": {}}
    for name, titles in ARTICLES.items():
        v = np.zeros(len(days))
        found = False
        for t in titles:
            s = fetch(t)
            time.sleep(1)
            found |= bool(s)
            v += np.array([s.get(k, 0) for k in keys], dtype=float)
        if not found:
            out["onsets"][name] = None
            continue
        out["series"][name] = [int(x) for x in v]
        pre = v[e0 - 90:e0 - 14]
        med = float(np.median(pre))
        mad = float(np.median(np.abs(pre - med))) * 1.4826
        roll = np.convolve(v, np.ones(7) / 7, mode="full")[:len(v)]
        thr = max(med + 5 * mad, med * 1.5, 20)
        on = next((i for i in range(e0 - 14, len(v)) if roll[i] > thr), None)
        out["onsets"][name] = None if on is None else {"day": days[on].isoformat(), "days_after_release": on - e0,
                                                        "pre_median": round(med, 1),
                                                        "peak": int(v[e0:].max()) if v[e0:].size else None}
        print(name, out["onsets"][name], flush=True)
    out["days"] = [days[0].isoformat(), days[-1].isoformat()]
    out["map"] = MAP
    json.dump(out, open(sys.argv[1] if len(sys.argv) > 1 else f"{MAP}_attention.json", "w"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
