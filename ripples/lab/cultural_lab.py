"""Cultural lab (direction D-26, protocol ledger 1279): compare discovery methods on daily pageviews with fake events.

Substrate: pv.npz with articles[A], days[D] (ordinal), views[A, D] (daily en.wikipedia user views; NaN = missing) and
events.json (the Wikidata catalog: qid, typ, title, released, links). Fake world: events keep real types and
prominence, but get random release days, so no real ripple is attached to them; ripples of known shape are planted on
random (event, article) pairs. Every candidate for a fake event that is not a planted pair is a false discovery.

Methods (each returns a scored list of (event, article) candidates):
  ghost  D4/D1: response of each article at the event date vs the same article's responses at ghost dates (same-type
         events of similar prominence, other dates) -> z per (event, article).
  anom   D2: outcome-first. For each article, day-level breaks (the largest jumps in 7-day means); each break is
         attributed to events released 0-14 days before it, split across them.
  naive  a before/after z vs the article's own daily noise (the design we are trying to beat).
Scorecard per method: recall of planted pairs in the top K, and verified recall after a shared held-out check
(the response must also appear in the second half of the window, days 31-60, when the effect is sustained).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys

import numpy as np

CACHE = os.path.expanduser(os.environ.get("LAB_CACHE", "~/.cache/ripples-lab"))
PRE, POST = (-60, -1), (1, 30)


def load():
    z = np.load(os.path.join(CACHE, "pv.npz"), allow_pickle=False)
    ev = json.load(open(os.path.join(CACHE, "events.json")))
    return z["articles"], z["days"], z["views"].astype(np.float64), ev


def resp(lv, d, a=PRE, b=POST):
    """Mean log views in the post window minus the pre window, for all articles at day index d."""
    pre = np.nanmean(lv[:, d + a[0]:d + a[1] + 1], axis=1)
    post = np.nanmean(lv[:, d + b[0]:d + b[1] + 1], axis=1)
    return post - pre


def resp_trend(lv, d, a=PRE, b=POST):
    """Post-window mean minus the pre-window linear trend extrapolated to the post window's midpoint."""
    t = np.arange(a[0], a[1] + 1, dtype=float)
    y = lv[:, d + a[0]:d + a[1] + 1]
    ok = np.isfinite(y)
    tm = np.where(ok, t, np.nan)
    mt, my = np.nanmean(tm, axis=1, keepdims=True), np.nanmean(np.where(ok, y, np.nan), axis=1, keepdims=True)
    slope = np.nansum((tm - mt) * (y - my), axis=1) / np.nansum((tm - mt) ** 2, axis=1)
    mid = (b[0] + b[1]) / 2
    pred = my[:, 0] + slope * (mid - mt[:, 0])
    post = np.nanmean(lv[:, d + b[0]:d + b[1] + 1], axis=1)
    return post - pred


def plant(lv, d, art, size, shape, D):
    out = lv.copy()
    t = np.arange(D - d)
    bump = size * (np.exp(-t / 20.0) if shape == "decay" else np.ones_like(t, dtype=float))
    out[art, d:] = out[art, d:] + np.log1p(bump)
    return out


