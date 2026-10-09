"""Relevant Surprise Score (RSS), v1: score and rank existing Ripple candidates. Ranking only; candidate generation is untouched.

    python3 ripples/engine/rank/rss.py --data DIR                             # config_v0.json, the registered starting point
    python3 ripples/engine/rank/rss.py --data DIR --config ripples/engine/rank/config_v1_exploratory.json

DIR holds one experiment's inputs: candidates.jsonl, controls.jsonl, features.jsonl, features_controls.jsonl
(default: rank/ in the engine work directory). Outputs go to DIR/out unless --out says otherwise.

Writes (deterministic for fixed inputs and config; no timestamps in the outputs):
    out/rss_scores.jsonl     one row per evaluation candidate: components, S, R, RSS, gates, duplicate status, ranks, explanation
    out/rss_controls.jsonl   the planted controls scored the same way (validity checks only; never ranked with candidates)
    out/rss_summary.json     input and config hashes, component distributions, Spearman correlations between components

S  = weighted mean of the available normalized surprise components (S_A, S_B as a pool percentile, S_D).
R  = weighted geometric mean of the available relevance dimensions (C, G; U omitted when unavailable).
RSS = S^alpha x R^beta. Evidence eligibility, the relevance gate and duplicates order the list; they never change RSS.
"""
import argparse, hashlib, json, math, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import workdir  # noqa: E402
STOP = set("a an the of to in on for and or by with from its it is as at after be into than that this their was were".split())


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def load_jsonl(path):
    return [json.loads(l) for l in open(path) if l.strip()]


def midrank_pct(pool_values, x):
    """Share of the pool below x plus half the ties, in [0, 1]."""
    below = sum(1 for v in pool_values if v < x)
    ties = sum(1 for v in pool_values if v == x)
    return (below + 0.5 * ties) / len(pool_values)


def rank_values(xs):
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    r = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        for k in range(i, j + 1):
            r[order[k]] = (i + j) / 2 + 1
        i = j + 1
    return r


def spearman(a, b):
    pairs = [(x, y) for x, y in zip(a, b) if x is not None and y is not None]
    if len(pairs) < 3:
        return None
    ra, rb = rank_values([p[0] for p in pairs]), rank_values([p[1] for p in pairs])
    ma, mb = sum(ra) / len(ra), sum(rb) / len(rb)
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    den = math.sqrt(sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb))
    return round(num / den, 4) if den else None


def tokens(s):
    return {t for t in re.findall(r"[a-z0-9]+", s.lower()) if t not in STOP and len(t) > 2}


def score_rows(feats, cands, cfg, pool_bits):
    sw, rw = cfg["s_components"], cfg["r_weights"]
    out = []
    for f in feats:
        c = cands[f["id"]]
        s_parts = {"S_A": f["S_A"]["value"], "S_B": None if f["S_B"]["missing"] else round(midrank_pct(pool_bits, f["S_B"]["bits"]), 4),
                   "S_D": f["S_D"]["value"]}
        have = {k: v for k, v in s_parts.items() if v is not None and sw.get(k, 0) > 0}
        S = round(sum(sw[k] * v for k, v in have.items()) / sum(sw[k] for k in have), 4) if have else None
        r_parts = {"C": f["C"]["value"], "G": f["G"]["value"], "U": f["U"]["value"]}
        r_have = {k: v for k, v in r_parts.items() if v is not None and rw.get(k, 0) > 0}
        R = None
        if all(r_parts[k] is not None for k in cfg["r_required"]) and r_have:
            wsum = sum(rw[k] for k in r_have)
            R = round(math.prod(max(v, 0.0) ** (rw[k] / wsum) for k, v in r_have.items()), 4)
        RSS = round((S ** cfg["alpha"]) * (R ** cfg["beta"]), 4) if S is not None and R is not None else None
        gate = cfg["relevance_gate"]
        rel_ok = (r_parts["C"] is not None and r_parts["C"] >= gate["C_min"]) and (r_parts["G"] is None or r_parts["G"] >= gate["G_min"])
        out.append({"id": f["id"], "catalyst_id": f["catalyst_id"], "group_id": f["group_id"], "source": c.get("source"), "kind": f["kind"],
                    "components": {**s_parts, "S_B_bits": f["S_B"]["bits"], "C": r_parts["C"], "G": r_parts["G"], "U": None},
                    "weights_used": {"S": {k: round(sw[k] / sum(sw[k] for k in have), 4) for k in have} if have else {},
                                     "R": {k: round(rw[k] / sum(rw[k] for k in r_have), 4) for k in r_have} if r_have else {}},
                    "missing": [k for k, v in {**s_parts, "C": r_parts["C"], "G": r_parts["G"], "U": None}.items() if v is None],
                    "S": S, "R": R, "RSS": RSS,
                    "eligible": c["eligibility"]["eligible"], "eligibility_rule": c["eligibility"]["rule"], "eligibility_reason": c["eligibility"]["reason"],
                    "evidence_grade": c.get("evidence_grade"), "relevance_gate": "pass" if rel_ok else "fail",
                    "_f": f, "_c": c})
    return out


