#!/usr/bin/env python3
"""E9 phase 1 (ledger 1275, 1276): US baby-name counts by year from the public BigQuery copy of the SSA names data.

ssa.gov refused the database network (403, 2026-09-27) and the collection rules forbid working around a host that says
no, so the names come from bigquery-public-data.usa_names.usa_1910_current (SSA state-level counts, published by Google).
Only national totals per (name, sex, year) are written, for 1995 onward and only for names that are common enough to be
synthetic-control donors (>= 500 births over 2000-2010) plus the pre-registered target names. Aggregates only; no
personal data exists in this dataset.

Written through public.att_e9_names_load in 2,000-row batches. Every query is dry-run first under a byte cap.
"""
from __future__ import annotations

import argparse
import sys
import time

from common import GIB, Supabase, bq_client, dry_run_bytes, fmt_bytes, log, run_query, summary

TARGETS = ("Arya", "Elsa", "Khaleesi")
SQL = """
with nat as (
  select name, gender as sex, year, sum(number) as n
  from `bigquery-public-data.usa_names.usa_1910_current`
  where year >= 1995
  group by name, gender, year)
select nat.name, nat.sex, nat.year, nat.n
from nat
join (select name, sex from nat where year between 2000 and 2010 group by name, sex having sum(n) >= 500
      union distinct
      select name, sex from nat where name in unnest(@targets) group by name, sex) keep
  using (name, sex)
order by name, sex, year
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="ripple-509716")
    ap.add_argument("--location", default="US")
    ap.add_argument("--max-gib", type=float, default=2.0)
    ap.add_argument("--dry-run-only", action="store_true")
    a = ap.parse_args()
    from google.cloud import bigquery

    params = [bigquery.ArrayQueryParameter("targets", "STRING", list(TARGETS))]
    client = bq_client(a.project, a.location)
    est = dry_run_bytes(client, SQL, params)
    log(f"dry run: {fmt_bytes(est)}")
    if est > a.max_gib * GIB:
        sys.exit(f"query would scan {fmt_bytes(est)}, above the {a.max_gib} GiB cap")
    if a.dry_run_only:
        summary(f"### E9 names\nDry run only: {fmt_bytes(est)}")
        return 0
    rows, billed, _ = run_query(client, SQL, int(a.max_gib * GIB), params)
    out = [{"name": r["name"], "sex": r["sex"], "year": int(r["year"]), "n": int(r["n"])} for r in rows]
    log(f"{len(out)} rows, {len({(r['name'], r['sex']) for r in out})} names, years {min(r['year'] for r in out)}-"
        f"{max(r['year'] for r in out)}, billed {fmt_bytes(billed)}")
    sb = Supabase()
    written = 0
    for i in range(0, len(out), 2000):
        res = sb.rpc("att_e9_names_load", {"p_rows": out[i:i + 2000]}) or {}
        written += int(res.get("rows") or 0)
        time.sleep(0.5)
    targets = {t: sorted((r["year"], r["n"]) for r in out if r["name"] == t and r["sex"] == "F")[-3:] for t in TARGETS}
    summary(f"### E9 names\nrows {len(out)}, written {written}, billed {fmt_bytes(billed)}\n\nlatest target years: {targets}")
    log(f"written {written}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
