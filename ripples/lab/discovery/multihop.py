"""Multi-hop ripples v1 (ripples/docs/multihop_plan_v1.md, registered Oct 4, 2026 before any search).

stone -> intermediate -> lasting mark, each hop graded and ordered.
  stage1   A: candidates from the stone's article (lead and non-plot sections) plus its attention leads; the specificity
              filter on Wikidata. B: hop 1, measured (the checker's attention test) or reported (a causal sentence in the
              stone's article). The survivors' redirects and names. Writes docs/results/multihop_stage1_v1.json.
  stage2   C: hop 2 from the laptop: H1 Hansard bill debates resolved to Acts, H2 the Wikipedia reverse hop.
              Writes docs/results/multihop_hop2_v1.json. (H4, the Congressional Record, is multihop_gov.py in a workflow.)
  compose  automated chains (main set and famous decoys), D1 wrong-stone decoys. Writes docs/results/multihop_raw_v1.json.
  build    with the hand check (docs/results/multihop_hand_v1.json): docs/results/multihop_v1.json.
Run from the repository root. One process, one limiter across every host: at most one request a second; a 403, 429 or
any 5xx stops the run; a 404 is a skip. Responses are cached in a local file outside the repository (MULTIHOP_CACHE)
so a re-run after a code fix asks nothing twice.
"""
from __future__ import annotations

import ast
import datetime as dt
import html
import json
import os
import random
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter

os.environ.setdefault("BUDGET_MIN", "100000")  # the shared helpers carry a time budget; this run has its own caps
HERE = os.path.dirname(os.path.abspath(__file__))
LAB = os.path.dirname(HERE)
ROOT = os.path.dirname(LAB)  # ripples/
sys.path.insert(0, LAB)
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import mark_first as mf  # noqa: E402
import editor_trail as et  # noqa: E402
import chain_check as cc  # noqa: E402
import cite_score  # noqa: E402
import bill_act  # noqa: E402
from legacy import clean, sentences, links, plain  # noqa: E402
from legacy2 import SKIP  # noqa: E402
from hop3 import MARKT, NOT  # noqa: E402

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
WP = "https://en.wikipedia.org/w/api.php"
SPARQL = "https://query.wikidata.org/sparql"
HAN = "https://hansard-api.parliament.uk/search/contributions/Spoken.json"
RES = os.path.join(ROOT, "docs", "results")
STAGE1 = os.environ.get("MULTIHOP_STAGE1") or os.path.join(RES, "multihop_stage1_v1.json")
HOP2 = os.environ.get("MULTIHOP_HOP2") or os.path.join(RES, "multihop_hop2_v1.json")
GOVR = os.path.join(RES, "multihop_gov_v1.json")
RAW = os.path.join(RES, "multihop_raw_v1.json")
HAND = os.path.join(RES, "multihop_hand_v1.json")
FINAL = os.path.join(RES, "multihop_v1.json")
# every stone's raw link targets (for the D1 exclusion) are bulky and kept beside the cache, outside the repository
SIDECAR = os.environ.get("MULTIHOP_TARGETS") or os.path.join(os.path.expanduser("~"), ".multihop_targets.json")
CACHE = os.environ.get("MULTIHOP_CACHE") or os.path.join(os.path.expanduser("~"), ".multihop_cache.sqlite")
TODAY = dt.date.fromisoformat(os.environ["MULTIHOP_TODAY"]) if os.environ.get("MULTIHOP_TODAY") else dt.date.today()  # the run spans midnight; one cutoff
CAUSAL = mf.CAUSAL
YEAR = re.compile(r"\b(1[6-9]\d\d|20\d\d)\b")
PAGEVIEWS_FROM = dt.date(2015, 8, 1)
MEASURED_CAP, TO_HOP2_MEASURED, TO_HOP2_REPORTED = 20, 4, 3
SEED = 20261004

# ---------- the specificity filter, as registered ----------
DENY = re.compile(r"taxon|species|genus|group of organisms|concept|academic discipline|field of study|branch of|occupation|profession|position|"
                  r"genre|style|technique|ideology|religion|ethnic group|language|country|sovereign state|city|town|village|human settlement|"
                  r"municipality|county|state of|province|region|continent|island|river|lake|sea|ocean|mountain|administrative|territory|"
                  r"Wikimedia|disambiguation|list|film|television series|TV series|miniseries|episode|season|song|single|album|book|novel|"
                  r"literary work|written work|video game|podcast|fictional|character|work of art|painting|chemical|compound|disease|food|"
                  r"dish|sandwich|beverage|drink|cuisine|sport|game|holiday|calendar|year|decade|century|color|symbol|award|prize", re.I)
