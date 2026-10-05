"""Multi-hop ripples v1: compose the automated chains, run the D1 wrong-stone decoys, and build the renderable file.

  compose  stage 1 + hop 2 (laptop) + hop 2 (Congressional Record, from the workflow) -> automated chains for the main set
           and the famous decoys; D1: three wrong stones per main-set chain, hop 1 re-run. Writes multihop_raw_v1.json.
  build    multihop_raw_v1.json + the hand check (multihop_hand_v1.json) -> multihop_v1.json.
Called through multihop.py so the same limiter, cache and stop rule apply.
"""
from __future__ import annotations

import datetime as dt
import glob
import json
import os
import random
import re
import urllib.parse

import numpy as np

import multihop as M
import editor_trail as et

K1 = ("Mr Bates vs The Post Office", {"Paula Vennells", "British Post Office scandal", "Horizon (IT system)"}, "offences act 2024")
K2 = ("Tiger King", {"Joe Exotic", "Carole Baskin"}, "big cat public safety act")


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", (s or "").lower()).strip("-")[:40]


def wiki_url(t):
    return "https://en.wikipedia.org/wiki/" + urllib.parse.quote((t or "").replace(" ", "_"))


def pv_url(t, date):
    d = dt.date.fromisoformat(date)
    a, b = (d - dt.timedelta(days=120)).isoformat(), (d + dt.timedelta(days=90)).isoformat()
    return f"https://pageviews.wmcloud.org/?project=en.wikipedia.org&platform=all-access&agent=user&range={a}..{b}&pages=" + urllib.parse.quote(t.replace(" ", "_"))


def norm_mark(m):
    m = re.sub(r"\(within the .*\)$", "", m or "")
    return re.sub(r"[^a-z0-9]+", " ", m.lower()).strip()


def hop1_step(st, v):
    if v["grade"] == "measured":
        m = v["measured"]
        sent = (f"Daily Wikipedia views of {v['title']} rose {m['ratio']:,}-fold over their baseline from {m['onset']}, after the stone; "
                f"p = {m['p']} against {m['n_placebo']} placebo dates in the page's own history (the checker's attention test).")
        return {"title": f"Attention to {v['title']} surges", "date": m["onset"], "grade": "measured", "intermediate": v["title"],
                "source_label": f"Wikipedia pageviews: {v['title']}", "source_url": pv_url(v["title"], st["date"] if len(st["date"]) == 10 else m["onset"]),
                "sentence": sent, "supporting": [r["text"] for r in v.get("reported", [])[:1]]}
    r = v["reported"][0]
    return {"title": f"{v['title']}, after {st['title']}", "date": v["date"], "grade": "reported", "intermediate": v["title"],
            "source_label": f"Wikipedia: {st['real']} ({r['section']})", "source_url": wiki_url(st["real"]), "sentence": r["text"]}


def hop2_steps(r1, gov):
    """Every in-order hop-2 record for one survivor, as (mark, step) pairs."""
    out = []
    for h in (r1 or {}).get("h1", {}).get("hits", []):
        if h["verdict"] != "in order":
            continue
        out.append(({"title": h["act"], "date": h["royal_assent"], "kind": "Law", "source_label": "legislation.gov.uk" if h.get("act_url") else "UK Parliament Bills API",
                     "source_url": h.get("act_url")},
                    {"title": h["act"], "date": h["royal_assent"], "grade": "reported", "record_date": h["date"], "via": "Hansard",
                     "source_label": f"Hansard, {' '.join(h['debate'].split())}, {h['date']}", "source_url": h.get("url"),
                     "sentence": h["window"], "names_stone": h.get("names_stone"), "cite_why": h.get("cite_why")}))
    for h in (r1 or {}).get("h2", {}).get("hits", []):
        if h["verdict"] != "in order":
            continue
        out.append(({"title": h["mark"], "date": h["mark_date"], "kind": "Law or institution", "source_label": f"Wikipedia: {h['mark']}",
                     "source_url": wiki_url(h["mark"])},
                    {"title": h["mark"], "date": h["mark_date"], "grade": "reported", "record_date": None, "via": "Wikipedia reverse hop",
                     "source_label": f"Wikipedia: {h['mark']}", "source_url": wiki_url(h["mark"]), "sentence": h["sentences"][0],
                     "names_stone": h.get("names_stone"), "dated_by": h.get("dated_by")}))
    for h in (gov or {}).get("hits", []):
        if h.get("verdict") != "in order":
            continue
        out.append(({"title": h["act"], "date": h["enacted"], "kind": "Law", "source_label": "govinfo.gov", "source_url": h.get("act_url")},
                    {"title": h["act"], "date": h["enacted"], "grade": "reported", "record_date": h["date"], "via": "Congressional Record",
                     "source_label": f"Congressional Record, {h['title']}, {h['date']}", "source_url": h.get("url"), "sentence": h["window"],
                     "names_stone": h.get("names_stone"), "cite_why": h.get("cite_why")}))
    return out


