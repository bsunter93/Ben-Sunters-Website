"""Discovery v1.1 over sixty more stones (events, disasters, works), fixed before the run: forward and reverse readings,
and a sentence counts only if it names an enacted or established thing (passed, enacted, signed, established, founded,
created, ruled, banned, adopted, formed, set up) with a year at or after the stone. Honest UA, one request a second."""
import json, re
from legacy2 import mine
from hop3 import backlinks, MARKT, NOT
from legacy import get, clean, sentences, plain, CONN
from order import mark_year
ENACT = re.compile(r"\b(passed|enacted|signed into law|signed|established|founded|created|ruled|banned|adopted|formed|set up|launched|introduced and passed|became law|royal assent|ratified|instituted|mandated|required)\b", re.I)
STONES = [("Hurricane Sandy", 2012), ("September 11 attacks", 2001), ("Chernobyl disaster", 1986), ("Bhopal disaster", 1984), ("Challenger disaster", "Space Shuttle Challenger disaster", 1986), ("Columbia disaster", "Space Shuttle Columbia disaster", 2003), ("Hillsborough disaster", 1989), ("Grenfell Tower fire", 2017), ("Rana Plaza collapse", "2013 Dhaka garment factory collapse", 2013), ("Enron scandal", 2001), ("Theranos", 2003), ("Cambridge Analytica", "Facebook–Cambridge Analytica data scandal", 2018), ("Boston Marathon bombing", 2013), ("Oklahoma City bombing", 1995), ("Virginia Tech shooting", 2007), ("Parkland shooting", "Parkland high school shooting", 2018), ("Uvalde shooting", "Robb Elementary School shooting", 2022), ("Pulse nightclub shooting", 2016), ("Las Vegas shooting", "2017 Las Vegas shooting", 2017), ("Ferguson unrest", 2014), ("Murder of George Floyd", 2020), ("Me Too movement", "MeToo movement", 2017), ("Harvey Weinstein sexual abuse cases", 2017), ("Jeffrey Epstein", 2019), ("Flint", "Flint water crisis", 2014), ("Camp Fire", "Camp Fire (2018)", 2018), ("Lac-Mégantic rail disaster", 2013), ("Costa Concordia disaster", 2012), ("Germanwings Flight 9525", 2015), ("Boeing 737 MAX groundings", 2019), ("Takata airbag recall", "Takata Corporation", 2014), ("Volkswagen emissions scandal", 2015), ("Dieselgate", "Volkswagen emissions scandal", 2015), ("Equifax data breach", "2017 Equifax data breach", 2017), ("Target data breach", "Target Corporation", 2013), ("Snowden leaks", "Global surveillance disclosures (2013–present)", 2013), ("WikiLeaks Iraq War logs", "Iraq War documents leak", 2010), ("Panama Papers", 2016), ("Lehman Brothers collapse", "Bankruptcy of Lehman Brothers", 2008), ("Madoff fraud", "Madoff investment scandal", 2008), ("Love Canal", 1978), ("Jaws", "Jaws (film)", 1975), ("Bowling for Columbine", 2002), ("The Cove", "The Cove (film)", 2009), ("Food, Inc.", 2008), ("Gasland", 2010), ("The Thin Blue Line", "The Thin Blue Line (1988 film)", 1988), ("Paradise Lost", "Paradise Lost: The Child Murders at Robin Hood Hills", 1996), ("Dear Zachary", "Dear Zachary: A Letter to a Son About His Father", 2008), ("Leaving Neverland", 2019), ("Surviving R. Kelly", 2019), ("The Jinx", "The Jinx: The Life and Deaths of Robert Durst", 2015), ("Making a Murderer", 2015), ("Cathy Come Home", 1966), ("Philadelphia", "Philadelphia (film)", 1993), ("Schindler's List", 1993), ("Hotel Rwanda", 2004), ("Kony 2012", 2012), ("Super Size Me", 2004), ("Sicko", 2007)]
def norm(e): return (e[0], e[1], e[2]) if len(e) == 3 else (e[0], e[0], e[1])
out = []
for stone, article, year in map(norm, STONES):
    real, cands = mine(article); cands = cands or []
    fwd = []
    for c in cands:
        if not (c["causal"] and ENACT.search(c["text"])): continue
        ys = [int(y) for y in c["years"]]
        if ys and max(ys) < year: continue
        fwd.append({"section": c["section"], "years": c["years"], "text": c["text"][:300]})
    bl = backlinks(real or article); marky = [t for t in dict.fromkeys(bl) if MARKT.search(t) and not NOT.search(t)][:12]
    names = {n for n in {article, stone, real or "", re.sub(r"\s*\(.*\)$", "", article)} if len(n) > 3}
    rev = []
    for t in marky:
        d = get({"action": "parse", "page": t, "prop": "wikitext", "redirects": 1}); txt, _ = clean(d.get("parse", {}).get("wikitext", {}).get("*", ""))
        dw = [w.lower() for w in re.findall(r"[A-Za-z][A-Za-z\-']{3,}", re.sub(r"\s*\(.*\)$", "", t)) if w.lower() not in ("united", "states", "national", "federal", "department")]
        for sent in sentences(txt):
            low = sent.lower()
            if any(n.lower() in low for n in names) and CONN.search(sent) and (not dw or any(w in low for w in dw)):
                my, how = mark_year(t)
                if my is not None and my < year: break
                rev.append({"mark": t, "mark_year": my, "how": how, "text": plain(sent)[:300]}); break
    out.append({"stone": stone, "article": real or article, "year": year, "forward": fwd, "reverse": rev})
    print(f"{stone[:26]:26s} ({year}) | forward {len(fwd):2d} | reverse {len(rev)} | " + "; ".join(r["mark"][:34] for r in rev[:3]))
    json.dump(out, open("wider.json", "w"), indent=1)
print("\nstones", len(out), "forward sentences", sum(len(o["forward"]) for o in out), "reverse pairs", sum(len(o["reverse"]) for o in out))
