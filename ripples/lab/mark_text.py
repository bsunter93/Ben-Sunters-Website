"""Mark-text search v1.2 (ripples/docs/mark_text_v1_2.md): cultural works named inside legal and parliamentary text.

v1.2 (Oct 3, after v1.1): named works are read through every Hansard page (up to 1,000 contributions); named markers that
are also ordinary words need a work-context word within 160 characters; bill stages (second reading, committee, report,
third reading) are their own tier.

v1.1 (Oct 3, after v1's 26-minute run): named-work markers resolve as the title themselves; Hansard reads the newest and
the oldest 100 contributions per phrase; legislation.gov.uk notes are fetched from real document paths (UK enactments
only) and dated by the path's year.

The mark-first search reads Wikipedia's articles about laws. This one reads the records themselves, keyless:
  FR   the Federal Register (rules, proposed rules, notices): full-text search for marker phrases, context from excerpts
       and, for the strongest hits, the document's raw text.
  UKL  legislation.gov.uk: the Atom search feed for marker phrases over legislation and explanatory notes.
  HAN  the UK Parliament Hansard API: spoken contributions that use a marker phrase; the debate's bill or act is the mark.
  GOV  GovInfo (bills, public laws, the Congressional Record): only when DATA_GOV_KEY is set (free key from api.data.gov).
For every hit: the marker phrase, the title it introduces (regex), the work resolved on Wikipedia/Wikidata (class and
date), the record's date, the order, and the causal words around it. Honest UA, 1 s between requests, stop on refusal,
saves as it goes. Explore stage: nothing here is shown as measured.
"""
from __future__ import annotations

import datetime as dt
import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import mark_first as mf  # noqa: E402  (shared helpers: get, sparql, budget, Stop, WP, strip_markup)

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.environ.get("OUT_JSON") or os.path.join(ROOT, "docs", "results", "mark_text_v1_2.json")
PROTOCOL = "ripples/docs/mark_text_v1_2.md"
KEY = os.environ.get("DATA_GOV_KEY", "").strip()
FR = "https://www.federalregister.gov/api/v1/documents.json"
UKL = "https://www.legislation.gov.uk"
HAN = "https://hansard-api.parliament.uk"
GOV = "https://api.govinfo.gov"

# marker phrases, fixed before the run: a record that names a work usually introduces it with one of these
MARKERS = ["Netflix", "HBO", "ITV drama", "BBC drama", "television drama", "television series", "TV series", "docuseries",
           "documentary film", "the documentary", "miniseries", "motion picture", "feature film", "the novel", "best-selling book",
           "bestselling book", "video game", "viral video", "social media challenge", "TikTok", "podcast", "60 Minutes", "Dateline",
           "Panorama programme", "Dispatches programme", "Channel 4 documentary", "reality television", "Super Size Me", "Blackfish",
           "Tiger King", "Mr Bates", "The Jungle", "Silent Spring", "Unsafe at Any Speed", "WarGames", "Cathy Come Home",
           "Thirteen Reasons Why", "13 Reasons Why", "Squid Game", "Stranger Things", "Baby Reindeer", "Adolescence"]
# markers that are themselves a work: the marker resolves as the title (v1 missed Mr Bates for want of a quote mark)
NAMED = {"Super Size Me": "Super Size Me", "Blackfish": "Blackfish (film)", "Tiger King": "Tiger King", "Mr Bates": "Mr Bates vs The Post Office",
         "The Jungle": "The Jungle", "Silent Spring": "Silent Spring", "Unsafe at Any Speed": "Unsafe at Any Speed", "WarGames": "WarGames",
         "Cathy Come Home": "Cathy Come Home", "Thirteen Reasons Why": "13 Reasons Why", "13 Reasons Why": "13 Reasons Why",
         "Squid Game": "Squid Game", "Stranger Things": "Stranger Things", "Baby Reindeer": "Baby Reindeer", "Adolescence": "Adolescence (TV series)"}