ECHO_P = ["P57", "P58", "P162", "P86", "P50", "P170", "P272", "P449", "P750", "P1040", "P344", "P371", "P175", "P179", "P361", "P527"]
ACTING = {"Q33999", "Q10800557", "Q10798782", "Q2259451", "Q2405480"}
NS = {"file", "image", "category", "template", "wikipedia", "wp", "help", "portal", "draft", "module", "special", "media", "wikt", "wiktionary",
      "s", "q", "n", "commons", "d", "talk", "user", "w", "meta", "mw", "wikisource", "wikiquote", "wikinews", "voy", "species", "b", "v"}
WORDS = set()
if os.path.exists("/usr/share/dict/words"):
    WORDS = {w.strip().lower() for w in open("/usr/share/dict/words", encoding="utf-8", errors="ignore")}
STOPW = {"the", "a", "an", "of", "and", "in", "on", "at", "to", "for", "by", "with", "from", "de", "la", "le", "von", "van"}


def guarded(name):
    """The name guard: at least two words, or one word of five letters or more that is not in the system word list."""
    ws = [w for w in re.findall(r"[\w'’.-]+", name or "") if w.lower() not in STOPW]
    if len(ws) >= 2:
        return True
    return len(ws) == 1 and len(ws[0]) >= 5 and ws[0].lower() not in WORDS


def bare(title):
    return re.sub(r"\s*\([^)]*\)\s*$", "", title or "").strip()


def norm_target(t):
    t = (t or "").split("#")[0].replace("_", " ").strip().lstrip(":")
    t = re.sub(r"\s+", " ", t)
    if not t:
        return None
    if ":" in t and t.split(":")[0].strip().lower() in NS | {""} or re.match(r"^[a-z]{2,3}(-[a-z]+)?:", t):
        return None
    return t[0].upper() + t[1:]


# ---------- one HTTP layer for every host ----------
class Stop(Exception):
    pass


LAST = [0.0]
COUNTS = Counter()
STATE = {"stopped": None}
_db = None


def db():
    global _db
    if _db is None:
        _db = sqlite3.connect(CACHE)
        _db.execute("CREATE TABLE IF NOT EXISTS c (k TEXT PRIMARY KEY, status INTEGER, body TEXT, t TEXT)")
    return _db


def fetch(url, headers=None, timeout=90):
    """Text of url, or None for a 404 or a network error; Stop on a 403, 429 or any 5xx. Cached."""
    row = db().execute("SELECT status, body FROM c WHERE k=?", (url,)).fetchone()
    if row:
        return row[1] if row[0] == 200 else None
    if STATE["stopped"]:
        raise Stop(STATE["stopped"])
    wait = 1.0 - (time.time() - LAST[0])
    if wait > 0:
        time.sleep(wait)
    host = urllib.parse.urlparse(url).netloc
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    status, body = 200, None
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        status = e.code
    except Exception as e:  # noqa: BLE001  a timeout or reset is not a status; logged, not cached
        LAST[0] = time.time(); COUNTS[host] += 1
        print(f"  network error at {host}: {str(e)[:80]}", flush=True)
        return None
    LAST[0] = time.time(); COUNTS[host] += 1
    if status in (403, 429) or status >= 500:
        STATE["stopped"] = f"HTTP {status} from {host} at {TODAY.isoformat()}"
        raise Stop(STATE["stopped"])
    db().execute("INSERT OR REPLACE INTO c VALUES (?,?,?,?)", (url, status, body if status == 200 else None, dt.datetime.utcnow().isoformat()))
    db().commit()
    return body if status == 200 else None


def fetch_json(url, headers=None):
    body = fetch(url, headers)
    try:
        return json.loads(body) if body else None
    except ValueError:
        return None


def wp(params):
    return fetch_json(WP + "?" + urllib.parse.urlencode({**params, "format": "json", "formatversion": 2})) or {}


def sparql(q):
    d = fetch_json(SPARQL + "?" + urllib.parse.urlencode({"query": q}), {"Accept": "application/sparql-results+json"})
    return (d or {}).get("results", {}).get("bindings", [])


# the shared helpers go through the same limiter, cache and stop rule
et.get = lambda url: fetch_json(url)
mf.get = lambda url, headers=None, delay=1.0, timeout=90: fetch(url, headers, timeout)

_series_cache = {}


