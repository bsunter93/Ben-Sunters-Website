#!/usr/bin/env python3
"""NOAA Storm Events aggregates for Ripple Map (ENGINE 6.3 regional outcome panels), computed in BigQuery.

Source: bigquery-public-data.noaa_historic_severe_storms.storms_<year> (NOAA NCEI Storm Events Database, one table per
year, one row per storm event report). Nothing is downloaded from NOAA directly and no event-level row is stored: only
STATE x WEEK aggregates (week ending Saturday, the grain of the other weekly panels) go to Supabase through
public.att_ingest under source noaa.storms:

  metric n         number of storm event reports in the state that week (all event types)
  metric damage    property + crop damage in USD (sum; 0 when none reported)
  metric n_flood   reports whose event_type is a flood type (flash flood, flood, coastal flood, lakeshore flood)

  --metrics full adds (owner option, ~2.5x the rows):
  metric n_tornado, n_wind_hail (thunderstorm wind, hail, high wind, strong wind), n_winter (winter storm, winter
  weather, heavy snow, blizzard, ice storm, cold/wind chill, extreme cold/wind chill), n_heat_fire (heat, excessive heat,
  wildfire, drought)

Rows: geo US-<ST>, key <ST>, day = week-ending Saturday, meta {weekly: true, via: bq}. Only the 50 states + DC (NOAA's
state names are mapped; marine zones, territories and unknown names are dropped and counted in the log).

Budget: every query is dry-run first (--max-gib-query, --max-gib-run), each executed job carries maximum_bytes_billed,
the run aborts when the Supabase database is within --db-headroom-mb of its cap, and --max-rows caps the rows written
per run. Storage estimate at 115 B/row: 3 metrics x 52 geos x 52 weeks/yr = ~8k rows/yr (~1 MB/yr).
"""
from __future__ import annotations

import argparse
import datetime as dt
import sys
from collections import defaultdict

from common import GIB, Supabase, bq_client, dry_run_bytes, fmt_bytes, gh_run_ref, log, run_query, summary

PUBLIC = "bigquery-public-data.noaa_historic_severe_storms"
STATES = {
    "ALABAMA": "AL", "ALASKA": "AK", "ARIZONA": "AZ", "ARKANSAS": "AR", "CALIFORNIA": "CA", "COLORADO": "CO",
    "CONNECTICUT": "CT", "DELAWARE": "DE", "DISTRICT OF COLUMBIA": "DC", "FLORIDA": "FL", "GEORGIA": "GA", "HAWAII": "HI",
    "IDAHO": "ID", "ILLINOIS": "IL", "INDIANA": "IN", "IOWA": "IA", "KANSAS": "KS", "KENTUCKY": "KY", "LOUISIANA": "LA",
    "MAINE": "ME", "MARYLAND": "MD", "MASSACHUSETTS": "MA", "MICHIGAN": "MI", "MINNESOTA": "MN", "MISSISSIPPI": "MS",
    "MISSOURI": "MO", "MONTANA": "MT", "NEBRASKA": "NE", "NEVADA": "NV", "NEW HAMPSHIRE": "NH", "NEW JERSEY": "NJ",
    "NEW MEXICO": "NM", "NEW YORK": "NY", "NORTH CAROLINA": "NC", "NORTH DAKOTA": "ND", "OHIO": "OH", "OKLAHOMA": "OK",
    "OREGON": "OR", "PENNSYLVANIA": "PA", "RHODE ISLAND": "RI", "SOUTH CAROLINA": "SC", "SOUTH DAKOTA": "SD",
    "TENNESSEE": "TN", "TEXAS": "TX", "UTAH": "UT", "VERMONT": "VT", "VIRGINIA": "VA", "WASHINGTON": "WA",
    "WEST VIRGINIA": "WV", "WISCONSIN": "WI", "WYOMING": "WY",
}
GROUPS = {
    "n_flood": ("flash flood", "flood", "coastal flood", "lakeshore flood"),
    "n_tornado": ("tornado", "funnel cloud", "waterspout"),
    "n_wind_hail": ("thunderstorm wind", "hail", "high wind", "strong wind", "marine thunderstorm wind", "marine hail"),
    "n_winter": ("winter storm", "winter weather", "heavy snow", "blizzard", "ice storm", "cold/wind chill",
                 "extreme cold/wind chill", "lake-effect snow", "sleet", "freezing fog", "frost/freeze"),
    "n_heat_fire": ("heat", "excessive heat", "wildfire", "drought", "dense smoke"),
}
CORE = ("n", "damage", "n_flood")
FULL = CORE + ("n_tornado", "n_wind_hail", "n_winter", "n_heat_fire")


