"""Discovery maps: turn editor-trail results (ripples/docs/results/editor_trail_v1.json) into demo map data.

Keeps candidates that rose unusually (p <= 0.05 against the article's own history), began on or after attention to
the event began (the ordering rule), and are not seasonal. Drops same-field noise: awards, given names, lists,
discographies, other TV series, films, manga and production studios. Sorts the rest into industry slices by their
Wikidata description, at most 4 per slice and 12 per event. Output: ripples/demo/discovered.json.
These are explore-stage findings: measured attention rises in the right order, not confirmed causal links.
"""
from __future__ import annotations

import json
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "docs", "results", "editor_trail_v1.json")
OUT = os.path.join(ROOT, "demo", "discovered.json")

TITLES = {"stranger-things-4": "Stranger Things 4", "wednesday": "Wednesday", "saltburn": "Saltburn", "squid-game": "Squid Game",
          "the-bear": "The Bear", "bridgerton": "Bridgerton", "top-gun-maverick": "Top Gun: Maverick", "barbie": "Barbie",
          "queens-gambit": "The Queen's Gambit", "chernobyl": "Chernobyl", "tiger-king": "Tiger King",
          "the-last-of-us": "The Last of Us", "euphoria-s2": "Euphoria, season 2", "shogun": "Shōgun"}
DROP = re.compile(r"award|given name|wikimedia|discography|decade|ceremony|television (series|show|program|channel)|miniseries|"
                  r"\bfilm\b|manga|manhwa|webtoon|anime|production company|film studio|animation studio|streaming|"
                  r"magazine|roller coaster|^$", re.I)
SLICES = [  # first match wins
    ("Music", re.compile(r"\b(song|single|album|band|singer)\b", re.I)),
    ("Games & play", re.compile(r"\bgame\b", re.I)),
    ("Science & nature", re.compile(r"\b(species|genus|fung|plant species|orchid)\b", re.I)),
    ("Food & drink", re.compile(r"\b(sandwich|dish|food|drink|candy|cuisine)\b", re.I)),
    ("Books", re.compile(r"\b(novel|short story|book|non-fiction|novels|poem)\b", re.I)),
    ("Business & brands", re.compile(r"\b(company|chain|corporation|telecommunications|brand|retailer|organization|non-profit)\b", re.I)),
    ("Law & history", re.compile(r"\b(case|law|legal|camp|battle|relations|history|title of nobility|ball)\b", re.I)),
    ("Places & tourism", re.compile(r"\b(town|city|village|castle|house|building|station|prison|museum|mall|square|county|"
                                    r"neighborhood|neighbourhood|eldership|municipality|listed|heritage|theater|theatre|"
                                    r"power plant|parish|division|park|zoo|settlement|structure|crescent)\b", re.I)),
]


def slice_of(c):
    text = f"{c['title']} {c['desc']}"
    if c["group"] == "music":
        return "Music"
    for name, rx in SLICES:
        if rx.search(text):
            return name
    return "Places & tourism" if c["group"] == "place" else None


def label(t):
    return re.sub(r"\s*\((song|album|novel|video game|game|TV series|.*?song)\)$", "", t)


def main() -> int:
    src = json.load(open(SRC))
    out = {"source": "ripples/docs/results/editor_trail_v1.json", "stage": "explore", "events": {}}
    for slug, e in src["events"].items():
        keep, per = [], {}
        for c in e.get("candidates", []):
            if c.get("p") is None or c["p"] > 0.05 or c.get("seasonal") or DROP.search(f"{c['desc']} {c['title']}"):
                continue
            s = slice_of(c)
            if not s or per.get(s, 0) >= 4:
                continue
            per[s] = per.get(s, 0) + 1
            keep.append({"title": c["title"], "label": label(c["title"]), "desc": c["desc"], "slice": s, "onset": c["onset"],
                         "lag": c["lag"], "ratio": c["ratio"], "p": c["p"], "baseline": c["baseline"], "weekly": c["weekly"]})
            if len(keep) >= 12:
                break
        if keep:
            out["events"][slug] = {"title": TITLES.get(slug, slug), "date": e["date"], "event_onset": e.get("event_onset"),
                                   "articles": e.get("articles"), "links": keep}
        print(slug, len(keep), sorted({k["slice"] for k in keep}))
    json.dump(out, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
