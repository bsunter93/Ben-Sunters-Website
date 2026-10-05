"""Records 2 (ripples/docs/records2_plan_v1.md): new cited-cause record sources for the records route.

The records route reads records that name a work as a reason. Hansard and the Congressional Record were the first two;
this pass adds the Federal Register's final rules (a final rule whose preamble names the stone; the mark is the rule)
and registers, without running, US court opinions on CourtListener (its REST API requires an account token; see the
plan). Every stone list already in lab/discovery is read; fifty famous films are the decoys.

  python3 ripples/lab/records2.py plan       # writes docs/results/records2_queries_v1.json (the registered queries)
  python3 ripples/lab/records2.py selftest   # offline checks of the matcher and the guards, no network
  python3 ripples/lab/records2.py run        # the registered run: Federal Register API, honest UA, 1.1 s a request
  python3 ripples/lab/records2.py review     # prints every surviving sentence for the hand read
  python3 ripples/lab/records2.py build      # merges docs/results/records2_hand_v1.json -> docs/results/records2_v1.json

Network rules: the honest user agent, at least 1.1 s between requests, a stop for the day on any 401, 403, 429 or 5xx,
on a timeout, or on a redirect to the site's access-request page; no retries, no other agent, no other host for the
same text. A 404 on one document's text is logged as "no text" and that document is skipped (a missing file, not a
refusal; the Oct 4 run stopped on one, and this plan says so in advance). Aggregate data only.
"""
from __future__ import annotations

import ast
import datetime as dt
import json
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import cite_score  # noqa: E402

LAB = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(LAB, "..")
RES = os.path.join(ROOT, "docs", "results")
QUERIES = os.path.join(RES, "records2_queries_v1.json")
RAW = os.path.join(RES, "records2_raw_v1.json")
HAND = os.path.join(RES, "records2_hand_v1.json")
OUT = os.path.join(RES, "records2_v1.json")
PROTOCOL = "ripples/docs/records2_plan_v1.md"
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
FR = "https://www.federalregister.gov/api/v1/documents.json"
GAP = 1.1           # seconds between requests
PER_PAGE = 20       # search results read per query
MAX_DOCS = 15       # final-rule texts read per stone, in relevance order across its queries
MAX_REQUESTS = 1500  # the whole run

# ---------------------------------------------------------------- the stones -------------------------------------------
def _literal(path, name):
    """The list assigned to `name` in a discovery script, read without running the script."""
    tree = ast.parse(open(path, encoding="utf-8").read())
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
            return ast.literal_eval(node.value)
    raise KeyError(name)


# Hand table, fixed before any search. Keyed by the article title used in the source list (catalog entries by slug).
# type: work | event | thing.  amb: the phrase can mean something else in a US government document (ordinary words, a
# place, a person, a company, a product, another event).  word: the disambiguating word added to the query when amb.
# guard: extra words that count as context within 160 characters (works also accept the general work words).
# phrases: what is searched (the title less its parenthetical unless given).  case: "i" for common-noun things.
H = {}
def h(key, type_, amb=False, word=None, phrases=None, guard=None, case=None, date=None, skip=None):
    H[key] = {"type": type_, "amb": amb, "word": word, "phrases": phrases, "guard": guard, "case": case, "date": date, "skip": skip}

# catalog (stones_all.json, in class)
h("tiger-king", "work", True, "Netflix", guard=r"Joe Exotic|docuseries|big cats?")
h("broad-street-sanitation", "event", phrases=["Broad Street pump"], guard=r"cholera|John Snow|1854")
h("chernobyl-zone", "work", True, "miniseries", phrases=["Chernobyl"], guard=r"HBO|miniseries|drama")
h("mr-bates-horizon", "work", True, "television", phrases=["Mr Bates", "Mr. Bates"], guard=r"Post Office|ITV|Horizon")
h("cathy-come-home", "work")
h("quincy-orphan-drug", "work", True, "television", phrases=["Quincy, M.E.", "Quincy"], guard=r"Jack Klugman|medical examiner|orphan")
h("octopus-sentience", "work")
h("sixty-minutes-stock-act", "work", True, "CBS", guard=r"CBS|segment|broadcast|aired|news program|investigat\w+ report")
h("victim-1961", "work", True, "film", guard=r"Dirk Bogarde|1961")
h("daily-show-zadroga", "work", guard=r"Jon Stewart|Comedy Central")
h("manhunt-byron", "work", True, "game", guard=r"Rockstar|video game")
h("west-wing-hatred-act", "work", True, "television", guard=r"NBC|Aaron Sorkin|drama")
h("silent-spring-ddt", "work", True, "book", guard=r"Rachel Carson|Carson's|Carson,? R")
h("adolescence-schools", "work", True, "Netflix", guard=r"Netflix|drama|Jack Thorne|Stephen Graham")
h("america-and-alcohol", "event", True, "repeal", phrases=["Prohibition"],
  guard=r"Eighteenth Amendment|18th Amendment|Volstead|Prohibition era|National Prohibition|repeal of Prohibition|Twenty-first Amendment|21st Amendment|\b1920\b|\b1933\b")
h("the-jungle-fda", "work", True, "Sinclair", guard=r"Upton Sinclair|Sinclair's|meatpacking|meat-packing|meat packing")
h("triangle-shirtwaist", "event", phrases=["Triangle Shirtwaist"])
h("dust-bowl-soil", "event", phrases=["Dust Bowl"])
h("sputnik-nasa-arpa", "event", phrases=["Sputnik"])
h("sputnik-gps", "event", skip="the same stone as sputnik-nasa-arpa")
h("unsafe-at-any-speed", "work", guard=r"Ralph Nader|Nader")
h("cuyahoga-clean-water", "event", True, "fire", phrases=["Cuyahoga River"], guard=r"fire|burned|caught fire|ablaze|1969")
h("love-canal-superfund", "event")
h("three-mile-island-nrc", "event", True, "accident", guard=r"accident|1979|meltdown|partial melt|TMI-2 accident")
h("exxon-valdez-opa90", "event", phrases=["Exxon Valdez"])
h("liebeck-hot-coffee", "thing", phrases=["Liebeck"])
h("columbine-active-shooter", "event", True, "shooting", phrases=["Columbine"], guard=r"shooting|shootings|massacre|High School|1999|gunm[ae]n")
h("flint-lead-pipes", "event", True, "water", phrases=["Flint"], guard=r"drinking water|water crisis|water system|lead|Michigan|\b201[456]\b")
h("serial", "work", skip="the same stone as the culture list's Serial (podcast)")
h("svb", "event", phrases=["Silicon Valley Bank"])
h("dobbs", "thing", True, "Jackson", phrases=["Dobbs v. Jackson", "Dobbs"], guard=r"Dobbs v\.|Jackson Women|Supreme Court|decision|Roe")
h("tylenol", "event", True, "tampering", phrases=["Tylenol"], guard=r"tamper\w*|poison\w*|cyanide|1982|Chicago")
h("gdpr", "thing", phrases=["General Data Protection Regulation", "GDPR"])
h("fukushima", "event")
h("winter-storm-uri", "event", phrases=["Winter Storm Uri"])
h("ice-bucket", "thing", skip="the same stone as the culture list's Ice Bucket Challenge")
h("cash-for-clunkers", "thing", phrases=["Cash for Clunkers"])
h("airbnb", "thing", date="2008-08-11")
h("wardrobe-malfunction", "event", phrases=["Super Bowl XXXVIII", "Janet Jackson"], guard=r"Super Bowl|halftime|wardrobe|indecen\w+|broadcast")
h("anthrax", "event", phrases=["anthrax attacks", "anthrax letters"], case="i")
h("planet-earth", "work", True, "BBC", guard=r"BBC|Attenborough")
h("tambora-bicycle", "event", phrases=["Tambora"])
h("earthquake-bank", "event", phrases=["1906 San Francisco earthquake", "1906 earthquake"])

