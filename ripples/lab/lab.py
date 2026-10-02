"""Ripple Lab: score a discovery design end to end in fake worlds (protocol: ledger 1279, ripples/lab/README.md).

A fake world keeps every real FEMA declaration date and state, but its "treated" counties are drawn at random from that
event's clean same-state donors, so no real effect exists. Effects of known size are planted in random
(shock group x outcome x window) cells. The full pipeline then runs: screen on pre-2016 events (BH), confirm on 2016+
events (calibrated one-sided p). Scorecard: false discoveries per run and recall of planted cells.

The only real-data use is the registered positive controls (--positive-controls), which are obvious by construction.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import time

import numpy as np
from scipy.special import erfc

sys.path.insert(0, os.path.dirname(__file__))
from data import CACHE, build_fema, build_panel  # noqa: E402

GROUPS = {
    "storm": {"Severe Storm", "Straight-Line Winds", "Tornado", "Coastal Storm"},
    "flood": {"Flood", "Dam/Levee Break", "Mud/Landslide"},
    "hurricane": {"Hurricane", "Tropical Storm", "Typhoon", "Tropical Depression"},
    "fire": {"Fire"},
    "winter": {"Severe Ice Storm", "Snowstorm", "Winter Storm", "Freezing"},
    "quake": {"Earthquake"},
}
WINDOWS = {"q1_2": (1, 2), "q3_6": (3, 6), "q7_10": (7, 10)}
PRE = (-4, -1)
REGIMES = [(20083, 20092), (20201, 20212)]
SPLIT_YEAR = 2016


def qnum(yq: int) -> int:
    return (yq // 10) * 4 + (yq % 10 - 1)


def build_events(panel: dict, fema: list[dict], min_donors: int = 6, split: str = "time", seed: int = 1) -> list[dict]:
    counties = [str(c) for c in panel["counties"]]
    ci = {c: i for i, c in enumerate(counties)}
    quarters = [int(q) for q in panel["quarters"]]
    q_index = {q: i for i, q in enumerate(quarters)}
    group_of = {it: g for g, its in GROUPS.items() for it in its}
    decl_q: dict[int, list[int]] = {}
    ev: dict[tuple[int, str], dict] = {}
    for r in fema:
        st, co = str(r.get("fipsStateCode") or "").zfill(2), str(r.get("fipsCountyCode") or "").zfill(3)
        d = (r.get("incidentBeginDate") or "")[:10]
        if not d or co == "000":
            continue
        y, m = int(d[:4]), int(d[5:7])
        yq = y * 10 + (m - 1) // 3 + 1
        c = st + co
        if c in ci and yq in q_index:
            decl_q.setdefault(ci[c], []).append(q_index[yq])
        g = group_of.get(r.get("incidentType"))
        if g is None or c not in ci:
            continue
        e = ev.setdefault((int(r["disasterNumber"]), st), {"num": int(r["disasterNumber"]), "state": st, "group": g,
                                                            "yq": yq, "treated": set()})
        e["yq"] = min(e["yq"], yq)
        e["treated"].add(ci[c])
    by_state: dict[str, list[int]] = {}
    for c, i in ci.items():
        by_state.setdefault(c[:2], []).append(i)
    decl_arr = {i: np.array(sorted(v)) for i, v in decl_q.items()}
    out = []
    for e in ev.values():
        if e["yq"] not in q_index:
            continue
        q0 = q_index[e["yq"]]
        lo, hi = q0 + PRE[0], q0 + max(w[1] for w in WINDOWS.values())
        if lo < 0 or hi >= len(quarters):
            continue
        qlo, qhi = quarters[lo], quarters[hi]
        if any(qlo <= r1 and qhi >= r0 for r0, r1 in REGIMES):
            continue
        donors = [i for i in by_state.get(e["state"], []) if i not in e["treated"]
                  and not (i in decl_arr and ((decl_arr[i] >= lo) & (decl_arr[i] <= hi)).any())]
        if len(donors) < min_donors:
            continue
        out.append({**e, "q0": q0, "treated": np.array(sorted(e["treated"])), "donors": np.array(donors),
                    "period": "screen" if e["yq"] // 10 < SPLIT_YEAR else "confirm"})
    if split == "random":   # random halves of events within each shock group (fixed seed, set before any data is read)
        r = np.random.default_rng(seed)
        for e in out:
            e["period"] = "screen" if r.random() < 0.5 else "confirm"
    return out


def deltas(panel: dict, events: list[dict]) -> None:
    """Attach d[county, series, window] = mean log(window) - mean log(pre) for treated and donors (NaN if incomplete)."""
    le = np.log(panel["emp"].astype(np.float64))
    for e in events:
        q0 = e["q0"]
        idx = np.concatenate([e["treated"], e["donors"]])
        pre = le[:, idx, q0 + PRE[0]:q0 + PRE[1] + 1].mean(axis=2)
        ws = [le[:, idx, q0 + a:q0 + b + 1].mean(axis=2) - pre for a, b in WINDOWS.values()]
        d = np.stack(ws, axis=2).transpose(1, 0, 2)  # [n, S, W]
        e["d_all"] = d
        e["nt_real"] = len(e["treated"])


def event_stats(d_t: np.ndarray, d_c: np.ndarray):
    mt, mc = np.nanmean(d_t, axis=0), np.nanmean(d_c, axis=0)
    nt, nc = np.sum(np.isfinite(d_t), axis=0), np.sum(np.isfinite(d_c), axis=0)
    vc = np.nanvar(d_c, axis=0, ddof=1)
    est = mt - mc
    var = vc * (1 / np.maximum(nt, 1) + 1 / np.maximum(nc, 1))
    bad = (nt < 1) | (nc < 3) | ~np.isfinite(var) | (var <= 0)
    est[bad], var[bad] = np.nan, np.nan
    return est, var


def pool(est: np.ndarray, var: np.ndarray, how: str):
    """est, var: [E, S, W] with NaN for missing. Returns z[S, W] and n events."""
    ok = np.isfinite(est) & np.isfinite(var)
    n = ok.sum(axis=0)
    e0, v0 = np.where(ok, est, 0.0), np.where(ok, var, 1.0)
    if how == "mean":
        m = e0.sum(axis=0) / np.maximum(n, 1)
        v = np.where(ok, var, 0.0).sum(axis=0) / np.maximum(n, 1) ** 2
    else:  # DerSimonian-Laird random effects
        w = np.where(ok, 1 / v0, 0.0)
        sw = w.sum(axis=0)
        mu = (w * e0).sum(axis=0) / np.maximum(sw, 1e-12)
        qs = (w * (e0 - mu) ** 2).sum(axis=0)
        c = sw - (w ** 2).sum(axis=0) / np.maximum(sw, 1e-12)
        tau2 = np.maximum(0.0, (qs - (n - 1)) / np.where(c > 0, c, np.inf))
        w2 = np.where(ok, 1 / (v0 + tau2), 0.0)
        m = (w2 * e0).sum(axis=0) / np.maximum(w2.sum(axis=0), 1e-12)
        v = 1 / np.maximum(w2.sum(axis=0), 1e-12)
    z = np.where(n >= 3, m / np.sqrt(v), np.nan)
    return z, n, m


def world(events, rng, how, plant=None, real=False):
    """z[group][period] -> [S, W]. plant: {(group, s, w): delta} added to (pseudo-)treated counties."""
    acc: dict[tuple[str, str], tuple[list, list]] = {}
    for e in events:
        d = e["d_all"]
        nt_real = e["nt_real"]
        if real:
            d_t, d_c = d[:nt_real], d[nt_real:]
        else:
            don = d[nt_real:]
            k = max(1, min(nt_real, len(don) // 2))
            pick = rng.permutation(len(don))
            d_t, d_c = don[pick[:k]].copy(), don[pick[k:]]
        if plant:
            for (g, s, w), delta in plant.items():
                if g == e["group"]:
                    d_t[:, s, w] += delta
        est, var = event_stats(d_t, d_c)
        a = acc.setdefault((e["group"], e["period"]), ([], []))
        a[0].append(est)
        a[1].append(var)
    out = {}
    for (g, p), (es, vs) in acc.items():
        z, n, m = pool(np.stack(es), np.stack(vs), how)
        out.setdefault(g, {})[p] = (z, n, m)
    return out


def calibrate(null_z: np.ndarray, z: np.ndarray, two_sided: bool, sign: np.ndarray | None = None,
              mode: str = "standardized"):
    """p per cell from null draws [B, ...]. "empirical" ranks z among the draws (resolution 1/(B+1), too coarse for
    BH over many cells); "standardized" centers and scales z by the null draws' mean and sd, then uses the normal tail."""
    if mode == "empirical":
        if two_sided:
            return (1 + (np.abs(null_z) >= np.abs(z)).sum(axis=0)) / (1 + null_z.shape[0])
        s = np.sign(sign)
        return (1 + ((s * null_z) >= (s * z)).sum(axis=0)) / (1 + null_z.shape[0])
    mu, sd = np.nanmean(null_z, axis=0), np.nanstd(null_z, axis=0, ddof=1)
    zc = (z - mu) / np.where(sd > 0, sd, np.nan)
    if two_sided:
        return erfc(np.abs(zc) / np.sqrt(2))
    return 0.5 * erfc(np.sign(sign) * zc / np.sqrt(2))


