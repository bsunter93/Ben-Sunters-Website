#!/usr/bin/env python3
"""Probe 3: is the GDELT TV n-gram data clustered (so an exact NGRAM filter reads far less than the full-scan dry run),
and how are n-grams cased? Metadata queries (free) plus a tiny TABLESAMPLE read. Output: source_probe_v3.json."""
from __future__ import annotations

import json
import sys

from common import GIB, bq_client, run_query

T = "gdelt-bq.gdeltv2"


def main() -> int:
    c = bq_client("ripple-509716", "US")
    rep = {}
    for name, sql, cap in [
        ("clustering", f"select table_name, column_name, clustering_ordinal_position from `{T}.INFORMATION_SCHEMA.COLUMNS` "
                       f"where table_name in ('iatv_1gramsv2','iatv_2gramsv2') and clustering_ordinal_position is not null", GIB),
        ("partitions", f"select table_name, count(*) n, min(partition_id) p0, max(partition_id) p1, sum(total_logical_bytes) b "
                       f"from `{T}.INFORMATION_SCHEMA.PARTITIONS` where table_name in ('iatv_1gramsv2','iatv_2gramsv2') "
                       f"group by 1", GIB),
        ("sample_2g", f"select NGRAM, DATE, STATION, COUNT from `{T}.iatv_2gramsv2` tablesample system (0.001 percent) "
                      f"limit 30", 2 * GIB),
    ]:
        try:
            rows, b, _ = run_query(c, sql, cap)
            rep[name] = {"billed": b, "rows": [{k: str(v) for k, v in r.items()} for r in rows]}
        except Exception as e:  # noqa: BLE001
            rep[name] = {"error": str(e)[:300]}
        print(name, json.dumps(rep[name])[:1500], flush=True)
    open(sys.argv[1] if len(sys.argv) > 1 else "source_probe_v3.json", "w").write(json.dumps(rep, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
