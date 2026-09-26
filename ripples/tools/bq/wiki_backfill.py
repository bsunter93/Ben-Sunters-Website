#!/usr/bin/env python3
"""Backfill daily Wikipedia pageviews for tracked titles from bigquery-public-data.wikipedia.pageviews_YYYY
(OWNER_DECISIONS D-12). The AQS API stays for the daily top-up; this only extends history backwards.

1. Work list from Supabase (public.att_ce_wiki_targets): registry wiki.pv titles with a gap at the start of the window;
   fill_to is the day before the first stored day, so AQS rows are never overwritten.
2. Walk the union date range backwards in chunks (never crossing a year, since tables are per year). Each chunk query
   is partition-pruned by datehour literals and filtered to wiki IN (our languages, desktop + mobile web codes) and
   title IN (tracked list) via query parameters.
3. Every chunk is dry-run first. A chunk over --max-gib-query is halved (down to one day). The run stops before the
   chunk that would take the cumulative dry-run estimate over --max-gib-run, or once --max-rows rows were written, or
   when the database is within --db-headroom-mb of its cap. Executed jobs carry maximum_bytes_billed.
4. Rows go through public.att_ingest (source wiki.pv, metric n, geo <lang>.wikipedia, key = title, meta via=bq).

Note: the pageview dumps behind this dataset count desktop (`en`) and mobile web (`en.m`); AQS all-access also counts
the apps, so BigQuery history can sit slightly below AQS for app-heavy titles. Rows are tagged meta.via = 'bq'.
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from collections import defaultdict

from common import GIB, Supabase, bq_client, dry_run_bytes, fmt_bytes, gh_run_ref, log, run_query, summary

PUBLIC = "bigquery-public-data.wikipedia"


def parse_date(s):
    if s is None or s == "":
        return None
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        sys.exit(f"bad date {s!r}; use YYYY-MM-DD")
    return dt.date.fromisoformat(s)


def chunk_sql(year: int, a: dt.date, b: dt.date) -> str:
    # a, b are date objects (validated), inlined as literals so partition pruning is certain.
    end = b + dt.timedelta(days=1)
    return f"""
SELECT DATE(datehour) AS d, wiki, title, SUM(views) AS v
FROM `{PUBLIC}.pageviews_{int(year)}`
WHERE datehour >= TIMESTAMP('{a.isoformat()} 00:00:00+00') AND datehour < TIMESTAMP('{end.isoformat()} 00:00:00+00')
  AND wiki IN UNNEST(@wikis)
  AND title IN UNNEST(@titles)
