"""G4 BACKLINKS: find institutions whose own English Wikipedia article names a cultural work as the reason they exist,
are named, or changed.

Phases (cached under g4_cache/ so a rerun resumes):
  select : top 700 works by sitelinks from g2_stones.json, balanced across classes (round robin by rank), plus any film
           whose Wikidata genre or instance is documentary film (checked with wbgetentities, 50 ids a request)
  bl     : English Wikipedia backlinks per work (generator=backlinks, ns 0, one redirect level, 500 max) with
           pageprops (wikibase_item, disambiguation, short description) and info (redirect flag) in the same request
  wd     : Wikidata wbgetentities (claims) for backlink pages that survive a cheap title and short-description prefilter
           (drops lists, years, disambiguation, people, and other works); then English labels for every P31 class seen
  type   : keep pages whose P31 class label matches the institutional allow list and none matches the deny list
  text   : wikitext of typed pages, 50 titles a request; keep only sentences that link to (or name) a selected work
  match  : sentence must link the page to the work AND carry cause language; every candidate gets a strict read
           recorded in REVIEW below; everything not kept gets a rejection reason
Honest UA on every request, at most 1 request a second per endpoint, maxlag=5; any 403/429/5xx stops that endpoint for
the day with no retry."""
import json, re, sys, time, os, html, threading, urllib.parse, urllib.request, urllib.error
from collections import Counter, defaultdict

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
HERE = os.path.dirname(os.path.abspath(__file__))
P = lambda f: os.path.join(HERE, f)
C = lambda f: os.path.join(HERE, "g4_cache", f)
os.makedirs(P("g4_cache"), exist_ok=True)
WPAPI = "https://en.wikipedia.org/w/api.php"
WDAPI = "https://www.wikidata.org/w/api.php"
STOPPED = {}
WD_DEADLINE = float(os.environ.get("G4_WD_DEADLINE", "9e18"))
TEXT_DEADLINE = float(os.environ.get("G4_TEXT_DEADLINE", "9e18"))
MAX_TIER2 = int(os.environ.get("G4_MAX_TIER2", "1"))
_last = defaultdict(float)
_lock = defaultdict(threading.Lock)


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, file=sys.stderr, flush=True)


def api(endpoint, params, post=False):
    """One polite request. Returns parsed JSON or None. 403/429/5xx stop the endpoint for the day."""
    if endpoint in STOPPED: return None
    base = WPAPI if endpoint == "wikipedia" else WDAPI
    params = {**params, "format": "json", "formatversion": 2, "maxlag": 5}
    for attempt in range(4):
        with _lock[endpoint]:
            w = 1.05 - (time.time() - _last[endpoint])
            if w > 0: time.sleep(w)
            data = urllib.parse.urlencode(params).encode() if post else None
            url = base if post else base + "?" + urllib.parse.urlencode(params)
            req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, "Accept": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    retry_after = r.headers.get("Retry-After")
                    d = json.load(r)
            except urllib.error.HTTPError as e:
                _last[endpoint] = time.time()
                if e.code in (403, 429) or e.code >= 500:
                    STOPPED[endpoint] = f"HTTP {e.code}"; log(f"STOP {endpoint}: HTTP {e.code}"); return None
                log(f"{endpoint}: HTTP {e.code}"); return None
            except Exception as e:
                _last[endpoint] = time.time(); log(f"{endpoint}: {e}")
                if attempt < 1: continue
                return None
            _last[endpoint] = time.time()
        if isinstance(d, dict) and d.get("error", {}).get("code") == "maxlag":
            # served with HTTP 200: wait the advertised time, as the maxlag manual asks, then try again
            time.sleep(max(5, int(retry_after or 5))); continue
        return d
    return None


# ---------------------------------------------------------------- select
def phase_select():
    if os.path.exists(C("works.json")): return json.load(open(C("works.json")))
    stones = json.load(open(P("g2_stones.json")))
    by = defaultdict(list)
    for s in sorted(stones, key=lambda x: -x["sl"]): by[s["kind"]].append(s)
    picked, seen, r = [], set(), 0
    while len(picked) < 700 and any(r < len(v) for v in by.values()):
        for k in sorted(by):
            if r < len(by[k]) and len(picked) < 700:
                picked.append(by[k][r]); seen.add(by[k][r]["qid"])
        r += 1
    # documentaries: any film in the stone list whose instance or genre is documentary film
    films = [s for s in stones if s["kind"] == "film"]
    docs = []
    for i in range(0, len(films), 50):
        ids = [s["qid"] for s in films[i:i + 50]]
        d = api("wikidata", {"action": "wbgetentities", "ids": "|".join(ids), "props": "claims"})
        if not d: break
        for q, e in d.get("entities", {}).items():
            cl = e.get("claims", {})
            vals = {c["mainsnak"].get("datavalue", {}).get("value", {}).get("id") for p in ("P31", "P136") for c in cl.get(p, [])}
            if vals & {"Q93204", "Q1395954", "Q1366112"}: docs.append(q)
    for s in films:
        if s["qid"] in docs and s["qid"] not in seen:
            picked.append(s); seen.add(s["qid"])
    for s in picked: s["is_documentary"] = s["qid"] in docs
    json.dump(picked, open(C("works.json"), "w"), indent=0)
    log(f"selected {len(picked)} works, {len(docs)} documentaries in the stone list")
    return picked


# ---------------------------------------------------------------- prefilter (cheap, before any Wikidata call)
DROP_TITLE = re.compile(r"^(List|Lists|Index|Outline|Timeline|Glossary|Bibliography|Discography|Filmography) of|^\d{1,4}s? in |"
                        r"\((?:[^)]*\s)?(film|album|song|single|series|novel|book|game|character|episode|soundtrack|band|"
                        r"musician|actor|actress|singer|rapper|comics|comic|manga|anime|play|musical|miniseries|EP|"
                        r"short story|novella|poem|painting|TV program|TV programme|franchise|mixtape|opera|ballet|"
                        r"disambiguation|season \d+|season)\)$|^\d{4}$|^\d{4} (in|at|FIFA|Summer|Winter)|"
                        r"\(season \d+\)|season \d+\)?$| \(\d{4}\)$")
ORGWORDS = re.compile(r"\b(company|corporation|studio|developer|publisher|organi[sz]ation|agency|foundation|charity|museum|"
                      r"school|university|college|team|club|law|act|statute|award|prize|festival|convention|park|street|"
                      r"road|town|city|village|memorial|statue|monument|case|court|league|society|association|institute|"
                      r"program|programme|campaign|policy|regulation|standard|retailer|chain|ministry|department|"
                      r"commission|government|legislation|settlement|community|county|municipality|event|tournament|"
                      r"theme park|restaurant|brand|manufacturer|network|channel|broadcaster|label|nonprofit|non-profit)\b", re.I)
