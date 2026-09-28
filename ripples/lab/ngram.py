"""Google Books Ngram (English, 2020 release) yearly word frequencies for the cultural lab (direction D-26).

Streams the 24 official 1-gram files and the total-count file from storage.googleapis.com (public, keyless; the dataset
is licensed CC BY 3.0), keeps untagged lower-cased alphabetic words (apostrophes and hyphens allowed) for 1990-2019, sums
case variants, and keeps words with at least --min-total matches over 2000-2019. Output (cached, not stored in the
database): LAB_CACHE/ngram.npz with words[W], years[Y], counts[W, Y] (int64) and totals[Y] (all words that year), so
frequency = counts / totals. Aggregates only; no personal data exists in this source.
"""
from __future__ import annotations

import argparse
import gzip
import os
import re
import sys
import time
import urllib.request

import numpy as np

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
BASE = "http://storage.googleapis.com/books/ngrams/books/20200217/eng/"
CACHE = os.path.expanduser(os.environ.get("LAB_CACHE", "~/.cache/ripples-lab"))
WORD = re.compile(r"^[A-Za-z][A-Za-z'\-]{0,39}$")


def open_stream(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    return urllib.request.urlopen(req, timeout=300)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--y0", type=int, default=1990)
    ap.add_argument("--y1", type=int, default=2019)
    ap.add_argument("--min-total", type=int, default=20000)
    ap.add_argument("--files", type=int, default=24)
    a = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    out = os.path.join(CACHE, "ngram.npz")
    if os.path.exists(out):
        print("ngram.npz cached")
        return 0
    Y = a.y1 - a.y0 + 1
    acc: dict[str, np.ndarray] = {}
    t0 = time.time()
    for k in range(a.files):
        url = f"{BASE}1-{k:05d}-of-{a.files:05d}.gz"
        n_lines = kept = 0
        with open_stream(url) as raw, gzip.GzipFile(fileobj=raw) as gz:
            for line in gz:
                n_lines += 1
                parts = line.decode("utf-8", "replace").rstrip("\n").split("\t")
                w = parts[0]
                if "_" in w or not WORD.match(w):
                    continue
                vec = None
                for p in parts[1:]:
                    yr, mc, _vc = p.split(",")
                    y = int(yr)
                    if a.y0 <= y <= a.y1:
                        if vec is None:
                            vec = np.zeros(Y, dtype=np.int64)
                        vec[y - a.y0] += int(mc)
                if vec is None:
                    continue
                key = w.lower()
                if key in acc:
                    acc[key] += vec
                else:
                    acc[key] = vec
                kept += 1
        # prune rare words between files to bound memory
        cut = 2000 - a.y0
        acc = {w: v for w, v in acc.items() if v[cut:].sum() >= a.min_total // 4}
        print(f"file {k + 1}/{a.files}: {n_lines} lines, {kept} kept, {len(acc)} words ({time.time() - t0:.0f}s)", flush=True)
    cut = 2000 - a.y0
    words = sorted(w for w, v in acc.items() if v[cut:].sum() >= a.min_total)
    counts = np.stack([acc[w] for w in words]) if words else np.zeros((0, Y), dtype=np.int64)
    totals = np.zeros(Y, dtype=np.int64)
    with open_stream(BASE + "totalcounts-1") as r:
        for tok in r.read().decode().split():
            p = tok.split(",")
            if len(p) >= 2 and p[0].isdigit() and a.y0 <= int(p[0]) <= a.y1:
                totals[int(p[0]) - a.y0] = int(p[1])
    np.savez_compressed(out, words=np.array(words), years=np.arange(a.y0, a.y1 + 1), counts=counts, totals=totals)
    print(f"saved {len(words)} words x {Y} years ({time.time() - t0:.0f}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
