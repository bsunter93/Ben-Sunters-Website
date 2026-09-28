"""Wide Wikipedia outcome panel: daily views of the Level-4 Vital Articles (about 10,000), for the discovery engine's
wide lens (ripples/docs/q3_protocol_wide.md). Same rules as cult_data.py: one request at a time with a 1 s pause,
honest User-Agent, stop on 403/429/503 with no retry (no backoff here), resumable from the Actions cache.

  python l4_panel.py fetch   downloads missing articles into $LAB_CACHE/pv/ (shared naming with the Level-3 panel)
  python l4_panel.py build   writes $LAB_CACHE/pv_l4.npz on the fixed window 2015-07-01..2026-08-31

The article list is saved once ($LAB_CACHE/vital_l4.json) and never refreshed, so the panel is fixed.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse

import numpy as np

import cult_data as CD

END = dt.date(2026, 8, 31)
PAUSE = 1.0
PREFIXES = ("Wikipedia:Vital articles/Level/4", "Wikipedia:Vital articles/Level 4")


def level4() -> list[str]:
    """Level-4 Vital Articles: the level-4 subpages (and their subpages) linked from the level-4 index pages."""
    subs, seen = set(), set()
    frontier = [p for p in PREFIXES]
    while frontier:
        page = frontier.pop()
        if page in seen:
            continue
        seen.add(page)
        for t in CD.page_links(page, "4"):
            if t.startswith(tuple(p + "/" for p in PREFIXES)) and t not in seen:
                subs.add(t)
                frontier.append(t)
        time.sleep(PAUSE)
    got = set()
    for page in sorted(subs | set(PREFIXES)):
        got |= set(CD.page_links(page, "0"))
        time.sleep(PAUSE)
    return sorted(got)


def fname(t: str) -> str:
    name = urllib.parse.quote(t, safe="")
    return os.path.join(CD.CACHE, "pv", name + ".json") if len(name) <= 200 else None


def blocked_today() -> bool:
    """Standing rule: after a 403/429/503 there is no retry that UTC day. A stop writes $LAB_CACHE/l4_stopped (the
    date); l4_blocked_dates.txt next to this file lists dates blocked by hand (e.g. a stop recorded by older code)."""
    today = dt.datetime.now(dt.timezone.utc).date().isoformat()
    marker = os.path.join(CD.CACHE, "l4_stopped")
    listed = os.path.join(os.path.dirname(__file__), "l4_blocked_dates.txt")
    dates = set()
    if os.path.exists(marker):
        dates.add(open(marker).read().strip())
    if os.path.exists(listed):
        dates |= {l.strip() for l in open(listed) if l.strip() and not l.startswith("#")}
    return today in dates


def fetch() -> int:
    os.makedirs(os.path.join(CD.CACHE, "pv"), exist_ok=True)
    if blocked_today():
        print("Wikimedia stopped us earlier today; no retry until tomorrow (UTC)", flush=True)
        return 0
    lst = os.path.join(CD.CACHE, "vital_l4.json")
    if not os.path.exists(lst):
        titles = level4()
        if len(titles) < 5000:
            print(f"level-4 list too small ({len(titles)}); the Vital Articles layout changed", flush=True)
            return 1
        json.dump(titles, open(lst, "w"))
    titles = json.load(open(lst))
    todo = [t for t in titles if fname(t) and not os.path.exists(fname(t))]
    print(f"level 4: {len(titles)} articles, {len(todo)} to fetch", flush=True)
    t0 = time.time()
    for n, t in enumerate(todo):
        if time.time() - t0 > float(os.environ.get("L4_BUDGET_MIN", "300")) * 60:
            print(f"time budget reached after {n}; the next run resumes", flush=True)
            break
        try:
            s = CD.views(t, END)
        except (CD.Stop, urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e:
            # any refusal or server error (403/429/5xx, timeouts) ends fetching for the day
            print(f"stopped: {e} after {n}; no retry today", flush=True)
            with open(os.path.join(CD.CACHE, "l4_stopped"), "w") as f:
                f.write(dt.datetime.now(dt.timezone.utc).date().isoformat())
            break
        json.dump(s, open(fname(t), "w"))
        time.sleep(PAUSE)
        if n % 250 == 0:
            print(f"{n}/{len(todo)}", flush=True)
    return 0


def build() -> int:
    lst = os.path.join(CD.CACHE, "vital_l4.json")
    titles = sorted(set(json.load(open(lst))) | set(json.load(open(os.path.join(CD.CACHE, "vital_l3.json")))))
    D = (END - CD.START).days + 1
    arts, rows, missing = [], [], 0
    for t in titles:
        f = fname(t)
        if not f or not os.path.exists(f):
            missing += 1
            continue
        s = json.load(open(f))
        row = np.full(D, np.nan, np.float32)
        for k, v in s.items():
            i = (dt.date(int(k[:4]), int(k[4:6]), int(k[6:8])) - CD.START).days
            if 0 <= i < D:
                row[i] = v
        if np.isfinite(row).sum() < 0.9 * D:
            continue
        arts.append(t)
        rows.append(row)
    days = np.array([(CD.START + dt.timedelta(days=i)).toordinal() for i in range(D)])
    np.savez_compressed(os.path.join(CD.CACHE, "pv_l4.npz"), articles=np.array(arts), days=days, views=np.stack(rows))
    print(json.dumps({"listed": len(titles), "missing": missing, "articles": len(arts), "days": D}), flush=True)
    complete = len(arts) >= 5000 and missing <= 0.05 * len(titles)
    with open(os.path.join(CD.CACHE, "l4_complete"), "w") as f:
        f.write("1" if complete else "0")
    return 0  # the screen job runs only when l4_complete is 1 (a mostly complete panel)


if __name__ == "__main__":
    sys.exit({"fetch": fetch, "build": build}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: 2)())
