"""Shared helpers for the Ripple Map BigQuery jobs (WS-G).

Auth: BigQuery uses Application Default Credentials written by google-github-actions/auth (keyless Workload Identity
Federation, OWNER_DECISIONS D-8). Supabase uses SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY and only calls the
service-role RPC wrappers public.att_ce_* and public.att_ingest.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time
import urllib.error
import urllib.request

GIB = 1024 ** 3


def log(msg: str) -> None:
    print(msg, flush=True)


def summary(md: str) -> None:
    """Append a line to the GitHub job summary when running in Actions."""
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(md.rstrip("\n") + "\n")


def gh_run_ref() -> str:
    run = os.environ.get("GITHUB_RUN_ID")
    if not run:
        return "local"
    return f"{os.environ.get('GITHUB_WORKFLOW', '')}#{run}.{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}"


def finite(x):
    """Float or None (JSON has no NaN/Infinity)."""
    if x is None:
        return None
    try:
        f = float(x)
    except (TypeError, ValueError):
        return None
    return f if math.isfinite(f) else None


class Supabase:
    def __init__(self) -> None:
        url = os.environ.get("SUPABASE_URL", "").rstrip("/")
        key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not url or not key:
            sys.exit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
        self.base = url + "/rest/v1/rpc/"
        self.headers = {"apikey": key, "Content-Type": "application/json", "Accept": "application/json"}
        # Legacy service_role keys are JWTs and also go in Authorization; new sb_secret_ keys only need apikey.
        if key.startswith("eyJ"):
            self.headers["Authorization"] = "Bearer " + key

    def rpc(self, fn: str, args: dict, retries: int = 3, timeout: int = 120):
        body = json.dumps(args, separators=(",", ":")).encode()
        for attempt in range(1, retries + 1):
            req = urllib.request.Request(self.base + fn, data=body, headers=self.headers, method="POST")
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    raw = resp.read()
                    return json.loads(raw) if raw else None
            except urllib.error.HTTPError as e:
                detail = e.read().decode(errors="replace")[:500]
                if e.code >= 500 and attempt < retries:
                    time.sleep(2 * attempt)
                    continue
                raise RuntimeError(f"Supabase rpc {fn} failed: HTTP {e.code} {detail}") from None
            except urllib.error.URLError as e:
                if attempt < retries:
                    time.sleep(2 * attempt)
                    continue
                raise RuntimeError(f"Supabase rpc {fn} failed: {e}") from None
        return None


def bq_client(project: str, location: str):
    from google.cloud import bigquery  # imported late so --help works without the package

    return bigquery.Client(project=project, location=location)


def dry_run_bytes(client, sql: str, params=None) -> int:
    from google.cloud import bigquery

    cfg = bigquery.QueryJobConfig(dry_run=True, use_query_cache=False, query_parameters=params or [])
    job = client.query(sql, job_config=cfg)
    return int(job.total_bytes_processed or 0)


def run_query(client, sql: str, max_bytes_billed: int, params=None, dest=None):
    """Run a query with a hard maximum_bytes_billed ceiling (BigQuery fails the job, uncharged, above it)."""
    from google.cloud import bigquery

    cfg = bigquery.QueryJobConfig(maximum_bytes_billed=int(max_bytes_billed), use_query_cache=True,
                                  query_parameters=params or [])
    if dest is not None:
        cfg.destination = dest
    job = client.query(sql, job_config=cfg)
    rows = list(job.result())
    return rows, int(job.total_bytes_billed or 0), int(job.total_bytes_processed or 0)


def fmt_bytes(n: int) -> str:
    return f"{n / GIB:.3f} GiB ({n:,} B)"