def bh(p: np.ndarray, q: float) -> np.ndarray:
    flat = p.ravel()
    ok = np.isfinite(flat)
    order = np.argsort(np.where(ok, flat, np.inf))
    m = ok.sum()
    passed = np.zeros_like(flat, dtype=bool)
    if m == 0:
        return passed.reshape(p.shape)
    ranks = np.arange(1, len(flat) + 1)
    below = np.where(ok[order], flat[order] <= q * ranks / m, False)
    if below.any():
        kmax = np.max(np.nonzero(below)[0])
        passed[order[:kmax + 1]] = True
    return passed.reshape(p.shape)


def run(args):
    t0 = time.time()
    panel, fema = build_panel(), build_fema()
    events = build_events(panel, fema, split=args.split)
    deltas(panel, events)
    groups = sorted({e["group"] for e in events})
    S, W = len(panel["series"]), len(WINDOWS)
    counts = {g: {p: sum(1 for e in events if e["group"] == g and e["period"] == p) for p in ("screen", "confirm")}
              for g in groups}
    print(f"events: {len(events)} {counts}  ({time.time() - t0:.0f}s)", flush=True)
    rng = np.random.default_rng(args.seed)

    def stack(worlds, g, p):
        return np.stack([w[g][p][0] if g in w and p in w[g] else np.full((S, W), np.nan) for w in worlds])

    report = {"design": {"estimator": args.estimator, "split": args.split, "split_year": SPLIT_YEAR, "windows": WINDOWS, "pre": PRE,
                         "bh_q": args.q, "pmode": args.pmode, "confirm_p": args.confirm_p, "null_draws": args.null},
              "events": counts, "series": [str(s) for s in panel["series"]]}
    nulls = [world(events, rng, args.estimator) for _ in range(args.null)]
    null_z = {(g, p): stack(nulls, g, p) for g in groups for p in ("screen", "confirm")}
    print(f"null draws done ({time.time() - t0:.0f}s)", flush=True)

    eligible = [(g, s, w) for g in groups for s in range(S) for w in range(W)
                if counts[g]["screen"] >= 5 and counts[g]["confirm"] >= 5]

    def pipeline(wz):
        ps = np.stack([calibrate(null_z[(g, "screen")], wz[g]["screen"][0], True, mode=args.pmode) if g in wz and "screen" in wz[g]
                       else np.full((S, W), np.nan) for g in groups])
        promoted = bh(ps, args.q)
        found = []
        for gi, g in enumerate(groups):
            if "confirm" not in wz.get(g, {}):
                continue
            zs, zc = wz[g]["screen"][0], wz[g]["confirm"][0]
            pc = calibrate(null_z[(g, "confirm")], zc, False, zs, mode=args.pmode)
            for s in range(S):
                for w in range(W):
                    if promoted[gi, s, w] and pc[s, w] <= args.confirm_p and np.sign(zc[s, w]) == np.sign(zs[s, w]):
                        found.append((g, s, w, float(np.sign(zc[s, w]))))
        return found, float(np.nanmean(ps <= 0.05))

    score = {}
    for delta in [0.0] + args.deltas:
        fp, tp, planted_total, cal = 0, 0, 0, []
        for r in range(args.worlds):
            plant = {}
            if delta > 0:
                for i in rng.choice(len(eligible), size=args.plants, replace=False):
                    plant[eligible[i]] = delta * rng.choice([-1, 1])
            wz = world(events, rng, args.estimator, plant)
            found, c = pipeline(wz)
            cal.append(c)
            planted_total += len(plant)
            for g, s, w, sign in found:
                if (g, s, w) in plant and np.sign(plant[(g, s, w)]) == sign:
                    tp += 1
                else:
                    fp += 1
        score[f"{delta:.3f}"] = {"false_discoveries_per_run": round(fp / args.worlds, 3),
                                 "recall": round(tp / planted_total, 3) if planted_total else None,
                                 "screen_p05_share_all_cells": round(float(np.mean(cal)), 3)}
        print(f"delta {delta:.3f}: {score[f'{delta:.3f}']} ({time.time() - t0:.0f}s)", flush=True)
    report["scorecard"] = score

    if args.positive_controls:
        real = world(events, rng, args.estimator, real=True)
        si = {str(s): i for i, s in enumerate(panel["series"])}
        wi = {k: i for i, k in enumerate(WINDOWS)}
        pcs = [("hurricane", "1012", "q3_6", +1), ("hurricane", "1012", "q7_10", +1), ("hurricane", "1026", "q1_2", -1)]
        res = []
        for g, s, w, sign in pcs:
            row = {"shock": g, "series": s, "window": w, "expected_sign": sign}
            for p in ("screen", "confirm"):
                if g in real and p in real[g]:
                    z, n, m = real[g][p]
                    z0 = z[si[s], wi[w]]
                    pv = calibrate(null_z[(g, p)][:, si[s], wi[w]], z0, False, np.array(sign), mode=args.pmode)
                    row[p] = {"effect_pct": round(100 * float(m[si[s], wi[w]]), 2), "z": round(float(z0), 2),
                              "p_one_sided": round(float(pv), 4), "events": int(n[si[s], wi[w]])}
            res.append(row)
        report["positive_controls_real"] = res
        print(json.dumps(res, indent=1), flush=True)

    report["seconds"] = round(time.time() - t0)
    return report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--estimator", choices=["dl", "mean"], default="dl")
    ap.add_argument("--worlds", type=int, default=40)
    ap.add_argument("--null", type=int, default=200)
    ap.add_argument("--plants", type=int, default=3)
    ap.add_argument("--deltas", type=float, nargs="*", default=[0.01, 0.02, 0.03])
    ap.add_argument("--q", type=float, default=0.10)
    ap.add_argument("--confirm-p", type=float, default=0.05)
    ap.add_argument("--split", choices=["time", "random"], default="time")
    ap.add_argument("--pmode", choices=["standardized", "empirical"], default="standardized")
    ap.add_argument("--seed", type=int, default=20260927)
    ap.add_argument("--positive-controls", action="store_true")
    ap.add_argument("--out", default="lab_report.json")
    a = ap.parse_args()
    rep = run(a)
    rep["run_at"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    json.dump(rep, open(a.out, "w"), indent=1)
    md = [f"### Ripple Lab ({a.estimator}, split={a.split})", "", f"events: `{json.dumps(rep['events'])}`", "",
          "| planted effect | false discoveries / run | recall | screen share p<=.05 |", "|---|---|---|---|"]
    for k, v in rep["scorecard"].items():
        md.append(f"| {k} | {v['false_discoveries_per_run']} | {v['recall']} | {v['screen_p05_share_all_cells']} |")
    if "positive_controls_real" in rep:
        md += ["", "Positive controls (real data, obvious by construction):", "```",
               json.dumps(rep["positive_controls_real"], indent=1), "```"]
    s = os.environ.get("GITHUB_STEP_SUMMARY")
    if s:
        open(s, "a").write("\n".join(md) + "\n")
    print("\n".join(md))
    return 0


if __name__ == "__main__":
    sys.exit(main())
