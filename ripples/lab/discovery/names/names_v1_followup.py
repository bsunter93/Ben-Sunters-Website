#!/usr/bin/env python3
"""Names v1 follow-up (ripples/docs/names_plan_v1.md section 10; specifics in names_v1_hypotheses.json, committed before
this runs): event siblings, generated hypotheses and the lag prior for every confirmed (measured) pair.

  python names_v1_followup.py   -> ripples/docs/results/names_v1_followup.json
"""
from __future__ import annotations

import json
import os
import random
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import names_v1 as nv  # noqa: E402

SIB_CO_SL, SIB_GENRE_SL, SIB_GENRE_MAX = 30, 60, 40


def chars_of_works(works):
    """Characters of each work (P1441 or the work's P674), with label, given-name labels, sex and English article."""
    out = {}
    for ch in nv.chunks(sorted(works), 40):
        vals = " ".join("wd:" + q for q in ch)
        q = f"""SELECT DISTINCT ?w ?c WHERE {{ VALUES ?w {{ {vals} }} {{ ?c wdt:P1441 ?w }} UNION {{ ?w wdt:P674 ?c }} }} LIMIT 20000"""
        for b in nv.sparql(q) or []:
            out.setdefault(nv.qid(nv.val(b, "w")), set()).add(nv.qid(nv.val(b, "c")))
    return {k: sorted(v) for k, v in out.items()}


def family_of(stone, R):
    """Source and adaptations of the stone; works by the same production company within 2 years (30+ sitelinks);
    works sharing a genre within 1 year (60+ sitelinks, at most 40)."""
    q = f"""SELECT DISTINCT ?rel ?x WHERE {{
  {{ wd:{stone} wdt:P144 ?x . BIND("source" AS ?rel) }} UNION {{ ?x wdt:P144 wd:{stone} . BIND("adaptation" AS ?rel) }}
  UNION {{ wd:{stone} wdt:P4969 ?x . BIND("adaptation" AS ?rel) }}
  UNION {{ wd:{stone} wdt:P272 ?x . BIND("company" AS ?rel) }} UNION {{ wd:{stone} wdt:P136 ?x . BIND("genre" AS ?rel) }}
}}"""
    rows = nv.sparql(q) or []
    fam = {"source": [], "adaptation": [], "company": [], "genre": []}
    for b in rows:
        fam[nv.val(b, "rel")].append(nv.qid(nv.val(b, "x")))
    sib_works = {"same work": [stone] + fam["source"] + fam["adaptation"], "same company": [], "same genre": []}
    for co in fam["company"][:3]:
        q = f"""SELECT DISTINCT ?w ?sl ?d WHERE {{ ?w wdt:P272 wd:{co} ; wikibase:sitelinks ?sl . FILTER(?sl >= {SIB_CO_SL})
  {{ ?w wdt:P577 ?d }} UNION {{ ?w wdt:P580 ?d }} FILTER(YEAR(?d) >= {R - 2} && YEAR(?d) <= {R + 2}) }} LIMIT 300"""
        sib_works["same company"] += [nv.qid(nv.val(b, "w")) for b in nv.sparql(q) or []]
    gw = {}
    for g in fam["genre"][:4]:
        q = f"""SELECT DISTINCT ?w ?sl WHERE {{ ?w wdt:P136 wd:{g} ; wikibase:sitelinks ?sl . FILTER(?sl >= {SIB_GENRE_SL})
  {{ ?w wdt:P577 ?d }} UNION {{ ?w wdt:P580 ?d }} FILTER(YEAR(?d) >= {R - 1} && YEAR(?d) <= {R + 1}) }} LIMIT 500"""
        for b in nv.sparql(q) or []:
            gw[nv.qid(nv.val(b, "w"))] = max(gw.get(nv.qid(nv.val(b, "w")), 0), int(nv.val(b, "sl")))
    sib_works["same genre"] = [w for w, _ in sorted(gw.items(), key=lambda x: -x[1])][:SIB_GENRE_MAX]
    for k in ("same company", "same genre"):
        sib_works[k] = [w for w in dict.fromkeys(sib_works[k]) if w not in sib_works["same work"]]
    return sib_works


def candidate_names(it, st):
    """The names a character can carry under H1: its given-name labels and the first token of its English label."""
    lab = it.get("label") or ""
    first = re.split(r"[\s,]+", lab.strip())[0] if lab else ""
    names = set(it.get("given") or []) | ({first} if first else set())
    out = []
    for nm in names:
        for sx in ("F", "M"):
            if it.get("sex") not in (None, sx):
                continue
            if (nm, sx) in st.idx:
                out.append((nm, sx))
    return out


