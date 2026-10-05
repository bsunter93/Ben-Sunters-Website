"""Surprise score v1 for a stone -> lasting-mark pair, from public structure only (docs/surprise_plan_v1.md).

Two halves, equal weight, no weights fit on any label:

  D, domain distance:  d1 = 1 - cosine(TF-IDF of the stone's lead + categories, the mark's lead + categories,
                             or the evidence sentence when the mark has no article of its own)
                       d2 = 1 - Jaccard(article links out of the stone, article links out of the mark)
  U, unlinkedness:     u1 = 1 - (directions linked between the two articles) / 2
                       u2 = 1 if the stone's lead does not name the mark (or hold its evidence sentence), else 0
                       u3 = 1 if the mark's lead does not name the stone, else 0
                       u4 = 1 - overlap coefficient of the two backlink sets
                            (articles linking to both / the smaller of the two backlink counts)

Every feature becomes a percentile rank (mid-ranks for ties) over all pairs scored in the run where it is available;
d1 is ranked within its document type (mark article or evidence sentence) so a short sentence is not "far" by length.
D is the mean of the available d percentiles, U the mean of the available u percentiles, surprise = (D + U) / 2.

Network: Wikipedia and Wikidata APIs only, the honest user agent, at most one request a second, and a stop on any
HTTP error, refusal or timeout with no same-day retry (a stop marker, as lab/l4_panel.py writes). Raw responses are
cached outside the repository (--cache); only the computed features are committed.

  python3 ripples/lab/discovery/surprise.py --cache /path/to/cache            # fetch, score, evaluate, write
  python3 ripples/lab/discovery/surprise.py --cache /path/to/cache --offline  # rescore from the cache only
"""
import argparse, datetime as dt, hashlib, json, math, os, random, re, sys, time
import urllib.error, urllib.parse, urllib.request

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
WP = "https://en.wikipedia.org/w/api.php"
WD = "https://www.wikidata.org/w/api.php"
PAUSE = 1.05
HERE = os.path.dirname(os.path.abspath(__file__))
RIPPLES = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(RIPPLES, "docs", "results", "surprise_v1.json")
BLOCKED = os.path.join(HERE, "surprise_blocked_dates.txt")
SEED = 20261005


# ---------------------------------------------------------------------------------------------------------------- net
class Stop(Exception):
    pass


class Net:
    def __init__(self, cache, offline):
        self.cache, self.offline, self.last, self.calls, self.hits = cache, offline, 0.0, 0, 0
        os.makedirs(cache, exist_ok=True)
        self.marker = os.path.join(cache, "surprise_stopped")
        today = dt.datetime.now(dt.timezone.utc).date().isoformat()
        dates = set()
        for f in (self.marker, BLOCKED):
            if os.path.exists(f):
                dates |= {l.strip() for l in open(f) if l.strip() and not l.startswith("#")}
        if today in dates and not offline:
            print("a stop was recorded today (UTC); running from the cache only", flush=True)
            self.offline = True

    def get(self, base, params):
        q = dict(params, format="json", formatversion="2")
        url = base + "?" + urllib.parse.urlencode(sorted(q.items()))
        key = os.path.join(self.cache, hashlib.sha1(url.encode()).hexdigest() + ".json")
        if os.path.exists(key):
            self.hits += 1
            return json.load(open(key))
        if self.offline:
            raise Stop("offline and not cached: " + url[:160])
        wait = PAUSE - (time.time() - self.last)
        if wait > 0:
            time.sleep(wait)
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.load(r)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError) as e:
            self.last = time.time()
            day = dt.datetime.now(dt.timezone.utc).date().isoformat()
            open(self.marker, "w").write(day + "\n")
            with open(BLOCKED, "a") as f:
                f.write(day + "\n")
            raise Stop(f"{e} on {url[:160]}; stop marker written, no retry today")
        self.last = time.time()
        self.calls += 1
        if "error" in data:
            raise Stop(f"API error {data['error']} on {url[:160]}")
        json.dump(data, open(key, "w"))
        return data

    def query_all(self, base, params):
        """An action=query call followed through every continuation; yields each response."""
        cont = {}
        while True:
            d = self.get(base, dict(params, **cont))
            yield d
            if "continue" not in d:
                return
            cont = d["continue"]


# --------------------------------------------------------------------------------------------------------- entities
def chunks(xs, n):
    for i in range(0, len(xs), n):
        yield xs[i:i + n]


