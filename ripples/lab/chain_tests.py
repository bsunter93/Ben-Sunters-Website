"""Chain tests v1 (ripples/docs/chain_tests_v1.md, ledger 1498): event -> Seattle library checkouts, in time order.

Input: a JSON file {"series": {heading: {"YYYY-MM": n}}, "panel_median": {"YYYY-MM": median log1p(n)}}, exported from
ripples.att_sea. Output: chain_tests_v1.json. Pure computation; no network.
"""
from __future__ import annotations

import json
import sys

import numpy as np

SEED, N_PLACEBO = 20260930, 200
CHAINS = [("The Queen's Gambit", "2020-10", "Chess"), ("Chernobyl (HBO)", "2019-05", "Chernobyl"),
          ("Tiger King", "2020-03", "Tigers"), ("GameStop short squeeze", "2021-01", "Stocks"),
          ("Wordle", "2022-01", "Word games"), ("Tokyo Olympics", "2021-07", "Skateboarding"),
          ("Tokyo Olympics", "2021-07", "Rock climbing"), ("Tidying Up with Marie Kondo", "2019-01", "Orderliness"),
          ("The Last Dance", "2020-04", "Basketball"), ("Cobra Kai on Netflix", "2020-08", "Karate"),
          ("Oppenheimer", "2023-07", "Atomic bomb"), ("Barbie", "2023-07", "Barbie dolls"),
          ("Dune (film)", "2021-10", "Dune (Imaginary place)")]
FLAGS = {"Tigers": "falls in the 2020 library closure", "Basketball": "falls in the 2020 library closure",
         "Atomic bomb": "same month as Barbie", "Barbie dolls": "same month as Oppenheimer"}


def months(a="2005-04", b="2026-08"):
    y, m = map(int, a.split("-"))
    out = []
    while f"{y}-{m:02d}" <= b:
        out.append(f"{y}-{m:02d}")
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)
    return out


def main() -> int:
    src = json.load(open(sys.argv[1]))
    out_path = sys.argv[2] if len(sys.argv) > 2 else "chain_tests_v1.json"
    M = months()
    idx = {m: i for i, m in enumerate(M)}
    med = np.array([src["panel_median"].get(m, np.nan) for m in M], dtype=float)
    rng = np.random.default_rng(SEED)
    rep = {"protocol": "ripples/docs/chain_tests_v1.md", "ledger": 1498, "seed": SEED, "placebos": "all admissible months", "chains": []}
    zs = []
    for event, m0, head in CHAINS:
        s = src["series"].get(head)
        row = {"event": event, "month": m0, "heading": head, "flag": FLAGS.get(head)}
        if not s:
            row["skip"] = "no checkouts found for this heading"
            rep["chains"].append(row)
            continue
        raw = np.array([np.log1p(s.get(m, 0)) for m in M]) - med
        x = np.full(len(M), np.nan)
        for i in range(36, len(M)):  # minus the median of the same calendar month in the previous 3 years
            prev = [raw[i - 12 * k] for k in (1, 2, 3) if np.isfinite(raw[i - 12 * k])]
            if len(prev) >= 2 and np.isfinite(raw[i]):
                x[i] = raw[i] - np.median(prev)

        def effect(i):
            post, pre = x[i:i + 3], x[i - 6:i]
            if np.isfinite(post).sum() < 3 or np.isfinite(pre).sum() < 4:
                return np.nan
            return float(np.nanmean(post) - np.nanmean(pre))

        i0 = idx[m0]
        obs = effect(i0)
        lo = max(idx["2008-01"], 42)
        pool = [i for i in range(lo, len(M) - 3) if abs(i - i0) >= 7 and np.isfinite(effect(i))]
        # every admissible month is a placebo (about 200; fewer than 200 exist from 2008, so none is drawn twice)
        P = np.array([effect(i) for i in pool])
        p = float((1 + (P >= obs).sum()) / (1 + N_PLACEBO)) if np.isfinite(obs) else None
        pm, ps = float(np.median(P)), float(1.4826 * np.median(np.abs(P - np.median(P))))
        z = float(np.clip((obs - pm) / ps, -4, 4)) if np.isfinite(obs) and ps > 0 else None
        pre = x[i0 - 12:i0]
        thr = np.nanmean(pre) + 2 * 1.4826 * np.nanmedian(np.abs(pre - np.nanmedian(pre)))
        onset = next((M[i] for i in range(i0 - 3, min(i0 + 7, len(M))) if np.isfinite(x[i]) and x[i] > thr), None)
        order_ok = onset is not None and onset >= m0
        row.update(effect=None if not np.isfinite(obs) else round(obs, 3), p=p, z=None if z is None else round(z, 2),
                   onset=onset, order_ok=bool(order_ok), passes=bool(p is not None and p <= 0.05 and order_ok),
                   checkouts={m: int(s.get(m, 0)) for m in M[i0 - 12:i0 + 7]})
        if z is not None:
            zs.append(z)
        rep["chains"].append(row)
    n = len(zs)
    if n:
        pooled = sum(zs) / np.sqrt(n)
        rep.update(n_scored=n, passing=int(sum(c.get("passes", False) for c in rep["chains"])),
                   expected_by_chance=round(0.05 * n, 2), pooled_z=round(float(pooled), 2))
    json.dump(rep, open(out_path, "w"), indent=1)
    for c in rep["chains"]:
        print(c["heading"], c.get("effect"), c.get("p"), c.get("onset"), c.get("passes"), c.get("skip", ""))
    print({k: rep.get(k) for k in ("n_scored", "passing", "expected_by_chance", "pooled_z")})
    return 0


if __name__ == "__main__":
    sys.exit(main())
