"""Build a query grid file: every (event class x outcome domain) cell becomes a query family.

    python3 ripples/engine/generate/make_queries.py --out ripples/engine/generate/queries/<name>.json --plan PLAN.md
    python3 ripples/engine/generate/make_queries.py --dry-run          # print the counts; write nothing

Run once, before the first request of a new run, and never overwrite a frozen file: the harvest refuses to mix query
files in one work directory, and the plan registers the file's sha256. Each cell gets two OpenAlex queries (design term
A is always "natural experiment"; design term B depends on the event class) and, for O5 cells, two PubMed queries.
The frozen file of the discovery v4 pilot is queries/discovery_v4.json, sha256
b377d9e8e7dc6c0d2a869fc97d0ca6117d6bc949ca280489f684e8d5eb9fd37f. Run with the v4 plan, this script reproduces its
cells, sampling and scoring rules; only frozen_utc (and plan_sha256, for another plan) differ.
"""
import argparse, datetime, hashlib, json, os

EVENTS = {
    "I1": {"name": "sports results and big games",
           "words": ['"Super Bowl"', '"World Cup"', '"football game"', '"football match"', '"sporting event"', '"sports event"',
                     '"home team"', '"upset loss"', '"unexpected loss"', '"playoff"', '"championship game"', '"Olympic Games"',
                     '"NFL"', '"college football"']},
    "I2": {"name": "media arrival and rollout",
           "words": ['"introduction of television"', '"arrival of television"', '"television signal"', '"TV signal"',
                     '"cable television"', '"cable TV"', '"satellite television"', '"radio broadcasts"', '"radio coverage"',
                     '"broadband"', '"high-speed internet"', '"mobile phone coverage"', '"3G"', '"Fox News"', '"television channel"']},
    "I3": {"name": "entertainment releases",
           "words": ['"movie release"', '"film release"', '"blockbuster"', '"box office"', '"video game release"',
                     '"television series"', '"TV series"', '"TV show"', '"album release"', '"bestseller"', '"best-selling book"',
                     '"Netflix"', 'movie', 'movies', 'film']},
    "I4": {"name": "celebrity moments",
           "words": ['"celebrity"', '"celebrities"', '"public figure"', '"royal wedding"', '"royal family"', '"scandal"',
                     '"coming out"', '"pop star"', '"superstar"', '"star player"', '"high-profile death"', '"famous"']},
    "I5": {"name": "one-off shocks",
           "words": ['"blackout"', '"power outage"', '"terrorist attack"', '"terror attack"', '"earthquake"', '"hurricane"',
                     '"natural disaster"', '"solar eclipse"', '"internet outage"', '"mass shooting"', '"bombing"', '"tsunami"',
                     '"wildfire"']},
    "I6": {"name": "tech and product launches",
           "words": ['"smartphone"', '"iPhone"', '"mobile app"', '"app launch"', '"Pokemon Go"', '"Pokémon GO"',
                     '"video game launch"', '"Uber"', '"ride-sharing"', '"ride-hailing"', '"Facebook"', '"Twitter"',
                     '"Craigslist"', '"dating app"', '"online dating"', '"product launch"']},
    "I7": {"name": "dated clock and calendar rule changes",
           "words": ['"daylight saving time"', '"daylight saving"', '"daylight savings"', '"time zone"', '"time-zone"',
                     '"clock change"', '"clock shift"', '"International Date Line"', '"calendar reform"']},
    "I8": {"name": "viral moments, memes, challenges",
           "words": ['"viral video"', '"went viral"', '"viral post"', '"internet meme"', '"meme"', '"online challenge"',
                     '"social media challenge"', '"Ice Bucket Challenge"', '"TikTok"', '"MeToo"', '"hashtag"']},
}