def _series(title, end):
    """Daily views from Jul 1, 2015 to two days ago, fetched once per article (a later cutoff slices the same data)."""
    if title not in _series_cache:
        d = fetch_json(et.PV.format(t=urllib.parse.quote(title.replace(" ", "_"), safe=""), b=(TODAY - dt.timedelta(days=2)).strftime("%Y%m%d")))
        _series_cache[title] = {i["timestamp"][:8]: i["views"] for i in d.get("items", [])} if d else None
    return _series_cache[title]


et.series = _series


# ---------- dates ----------
def prec(d):
    return "day" if d and len(d) >= 10 else "month" if d and len(d) == 7 else "year"


def ge(a, b):
    """a on or after b, compared at the coarser precision of the two."""
    if not a or not b:
        return False
    n = min(len(a), len(b), 10)
    n = 4 if n < 7 else 7 if n < 10 else 10
    return a[:n] >= b[:n]


# ---------- stones ----------
def stones_main():
    S = {}
    sa = json.load(open(os.path.join(RES, "stones_all.json")))
    for k, v in sa.items():
        if v.get("in_class") and v.get("date"):
            art = "Chernobyl (miniseries)" if k == "chernobyl-zone" else v["article"]  # registered correction
            S.setdefault(art, {"article": art, "title": v["stone"], "date": v["date"], "from": []})["from"].append("catalog:" + k)
    for k, e in json.load(open(os.path.join(ROOT, "demo", "discovered.json")))["events"].items():
        art = e["articles"][0]
        S.setdefault(art, {"article": art, "title": e["title"], "date": e["date"], "from": [], "leads": []})
        S[art]["from"].append("attention:" + k)
        S[art]["leads"] = [l["title"] for l in e.get("links", [])]
    for k, s in json.load(open(os.path.join(ROOT, "demo", "discovered_wiki.json")))["stones"].items():
        S.setdefault(s["article"], {"article": s["article"], "title": s["stone"], "date": s["date"], "from": []})["from"].append("wiki:" + k)
    src = open(os.path.join(HERE, "heldout.py")).read()
    for art, name, year in ast.literal_eval(re.search(r"STONES = (\[.*?\])\n", src).group(1)):
        S.setdefault(art, {"article": art, "title": name, "date": str(year), "from": []})["from"].append("heldout")
    S.pop("Top Gun: Maverick", None)  # registered: it stays a famous decoy
    for s in S.values():
        s.setdefault("leads", [])
        s["set"] = "main"
    return list(S.values())


def stones_famous():
    src = open(os.path.join(HERE, "famous_decoys.py")).read()
    out = []
    for art, year in ast.literal_eval(re.search(r"FAMOUS = (\[.*?\])\n", src).group(1)):
        out.append({"article": art, "title": bare(art), "date": str(year), "from": ["famous_decoys"], "leads": [], "set": "famous"})
    return out


# ---------- Wikipedia helpers ----------
def resolve_titles(titles):
    """input title -> (final title, QID or None); missing pages map to None."""
    out = {}
    titles = [t for t in dict.fromkeys(titles) if t]
    for i in range(0, len(titles), 50):
        chunk = titles[i:i + 50]
        d = wp({"action": "query", "titles": "|".join(chunk), "redirects": 1, "prop": "pageprops", "ppprop": "wikibase_item"})
        q = d.get("query", {})
        norm = {x["from"]: x["to"] for x in q.get("normalized", [])}
        redir = {x["from"]: x["to"] for x in q.get("redirects", [])}
        pages = {p["title"]: p for p in q.get("pages", [])}
        for t in chunk:
            f = norm.get(t, t)
            f = redir.get(f, f)
            f = redir.get(f, f)
            p = pages.get(f)
            if not p or p.get("missing") or p.get("invalid"):
                out[t] = None
            else:
                out[t] = (p["title"], (p.get("pageprops") or {}).get("wikibase_item"))
    return out


def read_stone(title):
    """The stone's article: real title, QID, kept sections' sentences (plain text and links), and link targets in order."""
    d = wp({"action": "parse", "page": title, "prop": "wikitext", "redirects": 1})
    if "parse" not in d:
        return None
    wt = d["parse"]["wikitext"]
    real = d["parse"]["title"]
    parts = re.split(r"^(=+)\s*(.*?)\s*\1\s*$", wt, flags=re.M)
    secs = [("Lead", parts[0])] + [(parts[i + 1], parts[i + 2]) for i in range(1, len(parts) - 2, 3)]
    sents, order = [], []
    for head, body in secs:
        if head != "Lead" and SKIP.search(head):
            continue
        txt, _ = clean(body)
        for s in sentences(txt):
            tg = [x for x in (norm_target(l) for l in links(s)) if x]
            order += tg
            sents.append({"section": head, "text": plain(s)[:600], "links": list(dict.fromkeys(tg))})
    return {"real": real, "sentences": sents, "targets": list(dict.fromkeys(order))}


