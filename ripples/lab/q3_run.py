"""Q3 screen v1: discovery v1 (ledger 1283) on the registered real event families (ripples/docs/q3_protocol.md).

Reads the lab panel ($LAB_CACHE/pv.npz, 998 Vital Articles), downloads each event article's daily views and its
outgoing links (for echo flags) with the same politeness as cult_data.py, and prints a JSON report. Nothing here is a
finding: results are candidates for a separately registered confirmation.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import sys
import time
import urllib.parse

import numpy as np

import cult_data as CD
import cultural_lab as L

SEED = 20260929
N_PLACEBO, N_NULL, CLIP = 200, 1000, 4.0
PAUSE = 1.0  # seconds between Wikimedia requests
FAM_FILE = os.path.join(os.path.dirname(__file__), "..", "corpus", "q3_families_v1.tsv")


def read_families():
    fams = {}  # FAM_FILE may be replaced from the command line
    for line in open(FAM_FILE, encoding="utf-8"):
        if line.startswith("#") or line.startswith("family\t") or not line.strip():
            continue
        fam, eid, title, day0 = line.rstrip("\n").split("\t")
        fams.setdefault(fam, []).append({"id": eid, "article": title, "day0": day0})
    return fams


def cached(kind, title, fetch):
    d = os.path.join(CD.CACHE, kind)
    os.makedirs(d, exist_ok=True)
    name = urllib.parse.quote(title, safe="")
    if len(name) > 200:  # Linux allows 255 bytes; long non-Latin titles are keyed by a hash instead
        name = "md5-" + hashlib.md5(title.encode("utf-8")).hexdigest()
    f = os.path.join(d, name + ".json")
    if not os.path.exists(f):
        data = fetch()
        json.dump(data, open(f, "w"))
        time.sleep(PAUSE)  # one Wikimedia request at a time with a pause (run of 2026-09-28 was stopped by a 429)
    return json.load(open(f))


def event_views(title, end, redirects):
    """Daily views of the event article; with redirects=True summed over its current title and all its redirects."""
    if not redirects:
        return cached("q3pv", title, lambda: CD.views(title, end)), [title]
    titles = cached("q3titles", title, lambda: CD.titles_with_redirects(title))
    total = {}
    for t in titles:
        for k, v in cached("q3pv", t, lambda: CD.views(t, end)).items():
            total[k] = total.get(k, 0) + v
    return total, titles


def norm_name(t):
    """Loose name key for echo matching across panels: NYT tags ("subject:Chess", "persons:Obama, Barack") and
    Wikipedia titles ("Chess", "Barack Obama", "Mercury (planet)") map to the same lower-case words."""
    t = t.split(":", 1)[1] if ":" in t and t.split(":", 1)[0].isalpha() and t.split(":", 1)[0].islower() else t
    t = t.split(" (")[0]
    if t.count(",") == 1:  # "Last, First" person names
        last, first = [w.strip() for w in t.split(",")]
        t = f"{first} {last}"
    return " ".join(t.replace("_", " ").lower().split())


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--families", default="")
    ap.add_argument("--redirects", action="store_true", help="sum event-article views over all redirect titles")
    ap.add_argument("--confirm", default="", help="pre-specified outcomes, '|'-separated: confirmation mode")
    ap.add_argument("--panel", default="pv.npz", help="outcome panel in $LAB_CACHE (pv.npz = Wikipedia; nyt_pv.npz = "
                    "NYT tag coverage). Event curves always come from Wikipedia; the panel sets the day grid.")
    ap.add_argument("--same-weekday", action="store_true", help="placebo and moved dates keep each event's weekday")
    ap.add_argument("--min-coverage", type=float, default=0.0,
                    help="an outcome gets no score for an event when less than this share of its window has data")
    a = ap.parse_args()
    global FAM_FILE
    FAM_FILE = a.families or FAM_FILE
    confirm = [t for t in a.confirm.split("|") if t]
    z = np.load(os.path.join(CD.CACHE, a.panel), allow_pickle=False)
    arts, days = [str(a) for a in z["articles"]], z["days"]
    raw = bool(z["raw"]) if "raw" in z.files else False  # pre-transformed panel (econ_panel.py): use values as they are
    lv = z["views"].astype(np.float64) if raw else np.log1p(z["views"].astype(np.float64))
    A, D = lv.shape
    start = dt.date.fromordinal(int(days[0]))
    end = dt.date.fromordinal(int(days[-1]))
    x = lv if raw else lv - np.nanmedian(lv, axis=0)
    fin = np.isfinite(x)
    lo, hi = 364 + 61, D - 121
    rng = np.random.default_rng(SEED)
    pdays = rng.integers(lo, hi, size=N_PLACEBO)
    adm = np.arange(lo, hi)

    def cstat(d, dc):
        s = L.couple_diff_stat(x, int(d), dc)
        if a.min_coverage > 0:
            cov = fin[:, int(d) + L.CT[0] - 1:int(d) + L.CT[-1] + 1].mean(axis=1)
            s = np.where(cov >= a.min_coverage, s, np.nan)
        return s

    def draw(d0, size=None):
        pool = adm[(adm - d0) % 7 == 0] if a.same_weekday else adm
        return rng.choice(pool, size=size)
    ztab = np.array([L._NORM.inv_cdf(1 - min(max((1 + k) / (1 + N_PLACEBO), 0.5 / (1 + N_PLACEBO)),
                                             1 - 0.5 / (1 + N_PLACEBO))) for k in range(N_PLACEBO + 1)])
    ztabn = np.zeros((N_PLACEBO + 1, N_PLACEBO + 1))  # [placebos with a score, placebos at or above] -> z
    for nf in range(1, N_PLACEBO + 1):
        for k in range(nf + 1):
            ztabn[nf, k] = L._NORM.inv_cdf(1 - min(max((1 + k) / (1 + nf), 0.5 / (1 + nf)), 1 - 0.5 / (1 + nf)))
    fams = read_families()
    report = {"options": {"panel": a.panel, "same_weekday": a.same_weekday, "min_coverage": a.min_coverage},
              "protocol": os.environ.get("Q3_PROTOCOL", "ripples/docs/q3_protocol.md"), "method": "discovery v1 (ledger 1283)", "seed": SEED,
              "panel": {"file": a.panel, "articles": A, "start": str(start), "end": str(end)}, "families": {}}
    art_idx = {a: k for k, a in enumerate(arts)}

    for fam, members in fams.items():
        used, echoes = [], set()
        for m in members:
            try:
                s, titles = event_views(m["article"], end, a.redirects)
                m["titles_used"] = len(titles)
                links = cached("q3links", m["article"], lambda: CD.page_links(m["article"], "0"))
            except CD.Stop as e:
                print(f"stopped: {e}", flush=True)
                return 1
            echoes |= {norm_name(t) for t in list(links) + [m["article"]]}
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
            P = np.stack([cstat(d, dc) for d in (draw(d0, N_PLACEBO) if a.same_weekday else pdays)])
            pm = np.nanmedian(P, axis=0)
            ps = 1.4826 * np.nanmedian(np.abs(P - pm), axis=0)
            ps = np.where(ps > 0, ps, np.nan)
            m.update(d0=str(start + dt.timedelta(days=d0)), _d0=d0, _dc=dc, _P=P, _pm=pm, _ps=ps,
                     _nf=np.isfinite(P).sum(axis=0))
            used.append(m)
        n = len(used)
        # common-shock flag: members whose event days fall within 30 days of another member (a shared shock such as
        # the March 2020 lockdown can masquerade as a family ripple; leave-one-out is the guard, this is the warning)
        ds = sorted((m["_d0"], m["id"]) for m in used)
        clustered = set()
        for (d1, id1), (d2, id2) in zip(ds, ds[1:]):
            if d2 - d1 <= 30:
                clustered |= {id1, id2}
        clustered = sorted(clustered)
        if n < 3:
            report["families"][fam] = {"members": members, "note": "fewer than 3 usable members; not tested"}
            continue

        def zpair(m, d):
            s = cstat(d, m["_dc"])
            zm = np.clip((s - m["_pm"]) / m["_ps"], -CLIP, CLIP)
            k = (m["_P"] >= s[None, :]).sum(axis=0)
            # with a coverage rule some placebo dates have no score: rank against the placebos that do
            zr = ztab[k] if a.min_coverage <= 0 else ztabn[m["_nf"], k]
            return np.nan_to_num(zm), np.where(np.isfinite(s), zr, 0.0)

        obs = [zpair(m, m["_d0"]) for m in used]
        OM = np.stack([o[0] for o in obs])  # members x A
        OR = np.stack([o[1] for o in obs])
        smad, srank = OM.sum(0) / np.sqrt(n), OR.sum(0) / np.sqrt(n)
        NM = np.zeros((N_NULL, n, A), np.float32)
        NR = np.zeros((N_NULL, n, A), np.float32)
        for w in range(N_NULL):
            for k, m in enumerate(used):
                NM[w, k], NR[w, k] = zpair(m, draw(m["_d0"]) if a.same_weekday else rng.integers(lo, hi))
        if confirm:
            res = []
            for t in confirm:
                if t not in art_idx:
                    res.append({"outcome": t, "error": "not in panel"})
                    continue
                j = art_idx[t]
                nm, nr = NM[:, :, j].sum(1) / np.sqrt(n), NR[:, :, j].sum(1) / np.sqrt(n)
                res.append({"outcome": t, "echo": norm_name(t) in echoes, "score_mad": round(float(smad[j]), 3),
                            "score_rank": round(float(srank[j]), 3),
                            "p_mad": round(float((1 + (nm >= smad[j]).sum()) / (1 + N_NULL)), 4),
                            "p_rank": round(float((1 + (nr >= srank[j]).sum()) / (1 + N_NULL)), 4),
                            "member_z_mad": [round(float(v), 2) for v in OM[:, j]]})
            report["families"][fam] = {"members": [{k: v for k, v in m.items() if not k.startswith("_")}
                                                   for m in members], "n_used": n, "clustered_members": clustered,
                                       "confirmation": res}
            print(f"{fam}: {n} members, confirmation {res}", flush=True)
            continue
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
            "clustered_members": clustered,
            "min_p_both": float(p_both.min()),
            "top": [{"article": arts[j], "score_mad": round(float(smad[j]), 3), "score_rank": round(float(srank[j]), 3),
                     "p_mad": round(float(p_mad[j]), 4), "p_rank": round(float(p_rank[j]), 4),
                     "loo_stable": bool(loo[j]), "echo": norm_name(arts[j]) in echoes,
                     "member_z_mad": [round(float(v), 2) for v in OM[:, j]]} for j in order],
            "_pboth": p_both, "_loo": loo, "_echo": echoes,  # echoes holds normalized names
        }
        print(f"{fam}: {n} members, min p {p_both.min():.4f}", flush=True)

    if confirm:
        out = json.dumps(report, indent=1, ensure_ascii=False, default=str)
        print(out)
        with open(os.environ.get("Q3_OUT", "q3_confirm.json"), "w", encoding="utf-8") as f:
            f.write(out)
        return 0
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
                                  "echo": norm_name(arts[j]) in r["_echo"]})
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