def main():
    res = json.load(open(os.path.join(nv.RESULTS, "names_v1.json")))
    hyp = json.load(open(os.path.join(nv.RESULTS, "names_v1_hypotheses.json")))
    keys, N = nv.load()
    st = nv.Stats(keys, N)
    confirmed = [p for p in res["pairs"] if p["grade"] == "measured"]
    dn_rate = res["decoys"]["decoy_names"]["rate"] or 0.0
    out = {"version": "names_v1_followup", "hypotheses_file": "ripples/docs/results/names_v1_hypotheses.json",
           "siblings": [], "hypotheses": [], "lag": {}}

    # ---- siblings, one family per confirmed stone
    done = set()
    for p in confirmed:
        s = p["stone"]
        if s["wikidata"] in done or s["shelf"] in ("person (born)", "person (debut)", "storm", "named thing"):
            continue
        done.add(s["wikidata"])
        R = int(s["date"][:4])
        M = int(s["date"][5:7]) if len(s["date"]) >= 7 else None
        sign = 1 if p["direction"] == "rise" else -1
        fam = family_of(s["wikidata"], R)
        allw = sorted({w for v in fam.values() for w in v})
        cw = chars_of_works(allw)
        chars = sorted({c for v in cw.values() for c in v})
        D = nv.details(set(chars) | set(allw))
        T = nv.dates_of(set(allw))
        rows = []
        for rel, works in fam.items():
            for w in works:
                wi = D.get(w, {})
                if rel != "same work" and (not wi.get("enwiki")):
                    continue
                dt = nv.first_date(T.get(w)) if rel != "same work" else {"y": R, "m": M, "d": None}
                if not dt:
                    continue
                for c in cw.get(w, []):
                    ci = D.get(c, {})
                    if ci.get("failed") or ci.get("human") or not ci.get("enwiki"):
                        continue
                    for nm, sx in candidate_names(ci, st):
                        if nm == p["name"] and sx == p["sex"] and rel == "same work":
                            continue
                        t = nv.test_pair(st, st.idx[(nm, sx)], dt["y"], dt["m"], sign)
                        rows.append({"family": rel, "work": wi.get("label") or w, "work_wikidata": w,
                                     "work_date": nv.fmt_date(dt), "character": ci.get("label"), "character_wikidata": c,
                                     "name": nm, "sex": sx, "grade": t["grade"], "p_year": t.get("p_year"),
                                     "p_own": t.get("p_own"), "peak_year": t.get("t_hat"),
                                     "counts": st.counts(st.idx[(nm, sx)], dt["y"] - 2, min(nv.Y1, dt["y"] + 3))})
        uniq = {}
        for r in rows:
            uniq.setdefault((r["family"], r["name"], r["sex"], r["work_wikidata"]), r)
        rows = list(uniq.values())
        n = len(rows)
        meas = sum(1 for r in rows if r["grade"] == "measured")
        verdict = ("generalizes" if meas >= 2 and n and meas / n >= 5 * dn_rate else "partial" if meas == 1
                   else "isolated" if meas == 0 else "partial")
        out["siblings"].append({"stone": s["title"], "stone_wikidata": s["wikidata"], "confirmed_name": p["name"],
                                "tested": n, "measured": meas, "timed": sum(1 for r in rows if r["grade"] == "timed"),
                                "busted": sum(1 for r in rows if r["grade"] == "busted"),
                                "decoy_name_rate": dn_rate, "verdict": verdict, "pairs": rows})

    # ---- generated hypotheses, as written in the addendum
    for h in hyp["pairs"]:
        i = st.idx[(h["name"], h["sex"])]
        sign = 1 if h["direction"] == "rise" else -1
        R, M = int(h["release"][:4]), (int(h["release"][5:7]) if len(h["release"]) >= 7 else None)
        base = nv.test_pair(st, i, R, M, sign)
        th = base["t_hat"]
        rec = {"name": h["name"], "sex": h["sex"], "direction": h["direction"], "stone": h["stone"], "results": []}
        for x in h["hypotheses"]:
            kind = x["kind"]
            r = {"kind": kind, "statement": x["statement"]}
            if kind == "persist":
                per = nv.persistence(st, i, th, R, sign)
                r["value"] = per
                r["held"] = per["persisted"] if per["years_observed"] >= 2 else None
            elif kind == "reversal":
                ys = [y for y in range(th + 1, th + 5) if y <= nv.Y1]
                best = min(ys, key=lambda y: st.p_year[-sign][i, y - nv.Y0]) if ys else None
                pv = float(st.p_year[-sign][i, best - nv.Y0]) if best else None
                happened = pv is not None and pv <= 0.05
                r["value"] = {"best_year": best, "p_year": round(pv, 4) if pv is not None else None,
                              "counts": st.counts(i, th, min(nv.Y1, th + 4))}
                r["held"] = happened if x.get("predicted", True) else (not happened)
            elif kind == "companion":
                vals = []
                for nm in x["names"]:
                    j = st.idx.get((nm, h["sex"]))
                    if j is None:
                        vals.append({"name": nm, "in_data": False})
                        continue
                    W = base["window"]
                    py = min(float(st.p_year[sign][j, y - nv.Y0]) for y in W)
                    vals.append({"name": nm, "in_data": True, "min_p_year_in_window": round(py, 4),
                                 "rose": py <= 0.05, "counts": st.counts(j, R - 2, min(nv.Y1, R + 3))})
                # base rate: random same-sex names of similar size, same window
                b0 = st.N[i, R - 1 - nv.Y0]
                pool = [j for j in range(len(keys)) if st.sex[j] == h["sex"] and j != i
                        and abs(np.log((st.N[j, R - 1 - nv.Y0] + 5) / (b0 + 5))) <= np.log(2)]
                rr = random.Random(f"{nv.SEED}-comp-{h['name']}")
                smp = rr.sample(pool, min(200, len(pool)))
                rate = float(np.mean([min(st.p_year[sign][j, y - nv.Y0] for y in base["window"]) <= 0.05
                                      for j in smp])) if smp else None
                r["value"] = {"variants": vals, "base_rate_random_name": round(rate, 3) if rate is not None else None}
                tested = [v for v in vals if v.get("in_data")]
                r["held"] = any(v["rose"] for v in tested) if tested else None
            elif kind == "lag":
                pred = R if (M and M <= 3) else R + 1
                r["value"] = {"predicted_peak": pred, "actual_peak": th}
                r["held"] = th == pred
            elif kind == "sex":
                other = "M" if h["sex"] == "F" else "F"
                j = st.idx.get((h["name"], other))
                if j is None:
                    r["value"], r["held"] = {"in_data": False}, None
                else:
                    py = min(float(st.p_year[sign][j, y - nv.Y0]) for y in base["window"])
                    r["value"] = {"in_data": True, "min_p_year_in_window": round(py, 4),
                                  "counts": st.counts(j, R - 2, min(nv.Y1, R + 3))}
                    r["held"] = py > 0.05
            elif kind == "sequel":
                vals = []
                for sq in x["sequels"]:
                    R2 = int(sq["date"][:4])
                    M2 = int(sq["date"][5:7]) if len(sq["date"]) >= 7 else None
                    W2 = [y for y in range(nv.r_eff(R2, M2), nv.r_eff(R2, M2) + 2) if y <= nv.Y1]  # two years from R_eff
                    if not W2:
                        vals.append({**sq, "observable": False})
                        continue
                    py = min(float(st.p_year[sign][i, y - nv.Y0]) for y in W2)
                    vals.append({**sq, "observable": True, "window": W2, "min_p_year": round(py, 4),
                                 "counts": st.counts(i, R2 - 1, min(nv.Y1, R2 + 2))})
                obs = [v for v in vals if v["observable"]]
                r["value"] = vals
                r["held"] = any(v["min_p_year"] <= 0.10 for v in obs) if obs else None
            rec["results"].append(r)
        out["hypotheses"].append(rec)

    # ---- lag prior
    def lags(ps):
        rows = []
        for p in ps:
            R = int(p["stone"]["date"][:4])
            M = int(p["stone"]["date"][5:7]) if len(p["stone"]["date"]) >= 7 else 7
            rows.append({"name": p["name"], "stone": p["stone"]["title"], "onset_minus_release": p["onset_year"] - R,
                         "peak_minus_release": p["peak_year"] - R,
                         "months_release_to_mid_peak_year": (p["peak_year"] - R) * 12 + (7 - M)})
        def dist(k):
            v = [r[k] for r in rows]
            if not v:
                return None
            vals, cnt = np.unique(v, return_counts=True)
            return {"values": {str(int(a)): int(b) for a, b in zip(vals, cnt)}, "median": float(np.median(v)),
                    "mean": round(float(np.mean(v)), 2)}
        return {"n": len(rows), "rows": rows, "onset_minus_release": dist("onset_minus_release"),
                "peak_minus_release": dist("peak_minus_release"),
                "months_release_to_mid_peak_year": dist("months_release_to_mid_peak_year")}
    seen = set()
    uniq_c, uniq_t = [], []
    for p in res["pairs"]:
        k = (p["name"], p["sex"], p["direction"], p["peak_year"])
        if k in seen or p["grade"] not in ("measured", "timed"):
            continue
        seen.add(k)
        (uniq_c if p["grade"] == "measured" else uniq_t).append(p)
    out["lag"] = {"confirmed": lags(uniq_c), "timed": lags(uniq_t)}
    with open(os.path.join(nv.RESULTS, "names_v1_followup.json"), "w") as f:
        json.dump(out, f, indent=1)
    print(json.dumps({"siblings": [{k: v for k, v in s.items() if k != "pairs"} for s in out["siblings"]],
                      "lag": {k: {kk: vv for kk, vv in v.items() if kk != "rows"} for k, v in out["lag"].items()}},
                     indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
