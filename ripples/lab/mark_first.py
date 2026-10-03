"""Mark-first search v1 (ripples/docs/mark_first_v1.md): from lasting marks upstream to the cultural events they cite.

Stage 0  Wikidata causal statements whose cause is a creative work (P828, P1478, P1479), and works with P1542.
Stage 1  Laws, acts, statutes, executive orders and regulations with an enwiki article (Wikidata) -> the creative works
         their articles link to (a works set built from Wikidata in year chunks) -> the sentence and section of the
         link -> causal-language score and date order.
Stage 2  Federal Register full-text probe: catalog events by name plus generic markers.
Anonymous, honest UA, 1 s between Wikipedia and Wikidata requests, 2 s between SPARQL queries, stop on 403/429/503.
Saves as it goes and resumes. Output: ripples/docs/results/mark_first_v1.json.
"""
from __future__ import annotations

import datetime as dt
import glob
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.environ.get("OUT_JSON") or os.path.join(ROOT, "docs", "results", "mark_first_v1.json")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
WP = "https://en.wikipedia.org/w/api.php"
SPARQL = "https://query.wikidata.org/sparql"
FR = "https://www.federalregister.gov/api/v1/documents.json"
BUDGET_MIN = float(os.environ.get("BUDGET_MIN", "200"))
MAX_MARKS = int(os.environ.get("MAX_MARKS", "16000"))
T0 = time.time()

# creative-work classes: (class, kind). Songs are left out (volume).
WORKS = {"Q11424": "film", "Q93204": "documentary", "Q506240": "TV film", "Q202866": "animated film", "Q5398426": "TV series",
         "Q1259759": "miniseries", "Q15416": "TV program", "Q526877": "web series", "Q581714": "animated series",
         "Q63952888": "anime series", "Q571": "book", "Q7725634": "book", "Q8261": "novel", "Q7889": "video game",
         "Q2927074": "internet meme", "Q24634210": "podcast"}
# mark classes queried directly, in addition to the classes found under "law"
MARK_CLASSES = {"Q476068": "Act of Congress", "Q4677783": "Act of Parliament (UK)", "Q820655": "statute", "Q7748": "law",
                "Q217310": "executive order", "Q49371": "legislation"}
CAUSAL = re.compile(r"\b(in response to|in the wake of|following|after|prompted|inspired|spurred|led to|as a result|because of|"
                    r"reaction to|motivated|sparked|catalyst|outcry|public pressure|named after|aftermath|triggered|in light of|"
                    r"drew attention|raised awareness|highlighted)\b", re.I)
CULTURE_SECTION = re.compile(r"popular culture|in media|in film|in fiction|legacy|see also|references|further reading|external links|"
                             r"adaptation|depiction|portrayal|cultural impact|reception|notes", re.I)
GENERIC_TERMS = ["Netflix series", "Netflix documentary", "HBO series", "viral video", "social media challenge", "TikTok challenge",
                 "Tiger King", "documentary film", "reality television", "video game", "Squid Game", "Stranger Things", "Blackfish",
                 "Super Size Me", "13 Reasons Why", "Mr Bates", "The Jungle Upton Sinclair", "Silent Spring", "WarGames"]


class Stop(Exception):
    pass


def budget():
    if (time.time() - T0) / 60 > BUDGET_MIN:
        raise Stop("time budget reached")


def get(url, headers=None, delay=1.0, timeout=90):
    budget()
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        if e.code in (403, 429, 503):
            raise Stop(f"HTTP {e.code} at {url[:80]}")
        print(f"HTTP {e.code} at {url[:100]}", flush=True)
        body = None
    except Exception as e:  # noqa: BLE001
        print(f"error at {url[:100]}: {str(e)[:80]}", flush=True)
        body = None
    finally:
        time.sleep(delay)
    return body


def sparql(q, delay=2.0):
    body = get(f"{SPARQL}?{urllib.parse.urlencode({'query': q, 'format': 'json'})}",
               headers={"Accept": "application/sparql-results+json"}, delay=delay, timeout=120)
    if not body:
        return None
    try:
        return json.loads(body)["results"]["bindings"]
    except (ValueError, KeyError):
        return None


