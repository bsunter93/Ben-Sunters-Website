"""Shape v1: the time shape of a response, lag families, and catalyst vs outcome strength, from series already stored
in the repository (no network). Pre-registered in ripples/docs/shape_plan_v1.md.

Two modes, run in this order:
  python3 ripples/lab/discovery/shape.py placebo   calibration on placebo (decoy) dates only. Reads the two long daily files
                                         (queens_gambit_attention.json, tiger_king_attention.json) and uses only windows
                                         that end 30 days before each file's stone or start more than a year after it.
                                         Plants known shapes into those windows and picks the rules' thresholds.
                                         Writes ripples/docs/results/shape_placebo_v1.json.
  python3 ripples/lab/discovery/shape.py real      the registered run on every stored series. Refuses to run unless FROZEN
                                         below matches the calibration file. Writes ripples/docs/results/shape_v1.json
                                         and ripples/docs/results/lag_priors_v1.json.

Every series is reduced to weekly totals aligned at its parent date (week 0 is the week that starts at, or contains,
the parent date). The baseline is the series' own weeks -12..-3; nothing is fitted.
"""
from __future__ import annotations

import datetime as dt
import glob
import hashlib
import itertools
import json
import math
import os
import re
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
RES = os.path.join(ROOT, "docs", "results")
PLACEBO_OUT = os.path.join(RES, "shape_placebo_v1.json")
SHAPE_OUT = os.path.join(RES, "shape_v1.json")
PRIOR_OUT = os.path.join(RES, "lag_priors_v1.json")
LONG_FILES = ["queens_gambit_attention.json", "tiger_king_attention.json"]
LONG_DAY0 = dt.date(2019, 12, 1)
SEED = 20261004
D = dt.date.fromisoformat

# ---------- fixed design constants (not tuned) ----------
FLOOR = 70.0          # weekly views added before logs (10 a day), so near-empty articles do not read as huge lifts
PRE = (-12, -3)       # baseline weeks; the two weeks before the parent are left out (trailers, anticipation)
MIN_PRE = 6           # fewer baseline weeks than this: not classified
W_MAIN = 21           # the common post window in weeks (147 days), the length every stone-aligned file carries
W_SHORT = 13          # the truncation cutoff (91 days)
MIN_POST = 8          # fewer post weeks than this: not classified
MIN_EXCESS = 140.0    # the peak week must add at least 20 views a day over the baseline (the checker's "med + 20")
LATE = 4              # the late window is the last four weeks of the post window
RAISED_FLOOR = 1.5    # a late level at least 1.5 times the baseline is a raised floor
CLASSES = ["immediate spike", "delayed spike", "gradual ramp", "step change", "pulse and decay", "multiple waves"]
EXTRA = ["late spike", "no response"]

# ---------- thresholds chosen on placebo dates (filled from shape_placebo_v1.json, then frozen) ----------
FROZEN = {"stat": "exceed", "smin": 0.05, "on_frac": 0.1, "hl_spike": 10, "lf_step": 0.4, "ramp_peak": 8, "jump": 0.5,
          "trough": 0.3, "rewave": 0.4, "tau": 0.7053, "tau13": 0.6188}


# ---------- core: weekly features and the rules ----------
def baseline(w, k0, smin):
    lo, hi = max(0, k0 + PRE[0]), k0 + PRE[1]
    if hi < 0 or hi - lo + 1 < MIN_PRE:
        return None
    x = np.log10(np.asarray(w, float) + FLOOR)
    pre = x[lo:hi + 1]
    m = float(np.median(pre))
    s = max(1.4826 * float(np.median(np.abs(pre - m))), smin)
    return x, m, s, float(pre.max())


def gate_stat(kind, x, m, s, pmax, ks):
    """The response statistic over weeks ks: z (log lift in baseline-noise units), lift (log lift), or exceed (log of
    the peak over the highest baseline week)."""
    xp = float(x[ks].max())
    if kind == "z":
        return (xp - m) / s
    if kind == "lift":
        return xp - m
    return xp - pmax


def features(w, k0, W, P):
    """Everything the rules need, for the post window weeks 0..W-1 after week k0. None if too short."""
    w = np.asarray(w, float)
    b = baseline(w, k0, P["smin"])
    if b is None:
        return None
    x, m, s, pmax = b
    W = min(W, len(w) - k0)
    if W < MIN_POST:
        return None
    ks = np.arange(k0, k0 + W)
    base = 10 ** m - FLOOR
    exc = w - base
    kp = int(ks[np.argmax(w[ks])])
    ep = float(exc[kp])
    T = gate_stat(P["stat"], x, m, s, pmax, ks)
    return {"x": x, "m": m, "s": s, "base": max(base, 0.0), "exc": exc, "k0": k0, "W": W, "kp": kp, "ep": ep, "T": T,
            "lift": 10 ** (float(x[kp]) - m)}


def half_life_weeks(exc, kp, end):
    """Weeks from the peak until the excess first falls to half of the peak excess, interpolated on a log scale
    between the two bracketing weeks; None when it never halves inside the window."""
    ep = exc[kp]
    for k in range(kp + 1, end):
        if exc[k] <= 0.5 * ep:
            a, b = exc[k - 1], exc[k]
            if b > 0 and a > b:
                return (k - 1 - kp) + math.log(a / (0.5 * ep)) / math.log(a / b)
            return (k - 1 - kp) + (a - 0.5 * ep) / max(a - b, 1e-9)
    return None


def count_waves(exc, ep, k0, end, P):
    """A wave starts when the excess reaches rewave x peak excess; it ends when the excess falls below trough x peak
    excess; a later return to rewave x peak is a new wave."""
    n, inside = 0, False
    for k in range(k0, end):
        e = exc[k] / ep
        if not inside and e >= P["rewave"]:
            n, inside = n + 1, True
        elif inside and e < P["trough"]:
            inside = False
    return n