PERSON_OR_WORK = re.compile(r"\b(born|actor|actress|singer|rapper|musician|songwriter|composer|writer|author|novelist|poet|"
                            r"director|filmmaker|producer|comedian|presenter|host|journalist|politician|footballer|player|"
                            r"wrestler|artist|painter|cartoonist|illustrator|animator|screenwriter|model|dancer|guitarist|"
                            r"drummer|bassist|pianist|DJ|YouTuber|personality|businessman|businesswoman|entrepreneur|"
                            r"character|fictional|film|album|song|single|series|sitcom|episode|novel|book|video game|game|"
                            r"soundtrack|comic|comics|manga|anime|musical|play|miniseries|short story|EP|mixtape|franchise|"
                            r"band|duo|trio|rapper|group|poem|painting|opera|ballet|television program|TV program|"
                            r"disambiguation|topics referred to|list|year|decade|century|surname|given name|"
                            r"species|genus|family of)\b|\(\d{3,4}\s*[–-]\s*\d{0,4}\)|\b\d{4}\s*[–-]\s*\d{4}\b|"
                            r"^(American|British|English|Canadian|Australian|Japanese|French|German|Irish|Scottish|"
                            r"Welsh|Indian|Korean|South Korean|Italian|Spanish|Mexican|Swedish|Dutch)\s+[a-z ]*(er|ist|or|ess|an)$", re.I)


def keep_for_wd(title, sd, disamb):
    if disamb: return False
    if DROP_TITLE.search(title): return False
    if sd:
        if ORGWORDS.search(sd) and not re.search(r"\b(born|\d{4}\s*[–-]\s*\d{4})\b|\(\d{4}", sd): return True
        if PERSON_OR_WORK.search(sd): return False
    return True


# ---------------------------------------------------------------- class labels: the typing rule
ALLOW = re.compile(r"organi[sz]ation|nonprofit|non-profit|charit|foundation|agency|authority|ministry|department|"
                   r"commission|bureau|council|government|legislat|\blaw\b|\bact\b|act of|statute|\bbill\b|ordinance|"
                   r"regulation|directive|standard|policy|program|initiative|campaign|sports team|\bteam\b|\bclub\b|"
                   r"league|memorial|statue|monument|sculpture|street|\broad\b|avenue|boulevard|square|plaza|bridge|"
                   r"\bpark\b|human settlement|\bcity\b|\btown\b|village|municipality|census-designated place|"
                   r"unincorporated community|neighbo(u)?rhood|hamlet|borough|company|business|enterprise|corporation|"
                   r"conglomerate|retail|chain|court case|legal case|case law|court decision|judgment|ruling|"
                   r"\baward\b|\bprize\b|school|college|university|academy|museum|festival|convention|recurring event|"
                   r"event series|annual event|tournament|competition|holiday|observance|society|association|"
                   r"institute|\btrust\b|\bfund\b|\bunion\b|treaty|amendment|resolution|\brating system|certification|"
                   r"protected area|nature reserve|national park|wildlife|sanctuary|zoo|theme park|amusement park|"
                   r"\bcode\b|guideline|protocol|executive order|referendum|ban\b|sport|military unit|squadron|"
                   r"political party|club|mascot|brand|restaurant|hotel|building|structure|venue|stadium|arena|developer|"
                   r"publisher|studio|publishing house|educational institution|higher education|station|network|"
                   r"channel|record label|distributor|casino|civil parish|township|burgh|commune|area of London|"
                   r"county|district|prefecture|cinema|theat(er|re)|library|hospital|airline|spacecraft|orbiter|"
                   r"\bship\b|locomotive|lawsuit|litigation|\btrial\b|sport", re.I)
DENY = re.compile(r"^(human|Wikimedia .*|fictional .*|.* character|film|.* film|television series|.* television series|"
                  r"episode|television episode|.* episode|album|studio album|.* album|song|single|.* single|literary work|"
                  r"novel|book|video game|.* video game|musical group|band|.* band|year|calendar year|decade|"
                  r".* season|television program|.* series|written work|comic|.* comic|comic book|manga series|"
                  r"musical work|musical composition|composition|play|musical|soundtrack album|taxon|family name|"
                  r"given name|film series|media franchise|franchise|.* franchise|television film|short film|"
                  r"animated film|feature film|anime film|music video|extended play|mixtape|compilation album|"
                  r"poem|painting|work of art|creative work|version, edition or translation|"
                  r"television season|award ceremony|.* award ceremony|sports season|.* sports season|.* universe|"
                  r".*fictional.*|form of .*|area of law|art movement|.* genre|genre|concept|.* concept|"
                  r"field of study|academic discipline|type of policy|political ideology)$", re.I)


HARD_DENY = re.compile(r"^(human|Wikimedia .*|film|.* film|television series|.* television series|episode|"
                       r"television series episode|album|studio album|song|single|literary work|novel|video game|"
                       r"musical group|band|.* band|year|calendar year|decade|television program|written work|"
                       r"family name|given name|taxon|television film|short film|animated film|feature film)$", re.I)
PLACE = re.compile(r"settlement|city|town|village|municipality|census-designated|unincorporated|neighbo|hamlet|borough|"
                   r"civil parish|burgh|commune|area of London|county|district|prefecture", re.I)
COMPANY = re.compile(r"company|business|enterprise|corporation|conglomerate|brand|developer|publisher|studio|"
                     r"publishing house|station|network|channel|record label|distributor|retail|chain|casino|hotel|"
                     r"restaurant|airline", re.I)


MASCOT = re.compile(r"^(mascot character|advertising character|mascot|public service announcement|advertising campaign|"
                    r"public awareness campaign)$", re.I)  # public-service mascots such as Smokey Bear


def classify(p31, labels):
    labs = [labels.get(q, "") for q in p31]
    if any(HARD_DENY.match(l) for l in labs if l): return None
    hits = [l for l in labs if l and ((ALLOW.search(l) and not DENY.match(l)) or MASCOT.match(l))]
    return hits[0] if hits else None


def tier(label):
    return 2 if PLACE.search(label) else 1 if COMPANY.search(label) else 0


# ---------------------------------------------------------------- wikitext helpers
def strip_templates(wt):
    wt = re.sub(r"\{\{\s*(?:ill|interlanguage link|nowrap|nobr|lang\|[a-z-]+|small|em|vr|abbr|' ?)\|([^{}|]*)[^{}]*\}\}", r"\1", wt, flags=re.I)
    for _ in range(12):
        new = re.sub(r"\{\{[^{}]*\}\}", "", wt)
        if new == wt: break
        wt = new
    return wt


def clean(wt, keep_italics=False):
    wt = re.sub(r"<!--.*?-->", "", wt, flags=re.S)
    wt = re.sub(r"<ref[^>/]*/>", "", wt); wt = re.sub(r"<ref[^>]*>.*?</ref>", "", wt, flags=re.S)
    wt = strip_templates(wt)
    wt = re.sub(r"\{\|.*?\|\}", "", wt, flags=re.S)
    wt = re.sub(r"\[\[(?:File|Image):[^\[\]]*(?:\[\[[^\]]*\]\][^\[\]]*)*\]\]", "", wt, flags=re.I)
    wt = re.sub(r"<[^>]+>", "", wt)
    if not keep_italics: wt = re.sub(r"'{2,}", "", wt)
    wt = re.sub(r"\[https?://\S+\s([^\]]*)\]", r"\1", wt)
    return wt