def wikidata_props(qids):
    """QID -> {'classes': [labels], 'sub': bool, 'occ': set, 'ctry': set}"""
    out = {q: {"classes": [], "sub": False, "occ": set(), "ctry": set()} for q in qids}
    qids = list(out)
    for i in range(0, len(qids), 80):
        vals = " ".join("wd:" + q for q in qids[i:i + 80])
        rows = sparql(f"""SELECT ?item ?p ?v ?vl WHERE {{ VALUES ?item {{ {vals} }}
          {{ VALUES ?p {{ wdt:P31 wdt:P279 wdt:P106 wdt:P27 wdt:P17 wdt:P495 }} ?item ?p ?v . }}
          UNION {{ ?item wdt:P159/wdt:P17 ?v . BIND(wdt:P159 AS ?p) }}
          OPTIONAL {{ ?v rdfs:label ?vl . FILTER(LANG(?vl) = "en") }} }}""")
        for r in rows:
            q = r["item"]["value"].rsplit("/", 1)[-1]
            p = r["p"]["value"].rsplit("/", 1)[-1]
            v = r["v"]["value"].rsplit("/", 1)[-1]
            o = out.setdefault(q, {"classes": [], "sub": False, "occ": set(), "ctry": set()})
            if p == "P31":
                o["classes"].append((r.get("vl") or {}).get("value") or v)
            elif p == "P279":
                o["sub"] = True
            elif p == "P106":
                o["occ"].add(v)
            else:
                o["ctry"].add(v)
    return out


def stone_wikidata(stones):
    """Echo values, countries and publication dates for every stone with a QID."""
    qs = [s["qid"] for s in stones if s.get("qid")]
    echo, ctry, dates = {}, {}, {}
    props = " ".join("wdt:" + p for p in ECHO_P)
    for i in range(0, len(qs), 40):
        vals = " ".join("wd:" + q for q in qs[i:i + 40])
        for r in sparql(f"SELECT ?s ?v WHERE {{ VALUES ?s {{ {vals} }} VALUES ?p {{ {props} }} ?s ?p ?v . }}"):
            echo.setdefault(r["s"]["value"].rsplit("/", 1)[-1], set()).add(r["v"]["value"].rsplit("/", 1)[-1])
        for r in sparql(f"SELECT ?s ?v WHERE {{ VALUES ?s {{ {vals} }} ?s wdt:P495|wdt:P17 ?v . }}"):
            ctry.setdefault(r["s"]["value"].rsplit("/", 1)[-1], set()).add(r["v"]["value"].rsplit("/", 1)[-1])
        for r in sparql(f"SELECT ?s ?d WHERE {{ VALUES ?s {{ {vals} }} ?s wdt:P577|wdt:P580|wdt:P585 ?d . }}"):
            dates.setdefault(r["s"]["value"].rsplit("/", 1)[-1], []).append(r["d"]["value"][:10])
    return echo, ctry, dates


def year_date(dates, year):
    """The earliest date inside the listed year (registered rule for year-only stones), else None."""
    inside = sorted(d for d in dates if d[:4] == str(year) and re.match(r"\d{4}-\d{2}-\d{2}$", d) and not d.endswith("-01-01"))
    return inside[0] if inside else None


def filter_reason(title, qid, props, stone, echo):
    if not qid:
        return "no Wikidata item"
    p = props.get(qid) or {}
    if p.get("sub"):
        return "a class (subclass of)"
    if not p.get("classes"):
        return "no instance-of"
    bad = [c for c in p["classes"] if DENY.search(c)]
    if bad:
        return "generic kind: " + bad[0]
    if qid == stone.get("qid") or qid in echo:
        return "echo of the stone (creator, broadcaster, series)"
    if p.get("occ") & ACTING:
        return "echo: an actor"
    a, b = bare(title).lower(), bare(stone["real"]).lower()
    if a in b or b in a:
        return "the stone's own title"
    return None


