"""Pick a blind batch for a person to rate (the owner's ten minutes), from a run's rating packet.

    python3 ripples/engine/rate/human/pick.py --n 30 [--controls 3] [--seed 11]

Reads rate/items.json and data/rate_key.json (rate/build_items.py) and, when present, data/scores.json (simulated
surprise index, for strata) and enrich/enrich.json (why lines). Draws the real items in equal thirds by simulated
surprise (or at random when there are no scores), shows a why line on a seeded half of the items that have one, and
adds planted obvious and fabricated controls. A planted control's line, when it has one, is labeled as untested. A
model-written reason is never shown on a real item: the owner rated a fabricated claim fully believable when it
carried one (Oct 11).

Writes rate/human/items.json (what the page shows, in a seeded order) and rate/human/key.json (what each item is).
Then: python3 ripples/engine/rate/human/build_page.py, publish rate/human/page.html, and after the ratings come
back, python3 ripples/engine/rate/human/score.py --ratings <folder of exported rating files>.
"""
import argparse
import json
import os
import random
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--n", type=int, default=30)
    ap.add_argument("--controls", type=int, default=3, help="of each kind, obvious and fabricated")
    ap.add_argument("--seed", type=int, default=11)
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    items = json.load(open(os.path.join(work, "rate", "items.json")))
    key = json.load(open(os.path.join(work, "data", "rate_key.json")))
    sp = os.path.join(work, "data", "scores.json")
    sidx = {k: v.get("sidx") for k, v in json.load(open(sp))["items"].items()} if os.path.exists(sp) else {}
    ep = os.path.join(work, "enrich", "enrich.json")
    why = json.load(open(ep))["why"] if os.path.exists(ep) else {}
    rng = random.Random(a.seed)
    real = [k for k, v in key.items() if v.get("group") in ("gate_pass", "audit_reject")]
    if sidx:
        real.sort(key=lambda k: sidx.get(k) or 0)
        thirds = [real[: len(real) // 3], real[len(real) // 3: 2 * len(real) // 3], real[2 * len(real) // 3:]]
        each = [a.n // 3 + (1 if j < a.n % 3 else 0) for j in range(3)]
        picked = [k for t, m in zip(thirds, each) for k in rng.sample(t, min(m, len(t)))]
    else:
        picked = rng.sample(real, min(a.n, len(real)))
    for g in ("planted_obvious", "planted_fabricated"):
        pool = [k for k, v in key.items() if v.get("group") == g]
        picked += rng.sample(pool, min(a.controls, len(pool)))
    shown, keyout = [], {}
    with_why = [k for k in picked if why.get(key[k].get("ref"))]
    show = set(rng.sample(with_why, len(with_why) // 2))
    for k in picked:
        it, w = items[int(k)], why.get(key[k].get("ref"))
        line = w["why"] if (k in show and w) else None
        label = ("Why, per the authors:" if w and w.get("kind") == "tested" else "The authors' best guess:") if line else None
        hid = f"r{k}"
        shown.append({"id": hid, "stone": it["stone"], "date": it.get("stone_date", ""), "changed": it["claim"].split(" led to: ", 1)[-1],
                      "evidence": it.get("evidence", ""), "why": line, "whyLabel": label})
        keyout[hid] = {"i": int(k), "group": key[k].get("group"), "ref": key[k].get("ref"), "why_shown": bool(line), "sidx": sidx.get(k)}
    rng.shuffle(shown)
    d = os.path.join(work, "rate", "human"); os.makedirs(d, exist_ok=True)
    json.dump(shown, open(os.path.join(d, "items.json"), "w"), indent=1, ensure_ascii=False)
    json.dump(keyout, open(os.path.join(d, "key.json"), "w"), indent=1)
    print(f"{len(shown)} items ({len(picked) - 2 * a.controls} real, {2 * a.controls} controls, {sum(1 for v in keyout.values() if v['why_shown'])} with a why line) -> rate/human/")


if __name__ == "__main__":
    main()
