#!/usr/bin/env python3
"""Attention-source probe: what the free public BigQuery datasets actually hold (tables, columns, date ranges,
coverage), before any lens is designed on them. Metadata and small aggregate queries only, each dry-run first under a
byte cap. No results about events are computed here. Output: a JSON report (source_probe_v1).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys

from common import GIB, bq_client, dry_run_bytes, fmt_bytes, log, run_query

GT = "bigquery-public-data.google_trends"
QUERIES = [
    ("gt_tables", f"select table_id, row_count, size_bytes from `{GT}.__TABLES__`"),
    ("gt_columns", f"select table_name, column_name, data_type from `{GT}.INFORMATION_SCHEMA.COLUMNS` "
                   "order by table_name, ordinal_position"),
    ("gt_top_ranges", f"select min(refresh_date) r0, max(refresh_date) r1, count(distinct refresh_date) nr, "
                      f"min(week) w0, max(week) w1, count(distinct term) nt, count(distinct dma_id) nd "
                      f"from `{GT}.top_terms`"),
    ("gt_rising_ranges", f"select min(refresh_date) r0, max(refresh_date) r1, count(distinct refresh_date) nr, "
                         f"min(week) w0, max(week) w1, count(distinct term) nt from `{GT}.top_rising_terms`"),
    ("gt_intl_ranges", f"select min(refresh_date) r0, max(refresh_date) r1, count(distinct refresh_date) nr, "
                       f"min(week) w0, max(week) w1, count(distinct term) nt, count(distinct country_code) nc "
                       f"from `{GT}.international_top_terms`"),
    ("gt_latest_history", f"select refresh_date, count(distinct week) nw, count(distinct term) nt, "
                          f"countif(score is not null) scored, count(*) n from `{GT}.top_terms` "
                          f"where refresh_date >= date_sub(current_date(), interval 3 day) group by 1 order by 1"),
    ("gt_top_sample", f"select refresh_date, week, term, rank, score from `{GT}.top_terms` "
                      f"where refresh_date = (select max(refresh_date) from `{GT}.top_terms`) "
                      f"and dma_name like 'New York%' order by week desc, rank limit 80"),
    ("gt_rising_sample", f"select * from `{GT}.top_rising_terms` "
                         f"where refresh_date = (select max(refresh_date) from `{GT}.top_rising_terms`) "
                         f"and dma_name like 'New York%' order by week desc, rank limit 40"),
    ("gt_terms_per_week", f"select week, count(distinct term) nt from `{GT}.top_terms` "
                          f"where refresh_date = (select max(refresh_date) from `{GT}.top_terms`) "
                          f"group by 1 order by 1 limit 400"),
    ("hn_ranges", "select min(timestamp) t0, max(timestamp) t1, count(*) n, countif(type='story') stories "
                  "from `bigquery-public-data.hacker_news.full`"),
    ("gdelt_tables", "select table_id, row_count, size_bytes from `gdelt-bq.gdeltv2.__TABLES__`"),
    ("wiki_tables", "select table_id, row_count, size_bytes from `bigquery-public-data.wikipedia.__TABLES__` "
                    "order by table_id desc limit 30"),
    ("reddit_fh", "select table_id, row_count from `fh-bigquery.reddit_comments.__TABLES__` "
                  "order by table_id desc limit 12"),
    ("reddit_posts_fh", "select table_id, row_count from `fh-bigquery.reddit_posts.__TABLES__` "
                        "order by table_id desc limit 12"),
    ("so_ranges", "select min(creation_date) t0, max(creation_date) t1, count(*) n "
                  "from `bigquery-public-data.stackoverflow.posts_questions`"),
]


def conv(v):
    if isinstance(v, (dt.date, dt.datetime)):
        return v.isoformat()
    return v


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="ripple-509716")
    ap.add_argument("--location", default="US")
    ap.add_argument("--max-gib", type=float, default=25.0)
    ap.add_argument("--out", default="source_probe_v1.json")
    a = ap.parse_args()
    client = bq_client(a.project, a.location)
    rep, total = {"version": "v1", "queries": {}}, 0
    for name, sql in QUERIES:
        try:
            est = dry_run_bytes(client, sql)
            if est > a.max_gib * GIB:
                rep["queries"][name] = {"skip": f"would scan {fmt_bytes(est)}"}
                continue
            rows, billed, _ = run_query(client, sql, int(a.max_gib * GIB))
            total += billed
            rep["queries"][name] = {"billed": billed, "rows": [{k: conv(v) for k, v in r.items()} for r in rows]}
            log(f"{name}: {len(rows)} rows, billed {fmt_bytes(billed)}")
        except Exception as e:  # noqa: BLE001 - record and continue (dataset may not exist or be restricted)
            rep["queries"][name] = {"error": str(e)[:400]}
            log(f"{name}: error {str(e)[:200]}")
    rep["billed_total"] = total
    open(a.out, "w").write(json.dumps(rep, indent=1, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
