#!/usr/bin/env python3
"""Salmon search v1 (ripples/docs/salmon_protocol_v1.md): national US baby-name counts per (name, sex, year) from the
public BigQuery copy of the SSA data (bigquery-public-data.usa_names.usa_1910_current), 1985 onward, names with at
least 5 births in a year (the SSA publication floor). Aggregates only. Written to a local CSV for ripples/lab/salmon.py;
nothing is stored in the database. The query is dry-run first under a byte cap.
"""
from __future__ import annotations

import argparse
import csv
import sys

from common import GIB, bq_client, dry_run_bytes, fmt_bytes, log, run_query, summary

SQL = """
select name, gender as sex, year, sum(number) as n
from `bigquery-public-data.usa_names.usa_1910_current`
where year >= 1985
group by name, gender, year
having n >= 5
order by name, sex, year
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="ripple-509716")
    ap.add_argument("--location", default="US")
    ap.add_argument("--max-gib", type=float, default=2.0)
    ap.add_argument("--out", default="names_national.csv")
    a = ap.parse_args()
    client = bq_client(a.project, a.location)
    est = dry_run_bytes(client, SQL)
    log(f"dry run: {fmt_bytes(est)}")
    if est > a.max_gib * GIB:
        sys.exit(f"query would scan {fmt_bytes(est)}, above the {a.max_gib} GiB cap")
    rows, billed, _ = run_query(client, SQL, int(a.max_gib * GIB))
    n = 0
    with open(a.out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["name", "sex", "year", "n"])
        for r in rows:
            w.writerow([r["name"], r["sex"], int(r["year"]), int(r["n"])])
            n += 1
    log(f"{n} rows written to {a.out}, billed {fmt_bytes(billed)}")
    summary(f"### Salmon names\n{n} rows, billed {fmt_bytes(billed)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
