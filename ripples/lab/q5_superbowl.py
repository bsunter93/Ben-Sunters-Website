"""Confirmation of Super Bowls -> numerals (ripples/docs/q5_superbowl_numerals_protocol.md, ledger 1457).

Local-season test: each Super Bowl (LI-LX) is scored on a fixed outcome with discovery v1's onset-coupled statistic,
and compared with the same statistic at the Sundays 1-3 weeks before and after that year's game (6 per year). The
family score (sum of per-event z / sqrt(10)) is compared with 10,000 draws that swap each game day for one of its own
year's local Sundays... (v1 design, found miscalibrated in offline null tests before any real data: 16% false
positives at 0.05). Registered implementation (amendment before running): the local contrast
T = sum_i [z(game_i) - mean_k z(game_i + k)] / sqrt(n), k in +/-1..3 weeks (Sundays), is compared with 2,000 sets in
which every game is replaced by a random Sunday across the panel and the same contrast is computed. A plain seasonal
effect cancels inside each contrast; the null is calibrated by construction.

Per-event z (implementation note registered before running): MAD z against 200 random Sundays across the panel
(same-weekday placebos), clipped at +/-4. Negative control: Super Bowl 50 (2016-02-07, branded with Arabic numerals).
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys

import numpy as np

import cult_data as CD
import cultural_lab as L
from q3_run import event_views
from q4_matched import series

SEED = 20260930
N_PLACEBO, N_NULL, CLIP = 200, 2000, 4.0
OUTCOMES = ["Roman numerals", "Arabic numerals"]
LOCAL = [-21, -14, -7, 7, 14, 21]
GAMES = [("Super Bowl LI", "2017-02-05"), ("Super Bowl LII", "2018-02-04"), ("Super Bowl LIII", "2019-02-03"),
         ("Super Bowl LIV", "2020-02-02"), ("Super Bowl LV", "2021-02-07"), ("Super Bowl LVI", "2022-02-13"),
         ("Super Bowl LVII", "2023-02-12"), ("Super Bowl LVIII", "2024-02-11"), ("Super Bowl LIX", "2025-02-09"),
         ("Super Bowl LX", "2026-02-08")]
CONTROL = ("Super Bowl 50", "2016-02-07")


def curve(e, d0):
    win, pre = e[d0 + L.CT[0]:d0 + L.CT[-1] + 1], e[d0 - 60:d0]
    if np.isfinite(win).sum() < 0.8 * len(L.CT):
        return None
    base = np.nanmedian(pre) if np.isfinite(pre).sum() >= 20 else np.nanpercentile(win, 10)
    c = np.clip(np.nan_to_num(win - base), 0, None)
    mm = c[(L.CT >= 1) & (L.CT <= 30)].mean()
    if mm <= 0.05:
        return None
    return np.diff(np.concatenate([[0.0], c / mm]))


def main() -> int:
    z = np.load(os.path.join(CD.CACHE, "pv.npz"), allow_pickle=False)
    days = z["days"]
    D = len(days)
    start, end = dt.date.fromordinal(int(days[0])), dt.date.fromordinal(int(days[-1]))
    med = np.nanmedian(np.log1p(z["views"].astype(np.float64)), axis=0)
    lo, hi = 60 + 21, D - 121
    rng = np.random.default_rng(SEED)
    sundays = np.array([d for d in range(lo, hi) if (start + dt.timedelta(days=int(d))).weekday() == 6])
    pdays = rng.choice(sundays, size=N_PLACEBO, replace=False)
    inner = sundays[(sundays >= lo + 21) & (sundays < hi - 21)]
    report = {"protocol": "ripples/docs/q5_superbowl_numerals_protocol.md", "ledger": 1457, "seed": SEED,
              "outcomes": {}, "control_event": CONTROL[0]}
    try:
        curves = {}
        for art, day in GAMES + [CONTROL]:
            ev, titles = event_views(art, end, True)
            e = series(ev, start, D)
            d0 = (dt.date.fromisoformat(day) - start).days
            dc = curve(e, d0) if titles and 0 <= d0 < D else None
            curves[art] = (d0, dc, len(titles))
        for out in OUTCOMES:
            sv, stitles = event_views(out, end, True)
            x = (series(sv, start, D) - med)[None, :]
            res = {"subject_titles_used": len(stitles), "events": [], "_zf": []}
            zs, local = [], []
            for art, day in GAMES + [CONTROL]:
                d0, dc, nt = curves[art]
                if dc is None:
                    res["events"].append({"event": art, "day0": day, "skip": "no usable event curve", "titles": nt})
                    continue
                stat = lambda d, dc=dc: float(L.couple_diff_stat(x, int(d), dc)[0])  # noqa: E731
                P = np.array([stat(d) for d in pdays])
                pm = float(np.median(P))
                ps = 1.4826 * float(np.median(np.abs(P - pm))) or np.nan
                zf = lambda d: float(np.clip((stat(d) - pm) / ps, -CLIP, CLIP)) if np.isfinite(ps) else 0.0  # noqa
                zg = zf(d0)
                zl = [zf(d0 + k) for k in LOCAL]
                row = {"event": art, "day0": day, "z_game": round(zg, 3), "z_local": [round(v, 3) for v in zl],
                       "game_above_all_local": bool(zg > max(zl)),
                       "p_global": round(float((1 + (P >= stat(d0)).sum()) / (1 + N_PLACEBO)), 4)}
                res["events"].append(row)
                if art != CONTROL[0]:
                    zs.append(zg)
                    local.append(zl)
                    res["_zf"].append(zf)
            n = len(zs)
            if n >= 3:
                contrast = lambda zg, zl: zg - float(np.mean(zl))  # noqa: E731
                obs = sum(contrast(a, b) for a, b in zip(zs, local)) / np.sqrt(n)
                fz = [ev_z for ev_z in res.pop("_zf")]
                null = np.empty(N_NULL)
                for w in range(N_NULL):
                    ds = rng.choice(inner, size=n)
                    null[w] = sum(contrast(f(d), [f(d + k) for k in LOCAL]) for f, d in zip(fz, ds)) / np.sqrt(n)
                res.update(n_games=n, local_contrast=round(float(obs), 3),
                           p_local_season=round(float((1 + (null >= obs).sum()) / (1 + N_NULL)), 5),
                           games_above_all_local=int(sum(r.get("game_above_all_local", False) for r in res["events"]
                                                         if r["event"] != CONTROL[0])),
                           median_game_z=round(float(np.median(zs)), 3))
                ctl = next((r for r in res["events"] if r["event"] == CONTROL[0] and "z_game" in r), None)
                if ctl:
                    res["control_z"] = ctl["z_game"]
                    res["control_below_median"] = bool(ctl["z_game"] < np.median(zs))
            res.pop("_zf", None)
            report["outcomes"][out] = res
    except CD.Stop as e:
        report["stopped"] = str(e)
        print(f"stopped: {e}", flush=True)
    rn = report["outcomes"].get("Roman numerals", {})
    report["verdict_primary"] = ("confirmed (timing)" if rn.get("p_local_season", 1) <= 0.05 else
                                 "not confirmed" if "p_local_season" in rn else "not run")
    txt = json.dumps(report, indent=1)
    print(txt, flush=True)
    open(os.environ.get("Q5_OUT", "q5_superbowl_numerals.json"), "w").write(txt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