def classify(w, k0, W, P, tau, force=False, f=None):
    """The shape class and its measurements. force=True classifies even below the gate (used when the checker's own
    test already found a response). f: features already computed for the same series, window and statistic."""
    f = f if f is not None else features(w, k0, W, P)
    if f is None:
        return {"shape": "not classified", "why": "too short"}
    exc, kp, ep, end = f["exc"], f["kp"], f["ep"], f["k0"] + f["W"]
    gate = bool(f["T"] >= tau and ep >= MIN_EXCESS)
    out = {"gate": gate, "T": round(f["T"], 3), "peak_lift": round(f["lift"], 2), "baseline_weekly": round(f["base"], 1),
           "peak_week": kp - k0, "window_weeks": f["W"]}
    if not gate and not (force and ep >= MIN_EXCESS and f["lift"] > 1.0):
        out["shape"] = "no response"
        if force:
            out["why"] = "graded a response by the checker, but the peak week adds under 20 views a day in weekly totals"
        return out
    # onset: the first week of the run that carries the peak, every week of it at on_frac x peak excess or more
    j = kp
    while j - 1 >= k0 - 2 and exc[j - 1] >= P["on_frac"] * ep:
        j -= 1
    onset = j - k0
    hl = half_life_weeks(exc, kp, end)
    fade = next((k - kp for k in range(kp + 1, end) if exc[k] <= 0.2 * ep), None)  # weeks until 80% of the excess is gone
    late = exc[end - LATE:end]
    lf = float(np.median(late)) / ep
    late_lift = 10 ** (float(np.median(f["x"][end - LATE:end])) - f["m"])
    waves = count_waves(exc, ep, k0, end, P)
    incr = np.diff(exc[max(k0 - 1, 0):kp + 1])
    max_jump = float(incr.max()) / ep if incr.size else 1.0
    early = float(exc[k0:k0 + 3].max()) / ep
    out.update(onset_week=onset, half_life_days=None if hl is None else round(7 * hl, 1), fade_weeks=fade, late_fraction=round(lf, 3),
               late_lift=round(late_lift, 2), waves=waves, max_jump=round(max_jump, 3))
    if waves >= 2:
        shape = "multiple waves"
    elif kp - k0 >= P["ramp_peak"] and max_jump <= P["jump"] and early <= 0.5:
        shape = "gradual ramp"
    elif lf >= P["lf_step"] and late_lift >= RAISED_FLOOR:
        shape = "step change"
    elif onset > 8:
        shape = "late spike"
    elif onset >= 2:
        shape = "delayed spike"
    elif hl is not None and 7 * hl <= P["hl_spike"]:
        shape = "immediate spike"
    else:
        shape = "pulse and decay"
    out["shape"] = shape
    out["raised_floor"] = bool(shape not in ("step change",) and late_lift >= RAISED_FLOOR and lf >= 0.15)
    out["gate_bypassed"] = bool(not gate)
    return out


# ---------- placebo windows and planted shapes ----------
def long_series():
    """(file, article, daily array, stone index) for the two long daily files."""
    out = []
    for f in LONG_FILES:
        d = json.load(open(os.path.join(RES, f)))
        st = (D(d["event_day"]) - LONG_DAY0).days
        for name, s in d["series"].items():
            out.append((f, name, np.array(s, float), st))
    return out


def decoy_starts(n, st, post_days=147, pre_days=84):
    """Placebo dates every 7 days whose window (84 days before to 147 days after) ends at least 30 days before the
    stone, or whose baseline starts more than 365 days after it."""
    return [t for t in range(pre_days, n - post_days + 1, 7) if t + post_days < st - 30 or t - pre_days > st + 365]


def weekly_at(v, t, pre_w=12, post_w=21):
    return np.array([v[t + 7 * k:t + 7 * k + 7].sum() for k in range(-pre_w, post_w)])


def profile(shape, rng, n=147):
    """A daily excess profile (peak about 1) over days 0..n-1 after the placebo date, and its parameters."""
    t = np.arange(n, dtype=float)
    if shape == "immediate spike":
        t0, h = int(rng.integers(0, 4)), float(rng.uniform(1, 4))
        f, par = np.where(t >= t0, 2 ** (-(t - t0) / h), 0.0), {"t0": t0, "half_life": h}
    elif shape == "pulse and decay":
        t0, h = int(rng.integers(0, 7)), float(rng.uniform(14, 42))
        f, par = np.where(t >= t0, 2 ** (-(t - t0) / h), 0.0), {"t0": t0, "half_life": h}
    elif shape == "delayed spike":
        t0, h = int(rng.integers(14, 57)), float(rng.uniform(1, 14))
        f, par = np.where(t >= t0, 2 ** (-(t - t0) / h), 0.0), {"t0": t0, "half_life": h}
    elif shape == "gradual ramp":
        t0, r = int(rng.integers(0, 15)), float(rng.uniform(56, 140))
        f, par = np.clip((t - t0) / r, 0, 1), {"t0": t0, "rise_days": r}
    elif shape == "step change":
        t0, o = int(rng.integers(0, 7)), float(rng.uniform(0, 0.6))
        f = np.where(t >= t0, 1 + o * 2 ** (-(t - t0) / 7.0), 0.0) / (1 + o)
        par = {"t0": t0, "overshoot": o}
    elif shape == "multiple waves":
        t0, g = int(rng.integers(0, 7)), int(rng.integers(28, 99))
        h1, h2, r = float(rng.uniform(2, 10)), float(rng.uniform(2, 10)), float(rng.uniform(0.6, 1.2))
        f = np.where(t >= t0, 2 ** (-(t - t0) / h1), 0.0) + r * np.where(t >= t0 + g, 2 ** (-(t - t0 - g) / h2), 0.0)
        par = {"t0": t0, "gap_days": g, "second_ratio": r}
    else:
        raise ValueError(shape)
    return f, par


def build_placebo(rng):
    """Unplanted decoy windows and one planted copy per shape per window, with the plant's size and parameters."""
    rows = []
    for f, name, v, st in long_series():
        for t in decoy_starts(len(v), st):
            pre = v[t - 84:t - 14]
            base_d = max(float(np.median(pre)), 1.0)
            rec = {"file": f, "article": name, "date": (LONG_DAY0 + dt.timedelta(days=t)).isoformat(), "none": weekly_at(v, t), "plants": {}}
            for shp in CLASSES:
                prof, par = profile(shp, rng)
                a = float(10 ** rng.uniform(0, 2))  # peak daily excess 1x to 100x the daily baseline
                vv = v.copy()
                vv[t:t + 147] += a * base_d * prof
                rec["plants"][shp] = {"weekly": weekly_at(vv, t), "size": a, **par}
            rows.append(rec)
    return rows


GRID = {"stat": ["z", "lift", "exceed"], "smin": [0.05, 0.08], "on_frac": [0.1, 0.2, 0.3], "hl_spike": [7, 10],
        "lf_step": [0.4, 0.5, 0.6], "ramp_peak": [6, 8], "jump": [0.35, 0.5], "trough": [0.3, 0.5], "rewave": [0.4, 0.6]}


def tau_for(rows, P, W=W_MAIN, q=95):
    """The gate threshold: the q-th percentile of the statistic on unplanted decoy windows (5% false positives at 95)."""
    Ts = []
    for r in rows:
        f = features(r["none"], 12, W, P)
        if f is not None:
            Ts.append(f["T"] if f["ep"] >= MIN_EXCESS else -np.inf)
    return float(np.percentile(np.array(Ts), q)), len(Ts)


