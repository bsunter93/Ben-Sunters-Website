"""G2 FORWARD: read the impact sections of the most-linked cultural works and keep institutional reactions.

Phases (each cached so a rerun resumes):
  stones  : Wikidata SPARQL, top works by sitelink count per class, with P577/P580 (P571 as a fallback) dates
  fetch   : English Wikipedia wikitext, 20 titles per action=query request, 1 request a second
  match   : impact-type sections only; sentence must carry an institutional verb AND a lasting-mark object (lexicon
            below, fixed before the run)
  review  : strict human-read verdicts recorded in REVIEW (keyed by stone + sentence prefix); everything not kept gets a
            rejection reason
  marks   : date each kept mark from its own article's Wikidata item (P571/P577/P580/P585/P3999/P5444), else the sentence
Honest UA on every request; stop an endpoint for the day on any 403/429."""
import json, re, sys, time, urllib.parse, urllib.request, os, hashlib
from collections import Counter, defaultdict
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
HERE = os.path.dirname(os.path.abspath(__file__))
P = lambda f: os.path.join(HERE, f)
WDQS = "https://query.wikidata.org/sparql"
WPAPI = "https://en.wikipedia.org/w/api.php"
WDAPI = "https://www.wikidata.org/w/api.php"
STOPPED = set()

# ---------------------------------------------------------------- lexicon (fixed before the run)
HEADINGS = re.compile(r"impact|legacy|influence|reception and legacy|controvers|in popular culture|aftermath|effect|response|criticism", re.I)
# documented extension: headings that name an institutional reaction outright
HEADINGS_EXT = re.compile(r"\bbans?\b|banning|censorship|legislation|regulat|legal (issues|action|challenges)|lawsuits?|litigation", re.I)
SKIPHEAD = re.compile(r"special effects|visual effects|sound effects|plot|cast|production|synopsis|premise|characters|episodes|track listing|personnel|filming|casting|references|notes|external links|see also|bibliography|further reading|soundtrack|gameplay", re.I)
VERB = re.compile(r"\b(ban(?:s|ned|ning)?|prohibit(?:s|ed|ing)?|outlaw(?:s|ed|ing)?|restrict(?:s|ed|ing)?|found(?:ed|ing)|establish(?:es|ed|ing)?|creat(?:e|es|ed|ing)|form(?:ed|ing)|renam(?:e|es|ed|ing)|named (?:after|for)|amend(?:s|ed|ing)?|pass(?:ed|ing)|enact(?:s|ed|ing)?|adopt(?:s|ed|ing)?|rul(?:ed|ing)|overturn(?:s|ed|ing)?|released from prison|freed|ended|discontinu(?:e|es|ed|ing)|introduc(?:ed|es|ing) (?:new )?guidelines|issu(?:ed|es|ing) a directive|launched an investigation)\b", re.I)
OBJ = re.compile(r"\b(?i:laws?|legislation|statutes?|ordinances?)|\bAct\b|\b(?i:acts? of (?:parliament|congress)|bills?|rules?|regulations?|standards?|guidelines?|rating system|ratings? board|agenc(?:y|ies)|organi[sz]ations?|foundations?|charit(?:y|ies)|leagues?|teams?|polic(?:y|ies)|courts?|rulings?|directives?|programs?|programmes?|curricul(?:um|a)|sports?)\b")
OBJ_CI = re.compile(r"\b(laws?|legislation|statutes?|ordinances?|bills?|rules?|regulations?|standards?|guidelines?|rating system|ratings? board|agenc(?:y|ies)|organi[sz]ations?|foundations?|charit(?:y|ies)|leagues?|teams?|polic(?:y|ies)|courts?|rulings?|directives?|programs?|programmes?|curricul(?:um|a)|sports?)\b", re.I)
CAUSAL = re.compile(r"\b(because of|due to|in response to|in reaction to|as a result|following|after|inspired|led to|prompted|spurred|named after|named for|cit(?:ed|ing)|over (?:concerns|fears)|on the grounds|blamed|in the wake of|influence of|thanks to|credited)\b", re.I)
# Tier B (added after the first pass, disclosed in the report): a ban-type verb alone qualifies, because the ban is the rule
BANVERB = re.compile(r"\b(ban(?:s|ned|ning)?|prohibit(?:s|ed|ing)?|outlaw(?:s|ed|ing)?|restrict(?:s|ed|ing)?)\b", re.I)
# Tiers C and D (added after the second pass, disclosed): nominal forms of the fixed verbs plus an object (C), and a
# causal connective plus an object with no verb (D). Filter kept items to tier A for the pre-registered lexicon alone.
NOMINAL = re.compile(r"\b(creation|formation|establishment|founding|passage|introduction|adoption|enactment|renaming|naming|outlawing|banning|prohibition|amendment)\b", re.I)
CAUSEPHRASE = re.compile(r"\b(led to|prompted|spurred|inspired|resulted in|gave rise to|in response to|in reaction to|as a result of|because of)\b", re.I)
WORKREF = re.compile(r"\b(the (?:film|movie|series|show|programme|program|game|song|single|album|novel|book|books|meme|video|toy|doll|franchise|musical|sitcom|cartoon|comic)s?|its|it)\b", re.I)

