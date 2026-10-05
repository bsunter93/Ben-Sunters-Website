"""The dating step of screen v2 (docs/screen_plan_v2.md): resolve each undated mark's year from its own record.

Reads docs/results/screen_dating_inputs_v2.json (the record titles, fixed before any lookup) and writes
docs/results/screen_dating_v2.json with the source of every date. The date is the first year in the record's title, or
the first year in an enactment or founding field of its infobox (or a taxon's authority year); there is no fallback to
the lead. A redirect to a page that shares no word of four or more letters with the named title counts as a different
subject. Honest user agent, at most one request a second, and a stop on any 403, 429 or 5xx. Run from
ripples/docs/results:

    python3 ../../lab/discovery/screen_date.py
"""
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
API = "https://en.wikipedia.org/w/api.php"
YEAR = r"(1[6-9]\d\d|20\d\d)"
FIELDS = (r"enacted|date_enacted|date_signed|signed|royal_assent|date_of_royal_assent|ratified|date_ratified|adopted|"
          r"date_adopted|formed|founded|foundation|established|date_established|effective|date_effective|date_passed|passed|"
          r"formation|date_formed|inception|start_date|created|date_created|opened|date_opened|"
          r"authority|binomial_authority|genus_authority|signed_date|date_drafted|date_effective")
GENERIC = {"united", "states", "national", "federal", "department", "office", "the", "and", "act", "foundation", "commission", "report"}
_last = [0.0]


def get(params):
    wait = 1.0 - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    url = API + "?" + urllib.parse.urlencode({**params, "format": "json"})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            _last[0] = time.time()
            return json.load(r)
    except urllib.error.HTTPError as e:
        _last[0] = time.time()
        if e.code in (403, 429) or e.code >= 500:
            print(f"STOP: HTTP {e.code}; no retry today", file=sys.stderr)
            sys.exit(2)
        return {"error": {"code": str(e.code)}}


def words(t):
    return {w.lower() for w in re.findall(r"[A-Za-z][A-Za-z\-']{3,}", t)} - GENERIC


def resolve(title):
    rec = {"requested": title, "page": None, "year": None, "how": None, "field": None, "note": None}
    m = re.search(r"\b" + YEAR + r"\b", title)
    d = get({"action": "parse", "page": title, "prop": "wikitext", "section": 0, "redirects": 1})
    if "error" in d:
        rec["note"] = "no such page"
        return rec
    page = d["parse"]["title"]
    rec["page"] = page
    if page != title and not (words(page) & words(title)):
        rec["note"] = f"redirects to a different subject ({page})"
        return rec
    if m:
        rec.update(year=int(m.group(1)), how="title", field=title)
        return rec
    t2 = re.search(r"\b" + YEAR + r"\b", page)
    if t2:
        rec.update(year=int(t2.group(1)), how="title", field=page)
        return rec
    wt = d["parse"]["wikitext"]["*"]
    f = re.search(r"\|\s*(" + FIELDS + r")\s*=\s*([^\n]*?)\b" + YEAR + r"\b", wt, re.I)
    if f:
        rec.update(year=int(f.group(3)), how="infobox", field=f.group(1).strip().lower())
        return rec
    rec["note"] = "no year in the title or an infobox field"
    return rec


def main():
    inputs = json.load(open("screen_dating_inputs_v2.json"))["records"]
    out = {}
    cache = {}
    for cid, v in inputs.items():
        if not v["record"]:
            out[cid] = {"requested": None, "page": None, "year": None, "how": "null record", "field": None, "note": v["why_null"]}
            continue
        if v["record"] not in cache:
            cache[v["record"]] = resolve(v["record"])
            r = cache[v["record"]]
            print(f"{cid:6s} {v['record'][:60]:60s} -> {r['page']} | {r['year']} ({r['how']} {r['field'] or ''}) {r['note'] or ''}")
        out[cid] = cache[v["record"]]
    json.dump({"_about": "Dating step of screen v2: the year of each undated mark from its own record, with its source. "
                         "Lookups by lab/discovery/screen_date.py under the honest user agent, one request a second.",
               "requests": len(cache), "dates": out}, open("screen_dating_v2.json", "w"), ensure_ascii=False, indent=1)
    print("requests", len(cache), "| resolved", sum(1 for r in cache.values() if r["year"]))


if __name__ == "__main__":
    main()
