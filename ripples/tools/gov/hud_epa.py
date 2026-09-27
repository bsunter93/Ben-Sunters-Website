"""Ripple Map: HUD Fair Market Rents and EPA daily AQI by county, fetched from GitHub Actions.

Both hosts refuse requests from the Supabase network (huduser.gov answers 400 to everything, aqs.epa.gov times out in
the TLS handshake), so this job runs on a GitHub runner and writes through public.att_ingest like the BigQuery jobs.

  epa.aqi  EPA AirData "daily AQI by county" annual files (keyless, public domain), reduced to weekly (week ending
           Saturday) max and mean AQI per county: geo US-CTY-<fips>, metrics aqi_max / aqi_mean. The AQS API key is used
           once per run to confirm the key works (list/states); the bulk files do not need it.
  hud.fmr  HUD USER Fair Market Rents API (Bearer token): 2-bedroom FMR per county per fiscal year, day = FY start
           (Oct 1 of the prior year): geo US-CTY-<fips>, metric fmr_2br.

Rules: honest UA, stop on 403/429/503 (no retry that run), per-run row cap, 1,000 rows per att_ingest call with a pause
between calls (the database has a disk-IO burst budget), stop on the database size cap. Keys come from the environment
(GitHub secrets) and are never logged.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
import zipfile
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bq"))
from common import Supabase, log, summary  # noqa: E402

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
STATES = ["AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA",
          "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR",
          "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "PR"]


class Stop(Exception):
    pass


def get(url: str, headers: dict | None = None, timeout: int = 120) -> bytes:
    h = {"User-Agent": UA, "Accept": "*/*"}
    h.update(headers or {})
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        if e.code in (403, 429, 503):
            raise Stop(f"HTTP {e.code} from {url.split('?')[0]}") from None
        raise


def week_end_sat(d: dt.date) -> dt.date:
    return d + dt.timedelta(days=(5 - d.weekday()) % 7)


class Writer:
    def __init__(self, sb: Supabase, cap: int, dry: bool):
        self.sb, self.cap, self.dry = sb, cap, dry
        self.written = 0
        self.rejected = 0
        self.stop_reason = None

    def put(self, rows: list[dict]) -> bool:
        for i in range(0, len(rows), 1000):
            if self.written >= self.cap:
                self.stop_reason = "row cap"
                return False
            chunk = rows[i:i + 1000]
            if self.dry:
                self.written += len(chunk)
                continue
            res = self.sb.rpc("att_ingest", {"p_rows": chunk}) or {}
            self.written += int(res.get("rows") or 0)
            rej = res.get("rejected") or []
            self.rejected += len(rej)
            if any(x.get("reason") == "db_size_cap" for x in rej):
                self.stop_reason = "db_size_cap"
                return False
            time.sleep(0.7)   # stay well under the disk-IO burst budget
        return True


def epa(years: list[int], w: Writer) -> dict:
    out = {"key_check": None, "years": {}}
    key, email = os.environ.get("EPA_AQS_KEY", ""), os.environ.get("EPA_AQS_EMAIL", "")
    if key and email:
        try:
            j = json.loads(get(f"https://aqs.epa.gov/data/api/list/states?email={email}&key={key}", timeout=60))
            out["key_check"] = (j.get("Header") or [{}])[0].get("status", "unknown")
        except Stop as e:
            out["key_check"] = f"stopped: {e}"
        except Exception as e:  # noqa: BLE001
            out["key_check"] = f"failed: {type(e).__name__}"
    for y in years:
        try:
            raw = get(f"https://aqs.epa.gov/aqsweb/airdata/daily_aqi_by_county_{y}.zip", timeout=300)
        except Stop as e:
            out["years"][y] = f"stopped: {e}"
            break
        except urllib.error.HTTPError as e:
            out["years"][y] = f"HTTP {e.code}"
            continue
        zf = zipfile.ZipFile(io.BytesIO(raw))
        name = zf.namelist()[0]
        agg = defaultdict(list)
        with zf.open(name) as fh:
            for r in csv.DictReader(io.TextIOWrapper(fh, encoding="utf-8", errors="replace")):
                try:
                    fips = f"{int(r['State Code']):02d}{int(r['County Code']):03d}"
                    d = dt.date.fromisoformat(r["Date"])
                    aqi = float(r["AQI"])
                except (KeyError, ValueError):
                    continue
                agg[(fips, week_end_sat(d))].append(aqi)
        rows = []
        for (fips, wk), v in sorted(agg.items()):
            for m, val in (("aqi_max", max(v)), ("aqi_mean", round(sum(v) / len(v), 2))):
                rows.append({"source": "epa.aqi", "metric": m, "geo": f"US-CTY-{fips}", "key": fips, "day": wk.isoformat(),
                             "value": val, "meta": {"weekly": True, "days": len(v), "via": "gha"}})
        ok = w.put(rows)
        out["years"][y] = f"{len(rows)} weekly rows"
        log(f"epa {y}: {len(rows)} rows; written so far {w.written}")
        if not ok:
            break
    return out


def hud(years: list[int], w: Writer) -> dict:
    out = {"years": {}}
    tok = os.environ.get("HUD_USER_TOKEN", "")
    if not tok:
        return {"skipped": "no HUD_USER_TOKEN"}
    auth = {"Authorization": "Bearer " + tok, "Accept": "application/json"}
    for y in years:
        rows, errs = [], 0
        for st in STATES:
            try:
                j = json.loads(get(f"https://www.huduser.gov/hudapi/public/fmr/statedata/{st}?year={y}", auth, timeout=60))
            except Stop as e:
                out["years"][y] = f"stopped: {e}"
                w.put(rows)
                return out
            except urllib.error.HTTPError as e:
                errs += 1
                if e.code in (400, 401):
                    out["years"][y] = f"HTTP {e.code} (token or request rejected)"
                    return out
                continue
            for c in (j.get("data") or {}).get("counties") or []:
                fips = str(c.get("fips_code") or "")[:5]
                v = c.get("Two-Bedroom")
                if len(fips) == 5 and fips.isdigit() and isinstance(v, (int, float)):
                    rows.append({"source": "hud.fmr", "metric": "fmr_2br", "geo": f"US-CTY-{fips}", "key": fips,
                                 "day": f"{y - 1}-10-01", "value": v, "meta": {"fy": y, "via": "gha"}})
            time.sleep(0.3)
        # one row per county per year (metro counties can repeat across areas: keep the first)
        seen, uniq = set(), []
        for r in rows:
            if r["key"] not in seen:
                seen.add(r["key"]); uniq.append(r)
        ok = w.put(uniq)
        out["years"][y] = f"{len(uniq)} counties, {errs} state errors"
        log(f"hud {y}: {len(uniq)} rows; written so far {w.written}")
        if not ok:
            break
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--what", default="both", choices=["both", "epa", "hud"])
    ap.add_argument("--epa-from", type=int, default=2010)
    ap.add_argument("--epa-to", type=int, default=dt.date.today().year - 1)
    ap.add_argument("--hud-from", type=int, default=2017)
    ap.add_argument("--hud-to", type=int, default=dt.date.today().year + (1 if dt.date.today().month >= 10 else 0))
    ap.add_argument("--max-rows", type=int, default=250000)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    w = Writer(Supabase(), a.max_rows, a.dry_run)
    res = {}
    try:
        if a.what in ("both", "hud"):
            res["hud"] = hud(list(range(a.hud_from, a.hud_to + 1)), w)
        if a.what in ("both", "epa") and w.stop_reason is None:
            res["epa"] = epa(list(range(a.epa_from, a.epa_to + 1)), w)
    finally:
        res.update({"written": w.written, "rejected": w.rejected, "stop": w.stop_reason, "dry_run": a.dry_run})
        log(json.dumps(res, indent=1, default=str))
        summary("### HUD / EPA\n```\n" + json.dumps(res, indent=1, default=str) + "\n```")
    return 0


if __name__ == "__main__":
    sys.exit(main())