def ordered(st, s1, s2):
    """stone <= hop 1 <= record <= mark at the coarser precision of each pair."""
    if not M.ge(s1["date"], st["date"]):
        return False
    if s2.get("record_date") and not (M.ge(s2["record_date"], s1["date"]) and M.ge(s2["date"], s2["record_date"])):
        return False
    return M.ge(s2["date"], s1["date"])


def chains_for(stones, hop2, gov):
    out = []
    for st in stones:
        for v in st.get("survivors", []):
            key = f"{st['real']}|{v['title']}"
            s1 = hop1_step(st, v)
            seen = {}
            for mark, s2 in hop2_steps(hop2.get(key), gov.get(key)):
                if not mark["title"] or not ordered(st, s1, s2):
                    continue
                nm = norm_mark(mark["title"])
                if nm in seen:
                    seen[nm]["other_records"].append({"via": s2["via"], "source_label": s2["source_label"], "source_url": s2["source_url"], "sentence": s2["sentence"][:400]})
                    continue
                c = {"id": f"{slug(st['title'])}--{slug(v['title'])}--{slug(mark['title'])}", "set": st["set"],
                     "stone": {"title": st["title"], "article": st["real"], "date": st["date"], "url": wiki_url(st["real"])},
                     "intermediate": {"title": v["title"], "qid": v.get("qid"), "url": wiki_url(v["title"])},
                     "steps": [s1, s2], "mark": mark, "weakest": "reported", "context": "", "other_records": []}
                seen[nm] = c
                out.append(c)
    return out


# ---------- D1: wrong stones ----------
def as_date(s):
    return dt.date.fromisoformat(s if len(s) == 10 else s[:4] + "-07-01")


def measurable_for(title, date):
    """Can the checker's attention test run for this article at this date (a baseline and at least 20 placebo windows)?"""
    if len(date) != 10:
        return False
    d = dt.date.fromisoformat(date)
    if d < M.PAGEVIEWS_FROM or d > M.TODAY - dt.timedelta(days=45):
        return False
    s = et.series(title, d)
    if not s:
        return False
    end = min(d + dt.timedelta(days=75), M.TODAY - dt.timedelta(days=2))
    v = et.to_array(s, end)
    ri = (d - et.DAY0).days
    if not et.valid(v, ri - 30):
        return False
    return sum(1 for e in range(130, ri - 200, 14) if et.valid(v, e)) >= 20


def wrong_stone_hop1(inter, wrong, names):
    """Hop 1 for a known intermediate against a wrong stone: measured where it can run, and reported."""
    res = {"wrong_stone": wrong["real"], "date": wrong["date"]}
    if measurable_for(inter, wrong["date"]):
        m = M.hop1_measured(inter, wrong["date"])
        res["measured"] = {k: m.get(k) for k in ("verdict", "onset", "ratio", "p", "n_placebo")}
    rd = M.read_stone(wrong["article"])
    hits = []
    if rd:
        tmp = {"date": wrong["date"], "read": rd}
        name_map = {inter: (M.bare(inter) if M.guarded(M.bare(inter)) else None)}
        for n in names:
            name_map[n] = n
        rep = M.reported_sentences(tmp, name_map)
        targets_me = {inter} | set(names)
        hits = [x for t, xs in rep.items() if t in targets_me for x in xs]
    res["reported"] = hits[:3]
    res["pass"] = bool((res.get("measured") or {}).get("verdict") == "measured" or hits)
    return res


