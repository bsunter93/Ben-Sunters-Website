"""NYT outcome panel for the discovery engine: daily article counts per NYT index tag, on the same day grid as the
Wikipedia panel (pv.npz), so q3_run.py can use news coverage as the outcome instead of page views.

Input: $LAB_CACHE/nyt/YYYY-MM.json.gz from nyt_archive.py (counts only: articles per day and per tag per day).
Output: $LAB_CACHE/nyt_pv.npz with articles = tag names ("subject:Chess", "persons:...", ...), days = the Wikipedia
panel's day ordinals, views = 7-day trailing sums of the tag's daily article count (float32). The 7-day sum turns
sparse daily counts into a usable series; the engine then takes log(1 + x) and removes the all-series daily median,
which absorbs changes in the paper's total volume.

Tags kept (fixed rule, set before any event is tested): at least 300 articles over the panel window and present in at
least 25% of its months; the 1,500 largest by total articles.
"""
from __future__ import annotations

import datetime as dt
import glob
import gzip
import json
import os
import sys

import numpy as np

CACHE = os.path.expanduser(os.environ.get("LAB_CACHE", "~/.cache/ripples-lab"))
MIN_TOTAL, MIN_MONTH_SHARE, MAX_TAGS = 300, 0.25, 1500


def main() -> int:
    grid = np.load(os.path.join(CACHE, "pv.npz"), allow_pickle=False)["days"]
    start, D = dt.date.fromordinal(int(grid[0])), len(grid)
    end = start + dt.timedelta(days=D - 1)
    files = sorted(glob.glob(os.path.join(CACHE, "nyt", "*.json.gz")))
    counts, months_seen, total = {}, {}, np.zeros(D)
    per_month = {}
    for f in files:
        ym = os.path.basename(f)[:7]
        y, m = int(ym[:4]), int(ym[5:7])
        if dt.date(y, m, 1) > end or (dt.date(y, m, 1) + dt.timedelta(days=31)) < start:
            continue
        d = json.load(gzip.open(f, "rt", encoding="utf-8"))
        per_month[ym] = (sum(d["days"].values()), len(d["kw"]))
        for day, n in d["days"].items():
            i = (dt.date.fromisoformat(day) - start).days
            if 0 <= i < D:
                total[i] += n
        for tag, byday in d["kw"].items():
            arr = counts.get(tag)
            for day, n in byday.items():
                i = (dt.date.fromisoformat(day) - start).days
                if 0 <= i < D:
                    if arr is None:
                        arr = counts[tag] = np.zeros(D, np.float32)
                    arr[i] += n
            if arr is not None:
                months_seen[tag] = months_seen.get(tag, 0) + 1
    n_months = len(per_month)
    keep = [t for t, a in counts.items() if a.sum() >= MIN_TOTAL and months_seen.get(t, 0) >= MIN_MONTH_SHARE * n_months]
    keep = sorted(keep, key=lambda t: -counts[t].sum())[:MAX_TAGS]
    ker = np.ones(7, np.float32)
    rows = np.stack([np.convolve(counts[t], ker)[:D] for t in keep]) if keep else np.zeros((0, D), np.float32)
    rows[:, :6] = np.nan  # first days lack a full week
    np.savez_compressed(os.path.join(CACHE, "nyt_pv.npz"), articles=np.array(keep), days=grid, views=rows)
    thin = sorted(ym for ym, (arts, tags) in per_month.items() if arts and tags == 0)
    print(json.dumps({"months": n_months, "tags_total": len(counts), "tags_kept": len(keep),
                      "articles_in_window": int(total.sum()), "months_with_articles_but_no_tags": thin,
                      "top_tags": keep[:15]}, indent=1), flush=True)
    return 0 if keep else 1


if __name__ == "__main__":
    sys.exit(main())