def hop1_measured(title, date):
    try:
        r = cc.wiki_test([title], dt.date.fromisoformat(date), 45)
    except IndexError:  # the article's first recorded day is after the test window
        return {"verdict": "no baseline (article created later)"}
    out = {k: r.get(k) for k in ("onset", "ratio", "p", "n_placebo", "baseline", "new_article", "result")}
    out["weekly"] = r.get("weekly")
    if r.get("result") == "no article":
        out["verdict"] = "no article"
    elif r.get("new_article"):
        out["verdict"] = "no baseline (article created then)"
    elif r.get("p") is None:
        out["verdict"] = "no sustained rise" if r.get("result") else "rose, too little history"
    elif r["p"] <= 0.05:
        out["verdict"] = "measured" if r["onset"] >= date else "busted: rose before the stone"
    else:
        out["verdict"] = "within chance"
    return out


def reported_sentences(st, names_by_target):
    """target -> list of qualifying causal sentences in the stone's article (links it, or names it by a guarded name)."""
    sy = int(st["date"][:4])
    hits = {}
    for s in st["read"]["sentences"]:
        if not CAUSAL.search(s["text"]):
            continue
        ys = [int(y) for y in YEAR.findall(s["text"])]
        if ys and max(ys) < sy:
            continue
        found = set(s["links"])
        for tg, nm in names_by_target.items():
            if nm and re.search(r"(?<![\w])" + re.escape(nm) + r"(?![\w])", s["text"]):
                found.add(tg)
        later = [y for y in ys if y >= sy]
        for tg in found:
            hits.setdefault(tg, []).append({"section": s["section"], "text": s["text"], "date": str(min(later)) if later else st["date"]})
    return hits