def d1(chains, stones):
    rng = random.Random(M.SEED)
    by_real = {s["real"]: s for s in stones if s.get("real")}
    out = []
    done = {}
    for c in chains:
        st = by_real[c["stone"]["article"]]
        v = next(x for x in st["survivors"] if x["title"] == c["intermediate"]["title"])
        k = (st["real"], v["title"])
        if k in done:  # one draw per stone and intermediate: the hop-2 mark does not change hop 1
            out.append({**done[k], "chain": c["id"]})
            continue
        me = {v["title"]} | set(v.get("redirects", []))
        me_t = {M.norm_target(x) for x in me}
        mark_date = c["mark"]["date"] or "9999"
        pool = []
        for w in stones:
            if w is st or not w.get("real") or w["set"] != "main":
                continue
            if abs((as_date(w["date"]) - as_date(st["date"])).days) <= 60:
                continue
            if not M.ge(mark_date, w["date"]):  # the wrong stone must not come after the mark
                continue
            if set(w.get("targets", [])) & me_t:
                continue
            pool.append(w)
        if v["grade"] == "measured":
            pool = [w for w in pool if measurable_for(v["title"], w["date"])]
        pool.sort(key=lambda w: w["real"])
        pick = rng.sample(pool, min(3, len(pool)))
        res = {"stone": st["real"], "intermediate": v["title"], "true_grade": v["grade"], "pool": len(pool),
               "tests": [wrong_stone_hop1(v["title"], w, v.get("names", [])) for w in pick]}
        res["passes"] = sum(1 for t in res["tests"] if t["pass"])
        done[k] = res
        out.append({**res, "chain": c["id"]})
        print(f"  D1 {st['real'][:28]:28s} / {v['title'][:28]:28s} | pool {len(pool):3d} | passes {res['passes']} of {len(res['tests'])}", flush=True)
    return out


# ---------- what the repository already holds ----------
def held_pairs():
    held = []
    for f in glob.glob(os.path.join(M.ROOT, "chains", "batch*.json")):
        d = json.load(open(f))
        for ch in (d if isinstance(d, list) else d.get("chains", [])):
            held.append({"src": "catalog:" + (ch.get("slug") or ""), "title": ch.get("title", ""), "text": json.dumps(ch.get("steps", []))})
    for k, s in json.load(open(os.path.join(M.ROOT, "demo", "discovered_wiki.json")))["stones"].items():
        held.append({"src": "wiki:" + k, "title": s["stone"], "text": json.dumps(s["marks"])})
    for p in json.load(open(os.path.join(M.RES, "bill_act_v1.json"))).get("pairs", []):
        held.append({"src": "bill_act", "title": p["work"], "text": p["act"]})
    return held


def mark_held(c, held):
    stone = c["stone"]["title"].lower()
    art = c["stone"]["article"].lower()
    words = [w for w in re.findall(r"[a-z]{4,}", norm_mark(c["mark"]["title"])) if w not in ("united", "states", "national", "federal", "department", "with", "from")]
    hits = []
    for h in held:
        if stone not in h["title"].lower() and M.bare(art) not in h["title"].lower():
            continue
        low = h["text"].lower()
        if words and all(w in low for w in words):
            hits.append(h["src"])
    return hits