def title_of(url):
    return urllib.parse.unquote(url.rsplit("/wiki/", 1)[-1]).replace("_", " ")


def qid(uri):
    return uri.rsplit("/", 1)[-1]


def year_chunks():
    out = [(1800, 1899)] + [(y, y + 9) for y in range(1900, 1950, 10)] + [(y, y + 4) for y in range(1950, 1990, 5)]
    return out + [(y, y) for y in range(1990, dt.date.today().year + 2)]


# ---------- Stage 0: Wikidata causal statements ----------
def stage0():
    vals = " ".join(f"wd:{q}" for q in WORKS)
    rows = []
    q1 = f"""SELECT ?effect ?effectLabel ?cause ?causeLabel ?prop ?d ?ea ?ca WHERE {{
      VALUES ?cls {{ {vals} }} ?cause wdt:P31 ?cls .
      ?effect ?prop ?cause . FILTER(?prop IN (wdt:P828, wdt:P1478, wdt:P1479))
      OPTIONAL {{ ?effect wdt:P577|wdt:P571|wdt:P585|wdt:P580 ?d }}
      OPTIONAL {{ ?ea schema:about ?effect ; schema:isPartOf <https://en.wikipedia.org/> }}
      OPTIONAL {{ ?ca schema:about ?cause ; schema:isPartOf <https://en.wikipedia.org/> }}
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en" . }} }} LIMIT 3000"""
    q2 = f"""SELECT ?effect ?effectLabel ?cause ?causeLabel ?prop ?d ?ea ?ca WHERE {{
      VALUES ?cls {{ {vals} }} ?cause wdt:P31 ?cls .
      ?cause ?prop ?effect . FILTER(?prop IN (wdt:P1542, wdt:P1536, wdt:P1537))
      OPTIONAL {{ ?effect wdt:P577|wdt:P571|wdt:P585|wdt:P580 ?d }}
      OPTIONAL {{ ?ea schema:about ?effect ; schema:isPartOf <https://en.wikipedia.org/> }}
      OPTIONAL {{ ?ca schema:about ?cause ; schema:isPartOf <https://en.wikipedia.org/> }}
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en" . }} }} LIMIT 3000"""
    for q in (q1, q2):
        for b in sparql(q) or []:
            rows.append({"cause": b["causeLabel"]["value"], "cause_q": qid(b["cause"]["value"]),
                         "effect": b["effectLabel"]["value"], "effect_q": qid(b["effect"]["value"]),
                         "prop": qid(b["prop"]["value"]), "effect_date": b.get("d", {}).get("value", "")[:10] or None,
                         "effect_article": title_of(b["ea"]["value"]) if "ea" in b else None,
                         "cause_article": title_of(b["ca"]["value"]) if "ca" in b else None})
    seen, out = set(), []
    for r in rows:
        k = (r["cause_q"], r["effect_q"])
        if k not in seen:
            seen.add(k)
            out.append(r)
    return out


# ---------- Stage 1a: the works set ----------
def works_set(state):
    works = state.setdefault("works", {})
    done = set(state.setdefault("works_chunks_done", []))
    vals = " ".join(f"wd:{q}" for q in WORKS)
    for y0, y1 in year_chunks():
        key = f"{y0}-{y1}"
        if key in done:
            continue
        q = f"""SELECT ?w ?cls ?d ?a WHERE {{ VALUES ?cls {{ {vals} }} ?w wdt:P31 ?cls . ?w wdt:P577|wdt:P580|wdt:P571 ?d .
                FILTER(YEAR(?d) >= {y0} && YEAR(?d) <= {y1}) ?a schema:about ?w ; schema:isPartOf <https://en.wikipedia.org/> . }}"""
        rows = sparql(q)
        if rows is None:
            print("works chunk failed", key, flush=True)
            continue
        for b in rows:
            t = title_of(b["a"]["value"])
            d = b["d"]["value"][:10]
            cur = works.get(t)
            if not cur or d < cur[1]:
                works[t] = [WORKS.get(qid(b["cls"]["value"]), "work"), d, qid(b["w"]["value"])]
        done.add(key)
        state["works_chunks_done"] = sorted(done)
        print("works", key, len(rows), "rows;", len(works), "titles", flush=True)
    return works


