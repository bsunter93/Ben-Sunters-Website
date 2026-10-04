"""The culture shelf into demo/discovered_wiki.json: behavior marks from culture.json, dated from the sentence or the
record, verified against the stone's article (and the mark's where one exists). One request a second, honest UA."""
import json, re
from legacy import get, clean
W = lambda t: "https://en.wikipedia.org/wiki/" + t.replace(" ", "_")
import re as _re
cult = {}
for o in json.load(open("culture.json")):
    for k in {o["article"], o["stone"], _re.sub(r"\s*\(.*\)$", "", o["article"])}: cult[k] = o
def sent(article, key):
    o = cult.get(article) or cult.get(re.sub(r"\s*\(.*\)$", "", article))
    for f in o["forward"]:
        if key.lower() in f["text"].lower(): return f["text"][:320], f["section"]
    raise KeyError(f"{article}: {key}")
def M(article, key, label, title, kind, date, prec, mark_article=None, grade=None, note=None):
    text, section = sent(article, key)
    m = {"label": label, "title": title, "kind": kind, "date": date, "precision": prec, "sentence": text, "source_label": f"Wikipedia: {article}, {section}", "source_url": W(article) + "#" + section.replace(" ", "_"), "found": "forward", "mark_url": W(mark_article) if mark_article else None, "mark_article": mark_article}
    if grade: m["grade"] = grade
    if note: m["note"] = note
    return m
