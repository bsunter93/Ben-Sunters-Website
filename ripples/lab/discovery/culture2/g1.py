"""G1 REVERSE: find Wikipedia articles whose text gives a cultural work (film, TV show, episode, game, song, book, toy,
viral video) as the REASON an institution, law, rule, team, agency or policy exists or changed.

Phrase list is fixed below before any run. Honest UA. Search API one request every 2 seconds with maxlag=5; other
endpoints one a second. Any 403/429/5xx stops that endpoint for the day (no retry, no other UA).

Usage:
  python3 g1.py search            # run every fixed phrase, save g1_hits.json
  python3 g1.py triage            # keyword-score snippets, print for strict human reading
  python3 g1.py context picks.json   # fetch the sentence + section for picked (title, phrase) pairs
  python3 g1.py date "Title" ...  # print infobox/lead date for articles (stone or mark)
"""
import json, re, sys, time, os, html, urllib.parse, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
API = "https://en.wikipedia.org/w/api.php"
STOPFILE = os.path.join(HERE, "g1_stopped.json")

# ---- FIXED PHRASE LIST (written before the first run; do not edit after) ----
PHRASES = [
    # in response / in reaction
    "in response to the film", "in response to the movie", "in response to the television series",
    "in response to the TV series", "in response to the show", "in response to the episode",
    "in response to the documentary", "in response to the video game", "in response to the song",
    "in response to the novel", "in response to the book", "in response to the music video",
    "in reaction to the film", "in reaction to the video game", "in reaction to the television",
    "in reaction to the episode", "in reaction to the documentary", "in reaction to the song",
    # naming
    "named after the film", "named after the movie", "named after the television series",
    "named after the television show", "named after the TV show", "named after the TV series",
    "named after the video game", "named after the song", "named after the novel", "named after the cartoon",
    "named for the film", "named for the television", "named after the sitcom", "named after the toy",
    # inspired / after watching
    "inspired by the film", "inspired by the television series", "inspired by the documentary",
    "inspired by the episode", "after watching the film", "after watching the documentary",
    "after watching the episode", "after seeing the film", "after watching the movie", "after seeing the documentary",
    # broadcast / release
    "following the broadcast of", "after the broadcast of", "following the airing of", "after the episode aired",
    "after the episode", "after the release of the song", "after the release of the film",
    "following the release of the film", "following the release of the game", "following the documentary",
    "after the documentary", "following the film", "after the film",
    # prompted
    "the episode prompted", "the game prompted", "the song prompted", "the documentary prompted",
    "the film prompted", "the movie prompted", "the series prompted", "the show prompted",
    "the novel prompted", "the book prompted", "the video prompted", "the broadcast prompted",
    "prompted by the film", "prompted by the episode", "prompted by the documentary", "prompted by the television",
    "prompted by the song", "prompted by the video game", "prompted by the game",
    # led to
    "the film led to", "the series led to", "the show led to", "the documentary led to", "the episode led to",
    "the song led to", "the game led to", "the book led to", "the novel led to", "the movie led to",
    # cited / credited / blamed
    "credited the film", "cited the film", "credited the television", "credited the documentary",
    "cited the documentary", "credited the show", "cited the episode", "blamed the film",
    "blamed the video game", "blamed the show",
    # popularity / wake
    "due to the popularity of the film", "due to the popularity of the show", "due to the popularity of the series",
    "due to the popularity of the game", "the popularity of the film led", "the popularity of the show led",
    "the popularity of the series led", "in the wake of the film", "in the wake of the show",
    "in the wake of the series", "in the wake of the documentary", "spurred by the film", "sparked by the film",
    "fueled by the film",
]
SEARCH_LIMIT = 100   # per page
MAX_PAGES = 2        # up to 200 hits per phrase

_last = {"search": 0.0, "other": 0.0}
GAP = {"search": 2.1, "other": 1.1}

def stopped():
    return json.load(open(STOPFILE)) if os.path.exists(STOPFILE) else {}

def get(params, endpoint="other"):
    st = stopped()
    if endpoint in st:
        raise RuntimeError(f"endpoint {endpoint} stopped for the day: {st[endpoint]}")
    wait = GAP[endpoint] - (time.time() - _last[endpoint])
    if wait > 0: time.sleep(wait)
    p = dict(params, format="json", formatversion="2", maxlag="5")
    url = API + "?" + urllib.parse.urlencode(p)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    _last[endpoint] = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code in (403, 429) or e.code >= 500:
            st[endpoint] = f"HTTP {e.code} at {time.strftime('%H:%M:%S')}"
            json.dump(st, open(STOPFILE, "w"))
        raise
    if "error" in d and d["error"].get("code") == "maxlag":
        time.sleep(6); _last[endpoint] = time.time()
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.loads(r.read().decode("utf-8"))
    return d

def strip(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s or ""))

def cmd_search():
    out = {"phrases": {}, "queries": 0}
    path = os.path.join(HERE, "g1_hits.json")
    if os.path.exists(path): out = json.load(open(path))
    for ph in PHRASES:
        if ph in out["phrases"]: continue
        hits, total, offset = [], 0, 0
        for page in range(MAX_PAGES):
            d = get({"action": "query", "list": "search", "srsearch": f'"{ph}"', "srlimit": SEARCH_LIMIT,
                     "sroffset": offset, "srprop": "snippet|sectiontitle", "srnamespace": 0}, "search")
            out["queries"] += 1
            q = d.get("query", {}); total = q.get("searchinfo", {}).get("totalhits", 0)
            for h in q.get("search", []):
                hits.append({"title": h["title"], "snippet": strip(h.get("snippet")), "section": h.get("sectiontitle", "")})
            if "continue" not in d: break
            offset = d["continue"]["sroffset"]
        out["phrases"][ph] = {"total": total, "hits": hits}
        print(f"{ph:45s} total {total:6d} kept {len(hits)}", flush=True)
        json.dump(out, open(path, "w"), indent=0)
    print("queries", out["queries"], "hits", sum(len(v["hits"]) for v in out["phrases"].values()))

