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


RB = {"pre": 60, "post": 30, "seasonal": True}  # robust-method windows; set from the command line


def rstat(x, d, seasonal=None):
    """Robust level shift: median of days 1-30 minus median of days -60..-1, on a series with the all-article daily
    median already removed (shared swings: pandemic, school year, site-wide traffic). With seasonal=True the same
    quantity 52 weeks earlier is subtracted, which removes yearly cycles. Medians ignore one-day news spikes."""
    pre, post = RB["pre"], RB["post"]
    seasonal = RB["seasonal"] if seasonal is None else seasonal
    r = np.nanmedian(x[:, d + 1:d + 1 + post], axis=1) - np.nanmedian(x[:, d - pre:d], axis=1)
    if seasonal:
        e = d - 364
        r = r - (np.nanmedian(x[:, e + 1:e + 1 + post], axis=1) - np.nanmedian(x[:, e - pre:e], axis=1))
    return r


def recall_at_fd(pairs, worlds, per_world):
    """pairs: (score, is_planted). Threshold = score exceeded by per_world * worlds non-planted candidates, i.e. the
    fake-event null sets the cutoff; returns the share of planted pairs above it (recall at that false-discovery load)."""
    null = np.sort([s for s, p in pairs if not p])[::-1]
    hits = np.array([s for s, p in pairs if p])
    if len(hits) == 0:
        return 0.0
    k = int(round(per_world * worlds))
    thr = null[k] if k < len(null) else -np.inf
    return round(float((hits > thr).mean()), 3)


_NORM = __import__("statistics").NormalDist()


def rank_z(real, P):
    """Per-article empirical placebo p-value (one-sided, (1 + #placebo >= real) / (1 + n)) mapped to a normal z. Bounded
    by the number of placebo dates, so an article whose placebo spread is too narrow cannot produce a huge score."""
    n = P.shape[0]
    pv = np.clip((1 + (P >= real[None, :]).sum(axis=0)) / (1 + n), 0.5 / (1 + n), 1 - 0.5 / (1 + n))
    z = np.array([_NORM.inv_cdf(1 - q) for q in pv])
    return np.where(np.isfinite(real), z, np.nan)


CT = np.arange(-14, 91)  # coupling window, days relative to the event


def event_curves(ev, days):
    """Each event's own attention curve around its real release: log views above the pre-release baseline on days
    -14..+90, clipped at 0 and scaled so the mean over days 1-30 is 1. Returns {event index: curve} for events whose
    English Wikipedia article has views around the release. Used as a shape only; it is moved to the fake date."""
    f = os.path.join(CACHE, "ev_pv.npz")
    if not os.path.exists(f):
        return {}
    z = np.load(f, allow_pickle=False)
    idx = {q: k for k, q in enumerate(z["qids"])}
    lvv = np.log1p(z["views"].astype(np.float64))
    d0 = int(days[0])
    out = {}
    for i, e in enumerate(ev):
        k = idx.get(e.get("qid"))
        if k is None or not e.get("released"):
            continue
        r = dt.date.fromisoformat(e["released"][:10]).toordinal() - d0
        if r - 60 < 0 or r + CT[-1] >= lvv.shape[1]:
            continue
        win = lvv[k, r + CT[0]:r + CT[-1] + 1]
        pre = lvv[k, r - 60:r]
        if np.isfinite(win).sum() < 0.8 * len(CT):
            continue
        base = np.nanmedian(pre) if np.isfinite(pre).sum() >= 20 else np.nanpercentile(win, 10)
        c = np.clip(np.nan_to_num(win - base), 0, None)
        m = c[(CT >= 1) & (CT <= 30)].mean()
        if m > 0.05:
            out[i] = c / m
    return out


def couple_stat(x, d, c):
    """Least-squares loading of each article's post-event shift (days 1..90 minus its median over days -28..-1) on the
    event's attention curve; pre-event days enter too, where a coupled ripple must be flat."""
    base = np.nanmedian(x[:, d - 28:d], axis=1, keepdims=True)
    y = np.nan_to_num(x[:, d + CT[0]:d + CT[-1] + 1] - base)
    return y @ c / (c @ c)


