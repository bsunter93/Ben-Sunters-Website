"""E9 phase 1 (registered: ledger 1275; data-source disclosure 1276; design in ripples/docs/experiments.md, "E9").

Can the method recover four known cultural ripples and reject fake ones? Runs the registered designs with one code path
for every hypothesis, real or fake. Data comes from public.att_e9_export (Wikipedia daily pageviews for the 13
pre-listed articles; US baby-name counts by year from the public SSA copy). Prints a JSON result; nothing is written.

Details fixed here, before the data is looked at (the registration left them open):
- log views uses the raw daily count (no article in the panel has a zero day).
- Pageview placebo dates: same weekday, more than 180 days from the real date, full -90..+60 window inside the data;
  500 drawn without replacement (seed below).
- Names: female names (all four targets are girls' names). Donors = names ranked 200-2000 by total births over the
  pre-period, present (>= 5 births) in every pre and post year, excluding the target and names tied to the same title.
  Synthetic control = non-negative weights summing to 1 fitted on the pre-period log counts; effect = mean post gap.
  Positive controls use every donor as a placebo; negative controls use 200 sampled donors (compute budget).
- Negative controls: 100 pageview pairs (random article from the 13, random date more than 180 days from both real
  dates; comparisons = the other articles of its pre-listed group, with Photosynthesis in the chess group) and 100
  name pairs (random donor-pool name, random year, alternating the P3 and P4 window shapes).
- Unrelated controls: Photosynthesis at the P1 and P2 dates; the name Ruth with the P3 and P4 designs.
"""
from __future__ import annotations

import datetime as dt
import json
import math
import os
import sys
import time

import numpy as np
from scipy.optimize import nnls

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bq"))
from common import Supabase, summary  # noqa: E402

SEED = 20260928
ALPHA = 0.05
CHESS = ["Chess", "Checkers", "Go_(game)", "Backgammon", "Poker", "Sudoku"]
MUSIC = ["Kate_Bush", "Madonna", "Cyndi_Lauper", "Peter_Gabriel", "Tears_for_Fears", "Depeche_Mode"]
GROUP = {a: CHESS for a in CHESS} | {a: MUSIC for a in MUSIC} | {"Photosynthesis": CHESS + ["Photosynthesis"]}
TIED = {"Arya": {"Arya", "Khaleesi", "Daenerys", "Sansa", "Brienne", "Cersei", "Ygritte", "Lyanna", "Catelyn",
                 "Margaery", "Shae", "Talisa", "Meera", "Gilly", "Missandei", "Melisandre", "Yara", "Tyrion", "Jon"},
        "Elsa": {"Elsa", "Anna", "Olaf", "Kristoff", "Hans", "Sven", "Idunn", "Iduna", "Agnarr"}}


# ---------------------------------------------------------------- pageviews (timing design)
class PV:
    def __init__(self, raw: dict):
        self.start = {a: dt.date.fromisoformat(v["start"]) for a, v in raw.items()}
        self.logv = {a: np.log(np.asarray(v["views"], float)) for a, v in raw.items()}

    def idx(self, a: str, d: dt.date) -> int:
        return (d - self.start[a]).days

    def ok(self, a: str, d: dt.date) -> bool:
        i = self.idx(a, d)
        return i - 90 >= 0 and i + 60 < len(self.logv[a])

    def effect(self, a: str, d: dt.date) -> float:
        i, x = self.idx(a, d), self.logv[a]
        return float(x[i + 1:i + 61].mean() - x[i - 90:i].mean())

    def test(self, a: str, d: dt.date, comps: list[str], rng) -> dict:
        real = self.effect(a, d)
        cands = [d + dt.timedelta(days=7 * k) for k in range(-600, 601)]
        cands = [c for c in cands if abs((c - d).days) > 180 and self.ok(a, c)]
        pick = rng.choice(len(cands), size=min(500, len(cands)), replace=False)
        null = np.array([self.effect(a, cands[j]) for j in pick])
        p = (1 + int((null >= real).sum())) / (1 + len(null))
        ce = {c: round(self.effect(c, d), 4) for c in comps}
        above = all(real > v for v in ce.values())
        return {"article": a, "date": d.isoformat(), "effect": round(real, 4), "p": round(p, 4),
                "n_placebo": len(null), "comparisons": ce, "above_all": above, "pass": p <= ALPHA and above}


