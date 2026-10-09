"""Evaluate RSS against human ratings on held-out catalysts (spec section 8).

    python3 ripples/engine/rank/eval.py --data DIR      # reads DIR/ratings/r*_pass2.json, writes DIR/eval_out/report.json and .md
    python3 ripples/engine/rank/eval.py --data DIR --ratings DIR2 --out DIR3 --folds 5
    python3 ripples/engine/rank/eval.py --data DIR --exploratory   # adds "evidence tier, then RSS", the v1 candidate

DIR is the experiment's input directory, as for rss.py; it also holds packets/key_pass2.json (never given to raters)
and, after rss.py has run, out/rss_controls.jsonl.

Rater files: {"rater": "r1", "ratings": [{"item": "Q001", "surprise": 1-5, "on_my_pass1_list": "yes|partly|no",
"catalyst_relevance": 1-5, "consequence_significance": 1-5, "discovery_value": 1-5, "evidence_quality": 1-5}, ...]}
(a bare list of those objects is accepted too). Items map to candidates through packets/key_pass2.json.

Accepted discovery: eligible (Ripple's existing evidence rules) and mean discovery value >= 3.5 and mean surprise >= 3.5.
Splits: grouped K-fold on catalyst group ids, so no catalyst group is in both a training and a test fold.
Rankers: existing Ripple ranking (evidence_first_v0), surprise only (S), relevance only (R), RSS, RSS without each
component, and RSS with alpha, beta and S weights tuned on the training folds only. Every ranker puts eligible
candidates first and moves duplicates after the rest, so the comparison is about ordering.
"""
import argparse, copy, glob, json, math, os, random, statistics as st, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import workdir  # noqa: E402
DATA = None
EXPLORATORY = False
import rss as RS  # noqa: E402

SCALES = ["surprise", "catalyst_relevance", "consequence_significance", "discovery_value", "evidence_quality"]
KS = (10, 20)


def load_ratings(rdir, key):
    raters = {}
    for f in sorted(glob.glob(f"{rdir}/r*_pass2.json")):
        js = json.load(open(f))
        rows = js["ratings"] if isinstance(js, dict) else js
        name = (js.get("rater") if isinstance(js, dict) else None) or os.path.basename(f).split("_")[0]
        clean = {}
        for x in rows:
            if x.get("item") not in key:
                continue
            vals = {s: x.get(s) for s in SCALES}
            if any(v is not None and not (1 <= v <= 5) for v in vals.values()):
                raise SystemExit(f"{f}: rating outside 1 to 5 on {x['item']}")
            clean[x["item"]] = {**vals, "on_my_pass1_list": x.get("on_my_pass1_list")}
        raters[name] = clean
    return raters


def item_stats(raters, key):
    out = {}
    for q, k in key.items():
        rec = {"candidate_id": k["candidate_id"], "control": k["control"], "n_raters": 0}
        for s in SCALES:
            xs = [r[q][s] for r in raters.values() if q in r and r[q].get(s) is not None]
            rec[s] = round(st.mean(xs), 3) if xs else None
            rec[f"{s}_sd"] = round(st.pstdev(xs), 3) if len(xs) > 1 else None
            rec["n_raters"] = max(rec["n_raters"], len(xs))
        on = [r[q]["on_my_pass1_list"] for r in raters.values() if q in r and r[q].get("on_my_pass1_list")]
        rec["on_list_share"] = round(sum(1 for v in on if v in ("yes", "partly")) / len(on), 3) if on else None
        out[k["candidate_id"]] = rec
    return out


def rater_agreement(raters, key):
    names = sorted(raters)
    res = {}
    for s in SCALES:
        vals = []
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                a, b = raters[names[i]], raters[names[j]]
                common = [q for q in key if q in a and q in b and a[q].get(s) is not None and b[q].get(s) is not None]
                if len(common) >= 3:
                    v = RS.spearman([a[q][s] for q in common], [b[q][s] for q in common])
                    if v is not None:
                        vals.append(v)
        res[s] = round(st.mean(vals), 3) if vals else None
    return res


