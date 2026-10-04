"""The culture shelf: recognizable cultural stones, chosen before the run, read forward only with a behavior lexicon beside
the law lexicon. A sentence counts if it has a causal connective, and an enacted-thing word or a behavior word, and no
year earlier than the stone. Honest UA, one request a second."""
import json, re
from legacy2 import mine
ENACT = re.compile(r"\b(passed|enacted|signed into law|established|founded|created|ruled|banned|adopted|formed|set up|became law|royal assent|ratified|mandated|required|renamed|discontinued|dropped|removed from)\b", re.I)
BEHAV = re.compile(r"\b(sales|sold|demand|tourism|tourists|visitors|visitation|recruitment|recruits|enlistment|enrollment|enrolment|adoptions?|abandon(ed|ment)|baby names?|popularity|searches|boom|surge|shortage|revived|revival|charted|membership|attendance|bookings|orders|ratings|streams|downloads|subscriptions|increase[d]?|decline[d]?|fell|rose|doubled|tripled|quadrupled|spike[d]?|jumped)\b", re.I)
exec(open("culture_stones.py").read())  # STONES = [(article, year), ...]
out = []
for article, year in STONES:
    real, cands = mine(article, keep=BEHAV); cands = cands or []
    keep = []
    for c in cands:
        if not c["causal"]: continue
        if not (ENACT.search(c["text"]) or BEHAV.search(c["text"])): continue
        ys = [int(y) for y in c["years"]]
        if ys and max(ys) < year: continue
        keep.append({"section": c["section"], "years": c["years"], "text": c["text"][:300], "law": bool(ENACT.search(c["text"])), "behavior": bool(BEHAV.search(c["text"]))})
    out.append({"stone": re.sub(r"\s*\(.*\)$", "", article), "article": real or article, "year": year, "forward": keep})
    print(f"{article[:34]:34s} ({year}) | kept {len(keep):2d} | behavior {sum(k['behavior'] for k in keep):2d} law {sum(k['law'] for k in keep):2d}")
    json.dump(out, open("culture.json", "w"), indent=1)
print("\nstones", len(out), "sentences", sum(len(o["forward"]) for o in out))
