"""Report yields: the earlier baselines and every logged run in one table, and one run's yield by cell.

    python3 ripples/engine/yield/report.py                  # baselines.json plus the ledger
    python3 ripples/engine/yield/report.py --cells <run>    # that run's yield by cell (query family)
    python3 ripples/engine/yield/report.py --ledger FILE    # a ledger other than the work directory's

Prints Markdown, ready to paste into a dated record. Every panel number is a simulated panel's.
"""
import argparse
import json
import os
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402


def fmt(x):
    return "" if x is None else (f"{x:g}" if isinstance(x, (int, float)) else str(x))


def main():
    ap = argparse.ArgumentParser(description="Print the yield table (script step).")
    ap.add_argument("--cells", metavar="RUN", help="print one run's yield by cell")
    ap.add_argument("--ledger")
    workdir.add_arg(ap)
    a = ap.parse_args()
    W = workdir.resolve(a.work, create=False)
    ledger = a.ledger or os.path.join(W, "yield_ledger.jsonl")
    rows = [json.loads(l) for l in open(ledger) if l.strip()] if os.path.exists(ledger) else []
    if a.cells:
        r = next((x for x in rows if x["run"] == a.cells), None)
        if not r or not r.get("by_cell"):
            raise SystemExit(f"no by-cell counts for run {a.cells} in {ledger}")
        print(f"Yield by cell, {r['run']} ({r['generator']}, {r['date']}), simulated panel\n")
        print("| Cell | Entering verification | Defensible | Surprising | Good | Per 100 |\n|---|---|---|---|---|---|")
        for cell, b in sorted(r["by_cell"].items(), key=lambda kv: (-kv[1]["good"], -kv[1]["n"], kv[0])):
            print(f"| {cell} | {b['n']} | {b['defensible']} | {b['surprising']} | {b['good']} | {round(100 * b['good'] / b['n'])} |")
        return
    base = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "baselines.json")))["rows"]
    print("Surprising, defensible discoveries per 100 candidates (simulated panel)\n")
    print("| Run | Date | Generator | Entering verification | Good | Per 100 | Raw pairs | Per 100 raw | Validity | Note |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for b in base:
        print(f"| {b['run']} | {b['date']} | {b['generator']} | {b['n']} | {b['good']} | {b['per_100']} |  |  | passed | {b['note']} |")
    for r in rows:
        v = r.get("validity_pass")
        print(f"| {r['run']} | {r['date']} | {r['generator']} | {r['n_entering']} | {r['n_good']} | {fmt(r['per_100_entering'])} | "
              f"{fmt(r.get('n_raw'))} | {fmt(r.get('per_100_raw'))} | {'' if v is None else ('passed' if v else 'failed')} | {r.get('note', '')} |")
    if not rows:
        print(f"\nNo run logged yet in {ledger}.")


if __name__ == "__main__":
    main()