# ---------- Stage 1b: the marks ----------
def mark_classes():
    found = dict(MARK_CLASSES)
    q = """SELECT ?c ?cLabel (COUNT(?m) AS ?n) WHERE { ?c wdt:P279* wd:Q7748 . ?m wdt:P31 ?c .
           ?a schema:about ?m ; schema:isPartOf <https://en.wikipedia.org/> .
           SERVICE wikibase:label { bd:serviceParam wikibase:language "en" . } } GROUP BY ?c ?cLabel ORDER BY DESC(?n) LIMIT 80"""
    for b in sparql(q) or []:
        if int(b["n"]["value"]) >= 20:
            found[qid(b["c"]["value"])] = b["cLabel"]["value"]
    return found


def marks_set(state):
    marks = state.setdefault("marks", {})
    done = set(state.setdefault("mark_classes_done", []))
    classes = state.get("mark_classes") or mark_classes()
    state["mark_classes"] = classes
    for c, label in classes.items():
        if c in done:
            continue
        q = f"""SELECT ?m ?a ?d ?countryLabel WHERE {{ ?m wdt:P31 wd:{c} . ?a schema:about ?m ; schema:isPartOf <https://en.wikipedia.org/> .
                OPTIONAL {{ ?m wdt:P577|wdt:P571|wdt:P7588|wdt:P585|wdt:P580|wdt:P1619 ?d }} OPTIONAL {{ ?m wdt:P17 ?country }}
                SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en" . }} }} LIMIT 25000"""
        rows = sparql(q)
        if rows is None:
            print("marks class failed", c, label, flush=True)
            continue
        for b in rows:
            t = title_of(b["a"]["value"])
            d = b.get("d", {}).get("value", "")[:10] or None
            cur = marks.get(t)
            if not cur:
                marks[t] = {"q": qid(b["m"]["value"]), "class": label, "date": d, "country": b.get("countryLabel", {}).get("value")}
            elif d and (not cur["date"] or d < cur["date"]):
                cur["date"] = d
        done.add(c)
        state["mark_classes_done"] = sorted(done)
        print("marks", c, label, len(rows), "rows;", len(marks), "titles", flush=True)
    return marks


# ---------- Stage 1c: links from marks to works ----------
def links_for(titles):
    """All namespace-0 links of up to 50 articles, with continuation. Returns {title: [linked titles]}."""
    out = {t: [] for t in titles}
    cont = {}
    for _ in range(40):
        params = {"action": "query", "prop": "links", "plnamespace": 0, "pllimit": "max", "titles": "|".join(titles),
                  "format": "json", "redirects": 1, **cont}
        body = get(f"{WP}?{urllib.parse.urlencode(params)}")
        if not body:
            return out
        d = json.loads(body)
        for p in d.get("query", {}).get("pages", {}).values():
            t = p.get("title")
            if t in out:
                out[t] += [l["title"] for l in p.get("links", [])]
            else:  # redirected title: map back
                for r in d.get("query", {}).get("redirects", []):
                    if r.get("to") == t and r.get("from") in out:
                        out[r["from"]] += [l["title"] for l in p.get("links", [])]
        if "continue" not in d:
            return out
        cont = {"plcontinue": d["continue"]["plcontinue"], "continue": d["continue"]["continue"]}
    return out


def wikitext(title):
    params = {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main", "titles": title, "format": "json",
              "redirects": 1, "formatversion": 2}
    body = get(f"{WP}?{urllib.parse.urlencode(params)}")
    if not body:
        return ""
    try:
        return json.loads(body)["query"]["pages"][0]["revisions"][0]["slots"]["main"]["content"]
    except (KeyError, IndexError, ValueError):
        return ""


def strip_markup(s):
    s = re.sub(r"<ref[^>]*/>", "", s)
    s = re.sub(r"<ref[^>]*>.*?</ref>", "", s, flags=re.S)
    s = re.sub(r"\{\{[^{}]*\}\}", "", s)
    s = re.sub(r"\{\{[^{}]*\}\}", "", s)
    s = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", s)
    s = re.sub(r"'{2,}", "", s)
    s = re.sub(r"<[^>]+>", "", s)
    return html.unescape(re.sub(r"\s+", " ", s)).strip()