def stage1(which):
    stones = (stones_main() if which in ("main", "all") else []) + (stones_famous() if which in ("famous", "all") else [])
    only = [x for x in os.environ.get("MULTIHOP_ONLY", "").split("|") if x]
    if only:  # a smoke test on named stones, written elsewhere
        stones = [s for s in stones if s["article"] in only]
    print(f"stage 1: {len(stones)} stones", flush=True)
    # the stones' own articles and items
    for st in stones:
        st["read"] = read_stone(st["article"])
        if not st["read"]:
            print("  no article:", st["article"], flush=True)
            continue
        st["real"] = st["read"]["real"]
    live = [s for s in stones if s.get("read")]
    rq = resolve_titles([s["real"] for s in live])
    for s in live:
        s["qid"] = (rq.get(s["real"]) or (None, None))[1]
    echo, sctry, sdates = stone_wikidata(live)
    for s in live:
        s["us"] = "Q30" in sctry.get(s.get("qid"), set())
        if len(s["date"]) == 4:  # year-only stones: the earliest dated publication inside that year
            d = year_date(sdates.get(s.get("qid"), []), s["date"])
            s["date_rule"] = "Wikidata, earliest in the year" if d else "year precision"
            if d:
                s["date"] = d
    # candidates
    for s in live:
        sentences_ = s["read"]["sentences"]
        names = {t: (bare(t) if guarded(bare(t)) else None) for t in s["read"]["targets"]}
        causal = reported_sentences(s, names)
        measurable = (len(s["date"]) == 10 and dt.date.fromisoformat(s["date"]) >= PAGEVIEWS_FROM
                      and dt.date.fromisoformat(s["date"]) <= TODAY - dt.timedelta(days=45))
        order = [norm_target(l) for l in s["leads"]] + s["read"]["targets"]
        order = [t for t in dict.fromkeys(order) if t]
        want = set(causal) | set(norm_target(l) for l in s["leads"])
        res = resolve_titles(list(want))
        # for the measured test, resolve in candidate order until 20 pass the filter
        cands, seen_final, measured_pool, filt = [], set(), [], {}
        props = {}
        i = 0
        while True:
            batch_titles = [t for t in order[i:i + 50]] if measurable else []
            if measurable and batch_titles:
                res.update(resolve_titles([t for t in batch_titles if t not in res]))
            pending = [t for t in (batch_titles if measurable else []) + [t for t in want if t not in filt] if res.get(t)]
            qn = [res[t][1] for t in pending if res[t][1] and res[t][1] not in props]
            if qn:
                props.update(wikidata_props(qn))
            for t in dict.fromkeys(pending):
                if t in filt:
                    continue
                fin, q = res[t]
                filt[t] = filter_reason(fin, q, props, s, echo.get(s.get("qid"), set()))
                if measurable and t in batch_titles and not filt[t] and fin not in seen_final and len(measured_pool) < MEASURED_CAP:
                    seen_final.add(fin); measured_pool.append(t)
            i += 50
            if not measurable or len(measured_pool) >= MEASURED_CAP or i >= len(order):
                break
        # leads first: make sure the attention leads are in the pool if they pass (they head the order already)
        for t in dict.fromkeys(list(want) + measured_pool):
            r = res.get(t)
            if not r:
                continue
            fin, q = r
            c = next((c for c in cands if c["title"] == fin), None)
            if not c:
                c = {"title": fin, "qid": q, "targets": [], "filter": filt.get(t), "ctry": sorted((props.get(q) or {}).get("ctry", [])),
                     "classes": (props.get(q) or {}).get("classes", [])[:3], "lead": t in [norm_target(l) for l in s["leads"]]}
                cands.append(c)
            c["targets"].append(t)
            if t in causal:
                c.setdefault("reported", []).extend(causal[t])
        for c in cands:
            if c["filter"]:
                continue
            if measurable and any(t in measured_pool for t in c["targets"]):
                c["measured"] = hop1_measured(c["title"], s["date"])
        # hop-1 survivors, capped as registered
        m = sorted([c for c in cands if not c["filter"] and (c.get("measured") or {}).get("verdict") == "measured"], key=lambda c: -c["measured"]["ratio"])
        r = [c for c in cands if not c["filter"] and c.get("reported") and c not in m[:TO_HOP2_MEASURED]]
        r.sort(key=lambda c: (-len(c["reported"]), min([order.index(t) for t in c["targets"] if t in order] or [9999])))
        surv = []
        for c in m[:TO_HOP2_MEASURED]:
            surv.append({"title": c["title"], "qid": c["qid"], "grade": "measured", "date": c["measured"]["onset"], "ctry": c["ctry"],
                         "measured": {k: v for k, v in c["measured"].items() if k != "weekly"}, "reported": (c.get("reported") or [])[:2]})
        for c in r[:TO_HOP2_REPORTED]:
            rep = sorted(c["reported"], key=lambda x: x["date"])
            surv.append({"title": c["title"], "qid": c["qid"], "grade": "reported", "date": rep[0]["date"], "ctry": c["ctry"], "reported": rep[:3]})
        s["candidates"] = cands
        s["survivors"] = surv
        s["measurable"] = measurable
        print(f"  {s['set']:6s} {s['real'][:40]:40s} {s['date']} | targets {len(s['read']['targets']):4d} | resolved {len(cands):3d} "
              f"| pass filter {sum(1 for c in cands if not c['filter']):3d} | measured {len(m):2d} | reported {len(r):2d} | to hop 2 {len(surv)}", flush=True)
    # names for hop 2: the title less any parenthetical and the two shortest guarded redirects
    redirs = {}
    for s in live:
        for v in s["survivors"]:
            if v["title"] not in redirs:
                d = wp({"action": "query", "titles": v["title"], "prop": "redirects", "rdlimit": "max", "rdnamespace": 0})
                pg = (d.get("query", {}).get("pages") or [{}])[0]
                redirs[v["title"]] = [x["title"] for x in pg.get("redirects", [])]
            rd = redirs[v["title"]]
            names = [bare(v["title"])] if guarded(bare(v["title"])) else []
            extra = sorted({bare(x) for x in rd if guarded(bare(x)) and bare(x).lower() not in {n.lower() for n in names}}, key=lambda x: (len(x), x))
            v["names"] = names + extra[:2]
            v["redirects"] = rd
            v["us"] = s.get("us") or "Q30" in v["ctry"]
    out = {"protocol": "ripples/docs/multihop_plan_v1.md", "run": TODAY.isoformat(), "requests": dict(COUNTS), "stopped": STATE["stopped"],
           "stones": [{k: v for k, v in s.items() if k != "read"} for s in stones]}
    json.dump({s["article"]: (s.get("read") or {}).get("targets", []) for s in stones}, open(SIDECAR, "w"), ensure_ascii=False)
    for s in out["stones"]:
        for c in s.get("candidates", []):
            if c.get("measured"):
                c["measured"].pop("weekly", None)
    json.dump(out, open(STAGE1, "w"), ensure_ascii=False, indent=0)
    print("stage 1 written;", dict(COUNTS), flush=True)


