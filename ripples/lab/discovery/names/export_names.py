#!/usr/bin/env python3
"""Names v1 (ripples/docs/names_plan_v1.md): export the US baby-name counts the project already holds.

ssa.gov refused the honest user agent on 2026-10-05 (HTTP 403), so no new names data is fetched from anywhere. The
counts used are the ones loaded into ripples.att_e9_names on 2026-09-28 for E9 phase 1 (ripples/tools/bq/e9_names.py:
national totals per name, sex and year, 1995-2021, summed from the SSA state files; names with at least 500 births over
2000-2010 plus Arya, Elsa and Khaleesi). They are read through the existing att_e9_export RPC and written as one CSV
(name, sex, year, n). Aggregates only; no personal data exists in this dataset.
"""
from __future__ import annotations

import csv
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "tools", "bq"))
from common import Supabase  # noqa: E402


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "names_national_1995_2021.csv"
    data = Supabase().rpc("att_e9_export", {}, timeout=300) or {}
    names = data.get("names") or {}
    rows = []
    for key, years in names.items():
        name, sex = key.split("|")
        for y, n in years.items():
            rows.append((name, sex, int(y), int(n)))
    rows.sort()
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["name", "sex", "year", "n"])
        w.writerows(rows)
    print(f"{len(rows)} rows, {len(names)} name-sex pairs, years {min(r[2] for r in rows)}-{max(r[2] for r in rows)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