def fetch_entities(net, titles):
    """Resolve titles and fetch lead, categories, Wikidata id, out-links and redirect titles for each article."""
    titles = sorted({t for t in titles if t})
    canon, ent = {}, {}
    for batch in chunks(titles, 50):
        for d in net.query_all(WP, {"action": "query", "titles": "|".join(batch), "redirects": 1,
                                    "prop": "categories|pageprops", "clshow": "!hidden", "cllimit": "max",
                                    "ppprop": "wikibase_item"}):
            q = d.get("query", {})
            step = {}
            for n in q.get("normalized", []):
                step[n["from"]] = n["to"]
            red = {r["from"]: r["to"] for r in q.get("redirects", [])}
            for t in batch:
                x = step.get(t, t)
                x = red.get(x, x)
                canon.setdefault(t, x)
            for p in q.get("pages", []):
                if p.get("missing") or p.get("invalid"):
                    continue
                e = ent.setdefault(p["title"], {"title": p["title"], "cats": [], "lead": "", "links": [],
                                                "redirects": [], "qid": None})
                e["cats"] += [c["title"].split(":", 1)[1] for c in p.get("categories", [])]
                if p.get("pageprops", {}).get("wikibase_item"):
                    e["qid"] = p["pageprops"]["wikibase_item"]
    for t in titles:
        if canon.get(t) not in ent:
            canon[t] = None
    real = sorted(ent)
    for batch in chunks(real, 20):
        for d in net.query_all(WP, {"action": "query", "titles": "|".join(batch), "prop": "extracts",
                                    "exintro": 1, "explaintext": 1, "exlimit": 20}):
            for p in d.get("query", {}).get("pages", []):
                if p["title"] in ent and p.get("extract"):
                    ent[p["title"]]["lead"] = p["extract"]
        for d in net.query_all(WP, {"action": "query", "titles": "|".join(batch), "prop": "links",
                                    "plnamespace": 0, "pllimit": "max"}):
            for p in d.get("query", {}).get("pages", []):
                if p["title"] in ent:
                    ent[p["title"]]["links"] += [l["title"] for l in p.get("links", [])]
    for batch in chunks(real, 50):
        for d in net.query_all(WP, {"action": "query", "titles": "|".join(batch), "prop": "redirects",
                                    "rdnamespace": 0, "rdlimit": "max", "rdprop": "title"}):
            for p in d.get("query", {}).get("pages", []):
                if p["title"] in ent:
                    ent[p["title"]]["redirects"] += [r["title"] for r in p.get("redirects", [])]
    for t in real:
        e = ent[t]
        e["cats"], e["links"], e["redirects"] = sorted(set(e["cats"])), sorted(set(e["links"])), sorted(set(e["redirects"]))
        e["backlinks"] = linksto(net, [t])
    qids = sorted({e["qid"] for e in ent.values() if e["qid"]})
    p31 = {}
    for batch in chunks(qids, 50):
        d = net.get(WD, {"action": "wbgetentities", "ids": "|".join(batch), "props": "claims"})
        for q, it in d.get("entities", {}).items():
            vals = []
            for c in it.get("claims", {}).get("P31", []):
                v = c.get("mainsnak", {}).get("datavalue", {}).get("value", {})
                if isinstance(v, dict) and v.get("id"):
                    vals.append(v["id"])
            p31[q] = vals
    cls = sorted({c for v in p31.values() for c in v})
    label = {}
    for batch in chunks(cls, 50):
        d = net.get(WD, {"action": "wbgetentities", "ids": "|".join(batch), "props": "labels", "languages": "en"})
        for q, it in d.get("entities", {}).items():
            label[q] = it.get("labels", {}).get("en", {}).get("value", q)
    for e in ent.values():
        e["p31"] = [label.get(c, c) for c in p31.get(e["qid"], [])]
    return canon, ent


def linksto(net, titles):
    """Number of main-namespace articles linking to every title given (CirrusSearch linksto:)."""
    if any('"' in t for t in titles):
        return None
    q = " ".join(f'linksto:"{t}"' for t in titles)
    d = net.get(WP, {"action": "query", "list": "search", "srsearch": q, "srnamespace": 0, "srlimit": 1,
                     "srinfo": "totalhits", "srprop": ""})
    return d.get("query", {}).get("searchinfo", {}).get("totalhits")


# ------------------------------------------------------------------------------------------------------------- text
STOP = set("""a about above after again against all also am an and any are as at be because been before being below
between both but by can could did do does doing down during each few for from further had has have having he her here
hers herself him himself his how i if in into is it its itself just me more most my myself no nor not now of off on
once only or other our ours ourselves out over own same she should so some such than that the their theirs them
themselves then there these they this those through to too under until up very was we were what when where which while
who whom why will with would you your yours yourself yourselves one two three first second new may later known
including however since among within without became become becomes many much several well like used use part s""".split())