def grouped_folds(rows, k):
    sizes = {}
    for r in rows:
        sizes[r["group_id"]] = sizes.get(r["group_id"], 0) + 1
    folds = [[] for _ in range(k)]
    load = [0] * k
    for g in sorted(sizes, key=lambda g: (-sizes[g], g)):
        i = min(range(k), key=lambda i: (load[i], i))
        folds[i].append(g)
        load[i] += sizes[g]
    return [set(f) for f in folds]


def ranked(rows, score_fn, gate=None):
    """Eligible first, then (optionally) the relevance gate, then score; duplicates move after their cluster's best."""
    def key(r):
        s = score_fn(r)
        return (0 if r["eligible"] else 1, 0 if (gate is None or gate(r)) else 1, 0 if s is not None else 1, -(s or 0), r["id"])
    pre = sorted(rows, key=key)
    seen, first, dup = set(), [], []
    for r in pre:
        c = r.get("_cluster")
        if c and c in seen:
            dup.append(r)
        else:
            if c:
                seen.add(c)
            first.append(r)
    return first + dup


def dcg(gains, k):
    return sum(g / math.log2(i + 2) for i, g in enumerate(gains[:k]))


def metrics(order, H, k_list=KS):
    rated = [r for r in order if H.get(r["id"], {}).get("discovery_value") is not None]
    acc = lambda r: r["eligible"] and H[r["id"]]["discovery_value"] >= 3.5 and (H[r["id"]]["surprise"] or 0) >= 3.5
    m = {"n": len(rated)}
    gains = [H[r["id"]]["discovery_value"] - 1 for r in rated]
    ideal = sorted(gains, reverse=True)
    for k in k_list:
        top = rated[:k]
        m[f"P@{k}"] = round(sum(acc(r) for r in top) / len(top), 4) if top else None
        m[f"NDCG@{k}"] = round(dcg(gains, k) / dcg(ideal, k), 4) if rated and dcg(ideal, k) > 0 else None
        m[f"short@{k}"] = len(top) < k
    m["accepted_total"] = sum(acc(r) for r in rated)
    return m


def build_rows(cfg, H=None):
    cands = {c["id"]: c for c in RS.load_jsonl(f"{DATA}/candidates.jsonl")}
    feats = RS.load_jsonl(f"{DATA}/features.jsonl")
    pool_bits = [f["S_B"]["bits"] for f in feats]
    rows = RS.score_rows(feats, cands, cfg, pool_bits)
    manual = {i: k for k, ids in cfg["dedupe"]["manual_clusters"].items() for i in ids}
    RS.dedupe(rows, cfg, {i: c["outcome"] for i, c in cands.items()})
    for r in rows:  # one cluster label per duplicate set, shared by every ranker
        r["_cluster"] = manual.get(r["id"]) or (f"dup:{r['duplicate_of']}" if r["duplicate_of"] else None)
    lead = {r["duplicate_of"]: f"dup:{r['duplicate_of']}" for r in rows if r["duplicate_of"] and not manual.get(r["id"])}
    for r in rows:
        if r["id"] in lead and not r["_cluster"]:
            r["_cluster"] = lead[r["id"]]
        r["baseline"] = r["_c"]["baseline"]["signal"]
        r["outcome_type"] = r["_f"]["S_B"]["outcome_type"]
    return rows


def ablation_cfg(cfg, drop):
    c = copy.deepcopy(cfg)
    if drop in c["s_components"]:
        c["s_components"][drop] = 0.0
    if drop in c["r_weights"]:
        c["r_weights"][drop] = 0.0
        c["r_required"] = [x for x in c["r_required"] if x != drop]
        if drop == "C":
            c["relevance_gate"]["C_min"] = -1
        if drop == "G":
            c["relevance_gate"]["G_min"] = -1
    return c


