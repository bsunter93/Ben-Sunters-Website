"""What is already known: the live chains and yield v1's study items, for the dedupe review before the gate.

    python3 ripples/engine/generate/dedupe_sources.py            # writes data/dedupe_sources.json
    python3 ripples/engine/generate/dedupe_sources.py --check    # also lists raw pairs whose stone shares a word with one

Reads ripples/chains/batch*.json (slug, title, date, step claims) and ripples/docs/results/yield_v1/ (the 56 study
items). The review itself is a person's call, written to data/review.json as {"<raw_id>": {"action": "drop_live" or
"drop_yield_v1", "note": "..."}} before build_candidates.py runs. --check only points at rows to read.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402

STOP = set("a an the of to in on for and or by with from its it is as at after be into than that this their was were "
           "us uk new first last day days game games film show series release launch death".split())


def words(t):
    return {w for w in re.findall(r"[a-z']+", (t or "").lower()) if len(w) > 2 and w not in STOP}


def sources():
    chains = []
    for f in sorted(glob.glob(os.path.join(workdir.RIPPLES, "chains", "batch*.json"))):
        for c in json.load(open(f)):
            chains.append({"slug": c["slug"], "title": c["title"], "date": c.get("date"),
                           "steps": [s.get("claim", "") for s in c.get("steps", [])]})
    yd = os.path.join(workdir.RIPPLES, "docs", "results", "yield_v1")
    items = json.load(open(os.path.join(yd, "items.json")))
    key = json.load(open(os.path.join(yd, "key.json")))
    studies = [{"i": int(i), "ref": k[1], "stone": items[int(i)]["stone"], "claim": items[int(i)]["claim"]}
               for i, k in sorted(key.items(), key=lambda x: int(x[0])) if k[0] == "studies"]
    try:
        commit = subprocess.run(["git", "-C", workdir.REPO, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    except OSError:
        commit = ""
    return {"live_chains": chains, "yield_v1_studies": studies, "live_commit": commit}


def main():
    ap = argparse.ArgumentParser(description="Write the dedupe sources (script step).")
    ap.add_argument("--check", action="store_true", help="list raw pairs whose stone shares a word with a known one")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    src = sources()
    out = os.path.join(work, "data", "dedupe_sources.json")
    json.dump(src, open(out, "w"), indent=1, ensure_ascii=False)
    print("live chains", len(src["live_chains"]), "yield v1 study items", len(src["yield_v1_studies"]), "->", out)
    if not a.check:
        return
    rp = os.path.join(work, "data", "raw_pairs.jsonl")
    if not os.path.exists(rp):
        print("no raw pairs yet")
        return
    known = [("chain " + c["slug"], words(c["title"])) for c in src["live_chains"]]
    known += [("yield_v1 " + s["ref"], words(s["stone"])) for s in src["yield_v1_studies"]]
    for line in open(rp):
        r = json.loads(line)
        w = words(r["stone"])
        hits = [name for name, kw in known if w & kw]
        if hits:
            print(r["raw_id"], r["stone"][:60], "|", ", ".join(hits[:4]))


if __name__ == "__main__":
    main()