new = {
 "frozen-culture": {"stone": "Frozen", "article": "Frozen (2013 film)", "date": "2013-11-27", "title": "Frozen → Norway tourism", "first": "Frozen opens", "marks": [
   M("Frozen (2013 film)", "added more tours of Norway", "Norway tours", "Tour operators add Norway tours to meet demand", "Behavior", "2014", "year")]},
 "game-of-thrones": {"stone": "Game of Thrones", "article": "Game of Thrones", "date": "2011-04-17", "title": "Game of Thrones → a sixth of Northern Ireland's tourists", "first": "Game of Thrones premieres", "marks": [
   M("Game of Thrones", "350,000 visitors", "Northern Ireland tourism", "A sixth of Northern Ireland's tourists come because of the series", "Behavior", "2019", "year")]},
 "finding-nemo": {"stone": "Finding Nemo", "article": "Finding Nemo", "date": "2003-05-30", "title": "Finding Nemo → demand for reef fish", "first": "Finding Nemo opens", "marks": [
   M("Finding Nemo", "Demand for tropical fish skyrocketed", "Demand for reef fish", "Demand for tropical aquarium fish rises after the film", "Behavior", "2003", "year", note="A 2019 Oxford study of sales after Finding Dory found no increase; the record states the Nemo rise and the Dory null side by side.")]},
 "101-dalmatians": {"stone": "101 Dalmatians", "article": "101 Dalmatians (1996 film)", "date": "1996-11-27", "title": "101 Dalmatians → a run on Dalmatian puppies", "first": "101 Dalmatians opens", "marks": [
   M("101 Dalmatians (1996 film)", "Dalmatian sales shot up", "Dalmatian sales", "Dalmatian puppy sales rise after the premiere", "Behavior", "1997", "year")]},
 "sideways": {"stone": "Sideways", "article": "Sideways (film)", "date": "2004-10-22", "title": "Sideways → less Merlot, more Pinot noir", "first": "Sideways opens", "marks": [
   M("Sideways (film)", "Merlot sales dropped 2%", "The Sideways effect", "Merlot sales fall and Pinot noir sales rise in the western United States", "Industry", "2005", "year", note="A 2022 study in the Journal of Wine Economics found the film reduced demand for Merlot and raised demand for Pinot noir.")]},
 "queens-gambit": {"stone": "The Queen's Gambit", "article": "The Queen's Gambit (miniseries)", "date": "2020-10-23", "title": "The Queen's Gambit → chess set sales", "first": "The Queen's Gambit premieres", "marks": [
   M("The Queen's Gambit (miniseries)", "Sales of chess sets rose", "Chess set sales", "Sales of chess sets rise sharply", "Industry", "2020", "year")]},
 "top-gun": {"stone": "Top Gun", "article": "Top Gun", "date": "1986-05-16", "title": "Top Gun → the Navy recruitment claim", "first": "Top Gun opens", "marks": [
   M("Top Gun", "went up by 500%", "The 500% recruitment claim", "The claim that naval aviator applications rose 500%", "Behavior", "1986", "year", grade="disputed", note="The article says the claim's accuracy has since been questioned; it is shown as disputed, not as a mark.")]},
 "pokemon-go": {"stone": "Pokémon Go", "article": "Pokémon Go", "date": "2016-07-06", "title": "Pokémon Go → a parole rule and a national ban", "first": "Pokémon Go launches", "marks": [
   M("Pokémon Go", "sex offenders are banned from using the application", "New York's parole rule", "New York bars sex offenders on parole from the app", "Law", "2016", "year"),
   M("Pokémon Go", "Supreme Council of Virtual Space in Iran", "Iran's ban", "Iran bans the game", "Policy", "2016-08", "month")]},
 "jurassic-park": {"stone": "Jurassic Park", "article": "Jurassic Park (film)", "date": "1993-06-11", "title": "Jurassic Park → the Toronto Raptors", "first": "Jurassic Park opens", "marks": [
   M("Jurassic Park (film)", "Toronto Raptors", "The Toronto Raptors' name", "An NBA franchise is named after the film's dinosaurs", "Institution", "1995", "year", "Toronto Raptors")]},
 "avatar-2009": {"stone": "Avatar", "article": "Avatar (2009 film)", "date": "2009-12-18", "title": "Avatar → 3D televisions", "first": "Avatar opens", "marks": [
   M("Avatar (2009 film)", "3D televisions", "3D televisions", "Electronics makers release 3D televisions", "Industry", "2010", "year")]},
 "fifty-shades": {"stone": "Fifty Shades of Grey", "article": "Fifty Shades of Grey", "date": "2011-06-20", "title": "Fifty Shades of Grey → a national ban", "first": "Fifty Shades of Grey is published", "marks": [
   M("Fifty Shades of Grey", "Malaysian Home Ministry banned", "Malaysia's ban", "Malaysia bans the books and the film", "Policy", "2015-02", "month")]},
 "da-vinci-code": {"stone": "The Da Vinci Code", "article": "The Da Vinci Code", "date": "2003-03-18", "title": "The Da Vinci Code → bans in seven Indian states", "first": "The Da Vinci Code is published", "marks": [
   M("The Da Vinci Code", "seven Indian states", "Indian state bans", "Seven Indian states ban the film adaptation", "Policy", "2006", "year")]},
 "mad-men": {"stone": "Mad Men", "article": "Mad Men", "date": "2007-07-19", "title": "Mad Men → the return of the suit", "first": "Mad Men premieres", "marks": [
   M("Mad Men", "revival in men's suits", "The suit revival", "A revival in men's suits in the show's style", "Industry", "2008", "year")]},
 "bake-off": {"stone": "The Great British Bake Off", "article": "The Great British Bake Off", "date": "2010-08-17", "title": "Bake Off → baking ingredient sales", "first": "The Great British Bake Off premieres", "marks": [
   M("The Great British Bake Off", "sharp rises in sales of bak", "Baking sales", "UK shops report sharp rises in sales of baking ingredients and equipment", "Industry", "2011", "year")]},
 "hamilton": {"stone": "Hamilton", "article": "Hamilton (musical)", "date": "2015-08-06", "title": "Hamilton → the Hamilton Education Program", "first": "Hamilton opens on Broadway", "marks": [
   M("Hamilton (musical)", "Hamilton Education Program was founded", "Hamilton Education Program", "The Hamilton Education Program is founded with Rockefeller Foundation funding", "Institution", "2016", "year")]},
 "furby": {"stone": "Furby", "article": "Furby", "date": "1998-10-02", "title": "Furby → banned by the NSA", "first": "Furby goes on sale", "marks": [
   M("Furby", "National Security Agency", "The NSA's Furby ban", "The NSA bans Furbies from its property", "Policy", "1999-01-13", "day")]},
 "tetris": {"stone": "Tetris", "article": "Tetris", "date": "1984-06-06", "title": "Tetris → The Tetris Company", "first": "Tetris is written in Moscow", "marks": [
   M("Tetris", "established the Tetris Company", "The Tetris Company", "The Tetris Company is established to hold the rights", "Institution", "1996", "year", "The Tetris Company")]},
 "zumba": {"stone": "Zumba", "article": "Zumba", "date": "2001-01-01", "title": "Zumba → banned in Iran", "first": "Zumba is founded", "marks": [
   M("Zumba", "banned in Iran", "Iran's ban", "Iran bans Zumba", "Policy", "2017-06", "month")]},
 "woodstock": {"stone": "Woodstock", "article": "Woodstock", "date": "1969-08-15", "title": "Woodstock → a museum town's economy", "first": "The Woodstock festival opens in Bethel", "marks": [
   M("Woodstock", "2.9", "Bethel Woods visitors", "Bethel Woods draws 2.9 million visitors and supports 172 jobs", "Industry", "2006", "year")]},
 "13-reasons-why": {"stone": "13 Reasons Why", "article": "13 Reasons Why", "date": "2017-03-31", "title": "13 Reasons Why → a rise in teen suicide the month after", "first": "13 Reasons Why is released", "marks": [
   M("13 Reasons Why", "suicide among teenagers rose", "Teen suicide study", "A JAACAP study finds teen suicide rose in the month after release", "Public health", "2017-04", "month", note="Later analyses disputed the size and attribution of the rise; the record is a published study, not a measured link in this product.")]},
 "blue-planet-ii": {"stone": "Blue Planet II", "article": "Blue Planet II", "date": "2017-10-29", "title": "Blue Planet II → marine biology applications and the plastics turn", "first": "Blue Planet II airs", "marks": [
   M("Blue Planet II", "applications for marine biology", "Marine biology applications", "British universities see a sudden rise in marine biology applications", "Education", "2018", "year"),
   M("Blue Planet II", "long-lasting increased political", "The plastics turn", "A 2020 study finds lasting political and public interest in plastic pollution in the UK", "Policy", "2020", "year")]},
 "emily-in-paris": {"stone": "Emily in Paris", "article": "Emily in Paris", "date": "2020-10-02", "title": "Emily in Paris → a reason to visit", "first": "Emily in Paris premieres", "marks": [
   M("Emily in Paris", "38% of tourists", "Paris tourism", "38% of surveyed tourists cite the series as a reason for visiting Paris", "Behavior", "2024", "year")]},
}
extra = {"an-inconvenient-truth": [M("An Inconvenient Truth", "Journal of Environmental Economics", "Carbon-offset purchases", "Carbon-offset purchases rise near theaters that showed the film", "Behavior", "2006", "year")]}
d = json.load(open("../site/ripples/demo/discovered_wiki.json"))
for slug, st in new.items(): d["stones"][slug] = st
for slug, ms in extra.items(): d["stones"][slug]["marks"] += ms
MONTHS = ["January","February","March","April","May","June","July","August","September","October","November","December"]; cache = {}
def text_of(t):
    if t not in cache:
        r = get({"action": "parse", "page": t, "prop": "wikitext", "redirects": 1}); cache[t] = clean(r.get("parse", {}).get("wikitext", {}).get("*", ""))[0]
    return cache[t]
flagged = []
for slug, st in d["stones"].items():
    for i, m in enumerate(st["marks"]):
        m["id"] = f"w{i}"
        if "verified" in m: continue
        arts = [a for a in [m.get("mark_article"), st["article"]] if a]
        y = m["date"][:4]; mon = MONTHS[int(m["date"][5:7]) - 1] if m["precision"] != "year" else None
        ok = any(y in text_of(a) and (mon is None or mon in text_of(a) or (mon[:3] + " ") in text_of(a)) for a in arts)
        m["verified"] = "year+month" if (ok and mon) else ("year" if ok else "unverified")
        if not ok: flagged.append((slug, m["label"], m["date"]))
        print(f"{slug[:20]:20s} {m['label'][:34]:34s} {m['date']:10s} {m['precision']:5s} {'ok' if ok else '<-- CHECK'}")
json.dump(d, open("../site/ripples/demo/discovered_wiki.json", "w"), indent=1, ensure_ascii=False)
print("\nstones", len(d["stones"]), "marks", sum(len(s["marks"]) for s in d["stones"].values()), "flagged", len(flagged)); [print("  ", f) for f in flagged]