def parse_date(s):
    return dt.date.fromisoformat(s) if s else None


def week_end_sat(d: dt.date) -> dt.date:
    return d + dt.timedelta(days=(5 - d.weekday()) % 7)  # Monday=0 .. Saturday=5


def year_sql(year: int) -> str:
    """One aggregate query per year table: state x day x event_type counts + damage (tiny result, one scan of the table)."""
    return f"""
      SELECT UPPER(state) AS st, DATE(event_begin_time) AS d, LOWER(event_type) AS et, COUNT(*) AS n,
             SUM(COALESCE(damage_property, 0) + COALESCE(damage_crops, 0)) AS dmg
      FROM `{PUBLIC}.storms_{year}`
      WHERE event_begin_time IS NOT NULL AND state IS NOT NULL
      GROUP BY 1, 2, 3
    """


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", default="ripple-509716", help="billing project for the query jobs")
    ap.add_argument("--location", default="US")
    ap.add_argument("--from", dest="date_from", default="2019-01-01", help="first week-ending day to write (YYYY-MM-DD)")
    ap.add_argument("--to", dest="date_to", default=None, help="last day (default: today minus 60: NOAA publishes with a lag)")
    ap.add_argument("--metrics", choices=["core", "full"], default="core", help="core = n, damage, n_flood; full adds 4 type groups")
    ap.add_argument("--max-gib-query", type=float, default=2.0)
    ap.add_argument("--max-gib-run", type=float, default=10.0)
    ap.add_argument("--max-rows", type=int, default=60000)
    ap.add_argument("--db-headroom-mb", type=int, default=15)
    ap.add_argument("--dry-run-only", action="store_true")
    a = ap.parse_args()
    d_from = parse_date(a.date_from)
    d_to = parse_date(a.date_to) or (dt.date.today() - dt.timedelta(days=60))
    metrics = FULL if a.metrics == "full" else CORE
    q_cap, run_cap = int(a.max_gib_query * GIB), int(a.max_gib_run * GIB)

    sb = Supabase()
    run_id = sb.rpc("att_ce_log_run", {"p": {"kind": "storm_events_bq", "gh_run": gh_run_ref(),
                                               "detail": {"dry_run_only": a.dry_run_only, "metrics": a.metrics,
                                                          "from": d_from.isoformat(), "to": d_to.isoformat()}}})

    def finish(status, **kw):
        sb.rpc("att_ce_log_run", {"p": {"run_id": run_id, "status": status, **kw}})

    # database headroom (same guard as the wiki backfill: att_ce_wiki_targets reports db_mb / cap_mb)
    w = sb.rpc("att_ce_wiki_targets", {"p_from": None, "p_to": None, "p_limit": 1})
    db_mb, cap_mb = float(w["db_mb"]), float(w["cap_mb"])
    log(f"db {db_mb} MB of {cap_mb} MB; window {d_from}..{d_to}; metrics {a.metrics}")
    summary(f"### NOAA Storm Events aggregates (BigQuery)\n- window {d_from}..{d_to}; metrics {a.metrics}; db {db_mb}/{cap_mb} MB")
    if db_mb > cap_mb - a.db_headroom_mb:
        finish("aborted", detail={"reason": "db_headroom", "db_mb": db_mb, "cap_mb": cap_mb})
        log("ABORT: database too close to its size cap")
        return 2

    client = bq_client(a.project, a.location)
    from google.api_core.exceptions import NotFound

    est_total = billed = written = 0
    dropped = defaultdict(int)
    stop_reason = "done"
    try:
        for year in range(d_from.year, d_to.year + 1):
            try:
                client.get_table(f"{PUBLIC}.storms_{year}")
            except NotFound:
                log(f"warning: {PUBLIC}.storms_{year} does not exist yet; skipping {year}")
                continue
            sql = year_sql(year)
            est = dry_run_bytes(client, sql)
            log(f"{year}: dry-run {fmt_bytes(est)}")
            if est > q_cap:
                finish("aborted", detail={"reason": "query_cap", "year": year, "bytes": est})
                log("ABORT: one query exceeds --max-gib-query")
                return 3
            if est_total + est > run_cap:
                stop_reason = "run_cap"
                break
            est_total += est
            if a.dry_run_only:
                continue
            rows, bb, _ = run_query(client, sql, max_bytes_billed=int(est * 1.05) + 10 * 1024 ** 2)
            billed += bb
            agg = defaultdict(float)
            for r in rows:
                st = STATES.get(str(r["st"] or "").strip())
                if not st:
                    dropped[str(r["st"])[:30]] += int(r["n"] or 0)
                    continue
                d = r["d"]
                if d is None or d < d_from or d > d_to:
                    continue
                wk = week_end_sat(d).isoformat()
                n = int(r["n"] or 0)
                agg[(st, wk, "n")] += n
                agg[(st, wk, "damage")] += float(r["dmg"] or 0)
                et = str(r["et"] or "").strip().lower()
                for m, types in GROUPS.items():
                    if m in metrics and et in types:
                        agg[(st, wk, m)] += n
            # zero-fill count metrics for state-weeks that had reports of any kind but none of a group
            weeks = {(st, wk) for (st, wk, _m) in agg}
            for (st, wk) in weeks:
                for m in metrics:
                    agg.setdefault((st, wk, m), 0.0)
            out = [{"source": "noaa.storms", "metric": m, "geo": f"US-{st}", "key": st, "day": wk, "value": v,
                    "meta": {"weekly": True, "via": "bq", "table": f"storms_{year}"}} for (st, wk, m), v in sorted(agg.items())]
            n_rej = 0
            for i in range(0, len(out), 1000):
                res = sb.rpc("att_ingest", {"p_rows": out[i:i + 1000]})
                written += int(res.get("rows") or 0)
                n_rej += len(res.get("rejected") or [])
                if any(x.get("reason") == "db_size_cap" for x in res.get("rejected") or []):
                    stop_reason = "db_size_cap"
                    break
            log(f"  {year}: {len(rows)} BQ rows -> {len(out)} weekly rows; written total {written}; rejected {n_rej}; billed {fmt_bytes(bb)}")
            if stop_reason == "db_size_cap":
                break
            if written >= a.max_rows:
                stop_reason = "row_cap"
                break
        if dropped:
            top = sorted(dropped.items(), key=lambda x: -x[1])[:8]
            log(f"dropped non-state rows (marine zones / territories): {top}")
        log(f"stop: {stop_reason}; dry-run total {fmt_bytes(est_total)}; billed {fmt_bytes(billed)}; rows {written}")
        summary(f"- stop: {stop_reason}\n- dry-run total: {fmt_bytes(est_total)} (cap {a.max_gib_run} GiB)\n"
                f"- billed: {fmt_bytes(billed)}\n- rows written: {written}")
        finish("ok" if stop_reason in ("done", "row_cap") else "partial", rows_written=written,
               detail={"stop": stop_reason, "est_bytes": est_total, "billed_bytes": billed, "metrics": a.metrics,
                       "dropped": dict(sorted(dropped.items(), key=lambda x: -x[1])[:8])})
        return 0
    except Exception as e:  # noqa: BLE001
        finish("failed", detail={"error": str(e)[:500], "rows_written": written})
        log(f"FAILED: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
