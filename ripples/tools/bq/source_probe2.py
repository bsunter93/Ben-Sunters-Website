#!/usr/bin/env python3
"""Attention-source probe 2: free non-Wikipedia sources with history. (1) Reddit via the Arctic Shift archive API and
(2) Hacker News via Algolia: a handful of requests each (honest UA, 2 s apart, stop on 403/429), recording status and a
short body sample. (3) GDELT TV-news caption n-grams in BigQuery: schema, date range, partitioning, and dry-run sizes of
a filtered query. Nothing about events is computed. Output: source_probe_v2.json.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request

from common import bq_client, dry_run_bytes, log, run_query, GIB

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
URLS = [
    "https://arctic-shift.photon-reddit.com/api/posts/search?subreddit=chess&after=2020-10-01&before=2020-10-02&limit=2",
    "https://arctic-shift.photon-reddit.com/api/posts/search?title=chess&after=2020-10-01&before=2020-10-02&limit=2",
    "https://arctic-shift.photon-reddit.com/api/posts/search/aggregate?aggregate=created_utc&frequency=day&title=chess"
    "&after=2020-10-01&before=2020-11-01",
    "https://arctic-shift.photon-reddit.com/api/comments/search/aggregate?aggregate=created_utc&frequency=day"
    "&body=chess&after=2020-10-01&before=2020-10-08",
    "https://arctic-shift.photon-reddit.com/api/time_series?key=global/posts/count&precision=day"
    "&after=2020-10-01&before=2020-10-05",
    "https://hn.algolia.com/api/v1/search_by_date?query=chess&tags=story&numericFilters=created_at_i>1601510400,"
    "created_at_i<1604188800&hitsPerPage=0",
]
IATV = "gdelt-bq.gdeltv2"


def main() -> int:
    rep = {"version": "v2", "http": [], "bq": {}}
    for u in URLS:
        req = urllib.request.Request(u, headers={"User-Agent": UA, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                body = r.read(3000).decode(errors="replace")
                rep["http"].append({"url": u, "status": r.status, "body": body})
        except urllib.error.HTTPError as e:
            rep["http"].append({"url": u, "status": e.code, "body": e.read(600).decode(errors="replace")})
            if e.code in (403, 429):
                log(f"stop: {e.code} on {u}")
        except Exception as e:  # noqa: BLE001
            rep["http"].append({"url": u, "error": str(e)[:300]})
        log(f"{u[:90]} -> {rep['http'][-1].get('status', rep['http'][-1].get('error'))}")
        time.sleep(2)
    c = bq_client("ripple-509716", "US")
    for name, sql in [
        ("iatv_cols", f"select table_name, column_name, data_type, is_partitioning_column from "
                      f"`{IATV}.INFORMATION_SCHEMA.COLUMNS` where table_name in ('iatv_1gramsv2','iatv_2gramsv2',"
                      f"'iatv_1grams','iatv_showinventory') order by table_name, ordinal_position"),
        ("iatv_opts", f"select table_name, option_name, option_value from `{IATV}.INFORMATION_SCHEMA.TABLE_OPTIONS` "
                      f"where table_name in ('iatv_1gramsv2','iatv_2gramsv2')"),
    ]:
        try:
            rows, _, _ = run_query(c, sql, 2 * GIB)
            rep["bq"][name] = [dict(r.items()) for r in rows]
        except Exception as e:  # noqa: BLE001
            rep["bq"][name] = {"error": str(e)[:300]}
    for name, sql in [
        ("dry_1gv2_all", f"select * from `{IATV}.iatv_1gramsv2`"),
        ("dry_1gv2_min", f"select min(DATE) from `{IATV}.iatv_1gramsv2`"),
    ]:
        try:
            rep["bq"][name] = dry_run_bytes(c, sql)
        except Exception as e:  # noqa: BLE001
            rep["bq"][name] = {"error": str(e)[:300]}
    try:
        cols = [r["column_name"] for r in rep["bq"].get("iatv_cols", []) if r.get("table_name") == "iatv_1gramsv2"]
        rep["bq"]["cols_1gv2"] = cols
        sample = f"select * from `{IATV}.iatv_1gramsv2` limit 5"
        rows, b, _ = run_query(c, sample, 2 * GIB)
        rep["bq"]["sample_1gv2"] = [{k: str(v) for k, v in r.items()} for r in rows]
        rep["bq"]["sample_billed"] = b
    except Exception as e:  # noqa: BLE001
        rep["bq"]["sample_1gv2"] = {"error": str(e)[:300]}
    open(sys.argv[1] if len(sys.argv) > 1 else "source_probe_v2.json", "w").write(json.dumps(rep, indent=1, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
