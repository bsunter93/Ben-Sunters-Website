"""Extend demo/discovered_wiki.json with the screened survivors of the sixty-stone v1.1 run. Sentences are pulled from
wider.json by a key phrase so the evidence is the engine's own text; each date is verified against the article's text."""
import json, re
from legacy import get, clean
W = lambda t: "https://en.wikipedia.org/wiki/" + t.replace(" ", "_")
wider = {o["stone"]: o for o in json.load(open("wider.json"))}
def sent(stone, key):
    o = wider[stone]
    for f in o["forward"]:
        if key.lower() in f["text"].lower(): return f["text"][:320], f["section"]
    for r in o["reverse"]:
        if key.lower() in r["text"].lower(): return r["text"][:320], None
    raise KeyError(f"{stone}: {key}")
def M(stone, key, label, title, kind, date, prec, mark_article, src_article, found="forward"):
    text, section = sent(stone, key)
    src = src_article if found == "forward" else (mark_article or src_article)
    return {"label": label, "title": title, "kind": kind, "date": date, "precision": prec, "sentence": text, "source_label": f"Wikipedia: {src}" + (f", {section}" if section and found == "forward" else ""), "source_url": W(src) + (("#" + section.replace(" ", "_")) if section and found == "forward" else ""), "found": found, "mark_url": W(mark_article) if mark_article else None, "mark_article": mark_article}
