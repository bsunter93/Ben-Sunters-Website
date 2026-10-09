"""Papers: dedupe harvested records by DOI into data/papers.json, prescreen, and write extraction batches.

    python3 ripples/engine/generate/build_papers.py <wave>                 # e.g. w1; batches of 60
    python3 ripples/engine/generate/build_papers.py <wave> --batch-size 40
    python3 ripples/engine/generate/build_papers.py <wave> --dry-run       # counts only; writes nothing

Prescreen (a script, by word patterns, before the judged extraction step):
  no_abstract     no abstract in the harvest or the Crossref backfill
  no_event_word   no event word of any class
  no_cell_words   no query cell whose event words and outcome words both appear (grid cells only)
  no_design_word  no comparison-design word
  pass            goes to extraction
Writes data/papers.json and data/extract_in/<wave>_bNN.json for papers that pass and were not sent before
(data/extract_sent.json). Each batch holds paper_id, title, year, venue and abstract only.
"""
import argparse, json, os, re, sys
from collections import Counter

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402

EVENT = re.compile(r"super bowl|world cup|football|soccer|nfl\b|nba\b|baseball|basketball|hockey|olympic|sport|match day|home team|"
                   r"playoff|championship|tournament|game day|television|\btv\b|cable|satellite|radio|broadband|internet|3g|4g|mobile phone|"
                   r"cell phone|fox news|channel|broadcast|film|movie|cinema|blockbuster|box office|video game|series|album|song|book|"
                   r"novel|netflix|show|celebrit|famous|royal|scandal|coming out|star\b|death of|blackout|power outage|outage|attack|"
                   r"terror|earthquake|hurricane|disaster|eclipse|shooting|bombing|tsunami|wildfire|flood|smartphone|iphone|app\b|apps\b|"
                   r"launch|pok[eé]mon|uber|lyft|ride-?shar|ride-?hail|facebook|twitter|craigslist|dating|platform|daylight sav|"
                   r"time zone|time-zone|clock|calendar|date line|viral|meme|challenge|tiktok|metoo|hashtag")
DESIGN = re.compile(r"natural experiment|difference-in-difference|differences-in-difference|difference in difference|"
                    r"interrupted time|time[- ]series|regression discontinuity|synthetic control|event[- ]study|quasi-experiment|"
                    r"instrumental variable|exogenous|arima|segmented regression|expected|counterfactual|randomi[sz]ed|"
                    r"fixed effects|control group|comparison group|staggered|plausibly|identification|causal|placebo")

CLS = {
 "I1": r"super bowl|world cup|football|soccer|\bnfl\b|sport|home team|upset|unexpected loss|playoff|championship|olympic|match(es)? day|game day|\bgames?\b|\bmatch(es)?\b|tournament",
 "I2": r"televis|\btv\b|cable|satellite|radio|broadband|internet|mobile phone|cell(ular)? phone|\b[34]g\b|fox news|channel|broadcast|signal",
 "I3": r"movie|film|cinema|blockbuster|box office|video ?game|series|\bshow\b|album|song|bestsell|best-sell|book|novel|netflix|release",
 "I4": r"celebrit|famous|public figure|royal|scandal|coming out|pop star|superstar|star player|death of|icon|athlete",
 "I5": r"blackout|power outage|outage|terror|attack|earthquake|hurricane|cyclone|typhoon|disaster|eclipse|shooting|bombing|tsunami|wildfire|bushfire|flood",
 "I6": r"smartphone|iphone|mobile app|\bapps?\b|launch|pok[eé]mon|uber|lyft|ride-?shar|ride-?hail|facebook|twitter|craigslist|dating|platform|product",
 "I7": r"daylight sav|time zone|time-zone|clock|calendar|date line|\bdst\b",
 "I8": r"viral|meme|challenge|tiktok|metoo|me too|hashtag",
}
DOM = {
 "O1": r"birth|fertilit|concepti|childbear|pregnan",
 "O2": r"marri|divorc|cohabit|family formation",
 "O3": r"crime|crimin|violen|assault|homicid|arrest|offen",
 "O4": r"judge|sentenc|jury|juries|court|judicial|asylum|parole",
 "O5": r"hospital|admission|emergency department|injur|mortalit|death|myocardial|cardiovascular|cardiac",
 "O6": r"traffic|crash|accident|road|motor vehicle|collision",
 "O7": r"test score|attendance|achievement|exam|educational|college major|enrol|academic|school",
 "O8": r"\bnames?\b|naming|language|word use|vocabular|dialect|linguistic",
 "O9": r"productiv|absentee|sick leave|labor supply|labour supply|work hours|worker|employee",
 "O10": r"spending|sales|purchas|consumption|expenditure|demand",
 "O11": r"blood don|organ don|donor|volunteer|charit|donation|census|civic",
}
CLS = {k: re.compile(v) for k, v in CLS.items()}
DOM = {k: re.compile(v) for k, v in DOM.items()}