def sentences(text):
    text = re.sub(r"^[*#:;]+\s*", "", text, flags=re.M)
    text = re.sub(r"\s+", " ", text)
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+(?=[A-Z\[\"])", text) if len(s.strip()) > 25]


def norm(t):
    t = urllib.parse.unquote(t.split("#")[0]).replace("_", " ").strip()
    return (t[:1].upper() + t[1:]) if t else t


def links(s): return [norm(l.split("|")[0]) for l in re.findall(r"\[\[([^\]]+)\]\]", s) if ":" not in l.split("|")[0]]
def plain(s): return re.sub(r"\[\[([^\]|]+\|)?([^\]]+)\]\]", r"\2", s).strip()


def split_sections(wt):
    out = [("(lead)", wt.split("\n==")[0])]
    parts = re.split(r"^(={2,6})\s*(.*?)\s*\1\s*$", wt, flags=re.M)
    for i in range(1, len(parts) - 2, 3): out.append((parts[i + 1], parts[i + 2]))
    return out


# ---------------------------------------------------------------- the run
class Run:
    def __init__(self, works):
        self.works = works
        self.bl = json.load(open(C("bl.json"))) if os.path.exists(C("bl.json")) else {}
        self.wd = json.load(open(C("wd.json"))) if os.path.exists(C("wd.json")) else {}
        self.labels = json.load(open(C("labels.json"))) if os.path.exists(C("labels.json")) else {}
        self.text = json.load(open(C("text.json"))) if os.path.exists(C("text.json")) else {}
        self.text2 = json.load(open(C("text2.json"))) if os.path.exists(C("text2.json")) else {}
        self.bl_done = False
        self.wd_done = False

    def save(self, which=("bl", "wd", "labels", "text", "text2")):
        for name, obj in (("bl", self.bl), ("wd", self.wd), ("labels", self.labels), ("text", self.text), ("text2", self.text2)):
            if name not in which: continue
            tmp = C(name + ".json.tmp"); json.dump(obj, open(tmp, "w")); os.replace(tmp, C(name + ".json"))

    def backlinks(self, title):
        d = api("wikipedia", {"action": "query", "generator": "backlinks", "gbltitle": title, "gblnamespace": 0,
                              "gbllimit": 500, "gblredirect": 1, "prop": "pageprops|info",
                              "ppprop": "wikibase_item|disambiguation|wikibase-shortdesc", "redirects": 0})
        if d is None: return None
        pages, redirs = [], []
        for pg in d.get("query", {}).get("pages", []):
            if pg.get("ns") != 0: continue
            if pg.get("redirect"): redirs.append(pg["title"]); continue
            pp = pg.get("pageprops", {})
            pages.append([pg["title"], pp.get("wikibase_item"), pp.get("wikibase-shortdesc", ""), "disambiguation" in pp])
        return {"pages": pages, "redirects": redirs, "more": "continue" in d}

    def t_backlinks(self):
        for i, w in enumerate(self.works):
            if w["title"] in self.bl: continue
            r = self.backlinks(w["title"])
            if r is None:
                if "wikipedia" in STOPPED: break
                continue
            self.bl[w["title"]] = r
            if i % 25 == 0: log(f"backlinks {len(self.bl)}/{len(self.works)}")
        self.bl_done = True

    def wd_queue(self):
        q = {}
        inst = re.compile(r"organi[sz]ation|foundation|agency|\bact\b|\blaw\b|award|prize|museum|school|memorial|"
                          r"statue|team|club|festival|program|campaign|policy|court|case|street|road|league|society|"
                          r"association|mascot|charity|nonprofit|regulation|standard|sport|monument|day\b", re.I)
        for w, r in list(self.bl.items()):
            for t, qid, sd, dis in r["pages"]:
                if qid and qid not in self.wd and keep_for_wd(t, sd, dis):
                    q[qid] = min(q.get(qid, 9), 0 if inst.search(sd or "") else 1 if not sd else 2)
        return sorted(q, key=lambda x: (q[x], x))

    def t_wikidata(self):
        DATEP = ("P571", "P1619", "P580", "P585", "P577", "P7588", "P5444", "P3999")
        while True:
            if time.time() > WD_DEADLINE: log("wikidata deadline reached"); break
            q = self.wd_queue()
            need_lab = sorted({c for e in self.wd.values() for c in e["p31"] if c not in self.labels})
            if len(need_lab) >= 50 or (need_lab and (not q or getattr(self, "_lab_tick", 0) % 10 == 9) and self.bl_done):
                d = api("wikidata", {"action": "wbgetentities", "ids": "|".join(need_lab[:50]), "props": "labels", "languages": "en"})
                if d is None and "wikidata" in STOPPED: break
                for cq in need_lab[:50]:
                    self.labels[cq] = (d or {}).get("entities", {}).get(cq, {}).get("labels", {}).get("en", {}).get("value", "")
                continue
            if not q:
                if self.bl_done: break
                time.sleep(3); continue
            if len(q) < 50 and not self.bl_done:
                time.sleep(3); continue
            batch = q[:50]
            self._lab_tick = getattr(self, "_lab_tick", 0) + 1
            d = api("wikidata", {"action": "wbgetentities", "ids": "|".join(batch), "props": "claims"})
            if d is None:
                if "wikidata" in STOPPED: break
                for x in batch: self.wd[x] = {"p31": [], "dates": {}, "err": 1}
                continue
            for x in batch:
                e = d.get("entities", {}).get(x, {})
                cl = e.get("claims", {})
                p31 = [c["mainsnak"].get("datavalue", {}).get("value", {}).get("id") for c in cl.get("P31", [])]
                dates = {}
                for p in DATEP:
                    for c in cl.get(p, []):
                        v = c["mainsnak"].get("datavalue", {}).get("value", {})
                        if isinstance(v, dict) and v.get("time"): dates[p] = v["time"]; break
                self.wd[x] = {"p31": [c for c in p31 if c], "dates": dates}
            if len(self.wd) % 1000 < 50: log(f"wikidata {len(self.wd)} entities, queue {len(q)}"); self.save(("wd", "labels"))
        need_lab = sorted({c for e in self.wd.values() for c in e["p31"] if c not in self.labels})
        for i in range(0, len(need_lab), 50):
            d = api("wikidata", {"action": "wbgetentities", "ids": "|".join(need_lab[i:i + 50]), "props": "labels", "languages": "en"})
            if d is None: break
            for cq in need_lab[i:i + 50]:
                self.labels[cq] = d.get("entities", {}).get(cq, {}).get("labels", {}).get("en", {}).get("value", "")
        self.save(("wd", "labels")); log(f"wikidata done: {len(self.wd)} entities, {len(self.wd_queue())} left unqueried")
        self.wd_done = True

    def typed(self):
        out = {}
        for w, r in self.bl.items():
            for t, qid, sd, dis in r["pages"]:
                e = self.wd.get(qid) if qid else None
                if not e: continue
                c = classify(e["p31"], self.labels)
                if c: out.setdefault(t, {"qid": qid, "class": c, "works": []})["works"].append(w)
        return out

    def t_text(self):
        titleset = {}
        for w in self.works:
            r = self.bl.get(w["title"], {})
            for t in [w["title"]] + r.get("redirects", []): titleset[norm(t)] = w["title"]
        n = 0
        while time.time() < TEXT_DEADLINE:
            typed = self.typed()
            todo = sorted([t for t in typed if t not in self.text], key=lambda t: (tier(typed[t]["class"]), t))
            if not todo:
                if self.wd_done: break
                time.sleep(5); continue
            if self.wd_done is False and tier(typed[todo[0]]["class"]) == 2 and len(todo) < 50:
                time.sleep(5); continue
            batch = todo[:50]
            params = {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main", "titles": "|".join(batch)}
            got = {}
            while True:
                d = api("wikipedia", params, post=True)
                if d is None: break
                for pg in d.get("query", {}).get("pages", []):
                    if "revisions" in pg: got[pg["title"]] = pg["revisions"][0]["slots"]["main"]["content"]
                if "continue" in d: params = {**params, **d["continue"]}
                else: break
            if d is None and "wikipedia" in STOPPED: break
            for t in batch:
                wt = got.get(t)
                if wt is None: self.text[t] = []; continue
                hits = []
                for head, body in split_sections(wt):
                    for s in sentences(clean(body)):
                        ls = [titleset[l] for l in links(s) if l in titleset]
                        if ls: hits.append([head, s, sorted(set(ls))])
                self.text[t] = hits
            n += 1
            if n % 10 == 0: log(f"text {len(self.text)} fetched, {len(todo) - 50} typed waiting"); self.save(("text",))
        self.save(("text",)); log(f"text done {len(self.text)}")


    def t_text2(self):
        """Second pass: sentences that link the work OR name it (italic title, or a multiword title in plain text)."""
        titleset = {}
        for w in self.works:
            r = self.bl.get(w["title"], {})
            for t in [w["title"]] + r.get("redirects", []): titleset[norm(t)] = w["title"]
        typed = self.typed()
        todo = sorted([t for t in typed if t not in self.text2 and tier(typed[t]["class"]) <= MAX_TIER2],
                      key=lambda t: (tier(typed[t]["class"]), t))
        log(f"text2: {len(todo)} pages")
        for i in range(0, len(todo), 50):
            if time.time() > TEXT_DEADLINE: log("text2 deadline"); break
            batch = todo[i:i + 50]
            params = {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main", "titles": "|".join(batch)}
            got = {}
            while True:
                d = api("wikipedia", params, post=True)
                if d is None: break
                for pg in d.get("query", {}).get("pages", []):
                    if "revisions" in pg: got[pg["title"]] = pg["revisions"][0]["slots"]["main"]["content"]
                if "continue" in d: params = {**params, **d["continue"]}
                else: break
            if d is None and "wikipedia" in STOPPED: break
            for t in batch:
                wt = got.get(t)
                if wt is None: self.text2[t] = []; continue
                pats = []
                for w in typed[t]["works"]:
                    base = re.sub(r" \(.*\)$", "", w)
                    if len(base) < 3: continue
                    p = r"''" + re.escape(base) + r"''"
                    if " " in base and len(base) >= 8: p += r"|\b" + re.escape(base) + r"\b"
                    pats.append((w, re.compile(p)))
                hits = []
                for head, body in split_sections(wt):
                    for sent in sentences(clean(body, keep_italics=True)):
                        ls = {titleset[l] for l in links(sent) if l in titleset}
                        ls |= {w for w, p in pats if p.search(sent)}
                        if ls: hits.append([head, re.sub(r"'{2,}", "", sent), sorted(ls)])
                self.text2[t] = hits
            if (i // 50) % 10 == 0: log(f"text2 {len(self.text2)}/{len(todo)}"); self.save(("text2",))
        self.save(("text2",)); log(f"text2 done {len(self.text2)}")


CAUSE = re.compile(r"\b(named (?:after|for)|takes? (?:its|their) name|took (?:its|their) name|derives? (?:its|their) name|"
                   r"name (?:comes|came|was taken|is taken|derives|derived|is derived|was derived|was inspired|is a reference|"
                   r"refers)|renamed|re-named|changed (?:its|their|the) name|in response to|response to|in reaction to|"
                   r"reaction to|inspired by|was inspired|were inspired|inspiration|prompted|led to|leading to|lead to|"
                   r"as a result of|resulted in|result of|following the (?:release|broadcast|airing|publication|success|"
                   r"popularity|premiere|screening)|after (?:the )?(?:release|broadcast|airing|publication|watching|seeing|"
                   r"reading|viewing|premiere|screening|success)|after (?:he|she|they|the founders?) (?:saw|watched|read)|"
                   r"because of|due to|spurred|sparked|influenced by|motivated|catalyst|credited (?:with|as)|"
                   r"in honou?r of|dedicated to|commemorat\w*|founded (?:after|in response|following|because)|"
                   r"established (?:after|in response|following|because)|created (?:after|in response|following|because)|"
                   r"banned|\bban\b|prohibit\w*|outlaw\w*|legislation|ruled|ruling|lawsuit|sued|"
                   r"policy|stopped|ended|discontinued|ceased|pulled|withdrew|removed|tribute|homage|in the wake of|"
                   r"galvaniz\w*|spawned|thanks to|popularity of|success of|needed a new|need for a new|"
                   r"after the (?:film|movie|book|novel|series|show|documentary|song|game|episode|poster)|"
                   r"because of the (?:film|movie|book|novel|series|show|documentary))\b", re.I)


def phase_match(run):
    typed = run.typed()
    works = {w["title"]: w for w in run.works}
    cands, counts = [], Counter()
    for page in set(run.text) | set(run.text2):
        hits = run.text2[page] if page in run.text2 else run.text[page]
        info = typed.get(page)
        if not info: continue
        for head, s, ws in hits:
            for w in ws:
                if w not in info["works"]: continue
                m = CAUSE.search(plain(s))
                if not m and re.search(r"statue|sculpture|monument|memorial|plaque|mural", info["class"], re.I):
                    m = re.search(r"\b(based on|depict\w*|honou?rs?)\b", plain(s), re.I)
                if not m: counts["no_cause_language"] += 1; continue
                cands.append({"stone": w, "page": page, "class": info["class"], "qid": info["qid"], "section": head,
                              "sentence": plain(s), "cue": m.group(0)})
    return cands, counts


if __name__ == "__main__":
    works = phase_select()
    run = Run(works)
    if "fetch" in sys.argv:
        ta = threading.Thread(target=run.t_backlinks); tb = threading.Thread(target=run.t_wikidata)
        ta.start(); tb.start(); ta.join(); run.save(("bl",)); log("backlinks done")
        run.t_text(); tb.join(); run.save(); log("fetch done", dict(STOPPED))
        json.dump(dict(STOPPED), open(C("stopped.json"), "w"))
    if "text2" in sys.argv:
        run.t_text2()
    if "match" in sys.argv:
        cands, counts = phase_match(run)
        json.dump(cands, open(C("cands.json"), "w"), indent=0)
        log(f"candidates {len(cands)}", dict(counts))


# ---------------------------------------------------------------- strict read: verdicts on candidates (filled after the run)
# key: (stone, page) -> dict(keep, mark, mark_kind, reason or notes, disputed, mark_date override)
K = lambda mark, kind, notes="", **kw: dict(keep=True, mark=mark, mark_kind=kind, notes=notes, **kw)
R = lambda reason: dict(keep=False, reason=reason)
REVIEW = {
    ("Born This Way (album)", "Born This Way Foundation"): K("Born This Way Foundation (name)", "organization name",
        "Lady Gaga's foundation takes its name from the 2011 album and its title song."),
    ("The Raven", "Baltimore Ravens"): K("Baltimore Ravens team name", "team name",
        "Team-name section: the name was inspired by Poe's poem.", mark_date="1996", mark_date_source="wikidata P571"),
    ("Bambi", "Bambi Award"): K("Bambi Award (name)", "award name",
        "Article hedges: attributed via Marika Rokk's daughter, and credits either Salten's book or the 1942 film.",
        disputed=True),
    ("Nineteen Eighty-Four", "Big Brother Awards"): K("Big Brother Awards (name)", "award name",
        "Privacy-invasion anti-awards named after Orwell's Big Brother."),
    ("The Little Prince", "B612 Foundation"): K("B612 Foundation (name)", "organization name",
        "Asteroid-defense nonprofit named for the Little Prince's home asteroid."),
    ("Doom (1993 video game)", "Entertainment Software Rating Board"): K("Entertainment Software Rating Board", "rating body",
        "ESRB set up in 1994 in response to the 1993 hearings that followed Mortal Kombat, Night Trap, and Doom; Doom is one of three named titles."),
    ("The Dark Side of the Moon", "Canada Cup"): K("Canada Cup trophy design", "trophy design",
        "The trophy's designer cited the album cover as her inspiration.", mark_date="1976", mark_date_source="first Canada Cup, 1976"),
    ("Elon Musk salute controversy", "Everyone Hates Elon"): K("Everyone Hates Elon (campaign group)", "organization",
        "Formed in early 2025 partly in response to the salute; one of several stated reasons. Stone is a news event the stone list classes as a meme.",
        mark_date="2025", mark_date_source="sentence"),
    ("Uncle Tom's Cabin", "Fugitive Slave Act of 1850"): R("reversed_direction"),
    ("Saludos Amigos", "Good Neighbor policy"): R("reversed_direction"),
    ("Inside Out", "Cranium Command"): R("reversed_direction"),
    ("Half-Life 2", "Deception Pass Bridge"): R("reversed_direction"),
    ("Moby-Dick", "Ann Alexander (ship)"): R("reversed_direction"),
    ("Red Dead Redemption 2", "Butch Cassidy's Wild Bunch"): R("reversed_direction"),
    ("Slumdog Millionaire", "Cinema of India"): R("reversed_direction"),
    ("Universal Declaration of Human Rights", "European Convention on Human Rights"): R("stone_is_legal_instrument_not_culture"),
    ("Kalevala", "Finnish coastal defence ship Ilmarinen"): R("named_vessel_outside_institution_list"),
    ("Shahnameh", "Alvand-class frigate"): R("named_vessel_outside_institution_list"),
    ("Harry Potter and the Goblet of Fire", "GWR 4900 Class 5972 Olton Hall"): R("temporary_promotion"),
    ("Master of Puppets", "Download Festival"): R("one_time_event"),
    ("Grass Mud Horse", "China Digital Times"): R("mark_date_unknown"),
    ("Finding Nemo", "Epcot"): R("same_owner_franchise_extension"),
    ("Moana (2016 film)", "Epcot"): R("same_owner_franchise_extension"),
    ("Ratatouille (film)", "Epcot"): R("same_owner_franchise_extension"),
    ("Inside Out", "Disney California Adventure"): R("same_owner_franchise_extension"),
    ("Toy Story (franchise)", "Disney's Hollywood Studios"): R("same_owner_franchise_extension"),
    ("Toy Story", "Animation"): R("not_an_institution"),
    ("One Hundred Years of Solitude", "Macondo Writers Workshop"): K("Macondo Writers Workshop (name)", "organization name",
        "Sandra Cisneros founded the workshop in 1995 and named it after the novel's town."),
    ("Braveheart", "Liberty University"): K("Falkirk Center name (now Standing for Freedom Center)", "organization name",
        "Name derived in part from Falwell's affinity for Braveheart and the Battle of Falkirk it depicts, plus a Falwell-Kirk portmanteau; one of several sources of the name.",
        mark_date="2019-11", mark_date_source="article: Liberty and Kirk launched the think tank in November 2019"),
    ("Angry Birds (video game)", "Mighty Eagle"): K("Mighty Eagle (NASA robotic lander) name", "vehicle name",
        "NASA Marshall test lander named after the Angry Birds character. Article gives no naming date; design began late 2009, integration finished January 2011.",
        mark_date="2011-01", mark_date_source="article: vehicle integration completed January 2011"),
    ("Cinderella (1950 film)", "Magic Kingdom"): R("same_owner_franchise_extension"),
    ("Paw Patrol", "Movie Park Germany"): R("licensed_attraction_merchandise"),
    ("Dumbo", "London Zoo"): R("named_animal_not_lasting_institution_mark"),
    ("Lolcat", "LOLCODE"): R("not_an_institution"),
    ("Don Quixote", "Monterrey Institute of Technology and Higher Education"): R("named_after_author_not_work"),
    ("The Jungle Book", "Kipling Avenue"): R("named_after_author_not_work"),
    ("Lolita", "Mann Act"): R("reversed_direction"),
    ("The Last of Us Part II", "Harborview Medical Center"): R("reversed_direction"),
    ("Journey to the West", "Karate"): R("not_an_institution"),
    ("The Jungle Book", "Scouts de Argentina"): K("Cub Scout leader titles (Akela, Baloo, Bagheera)", "naming convention",
        "Scouts de Argentina names troop leaders after the book's characters. Adoption date not given; order holds because the titles are taken from the book.",
        mark_date="unknown", mark_date_source="none given", order_by_naming=True),
    ("The Raven", "Raven Society"): K("Raven Society (name)", "organization name",
        "University of Virginia honor society named after Poe's poem; Poe attended the university in 1826.",
        mark_date="1904", mark_date_source="article: founded and named in 1904"),
    ("The Raven", "Ravenite Social Club"): K("Ravenite Social Club (name)", "organization name",
        "Carlo Gambino renamed the club in the 1950s; the article says only some sources tie the name to the poem and notes it began as the Raven Knights.",
        disputed=True, mark_date="1950s", mark_date_source="sentence"),
    ("The Smurfs", "Samsunspor"): K("Sirinler supporters group (name)", "supporters group name",
        "Samsunspor's main ultras group, founded in 1986, takes its name from the cartoon.", mark_date="1986", mark_date_source="sentence"),
    ("Robinson Crusoe", "Queen's Gardens, Kingston upon Hull"): K("Robinson Crusoe plaque, Queen's Gardens", "memorial plaque",
        "Plaque commemorates the fictional character's departure from Hull and quotes the novel. Plaque date not given; order holds because it commemorates the character.",
        mark_date="unknown", mark_date_source="none given", order_by_naming=True),
    ("Covfefe", "Presidential Records Act"): R("bill_introduced_not_enacted"),
    ("Jane Eyre", "St Catherine's School, Waverley"): R("named_after_author_not_work"),
    ("Monopoly (game)", "Park Lane"): R("reversed_direction"),
    ("Nineteen Eighty-Four", "Trafalgar Square"): R("fictional_rename_inside_work"),
    ("Pac-Man", "RC Strasbourg Alsace"): R("nickname_not_lasting_mark"),
    ("Slinky", "The Quantum Leap"): R("nickname_not_lasting_mark"),
    ("Twenty Thousand Leagues Under the Seas", "Sea Shepherd Conservation Society"): R("named_after_author_not_work"),
    ("Father of the Pride", "Parents Television and Media Council"): R("campaign_not_lasting"),
    ("Shrek", "Parents Television and Media Council"): R("campaign_not_lasting"),
    ("Chess", "Taliban"): R("general_ban_not_a_reaction_to_release"),
    ("StarCraft (video game)", "StarCraft II in esports"): R("same_owner_franchise_extension"),
    ("Divine Comedy", "Pietà (Michelangelo)"): R("not_an_institution"),
    ("Divine Comedy", "Santa Maria Novella"): R("artwork_influence_not_institutional"),
    ("Constitution of the United States", "Switzerland"): R("stone_is_legal_instrument_not_culture"),
    ("The Great Gatsby", "Flushing Meadows–Corona Park"): R("reversed_direction"),
    ("One Hundred and One Dalmatians", "Primrose Hill"): R("reversed_direction"),
    ("The Raven", "Trough Creek State Park"): R("reversed_direction"),
    ("The Simpsons", "Scopes trial"): R("reversed_direction"),
    ("Abbey Road", "Abbey Road Studios"): K("Abbey Road Studios (renamed from EMI Studios)", "institution renaming",
        "EMI renamed its studio after the band's 1969 album in 1976. A company, kept because it is a change to the institution, not a founding name.",
        mark_date="1976", mark_date_source="sentence"),
    ("Brave New World", "Brave New Workshop"): K("Brave New Workshop (name)", "organization name",
        "Minneapolis satirical theater took its name from Huxley's novel."),
    ("The Hobbit", "Wellington"): K("Giant eagle sculptures at Wellington Airport", "statue",
        "Sculptures commemorating The Hobbit; installed for the film trilogy, and the sentence links the novel. Only bound on date: already in place when the January 2014 earthquake hit.",
        mark_date="2014-01-20", mark_date_source="sentence (in place by this date)"),
    ("Casablanca (film)", "Casablanca Records"): R("company_naming_not_policy"),
    ("Star Wars", "Chewco"): R("company_naming_not_policy"),
    ("Star Trek", "Apple Inc."): R("company_founding_not_policy"),
    ("Encyclopædia Britannica", "Coca-Cola"): R("company_product_design_not_policy"),
    ("Crime and Punishment", "Crimée station"): R("temporary_joke_rename"),
    ("South Park", "Comedy Central"): R("one_time_censorship"),
    ("Hannah Montana", "Disney Channel"): R("one_time_censorship"),
    ("The Hunchback of Notre-Dame", "University of Notre Dame Australia"): R("names_another_work"),
    ("The Good, the Bad and the Ugly", "GStreamer"): R("not_an_institution"),
    ("Song of Roland", "Valhallaorden"): R("legend_not_the_work"),
    ("The Simpsons", "Budweiser"): R("reversed_direction"),
    ("Fight Club", "Young Liberals (Australia)"): R("not_lasting"),
    ("The Lord of the Rings", "Blizzard Entertainment"): R("inspired_another_work"),
    ("Sherlock (TV series)", "BBC Books"): R("same_owner_franchise_extension"),
    ("Book of Mormon", "The Church of Jesus Christ of Latter-day Saints"): R("founding_text_same_author"),
    ("Rubik's Cube", "Puzzle Museum"): R("not_a_reason_for_existence"),
    ("Titanic (1997 film)", "Cunard Line"): K("Carnival's 1998 acquisition of Cunard", "corporate decision",
        "The company historian later said the acquisition was in part due to the success of the 1997 film.",
        mark_date="1998", mark_date_source="section (Carnival, 1998 to present)"),
    ("Adventures of Huckleberry Finn", "Upper Dublin High School"): R("mark_date_unknown"),
    ("Kung Fu Panda (film)", "DreamWorks Animation"): R("temporal_not_causal"),
    ("Nineteen Eighty-Four", "Crass Records"): R("refers_to_the_year_not_the_work"),
    ("Braveheart", "Wallace Monument"): R("statue_removed_2008_not_lasting"),
    ("Les Misérables", "Le Gavroche"): R("company_naming_not_policy"),
    ("Treasure Island", "Long John Silver's"): R("company_naming_not_policy"),
    ("The Adventures of Tintin", "Ottakar's"): R("company_naming_not_policy"),
    ("Harry Potter", "Jelly Belly"): R("merchandise"),
    ("Game of Thrones", "Johnnie Walker"): R("merchandise"),
    ("The Three Musketeers", "Messageries Maritimes"): R("company_naming_not_policy"),
    ("Rubik's Cube", "Ideal Toy Company"): R("is_the_product_itself"),
    ("The Smurfs", "Mitre Line"): R("nickname_not_lasting_mark"),
    ("Return of the Jedi", "Pixar"): R("indirect_revenue_effect"),
    ("Star Wars", "Pixar"): R("indirect_revenue_effect"),
    ("Toy Story", "Industrial Light & Magic"): R("reversed_direction"),
    ("Mein Kampf", "Indigo Books and Music"): K("Indigo stops stocking Mein Kampf", "retail policy",
        "Canada's largest bookseller removed the book from its shelves in 2001.", mark_date="2001", mark_date_source="sentence"),
    ("Pong", "Coleco"): R("ordinary_market_entry"),
    ("Elon Musk salute controversy", "Reddit"): K("X-link bans across 100+ subreddits", "community rule",
        "In January 2025 over 100 Reddit communities banned links to X after the gesture. Stone is a news event the stone list classes as a meme; rules set by community moderators, not by the company.",
        mark_date="2025-01", mark_date_source="sentence"),
    ("Elon Musk salute controversy", "Tesla, Inc."): R("sales_not_lasting_mark"),
    ("Robinson Crusoe", "Transmeta"): R("company_product_naming_not_policy"),
    ("Treasure Island", "Treasure Island Hotel and Casino"): R("company_naming_not_policy"),
    ("League of Legends", "Tiffany & Co."): R("merchandise"),
    ("Final Fantasy VII", "Square (video game company)"): R("reversed_direction"),
    ("Sex and the City", "Soapnet"): R("proposal_not_adopted"),
    ("Book of Mormon", "Ammon, Idaho"): K("Ammon, Idaho (town renamed)", "named place",
        "Bishop Rawson renamed the town in honor of Ammon, a figure in the Book of Mormon.",
        mark_date="1893-02-09", mark_date_source="article: name changed from South Iona Ward to Ammon on February 9, 1893"),
    ("Book of Mormon", "Bountiful, Utah"): K("Bountiful, Utah (city name)", "named place",
        "Named both for its gardening reputation and for the Book of Mormon city of Bountiful; one of two stated reasons.",
        mark_date="1855", mark_date_source="article: known as Sessions Settlement before being named Bountiful in 1855"),
    ("Don Quixote", "Barataria, Louisiana"): K("Barataria, Louisiana (place name, via Bayou and Bay Barataria)", "named place",
        "Name traces through Barataria Bay to the island Sancho Panza governs in Part II of the novel. Naming date not given.",
        mark_date="unknown", mark_date_source="none given (place appears in the 1850 census)", order_by_naming=True),
    ("Monopoly (game)", "Atlantic City, New Jersey"): K("Orange Loop district name, Atlantic City", "named place",
        "District derives its name from the orange color of its streets on the Monopoly board (the game itself took its street names from the city).",
        mark_date="unknown", mark_date_source="none given (Orange Loop Amphitheater open by 2022)", order_by_naming=True, sentence_prefix="James Place",
        sentence_override="It is bounded by Tennessee Avenue, St. James Place, Pacific Avenue and the boardwalk, and derives its name from the orange color of those streets on a traditional Monopoly gameboard."),
    ("The Chronicles of Narnia", "Belfast"): K("C. S. Lewis Square, East Belfast", "named place and statues",
        "Square opened in 2017, named for the author and themed on the Narnia books.", mark_date="2017", mark_date_source="sentence",
        sentence_override="CS Lewis Square (2017), named and themed in honour of the local author of The Chronicles of Narnia."),
    ("Ulysses (novel)", "Ballsbridge"): R("source_is_not_the_institution_article"),
    ("Cars (film)", "Ash Fork, Arizona"): R("reversed_direction"),
    ("Frozen (2013 film)", "Balestrand Municipality"): R("reversed_direction"),
    ("Gravity Falls", "Boring, Oregon"): R("reversed_direction"),
    ("One Hundred Years of Solitude", "Aracataca"): R("reversed_direction"),
    ("The Three Musketeers", "Aramits"): R("reversed_direction"),
    ("Brave New World", "Billingham"): R("reversed_direction"),
    ("Harry Potter and the Philosopher's Stone (film)", "Warner Bros. Studios Leavesden"): R("same_owner_franchise_extension"),
    ("Twenty Thousand Leagues Under the Seas", "Arkoe, Missouri"): R("article_says_claim_is_false"),
    ("Book of Mormon", "Lamoni, Iowa"): K("Lamoni, Iowa (city name)", "named place",
        "Named after Lamoni, a king in the Book of Mormon.", mark_date="1879", mark_date_source="article: formally platted in 1879"),
    ("Book of Mormon", "Nephi, Utah"): K("Nephi, Utah (city name)", "named place",
        "Named after Nephi, son of Lehi, from the Book of Mormon. Earlier called Salt Creek.", mark_date="1882", mark_date_source="article: town and post office became Nephi in 1882"),
    ("Gulliver's Travels", "Clark County, Kentucky"): K("Lulbegrud Creek (name)", "named place",
        "Creek named for Lorbrulgrud, the Brobdingnag capital; told in the county article. Naming date not given.",
        mark_date="unknown", mark_date_source="none given", order_by_naming=True),
    ("Paradise Lost", "Horton, Berkshire"): K("Paradise Lost memorial window, St Michael's, Horton", "memorial window",
        "A 19th-century stained glass window in the parish church commemorates the poem (Milton's mother is buried there).",
        mark_date="1800s", mark_date_source="sentence (19th century)"),
    ("Lolita", "Lolita, Texas"): R("claim_is_the_authors_belief_not_a_record"),
    ("Moby-Dick", "Melville, New York"): R("named_after_author_not_work"),
    ("Paradise Lost", "Milton, Wisconsin"): R("named_after_author_not_work"),
    ("Robinson Crusoe", "Le Plessis-Robinson"): R("via_another_work"),
    ("Neon Genesis Evangelion", "Hakone"): R("tourism_merchandise"),
    ("Shahnameh", "Mashhad"): R("named_after_author_not_work"),
    ("The Tale of Genji", "Echizen, Fukui"): R("named_after_author_not_work"),
    ("The Brothers Karamazov", "Marfa, Texas"): R("article_says_claim_is_false"),
    ("Don Quixote", "Guanajuato (city)"): R("named_after_author_not_work"),
    ("Harry Potter", "Dursley"): R("reversed_direction"),
    ("Frankenstein", "Darmstadt"): R("reversed_direction"),
    ("Monopoly (game)", "Mayfair"): R("reversed_direction"),
    ("Uncle Tom's Cabin", "Pennville, Indiana"): K("Eliza Harris Marker, Pennville", "historical marker",
        "Marker reads that Eliza Harris of Uncle Tom's Cabin fame rested here; it memorializes a local legend tied to the character.",
        mark_date="1923", mark_date_source="article: marker erected in 1923"),
    ("Kalevala", "Helsinki"): R("architectural_style_influence"),
    ("The Office (American TV series)", "Shoreline School District"): K("'Dwight the Knight' mascot, Kellogg Middle School", "school mascot name",
        "Mascot named after alumnus Rainn Wilson's character Dwight Schrute. Naming date not given; order holds because the character debuted in 2005.",
        mark_date="unknown", mark_date_source="none given", order_by_naming=True),
    ("Hansel and Gretel", "Wrocław"): R("nickname_not_lasting_mark"),
    ("Great Expectations", "Wainscott, New York"): R("named_after_place_not_work"),
    ("Grand Theft Auto V", "Yankton, South Dakota"): R("reversed_direction"),
    ("Monopoly (game)", "Virginia Beach, Virginia"): R("reversed_direction"),
    ("The Raven", "Poe (mascot)"): R("named_after_author_not_work"),
    ("Team Fortress 2", "Tux (mascot)"): R("reversed_direction"),
    ("2001: A Space Odyssey", "Bicentennial Capitol Mall State Park"): K("Monolith-style pylons on the park walkways", "public design",
        "Walkway pylons in the Nashville state park were inspired by the film's monoliths (and by unbuilt Venturi pylons)."),
    ("The Witcher 3: Wild Hunt", "Blue Whale Challenge"): R("ban_caused_by_other_event"),
    ("Abbey Road", "Abbey Road, London"): R("tourism"),
    ("Tamagotchi", "Bandai"): K("Planned Sega and Bandai merger called off", "corporate decision",
        "The major success of the Tamagotchi line, plus opposition inside Bandai, caused the merger plan to fall through.",
        mark_date="1997", mark_date_source="sentence: the toy line launched the previous year (1996)"),
    ("Pokémon Go", "Lower Garden District, New Orleans"): R("not_shown_lasting"),
    ("The Da Vinci Code", "Rosslyn Chapel"): R("tourism"),
    ("Journey to the West", "Fuzhou"): R("temporal_not_explicitly_causal"),
    ("Adventures of Huckleberry Finn", "Concord Free Public Library"): K("Concord Free Public Library bans Huckleberry Finn", "institutional ban",
        "In March 1885 the library became the first institution to ban the novel.", mark_date="1885-03", mark_date_source="sentence"),
    ("Seinfeld", "Festivus"): K("Festivus as a celebrated holiday", "durable behavior change",
        "The holiday began in writer Dan O'Keefe's family; wider adoption followed the 1997 episode, with many celebrants inspired by it.",
        mark_date="after 1997-12", mark_date_source="sentence: people 'subsequently' began celebrating after the episode", order_by_naming=True),
    ("Snow White and the Seven Dwarfs (film)", "Bronx Zoo"): R("named_animal_not_lasting_institution_mark"),
    ("Book of Mormon", "Community of Christ"): R("not_a_change"),
    ("Alice's Adventures in Wonderland", "Central Park"): K("Alice in Wonderland sculpture (Margaret Delacorte Memorial)", "statue",
        "Bronze of Alice and companions at Conservatory Water, dedicated 1959.", mark_date="1959", mark_date_source="sentence"),
    ("Kony 2012", "Invisible Children, Inc."): R("same_owner"),
    ("...And Justice for All (album)", "Grammy Award for Best Hard Rock/Metal Performance Vocal or Instrumental"): R("change_not_stated_in_work_sentence"),
    ("Bambi", "Smokey Bear"): K("Smokey Bear (Forest Service fire-prevention symbol)", "public program mascot",
        "Disney loaned Bambi to the Forest Service's fire-prevention campaign for only a year, so the service needed a new symbol of its own.",
        mark_date="1944", mark_date_source="Smokey Bear created 1944 (article: Campaign beginnings)"),
    ("Donkey Kong (1981 video game)", "Universal City Studios, Inc. v. Nintendo Co., Ltd."): R("reversed_direction"),
    ("The Little Mermaid", "The Little Mermaid (statue)"): K("The Little Mermaid statue, Copenhagen", "statue",
        "Edvard Eriksen's bronze, based on Andersen's 1837 tale, unveiled in 1913.", sentence_prefix="Based on"),
    ("2001: A Space Odyssey", "HAL Laboratory"): R("company_naming_not_policy"),
    ("Harry Potter and the Deathly Hallows", "Balmoral Hotel"): R("named_after_author_not_work"),
    ("Overwatch (2016 video game)", "Blizzard Entertainment"): R("change_caused_by_other_event"),
    ("Blood Bowl", "Impact! Miniatures"): R("change_caused_by_other_event"),
    ("The Jungle Book", "Akella"): R("company_naming_not_policy"),
    ("Fortnite", "Epic Games"): R("same_owner"),
    ("Beauty and the Beast (1991 film)", "The Walt Disney Company"): R("sentence_is_about_a_different_film"),
    ("Pirates of the Caribbean: The Curse of the Black Pearl", "Touchstone Pictures"): R("same_owner"),
    ("Toy Story", "Pixar"): R("same_owner"),
    ("Toy Story (franchise)", "Pixar"): R("same_owner"),
    ("Around the World in Eighty Days", "Phileas Fogg snacks"): R("company_naming_not_policy"),
}
REJECT_DEFAULT = "read_mention_only_or_not_a_reason"


def mark_date(run, qid, sentence, stone_year):
    e = run.wd.get(qid, {})
    for p in ("P571", "P1619", "P7588", "P5444", "P580", "P585", "P577"):
        t = e.get("dates", {}).get(p)
        if t:
            y = t.lstrip("+")[:10].replace("-00", "")
            return y, f"wikidata {p}"
    ys = [y for y in re.findall(r"\b(1[6-9]\d\d|20[0-2]\d)\b", sentence) if int(y) >= stone_year]
    return (ys[0], "sentence") if ys else (None, None)


def phase_write(run):
    cands, counts = phase_match(run)
    works = {w["title"]: w for w in run.works}
    kept, rej = [], Counter(counts)
    seen = set()
    for c in cands:
        key = (c["stone"], c["page"])
        v = REVIEW.get(key)
        if not v or not v.get("keep"):
            if key not in seen: rej[(v or {}).get("reason", REJECT_DEFAULT)] += 1
            seen.add(key); continue
        if key in seen: continue
        if v.get("sentence_prefix") and not c["sentence"].startswith(v["sentence_prefix"]): continue
        seen.add(key)
        w = works[c["stone"]]
        sy = int(w["date"][:4])
        md, src = (v["mark_date"], v.get("mark_date_source", "sentence")) if v.get("mark_date") else mark_date(run, c["qid"], c["sentence"], sy)
        order_ok = bool(v.get("order_by_naming")) or (bool(md) and str(md)[:4].isdigit() and int(str(md)[:4]) >= sy)
        if not order_ok: rej["mark_not_after_stone"] += 1; continue
        kept.append({"gen": "G4", "stone": c["stone"].split(" (")[0] if v.get("short_stone", True) else c["stone"],
                     "stone_article": c["stone"], "stone_date": w["date"], "stone_kind": w["kind"],
                     "mark": v["mark"], "mark_kind": v["mark_kind"], "mark_date": md, "mark_date_source": src or "",
                     "mark_article": c["page"], "sentence": html.unescape(v.get("sentence_override") or c["sentence"]).replace("\xa0", " "),
                     "source_article": c["page"],
                     "source_section": c["section"],
                     "source_url": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(c["page"].replace(" ", "_")) +
                                   ("" if c["section"] == "(lead)" else "#" + urllib.parse.quote(c["section"].replace(" ", "_"))),
                     "cause_label": "reason", "order_ok": True, "disputed": bool(v.get("disputed")),
                     "notes": v.get("notes", "")})
    typed = run.typed()
    out = {"generator": "G4", "works": len(run.works), "backlink_pages": sum(len(r["pages"]) for r in run.bl.values()),
           "unique_backlink_pages": len({p[0] for r in run.bl.values() for p in r["pages"]}),
           "typed_pages": len(typed), "candidates_read": len({(c["stone"], c["page"]) for c in cands}),
           "kept": kept, "rejected_counts": dict(rej), "stopped": dict(STOPPED) or json.load(open(C("stopped.json"))) if os.path.exists(C("stopped.json")) else {}}
    json.dump(out, open(P("g4.json"), "w"), indent=1, ensure_ascii=False)
    log(f"wrote g4.json kept {len(kept)}")


if __name__ == "__main__" and "write" in sys.argv:
    phase_write(Run(phase_select()))