def compose():
    s1 = json.load(open(M.STAGE1))
    hop2 = json.load(open(M.HOP2))["done"]
    gov = json.load(open(M.GOVR))["results"] if os.path.exists(M.GOVR) else {}
    stones = s1["stones"]
    targets = json.load(open(M.SIDECAR))
    for s in stones:
        s["targets"] = targets.get(s["article"], [])
    main = chains_for([s for s in stones if s["set"] == "main"], hop2, gov)
    famous = chains_for([s for s in stones if s["set"] == "famous"], hop2, gov)
    held = held_pairs()
    for c in main:
        c["known_positive"] = ("K1" if c["stone"]["article"] == K1[0] and c["intermediate"]["title"] in K1[1] and K1[2] in norm_mark(c["mark"]["title"]) else
                               "K2" if c["stone"]["article"] == K2[0] and c["intermediate"]["title"] in K2[1] and K2[2] in norm_mark(c["mark"]["title"]) else None)
        c["mark_already_held"] = mark_held(c, held)
    print(f"automated chains: main {len(main)}, famous decoys {len(famous)} from {len({c['stone']['article'] for c in famous})} films", flush=True)
    d1r = []
    try:
        d1r = d1(main, stones)
    except M.Stop as e:
        print("D1 stopped:", e, flush=True)
    raw = {"protocol": "ripples/docs/multihop_plan_v1.md", "run": M.TODAY.isoformat(), "requests_compose": dict(M.COUNTS), "stopped": M.STATE["stopped"],
           "counts": {"stones_main": sum(1 for s in stones if s["set"] == "main"), "stones_famous": sum(1 for s in stones if s["set"] == "famous"),
                      "survivors_main": sum(len(s.get("survivors", [])) for s in stones if s["set"] == "main"),
                      "survivors_famous": sum(len(s.get("survivors", [])) for s in stones if s["set"] == "famous"),
                      "chains_main": len(main), "chains_famous": len(famous), "famous_films_with_a_chain": len({c["stone"]["article"] for c in famous}),
                      "d1_tests": sum(len(r["tests"]) for r in {(r["stone"], r["intermediate"]): r for r in d1r}.values()),
                      "d1_passes": sum(r["passes"] for r in {(r["stone"], r["intermediate"]): r for r in d1r}.values())},
           "main": main, "famous": famous, "d1": d1r}
    M.write_json(raw, M.RAW, indent=1)
    print(json.dumps(raw["counts"], indent=1), flush=True)


def build():
    raw = json.load(open(M.RAW))
    hand = json.load(open(M.HAND))
    keep, rejected = [], []
    for c in raw["main"]:
        h = hand["verdicts"].get(c["id"])
        if not h:
            raise SystemExit(f"no hand verdict for {c['id']}")
        steps = []
        for s in c["steps"]:
            steps.append({k: s.get(k) for k in ("title", "date", "grade", "source_label", "source_url", "sentence")} |
                         ({"record_date": s["record_date"]} if s.get("record_date") else {}))
        if h.get("titles"):
            for i, t in enumerate(h["titles"]):
                if t:
                    steps[i]["title"] = t
        row = {"id": c["id"], "stone": {"title": c["stone"]["title"], "date": c["stone"]["date"], "source_url": c["stone"]["url"]},
               "intermediate": c["intermediate"]["title"], "steps": steps,
               "mark": {k: c["mark"].get(k) for k in ("title", "date", "kind", "source_label", "source_url")} | (h.get("mark") or {}),
               "weakest": c["weakest"], "context": "", "known_positive": c.get("known_positive"),
               "mark_already_held": bool(c.get("mark_already_held")), "hand_check": {"verdict": h["verdict"], "note": h.get("note", "")}}
        if h.get("mark_date"):
            row["mark"]["date"] = h["mark_date"]
        if h["verdict"] == "survives":
            keep.append(row)
        else:
            row["hand_check"]["criterion"] = h.get("criterion")
            rejected.append(row)
    out = {"_about": ("Two-hop ripples from the multi-hop engine v1 (docs/multihop_plan_v1.md, registered before the search; results in "
                      "docs/multihop_v1.md). Each chain is stone -> intermediate -> lasting mark. Hop 1 is measured (the checker's attention test "
                      "on the intermediate's Wikipedia views, in order after the stone) or reported (a sentence in the stone's article). Hop 2 is "
                      "reported: a record (Hansard, the Congressional Record, or a law's Wikipedia article) that names the intermediate as a reason "
                      "for the mark. The weakest link is reported. 'context' is the 'It wasn't the only reason' note, left blank for a human editor. "
                      "Every chain listed under 'chains' survived a strict hand check; 'rejected' keeps the automated chains that did not, with why. "
                      "Em dashes inside quoted records are set as en dashes; nothing else in a quote is changed."),
           "run": raw["run"], "chains": keep, "rejected": rejected}
    M.write_json(out, M.FINAL, indent=1)
    print(f"built: {len(keep)} chains, {len(rejected)} rejected", flush=True)


def main(cmd):
    if cmd == "compose":
        compose()
    elif cmd == "build":
        build()
    else:
        raise SystemExit("compose | build")