def context_of(text, work):
    """The section heading and the sentence of the first link to `work` in `text`, plus whether it is in the lead."""
    pat = re.compile(r"\[\[" + re.escape(work) + r"(?:\|[^\]]*)?\]\]", re.I)
    m = pat.search(text)
    if not m:
        # first letter case-insensitive, underscores
        m = re.search(r"\[\[" + re.escape(work[0]).lower() + re.escape(work[1:]) + r"(?:\|[^\]]*)?\]\]", text) if len(work) > 1 else None
    if not m:
        return None
    before = text[:m.start()]
    heads = re.findall(r"^==+\s*(.*?)\s*==+\s*$", before, flags=re.M)
    section = heads[-1] if heads else "lead"
    # sentence boundaries, generous
    start = max(before.rfind(". "), before.rfind(".\n"), before.rfind("\n\n"), 0)
    after = text[m.end():]
    endm = re.search(r"\.(\s|$)|\n\n", after)
    end = m.end() + (endm.start() + 1 if endm else min(300, len(after)))
    sent = strip_markup(text[start:end])
    if len(sent) > 600:
        sent = sent[:600] + "…"
    return {"section": section, "sentence": sent, "in_lead": section == "lead"}


def year_from_lead(text):
    lead = strip_markup(text.split("\n==", 1)[0])[:1500]
    m = re.search(r"\b(?:enacted|passed|signed|adopted|promulgated|came into force|introduced)\b[^.]{0,80}?\b((?:18|19|20)\d{2})\b", lead)
    if m:
        return m.group(1)
    m = re.search(r"\b((?:18|19|20)\d{2})\b", lead)
    return m.group(1) if m else None


