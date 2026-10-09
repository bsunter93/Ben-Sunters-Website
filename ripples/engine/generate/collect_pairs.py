"""Collect the extraction step's output into data/raw_pairs.jsonl (every raw pair) and data/screen.jsonl.

    python3 ripples/engine/generate/collect_pairs.py

Reads data/extract_out/<batch>.jsonl (one line per screened paper and one per raw pair, as extract_prompt.txt asks)
against data/extract_in/<batch>.json and data/papers.json. Adds the paper's DOI, PMID, venue, year and query cells,
sets content_cell (event class x outcome domain), and checks that every quote is verbatim in the paper's harvested
title or abstract (quote_in_harvest). Raw ids are R0001, R0002, ... in batch order, so rerun this only after every
batch is in. The raw pair count is the raw denominator of the yield.
"""
import argparse
import glob
import json
import os
import re
import sys
from collections import Counter

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402


def norm(t):
    t = (t or "").replace("\u2019", "'").replace("\u2013", "-").replace("\u2014", "-")
    return re.sub(r"\s+", " ", t).strip().lower()


def main():
    ap = argparse.ArgumentParser(description="Collect raw pairs from the extraction output (script step).")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    papers = {p["paper_id"]: p for p in json.load(open(f"{work}/data/papers.json"))}
    rows, screens, bad = [], [], []
    files = sorted(glob.glob(f"{work}/data/extract_out/*.jsonl"))
    if not files:
        print("no extraction output yet in", f"{work}/data/extract_out/")
        return
    for f in files:
        batch = os.path.basename(f)[:-6]
        inp = {p["paper_id"] for p in json.load(open(f"{work}/data/extract_in/{batch}.json"))}
        seen = set()
        for line in open(f):
            if not line.strip():
                continue
            r = json.loads(line)
            if r.get("screen"):
                screens.append({**r, "batch": batch})
                seen.add(r["paper_id"])
                continue
            p = papers[r["paper_id"]]
            r["batch"] = batch
            r["doi"], r["pmid"], r["venue"], r["year"] = p["doi"], p["pmid"], p["venue"], p["year"]
            r["query_cells"] = p["query_cells"]
            r["content_cell"] = f"{r['event_class']}x{r['outcome_domain']}"
            r["quote_in_harvest"] = norm(r["quote"]) in norm(p["title"] + " " + p["abstract"])
            if not r["quote_in_harvest"]:
                bad.append((r["paper_id"], r["quote"][:80]))
            rows.append(r)
        missing = inp - seen
        if missing:
            print("WARN", batch, "papers without a screen line:", len(missing))
    for n, r in enumerate(rows, 1):
        r["raw_id"] = f"R{n:04d}"
    with open(f"{work}/data/raw_pairs.jsonl", "w") as fo:
        for r in rows:
            fo.write(json.dumps(r, ensure_ascii=False) + "\n")
    with open(f"{work}/data/screen.jsonl", "w") as fo:
        for s in screens:
            fo.write(json.dumps(s, ensure_ascii=False) + "\n")
    print("screened", len(screens), dict(Counter(s["reason"] for s in screens)))
    print("raw pairs", len(rows), "excluded", dict(Counter(r["excluded"] for r in rows)))
    print("quotes not verbatim in harvest:", len(bad), bad[:5])


if __name__ == "__main__":
    main()
