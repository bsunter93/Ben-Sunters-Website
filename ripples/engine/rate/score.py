"""Score a rated run: validity, both yields, the gate audit, spread, and yield by cell. A script step.

    python3 ripples/engine/rate/score.py                 # writes data/scores.json and data/summary.json
    python3 ripples/engine/rate/score.py --check-only    # only check the five rating files

Reads rate/items.json, data/rate_key.json, rate/ratings_r1.json to ratings_r5.json, data/anchors.json,
data/verified.json, data/verify_selection.json and data/candidates_core.json.

Surprise index per item = mean over the raters of (surprise + 6 - predicted) / 2. Surprising: at least 3.5. Defensible:
the verification verdict. Good: both. Validity bars: planted obvious mean surprise index at most 2.5, planted fabricated
mean believable at most 2.5, anchor drift under 0.5. Yields: good per 100 gate-passers entering verification, good per
100 raw pairs (observed, and estimated when the gate-passers were sampled), surprising and defensible rates apart, the
audit, the domains of the good finds and the law or policy share, and every count by cell, domain and event class.
Every number from this panel is a simulated panel's; label it so.
"""
import argparse, itertools, json, os, statistics as st, sys
from collections import Counter, defaultdict

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402

S = ("predicted", "surprise", "interest", "believable")


def sp(a, b):
    ra = {i: r for r, i in enumerate(sorted(range(len(a)), key=lambda k: a[k]))}
    rb = {i: r for r, i in enumerate(sorted(range(len(b)), key=lambda k: b[k]))}
    n = len(a)
    return 1 - 6 * sum((ra[i] - rb[i]) ** 2 for i in range(n)) / (n * (n * n - 1))


def check(W, items):
    R = []
    for n in range(1, 6):
        p = f"{W}/rate/ratings_r{n}.json"
        if not os.path.exists(p):
            raise SystemExit(f"missing {p}")
        r = json.load(open(p))
        assert sorted(x["i"] for x in r) == list(range(len(items))), f"rater {n}: indices do not cover the items"
        assert all(isinstance(x[k], int) and 1 <= x[k] <= 5 for x in r for k in S), f"rater {n}: a value outside 1 to 5"
        R.append(r)
    return R


