"""Ripple Map b9: QCEW county employment for 2001-2013 from the BLS bulk annual files, fetched on GitHub Actions.

The QCEW open-data API (used in the database by att_b9_tick) only serves 2014 onward (ledger 1274), so the earlier
years come from https://data.bls.gov/cew/data/files/<year>/csv/<year>_qtrly_by_industry.zip. From each zip only two
members are read: supersector 1023 (Financial activities) and 10 (Total, all industries). Rows kept are exactly the ones
the database parser keeps: private ownership (own_code 5), county level (agglvl 73 for 1023, 71 for 10), not suppressed,
numeric monthly employment. Written through public.att_b9_qcew_load in 2,000-row batches with a pause (disk-IO budget).

Rules: honest UA, stop on 403/429/503 with no retry, aggregate public counts only. No keys besides the Supabase
service role (GitHub secret, never logged).
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bq"))
from common import Supabase, log, summary  # noqa: E402

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
URL = "https://data.bls.gov/cew/data/files/{y}/csv/{y}_qtrly_by_industry.zip"
AGG = {"1023": "73", "10": "71"}


class Stop(Exception):
    pass


def download(url: str, dest: str) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=300) as resp, open(dest, "wb") as f:
            shutil.copyfileobj(resp, f, 1 << 20)
    except urllib.error.HTTPError as e:
        if e.code in (403, 429, 503):
            raise Stop(f"HTTP {e.code} from {url}") from None
        raise


def rows_from_zip(path: str, year: int):
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            m = re.search(r"q1-q4 (10|1023) ", os.path.basename(name))
            if not m:
                continue
            ind = m.group(1)
            with z.open(name) as fh:
                for r in csv.DictReader(io.TextIOWrapper(fh, encoding="utf-8", errors="replace")):
                    area = (r.get("area_fips") or "").strip()
                    if (r.get("own_code") or "").strip() != "5" or (r.get("agglvl_code") or "").strip() != AGG[ind]:
                        continue
                    if not re.fullmatch(r"[0-9]{5}", area) or area.endswith("000"):
                        continue
                    if (r.get("disclosure_code") or "").strip() == "N":
                        continue
                    q = (r.get("qtr") or "").strip()
                    if q not in ("1", "2", "3", "4") or int(r.get("year") or 0) != year:
                        continue
                    for mm in (1, 2, 3):
                        e = (r.get(f"month{mm}_emplvl") or "").strip()
                        if e.isdigit():
                            yield {"a": area, "i": ind, "m": f"{year}-{(int(q) - 1) * 3 + mm:02d}-01", "e": int(e)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from-year", type=int, default=2001)
    ap.add_argument("--to-year", type=int, default=2013)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.from_year < 2001 or a.to_year > 2013:
        sys.exit("years must be within 2001-2013 (2014+ comes from the open-data API)")
    sb = None if a.dry_run else Supabase()
    res = {"years": {}, "dry_run": a.dry_run, "stop": None}
    tmp = tempfile.mkdtemp()
    try:
        for y in range(a.from_year, a.to_year + 1):
            path = os.path.join(tmp, f"{y}.zip")
            t0 = time.time()
            download(URL.format(y=y), path)
            mb = os.path.getsize(path) / 1e6
            sent = written = 0
            batch: list[dict] = []
            for row in rows_from_zip(path, y):
                batch.append(row)
                if len(batch) == 2000:
                    sent += len(batch)
                    if sb:
                        written += int((sb.rpc("att_b9_qcew_load", {"p_rows": batch}) or {}).get("rows") or 0)
                        time.sleep(0.5)
                    batch = []
            if batch:
                sent += len(batch)
                if sb:
                    written += int((sb.rpc("att_b9_qcew_load", {"p_rows": batch}) or {}).get("rows") or 0)
            os.remove(path)
            res["years"][y] = {"zip_mb": round(mb, 1), "rows": sent, "written": written, "sec": round(time.time() - t0)}
            log(f"{y}: {res['years'][y]}")
    except Stop as e:
        res["stop"] = str(e)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        log(json.dumps(res, indent=1))
        summary("### QCEW backfill\n```\n" + json.dumps(res, indent=1) + "\n```")
    return 0


if __name__ == "__main__":
    sys.exit(main())
