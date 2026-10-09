"""Build the rater packet: rate/items.json (stone, stone_date, claim, evidence only) and data/rate_key.json (never shown).

    python3 ripples/engine/rate/build_items.py

Items: every defensible gate-passer, the audited gate rejects, the 10 planted obvious and 10 planted fabricated
controls, and the 10 yield v1 anchors (build_controls.py). Raters see the claim and its evidence line only, never the
gate result, the cell or the generator. Order is a fixed shuffle (seed 4400) so the groups are interleaved; each rater
reshuffles with their own seed (personas.json). Then run each rater as a judged step:
python3 ripples/engine/runner.py rate <1 to 5>.
"""
import argparse
import json
import os
import random
import sys
from collections import Counter

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Build the rater packet (script step).")
    ap.add_argument("--seed", type=int, default=4400)
    workdir.add_arg(ap)
    a = ap.parse_args()
    W = workdir.resolve(a.work)
    V = json.load(open(f"{W}/data/verified.json"))
    SEL = json.load(open(f"{W}/data/verify_selection.json"))
    C = {c["candidate_id"]: c for c in json.load(open(f"{W}/data/candidates_core.json"))}
    if os.path.exists(f"{W}/rate/items.json"):
        raise SystemExit("rate/items.json exists; the packet is fixed once raters start")
    rows = []
    for cid in SEL["gate_pass"]:
        if V[cid]["defensible"]:
            rows.append(({"group": "gate_pass", "ref": cid}, V[cid]))
    for cid in SEL["audit"]:
        rows.append(({"group": "audit_reject", "ref": cid}, V[cid]))
    items, key = [], {}
    for k, v in rows:
        c = C[k["ref"]]
        items.append({"stone": c["stone_name"], "stone_date": c["stone_date"], "claim": v.get("claim") or c["claim"],
                      "evidence": v.get("evidence_line", "")})
        key[len(items) - 1] = k
    for x in json.load(open(f"{W}/data/controls.json")) + json.load(open(f"{W}/data/anchors.json")):
        items.append({"stone": x["stone"], "stone_date": x["stone_date"], "claim": x["claim"], "evidence": x["evidence"]})
        key[len(items) - 1] = {"group": x["group"], "ref": x["ref"]}
    idx = list(range(len(items)))
    random.seed(a.seed)
    random.shuffle(idx)
    items2 = [items[i] for i in idx]
    key2 = {str(n): key[i] for n, i in enumerate(idx)}
    json.dump(items2, open(f"{W}/rate/items.json", "w"), indent=1, ensure_ascii=False)
    json.dump(key2, open(f"{W}/data/rate_key.json", "w"), indent=1)
    print(len(items2), dict(Counter(k["group"] for k in key2.values())))


if __name__ == "__main__":
    main()