def stem(w):
    if len(w) > 4 and w.endswith("ies"):
        return w[:-3] + "y"
    if len(w) > 3 and w.endswith("s") and not w.endswith(("ss", "us", "is")):
        return w[:-1]
    return w


def toks(text):
    return [stem(w) for w in re.findall(r"[a-z]+", text.lower()) if w not in STOP and len(w) > 2]


def core(title):
    return re.sub(r"\s*\([^)]*\)$", "", title or "").strip()


def strip_names(text, names):
    for n in sorted(names, key=len, reverse=True):
        if n:
            text = re.sub(r"(?i)(?<![A-Za-z0-9])" + re.escape(n) + r"(?![A-Za-z0-9])", " ", text)
    return text


def names_in(text, names):
    """True if any name occurs in text: multiword names case-insensitively, one-word names case-sensitively."""
    for n in names:
        n = re.sub(r"^The\s+", "", n.strip())
        if len(n) < 3:
            continue
        flags = re.I if " " in n else 0
        if re.search(r"(?<![A-Za-z0-9])" + re.escape(n) + r"(?![A-Za-z0-9])", text, flags):
            return True
    return False


def shingles(text, k=6):
    w = re.findall(r"[a-z0-9]+", text.lower())
    return {" ".join(w[i:i + k]) for i in range(len(w) - k + 1)}


def clean_sentence(s):
    s = re.sub(r"\[ref\]", " ", s or "")
    s = re.sub(r"&nbsp;", " ", s)
    return re.sub(r"\s+", " ", s).strip()


# ---------------------------------------------------------------------------------------------------------- features
def features(pairs, canon, ent, net):
    """Raw features for each pair. A pair: stone_article, mark_article (or None), sentence, found, stone_label,
    mark_label."""
    docs = {}
    for p in pairs:
        S = ent.get(canon.get(p["stone_article"]) or "")
        if not S:
            p["error"] = "stone article not found"
            continue
        p["stone_title"] = S["title"]
        M = ent.get(canon.get(p.get("mark_article") or "") or "")
        if M and M["title"] == S["title"]:
            M = None  # the mark's "article" is the stone's own article: treat as a mark without one
        p["mark_title"] = M["title"] if M else None
        s_names = {core(S["title"]), p.get("stone_label") or ""} | {r for r in S["redirects"] if " " in r}
        sent = clean_sentence(p.get("sentence"))
        if M:
            m_names = {core(M["title"])} | {r for r in M["redirects"] if " " in r}
            if p.get("mark_label") and p["mark_label"].lower() in sent.lower():
                m_names.add(p["mark_label"])
        else:
            m_names = {p["mark_label"]} if p.get("mark_label") and p["mark_label"].lower() in sent.lower() else set()
        p["stone_doc"] = S["lead"] + " " + " ".join(S["cats"])
        if M:
            p["mark_doc"], p["doc_type"] = strip_names(M["lead"] + " " + " ".join(M["cats"]), s_names), "article"
        else:
            p["mark_doc"], p["doc_type"] = strip_names(sent, s_names), "sentence"
        f = {}
        # d2, u1, u3, u4 need the mark's own article
        if M:
            ls, lm = set(S["links"]) - {M["title"]}, set(M["links"]) - {S["title"]}
            f["d2"] = 1 - (len(ls & lm) / len(ls | lm)) if (ls | lm) else None
            s_all = {S["title"]} | set(S["redirects"])
            m_all = {M["title"]} | set(M["redirects"])
            dirs = int(bool(set(S["links"]) & m_all)) + int(bool(set(M["links"]) & s_all))
            f["u1"] = 1 - dirs / 2
            f["u3"] = 0 if names_in(M["lead"], s_names) else 1
            bs, bm = S.get("backlinks"), M.get("backlinks")
            both = linksto(net, [S["title"], M["title"]]) if (bs and bm) else None
            f["cocite"], f["bl_stone"], f["bl_mark"] = both, bs, bm
            f["u4"] = 1 - min(1.0, both / min(bs, bm)) if (both is not None and bs and bm) else None
        else:
            f.update(d2=None, u1=None, u3=None, u4=None, cocite=None, bl_stone=S.get("backlinks"), bl_mark=None)
        in_lead = names_in(S["lead"], m_names) if m_names else False
        if not in_lead and p.get("found") == "forward" and sent:
            in_lead = bool(shingles(sent) & shingles(S["lead"]))
        f["u2"] = 0 if in_lead else 1
        p["f"] = f
        p["stone_class"] = S.get("p31", [])
        p["mark_class"] = M.get("p31", []) if M else []
        p["mark_has_article"] = bool(M)
        docs[("S", S["title"])] = p["stone_doc"]
        docs[("M", p["id"])] = p["mark_doc"]
    # d1: TF-IDF cosine over every document in the run
    tf = {k: toks(v) for k, v in docs.items()}
    df = {}
    for t in tf.values():
        for w in set(t):
            df[w] = df.get(w, 0) + 1
    N = len(tf)
    idf = {w: math.log((N + 1) / (c + 1)) + 1 for w, c in df.items()}

    def vec(t):
        c = {}
        for w in t:
            c[w] = c.get(w, 0) + 1
        v = {w: n * idf[w] for w, n in c.items()}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1.0
        return {w: x / norm for w, x in v.items()}

    vecs = {k: vec(t) for k, t in tf.items()}
    for p in pairs:
        if "f" not in p:
            continue
        a, b = vecs[("S", p["stone_title"])], vecs[("M", p["id"])]
        cos = sum(x * b.get(w, 0.0) for w, x in a.items()) if b else 0.0
        p["f"]["d1"] = 1 - cos
        p["f"]["specificity"] = 1.0 if p["mark_has_article"] else (
            0.5 if p.get("mark_kind") in ("Law", "Institution", "Regulation", "Treaty", "Policy", "Legal") else 0.0)