# ---------- stage 2: hop 2 from the laptop ----------
def mark_year_from(title, wt):
    t = YEAR.search(title)
    if t:
        return int(t.group(1)), "title", None
    lead = re.split(r"^==", wt, maxsplit=1, flags=re.M)[0]
    m = re.search(r"\|\s*(enacted|date_enacted|date_signed|signed|royal_assent|date_of_royal_assent|ratified|date_ratified|adopted|date_adopted|formed|"
                  r"founded|established|date_established|effective|date_effective|date_passed|passed|formation|date_formed|inception|start_date|created|"
                  r"date_created|opened|date_opened)\s*=\s*([^\n]*)", lead, re.I)
    if m and YEAR.search(m.group(2)):
        val = m.group(2)
        full = None
        sd = re.search(r"\{\{\s*(?:start date|start-date|date|dts)[^|}]*\|\s*(\d{4})\s*\|\s*(\d{1,2})\s*\|\s*(\d{1,2})", val, re.I)
        if sd:
            full = f"{sd.group(1)}-{int(sd.group(2)):02d}-{int(sd.group(3)):02d}"
        else:
            md = re.search(r"(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s+(\d{4})|"
                           r"(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})", val)
            if md:
                mon = md.group(1) or md.group(5)
                day = md.group(2) or md.group(4)
                yr = md.group(3) or md.group(6)
                full = dt.datetime.strptime(f"{mon} {int(day)} {yr}", "%B %d %Y").date().isoformat()
        return int(YEAR.search(val).group(1)), "infobox", full
    txt, _ = clean(lead)
    ys = [int(y) for y in YEAR.findall(txt[:1500]) if int(y) >= 1700]
    return (min(ys), "lead", None) if ys else (None, "none", None)


def h2(v, stone):
    """The Wikipedia reverse hop for one survivor."""
    bl, cont = [], {}
    for _ in range(2):
        d = wp({"action": "query", "list": "backlinks", "bltitle": v["title"], "blnamespace": 0, "bllimit": 500, "blredirect": 1, **cont})
        for b in d.get("query", {}).get("backlinks", []):
            if not b.get("redirect"):  # a redirect to the intermediate is another name for it, not an article that links to it
                bl.append(b["title"])
            bl += [r["title"] for r in b.get("redirlinks", [])]
        if "continue" in d:
            cont = d["continue"]
        else:
            break
    hy = int(v["date"][:4])
    marky = [t for t in dict.fromkeys(bl) if MARKT.search(t) and not NOT.search(t)]
    with_year = [t for t in marky if YEAR.search(t) and int(YEAR.search(t).group(1)) >= hy]
    no_year = [t for t in marky if not YEAR.search(t)]
    pick = (with_year + no_year)[:12]
    out = {"backlinks": len(bl), "mark_titled": len(marky), "read": pick, "hits": []}
    if not pick:
        return out
    pages, cont = {}, {}
    for _ in range(6):
        d = wp({"action": "query", "titles": "|".join(pick), "prop": "revisions", "rvprop": "content", "rvslots": "main", "redirects": 1, **cont})
        for p in d.get("query", {}).get("pages", []):
            if p.get("revisions") or p["title"] not in pages:
                pages[p["title"]] = p
        if "continue" in d:
            cont = d["continue"]
        else:
            break
    pages = list(pages.values())
    me = {v["title"]} | set(v.get("redirects", []))
    me_norm = {norm_target(x) for x in me}
    stone_names = {bare(stone["real"]), stone["title"]} - {""}
    for p in pages:
        revs = p.get("revisions") or []
        if not revs:
            continue
        wt = revs[0].get("slots", {}).get("main", {}).get("content", "")
        t = p["title"]
        txt, _ = clean(wt)
        dw = [w.lower() for w in re.findall(r"[A-Za-z][A-Za-z\-']{3,}", bare(t)) if w.lower() not in ("united", "states", "national", "federal", "department")]
        good = []
        for sent in sentences(txt):
            lk = {norm_target(x) for x in links(sent)}
            pl = plain(sent)
            named = bool(lk & me_norm) or any(re.search(r"(?<![\w])" + re.escape(n) + r"(?![\w])", pl) for n in v["names"])
            if not named or not CAUSAL.search(pl):
                continue
            if dw and not any(w in pl.lower() for w in dw):
                continue
            good.append(pl[:600])
        if not good:
            continue
        my, how, full = mark_year_from(t, wt)
        hit = {"mark": t, "mark_year": my, "dated_by": how, "mark_date": full or (str(my) if my else None), "sentences": good[:3],
               "names_stone": any(n and n.lower() in " ".join(good).lower() for n in stone_names)}
        if my is None:
            hit["verdict"] = "undated"
        elif my < hy:
            hit["verdict"] = "busted: before the hop-1 step"
        else:
            hit["verdict"] = "in order"
        out["hits"].append(hit)
    return out


