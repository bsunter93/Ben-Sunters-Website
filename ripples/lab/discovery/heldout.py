"""Held-out test of the refined strict rule on 20 stones the catalog has never touched. The refinement, fixed before this
run and after the first screen (disclosed): the causal sentence in the mark's article must name the stone AND a
distinctive word of the mark's own title, so a sentence about some other thing in that article does not count.
Stone dates are given by hand (release or event year). Honest UA, one request a second."""
import json, re
from hop3 import backlinks, MARKT, NOT
from legacy import get, clean, sentences, plain, CONN
from order import mark_year
STONES = [("Blackfish (film)", "Blackfish", 2013), ("Super Size Me", "Super Size Me", 2004), ("An Inconvenient Truth", "An Inconvenient Truth", 2006), ("The Day After", "The Day After", 1983), ("Jaws (film)", "Jaws", 1975), ("Roots (1977 miniseries)", "Roots", 1977), ("Erin Brockovich (film)", "Erin Brockovich", 2000), ("Spotlight (film)", "Spotlight", 2015), ("13 Reasons Why", "13 Reasons Why", 2017), ("Making a Murderer", "Making a Murderer", 2015), ("The Social Dilemma", "The Social Dilemma", 2020), ("Hurricane Katrina", "Hurricane Katrina", 2005), ("Deepwater Horizon oil spill", "Deepwater Horizon", 2010), ("Sandy Hook Elementary School shooting", "Sandy Hook", 2012), ("Chernobyl (miniseries)", "Chernobyl (miniseries)", 2019), ("Fast Food Nation", "Fast Food Nation", 2001), ("Blood Diamond (film)", "Blood Diamond", 2006), ("The China Syndrome", "The China Syndrome", 1979), ("Cosmos: A Personal Voyage", "Cosmos", 1980), ("Philadelphia (film)", "Philadelphia", 1993)]
STOP = set("the a an of and in on to for by with act law bill united states national federal".split())
def distinct(title): return [w for w in re.findall(r"[A-Za-z][A-Za-z\-']+", re.sub(r"\s*\(.*\)$", "", title)) if w.lower() not in STOP and len(w) > 3]
out = []
for article, stone, year in STONES:
    bl = backlinks(article); marky = [t for t in dict.fromkeys(bl) if MARKT.search(t) and not NOT.search(t)][:14]
    names = {n for n in {article, stone, re.sub(r"\s*\(.*\)$", "", article)} if len(n) > 3}
    found = []
    for t in marky:
        d = get({"action": "parse", "page": t, "prop": "wikitext", "redirects": 1}); txt, _ = clean(d.get("parse", {}).get("wikitext", {}).get("*", ""))
        dw = [w.lower() for w in distinct(t)]
        for sent in sentences(txt):
            low = sent.lower()
            if any(n.lower() in low for n in names) and CONN.search(sent) and (not dw or any(w in low for w in dw)):
                my, how = mark_year(t); verdict = "undated" if my is None else ("busted: before the stone" if my < year else "in order")
                found.append({"mark": t, "mark_year": my, "how": how, "verdict": verdict, "sentence": plain(sent)[:260]}); break
    out.append({"stone": stone, "article": article, "year": year, "backlinks": len(bl), "mark_titled": len(marky), "pairs": found})
    print(f"{stone[:24]:24s} ({year}) | links {len(bl):4d} | mark-titled {len(marky):2d} | pairs {len(found)} | " + "; ".join(f"{f['mark'][:36]} [{f['verdict'][:6]}]" for f in found))
json.dump(out, open("heldout.json", "w"), indent=1)
pairs = [(o["stone"], o["year"], f) for o in out for f in o["pairs"]]
print(f"\npairs {len(pairs)}: in order {sum(1 for *_, f in pairs if f['verdict']=='in order')}, busted {sum(1 for *_, f in pairs if f['verdict'].startswith('busted'))}, undated {sum(1 for *_, f in pairs if f['verdict']=='undated')}")
print("\nIN ORDER, for the blind screen:")
for i, (s, y, f) in enumerate([p for p in pairs if p[2]["verdict"] == "in order"], 1): print(f"{i:2d}. {s[:22]:22s} ({y}) -> {f['mark'][:55]} ({f['mark_year']}, {f['how']})\n    {f['sentence'][:240]}")
