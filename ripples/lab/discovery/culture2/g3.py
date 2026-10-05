#!/usr/bin/env python3
"""G3 EFFECTS AND LISTS generator for Ripple.

Finds Wikipedia articles that are themselves about the effects of works
(titles like "X effect", "Cultural impact of X", controversy and moral panic
articles, category members about media effects), reads them, and extracts
sentences where an institution reacted to a work or a measured, durable
behavior change is attributed to it.

Phases (run in order):
  discover  search API + category members -> sources.json
  fetch     parse API (rendered HTML) per source -> pages/*.json
  match     fixed lexicon over sentences -> candidates.json
  intros    fetch intro text for stone/mark titles listed in review.json
  finalize  review.json (hand-read verdicts) -> g3.json

Network rules: honest UA, maxlag=5, search API <= 1 req / 2 s, other
endpoints <= 1 req / s, and a 403/429/5xx stops that endpoint for the day.
"""
import json, os, re, sys, time, html, urllib.parse, urllib.request, urllib.error
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(HERE, "pages")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
API = "https://en.wikipedia.org/w/api.php"
GAP = {"search": 2.0, "other": 1.0}
_last = {"search": 0.0, "other": 0.0}
STOPS_FILE = os.path.join(HERE, "stops.json")


def _stops():
    if os.path.exists(STOPS_FILE):
        return json.load(open(STOPS_FILE))
    return {}


def _stop(kind, why):
    s = _stops()
    s[kind] = {"why": why, "at": time.strftime("%Y-%m-%d %H:%M:%S")}
    json.dump(s, open(STOPS_FILE, "w"), indent=1)
    print("STOP", kind, why, file=sys.stderr)


def api(params, kind="other"):
    if kind in _stops():
        raise RuntimeError("endpoint stopped: " + kind)
    wait = GAP[kind] - (time.time() - _last[kind])
    if wait > 0:
        time.sleep(wait)
    p = dict(params)
    p.update({"format": "json", "formatversion": "2", "maxlag": "5"})
    url = API + "?" + urllib.parse.urlencode(p)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "identity"})
    _last[kind] = time.time()
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code in (403, 429) or e.code >= 500:
            _stop(kind, "HTTP %d" % e.code)
        raise
    if isinstance(data, dict) and data.get("error", {}).get("code") == "maxlag":
        # lag above 5 s: honor the server and back off once
        time.sleep(10)
        return api(params, kind)
    return data


# ---------------------------------------------------------------- discover
SEARCHES = [
    'intitle:effect film', 'intitle:effect television', 'intitle:effect series',
    'intitle:effect show', 'intitle:effect novel', 'intitle:effect book',
    'intitle:effect "video game"', 'intitle:effect documentary', 'intitle:effect song',
    'intitle:effect character', 'intitle:effect actor', 'intitle:effect sitcom',
    'intitle:effect broadcast', 'intitle:effect children\'s programme',
    'intitle:"cultural impact"', 'intitle:"cultural influence"', 'intitle:"impact of" film',
    'intitle:"impact of" television', 'intitle:"legacy of" film', 'intitle:"influence of" novel',
    'intitle:phenomenon film', 'intitle:phenomenon television', 'intitle:craze',
    'intitle:controversy "video game" banned', 'intitle:controversy television episode banned',
    'intitle:controversy film banned', 'intitle:controversies video game',
    'intitle:"moral panic"', 'intitle:panic television', 'intitle:panic game',
    'intitle:hearings video games', 'intitle:syndrome film television',
    'film "led to the passage"', 'television series "led to the passage"',
    'documentary "led to the release"', 'film "named after the film"',
    'episode "guidelines" seizures broadcast',
]
CAT_QUERIES = [
    "moral panic", "media influence", "media effects", "video game controversies",
    "television controversies", "film controversies", "film censorship",
    "censored episodes", "copycat crimes", "fandom", "works influencing legislation",
]
TITLE_WORDS = re.compile(r"\b(effect|impact|legacy|influence|phenomenon|craze|panic|controvers|syndrome|hearings|mania|fever|bump)\w*", re.I)
MEDIA_WORDS = re.compile(r"\b(film|movie|television|TV|series|sitcom|show|novel|book|game|documentary|song|episode|broadcast|actor|actress|character|programme|program|album|comic|cartoon|anime|radio|play)\b", re.I)


