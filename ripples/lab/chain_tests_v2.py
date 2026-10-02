"""Chain tests v2 (ripples/docs/chain_tests_v2.md): less obvious event -> behavior chains, in time order.

Same data and series as v1 (Seattle library checkouts by subject heading, panel-median and season adjusted), with a
6-month effect window (downstream behavior can be slower) and two kinds of chain:
  one step:  event -> a less obvious behavior (e.g. Squid Game -> Korean-language books);
  two steps: event -> A -> B, where B must start strictly after A (e.g. The Queen's Gambit -> chess -> board games).
A step passes if p <= 0.05 against every admissible month and its rise starts in the event month or later; a chain
passes if every step passes and, for two steps, B's rise starts in a later month than A's (owner ordering rule).
Input JSON {"series": {heading: {"YYYY-MM": n}}, "panel_median": {...}}; pure computation, no network.
"""
from __future__ import annotations

import json
import sys

import numpy as np

from chain_tests import months

WIN = 6
CHAINS = [("Squid Game", "2021-09", ["Korean language"]),
          ("Stranger Things season 4", "2022-05", ["Dungeons and Dragons Game"]),
          ("Shogun (FX)", "2024-02", ["Tokugawa period"]),
          ("Tiger King", "2020-03", ["Wild animal trade"]),
          ("Tidying Up with Marie Kondo", "2019-01", ["Simplicity"]),
          ("Barbie", "2023-07", ["Feminism"]),
          ("GameStop short squeeze", "2021-01", ["Speculation"]),
          ("The Queen's Gambit", "2020-10", ["Chess", "Board games"]),
          ("The Last of Us (HBO)", "2023-01", ["Fungi", "Mushroom culture"]),
          ("Chernobyl (HBO)", "2019-05", ["Chernobyl", "Nuclear power plants"])]


def step(M, idx, med, s, m0):
    raw = np.array([np.log1p(s.get(m, 0)) for m in M]) - med
    x = np.full(len(M), np.nan)
    for i in range(36, len(M)):
        prev = [raw[i - 12 * k] for k in (1, 2, 3) if np.isfinite(raw[i - 12 * k])]
        if len(prev) >= 2 and np.isfinite(raw[i]):
            x[i] = raw[i] - np.median(prev)

    def effect(i):
        post, pre = x[i:i + WIN], x[i - 6:i]
        if np.isfinite(post).sum() < WIN or np.isfinite(pre).sum() < 4:
            return np.nan
        return float(np.nanmean(post) - np.nanmean(pre))

    i0 = idx[m0]
    obs = effect(i0)
    lo = max(idx["2008-01"], 42)
    pool = [i for i in range(lo, len(M) - WIN) if abs(i - i0) >= WIN + 4 and np.isfinite(effect(i))]
    P = np.array([effect(i) for i in pool])
    p = float((1 + (P >= obs).sum()) / (1 + len(P))) if np.isfinite(obs) else None
    pre = x[i0 - 12:i0]
    thr = np.nanmean(pre) + 2 * 1.4826 * np.nanmedian(np.abs(pre - np.nanmedian(pre)))
    onset = next((M[i] for i in range(i0 - 3, min(i0 + 10, len(M))) if np.isfinite(x[i]) and x[i] > thr), None)
    return {"effect": None if not np.isfinite(obs) else round(obs, 3), "p": p, "placebos": len(P), "onset": onset,
            "after_event": bool(onset is not None and onset >= m0),
            "passes": bool(p is not None and p <= 0.05 and onset is not None and onset >= m0),
            "checkouts": {m: int(s.get(m, 0)) for m in M[i0 - 12:min(i0 + 10, len(M))]}}


def main() -> int:
    src = json.load(open(sys.argv[1]))
    M = months()
    idx = {m: i for i, m in enumerate(M)}
    med = np.array([src["panel_median"].get(m, np.nan) for m in M], dtype=float)
    rep = {"protocol": "ripples/docs/chain_tests_v2.md", "window_months": WIN, "chains": []}
    for event, m0, heads in CHAINS:
        row = {"event": event, "month": m0, "steps": []}
        for h in heads:
            s = src["series"].get(h)
            row["steps"].append({"heading": h, **(step(M, idx, med, s, m0) if s else {"skip": "no checkouts found"})})
        st = row["steps"]
        ok = all(x.get("passes") for x in st)
        if len(st) == 2 and ok:
            ok = st[1]["onset"] > st[0]["onset"]
            row["order"] = "B after A" if ok else "B not after A"
        row["passes"] = bool(ok)
        rep["chains"].append(row)
        print(event, [(x["heading"], x.get("p"), x.get("onset"), x.get("passes")) for x in st], row["passes"])
    steps = [x for c in rep["chains"] for x in c["steps"] if x.get("p") is not None]
    rep.update(chains_passing=int(sum(c["passes"] for c in rep["chains"])), steps_scored=len(steps),
               steps_passing=int(sum(x["passes"] for x in steps)), steps_expected_by_chance=round(0.05 * len(steps), 2))
    json.dump(rep, open(sys.argv[2] if len(sys.argv) > 2 else "chain_tests_v2.json", "w"), indent=1)
    print({k: rep[k] for k in ("chains_passing", "steps_scored", "steps_passing", "steps_expected_by_chance")})
    return 0


if __name__ == "__main__":
    sys.exit(main())
