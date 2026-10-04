"""Date each strict pair's mark from the lead of its article (the earliest year in the lead at or after 1700, or an
infobox enacted/formed/date field), apply the ordering rule against the stone's date, print the survivors with their sentence."""
import json, re
from legacy import get, clean, plain
hop = json.load(open("hop3_recall.json")); stones = json.load(open("stones_all.json"))
NOISE = re.compile(r"^(List of|Law & Order|Code to Zero|Let Rock Rule)", re.I)
def mark_year(title):
    t = re.search(r"\b(1[7-9]\d\d|20\d\d)\b", title)
    if t: return int(t.group(1)), "title"
    d = get({"action": "parse", "page": title, "prop": "wikitext", "section": 0, "redirects": 1})
    wt = d.get("parse", {}).get("wikitext", {}).get("*", "")
    m = re.search(r"\|\s*(enacted|date_enacted|date_signed|signed|royal_assent|date_of_royal_assent|ratified|date_ratified|adopted|date_adopted|formed|founded|established|date_established|effective|date_effective|date_passed|passed|formation|date_formed|inception|start_date|created|date_created|opened|date_opened)\s*=\s*[^\n]*?(1[7-9]\d\d|20\d\d)", wt, re.I)
    if m: return int(m.group(2)), "infobox"
    txt, _ = clean(wt); ys = [int(y) for y in re.findall(r"\b(1[7-9]\d\d|20\d\d)\b", txt[:1500])]
    return (min(ys), "lead") if ys else (None, "none")
out = []
for slug, h in hop.items():
    sd = stones[slug]["date"]; sy = int(sd[:4]) if sd else None
    for f in h.get("found", []):
        if not f["causal"] or NOISE.search(f["mark_article"]): continue
        my, how = mark_year(f["mark_article"])
        verdict = "undated" if my is None or sy is None else ("busted: before the stone" if my < sy else "in order")
        sent = next((s for s in f["sentences"] if s["causal"]), f["sentences"][0])
        out.append({"slug": slug, "stone": stones[slug]["stone"], "stone_year": sy, "mark": f["mark_article"], "mark_year": my, "how": how, "verdict": verdict, "sentence": sent["text"][:260]})
json.dump(out, open("strict_pairs.json", "w"), indent=1)
from collections import Counter; print(Counter(o["verdict"] for o in out))
print("\nIN ORDER:")
for o in out:
    if o["verdict"] == "in order": print(f"  {o['stone'][:22]:22s} ({o['stone_year']}) -> {o['mark'][:52]:52s} ({o['mark_year']}, {o['how']})\n      {o['sentence'][:200]}")
print("\nBUSTED (predecessors):"); [print(f"  {o['stone'][:22]:22s} ({o['stone_year']}) -> {o['mark'][:50]} ({o['mark_year']})") for o in out if o["verdict"].startswith("busted")]
print("\nUNDATED:"); [print(f"  {o['stone'][:22]:22s} -> {o['mark'][:50]}") for o in out if o["verdict"] == "undated"]