def placebo_mode() -> int:
    rng = np.random.default_rng(SEED)
    rows = build_placebo(rng)
    print("decoy windows", len(rows), flush=True)
    keys = list(GRID)
    results = []
    # the gate first: for each statistic, the 5% threshold and the planted detection rate (power) at that threshold
    gate_rows = {}
    for stat, smin in itertools.product(GRID["stat"], GRID["smin"]):
        if stat != "z" and smin != GRID["smin"][0]:
            continue
        P0 = {"stat": stat, "smin": smin}
        tau, n = tau_for(rows, P0)
        det = {}
        for shp in CLASSES:
            hits = [features(r["plants"][shp]["weekly"], 12, W_MAIN, P0) for r in rows]
            det[shp] = float(np.mean([h is not None and h["T"] >= tau and h["ep"] >= MIN_EXCESS for h in hits]))
        fp = float(np.mean([(lambda h: h is not None and h["T"] >= tau and h["ep"] >= MIN_EXCESS)(features(r["none"], 12, W_MAIN, P0)) for r in rows]))
        gate_rows[f"{stat}/{smin}"] = {"tau": round(tau, 4), "fp": round(fp, 4), "power": {k: round(v, 3) for k, v in det.items()},
                                       "mean_power": round(float(np.mean(list(det.values()))), 4)}
        print("gate", stat, smin, gate_rows[f"{stat}/{smin}"], flush=True)
    best_gate = max(gate_rows, key=lambda k: (gate_rows[k]["mean_power"], -list(gate_rows).index(k)))
    stat, smin = best_gate.split("/")[0], float(best_gate.split("/")[1])
    tau = gate_rows[best_gate]["tau"]
    # the shape rules: grid over the remaining thresholds, scored on planted windows the gate detects
    rest = [k for k in keys if k not in ("stat", "smin")]
    P0 = {"stat": stat, "smin": smin}
    cache = [{shp: features(r["plants"][shp]["weekly"], 12, W_MAIN, P0) for shp in CLASSES} for r in rows]
    for combo in itertools.product(*[GRID[k] for k in rest]):
        P = {"stat": stat, "smin": smin, **dict(zip(rest, combo))}
        conf = {s: {} for s in CLASSES}
        for r, cf in zip(rows, cache):
            for shp in CLASSES:
                if cf[shp] is None:
                    continue
                c = classify(r["plants"][shp]["weekly"], 12, W_MAIN, P, tau, f=cf[shp])
                if c.get("gate"):
                    conf[shp][c["shape"]] = conf[shp].get(c["shape"], 0) + 1
        rec = {s: conf[s].get(s, 0) / max(1, sum(conf[s].values())) for s in CLASSES}
        bal = float(np.mean(list(rec.values())))
        results.append((bal, P, rec, conf))
    results.sort(key=lambda r: -r[0])  # stable: ties keep grid order
    bal, P, rec, conf = results[0]
    # what the chosen rules do on unplanted windows, and how stable they are when the window is cut at 13 weeks
    none_cls = {}
    for r in rows:
        c = classify(r["none"], 12, W_MAIN, P, tau)
        none_cls[c["shape"]] = none_cls.get(c["shape"], 0) + 1
    tau13, _ = tau_for(rows, P, W_SHORT)
    same = tot = 0
    flips = {}
    for r in rows:
        for shp in CLASSES:
            a = classify(r["plants"][shp]["weekly"], 12, W_SHORT, P, tau13)
            b = classify(r["plants"][shp]["weekly"], 12, W_MAIN, P, tau)
            if a.get("gate") and b.get("gate"):
                tot += 1
                same += a["shape"] == b["shape"]
                if a["shape"] != b["shape"]:
                    k = f"{a['shape']} -> {b['shape']}"
                    flips[k] = flips.get(k, 0) + 1
    # decoy thresholds for the lag-window comparison: every window from week -1 to week 20, at 5% and 1%
    windows = {}
    for a in range(-1, W_MAIN):
        for b in range(a, W_MAIN):
            Ts = []
            for r in rows:
                bb = baseline(r["none"], 12, smin)
                x, m, s, pmax = bb
                ks = np.arange(12 + a, 12 + b + 1)
                base = 10 ** m - FLOOR
                ok = float((np.asarray(r["none"])[ks] - base).max()) >= MIN_EXCESS
                Ts.append(gate_stat(stat, x, m, s, pmax, ks) if ok else -np.inf)
            windows[f"{a}:{b}"] = [round(float(np.percentile(Ts, 95)), 4), round(float(np.percentile(Ts, 99)), 4)]
    out = {"protocol": "ripples/docs/shape_plan_v1.md", "code": "ripples/lab/discovery/shape.py placebo", "run": dt.date.today().isoformat(),
           "seed": SEED, "decoy_windows": len(rows), "decoy_series": sorted({f"{r['file']}:{r['article']}" for r in rows}),
           "constants": {"FLOOR": FLOOR, "PRE": PRE, "MIN_PRE": MIN_PRE, "W_MAIN": W_MAIN, "W_SHORT": W_SHORT, "MIN_POST": MIN_POST,
                         "MIN_EXCESS": MIN_EXCESS, "LATE": LATE, "RAISED_FLOOR": RAISED_FLOOR},
           "gate_candidates": gate_rows, "gate_chosen": best_gate,
           "chosen": {**P, "tau": round(tau, 4), "tau13": round(tau13, 4)},
           "balanced_accuracy": round(bal, 4), "recall_by_shape": {k: round(v, 3) for k, v in rec.items()},
           "confusion": conf, "unplanted_classes": none_cls,
           "truncation_planted": {"same": same, "pairs": tot, "share": round(same / max(1, tot), 4), "flips": dict(sorted(flips.items(), key=lambda x: -x[1]))},
           "top10": [{"balanced_accuracy": round(b, 4), **{k: p[k] for k in rest}} for b, p, _, _ in results[:10]],
           "window_tau": windows}
    json.dump(out, open(PLACEBO_OUT, "w"), indent=1)
    print(json.dumps({k: out[k] for k in ("gate_chosen", "chosen", "balanced_accuracy", "recall_by_shape", "unplanted_classes", "truncation_planted")}, indent=1))
    return 0


# ---------- real mode: every stored series ----------
STONE_ALIAS = {"jwst-first-images": "jwst", "queens-gambit-2": "queens-gambit", "chernobyl-zone": "chernobyl", "squid-game-ripples": "squid-game",
               "queens_gambit_attention.json": "queens-gambit", "tiger_king_attention.json": "tiger-king"}


def stone_of(slug):
    s = slug.split("--")[0]
    return STONE_ALIAS.get(s, s)


# the stone's own article(s): its catalyst, never one of its outcomes
OWN = {"tiger-king": ["Tiger King", "Tiger King: Murder, Mayhem and Madness"], "queens-gambit": ["The Queen's Gambit (miniseries)"],
       "chernobyl": ["Chernobyl (miniseries)"], "squid-game": ["Squid Game", "Squid Game season 1"],
       "stranger-things-4": ["Stranger Things (season 4)", "Stranger Things season 4", "Stranger Things"],
       "the-last-of-us": ["The Last of Us (TV series)"], "shogun": ["Shōgun (2024 TV series)"], "barbie": ["Barbie (film)"],
       "oppenheimer": ["Oppenheimer (film)"], "jwst": ["James Webb Space Telescope"], "wordle": ["Wordle"],
       "mr-bates-horizon": ["Mr Bates vs The Post Office"], "octopus-sentience": ["My Octopus Teacher"],
       "ocean-attenborough": ["Ocean with David Attenborough"], "adolescence-schools": ["Adolescence (TV series)"],
       "svb": ["Collapse of Silicon Valley Bank"], "ever-given": ["Ever Given", "2021 Suez Canal obstruction"],
       "gdpr": ["General Data Protection Regulation"], "pokemon-go": ["Pokémon Go"], "gamestop": ["GameStop short squeeze", "GameStop"],
       "chatgpt": ["ChatGPT"], "tiktok": ["TikTok"]}
