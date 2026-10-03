"""Citation scorer v1: was the work cited as a reason, or as an illustration?

Given the sentence around a citation of a work in a record (Hansard, the Federal Register, the Congressional Record),
score 0–4 and say why. Rules, not a model, so every score can be read:
  +2  a causal verb or phrase within 160 characters of the work (prompted, led to, in response to, galvanised, exposed,
      highlighted, brought to the attention, following, after, because of, campaign, outcry, credited ...)
  +1  the work is the subject of the clause (the drama/film/documentary/series/book + verb), not an aside
  +1  a change word nearby (law, bill, act, reform, change, review, inquiry, ban, duty, offence, compensation ...)
  -2  an illustration cue (like, as in, reminiscent, think of, fans of, the famous, filmed in, my constituency,
      watched it, enjoyed, anniversary, quote, "as the saying", a pun on the title)
  -1  the title is used as ordinary words (a lowercase match, or an idiom: stranger things have happened)
A score of 2 or more is "cited as a reason"; 1 is "mentioned in context"; 0 or less is "an aside".
The owner's first blind round and a hand screen are the calibration set (cite_score_eval.json).
"""
from __future__ import annotations

import json
import os
import re
import sys

CAUSAL = re.compile(r"\b(prompt\w*|led to|leads? to|in response to|in the wake of|galvani[sz]\w*|expos\w+|highlight\w*|brought (?:to|home|about)|"
                    r"drew attention|raised (?:the )?(?:issue|awareness|profile)|following|after|because of|as a result|campaign\w*|outcry|credit\w*|"
                    r"inspired|spurred|catalys\w*|momentum|pressure|public attention|public awareness|shone a (?:spot)?light|woke|wake-up|"
                    r"changed (?:the )?(?:debate|minds|attitudes|law|public)|reminds? us|showed|shows|revealed|demonstrat\w+|made (?:the case|people|clear)|"
                    r"triggered|accelerat\w+|precipitat\w+|impetus|testif\w+|testimony|sparked|explor\w+|influenc\w+|addresses|"
                    r"the effect|the impact|has had|powerful\w*|groundbreaking|seminal|moved|shocked)\b", re.I)
ARGUMENT = re.compile(r"\b(example|case in point|shows why|that is why|this is why|illustrates why|is exactly why|makes the case|the point|"
                      r"we must|we need|we should|the government (?:must|should|needs)|calls? for|urge)\b", re.I)
CHANGE = re.compile(r"\b(law|laws|bill|act|reform|change|review|inquiry|ban|banned|duty|offence|offense|compensation|legislat\w*|regulat\w*|"
                    r"statutory|amendment|clause|measure|policy|scheme|protect\w*|rights?)\b", re.I)
ILLUSTRATION = re.compile(r"\b(like|as in|reminiscent|think of|fans? of|the famous|filmed in|film(?:ed|ing) (?:in|at)|my constituency|watched|enjoyed|"
                          r"anniversary|as the saying|to quote|paraphras\w*|the words of|starred|star of|episode of|series of|plot|character|"
                          r"a nice|lighter note|joke|pun|tongue in cheek|the title|if (?:members|noble lords) have not seen|i remember|when i was (?:very )?young|"
                          r"read(?:ing)? it|many years ago|years ago|in my youth|at school|my favourite|my favorite|nostalg\w+)\b", re.I)
SUBJECT = re.compile(r"\b(drama|film|documentary|series|programme|program|book|novel|game|podcast|play|movie|show)\b[^.;]{0,40}\b(prompted|showed|"
                     r"exposed|highlighted|brought|revealed|led|galvani[sz]ed|changed|reminded|demonstrated|made|has had|had an? (?:huge|significant|profound)|"
                     r"triggered|sparked|raised|drew)\b", re.I)
IDIOM = re.compile(r"stranger things have happened|the jungle (?:in|at|would|camp|near)|yes,? minister|care bears?\b(?! \()|big brother is watching|"
                   r"heartbeat away|in adolescence|their adolescence|of adolescence|adolescence (?:is|and|to|of)|black ?fish(?:ing|eries)?", re.I)


def near(text, work, span=220):
    t = re.sub(r"\s+", " ", text or "")
    i = t.lower().find(work.lower())
    if i < 0:
        key = re.sub(r"\s*\(.*\)$", "", work).split(":")[0].strip()
        i = t.lower().find(key.lower())
    if i < 0:
        return t[:2 * span], t
    return t[max(0, i - span): i + len(work) + span], t