# wider (wider.py): events, with the works among them
for k in ["Hurricane Sandy", "Grenfell Tower fire", "Theranos", "Cambridge Analytica", "Panama Papers", "Madoff fraud", "Love Canal",
          "Costa Concordia disaster", "Germanwings Flight 9525", "Takata airbag recall", "Pulse nightclub shooting", "Murder of George Floyd",
          "Bhopal disaster", "Rana Plaza collapse", "Enron scandal", "Lac-Mégantic rail disaster", "Chernobyl disaster"]:
    h(k, "event")
H["Hurricane Sandy"]["phrases"] = ["Hurricane Sandy", "Superstorm Sandy"]
H["Grenfell Tower fire"]["phrases"] = ["Grenfell"]
H["Madoff fraud"]["phrases"] = ["Madoff"]
H["Costa Concordia disaster"]["phrases"] = ["Costa Concordia"]
H["Germanwings Flight 9525"]["phrases"] = ["Germanwings"]
H["Takata airbag recall"]["phrases"] = ["Takata"]
H["Pulse nightclub shooting"]["phrases"] = ["Pulse nightclub"]
H["Murder of George Floyd"]["phrases"] = ["George Floyd"]
H["Bhopal disaster"]["phrases"] = ["Bhopal"]
H["Rana Plaza collapse"]["phrases"] = ["Rana Plaza"]
H["Enron scandal"]["phrases"] = ["Enron"]
H["Lac-Mégantic rail disaster"]["phrases"] = ["Lac-Mégantic", "Lac-Megantic"]
H["Chernobyl disaster"]["phrases"] = ["Chernobyl"]
h("September 11 attacks", "event", True, "attacks", phrases=["September 11"], guard=r"attacks?|terroris\w+|2001|hijack\w*")
h("Challenger disaster", "event", True, "shuttle", phrases=["Challenger"], guard=r"[Ss]huttle|NASA|1986|disaster|accident|explosion")
h("Columbia disaster", "event", phrases=["Space Shuttle Columbia", "Columbia Accident Investigation Board"])
h("Hillsborough disaster", "event", True, "stadium", phrases=["Hillsborough"], guard=r"stadium|football|1989|disaster|crush")
h("Boston Marathon bombing", "event", True, "bombing", phrases=["Boston Marathon"], guard=r"bomb\w*|attack|2013|explosi\w+")
h("Oklahoma City bombing", "event", True, "bombing", phrases=["Oklahoma City"], guard=r"bomb\w*|Murrah|1995|attack")
h("Virginia Tech shooting", "event", True, "shooting", phrases=["Virginia Tech"], guard=r"shooting|shootings|massacre|2007|gunman")
h("Parkland shooting", "event", True, "shooting", phrases=["Parkland"], guard=r"shooting|shootings|Marjory Stoneman Douglas|2018|gunman")
h("Uvalde shooting", "event", True, "shooting", phrases=["Uvalde"], guard=r"shooting|shootings|Robb Elementary|2022|gunman")
h("Las Vegas shooting", "event", True, "shooting", phrases=["Las Vegas"], guard=r"shooting|shootings|massacre|October 1, 2017|2017|gunman|bump")
h("Ferguson unrest", "event", True, "Missouri", phrases=["Ferguson"], guard=r"Missouri|unrest|protests?|Michael Brown|2014")
h("Me Too movement", "event", True, "movement", phrases=["MeToo", "Me Too"], guard=r"movement|sexual harassment|2017|#")
h("Harvey Weinstein sexual abuse cases", "event", phrases=["Harvey Weinstein"])
h("Jeffrey Epstein", "event", phrases=["Jeffrey Epstein"])
h("Flint", "event", skip="the same stone as the catalog's flint-lead-pipes")
h("Camp Fire", "event", True, "Paradise", phrases=["Camp Fire"], guard=r"Paradise|2018|wildfire|Butte County|PG&E")
h("Boeing 737 MAX groundings", "event", True, "Ethiopian", phrases=["737 MAX"], guard=r"Lion Air|Ethiopian|accidents?|crash\w*|grounding|2018|2019")
h("Volkswagen emissions scandal", "event", True, "defeat", phrases=["Volkswagen", "Dieselgate"], guard=r"defeat devices?|emissions|scandal|2015|diesel")
h("Dieselgate", "event", skip="the same stone as the Volkswagen emissions scandal")
h("Equifax data breach", "event", True, "breach", phrases=["Equifax"], guard=r"breach|2017|hack\w*|compromis\w+|cyber\w*")
h("Target data breach", "event", True, "breach", phrases=["Target"], guard=r"data breach|breach|2013|hack\w*|payment card")
h("Snowden leaks", "event", phrases=["Edward Snowden"])
h("WikiLeaks Iraq War logs", "event", phrases=["WikiLeaks"])
h("Lehman Brothers collapse", "event", True, "bankruptcy", phrases=["Lehman Brothers"], guard=r"bankrupt\w*|collapse|failure|2008|crisis")
h("Jaws", "work", skip="the same stone as Jaws (film) in the held-out list")
h("Bowling for Columbine", "work")
h("The Cove", "work", True, "documentary", guard=r"dolphins?|Taiji")
h("Food, Inc.", "work", True, "documentary", guard=r"Robert Kenner")
h("Gasland", "work", guard=r"Josh Fox|fracking")
h("The Thin Blue Line", "work", True, "documentary", guard=r"Errol Morris|Randall Dale Adams")
h("Paradise Lost", "work", True, "documentary", guard=r"West Memphis|HBO")
h("Dear Zachary", "work")
h("Leaving Neverland", "work")
h("Surviving R. Kelly", "work")
h("The Jinx", "work", True, "documentary", guard=r"Robert Durst|HBO")
h("Making a Murderer", "work")
h("Cathy Come Home", "work", skip="the same stone as the catalog's cathy-come-home")
h("Philadelphia", "work", True, "film", guard=r"Tom Hanks|AIDS|1993")
h("Schindler's List", "work")
h("Hotel Rwanda", "work")
h("Kony 2012", "work")
h("Super Size Me", "work", guard=r"Morgan Spurlock|Spurlock")
h("Sicko", "work", True, "documentary", guard=r"Michael Moore")