SHAPES = ("step", "pulse", "delayed", "gradual", "slope", "decay")


def shape_lift(shape, n, rng):
    """Synthetic ripple library (spec section 37), as a log-lift profile over days 0..n-1 scaled so its mean over days
    1-90 is 1. step: level shift; pulse: 14-day bump; delayed: step starting on day 30-60; gradual: ramps to a plateau
    over 60 days; slope: linear growth; decay: jump that halves in about two weeks."""
    t = np.arange(n, dtype=float)
    if shape == "step":
        f = np.ones(n)
    elif shape == "pulse":
        f = (t < 14).astype(float)
    elif shape == "delayed":
        f = (t >= rng.integers(30, 61)).astype(float)
    elif shape == "gradual":
        f = np.minimum(t / 60.0, 1.0)
    elif shape == "slope":
        f = t / 90.0
    else:
        f = np.exp(-t / 20.0)
    m = f[1:91].mean()
    return f / m if m > 0 else f


# shape statistics for the max-statistic method: (name, post window as day offsets, lag) on the market-adjusted series;
# each is (median over the post window) - (median over days -60..-1), except slope, which is a change in trend
SHAPE_STATS = (("car7", 1, 8), ("car30", 1, 31), ("car90", 1, 91), ("lag30", 31, 61), ("lag60", 61, 91))


def shape_stats(x, d):
    base = np.nanmedian(x[:, d - 60:d], axis=1)
    out = [np.nanmedian(x[:, d + a:d + b], axis=1) - base for _, a, b in SHAPE_STATS]
    # slope change: trend over days 1..90 minus trend over days -90..-1 (least squares on day index)
    t = np.arange(90, dtype=float) - 44.5
    post = np.nan_to_num(x[:, d + 1:d + 91] - np.nanmean(x[:, d + 1:d + 91], axis=1, keepdims=True))
    pre = np.nan_to_num(x[:, d - 90:d] - np.nanmean(x[:, d - 90:d], axis=1, keepdims=True))
    out.append((post @ t - pre @ t) / (t @ t) * 90)
    return np.stack(out)  # [n_stats, A]


def couple_diff_stat(x, d, dc):
    """Onset-aligned coupling: loading of each article's day-to-day changes on the event curve's day-to-day changes over
    days -14..+90. Differencing removes slow drift and rewards bursts that start and stop on the event's own days."""
    y = np.diff(np.nan_to_num(x[:, d + CT[0] - 1:d + CT[-1] + 1]), axis=1)
    return y @ dc / (dc @ dc)


