"""Controls and anchors for the rating panel: 10 planted obvious, 10 planted fabricated, 10 yield v1 anchors.

    python3 ripples/engine/rate/build_controls.py      # writes data/controls.json and data/anchors.json

Planted controls come from ripples/docs/results/panel_v1/: the items of panel_v1.json whose source is planted_obvious
or planted_fabricated (selected by source, never by key index), with their evidence lines from items.json. Anchors are
10 of yield v1's 56 study items (ripples/docs/results/yield_v1/), drawn with random.seed(4300) and random.sample over
their item indices, after the items whose outcomes the owner's rulings exclude (suicide, self-harm, overdose, party
votes) are dropped from the pool. Anchor drift is the mean absolute change in surprise index against yield v1's scores.
"""
import argparse
import json
import os
import random
import re
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402

PANEL = os.path.join(workdir.RIPPLES, "docs", "results", "panel_v1")
YIELD = os.path.join(workdir.RIPPLES, "docs", "results", "yield_v1")
EXCL = re.compile(r"suicid|self-harm|overdose|republican vote|votes|elections|bjp", re.I)


def main():
    ap = argparse.ArgumentParser(description="Build the panel's controls and anchors (script step).")
    ap.add_argument("--seed", type=int, default=4300)
    ap.add_argument("--n-anchors", type=int, default=10)
    workdir.add_arg(ap)
    a = ap.parse_args()
    W = workdir.resolve(a.work)
    pv = json.load(open(os.path.join(PANEL, "panel_v1.json")))
    ev = {x["id"]: x for x in json.load(open(os.path.join(PANEL, "items.json")))}
    ctl = []
    for x in pv["items"]:
        if x["source"] in ("planted_obvious", "planted_fabricated"):
            e = ev[x["id"]]
            assert e["claim"] == x["claim"], x["id"]
            ctl.append({"group": x["source"], "ref": x["id"], "stone": e["stone"], "stone_date": e["stone_date"],
                        "claim": e["claim"], "evidence": e["evidence"]})
    assert sum(c["group"] == "planted_obvious" for c in ctl) == 10 and sum(c["group"] == "planted_fabricated" for c in ctl) == 10
    items = json.load(open(os.path.join(YIELD, "items.json")))
    key = json.load(open(os.path.join(YIELD, "key.json")))
    scores = json.load(open(os.path.join(YIELD, "scores.json")))
    study_idx = sorted(int(i) for i in key if key[i][0] == "studies")
    assert len(study_idx) == 56
    dropped = [i for i in study_idx if EXCL.search(items[i]["claim"])]
    pool = [i for i in study_idx if i not in dropped]
    random.seed(a.seed)
    pick = random.sample(pool, a.n_anchors)
    anchors = [{"group": "anchor_yield_v1", "ref": f"yield_v1:{i}:{key[str(i)][1]}", "stone": items[i]["stone"],
                "stone_date": items[i]["stone_date"], "claim": items[i]["claim"], "evidence": items[i]["evidence"],
                "yield_v1_sidx": scores[str(i)]["sidx"]} for i in pick]
    json.dump(ctl, open(f"{W}/data/controls.json", "w"), indent=1, ensure_ascii=False)
    json.dump(anchors, open(f"{W}/data/anchors.json", "w"), indent=1, ensure_ascii=False)
    print("controls", len(ctl), "anchor pool", len(pool), "dropped by the rulings", len(dropped), "anchors", len(anchors))
    for x in anchors:
        print(" ", round(x["yield_v1_sidx"], 2), x["claim"][:100])


if __name__ == "__main__":
    main()
