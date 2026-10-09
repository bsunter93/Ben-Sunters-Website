"""Raw pairs to candidates (data/candidates_core.json) and stones (data/stones.json).

    python3 ripples/engine/generate/build_candidates.py

Reads data/raw_pairs.jsonl plus three review files a person writes after reading the raw pairs:
  data/stone_map.json   {"<raw stone string>": "<stone_id>"}: the same stone named two ways maps to one id
  data/stone_defs.json  {stone_id: {"name", "date", "cache_id" (optional: a stone already predicted in an earlier run)}}
  data/review.json      {"<raw_id>": {"action": "drop_live" | "drop_yield_v1" | "exclude_topic_match" | "exclude_other" |
                                      "merge_into:<raw_id>" | "unexclude", "note": "...", "outcome": optional fix,
                                      "outcome_domain": optional fix}}
Rules: excluded rows and null rows (direction none) never become candidates; duplicates of live chains or yield v1's 56
study items are logged and dropped; the same stone and outcome from several papers merge into the first raw pair's
candidate. Candidate ids are stable: C + the raw id of the pair that founded it. Every raw id gets a status in
data/raw_status.json.
"""
import argparse
import json
import os
import sys
from collections import Counter

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Build candidates from reviewed raw pairs (script step).")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    raw = [json.loads(l) for l in open(f"{work}/data/raw_pairs.jsonl") if l.strip()]
    smap = json.load(open(f"{work}/data/stone_map.json"))
    sdef = json.load(open(f"{work}/data/stone_defs.json"))
    rev = json.load(open(f"{work}/data/review.json")) if os.path.exists(f"{work}/data/review.json") else {}
    cands, status = {}, {}
    for r in raw:
        rid = r["raw_id"]
        act = rev.get(rid, {}).get("action", "")
        if r["excluded"] and act != "unexclude":
            status[rid] = "excluded_" + r["excluded"]
            continue
        if act.startswith("exclude_"):
            status[rid] = act
            continue
        if r["direction"] == "none":
            status[rid] = "null_finding"
            continue
        if act in ("drop_live", "drop_yield_v1"):
            status[rid] = act
            continue
        if r["stone"] not in smap:
            raise SystemExit(f"unmapped stone: {r['stone']!r} ({rid}); add it to data/stone_map.json")
        sid = smap[r["stone"]]
        if act.startswith("merge_into:"):
            tgt = "C" + act.split(":", 1)[1]
            cands[tgt]["also_papers"].append({"raw_id": rid, "paper_id": r["paper_id"], "doi": r["doi"], "pmid": r["pmid"]})
            status[rid] = "merged_into_" + tgt
            continue
        cid = "C" + rid
        s = sdef[sid]
        outcome = rev.get(rid, {}).get("outcome") or r["outcome"]
        dom = rev.get(rid, {}).get("outcome_domain") or r["outcome_domain"]
        cands[cid] = {"candidate_id": cid, "raw_id": rid, "stone_id": sid, "stone_name": s["name"], "stone_date": s["date"],
                      "event_class": r["event_class"], "outcome": outcome, "outcome_domain": dom,
                      "other_domain": r.get("other_domain", ""), "content_cell": r["event_class"] + "x" + dom,
                      "query_cells": r["query_cells"], "direction": r["direction"], "effect": r["effect"],
                      "design": r["design"], "quote": r["quote"], "population_place": r["population_place"],
                      "paper_id": r["paper_id"], "doi": r["doi"], "pmid": r["pmid"], "venue": r["venue"], "year": r["year"],
                      "law_policy": bool(r["law_policy"]), "claim": f"{s['name']} led to: {outcome}", "also_papers": []}
        status[rid] = "candidate"
    json.dump(list(cands.values()), open(f"{work}/data/candidates_core.json", "w"), indent=1, ensure_ascii=False)
    used = {c["stone_id"] for c in cands.values()}
    json.dump({k: v for k, v in sdef.items() if k in used}, open(f"{work}/data/stones.json", "w"), indent=1, ensure_ascii=False)
    json.dump(status, open(f"{work}/data/raw_status.json", "w"), indent=1)
    print("raw", len(raw), dict(Counter(status.values())))
    print("candidates", len(cands), "stones", len(used), "cached stones", sum(1 for k in used if sdef[k].get("cache_id")))


if __name__ == "__main__":
    main()
