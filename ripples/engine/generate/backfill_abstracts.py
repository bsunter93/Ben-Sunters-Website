"""Crossref backup for missing abstracts (the plans allow Crossref only for missing abstracts or dates).

    python3 ripples/engine/generate/backfill_abstracts.py              # after build_papers.py has written data/papers.json
    python3 ripples/engine/generate/backfill_abstracts.py --dry-run    # how many papers would be asked for

For papers with no abstract, a DOI, and a title that carries an event word of one of its query cells, ask Crossref for
the publisher-deposited abstract. Writes data/abstract_backfill.json; run build_papers.py again to use it.
"""
import argparse
import json
import os
import re
import sys
import urllib.parse

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch  # noqa: E402
import workdir  # noqa: E402
from build_papers import CLS  # noqa: E402


def title_has_event(p):
    t = (p["title"] or "").lower()
    for qc in p["query_cells"]:
        i = qc.split("x")[0]
        if i not in CLS or CLS[i].search(t):
            return True
    return False


def main():
    ap = argparse.ArgumentParser(description="Crossref abstracts for papers that have none (script step).")
    ap.add_argument("--dry-run", action="store_true")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    fetch.configure(work)
    papers = json.load(open(os.path.join(work, "data", "papers.json")))
    p_out = os.path.join(work, "data", "abstract_backfill.json")
    out = json.load(open(p_out)) if os.path.exists(p_out) else {}
    todo = [p for p in papers if not p["abstract"] and p["doi"] and p["paper_id"] not in out and title_has_event(p)]
    print("to backfill", len(todo))
    if a.dry_run:
        return
    for p in todo:
        if "api.crossref.org" in fetch.blocked_hosts():
            print("crossref stopped for the UTC day")
            break
        st, body, _ = fetch.get("https://api.crossref.org/works/" + urllib.parse.quote(p["doi"]))
        if st != 200:
            out[p["paper_id"]] = {"status": st}
            continue
        m = json.loads(body)["message"]
        ab = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.get("abstract", "") or "")).strip()
        out[p["paper_id"]] = {"status": st, "abstract": ab, "issued": m.get("issued")}
        json.dump(out, open(p_out, "w"), indent=1, ensure_ascii=False)
    json.dump(out, open(p_out, "w"), indent=1, ensure_ascii=False)
    print("backfilled with abstract", sum(1 for v in out.values() if v.get("abstract")), "of", len(out))


if __name__ == "__main__":
    main()
