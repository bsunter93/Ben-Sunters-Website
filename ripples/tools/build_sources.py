#!/usr/bin/env python3
"""Build ripples/demo/sources.json: one real source link per chain step.

Output shape: {chain slug: {step number as a string: {"url": ..., "label": ...}}}.

Two inputs, merged in order:

1. Hints. Every chain in ripples/chains/*.json (a list, or {"chains": [...]});
   a step whose `wiki` field names the Wikipedia article it is about gets
   https://en.wikipedia.org/wiki/<Title> with the label "Wikipedia: <Title>".
   `wiki` may be a string or a list; the first title wins.
2. CURATED, the hand-written table below, which overrides the hints for the
   most-viewed stories.

Keying. Chains are keyed by the step's `n`. The slug "tiger-king" is shown in
the demo as a ripple MAP (ripples/maps/out/tiger-king.json, MAPS config in
ripples/demo/index.html), not as the chain of the same slug. The demo's
fromMap() looks items up by their index in the map's `steps` array
(MAPS["tiger-king"].nodes keys 1, 2, 4, 5 are those indexes), so "tiger-king"
is keyed by map step INDEX (0 = the release). The hint pass skips that slug so
the chain's step numbers cannot collide with the map's indexes.

Every URL here was written from knowledge without fetching (no network in the
build sandbox). Only well-known Wikipedia titles and a few official URL
patterns are used; where a title or URL was uncertain the step is left out.
A missing link renders as "not linked yet"; a wrong link is worse.
"""
import glob
import json
import os
from urllib.parse import quote

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CHAINS = os.path.join(ROOT, "chains", "*.json")
OUT = os.path.join(ROOT, "demo", "sources.json")

# Slugs the demo renders from ripples/maps/out, keyed by map step index, not chain n.
MAP_SLUGS = {"tiger-king"}


def wiki(title):
    """Wikipedia URL and label for an exact article title."""
    url = "https://en.wikipedia.org/wiki/" + quote(title.replace(" ", "_"), safe="/()_,:'!-")
    return (url, "Wikipedia: " + title)


def congress(ordinal, house, number, label):
    return ("https://www.congress.gov/bill/%s-congress/%s/%d" % (ordinal, house, number),
            "congress.gov: " + label)


W = wiki
NIAAA = ("https://www.niaaa.nih.gov/publications/surveillance-reports",
         "NIAAA: apparent per-capita alcohol consumption, surveillance reports")