def run(a):
    arts, days, views, ev = load()
    lv = np.log1p(views)
    A, D = lv.shape
    rng = np.random.default_rng(a.seed)
    lo, hi = 364 + 61, D - 121  # a year of history before every event, so the seasonal method has a baseline
    ev = [e for e in ev if e.get("typ")]
    links = np.array([e.get("links") or 0 for e in ev], dtype=float)
    types = np.array([e["typ"] for e in ev])
    curves = event_curves(ev, days)
    if a.plant_shape == "coupled" and not curves:
        sys.exit("coupled plants need ev_pv.npz (run cult_data.py)")
    pool = np.array(sorted(curves)) if curves else np.arange(len(ev))
    scores = {m: {"top_hits": 0, "verified_hits": 0, "false_verified": 0}
              for m in ("naive", "ghost", "anom", "placebo", "trend", "robust", "couple", "couple_d", "couple_d_rank",
                        "shapemax")}
    fam_pairs = {}  # method -> [(family score, is planted family)]
    fam_total = [0]
    shape_hits = {}  # (method, shape) -> [planted pair recovered at 1 false/world threshold?] filled after the loop
    plant_shape_of = {}
    fd_pairs = {m: [] for m in scores}
    market = np.nanmedian(lv, axis=0)
    planted_total = 0
    for w in range(a.worlds):
        fake_day = rng.integers(lo, hi, size=len(ev))
        sub = rng.choice(pool, size=min(a.events, len(pool)), replace=False)
        world = lv
        planted = set()
        for i in rng.choice(sub, size=a.plants, replace=False):
            art = int(rng.integers(0, A))
            shp = a.plant_shape
            if shp == "mix":
                shp = rng.choice(list(SHAPES) + (["coupled"] if curves else []))
            plant_shape_of[(w, int(i), art)] = shp
            if shp in SHAPES:
                d = int(fake_day[i])
                world = world.copy()
                n = min(D - d, 180)
                world[art, d:d + n] += np.log1p(a.size) * shape_lift(shp, n, rng)
            elif shp == "coupled":
                # the ripple follows the event's own attention curve (mean lift over days 1-30 = size)
                d = int(fake_day[i])
                world = world.copy()
                world[art, d + CT[0]:d + CT[-1] + 1] += np.log1p(a.size) * curves[int(i)]
            else:
                world = plant(world, int(fake_day[i]), art, a.size, rng.choice(["step", "decay"]), D)  # legacy
            planted.add((int(i), art))
        planted_total += len(planted)
        # family ripples (spec: event-family replication): the same article responds to several events of one type,
        # each response following that event's own attention curve at the family lift
        fam_planted = set()
        group_of = {}
        if a.family_mode == "groups":
            # narrow, pre-defined families (stand-in for owner-curated families such as "sports films"): the world's
            # events are split into disjoint groups of family_events; a planted family is a whole group
            order = rng.permutation(sub)
            for g in range(len(order) // a.family_events):
                for i in order[g * a.family_events:(g + 1) * a.family_events]:
                    group_of[int(i)] = f"g{g}"
        if a.family_plants and curves and a.family_mode == "groups":
            gids = sorted(set(group_of.values()))
            for gi in rng.choice(len(gids), size=min(a.family_plants, len(gids)), replace=False):
                g = gids[int(gi)]
                art = int(rng.integers(0, A))
                for i in [k for k, v in group_of.items() if v == g]:
                    d = int(fake_day[i])
                    world = world.copy()
                    world[art, d + CT[0]:d + CT[-1] + 1] += np.log1p(a.family_size) * curves[int(i)]
                fam_planted.add((g, art))
        elif a.family_plants and curves:
            subt = types[sub]
            ok_types = [t for t in set(subt) if (subt == t).sum() >= a.family_events]
            for _ in range(a.family_plants):
                if not ok_types:
                    break
                t = ok_types[int(rng.integers(len(ok_types)))]
                art = int(rng.integers(0, A))
                members = rng.choice(sub[subt == t], size=a.family_events, replace=False)
                for i in members:
                    d = int(fake_day[i])
                    world = world.copy()
                    world[art, d + CT[0]:d + CT[-1] + 1] += np.log1p(a.family_size) * curves[int(i)]
                fam_planted.add((t, art))
        fam_total[0] += len(fam_planted)
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
        # robust: market-adjusted, seasonal, median-based shift, standardized by the article's own placebo dates
        # (median/MAD); one-sided, since a ripple is an increase in attention
        xw = world - market
        RBr = {int(i): rstat(xw, int(fake_day[i])) for i in sub}
        PB = np.stack([rstat(xw, int(d)) for d in pd_days])
        bmed = np.nanmedian(PB, axis=0)
        bmad = 1.4826 * np.nanmedian(np.abs(PB - bmed), axis=0)
        cands["robust"] = [((RBr[i][j] - bmed[j]) / bmad[j], i, j) for i in RBr for j in range(A)]
        # couple (D5): loading on the event's own attention curve, calibrated per article at placebo dates with the
        # same curve (median/MAD); one-sided
        cp = []
        if curves:
            for i in sub:
                c = curves[int(i)]
                real = couple_stat(xw, int(fake_day[i]), c)
                P = np.stack([couple_stat(xw, int(dd), c) for dd in pd_days[:a.couple_placebo]])
                pm = np.nanmedian(P, axis=0)
                ps = 1.4826 * np.nanmedian(np.abs(P - pm), axis=0)
                zz = (real - pm) / np.where(ps > 0, ps, np.nan)
                cp += [(zz[j], int(i), j) for j in range(A)]
        cands["couple"] = cp
        cd, cdr = [], []
        if curves:
            for i in sub:
                dc = np.diff(np.concatenate([[0.0], curves[int(i)]]))
                real = couple_diff_stat(xw, int(fake_day[i]), dc)
                P = np.stack([couple_diff_stat(xw, int(dd), dc) for dd in pd_days[:a.couple_placebo]])
                pm = np.nanmedian(P, axis=0)
                ps = 1.4826 * np.nanmedian(np.abs(P - pm), axis=0)
                zz = (real - pm) / np.where(ps > 0, ps, np.nan)
                cd += [(zz[j], int(i), j) for j in range(A)]
                rz = rank_z(real, P)
                cdr += [(rz[j], int(i), j) for j in range(A)]
        cands["couple_d"] = cd
        cands["couple_d_rank"] = cdr
        # shapemax: each shape statistic standardized by the article's own placebo dates (median/MAD), T = max over
        # shapes, then T itself calibrated against the same max at
        # placebo dates, so choosing the best-looking shape is paid for (spec sections 6-8)
        PS = np.stack([shape_stats(xw, int(dd)) for dd in pd_days])  # [P, S, A]
        smed = np.nanmedian(PS, axis=0)
        smad = 1.4826 * np.nanmedian(np.abs(PS - smed), axis=0)
        smad = np.where(smad > 0, smad, np.nan)
        Tnull = np.nanmax((PS - smed) / smad, axis=1)  # [P, A]
        half = len(pd_days) // 2  # calibrate max on the other half of placebo dates, so it is not fit to itself
        tmed = np.nanmedian(Tnull[half:], axis=0)
        tmad = 1.4826 * np.nanmedian(np.abs(Tnull[half:] - tmed), axis=0)
        sm = []
        for i in sub:
            T = np.nanmax((shape_stats(xw, int(fake_day[i])) - smed) / smad, axis=0)
            zz = (T - tmed) / np.where(tmad > 0, tmad, np.nan)
            sm += [(zz[j], int(i), j) for j in range(A)]
        cands["shapemax"] = sm
        # family test: for each (event type, article), pool each method's per-pair z over every event of that type in
        # this world, each z clipped to [-4, 4] so one coincident burst cannot carry a family
        if a.family_plants and curves:
            sub_types = ({int(i): group_of.get(int(i), "none") for i in sub} if a.family_mode == "groups"
                         else {int(i): types[int(i)] for i in sub})
            for m in ("couple", "couple_d", "couple_d_rank", "robust", "shapemax", "placebo"):
                vals = {}
                for sc, i, j in cands.get(m, []):
                    if np.isfinite(sc):
                        vals.setdefault((sub_types[int(i)], int(j)), []).append(float(np.clip(sc, -4, 4)))
                # mean-pooled (all events of the type) and top-k pooled (the k strongest members, k fixed in advance)
                fam_pairs.setdefault(m, []).extend((sum(v) / np.sqrt(len(v)), k in fam_planted) for k, v in vals.items())
                kk = a.family_topk
                if m == "couple_d":  # higher clip: real articles have bursts far above 4 MADs (run 2 saturated at 4)
                    raw = {}
                    for sc, i, j in cands.get(m, []):
                        if np.isfinite(sc):
                            raw.setdefault((sub_types[int(i)], int(j)), []).append(float(np.clip(sc, -10, 10)))
                    fam_pairs.setdefault(m + "_topk10", []).extend(
                        (sum(sorted(v, reverse=True)[:kk]) / np.sqrt(kk), k in fam_planted) for k, v in raw.items()
                        if len(v) >= kk)
                fam_pairs.setdefault(m + "_topk", []).extend(
                    (sum(sorted(v, reverse=True)[:kk]) / np.sqrt(kk), k in fam_planted) for k, v in vals.items()
                    if len(v) >= kk)
        for m, lst in cands.items():
            lst = [c for c in lst if np.isfinite(c[0])]
            if m in ("robust", "couple", "couple_d", "couple_d_rank", "shapemax"):
                lst = [(max(c[0], 0.0), c[1], c[2]) for c in lst]
            fd_pairs[m] += [(abs(c[0]), (c[1], c[2]) in planted) for c in lst]
            for c in lst:
                if (c[1], c[2]) in planted:
                    shape_hits.setdefault(m, []).append((abs(c[0]), plant_shape_of.get((w, c[1], c[2]), "?")))
            # planted pairs that a method never scored count as misses
            fd_pairs[m] += [(-np.inf, True) for pr in planted if pr not in {(c[1], c[2]) for c in lst}]
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
               "false_verified_per_world": round(v["false_verified"] / a.worlds, 2),
               "recall_at_1_false_per_world": recall_at_fd(fd_pairs[m], a.worlds, 1.0),
               "recall_at_0.1_false_per_world": recall_at_fd(fd_pairs[m], a.worlds, 0.1),
               "null_top_scores": [round(float(x), 2) for x in
                                   sorted((sc for sc, pl in fd_pairs[m] if not pl), reverse=True)[:8]],
               "planted_score_quartiles": [round(float(x), 2) for x in
                                           np.percentile([sc for sc, pl in fd_pairs[m] if pl and np.isfinite(sc)]
                                                         or [np.nan], [25, 50, 75])]}
           for m, v in scores.items()}
    for m in rep:
        null = np.sort([sc for sc, pl in fd_pairs[m] if not pl])[::-1]
        thr = null[a.worlds] if a.worlds < len(null) else -np.inf
        by = {}
        for sc, shp in shape_hits.get(m, []):
            by.setdefault(shp, []).append(sc > thr)
        rep[m]["recall_by_shape_at_1_false"] = {k: round(float(np.mean(v)), 2) for k, v in sorted(by.items())}
    fam = {m: {"recall_at_1_false_family_per_world": recall_at_fd(v, a.worlds, 1.0),
               "recall_at_0.1_false_family_per_world": recall_at_fd(v, a.worlds, 0.1),
               "null_top": [round(float(x), 2) for x in sorted((sc for sc, pl in v if not pl), reverse=True)[:5]],
               "planted_quartiles": [round(float(x), 2) for x in
                                     np.percentile([sc for sc, pl in v if pl] or [np.nan], [25, 50, 75])]}
           for m, v in fam_pairs.items()}
    return {"family": fam, "families_planted": fam_total[0], "settings": vars(a), "articles": int(A), "days": int(D), "events": len(ev), "scorecard": rep}


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
    ap.add_argument("--rb-pre", type=int, default=60, help="robust method: days before the event")
    ap.add_argument("--rb-post", type=int, default=30, help="robust method: days after the event")
    ap.add_argument("--rb-seasonal", type=int, default=1, help="robust method: subtract the same shift 52 weeks earlier")
    ap.add_argument("--plant-shape", choices=["generic", "coupled", "mix"] + list(SHAPES), default="mix",
                    help="ripple shape: one from the library, coupled (follows the event's own attention curve), mix "
                         "(a random library shape per plant), or generic (legacy step/decay)")
    ap.add_argument("--couple-placebo", type=int, default=100)
    ap.add_argument("--family-plants", type=int, default=0, help="family ripples per world (0 = off)")
    ap.add_argument("--family-events", type=int, default=5, help="events per planted family")
    ap.add_argument("--family-size", type=float, default=0.5, help="lift of each family member's response")
    ap.add_argument("--family-topk", type=int, default=5, help="members pooled by the top-k family statistic")
    ap.add_argument("--family-mode", choices=["type", "groups"], default="type",
                    help="type: families are catalog types (broad); groups: disjoint pre-defined groups of "
                         "family_events events (narrow, like owner-curated families)")
    ap.add_argument("--out", default="cultural_lab_report.json")
    a = ap.parse_args()
    RB.update(pre=a.rb_pre, post=a.rb_post, seasonal=bool(a.rb_seasonal))
    rep = run(a)
    rep["run_at"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    json.dump(rep, open(a.out, "w"), indent=1)
    print(json.dumps({"scorecard": rep["scorecard"], "family": rep.get("family")}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