INST = re.compile(r"\b(laws?|act|acts|bill|legislat\w*|bann?ed|bans?|prohibit\w*|outlaw\w*|regulat\w*|rules?|ruled|ruling|"
                  r"polic(y|ies)|guidelines?|standards?|agency|commission|department|ministry|government|council|parliament|"
                  r"congress|senate|court|lawsuit|statute|ordinance|amend\w*|team|club|league|franchise|renamed|mascot|"
                  r"foundation|charity|organi[sz]ation|founded|established|created|formed|program(me)?|military|army|navy|"
                  r"air force|police|FBI|CIA|NSA|FCC|FDA|NASA|warning|label|curriculum|holiday|designated|declared|"
                  r"official(ly)?|ordered|required|mandat\w*|introduced|passed|signed|enacted|restrict\w*|forbid\w*|"
                  r"prison|school|university|hospital|church|pope|vatican|airline|airport|navy|ship)\b", re.I)
NOISE = re.compile(r"\b(box office|grossed|ratings|viewers|sales|sold|soundtrack|sequel|remake|DVD|Blu-ray|nominated|award)\b", re.I)

def cmd_triage(minscore=2):
    d = json.load(open(os.path.join(HERE, "g1_hits.json")))
    seen, rows = set(), []
    for ph, v in d["phrases"].items():
        for h in v["hits"]:
            key = (h["title"], ph)
            if key in seen: continue
            seen.add(key)
            s = h["snippet"]
            score = len(set(m.group(0).lower() for m in INST.finditer(s))) - len(NOISE.findall(s))
            if re.match(r"^(List of|Lists of)", h["title"]): score -= 2
            rows.append((score, ph, h["title"], h["section"], s))
    rows = [r for r in rows if r[0] >= minscore]
    rows.sort(key=lambda r: (-r[0], r[1]))
    for r in rows:
        print(f"[{r[0]}] {r[1]} || {r[2]} || {r[3]} || {r[4]}")
    print("rows", len(rows), file=sys.stderr)

def plaintext(title):
    d = get({"action": "query", "prop": "extracts", "explaintext": 1, "exsectionformat": "wiki", "titles": title, "redirects": 1})
    pages = d.get("query", {}).get("pages", [])
    return (pages[0].get("title", title), pages[0].get("extract", "")) if pages else (title, "")

def sentence_with(text, phrase):
    """Return (sentence, section) for the first sentence containing the phrase (case-insensitive)."""
    section = "(lead)"
    for line in text.split("\n"):
        m = re.match(r"^=+\s*(.*?)\s*=+$", line.strip())
        if m: section = m.group(1); continue
        if phrase.lower() in line.lower():
            sents = re.split(r"(?<=[.!?])\s+(?=[A-Z\"'])", line)
            for i, s in enumerate(sents):
                if phrase.lower() in s.lower():
                    ctx = " ".join(sents[max(0, i - 1): i + 2])
                    return s.strip(), section, ctx.strip()
    return None, None, None

def cmd_context(picks_path):
    picks = json.load(open(picks_path))
    out = []
    for p in picks:
        title, phrase = p["title"], p["phrase"]
        real, txt = plaintext(title)
        s, sec, ctx = sentence_with(txt, p.get("find", phrase))
        out.append(dict(p, real_title=real, sentence=s, section=sec, context=ctx))
        print(f"## {real} [{sec}]\n   {ctx}\n", flush=True)
    json.dump(out, open(picks_path.replace(".json", "_ctx.json"), "w"), indent=1)

DATEKEYS = (r"enacted|date_enacted|date_signed|signed|royal_assent|date_of_royal_assent|ratified|adopted|date_adopted|formed|"
            r"founded|established|date_established|effective|date_effective|date_passed|passed|formation|date_formed|"
            r"inception|start_date|created|date_created|opened|date_opened|released|release_date|released_date|"
            r"first_aired|airdate|air_date|published|pub_date|release|date|first_run|premiere|years|launched|introduced|"
            r"first_date|venue_date|decided|date_decided|DecideDate|DecideYear")

def article_date(title):
    d = get({"action": "parse", "page": title, "prop": "wikitext", "section": 0, "redirects": 1})
    wt = d.get("parse", {}).get("wikitext", "")
    if isinstance(wt, dict): wt = wt.get("*", "")
    for m in re.finditer(r"^\s*\|\s*(" + DATEKEYS + r")\s*=\s*([^\n]*)", wt, re.I | re.M):  # infobox params only (line start)
        y = re.search(r"\b(1[5-9]\d\d|20\d\d)\b", m.group(2))
        if y:
            return y.group(1), f"infobox {m.group(1)}: {m.group(2)[:80].strip()}"
    txt = re.sub(r"\{\{[^{}]*\}\}", "", wt)
    ys = re.findall(r"\b(1[5-9]\d\d|20\d\d)\b", txt[:3000])
    return (ys[0], "lead first year") if ys else (None, "none")

def cmd_date(titles):
    res = {}
    for t in titles:
        try:
            y, how = article_date(t)
        except Exception as e:
            y, how = None, f"error {e}"
        res[t] = (y, how)
        print(f"{t} => {y} ({how})", flush=True)
    return res