# held out (heldout.py)
h("Blackfish (film)", "work", True, "documentary", guard=r"SeaWorld|orcas?|killer whales?|Tilikum")
h("An Inconvenient Truth", "work", True, "documentary", guard=r"Al Gore|Gore's")
h("The Day After", "work", True, "television", guard=r"ABC|nuclear war|1983")
h("Jaws (film)", "work", True, "film", guard=r"Spielberg|Benchley|sharks?")
h("Roots (1977 miniseries)", "work", True, "television", guard=r"Alex Haley|Kunta Kinte|miniseries")
h("Erin Brockovich (film)", "work", True, "film", guard=r"Julia Roberts|Hinkley")
h("Spotlight (film)", "work", True, "film", guard=r"Boston Globe")
h("13 Reasons Why", "work", guard=r"Netflix|suicide")
h("Making a Murderer", "work")
h("The Social Dilemma", "work", guard=r"Netflix|documentary")
h("Hurricane Katrina", "event")
h("Deepwater Horizon oil spill", "event", phrases=["Deepwater Horizon"])
h("Sandy Hook Elementary School shooting", "event", True, "shooting", phrases=["Sandy Hook"], guard=r"shooting|shootings|Elementary|2012|Newtown|gunman")
h("Chernobyl (miniseries)", "work", skip="the same stone as the catalog's chernobyl-zone (the 2019 miniseries)")
h("Fast Food Nation", "work", guard=r"Eric Schlosser|Schlosser")
h("Blood Diamond (film)", "work", True, "film", guard=r"Leonardo DiCaprio|2006")
h("The China Syndrome", "work", True, "film", guard=r"Jane Fonda|Three Mile Island|1979")
h("Cosmos: A Personal Voyage", "work", phrases=["Cosmos: A Personal Voyage"], guard=r"Carl Sagan|Sagan")
h("Philadelphia (film)", "work", skip="the same stone as the wider list's Philadelphia")

# culture (culture_stones.py). Works unless listed as things or events; amb and word per title.
CULT_AMB = {"Frozen (2013 film)": "film", "Sideways (film)": "film", "The Queen's Gambit (miniseries)": "television", "Twilight (2008 film)": "film",
            "Top Gun": "film", "Breaking Bad": "television", "Squid Game": "Netflix", "Stranger Things": "Netflix", "Barbie (film)": "film",
            "Titanic (1997 film)": "film", "Star Wars (film)": "film", "Avatar (2009 film)": "film", "Black Panther (film)": "film",
            "Friends": "television", "Seinfeld": "television", "The Crown (TV series)": "television", "Serial (podcast)": "podcast",
            "Survivor (American TV series)": "television", "Jersey Shore (TV series)": "MTV", "Old Town Road": "song",
            "Thriller (album)": "album", "Nevermind": "album", "Hamilton (musical)": "musical", "Pac-Man": "game",
            "Grand Theft Auto V": "game", "Jaws (film)": "film", "Babe (film)": "film", "Ratatouille (film)": "film",
            "Psycho (1960 film)": "film", "Rocky": "film", "Grease (film)": "film", "Clueless (film)": "film",
            "Sex Education (TV series)": "Netflix", "Euphoria (American TV series)": "HBO", "Love Island (2015 TV series)": "television",
            "An Inconvenient Truth": "documentary", "Blackfish (film)": "documentary", "What the Health": "documentary",
            "Our Planet": "Netflix", "Chef's Table": "Netflix", "The Bear (TV series)": "television",
            "Yellowstone (American TV series)": "television", "White Lotus": "HBO", "Succession (TV series)": "HBO",
            "Normal People (TV series)": "television", "Narcos": "Netflix", "Dark (TV series)": "Netflix",
            "Lupin (French TV series)": "Netflix", "Baby Reindeer": "Netflix", "Adolescence (TV series)": "Netflix"}
CULT_THING = {"Ice Bucket Challenge": None, "Planking (fad)": r"fad|craze|trend|photograph\w*|social media|viral", "Fidget spinner": None,
              "Beanie Babies": None, "Tamagotchi": None, "Furby": None, "Rubik's Cube": None, "Cabbage Patch Kids": None, "Pet Rock": None,
              "Zumba": None, "CrossFit": None, "Dry January": None, "Veganuary": None, "Movember": None, "Pumpkin Spice Latte": None,
              "Cronut": None, "Dalgona coffee": None, "Avocado toast": None, "Ketogenic diet": None, "Marie Kondo": None, "Hygge": None}
CULT_EVENT = {"Woodstock": ("festival", r"festival|1969|concert|music"), "Live Aid": ("concert", r"concert|1985|Geldof|famine"),
              "Fyre Festival": (None, None)}
CULT_PHRASES = {"Harry Potter and the Philosopher's Stone": ["Harry Potter"], "The Queen's Gambit (miniseries)": ["Queen's Gambit"],
                "The Hunger Games (film)": ["Hunger Games"], "The Sopranos": ["Sopranos"], "Keeping Up with the Kardashians": ["Kardashians"],
                "The Great British Bake Off": ["Great British Bake Off", "Great British Baking Show"], "Candy Crush Saga": ["Candy Crush"],
                "Grand Theft Auto V": ["Grand Theft Auto"], "Pokémon Go": ["Pokémon Go", "Pokemon Go"], "Harlem Shake (meme)": ["Harlem Shake"],
                "Planking (fad)": ["Planking"], "Eat, Pray, Love": ["Eat, Pray, Love"], "Thriller (album)": ["Thriller"],
                "White Lotus": ["White Lotus"]}
