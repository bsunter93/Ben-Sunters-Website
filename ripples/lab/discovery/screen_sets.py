"""Build the frozen evaluation sets for the screen (docs/screen_plan_v1.md) from the discovery runs' own output.

Only candidate fields are copied: stone, stone year, mark title and year where the run produced one, the sentence, its
section and years, and the source. No hand decision is read: the builder's verdicts in discovery_corpus1_screen.json and
the product file demo/discovered_wiki.json are not opened here. The `verdict` field of strict_pairs.json and
heldout_fwd.json is the automated ordering rule, used only to select the rows the person screened (in order), and it is
not copied. Run from ripples/docs/results:

    python3 ../../lab/discovery/screen_sets.py      # writes screen_candidates_v1.json
"""
import json
import re

# class: "culture" when the stone is a work, broadcast, product, toy, game, fad or diet; "events" otherwise
# (disasters, attacks, accidents, crimes, scandals, leaks, movements, policies, rulings, launches). Fixed before labeling.
CULTURE_STRICT = {"60 Minutes", "The Daily Show", "The West Wing", "Silent Spring", "Super Bowl XXXVIII halftime"}
EVENTS_HELDOUT = {"Hurricane Katrina", "Deepwater Horizon", "Sandy Hook"}
CULTURE_WIDER = {"Jaws", "Bowling for Columbine", "The Cove", "Food, Inc.", "Gasland", "The Thin Blue Line", "Paradise Lost",
                 "Dear Zachary", "Leaving Neverland", "Surviving R. Kelly", "The Jinx", "Making a Murderer", "Cathy Come Home",
                 "Philadelphia", "Schindler's List", "Hotel Rwanda", "Kony 2012", "Super Size Me", "Sicko"}


def clean(t):
    # source text keeps its words; an em dash (U+2014) becomes a spaced hyphen, per the house style
    return re.sub(r"\s+", " ", (t or "").replace("\u2014", " - ")).strip()