def run(a):
    arts, days, views, ev = load()
    lv = np.log1p(views)
    A, D = lv.shape
    rng = np.random.default_rng(a.seed)
    lo, hi = -PRE[0] + 1, D - 61
    ev = [e for e in ev if e.get("typ")]
    links = np.array([e.get("links") or 0 for e in ev], dtype=float)
    types = np.array([e["typ"] for e in ev])
    scores = {m: {"top_hits": 0, "verified_hits": 0, "false_verified": 0}
              for m in ("naive", "ghost", "anom", "placebo", "trend")}
    planted_total = 0
    for w in range(a.worlds):
        fake_day = rng.integers(lo, hi, size=len(ev))
        sub = rng.choice(len(ev), size=min(a.events, len(ev)), replace=False)
        world = lv
        planted = set()
        for i in rng.choice(sub, size=a.plants, replace=False):
            art = int(rng.integers(0, A))
            world = plant(world, int(fake_day[i]), art, a.size, rng.choice(["step", "decay"]), D)
            planted.add((int(i), art))
        planted_total += len(planted)
        noise = np.nanstd(np.diff(world, axis=1), axis=1) * np.sqrt(1 / 30 + 1 / 60)
        R = {int(i): resp(world, int(fake_day[i])) for i in sub}
        R2 = {int(i): resp(world, int(fake_day[i]), PRE, (31, 60)) for i in sub}
        P2 = np.stack([resp(world, int(d), PRE, (31, 60)) for d in rng.integers(lo, hi, size=a.placebo_dates)])
        v_mu, v_sd = np.nanmean(P2, axis=0), np.nanstd(P2, axis=0, ddof=1)
        # article-specific placebo-date calibration: each article's own response at random dates
        pd_days = rng.integers(lo, hi, size=a.placebo_dates)
        P = np.stack([resp(world, int(d)) for d in pd_days])
        PT = np.stack([resp_trend(world, int(d)) for d in pd_days])
        pmu, psd = np.nanmean(P, axis=0), np.nanstd(P, axis=0, ddof=1)
        tmu, tsd = np.nanmean(PT, axis=0), np.nanstd(PT, axis=0, ddof=1)
        RT = {int(i): resp_trend(world, int(fake_day[i])) for i in sub}
        cands = {}
        cands["placebo"] = [((R[i][j] - pmu[j]) / psd[j], i, j) for i in R for j in range(A)]
        cands["trend"] = [((RT[i][j] - tmu[j]) / tsd[j], i, j) for i in R for j in range(A)]
        cands["naive"] = [(R[i][j] / noise[j], i, j) for i in R for j in range(A)]
        # ghosts: same type, prominence within a factor of 2, different day; responses at their fake days
        gz = []
        for i in R:
            g = [k for k in range(len(ev)) if k != i and types[k] == types[i]
                 and 0.5 <= (links[k] + 1) / (links[i] + 1) <= 2 and abs(int(fake_day[k]) - int(fake_day[i])) > 90]
            g = rng.choice(g, size=min(a.ghosts, len(g)), replace=False) if g else []
            if len(g) < 5:
                continue
            G = np.stack([resp(world, int(fake_day[k])) for k in g])
            mu, sd = np.nanmean(G, axis=0), np.nanstd(G, axis=0, ddof=1)
            zz = (R[i] - mu) / np.where(sd > 0, sd, np.nan)
            gz += [(zz[j], i, j) for j in range(A)]
        cands["ghost"] = gz
        # outcome-first: breaks in 7-day means, attributed to events 0-14 days before
        m7 = np.array([np.convolve(np.nan_to_num(world[j]), np.ones(7) / 7, mode="same") for j in range(A)])
        jump = m7[:, 7:] - m7[:, :-7]
        sdj = np.nanstd(jump, axis=1)
        an = []
        by_day = {}
        for i in sub:
            by_day.setdefault(int(fake_day[i]), []).append(int(i))
        for j in range(A):
            top = np.argsort(-np.abs(jump[j]))[:a.breaks]
            for t in top:
                day = int(t) + 7
                near = [i for dd in range(day - 14, day + 1) for i in by_day.get(dd, [])]
                for i in near:
                    an.append((jump[j, t] / sdj[j] / len(near), i, j))
        cands["anom"] = an
        for m, lst in cands.items():
            lst = [c for c in lst if np.isfinite(c[0])]
            lst.sort(key=lambda c: -abs(c[0]))
            top = lst[:a.topk]
            hits = {(i, j) for _, i, j in top} & planted
            scores[m]["top_hits"] += len(hits)
            # shared held-out check: same sign and |z| >= 2 in days 31-60 against the article's noise
            for s, i, j in top:
                zv = (R2[i][j] - v_mu[j]) / v_sd[j]
                ok = np.sign(zv) == np.sign(s) and abs(zv) >= a.verify_z
                if ok:
                    if (i, j) in planted:
                        scores[m]["verified_hits"] += 1
                    else:
                        scores[m]["false_verified"] += 1
        print(f"world {w + 1}/{a.worlds}", flush=True)
    rep = {m: {"recall_topk": round(v["top_hits"] / planted_total, 3),
               "verified_recall": round(v["verified_hits"] / planted_total, 3),
               "false_verified_per_world": round(v["false_verified"] / a.worlds, 2)} for m, v in scores.items()}
    return {"settings": vars(a), "articles": int(A), "days": int(D), "events": len(ev), "scorecard": rep}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--worlds", type=int, default=10)
    ap.add_argument("--events", type=int, default=150)
    ap.add_argument("--plants", type=int, default=10)
    ap.add_argument("--size", type=float, default=0.3, help="planted multiplicative lift (0.3 = +30%)")
    ap.add_argument("--ghosts", type=int, default=30)
    ap.add_argument("--breaks", type=int, default=5)
    ap.add_argument("--topk", type=int, default=50)
    ap.add_argument("--verify-z", type=float, default=2.0)
    ap.add_argument("--placebo-dates", type=int, default=200)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out", default="cultural_lab_report.json")
    a = ap.parse_args()
    rep = run(a)
    rep["run_at"] = dt.datetime.utcnow().isoformat(timespec="seconds") + "Z"
    json.dump(rep, open(a.out, "w"), indent=1)
    print(json.dumps(rep["scorecard"], indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
