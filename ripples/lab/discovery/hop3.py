import json, re, sys, random
from legacy import get, clean, sentences, plain, CONN
from legacy2 import mine
# a mark-shaped title: a legal or institutional form, not a first name or an award
MARKT = re.compile(r"\b(Act|Acts|Law|Laws|Regulation|Regulations|Directive|Commission|Agency|Administration|Ordinance|Statute|Amendment|Rule|Code|Treaty|Convention|Authority|Bureau|Department|Standards?|Reform Act|Ban|Protocol|Charter|Decree)\b")
NOT = re.compile(r"\b(Award|Awards|Emmy|Prize|Honor|Medal|Festival|School|University|College|Institute of Technology|Art Institute|Culinary)\b|^Bill\b", re.I)
def backlinks(title, cap=2000):
    out, cont = [], {}
    while True:
        d = get({"action": "query", "list": "backlinks", "bltitle": title, "blnamespace": 0, "bllimit": 500, "blredirect": 1, **cont})
        for b in d.get("query", {}).get("backlinks", []):
            out.append(b["title"]); out += [r["title"] for r in b.get("redirlinks", [])]
        if "continue" in d and len(out) < cap: cont = d["continue"]
        else: break
    return out
def names_stone(mark_title, names):
    d = get({"action": "parse", "page": mark_title, "prop": "wikitext", "redirects": 1})
    txt, _ = clean(d.get("parse", {}).get("wikitext", {}).get("*", "")); hits = []
    for sent in sentences(txt):
        low = sent.lower()
        if any(n.lower() in low for n in names): hits.append({"text": plain(sent)[:320], "causal": bool(CONN.search(sent)), "years": sorted(set(re.findall(r"\b(1[6-9]\d\d|20\d\d)\b", sent)))})
    return hits
def reverse(article, stone, cap_marks=14):
    bl = backlinks(article); marky = [t for t in dict.fromkeys(bl) if MARKT.search(t) and not NOT.search(t)][:cap_marks]
    names = {article, stone, re.sub(r"\s*\(.*\)$", "", article)}; names = {n for n in names if len(n) > 3}
    found = []
    for t in marky:
        h = names_stone(t, names)
        if h: found.append({"mark_article": t, "sentences": h[:3], "causal": any(x["causal"] for x in h)})
    return len(bl), marky, found
if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "recall":
        stones = json.load(open("stones_all.json")); own = json.load(open("legacy2_all.json")); res = {}
        for slug, st in stones.items():
            if not st["in_class"]: continue
            art = own.get(slug, {}).get("article") or st["article"]
            n, marky, found = reverse(art, st["stone"])
            res[slug] = {"article": art, "backlinks": n, "mark_titled": marky, "found": found}
            print(f"{slug:26s} | links {n:4d} | mark-titled {len(marky):2d} | name the stone {len(found):2d} causal {sum(f['causal'] for f in found):2d} | " + "; ".join(f["mark_article"][:30] for f in found[:5]))
        json.dump(res, open("hop3_recall.json", "w"), indent=1)
    elif mode == "decoys":
        random.seed(11); decoys = []
        for q in ['incategory:"2015 American films"', 'incategory:"2007 American films"', 'incategory:"2012 American television series debuts"']:
            d = get({"action": "query", "list": "search", "srsearch": q, "srlimit": 100, "srnamespace": 0})
            ms = [h["title"] for h in d.get("query", {}).get("search", []) if not h["title"].startswith("List of")]
            random.shuffle(ms); decoys += ms[:17]
        decoys = decoys[:50]; res = {}
        for t in decoys:
            real, cands = mine(t); causal = [c for c in (cands or []) if c["causal"]]
            n, marky, found = reverse(real or t, re.sub(r"\s*\(.*\)$", "", t), cap_marks=6)
            cf = [f for f in found if f["causal"]]
            res[t] = {"own_markish": len(cands or []), "own_causal": len(causal), "backlinks": n, "mark_titled": len(marky), "reverse_found": len(found), "reverse_causal": len(cf), "examples": [c["text"][:200] for c in causal[:2]] + [f["mark_article"] + ": " + f["sentences"][0]["text"][:160] for f in cf[:2]]}
            print(f"{t[:38]:38s} | own mark-shaped {len(cands or []):3d} causal {len(causal):2d} | links {n:4d} mark-titled {len(marky):2d} naming it {len(found)} causal {len(cf)}")
        json.dump(res, open("decoys.json", "w"), indent=1)
        print(f"\ndecoys yielding a candidate by the loose rule (any own causal mark-shaped sentence, or any mark article naming it): {sum(1 for r in res.values() if r['own_causal'] or r['reverse_found'])} of {len(res)}")
        print(f"decoys yielding a candidate by the strict rule (a mark-titled article names the decoy in a causal sentence): {sum(1 for r in res.values() if r['reverse_causal'])} of {len(res)}")
    elif mode == "namesake":
        for t in ["List of laws named after people", "List of legislation named for a person"]:
            d = get({"action": "parse", "page": t, "prop": "wikitext", "redirects": 1}); wt = d.get("parse", {}).get("wikitext", {}).get("*", "")
            open(re.sub(r"\W+", "_", t) + ".wikitext", "w").write(wt); print(t, "->", d.get("parse", {}).get("title"), len(wt), "bytes;", len(re.findall(r"^\*", wt, re.M)), "bullets;", len(re.findall(r"^\|-", wt, re.M)), "table rows")