# where each stone's catalyst series (its own attention, aligned at the stone) is stored; the longest baseline wins
CATALYST = {"tiger-king": ("long", "tiger_king_attention.json:event"), "queens-gambit": ("long", "queens_gambit_attention.json:event"),
            "chernobyl": ("map", "chernobyl:0"), "squid-game": ("map", "squid-game:0"), "stranger-things-4": ("map", "stranger-things-4:0"),
            "the-last-of-us": ("map", "the-last-of-us:0"), "shogun": ("map", "shogun:0"), "barbie": ("map", "barbie:0"),
            "oppenheimer": ("map", "oppenheimer:0"), "jwst": ("map", "jwst-first-images:0"), "wordle": ("map", "wordle:0"),
            "mr-bates-horizon": ("attn", "mr-bates-horizon:1"), "octopus-sentience": ("attn", "octopus-sentience:1"),
            "ocean-attenborough": ("attn", "ocean-attenborough:1"), "adolescence-schools": ("attn", "adolescence-schools:1"),
            "svb": ("attn", "svb:1"), "ever-given": ("attn", "ever-given:1"), "gdpr": ("attn", "gdpr:1"),
            "pokemon-go": ("chain", "pokemon-go:1"), "gamestop": ("chain", "gamestop:1"), "chatgpt": ("chain", "chatgpt:1"), "tiktok": ("chain", "tiktok:1")}
# map steps that follow another step rather than the stone (from the MAPS table in demo/index.html)
MAP_PARENT = {("tiger-king", 2): 1, ("queens-gambit", 2): 1, ("chernobyl", 2): 1}
# link type of every confirmed step, assigned from the claim (see the plan's table); discovered leads are all media -> search
FAMILY = {
    "chain:frozen:2": "culture -> naming", "chain:tiger-king:2": "media -> search", "chain:pokemon-go:1": "launch -> adoption",
    "chain:wordle:2": "launch -> adoption", "chain:barbie:4": "event -> new term", "chain:chernobyl-zone:2": "media -> search",
    "chain:mr-bates-horizon:2": "media -> search", "chain:mr-bates-horizon:9": "media -> search", "chain:daily-show-zadroga:5": "news -> search",
    "chain:ocean-attenborough:2": "media -> search", "chain:america-and-alcohol:25": "news -> search", "chain:covid-remote:2": "event -> new term",
    "chain:jwst:2": "news -> search", "chain:gamestop:1": "news -> search", "chain:chatgpt:1": "launch -> adoption",
    "chain:airpods:2": "launch -> adoption", "chain:tiktok:1": "launch -> adoption", "chain:thailand-floods:4": "shock -> prices and purchases",
    "chain:cash-for-clunkers:4": "shock -> prices and purchases", "chain:queens-gambit-2:2": "media -> search",
    "chain:toilet-paper:1": "shock -> prices and purchases", "chain:toilet-paper:2": "news -> search", "chain:squid-game-ripples:12": "media -> search",
    "map:barbie:1": "media -> search", "map:chernobyl:1": "media -> search", "map:chernobyl:2": "search -> search",
    "map:jwst-first-images:1": "news -> search", "map:oppenheimer:1": "media -> search", "map:queens-gambit:1": "media -> search",
    "map:queens-gambit:2": "search -> search", "map:shogun:1": "media -> search", "map:squid-game:1": "media -> search",
    "map:squid-game:2": "media -> search", "map:stranger-things-4:1": "media -> search", "map:stranger-things-4:2": "media -> search",
    "map:the-last-of-us:1": "media -> search", "map:tiger-king:1": "media -> search", "map:tiger-king:2": "search -> search",
    "map:wordle:1": "media -> search",
    "attn:haber-nitrogen:7": "news -> search", "attn:america-and-alcohol:21": "news -> search", "attn:three-mile-island-nrc:10": "news -> search",
    "attn:serial:4": "news -> search", "attn:squid-game-ripples:5": "news -> search", "attn:gdpr:1": "news -> search",
}
# duplicates keep the record that carries the checker's own verdict first; the long files only add series stored nowhere else
SOURCE_RANK = {"chain": 0, "map": 1, "disc": 2, "attn": 3, "owner": 4, "editor": 5, "hop2": 6, "long": 7}
CHAIN_YES = ("measured", "timed (new article)", "timed (short history)", "moved, wrong order")
ATTN_YES = ("attention rose", "article created then", "rose, no placebo history")
ATTN_NO = ("within chance", "no sustained rise")


def norm(a):
    return (a or "").replace("_", " ").strip().lower()


def k0_of(weekly, parent):
    """Index of the weekly bin that starts at, or contains, the parent date."""
    starts = [D(d) for d, _ in weekly]
    k = max((i for i, s in enumerate(starts) if s <= parent), default=None)
    return k if k is not None and (parent - starts[k]).days < 7 else None


