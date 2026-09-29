"""Q6: the named-subject test on attention lenses beyond Wikipedia (ripples/docs/q6_lenses_protocol.md, ledger 1464).

Same design as Q4 (q4_matched.py): the event curve comes from the event's Wikipedia article (it only fixes the event's
timing and shape); the outcome is the event's own pre-named subject, measured in each lens:
  wiki: the subject article's views (summed over redirects), log(1 + views) minus the 998-article panel's daily median;
  tv:   US TV-news caption mentions of the subject phrase, log(1 + 1e7 * mentions / caption words that day);
  hn:   Hacker News items mentioning the subject phrase, log(1 + 1e4 * items / all items that day).
Registered change from Q4 v1 for all lenses, the Wikipedia one included: placebo and moved dates keep each event's
weekday (TV and HN have strong weekly cycles). A subject enters a lens only if it has at least 30 days with a mention in
the panel window (TV: 1-2-word phrases only). Per event: MAD and rank z against 200 same-weekday placebo dates; per
family: sum(z)/sqrt(n) against 1,000 worlds of same-weekday moved dates. Pass: p <= 0.05 for both versions.
"""
from __future__ import annotations

import csv
import datetime as dt
import json
import os
import sys

import numpy as np

import cult_data as CD
import cultural_lab as L
from q3_run import event_views
from q4_matched import read, series

SEED = 20261002
N_PLACEBO, N_NULL, CLIP, MIN_DAYS = 200, 1000, 4.0, 30
CORPUS = os.path.join(os.path.dirname(__file__), "..", "corpus")
FILES = ["q4_subjects_v1.tsv", "q4_subjects_v1b.tsv", "q4_heldout_drama_v1.tsv"]
LENSES = ["wiki", "tv", "hn"]


def phrase(s: str) -> str:
    import re
    return " ".join(re.sub(r"\s*\([^)]*\)", "", s).lower().split())


def load_lens(path, start, D, scale):
    counts, total = {}, np.full(D, np.nan)
    if not os.path.exists(path):
        return None
    for r in csv.DictReader(open(path, encoding="utf-8")):
        i = (dt.date.fromisoformat(r["day"]) - start).days
        if not 0 <= i < D:
            continue
        if r["phrase"] == "__total__":
            total[i] = float(r["n"])
        else:
            counts.setdefault(r["phrase"], np.zeros(D))[i] += float(r["n"])
    ok = np.isfinite(total) & (total > 0)

    def get(p):
        c = counts.get(p)
        if c is None or (c[ok] > 0).sum() < MIN_DAYS:
            return None
        x = np.full(D, np.nan)
        x[ok] = np.log1p(scale * c[ok] / total[ok])
        return x
    return get, int(ok.sum())