def cmd_deepen(cap=1000):
    """Page further into the SAME fixed phrases whose totals exceed what pass one kept (no new phrases)."""
    path = os.path.join(HERE, "g1_hits.json"); out = json.load(open(path))
    for ph in PHRASES:
        v = out["phrases"][ph]; have = len(v["hits"])
        if v["total"] <= have or have >= cap: continue
        offset = have
        while offset < min(v["total"], cap):
            d = get({"action": "query", "list": "search", "srsearch": f'"{ph}"', "srlimit": SEARCH_LIMIT,
                     "sroffset": offset, "srprop": "snippet|sectiontitle", "srnamespace": 0}, "search")
            out["queries"] += 1
            for h in d.get("query", {}).get("search", []):
                v["hits"].append({"title": h["title"], "snippet": strip(h.get("snippet")), "section": h.get("sectiontitle", "")})
            if "continue" not in d: break
            offset = d["continue"]["sroffset"]
        print(f"{ph:45s} total {v['total']:6d} now {len(v['hits'])}", flush=True)
        json.dump(out, open(path, "w"), indent=0)
    print("queries", out["queries"], "hits", sum(len(v["hits"]) for v in out["phrases"].values()))

# ---- STRICT READ RESULTS (filled in by hand after reading every candidate sentence in full) ----
# Columns: stone, stone_article, stone_date, stone_kind, mark, mark_kind, mark_date, mark_date_source, mark_article,
#          sentence, source_article, source_section, notes
KEPT = [
 ("Rififi", "Rififi", "1955-04-13", "film", "Rifamycin class of antibiotics (incl. rifampicin) named after the film", "drug name (scientific nomenclature)", "1957", "Rifampicin, History: 'In 1957, a soil sample ... was brought ... to the Lepetit Pharmaceuticals research lab'", "Rifamycin",
  "Because Sensi, Timbal and the researchers were particularly fond of the French crime story Rififi (about a jewel heist and rival gangs), they decided to call these compounds rifamycins.", "Rifampicin", "History",
  "Rifamycin lead also: 'The name rifamycin (originally rifomycin) was derived from the 1955 French film Rififi.' Rifampicin is a frontline tuberculosis drug."),
 ("Shakespeare in Love", "Shakespeare in Love", "1998-12-11", "film", "Earl of Wessex peerage created for Prince Edward", "peerage title (royal creation)", "1999", "Earl of Wessex, section 'Second creation (1999)'", "Earl of Wessex",
  "The Sunday Telegraph newspaper reported that Edward was drawn to the historic title of Earl of Wessex after watching the 1998 film Shakespeare in Love, in which a character with the title “Lord Wessex” is played by Colin Firth.", "Earl of Wessex", "Second creation (1999)",
  "Attributed to a newspaper report; the article states it as reported, not disputed."),
 ("The Taking of Pelham One Two Three", "The Taking of Pelham One Two Three (1974 film)", "1974-10-02", "film", "New York City Transit Authority stopped scheduling any train to leave Pelham Bay Park at 1:23", "rule (transit scheduling)", "after 1974 ('for several years after the film was released')", "sentence", "New York City Subway",
  "For several years after the film was released, the New York City Transit Authority would not schedule any train to leave Pelham Bay Park station at 1:23.", "The Taking of Pelham One Two Three (1974 film)", "(lead)",
  "Also in New York City Subway in popular culture: 'The time of the movie led to the MTA avoiding 1:23 as a departure time for Pelham trains.' Durable for several years, not permanent."),
 ("Weddad", "Weddad", "1936", "film", "Wydad AC (Casablanca football club) named after the film", "team (name)", "1937-05-08", "Wydad AC infobox founded", "Wydad AC",
  "The sports team Wydad AC in Casablanca, Morocco, is named after the film.", "Weddad", "(lead)",
  "Wydad AC history section tells the founding-meeting story: a founder arrived late from the latest Umm Kulthum film Weddad and the name was adopted."),
 ("Whacking Day", "Whacking Day", "1993-04-29", "TV episode (The Simpsons)", "Toad Day Out, annual cane toad cull in North Queensland", "durable civic event", "2009", "Toad Day Out lead: 'has been held since 2009'", "Toad Day Out",
  "The event was inspired by an episode of The Simpsons called \"Whacking Day\".", "Toad Day Out", "(lead)",
  "Whacking Day article, Reception, says the same of the annual 29 March event."),
 ("Different from the Others", "Different from the Others", "1919-06-30", "film", "Weimar Republic film censorship law reinstated (Reichslichtspielgesetz)", "law", "1920-05-12", "Different from the Others, Reception: 'reinstated on May 12, 1920'", "Different from the Others",
  "A new censorship program was created in response to the film in May 1920, and the film was banned except for private educational showings in August 1920.", "Different from the Others", "Background",
  "Reception section: 'In response to this controversy, censorship laws for cinema were re-launched in the Weimar Republic ... Reichslichtspielgesetz ... reinstated on May 12, 1920.' Film is one of the first pro-gay films."),
 ("Kantara", "Kantara (2022 film)", "2022-09-30", "film", "Government of Karnataka monthly allowance for Buta Kola performers over 60", "policy (state welfare allowance)", "undated in article", "sentence entails the allowance followed the film ('as a result of the movie')", "Buta Kola",
  "The Government of Karnataka, in response to the movie, has initiated a monthly allowance for Buta Kola performers who are above the age of 60.", "Kantara (2022 film)", "Legacy and impact",
  "Buta Kola article: 'As a result of the movie, the Government of Karnataka introduced a monthly allowance...'. No date given on Wikipedia."),
 ("Shores of Silence", "Shores of Silence", "2000", "documentary film", "India banned whale shark fishing (Schedule I, Wildlife Protection Act)", "law (species protection listing)", "2001-05", "Whale shark, Conservation status: 'followed by India in May 2001'", "Whale shark",
  "In response to the film, the Indian government introduced legislature to ban fishing of whale sharks, declaring them endangered species and protecting them under the Wildlife Protection Act of 1972.", "Shores of Silence", "(lead)",
  "Documentary by Mike Pandey."),
 ("Hibiscus Town", "Hibiscus Town", "1986", "film", "Town of Wangcun renamed Furong", "place name (official renaming)", "undated in article", "sentence entails rename followed the film ('renamed following the success of the eponymous film')", "Furong, Yongshun County",
  "Furong was originally known as Wangcun, but was renamed following the success of the eponymous film, Hibiscus Town.", "Furong, Yongshun County", "(lead)", "No rename year on Wikipedia."),
 ("It Is Not the Homosexual Who Is Perverse, But the Society in Which He Lives", "It Is Not the Homosexual Who Is Perverse, But the Society in Which He Lives", "1971", "film", "HIB, the East Berlin gay group that became the Sonntags-Club (first secular LGBT group in East Germany)", "organization", "1970s (HIB); Sonntags-Club 1986", "Sonntags-Club article sentence; infobox formation 1986", "Sonntags-Club",
  "HIB, the group from which the Sonntags-Club emerged, was founded in the 1970s after the premiere of an underground LGBT film titled \"Nicht der Homosexuelle ist pervers, sondern die Situation, in der er lebt\" (It Is Not the Homosexual Who Is Perverse, But the Society in Which He Lives).", "Sonntags-Club", "1970s",
  "Same article, Notable people: 'He founded the group after seeing the film ... with Michael Eggert.' A West German film seeding an East German organization."),
 ("Crude", "Crude (2009 film)", "2009-01-18", "documentary film", "Judge Lewis Kaplan's ruling that the $19 billion Ecuadorian judgment against Chevron was obtained by fraud", "court ruling", "2014", "sentence", "Crude (2009 film)",
  "The judge Lewis Kaplan ruled in 2014 that the American lawyers for the plaintiffs had used fraud in obtaining the $19 billion Ecuadorian court judgment against Chevron and cited the film outtakes as a reason for his decision.", "Crude (2009 film)", "Subpoena of footage",
  "Affirmed by the Second Circuit. A film made in support of the plaintiffs became evidence against them."),
 ("Shiri", "Shiri (film)", "1999-02-13", "film", "Revision of South Korea's Motion Picture Promotion Law allowing individuals to finance films", "law (amendment)", "1999", "sentence", "Korean Wave",
  "Shiri had been funded partly through venture capital, and the success of the film led to a 1999 revision of the Motion Picture Promotion Law to allow individuals to finance film productions.", "Korean Wave", "Film in the first generation",
  "Same calendar year as the stone; the sentence asserts the sequence (success, then revision)."),
 ("This Was the XFL", "XFL (2001)", "2016-11-11 (Doc NYC); ESPN 2017-02-02", "TV documentary (30 for 30)", "Revived XFL football league", "league", "2018-01-25", "XFL (2020) infobox founded", "XFL (2020)",
  "Interest in the league was revived when ESPN Films released a 30 for 30 documentary surrounding the league, and shortly after the film debuted, McMahon began preparing for a new iteration of the league", "XFL (2001)", "(lead)",
  "Stone date from XFL (2001), Legacy. XFL (2020-2023) article adds that McMahon mused about a revival in the documentary itself."),
 ("Varsity Blues", "Varsity Blues (film)", "1999-01-15", "film", "Operation Varsity Blues, the federal investigation into the college admissions bribery scheme", "named program (federal investigation)", "2019", "2019 college admissions bribery scandal lead", "2019 college admissions bribery scandal",
  "The investigation's name, Operation Varsity Blues, comes from a 1999 film of the same name.", "2019 college admissions bribery scandal", "(lead)", ""),
 ("\"Oh My Darling, Clementine\"", "Oh My Darling, Clementine", "1884", "song", "Clementine, the Los Alamos fast-neutron reactor", "facility name (government reactor)", "1946", "sentence: 'first achieved criticality in 1946'", "Clementine (nuclear reactor)",
  "The reactor was named after the song \"Oh My Darling, Clementine.\"", "Clementine (nuclear reactor)", "(lead)",
  "Reason given: deep canyon and operators were '49ers' (plutonium-239 code name 49)."),
 ("Pedigree Dogs Exposed", "Pedigree Dogs Exposed", "2008-08-19", "TV documentary", "Kennel Club reviewed and revised the breed standard for every breed", "standard", "2008-10-07 (plans); revised standards released 12 January", "article, Revised breed standards section", "Pedigree Dogs Exposed",
  "Due to strong public reaction, it later rolled out new health plans and reviewed breed standards for every breed, an action which some breeders condemned as an overreaction.", "Pedigree Dogs Exposed", "(lead)",
  "Standalone BBC One documentary, not a news strand."),
 ("Rasputin and the Empress", "Rasputin and the Empress", "1932-12-23", "film", "Youssoupoff v MGM: English Court of Appeal held Princess Irina was defamed", "court ruling", "1934", "sentence", "Unintentional defamation",
  "After seeing the film twice and hearing testimony, the English Court of Appeal agreed that the princess had been defamed.", "Unintentional defamation", "History",
  "Commonly linked to the 'all persons fictitious' disclaimer, but that link is not in the sentence used here."),
 ("Ben-Hur (1907 film)", "Ben-Hur (1907 film)", "1907-12-07", "film", "Kalem Co. v. Harper Bros., the U.S. Supreme Court case over the unlicensed film adaptation", "court ruling", "1911", "Kalem Co. v. Harper Bros. infobox DecideYear", "Kalem Co. v. Harper Bros.",
  "The case involved a 1907 film adaptation of the 1880 novel Ben-Hur: A Tale of the Christ by Lew Wallace.", "Kalem Co. v. Harper Bros.", "(lead)",
  "The film is the subject of the suit rather than a cited motive; a ruling that films can infringe copyright."),
 ("Hidden Figures", "Hidden Figures", "2016-12-10", "film", "U.S. State Department 'Hidden No More' IVLP exchange program for women in STEM", "named program (government)", "2017", "sentence: 'The exchange program began in 2017'", "Hidden Figures",
  "Department of State on the third annual \"Hidden No More\" exchange program, which was inspired by the film and brings to the United States 50 women from around the world who have excelled in STEM careers", "Hidden Figures", "Charity screenings",
  "Next sentence: 'The exchange program began in 2017 after local US embassies screened the film to their local communities.'"),
 ("Chal Parha (episode on corporal punishment)", "Shehzad Roy", "2013-02-15", "TV episode", "Pakistan National Assembly unanimously passed a bill making corporal punishment an offence", "law (bill passed by National Assembly)", "2013-03-12", "sentence", "Shehzad Roy",
  "Soon after the episode aired, Pakistan's provincial assemblies passed a resolution against corporal punishment and on 12 March 2013, the National Assembly unanimously passed a Bill making corporal punishment an offence.", "Shehzad Roy", "Chal Parha",
  "Preceding sentence: the episode 'resulted in catalysing a decision by the government to finally ban corporal punishment.' Article does not state final enactment of the 2013 bill."),
 ("Dear Zachary: A Letter to a Son About His Father", "Dear Zachary: A Letter to a Son About His Father", "2008-01", "documentary film", "Bill C-464 ('Zachary's Bill'), Canadian bail law", "law", "2010", "sentence: 'signed into law the following year' (after 2009)", "Dear Zachary: A Letter to a Son About His Father",
  "In 2009, after watching the film, Canadian MP Scott Andrews introduced Bill C-464 (also known as \"Zachary's Bill\") to the Parliament of Canada.", "Dear Zachary: A Letter to a Son About His Father", "(lead)", ""),
 ("Sin by Silence", "Sin by Silence", "2009", "documentary film", "California AB 593 and AB 1593 (Sin by Silence Bills)", "law", "2012-09-30", "sentence: 'signed into law by Governor Brown on September 30, 2012'", "Sin by Silence",
  "In 2012, Assemblywoman Fiona Ma introduced AB 1593 and AB 593, The Sin by Silence Bills, inspired by the documentary.", "Sin by Silence", "(lead)", ""),
 ("Animal Machines", "Ruth Harrison", "1964", "book", "Brambell Report and its Five Freedoms for farm animals", "standard (animal welfare)", "1965", "Five Freedoms, History", "Five Freedoms",
  "In 1965, the UK government commissioned an investigation, led by Professor Roger Brambell, into the welfare of intensively farmed animals, partly in response to concerns raised in Ruth Harrison's 1964 book, Animal Machines.", "Five Freedoms", "History",
  "Ruth Harrison article: 'The book prompted the British government to appoint a committee chaired by Francis Brambell.'"),
 ("JFK", "JFK (film)", "1991-12-20", "film", "President John F. Kennedy Assassination Records Collection Act and its Assassination Records Review Board", "law and agency", "1992-10-26", "JFK Records Act lead: 'effective October 26, 1992'", "President John F. Kennedy Assassination Records Collection Act of 1992",
  "The final report of the act's Assassination Records Review Board (ARRB) partially credited the conclusions in Oliver Stone's 1991 film JFK with the passage of the act.", "President John F. Kennedy Assassination Records Collection Act of 1992", "Background", "Well known."),
 ("Unsafe at Any Speed", "Unsafe at Any Speed", "1965-11-30", "book", "United States Department of Transportation", "agency", "1966 (act); formed 1967-04-01", "sentence; DOT infobox formed", "United States Department of Transportation",
  "U.S Senate hearings prompted by the book led to the creation of the United States Department of Transportation in 1966 and the predecessor agencies of the National Highway Traffic Safety Administration in 1970.", "Unsafe at Any Speed", "Government response", "Well known."),
 ("On American Soil", "Jack Hamann", "2005", "book", "Army board overturned the 1944 Fort Lawton court-martial convictions", "court ruling (military records board)", "2007-10-26", "Fort Lawton riot, U.S. Army Board for Correction of Military Records section", "Fort Lawton riot",
  "The book led to a congressional review and ultimately the voiding of the court-martial of those soldiers.", "Jack Hamann", "Work", ""),
 ("Monty Python's Flying Circus", "Monty Python's Flying Circus", "1969-10-05", "TV series", "Python programming language named after the show", "name (programming language)", "1991-02-20", "Python infobox released", "Python (programming language)",
  "The name Python derives from the British comedy series Monty Python's Flying Circus.", "Python (programming language)", "History", "Well known."),
 ("The Onedin Line", "The Onedin Line", "1971-10-15", "TV series", "Ånedin-Linjen, Stockholm ferry company named after the series", "company (name)", "1973", "sentence", "Baltic Sea cruiseferries",
  "After ten years, traffic between Sweden and Åland was joined by the Ålandian company Birka Line in 1971 and the Stockholmian company Ånedin-Linjen, named after the TV series The Onedin Line, in 1973.", "Baltic Sea cruiseferries", "Price contests and fun cruises", ""),
 ("Funeral Parade of Roses", "Funeral Parade of Roses", "1969-09-13", "film", "Barazoku, Japan's first commercial gay magazine, named after the film", "publication (name)", "1971-07-30", "Barazoku, Origins: 'The first issue was published on 30 July 1971'", "Barazoku",
  "The Japanese queer magazine Barazoku was named after the film.", "Funeral Parade of Roses", "Legacy", ""),
 ("\"Makin' Whoopee\"", "Makin' Whoopee", "1928", "song", "Macon Whoopees hockey team", "team (name)", "1973-07-04", "Macon Whoopees (SHL), History: announced July 4, 1973", "Macon Whoopees (SHL)",
  "The original Whoopees team was named after the song \"Makin' Whoopee\" by Gus Kahn, and is the subject of the book Once Upon A Whoopee: A Town, A Team, A Song, A Dream, by Ed Grisamore and Bill Buckley.", "Macon Whoopees (SHL)", "(lead)",
  "Team folded in February 1974; name revived 1996."),
 ("\"Strawberry Fields Forever\"", "Strawberry Fields Forever", "1967-02-13", "song", "Strawberry Fields memorial in Central Park", "place name (municipal memorial)", "1985-10-09", "Strawberry Fields (memorial), Creation", "Strawberry Fields (memorial)",
  "It is named after the Beatles' song \"Strawberry Fields Forever\", written by Lennon.", "Strawberry Fields (memorial)", "(lead)", "Well known."),
 ("Remember the Titans", "Remember the Titans", "2000-09-29", "film", "Hidden Valley High School (Roanoke County) nickname 'Titans'", "team (school nickname)", "2002-08", "Hidden Valley High School infobox established", "Hidden Valley High School (Virginia)",
  "The incoming student population selected the nickname \"Titans\" in response to the film Remember the Titans which dramatized the 1971 state-championship football team from T. C. Williams High School.", "Hidden Valley High School (Virginia)", "History", ""),
 ("Remember the Titans", "Remember the Titans", "2000-09-29", "film", "Manchester Titans American football club name", "team (name)", "2003", "Manchester Titans infobox founded", "Manchester Titans",
  "The team name was inspired by the film Remember the Titans.", "Manchester Titans", "History", "Second team named after the same film."),
 ("Steel Magnolias", "Steel Magnolias", "1989-11-15", "film", "Magnolia Basket Campobasso, Italian women's basketball club", "team (name)", "2017 (history) / 2018 (lead and infobox)", "article, conflicting years", "Magnolia Basket Campobasso",
  "The team's name is inspired by the film Steel Magnolias.", "Magnolia Basket Campobasso", "Team history", ""),
 ("Trevor", "Trevor (film)", "1994", "short film", "The Trevor Project", "organization", "1998-03-25", "The Trevor Project infobox founded", "The Trevor Project",
  "In 1998, Stone co-founded a nonprofit organization inspired by the film Trevor, called The Trevor Project.", "Randy Stone", "The Trevor Project", "Founded by the film's creators."),
 ("Mr. Holland's Opus", "Mr. Holland's Opus", "1995-12-29", "film", "The Mr. Holland's Opus Foundation", "organization", "1996", "sentence", "The Mr. Holland's Opus Foundation",
  "Inspired by the film Mr. Holland's Opus, the foundation provides musical instruments and vital support services to under-funded school music programs across the United States.", "The Mr. Holland's Opus Foundation", "(lead)", "Founded by the film's composer, Michael Kamen."),
 ("The National Parks: America's Best Idea", "The National Parks: America's Best Idea", "2009-09-27", "TV documentary series", "National Park Foundation's America's Best Ideas Program", "named program", "2009 or later", "sentence", "National Park Foundation",
  "The America's Best Ideas Program was launched by the National Park Foundation following the airing of  the documentary by Ken Burns, The National Parks: America’s Best Idea in 2009.", "National Park Foundation", "Best Idea Program", "Program name echoes the series title."),
 ("Women Veterans: America's Forgotten Heroines", "June A. Willenz", "1983", "book", "Veterans Administration Women Veterans Advisory Committee (and first congressional hearings on women veterans)", "agency body (advisory committee)", "undated in article", "sentence entails the committee followed the book ('largely in response to the book')", "June A. Willenz",
  "Largely in response to the book, Congress held its first hearings on women veterans and the Veterans Administration established a Women Veterans Advisory Committee.", "June A. Willenz", "Career", ""),
 ("Animals in War", "Jilly Cooper", "1983", "book", "Animals in War Memorial, Hyde Park", "memorial", "2004", "Animals in War Memorial lead", "Animals in War Memorial",
  "The memorial was inspired by Jilly Cooper's 1983 book Animals in War, and was made possible by a specially created fund of £1.4 million from public donations of which Cooper was a co-trustee.", "Animals in War Memorial", "History", ""),
 ("The Conservation Game", "The Conservation Game", "2021-04", "documentary film", "Big Cat Public Safety Act", "law", "2022-12", "sentence", "Michael Webber (filmmaker)",
  "The film also contributed to the passage of the Big Cat Public Safety Act, with Congressman Mike Quigley stating that \"'The Conservation Game' shines a light on an important issue that my colleagues and I in Congress have been working diligently to address for years.\"", "Michael Webber (filmmaker)", "The Conservation Game (2021)",
  "Contributory cause; next sentence: 'One year following the release of the film, the act was signed into law in December 2022.'"),
 ("Now the Chips Are Down", "Now the Chips Are Down", "1978-03-31", "TV documentary (Horizon)", "UK Microelectronics Education Programme", "named program (government)", "1981", "sentence", "Now the Chips Are Down",
  "The UK government launched the Microelectronics Education Programme in 1981, with a budget of more than £10 million.", "Now the Chips Are Down", "Consequences",
  "Causal link is carried by the section heading 'Consequences' and the lead ('played an important part in raising awareness ... within government'); weaker than the others."),
 ("Untitled 1975 television documentary on violence against women", "Sarah Haffner", "1975", "TV documentary", "First women's shelter in West Berlin and West Germany", "institution (shelter)", "late 1970s", "Sarah Haffner lead", "Sarah Haffner",
  "The documentary led to the funding of a shelter for women in Berlin.", "Sarah Haffner", "Advocacy for women's shelters", "Next sentence: 'It was the first shelter of its kind anywhere in West Berlin or West Germany.' The documentary has no article of its own."),
 ("Red Under the Bed", "Ricky Tomlinson", "1973", "TV documentary", "CCRC referral of the Shrewsbury 24 convictions; Court of Appeal quashed them", "court ruling (referral and quashing)", "2020-05 (referral); 2021-03 (quashed)", "Ricky Tomlinson, Politics section", "Ricky Tomlinson",
  "The CCRC cited the documentary and its possible influence on the jury when announcing its decision to refer the cases of Tomlinson and others to the Court of Appeal.", "Ricky Tomlinson", "Richard Whiteley claims", "The documentary is one cited ground among others."),
 ("The Dying Rooms", "The Dying Rooms", "1995", "TV documentary", "Care of China's Orphaned and Abandoned (charity)", "organization", "undated in article", "sentence entails it followed ('established after the documentary was screened')", "Kate Blewett",
  "She is trustee of Care of China's Orphaned and Abandoned, a charitable organization which was established after the documentary was screened.", "Kate Blewett", "Work", "'After' is temporal; preceding sentence says the film prompted an enormous outcry."),
 ("The Italian Job", "The Italian Job", "1969-06-05", "film", "The Italian Job charity event, held annually", "durable charity event", "1990", "sentence", "The Italian Job",
  "A charity event titled The Italian Job, founded in 1990 and held annually, was inspired by the film; as of 2020, it had raised nearly £3,000,000.", "The Italian Job", "(lead)", ""),
 ("The Katzenjammer Kids", "The Katzenjammer Kids", "1897", "comic strip", "Knoll and Tott, the two highest peaks of Chermsideøya, Svalbard", "place name (official)", "undated in article", "sentence entails naming followed the characters", "Chermsideøya",
  "The island's two highest peaks are Knoll (280 m) on the southwestern half and Tott (230 m) on the northeastern half, named after the cartoon characters The Katzenjammer Kids, which in Norwegian is named Knoll and Tott.", "Chermsideøya", "(lead)", "Comic strip is outside the listed work types but is a mass cultural work."),
 ("Betaab", "Betaab", "1983-08-05", "film", "Betaab Valley, Kashmir", "place name", "undated in article", "sentence entails naming followed the film", "Betaab",
  "The famous tourist destination Betaab Valley in the Kashmir was named after the film Betaab.", "Betaab", "Betaab Valley", "Tourism followed too; the kept mark is the name only."),
 ("Gunaa", "Gunaa", "1991-11-05", "film", "Guna Caves (Devil's Kitchen, Kodaikanal) renamed for the film", "place name", "undated in article", "sentence entails naming followed the film", "Guna Caves",
  "Hence, the area was subsequently named after the film.", "Guna Caves", "(lead)", "Tourism followed too; the kept mark is the name only."),
 ("Ishtar", "Ishtar (film)", "1987-05-15", "film", "Tri-Star renamed Columbia Pictures Entertainment", "company restructuring", "1987-12-18", "Columbia Pictures Entertainment infobox founded", "Columbia Pictures Television",
  "Subsequently, Tri-Star was renamed as Columbia Pictures Entertainment after the film Ishtar turned out to be a notorious failure both critically and financially.", "Columbia Pictures Television", "Columbia Pictures Entertainment (1987–1989)", "Causal phrasing is 'after'; corporate history has other drivers. Low confidence."),
 ("Oopiri", "Oopiri", "2016-03-25", "film", "Challengers on Wheels-Celebrating Life community for physically disabled people", "organization", "2016-04", "sentence", "Oopiri",
  "Inspired by the film, paraplegic television personality Sujatha Barla established the Challengers on Wheels-Celebrating Life community for physically disabled people in April 2016.", "Oopiri", "Legacy", ""),
 ("\"White Tee\"", "White Tee", "2004", "song", "Clubs and schools banned white T-shirts", "rule (dress codes)", "undated in article", "sentence: 'after the release of the song'", "White Tee",
  "An article in the Pittsburgh Post-Gazette, which mentions the song, and the fashion statement, stated that after the release of the song, many clubs and schools began to ban the use of white T-shirts on the basis that the shirts were associated with gangs.", "White Tee", "Controversy", "Single newspaper source; 'many clubs and schools' is vague; the gang association, not the song, is the stated basis. Low confidence."),
 ("No More Bets", "No More Bets", "2023-08-08", "film", "Cambodia banned screenings of the film", "policy (state ban of the work)", "2023", "sentence (no exact date)", "No More Bets",
  "In response to the film, Cambodia banned showings of No More Bets due to its potential allusion to the country and the negative image it portrays, while the film was criticised by the governments of Myanmar.", "No More Bets", "(lead)", "A ban of the work itself; lower surprise."),
 ("Alibi", "Alibi (1929 film)", "1929-04-20", "film", "Circuit court injunction overturning the Chicago Board of Censors ban", "court ruling", "1929", "article context (no exact date)", "Alibi (1929 film)",
  "After watching the film, Judge Harry Fisher, stating that \"censorship is a form of tyranny at best, and abhorrent to ideals of the American people,\" issued an injunction allowing the film to be shown in an U.A. theater.", "Alibi (1929 film)", "Censorship", "Ruling about the work itself; lower surprise."),
]

