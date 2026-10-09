"""Verification judgment: inputs for the judged step, and the verdicts assembled into data/verified.json.

    python3 ripples/engine/verify/judge.py inputs <wave>     # selected candidates + fetched text -> verify/judge_in/<wave>_jNN.json
    python3 ripples/engine/verify/judge.py assemble          # verify/judge_raw/*.jsonl -> data/verified.json

Between the two, judge_prompt.txt is applied to each input file in a fresh context that reads only the prompt and that
file (python3 ripples/engine/runner.py verify <file> prints the instructions). The judgment uses only the fetched text.

A candidate is defensible only when all hold: the fetched text is the same paper; the quote is found (or the judgment
copies a better quote from the text); the claim is supported or partly supported; the stone comes before the outcome
window; and the design compares against a baseline. assemble recomputes that rule from the fields and keeps a candidate
defensible only when the rule and the judgment agree; disagreements are listed. It also writes each candidate's
evidence line for the rater packet: Venue (design): "quote".
"""
import argparse
import glob
import json
import os
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402

CHUNK = 10
TEXT_CAP = 40000
SUFFIX = {"pubmed": "pubmed", "crossref-abstract": "crossref", "landing": "landing", "open-copy": "open"}
FIELDS = ["candidate_id", "same_paper", "quote_found", "better_quote", "claim_supported", "claim_fix", "date_order",
          "design_ok", "grade", "defensible", "note"]


def yes(v):
    return str(v).strip().lower() == "yes"


def inputs(W, wave):
    sel = json.load(open(f"{W}/data/verify_selection.json"))
    C = {c["candidate_id"]: c for c in json.load(open(f"{W}/data/candidates_core.json"))}
    P = {p["paper_id"]: p for p in json.load(open(f"{W}/data/papers.json"))}
    summ = json.load(open(f"{W}/verify/verify_fetch_summary.json"))
    queued = set()
    for f in glob.glob(f"{W}/verify/judge_in/*.json"):
        queued |= {x["candidate_id"] for x in json.load(open(f))}
    items, no_text = [], []
    for cid in sel["gate_pass"] + sel["audit"]:
        if cid in queued:
            continue
        c, s = C[cid], summ.get(cid)
        if not s or not s.get("any_text"):
            no_text.append(cid)
            continue
        texts = []
        for t in s["any_text"]:
            p = f"{W}/verify/{s['safe']}__{SUFFIX[t['source']]}.txt"
            if os.path.exists(p):
                texts.append({"source": t["source"], "url": t["url"], "text": open(p).read()[:TEXT_CAP]})
        items.append({"candidate_id": cid, "paper_title": P.get(c["paper_id"], {}).get("title", ""), "doi": c.get("doi"),
                      "stone": f"{c['stone_name']} ({c['stone_date']})", "outcome": c["outcome"], "direction": c["direction"],
                      "effect": c["effect"], "design": c["design"], "quote": c["quote"],
                      "quote_found_by_script": bool(s.get("found_in")), "texts": texts})
    n = 0
    for i in range(0, len(items), CHUNK):
        n += 1
        p = f"{W}/verify/judge_in/{wave}_j{n:02d}.json"
        if os.path.exists(p):
            raise SystemExit(f"{p} exists; use a new wave name")
        json.dump(items[i:i + CHUNK], open(p, "w"), indent=1, ensure_ascii=False)
    print("items", len(items), "files", n, "with no fetched text (not defensible):", len(no_text), no_text[:10])


def assemble(W):
    sel = json.load(open(f"{W}/data/verify_selection.json"))
    C = {c["candidate_id"]: c for c in json.load(open(f"{W}/data/candidates_core.json"))}
    rows = {}
    for f in sorted(glob.glob(f"{W}/verify/judge_raw/*.jsonl")):
        b = os.path.basename(f)[:-6]
        inp = {x["candidate_id"] for x in json.load(open(f"{W}/verify/judge_in/{b}.json"))}
        got = [json.loads(l) for l in open(f) if l.strip()]
        assert {r["candidate_id"] for r in got} == inp, f"{b}: ids differ from its input"
        for r in got:
            miss = [k for k in FIELDS if k not in r]
            assert not miss, (b, r["candidate_id"], miss)
            rows[r["candidate_id"]] = r
    out, disagree = {}, []
    for cid in sel["gate_pass"] + sel["audit"]:
        c = C[cid]
        r = rows.get(cid)
        if r is None:
            out[cid] = {"candidate_id": cid, "judged": False, "defensible": False, "note": "no fetched text or not judged",
                        "claim": c["claim"], "evidence_line": ""}
            continue
        quote = c["quote"] if yes(r["quote_found"]) else (r.get("better_quote") or "")
        rule = (yes(r["same_paper"]) and bool(quote) and str(r["claim_supported"]).lower() in ("yes", "partly")
                and yes(r["date_order"]) and yes(r["design_ok"]))
        if rule != yes(r["defensible"]):
            disagree.append(cid)
        claim = c["claim"]
        if str(r["claim_supported"]).lower() == "partly" and r.get("claim_fix"):
            claim = f"{c['stone_name']} led to: {r['claim_fix']}"
        out[cid] = {**r, "judged": True, "defensible": rule and yes(r["defensible"]), "quote_used": quote, "claim": claim,
                    "evidence_line": f"{c.get('venue') or 'Published study'} ({c['design']}): \"{quote}\"" if quote else ""}
    json.dump(out, open(f"{W}/data/verified.json", "w"), indent=1, ensure_ascii=False)
    gp = sel["gate_pass"]
    print(f"gate-passers defensible {sum(out[c]['defensible'] for c in gp)} of {len(gp)}; "
          f"audit defensible {sum(out[c]['defensible'] for c in sel['audit'])} of {len(sel['audit'])}")
    if disagree:
        print("rule and judgment disagree (kept not defensible):", disagree)


def main():
    ap = argparse.ArgumentParser(description="Inputs and verdicts for the verification judgment.")
    ap.add_argument("cmd", choices=["inputs", "assemble"])
    ap.add_argument("wave", nargs="?")
    workdir.add_arg(ap)
    a = ap.parse_args()
    W = workdir.resolve(a.work)
    if a.cmd == "inputs":
        if not a.wave:
            ap.error("inputs needs a wave name")
        inputs(W, a.wave)
    else:
        assemble(W)


if __name__ == "__main__":
    main()