def cell_words(p, t):
    """True when some query cell's event words and outcome words both appear. Non-grid cells (no IxO id) pass."""
    for qc in p["query_cells"]:
        if "x" not in qc or qc.split("x")[0] not in CLS or qc.split("x")[1] not in DOM:
            return True
        i, o = qc.split("x")
        if CLS[i].search(t) and DOM[o].search(t):
            return True
    return False


def build(work):
    recs = [json.loads(l) for l in open(os.path.join(work, "data", "harvest.jsonl")) if l.strip()]
    extra_p = os.path.join(work, "data", "abstract_backfill.json")
    extra = json.load(open(extra_p)) if os.path.exists(extra_p) else {}
    papers = {}
    for r in recs:
        key = r["doi"] or r["id"]
        p = papers.get(key)
        if p is None:
            p = papers[key] = {"paper_id": key, "doi": r["doi"], "ids": [], "title": r["title"] or "", "year": r["year"],
                               "venue": r["venue"], "abstract": r["abstract"] or "", "cites": r["cites"], "pmid": r["pmid"],
                               "landing": r["landing"], "query_cells": [], "sources": []}
        if r["id"] not in p["ids"]:
            p["ids"].append(r["id"])
        if len(r["abstract"] or "") > len(p["abstract"]):
            p["abstract"] = r["abstract"]
        if r.get("pmid") and not p["pmid"]:
            p["pmid"] = r["pmid"]
        if r.get("landing") and not p["landing"]:
            p["landing"] = r["landing"]
        if r.get("cites") is not None and p["cites"] is None:
            p["cites"] = r["cites"]
        qc = r["query_cell"]
        if qc not in p["query_cells"]:
            p["query_cells"].append(qc)
        if r["src"] not in p["sources"]:
            p["sources"].append(r["src"])
    for key, p in papers.items():
        if not p["abstract"] and key in extra and extra[key].get("abstract"):
            p["abstract"] = extra[key]["abstract"]
            p["abstract_source"] = "crossref"
        t = (p["title"] + " " + p["abstract"]).lower()
        if not p["abstract"]:
            p["prescreen"] = "no_abstract"
        elif not EVENT.search(t):
            p["prescreen"] = "no_event_word"
        elif not cell_words(p, t):
            p["prescreen"] = "no_cell_words"
        elif not DESIGN.search(t):
            p["prescreen"] = "no_design_word"
        else:
            p["prescreen"] = "pass"
    return recs, papers


def main():
    ap = argparse.ArgumentParser(description="Dedupe, prescreen and batch papers for extraction (script step).")
    ap.add_argument("wave", help="a short name for this batch round, e.g. w1")
    ap.add_argument("--batch-size", type=int, default=60)
    ap.add_argument("--dry-run", action="store_true", help="print counts; write nothing")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    recs, papers = build(work)
    sent_p = os.path.join(work, "data", "extract_sent.json")
    sent = json.load(open(sent_p)) if os.path.exists(sent_p) else {}
    todo = [p for p in papers.values() if p["prescreen"] == "pass" and p["paper_id"] not in sent]
    print("records", len(recs), "unique papers", len(papers), dict(Counter(p["prescreen"] for p in papers.values())))
    if a.dry_run:
        print("would send", len(todo), "papers in", -(-len(todo) // a.batch_size), "batches")
        return
    nb = 0
    for i in range(0, len(todo), a.batch_size):
        nb += 1
        name = f"{a.wave}_b{nb:02d}"
        out = os.path.join(work, "data", "extract_in", name + ".json")
        if os.path.exists(out):
            raise SystemExit(f"{out} exists; use a new wave name")
        batch = [{"paper_id": p["paper_id"], "title": p["title"], "year": p["year"], "venue": p["venue"], "abstract": p["abstract"]}
                 for p in todo[i:i + a.batch_size]]
        json.dump(batch, open(out, "w"), indent=1, ensure_ascii=False)
        for p in todo[i:i + a.batch_size]:
            sent[p["paper_id"]] = name
    json.dump(sent, open(sent_p, "w"), indent=1)
    json.dump(list(papers.values()), open(os.path.join(work, "data", "papers.json"), "w"), indent=1, ensure_ascii=False)
    print("new batches", nb, "papers sent", len(todo))


if __name__ == "__main__":
    main()
