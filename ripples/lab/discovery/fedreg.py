"""Corpus 4 probe: Federal Register documents whose text names the stone (documented public API, no key). One request a
second, honest UA, stop on any 4xx/5xx. Counts and the first titles with dates; the connective check needs full text later."""
import json, re, sys, time, urllib.parse, urllib.request
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
stones = json.load(open("stones_all.json")); out = {}; last = 0
for slug, st in stones.items():
    if not st["in_class"]: continue
    q = st["stone"] if len(st["stone"]) > 4 else st["article"]
    url = "https://www.federalregister.gov/api/v1/documents.json?" + urllib.parse.urlencode({"conditions[term]": f'"{q}"', "per_page": 5, "order": "oldest", "fields[]": ["title", "publication_date", "type", "agencies"]}, doseq=True)
    w = 1.0 - (time.time() - last); 
    if w > 0: time.sleep(w)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=30) as r: d = json.load(r); last = time.time()
    except urllib.error.HTTPError as e: print("STOP: HTTP", e.code, "on", q); break
    n = d.get("count", 0); docs = d.get("results", [])
    out[slug] = {"query": q, "count": n, "first": [(x["publication_date"], x["type"], x["title"][:90]) for x in docs]}
    print(f"{slug:26s} | {q[:28]:28s} | {n:5d} docs | " + (f"first {docs[0]['publication_date']} {docs[0]['type']}: {docs[0]['title'][:70]}" if docs else ""))
json.dump(out, open("fedreg_probe.json", "w"), indent=1)