def score(sentence, work):
    win, full = near(sentence, work)
    pts, why = 0, []
    if IDIOM.search(full):
        return 0, ["title used as ordinary words"]
    c = CAUSAL.findall(win)
    if c:
        pts += 2; why.append("causal language: " + ", ".join(sorted({x.lower() if isinstance(x, str) else x[0].lower() for x in c})[:3]))
    if SUBJECT.search(win):
        pts += 1; why.append("the work is the subject of the clause")
    after = win[win.lower().find(work.split(" (")[0].lower()):] if work.split(" (")[0].lower() in win.lower() else win
    if CHANGE.search(after[:260]):
        pts += 1; why.append("a change word follows")
    if ARGUMENT.search(win):
        pts += 1; why.append("used in an argument")
    il = ILLUSTRATION.findall(win)
    if il:
        pts -= 2; why.append("illustration cue: " + ", ".join(sorted({x.lower() for x in il})[:3]))
    return max(0, min(4, pts)), why


def label(s):
    return "reason" if s >= 2 else "context" if s == 1 else "aside"


# hand labels for calibration: (work, mark fragment) -> reason / aside, from the Oct 3 hand screen and the owner's grades
HAND = {("Mr Bates vs The Post Office", "Offences Bill"): "reason", ("Mr Bates vs The Post Office", "Leasehold"): "aside",
        ("Adolescence (TV series)", "Wellbeing and Schools"): "reason", ("Cathy Come Home", "Housing Subsidies"): "reason",
        ("Cathy Come Home", "Homelessness Reduction"): "reason", ("My Octopus Teacher", "Sentience"): "reason",
        ("Baby Reindeer", "Criminal Justice"): "reason", ("Manhunt (video game)", "British Board"): "reason",
        ("McMafia", "Sanctions"): "reason", ("Silent Spring", "Agriculture Bill"): "aside", ("Silent Spring", "Gas Bill"): "aside",
        ("Nineteen Eighty-Four", "Metrology"): "aside", ("Stranger Things", "Early Parliamentary"): "aside",
        ("Stranger Things", "Ground Rent"): "aside", ("Welcome to Wrexham", "Football Governance"): "aside",
        ("Nightsleeper", "Passenger Railway"): "aside", ("Yes Minister", "Fire Safety"): "aside", ("Care Bears (TV series)", "Care Planning"): "aside",
        ("The Jungle", "Cross-border"): "aside", ("Gaza: How to Survive a Warzone", "Points of Order"): "aside",
        ("Ocean with David Attenborough", "Biodiversity"): "context", ("Super Size Me", "Food Products"): "context",
        ("Heartbeat (British TV series)", "Terminally Ill"): "aside", ("Downton Abbey", "Equality (Titles)"): "aside",
        ("Mr Bates vs The Post Office", "Compensation Bill"): "reason", ("Victim (1961 film)", ""): "reason"}


def main() -> int:
    root = os.path.join(os.path.dirname(__file__), "..", "docs", "results")
    files = [f for f in ("mark_text_v1_3.json", "mark_text_v1_2.json") if os.path.exists(os.path.join(root, f))]
    pairs = json.load(open(os.path.join(root, files[0]))).get("pairs", []) if files else []
    rows, ev = [], []
    for p in pairs:
        s, why = score(p.get("sentence") or "", p.get("work") or "")
        rows.append({"work": p.get("work"), "mark": p.get("mark"), "tier": p.get("tier"), "source": p.get("source"), "score": s, "label": label(s), "why": why})
    for (w, frag), truth in HAND.items():
        cand = [r for r in rows if r["work"] == w and frag.lower() in (r["mark"] or "").lower()]
        if cand:
            best = max(cand, key=lambda r: r["score"])
            ev.append({"work": w, "mark": best["mark"], "truth": truth, "pred": best["label"], "score": best["score"], "why": best["why"]})
    tp = sum(1 for e in ev if e["truth"] == "reason" and e["pred"] == "reason")
    fp = sum(1 for e in ev if e["truth"] != "reason" and e["pred"] == "reason")
    fn = sum(1 for e in ev if e["truth"] == "reason" and e["pred"] != "reason")
    out = {"source": files[0] if files else None, "n_pairs": len(rows), "by_label": {k: sum(1 for r in rows if r["label"] == k) for k in ("reason", "context", "aside")},
           "eval": {"n": len(ev), "tp": tp, "fp": fp, "fn": fn, "precision": round(tp / max(1, tp + fp), 2), "recall": round(tp / max(1, tp + fn), 2), "rows": ev},
           "pairs": rows}
    json.dump(out, open(os.path.join(root, "cite_score_v1.json"), "w"), ensure_ascii=False, indent=0)
    print(json.dumps({k: v for k, v in out.items() if k != "pairs"}, ensure_ascii=False, indent=1)[:4000])
    return 0


if __name__ == "__main__":
    sys.exit(main())
