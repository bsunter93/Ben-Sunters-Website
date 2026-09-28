"""Store finished Q3 screen reports in Supabase (ripples.att_q3_results via att_q3_result_put), so results can be read
in full later: the job log API returns only the last 5,000 lines. Usage: python q3_upload.py FILE [FILE ...].
Missing files are skipped (a lens that did not finish). Aggregate statistics only."""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools", "bq"))
from common import Supabase  # noqa: E402


def clean(x):
    """NaN/inf are not valid JSON for Postgres jsonb: store them as null."""
    if isinstance(x, float) and x != x or x in (float("inf"), float("-inf")):
        return None
    if isinstance(x, dict):
        return {k: clean(v) for k, v in x.items()}
    if isinstance(x, list):
        return [clean(v) for v in x]
    return x


def main() -> int:
    run = f"{os.environ.get('GITHUB_SERVER_URL', '')}/{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/" \
          f"{os.environ.get('GITHUB_RUN_ID', '')}"
    sb = Supabase()
    for path in sys.argv[1:]:
        if not os.path.exists(path):
            print(f"skip {path}: not found", flush=True)
            continue
        name = os.path.basename(path).removesuffix(".json")
        rid = sb.rpc("att_q3_result_put", {"p_name": name, "p_run": run, "p_report": clean(json.load(open(path)))})
        print(f"stored {name} as {rid}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