def rankers(cfg):
    gate = lambda r: r["relevance_gate"] == "pass"
    out = {"existing (evidence_first_v0)": (cfg, lambda r: r["baseline"], None),
           "surprise only (S)": (cfg, lambda r: r["S"], None),
           "relevance only (R)": (cfg, lambda r: r["R"], None),
           "RSS": (cfg, lambda r: r["RSS"], gate)}
    if EXPLORATORY:
        # chosen after seeing the v0 results (docs/rss_v1.md): evidence tier first, then RSS inside each tier
        out["evidence tier, then RSS (exploratory)"] = (cfg, lambda r: (r["_c"]["baseline"].get("ladder_weight") or 0) * 10 + (r["RSS"] or 0), None)
    for d in ("S_A", "S_B", "S_D", "C", "G"):
        out[f"RSS without {d}"] = (ablation_cfg(cfg, d), lambda r: r["RSS"], gate)
    return out


TUNE_GRID = [(a, b, w) for a in (0.5, 1.0, 2.0) for b in (0.5, 1.0, 2.0)
             for w in ({"S_A": 1, "S_B": 1, "S_D": 1}, {"S_A": 2, "S_B": 1, "S_D": 1}, {"S_A": 1, "S_B": 2, "S_D": 1})]


def main():
    global DATA, EXPLORATORY
    ap = argparse.ArgumentParser(description="Evaluate RSS against ratings on held-out catalysts (script step).")
    ap.add_argument("--data", help="the experiment's input directory (default: rank/ in the work directory)")
    ap.add_argument("--ratings", help="rater files (default: DATA/ratings)")
    ap.add_argument("--out", help="report directory (default: DATA/eval_out)")
    ap.add_argument("--config", default=f"{HERE}/config_v0.json")
    ap.add_argument("--exploratory", action="store_true", help="add the exploratory ranker: evidence tier, then RSS")
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--boot", type=int, default=1000)
    workdir.add_arg(ap)
    a = ap.parse_args()
    EXPLORATORY = a.exploratory
    DATA = os.path.abspath(a.data or os.path.join(workdir.resolve(a.work, create=False), "rank"))
    a.ratings = a.ratings or os.path.join(DATA, "ratings")
    a.out = a.out or os.path.join(DATA, "eval_out")
    cfg = json.load(open(a.config))
    key = json.load(open(f"{DATA}/packets/key_pass2.json"))
    raters = load_ratings(a.ratings, key)
    if not raters:
        raise SystemExit(f"no rater files matching {a.ratings}/r*_pass2.json")
    H = item_stats(raters, key)
    os.makedirs(a.out, exist_ok=True)

    base_rows = build_rows(cfg)
    groups = grouped_folds(base_rows, a.folds)
    R = rankers(cfg)
    rows_by_cfg = {}

    def rows_for(c):
        k = json.dumps(c, sort_keys=True)
        if k not in rows_by_cfg:
            rows_by_cfg[k] = build_rows(c)
        return rows_by_cfg[k]

    def tuned_cfg(train_groups):
        best, best_v = None, -1
        for al, be, w in TUNE_GRID:
            c = copy.deepcopy(cfg); c["alpha"], c["beta"], c["s_components"] = al, be, w
            rows = [r for r in rows_for(c) if r["group_id"] in train_groups]
            v = metrics(ranked(rows, lambda r: r["RSS"], lambda r: r["relevance_gate"] == "pass"), H)["NDCG@20"] or 0
            if v > best_v + 1e-12:
                best, best_v = (c, (al, be, w)), v
        return best

    per_fold, pooled_scores, tuned_choices = {}, {}, []
    for fi, test in enumerate(groups):
        train = set().union(*[g for j, g in enumerate(groups) if j != fi])
        fold_rankers = dict(R)
        tc, choice = tuned_cfg(train)
        tuned_choices.append({"fold": fi + 1, "alpha": choice[0], "beta": choice[1], "s_weights": choice[2]})
        fold_rankers["RSS tuned on training catalysts"] = (tc, lambda r: r["RSS"], lambda r: r["relevance_gate"] == "pass")
        for name, (c, fn, gate) in fold_rankers.items():
            rows = [r for r in rows_for(c) if r["group_id"] in test]
            per_fold.setdefault(name, []).append(metrics(ranked(rows, fn, gate), H))
            for r in rows:
                pooled_scores.setdefault(name, {})[r["id"]] = (r, fn(r), gate(r) if gate else True)

    def pooled_order(name, ids=None):
        trip = pooled_scores[name]
        rows = [t[0] for i, t in trip.items() if ids is None or i in ids]
        sc = {i: t[1] for i, t in trip.items()}
        gt = {i: t[2] for i, t in trip.items()}
        return ranked(rows, lambda r: sc[r["id"]], lambda r: gt[r["id"]])

    acc = lambda r: r["eligible"] and H[r["id"]]["discovery_value"] is not None and H[r["id"]]["discovery_value"] >= 3.5 and (H[r["id"]]["surprise"] or 0) >= 3.5
    table = {}
    for name in per_fold:
        fm = per_fold[name]
        row = {}
        for mname in [f"P@{k}" for k in KS] + [f"NDCG@{k}" for k in KS]:
            xs = [m[mname] for m in fm if m[mname] is not None]
            row[mname] = {"mean": round(st.mean(xs), 4) if xs else None, "sd": round(st.pstdev(xs), 4) if len(xs) > 1 else None}
        order = pooled_order(name)
        rated = [r for r in order if H.get(r["id"], {}).get("discovery_value") is not None]
        top = rated[:100]
        row["accepted_per_100_reviewed"] = round(100 * sum(acc(r) for r in top) / len(top), 2) if top else None
        sc = [pooled_scores[name][r["id"]][1] for r in rated]
        row["spearman_vs_discovery_value"] = RS.spearman(sc, [H[r["id"]]["discovery_value"] for r in rated])
        row["spearman_vs_surprise"] = RS.spearman(sc, [H[r["id"]]["surprise"] for r in rated])
        el = [r for r in rated if r["eligible"]]
        row["spearman_vs_discovery_value_eligible"] = RS.spearman([pooled_scores[name][r["id"]][1] for r in el], [H[r["id"]]["discovery_value"] for r in el])
        t20 = rated[:20]
        row["monitor_top20"] = {
            "duplicates": sum(1 for r in t20 if r.get("_cluster") and r["duplicate_of"]),
            "distinct_outcome_types": len({r["outcome_type"] for r in t20}),
            "mean_evidence_quality": round(st.mean([H[r["id"]]["evidence_quality"] for r in t20 if H[r["id"]]["evidence_quality"] is not None]), 3) if t20 else None,
            "false_positives (ineligible or evidence quality < 2.5)": sum(1 for r in t20 if not r["eligible"] or (H[r["id"]]["evidence_quality"] or 5) < 2.5),
        }
        table[name] = row

    # paired catalyst-group bootstrap of RSS minus existing on the pooled ranking
    rng = random.Random(7)
    gids = sorted({r["group_id"] for r in base_rows})
    members = {}
    for r in base_rows:
        members.setdefault(r["group_id"], []).append(r["id"])
    diffs = {"NDCG@20": [], "P@20": []}
    for _ in range(a.boot):
        pick = [rng.choice(gids) for _ in gids]
        ids = {}
        for n, g in enumerate(pick):
            for i in members[g]:
                ids[i] = ids.get(i, 0) + 1
        ms = {}
        for name in ("RSS", "existing (evidence_first_v0)"):
            order = [r for r in pooled_order(name, set(ids)) for _ in range(ids[r["id"]])]
            ms[name] = metrics(order, H, (20,))
        for m in diffs:
            x, y = ms["RSS"][m], ms["existing (evidence_first_v0)"][m]
            if x is not None and y is not None:
                diffs[m].append(x - y)
    boot = {m: {"mean_diff": round(st.mean(v), 4), "ci95": [round(sorted(v)[int(.025 * len(v))], 4), round(sorted(v)[int(.975 * len(v)) - 1], 4)]}
            if v else None for m, v in diffs.items()}

    # component validity: each feature against its human counterpart (all rated candidates)
    rated_rows = [r for r in base_rows if H.get(r["id"], {}).get("discovery_value") is not None]
    hv = lambda s: [H[r["id"]][s] for r in rated_rows]
    comp = {
        "S_A vs surprise": RS.spearman([r["components"]["S_A"] for r in rated_rows], hv("surprise")),
        "S_B vs surprise": RS.spearman([r["components"]["S_B"] for r in rated_rows], hv("surprise")),
        "S_D vs surprise": RS.spearman([r["components"]["S_D"] for r in rated_rows], hv("surprise")),
        "S vs surprise": RS.spearman([r["S"] for r in rated_rows], hv("surprise")),
        "C vs catalyst_relevance": RS.spearman([r["components"]["C"] for r in rated_rows], hv("catalyst_relevance")),
        "G vs consequence_significance": RS.spearman([r["components"]["G"] for r in rated_rows], hv("consequence_significance")),
        "R vs discovery_value": RS.spearman([r["R"] for r in rated_rows], hv("discovery_value")),
        "RSS vs discovery_value": RS.spearman([r["RSS"] for r in rated_rows], hv("discovery_value")),
        "S_A predicted vs raters' pass-1 lists (share agreeing)": None,
    }
    agree = [(r["components"]["S_A"] is not None and r["components"]["S_A"] < 1.0, H[r["id"]]["on_list_share"] >= 0.5)
             for r in rated_rows if H[r["id"]]["on_list_share"] is not None and r["components"]["S_A"] is not None]
    if agree:
        comp["S_A predicted vs raters' pass-1 lists (share agreeing)"] = round(sum(x == y for x, y in agree) / len(agree), 3)

    # validity checks on the planted controls
    real = [v for v in H.values() if not v["control"]]
    ob = [v for v in H.values() if v["control"] == "planted_obvious"]
    fk = [v for v in H.values() if v["control"] == "planted_fabricated"]
    med = lambda xs: st.median(xs) if xs else None
    ms = lambda vs, s: round(st.mean([v[s] for v in vs if v[s] is not None]), 3) if any(v[s] is not None for v in vs) else None
    real_surp_med = med([v["surprise"] for v in real if v["surprise"] is not None])
    real_evq_med = med([v["evidence_quality"] for v in real if v["evidence_quality"] is not None])
    ctrl_scores = {r["id"]: r for r in RS.load_jsonl(f"{DATA}/out/rss_controls.jsonl")} if os.path.exists(f"{DATA}/out/rss_controls.jsonl") else {}
    validity = {
        "planted_obvious_mean_surprise": ms(ob, "surprise"), "real_median_surprise": real_surp_med,
        "obvious_ok (<= 2.5 and below the real median)": None if ms(ob, "surprise") is None else (ms(ob, "surprise") <= 2.5 and ms(ob, "surprise") < real_surp_med),
        "planted_fabricated_mean_evidence_quality": ms(fk, "evidence_quality"), "real_median_evidence_quality": real_evq_med,
        "fabricated_ok (<= 2.5 and below the real median)": None if ms(fk, "evidence_quality") is None else (ms(fk, "evidence_quality") <= 2.5 and ms(fk, "evidence_quality") < real_evq_med),
        "S_A_recall_on_obvious_controls": (lambda xs: round(sum(xs) / len(xs), 3) if xs else None)(
            [ctrl_scores[i]["components"]["S_A"] < 1.0 for i in ctrl_scores if ctrl_scores[i]["control"] == "planted_obvious" and ctrl_scores[i]["components"]["S_A"] is not None]),
        "obvious_controls_mean_RSS_pool_percentile (lower is better)": (lambda xs: round(st.mean(xs), 3) if xs else None)(
            [ctrl_scores[i]["RSS_pool_percentile"] for i in ctrl_scores if ctrl_scores[i]["control"] == "planted_obvious" and ctrl_scores[i]["RSS_pool_percentile"] is not None]),
        "fabricated_controls_mean_RSS_pool_percentile (RSS alone; the evidence gate is what excludes them)": (lambda xs: round(st.mean(xs), 3) if xs else None)(
            [ctrl_scores[i]["RSS_pool_percentile"] for i in ctrl_scores if ctrl_scores[i]["control"] == "planted_fabricated" and ctrl_scores[i]["RSS_pool_percentile"] is not None]),
    }

    disagreement = {s: round(st.mean([v[f"{s}_sd"] for v in H.values() if v[f"{s}_sd"] is not None]), 3)
                    if any(v[f"{s}_sd"] is not None for v in H.values()) else None for s in SCALES}
    report = {"raters": sorted(raters), "n_items_rated": sum(1 for v in H.values() if v["discovery_value"] is not None),
              "folds": a.folds, "fold_groups": [sorted(g) for g in groups], "tuned_choices": tuned_choices,
              "agreement_mean_pairwise_spearman": rater_agreement(raters, key), "mean_item_sd": disagreement,
              "base_rate_accepted_among_rated": round(sum(1 for r in rated_rows if acc(r)) / len(rated_rows), 4) if rated_rows else None,
              "rankers": table, "bootstrap_RSS_minus_existing": boot, "component_validity_spearman": comp, "validity_checks": validity,
              "item_means": H}
    json.dump(report, open(f"{a.out}/report.json", "w"), indent=1, sort_keys=True)

    L = ["# RSS evaluation report", "",
         f"Raters: {', '.join(sorted(raters))}. Items rated: {report['n_items_rated']}. Held-out design: {a.folds} grouped folds on catalyst groups.",
         f"Accepted = eligible, mean discovery value >= 3.5 and mean surprise >= 3.5. Base rate among rated candidates: {report['base_rate_accepted_among_rated']}.", "",
         "| Ranker | P@10 | P@20 | NDCG@10 | NDCG@20 | Accepted per 100 reviewed | Spearman vs value | Spearman vs surprise |", "|---|---|---|---|---|---|---|---|"]
    f = lambda d: "n/a" if d is None or d.get("mean") is None else f"{d['mean']:.3f}" + (f" ({d['sd']:.3f})" if d.get("sd") is not None else "")
    for name, row in table.items():
        L.append(f"| {name} | {f(row['P@10'])} | {f(row['P@20'])} | {f(row['NDCG@10'])} | {f(row['NDCG@20'])} | {row['accepted_per_100_reviewed']} | {row['spearman_vs_discovery_value']} | {row['spearman_vs_surprise']} |")
    L += ["", "Fold means with the standard deviation across folds in parentheses.", "",
          f"Bootstrap over catalyst groups, RSS minus existing: {json.dumps(boot)}", "",
          "## Top-20 monitoring (pooled held-out ranking)", "", "| Ranker | Duplicates | Distinct outcome types | Mean evidence quality | False positives |", "|---|---|---|---|---|"]
    for name, row in table.items():
        mo = row["monitor_top20"]
        L.append(f"| {name} | {mo['duplicates']} | {mo['distinct_outcome_types']} | {mo['mean_evidence_quality']} | {mo['false_positives (ineligible or evidence quality < 2.5)']} |")
    L += ["", "## Components against their human counterparts (Spearman)", ""] + [f"- {k}: {v}" for k, v in comp.items()]
    L += ["", "## Validity checks on the planted controls", ""] + [f"- {k}: {v}" for k, v in validity.items()]
    L += ["", "## Rater agreement", "", f"Mean pairwise Spearman: {json.dumps(report['agreement_mean_pairwise_spearman'])}",
          f"Mean per-item standard deviation: {json.dumps(disagreement)}", "",
          "Do not read a higher RSS row as proof that RSS measures human surprise or value; read the held-out comparison and the ablations."]
    open(f"{a.out}/report.md", "w").write("\n".join(L) + "\n")
    print("\n".join(L[:7 + len(table)]))
    print(f"report: {a.out}/report.md and report.json")


if __name__ == "__main__":
    main()
