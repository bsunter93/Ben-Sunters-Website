"""GDELT DOC 2.0 news-attention timelines for the cultural catalog (direction D-26; owner: story spikes as a proxy
for what is trending). For each catalog event since 2016-10 (public.att_cult_catalog), one request to the DOC API in
timelinevolraw mode: daily count of monitored news articles matching the title phrase, plus the day's total monitored
articles. Loaded through public.att_gdelt_load. Resumable (skips events already loaded).

Politeness: honest UA, one request every 6 s (GDELT asks for no more than one every 5 s), stop on 403/429/503.
Query: the title without a trailing parenthetical, quoted; single-word titles get a type word to cut ambiguity
(e.g. "Frozen" (film OR movie)). No personal data exists in this source.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bq"))
from common import Supabase, log, summary  # noqa: E402

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
API = "https://api.gdeltproject.org/api/v2/doc/doc"
TYPE_WORDS = {"film": "(film OR movie)", "tv": "(series OR show OR season)", "song": "(song OR single)",
              "album": "(album)", "game": "(game)", "book": "(book OR novel)"}


def query_for(e: dict) -> str | None:
    t = re.sub(r"\s*\([^)]*\)\s*$", "", e["title"] or "").strip().replace('"', "")
    if len(t) < 3:
        return None
    q = f'"{t}"'
    if len(t.split()) == 1 and e["typ"] in TYPE_WORDS:
        q += " " + TYPE_WORDS[e["typ"]]
    return q


def fetch(q: str, start: str, end: str) -> dict:
    params = {"query": q, "mode": "timelinevolraw", "format": "json", "startdatetime": start, "enddatetime": end}
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=90) as r:
        raw = r.read()
    return json.loads(raw) if raw.strip() else {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-events", type=int, default=400)
    ap.add_argument("--end", default="20251231235959")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    sb = Supabase()
    cat = sb.rpc("att_cult_catalog", {}) or []
    todo = [e for e in cat if not e.get("gdelt_done")][: a.max_events]
    res = {"catalog": len(cat), "todo": len(todo), "done": 0, "empty": 0, "skipped": 0, "rows": 0, "stop": None}
    for i, e in enumerate(todo):
        q = query_for(e)
        if not q:
            res["skipped"] += 1
            continue
        try:
            j = fetch(q, "20170101000000", a.end)
        except urllib.error.HTTPError as ex:
            if ex.code in (403, 429, 503):
                res["stop"] = f"HTTP {ex.code}"
                break
            log(f"{e['qid']}: HTTP {ex.code}")
            time.sleep(6)
            continue
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as ex:
            log(f"{e['qid']}: {type(ex).__name__}")
            time.sleep(6)
            continue
        series = {s.get("series"): s.get("data") or [] for s in (j.get("timeline") or [])}
        counts = series.get("Article Count") or (next(iter(series.values())) if series else [])
        rows = []
        for d in counts:
            day = str(d.get("date", ""))[:8]
            if len(day) == 8:
                rows.append({"qid": e["qid"], "day": f"{day[:4]}-{day[4:6]}-{day[6:]}", "a": int(d.get("value") or 0),
                             "t": str(d.get("norm") or "")})
        if not rows:
            res["empty"] += 1
            rows = [{"qid": e["qid"], "day": "2017-01-01", "a": 0, "t": ""}]  # marks the event as tried
        if not a.dry_run:
            for k in range(0, len(rows), 2000):
                res["rows"] += int((sb.rpc("att_gdelt_load", {"p_rows": rows[k:k + 2000]}) or {}).get("rows") or 0)
        res["done"] += 1
        if (i + 1) % 25 == 0:
            log(f"{i + 1}/{len(todo)} events, {res['rows']} rows")
        time.sleep(6)
    log(json.dumps(res))
    summary("### GDELT timelines\n```\n" + json.dumps(res, indent=1) + "\n```")
    return 0


if __name__ == "__main__":
    sys.exit(main())