# named markers that are also ordinary words need a work-context word nearby (v1.1 matched the fish, the Calais camp, an idiom)
AMBIGUOUS = {"Blackfish", "The Jungle", "Adolescence", "Stranger Things", "Mr Bates", "Tiger King", "Squid Game", "Baby Reindeer", "WarGames"}
WORK_CTX = re.compile(r"\b(drama|series|film|documentary|programme|program|show|Netflix|ITV|BBC|Channel 4|HBO|book|novel|broadcast|episode|"
                      r"aired|watched|viewers|screen|television|TV|docuseries|streaming|Upton Sinclair|SeaWorld|orca|Post Office|Horizon|"
                      r"Richard Gadd|Jack Thorne|Stephen Graham|Joe Exotic|Hollywood|Matthew Broderick)\b", re.I)
# the title a marker introduces
TITLE_RX = [
    re.compile(r"(?:series|drama|documentary|docuseries|film|movie|novel|book|miniseries|podcast|game|programme|program|show)\s+"
               r"(?:called|titled|entitled|named)?\s*[\"“‘']([^\"”’']{2,80})[\"”’']", re.I),
    re.compile(r"[\"“]([A-Z][^\"”]{2,70})[\"”],?\s+(?:a|an|the)\s+(?:Netflix|HBO|ITV|BBC|Channel 4|Hulu|Amazon|Disney|television|TV|"
               r"documentary|feature|film|novel|book|video game|podcast)", re.I),
    re.compile(r"(?:Netflix|HBO|ITV|BBC|Channel 4|Hulu|Amazon Prime|Disney\+|Apple TV\+)(?:'s)?\s+(?:original\s+)?(?:series|drama|documentary|"
               r"docuseries|show|film|miniseries)\s+[\"“‘']?([A-Z][\w' :&!?.-]{2,60}?)[\"”’']?(?=[,.;:)]|\s+(?:which|that|about|has|had|was|is|and)\b)"),
    re.compile(r"(?:the|a)\s+(?:\d{4}\s+)?(?:film|movie|documentary|novel|book|television series|TV series|miniseries|docuseries|video game|podcast)"
               r"\s+[\"“‘']?([A-Z][\w' :&!?.-]{2,60}?)[\"”’']?(?=[,.;:)]|\s+(?:which|that|about|by|has|had|was|is|and|depict|portray|tells|follows)\b)"),
]
CAUSAL = mf.CAUSAL
WORK_WORDS = re.compile(r"film|series|book|novel|documentary|game|podcast|programme|program|miniseries|work|play|song|album|episode|written work|"
                        r"literary|television|animated|short|web", re.I)

state = {}


def save():
    tmp = OUT + ".tmp"
    json.dump(state, open(tmp, "w"), ensure_ascii=False)
    os.replace(tmp, OUT)


def titles_in(text):
    out = []
    for rx in TITLE_RX:
        for m in rx.finditer(text):
            t = re.sub(r"\s+", " ", m.group(1)).strip(" .,;:'\"“”‘’")
            if 2 < len(t) <= 80 and not re.fullmatch(r"(?:the|a|an|this|that|which|these|those)\b.*", t, re.I):
                out.append(t)
    seen, uniq = set(), []
    for t in out:
        if t.lower() not in seen:
            seen.add(t.lower()); uniq.append(t)
    return uniq[:6]


def window(text, needle, span=320):
    i = text.lower().find(needle.lower())
    if i < 0:
        return text[:2 * span]
    return text[max(0, i - span): i + len(needle) + span]