def load_real():
    """Every stored series as a record. No statistic is computed here."""
    R = []

    def add(**kw):
        kw.setdefault("resolution", "weekly")
        R.append(kw)

    # 1. the two long daily files, re-binned to weeks that start on the stone's date
    for f in LONG_FILES:
        d = json.load(open(os.path.join(RES, f)))
        st = (D(d["event_day"]) - LONG_DAY0).days
        for name, s in d["series"].items():
            v = np.array(s, float)
            wk = [[(LONG_DAY0 + dt.timedelta(days=st + 7 * k)).isoformat(), float(v[st + 7 * k:st + 7 * k + 7].sum())] for k in range(-12, 30)]
            on = (d.get("onsets") or {}).get(name) or {}
            add(id=f"long:{f}:{name}", source="long", stone=stone_of(f), slug=f, articles=[name.replace("_", " ")] if name != "event" else ["event:" + stone_of(f)],
                role="catalyst" if name == "event" else "outcome", tier="stored attention file", parent=d["event_day"], parent_what="stone",
                weekly=wk, house_response=None, house={"onset": on.get("day")})
    # 2. generated maps: the event series is the catalyst; attention steps are outcomes; monthly library series are listed only
    for path in sorted(glob.glob(os.path.join(ROOT, "maps", "out", "*.json"))):
        if path.endswith("index.json"):
            continue
        m = json.load(open(path))
        cfg = json.load(open(os.path.join(ROOT, "maps", m["slug"] + ".json")))
        for i, s in enumerate(m["steps"]):
            sid = f"map:{m['slug']}:{i}"
            se = s.get("series") or {}
            if s.get("monthly"):
                add(id=sid, source="map", stone=stone_of(m["slug"]), slug=m["slug"], articles=re.findall(r"“([^”]+)”", s.get("measure", "")), role="outcome",
                    tier="product", parent=m["release"], parent_what="stone", weekly=None, resolution="monthly", house_response=None,
                    house={"evidence": s.get("evidence")}, claim=s.get("title"))
                continue
            if not se.get("weekly"):
                continue
            pi = MAP_PARENT.get((m["slug"], i))
            parent = m["steps"][pi]["date"] if pi else m["release"]
            arts = [a.replace("_", " ") for a in cfg["event_articles"]] if i == 0 else re.findall(r"“([^”]+)”", s.get("measure", ""))
            # map_builder.py stores each week as the mean daily views; every other source stores weekly totals (deviation 1)
            wk7 = [[d0, 7.0 * float(v0)] for d0, v0 in se["weekly"]]
            add(id=sid, source="map", stone=stone_of(m["slug"]), slug=m["slug"], step=i, articles=arts, role="catalyst" if i == 0 else "outcome",
                tier="product", parent=parent, parent_what=f"step {pi}" if pi else "stone", weekly=wk7,
                house_response=None if i == 0 else s.get("evidence") in ("tested", "timed"),
                house={"evidence": s.get("evidence"), "onset": se.get("onset")}, claim=s.get("title"),
                lag_days=None if i == 0 or not s.get("date") or len(s["date"]) < 10 else (D(s["date"]) - D(parent)).days)
    # 3. attention leads shown in the product (measured), aligned at the stone
    disc = json.load(open(os.path.join(ROOT, "demo", "discovered.json")))
    shown = set()
    for slug, ev in disc["events"].items():
        for l in ev["links"]:
            shown.add((slug, l["title"]))
            add(id=f"disc:{slug}:{l['title']}", source="disc", stone=stone_of(slug), slug=slug, articles=[l["title"]], role="outcome", tier="product",
                parent=ev["date"], parent_what="stone", weekly=l["weekly"], house_response=True,
                house={"p": l["p"], "ratio": l["ratio"], "onset": l["onset"]}, claim=l.get("headline"), lag_days=l["lag"])
    # 4. every engine candidate (first hop) and 5. second-hop candidates
    for fname, src, tier in (("editor_trail_v1.json", "editor", "engine candidate"), ("editor_trail_hop2.json", "hop2", "engine second hop")):
        et = json.load(open(os.path.join(RES, fname)))
        for slug, ev in et["events"].items():
            for c in ev.get("candidates", []):
                if not c.get("weekly"):
                    continue
                add(id=f"{src}:{slug}:{c['title']}", source=src, stone=stone_of(slug), slug=slug, articles=[c["title"]], role="outcome", tier=tier,
                    parent=ev["date"], parent_what="stone" if src == "editor" else "first-hop lead", weekly=c["weekly"],
                    house_response=None if c.get("p") is None else c["p"] <= 0.05, house={"p": c.get("p"), "ratio": c.get("ratio"), "onset": c.get("onset")},
                    lag_days=c.get("lag"), shown=(slug, c["title"]) in shown)
    # 6. checked chains: wiki steps, attention checks, and official series (listed, not classified)
    cc = json.load(open(os.path.join(RES, "chain_check_v1.json")))
    for ch in cc["chains"]:
        for s in ch["steps"]:
            v = s.get("verdict", "")
            if s.get("weekly"):
                add(id=f"chain:{ch['slug']}:{s['n']}", source="chain", stone=stone_of(ch["slug"]), slug=ch["slug"], step=s["n"],
                    articles=s["test"].get("articles") or [], role="outcome", tier="claim", parent=s["ref"], parent_what="step before",
                    weekly=s["weekly"], house_response=True if v in CHAIN_YES else False if v == "no movement" else None,
                    house={"verdict": v, "p": s.get("p"), "ratio": s.get("ratio"), "onset": s.get("onset")}, claim=s.get("claim"),
                    lag_days=(D(s["onset"]) - D(s["ref"])).days if s.get("onset") else None)
            elif s.get("points") and s["test"]["type"] in ("fred", "ssa", "file", "zillow", "arxiv", "stackex"):
                per = s.get("period_days") or (365 if s["test"]["type"] == "ssa" else 31)
                add(id=f"chain:{ch['slug']}:{s['n']}", source="chain", stone=stone_of(ch["slug"]), slug=ch["slug"], step=s["n"],
                    articles=[str(s.get("series") or s["test"].get("id") or s["test"]["type"])], role="outcome", tier="claim", parent=s["ref"],
                    parent_what="step before", weekly=None, resolution="annual" if per >= 300 else "monthly",
                    house_response=True if v in CHAIN_YES else False if v == "no movement" else None,
                    house={"verdict": v, "p": s.get("p"), "onset": s.get("onset")}, claim=s.get("claim"),
                    lag_days=(D(s["onset"]) - D(s["ref"])).days if s.get("onset") else None)
            a = s.get("attn") or {}
            if a.get("weekly") and s.get("onset"):
                av = a.get("verdict") or ""
                add(id=f"attn:{ch['slug']}:{s['n']}", source="attn", stone=stone_of(ch["slug"]), slug=ch["slug"], step=s["n"],
                    articles=a.get("articles") or [], role="outcome", tier="claim (attention check)", parent=s["onset"], parent_what="the step's own date",
                    weekly=a["weekly"], house_response=True if av in ATTN_YES else False if av in ATTN_NO else None,
                    house={"verdict": av, "p": a.get("p"), "ratio": a.get("ratio"), "onset": a.get("onset")}, claim=s.get("claim"),
                    lag_days=(D(a["onset"]) - D(s["onset"])).days if a.get("onset") else None)
    # 7. the older owner-chain run (weekly windows of uneven length)
    oc = json.load(open(os.path.join(RES, "owner_chains_v1.json")))
    for i, tst in enumerate(oc["tests"]):
        if not tst.get("weekly"):
            continue
        add(id=f"owner:{tst['chain']}:{tst['step']}:{tst['label']}", source="owner", stone=stone_of(tst["chain"]), slug=tst["chain"], step=tst["step"],
            articles=list(tst.get("found") or {}), role="outcome", tier="claim (older run)", parent=tst["ref"], parent_what=tst.get("ref_what"),
            weekly=tst["weekly"], house_response=True if tst.get("onset") else False if tst.get("result") else None,
            house={"onset": tst.get("onset"), "ratio": tst.get("ratio"), "result": tst.get("result")}, claim=tst.get("label"),
            lag_days=tst.get("lag_days"))
    # catalysts named in the table take the catalyst role
    cat_ids = {f"{src}:{key}" if src != "long" else f"long:{key}" for src, key in CATALYST.values()}
    for r in R:
        if r["id"] in cat_ids:
            r["role"] = "catalyst"
    # duplicates: the same stone, first article and parent date; the better-aligned source is kept
    best = {}
    for r in sorted(R, key=lambda r: SOURCE_RANK[r["source"]]):
        key = (r["stone"], norm((r["articles"] or [""])[0]), r["parent"], r["resolution"])
        if key in best:
            r["duplicate_of"] = best[key]
        else:
            best[key] = r["id"]
    return R


def times(x):
    """A multiplier in plain words: two significant figures, no decimals above ten."""
    return f"{x:.1f}" if x < 10 else f"{int(float(f'{x:.2g}')):,}"