def explain(r):
    f, c = r["_f"], r["_c"]
    sa = f["S_A"]
    if sa["missing"]:
        a = "S_A missing"
    elif sa["rank"] is None:
        a = "not in the 25 predictions"
    else:
        a = f"predicted at rank {sa['rank']} ({sa['level']})"
    b = f"{f['S_B']['catalyst_type']} to {f['S_B']['outcome_type']} {f['S_B']['bits']:.1f} bits"
    d = "S_D missing" if f["S_D"]["missing"] else {"lead": "stated in the stone's article lead", "body": "stated in the stone's article body", "absent": "not in the stone's article"}[f["S_D"]["where"]]
    g = f["G"]["codes"]
    fmt = lambda v: "n/a" if v is None else f"{v:.2f}"
    gate = "" if r["eligible"] else f"; ineligible ({c['eligibility']['reason']})"
    gate += "" if r["relevance_gate"] == "pass" else "; below the relevance floor"
    gate += f"; duplicate of {r['duplicate_of']}" if r.get("duplicate_of") else ""
    return (f"RSS {fmt(r['RSS'])} = S {fmt(r['S'])} ({a}; {b}; {d}) x R {fmt(r['R'])} (C {fmt(r['components']['C'])} {f['C']['level']}; "
            f"G {fmt(r['components']['G'])}: scope {g['scope']}, reach {g['reach']}, permanence {g['permanence']}){gate}.")


def order_key(r):
    return (0 if r["eligible"] else 1, 0 if r["relevance_gate"] == "pass" else 1, 0 if r["RSS"] is not None else 1,
            1 if r.get("duplicate_of") else 0, -(r["RSS"] or 0), -(r["R"] or 0), r["id"])


def dedupe(rows, cfg, outcome_of):
    """Mark duplicates within a catalyst group; the best-ranked member of each cluster stands."""
    manual = {i: k for k, ids in cfg["dedupe"]["manual_clusters"].items() for i in ids}
    pre = sorted(rows, key=lambda r: order_key({**r, "duplicate_of": None}))
    kept = []
    for r in pre:
        r["duplicate_of"] = None
        for k in kept:
            if k["group_id"] != r["group_id"]:
                continue
            same_manual = manual.get(r["id"]) is not None and manual.get(r["id"]) == manual.get(k["id"])
            ta, tb = tokens(outcome_of[r["id"]]), tokens(outcome_of[k["id"]])
            jac = len(ta & tb) / len(ta | tb) if ta | tb else 0
            if same_manual or jac >= cfg["dedupe"]["jaccard_min"]:
                r["duplicate_of"] = k["id"]
                r["duplicate_reason"] = f"manual cluster {manual[r['id']]}" if same_manual else f"outcome Jaccard {jac:.2f}"
                break
        if not r["duplicate_of"]:
            kept.append(r)
    return rows