def stage1(state):
    works = works_set(state)
    marks = marks_set(state)
    pairs = state.setdefault("pairs", [])
    scanned = set(state.setdefault("marks_scanned", []))
    hits_by_mark = state.setdefault("hits_by_mark", {})
    # recent first; undated last
    order = sorted((t for t in marks if t not in scanned), key=lambda t: marks[t]["date"] or "0000", reverse=True)[:MAX_MARKS]
    print("marks to scan:", len(order), flush=True)
    for i in range(0, len(order), 50):
        batch = order[i:i + 50]
        links = links_for(batch)
        for t in batch:
            hits = [l for l in links.get(t, []) if l in works and l.lower() not in t.lower() and t.lower() not in l.lower()]
            if hits:
                hits_by_mark[t] = hits
            scanned.add(t)
        state["marks_scanned"] = sorted(scanned)
        if (i // 50) % 20 == 0:
            save(state)
            print(f"scanned {len(scanned)}/{len(marks)}; marks with hits {len(hits_by_mark)}", flush=True)
    # context for every mark with hits
    ctx_done = set(state.setdefault("ctx_done", []))
    for t, hits in list(hits_by_mark.items()):
        if t in ctx_done:
            continue
        text = wikitext(t)
        m = marks[t]
        mdate = m["date"] or (year_from_lead(text) + "-07-01" if text and year_from_lead(text) else None)
        for w in hits:
            kind, wdate, wq = works[w]
            c = context_of(text, w) if text else None
            lag = (dt.date.fromisoformat(mdate) - dt.date.fromisoformat(wdate)).days if (mdate and wdate) else None
            culture = bool(c and CULTURE_SECTION.search(c["section"]))
            score = len(CAUSAL.findall(c["sentence"])) if c else 0
            pairs.append({"mark": t, "mark_q": m["q"], "mark_class": m["class"], "mark_country": m["country"], "mark_date": mdate,
                          "mark_date_source": "wikidata" if m["date"] else ("lead" if mdate else None),
                          "work": w, "work_kind": kind, "work_date": wdate, "work_q": wq, "lag_days": lag,
                          "ordered": (lag is not None and lag >= 0), "section": c["section"] if c else None,
                          "in_lead": c["in_lead"] if c else False, "culture_section": culture,
                          "sentence": c["sentence"] if c else None, "causal_score": score})
        ctx_done.add(t)
        state["ctx_done"] = sorted(ctx_done)
        if len(ctx_done) % 25 == 0:
            save(state)
    return pairs


# ---------- Stage 2: Federal Register ----------
def catalog_terms():
    terms = set(GENERIC_TERMS)
    for f in glob.glob(os.path.join(ROOT, "chains", "*.json")):
        for c in json.load(open(f)):
            terms.add(re.sub(r"\s*\(.*?\)|,.*| and .*| beyond .*", "", c["title"]).strip())
    p = os.path.join(ROOT, "demo", "discovered.json")
    if os.path.exists(p):
        for e in json.load(open(p))["events"].values():
            terms.add(e["title"])
    terms = {t.strip("'\"") for t in terms}
    # proper names only: a later word is capitalized, or it is one word (drops descriptions like "A heat pump experiment")
    return sorted(t for t in terms if len(t) > 3 and (" " not in t or any(w[:1].isupper() for w in t.split()[1:])))


def stage2(state):
    out = state.setdefault("federal_register", {})
    for term in catalog_terms():
        if term in out:
            continue
        params = {"conditions[term]": f'"{term}"', "per_page": 20, "order": "oldest",
                  "fields[]": ["title", "publication_date", "type", "agency_names", "html_url", "document_number"]}
        body = get(f"{FR}?{urllib.parse.urlencode(params, doseq=True)}", delay=1.0)
        if not body:
            out[term] = {"count": None}
            continue
        try:
            d = json.loads(body)
        except ValueError:
            out[term] = {"count": None}
            continue
        docs = [{"title": x.get("title"), "date": x.get("publication_date"), "type": x.get("type"),
                 "agencies": x.get("agency_names"), "url": x.get("html_url")} for x in d.get("results", [])]
        out[term] = {"count": d.get("count", 0), "docs": docs}
        print("FR", term, d.get("count", 0), flush=True)
    return out


# ---------- summary ----------
def recall(pairs):
    want = {"Mr Bates vs The Post Office": ["Post Office (Horizon System) Offences Act 2024"],
            "Tiger King": ["Big Cat Public Safety Act"],
            "The Jungle": ["Pure Food and Drug Act", "Federal Meat Inspection Act"],
            "Unsafe at Any Speed": ["National Traffic and Motor Vehicle Safety Act"],
            "WarGames": ["Computer Fraud and Abuse Act", "National Security Decision Directive 145"]}
    out = {}
    for w, ms in want.items():
        hit = [p for p in pairs if p["work"] == w and any(m.lower() in p["mark"].lower() for m in ms)]
        out[w] = {"found": bool(hit), "ordered": any(p["ordered"] for p in hit), "causal": any(p["causal_score"] > 0 for p in hit),
                  "marks": sorted({p["mark"] for p in hit})}
    return out


def save(state):
    tmp = OUT + ".tmp"
    json.dump(state, open(tmp, "w"), ensure_ascii=False)
    os.replace(tmp, OUT)


def main() -> int:
    state = json.load(open(OUT)) if os.path.exists(OUT) else {"protocol": "ripples/docs/mark_first_v1.md", "started": dt.date.today().isoformat()}
    state.pop("stopped", None)
    try:
        if "causal_statements" not in state:
            state["causal_statements"] = stage0()
            print("stage 0:", len(state["causal_statements"]), "causal statements", flush=True)
            save(state)
        stage1(state)
        save(state)
        stage2(state)
    except Stop as e:
        state["stopped"] = str(e)
        print("stopped:", e, flush=True)
    pairs = state.get("pairs", [])
    good = [p for p in pairs if p["ordered"] and p["causal_score"] > 0 and not p["culture_section"]]
    good.sort(key=lambda p: (-p["causal_score"], -p["in_lead"], p["lag_days"] or 0))
    state["summary"] = {"marks": len(state.get("marks", {})), "works": len(state.get("works", {})), "scanned": len(state.get("marks_scanned", [])),
                        "pairs": len(pairs), "ordered_causal": len(good), "recall": recall(pairs), "top": good[:60]}
    save(state)
    print(json.dumps({k: v for k, v in state["summary"].items() if k != "top"}, indent=1))
    for p in good[:40]:
        print(f"  {p['work_date']} {p['work']} [{p['work_kind']}] -> {p['mark_date']} {p['mark']} [{p['mark_class']}] score {p['causal_score']} §{p['section']}")
        print(f"     {p['sentence'][:200] if p['sentence'] else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