def h1(v, stone):
    """Hansard bill debates naming the survivor, resolved to Acts."""
    start = v["date"] if len(v["date"]) == 10 else f"{v['date'][:4]}-01-01"
    if start < stone["date"][:10] and len(stone["date"]) == 10:
        start = stone["date"]
    end = min(TODAY, dt.date(int(start[:4]) + 6, int(start[5:7]), min(int(start[8:10]), 28))).isoformat()
    stone_names = {bare(stone["real"]), stone["title"]} - {""}
    out = {"names": v["names"], "start": start, "end": end, "counts": {}, "hits": []}
    for name in v["names"]:
        total = None
        rows = []
        for skip in (0, 100):
            if total is not None and skip >= total:
                break
            q = urllib.parse.urlencode({"queryParameters.searchTerm": f'"{name}"', "queryParameters.startDate": start, "queryParameters.endDate": end,
                                        "queryParameters.orderBy": "SittingDateAsc", "queryParameters.take": 100, "queryParameters.skip": skip})
            d = fetch_json(f"{HAN}?{q}") or {}
            total = d.get("TotalResultCount", 0)
            rows += d.get("Results") or []
        out["counts"][name] = total
        for r in rows:
            section = r.get("DebateSection") or ""
            if not re.search(r"\bBill\b", section):
                continue
            text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", r.get("ContributionTextFull") or r.get("ContributionText") or "")).strip()
            text = html.unescape(text)
            if name.lower() not in text.lower():
                continue
            win, _ = cite_score.near(text, name)
            sc, why = cite_score.score(win, name)
            if cite_score.label(sc) != "reason":
                continue
            date = (r.get("SittingDate") or "")[:10]
            res = bill_act.resolve(section, date)
            hit = {"name": name, "debate": section, "date": date, "house": r.get("House"), "member": r.get("MemberName"), "window": win[:700],
                   "cite_score": sc, "cite_why": why, "act": res.get("act"), "royal_assent": res.get("royal_assent"), "act_url": res.get("url"),
                   "resolve_note": res.get("note"), "names_stone": any(n and n.lower() in win.lower() for n in stone_names),
                   "url": f"https://hansard.parliament.uk/debates/{r['DebateSectionExtId']}" if r.get("DebateSectionExtId") else None}
            if not res.get("act") or not res.get("royal_assent"):
                hit["verdict"] = "no Act"
            elif res["royal_assent"] < date:
                hit["verdict"] = "busted: Act before the debate"
            else:
                hit["verdict"] = "in order"
            out["hits"].append(hit)
    return out


def stage2(which):
    s1 = json.load(open(STAGE1))
    prev = json.load(open(HOP2)) if os.path.exists(HOP2) else {"done": {}}
    done = prev["done"]
    try:
        for st in s1["stones"]:
            if which != "all" and st["set"] != which:
                continue
            for v in st.get("survivors", []):
                key = f"{st['real']}|{v['title']}"
                if key in done:
                    continue
                r = {"stone": st["real"], "set": st["set"], "intermediate": v["title"]}
                r["h2"] = h2(v, st)
                r["h1"] = h1(v, st) if v["names"] else {"skipped": "no guarded name"}
                done[key] = r
                ok2 = [h for h in r["h2"]["hits"] if h["verdict"] == "in order"]
                ok1 = [h for h in r["h1"].get("hits", []) if h["verdict"] == "in order"]
                print(f"  {st['set']:6s} {st['real'][:30]:30s} -> {v['title'][:34]:34s} | H2 {len(ok2)} {'; '.join(h['mark'][:40] for h in ok2[:2])} "
                      f"| H1 {len(ok1)} {'; '.join((h['act'] or '')[:40] for h in ok1[:2])}", flush=True)
                json.dump({"run": TODAY.isoformat(), "done": done, "requests": dict(COUNTS), "stopped": STATE["stopped"]}, open(HOP2, "w"), ensure_ascii=False, indent=0)
    except (Stop, mf.Stop) as e:
        STATE["stopped"] = str(e); print("stopped:", e, flush=True)
    json.dump({"run": TODAY.isoformat(), "done": done, "requests": dict(COUNTS), "stopped": STATE["stopped"]}, open(HOP2, "w"), ensure_ascii=False, indent=0)


if __name__ == "__main__":
    cmd = sys.argv[1]
    arg = sys.argv[2] if len(sys.argv) > 2 else "all"
    try:
        if cmd == "stage1":
            stage1(arg)
        elif cmd == "stage2":
            stage2(arg)
        else:
            import multihop_compose  # noqa: F401  compose and build live beside this file
            multihop_compose.main(cmd)
    except (Stop, mf.Stop, et.Stop) as e:
        print("STOPPED:", e, flush=True)
        sys.exit(2)