# ---------------------------------------------------------------- names (synthetic control)
class Names:
    def __init__(self, raw: dict):
        self.n = {}
        for k, ys in raw.items():
            name, sex = k.split("|")
            if sex == "F":
                self.n[name] = {int(y): int(v) for y, v in ys.items()}

    def series(self, name: str, years: list[int]):
        s = self.n.get(name, {})
        return np.log([s[y] for y in years]) if all(y in s for y in years) else None

    def donors(self, target: str, pre: list[int], post: list[int]) -> tuple[list[str], np.ndarray]:
        tied = TIED.get(target, {target})
        tot = sorted(((sum(s.get(y, 0) for y in pre), nm) for nm, s in self.n.items()), reverse=True)
        ranked = [nm for _, nm in tot[199:2000]]
        names, rows = [], []
        for nm in ranked:
            if nm in tied or nm == target:
                continue
            x = self.series(nm, pre + post)
            if x is not None:
                names.append(nm)
                rows.append(x)
        return names, np.array(rows).T  # years x donors

    @staticmethod
    def sc_effect(y: np.ndarray, X: np.ndarray, npre: int) -> float:
        lam = 1e3
        A = np.vstack([X[:npre], lam * np.ones(X.shape[1])])
        b = np.concatenate([y[:npre], [lam]])
        w, _ = nnls(A, b, maxiter=50 * X.shape[1])
        return float((y[npre:] - X[npre:] @ w).mean())

    def test(self, target: str, pre: list[int], post: list[int], rng, n_placebo: int | None = None) -> dict:
        y = self.series(target, pre + post)
        if y is None:
            return {"name": target, "error": "target missing a year", "pass": False}
        names, X = self.donors(target, pre, post)
        real = self.sc_effect(y, X, len(pre))
        idx = range(len(names)) if n_placebo is None else rng.choice(len(names), size=min(n_placebo, len(names)),
                                                                     replace=False)
        null = []
        for j in idx:
            keep = np.ones(len(names), bool)
            keep[j] = False
            null.append(self.sc_effect(X[:, j], X[:, keep], len(pre)))
        null = np.array(null)
        p = (1 + int((null >= real).sum())) / (1 + len(null))
        return {"name": target, "pre": [pre[0], pre[-1]], "post": [post[0], post[-1]], "effect": round(real, 4),
                "p": round(p, 4), "n_donors": len(names), "n_placebo": len(null), "pass": p <= ALPHA}


def wilson_upper(k: int, n: int, z: float = 1.96) -> float:
    if n == 0:
        return 1.0
    ph = k / n
    return (ph + z * z / (2 * n) + z * math.sqrt(ph * (1 - ph) / n + z * z / (4 * n * n))) / (1 + z * z / n)


