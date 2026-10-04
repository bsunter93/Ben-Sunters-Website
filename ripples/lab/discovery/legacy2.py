"""Corpus 1, second reading: the whole article in one request, split by heading; skip plot/cast/production-type
sections; every sentence that is mark-shaped (law, act, agency, founded, banned, regulation ...) is a candidate, and a
causal connective raises its score. One request a second, honest UA, stop on 4xx/5xx."""
import json, re, sys
from legacy import get, clean, sentences, links, plain, CONN, MARKISH
SKIP = re.compile(r"plot|cast|episode|character|production|filming|music|soundtrack|release|marketing|ratings|awards|references|see also|external|notes|bibliography|further reading|synopsis|premise|development|casting|design|gameplay|track|personnel|chart|certif|home media|crew|setting|style|themes|box office|distribution|broadcast|sources|footnotes|citations", re.I)
def mine(title, keep=None):
    d = get({"action": "parse", "page": title, "prop": "wikitext|sections", "redirects": 1})
    if "error" in d: return None, []
    wt = d["parse"]["wikitext"]["*"]; real = d["parse"]["title"]
    parts = re.split(r"^(=+)\s*(.*?)\s*\1\s*$", wt, flags=re.M)  # [lead, lvl, head, body, lvl, head, body ...]
    secs = [("Lead", parts[0])] + [(parts[i + 1], parts[i + 2]) for i in range(1, len(parts) - 2, 3)]
    cands = []
    for head, body in secs:
        if head != "Lead" and SKIP.search(head): continue
        txt, refs = clean(body)
        for sent in sentences(txt):
            mk = bool(MARKISH.search(sent)) or bool(keep and keep.search(sent)); cn = bool(CONN.search(sent))
            if not mk: continue
            cands.append({"section": head, "text": plain(sent)[:400], "links": links(sent), "years": sorted(set(re.findall(r"\b(1[6-9]\d\d|20\d\d)\b", sent))), "causal": cn, "has_ref": "[ref]" in sent})
    return real, cands
if __name__ == "__main__":
    stones = json.load(open(sys.argv[1])); res = {}
    for slug, st in stones.items():
        real, cands = mine(st["article"])
        res[slug] = {"article": real, "candidates": cands}
        print(f"{slug:26s} | {str(real)[:30]:30s} | mark-shaped {len(cands):3d} | with a connective {sum(c['causal'] for c in cands):3d}")
    json.dump(res, open(sys.argv[2], "w"), indent=1)
    # corpus 2 seed: legislation named after people
    d = get({"action": "parse", "page": "List of legislation named after people", "prop": "wikitext", "redirects": 1})
    open("namesake_seed.wikitext", "w").write(d.get("parse", {}).get("wikitext", {}).get("*", ""))
    print("namesake seed bytes:", len(open("namesake_seed.wikitext").read()))