def percentile(values):
    """Mid-rank percentile in (0, 1) for each non-None value; None stays None."""
    idx = [i for i, v in enumerate(values) if v is not None]
    srt = sorted(idx, key=lambda i: values[i])
    out = [None] * len(values)
    i = 0
    while i < len(srt):
        j = i
        while j + 1 < len(srt) and values[srt[j + 1]] == values[srt[i]]:
            j += 1
        r = (i + j) / 2 + 0.5
        for k in range(i, j + 1):
            out[srt[k]] = r / len(srt)
        i = j + 1
    return out


def score(pairs):
    """Percentiles are taken over unique pairs, so a pair listed in two sets counts once."""
    ok = [p for p in pairs if "f" in p]
    uniq = {}
    for p in ok:
        uniq.setdefault(pair_key(p), p)
    u = list(uniq.values())
    pct = {k: {} for k in uniq}
    for name in ("d2", "u1", "u2", "u3", "u4"):
        for p, q in zip(u, percentile([p["f"][name] for p in u])):
            pct[pair_key(p)][name] = q
    for dtype in ("article", "sentence"):
        grp = [p for p in u if p["doc_type"] == dtype]
        for p, q in zip(grp, percentile([p["f"]["d1"] for p in grp])):
            pct[pair_key(p)]["d1"] = q
    for p in ok:
        pc = p["pct"] = dict(pct[pair_key(p)])
        d = [pc[k] for k in ("d1", "d2") if pc.get(k) is not None]
        uu = [pc[k] for k in ("u1", "u2", "u3", "u4") if pc.get(k) is not None]
        p["D"] = sum(d) / len(d) if d else None
        p["U"] = sum(uu) / len(uu) if uu else None
        halves = [x for x in (p["D"], p["U"]) if x is not None]
        p["surprise"] = sum(halves) / len(halves)
    order = sorted(u, key=lambda p: -p["surprise"])
    rank = {pair_key(p): i for i, p in enumerate(order, 1)}
    for p in ok:
        p["rank_all"] = rank[pair_key(p)]


# -------------------------------------------------------------------------------------------------------- statistics
def auc(pos, neg):
    if not pos or not neg:
        return None
    s = sum(1.0 if a > b else 0.5 if a == b else 0.0 for a in pos for b in neg)
    return s / (len(pos) * len(neg))


def perm_p(pos, neg, n=20000):
    obs, allv, k = auc(pos, neg), pos + neg, len(pos)
    rng, hit = random.Random(SEED), 0
    for _ in range(n):
        rng.shuffle(allv)
        if auc(allv[:k], allv[k:]) >= obs - 1e-12:
            hit += 1
    return (hit + 1) / (n + 1)


def boot_ci(pos, neg, n=2000):
    rng, out = random.Random(SEED), []
    for _ in range(n):
        out.append(auc([rng.choice(pos) for _ in pos], [rng.choice(neg) for _ in neg]))
    out.sort()
    return [round(out[int(0.025 * n)], 3), round(out[int(0.975 * n) - 1], 3)]


def ranks(xs):
    return [r for r in percentile(xs)]