GROUP BY d, wiki, title""".strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", default="ripple-509716", help="billing project for the query jobs")
    ap.add_argument("--location", default="US")
    ap.add_argument("--from", dest="date_from", default=None, help="YYYY-MM-DD (default: to - ce.wiki_bq_days)")
    ap.add_argument("--to", dest="date_to", default=None, help="YYYY-MM-DD (default: today - 2)")
    ap.add_argument("--max-titles", type=int, default=1000)
    ap.add_argument("--chunk-days", type=int, default=7)
    ap.add_argument("--max-gib-query", type=float, default=25.0)
    ap.add_argument("--max-gib-run", type=float, default=100.0)
    ap.add_argument("--max-rows", type=int, default=40000)
    ap.add_argument("--db-headroom-mb", type=int, default=30)
    ap.add_argument("--dry-run-only", action="store_true")
    a = ap.parse_args()
    d_from, d_to = parse_date(a.date_from), parse_date(a.date_to)
    q_cap, run_cap = int(a.max_gib_query * GIB), int(a.max_gib_run * GIB)

    sb = Supabase()
    run_id = sb.rpc("att_ce_log_run", {"p": {"kind": "wiki_bq_backfill", "gh_run": gh_run_ref(),
                                               "detail": {"dry_run_only": a.dry_run_only}}})

    def finish(status, **kw):
        sb.rpc("att_ce_log_run", {"p": {"run_id": run_id, "status": status, **kw}})

    est_total = billed = written = 0
    try:
        w = sb.rpc("att_ce_wiki_targets", {"p_from": d_from.isoformat() if d_from else None,
                                           "p_to": d_to.isoformat() if d_to else None, "p_limit": a.max_titles})
        targets = w.get("targets") or []
        log(f"window {w['from']}..{w['to']}: {len(targets)} titles with a gap; db {w['db_mb']} MB of {w['cap_mb']} MB")
        summary(f"### Wikipedia BigQuery backfill\n- window {w['from']}..{w['to']}; titles with a gap: {len(targets)}; "
                f"db {w['db_mb']}/{w['cap_mb']} MB")
        if not targets:
            finish("ok", rows_written=0, detail={"note": "no gaps"})
            return 0
        if float(w["db_mb"]) > float(w["cap_mb"]) - a.db_headroom_mb:
            finish("aborted", detail={"reason": "db_headroom", "db_mb": w["db_mb"], "cap_mb": w["cap_mb"]})
            log("ABORT: database too close to its size cap")
            return 2

        tg = []
        for t in targets:
            lang = t["geo"].split(".")[0]
            tg.append({"key": t["key"], "geo": t["geo"], "lang": lang,
                       "from": dt.date.fromisoformat(t["fill_from"]), "to": dt.date.fromisoformat(t["fill_to"])})
        lo, hi = min(t["from"] for t in tg), max(t["to"] for t in tg)

        client = bq_client(a.project, a.location)
        from google.api_core.exceptions import NotFound
        from google.cloud import bigquery

        have_year = {}

        def year_ok(y):
            if y not in have_year:
                try:
                    client.get_table(f"{PUBLIC}.pageviews_{y}")
                    have_year[y] = True
                except NotFound:
                    log(f"warning: {PUBLIC}.pageviews_{y} does not exist; skipping {y}")
                    have_year[y] = False
            return have_year[y]

        b = hi
        stop_reason = "done"
        chunk = max(1, a.chunk_days)
        while b >= lo:
            a_day = max(lo, b - dt.timedelta(days=chunk - 1), dt.date(b.year, 1, 1))
            active = [t for t in tg if t["from"] <= b and t["to"] >= a_day]
            if not active or not year_ok(b.year):
                b = a_day - dt.timedelta(days=1)
                continue
            wikis = sorted({t["lang"] for t in active} | {t["lang"] + ".m" for t in active})
            titles = sorted({t["key"] for t in active})
            params = [bigquery.ArrayQueryParameter("wikis", "STRING", wikis),
                      bigquery.ArrayQueryParameter("titles", "STRING", titles)]
            sql = chunk_sql(b.year, a_day, b)
            est = dry_run_bytes(client, sql, params)
            log(f"dry-run {a_day}..{b} ({len(titles)} titles, {len(wikis)} wikis): {fmt_bytes(est)}")
            if est > q_cap:
                if chunk == 1:
                    stop_reason = "single_day_over_query_cap"
                    break
                chunk = max(1, chunk // 2)
                continue
            if est_total + est > run_cap:
                stop_reason = "run_byte_cap"
                break
            est_total += est
            if a.dry_run_only:
                b = a_day - dt.timedelta(days=1)
                continue
            rows, bb, _ = run_query(client, sql, max_bytes_billed=int(est * 1.05) + 10 * 1024 ** 2, params=params)
            billed += bb
            want = defaultdict(list)
            for t in active:
                want[(t["geo"], t["key"])].append(t)
            agg = defaultdict(float)
            for r in rows:
                geo = r["wiki"].split(".")[0] + ".wikipedia"
                spans = want.get((geo, r["title"]))
                if not spans or not any(s["from"] <= r["d"] <= s["to"] for s in spans):
                    continue
                agg[(geo, r["title"], r["d"])] += float(r["v"] or 0)
            out = [{"source": "wiki.pv", "metric": "n", "geo": g, "key": k, "day": d.isoformat(), "value": v,
                    "meta": {"via": "bq"}} for (g, k, d), v in agg.items()]
            n_rej = 0
            for i in range(0, len(out), 1000):
                res = sb.rpc("att_ingest", {"p_rows": out[i:i + 1000]})
                written += int(res.get("rows") or 0)
                n_rej += len(res.get("rejected") or [])
                if any(x.get("reason") == "db_size_cap" for x in res.get("rejected") or []):
                    stop_reason = "db_size_cap"
                    break
            log(f"  {len(rows)} BQ rows -> {len(out)} daily rows; written total {written}; rejected {n_rej}; billed {fmt_bytes(bb)}")
            if stop_reason == "db_size_cap":
                break
            if written >= a.max_rows:
                stop_reason = "row_cap"
                break
            b = a_day - dt.timedelta(days=1)

        log(f"stop: {stop_reason}; dry-run total {fmt_bytes(est_total)}; billed {fmt_bytes(billed)}; rows {written}")
        summary(f"- stop: {stop_reason}\n- dry-run total: {fmt_bytes(est_total)} (cap {a.max_gib_run} GiB)\n"
                f"- billed: {fmt_bytes(billed)}\n- rows written: {written}")
        status = "ok" if stop_reason in ("done", "row_cap", "run_byte_cap") else "aborted"
        finish(status, dry_run_bytes=est_total, billed_bytes=billed, rows_written=written, units=len(targets),
               detail={"stop": stop_reason, "from": w["from"], "to": w["to"], "reached": b.isoformat()})
        return 0 if status == "ok" else 2
    except Exception as e:
        finish("failed", dry_run_bytes=est_total, billed_bytes=billed, rows_written=written,
               detail={"error": str(e)[:1000]})
        raise


if __name__ == "__main__":
    sys.exit(main())