def main() -> int:
    ldir = sys.argv[1] if len(sys.argv) > 1 else "."
    z = np.load(os.path.join(CD.CACHE, "pv.npz"), allow_pickle=False)
    days = z["days"]
    D = len(days)
    start, end = dt.date.fromordinal(int(days[0])), dt.date.fromordinal(int(days[-1]))
    med = np.nanmedian(np.log1p(z["views"].astype(np.float64)), axis=0)
    lo, hi = 364 + 61, D - 121
    adm = np.arange(lo, hi)
    rng = np.random.default_rng(SEED)
    ztab = np.array([L._NORM.inv_cdf(1 - min(max((1 + k) / (1 + N_PLACEBO), 0.5 / (1 + N_PLACEBO)),
                                             1 - 0.5 / (1 + N_PLACEBO))) for k in range(N_PLACEBO + 1)])
    getters = {"wiki": None}
    report = {"protocol": "ripples/docs/q6_lenses_protocol.md", "ledger": 1464, "seed": SEED, "same_weekday": True,
              "lens_days": {}, "families": {}}
    for lens, fn, scale in (("tv", "lens_tv.csv", 1e7), ("hn", "lens_hn.csv", 1e4)):
        g = load_lens(os.path.join(ldir, fn), start, D, scale)
        getters[lens] = g[0] if g else None
        report["lens_days"][lens] = g[1] if g else 0

    def wiki(subj):
        sv, st = event_views(subj, end, True)
        x = series(sv, start, D) - med
        return x if st and np.isfinite(x).sum() >= 365 else None

    fams = {}
    for f in FILES:
        for fam, ms in read(os.path.join(CORPUS, f)).items():
            fams.setdefault(fam, []).extend(ms)
    try:
        for fam, members in fams.items():
            famrep = {}
            for lens in LENSES:
                get = wiki if lens == "wiki" else getters[lens]
                used, rows = [], []
                for m in members:
                    row = {"id": m["id"], "article": m["article"], "subject": m["subject"]}
                    rows.append(row)
                    if get is None:
                        row["skip"] = "lens not built"
                        continue
                    if lens == "tv" and len(phrase(m["subject"]).split()) > 2:
                        row["skip"] = "phrase longer than 2 words"
                        continue
                    ev, titles = event_views(m["article"], end, True)
                    e = series(ev, start, D)
                    x = get(m["subject"]) if lens == "wiki" else get(phrase(m["subject"]))
                    if not titles or not np.isfinite(e).any():
                        row["skip"] = "event article missing"
                        continue
                    if x is None:
                        row["skip"] = "subject too rare in lens"
                        continue
                    d0 = (dt.date.fromisoformat(m["day0"]) - start).days
                    if not lo <= d0 < hi:
                        row["skip"] = "day outside admissible range"
                        continue
                    win, pre = e[d0 + L.CT[0]:d0 + L.CT[-1] + 1], e[d0 - 60:d0]
                    if np.isfinite(win).sum() < 0.8 * len(L.CT):
                        row["skip"] = "too few views around the event"
                        continue
                    base = np.nanmedian(pre) if np.isfinite(pre).sum() >= 20 else np.nanpercentile(win, 10)
                    c = np.clip(np.nan_to_num(win - base), 0, None)
                    mm = c[(L.CT >= 1) & (L.CT <= 30)].mean()
                    if mm <= 0.05:
                        row["skip"] = "no attention rise"
                        continue
                    dc = np.diff(np.concatenate([[0.0], c / mm]))
                    X = x[None, :]
                    pool = adm[(adm - d0) % 7 == 0]
                    stat = lambda d, X=X, dc=dc: float(L.couple_diff_stat(X, int(d), dc)[0])  # noqa: E731
                    P = np.array([stat(d) for d in rng.choice(pool, N_PLACEBO)])
                    pm = float(np.median(P))
                    ps = 1.4826 * float(np.median(np.abs(P - pm))) or np.nan

                    def zpair(d, P=P, pm=pm, ps=ps, stat=stat):
                        s = stat(d)
                        return (float(np.clip((s - pm) / ps, -CLIP, CLIP)) if np.isfinite(ps) else 0.0,
                                float(ztab[int((P >= s).sum())]), s)

                    zm, zr, s = zpair(d0)
                    row.update(z_mad=round(zm, 3), z_rank=round(zr, 3),
                               p_event=round(float((1 + (P >= s).sum()) / (1 + N_PLACEBO)), 4))
                    used.append((zpair, pool))
                n = len(used)
                out = {"n_used": n, "members": rows}
                if n >= 3:
                    om = sum(r["z_mad"] for r in rows if "z_mad" in r) / np.sqrt(n)
                    orr = sum(r["z_rank"] for r in rows if "z_rank" in r) / np.sqrt(n)
                    NM, NR = np.zeros(N_NULL), np.zeros(N_NULL)
                    for w in range(N_NULL):
                        zz = [zp(rng.choice(pool))[:2] for zp, pool in used]
                        NM[w] = sum(a for a, _ in zz) / np.sqrt(n)
                        NR[w] = sum(b for _, b in zz) / np.sqrt(n)
                    pmad = float((1 + (NM >= om).sum()) / (1 + N_NULL))
                    prank = float((1 + (NR >= orr).sum()) / (1 + N_NULL))
                    out.update(score_mad=round(float(om), 3), score_rank=round(float(orr), 3), p_mad=round(pmad, 4),
                               p_rank=round(prank, 4), passes=bool(pmad <= 0.05 and prank <= 0.05),
                               events_p_le_05=int(sum(r.get("p_event", 1) <= 0.05 for r in rows)))
                famrep[lens] = out
                print(f"{fam}/{lens}: {n} events", flush=True)
            report["families"][fam] = famrep
    except CD.Stop as e:
        report["stopped"] = str(e)
    # cross-lens agreement per event (MAD z), over events scored in both lenses
    agree = {}
    for a_, b_ in (("wiki", "tv"), ("wiki", "hn"), ("tv", "hn")):
        pa, pb = [], []
        for fr in report["families"].values():
            za = {r["id"]: r["z_mad"] for r in fr.get(a_, {}).get("members", []) if "z_mad" in r}
            for r in fr.get(b_, {}).get("members", []):
                if "z_mad" in r and r["id"] in za:
                    pa.append(za[r["id"]])
                    pb.append(r["z_mad"])
        agree[f"{a_}_vs_{b_}"] = {"n": len(pa), "spearman": round(float(np.corrcoef(np.argsort(np.argsort(pa)),
                                  np.argsort(np.argsort(pb)))[0, 1]), 3) if len(pa) >= 5 else None}
    report["agreement"] = agree
    txt = json.dumps(report, indent=1, ensure_ascii=False, default=str)
    open(os.environ.get("Q6_OUT", "q6_lenses_v1.json"), "w", encoding="utf-8").write(txt)
    print(json.dumps({f: {l: {k: v.get(k) for k in ("n_used", "p_mad", "p_rank", "passes")} for l, v in fr.items()}
                      for f, fr in report["families"].items()}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