OUTCOMES = {
    "O1": {"name": "births and fertility",
           "words": ['births', '"birth rate"', 'fertility', 'conceptions', '"birth weight"', 'childbearing', 'pregnancies']},
    "O2": {"name": "marriage, divorce, family",
           "words": ['marriage', 'marriages', 'divorce', 'divorces', 'cohabitation', '"family formation"']},
    "O3": {"name": "crime and violence",
           "words": ['crime', 'violence', '"domestic violence"', '"intimate partner violence"', 'assault', '"hate crime"',
                     'homicide', 'arrests']},
    "O4": {"name": "courts, judges, sentencing, juries",
           "words": ['judges', 'sentencing', '"sentence length"', 'jury', 'juries', '"court decisions"', '"judicial decisions"',
                     '"asylum decisions"', 'parole']},
    "O5": {"name": "hospital admissions, injuries, mortality",
           "words": ['"hospital admissions"', '"emergency department"', 'injuries', 'mortality', 'deaths', '"myocardial infarction"',
                     '"cardiovascular events"', 'hospitalizations']},
    "O6": {"name": "traffic and transport accidents",
           "words": ['"traffic accidents"', '"car crashes"', '"traffic crashes"', '"road accidents"', '"traffic fatalities"',
                     '"motor vehicle crashes"', '"fatal crashes"', '"road traffic"']},
    "O7": {"name": "school attendance, test scores, education choices",
           "words": ['"test scores"', '"school attendance"', '"student achievement"', '"exam performance"', '"educational attainment"',
                     '"college major"', '"school enrollment"', '"academic performance"']},
    "O8": {"name": "names and language",
           "words": ['"baby names"', '"first names"', '"given names"', 'naming', '"language use"', '"word use"', 'vocabulary', 'dialect']},
    "O9": {"name": "work, productivity, absenteeism",
           "words": ['productivity', 'absenteeism', '"sick leave"', '"labor supply"', '"work hours"', '"worker performance"',
                     '"labor productivity"']},
    "O10": {"name": "spending outside the stone's own product category",
            "words": ['"consumer spending"', '"household spending"', 'sales', 'purchases', 'consumption', 'expenditure', 'demand']},
    "O11": {"name": "civic acts",
            "words": ['"blood donation"', '"blood donors"', '"organ donation"', '"organ donor"', 'volunteering', '"charitable giving"',
                      'donations', '"census response"', '"civic engagement"']},
}

# Second design term per event class (query A always uses "natural experiment").
DESIGN_B = {"I1": "difference-in-differences", "I2": "difference-in-differences", "I3": "exogenous", "I4": "quasi-experimental",
            "I5": "difference-in-differences", "I6": "difference-in-differences", "I7": "regression discontinuity", "I8": "event study"}

REMOVED = {
    "I4xO5": "topic match: celebrity illness disclosure to screening or care for that illness, and celebrity suicide to suicides, dominate this cell",
    "I8xO11": "topic match: viral challenges and hashtag campaigns to donations or volunteering for their stated cause dominate this cell",
}


def oa_q(i, o, design):
    return "(" + " OR ".join(EVENTS[i]["words"]) + ") AND (" + " OR ".join(OUTCOMES[o]["words"]) + ') AND "' + design + '"'


def pm_term(w):
    w = w.strip('"')
    return f'"{w}"[tiab]' if " " in w or "-" in w else f"{w}[tiab]"


def pm_q(i, o, design):
    ev = " OR ".join(pm_term(w) for w in EVENTS[i]["words"])
    oc = " OR ".join(pm_term(w) for w in OUTCOMES[o]["words"])
    return f"({ev}) AND ({oc}) AND {pm_term(design)}"


cells = []
for i in EVENTS:
    for o in OUTCOMES:
        cid = f"{i}x{o}"
        if cid in REMOVED:
            continue
        c = {"cell": cid, "event_class": i, "outcome_domain": o,
             "openalex": [oa_q(i, o, "natural experiment"), oa_q(i, o, DESIGN_B[i])]}
        if o == "O5":
            c["pubmed"] = [pm_q(i, o, "natural experiment"), pm_q(i, o, DESIGN_B[i])]
        cells.append(c)

ap = argparse.ArgumentParser(description="Build a frozen query grid file.")
ap.add_argument("--out", help="the new query file; must not exist")
ap.add_argument("--plan", help="the registered plan; its sha256 is recorded in the file")
ap.add_argument("--dry-run", action="store_true", help="print the counts; write nothing")
a = ap.parse_args()
if not a.dry_run and not a.out:
    ap.error("--out is required unless --dry-run")