def plain_words(c):
    """How the product could say the shape. A baseline under 10 views a day reads as "from almost nothing", since a
    multiplier over an empty article says more about the floor than the response."""
    s = c.get("shape")
    if s in (None, "no response", "not classified"):
        return "no unusual change" if s == "no response" else None
    tiny = (c.get("baseline_weekly") or 0) < 70
    wk = lambda n: "a week" if n <= 1 else f"{n} weeks"  # noqa: E731
    if s == "immediate spike":
        txt = f"a spike that was mostly gone within {wk(c['fade_weeks'])}" if c.get("fade_weeks") else "a spike within days"
    elif s == "pulse and decay":
        txt = f"a jump that faded over {wk(c['fade_weeks'])}" if c.get("fade_weeks") else f"a jump that was still fading after {c['window_weeks']} weeks"
    elif s == "step change":
        txt = (f"a new normal from almost nothing, still there {c['window_weeks']} weeks on" if tiny else
               f"a new normal: about {times(c['late_lift'])} times the old level, still there {c['window_weeks']} weeks on")
    elif s == "gradual ramp":
        pk = c["peak_week"]
        txt = f"a slow climb that peaked after about {round(pk / 4.35)} months" if pk >= 9 else f"a slow climb that peaked after {pk} weeks"
    elif s == "delayed spike":
        txt = f"a spike that arrived {c['onset_week']} weeks later"
    elif s == "late spike":
        txt = f"a spike {c['onset_week']} weeks later; that far out it may belong to another story"
    else:
        txt = f"came in {c['waves']} waves"
    if c.get("raised_floor"):
        txt += ", then settled well above where it started" if tiny else f", then settled at about {times(c['late_lift'])} times its old level"
    if c.get("onset_week") is not None and c["onset_week"] < 0:
        txt += " (it began rising before the date)"
    return txt


def shape_of(r, W, P, tau):
    if r.get("resolution") != "weekly" or not r.get("weekly"):
        return {"shape": "not classified", "why": f"{r.get('resolution')} series: the rules are calibrated on weekly attention"}
    k0 = k0_of(r["weekly"], D(r["parent"]))
    if k0 is None:
        return {"shape": "not classified", "why": "parent date outside the stored weeks"}
    w = [v for _, v in r["weekly"]]
    return classify(w, k0, W, P, tau, force=r.get("house_response") is True)


def quantiles(lags):
    a = np.array(sorted(lags), float)
    return {"n": len(a), "min": float(a.min()), "q10": float(np.percentile(a, 10)), "q25": float(np.percentile(a, 25)),
            "median": float(np.median(a)), "q75": float(np.percentile(a, 75)), "q90": float(np.percentile(a, 90)), "max": float(a.max())}


def prior_window(lags):
    """The registered window rule: [q10, q90] with five or more lags, [min, max] with three or four, none below three."""
    if len(lags) >= 5:
        q = quantiles(lags)
        return q["q10"], q["q90"], "q10-q90"
    if len(lags) >= 3:
        return float(min(lags)), float(max(lags)), "min-max"
    return None


def weeks_for(lo, hi, post):
    a = max(-1, math.floor(lo / 7))
    b = min(W_MAIN - 1, math.floor(hi / 7) + 1, post - 1)
    return a, max(a, b)


def detect(r, a, b, P, wt, q):
    k0 = k0_of(r["weekly"], D(r["parent"]))
    w = np.array([v for _, v in r["weekly"]], float)
    bb = baseline(w, k0, P["smin"])
    x, m, s, pmax = bb
    ks = np.arange(k0 + a, k0 + b + 1)
    ok = float((w[ks] - (10 ** m - FLOOR)).max()) >= MIN_EXCESS
    T = gate_stat(P["stat"], x, m, s, pmax, ks)
    tau = wt[f"{a}:{b}"][0 if q == 95 else 1]
    return bool(ok and T >= tau)


def mcnemar(a, b):
    """Exact two-sided McNemar p for paired hits a (method 1) and b (method 2)."""
    n10 = sum(1 for x, y in zip(a, b) if x and not y)
    n01 = sum(1 for x, y in zip(a, b) if y and not x)
    n = n10 + n01
    if n == 0:
        return 1.0, n10, n01
    k = min(n10, n01)
    p = sum(math.comb(n, i) for i in range(0, k + 1)) / 2 ** n
    return min(1.0, 2 * p), n10, n01


