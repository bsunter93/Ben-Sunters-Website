import json, re, sys, time, urllib.parse, urllib.request
from legacy import get
OVERRIDE = {"tiger-king": "Tiger King", "cuyahoga-clean-water": "Cuyahoga River fire", "dust-bowl-soil": "Dust Bowl", "america-and-alcohol": "Prohibition in the United States", "planet-earth": "Planet Earth (2006 TV series)", "svb": "Collapse of Silicon Valley Bank", "gdpr": "General Data Protection Regulation", "tambora-bicycle": "1815 eruption of Mount Tambora", "triangle-shirtwaist": "Triangle Shirtwaist Factory fire", "flint-lead-pipes": "Flint water crisis"}
rec = json.load(open("../recall_set.json")); old = json.load(open("stones_recall.json")); out = {}
for slug, st in rec.items():
    title = st["title"]; stone = re.split(r",| and | → |\s\(", title)[0].strip()
    if slug in OVERRIDE: art = OVERRIDE[slug]
    elif slug in old and slug not in ("tiger-king",): art = old[slug]["article"]
    else:
        d = get({"action": "query", "list": "search", "srsearch": stone, "srlimit": 1})
        hits = d.get("query", {}).get("search", []); art = hits[0]["title"] if hits else None
    out[slug] = {"article": art, "stone": stone, "marks": st["marks"], "date": st["date"]}
    print(f"{slug:28s} | {stone[:40]:40s} -> {art}")
json.dump(out, open("stones_all.json", "w"), indent=1)
