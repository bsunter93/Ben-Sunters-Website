"""Screen v2 (docs/screen_plan_v2.md): the v1 labels plus the dating step, compared with the hand keeps minus those that
violate the written definitions. Writes docs/results/screen_labels_v2.json, screen_compare_v2.json and
screen_corpus_v2.json. Run from ripples/docs/results after screen_date.py:

    python3 ../../lab/discovery/screen_v2.py
"""
import importlib.util
import json
import os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("sc1", os.path.join(HERE, "screen_compare.py"))
sc1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc1)

# Newly passing candidates that state a mark an earlier accepted candidate in the same set and stone already states
# (judged by the labeler, plan section "What v2 is", step 6)
DUPLICATES = {"WF007": "WR02 (Patriot Act)", "WF016": "WF015 (JASTA)", "WF085": "WR10 (NICS Improvement Amendments Act)",
              "N051": "N050 (Pure Food and Drug Act)", "N065": "N063 (ARPA)", "N191": "N063 (ARPA)"}

# The ground truth's removals (plan, table "hand keeps minus those that violate the written definitions")
REMOVED = {
    ("E3", "september-11: Victim Compensation Fund"): "relief fund",
    ("E3", "chernobyl: UN Chernobyl Trust Fund"): "relief fund",
    ("E3", "chernobyl: Chernobyl Children International"): "relief fund",
    ("E3", "boston-marathon: One Fund Boston"): "relief fund",
    ("E3", "pulse: OneOrlando Fund"): "relief fund",
    ("E3", "camp-fire: PG&E Fire Victim Trust"): "relief fund",
    ("E3", "hurricane-sandy: Sandy aid law"): "relief fund",
    ("E2", "BP federal contracting ban"): "temporary measure",
    ("E3", "camp-fire: Chico price-gouging ordinance"): "temporary measure",
    ("E4", "pokemon-go: Iran's ban"): "country ban of the work",
    ("E4", "zumba: Iran's ban"): "country ban of the work",
    ("E4", "fifty-shades: Malaysia's ban"): "country ban of the work",
    ("E4", "da-vinci-code: Indian state bans"): "country ban of the work",
    ("E3", "volkswagen: Switzerland's sales ban"): "country ban of the work",
    ("E2", "Dimmock ruling"): "government act on the work's own distribution",
    ("E4", "an-inconvenient-truth: Dimmock ruling"): "government act on the work's own distribution",
    ("E4", "frozen: Norway tours"): "tourism",
    ("E4", "game-of-thrones: Northern Ireland tourism"): "tourism",
    ("E4", "emily-in-paris: Paris tourism"): "tourism",
    ("E4", "tetris: The Tetris Company"): "the stone's own company",
    ("E4", "avatar: 3D televisions"): "attention, growth or crazes",
    ("E4", "blue-planet-ii: the plastics turn"): "attention, growth or crazes",
}
OWNER_FIVE = {"relief fund", "temporary measure", "country ban of the work", "tourism", "the stone's own company"}


def apply_dating(labels, dates, stone_year):
    out, log = [], []
    for l in labels:
        l = dict(l)
        d = dates.get(l["id"])
        if d is not None and l["reason_code"] == "undated":
            entry = {"id": l["id"], "record": d["requested"], "page": d["page"], "year": d["year"], "how": d["how"],
                     "field": d["field"], "note": d["note"], "stone_year": stone_year(l["id"])}
            if d["year"] is not None:
                if d["year"] >= entry["stone_year"]:
                    l["date_ok"] = True
                    l["gate"] = "pass"
                    if l["id"] in DUPLICATES:
                        l["decision"], l["reason_code"] = "rejected", "duplicate"
                        entry["result"] = "in order; duplicate of " + DUPLICATES[l["id"]]
                    else:
                        l["decision"], l["reason_code"] = "accepted", None
                        entry["result"] = "in order; accepted"
                else:
                    l["reason_code"] = "bad_timing"
                    entry["result"] = "busted: the record dates the mark before the stone"
            else:
                entry["result"] = "unresolved; stays undated"
            l["dating"] = {k: entry[k] for k in ("record", "page", "year", "how", "field", "note", "result")}
            log.append(entry)
        out.append(l)
    return out, log