def spearman(x, y):
    rx, ry = ranks(x), ranks(y)
    mx, my = sum(rx) / len(rx), sum(ry) / len(ry)
    cov = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    vx, vy = sum((a - mx) ** 2 for a in rx), sum((b - my) ** 2 for b in ry)
    return cov / math.sqrt(vx * vy) if vx and vy else None


def evaluate(items, key="surprise", full=True):
    pos = [p[key] for p in items if p["label"] == 1 and p.get(key) is not None]
    neg = [p[key] for p in items if p["label"] == 0 and p.get(key) is not None]
    r = {"n": len(pos) + len(neg), "positives": len(pos), "auc": round(auc(pos, neg), 3) if pos and neg else None}
    if full and pos and neg:
        r["p_one_sided"] = round(perm_p(pos, neg), 4)
        r["ci95"] = boot_ci(pos, neg)
    return r


# -------------------------------------------------------------------------------------------------------------- sets
# The first blind round (Oct 3, 2026): fifteen work -> law names went to the owner; the per-pair list was not recorded.
# Twelve are reconstructed (docs/surprise_plan_v1.md, "Evaluation sets"): grade 2 strictly non-obvious, 1 medium,
# 0 left out. Mark articles follow the registered rule: the law's own article; else the law step of the chain built
# from the pair; else the top exact-phrase search hit that is not the stone's own article.
BLIND = [
    ("Victim (1961 film)", "Sexual Offences Act 1967", 2),
    ("The Daily Show", "James Zadroga 9/11 Health and Compensation Act", 2),
    ("Ocean with David Attenborough", "High Seas Treaty", 2),
    ("Manhunt (video game)", "Digital Economy Act 2010", 2),
    ("Cathy Come Home", "Homelessness Reduction Act 2017", 1),
    ("Quincy, M.E.", "Orphan Drug Act of 1983", 1),
    ("My Octopus Teacher", "Animal Welfare (Sentience) Act 2022", 1),
    ("60 Minutes", "STOCK Act", 1),
    ("The West Wing", "Racial and Religious Hatred Act 2006", 1),
    ("Silent Spring", "National Environmental Policy Act", 1),
    ("Rangila Rasul", "Section 295A of the Indian Penal Code", 0),
    ("Holy Deadlock", "Matrimonial Causes Act 1937", 0),
]
# Candidates for the three blind-round names that cannot be identified (sensitivity only).
BLIND_FILL = [
    ("JFK (film)", "President John F. Kennedy Assassination Records Collection Act of 1992"),
    ("A Nation of Immigrants", "Hart-Celler Act"),
    ("Adolescence (TV series)", "Children's Wellbeing and Schools Act 2026"),
    ("McMafia", "Sanctions and Anti-Money Laundering Act 2018"),
    ("The Descent of Man, and Selection in Relation to Sex", "Butler Act"),
    ("The Caine Mutiny", "Twenty-fifth Amendment to the United States Constitution"),
]
# Which run put each engine mark into demo/discovered_wiki.json (lab/discovery/build_wiki.py, build_wiki2.py,
# build_wiki3.py). Stones not listed under V1_1 or CULTURE are v1; these marks on v1 stones came later.
V1_1 = {"september-11", "chernobyl-disaster", "bhopal", "challenger", "rana-plaza", "oklahoma-city", "virginia-tech",
        "parkland", "uvalde", "boston-marathon", "pulse", "las-vegas-2017", "enron", "cambridge-analytica", "metoo",
        "camp-fire", "lac-megantic", "volkswagen", "dear-zachary", "grenfell", "hurricane-sandy", "cathy-come-home"}
CULTURE = {"frozen-culture", "game-of-thrones", "finding-nemo", "101-dalmatians", "sideways", "queens-gambit",
           "top-gun", "pokemon-go", "jurassic-park", "avatar-2009", "fifty-shades", "da-vinci-code", "mad-men",
           "bake-off", "hamilton", "furby", "tetris", "zumba", "woodstock", "13-reasons-why", "blue-planet-ii",
           "emily-in-paris"}
LATE = {("flint-lead-pipes", "Child Lead Exposure Elimination Commission"): "v1.1",
        ("flint-lead-pipes", "BlueConduit"): "v1.1", ("love-canal-superfund", "LCARA"): "v1.1",
        ("an-inconvenient-truth", "Carbon-offset purchases"): "culture"}