REJECTED_DETAILED = {
 "order fails (mark precedes stone)": ["Council on American-Islamic Relations / True Lies (offices opened a month before release)"],
 "order unverifiable (no mark date on Wikipedia)": ["Best Defense / Pennsylvania blind-bidding ban"],
 "no lasting mark attributed to the work (proposal, letter, statement, apology, call)": ["Blackfish (only proposed bills attributed)", "Zen at War / sect apologies", "Fuck tha Police / FBI letter", "Expelled / bill proposal", "Dying to Survive / premier's appeal", "Joseph Massad / Weiner call", "Lives of a Bengal Lancer / MPAA remark", "Amatz / PDEA proposal", "Tongues Untied / attacks on PBS", "Hokuriku Proxy War / blame", "Call of the Wildman / warning letter"],
 "inquiry, hearing or investigation only": ["The Kid Who Couldn't Miss / Senate inquiry", "J'accuse les assassins de Coffin / royal commission", "Surviving R. Kelly / investigation"],
 "vague mark or vague causal claim": ["Victory Through Air Power", "Diary of a Camper", "Injustice (Ken Fero)", "Human Guinea Pigs", "Hospitals Don't Burn Down!", "Second Effort"],
 "temporal only, no stated reason": ["An Inconvenient Truth / Climate Reality Project", "Hum Log Tamil dub / Doordarshan rules", "Joshua Dugdale film / LAPD chief not reappointed"],
 "news or current-affairs journalism, not a cultural work": ["Exposure (Savile) / Operation Yewtree", "Rwanda's Untold Story / BBC ban", "Four Corners / greyhound racing", "Nightline / Al Campanis", "This American Life / judge charges", "Sweet Sweet Codeine / Nigeria codeine ban", "The Secret Hospital / Rampton inquiry", "Latvian broadcast / Saeima commission", "Australia's Shame / royal commission", "CBS Reports / Boston commissioner", "ARD doping documentary / WADA", "Godhavn documentary", "The Secret Agent / Barclays", "The Lobby / Track AIPAC", "Marketplace / Health Canada"],
 "not a lasting mark (incident, attack, protest, sales, tourism, behavior spike)": ["Camp Bastion raid", "Valter protest movement", "Goodbye Pork Pie subway incident", "867-5309 calls", "Kick a Ginger Day", "Guitar Hero bar nights", "Harvest (Numbers) organ donation intent", "Withnail and I pub rename", "Isolation tank market", "Psycho late-admission policy (part of the release itself)"],
 "informal nickname or term coinage, no institution": ["Katyusha rocket launcher nickname", "jump the shark", "Truman Show delusion", "Dark Forest hypothesis", "Mbube genre"],
 "stone not a notable cultural work": ["Farmers Fight / Texas Fight"],
 "weak source (disambiguation line only)": ["Born Free / Born Free Foundation"],
 "platform or broadcaster action against a person or one airing": ["Tinder Swindler / Tinder ban", "Izhar Ashdot song / IDF Radio ban"],
}

