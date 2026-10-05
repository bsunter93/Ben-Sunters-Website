"""Compare the blind screen labels (screen_labels_v1.json) with the person's decisions, as registered in
docs/screen_plan_v1.md. Writes docs/results/screen_compare_v1.json and docs/results/screen_corpus_v1.json.
Run from ripples/docs/results:

    python3 ../../lab/discovery/screen_compare.py

Hand decisions:
  E1  discovery_corpus1_screen.json, catalog_strict_in_order (mark / weak / context / wrong); kept = mark
  E2  the eleven marks of discovery_corpus1_screen.json heldout_forward_47 (the doc counts the Connecticut law and its
      registry, and the two BP-ban sentences, as separate sentences), matched by hand below
  E3  demo/discovered_wiki.json, matched by sentence (MECH) and, where a candidate states the same mark in another
      sentence, by hand (JUDGED, listed below so it can be checked)
  E4  the same, for the culture shelf; a product mark with grade "disputed" is a hand "disputed"
  E5  roundtable_v2.md: nothing kept from the famous decoys
  E6  decoys by construction, never screened
  S1  cite_score_v1.json eval rows (not blind)
"""
import json
import re
from collections import Counter

LAB = "screen_labels_v1.json"
CAND = "screen_candidates_v1.json"

# ---- E1: the builder's labels, in the order of the screen file (same order as S01..S23)
E1 = json.load(open("discovery_corpus1_screen.json"))["catalog_strict_in_order"]
E1_LABEL = {f"S{int(k.split()[0]):02d}": v.split(",")[0].split(" (")[0].strip() for k, v in E1.items()}

# ---- E2: the eleven marks and the sentences that state them (matched by hand after the labels were pushed)
E2_UNITS = {"Climate Reality Project": ["H04"], "Dimmock ruling": ["H06"], "INF Treaty": ["H09"], "GuLF Study": ["H27"],
            "National Ocean Council (EO 13547)": ["H30"], "National Commission": ["H32"], "BP federal contracting ban": ["H26", "H35"],
            "Connecticut FOIA change": ["H38"], "NY SAFE Act": ["H41"], "Connecticut gun law and offender registry": ["H42", "H43"],
            "Sandy Hook memorial": ["H45"]}

