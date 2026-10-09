"""Which candidates enter verification, by the registered sampling rules (discovery v4 plan, queries file "sampling").

    python3 ripples/engine/verify/selection.py              # writes data/verify_selection.json and data/verify_targets.json
    python3 ripples/engine/verify/selection.py --dry-run    # counts only

Every gate-passer enters verification, up to --cap (100): above the cap a random 100 is drawn with random.seed(4100)
and random.sample over the sorted candidate ids. A random --audit (20) of the gate's rejects is verified too, drawn with
random.seed(4200) the same way; the audit tests whether the gate throws good finds away. The raw pair count is kept
for the second denominator of the yield.
"""
import argparse
import json
import os
import random
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Select candidates for verification (script step).")
    ap.add_argument("--cap", type=int, default=100)
    ap.add_argument("--cap-seed", type=int, default=4100)
    ap.add_argument("--audit", type=int, default=20)
    ap.add_argument("--audit-seed", type=int, default=4200)
    ap.add_argument("--dry-run", action="store_true")
    workdir.add_arg(ap)
    a = ap.parse_args()
    W = workdir.resolve(a.work)
    C = {c["candidate_id"]: c for c in json.load(open(f"{W}/data/candidates_core.json"))}
    M = {json.loads(l)["candidate_id"]: json.loads(l) for l in open(f"{W}/data/matches.jsonl") if l.strip()}
    unmatched = sorted(set(C) - set(M))
    if unmatched:
        raise SystemExit(f"{len(unmatched)} candidates have no match record yet: {unmatched[:5]}")
    n_raw = sum(1 for l in open(f"{W}/data/raw_pairs.jsonl") if l.strip())
    passed = sorted(cid for cid in C if M[cid]["rank"] is None)
    rejects = sorted(cid for cid in C if M[cid]["rank"] is not None)
    if len(passed) > a.cap:
        random.seed(a.cap_seed)
        gate_pass = random.sample(passed, a.cap)
    else:
        gate_pass = list(passed)
    random.seed(a.audit_seed)
    audit = random.sample(rejects, min(a.audit, len(rejects)))
    print(f"raw pairs {n_raw}, candidates {len(C)}, gate passed {len(passed)} (verify {len(gate_pass)}), "
          f"rejected {len(rejects)} (audit {len(audit)})")
    if a.dry_run:
        return
    sel = {"n_raw_pairs": n_raw, "n_candidates": len(C), "gate_pass_all": passed, "gate_pass": gate_pass, "audit": audit,
           "rules": {"cap": a.cap, "cap_seed": a.cap_seed, "audit": a.audit, "audit_seed": a.audit_seed}}
    json.dump(sel, open(f"{W}/data/verify_selection.json", "w"), indent=1)
    P = {p["paper_id"]: p for p in json.load(open(f"{W}/data/papers.json"))}
    targets = []
    for cid in gate_pass + audit:
        c = C[cid]
        p = P.get(c["paper_id"], {})
        landing = p.get("landing") or ""
        targets.append({"target_id": cid, "paper_id": c["paper_id"], "doi": c.get("doi") or "", "pmid": c.get("pmid"),
                        "quote": c["quote"], "open_copies": [landing] if landing and "doi.org/" not in landing else []})
    json.dump(targets, open(f"{W}/data/verify_targets.json", "w"), indent=1, ensure_ascii=False)
    print("wrote data/verify_selection.json and data/verify_targets.json,", len(targets), "targets")


if __name__ == "__main__":
    main()
