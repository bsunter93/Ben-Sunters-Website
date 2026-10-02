"""Discovery maps: turn editor-trail results (ripples/docs/results/editor_trail_v1.json) into demo map data.

Starts from candidates that rose unusually (p <= 0.05 against the article's own history), began on or after attention
to the event began (the ordering rule), and are not seasonal; then applies an editorial qualification (KEEP below):
only leads with a material endpoint, a plausible path and event-pointing timing stay, each with its mechanism, the data
that would test the next step, and any documented outcome. Dropped leads are listed with reasons.
Output: ripples/demo/discovered.json.
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


# Editorial qualification (2 Oct 2026). A lead stays only if its endpoint is material (a chart, a place people visit,
# a company, a law, a food business, a charity) AND a plausible path from the event exists AND the timing points to the
# event. Each kept lead gets a mechanism (its slice), a headline, the data that would test the next step, and, where a
# documented outcome exists, that outcome as a second, dated step. Everything else is dropped with a reason.
KEEP = {
    ("stranger-things-4", "Running Up That Hill"): ("Music charts", "A 1985 Kate Bush song returns", "weekly chart positions",
        ("2022-06-17", "Running Up That Hill reaches No. 1 in the UK, 37 years after release", "Official Charts Company, 17 Jun 2022")),
    ("stranger-things-4", "Master of Puppets (song)"): ("Music charts", "Metallica's 1986 track finds a new audience", "weekly chart positions",
        ("2022-07-12", "Master of Puppets enters the Billboard Hot 100 for the first time", "Billboard, July 2022")),
    ("stranger-things-4", "Lukiškės Prison"): ("Tourism", "The Vilnius prison used for filming, now an arts venue", "visitor numbers at Lukiškės Prison 2.0", None),
    ("wednesday", "Bloody Mary (song)"): ("Music charts", "A dance trend revives a 2011 Lady Gaga track", "streaming and chart positions", None),
    ("wednesday", "Cantacuzino Castle"): ("Tourism", "The Romanian castle that played Nevermore Academy", "castle visitor numbers", None),
    ("saltburn", "Murder on the Dancefloor"): ("Music charts", "Sophie Ellis-Bextor's 2001 hit returns", "weekly chart positions",
        ("2024-01-05", "Murder on the Dancefloor climbs back into the UK Top 10", "Official Charts Company, Jan 2024")),
    ("squid-game", "SK Broadband"): ("Telecoms", "Korea's internet provider and Netflix's traffic", "court filings and network-fee bills",
        ("2021-09-30", "SK Broadband sues Netflix over network costs, citing the traffic surge", "SK Broadband counterclaim, Sept 2021 (the dispute began in 2020)")),
    ("squid-game", "Ddakji"): ("Toys & play", "The show's playground games become a craze", "toy and candy sales", None),
    ("the-bear", "Italian beef"): ("Food", "Chicago's Italian beef sandwich in the spotlight", "restaurant traffic and sales", None),
    ("bridgerton", "Ranger's House"): ("Tourism", "A Greenwich house that played the Featheringtons' home", "English Heritage visitor numbers", None),
    ("queens-gambit", "The Steps of the Sun"): ("Publishing", "Readers turn to Walter Tevis's other novels", "book sales for Tevis's backlist", None),
    ("chernobyl", "Voices from Chernobyl"): ("Publishing", "The oral history behind the series", "book sales", None),
    ("chernobyl", "Ignalina Nuclear Power Plant"): ("Tourism", "The Lithuanian plant that stood in for Chernobyl", "plant tour bookings", None),
    ("chernobyl", "Chernobyl Children International"): ("Charity", "A Chernobyl children's charity draws attention", "donations", None),
    ("tiger-king", "Greater Wynnewood Exotic Animal Park"): ("Regulation", "The zoo at the center of the show", "USDA inspection and licensing records",
        ("2020-08-18", "USDA suspends the park operator's exhibitor license", "USDA action against Jeff Lowe, Aug 2020")),
    ("tiger-king", "Big Cat Rescue"): ("Charity", "Carole Baskin's sanctuary in the spotlight", "donations and visits", None),
    ("the-last-of-us", "Long Long Time"): ("Music charts", "Episode 3 revives a 1970 Linda Ronstadt song", "streaming counts",
        ("2023-01-30", "Spotify reports a surge in Long Long Time streams after the episode", "Spotify, 30 Jan 2023")),
    ("shogun", "Gai-Jin"): ("Publishing", "Readers turn to James Clavell's other novels", "book sales for Clavell's backlist", None),
}
DROP_WHY = [  # (pattern on title or description, reason), first match wins; anything not kept falls through to the last
    (r"Maya Hawke|Labrinth|Tom Cruise|Naughty Dog|A24", "same field: the cast's or makers' own work"),
    (r"novel|short story|book|Asian Saga", "same field: related books"),
    (r"\bsong\b|single|album|concerto|Notebooks", "a soundtrack reference, not a material outcome"),
    (r"game|Pall-mall", "a duplicate or a curiosity: no material path"),
    (r"Brothers Home|Dark Souls|First Class|Mischief|Space Song", "timing points to unrelated news, not the event"),
    (r"town|city|neighborhood|county|settlement|municipality|eldership|Square|building|mall|station|theatre|theater|house|Somerley", "a setting or minor location: curiosity, not a material outcome"),
    (r"", "no plausible material path from the event"),
]


OUTCOME_SHORT = {"Running Up That Hill": "UK No. 1", "Master of Puppets (song)": "Hot 100 debut", "Murder on the Dancefloor": "UK Top 10",
                 "SK Broadband": "Sues Netflix", "Greater Wynnewood Exotic Animal Park": "License suspended", "Long Long Time": "Streams surge"}


def main() -> int:
    src = json.load(open(SRC))
    out = {"source": "ripples/docs/results/editor_trail_v1.json", "stage": "explore", "events": {}}
    for slug, e in src["events"].items():
        keep, dropped = [], []
        for c in e.get("candidates", []):
            if c.get("p") is None or c["p"] > 0.05 or c.get("seasonal"):
                continue
            k = KEEP.get((slug, c["title"]))
            if not k:
                if DROP.search(f"{c['desc']} {c['title']}") or not slice_of(c):
                    continue  # awards, lists, other screen works: never candidates
                why = next(r for rx, r in DROP_WHY if re.search(rx, f"{c['title']} {c['desc']}", re.I))
                dropped.append({"title": c["title"], "why": why})
                continue
            mech, head, nxt, outcome = k
            keep.append({"title": c["title"], "label": label(c["title"]), "desc": c["desc"], "slice": mech, "headline": head, "next": nxt,
                         "outcome": {**dict(zip(("date", "claim", "source"), outcome)), "short": OUTCOME_SHORT.get(c["title"])} if outcome else None, "onset": c["onset"],
                         "lag": c["lag"], "ratio": c["ratio"], "p": c["p"], "baseline": c["baseline"], "weekly": c["weekly"]})
        out["events"][slug] = {"title": TITLES.get(slug, slug), "date": e["date"], "event_onset": e.get("event_onset"),
                               "articles": e.get("articles"), "links": keep, "dropped": dropped}
        print(slug, len(keep), "kept,", len(dropped), "dropped", sorted({k["slice"] for k in keep}))
    json.dump(out, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