CASE_I = {"Fidget spinner", "Pumpkin Spice Latte", "Dalgona coffee", "Avocado toast", "Ketogenic diet", "Ice Bucket Challenge"}
GUARD_X = {"Harry Potter and the Philosopher's Stone": r"Rowling|wizard", "Finding Nemo": r"Pixar|Disney|clownfish|Nemo effect",
           "101 Dalmatians (1996 film)": r"Disney|Dalmatians? (?:breed|puppies)", "Jurassic Park (film)": r"Spielberg|Crichton|dinosaurs?",
           "Free Willy": r"Keiko|orcas?|killer whales?", "Pokémon Go": r"Niantic|augmented reality|players?|app", "Top Gun": r"Tom Cruise|1986|recruit\w*",
           "Super Size Me": r"Morgan Spurlock|Spurlock", "My Octopus Teacher": r"Netflix|documentary", "Seaspiracy": r"Netflix|documentary",
           "Blue Planet II": r"BBC|Attenborough|plastics?", "Planet Earth II": r"BBC|Attenborough", "Tetris": r"puzzle|video game",
           "Minecraft": r"video game|Mojang|Microsoft", "Fortnite": r"Epic Games|video game|players?", "Wordle": r"puzzle|New York Times"}


def stones():
    """Every stone from the existing lists, deduplicated, with the hand table applied. Decoys last."""
    out, seen = [], set()

    def add(key, display, article, date, group, default_type):
        hh = H.get(key) or H.get(article) or {}
        if hh.get("skip"):
            out.append({"id": _slug(key), "stone": display, "article": article, "group": group, "skip": hh["skip"]}); return
        if _slug(article) in seen:
            return
        seen.add(_slug(article))
        type_ = hh.get("type") or default_type
        phrases = hh.get("phrases") or CULT_PHRASES.get(article) or [re.sub(r"\s*\(.*\)$", "", display)]
        amb, word = hh.get("amb", False), hh.get("word")
        guard, case = hh.get("guard"), hh.get("case")
        if article in CULT_AMB and not hh:
            amb, word = True, CULT_AMB[article]
        if article in CULT_THING and not hh:
            type_ = "thing"; guard = CULT_THING[article]; amb = guard is not None; word = {"Planking (fad)": "fad"}.get(article)
        if article in CULT_EVENT and not hh:
            type_ = "event"; word, guard = CULT_EVENT[article]; amb = word is not None
        if article in CASE_I:
            case = "i"
        if article in GUARD_X and not guard:
            guard = GUARD_X[article]
        d = hh.get("date") or date
        rec = {"id": _slug(key), "stone": display, "article": article, "group": group, "type": type_, "date": d,
               "phrases": phrases, "amb": amb, "word": word if amb else None, "guard": guard, "case": case or "s"}
        if len(phrases) == 1 and phrases[0].lower() in STOPWORDS:
            rec["skip"] = "the title is a single function word and cannot be searched as a phrase"
        rec["queries"] = [] if rec.get("skip") else [_query(p, rec) for p in phrases]
        out.append(rec)

    cat = json.load(open(os.path.join(RES, "stones_all.json")))
    for slug, st in cat.items():
        if st.get("in_class"):
            add(slug, st["stone"], st["article"], st.get("date"), "catalog", "event")
    for e in _literal(os.path.join(LAB, "discovery", "wider.py"), "STONES"):
        stone, article, year = (e[0], e[1], e[2]) if len(e) == 3 else (e[0], e[0], e[1])
        add(stone, stone, article, str(year), "wider", "event")
    for article, stone, year in _literal(os.path.join(LAB, "discovery", "heldout.py"), "STONES"):
        add(article, stone, article, str(year), "heldout", "work")
    for article, year in _literal(os.path.join(LAB, "discovery", "culture_stones.py"), "STONES"):
        add(article, re.sub(r"\s*\(.*\)$", "", article), article, str(year), "culture", "work")
    wiki = json.load(open(os.path.join(ROOT, "demo", "discovered_wiki.json")))["stones"]
    exact = {}  # exact dates the product already verified, by display name
    key = lambda n: re.sub(r"^the\s+", "", fold(n).lower()).strip()
    for w in wiki.values():
        exact[key(w["stone"])] = w["date"]
    by_id = {"september-11-attacks": "september-11", "chernobyl-disaster": "chernobyl-disaster", "bhopal-disaster": "bhopal",
             "challenger-disaster": "challenger", "rana-plaza-collapse": "rana-plaza", "enron-scandal": "enron", "grenfell-tower-fire": "grenfell",
             "lac-megantic-rail-disaster": "lac-megantic", "volkswagen-emissions-scandal": "volkswagen", "parkland-shooting": "parkland",
             "uvalde-shooting": "uvalde", "pulse-nightclub-shooting": "pulse", "me-too-movement": "metoo"}
    for r in out:
        if r.get("date") and len(r["date"]) == 4 and by_id.get(r["id"]) in wiki and wiki[by_id[r["id"]]]["date"][:4] == r["date"]:
            r["date"] = wiki[by_id[r["id"]]]["date"]
        if r.get("date") and len(r["date"]) == 4:
            k = key(r["stone"])
            if k in exact and exact[k][:4] == r["date"]:
                r["date"] = exact[k]
    for article, year in _literal(os.path.join(LAB, "discovery", "famous_decoys.py"), "FAMOUS"):
        disp = re.sub(r"\s*\(.*\)$", "", article)
        H.setdefault(article, {"type": "work", "amb": article in DECOY_AMB, "word": "film" if article in DECOY_AMB else None,
                               "phrases": None, "guard": None, "case": None, "date": None, "skip": None})
        add(article, disp, article, str(year), "decoy", "work")
    return out


STOPWORDS = {"it", "up", "us", "her", "she", "he", "them", "they", "we", "me", "go", "saw", "the", "a", "an", "this", "that"}
# decoys whose title is an ordinary word or another thing's name in a US government document
DECOY_AMB = {"Transformers (film)", "Minions (film)", "The Hangover", "Frozen II", "Aquaman (film)", "Zootopia", "Moana", "Coco (2017 film)",
             "Inside Out (2015 film)", "The Dark Knight", "Iron Man (2008 film)", "Wonder Woman (2017 film)", "It (2017 film)", "Gravity (2013 film)",
             "Interstellar (film)", "Inception", "Bohemian Rhapsody (film)", "A Star Is Born (2018 film)", "Joker (2019 film)", "Dune (2021 film)",
             "Wicked (2024 film)", "Inside Out 2", "Moana 2", "Elemental (film)", "Lightyear (film)", "Sing (2016 American film)", "Big Hero 6 (film)",
             "Skyfall", "Casino Royale (2006 film)", "La La Land"}


def _slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def _query(phrase, rec):
    """The registered Federal Register query: the exact phrase in quotes, plus the disambiguating word when ambiguous."""
    q = '"' + phrase.replace("\u2019", "'") + '"'
    if rec["amb"] and rec["word"]:
        q += f" {rec['word']}"
    return q