# ---------- resolving a title to a work ----------
def resolve(title):
    """Wikipedia search -> Wikidata item -> P31 classes and earliest date. Cached in state['works']."""
    cache = state.setdefault("works", {})
    if title in cache:
        return cache[title]
    params = {"action": "query", "list": "search", "srsearch": title, "srlimit": 3, "format": "json"}
    body = mf.get(f"{mf.WP}?{urllib.parse.urlencode(params)}")
    res = None
    try:
        hits = json.loads(body)["query"]["search"]
    except (ValueError, KeyError, TypeError):
        hits = []
    for h in hits[:2]:
        pt = h["title"]
        params = {"action": "query", "prop": "pageprops", "ppprop": "wikibase_item", "titles": pt, "redirects": 1, "format": "json"}
        body = mf.get(f"{mf.WP}?{urllib.parse.urlencode(params)}")
        try:
            pg = next(iter(json.loads(body)["query"]["pages"].values()))
            q = pg["pageprops"]["wikibase_item"]
        except (ValueError, KeyError, TypeError, StopIteration):
            continue
        rows = mf.sparql(f"""SELECT ?cLabel (MIN(?d) AS ?d0) WHERE {{ wd:{q} wdt:P31 ?c . OPTIONAL {{ wd:{q} wdt:P577|wdt:P580|wdt:P571 ?d }}
                              SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en" . }} }} GROUP BY ?cLabel""")
        if not rows:
            continue
        classes = [b["cLabel"]["value"] for b in rows]
        if not any(WORK_WORDS.search(c) for c in classes):
            continue
        d0 = next((b["d0"]["value"][:10] for b in rows if b.get("d0", {}).get("value")), None)
        res = {"title": pt, "q": q, "classes": classes[:4], "date": d0}
        break
    cache[title] = res
    return res


def record(source, mark, mark_date, url, text, marker, tier):
    """One document hit -> zero or more (work, mark) pairs."""
    pairs = state.setdefault("pairs", [])
    ctx = window(text, marker)
    if marker.lower() not in ctx.lower():
        return
    if marker in AMBIGUOUS and not WORK_CTX.search(window(text, marker, 160)):
        return  # the word, not the work
    found = titles_in(ctx)
    if marker in NAMED and not any(NAMED[marker].split(" (")[0].lower() in t.lower() for t in found):
        found = [NAMED[marker]] + found
    for t in found:
        if t.lower() in mark.lower():
            continue
        w = resolve(t)
        if not w:
            continue
        lag = None
        if w["date"] and mark_date:
            try:
                lag = (dt.date.fromisoformat(mark_date[:10]) - dt.date.fromisoformat(w["date"])).days
            except ValueError:
                lag = None
        sent = re.sub(r"\s+", " ", ctx).strip()
        pairs.append({"source": source, "tier": tier, "mark": mark, "mark_date": mark_date, "url": url, "marker": marker, "title_text": t,
                      "work": w["title"], "work_q": w["q"], "work_classes": w["classes"], "work_date": w["date"], "lag_days": lag,
                      "ordered": lag is not None and lag >= 0, "causal_score": len(CAUSAL.findall(sent)), "sentence": sent[:600]})
        print(f"  pair [{source}] {w['title']} ({w['date']}) -> {mark} ({mark_date}) lag {lag} causal {len(CAUSAL.findall(sent))}", flush=True)


# ---------- sources ----------
def federal_register():
    done = state.setdefault("fr_done", [])
    for term in MARKERS:
        if term in done:
            continue
        params = {"conditions[term]": f'"{term}"', "per_page": 100, "order": "oldest",
                  "fields[]": ["title", "publication_date", "type", "html_url", "document_number", "excerpts", "raw_text_url"]}
        body = mf.get(f"{FR}?{urllib.parse.urlencode(params, doseq=True)}")
        try:
            d = json.loads(body)
        except (ValueError, TypeError):
            done.append(term); continue
        docs = d.get("results", [])
        print("FR", term, d.get("count"), "docs", len(docs), flush=True)
        deep = 0
        for x in docs:
            ex = mf.strip_markup(html.unescape(re.sub(r"<[^>]+>", " ", x.get("excerpts") or "")))
            text = ex
            if deep < 12 and x.get("raw_text_url") and re.search(r"Netflix|HBO|ITV|BBC|documentary|series|film|novel", ex, re.I):
                raw = mf.get(x["raw_text_url"])
                if raw:
                    text = window(raw, term, 600); deep += 1
            record("FR", x.get("title") or x.get("document_number"), x.get("publication_date"), x.get("html_url"), text, term,
                   "rule" if (x.get("type") or "").lower() in ("rule", "proposed rule") else "notice")
        done.append(term); save()