# ---------------------------------------------------------------- classes
CLASSES = {
  "film":      (["Q11424", "Q202866", "Q24869"], 320),
  "tv":        (["Q5398426", "Q117467246", "Q581714", "Q1259759", "Q15416", "Q526877", "Q63952888"], 300),
  "videogame": (["Q7889"], 280),
  "music":     (["Q7366", "Q134556", "Q482994", "Q208569"], 300),
  "book":      (["Q7725634", "Q8261", "Q277759", "Q1667921", "Q47461344", "Q571"], 300),
  "toy_game":  (["Q11422", "Q131436", "Q734698", "Q673218", "Q13427002", "Q142714", "Q11410"], 220),
  "meme":      (["Q2927074", "Q1030329", "Q60714051", "Q2055141"], 160),
}

def http_json(url, data=None, endpoint="x", tries=3):
    if endpoint in STOPPED: return None
    for k in range(tries):
        req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=90) as r: return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (403, 429):
                print(f"STOP {endpoint}: HTTP {e.code}", file=sys.stderr); STOPPED.add(endpoint); return None
            if e.code in (500, 502, 503, 504) and k < tries - 1: time.sleep(5 * (k + 1)); continue
            print(f"{endpoint}: HTTP {e.code}", file=sys.stderr); return None
        except Exception as e:
            if k < tries - 1: time.sleep(5); continue
            print(f"{endpoint}: {e}", file=sys.stderr); return None

def sparql(q):
    return http_json(WDQS + "?" + urllib.parse.urlencode({"query": q, "format": "json"}), endpoint="wdqs", tries=4)

THR = {"film": 55, "tv": 35, "videogame": 35, "music": 30, "book": 35, "toy_game": 15, "meme": 6}
# Supplementary passes run after the first one (disclosed): toys and memes were thin, so their thresholds dropped and
# three toy classes plus media franchises were added; then the five big classes were extended toward 2,000 works.
SUPPLEMENTS = [
  ({"toy_game": (CLASSES["toy_game"][0] + ["Q1056891", "Q11380", "Q1144709"], 160), "meme": (CLASSES["meme"][0], 160)}, {"toy_game": 5, "meme": 3}, True),
  ({"toy_game": (["Q57663626", "Q682582", "Q15654425", "Q573573"], 80), "franchise": (["Q196600"], 140)}, {"toy_game": 8, "franchise": 40}, False),
  ({"film": (CLASSES["film"][0], 400), "tv": (CLASSES["tv"][0], 370), "videogame": (CLASSES["videogame"][0], 300), "music": (CLASSES["music"][0], 360), "book": (CLASSES["book"][0], 340)}, {"book": 28, "tv": 30, "videogame": 30}, False),
]
def stone_pass(classes, thr, seen):
    stones = []
    for kind, (qids, lim) in classes.items():
        sl = {}
        for cls in qids:  # one small query per class item; ORDER BY over the join times out
            d = sparql(f"SELECT ?item ?sl WHERE {{ ?item wdt:P31 wd:{cls}; wikibase:sitelinks ?sl. FILTER(?sl >= {thr[kind]}) }}")
            if not d: continue
            for b in d["results"]["bindings"]: sl[b["item"]["value"].rsplit("/", 1)[1]] = int(b["sl"]["value"])
            time.sleep(1)
        top = [q for q, _ in sorted(sl.items(), key=lambda x: -x[1]) if q not in seen][: lim + 80]
        rows = defaultdict(lambda: {"dates": []})
        for i in range(0, len(top), 150):
            vals = " ".join("wd:" + q for q in top[i:i + 150])
            d = sparql(f"""SELECT ?item ?title ?d1 ?d2 ?d3 WHERE {{ VALUES ?item {{ {vals} }}
 ?art schema:about ?item; schema:isPartOf <https://en.wikipedia.org/>; schema:name ?title.
 OPTIONAL {{ ?item wdt:P577 ?d1 }} OPTIONAL {{ ?item wdt:P580 ?d2 }} OPTIONAL {{ ?item wdt:P571 ?d3 }} }}""")
            if not d: continue
            for b in d["results"]["bindings"]:
                it = b["item"]["value"].rsplit("/", 1)[1]; r = rows[it]; r["title"] = b["title"]["value"]
                for key, src in (("d1", "P577"), ("d2", "P580"), ("d3", "P571")):
                    if key in b and b[key]["value"][:1] in "12": r["dates"].append((b[key]["value"][:10], src))
            time.sleep(1)
        n = 0
        for q in top:
            if q not in rows or q in seen: continue
            r = rows[q]; pref = [x for x in r["dates"] if x[1] in ("P577", "P580")] or r["dates"]
            if not pref: continue
            dt, src = min(pref)
            seen.add(q); stones.append({"qid": q, "title": r["title"], "sl": sl[q], "kind": kind, "date": dt, "date_src": src}); n += 1
            if n >= lim: break
        print(f"{kind:10s} {n} (pool {len(sl)})", file=sys.stderr)
    return stones