def main():
    ap = argparse.ArgumentParser(description="Score and rank candidates by RSS (script step).")
    ap.add_argument("--data", help="the experiment's input directory (default: rank/ in the work directory)")
    ap.add_argument("--config", default=f"{HERE}/config_v0.json")
    ap.add_argument("--out", help="output directory (default: DATA/out)")
    workdir.add_arg(ap)
    a = ap.parse_args()
    a.data = os.path.abspath(a.data or os.path.join(workdir.resolve(a.work, create=False), "rank"))
    a.out = a.out or os.path.join(a.data, "out")
    cfg = json.load(open(a.config))
    os.makedirs(a.out, exist_ok=True)
    cands = {c["id"]: c for c in load_jsonl(f"{a.data}/candidates.jsonl")}
    ctrls = {c["id"]: c for c in load_jsonl(f"{a.data}/controls.jsonl")}
    feats = load_jsonl(f"{a.data}/features.jsonl")
    cfeats = load_jsonl(f"{a.data}/features_controls.jsonl")
    pool_bits = [f["S_B"]["bits"] for f in feats]

    rows = score_rows(feats, cands, cfg, pool_bits)
    dedupe(rows, cfg, {i: c["outcome"] for i, c in cands.items()})
    rows.sort(key=order_key)
    by_cat = {}
    for i, r in enumerate(rows, 1):
        r["rank_overall"] = i
        by_cat.setdefault(r["catalyst_id"], []).append(r)
        r["rank_within_catalyst"] = len(by_cat[r["catalyst_id"]])
    for r in rows:
        r["explanation"] = explain(r)
    crow = score_rows(cfeats, ctrls, cfg, pool_bits)
    for r in crow:
        r["duplicate_of"] = None
        r["control"] = r["_c"].get("control")
        r["RSS_pool_percentile"] = None if r["RSS"] is None else round(midrank_pct([x["RSS"] for x in rows if x["RSS"] is not None], r["RSS"]), 4)
        r["explanation"] = explain(r)

    keep = lambda r: {k: v for k, v in r.items() if not k.startswith("_")}
    with open(f"{a.out}/rss_scores.jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(keep(r), ensure_ascii=False, sort_keys=True) + "\n")
    with open(f"{a.out}/rss_controls.jsonl", "w") as f:
        for r in sorted(crow, key=lambda r: r["id"]):
            f.write(json.dumps(keep(r), ensure_ascii=False, sort_keys=True) + "\n")

    comps = ["S_A", "S_B", "S_D", "C", "G", "S", "R", "RSS"]
    val = lambda r, k: r[k] if k in ("S", "R", "RSS") else r["components"][k]
    dist = {}
    for k in comps:
        xs = sorted(v for v in (val(r, k) for r in rows) if v is not None)
        q = lambda p: xs[min(len(xs) - 1, int(p * (len(xs) - 1) + 0.5))] if xs else None
        dist[k] = {"n": len(xs), "missing": len(rows) - len(xs), "min": xs[0] if xs else None, "p25": q(.25), "median": q(.5),
                   "p75": q(.75), "max": xs[-1] if xs else None, "mean": round(sum(xs) / len(xs), 4) if xs else None}
    corr = {f"{x}~{y}": spearman([val(r, x) for r in rows], [val(r, y) for r in rows]) for i, x in enumerate(comps[:5]) for y in comps[i + 1:5]}
    summary = {"config": os.path.basename(a.config), "config_sha256": sha(a.config),
               "inputs_sha256": {p: sha(f"{a.data}/{p}") for p in ["candidates.jsonl", "controls.jsonl", "features.jsonl", "features_controls.jsonl"]},
               "n": len(rows), "eligible": sum(r["eligible"] for r in rows), "relevance_gate_fail": sum(r["relevance_gate"] == "fail" for r in rows),
               "duplicates": sum(1 for r in rows if r["duplicate_of"]), "unscored": sum(r["RSS"] is None for r in rows),
               "distributions": dist, "spearman_between_components": corr,
               "S_A_controls": {t: {"n": sum(1 for r in crow if r["control"] == t),
                                    "predicted": sum(1 for r in crow if r["control"] == t and r["_f"]["S_A"].get("rank") is not None)}
                                for t in ("planted_obvious", "planted_fabricated")}}
    # spec 11 step 6: the top of the list under RSS against the existing ranking (no human labels involved)
    elig = [r for r in rows if r["eligible"] and not r["duplicate_of"]]
    by_base = sorted(elig, key=lambda r: (-r["_c"]["baseline"]["signal"], r["id"]))
    by_rss = [r for r in rows if r["eligible"] and not r["duplicate_of"]]
    cmp_lines = ["# Top 20 eligible candidates: existing ranking against RSS", "",
                 "Existing ranking: evidence_first_v0 (Ripple ladder weight, then the source's own score as a tie-break). Duplicates removed.",
                 "No human labels are used here; this shows how the order changes, not whether it improves.", ""]
    for k in (10, 20):
        ov = len({r["id"] for r in by_base[:k]} & {r["id"] for r in by_rss[:k]})
        mix = lambda xs: ", ".join(f"{s} {n}" for s, n in sorted(__import__("collections").Counter(r["source"] for r in xs).items()))
        types = lambda xs: len({r["_f"]["S_B"]["outcome_type"] for r in xs})
        cmp_lines += [f"- Top {k}: overlap {ov} of {k}. Sources, existing: {mix(by_base[:k])}; RSS: {mix(by_rss[:k])}. "
                      f"Distinct outcome types, existing {types(by_base[:k])}, RSS {types(by_rss[:k])}."]
    cmp_lines += ["", "| # | Existing ranking | RSS |", "|---|---|---|"]
    lab = lambda r: f"{r['id']}: {r['_c']['claim'][:70]}"
    for i in range(20):
        cmp_lines.append(f"| {i + 1} | {lab(by_base[i])} | {lab(by_rss[i])} (RSS {by_rss[i]['RSS']:.2f}) |")
    open(f"{a.out}/top_compare.md", "w").write("\n".join(cmp_lines) + "\n")
    summary["top_overlap_existing_vs_rss"] = {k: len({r["id"] for r in by_base[:k]} & {r["id"] for r in by_rss[:k]}) for k in (10, 20)}
    pool = {k: [x[k] for x in rows if x[k] is not None] for k in ("S", "RSS")}
    summary["controls_mean_pool_percentile"] = {
        t: {k: round(sum(midrank_pct(pool[k], r[k]) for r in crow if r["control"] == t and r[k] is not None) /
                     max(1, sum(1 for r in crow if r["control"] == t and r[k] is not None)), 4) for k in ("S", "RSS")}
        for t in ("planted_obvious", "planted_fabricated")}
    json.dump(summary, open(f"{a.out}/rss_summary.json", "w"), indent=1, sort_keys=True)
    print(json.dumps({k: summary[k] for k in ("n", "eligible", "relevance_gate_fail", "duplicates", "unscored", "S_A_controls")}))
    for r in rows[:10]:
        print(r["rank_overall"], r["id"], r["explanation"])


if __name__ == "__main__":
    main()