def cmd_build():
    hits = json.load(open(os.path.join(HERE, "g1_hits.json")))
    n_hits = sum(len(v["hits"]) for v in hits["phrases"].values())
    naming = [p for p in PHRASES if p.startswith("named ")]
    n_naming = sum(len(hits["phrases"][p]["hits"]) for p in naming)
    kept = []
    for (stone, sa, sd, sk, mark, mk, md, mds, ma, sent, src, sec, notes) in KEPT:
        anchor = "" if sec in ("(lead)", "") else "#" + sec.replace(" ", "_")
        kept.append({"gen": "G1", "stone": stone, "stone_article": sa, "stone_date": sd, "stone_kind": sk, "mark": mark,
                     "mark_kind": mk, "mark_date": md, "mark_date_source": mds, "mark_article": ma, "sentence": sent,
                     "source_article": src, "source_section": sec,
                     "source_url": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(src.replace(" ", "_")) + anchor,
                     "cause_label": "reason", "order_ok": True, "disputed": False, "notes": notes})
    detailed = {k: len(v) for k, v in REJECTED_DETAILED.items()}
    n_detail = sum(detailed.values())
    KEPT_VIA_NAMING = 12  # kept pairs first surfaced by a "named after/for" phrase (counted by hand)
    rc = {"naming-phrase hits that name a band, business, product, person, settlement, species, episode, award or other work": n_naming - KEPT_VIA_NAMING}
    rc.update(detailed)
    rc["read in snippet, no institution or the work is not the reason (adaptations, sequels, careers, reviews, personal inspiration, art)"] = n_hits - n_naming - (len(KEPT) - KEPT_VIA_NAMING) - n_detail
    out = {"generator": "G1", "queries": hits["queries"], "hits": n_hits, "kept": kept, "rejected_counts": rc,
           "rejected_examples": REJECTED_DETAILED,
           "method_notes": "Fixed phrase list of 108 quoted phrases (pass one, 200 results per phrase); a second pass paged deeper into the same phrases only (up to 1000 results), no phrases added. Duplicates of kept pairs across phrases count in the snippet bucket."}
    json.dump(out, open(os.path.join(HERE, "g1.json"), "w"), indent=1, ensure_ascii=False)
    print("queries", out["queries"], "hits", n_hits, "kept", len(kept), "rejected", sum(rc.values()))

if __name__ == "__main__":
    c = sys.argv[1]
    if c == "search": cmd_search()
    elif c == "triage": cmd_triage(int(sys.argv[2]) if len(sys.argv) > 2 else 2)
    elif c == "context": cmd_context(sys.argv[2])
    elif c == "date": cmd_date(sys.argv[2:])
    elif c == "deepen": cmd_deepen()
    elif c == "build": cmd_build()

