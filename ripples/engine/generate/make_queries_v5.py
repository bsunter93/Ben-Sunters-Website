"""Build the v5 query grid (docs/discovery_plan_v5.md): v4's grid cut to six event classes and eight outcome domains,
with drinking, gambling and turnout words added, one OpenAlex and one PubMed query per cell.

    python3 ripples/engine/generate/make_queries_v5.py --out ripples/engine/generate/queries/discovery_v5.json --plan PLAN.md

Run once, before the first request; never overwrite a frozen file. The cell ids keep v4's codes, so extraction, the
prescreen and the yield tables read v5 the same way.
"""
import argparse, datetime, hashlib, json, os, runpy, sys

HERE = os.path.dirname(os.path.abspath(__file__))
argv, sys.argv = sys.argv, [sys.argv[0], "--dry-run"]
v4 = runpy.run_path(os.path.join(HERE, "make_queries.py"))  # v4's word lists, unchanged (its dry run prints its counts)
sys.argv = argv

EVENTS = {k: dict(v4["EVENTS"][k]) for k in ("I1", "I2", "I3", "I5", "I6", "I7")}
EVENTS["I5"]["words"] = EVENTS["I5"]["words"] + ['"school shooting"']
EVENTS["I6"]["words"] = EVENTS["I6"]["words"] + ['"Tinder"', '"Lyft"']
OUTCOMES = {k: dict(v4["OUTCOMES"][k]) for k in ("O1", "O2", "O3", "O5", "O6", "O9", "O10", "O11")}
OUTCOMES["O10"]["words"] = OUTCOMES["O10"]["words"] + ['"alcohol sales"', '"alcohol consumption"', "drinking", "gambling", "betting"]
OUTCOMES["O11"]["words"] = OUTCOMES["O11"]["words"] + ['"voter turnout"', "turnout", '"voter registration"']
DESIGN = ['natural experiment', 'difference-in-differences', 'regression discontinuity', 'event study']


def oa_q(i, o):
    return ("(" + " OR ".join(EVENTS[i]["words"]) + ") AND (" + " OR ".join(OUTCOMES[o]["words"]) + ") AND ("
            + " OR ".join(f'"{d}"' for d in DESIGN) + ")")


def pm_q(i, o):
    t = v4["pm_term"]
    return (f"({' OR '.join(t(w) for w in EVENTS[i]['words'])}) AND ({' OR '.join(t(w) for w in OUTCOMES[o]['words'])}) "
            f"AND ({' OR '.join(t(d) for d in DESIGN)})")


cells = [{"cell": f"{i}x{o}", "event_class": i, "outcome_domain": o, "openalex": [oa_q(i, o)], "pubmed": [pm_q(i, o)]}
         for i in EVENTS for o in OUTCOMES]
ap = argparse.ArgumentParser(description="Build the frozen v5 query grid.")
ap.add_argument("--out"); ap.add_argument("--plan"); ap.add_argument("--dry-run", action="store_true")
a = ap.parse_args()
doc = {"frozen_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "plan_sha256": hashlib.sha256(open(a.plan, "rb").read()).hexdigest() if a.plan else None,
       "note": "Frozen before the first request. v4's grid cut to six event classes and eight outcome domains; one OpenAlex and one PubMed query per cell.",
       "sources": {"openalex": "https://api.openalex.org/works?search=<q>&per-page=50 (keyless)", "pubmed": "esearch retmax=40 sort=relevance, then efetch"},
       "event_classes": EVENTS, "outcome_domains": OUTCOMES, "design_terms": DESIGN, "cells": cells,
       "counts": {"cells": len(cells), "openalex_queries": len(cells), "pubmed_queries": len(cells)}}
print("v5", doc["counts"])
if not a.dry_run:
    if os.path.exists(a.out):
        raise SystemExit(f"{a.out} exists; a query file is frozen once written")
    json.dump(doc, open(a.out, "w"), indent=1, ensure_ascii=False)
    print("wrote", a.out, "sha256", hashlib.sha256(open(a.out, "rb").read()).hexdigest())
