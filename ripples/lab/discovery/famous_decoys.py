"""Dev's ask: decoys that match the stones' fame. Fifty of the highest-grossing films of 2005 to 2024 with no mark the
builder knows of, chosen before the run, read with the culture lexicon (forward) and the strict reverse rule. The
number that matters is how many produce a candidate a screen would have to reject. Honest UA, one request a second."""
import json, re
from legacy2 import mine
from hop3 import backlinks, MARKT, NOT
from legacy import get, clean, sentences, plain, CONN
from order import mark_year
from culture import ENACT, BEHAV
FAMOUS = [("Transformers (film)", 2007), ("Pirates of the Caribbean: Dead Man's Chest", 2006), ("Shrek 2", 2004), ("Minions (film)", 2015), ("Fast & Furious 6", 2013), ("The Hangover", 2009), ("Mamma Mia! (film)", 2008), ("Despicable Me", 2010), ("Frozen II", 2019), ("Spider-Man 3", 2007), ("Jumanji: Welcome to the Jungle", 2017), ("Aquaman (film)", 2018), ("The Secret Life of Pets", 2016), ("Zootopia", 2016), ("Moana", 2016), ("Coco (2017 film)", 2017), ("Inside Out (2015 film)", 2015), ("Big Hero 6 (film)", 2014), ("The Lego Movie", 2014), ("Mission: Impossible – Fallout", 2018), ("Skyfall", 2012), ("Casino Royale (2006 film)", 2006), ("The Dark Knight", 2008), ("Iron Man (2008 film)", 2008), ("Deadpool (film)", 2016), ("Guardians of the Galaxy (film)", 2014), ("Wonder Woman (2017 film)", 2017), ("It (2017 film)", 2017), ("Gravity (2013 film)", 2013), ("Interstellar (film)", 2014), ("Inception", 2010), ("La La Land", 2016), ("Bohemian Rhapsody (film)", 2018), ("A Star Is Born (2018 film)", 2018), ("Joker (2019 film)", 2019), ("Dune (2021 film)", 2021), ("Top Gun: Maverick", 2022), ("Spider-Man: No Way Home", 2021), ("Avengers: Endgame", 2019), ("Avengers: Infinity War", 2018), ("The Super Mario Bros. Movie", 2023), ("Wicked (2024 film)", 2024), ("Inside Out 2", 2024), ("Deadpool & Wolverine", 2024), ("Moana 2", 2024), ("Elemental (film)", 2023), ("Lightyear (film)", 2022), ("Sing (2016 American film)", 2016), ("Ice Age: Dawn of the Dinosaurs", 2009), ("Madagascar: Escape 2 Africa", 2008)]
out = []
for article, year in FAMOUS:
    real, cands = mine(article, keep=BEHAV); cands = cands or []
    fwd = [c for c in cands if c["causal"] and (ENACT.search(c["text"]) or BEHAV.search(c["text"])) and not ([int(y) for y in c["years"]] and max(int(y) for y in c["years"]) < year)]
    bl = backlinks(real or article); marky = [t for t in dict.fromkeys(bl) if MARKT.search(t) and not NOT.search(t)][:8]
    names = {n for n in {article, real or "", re.sub(r"\s*\(.*\)$", "", article)} if len(n) > 3}; rev = []
    for t in marky:
        d = get({"action": "parse", "page": t, "prop": "wikitext", "redirects": 1}); txt, _ = clean(d.get("parse", {}).get("wikitext", {}).get("*", ""))
        dw = [w.lower() for w in re.findall(r"[A-Za-z][A-Za-z\-']{3,}", re.sub(r"\s*\(.*\)$", "", t)) if w.lower() not in ("united", "states", "national", "federal", "department")]
        for sent in sentences(txt):
            low = sent.lower()
            if any(n.lower() in low for n in names) and CONN.search(sent) and (not dw or any(w in low for w in dw)):
                my, how = mark_year(t)
                if my is not None and my < year: break
                rev.append({"mark": t, "mark_year": my, "text": plain(sent)[:260]}); break
    out.append({"stone": re.sub(r"\s*\(.*\)$", "", article), "year": year, "forward": [{"section": c["section"], "years": c["years"], "text": c["text"][:260]} for c in fwd], "reverse": rev})
    print(f"{article[:40]:40s} ({year}) | forward {len(fwd):2d} | reverse {len(rev)}")
    json.dump(out, open("famous_decoys.json", "w"), indent=1)
print("\nfamous decoys", len(out), "| with a forward candidate", sum(1 for o in out if o["forward"]), "| with a reverse pair", sum(1 for o in out if o["reverse"]))
