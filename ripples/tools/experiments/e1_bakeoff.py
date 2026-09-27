"""E1 method bake-off (experiments program, ledger 1272; ripples/docs/experiments.md).

Input: the placebo-only extract from ripples.att_e1_extract (donor counties only). Each replicate draws, per event, as
many pseudo-treated counties as the real event had designated counties (from that event's donors), injects an effect of
size delta into their window outcome, and asks each method for a one-sided p-value for "effect < 0". Reports recall
(share of replicates with p <= 0.05) per method and delta; delta = 0 is the false-positive rate. Because nominal p-values
can be miscalibrated, it also reports size-adjusted recall: each method's cutoff is set so exactly 5% of delta = 0
replicates pass, which puts all methods on equal terms. No real treated unit is
ever used.

usage: python e1_bakeoff.py extract.json [--reps 300] [--seed 7]
"""
from __future__ import annotations

import argparse
import json
import math
import random
import statistics as st

DELTAS = [0.0, -0.005, -0.01, -0.02, -0.03]


def norm_sf(z: float) -> float:
    return 0.5 * math.erfc(z / math.sqrt(2))


def p_lower(est: float, var: float) -> float:
    """One-sided p for est < 0."""
    if var <= 0:
        return 1.0 if est >= 0 else 0.0
    return 1 - norm_sf(est / math.sqrt(var))


def prep(ev: dict) -> list[dict]:
    out = []
    for d in ev.get("donors") or []:
        pre = d["pre"]
        base = sum(pre) / len(pre)
        diffs = [b - a for a, b in zip(pre, pre[1:])]
        sd = st.pstdev(diffs) if len(diffs) > 1 else 0.0
        q = [sum(pre[i:i + 3]) / 3 - base for i in range(0, 12, 3)]   # quarterly shape, level removed
        out.append({"y": d["w"] - base, "sd": max(sd, 1e-4), "q": q})
    return out


def event_stats(tr, co, method):
    yt = [u["y"] for u in tr]; yc = [u["y"] for u in co]
    if method in ("M1", "M4", "M5"):
        d = st.mean(yt) - st.mean(yc)
        v = (st.pvariance(yc) if len(yc) > 1 else 0.0) * (1 / len(yt) + 1 / len(yc))
        return d, v
    if method == "M2":   # precision-weighted means
        wt = [1 / u["sd"] ** 2 for u in tr]; wc = [1 / u["sd"] ** 2 for u in co]
        mt = sum(w * u["y"] for w, u in zip(wt, tr)) / sum(wt)
        mc = sum(w * u["y"] for w, u in zip(wc, co)) / sum(wc)
        resid = [u["y"] - mc for u in co]
        s2 = sum(w * r * r for w, r in zip(wc, resid)) / sum(wc)
        return mt - mc, s2 * (sum(w * w for w in wt) / sum(wt) ** 2 + sum(w * w for w in wc) / sum(wc) ** 2)
    if method == "M3":   # 10 nearest donors by pre-period shape for each treated county
        diffs, vs = [], []
        for u in tr:
            near = sorted(co, key=lambda c: sum((a - b) ** 2 for a, b in zip(u["q"], c["q"])))[:10]
            ys = [c["y"] for c in near]
            diffs.append(u["y"] - st.mean(ys)); vs.append(st.pvariance(ys) / len(ys) if len(ys) > 1 else 0.0)
        v = (st.pvariance(diffs) / len(diffs) if len(diffs) > 1 else 0.0) + st.mean(vs) / len(diffs)
        return st.mean(diffs), v
    raise ValueError(method)


def combine(stats, method, doses):
    ds = [d for d, _ in stats]; vs = [max(v, 1e-12) for _, v in stats]
    if method == "M4":   # DerSimonian-Laird random effects
        w = [1 / v for v in vs]
        mu = sum(wi * di for wi, di in zip(w, ds)) / sum(w)
        qstat = sum(wi * (di - mu) ** 2 for wi, di in zip(w, ds))
        c = sum(w) - sum(wi * wi for wi in w) / sum(w)
        tau2 = max(0.0, (qstat - (len(ds) - 1)) / c) if c > 0 else 0.0
        w2 = [1 / (v + tau2) for v in vs]
        return sum(wi * di for wi, di in zip(w2, ds)) / sum(w2), 1 / sum(w2)
    if method == "M5":   # dose-weighted
        w = [math.log1p(x) for x in doses]
        s = sum(w)
        return sum(wi * di for wi, di in zip(w, ds)) / s, sum(wi * wi * vi for wi, vi in zip(w, vs)) / s ** 2
    n = len(ds)   # plain mean of event effects
    return sum(ds) / n, sum(vs) / n ** 2


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("extract")
    ap.add_argument("--reps", type=int, default=300)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    raw = json.load(open(a.extract))
    events = []
    for ev in raw["events"] or []:
        units = prep(ev)
        if len(units) >= ev["n_t"] + 5:
            events.append((ev["n_t"], ev["dose"], units))
    rng = random.Random(a.seed)
    methods = ["M1", "M2", "M3", "M4", "M5"]
    hits = {(m, d): 0 for m in methods for d in DELTAS}
    zs = {(m, d): [] for m in methods for d in DELTAS}
    for _ in range(a.reps):
        draws = []
        for n_t, dose, units in events:
            idx = set(rng.sample(range(len(units)), n_t))
            draws.append((dose, [units[i] for i in idx], [u for i, u in enumerate(units) if i not in idx]))
        for delta in DELTAS:
            for m in methods:
                stats = [event_stats([dict(u, y=u["y"] + delta) for u in tr], co, m) for _, tr, co in draws]
                est, var = combine(stats, m, [dose for dose, _, _ in draws])
                if p_lower(est, var) <= 0.05:
                    hits[(m, delta)] += 1
                zs[(m, delta)].append(est / math.sqrt(var) if var > 0 else (-1e9 if est < 0 else 1e9))
    # Size-adjusted recall: each method's cutoff is the 5th percentile of its own z at delta = 0, so every method has
    # exactly a 5% false-positive rate on placebo data and recall is compared on equal terms.
    adj = {}
    for m in methods:
        null = sorted(zs[(m, 0.0)])
        cut = null[max(0, int(0.05 * len(null)) - 1)]
        adj[m] = {"cutoff_z": round(cut, 3),
                  **{f"{d:+.3f}": round(sum(z <= cut for z in zs[(m, d)]) / a.reps, 3) for d in DELTAS}}
    res = {"n_events": len(events), "reps": a.reps,
           "recall_nominal_p05": {m: {f"{d:+.3f}": round(hits[(m, d)] / a.reps, 3) for d in DELTAS} for m in methods},
           "recall_size_adjusted_5pct": adj}
    print(json.dumps(res, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
