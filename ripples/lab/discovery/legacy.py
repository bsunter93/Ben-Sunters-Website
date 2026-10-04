"""Corpus 1: the Legacy / Impact / Aftermath sections of a stone's Wikipedia article, read as text.
For each stone: fetch the article's section list, pull the sections whose heading says legacy/impact/aftermath/influence/
response/consequences/effects/legislation/political, split into sentences, keep the ones with a causal connective,
record the linked articles, the years and the references in each. Honest UA, one request a second, stop on any 4xx/5xx."""
import json, re, sys, time, urllib.parse, urllib.request, html
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
API = "https://en.wikipedia.org/w/api.php"
HEAD = re.compile(r"legacy|impact|aftermath|influence|response|reaction|consequence|effect|legislation|political|law|regulat|reform|policy|controvers", re.I)
CONN = re.compile(r"\b(led to|prompted|in response to|in the wake of|following|after the|because of|spurred|triggered|inspired|named after|in memory of|as a result|resulted in|gave rise|contributed to|credited with|cited|influenced|passed|enacted|signed into law|introduced|established|founded|created|banned|launched|changed|reformed)\b", re.I)
MARKISH = re.compile(r"\b(act|law|bill|statute|legislation|regulation|ban|banned|agency|commission|department|founded|established|institute|foundation|fund|charity|program|policy|reform|ordinance|treaty|convention|standard|recall|rule)\b", re.I)
_last = [0.0]
def get(params):
    wait = 1.0 - (time.time() - _last[0])
    if wait > 0: time.sleep(wait)
    url = API + "?" + urllib.parse.urlencode({**params, "format": "json"})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            _last[0] = time.time(); return json.load(r)
    except urllib.error.HTTPError as e:
        print("STOP: HTTP", e.code, "on", params.get("page"), file=sys.stderr); sys.exit(2)
def sections(title):
    d = get({"action": "parse", "page": title, "prop": "sections", "redirects": 1})
    if "error" in d: return None, []
    return d["parse"]["title"], [s for s in d["parse"]["sections"] if HEAD.search(s["line"])]
def wikitext(title, idx):
    d = get({"action": "parse", "page": title, "prop": "wikitext", "section": idx, "redirects": 1})
    return d.get("parse", {}).get("wikitext", {}).get("*", "")
def clean(wt):
    wt = re.sub(r"<ref[^>]*/>", "", wt); refs = re.findall(r"<ref[^>]*>(.*?)</ref>", wt, re.S)
    wt = re.sub(r"<ref[^>]*>.*?</ref>", " [ref] ", wt, flags=re.S)
    wt = re.sub(r"\{\{[^{}]*\}\}", "", wt); wt = re.sub(r"\{\{[^{}]*\}\}", "", wt)
    wt = re.sub(r"<[^>]+>", "", wt); wt = re.sub(r"'{2,}", "", wt); wt = re.sub(r"^=+.*=+$", "", wt, flags=re.M)
    return wt, refs
def sentences(text):
    text = re.sub(r"\s+", " ", text)
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+(?=[A-Z\[])", text) if len(s.strip()) > 40]
def links(s): return [l.split("|")[0].strip() for l in re.findall(r"\[\[([^\]]+)\]\]", s) if not l.lower().startswith(("file:", "image:", "category:"))]
def plain(s): return re.sub(r"\[\[([^\]|]+\|)?([^\]]+)\]\]", r"\2", s).replace(" [ref] ", " ")
def run(stones, out):
    res = {}
    for slug, st in stones.items():
        title = st["article"]
        real, secs = sections(title)
        if real is None: res[slug] = {"article": title, "error": "no article"}; print(slug, "| no article:", title); continue
        cands = []
        for s in secs:
            wt = wikitext(real, s["index"]); txt, refs = clean(wt)
            for sent in sentences(txt):
                if not CONN.search(sent): continue
                cands.append({"section": s["line"], "text": plain(sent)[:400], "links": links(sent), "years": sorted(set(re.findall(r"\b(1[6-9]\d\d|20\d\d)\b", sent))), "markish": bool(MARKISH.search(sent)), "has_ref": "[ref]" in sent})
        res[slug] = {"article": real, "sections": [s["line"] for s in secs], "candidates": cands}
        print(f"{slug:28s} | {real[:34]:34s} | sections {len(secs):2d} | causal sentences {len(cands):3d} | markish {sum(c['markish'] for c in cands):3d}")
    json.dump(res, open(out, "w"), indent=1)
if __name__ == "__main__":
    stones = json.load(open(sys.argv[1])); run(stones, sys.argv[2])