def uk_legislation():
    done = state.setdefault("ukl_done", [])
    for term in MARKERS:
        if term in done:
            continue
        hits = []
        for path in (f"/all/data.feed?text={urllib.parse.quote(term)}", f"/search/data.feed?text={urllib.parse.quote(term)}"):
            body = mf.get(UKL + path, headers={"Accept": "application/atom+xml"})
            if body and "<entry" in body:
                for e in re.findall(r"<entry>(.*?)</entry>", body, re.S):
                    title = html.unescape(re.sub(r"<[^>]+>", "", re.search(r"<title[^>]*>(.*?)</title>", e, re.S).group(1))) if re.search(r"<title[^>]*>", e) else ""
                    link = re.search(r'<link[^>]*rel="self"[^>]*href="([^"]+)"', e) or re.search(r'<id>(.*?)</id>', e)
                    upd = re.search(r"<(?:published|updated)>(\d{4}-\d{2}-\d{2})", e)
                    hits.append({"title": title, "url": link.group(1) if link else None, "date": upd.group(1) if upd else None})
                break
        print("UKL", term, len(hits), flush=True)
        state.setdefault("ukl_hits", {})[term] = hits[:50]
        # the explanatory notes carry the "why"; fetch the notes text for up to 8 items per term
        for h in hits[:12]:
            if not h["url"]:
                continue
            m = re.search(r"legislation\.gov\.uk/(?:id/)?((?:ukpga|uksi|asp|ssi|anaw|wsi|nia|nisr|ukla|ukcm)/(\d{4})/\d+)", h["url"])
            if not m:
                continue  # EU retained law and the like: not a UK enactment
            base, year = f"{UKL}/{m.group(1)}", m.group(2)
            notes = mf.get(base + "/notes/data.xht") or mf.get(base + "/notes/contents/data.xht") or mf.get(base + "/data.xht")
            if not notes:
                continue
            text = mf.strip_markup(html.unescape(re.sub(r"<[^>]+>", " ", notes)))
            if term.lower() in text.lower():
                record("UKL", h["title"], f"{year}-07-01", base, text, term, "law")
        done.append(term); save()


def hansard():
    done = state.setdefault("han_done", [])
    for term in MARKERS:
        if term in done:
            continue
        rows, total = [], None
        # named works: every page (up to 1,000 contributions); generic phrases: the newest 100 and the oldest 100
        plan = [("SittingDateDesc", skip) for skip in range(0, 1000, 100)] if term in NAMED else [("SittingDateDesc", 0), ("SittingDateAsc", 0)]
        for order, skip in plan:
            if total is not None and skip >= total:
                break
            q = urllib.parse.urlencode({"queryParameters.searchTerm": f'"{term}"', "queryParameters.take": 100, "queryParameters.skip": skip,
                                        "queryParameters.orderBy": order})
            body = mf.get(f"{HAN}/search/contributions/Spoken.json?{q}")
            try:
                d = json.loads(body)
                total = d.get("TotalResultCount", total)
                rows += d.get("Results") or d.get("results") or []
            except (ValueError, TypeError):
                print("HAN no json for", term, (body or "")[:120].replace("\n", " "), flush=True)
            if total is not None and total <= 100 and term not in NAMED:
                break
        seen = set(); rows = [r for r in rows if not (r.get("ContributionExtId") in seen or seen.add(r.get("ContributionExtId")))]
        state.setdefault("han_counts", {})[term] = total
        print("HAN", term, total, "total;", len(rows), "read", flush=True)
        for r in rows:
            text = mf.strip_markup(html.unescape(re.sub(r"<[^>]+>", " ", r.get("ContributionText") or r.get("ContributionTextFull") or "")))
            section = r.get("DebateSection") or r.get("DebateSectionTitle") or ""
            date = (r.get("SittingDate") or "")[:10]
            url = f"https://hansard.parliament.uk/search/Contributions?searchTerm={urllib.parse.quote(term)}"
            if r.get("DebateSectionExtId"):
                url = f"https://hansard.parliament.uk/debates/{r['DebateSectionExtId']}"
            tier = "bill debate" if re.search(r"\bBill\b|Regulations|\bOrder\b", section) else "act debate" if re.search(r"\bAct\b", section) else "debate"
            if tier == "bill debate" and re.search(r"Second Reading|Committee|Report Stage|Third Reading", section or "", re.I):
                tier = "bill stage"
            record("HAN", section or "Hansard contribution", date, url, text, term, tier)
        done.append(term); save()