def main() -> int:
    sb, deadline = Supabase(), time.time() + 60 * float(os.environ.get("E9_WAIT_MIN", "0"))
    while True:  # the last pageview downloads may still be arriving; wait for complete data, then run once
        data = sb.rpc("att_e9_export", {}, timeout=300) or {}
        pv, names = PV(data.get("pv") or {}), Names(data.get("names") or {})
        missing = sorted(a for a in set(CHESS + MUSIC + ["Photosynthesis"]) if a not in pv.logv)
        if (not missing and names.n) or time.time() > deadline:
            break
        print(f"waiting for data: missing {missing}, names {len(names.n)}", flush=True)
        time.sleep(120)
    if missing or not names.n:
        print(json.dumps({"error": "data incomplete", "missing_articles": missing, "names": len(names.n)}))
        return 1
    rng = np.random.default_rng(SEED)
    P1, P2 = dt.date(2020, 10, 23), dt.date(2022, 5, 27)
    pos = {
        "P1": pv.test("Chess", P1, [c for c in CHESS if c != "Chess"], rng),
        "P2": pv.test("Kate_Bush", P2, [c for c in MUSIC if c != "Kate_Bush"], rng),
        "P3": names.test("Arya", list(range(2006, 2011)), list(range(2012, 2017)), rng),
        "P4": names.test("Elsa", list(range(2009, 2014)), [2014], rng),
    }
    unrelated = {
        "Photosynthesis@P1": pv.test("Photosynthesis", P1, [c for c in CHESS if c != "Chess"], rng),
        "Photosynthesis@P2": pv.test("Photosynthesis", P2, [c for c in MUSIC if c != "Kate_Bush"], rng),
        "Ruth@P3": names.test("Ruth", list(range(2006, 2011)), list(range(2012, 2017)), rng, 200),
        "Ruth@P4": names.test("Ruth", list(range(2009, 2014)), [2014], rng, 200),
    }
    neg = []
    arts = sorted(GROUP)
    while len([r for r in neg if "article" in r]) < 100:
        a = arts[rng.integers(len(arts))]
        d = pv.start[a] + dt.timedelta(days=int(rng.integers(len(pv.logv[a]))))
        if not pv.ok(a, d) or min(abs((d - P1).days), abs((d - P2).days)) <= 180:
            continue
        neg.append(pv.test(a, d, [c for c in GROUP[a] if c != a], rng))
    pool = sorted(names.n)
    k = 0
    while k < 100:
        shape = "P3" if k % 2 == 0 else "P4"
        t = int(rng.integers(2001, 2020 if shape == "P3" else 2025))
        pre = list(range(t - 5, t))
        post = list(range(t + 1, t + 6)) if shape == "P3" else [t]
        nm = pool[rng.integers(len(pool))]
        dn, _ = names.donors(nm, pre, post)
        if nm not in names.n or names.series(nm, pre + post) is None or len(dn) < 50:
            continue
        tot = sorted(((sum(s.get(y, 0) for y in pre), x) for x, s in names.n.items()), reverse=True)
        if nm not in {x for _, x in tot[199:2000]}:
            continue
        r = names.test(nm, pre, post, rng, 200)
        r["shape"] = shape
        neg.append(r)
        k += 1
    fp = sum(r["pass"] for r in neg)
    npos = sum(r["pass"] for r in pos.values())
    res = {
        "experiment": "E9 phase 1", "registration": [1275, 1276], "seed": SEED,
        "positives": pos, "positives_passed": npos,
        "negatives": {"n": len(neg), "false_passes": fp, "rate": round(fp / len(neg), 4),
                      "wilson_upper": round(wilson_upper(fp, len(neg)), 4),
                      "pageview_false_passes": sum(r["pass"] for r in neg if "article" in r),
                      "name_false_passes": sum(r["pass"] for r in neg if "name" in r),
                      "passing": [r for r in neg if r["pass"]]},
        "unrelated": unrelated,
        "phase1_pass": npos >= 3 and fp / len(neg) <= 0.05,
    }
    out = json.dumps(res, indent=1)
    print(out)
    with open(os.environ.get("E9_OUT", "e9_phase1.json"), "w") as f:
        f.write(out)
    summary("### E9 phase 1\n```\n" + json.dumps({k: res[k] for k in ("positives_passed", "phase1_pass")} |
                                                 {"negatives": {k: res["negatives"][k] for k in
                                                                ("n", "false_passes", "wilson_upper")}}) + "\n```")
    return 0


if __name__ == "__main__":
    sys.exit(main())