# slug -> {n: (url, label)}. n is the chain step number, or the map step index for MAP_SLUGS.
CURATED = {
    # Map; keyed by index into ripples/maps/out/tiger-king.json steps.
    "tiger-king": {
        0: W("Tiger King"),
        1: W("Exotic pet"),
        2: W("Wildlife trade"),
        4: congress("116th", "house-bill", 1380, "H.R. 1380, Big Cat Public Safety Act (116th Congress)"),
        5: congress("117th", "house-bill", 263, "H.R. 263, Big Cat Public Safety Act (117th Congress), enacted Dec 20, 2022"),
    },
    "mr-bates-horizon": {
        1: W("Mr Bates vs The Post Office"),
        2: W("British Post Office scandal"),
        3: W("Paula Vennells"),
        4: W("Paula Vennells"),
        5: W("British Post Office scandal"),
        6: W("Post Office (Horizon System) Offences Act 2024"),
        7: W("Post Office (Horizon System) Offences Act 2024"),
        8: W("Post Office (Horizon System) Offences Act 2024"),
        9: W("Paula Vennells"),
    },
    "america-and-alcohol": {
        1: W("Volstead Act"),
        2: W("Prohibition in the United States"),
        3: W("Saint Valentine's Day Massacre"),
        4: W("Al Capone"),
        5: W("Twenty-first Amendment to the United States Constitution"),
        6: W("Alcoholics Anonymous"),
        7: NIAAA,
        9: W("National Institute on Alcohol Abuse and Alcoholism"),
        10: ("https://monitoringthefuture.org/", "Monitoring the Future, University of Michigan"),
        11: ("https://news.gallup.com/", "Gallup: Consumption Habits surveys"),
        12: W("Non-alcoholic beer"),
        15: W("Dry January"),
        16: W("Dry January"),
        17: W("Cannabis in Colorado"),
        18: W("Cannabis in Colorado"),
        19: W("Sober curious"),
        20: W("Sober curious"),
        21: W("Alcohol and cancer"),
        22: W("Alcohol and cancer"),
        23: NIAAA,
        24: ("https://www.cdc.gov/brfss/", "CDC: Behavioral Risk Factor Surveillance System"),
        25: W("Alcohol and cancer"),
        26: W("Dry January"),
    },
    "squid-game-ripples": {
        1: W("Squid Game"),
        2: W("Squid Game"),
        3: W("Squid Game"),
        5: W("SK Broadband"),
        7: W("SK Broadband"),
        10: W("MrBeast"),
        11: W("Squid Game: The Challenge"),
        12: W("Ddakji"),
    },
    "frozen": {
        1: W("Frozen (2013 film)"),
        2: ("https://www.ssa.gov/oact/babynames/", "Social Security Administration: popular baby names"),
    },
    "tambora-bicycle": {
        1: W("1815 eruption of Mount Tambora"),
        2: W("Year Without a Summer"),
        3: W("Year Without a Summer"),
        4: W("Karl Drais"),
        5: W("History of the bicycle"),
    },
    "silent-spring-ddt": {
        1: W("Silent Spring"),
        2: W("CBS Reports"),
        3: W("President's Science Advisory Committee"),
        4: W("United States Environmental Protection Agency"),
        5: W("DDT"),
    },
    "sixty-minutes-stock-act": {
        1: W("60 Minutes"),
        2: congress("112th", "house-bill", 1148, "H.R. 1148, STOCK Act (112th Congress)"),
        3: W("STOCK Act"),
        4: congress("112th", "senate-bill", 2038, "S. 2038, STOCK Act, Public Law 112-105"),
        5: W("STOCK Act"),
    },
    "daily-show-zadroga": {
        1: W("The Daily Show"),
        2: W("James Zadroga 9/11 Health and Compensation Act"),
        3: congress("111th", "house-bill", 847, "H.R. 847, James Zadroga 9/11 Health and Compensation Act"),
        4: W("Jon Stewart"),
        5: W("James Zadroga 9/11 Health and Compensation Act"),
        6: congress("116th", "house-bill", 1327, "H.R. 1327, Never Forget the Heroes Act (116th Congress)"),
    },
    "quincy-orphan-drug": {
        1: W("Quincy, M.E."),
        2: W("Jack Klugman"),
        3: W("Quincy, M.E."),
        4: W("Orphan Drug Act of 1983"),
        5: W("Orphan drug"),
    },
    "cathy-come-home": {
        1: W("Cathy Come Home"),
        2: W("Shelter (charity)"),
        3: W("Cathy Come Home"),
        4: W("Housing (Homeless Persons) Act 1977"),
        5: W("Housing (Homeless Persons) Act 1977"),
    },
    "octopus-sentience": {
        1: W("My Octopus Teacher"),
        2: W("Cephalopod intelligence"),
        3: W("My Octopus Teacher"),
        4: W("Animal Welfare (Sentience) Act 2022"),
        5: W("Animal Welfare (Sentience) Act 2022"),
        6: W("Animal Welfare (Sentience) Act 2022"),
    },
    "planet-earth": {
        1: W("Planet Earth (2006 TV series)"),
        3: W("U.S. Consumer Product Safety Commission"),
        4: ("https://www.anchorit.gov/", "CPSC: Anchor It! campaign"),
        5: W("STURDY Act"),
    },
}


def load_chains():
    out = []
    for path in sorted(glob.glob(CHAINS)):
        with open(path) as f:
            data = json.load(f)
        chains = data["chains"] if isinstance(data, dict) else data
        out.extend(c for c in chains if isinstance(c, dict) and c.get("slug"))
    return out


def hint_links(chains):
    links = {}
    for ch in chains:
        slug = ch["slug"]
        if slug in MAP_SLUGS:
            continue
        for st in ch.get("steps") or []:
            hint = st.get("wiki")
            if isinstance(hint, list):
                hint = hint[0] if hint else None
            if not hint or st.get("n") is None:
                continue
            url, label = wiki(str(hint))
            links.setdefault(slug, {})[str(st["n"])] = {"url": url, "label": label}
    return links


def main():
    chains = load_chains()
    links = hint_links(chains)
    for slug, steps in CURATED.items():
        for n, (url, label) in steps.items():
            links.setdefault(slug, {})[str(n)] = {"url": url, "label": label}
    # Sort slugs alphabetically and steps numerically.
    out = {slug: {k: links[slug][k] for k in sorted(links[slug], key=int)} for slug in sorted(links)}
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False, sort_keys=False)
        f.write("\n")
    total = 0
    for slug in out:
        total += len(out[slug])
        print("%-28s %3d" % (slug, len(out[slug])))
    print("%-28s %3d  (%d chains) -> %s" % ("total", total, len(out), os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    main()