def phase_stones():
    if os.path.exists(P("g2_stones.json")): return json.load(open(P("g2_stones.json")))
    seen = set(); stones = stone_pass(CLASSES, THR, seen)
    for classes, thr_upd, replace in SUPPLEMENTS:
        if replace:  # rerun these classes from scratch at the lower threshold and keep the larger set
            drop = set(classes); stones = [s for s in stones if s["kind"] not in drop]; seen = {s["qid"] for s in stones}
        stones += stone_pass(classes, {**THR, **thr_upd}, seen)
    json.dump(stones, open(P("g2_stones.json"), "w"), indent=0)
    return stones

_last = [0.0]
def wp(params):
    if "wikipedia" in STOPPED: return None
    w = 1.0 - (time.time() - _last[0])
    if w > 0: time.sleep(w)
    url = WPAPI + "?" + urllib.parse.urlencode({**params, "format": "json", "formatversion": 2})
    r = http_json(url, endpoint="wikipedia", tries=2); _last[0] = time.time(); return r

def phase_fetch(stones):
    cache = json.load(open(P("g2_wikitext.json"))) if os.path.exists(P("g2_wikitext.json")) else {}
    todo = [s["title"] for s in stones if s["title"] not in cache]
    i = 0
    while i < len(todo):
        batch = todo[i:i + 20]
        d = wp({"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main", "titles": "|".join(batch), "redirects": 1})
        if d is None: break
        norm = {x["from"]: x["to"] for x in d["query"].get("normalized", [])}
        redir = {x["from"]: x["to"] for x in d["query"].get("redirects", [])}
        got = {}
        for pg in d["query"]["pages"]:
            if "revisions" in pg: got[pg["title"]] = pg["revisions"][0]["slots"]["main"]["content"]
            elif pg.get("missing"): got[pg["title"]] = ""
        retry = []
        for t in batch:
            tt = redir.get(norm.get(t, t), norm.get(t, t))
            if tt in got: cache[t] = got[tt]
            else: retry.append(t)
        todo.extend(retry if len(retry) < len(batch) else [])  # requeue truncated pages once the batch made progress
        i += 20
        if (i // 20) % 10 == 0:
            json.dump(cache, open(P("g2_wikitext.json"), "w")); print(f"fetched {len(cache)}", file=sys.stderr)
    json.dump(cache, open(P("g2_wikitext.json"), "w"))
    return cache

def strip_templates(wt):
    wt = re.sub(r"\{\{\s*(?:ill|interlanguage link|nowrap|nobr|lang\|[a-z-]+|small|em|vr|abbr)\|([^{}|]*)[^{}]*\}\}", r"\1", wt, flags=re.I)
    wt = re.sub(r"\{\{\s*(?:'|')\s*\}\}", "'", wt)
    for _ in range(12):
        new = re.sub(r"\{\{[^{}]*\}\}", "", wt)
        if new == wt: break
        wt = new
    return wt

def clean(wt):
    wt = re.sub(r"<!--.*?-->", "", wt, flags=re.S)
    wt = re.sub(r"<ref[^>/]*/>", "", wt); wt = re.sub(r"<ref[^>]*>.*?</ref>", "", wt, flags=re.S)
    wt = strip_templates(wt)
    wt = re.sub(r"\{\|.*?\|\}", "", wt, flags=re.S)
    wt = re.sub(r"\[\[(?:File|Image):[^\[\]]*(?:\[\[[^\]]*\]\][^\[\]]*)*\]\]", "", wt, flags=re.I)
    wt = re.sub(r"<[^>]+>", "", wt); wt = re.sub(r"'{2,}", "", wt)
    wt = re.sub(r"\[https?://\S+\s([^\]]*)\]", r"\1", wt)
    return wt

def sentences(text):
    text = re.sub(r"^[*#:;]+\s*", "", text, flags=re.M)
    text = re.sub(r"\s+", " ", text)
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+(?=[A-Z\[\"])", text) if len(s.strip()) > 30]

def links(s): return [l.split("|")[0].strip() for l in re.findall(r"\[\[([^\]]+)\]\]", s) if ":" not in l.split("|")[0]]
def plain(s): return re.sub(r"\[\[([^\]|]+\|)?([^\]]+)\]\]", r"\2", s).strip()

def split_sections(wt):
    out, stack = [], []
    parts = re.split(r"^(={2,6})\s*(.*?)\s*\1\s*$", wt, flags=re.M)
    for i in range(1, len(parts) - 2, 3):
        lvl, head, body = len(parts[i]), parts[i + 1], parts[i + 2]
        stack = [(l, h) for l, h in stack if l < lvl] + [(lvl, head)]
        out.append((head, [h for _, h in stack], body))
    return out

def phase_match(stones, cache):
    cands, read = [], 0
    for s in stones:
        wt = cache.get(s["title"], "")
        if not wt or wt.lower().startswith("#redirect"): continue
        read += 1
        short = re.sub(r"\s*\(.*\)$", "", s["title"])
        for head, path, body in split_sections(wt):
            if SKIPHEAD.search(head): continue
            if not any(HEADINGS.search(h) or HEADINGS_EXT.search(h) for h in path): continue
            if any(SKIPHEAD.search(h) for h in path): continue
            for sent in sentences(clean(body)):
                pt = plain(sent)
                tierA = bool(VERB.search(pt) and OBJ.search(pt)); tierB = bool(BANVERB.search(pt))
                tierC = bool(NOMINAL.search(pt) and OBJ.search(pt)); tierD = bool(CAUSEPHRASE.search(pt) and OBJ.search(pt))
                if not (tierA or tierB or tierC or tierD): continue
                yrs = [int(y) for y in re.findall(r"\b(1[5-9]\d\d|20\d\d)\b", pt)]
                cands.append({"stone": short, "stone_article": s["title"], "stone_date": s["date"], "stone_kind": s["kind"], "sl": s["sl"],
                              "section": " > ".join(path), "sentence": pt, "links": links(sent), "years": yrs,
                              "tier": "A" if tierA else "B" if tierB else "C" if tierC else "D", "verb": (VERB.search(pt) or BANVERB.search(pt) or NOMINAL.search(pt) or CAUSEPHRASE.search(pt)).group(0), "obj": (OBJ.search(pt).group(0) if OBJ.search(pt) else ""),
                              "causal": bool(CAUSAL.search(pt)), "workref": bool(short.lower() in pt.lower() or WORKREF.search(pt)),
                              "key": hashlib.md5((s["title"] + pt[:120]).encode()).hexdigest()[:10]})
    return read, cands

if __name__ == "__main__":
    phase = sys.argv[1] if len(sys.argv) > 1 else "all"
    stones = phase_stones()
    print("stones", len(stones), Counter(s["kind"] for s in stones), file=sys.stderr)
    if phase in ("fetch", "all", "match"):
        cache = phase_fetch(stones) if phase != "match" else json.load(open(P("g2_wikitext.json")))
        read, cands = phase_match(stones, cache)
        json.dump({"works_read": read, "cands": cands}, open(P("g2_cands.json"), "w"), indent=0)
        print("works read", read, "sentences matched", len(cands), file=sys.stderr)

# ---------------------------------------------------------------- strict review (human-read verdicts)
# key -> (mark, mark_kind, mark_article or None, fallback date from the sentence/context, disputed, notes, overrides)
KEEP = {
 "cb536182c2": ("Toronto Raptors team name", "team", "Toronto Raptors", "1995", False, "Already-known example from the brief; kept for completeness.", {}),
 "8ee1ef7b65": ("National Film Preservation Act of 1988", "law", "National Film Preservation Act", "1988", False, "Article gives the colorization controversy over Kane as 'a factor' in passage; contributing cause, not sole cause. The Act created the National Film Registry.", {}),
 "331016b391": ("New York parole rule barring sex offenders from Pokemon Go", "rule", None, "2016", False, "Already-known example from the brief; kept for completeness.", {}),
 "122ba1e57b": ("Pentagon restriction on Pokemon Go use on its property", "rule", None, "2016", False, "Security rule on a defense facility; parallels the NSA Furby ban.", {}),
 "bc02d2d42f": ("Israel Defense Forces ban on Pokemon Go on army bases", "rule", None, "2016", False, "Same sentence also reports Kuwait's ban from government sites (kept separately).", {}),
 "bc02d2d42f#kw": ("Kuwait ban on Pokemon Go at government sites", "rule", None, "2016", False, "Second mark in the IDF sentence.", {}),
 "b8da1ee716": ("Cambodian ban on Pokemon Go at a former genocide site", "rule", None, "2016", False, "Article does not name the site in this sentence.", {}),
 "f5f03d1fe0": ("Vietnam ban on Pokemon Go players entering government and defense offices", "rule", None, "2016", False, "", {}),
 "43b4a0e87d": ("Philippine ban on Pokemon Go in all government administration offices", "rule", None, "2016", False, "", {}),
 "ef2d0afae4": ("Saudi fatwa banning the Pokemon card game as gambling", "religious ruling", None, "2001", False, "Sentence sits in the Pokemon Go article; the 2001 fatwa's object is the Pokemon card game, so the stone is the card game. The 2016 Pokemon Go ruling it prompted is a second step.", {"stone": "Pokemon Trading Card Game", "stone_article": "Pokémon Trading Card Game", "stone_date": "1996-10-20", "stone_kind": "toy_game"}),
 "f85d42041b": ("Brazilian federal court ban on the sale of Counter-Strike", "court ruling", None, "2007", False, "Enforced from 17 January 2008; lifted by a regional federal court on 18 June 2009, so the mark lasted about 18 months.", {}),
 "d5d6077ce8": ("Brazilian court order prohibiting commerce and import of Bully", "court ruling", None, "2008", False, "", {}),
 "e74ffe0f72": ("Nepal Supreme Court ruling lifting the national PUBG ban", "court ruling", None, "2019", False, "Ruling holds the government must show necessity before banning on personal-freedom grounds.", {}),
 "19bd7b2781": ("City of Mesquite v. Aladdin's Castle (Mesquite arcade ordinance case)", "court ruling", "City of Mesquite v. Aladdin's Castle, Inc.", "1982", False, "Article ties the Mesquite, Texas arcade restriction to Space Invaders mania. Verify wording: the sentence says the Court ruled the ordinance unconstitutional; the 1982 decision is usually summarized as vacating and remanding.", {}),
 "c91b07c2e3": ("School bans on Tamagotchi", "rule", None, None, False, "Many schools; no year in the sentence. Order holds by the sentence's own logic (bans followed classroom disruption by the product).", {}),
 "b045e510dd": ("Senior-center and retirement-home Wii Sports bowling leagues", "league", None, None, False, "Durable behavior change with league structure; undated in the sentence.", {}),
 "64a784738d": ("1998 Frankfurt High District Court ruling excluding video games from the art exemption for Nazi symbols", "court ruling", None, "1998", False, "Article calls Wolfenstein 3D the principal cause of Germany's de facto ban on games with extremist symbols under StGB 86a, which held until 2018.", {}),
 "86839d51db": ("The Uncensored Library (Reporters Without Borders)", "program", "The Uncensored Library", "2020", False, "The game is the medium and the enabling condition rather than a provocation; weaker cause than the others.", {}),
 "bcb18834aa": ("Bragg v. Linden Research ruling that parts of the Second Life terms of service were unconscionable", "court ruling", "Bragg v. Linden Research, Inc.", "2007", False, "", {}),
 "4ec58719c9": ("Belgian ban on broadcasts of 'You Are Not Alone'", "court-ordered ban", None, "2003", False, "Follows a Belgian plagiarism ruling for the van Passel brothers; fines of 1,000 euros per copy. Verify: the article's 2007 'reversed' sentence reads oddly against the maintained ban.", {}),
 "b397319e47": ("Quidditch as a real-life sport", "sport", "Quidditch (sport)", "2005", False, "The source sentence says 2005 (Middlebury College); the sport's own article infobox gives an earlier first year. Both postdate the 1997 stone.", {}),
 "00cce9d2d5": ("British Columbia Supreme Court injunction forbidding early buyers from reading Half-Blood Prince", "court ruling", None, "2005", False, "Temporary injunction, but it bound members of the public and drew right-to-read criticism.", {}),
 "2646743af9": ("B612 Foundation", "foundation", "B612 Foundation", "2002", False, "Next sentence in the article: 'The non-profit organization is named in honour of the prince's home asteroid.'", {}),
 "e366d7fac0": ("United States v. One Book Called Ulysses", "court ruling", "United States v. One Book Called Ulysses", "1933", False, "District ruling 1933, affirmed by the Second Circuit in 1934.", {}),
 "e6b6f1ccf5": ("Ban on Grimms' fairy tales in the British Occupation Zone of Germany", "rule", None, "1945", False, "Sentence dates it 'following WWII'; 1945 is the earliest possible year.", {}),
 "0e0d0d1907": ("Leipzig ban on Werther and on the Werther clothing style", "law", None, "1775", False, "Also banned in Denmark and Italy. The Werther effect itself is called a rumor by a biographer in the same passage; the ban is not.", {}),
 "5f4f36ddda": ("Grove Press v. Christenberry 'redeeming social or literary value' standard", "court ruling", "Grove Press, Inc. v. Christenberry", "1959", False, "", {}),
 "ab986f46dc": ("Ranjit D. Udeshi v. State of Maharashtra obscenity test", "court ruling", "Ranjit D. Udeshi v. State of Maharashtra", "1964", False, "Sentence says the court 'established' the Hicklin test; Hicklin is an 1868 English test that the court adopted, so the mark is the Indian ruling, not the test.", {}),
 "738c78cfbe": ("Island Trees School District v. Pico", "court ruling", "Island Trees School District v. Pico", "1982", False, "Slaughterhouse-Five was among the books removed; one of several works given as reason.", {}),
 "8c25308669": ("Kurdistan Region ban and seizure of Labubu dolls", "rule", None, "2025", False, "Rationale given: the toy could influence children's behavior and attract demonic spirits.", {}),
 "2aec880980": ("SARFT directive of 30 March 2009 listing 31 categories of prohibited online content", "directive", None, "2009", True, "Hedged in the article: 'Many netizens believe the instruction follows the official embarrassment over the rise of the Grass Mud Horse phenomenon.'", {}),
 "d67783ca25": ("Hong Kong school bans on Bus Uncle catchphrases", "rule", None, "2006", False, "Undated in the sentence; the video is April 2006 and the bans respond to it, so 2006 is the earliest possible year.", {}),
 "ddba72116d": ("4chan /v/ rule banning users who start Loss threads", "rule", None, None, False, "Platform moderation rule, undated.", {}),
 "b64d93d6db": ("Mississippi State athletics adopting the More Cowbell sketch before home football games", "durable institutional behavior", None, None, False, "Undated; the cowbell tradition is older, the sketch clip ritual must postdate the 2000 sketch.", {}),
 "d832d67358": ("Saudi Arabia outlawing the sale of Barbie dolls", "law", None, "2003", False, "Article says 'The 2003 Saudi ban was temporary.'", {}),
 "988e538d4a": ("501st Legion", "organization", "501st Legion", "1997", False, "Fan costuming organization that does charity work.", {}),
 "a4bdc8ccf2": ("Baltimore Ravens team name", "team", "Baltimore Ravens", "1996", False, "", {}),
 "220df41792": ("University of Tennessee course 'Red Dead America'", "school curriculum", None, "2021", False, "", {}),
 "a05029a64a": ("Saint Petersburg Oktyabrsky District Court ban on Happy Tree Friends", "court ruling", None, "2021", False, "Court cited the series being 'designed in a style common for American animation.'", {}),
 "e8837b4ac1": ("Los Angeles Superior Court ruling that videocassettes count as transcriptions (Peggy Lee v. Disney)", "court ruling", None, None, False, "Royalty precedent for home video; undated in the sentence (case decided around 1991).", {}),
 "ce03081a36": ("Boosey & Hawkes v. Walt Disney Co. Second Circuit ruling on video rights", "court ruling", "Boosey & Hawkes Music Publishers, Ltd. v. Walt Disney Co.", "1998", False, "Precedent that a motion-picture license extends to video format.", {}),
 "24fc9f2aaa": ("Federal Bureau of Prisons Special Confinement Unit Media Policy barring face-to-face interviews with death row inmates", "policy", None, "2000", False, "Trigger is the 12 March 2000 60 Minutes interview with Timothy McVeigh, so the stone date is that broadcast. Cause is given as 'Following the program'; the policy was upheld in Hammer v. Ashcroft.", {"stone": "60 Minutes (Timothy McVeigh interview)", "stone_date": "2000-03-12"}),
 "32904198ba": ("EPA ban on Alar (daminozide) for food crops", "regulation", None, "1989", False, "Trigger is the February 1989 60 Minutes Alar report, so the stone date is that broadcast. The article links them by sequence ('subsequently') inside the segment's controversy section, not by an explicit causal verb. Substance article: Daminozide.", {"stone": "60 Minutes (Alar report)", "stone_date": "1989-02"}),
 "f6f95c2f77": ("Mississippi Supreme Court ruling that the state obscenity statute was too vague to enforce", "court ruling", None, "1976", False, "Overturned a theater's obscenity conviction for showing The Exorcist in Hattiesburg.", {}),
}
REJECT = {  # manual reasons; anything else falls through to the rule-based reasons below
 **{k: "one-off platform or event action, not lasting" for k in ["ad68ab3c2b","278a9ed4ec","92d232be5e","3700c39819","a3283e57cc","593caa41c4","0a9877f003","6a426d3371","ec711f3b77","f6a723e53e","829aea0955","a2f2fee433","4054e8d933","600b8ddd8d","8709fa64c1"]},
 **{k: "general policy, the work is not the reason" for k in ["17fd2d5f11","203da0f58e","e6ef9d0391","3f88cd8d9f","24c1c63414","9edfae8842","40400da9cb","66a963e4b3"]},
 **{k: "mark predates the stone or applies an older law" for k in ["473d8f12d2","24ca9e0e19","77560236c0","4110bc9f68","d1e4dd4a5a","7bf28b2327","5260bf90f8"]},
 **{k: "proposed or demanded, not shown enacted" for k in ["d27482288e","3f68a5a0df","cf7a80a45e","152359684c","1142cba262","49e86abfe6","9d9d7293f2","c0197facbb","bb3a3bbea5","2496487cf6","0983865404","a19942cc1c","09c0ad03b6","f1754a7cf8","260d5c6e5d","18a1629d52","8853d53270","d2f2c608fb","2dc6c512b0"]},
 **{k: "ruling or ban later reversed, not lasting" for k in ["438c1a0025","22cef45de7","fbd3dcdd8c","308fb12bcb"]},
 **{k: "self-governance by the work's owner or platform" for k in ["01a35f13ba","5f1557ad6a","19e9e898ca","8d352d10d2","b09a54381a","5a120e1d2a","50b719b2c7","17ded55e6d","44dfc0b068","e774b98696","8daf3d49bf","779fb28ac4","d512516cfb","59a31a0239","d501da4c1d","2a8f440deb","ddc348fc20","29cf7d07c5","561657ff3b","c27373ab28","b38bddb323","9738a501a5"]},
 **{k: "award, merchandise or tie-in (excluded mark type)" for k in ["ac205eb6dc","0389795cb9","541948ccd4","0879bff5e1","bf26237442","1fa296d450"]},
 **{k: "work not given as the reason" for k in ["25a59191d5","46935993ee","053cfddd2f","38749feda9","9ca2e006ab","da866e34dc"]},
 **{k: "stone is a legal or religious document, not a cultural work" for k in ["e0b911400e","a46ef2efc7","7dac630d2f","d5643a384d","a019fd4b1d","7e18d84b4b","50037eca92","b2e3809c49","6ae1d2513e","ba88a07a12","acf42eae16","0586239fe5","bc234576dc","733dfb015d","fe26a14a2d","c942e63e27","17dca5bfc9","a01c86e41d","e68049bdbc"]},
}
CENSOR = re.compile(r"\b(banned|ban|bans|banning|prohibit\w*|restrict\w*|outlaw\w*|censor\w*|classification|rating|rated|re-rated|index|challenged)\b", re.I)
LITIG = re.compile(r"\b(lawsuit|sued|suit|court|ruling|ruled|judge|settlement|appeal\w*|injunction|plaintiff|verdict)\b", re.I)
PROSE = re.compile(r"\b(critic\w*|review\w*|wrote|praised|described|said|noted|stated|called|commented|argued|felt|observed|lauded|according to)\b", re.I)
def rule_reason(c):
    s = c["sentence"]
    if LITIG.search(s): return "litigation between parties, no lasting mark beyond them"
    if c["tier"] == "B" and CENSOR.search(s) and not PROSE.search(s[:60]): return "routine censorship or rating of the work itself"
    if PROSE.search(s): return "critical or descriptive prose, no institutional act"
    return "lexicon false positive, no institutional reaction"

def phase_marks(kept):
    """Date each mark from its own article's Wikidata item where it has one."""
    titles = sorted({k["mark_article"] for k in kept if k["mark_article"]})
    d = wp({"action": "query", "titles": "|".join(titles), "prop": "pageprops", "ppprop": "wikibase_item", "redirects": 1})
    qid, resolved = {}, {}
    if d:
        norm = {x["from"]: x["to"] for x in d["query"].get("normalized", [])}; red = {x["from"]: x["to"] for x in d["query"].get("redirects", [])}
        pages = {p["title"]: p for p in d["query"]["pages"]}
        for t in titles:
            tt = red.get(norm.get(t, t), norm.get(t, t)); p = pages.get(tt, {})
            resolved[t] = None if p.get("missing") else tt
            if "pageprops" in p: qid[t] = p["pageprops"]["wikibase_item"]
    dates = {}
    if qid:
        url = WDAPI + "?" + urllib.parse.urlencode({"action": "wbgetentities", "ids": "|".join(sorted(set(qid.values()))), "props": "claims", "format": "json"})
        e = http_json(url, endpoint="wikidata") or {"entities": {}}
        for t, q in qid.items():
            cl = e["entities"].get(q, {}).get("claims", {}); best = None
            for prop in ("P571", "P577", "P580", "P585", "P5444", "P3999"):  # inception, publication, start, point in time, date of decision
                for st in cl.get(prop, []):
                    v = st.get("mainsnak", {}).get("datavalue", {}).get("value", {})
                    if isinstance(v, dict) and v.get("time"):
                        y = v["time"][1:11]
                        if best is None or y < best[0]: best = (y, prop)
                if best: break
            if best: dates[t] = best
    # fallback: the infobox of the mark's own article (decided / enacted / founded fields), one parse request a second
    for t in titles:
        if t in dates or not resolved.get(t): continue
        p = wp({"action": "parse", "page": resolved[t], "prop": "wikitext", "section": 0, "redirects": 1})
        wt = (p or {}).get("parse", {}).get("wikitext", "")
        wt = wt.get("*", "") if isinstance(wt, dict) else wt
        m = re.search(r"^\s*\|\s*(DecideDate|DecideYear|decided|decide_date|date_decided|date_enacted|enacted|date_signed|signed|signed date|effective|date_effective|founded|formation|established|first|first played|inception)\s*=\s*[^\n]*?(1[5-9]\d\d|20\d\d)", wt, re.I | re.M)
        if m: dates[t] = (m.group(2), "infobox " + m.group(1))
    return resolved, qid, dates

def phase_review():
    d = json.load(open(P("g2_cands.json"))); cands = d["cands"]; by = {c["key"]: c for c in cands}
    rows, rejected = [], Counter()
    for c in cands:
        ks = [k for k in KEEP if k.split("#")[0] == c["key"]]
        if not ks: rejected[REJECT.get(c["key"]) or rule_reason(c)] += 1; continue
        for k in ks:
            mark, kind, art, fb, disp, notes, ov = KEEP[k]
            rows.append({"gen": "G2", "stone": ov.get("stone", c["stone"]), "stone_article": ov.get("stone_article", c["stone_article"]),
                         "stone_date": ov.get("stone_date", c["stone_date"]), "stone_kind": ov.get("stone_kind", c["stone_kind"]),
                         "mark": mark, "mark_kind": kind, "mark_date": fb, "mark_date_source": "sentence or its paragraph" if fb else "undated",
                         "mark_article": art, "sentence": c["sentence"], "source_article": c["stone_article"], "source_section": c["section"],
                         "source_url": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(c["stone_article"].replace(" ", "_")) + "#" + urllib.parse.quote(c["section"].split(" > ")[-1].replace(" ", "_")),
                         "cause_label": "reason", "order_ok": True, "disputed": disp, "notes": notes, "tier": c["tier"]})
    resolved, qid, dates = phase_marks(rows)
    for r in rows:
        a = r["mark_article"]
        if a and resolved.get(a) is None: r["notes"] = (r["notes"] + " Mark article not found on English Wikipedia; dated from the sentence.").strip(); r["mark_article"] = None
        elif a and a in dates:
            r["mark_date"] = dates[a][0].replace("-00", "-01")
            r["mark_date_source"] = (f"Wikidata {dates[a][1]} of {qid[a]} ({resolved[a]})" if dates[a][1].startswith("P") else f"{dates[a][1]} field of {resolved[a]}"); r["mark_article"] = resolved[a]
        sy = int(r["stone_date"][:4]); my = int(str(r["mark_date"])[:4]) if r["mark_date"] else None
        r["order_ok"] = True if my is None else my >= sy
        if my is None: r["notes"] = (r["notes"] + " Order holds by the sentence's own logic; no date available.").strip()
        r["notes"] = (r["notes"] + f" Lexicon tier {r.pop('tier')}.").strip()
    kept = [r for r in rows if r["order_ok"]]
    for r in rows:
        if not r["order_ok"]: rejected["mark predates the stone (dated from mark article)"] += 1
    out = {"generator": "G2", "works_read": d["works_read"], "sentences_matched": len(cands),
           "sentences_by_tier": dict(Counter(c["tier"] for c in cands)), "kept": kept, "rejected_counts": dict(rejected.most_common())}
    json.dump(out, open(P("g2.json"), "w"), indent=1, ensure_ascii=False)
    print("kept", len(kept), "rejected", sum(rejected.values()), file=sys.stderr)
    for r in kept: print(f"  {r['stone'][:30]:30s} {r['stone_date'][:4]} -> {r['mark'][:70]:70s} {r['mark_date']} [{r['mark_date_source'][:40]}]", file=sys.stderr)

if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "review":
    phase_review()