# The screens' non-obvious tags, as the result documents name them.
NONOBV_V1_1 = {("enron", "Tax code section 409A"),
               ("enron", "UK Companies (Audit, Investigations and Community Enterprise) Act"),
               ("metoo", "Indonesia's Sexual Violence Crime Act"),
               ("bhopal", "International Medical Commission on Bhopal"), ("challenger", "NASA Office of Safety"),
               ("chernobyl-disaster", "Early Notification Convention"), ("chernobyl-disaster", "Joint Convention"),
               ("boston-marathon", "One Boston Day"), ("oklahoma-city", "Victim Allocution Clarification Act"),
               ("parkland", "Florida's death-penalty unanimity repeal"),
               ("camp-fire", "Chico's price-gouging ordinance"), ("camp-fire", "California's wildfire fund (AB 1054)"),
               ("love-canal-superfund", "LCARA"), ("dear-zachary", "Bill C-464"),
               ("cambridge-analytica", "Social Science One"),
               ("flint-lead-pipes", "Child Lead Exposure Elimination Commission")}
NONOBV_CULTURE = {("sideways", "The Sideways effect"), ("bake-off", "Baking sales"), ("furby", "The NSA's Furby ban"),
                  ("jurassic-park", "The Toronto Raptors' name"), ("blue-planet-ii", "Marine biology applications"),
                  ("an-inconvenient-truth", "Carbon-offset purchases"), ("pokemon-go", "New York's parole rule"),
                  ("pokemon-go", "Iran's ban"), ("hamilton", "Hamilton Education Program")}
NONOBV_V1 = {("west-wing-hatred-act", "Racial and Religious Hatred Act 2006"),
             ("columbine-active-shooter", "New Jersey anti-bullying law"), ("fukushima", "Korea's NSSC")}
# v1's forward screen also called these two non-obvious (sensitivity only).
NONOBV_V1_FORWARD = {("cathy-come-home", "Crisis"), ("flint-lead-pipes", "BlueConduit")}


def build_pairs():
    pairs = []
    wiki = json.load(open(os.path.join(RIPPLES, "demo", "discovered_wiki.json")))
    for slug, s in wiki["stones"].items():
        for m in s["marks"]:
            key = (slug, m["label"])
            run = LATE.get(key) or ("v1.1" if slug in V1_1 else "culture" if slug in CULTURE else "v1")
            pairs.append({"id": f"wiki:{slug}:{m['id']}", "set": "engine", "run": run, "slug": slug,
                          "stone_label": s["stone"], "stone_article": s["article"], "mark_label": m["label"],
                          "mark_article": m.get("mark_article"), "mark_kind": m.get("kind"),
                          "sentence": m.get("sentence"), "found": m.get("found"), "grade": m.get("grade", "reported"),
                          "precision": m.get("precision")})
    for i, (st, mk, g) in enumerate(BLIND):
        pairs.append({"id": f"blind:{i}", "set": "blind", "stone_label": core(st), "stone_article": st,
                      "mark_label": core(mk), "mark_article": mk, "mark_kind": "Law", "owner_grade": g,
                      "found": "record"})
    mf = json.load(open(os.path.join(RIPPLES, "docs", "results", "mark_first_v1_1.json")))
    seen = set()
    for x in mf["pairs"]:
        if not (x.get("ordered") and x.get("causal_score", 0) > 0 and not x.get("news") and not x.get("reversed")):
            continue
        k = (x["work"], x["mark"])
        if k in seen:
            continue
        seen.add(k)
        pairs.append({"id": f"markfirst:{len(seen) - 1}", "set": "pool_mark_first", "stone_label": core(x["work"]),
                      "stone_article": x["work"], "mark_label": core(x["mark"]), "mark_article": x["mark"],
                      "mark_kind": "Law", "sentence": x.get("sentence"), "found": "reverse"})
    ba = json.load(open(os.path.join(RIPPLES, "docs", "results", "bill_act_v1.json")))
    seen = set()
    for x in ba["pairs"]:
        if not x.get("ordered"):
            continue
        k = (x["work"], x["act"])
        if k in seen:
            continue
        seen.add(k)
        act = re.sub(r"\s*\(.*$", "", x["act"]) if "(within" in x["act"] or "(repealed" in x["act"] else x["act"]
        pairs.append({"id": f"billact:{len(seen) - 1}", "set": "pool_bill_act", "stone_label": core(x["work"]),
                      "stone_article": x["work"], "mark_label": act, "mark_article": act, "mark_kind": "Law",
                      "sentence": x.get("sentence"), "found": "hansard", "cite_label": x.get("cite_label")})
    for i, (st, mk) in enumerate(BLIND_FILL):
        pairs.append({"id": f"blindfill:{i}", "set": "blind_fill", "stone_label": core(st), "stone_article": st,
                      "mark_label": core(mk), "mark_article": mk, "mark_kind": "Law", "found": "record"})
    return pairs


