"""Held-out, forward direction: the stone's own article minus plot/cast/production, every mark-shaped sentence with a
causal connective; a sentence that carries a year before the stone is set aside by the ordering rule."""
import json, re
from legacy2 import mine
from heldout import STONES
out = []
for article, stone, year in STONES:
    real, cands = mine(article); cands = cands or []
    keep = []
    for c in cands:
        if not c["causal"]: continue
        ys = [int(y) for y in c["years"]]
        verdict = "in order" if (not ys or max(ys) >= year) else "busted: before the stone"
        if ys and min(ys) < year and max(ys) >= year: verdict = "mixed years"
        keep.append({**c, "verdict": verdict})
    out.append({"stone": stone, "year": year, "mark_shaped": len(cands), "causal": len(keep), "in_order": sum(1 for k in keep if k["verdict"] == "in order"), "cands": keep})
    print(f"{stone[:24]:24s} ({year}) | mark-shaped {len(cands):3d} | causal {len(keep):2d} | in order {sum(1 for k in keep if k['verdict']=='in order'):2d}")
json.dump(out, open("heldout_fwd.json", "w"), indent=1)
print("\nIN-ORDER CAUSAL MARK-SHAPED SENTENCES, for the blind screen:")
i = 0
for o in out:
    for k in o["cands"]:
        if k["verdict"] != "in order": continue
        i += 1; print(f"{i:2d}. [{o['stone'][:20]} {o['year']} | {k['section'][:20]} | {','.join(k['years'][:3])}] {k['text'][:230]}")
