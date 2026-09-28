"""Q3 screen v1: discovery v1 (ledger 1283) on the registered real event families (ripples/docs/q3_protocol.md).

Reads the lab panel ($LAB_CACHE/pv.npz, 998 Vital Articles), downloads each event article's daily views and its
outgoing links (for echo flags) with the same politeness as cult_data.py, and prints a JSON report. Nothing here is a
finding: results are candidates for a separately registered confirmation.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys
import urllib.parse

import numpy as np

import cult_data as CD
import cultural_lab as L

SEED = 20260929
N_PLACEBO, N_NULL, CLIP = 200, 1000, 4.0
FAM_FILE = os.path.join(os.path.dirname(__file__), "..", "corpus", "q3_families_v1.tsv")


def read_families():
    fams = {}
    for line in open(FAM_FILE, encoding="utf-8"):
        if line.startswith("#") or line.startswith("family\t") or not line.strip():
            continue
        fam, eid, title, day0 = line.rstrip("\n").split("\t")
        fams.setdefault(fam, []).append({"id": eid, "article": title, "day0": day0})
    return fams


def cached(kind, title, fetch):
    d = os.path.join(CD.CACHE, kind)
    os.makedirs(d, exist_ok=True)
    f = os.path.join(d, urllib.parse.quote(title, safe="") + ".json")
    if not os.path.exists(f):
        json.dump(fetch(), open(f, "w"))
    return json.load(open(f))


def main() -> int:
    z = np.load(os.path.join(CD.CACHE, "pv.npz"), allow_pickle=False)
    arts, days = [str(a) for a in z["articles"]], z["days"]
    lv = np.log1p(z["views"].astype(np.float64))
    A, D = lv.shape
    start = dt.date.fromordinal(int(days[0]))
    end = dt.date.fromordinal(int(days[-1]))
    x = lv - np.nanmedian(lv, axis=0)
    lo, hi = 364 + 61, D - 121
    rng = np.random.default_rng(SEED)
    pdays = rng.integers(lo, hi, size=N_PLACEBO)
    ztab = np.array([L._NORM.inv_cdf(1 - min(max((1 + k) / (1 + N_PLACEBO), 0.5 / (1 + N_PLACEBO)),
                                             1 - 0.5 / (1 + N_PLACEBO))) for k in range(N_PLACEBO + 1)])
    fams = read_families()
    report = {"protocol": "ripples/docs/q3_protocol.md", "method": "discovery v1 (ledger 1283)", "seed": SEED,
              "panel": {"articles": A, "start": str(start), "end": str(end)}, "families": {}}
    art_idx = {a: k for k, a in enumerate(arts)}

    for fam, members in fams.items():
        used, echoes = [], set()
        for m in members:
            try:
                s = cached("q3pv", m["article"], lambda: CD.views(m["article"], end))
                links = cached("q3links", m["article"], lambda: CD.page_links(m["article"], "0"))
            except CD.Stop as e:
                print(f"stopped: {e}", flush=True)
                return 1
            echoes |= set(links) | {m["article"]}
            e = np.full(D, np.nan)
            for k, v in s.items():
                i = (dt.date(int(k[:4]), int(k[4:6]), int(k[6:8])) - start).days
                if 0 <= i < D:
                    e[i] = np.log1p(v)
            if ".." in m["day0"]:
                a0, b0 = [(dt.date.fromisoformat(t) - start).days for t in m["day0"].split("..")]
                seg = e[a0:b0 + 1]
                if not np.isfinite(seg).any():
                    m["skip"] = "no views in window"
                    continue
                d0 = a0 + int(np.nanargmax(seg))
            else:
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
            P = np.stack([L.couple_diff_stat(x, int(d), dc) for d in pdays])
            pm = np.nanmedian(P, axis=0)
            ps = 1.4826 * np.nanmedian(np.abs(P - pm), axis=0)
            ps = np.where(ps > 0, ps, np.nan)
            m.update(d0=str(start + dt.timedelta(days=d0)), _d0=d0, _dc=dc, _P=P, _pm=pm, _ps=ps)
            used.append(m)
        n = len(used)
        if n < 3:
            report["families"][fam] = {"members": members, "note": "fewer than 3 usable members; not tested"}
            continue

        def zpair(m, d):
            s = L.couple_diff_stat(x, int(d), m["_dc"])
            zm = np.clip((s - m["_pm"]) / m["_ps"], -CLIP, CLIP)
            zr = ztab[(m["_P"] >= s[None, :]).sum(axis=0)]
            return np.nan_to_num(zm), np.where(np.isfinite(s), zr, 0.0)

        obs = [zpair(m, m["_d0"]) for m in used]
        OM = np.stack([o[0] for o in obs])  # members x A
        OR = np.stack([o[1] for o in obs])
        smad, srank = OM.sum(0) / np.sqrt(n), OR.sum(0) / np.sqrt(n)
        NM = np.zeros((N_NULL, n, A), np.float32)
        NR = np.zeros((N_NULL, n, A), np.float32)
        for w in range(N_NULL):
            for k, m in enumerate(used):
                NM[w, k], NR[w, k] = zpair(m, rng.integers(lo, hi))
        max_mad = (NM.sum(1) / np.sqrt(n)).max(1)
        max_rank = (NR.sum(1) / np.sqrt(n)).max(1)
        p_mad = (1 + (max_mad[:, None] >= smad[None, :]).sum(0)) / (1 + N_NULL)
        p_rank = (1 + (max_rank[:, None] >= srank[None, :]).sum(0)) / (1 + N_NULL)
        p_both = np.maximum(p_mad, p_rank)
        # leave-one-member-out stability (MAD version): reduced score above the reduced family's null 95th percentile
        loo = np.ones(A, bool)
        for k in range(n):
            keep = [j for j in range(n) if j != k]
            red = OM[keep].sum(0) / np.sqrt(n - 1)
            thr = np.quantile((NM[:, keep].sum(1) / np.sqrt(n - 1)).max(1), 0.95)
            loo &= red >= thr
        order = np.argsort(p_both + 1e-9 * -smad)[:10]
        report["families"][fam] = {
            "members": [{k: v for k, v in m.items() if not k.startswith("_")} for m in members],
            "n_used": n,
            "min_p_both": float(p_both.min()),
            "top": [{"article": arts[j], "score_mad": round(float(smad[j]), 3), "score_rank": round(float(srank[j]), 3),
                     "p_mad": round(float(p_mad[j]), 4), "p_rank": round(float(p_rank[j]), 4),
                     "loo_stable": bool(loo[j]), "echo": arts[j] in echoes,
                     "member_z_mad": [round(float(v), 2) for v in OM[:, j]]} for j in order],
            "_pboth": p_both, "_loo": loo, "_echo": echoes,
        }
        print(f"{fam}: {n} members, min p {p_both.min():.4f}", flush=True)

    # Benjamini-Hochberg at q = 0.10 across tested families on each family's smallest p
    tested = [(f, r["min_p_both"]) for f, r in report["families"].items() if "min_p_both" in r]
    tested.sort(key=lambda t: t[1])
    k_pass = 0
    for i, (f, p) in enumerate(tested, 1):
        if p <= 0.10 * i / len(tested):
            k_pass = i
    passing = {f for f, _ in tested[:k_pass]}
    cands = []
    for f, r in report["families"].items():
        if "_pboth" in r:
            if f in passing:
                for j in np.where((r["_pboth"] <= 0.05) & r["_loo"])[0]:
                    cands.append({"family": f, "article": arts[j], "p_both": round(float(r["_pboth"][j]), 4),
                                  "echo": arts[j] in r["_echo"]})
            del r["_pboth"], r["_loo"], r["_echo"]
    report["bh_families_passing"] = sorted(passing)
    report["candidates"] = cands
    out = json.dumps(report, indent=1, ensure_ascii=False, default=str)
    print(out)
    with open(os.environ.get("Q3_OUT", "q3_screen_v1.json"), "w", encoding="utf-8") as f:
        f.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