def main():
    ap = argparse.ArgumentParser(description="Score a rated run (script step).")
    ap.add_argument("--check-only", action="store_true")
    workdir.add_arg(ap)
    a = ap.parse_args()
    W = workdir.resolve(a.work)
    items = json.load(open(f"{W}/rate/items.json"))
    R = check(W, items)
    print("five rating files cover", len(items), "items with values 1 to 5")
    if a.check_only:
        return
    key = {int(k): v for k, v in json.load(open(f"{W}/data/rate_key.json")).items()}
    sc = {}
    for i in range(len(items)):
        v = {s: st.mean(next(x[s] for x in r if x["i"] == i) for r in R) for s in S}
        v["sidx"] = (v["surprise"] + 6 - v["predicted"]) / 2
        sc[i] = v

    def grp(g):
        return [i for i in key if key[i]["group"] == g]

    agree = {}
    for s in ("predicted", "surprise", "believable"):
        vals = [[next(x[s] for x in r if x["i"] == i) for i in range(len(items))] for r in R]
        agree[s] = round(st.mean(sp(a, b) for a, b in itertools.combinations(vals, 2)), 2)

    anchors = {a["ref"]: a for a in json.load(open(f"{W}/data/anchors.json"))}
    drift = st.mean(abs(sc[i]["sidx"] - anchors[key[i]["ref"]]["yield_v1_sidx"]) for i in grp("anchor_yield_v1"))
    validity = {"obvious_mean_sidx": round(st.mean(sc[i]["sidx"] for i in grp("planted_obvious")), 2),
                "fabricated_mean_believable": round(st.mean(sc[i]["believable"] for i in grp("planted_fabricated")), 2),
                "anchor_drift": round(drift, 2), "agreement": agree}
    validity["pass"] = validity["obvious_mean_sidx"] <= 2.5 and validity["fabricated_mean_believable"] <= 2.5 and drift < 0.5

    V = json.load(open(f"{W}/data/verified.json"))
    SEL = json.load(open(f"{W}/data/verify_selection.json"))
    C = {c["candidate_id"]: c for c in json.load(open(f"{W}/data/candidates_core.json"))}
    rated = {key[i]["ref"]: i for i in key if key[i]["group"] in ("gate_pass", "audit_reject")}

    def verdict(cid):
        v = V[cid]
        i = rated.get(cid)
        s = sc[i] if i is not None else None
        surprising = s is not None and s["sidx"] >= 3.5
        return {"defensible": bool(v["defensible"]), "rated": i is not None, "sidx": round(s["sidx"], 2) if s else None,
                "believable": round(s["believable"], 2) if s else None, "surprising": surprising,
                "good": bool(v["defensible"]) and surprising}

    gp = SEL["gate_pass"]
    res = {cid: verdict(cid) for cid in gp}
    aud = {cid: verdict(cid) for cid in SEL["audit"]}
    n_gp = len(gp)
    good = [cid for cid in gp if res[cid]["good"]]
    n_raw = SEL["n_raw_pairs"]
    n_pass_all = len(SEL["gate_pass_all"])
    est_good_all = len(good) / n_gp * n_pass_all if n_gp else 0
    by_cell = defaultdict(lambda: {"n": 0, "good": 0, "surprising": 0, "defensible": 0})
    by_dom, by_cls = defaultdict(lambda: [0, 0]), defaultdict(lambda: [0, 0])
    for cid in gp:
        c = C[cid]
        b = by_cell[c["content_cell"]]
        b["n"] += 1
        b["good"] += res[cid]["good"]
        b["surprising"] += res[cid]["surprising"]
        b["defensible"] += res[cid]["defensible"]
        by_dom[c["outcome_domain"]][0] += 1
        by_dom[c["outcome_domain"]][1] += res[cid]["good"]
        by_cls[c["event_class"]][0] += 1
        by_cls[c["event_class"]][1] += res[cid]["good"]
    doms = Counter(C[cid]["outcome_domain"] for cid in good)
    lawp = sum(1 for cid in good if C[cid]["law_policy"])
    summary = {
        "validity": validity,
        "n_raw_pairs": n_raw, "n_gate_pass_all": n_pass_all, "n_gate_pass_verified": n_gp, "n_good": len(good),
        "good_per_100_gate_pass": round(100 * len(good) / n_gp, 1) if n_gp else None,
        "good_per_100_raw_observed": round(100 * len(good) / n_raw, 1),
        "good_per_100_raw_estimated": round(100 * est_good_all / n_raw, 1),
        "surprising_rate_gate_pass": round(100 * sum(r["surprising"] for r in res.values()) / n_gp, 1) if n_gp else None,
        "defensible_rate_gate_pass": round(100 * sum(r["defensible"] for r in res.values()) / n_gp, 1) if n_gp else None,
        "surprising_among_defensible": f"{sum(r['surprising'] for r in res.values() if r['defensible'])} of {sum(r['defensible'] for r in res.values())}",
        "audit": {"n": len(aud), "good": sum(r["good"] for r in aud.values()), "defensible": sum(r["defensible"] for r in aud.values()),
                  "surprising": sum(r["surprising"] for r in aud.values())},
        "spread": {"domains_O1_O11": sorted(d for d in doms if d != "O0"), "n_domains": len([d for d in doms if d != "O0"]),
                   "domain_counts": dict(doms), "law_policy_good": lawp,
                   "law_policy_share": round(100 * lawp / len(good), 1) if good else None},
        "by_cell": dict(by_cell), "by_domain": dict(by_dom), "by_class": dict(by_cls),
    }
    json.dump({"items": {i: {**sc[i], **key[i]} for i in sc}, "gate_pass": res, "audit": aud}, open(f"{W}/data/scores.json", "w"), indent=1)
    json.dump(summary, open(f"{W}/data/summary.json", "w"), indent=1)
    print(json.dumps({k: v for k, v in summary.items() if k not in ("by_cell", "by_domain", "by_class")}, indent=1))


if __name__ == "__main__":
    main()