# ---------------------------------------------------------------- matching ---------------------------------------------
def fold(s):
    """Accents off (Lac-Mégantic -> Lac-Megantic), curly quotes and dashes to plain, whitespace collapsed."""
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"').replace("``", '"').replace("''", '"')
    s = s.replace("\u2013", "-").replace("\u2014", "-").replace("\u00a0", " ")
    return re.sub(r"\s+", " ", s).strip()


def phrase_rx(phrase, case):
    p = fold(phrase)
    parts = []
    for ch in p:
        if ch == " ":
            parts.append(r"\s+")
        elif ch == "-":
            parts.append(r"-\s?")
        elif ch == "'":
            parts.append(r"['’]")
        elif ch == ",":
            parts.append(r",?")
        else:
            parts.append(re.escape(ch))
    body = "".join(parts)
    pre, post = r"(?<![A-Za-z0-9])", r"(?![A-Za-z0-9])"
    if case == "i":
        return re.compile(pre + body + post, re.I)
    up = "".join(re.escape(c) if c not in " -'," else {" ": r"\s+", "-": r"-\s?", "'": r"['’]", ",": r",?"}[c] for c in p.upper())
    return re.compile(pre + "(?:" + body + "|" + up + ")" + post)


WORK_WORDS = re.compile(r"\b(films?|movies?|motion pictures?|documentar(?:y|ies)|docuseries|miniseries|television|TV|sitcom|novels?|novelist|"
                        r"(?:the|her|his|their|a|landmark|seminal|famous|best-?selling|classic) book|book (?:titled|entitled|called|by)|"
                        r"author|Netflix|HBO|Hulu|aired|broadcast|episodes?|starring|actor|actress|screenplay|directed by|video games?|"
                        r"podcast|album|songs?|musical|Broadway|Disney|Pixar|Hollywood|box office|best-?seller|blockbuster)\b")
EVENT_WORDS = re.compile(r"\b(disaster|spill|explosion|blowout|accident|incident|fire|wildfire|shootings?|massacre|attacks?|bombings?|terroris\w+|"
                         r"hurricane|storm|flood\w*|breach|collapse|crisis|scandal|recalls?|derailment|crash\w*|failure|meltdown|leak|"
                         r"poisonings?|contamination|fraud|bankruptcy|outbreak|sinking|grounding|unrest|protests|riots|movement|tragedy|"
                         r"catastroph\w+|aftermath|victims)\b", re.I)
THING_WORDS = re.compile(r"\b(toys?|products?|app|game|company|challenge|campaign|diet|festival|concert|fad|craze|trend|brand|regulation|"
                         r"court|decision|case|program)\b", re.I)
NAMESAKE = re.compile(r"^[\s,]*(Institute|Foundation|Fund|Inc\b|LLC|L\.L\.C\.|Corp\b|Corporation|Company|Co\.|Center|Centre|Associates|"
                      r"Partners|Road|Rd\.|Street|St\.|Drive|Avenue|Ave\.|Lane|Boulevard|Blvd|Farms?|Ranch|Creek|River|Lake|Park|Mine|"
                      r"Field|Lease|Pipeline|Productions|Entertainment|Records|Studios|Township|County|Subdivision|Estates|Apartments|"
                      r"Trail|Bay|Island|Beach|Hotel|Casino|Resort|Mall|Ltd|Limited|Holdings|Group|L\.P\.|LP\b|Elementary|Middle School)")
PREAMBLE_END = re.compile(r"\bList of Subjects\b|For the reasons (?:stated|set (?:forth|out)|discussed) in the preamble")
NOT_A_MARK = re.compile(r"\b(correction|correcting amendments?|technical amendments?|technical corrections?|delay of effective date|stay of|"
                        r"withdrawal|extension of (?:comment period|compliance dates?)|confirmation of effective date|"
                        r"announcement of effective date|removal of expired)\b", re.I)


def year_of(d):
    return int(d[:4]) if d else None


INTRO_BEFORE = re.compile(r"\b(?:films?|movies?|motion picture|documentary|docuseries|miniseries|series|show|sitcom|drama|novel|book|album|"
                          r"song|single|musical|play|video game|game|podcast)\s*,?\s*(?:titled|entitled|called|named)?\s*\"?$", re.I)
INTRO_AFTER = re.compile(r"^\"?\s*(?:\(\s*(?:\d{4}\s*)?(?:film|movie|documentary|TV series|series|miniseries|novel|book|album|song|video game|game)\s*\)|"
                         r",\s*(?:a|an|the)\s+(?:[\w'.-]+\s+){0,3}(?:film|movie|documentary|docuseries|miniseries|television|TV|series|show|"
                         r"novel|book|album|song|video game|game|podcast|musical)\b)", re.I)
POSSESSIVE = re.compile(r"[A-Z][a-z]+(?: [A-Z]\.)?(?: [A-Z][a-z]+)?'s\s+(?:(?:landmark|seminal|famous|classic|best-?selling|\d{4})\s+)?"
                        r"(?:(?:book|novel|film|documentary|movie|series)\s*,?\s*)?\"?$")


def guard_ok(rec, text, i, j, sent):
    """Context check around the match at text[i:j]. Returns (ok, why).

    work, ambiguous title: the title must be introduced as a work (a work word directly before or after it), carry a
      creator's possessive, sit in quotation marks (titles of two words or more), or have the stone's own anchor word
      (its creator, its subject) in the same sentence. A work word somewhere nearby is not enough (the WarGames lesson).
    work, distinctive title: any of the above, or a work word within 160 characters.
    event, ambiguous name: the stone's own event words in the same sentence. Distinctive names pass.
    thing, ambiguous name: the stone's own words or a category word in the same sentence. Distinctive names pass.
    Works and things also fail when the match is the first part of another thing's name (Silent Spring Institute)."""
    win = text[max(0, i - 160): j + 160]
    t = rec["type"]
    extra = re.compile(rec["guard"]) if rec.get("guard") else None
    if t in ("work", "thing") and NAMESAKE.search(text[j:j + 40]):
        return False, "namesake: " + text[j:j + 30].strip()
    if t == "work":
        before, after = text[max(0, i - 60): i], text[j: j + 80]
        if INTRO_BEFORE.search(before) or INTRO_AFTER.search(after):
            return True, "introduced as a work"
        if POSSESSIVE.search(before):
            return True, "a creator's possessive"
        if len(rec["phrases"][0].split()) >= 2 and text[i - 1: i] == '"' and text[j: j + 1] in ('"', ",", "."):
            return True, "a quoted title"
        if extra and extra.search(sent):
            return True, "the stone's own anchor word in the sentence"
        if not rec["amb"] and WORK_WORDS.search(win):
            return True, "a work word nearby"
        return False, "not introduced as a work"
    if not rec["amb"]:
        return True, "a distinctive name"
    if t == "event":
        if extra and extra.search(sent):
            return True, "the stone's event words in the sentence"
        return False, "no event word in the sentence"
    if (extra and extra.search(sent)) or THING_WORDS.search(sent):
        return True, "category word in the sentence"
    return False, "no category word in the sentence"


