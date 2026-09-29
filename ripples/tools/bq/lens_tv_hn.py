#!/usr/bin/env python3
"""Non-Wikipedia attention lenses for the named-subject test (ripples/docs/q6_lenses_protocol.md).

TV: US television news captions (Internet Archive TV News Archive via GDELT, gdelt-bq.gdeltv2.iatv_1gramsv2 and
iatv_2gramsv2): daily spoken mentions of each 1- or 2-word subject phrase, all stations summed, plus the day's total
caption words (the denominator). One scan per table, partition-pruned to the panel dates.
HN: Hacker News stories and comments (bigquery-public-data.hacker_news.full): daily items whose title or text contains
each subject phrase (any length, word-bounded, case-insensitive), plus the day's total items.

Aggregate daily counts only. Every query is dry-run first; the run refuses to go past the monthly free-tier budget
(--budget-gib, counting this project's bytes billed so far this month when that is readable).
Output: lens_tv.csv and lens_hn.csv (day, phrase, n), phrase "__total__" for the denominator.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import re
import sys

from common import GIB, bq_client, dry_run_bytes, fmt_bytes, log, run_query, summary

CORPUS = os.path.join(os.path.dirname(__file__), "..", "..", "corpus")
FILES = ["q4_subjects_v1.tsv", "q4_subjects_v1b.tsv", "q4_heldout_drama_v1.tsv"]
T0, T1 = "2015-06-01", "2026-09-01"


def phrase(subject: str) -> str:
    return " ".join(re.sub(r"\s*\([^)]*\)", "", subject).lower().split())


def phrases() -> list[str]:
    out = set()
    for f in FILES:
        for line in open(os.path.join(CORPUS, f), encoding="utf-8"):
            if line.startswith("#") or line.startswith("family\t") or not line.strip():
                continue
            out.add(phrase(line.rstrip("\n").split("\t")[4]))
    return sorted(p for p in out if p)


def day(v) -> str:
    if isinstance(v, int) or (isinstance(v, str) and v.isdigit()):
        s = str(v)
        return f"{s[:4]}-{s[4:6]}-{s[6:8]}"
    return str(v)[:10]


def tv_sql(table: str) -> str:
    return f"""
select DATE d, k, sum(COUNT) n from (
  select DATE, COUNT, if(lower(NGRAM) in unnest(@p), lower(NGRAM), '__other__') k
  from `gdelt-bq.gdeltv2.{table}`
  where TIMESTAMP >= timestamp('{T0}') and TIMESTAMP < timestamp('{T1}'))
group by 1, 2"""


def hn_sql() -> str:
    return f"""
with t as (
  select date(timestamp) d, lower(concat(ifnull(title, ''), ' ', ifnull(text, ''))) s
  from `bigquery-public-data.hacker_news.full`
  where timestamp >= timestamp('{T0}') and timestamp < timestamp('{T1}') and (deleted is null or not deleted))
select d, m k, count(*) n from t, unnest(array(select distinct x from unnest(regexp_extract_all(s, @re)) x)) m
group by 1, 2
union all
select d, '__total__', count(*) from t group by 1"""


def month_billed(client) -> int | None:
    for view in ("JOBS_BY_PROJECT", "JOBS_BY_USER"):
        try:
            rows, _, _ = run_query(client, f"select sum(total_bytes_billed) b from `region-us`.INFORMATION_SCHEMA.{view} "
                                           f"where creation_time >= timestamp_trunc(current_timestamp(), month)", GIB)
            return int(rows[0]["b"] or 0)
        except Exception as e:  # noqa: BLE001
            log(f"{view} unreadable: {str(e)[:120]}")
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="ripple-509716")
    ap.add_argument("--location", default="US")
    ap.add_argument("--budget-gib", type=float, default=900.0, help="stay under this month-to-date total")
    ap.add_argument("--outdir", default=".")
    a = ap.parse_args()
    from google.cloud import bigquery

    c = bq_client(a.project, a.location)
    P = phrases()
    p1 = [p for p in P if len(p.split()) == 1]
    p2 = [p for p in P if len(p.split()) == 2]
    log(f"{len(P)} phrases: {len(p1)} one-word, {len(p2)} two-word, {len(P) - len(p1) - len(p2)} longer (HN only)")
    used = month_billed(c)
    log(f"month-to-date billed: {fmt_bytes(used) if used is not None else 'unknown'}")
    spent = used or 0
    alts = "|".join(re.escape(p).replace("\\'", "'").replace("'", "(?:'|&#x27;)")
                    for p in sorted(P, key=len, reverse=True))
    plan = [("tv", "iatv_1gramsv2", tv_sql("iatv_1gramsv2"), [bigquery.ArrayQueryParameter("p", "STRING", p1)]),
            ("tv", "iatv_2gramsv2", tv_sql("iatv_2gramsv2"), [bigquery.ArrayQueryParameter("p", "STRING", p2)]),
            ("hn", "hacker_news", hn_sql(), [bigquery.ScalarQueryParameter("re", "STRING", rf"\b({alts})\b")])]
    files = {"tv": open(os.path.join(a.outdir, "lens_tv.csv"), "w", newline=""),
             "hn": open(os.path.join(a.outdir, "lens_hn.csv"), "w", newline="")}
    w = {k: csv.writer(f) for k, f in files.items()}
    for k in w:
        w[k].writerow(["day", "phrase", "n"])
    tv_total = {}
    notes = []
    for lens, table, sql, params in plan:
        est = dry_run_bytes(c, sql, params)
        log(f"{table}: dry run {fmt_bytes(est)}")
        if spent + est > a.budget_gib * GIB:
            notes.append(f"{table} skipped: {fmt_bytes(est)} would pass the {a.budget_gib} GiB monthly budget")
            log(notes[-1])
            continue
        rows, b, _ = run_query(c, sql, int(est * 1.2) + GIB, params)
        spent += b
        n = 0
        for r in rows:
            d, key, cnt = day(r["d"]), r["k"], int(r["n"])
            if lens == "tv":
                if table == "iatv_1gramsv2":
                    tv_total[d] = tv_total.get(d, 0) + cnt
                if key == "__other__":
                    continue
            else:
                key = key.replace("&#x27;", "'")
            w[lens].writerow([d, key, cnt])
            n += 1
        log(f"{table}: {n} rows, billed {fmt_bytes(b)}")
    for d, t in sorted(tv_total.items()):
        w["tv"].writerow([d, "__total__", t])
    for f in files.values():
        f.close()
    summary(f"### Lens build (TV, HN)\nbilled this run {fmt_bytes(spent - (used or 0))}; " + "; ".join(notes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