# ---- E3 and E4: product marks -> candidate sentences. MECH from the sentence match (normalized containment or 60% of
# word tokens shared); JUDGED where another candidate states the same law, body or change.
E3_UNITS = {
    "love-canal: CERCLA / Superfund (product: ATSDR)": (["WF182"], ["WR15", "WF179"]),
    "love-canal: LCARA": (["WF181"], []),
    "flint: Lead and Copper Rule revisions": (["WR14"], []),
    "flint: Child Lead Exposure Elimination Commission": (["WF127"], []),
    "flint: BlueConduit": (["WF133"], []),
    "september-11: Victim Compensation Fund": (["WF005"], []),
    "september-11: Patriot Act": (["WR02"], ["WF007"]),
    "september-11: TSA": (["WF014"], []),
    "september-11: UK Anti-terrorism, Crime and Security Act": (["WF011"], []),
    "september-11: Canada's Anti-terrorism Act": (["WF010"], []),
    "september-11: New Zealand's Terrorism Suppression Act": (["WF012"], []),
    "september-11: Department of Homeland Security": (["WF013"], ["WF006"]),
    "september-11: JASTA": (["WF015", "WF016"], []),
    "chernobyl: Early Notification Convention": (["WF025"], []),
    "chernobyl: UN Chernobyl Trust Fund": (["WF022"], []),
    "chernobyl: Chernobyl Children International": (["WF027"], []),
    "chernobyl: Chernobyl Shelter Fund": (["WF023"], ["WF021"]),
    "chernobyl: Joint Convention": (["WF026"], []),
    "bhopal: Bhopal Gas Leak Disaster Act": (["WF031"], ["WF028"]),
    "bhopal: International Medical Commission on Bhopal": (["WR03"], []),
    "challenger: Rogers Commission": (["WF035"], ["WR04"]),
    "challenger: Challenger Center": (["WF045"], []),
    "challenger: NASA Office of Safety": (["WF041"], ["WF036"]),
    "rana-plaza: Bangladesh Accord": (["WF062"], ["WF059"]),
    "rana-plaza: factory-inspection law": (["WF058"], []),
    "oklahoma-city: AEDPA": (["WF076"], ["WF081", "WR09"]),
    "oklahoma-city: Victim Allocution Clarification Act": (["WF082"], []),
    "virginia-tech: NICS Improvement Amendments Act": (["WR10"], ["WF085", "WF088"]),
    "parkland: Never Again MSD": (["WF089"], []),
    "parkland: MSD High School Public Safety Act": (["WF093"], ["WF094"]),
    "parkland: STOP School Violence Act": (["WF097"], []),
    "parkland: death-penalty unanimity repeal": (["WF090", "WF091"], []),
    "uvalde: New York age-21 law": (["WF099"], []),
    "uvalde: Bipartisan Safer Communities Act": (["WF102", "WF103"], ["WF108"]),
    "uvalde: Texas training law": (["WF100"], []),
    "uvalde: Texas HB 3": (["WF105"], ["WF104"]),
    "boston-marathon: One Fund Boston": (["WF071"], []),
    "boston-marathon: One Boston Day": (["WF074"], []),
    "pulse: OneOrlando Fund": (["WF109"], []),
    "pulse: OnePulse Foundation": (["WF110"], ["WF111"]),
    "las-vegas: bump-stock ban": (["WF114"], ["WF113", "WF116"]),
    "enron: section 409A": (["WR07"], []),
    "enron: UK Companies (Audit, Investigations and Community Enterprise) Act": (["WR08"], []),
    "cambridge-analytica: Social Science One": (["WF068"], []),
    "metoo: Indonesia's Sexual Violence Crime Act": (["WR12"], []),
    "camp-fire: Chico price-gouging ordinance": (["WF136"], []),
    "camp-fire: AB 1054 wildfire fund": (["WF137"], []),
    "camp-fire: PG&E Fire Victim Trust": (["WF138"], []),
    "lac-megantic: FRA Emergency Order 28": (["WF149"], []),
    "volkswagen: Switzerland's sales ban": (["WF159", "WF166"], []),
    "dear-zachary: Bill C-464": (["WF191"], ["WF190"]),
    "grenfell: Grenfell Tower Memorial Commission": (["WF057"], []),
    "hurricane-sandy: Sandy aid law": (["WF002"], ["WF001"]),
    "cathy-come-home: Crisis": (["WF193"], []),
}
E4_UNITS = {
    "frozen: Norway tours": (["C004"], []),
    "game-of-thrones: Northern Ireland tourism": (["C005"], []),
    "finding-nemo: demand for reef fish": (["C016"], []),
    "101-dalmatians: Dalmatian sales": (["C019"], []),
    "sideways: the Sideways effect": (["C020"], ["C021"]),
    "queens-gambit: chess set sales": (["C022"], []),
    "pokemon-go: New York parole rule": (["C034"], []),
    "pokemon-go: Iran's ban": (["C039"], []),
    "jurassic-park: Toronto Raptors' name": (["C063"], []),
    "avatar: 3D televisions": (["C067"], []),
    "fifty-shades: Malaysia's ban": (["C076"], []),
    "da-vinci-code: Indian state bans": (["C078"], []),
    "mad-men: suit revival": (["C086"], []),
    "bake-off: baking sales": (["C092", "C093"], []),
    "hamilton: Hamilton Education Program": (["C117"], []),
    "furby: NSA Furby ban": (["C134"], ["C133"]),
    "tetris: The Tetris Company": (["C154", "C152"], []),
    "zumba: Iran's ban": (["C176"], []),
    "woodstock: Bethel Woods": (["C200"], []),
    "13-reasons-why: teen suicide study": (["C217"], []),
    "blue-planet-ii: marine biology applications": (["C227"], []),
    "blue-planet-ii: the plastics turn": (["C226"], []),
    "emily-in-paris: Paris tourism": (["C229"], []),
    "an-inconvenient-truth: Climate Reality Project": (["C221"], []),
    "an-inconvenient-truth: carbon-offset purchases": (["C222"], []),
    "an-inconvenient-truth: Dimmock ruling": ([], ["C223"]),
}
E4_DISPUTED = {"C023"}  # Top Gun's 500% claim, grade "disputed" in the product