def pair_key(p):
    return (p["stone_title"], p["mark_title"] or ("sentence:" + p["id"]))


def dedupe(pairs):
    """A pool or fill pair that repeats an earlier pair (same stone and mark article) is scored once, under the earlier
    set. Blind-round and engine pairs are all kept (three appear in both)."""
    order = {"blind": 0, "engine": 1, "blind_fill": 2, "pool_mark_first": 3, "pool_bill_act": 4}
    keep, seen = [], {}
    for p in sorted(pairs, key=lambda p: order[p["set"]]):
        if "f" not in p:
            keep.append(p)
            continue
        k = pair_key(p)
        if k in seen and p["set"] not in ("blind", "engine"):
            seen[k].setdefault("also_in", []).append(p["set"])
            continue
        seen.setdefault(k, p)
        keep.append(p)
    return keep


# ---------------------------------------------------------------------------------------------------------- evaluate
def label_sets(pairs):
    by = {p["id"]: p for p in pairs}
    blind = [dict(p, label=int(p["owner_grade"] == 2)) for p in pairs if p["set"] == "blind" and "f" in p]
    eng = [p for p in pairs if p["set"] == "engine" and "f" in p]

    def tag(p, pos):
        return dict(p, label=int((p["slug"], p["mark_label"]) in pos))
    v11 = [tag(p, NONOBV_V1_1) for p in eng if p["run"] == "v1.1"]
    cul = [tag(p, NONOBV_CULTURE) for p in eng if p["run"] == "culture" and p["grade"] != "disputed"]
    v1 = [tag(p, NONOBV_V1) for p in eng if p["run"] == "v1"]
    return blind, v11, cul, v1, by


