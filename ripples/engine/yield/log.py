"""Log one run's yield: one line per run in a ledger, so every generator is compared on the same number.

    python3 ripples/engine/yield/log.py --run <name> --generator "<words>"                # from data/summary.json
    python3 ripples/engine/yield/log.py --run <name> --generator "<words>" --n 15 --good 2  # a count made by hand
    python3 ripples/engine/yield/log.py --run <name> --generator "<words>" --dry-run       # print the line only

The one objective: surprising, defensible discoveries per 100 candidates. A candidate is a (stone, outcome, claimed
link) that enters verification. Two denominators are kept so a gate cannot fake the number: per 100 entering
verification, and per 100 raw harvested pairs. The ledger defaults to yield_ledger.jsonl in the work directory; pass
--ledger to write elsewhere (a run's published record, for example). A run name is logged once; --replace overwrites it.
"""
import argparse
import datetime
import hashlib
import json
import os
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest() if p and os.path.exists(p) else None


def main():
    ap = argparse.ArgumentParser(description="Append one run's yield to the ledger (script step).")
    ap.add_argument("--run", required=True)
    ap.add_argument("--generator", required=True)
    ap.add_argument("--summary", help="a score summary (default data/summary.json in the work directory)")
    ap.add_argument("--n", type=int, help="candidates entering verification (a hand count; skips the summary)")
    ap.add_argument("--good", type=int, help="good finds among them (with --n)")
    ap.add_argument("--raw", type=int, help="raw pairs behind them (with --n; optional)")
    ap.add_argument("--plan", help="the run's registered plan, to record its sha256")
    ap.add_argument("--queries", help="the run's frozen query file, to record its sha256")
    ap.add_argument("--note", default="")
    ap.add_argument("--ledger")
    ap.add_argument("--replace", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    workdir.add_arg(ap)
    a = ap.parse_args()
    W = workdir.resolve(a.work)
    row = {"run": a.run, "generator": a.generator, "date": datetime.date.today().strftime("%m/%d/%Y"),
           "plan_sha256": sha(a.plan), "queries_sha256": sha(a.queries), "note": a.note, "panel": "simulated"}
    if a.n is not None:
        if a.good is None or a.n <= 0:
            ap.error("--n needs --good, and --n must be positive")
        row.update({"source": "hand count", "n_entering": a.n, "n_good": a.good, "per_100_entering": round(100 * a.good / a.n, 1),
                    "n_raw": a.raw, "per_100_raw": round(100 * a.good / a.raw, 1) if a.raw else None})
    else:
        sp = a.summary or os.path.join(W, "data", "summary.json")
        s = json.load(open(sp))
        row.update({"source": os.path.basename(sp), "summary_sha256": sha(sp), "n_entering": s["n_gate_pass_verified"],
                    "n_good": s["n_good"], "per_100_entering": s["good_per_100_gate_pass"], "n_raw": s["n_raw_pairs"],
                    "per_100_raw": s["good_per_100_raw_observed"], "per_100_raw_estimated": s["good_per_100_raw_estimated"],
                    "validity_pass": s["validity"]["pass"], "validity": s["validity"], "audit": s["audit"],
                    "spread": s["spread"], "by_cell": s["by_cell"]})
    if a.dry_run:
        print(json.dumps(row, indent=1))
        return
    ledger = a.ledger or os.path.join(W, "yield_ledger.jsonl")
    rows = [json.loads(l) for l in open(ledger) if l.strip()] if os.path.exists(ledger) else []
    if any(r["run"] == a.run for r in rows):
        if not a.replace:
            raise SystemExit(f"run {a.run} is already in {ledger}; pass --replace to overwrite it")
        rows = [r for r in rows if r["run"] != a.run]
    rows.append(row)
    with open(ledger, "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"logged {a.run}: {row['n_good']} good of {row['n_entering']} = {row['per_100_entering']} per 100 -> {ledger}")


if __name__ == "__main__":
    main()
