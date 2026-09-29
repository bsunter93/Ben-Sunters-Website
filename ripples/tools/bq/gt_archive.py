#!/usr/bin/env python3
"""Google Trends archive: copy the public BigQuery trending-search lists (bigquery-public-data.google_trends) into
ripples.att_gt_terms before they expire (the dataset keeps only about 30 days of refresh dates). Daily, resumable: only
refresh dates not yet stored are read (the tables are partitioned by refresh_date, so each day scans little).

US (top_terms, top_rising_terms): the 210 DMA lists aggregated to national per (refresh_date, term, week) over scored
rows: n_regions = DMAs, best rank, mean score, max percent gain. International: per country, latest week only.
Aggregates of public lists only; no personal data.
"""
from __future__ import annotations

import argparse
import sys

from common import GIB, Supabase, bq_client, dry_run_bytes, fmt_bytes, log, run_query, summary

GT = "bigquery-public-data.google_trends"
US_SQL = """
select refresh_date, term, week, count(distinct dma_id) n, min(rank) best_rank, avg(score) mean_score, {gain} gain
from `{gt}.{table}`
where refresh_date in unnest(@dates) and score is not null
group by 1, 2, 3
"""
INTL_SQL = """
with t as (select * from `{gt}.{table}` where refresh_date in unnest(@dates)),
     lw as (select refresh_date, max(week) mw from t group by 1)
select t.refresh_date, t.country_code geo, t.term, t.week, count(*) n, min(t.rank) best_rank, avg(t.score) mean_score,
       {gain} gain
from t join lw on t.refresh_date = lw.refresh_date and t.week = lw.mw
group by 1, 2, 3, 4
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="ripple-509716")
    ap.add_argument("--location", default="US")
    ap.add_argument("--max-gib", type=float, default=60.0)
    a = ap.parse_args()
    from google.cloud import bigquery

    c, sb = bq_client(a.project, a.location), Supabase()
    have = {(r["scope"], str(r["refresh_date"])) for r in (sb.rpc("att_gt_have", {}) or [])}
    avail, _, _ = run_query(c, f"select distinct refresh_date d from `{GT}.top_terms` "
                               f"where refresh_date >= date_sub(current_date(), interval 45 day)", 2 * GIB)
    avail_i, _, _ = run_query(c, f"select distinct refresh_date d from `{GT}.international_top_terms` "
                                 f"where refresh_date >= date_sub(current_date(), interval 45 day)", 2 * GIB)
    jobs = [("us", sorted(str(r["d"]) for r in avail if ("us", str(r["d"])) not in have)),
            ("intl", sorted(str(r["d"]) for r in avail_i if ("intl", str(r["d"])) not in have))]
    total, billed = 0, 0
    for scope, dates in jobs:
        log(f"{scope}: {len(dates)} refresh dates to archive")
        if not dates:
            continue
        p = [bigquery.ArrayQueryParameter("dates", "DATE", dates)]
        for kind, table in (("top", "top_terms"), ("rising", "top_rising_terms")):
            if scope == "intl":
                table = "international_" + table
            gain = "max(percent_gain)" if kind == "rising" else "null"
            sql = (US_SQL if scope == "us" else INTL_SQL).format(gt=GT, table=table, gain=gain)
            est = dry_run_bytes(c, sql, p)
            if est > a.max_gib * GIB:
                sys.exit(f"{table}: would scan {fmt_bytes(est)}")
            rows, b, _ = run_query(c, sql, int(a.max_gib * GIB), p)
            billed += b
            out = [{"rd": str(r["refresh_date"]), "scope": scope, "geo": (r.get("geo") or "US") if scope == "intl"
                    else "US", "kind": kind, "term": r["term"], "week": str(r["week"]), "n": int(r["n"]),
                    "rank": r["best_rank"], "score": None if r["mean_score"] is None else round(float(r["mean_score"]), 2),
                    "gain": r["gain"]} for r in rows if r["term"]]
            for i in range(0, len(out), 4000):
                total += (sb.rpc("att_gt_load", {"p_rows": out[i:i + 4000]}) or {}).get("rows", 0)
            log(f"{scope}/{kind}: {len(out)} rows, billed {fmt_bytes(b)}")
    summary(f"### Google Trends archive\n{total} rows loaded, billed {fmt_bytes(billed)}")
    log(f"done: {total} rows, billed {fmt_bytes(billed)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