A = "September 11 attacks"
new = {
 "september-11": {"stone": "September 11", "article": A, "date": "2001-09-11", "title": "September 11 → eight laws and institutions on three continents", "first": "The September 11 attacks", "marks": [
   M(A, "Victim Compensation Fund was created", "9/11 Victim Compensation Fund", "Congress creates the September 11th Victim Compensation Fund", "Institution", "2001-09-22", "day", "September 11th Victim Compensation Fund", A),
   M(A, "Patriot Act was enacted", "Patriot Act", "The Patriot Act is signed", "Law", "2001-10-26", "day", "Patriot Act", A, "reverse"),
   M(A, "Transportation Security Administration", "TSA", "The Aviation and Transportation Security Act creates the TSA", "Institution", "2001-11-19", "day", "Transportation Security Administration", A),
   M(A, "Anti-terrorism, Crime and Security Act 2001", "UK Anti-terrorism, Crime and Security Act", "The United Kingdom passes the Anti-terrorism, Crime and Security Act 2001", "Law", "2001-12-14", "day", "Anti-terrorism, Crime and Security Act 2001", A),
   M(A, "Canadian Anti-Terrorism Act", "Canada's Anti-terrorism Act", "Canada passes its first anti-terrorism law", "Law", "2001-12-18", "day", "Anti-terrorism Act (Canada)", A),
   M(A, "Terrorism Suppression Act 2002", "New Zealand's Terrorism Suppression Act", "New Zealand enacts the Terrorism Suppression Act 2002", "Law", "2002-10-17", "day", "Terrorism Suppression Act 2002", A),
   M(A, "Department of Homeland Security was created", "Department of Homeland Security", "The Homeland Security Act creates the Department of Homeland Security", "Institution", "2002-11-25", "day", "Homeland Security Act", A),
   M(A, "Justice Against Sponsors of Terrorism Act that would", "JASTA", "Congress passes the Justice Against Sponsors of Terrorism Act over a veto", "Law", "2016-09-28", "day", "Justice Against Sponsors of Terrorism Act", A)]},
 "chernobyl-disaster": {"stone": "Chernobyl", "article": "Chernobyl disaster", "date": "1986-04-26", "title": "Chernobyl → two conventions, two funds and a charity", "first": "Reactor 4 at Chernobyl explodes", "marks": [
   M("Chernobyl disaster", "Convention on Early Notification", "Early Notification Convention", "The IAEA adopts the Convention on Early Notification of a Nuclear Accident", "Treaty", "1986-09-26", "day", "Convention on Early Notification of a Nuclear Accident", "Chernobyl disaster"),
   M("Chernobyl disaster", "Chernobyl Trust Fund was created in 1991", "UN Chernobyl Trust Fund", "The United Nations creates the Chernobyl Trust Fund", "Institution", "1991", "year", None, "Chernobyl disaster"),
   M("Chernobyl disaster", "Chernobyl Children International", "Chernobyl Children International", "Chernobyl Children International is founded", "Institution", "1991", "year", "Chernobyl Children International", "Chernobyl disaster"),
   M("Chernobyl disaster", "Chernobyl Shelter Fund was established in 1997", "Chernobyl Shelter Fund", "The G8 establishes the Chernobyl Shelter Fund", "Institution", "1997", "year", None, "Chernobyl disaster"),
   M("Chernobyl disaster", "Joint Convention on the Safety of Spent Fuel", "Joint Convention", "The Joint Convention on the Safety of Spent Fuel Management is adopted", "Treaty", "1997-09-05", "day", "Joint Convention on the Safety of Spent Fuel Management and on the Safety of Radioactive Waste Management", "Chernobyl disaster")]},
 "bhopal": {"stone": "Bhopal", "article": "Bhopal disaster", "date": "1984-12-03", "title": "Bhopal → an Act and a medical commission", "first": "The Bhopal gas leak", "marks": [
   M("Bhopal disaster", "Bhopal Gas Leak Act in March 1985", "Bhopal Gas Leak Disaster Act", "India passes the Bhopal Gas Leak Disaster Act", "Law", "1985-03", "month", None, "Bhopal disaster"),
   M("Bhopal disaster", "International Medical Commission on Bhopal", "International Medical Commission on Bhopal", "The International Medical Commission on Bhopal is established", "Institution", "1993", "year", "International Medical Commission on Bhopal", "Bhopal disaster", "reverse")]},
 "challenger": {"stone": "Challenger", "article": "Space Shuttle Challenger disaster", "date": "1986-01-28", "title": "Challenger → a commission, a safety office and a center", "first": "The Space Shuttle Challenger breaks apart", "marks": [
   M("Challenger disaster", "created the Rogers Commission", "Rogers Commission", "President Reagan creates the Rogers Commission", "Institution", "1986-02-03", "day", "Rogers Commission Report", "Space Shuttle Challenger disaster"),
   M("Challenger disaster", "Challenger Center for Space Science Education", "Challenger Center", "The crew's families found the Challenger Center for Space Science Education", "Institution", "1986", "year", "Challenger Center for Space Science Education", "Space Shuttle Challenger disaster"),
   M("Challenger disaster", "In 1986 NASA created a new Office of Safety", "NASA Office of Safety", "NASA creates the Office of Safety, Reliability, and Quality Assurance", "Institution", "1986", "year", None, "Space Shuttle Challenger disaster")]},
 "rana-plaza": {"stone": "Rana Plaza", "article": "2013 Dhaka garment factory collapse", "date": "2013-04-24", "title": "Rana Plaza → the Accord and a factory-inspection law", "first": "The Rana Plaza building collapses", "marks": [
   M("Rana Plaza collapse", "Accord on Fire and Building Safety in Bangladesh", "The Bangladesh Accord", "The Accord on Fire and Building Safety in Bangladesh is signed", "Policy", "2013-05", "month", "Accord on Fire and Building Safety in Bangladesh", "2013 Dhaka garment factory collapse"),
   M("Rana Plaza collapse", "government passed new laws requiring all garment factories", "Factory-inspection law", "Bangladesh passes laws requiring every garment factory to be inspected", "Law", "2013", "year", None, "2013 Dhaka garment factory collapse")]},
 "oklahoma-city": {"stone": "The Oklahoma City bombing", "article": "Oklahoma City bombing", "date": "1995-04-19", "title": "Oklahoma City → two federal laws", "first": "The Oklahoma City bombing", "marks": [
   M("Oklahoma City bombing", "Antiterrorism and Effective Death Penalty Act of 1996, which limited", "AEDPA", "The Antiterrorism and Effective Death Penalty Act is signed", "Law", "1996-04-24", "day", "Antiterrorism and Effective Death Penalty Act of 1996", "Oklahoma City bombing"),
   M("Oklahoma City bombing", "Victim Allocution Clarification Act", "Victim Allocution Clarification Act", "The Victim Allocution Clarification Act is signed", "Law", "1997-03-20", "day", None, "Oklahoma City bombing")]},
 "virginia-tech": {"stone": "The Virginia Tech shooting", "article": "Virginia Tech shooting", "date": "2007-04-16", "title": "Virginia Tech → the NICS Improvement Amendments Act", "first": "The Virginia Tech shooting", "marks": [
   M("Virginia Tech shooting", "NICS Improvement Amendments Act", "NICS Improvement Amendments Act", "The NICS Improvement Amendments Act is signed", "Law", "2008-01-08", "day", "NICS Improvement Amendments Act of 2007", "Virginia Tech shooting", "reverse")]},
 "parkland": {"stone": "Parkland", "article": "Parkland high school shooting", "date": "2018-02-14", "title": "Parkland → a state law, a federal law, a movement and a death-penalty change", "first": "The Parkland high school shooting", "marks": [
   M("Parkland shooting", "founded Never Again MSD", "Never Again MSD", "Students found Never Again MSD", "Institution", "2018-02", "month", "Never Again MSD", "Parkland high school shooting"),
   M("Parkland shooting", "Marjory Stoneman Douglas High School Public Safety Act", "Florida's MSD Public Safety Act", "Florida passes the Marjory Stoneman Douglas High School Public Safety Act", "Law", "2018-03-09", "day", "Marjory Stoneman Douglas High School Public Safety Act", "Parkland high school shooting"),
   M("Parkland shooting", "STOP School Violence Act was signed", "STOP School Violence Act", "The STOP School Violence Act is signed", "Law", "2018-03-23", "day", "STOP School Violence Act", "Parkland high school shooting"),
   M("Parkland shooting", "unanimity required to impose the death penalty has since been overturned by a bill signed by Governor Ron DeSantis", "Florida's death-penalty unanimity repeal", "Florida ends the unanimity requirement for a death sentence", "Law", "2023-04-20", "day", None, "Parkland high school shooting")]},
 "uvalde": {"stone": "Uvalde", "article": "Robb Elementary School shooting", "date": "2022-05-24", "title": "Uvalde → a federal law and three state laws", "first": "The Robb Elementary School shooting", "marks": [
   M("Uvalde shooting", "New York passed a new law raising the age", "New York's age-21 law", "New York raises the age to buy semi-automatic rifles to 21", "Law", "2022-06-06", "day", None, "Robb Elementary School shooting"),
   M("Uvalde shooting", "House of Representatives passed the Bipartisan Safer Communities Act", "Bipartisan Safer Communities Act", "The Bipartisan Safer Communities Act is signed", "Law", "2022-06-25", "day", "Bipartisan Safer Communities Act", "Robb Elementary School shooting"),
   M("Uvalde shooting", "Texas passed a law requiring members of law enforcement", "Texas training law", "Texas requires school-shooting response training for police", "Law", "2023-05-19", "day", None, "Robb Elementary School shooting"),
   M("Uvalde shooting", "signing by Governor Abbot on June 14, 2023", "Texas HB 3", "Texas signs House Bill 3, armed security at every school", "Law", "2023-06-14", "day", None, "Robb Elementary School shooting")]},
 "boston-marathon": {"stone": "The Boston Marathon bombing", "article": "Boston Marathon bombing", "date": "2013-04-15", "title": "Boston Marathon → a fund and a civic holiday", "first": "The Boston Marathon bombing", "marks": [
   M("Boston Marathon bombing", "One Fund Boston was established", "One Fund Boston", "The governor and the mayor establish One Fund Boston", "Institution", "2013-04", "month", "One Fund Boston", "Boston Marathon bombing"),
   M("Boston Marathon bombing", "One Boston Day", "One Boston Day", "Boston makes April 15 a permanent civic holiday, One Boston Day", "Policy", "2015-04-15", "day", None, "Boston Marathon bombing")]},
 "pulse": {"stone": "The Pulse shooting", "article": "Pulse nightclub shooting", "date": "2016-06-12", "title": "Pulse → a fund and a foundation", "first": "The Pulse nightclub shooting", "marks": [
   M("Pulse nightclub shooting", "OneOrlando, was established", "OneOrlando Fund", "The mayor establishes the OneOrlando fund", "Institution", "2016-06", "month", None, "Pulse nightclub shooting"),
   M("Pulse nightclub shooting", "created the OnePulse Foundation", "OnePulse Foundation", "The nightclub's owner creates the OnePulse Foundation", "Institution", "2016", "year", "OnePulse Foundation", "Pulse nightclub shooting")]},
 "las-vegas-2017": {"stone": "The Las Vegas shooting", "article": "2017 Las Vegas shooting", "date": "2017-10-01", "title": "Las Vegas → the bump-stock ban", "first": "The Las Vegas shooting", "marks": [
   M("Las Vegas shooting", "regulation banned new sales", "Bump-stock ban", "The Justice Department's rule bans bump stocks", "Regulation", "2018-12-18", "day", "Bump stock", "2017 Las Vegas shooting")]},
 "enron": {"stone": "Enron", "article": "Enron scandal", "date": "2001-10-16", "title": "Enron → a tax-code section and a British audit law", "first": "Enron restates its earnings", "marks": [
   M("Enron scandal", "Section 409A was enacted", "Tax code section 409A", "Congress enacts Section 409A on deferred compensation", "Law", "2004-10-22", "day", "Internal Revenue Code section 409A", "Enron scandal", "reverse"),
   M("Enron scandal", "Final Report of the Co-ordinating Group on Audit", "UK Companies (Audit, Investigations and Community Enterprise) Act", "The United Kingdom passes the Companies (Audit, Investigations and Community Enterprise) Act 2004", "Law", "2004-10-28", "day", "Companies (Audit, Investigations and Community Enterprise) Act 2004", "Enron scandal", "reverse")]},
 "cambridge-analytica": {"stone": "Cambridge Analytica", "article": "Facebook–Cambridge Analytica data scandal", "date": "2018-03-17", "title": "Cambridge Analytica → Social Science One", "first": "The Cambridge Analytica story breaks", "marks": [
   M("Cambridge Analytica", "established Social Science One", "Social Science One", "Facebook establishes Social Science One", "Institution", "2018-04", "month", "Social Science One", "Facebook–Cambridge Analytica data scandal")]},
 "metoo": {"stone": "MeToo", "article": "MeToo movement", "date": "2017-10-15", "title": "MeToo → Indonesia's Sexual Violence Crime Act", "first": "The MeToo hashtag spreads", "marks": [
   M("Me Too movement", "ratification of the PKS Bill", "Indonesia's Sexual Violence Crime Act", "Indonesia passes the Sexual Violence Crime Act", "Law", "2022-04-12", "day", "Sexual Violence Crime Act", "MeToo movement", "reverse")]},
 "camp-fire": {"stone": "The Camp Fire", "article": "Camp Fire (2018)", "date": "2018-11-08", "title": "The Camp Fire → an ordinance, a wildfire fund and a victims' trust", "first": "The Camp Fire ignites in Butte County", "marks": [
   M("Camp Fire", "emergency ordinance to prohibit price gouging", "Chico's price-gouging ordinance", "Chico passes an emergency ordinance against price gouging", "Law", "2018-11-16", "day", None, "Camp Fire (2018)"),
   M("Camp Fire", "wildfire insurance fund established by AB", "California's wildfire fund (AB 1054)", "California establishes a wildfire insurance fund under AB 1054", "Law", "2019-07-12", "day", None, "Camp Fire (2018)"),
   M("Camp Fire", "Fire Victim Trust (FVT) was established", "PG&E Fire Victim Trust", "The PG&E Fire Victim Trust is established", "Institution", "2020-07-01", "day", None, "Camp Fire (2018)")]},
 "lac-megantic": {"stone": "Lac-Mégantic", "article": "Lac-Mégantic rail disaster", "date": "2013-07-06", "title": "Lac-Mégantic → a federal emergency order on unattended trains", "first": "A runaway oil train derails in Lac-Mégantic", "marks": [
   M("Lac-Mégantic rail disaster", "Emergency Order establishing additional requirements", "FRA Emergency Order 28", "The Federal Railroad Administration orders new rules for unattended trains", "Regulation", "2013-08-02", "day", None, "Lac-Mégantic rail disaster")]},
 "volkswagen": {"stone": "Dieselgate", "article": "Volkswagen emissions scandal", "date": "2015-09-18", "title": "Dieselgate → a national sales ban", "first": "The EPA issues Volkswagen a notice of violation", "marks": [
   M("Volkswagen emissions scandal", "Switzerland banned sales", "Switzerland's sales ban", "Switzerland bans sales of Volkswagen diesel cars", "Regulation", "2015-09-26", "day", None, "Volkswagen emissions scandal")]},
 "dear-zachary": {"stone": "Dear Zachary", "article": "Dear Zachary: A Letter to a Son About His Father", "date": "2008-10-31", "title": "Dear Zachary → Canada's Bill C-464", "first": "Dear Zachary is released", "marks": [
   M("Dear Zachary", "signed into law on December 16", "Bill C-464", "Canada's Bill C-464 on bail and the protection of children receives royal assent", "Law", "2010-12-16", "day", None, "Dear Zachary: A Letter to a Son About His Father")]},
 "grenfell": {"stone": "Grenfell", "article": "Grenfell Tower fire", "date": "2017-06-14", "title": "Grenfell → a memorial commission", "first": "The Grenfell Tower fire", "marks": [
   M("Grenfell Tower fire", "Grenfell Tower Memorial Commission, established in 2018", "Grenfell Tower Memorial Commission", "The Grenfell Tower Memorial Commission is established", "Institution", "2018", "year", None, "Grenfell Tower fire")]},
 "hurricane-sandy": {"stone": "Hurricane Sandy", "article": "Hurricane Sandy", "date": "2012-10-29", "title": "Hurricane Sandy → the $50 billion aid law", "first": "Hurricane Sandy makes landfall", "marks": [
   M("Hurricane Sandy", "signed into law January 29", "Sandy aid law", "The Disaster Relief Appropriations Act is signed", "Law", "2013-01-29", "day", "Disaster Relief Appropriations Act, 2013", "Hurricane Sandy")]},
 "cathy-come-home": {"stone": "Cathy Come Home", "article": "Cathy Come Home", "date": "1966-11-16", "title": "Cathy Come Home → the charity Crisis", "first": "The BBC broadcasts Cathy Come Home", "marks": [
   M("Cathy Come Home", "the charity Crisis was f", "Crisis", "The charity Crisis is formed", "Institution", "1967", "year", "Crisis (charity)", "Cathy Come Home")]},
}
extra = {  # marks added to stones already in the file
 "flint-lead-pipes": [M("Flint", "Child Lead Exposure Elimination Commission", "Child Lead Exposure Elimination Commission", "Michigan creates the Child Lead Exposure Elimination Commission", "Institution", "2017-03-16", "day", None, "Flint water crisis"),
                      M("Flint", "founded BlueConduit", "BlueConduit", "University of Michigan researchers found BlueConduit", "Institution", "2019-06", "month", None, "Flint water crisis")],
 "love-canal-superfund": [M("Love Canal", "Love Canal Area Revitalization Agency", "LCARA", "New York founds the Love Canal Area Revitalization Agency", "Institution", "1980-06-04", "day", None, "Love Canal")],
}
d = json.load(open("../site/ripples/demo/discovered_wiki.json"))
for slug, st in new.items(): d["stones"][slug] = st
for slug, ms in extra.items(): d["stones"][slug]["marks"] += ms
MONTHS = ["January","February","March","April","May","June","July","August","September","October","November","December"]
cache = {}
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
d["run"] = "2026-10-04"; json.dump(d, open("../site/ripples/demo/discovered_wiki.json", "w"), indent=1, ensure_ascii=False)
print("\nstones", len(d["stones"]), "marks", sum(len(s["marks"]) for s in d["stones"].values()), "flagged", len(flagged)); [print("  ", f) for f in flagged]