def real_mode() -> int:
    cal = json.load(open(PLACEBO_OUT))
    chosen = {k: cal["chosen"][k] for k in FROZEN}
    if chosen != FROZEN:
        sys.exit(f"FROZEN does not match {PLACEBO_OUT}: {chosen} vs {FROZEN}")
    P, tau, tau13, wt = FROZEN, FROZEN["tau"], FROZEN["tau13"], cal["window_tau"]
    R = load_real()
    by_id = {r["id"]: r for r in R}
    # ---- 1. shapes ----
    for r in R:
        post = None
        if r.get("weekly") and r.get("resolution") == "weekly":
            k0 = k0_of(r["weekly"], D(r["parent"]))
            post = None if k0 is None else len(r["weekly"]) - k0
            r["pre_weeks"], r["post_weeks"] = (None, None) if k0 is None else (min(k0 + PRE[1] + 1, PRE[1] - PRE[0] + 1), post)
        r["shape21"] = shape_of(r, W_MAIN, P, tau)
        r["shape13"] = shape_of(r, W_SHORT, P, tau13) if post and post >= W_SHORT else None
        r["shape_full"] = shape_of(r, post, P, tau) if post and post > W_MAIN else None
        r["plain"] = plain_words(r["shape21"])
    uniq = [r for r in R if not r.get("duplicate_of")]
    cls = lambda c: c and c.get("shape") not in (None, "no response", "not classified")  # noqa: E731
    mix, mix_tier = {}, {}
    for r in uniq:
        s = r["shape21"]["shape"]
        mix[s] = mix.get(s, 0) + 1
        mix_tier.setdefault(r["tier"], {})
        mix_tier[r["tier"]][s] = mix_tier[r["tier"]].get(s, 0) + 1
    # truncation: the class at 13 weeks against the class at 21 weeks, series with 21 or more post weeks
    tr = [r for r in uniq if r.get("post_weeks") and r["post_weeks"] >= W_MAIN and cls(r["shape13"]) and cls(r["shape21"])]
    same = sum(r["shape13"]["shape"] == r["shape21"]["shape"] for r in tr)
    flips = {}
    for r in tr:
        if r["shape13"]["shape"] != r["shape21"]["shape"]:
            k = f"{r['shape13']['shape']} -> {r['shape21']['shape']}"
            flips[k] = flips.get(k, 0) + 1
    appeared = sum(1 for r in uniq if r.get("post_weeks") and r["post_weeks"] >= W_MAIN and r["shape13"] and not cls(r["shape13"]) and cls(r["shape21"]))
    vanished = sum(1 for r in uniq if r.get("post_weeks") and r["post_weeks"] >= W_MAIN and cls(r["shape13"]) and r["shape21"] and not cls(r["shape21"]))
    trunc = {"series": len(tr), "same": same, "share": round(same / max(1, len(tr)), 4), "bar": 0.80, "passed": bool(len(tr) and same / len(tr) >= 0.80),
             "flips": dict(sorted(flips.items(), key=lambda x: -x[1])), "response_appeared_after_13_weeks": appeared, "response_gone_by_21_weeks": vanished,
             "planted_reference": cal["truncation_planted"]["share"]}
    tr_tier = {}
    for r in tr:
        t = tr_tier.setdefault(r["tier"], [0, 0])
        t[0] += r["shape13"]["shape"] == r["shape21"]["shape"]
        t[1] += 1
    trunc["by_tier"] = {k: {"same": v[0], "series": v[1]} for k, v in tr_tier.items()}
    # ---- 2. lag families ----
    units = []
    for r in R:
        fam = FAMILY.get(r["id"]) or ("media -> search" if r["source"] == "disc" else None)
        if not fam:
            continue
        if r["source"] == "attn":
            v = r["house"].get("verdict")
            if v != "attention rose" or r.get("lag_days") is None or r["lag_days"] < -3:
                continue
        if r.get("lag_days") is None:
            continue
        units.append(r)
    seen, U = {}, []
    for r in sorted(units, key=lambda r: SOURCE_RANK[r["source"]]):
        key = (r["stone"], norm((r["articles"] or [""])[0]), r["parent"])
        if key in seen or r.get("duplicate_of") in seen.values():
            r["lag_duplicate_of"] = seen.get(key) or r.get("duplicate_of")
            continue
        seen[key] = r["id"]
        U.append(r)
    fams = {}
    for r in U:
        fams.setdefault(FAMILY.get(r["id"]) or "media -> search", []).append(r)
    priors = {}
    for f, rs in sorted(fams.items()):
        lags = [r["lag_days"] for r in rs]
        pw = prior_window(lags)
        priors[f] = {"quantiles_days": quantiles(lags), "window_days": None if pw is None else [round(pw[0], 1), round(pw[1], 1)],
                     "window_rule": None if pw is None else pw[2], "resolution": sorted({r["resolution"] for r in rs}),
                     "units": [{"id": r["id"], "lag_days": r["lag_days"], "stone": r["stone"], "tier": r["tier"], "claim": r.get("claim")} for r in sorted(rs, key=lambda r: r["lag_days"])]}
        if f == "media -> search":
            for sub, pick in (("subject (catalog and map steps)", lambda r: r["source"] != "disc"), ("spillover (engine leads)", lambda r: r["source"] == "disc")):
                sl = [r["lag_days"] for r in rs if pick(r)]
                if sl:
                    priors[f].setdefault("sub", {})[sub] = quantiles(sl)
    pooled = [r["lag_days"] for r in U]
    pw = prior_window(pooled)
    priors_all = {"quantiles_days": quantiles(pooled), "window_days": [round(pw[0], 1), round(pw[1], 1)], "window_rule": pw[2]}
    # held-out: leave one stone out; series with a weekly window, 6+ baseline weeks and 13+ post weeks
    ev = []
    for r in U:
        if r.get("resolution") != "weekly" or not r.get("weekly"):
            continue
        k0 = k0_of(r["weekly"], D(r["parent"]))
        if k0 is None or baseline(np.array([v for _, v in r["weekly"]], float), k0, P["smin"]) is None:
            continue
        post = len(r["weekly"]) - k0
        if post < W_SHORT:
            continue
        f = FAMILY.get(r["id"]) or "media -> search"
        train_f = [u["lag_days"] for u in U if u["stone"] != r["stone"] and (FAMILY.get(u["id"]) or "media -> search") == f]
        train_all = [u["lag_days"] for u in U if u["stone"] != r["stone"]]
        pw = prior_window(train_f)
        used = "family"
        if pw is None:
            pw, used = prior_window(train_all), "pooled"
        row = {"id": r["id"], "family": f, "stone": r["stone"], "lag_days": r["lag_days"], "prior_days": [round(pw[0], 1), round(pw[1], 1)],
               "prior_from": used, "n_train": len(train_f) if used == "family" else len(train_all), "post_weeks": post}
        for q in (95, 99):
            a, b = weeks_for(pw[0], pw[1], post)
            row[f"prior_weeks"] = [a, b]
            row[f"hit_prior_{q}"] = detect(r, a, b, P, wt, q)
            for name, hi in (("7", 6), ("30", 29), ("90", 89)):  # days 0-6, 0-29 and 0-89 after the parent
                a2, b2 = weeks_for(0, hi, post)
                row[f"hit_{name}_{q}"] = detect(r, a2, b2, P, wt, q)
        row["lag_inside_prior"] = bool(pw[0] <= r["lag_days"] <= pw[1])
        ev.append(row)
    held = {"units": ev, "n": len(ev)}
    for q in (95, 99):
        rates = {m: round(float(np.mean([e[f"hit_{m}_{q}"] for e in ev])), 4) if ev else None for m in ("prior", "7", "30", "90")}
        best = max(("7", "30", "90"), key=lambda m: (rates[m], -int(m)))
        p, n10, n01 = mcnemar([e[f"hit_prior_{q}"] for e in ev], [e[f"hit_{best}_{q}"] for e in ev])
        held[f"fp_{100 - q}pct"] = {"hit_rate": rates, "best_fixed": best + " days", "prior_minus_best": round(rates["prior"] - rates[best], 4),
                                    "prior_only": n10, "fixed_only": n01, "mcnemar_p": round(p, 4), "passed": bool(rates["prior"] > rates[best])}
    held["lag_inside_prior_share"] = round(float(np.mean([e["lag_inside_prior"] for e in ev])), 4) if ev else None
    held["bar"] = "held-out hit rate with family priors strictly above the best of the 7, 30 and 90-day windows, each at 5% false positives on decoy dates"
    held["passed"] = held["fp_5pct"]["passed"]
    # reported-only lags from a stone to its lasting mark (context; never a prior: a citation is reported, never measured)
    cc = json.load(open(os.path.join(RES, "chain_check_v1.json")))
    marks = {}
    for ch in cc["chains"]:
        for s in ch["steps"]:
            if s.get("mark") and s.get("verdict") == "reported" and s.get("onset") and len(s["onset"]) == 10:
                marks.setdefault(s["mark"], []).append({"chain": ch["slug"], "n": s["n"], "days_from_stone": (D(s["onset"]) - D(ch["date"])).days,
                                                        "claim": s["claim"]})
    marks_out = {k: {"quantiles_days": quantiles([u["days_from_stone"] for u in v]), "steps": sorted(v, key=lambda u: u["days_from_stone"])}
                 for k, v in sorted(marks.items(), key=lambda kv: -len(kv[1])) if len(v) >= 1}
    # ---- 3. catalyst vs outcome ----
    decoy_cat = []
    for f, name, v, st in long_series():
        for t in decoy_starts(len(v), st):
            wk = weekly_at(v, t)
            x, m, s, pmax = baseline(wk, 12, P["smin"])
            decoy_cat.append(gate_stat(P["stat"], x, m, s, pmax, np.arange(10, 16)))
    decoy_cat = np.array(decoy_cat)
    stones = {}
    for stone, (src, key) in sorted(CATALYST.items()):
        cid = f"{src}:{key}" if src != "long" else f"long:{key}"
        c = by_id.get(cid)
        if c is None:
            stones[stone] = {"catalyst": None, "why": f"{cid} not found"}
            continue
        w = np.array([v for _, v in c["weekly"]], float)
        k0 = k0_of(c["weekly"], D(c["parent"]))
        bb = baseline(w, k0, P["smin"])
        if bb is None:
            stones[stone] = {"catalyst": {"id": cid}, "why": "catalyst baseline too short"}
            continue
        x, m, s, pmax = bb
        ks = np.arange(max(0, k0 - 2), min(len(w), k0 + 4))
        lift = 10 ** (float(x[ks].max()) - m)
        S = gate_stat(P["stat"], x, m, s, pmax, ks)
        ccls = "weak" if lift < 10 else "strong" if lift >= 100 else "moderate"
        # deviation 2: a stone whose own article had no views at all from week -12 to week 3 (created later) has no
        # measurable catalyst; its flags are withheld rather than read as a weak catalyst
        measurable = bool(w[max(0, k0 - 12):k0 + 4].sum() > 0)
        own = {norm(a) for a in OWN.get(stone, [])} | {norm(a) for a in c["articles"]}
        outs = []
        for r in R:
            if r["stone"] != stone or r["role"] != "outcome" or r.get("duplicate_of") or r["id"] == cid:
                continue
            if norm((r["articles"] or [""])[0]) in own or not r.get("weekly") or r.get("resolution") != "weekly":
                continue
            sh = r["shape21"]
            k0o = k0_of(r["weekly"], D(r["parent"]))
            wo = np.array([v for _, v in r["weekly"]], float)
            bo = None if k0o is None else baseline(wo, k0o, P["smin"])
            if bo is None or len(wo) - k0o < MIN_POST:
                continue
            xo, mo, so, po = bo
            kso = np.arange(k0o, min(len(wo), k0o + W_MAIN))
            lo_ = 10 ** (float(xo[kso].max()) - mo)
            gate = bool(sh.get("gate"))
            responded = gate or r.get("house_response") is True
            flat = not gate and r.get("house_response") is not True
            outsized = bool(measurable and responded and (lo_ >= lift or (ccls == "weak" and lo_ >= 10)))
            no_echo = bool(measurable and ccls == "strong" and flat)
            base_w = 10 ** mo - FLOOR
            row = {"id": r["id"], "tier": r["tier"], "articles": r["articles"], "parent": r["parent"], "parent_what": r["parent_what"],
                   "claim": r.get("claim"), "lift": round(lo_, 2), "strength": round(gate_stat(P["stat"], xo, mo, so, po, kso), 3),
                   "gate": gate, "house_response": r.get("house_response"), "responded": responded, "flat": flat, "strong": bool(responded and lo_ >= 10),
                   "elasticity": round(math.log10(lo_) / math.log10(lift), 3) if lift > 1 and lo_ > 0 else None, "outsized": outsized, "no_echo": no_echo,
                   "low_baseline": bool(base_w < 70), "shape": sh.get("shape"), "plain": r["plain"]}
            outs.append(row)
            r["catalyst_strength"] = {"lift": round(lift, 2), "strength": round(S, 3), "class": ccls}
            r["outcome_strength"] = {"lift": row["lift"], "strength": row["strength"]}
            r["disproportion"] = "outsized response" if outsized else "no echo" if no_echo else None
        stones[stone] = {"catalyst": {"id": cid, "articles": c["articles"], "parent": c["parent"], "lift": round(lift, 2), "strength": round(S, 3),
                                      "class": ccls if measurable else "not measurable (the article did not exist yet)", "measurable": measurable, "decoy_percentile": round(float((decoy_cat < S).mean()), 4), "shape": c["shape21"].get("shape"),
                                      "plain": c["plain"]},
                         "outcomes": sorted(outs, key=lambda o: -o["lift"]),
                         "counts": {"outcomes": len(outs), "responded": sum(o["responded"] for o in outs), "flat": sum(o["flat"] for o in outs),
                                    "outsized": sum(o["outsized"] for o in outs), "no_echo": sum(o["no_echo"] for o in outs)}}
        c["catalyst_strength"] = stones[stone]["catalyst"]
    # ---- write ----
    keep = ("id", "source", "stone", "slug", "step", "articles", "role", "tier", "parent", "parent_what", "claim", "resolution", "pre_weeks",
            "post_weeks", "house_response", "house", "lag_days", "duplicate_of", "shape21", "shape13", "shape_full", "plain",
            "catalyst_strength", "outcome_strength", "disproportion")
    series = [{k: r.get(k) for k in keep if k in r} for r in R]
    try:
        sha = os.popen("git -C '%s' rev-parse --short HEAD 2>/dev/null" % ROOT).read().strip()
    except Exception:  # noqa: BLE001
        sha = ""
    out = {"protocol": "ripples/docs/shape_plan_v1.md", "code": "ripples/lab/discovery/shape.py real", "run": dt.date.today().isoformat(), "code_sha": sha,
           "frozen": FROZEN, "counts": {"series": len(R), "unique": len(uniq), "by_source": {s: sum(r["source"] == s for r in R) for s in SOURCE_RANK},
                                        "classified_unique": sum(1 for r in uniq if cls(r["shape21"]))},
           "shape_mix_unique": dict(sorted(mix.items(), key=lambda x: -x[1])), "shape_mix_by_tier": mix_tier, "truncation": trunc,
           "stones": stones, "series": series}
    json.dump(out, open(SHAPE_OUT, "w"), indent=1, ensure_ascii=False)
    pri = {"protocol": "ripples/docs/shape_plan_v1.md", "code": "ripples/lab/discovery/shape.py real", "run": dt.date.today().isoformat(), "code_sha": sha,
           "families": priors, "pooled": priors_all, "held_out": held, "reported_stone_to_mark": marks_out,
           "note": "Lags are days from the parent step's date to the response's onset as the checker dated it. A family window is the "
                   "registered rule over that family's confirmed lags; reported_stone_to_mark is context only, never a prior."}
    json.dump(pri, open(PRIOR_OUT, "w"), indent=1, ensure_ascii=False)
    print(json.dumps({"counts": out["counts"], "mix": out["shape_mix_unique"], "truncation": trunc,
                      "held_out": {k: v for k, v in held.items() if k != "units"},
                      "priors": {f: {"n": v["quantiles_days"]["n"], "median": v["quantiles_days"]["median"], "window": v["window_days"]} for f, v in priors.items()}},
                     indent=1, ensure_ascii=False))
    return 0


def count_mode() -> int:
    """Structure check before registration: how many records each loader yields. Computes no statistic."""
    R = load_real()
    print({s: sum(r["source"] == s for r in R) for s in SOURCE_RANK}, "total", len(R), "duplicates", sum(1 for r in R if r.get("duplicate_of")),
          "catalysts", sum(r["role"] == "catalyst" for r in R), "family-tagged", sum(1 for r in R if r["id"] in FAMILY))
    missing = [k for k in FAMILY if not any(r["id"] == k for r in R)]
    print("family ids not found:", missing)
    cats = {f"{s}:{k}" if s != "long" else f"long:{k}" for s, k in CATALYST.values()}
    print("catalyst ids not found:", [c for c in cats if not any(r["id"] == c for r in R)])
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "placebo"
    if mode == "placebo":
        sys.exit(placebo_mode())
    if mode == "real":
        sys.exit(real_mode())
    if mode == "count":
        sys.exit(count_mode())
    sys.exit(f"unknown mode {mode}")