def discover():
    out = {}
    for q in SEARCHES:
        try:
            d = api({"action": "query", "list": "search", "srsearch": q, "srlimit": 50,
                     "srnamespace": 0, "srprop": "snippet"}, kind="search")
        except Exception as e:
            print("search fail", q, e); break
        for h in d.get("query", {}).get("search", []):
            t = h["title"]; snip = re.sub(r"<[^>]+>", "", h.get("snippet", ""))
            if TITLE_WORDS.search(t) and (MEDIA_WORDS.search(snip) or MEDIA_WORDS.search(t)):
                out.setdefault(t, {"via": [], "snippet": snip})["via"].append("search:" + q)
        print(q, len(out))
    cats = {}
    for q in CAT_QUERIES:
        try:
            d = api({"action": "query", "list": "search", "srsearch": q, "srlimit": 15,
                     "srnamespace": 14}, kind="search")
        except Exception as e:
            print("cat search fail", q, e); break
        for h in d.get("query", {}).get("search", []):
            cats.setdefault(h["title"], q)
    json.dump({"articles": out, "categories": cats}, open(os.path.join(HERE, "discover_raw.json"), "w"), indent=1)
    print("articles", len(out), "categories", len(cats))


def catmembers(cat, depth=0, seen=None):
    seen = seen if seen is not None else set()
    if cat in seen:
        return []
    seen.add(cat)
    res, cont = [], {}
    while True:
        p = {"action": "query", "list": "categorymembers", "cmtitle": cat, "cmlimit": 500,
             "cmtype": "page|subcat"}
        p.update(cont)
        d = api(p)
        for m in d.get("query", {}).get("categorymembers", []):
            if m["ns"] == 14 and depth > 0:
                res += catmembers(m["title"], depth - 1, seen)
            elif m["ns"] == 0:
                res.append((m["title"], cat))
        if "continue" in d:
            cont = {"cmcontinue": d["continue"]["cmcontinue"]}
        else:
            break
    return res


def cats(chosen_file):
    chosen = json.load(open(chosen_file))  # {category: depth}
    src = json.load(open(os.path.join(HERE, "sources.json"))) if os.path.exists(os.path.join(HERE, "sources.json")) else {}
    for c, depth in chosen.items():
        for t, via in catmembers(c, depth):
            src.setdefault(t, {"via": []})["via"].append("cat:" + via)
        print(c, len(src))
    json.dump(src, open(os.path.join(HERE, "sources.json"), "w"), indent=1)


