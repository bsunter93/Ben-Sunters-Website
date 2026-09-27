"""Ripple Lab data: a county x quarter panel from BLS QCEW bulk files plus FEMA DR declarations.

Everything is public and keyless and fetched with an honest UA. Nothing personal: QCEW is aggregate employment and
FEMA declarations are public records. Outputs are cached in LAB_CACHE (default ~/.cache/ripples-lab):

  panel.npz   counties[C], quarters[Q] (e.g. 20011), series[S], emp[S, C, Q] (mean monthly private employment; NaN when
              missing or suppressed)
  fema.json   DR declarations: disasterNumber, state, county fips, incidentType, incidentBeginDate
"""
from __future__ import annotations

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

import numpy as np

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
CACHE = os.path.expanduser(os.environ.get("LAB_CACHE", "~/.cache/ripples-lab"))
QCEW = "https://data.bls.gov/cew/data/files/{y}/csv/{y}_qtrly_by_industry.zip"
FEMA = ("https://www.fema.gov/api/open/v2/DisasterDeclarationsSummaries?$filter=declarationType%20eq%20%27DR%27"
        "&$select=disasterNumber,fipsStateCode,fipsCountyCode,incidentType,incidentBeginDate&$top=10000&$skip={skip}")
SERIES = ["10", "1011", "1012", "1013", "1021", "1022", "1023", "1024", "1025", "1026", "1027"]
AGG = {s: ("71" if s == "10" else "73") for s in SERIES}


class Stop(Exception):
    pass


def fetch(url: str, dest: str | None = None, timeout: int = 300):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            if dest is None:
                return r.read()
            with open(dest, "wb") as f:
                shutil.copyfileobj(r, f, 1 << 20)
    except urllib.error.HTTPError as e:
        if e.code in (403, 429, 503):
            raise Stop(f"HTTP {e.code} from {url.split('?')[0]}") from None
        raise


def build_fema() -> list[dict]:
    path = os.path.join(CACHE, "fema.json")
    if os.path.exists(path):
        return json.load(open(path))
    rows, skip = [], 0
    while True:
        j = json.loads(fetch(FEMA.format(skip=skip)))
        batch = j.get("DisasterDeclarationsSummaries") or []
        rows += batch
        if len(batch) < 10000:
            break
        skip += 10000
        time.sleep(1)
    json.dump(rows, open(path, "w"))
    return rows


def build_panel(y0: int = 2001, y1: int = 2025) -> dict:
    path = os.path.join(CACHE, "panel.npz")
    if os.path.exists(path):
        z = np.load(path, allow_pickle=False)
        return {k: z[k] for k in z.files}
    data: dict[tuple[str, str, int], float] = {}
    counties: set[str] = set()
    years = []
    tmp = tempfile.mkdtemp()
    for y in range(y0, y1 + 1):
        zp = os.path.join(tmp, f"{y}.zip")
        try:
            fetch(QCEW.format(y=y), zp)
        except urllib.error.HTTPError as e:
            print(f"qcew {y}: HTTP {e.code}, skipped", flush=True)
            continue
        years.append(y)
        n = 0
        with zipfile.ZipFile(zp) as z:
            for name in z.namelist():
                m = re.search(r"q1-q4 (\d+) ", os.path.basename(name))
                if not m or m.group(1) not in AGG:
                    continue
                s = m.group(1)
                with z.open(name) as fh:
                    for r in csv.DictReader(io.TextIOWrapper(fh, encoding="utf-8", errors="replace")):
                        a = (r.get("area_fips") or "").strip()
                        if (r.get("own_code") or "").strip() != "5" or (r.get("agglvl_code") or "").strip() != AGG[s]:
                            continue
                        if not re.fullmatch(r"\d{5}", a) or a.endswith("000") or (r.get("disclosure_code") or "").strip() == "N":
                            continue
                        vals = [(r.get(f"month{k}_emplvl") or "").strip() for k in (1, 2, 3)]
                        vals = [float(v) for v in vals if v.isdigit()]
                        if len(vals) == 3 and min(vals) > 0:
                            data[(s, a, y * 10 + int(r["qtr"]))] = sum(vals) / 3
                            counties.add(a)
                            n += 1
        os.remove(zp)
        print(f"qcew {y}: {n} county-quarter-series values", flush=True)
    shutil.rmtree(tmp, ignore_errors=True)
    cl = sorted(counties)
    ql = [y * 10 + q for y in years for q in (1, 2, 3, 4)]
    ci = {c: i for i, c in enumerate(cl)}
    qi = {q: i for i, q in enumerate(ql)}
    emp = np.full((len(SERIES), len(cl), len(ql)), np.nan, dtype=np.float32)
    si = {s: i for i, s in enumerate(SERIES)}
    for (s, a, q), v in data.items():
        emp[si[s], ci[a], qi[q]] = v
    out = {"counties": np.array(cl), "quarters": np.array(ql), "series": np.array(SERIES), "emp": emp}
    np.savez_compressed(path, **out)
    return out


if __name__ == "__main__":
    os.makedirs(CACHE, exist_ok=True)
    try:
        f = build_fema()
        print(f"fema: {len(f)} DR county rows", flush=True)
        p = build_panel()
        print(f"panel: {p['emp'].shape}, finite share {np.isfinite(p['emp']).mean():.3f}", flush=True)
    except Stop as e:
        print(f"stopped: {e}", flush=True)
        sys.exit(2)