S1_TRUTH = {f"R{i + 1:02d}": r["truth"] for i, r in enumerate(json.load(open("cite_score_v1.json"))["eval"]["rows"])}


def auc(pos, neg):
    if not pos or not neg:
        return None
    wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return round(wins / (len(pos) * len(neg)), 3)


def kappa(rows):
    n = len(rows)
    if not n:
        return None
    a = sum(1 for g, h in rows if g == h) / n
    pg = sum(1 for g, _ in rows if g) / n
    ph = sum(1 for _, h in rows if h) / n
    pe = pg * ph + (1 - pg) * (1 - ph)
    return round((a - pe) / (1 - pe), 3) if pe < 1 else None


def main():
    labels = {l["id"]: l for l in json.load(open(LAB))["labels"]}
    cands = {c["id"]: c for c in json.load(open(CAND))["candidates"]}

    # hand decision per candidate and mark units per set
    hand, how, units = {}, {}, {}
    for i, lab in E1_LABEL.items():
        hand[i] = "kept" if lab == "mark" else "rejected"
        how[i] = f"E1 label: {lab}"
        if lab == "mark":
            units[("E1", i)] = [i]
    for name, ids in E2_UNITS.items():
        units[("E2", name)] = ids
        for i in ids:
            hand[i] = "kept"; how[i] = f"E2 mark: {name} (matched by hand)"
    for setname, table in (("E3", E3_UNITS), ("E4", E4_UNITS)):
        for name, (mech, judged) in table.items():
            units[(setname, name)] = mech + judged
            for i in mech:
                hand[i] = "kept"; how[i] = f"product mark {name} (sentence match)"
            for i in judged:
                hand[i] = "kept"; how[i] = f"product mark {name} (same mark, matched by hand)"
    for i in E4_DISPUTED:
        hand[i] = "disputed"; how[i] = "product mark shown as Disputed"
    for i, c in cands.items():
        if i in hand:
            continue
        if c["set"] in ("E2_heldout", "E3_wider", "E4_culture"):
            hand[i] = "rejected"; how[i] = "not among the person's kept marks"
        elif c["set"] == "E5_decoys_famous":
            hand[i] = "rejected"; how[i] = "famous decoy: nothing kept (roundtable_v2.md)"
        elif c["set"] == "E6_decoys_obscure":
            hand[i] = "decoy"; how[i] = "obscure decoy, never screened"
        elif c["set"] == "S1_citations":
            hand[i] = S1_TRUTH[i]; how[i] = "owner's citation grade (not blind)"
    judged_ids = {i for t in (E3_UNITS, E4_UNITS) for _, (m, j) in t.items() for i in j}

    def metrics(ids, unit_keys, use_judged=True):
        ids = [i for i in ids if hand[i] in ("kept", "rejected")]
        if not use_judged:
            ids = [i for i in ids if i not in judged_ids]
        g = {i: labels[i]["gate"] == "pass" for i in ids}
        k = {i: hand[i] == "kept" for i in ids}
        tp = sum(1 for i in ids if g[i] and k[i]); fp = sum(1 for i in ids if g[i] and not k[i])
        fn = sum(1 for i in ids if not g[i] and k[i]); tn = len(ids) - tp - fp - fn
        uk = [u for u in unit_keys if any(i in ids for i in units[u])]
        ur = [u for u in uk if any(labels[i]["gate"] == "pass" for i in units[u] if i in ids)]
        return {"n": len(ids), "hand_kept": tp + fn, "gate_pass": tp + fp, "tp": tp, "fp": fp, "fn": fn, "tn": tn,
                "precision": round(tp / (tp + fp), 3) if tp + fp else None,
                "recall_sentence": round(tp / (tp + fn), 3) if tp + fn else None,
                "kept_marks": len(uk), "kept_marks_recalled": len(ur),
                "recall_mark": round(len(ur) / len(uk), 3) if uk else None,
                "agreement": round((tp + tn) / len(ids), 3) if ids else None, "kappa": kappa([(g[i], k[i]) for i in ids])}

    blind = ["E1_strict", "E2_heldout", "E3_wider", "E4_culture"]
    setkey = {"E1_strict": "E1", "E2_heldout": "E2", "E3_wider": "E3", "E4_culture": "E4"}
    out = {"_about": "Comparison of screen_labels_v1.json with the person's decisions under docs/screen_plan_v1.md.", "by_set": {}, "by_class": {}}
    allids = [i for i in cands if cands[i]["set"] in blind]
    allunits = [u for u in units]
    out["pooled"] = metrics(allids, allunits)
    out["pooled_mechanical_matches_only"] = metrics(allids, allunits, use_judged=False)
    unseen = [i for i in allids if not labels[i]["seen_in_docs"]]
    out["pooled_unseen_in_docs"] = metrics(unseen, allunits)
    for s in blind:
        ids = [i for i in allids if cands[i]["set"] == s]
        out["by_set"][s] = metrics(ids, [u for u in units if u[0] == setkey[s]])
    for cl in ("events", "culture"):
        ids = [i for i in allids if cands[i]["class"] == cl]
        out["by_class"][cl] = metrics(ids, [u for u in units if any(cands[i]["class"] == cl for i in units[u])])
        out["by_class"][cl + "_unseen"] = metrics([i for i in ids if not labels[i]["seen_in_docs"]],
                                                  [u for u in units if any(cands[i]["class"] == cl for i in units[u])])
    # E1 sensitivity: weak counted as kept
    e1 = [i for i in allids if cands[i]["set"] == "E1_strict"]
    w = [i for i in e1 if E1_LABEL[i] in ("mark", "weak")]
    out["E1_weak_as_kept"] = {"kept": len(w), "recalled": sum(labels[i]["gate"] == "pass" for i in w)}
    # E1 by the four hand labels: mean scores
    out["E1_scores_by_hand_label"] = {lab: {d: round(sum(labels[i]["scores"][d] for i in e1 if E1_LABEL[i] == lab) / max(1, sum(1 for i in e1 if E1_LABEL[i] == lab)), 1)
                                            for d in ("interest", "surprise", "evidence", "novelty")} | {"n": sum(1 for i in e1 if E1_LABEL[i] == lab)}
                                      for lab in ("mark", "weak", "context", "wrong")}
    # decoys
    out["decoys"] = {s: {"n": sum(1 for i in cands if cands[i]["set"] == s), "gate_pass": sum(1 for i in cands if cands[i]["set"] == s and labels[i]["gate"] == "pass")}
                     for s in ("E5_decoys_famous", "E6_decoys_obscure")}
    # disputed
    out["disputed"] = {i: {"hand": hand[i], "screen_disputed": labels[i]["disputed"], "gate": labels[i]["gate"]} for i in E4_DISPUTED}
    # S1
    s1 = [i for i in cands if cands[i]["set"] == "S1_citations"]
    tp = sum(1 for i in s1 if labels[i]["link_label"] == "reason" and hand[i] == "reason")
    fp = sum(1 for i in s1 if labels[i]["link_label"] == "reason" and hand[i] != "reason")
    fn = sum(1 for i in s1 if labels[i]["link_label"] != "reason" and hand[i] == "reason")
    out["S1_citations_not_blind"] = {"n": len(s1), "tp": tp, "fp": fp, "fn": fn, "precision": round(tp / (tp + fp), 3) if tp + fp else None,
                                     "recall": round(tp / (tp + fn), 3) if tp + fn else None,
                                     "label_agreement": round(sum(1 for i in s1 if labels[i]["link_label"] == hand[i]) / len(s1), 3),
                                     "cite_score_v1": {"precision": 0.73, "recall": 0.89}}
    # four scores against keep / reject
    sc = {}
    for scope, ids in (("pooled", allids), ("events", [i for i in allids if cands[i]["class"] == "events"]),
                       ("culture", [i for i in allids if cands[i]["class"] == "culture"]),
                       ("gate_pass_only", [i for i in allids if labels[i]["gate"] == "pass"]),
                       ("is_mark_only", [i for i in allids if labels[i]["is_mark"]])):
        ids = [i for i in ids if hand[i] in ("kept", "rejected")]
        sc[scope] = {}
        for d in ("interest", "surprise", "evidence", "novelty"):
            pos = [labels[i]["scores"][d] for i in ids if hand[i] == "kept"]
            neg = [labels[i]["scores"][d] for i in ids if hand[i] == "rejected"]
            sc[scope][d] = {"mean_kept": round(sum(pos) / len(pos), 1) if pos else None, "mean_rejected": round(sum(neg) / len(neg), 1) if neg else None,
                            "auc": auc(pos, neg), "n_kept": len(pos), "n_rejected": len(neg)}
    out["scores_vs_hand"] = sc
    # confusion lists
    conf = {"false_pass": [], "miss": []}
    for i in allids:
        if hand[i] not in ("kept", "rejected"):
            continue
        g = labels[i]["gate"] == "pass"
        if g and hand[i] == "rejected":
            conf["false_pass"].append({"id": i, "stone": cands[i]["stone"], "mark_stated": labels[i]["mark_stated"], "justification": labels[i]["justification"], "sentence": cands[i]["sentence"][:240]})
        if not g and hand[i] == "kept":
            conf["miss"].append({"id": i, "stone": cands[i]["stone"], "reason_code": labels[i]["reason_code"], "mark_stated": labels[i]["mark_stated"], "justification": labels[i]["justification"], "how_kept": how[i], "sentence": cands[i]["sentence"][:240]})
    out["miss_reason_codes"] = dict(Counter(m["reason_code"] for m in conf["miss"]))
    out["confusion"] = conf
    out["judged_matches"] = sorted(judged_ids)
    json.dump(out, open("screen_compare_v1.json", "w"), ensure_ascii=False, indent=1)

    corpus = []
    for i, c in cands.items():
        l = labels[i]
        corpus.append({"id": i, "set": c["set"], "class": c["class"], "stone": c["stone"], "stone_year": c["stone_year"],
                       "mark": c["mark"], "sentence": c["sentence"], "source": c["source"],
                       "screen": {"decision": l["decision"], "reason_code": l["reason_code"], "flags": l["flags"], "gate": l["gate"],
                                  "is_mark": l["is_mark"], "link_label": l["link_label"], "date_ok": l["date_ok"], "disputed": l["disputed"],
                                  "mark_stated": l["mark_stated"], "scores": l["scores"], "justification": l["justification"]},
                       "hand": {"decision": hand[i], "how": how[i]}})
    json.dump({"_about": "The labeled corpus of what a good ripple is, v1: every candidate the discovery runs produced in the "
                         "evaluation sets, the language-model screen's decision with one reason code from the owner's fixed list, "
                         "flags, four 0 to 100 scores, and the person's decision where one exists. Screen labels were written blind "
                         "(screen_labels_v1.json); hand decisions were attached afterward (lab/discovery/screen_compare.py).",
               "reason_codes": ["not_a_mark", "attention_only", "context", "aside", "bad_timing", "undated", "weak_evidence",
                                "duplicate", "confounded", "obvious", "wrong_entity", "disputed"],
               "n": len(corpus), "candidates": corpus}, open("screen_corpus_v1.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps({k: out[k] for k in ("pooled", "pooled_mechanical_matches_only", "pooled_unseen_in_docs", "by_set", "by_class", "decoys", "S1_citations_not_blind", "E1_weak_as_kept", "miss_reason_codes")}, indent=1))


if __name__ == "__main__":
    main()