def govinfo():
    if not KEY:
        state["govinfo"] = "skipped: DATA_GOV_KEY not set"
        print("GOV skipped: no DATA_GOV_KEY", flush=True)
        return
    done = state.setdefault("gov_done", [])
    for term in MARKERS:
        if term in done:
            continue
        payload = json.dumps({"query": f'"{term}" collection:(PLAW OR BILLS OR CREC OR CHRG)', "pageSize": 50, "offsetMark": "*",
                              "sorts": [{"field": "publishdate", "sortOrder": "ASC"}]}).encode()
        req = urllib.request.Request(f"{GOV}/search?api_key={KEY}", data=payload, headers={"User-Agent": mf.UA, "Content-Type": "application/json"})
        mf.budget()
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                d = json.loads(r.read().decode("utf-8", "replace"))
        except Exception as e:  # noqa: BLE001
            print("GOV error", term, str(e)[:100], flush=True); done.append(term); continue
        finally:
            mf.time.sleep(1.0)
        res = d.get("results", [])
        print("GOV", term, d.get("count"), flush=True)
        for x in res[:20]:
            link = x.get("download", {}).get("txtLink") or x.get("resultLink")
            text = ""
            if link and "txtLink" in json.dumps(x.get("download", {})):
                body = mf.get(link + ("&" if "?" in link else "?") + f"api_key={KEY}")
                text = window(re.sub(r"<[^>]+>", " ", body or ""), term, 600)
            record("GOV", x.get("title") or x.get("packageId"), x.get("dateIssued"), x.get("resultLink"), text or (x.get("title") or ""), term,
                   "law" if (x.get("packageId") or "").startswith("PLAW") else "bill" if (x.get("packageId") or "").startswith("BILLS") else "record")
        done.append(term); save()


def probe():
    """Log what each endpoint returns, so a failed source can be read from the job log."""
    tests = [("FR", f"{FR}?conditions[term]=%22Netflix%22&per_page=1"), ("UKL", f"{UKL}/all/data.feed?text=Netflix"),
             ("HAN", f"{HAN}/search/contributions/Spoken.json?queryParameters.searchTerm=Netflix&queryParameters.take=1")]
    for name, url in tests:
        body = mf.get(url)
        print(f"probe {name}: {'none' if body is None else len(body)} bytes: {(body or '')[:200]!r}", flush=True)


def main() -> int:
    global state
    state = json.load(open(OUT)) if os.path.exists(OUT) else {"protocol": PROTOCOL, "started": dt.date.today().isoformat(), "markers": MARKERS}
    state.pop("stopped", None)
    try:
        if "probed" not in state:
            probe(); state["probed"] = True
        hansard()
        uk_legislation()
        federal_register()
        govinfo()
    except mf.Stop as e:
        state["stopped"] = str(e); print("stopped:", e, flush=True)
    pairs = state.get("pairs", [])
    good = [p for p in pairs if p["ordered"] and p["tier"] in ("law", "rule", "bill", "bill debate", "bill stage")]
    good.sort(key=lambda p: (-p["causal_score"], p["lag_days"] or 0))
    state["summary"] = {"pairs": len(pairs), "ordered": sum(1 for p in pairs if p["ordered"]), "good": len(good),
                        "by_source": {s: sum(1 for p in pairs if p["source"] == s) for s in ("HAN", "UKL", "FR", "GOV")}, "top": good[:80]}
    save()
    print(json.dumps({k: v for k, v in state["summary"].items() if k != "top"}, indent=1))
    for p in good[:40]:
        print(f"  [{p['source']}/{p['tier']}] {p['work_date']} {p['work']} -> {p['mark_date']} {p['mark'][:80]} causal {p['causal_score']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
