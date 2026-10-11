"""Score a person's blind ratings: the yield as a person sees it, and how well the engine's signals track them.

    python3 ripples/engine/rate/human/score.py --ratings DIR [--key rate/human/key.json] [--sim data/scores.json]

DIR holds one JSON file per rated item as the rating page stores it: {item, s, knew, b, t, why_shown}. s is surprise
on the claim alone (1 to 5), b is belief after the evidence, t is "would you tell someone". The key says what each item
is (rate/human/pick.py). With the run's simulated scores it also reports agreement with the simulated panel.

Good = s >= 4 and b >= 4. Reported: good per 100 real items and per 100 gate passers, the controls (planted obvious
should score low on s, planted fabricated low on b), Spearman of s with b and of t with each, the why line's effect on
b (items with a line against items without, and net of the simulated b when present), and agreement with the panel.
Writes data/human_scores.json. One person is a small sample: every number prints with its n.
"""
import argparse
import glob
import json
import os
import statistics as st
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402


def rank(v):
    s = sorted(range(len(v)), key=lambda i: v[i]); r = [0.0] * len(v); i = 0
    while i < len(v):
        j = i
        while j + 1 < len(v) and v[s[j + 1]] == v[s[i]]:
            j += 1
        for k in range(i, j + 1):
            r[s[k]] = (i + j) / 2
        i = j + 1
    return r


def rho(a, b):
    if len(a) < 3:
        return None
    ra, rb = rank(a), rank(b); ma, mb = st.mean(ra), st.mean(rb)
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb)); den = (sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb)) ** .5
    return round(num / den, 2) if den else None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--ratings", required=True)
    ap.add_argument("--key")
    ap.add_argument("--sim", help="data/scores.json with simulated surprise and believable per rating index")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    key = json.load(open(a.key or os.path.join(work, "rate", "human", "key.json")))
    simp = a.sim or os.path.join(work, "data", "scores.json")
    sim = json.load(open(simp))["items"] if os.path.exists(simp) else {}
    R = []
    for f in glob.glob(os.path.join(a.ratings, "**", "*.json"), recursive=True):
        r = json.load(open(f))
        if r.get("item") in key and all(r.get(x) for x in ("s", "b", "t")):
            R.append({**r, **key[r["item"]], "sim": sim.get(str(key[r["item"]].get("i")), {})})
    real = [r for r in R if r.get("group") in ("gate_pass", "audit_reject", "real")]
    obv = [r for r in R if r.get("group") == "planted_obvious"]; fab = [r for r in R if r.get("group") == "planted_fabricated"]
    good = lambda rs: sum(1 for r in rs if r["s"] >= 4 and r["b"] >= 4)
    gp = [r for r in real if r.get("group") == "gate_pass"]
    w = [r for r in real if r.get("why_shown")]; nw = [r for r in real if not r.get("why_shown")]
    out = {
        "rated": len(R), "real": len(real),
        "good_per_100_real": round(100 * good(real) / len(real), 1) if real else None,
        "good_per_100_gate_passers": round(100 * good(gp) / len(gp), 1) if gp else None, "n_gate_passers": len(gp),
        "controls": {"obvious_mean_s": round(st.mean(r["s"] for r in obv), 2) if obv else None, "n_obvious": len(obv),
                     "fabricated_mean_b": round(st.mean(r["b"] for r in fab), 2) if fab else None, "n_fabricated": len(fab),
                     "fabricated_believed_4plus": sum(1 for r in fab if r["b"] >= 4)},
        "rho_s_b": rho([r["s"] for r in real], [r["b"] for r in real]),
        "rho_t_s": rho([r["t"] for r in real], [r["s"] for r in real]), "rho_t_b": rho([r["t"] for r in real], [r["b"] for r in real]),
        "why": {"n_with": len(w), "n_without": len(nw), "mean_b_with": round(st.mean(r["b"] for r in w), 2) if w else None,
                "mean_b_without": round(st.mean(r["b"] for r in nw), 2) if nw else None},
        "knew": sum(1 for r in real if r.get("knew")),
    }
    ws = [r for r in real if r["sim"].get("surprise") is not None]
    if ws:
        out["agreement_with_panel"] = {"n": len(ws), "surprise": rho([r["s"] for r in ws], [r["sim"]["surprise"] for r in ws]),
                                       "believable": rho([r["b"] for r in ws], [r["sim"]["believable"] for r in ws]) if all("believable" in r["sim"] for r in ws) else None}
        wb = [r for r in ws if "believable" in r["sim"]]
        if wb:
            net = lambda rs: round(st.mean(r["b"] - r["sim"]["believable"] for r in rs), 2) if rs else None
            out["why"]["net_of_panel_with"] = net([r for r in wb if r.get("why_shown")]); out["why"]["net_of_panel_without"] = net([r for r in wb if not r.get("why_shown")])
    json.dump(out, open(os.path.join(work, "data", "human_scores.json"), "w"), indent=1)
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