def main():
    dates = json.load(open("screen_dating_v2.json"))["dates"]
    cands = {c["id"]: c for c in json.load(open("screen_candidates_v1.json"))["candidates"]}
    v1 = json.load(open("screen_labels_v1.json"))["labels"]
    labels, log = apply_dating(v1, dates, lambda i: cands[i]["stone_year"])
    lab = {l["id"]: l for l in labels}
    json.dump({"_about": "Screen v2 labels: the blind v1 labels (screen_labels_v1.json) with date_ok recomputed by the dating "
                         "step (screen_dating_v2.json) and the ordering rule; no other field changed. docs/screen_plan_v2.md.",
               "dating_log": log, "labels": labels}, open("screen_labels_v2.json", "w"), ensure_ascii=False, indent=1)

    # units and hand decisions, as in v1
    units = {}
    for i, labname in sc1.E1_LABEL.items():
        if labname == "mark":
            units[("E1", i)] = [i]
    for k, v in sc1.E2_UNITS.items():
        units[("E2", k)] = v
    for k, (m, j) in sc1.E3_UNITS.items():
        units[("E3", k)] = m + j
    for k, (m, j) in sc1.E4_UNITS.items():
        units[("E4", k)] = m + j
    judged = {i for t in (sc1.E3_UNITS, sc1.E4_UNITS) for _, (m, j) in t.items() for i in j}
    blind = {"E1_strict", "E2_heldout", "E3_wider", "E4_culture"}
    ids_all = [i for i in cands if cands[i]["set"] in blind and i not in sc1.E4_DISPUTED]

    def truth(removed):
        kept_units = {u: ids for u, ids in units.items() if u not in removed}
        kept_ids = {i for ids in kept_units.values() for i in ids}
        return kept_units, kept_ids

    def metrics(ids, kept_units, kept_ids, gate, use_judged=True):
        ids = [i for i in ids if use_judged or i not in judged]
        g = {i: gate(i) for i in ids}
        k = {i: i in kept_ids for i in ids}
        tp = sum(g[i] and k[i] for i in ids); fp = sum(g[i] and not k[i] for i in ids)
        fn = sum((not g[i]) and k[i] for i in ids); tn = len(ids) - tp - fp - fn
        uk = [u for u, uids in kept_units.items() if any(i in ids for i in uids)]
        ur = [u for u in uk if any(g.get(i) for i in kept_units[u] if i in g)]
        return {"n": len(ids), "hand_kept": tp + fn, "gate_pass": tp + fp, "tp": tp, "fp": fp, "fn": fn, "tn": tn,
                "precision": round(tp / (tp + fp), 3) if tp + fp else None,
                "recall_sentence": round(tp / (tp + fn), 3) if tp + fn else None,
                "kept_marks": len(uk), "kept_marks_recalled": len(ur), "recall_mark": round(len(ur) / len(uk), 3) if uk else None,
                "agreement": round((tp + tn) / len(ids), 3) if ids else None, "kappa": sc1.kappa([(g[i], k[i]) for i in ids])}

    g2 = lambda i: lab[i]["gate"] == "pass"
    g1 = lambda i: next(l for l in v1 if l["id"] == i)["gate"] == "pass"
    ku2, ki2 = truth(set(REMOVED))
    ku_a, ki_a = truth({u for u, why in REMOVED.items() if why in OWNER_FIVE})
    ku1, ki1 = truth(set())
    out = {"_about": "Screen v2 against the hand keeps minus those that violate the written definitions (docs/screen_plan_v2.md).",
           "removed_units": {f"{u[0]} {u[1]}": why for u, why in REMOVED.items()},
           "kept_units": len(ku2)}
    out["pooled"] = metrics(ids_all, ku2, ki2, g2)
    out["by_set"] = {s: metrics([i for i in ids_all if cands[i]["set"] == s], ku2, ki2, g2) for s in sorted(blind)}
    out["by_class"] = {c: metrics([i for i in ids_all if cands[i]["class"] == c], ku2, ki2, g2) for c in ("events", "culture")}
    out["sensitivity"] = {
        "a_owner_five_classes_only": metrics(ids_all, ku_a, ki_a, g2),
        "b_v1_truth_with_v2_labels": metrics(ids_all, ku1, ki1, g2),
        "c_mechanical_matches_only": metrics(ids_all, ku2, ki2, g2, use_judged=False),
        "d_unseen_in_docs": metrics([i for i in ids_all if not lab[i]["seen_in_docs"]], ku2, ki2, g2),
        "v1_labels_against_v2_truth": metrics(ids_all, ku2, ki2, g1),
    }
    out["by_class_unseen"] = {c: metrics([i for i in ids_all if cands[i]["class"] == c and not lab[i]["seen_in_docs"]], ku2, ki2, g2) for c in ("events", "culture")}
    out["decoys"] = {s: {"n": sum(1 for i in cands if cands[i]["set"] == s), "gate_pass": sum(1 for i in cands if cands[i]["set"] == s and g2(i))}
                     for s in ("E5_decoys_famous", "E6_decoys_obscure")}
    ev = [e for e in log]
    out["dating_step"] = {"eligible": len(ev), "null_record": sum(1 for e in ev if e["how"] == "null record"),
                          "looked_up": sum(1 for e in ev if e["how"] != "null record"),
                          "resolved": sum(1 for e in ev if e["year"] is not None),
                          "by_title": sum(1 for e in ev if e["how"] == "title"), "by_infobox": sum(1 for e in ev if e["how"] == "infobox"),
                          "busted": sum(1 for e in ev if e.get("result", "").startswith("busted")),
                          "newly_passing": sum(1 for e in ev if e.get("result", "").startswith("in order")),
                          "statute_site_fallback_used": 0, "log": ev}
    conf = {"false_pass": [], "miss": []}
    for i in ids_all:
        g = g2(i); k = i in ki2
        row = {"id": i, "set": cands[i]["set"], "class": cands[i]["class"], "stone": cands[i]["stone"], "mark_stated": lab[i]["mark_stated"],
               "reason_code": lab[i]["reason_code"], "justification": lab[i]["justification"], "sentence": cands[i]["sentence"][:240]}
        if g and not k:
            conf["false_pass"].append(row)
        if k and not g:
            conf["miss"].append(row)
    out["miss_reason_codes"] = dict(Counter(m["reason_code"] for m in conf["miss"]))
    out["missed_units"] = [f"{u[0]} {u[1]}" for u, uids in ku2.items() if not any(g2(i) for i in uids if i in lab)]
    out["confusion"] = conf
    json.dump(out, open("screen_compare_v2.json", "w"), ensure_ascii=False, indent=1)

    corpus = json.load(open("screen_corpus_v1.json"))
    removed_ids = {i: why for u, why in REMOVED.items() for i in units[u]}
    for c in corpus["candidates"]:
        l = lab[c["id"]]
        c["screen"] = {**c["screen"], "decision": l["decision"], "reason_code": l["reason_code"], "gate": l["gate"], "date_ok": l["date_ok"]}
        if "dating" in l:
            c["screen"]["dating"] = l["dating"]
        if c["id"] in removed_ids:
            c["hand"] = {"decision": "rejected", "how": c["hand"]["how"] + "; removed from the kept set: " + removed_ids[c["id"]] + " (owner's ruling, Oct 5)"}
    corpus["_about"] = corpus["_about"].replace("v1:", "v2:") + " v2: screen decisions after the dating step; hand keeps that violate the written definitions are marked rejected with the reason (docs/screen_plan_v2.md)."
    json.dump(corpus, open("screen_corpus_v2.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps({k: out[k] for k in ("kept_units", "pooled", "by_set", "by_class", "by_class_unseen", "sensitivity", "decoys", "miss_reason_codes")}, indent=1))
    print(json.dumps({k: v for k, v in out["dating_step"].items() if k != "log"}))


if __name__ == "__main__":
    main()