def run_eval(pairs):
    blind, v11, cul, v1, by = label_sets(pairs)
    pooled = v11 + cul
    res = {"primary": {}, "secondary": {}, "sensitivity": {}, "exploratory": {}}
    res["primary"]["blind_round_auc"] = evaluate(blind)
    res["primary"]["blind_round_spearman_grade"] = round(spearman([p["surprise"] for p in blind],
                                                                  [p["owner_grade"] for p in blind]), 3)
    res["primary"]["pooled_tags_auc"] = evaluate(pooled)
    res["primary"]["bar"] = {"blind_round_auc_min": 0.75, "pooled_tags_auc_min": 0.70}
    b, q = res["primary"]["blind_round_auc"]["auc"], res["primary"]["pooled_tags_auc"]["auc"]
    res["primary"]["blind_round_pass"] = b is not None and b >= 0.75
    res["primary"]["pooled_tags_pass"] = q is not None and q >= 0.70
    res["primary"]["met"] = res["primary"]["blind_round_pass"] and res["primary"]["pooled_tags_pass"]
    res["secondary"]["v1_1_tags_auc"] = evaluate(v11)
    res["secondary"]["culture_tags_auc"] = evaluate(cul)
    res["secondary"]["v1_builder_tags_auc"] = evaluate(v1)
    res["secondary"]["all_tags_auc"] = evaluate(pooled + v1)
    # sensitivity
    sw = [dict(p, label=int(p["stone_article"] in ("Victim (1961 film)", "The Daily Show", "Manhunt (video game)",
                                                   "My Octopus Teacher"))) for p in blind]
    res["sensitivity"]["blind_octopus_for_ocean"] = evaluate(sw)
    bo = [dict(p, label=int(p["owner_grade"] == 2 or p["stone_article"] == "My Octopus Teacher")) for p in blind]
    res["sensitivity"]["blind_octopus_and_ocean"] = evaluate(bo)
    fills = [p for p in pairs if (p["set"] == "blind_fill" or "blind_fill" in p.get("also_in", [])) and "f" in p]
    fills = [dict(p, label=0) for p in fills]
    aucs = []
    if len(fills) >= 3:
        import itertools
        for tri in itertools.combinations(fills, 3):
            aucs.append(evaluate(blind + list(tri), full=False)["auc"])
    res["sensitivity"]["blind_with_three_unknown_filled"] = {
        "candidates": [p["stone_article"] + " -> " + (p["mark_title"] or p["mark_label"]) for p in fills],
        "triples": len(aucs), "auc_min": min(aucs) if aucs else None,
        "auc_median": sorted(aucs)[len(aucs) // 2] if aucs else None, "auc_max": max(aucs) if aucs else None}
    pl = [dict(p, label=int(p["label"] or (p["slug"], p["mark_label"]) == ("blue-planet-ii", "The plastics turn")))
          for p in pooled]
    res["sensitivity"]["pooled_plastics_positive"] = evaluate(pl, full=False)
    tg = [p for p in pairs if p["set"] == "engine" and p.get("grade") == "disputed" and "f" in p]
    res["sensitivity"]["pooled_with_disputed_top_gun"] = evaluate(pooled + [dict(p, label=0) for p in tg], full=False)
    un = [dict(p, label=int(p["label"] or (p["slug"], p["mark_label"]) in NONOBV_V1_FORWARD)) for p in pooled]
    res["sensitivity"]["pooled_union_builder_tags"] = evaluate(un, full=False)
    # exploratory: each half and each feature alone
    for name, items in (("blind", blind), ("pooled", pooled)):
        ex = {}
        for k in ("D", "U"):
            ex[k] = evaluate(items, key=k, full=False)["auc"]
        for k in ("d1", "d2", "u1", "u2", "u3", "u4", "specificity"):
            its = [dict(p, _k=p["f"][k]) for p in items if p["f"].get(k) is not None]
            ex[k] = evaluate(its, key="_k", full=False)
        res["exploratory"][name] = ex
    # exploratory: the bill_act pool by citation label
    ba = [p for p in pairs if p["set"] == "pool_bill_act" and "f" in p]
    lab = {}
    for c in ("reason", "context", "aside"):
        xs = sorted(p["surprise"] for p in ba if p.get("cite_label") == c)
        lab[c] = {"n": len(xs), "median_surprise": round(xs[len(xs) // 2], 3) if xs else None}
    res["exploratory"]["bill_act_by_citation_label"] = lab
    return res, blind, pooled, v1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", required=True, help="directory for raw API responses (outside the repository)")
    ap.add_argument("--offline", action="store_true")
    ap.add_argument("--only", help="comma-separated pair sets to score (testing)")
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args()
    net = Net(a.cache, a.offline)
    pairs = build_pairs()
    if a.only:
        pairs = [p for p in pairs if p["set"] in a.only.split(",")]
    titles = {p["stone_article"] for p in pairs} | {p["mark_article"] for p in pairs if p.get("mark_article")}
    try:
        canon, ent = fetch_entities(net, sorted(titles))
        features(pairs, canon, ent, net)
    except Stop as e:
        print("STOPPED:", e, flush=True)
        sys.exit(2)
    pairs = dedupe(pairs)
    score(pairs)
    out = {"protocol": "ripples/docs/surprise_plan_v1.md", "run_utc": dt.datetime.now(dt.timezone.utc).isoformat(
        timespec="seconds"), "requests": net.calls, "cache_hits": net.hits,
        "formula": "surprise = (D + U) / 2; D = mean pct(d1, d2); U = mean pct(u1, u2, u3, u4); pct = mid-rank "
                   "percentile over every pair scored where the feature exists (d1 within its document type)"}
    if not a.only:
        res, blind, pooled, v1 = run_eval(pairs)
        out["evaluation"] = res
    eng = sorted([p for p in pairs if p["set"] == "engine" and "f" in p], key=lambda p: -p["surprise"])
    for r, p in enumerate(eng, 1):
        p["rank_engine"] = r
    keep = ("id", "set", "run", "slug", "stone_label", "stone_title", "mark_label", "mark_title", "mark_kind",
            "found", "grade", "owner_grade", "cite_label", "doc_type", "stone_class", "mark_class", "also_in",
            "error", "f", "pct", "D", "U", "surprise", "rank_all", "rank_engine")
    rows = []
    for p in sorted(pairs, key=lambda p: p.get("rank_all", 10 ** 6)):
        row = {k: p[k] for k in keep if k in p and p[k] not in (None, [], "")}
        for k in ("f", "pct"):
            if k in row:
                row[k] = {kk: (round(v, 4) if isinstance(v, float) else v) for kk, v in row[k].items()}
        for k in ("D", "U", "surprise"):
            if k in row:
                row[k] = round(row[k], 4)
        if "mark_title" not in row and p.get("sentence"):
            row["sentence"] = clean_sentence(p["sentence"])[:240]
        rows.append(row)
    out["pairs"] = rows
    json.dump(out, open(a.out, "w"), indent=1, ensure_ascii=False)
    print(f"{len(rows)} pairs, {net.calls} requests, {net.hits} cache hits -> {a.out}", flush=True)
    if "evaluation" in out:
        print(json.dumps(out["evaluation"]["primary"], indent=1))


if __name__ == "__main__":
    main()