# ---------------------------------------------------------------- fetch
class TextGrab(HTMLParser):
    """Collect paragraph and list-item text with link spans and current section."""
    SKIP = {"table", "style", "script", "sup", "figure", "figcaption", "math"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []  # (section, text, [(start, end, title)])
        self.section = "Lead"
        self.skip = 0
        self.cur = None
        self.links = []
        self.href = None
        self.hbuf = None
        self.divskip = 0

    def handle_starttag(self, tag, a):
        a = dict(a)
        cls = a.get("class", "") or ""
        if tag == "div":
            if self.divskip:
                self.divskip += 1
            elif any(k in cls for k in ("navbox", "reflist", "hatnote", "thumb", "sidebar", "metadata", "shortdescription", "mw-references", "infobox")):
                self.divskip = 1
            return
        if self.divskip:
            return
        if tag in self.SKIP:
            self.skip += 1
            return
        if self.skip:
            return
        if tag in ("h2", "h3"):
            self.hbuf = []
        elif tag in ("p", "li", "dd") and self.cur is None:
            self.cur, self.links = [], []
        elif tag == "a" and self.cur is not None:
            h = a.get("href", "")
            if h.startswith("/wiki/") and ":" not in h[6:]:
                self.href = (urllib.parse.unquote(h[6:].split("#")[0]).replace("_", " "), len("".join(self.cur)))
        elif tag == "br" and self.cur is not None:
            self.cur.append(" ")

    def handle_endtag(self, tag):
        if tag == "div":
            if self.divskip:
                self.divskip -= 1
            return
        if self.divskip:
            return
        if tag in self.SKIP:
            self.skip = max(0, self.skip - 1)
            return
        if self.skip:
            return
        if tag in ("h2", "h3") and self.hbuf is not None:
            self.section = re.sub(r"\s+", " ", "".join(self.hbuf)).strip()
            self.hbuf = None
        elif tag == "a" and self.href and self.cur is not None:
            t, s = self.href
            self.links.append((s, len("".join(self.cur)), t))
            self.href = None
        elif tag in ("p", "li", "dd") and self.cur is not None:
            txt = "".join(self.cur)
            if txt.strip():
                self.blocks.append((self.section, txt, self.links))
            self.cur, self.links = None, []

    def handle_data(self, d):
        if self.skip or self.divskip:
            return
        if self.hbuf is not None:
            self.hbuf.append(d)
        elif self.cur is not None:
            self.cur.append(d)


def fname(t):
    return os.path.join(PAGES, re.sub(r"[^A-Za-z0-9]+", "_", t)[:120] + ".json")


def fetch(limit=None):
    os.makedirs(PAGES, exist_ok=True)
    src = json.load(open(os.path.join(HERE, "sources.json")))
    n = 0
    for t in src:
        fn = fname(t)
        if os.path.exists(fn):
            continue
        try:
            d = api({"action": "parse", "page": t, "prop": "text|revid", "redirects": 1,
                     "disableeditsection": 1, "disablelimitreport": 1, "disabletoc": 1})
        except Exception as e:
            print("fetch fail", t, e)
            if "stopped" in str(e) or "other" in _stops():
                break
            continue
        if "parse" not in d:
            json.dump({"title": t, "missing": True}, open(fn, "w")); continue
        g = TextGrab(); g.feed(d["parse"]["text"])
        json.dump({"title": d["parse"]["title"], "asked": t, "revid": d["parse"].get("revid"),
                   "blocks": g.blocks}, open(fn, "w"))
        n += 1
        if n % 25 == 0:
            print("fetched", n)
        if limit and n >= limit:
            break
    print("fetched", n)


# ---------------------------------------------------------------- match
# Lexicon fixed before the first run. Institutional verbs, measured-behavior
# phrases, and lasting-mark objects. A sentence matches when it has a verb or
# behavior phrase AND a lasting-mark object word.
INST_VERBS = [
    r"bann(?:ed|ing)", r"prohibit(?:ed|s|ing)", r"outlaw(?:ed)", r"forb(?:ade|idden)",
    r"found(?:ed|ing)", r"establish(?:ed|ing|ment)", r"creat(?:ed|ion of)", r"renam(?:ed|ing)",
    r"named (?:after|for)", r"amend(?:ed|ment)", r"pass(?:ed|age)", r"enact(?:ed|ment)",
    r"adopt(?:ed|ion)", r"ruled", r"freed", r"releas(?:ed|e) from", r"exonerat(?:ed|ion)",
    r"overturn(?:ed)", r"vacat(?:ed)", r"ended", r"introduc(?:ed|tion of) (?:new )?(?:guidelines|rules|regulations|legislation|a law|a bill|laws)",
    r"issued (?:new )?(?:guidelines|rules|a ban|regulations)", r"(?:drew|drawn) up (?:guidelines|rules)",
    r"revis(?:ed|ion of) (?:its|the|their) (?:guidelines|rules|policy|policies|code)",
    r"chang(?:ed|e) (?:its|the|their) (?:policy|policies|rules|guidelines|law)",
    r"led to (?:the )?(?:creation|establishment|passage|formation|founding|introduction|adoption|enactment|ban|banning|release)",
    r"(?:resulted|culminat(?:ed|ing)) in (?:the )?(?:creation|establishment|passage|formation|founding|introduction|adoption|enactment|ban|release)",
    r"prompted (?:the )?(?:creation|establishment|passage|formation|founding|introduction|adoption|enactment|ban|release|congress|parliament|legislat)",
    r"in response to", r"inspired (?:the )?(?:creation|founding|formation|establishment|passage)",
    r"signed into law", r"legislat(?:ion|ure|ors?)", r"recalled", r"withdr(?:ew|awn)",
]
BEHAVIOR = [
    r"sales (?:fell|rose|dropped|declined|increased|plummeted|soared|jumped)",
    r"enrol(?:l)?ment", r"applications? (?:to|for|rose|increased|fell|surged|jumped)",
    r"registrations?", r"births?", r"birth rate", r"baby names?", r"(?:given )?names? (?:rose|increased|surged|became popular|grew in popularity|popularity)",
    r"donations?", r"measured", r"study (?:found|showed|concluded|estimated|suggested)",
    r"(?:studies|researchers|economists) (?:found|showed|concluded|estimated)",
    r"(?:per ?cent|%) (?:increase|decrease|rise|drop|decline|fall|reduction)",
    r"(?:increase|decrease|rise|drop|decline|fall|reduction) of \d+(?:\.\d+)? ?(?:%|per ?cent)",
    r"census", r"membership (?:rose|increased|grew|doubled|tripled)", r"participation (?:rose|increased|grew)",
    r"suicides? (?:rose|increased|rate)", r"recruit(?:ment|ing|s)",
]
MARK_OBJ = [
    r"law", r"laws", r"act", r"bill", r"statute", r"amendment", r"rule", r"rules", r"regulations?",
    r"standards?", r"guidelines?", r"code", r"policy", r"policies", r"agency", r"organi[sz]ation",
    r"foundation", r"charity", r"institute", r"institution", r"association", r"society", r"council",
    r"commission", r"board", r"authority", r"rating system", r"ratings? board", r"league", r"team",
    r"club", r"franchise", r"court", r"ruling", r"verdict", r"conviction", r"sentence", r"prison",
    r"ban", r"banned", r"prohibition", r"treaty", r"department", r"ministry", r"parliament", r"congress",
    r"senate", r"legislature", r"school", r"schools", r"university", r"military", r"navy", r"army",
    r"church", r"fatwa", r"museum", r"hospital", r"rate", r"rates", r"births?", r"enrol(?:l)?ment",
    r"census", r"registrations?", r"names?", r"donations?", r"species", r"protected", r"import",
    r"ordinance", r"decree", r"jury", r"juries", r"instructions?", r"broadcasters?", r"FCC", r"Ofcom",
    r"ESRB", r"BBFC", r"MPAA", r"NHS", r"NASA", r"FDA", r"EPA", r"UN", r"WHO",
]
CAUSE = [
    r"because of", r"due to", r"in response to", r"following", r"after (?:the|watching|seeing|reading|its|viewing)",
    r"inspired by", r"influenced by", r"prompted", r"led to", r"credited", r"attribut(?:ed|ing)",
    r"named (?:after|for)", r"as a result", r"result of", r"resulted in", r"spurred", r"sparked",
    r"triggered", r"caused", r"in the wake of", r"reaction to", r"partly", r"thanks to", r"helped",
    r"contributed", r"blamed", r"linked", r"cited",
]
RX_V = re.compile(r"\b(?:" + "|".join(INST_VERBS) + r")\b", re.I)
RX_B = re.compile(r"\b(?:" + "|".join(BEHAVIOR) + r")", re.I)
RX_O = re.compile(r"\b(?:" + "|".join(MARK_OBJ) + r")\b")  # case sensitive for acronyms
RX_O_CI = re.compile(r"\b(?:" + "|".join(m for m in MARK_OBJ if not m.isupper()) + r")\b", re.I)
RX_C = re.compile(r"\b(?:" + "|".join(CAUSE) + r")\b", re.I)
ABBR = re.compile(r"\b(?:U\.S|U\.K|Mr|Mrs|Ms|Dr|St|Jr|Sr|vs|No|Inc|Co|Ltd|Gen|Sen|Rep|Gov|Lt|Col|Capt|Prof|e\.g|i\.e|approx|ca|Jan|Feb|Mar|Apr|Aug|Sept?|Oct|Nov|Dec)\.$")
SKIP_SECTIONS = re.compile(r"^(See also|References|Notes|Further reading|External links|Bibliography|Sources|Citations|Footnotes)$", re.I)


def sentences(text):
    text = re.sub(r"\[\d+\]|\[citation needed\]|\[[a-z]\]", "", text)
    out, start = [], 0
    for m in re.finditer(r"[.!?][\"”’)]?\s+(?=[A-Z\"“(0-9])", text):
        cand = text[start:m.end()]
        if ABBR.search(text[max(0, m.start() - 6):m.start() + 1]):
            continue
        out.append((start, m.end()))
        start = m.end()
    if start < len(text):
        out.append((start, len(text)))
    return out


def match():
    rows = []
    articles = 0
    seen_titles = set()
    for fn in sorted(os.listdir(PAGES)):
        d = json.load(open(os.path.join(PAGES, fn)))
        if d.get("missing") or d["title"] in seen_titles:
            continue  # missing page, or a redirect to a page already read
        seen_titles.add(d["title"])
        articles += 1
        for sec, txt, links in d["blocks"]:
            if SKIP_SECTIONS.match(sec):
                continue
            for s, e in sentences(txt):
                sent = re.sub(r"\s+", " ", re.sub(r"\[\d+\]|\[citation needed\]", "", txt[s:e])).strip()
                if len(sent) < 30:
                    continue
                v = RX_V.findall(sent); b = RX_B.findall(sent)
                o = RX_O.findall(sent) + RX_O_CI.findall(sent)
                if not (v or b) or not o:
                    continue
                c = RX_C.findall(sent)
                lk = [t for (ls, le, t) in links if ls >= s and le <= e]
                yr = re.findall(r"\b(1[5-9]\d\d|20[0-2]\d)\b", sent)
                score = len(set(v)) + len(set(b)) + (1 if c else 0) + (1 if yr else 0)
                rows.append({"source_article": d["title"], "section": sec, "sentence": sent,
                             "verbs": sorted(set(x.lower() for x in v)), "behavior": sorted(set(x.lower() for x in b)),
                             "objects": sorted(set(x.lower() for x in o))[:8], "cause": sorted(set(x.lower() for x in c)),
                             "links": lk, "years": yr, "score": score, "revid": d.get("revid")})
    json.dump({"articles_read": articles, "rows": rows}, open(os.path.join(HERE, "candidates.json"), "w"), indent=1)
    print("articles", articles, "matched sentences", len(rows))


# ---------------------------------------------------------------- intros
def intros(titles_file):
    titles = json.load(open(titles_file))
    out = json.load(open(os.path.join(HERE, "intros.json"))) if os.path.exists(os.path.join(HERE, "intros.json")) else {}
    todo = [t for t in titles if t not in out]
    for i in range(0, len(todo), 20):
        chunk = todo[i:i + 20]
        d = api({"action": "query", "prop": "extracts", "exintro": 1, "explaintext": 1,
                 "exlimit": 20, "titles": "|".join(chunk), "redirects": 1})
        redir = {r["from"]: r["to"] for r in d.get("query", {}).get("redirects", [])}
        norm = {r["from"]: r["to"] for r in d.get("query", {}).get("normalized", [])}
        pages = {p["title"]: p.get("extract", "") for p in d.get("query", {}).get("pages", [])}
        for t in chunk:
            tt = redir.get(norm.get(t, t), norm.get(t, t))
            out[t] = {"resolved": tt, "intro": pages.get(tt, "")[:1500]}
    json.dump(out, open(os.path.join(HERE, "intros.json"), "w"), indent=1)
    print("intros", len(out))


# ---------------------------------------------------------------- finalize
def finalize():
    cand = json.load(open(os.path.join(HERE, "candidates.json")))
    rev = json.load(open(os.path.join(HERE, "review.json")))
    kept = []
    for k in rev["kept"]:
        item = {"gen": "G3"}
        item.update(k)
        item.setdefault("cause_label", "reason")
        item["source_url"] = "https://en.wikipedia.org/wiki/" + urllib.parse.quote(item["source_article"].replace(" ", "_"))
        kept.append(item)
    out = {"generator": "G3", "articles_read": cand["articles_read"],
           "sentences_matched": len(cand["rows"]), "kept": kept,
           "rejected_counts": rev["rejected_counts"]}
    json.dump(out, open(os.path.join(HERE, "g3.json"), "w"), indent=1, ensure_ascii=False)
    print("kept", len(kept))


# ---------------------------------------------------------------- summaries
REST = "https://en.wikipedia.org/api/rest_v1/page/summary/"
_last_rest = [0.0]


def summaries(titles_file):
    """Intro text for stone and mark articles via the REST summary endpoint (<= 1 req/s)."""
    titles = json.load(open(titles_file))
    path = os.path.join(HERE, "summaries.json")
    out = json.load(open(path)) if os.path.exists(path) else {}
    for t in titles:
        if t in out:
            continue
        if "rest" in _stops():
            break
        wait = 1.0 - (time.time() - _last_rest[0])
        if wait > 0:
            time.sleep(wait)
        url = REST + urllib.parse.quote(t.replace(" ", "_"), safe="")
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        _last_rest[0] = time.time()
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                d = json.loads(r.read().decode("utf-8"))
            out[t] = {"title": d.get("title"), "description": d.get("description"), "extract": d.get("extract")}
        except urllib.error.HTTPError as e:
            if e.code in (403, 429) or e.code >= 500:
                _stop("rest", "HTTP %d" % e.code); break
            out[t] = {"error": e.code}
    json.dump(out, open(path, "w"), indent=1, ensure_ascii=False)
    print("summaries", len(out))


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "discover": discover()
    elif cmd == "cats": cats(sys.argv[2])
    elif cmd == "fetch": fetch(int(sys.argv[2]) if len(sys.argv) > 2 else None)
    elif cmd == "match": match()
    elif cmd == "intros": intros(sys.argv[2])
    elif cmd == "finalize": finalize()
    elif cmd == "summaries": summaries(sys.argv[2])