def sentence_at(text, i, j, cap=600):
    """The sentence holding text[i:j]: from the previous sentence end to the next one, capped around the match."""
    ends = [m.end() for m in re.finditer(r"[.!?][\"')\]]?\s+(?=[A-Z\"(\[])", text[max(0, i - 900): i])]
    start = max(0, i - 900) + (ends[-1] if ends else 0)
    m = re.search(r"[.!?][\"')\]]?(?=\s+[A-Z\"(\[]|\s*$)", text[j: j + 900])
    end = j + (m.end() if m else min(900, len(text) - j))
    s = text[start:end].strip()
    if len(s) > cap:
        a = max(start, i - cap // 2)
        s = ("..." if a > start else "") + text[a: a + cap].strip() + "..."
    return s


def window3(text, i, j, cap=700):
    """The sentence before, the sentence, and the sentence after: what cite_score reads (bill_act's windows ran about 600)."""
    a = sentence_at(text, i, j, cap=10 ** 6)
    k = text.find(a[:40]) if a else i
    prev = text[max(0, k - 400): k]
    pm = list(re.finditer(r"[.!?][\"')\]]?\s+(?=[A-Z\"(\[])", prev))
    start = max(0, k - 400) + (pm[-2].end() if len(pm) >= 2 else 0) if pm else max(0, k - 200)
    e = k + len(a)
    nm = re.search(r"[.!?][\"')\]]?(?=\s+[A-Z\"(\[]|\s*$)", text[e + 1: e + 400])
    end = e + 1 + (nm.end() if nm else 200)
    w = text[start:end].strip()
    if len(w) > cap:
        c = max(0, i - start - cap // 2)
        w = w[c: c + cap]
    return w


def extract(rec, raw):
    """Every occurrence of the stone's phrases in a final rule's preamble, guarded and scored; the best one returned."""
    text = fold(raw)
    m = PREAMBLE_END.search(text)
    pre = text[: m.start()] if m else text
    hits, fails = [], []
    for ph in rec["phrases"]:
        rx = phrase_rx(ph, rec.get("case"))
        for mm in rx.finditer(pre):
            sent = sentence_at(pre, mm.start(), mm.end())
            ok, why = guard_ok(rec, pre, mm.start(), mm.end(), sent)
            if not ok:
                fails.append({"why": why, "snippet": pre[max(0, mm.start() - 90): mm.end() + 90]}); continue
            win = window3(pre, mm.start(), mm.end())
            sc, cwhy = cite_score.score(win, mm.group(0))
            s1, _ = cite_score.score(sent, mm.group(0))
            hits.append({"phrase": ph, "pos": mm.start(), "sentence": sent, "window": win, "s1": s1,
                         "cite_score": sc, "cite_why": cwhy, "cite_label": cite_score.label(sc), "guard": why})
    best = max(hits, key=lambda x: (x["cite_score"], x["s1"], -x["pos"])) if hits else None
    return best, len(hits), fails[:3], (len(text) if not m else m.start())


# ---------------------------------------------------------------- network ----------------------------------------------
class Stop(Exception):
    pass


_last = [0.0]
_n = [0]


def get(url, want_json=True):
    if _n[0] >= MAX_REQUESTS:
        raise Stop(f"request budget of {MAX_REQUESTS} reached")
    wait = GAP - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    _n[0] += 1
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json" if want_json else "text/plain"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            final = r.geturl()
            body = r.read().decode("utf-8", "replace")
            _last[0] = time.time()
    except urllib.error.HTTPError as e:
        _last[0] = time.time()
        if e.code == 404:
            return None
        raise Stop(f"HTTP {e.code} on {url[:120]}")
    except Exception as e:  # noqa: BLE001  (a timeout or a reset is a stop too)
        _last[0] = time.time()
        raise Stop(f"{type(e).__name__} on {url[:120]}: {str(e)[:80]}")
    if "unblock." in final or "Request Access" in body[:3000] and "captcha" in body.lower():
        raise Stop(f"redirected to the access-request page on {url[:120]}")
    if want_json:
        try:
            return json.loads(body)
        except ValueError:
            raise Stop(f"not JSON on {url[:120]}: {body[:80]!r}")
    return body


FIELDS = ["title", "type", "action", "document_number", "publication_date", "effective_on", "agencies", "html_url", "raw_text_url",
          "regulation_id_numbers", "citation", "significant"]


def fr_search(query, gte, types=("RULE",), lte=None, per_page=PER_PAGE):
    params = [("conditions[term]", query), ("per_page", per_page), ("order", "relevance")]
    params += [("conditions[type][]", t) for t in types]
    if gte:
        params.append(("conditions[publication_date][gte]", gte))
    if lte:
        params.append(("conditions[publication_date][lte]", lte))
    params += [("fields[]", f) for f in FIELDS]
    return get(FR + "?" + urllib.parse.urlencode(params))


# ---------------------------------------------------------------- commands ---------------------------------------------
def cmd_plan():
    st = stones()
    live = [s for s in st if not s.get("skip")]
    doc = {"protocol": PROTOCOL, "written": dt.date.today().isoformat(), "source": "Federal Register API v1, final rules (type RULE)",
           "per_page": PER_PAGE, "max_docs_per_stone": MAX_DOCS, "max_requests": MAX_REQUESTS,
           "counts": {"stones": sum(1 for s in live if s["group"] != "decoy"), "decoys": sum(1 for s in live if s["group"] == "decoy"),
                      "skipped": sum(1 for s in st if s.get("skip")), "queries": sum(len(s["queries"]) for s in live),
                      "ambiguous": sum(1 for s in live if s["amb"])},
           "stones": st}
    json.dump(doc, open(QUERIES, "w"), ensure_ascii=False, indent=1)
    print(json.dumps(doc["counts"]))


def _date_gte(d):
    if not d:
        return None
    return d if len(d) == 10 else f"{d[:4]}-01-01"


def cmd_run():
    plan = json.load(open(QUERIES))
    state = json.load(open(RAW)) if os.path.exists(RAW) else {"protocol": PROTOCOL, "started": dt.datetime.utcnow().isoformat(timespec="seconds") + "Z",
                                                              "done": [], "stones": {}, "diagnostics": {}, "log": []}
    today = dt.date.today().isoformat()
    if state.get("stopped", {}).get("date") == today:
        print("stopped earlier today:", state["stopped"]["why"], "- no same-day retry"); return 2

    before = state.get("requests_total", 0)

    def save():
        state["requests_total"] = before + _n[0]
        json.dump(state, open(RAW + ".tmp", "w"), ensure_ascii=False, indent=0)
        os.replace(RAW + ".tmp", RAW)

    try:
        # diagnostics first; they double as the reachability check
        if "jungle" not in state["diagnostics"]:
            d = fr_search('"The Jungle"', "1995-01-01", types=("PRORULE",), lte="1995-12-31")
            nums = [x.get("document_number") for x in (d or {}).get("results", [])]
            state["diagnostics"]["jungle"] = {"query": '"The Jungle" PRORULE 1995', "count": (d or {}).get("count"), "found_95_2366": "95-2366" in nums,
                                              "docs": nums[:10]}
            print("diag jungle:", state["diagnostics"]["jungle"], flush=True); save()
        if "jungle_text" not in state["diagnostics"]:
            rec = next(s for s in plan["stones"] if s["id"] == "the-jungle-fda")
            raw = get("https://www.federalregister.gov/api/v1/documents/95-2366.json?fields[]=raw_text_url&fields[]=title")
            body = get(raw["raw_text_url"], want_json=False) if raw and raw.get("raw_text_url") else None
            best, n, fails, _ = extract(rec, body or "") if body else (None, 0, [], 0)
            state["diagnostics"]["jungle_text"] = {"text": bool(body), "passing": n, "best": best and {k: best[k] for k in ("sentence", "cite_label", "cite_why", "guard")},
                                                   "fails": fails}
            print("diag jungle text:", n, best and best["sentence"][:200], flush=True); save()
        if "silent_spring_institute" not in state["diagnostics"]:
            rec = next(s for s in plan["stones"] if s["id"] == "silent-spring-ddt")
            raw = get("https://www.federalregister.gov/api/v1/documents/2022-25946.json?fields[]=raw_text_url&fields[]=title")
            body = get(raw["raw_text_url"], want_json=False) if raw and raw.get("raw_text_url") else None
            best, n, fails, _ = extract(rec, body or "") if body else (None, 0, [], 0)
            state["diagnostics"]["silent_spring_institute"] = {"text": bool(body), "passing": n, "screened": [f["why"] for f in fails],
                                                               "expected": "0 passing (the Institute is a namesake)"}
            print("diag Silent Spring Institute:", n, [f["why"] for f in fails], flush=True); save()

        for rec in plan["stones"]:
            if rec.get("skip") or rec["id"] in state["done"]:
                continue
            gte = _date_gte(rec.get("date"))
            docs, counts = {}, {}
            for q in rec["queries"]:
                d = fr_search(q, gte)
                counts[q] = (d or {}).get("count", 0)
                for x in (d or {}).get("results", []) or []:
                    docs.setdefault(x["document_number"], x)
            # relevance order across the queries: first query's list first, then the next query's new ones
            cands, skipped = [], []
            for num, x in docs.items():
                why = NOT_A_MARK.search(f"{x.get('title') or ''} {x.get('action') or ''}")
                if why:
                    skipped.append({"document_number": num, "title": (x.get("title") or "")[:120], "why": why.group(0)}); continue
                cands.append(x)
            read = []
            for x in cands[:MAX_DOCS]:
                if not x.get("raw_text_url"):
                    read.append({"document_number": x["document_number"], "no_text": "no raw_text_url"}); continue
                body = get(x["raw_text_url"], want_json=False)
                if body is None:
                    read.append({"document_number": x["document_number"], "no_text": "404"}); continue
                best, n, fails, plen = extract(rec, body)
                pub = x.get("publication_date")
                sd = rec.get("date") or ""
                ordered = (pub > sd) if len(sd) == 10 else ("same year" if pub[:4] == sd[:4] else pub[:4] > sd[:4]) if sd else None
                item = {"document_number": x["document_number"], "title": x.get("title"), "type": x.get("type"), "action": x.get("action"),
                        "agencies": [a.get("name") or a.get("raw_name") for a in (x.get("agencies") or [])], "publication_date": pub,
                        "effective_on": x.get("effective_on"), "html_url": x.get("html_url"), "citation": x.get("citation"),
                        "rins": x.get("regulation_id_numbers") or [], "significant": x.get("significant"), "ordered": ordered,
                        "passing": n, "fails": fails, "preamble_chars": plen}
                if best:
                    item.update({k: best[k] for k in ("phrase", "sentence", "window", "cite_score", "cite_why", "cite_label", "guard")})
                    item["strict"] = bool(ordered is True and best["cite_label"] == "reason")
                read.append(item)
            state["stones"][rec["id"]] = {"stone": rec["stone"], "group": rec["group"], "type": rec["type"], "date": rec.get("date"),
                                          "counts": counts, "found": len(docs), "not_marks": skipped, "read": read}
            state["done"].append(rec["id"])
            hits = [r for r in read if r.get("passing")]
            print(f"{rec['group']:8s} {rec['stone'][:34]:34s} | found {len(docs):3d} | read {len(read):2d} | passing {len(hits):2d} | strict "
                  f"{sum(1 for r in hits if r.get('strict'))}", flush=True)
            save()
    except Stop as e:
        state["stopped"] = {"date": today, "why": str(e)}
        print("STOP:", e, flush=True)
    state["finished"] = dt.datetime.utcnow().isoformat(timespec="seconds") + "Z"
    save()
    return 0


def surviving(state):
    for sid, s in state["stones"].items():
        for r in s["read"]:
            if r.get("passing"):
                yield sid, s, r


def cmd_review(group=None):
    state = json.load(open(RAW))
    for sid, s, r in surviving(state):
        if group and s["group"] != group:
            continue
        print(f"\n## {sid}|{r['document_number']}  [{s['group']}] {s['stone']} ({s['date']}) -> {r['publication_date']} {r['title'][:110]}")
        print(f"   {', '.join(r['agencies'][:2])} | ordered {r['ordered']} | cite {r['cite_label']} {r['cite_score']} {r['cite_why']} | strict {r.get('strict')}")
        print("   " + r["sentence"])


def cmd_build():
    state = json.load(open(RAW))
    hand = json.load(open(HAND)) if os.path.exists(HAND) else {}
    plan = json.load(open(QUERIES))
    pairs, screened = [], []
    for sid, s, r in surviving(state):
        key = f"{sid}|{r['document_number']}"
        hl = hand.get(key, {})
        row = {"stone_id": sid, "work": s["stone"], "work_date": s["date"], "group": s["group"], "stone_type": s["type"],
               "rule": r["title"], "document_number": r["document_number"], "publication_date": r["publication_date"], "ordered": r["ordered"],
               "cite_score": r["cite_score"], "cite_label": r["cite_label"], "strict": r.get("strict"), "hand_label": hl.get("label"),
               "via": hl.get("via"), "note": hl.get("note"), "sentence": r["sentence"], "url": r["html_url"]}
        screened.append(row)
        if s["group"] != "decoy" and hl.get("label") == "reason" and r["ordered"] is True:
            pairs.append({"work": s["stone"], "work_date": s["date"], "bill": (r["rins"][0] if r["rins"] else r["document_number"]),
                          "debated": r["publication_date"], "act": r["title"], "country": "US", "cite_score": r["cite_score"],
                          "cite_why": r["cite_why"], "cite_label": r["cite_label"], "royal_assent": r.get("effective_on") or r["publication_date"],
                          "act_url": r["html_url"], "ordered": True, "sentence": r["sentence"], "debate_url": r["html_url"],
                          "kind": "rule", "source": "Federal Register", "hand_label": "reason", "via": hl.get("via"), "new": hl.get("new"),
                          "agency": ", ".join(r["agencies"][:2]), "document_number": r["document_number"], "fr_citation": r.get("citation"),
                          "rin": r["rins"], "rule_action": r.get("action"), "publication_date": r["publication_date"],
                          "effective_on": r.get("effective_on"), "stone_type": s["type"], "note": hl.get("note"),
                          "court": None, "case_name": None, "date_filed": None, "opinion_url": None, "holding_mark": None})
    pairs.sort(key=lambda p: (p["work"], p["debated"]))
    dec = [s for s in state["stones"].values() if s["group"] == "decoy"]
    stn = [s for s in state["stones"].values() if s["group"] != "decoy"]
    decoy_strict = sorted({s["stone"] for s in dec for r in s["read"] if r.get("strict")})
    decoy_hand = sorted({row["work"] for row in screened if row["group"] == "decoy" and row["hand_label"] == "reason"})
    labeled = [x for x in screened if x["hand_label"] and x["group"] != "decoy"]
    tp = sum(1 for x in labeled if x["hand_label"] == "reason" and x["cite_label"] == "reason")
    fp = sum(1 for x in labeled if x["hand_label"] != "reason" and x["cite_label"] == "reason")
    fn = sum(1 for x in labeled if x["hand_label"] == "reason" and x["cite_label"] != "reason")
    distinct = {(p["work"], tuple(p["rin"]) or p["document_number"]) for p in pairs}
    new = {(p["work"], tuple(p["rin"]) or p["document_number"]) for p in pairs if p.get("new")}
    out = {"protocol": PROTOCOL, "run": state.get("started", "")[:10], "finished": state.get("finished"),
           "sources": {"federal_register": {"api": "https://www.federalregister.gov/api/v1/documents.json", "key": "none",
                                            "requests": state.get("requests_total"), "stopped": state.get("stopped")},
                       "courtlistener": {"api": "https://www.courtlistener.com/api/rest/v4/search/", "status": "not run: the REST API "
                                         "documentation says authentication is necessary (a token tied to an account); none was created",
                                         "documented_limits": "authenticated: 5 requests a minute, 50 an hour, 125 a day"}},
           "diagnostics": state.get("diagnostics"),
           "summary": {"stones_searched": len(stn), "decoys_searched": len(dec), "skipped": plan["counts"]["skipped"],
                       "stones_with_a_final_rule_found": sum(1 for s in stn if s["found"]),
                       "surviving_sentences": sum(1 for x in screened if x["group"] != "decoy"),
                       "surviving_sentences_decoys": sum(1 for x in screened if x["group"] == "decoy"),
                       "hand": {k: sum(1 for x in labeled if x["hand_label"] == k) for k in ("reason", "context", "aside")},
                       "pairs_reason": len(pairs), "distinct_stone_rulemakings": len(distinct), "new_distinct": len(new),
                       "decoys_passing_strict_rule": decoy_strict, "decoys_passing_hand_read": decoy_hand,
                       "cite_score_vs_hand": {"tp": tp, "fp": fp, "fn": fn, "precision": round(tp / max(1, tp + fp), 2),
                                              "recall": round(tp / max(1, tp + fn), 2)}},
           "pairs": pairs, "screened": screened}
    json.dump(out, open(OUT, "w"), ensure_ascii=False, indent=1)
    print(json.dumps(out["summary"], indent=1))


def cmd_selftest():
    rec = {"type": "work", "amb": True, "word": "book", "phrases": ["Silent Spring"], "guard": r"Rachel Carson|Carson's", "case": "s", "date": "1962-09-27"}
    t = ("Comments came from Earthjustice and Silent Spring Institute (Ref. 15). In 1962, Rachel Carson's Silent Spring raised public "
         "awareness of pesticide residues, which led to new rules. The silent spring of the marsh was noted.")
    best, n, fails, _ = extract(rec, t)
    assert n == 1 and "raised public" in best["sentence"], (n, best, fails)
    assert any("namesake" in f["why"] for f in fails), fails
    ev = {"type": "event", "amb": True, "word": "shooting", "phrases": ["Las Vegas"], "guard": r"shooting|bump", "case": "s", "date": "2017-10-01"}
    t2 = "The office in Las Vegas, Nevada will hold a hearing. Following the mass shooting in Las Vegas on October 1, 2017, ATF began this rulemaking."
    best, n, fails, _ = extract(ev, t2)
    assert n == 1 and "ATF began" in best["sentence"], (n, best)
    lm = {"type": "event", "amb": False, "word": None, "phrases": ["Lac-Mégantic"], "guard": None, "case": "s", "date": "2013-07-06"}
    best, n, _, _ = extract(lm, "The derailment at Lac-\nMegantic, Quebec, prompted PHMSA to act. List of Subjects Lac-Megantic")
    assert n == 1, n
    dec = {"type": "work", "amb": True, "word": "film", "phrases": ["Gravity"], "guard": None, "case": "s", "date": "2013"}
    best, n, fails, _ = extract(dec, "The specific gravity of the film was measured. Gravity drains are required.")
    assert n == 0, (n, best)
    print("selftest ok")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "plan"
    sys.exit({"plan": cmd_plan, "run": cmd_run, "build": cmd_build, "selftest": cmd_selftest}.get(cmd, lambda: cmd_review(sys.argv[2] if len(sys.argv) > 2 else None))() or 0)
