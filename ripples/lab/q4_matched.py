"""Q4 named-subject test (ripples/docs/q4_protocol_v1.md): does each event move attention to its own owner-named
subject? Discovery v1's statistic (onset-coupled day-to-day changes, ledger 1283) with a pre-specified outcome per
event, so there is no search over outcomes.

For every event: the event curve comes from the event article's views (summed over redirects), exactly as in
q3_run.py; the outcome is the subject article's views (summed over redirects), log(1 + views) minus the daily median of
the 998-article Wikipedia panel (removing platform-wide swings). The event's z-scores (MAD and rank) come from 200
placebo dates for its own subject; its p-value is the rank of the real score among the placebos. A family's score is
sum(z) / sqrt(n), tested against 1,000 worlds in which every event is moved to a random admissible date and scored
against its own subject again.

Politeness is q3_run.py's (1 s pause, stop on refusal). Reads $LAB_CACHE/pv.npz for the day grid and the panel median.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys

import numpy as np

import cult_data as CD
import cultural_lab as L
from q3_run import cached, event_views

SEED = 20261001
N_PLACEBO, N_NULL, CLIP = 200, 1000, 4.0
FILE = os.path.join(os.path.dirname(__file__), "..", "corpus", "q4_subjects_v1.tsv")


def read(path):
    fams = {}
    for line in open(path, encoding="utf-8"):
        if line.startswith("#") or line.startswith("family\t") or not line.strip():
            continue
        fam, eid, art, day0, subj = line.rstrip("\n").split("\t")
        fams.setdefault(fam, []).append({"id": eid, "article": art, "day0": day0, "subject": subj})
    return fams


def series(views: dict, start: dt.date, D: int) -> np.ndarray:
    out = np.full(D, np.nan)
    for k, v in views.items():
        i = (dt.date(int(k[:4]), int(k[4:6]), int(k[6:8])) - start).days
        if 0 <= i < D:
            out[i] = np.log1p(v)
    return out


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else FILE
    z = np.load(os.path.join(CD.CACHE, "pv.npz"), allow_pickle=False)
    days = z["days"]
    D = len(days)
    start, end = dt.date.fromordinal(int(days[0])), dt.date.fromordinal(int(days[-1]))
    med = np.nanmedian(np.log1p(z["views"].astype(np.float64)), axis=0)
    lo, hi = 364 + 61, D - 121
    rng = np.random.default_rng(SEED)
    pdays = rng.integers(lo, hi, size=N_PLACEBO)
    ztab = np.array([L._NORM.inv_cdf(1 - min(max((1 + k) / (1 + N_PLACEBO), 0.5 / (1 + N_PLACEBO)),
                                             1 - 0.5 / (1 + N_PLACEBO))) for k in range(N_PLACEBO + 1)])
    report = {"protocol": "ripples/docs/q4_protocol_v1.md", "method": "discovery v1 statistic, named subject per event",
              "seed": SEED, "file": os.path.basename(path), "families": {}}
    for fam, members in read(path).items():
        used = []
        for m in members:
            try:
                ev, titles = event_views(m["article"], end, True)
                sv, stitles = event_views(m["subject"], end, True)
                m["titles_used"], m["subject_titles_used"] = len(titles), len(stitles)
                links = cached("q3links", m["article"], lambda: CD.page_links(m["article"], "0"))
            except CD.Stop as e:
                print(f"stopped: {e}", flush=True)
                report["stopped"] = str(e)
                break
            m["subject_linked_from_event"] = m["subject"] in set(links)
            e = series(ev, start, D)
            x = series(sv, start, D) - med
            if not titles or not np.isfinite(e).any():
                m["skip"] = "event article missing"
                continue
            if not stitles or np.isfinite(x).sum() < 365:
                m["skip"] = "subject article missing"
                continue
            d0 = (dt.date.fromisoformat(m["day0"]) - start).days
            if not (lo <= d0 < hi):
                m["skip"] = "day outside admissible range"
                continue
            win, pre = e[d0 + L.CT[0]:d0 + L.CT[-1] + 1], e[d0 - 60:d0]
            if np.isfinite(win).sum() < 0.8 * len(L.CT):
                m["skip"] = "too few views around the event"
                continue
            base = np.nanmedian(pre) if np.isfinite(pre).sum() >= 20 else np.nanpercentile(win, 10)
            c = np.clip(np.nan_to_num(win - base), 0, None)
            mm = c[(L.CT >= 1) & (L.CT <= 30)].mean()
            if mm <= 0.05:
                m["skip"] = "no attention rise"
                continue
            dc = np.diff(np.concatenate([[0.0], c / mm]))
            X = x[None, :]
            stat = lambda d: float(L.couple_diff_stat(X, int(d), dc)[0])  # noqa: E731
            P = np.array([stat(d) for d in pdays])
            pm = float(np.median(P))
            ps = 1.4826 * float(np.median(np.abs(P - pm))) or np.nan

            def zpair(d, P=P, pm=pm, ps=ps, stat=stat):
                s = stat(d)
                return (float(np.clip((s - pm) / ps, -CLIP, CLIP)) if np.isfinite(ps) else 0.0,
                        float(ztab[int((P >= s).sum())]), s)

            zm, zr, s = zpair(d0)
            m.update(z_mad=round(zm, 3), z_rank=round(zr, 3),
                     p_event=round(float((1 + (P >= s).sum()) / (1 + N_PLACEBO)), 4))
            m["_z"], m["_d0"] = zpair, d0
            used.append(m)
        n = len(used)
        out = {"members": [{k: v for k, v in m.items() if not k.startswith("_")} for m in members], "n_used": n}
        if n >= 3:
            om = sum(m["z_mad"] for m in used) / np.sqrt(n)
            orr = sum(m["z_rank"] for m in used) / np.sqrt(n)
            NM, NR = np.zeros(N_NULL), np.zeros(N_NULL)
            for w in range(N_NULL):
                zz = [m["_z"](rng.integers(lo, hi))[:2] for m in used]
                NM[w] = sum(a for a, _ in zz) / np.sqrt(n)
                NR[w] = sum(b for _, b in zz) / np.sqrt(n)
            out.update(score_mad=round(float(om), 3), score_rank=round(float(orr), 3),
                       p_mad=round(float((1 + (NM >= om).sum()) / (1 + N_NULL)), 4),
                       p_rank=round(float((1 + (NR >= orr).sum()) / (1 + N_NULL)), 4),
                       events_p_le_05=int(sum(m["p_event"] <= 0.05 for m in used)))
        report["families"][fam] = out
        print(f"{fam}: {n} events scored", flush=True)
        if report.get("stopped"):
            break
    txt = json.dumps(report, indent=1, ensure_ascii=False, default=str)
    print(txt)
    with open(os.environ.get("Q4_OUT", "q4_subjects_v1.json"), "w", encoding="utf-8") as f:
        f.write(txt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