doc = {
    "frozen_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "plan_sha256": hashlib.sha256(open(a.plan, "rb").read()).hexdigest() if a.plan else None,
    "note": "Frozen before the first request. Each (I, O) cell is a query family: two OpenAlex queries (design term A is always "
            "natural experiment; design term B per event class), and two PubMed queries for O5 cells.",
    "sources": {
        "openalex": "https://api.openalex.org/works?search=<q>&per-page=50&select=id,doi,title,publication_year,cited_by_count,abstract_inverted_index,primary_location",
        "pubmed": "esearch.fcgi db=pubmed retmax=40 sort=relevance retmode=json, then efetch.fcgi rettype=abstract retmode=xml",
        "crossref": "backup only, for missing abstracts or dates",
    },
    "event_classes": {k: v for k, v in EVENTS.items()},
    "outcome_domains": {k: v for k, v in OUTCOMES.items()},
    "design_term_b": DESIGN_B,
    "removed_cells": REMOVED,
    "extraction_rules": [
        "A raw pair is (stone, outcome) from one paper that (1) names a specific datable stone in one of the event classes I1 to I8, "
        "(2) measures an outcome in real behavior or records, and (3) uses a quasi-experimental or experimental design against a baseline "
        "(natural experiment, difference in differences, regression discontinuity, event study, interrupted time series, synthetic control, "
        "instrumental variable on the event, randomized trial). Attitude or intention surveys alone, reviews, and plain before-and-after counts are out.",
        "A stone is datable when the paper gives its date or dated instances (a recurring event counts when its instances are dated, "
        "for example each Super Bowl or each spring DST transition). Generic exposure (screen time, media use, sports participation) is not a stone.",
        "Not stones for this pilot: laws, policies, programs and government interventions; the COVID-19 pandemic and lockdowns; weather, "
        "temperature, pollution and seasons; religious observances and holidays; ordinary calendar features (weekends, birthdays, moon phases).",
        "Excluded up front and logged with the reason, never candidates: outcomes of suicide, self-harm or overdose; party-vote outcomes "
        "(vote shares for parties or candidates); topic matches (the outcome is the stone's own subject, stated aim or product: illness "
        "disclosure to screening for that illness; place on screen to tourism there; product to its own sales or use; sport event to that "
        "sport's participation; campaign or documentary to its stated cause; celebrity suicide to suicides; media arrival to viewing of that "
        "medium; the people killed or injured by a disaster or attack itself).",
        "Each raw pair is logged with the cell of the query that found it and the cell it belongs to by content (event class x outcome domain).",
        "Null findings are logged as raw pairs with direction none.",
    ],
    "sampling": {
        "verify_cap": "If more than 100 candidates pass the gate, verify a random 100: Python random.seed(4100), random.sample over sorted candidate ids.",
        "audit": "20 gate rejects at random: random.seed(4200), random.sample over sorted reject ids.",
        "anchors": "10 of yield v1's 56 study items at random: random.seed(4300), random.sample over their item indices; drift = mean absolute change in surprise index against yield v1 scores.json.",
        "controls": "panel_v1.json['items'] where source is planted_obvious or planted_fabricated (10 each), evidence lines from panel_v1/items.json by id.",
    },
    "scoring": {
        "surprise_index": "mean over five raters of (surprise + 6 - predicted) / 2",
        "surprising": "surprise index at least 3.5",
        "defensible": "verified at the paper's own page, PubMed abstract, publisher-deposited abstract or an open copy; quote found; stone date before outcome window; design as claimed",
        "good": "surprising and defensible",
        "law_or_policy_flag": "outcome is a law, policy, vote or turnout, court, judge or jury decision, or government program uptake",
    },
    "cells": cells,
}
doc["counts"] = {"cells": len(cells), "openalex_queries": sum(len(c["openalex"]) for c in cells),
                 "pubmed_queries": sum(len(c.get("pubmed", [])) for c in cells)}
print(doc["counts"])
if not a.dry_run:
    if os.path.exists(a.out):
        raise SystemExit(f"{a.out} exists; a query file is frozen once written")
    json.dump(doc, open(a.out, "w"), indent=1, ensure_ascii=False)
    print("wrote", a.out, "sha256", hashlib.sha256(open(a.out, "rb").read()).hexdigest())