def main():
    out = []

    # E1: the catalog's strict reverse pairs in order, one row per unique (stone, mark), first sentence kept
    seen = set()
    n = 0
    for o in json.load(open("strict_pairs.json")):
        if o["verdict"] != "in order" or (o["stone"], o["mark"]) in seen:
            continue
        seen.add((o["stone"], o["mark"])); n += 1
        out.append({"id": f"S{n:02d}", "set": "E1_strict", "reading": "reverse",
                    "class": "culture" if o["stone"] in CULTURE_STRICT else "events",
                    "stone": o["stone"], "stone_year": o["stone_year"], "mark": o["mark"], "mark_year": o["mark_year"],
                    "mark_dated_by": o["how"], "years_in_sentence": [], "section": None,
                    "source": f"Wikipedia, the article \"{o['mark']}\"", "sentence": clean(o["sentence"])})

    # E2: held-out stones, forward sentences in order by the years they carry
    n = 0
    for o in json.load(open("heldout_fwd.json")):
        for c in o["cands"]:
            if c["verdict"] != "in order":
                continue
            n += 1
            out.append({"id": f"H{n:02d}", "set": "E2_heldout", "reading": "forward",
                        "class": "events" if o["stone"] in EVENTS_HELDOUT else "culture",
                        "stone": o["stone"], "stone_year": o["year"], "mark": None, "mark_year": None, "mark_dated_by": None,
                        "years_in_sentence": c["years"], "section": c["section"],
                        "source": f"Wikipedia, the article on {o['stone']}, section \"{c['section']}\"", "sentence": clean(c["text"])})

    # E3: discovery v1.1, sixty stones, reverse pairs then forward sentences
    w = json.load(open("wider_v1_1.json"))
    n = 0
    for o in w:
        for r in o["reverse"]:
            n += 1
            out.append({"id": f"WR{n:02d}", "set": "E3_wider", "reading": "reverse",
                        "class": "culture" if o["stone"] in CULTURE_WIDER else "events",
                        "stone": o["stone"], "stone_year": o["year"], "mark": r["mark"], "mark_year": r["mark_year"],
                        "mark_dated_by": r.get("how"), "years_in_sentence": [], "section": None,
                        "source": f"Wikipedia, the article \"{r['mark']}\"", "sentence": clean(r["text"])})
    n = 0
    for o in w:
        for f in o["forward"]:
            n += 1
            out.append({"id": f"WF{n:03d}", "set": "E3_wider", "reading": "forward",
                        "class": "culture" if o["stone"] in CULTURE_WIDER else "events",
                        "stone": o["stone"], "stone_year": o["year"], "mark": None, "mark_year": None, "mark_dated_by": None,
                        "years_in_sentence": f["years"], "section": f["section"],
                        "source": f"Wikipedia, the article \"{o['article']}\", section \"{f['section']}\"", "sentence": clean(f["text"])})

    # E4: the culture shelf, forward sentences
    n = 0
    for o in json.load(open("culture_v1.json")):
        for f in o["forward"]:
            n += 1
            out.append({"id": f"C{n:03d}", "set": "E4_culture", "reading": "forward", "class": "culture",
                        "stone": o["stone"], "stone_year": o["year"], "mark": None, "mark_year": None, "mark_dated_by": None,
                        "years_in_sentence": f["years"], "section": f["section"],
                        "source": f"Wikipedia, the article \"{o['article']}\", section \"{f['section']}\"", "sentence": clean(f["text"])})

    # E5: fifty famous films as decoys, forward and reverse
    n = 0
    for o in json.load(open("famous_decoys_v1.json")):
        for f in o["forward"]:
            n += 1
            out.append({"id": f"DF{n:02d}", "set": "E5_decoys_famous", "reading": "forward", "class": "culture",
                        "stone": o["stone"], "stone_year": o["year"], "mark": None, "mark_year": None, "mark_dated_by": None,
                        "years_in_sentence": f["years"], "section": f["section"],
                        "source": f"Wikipedia, the article on {o['stone']}, section \"{f['section']}\"", "sentence": clean(f["text"])})
        for r in o["reverse"]:
            n += 1
            out.append({"id": f"DF{n:02d}", "set": "E5_decoys_famous", "reading": "reverse", "class": "culture",
                        "stone": o["stone"], "stone_year": o["year"], "mark": r["mark"], "mark_year": r["mark_year"],
                        "mark_dated_by": None, "years_in_sentence": [], "section": None,
                        "source": f"Wikipedia, the article \"{r['mark']}\"", "sentence": clean(r["text"])})

    # E6: the fifty obscure decoys of v1, the example sentences the run kept (200 characters each)
    n = 0
    # the v1 decoys were American films of 2015 and 2007 and television debuts of 2012; the year of each comes from its title
    oyear = {"Insidious: Chapter 3": 2015, "Steve Jobs (film)": 2015, "The Bourne Ultimatum (film)": 2007, "The King of Kong": 2007,
             "Blades of Glory": 2007, "Wild Hogs": 2007, "Sicko": 2007, "Duck Dynasty": 2012, "Shahs of Sunset": 2012}
    for title, v in json.load(open("decoys.json")).items():
        for e in v["examples"]:
            n += 1
            rev = ": " in e[:120] and bool(re.match(r"^[A-Z][^:]{3,100}(Act|Law|Commission|Agency|Authority|Treaty|Regulation|Bill)[^:]*: ", e))
            out.append({"id": f"DO{n:02d}", "set": "E6_decoys_obscure", "reading": "reverse" if rev else "forward", "class": "culture",
                        "stone": re.sub(r"\s*\(.*\)$", "", title), "stone_year": oyear.get(title), "mark": e.split(": ")[0] if rev else None,
                        "mark_year": None, "mark_dated_by": None, "years_in_sentence": re.findall(r"\b(?:19|20)\d\d\b", e),
                        "section": None, "source": f"Wikipedia, the article on {title}" if not rev else f"Wikipedia, the article \"{e.split(': ')[0]}\"",
                        "sentence": clean(e.split(": ", 1)[1] if rev else e)})

    # S1: the citation calibration pairs behind cite_score v1 (not blind: the scorer's source hard-codes their labels).
    # Only work and mark are read from cite_score_v1.json; the sentence is the record pair cite_score scored highest.
    import os, sys
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    from cite_score import score as cite_points
    pairs = json.load(open("mark_text_v1_3.json"))["pairs"]
    n = 0
    for r in json.load(open("cite_score_v1.json"))["eval"]["rows"]:
        cand = [p for p in pairs if p.get("work") == r["work"] and p.get("mark") == r["mark"]]
        best = max(cand, key=lambda p: cite_points(p.get("sentence") or "", p.get("work") or "")[0])
        n += 1
        yr = lambda d: int(str(d)[:4]) if d and str(d)[:4].isdigit() else None
        out.append({"id": f"R{n:02d}", "set": "S1_citations", "reading": "record", "class": "culture",
                    "stone": r["work"], "stone_year": yr(best.get("work_date")), "mark": r["mark"], "mark_year": yr(best.get("mark_date")),
                    "mark_dated_by": "record date", "years_in_sentence": [], "section": None,
                    "source": f"{best.get('source')}: {clean(best.get('title_text'))[:120]}", "sentence": clean(best.get("sentence"))})

    meta = {"_about": "Frozen evaluation sets for the screen, candidate fields only (docs/screen_plan_v1.md). Built by "
                      "lab/discovery/screen_sets.py from the discovery runs' output; no hand decision was read to build it. "
                      "Em dashes in source text are written as spaced hyphens.",
            "counts": {}}
    for c in out:
        meta["counts"][c["set"]] = meta["counts"].get(c["set"], 0) + 1
    meta["counts"]["by_class"] = {k: sum(1 for c in out if c["class"] == k) for k in ("events", "culture")}
    json.dump({**meta, "candidates": out}, open("screen_candidates_v1.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps(meta["counts"]))


if __name__ == "__main__":
    main()
