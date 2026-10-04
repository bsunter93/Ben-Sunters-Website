import json, re
from legacy import get, clean, CONN
rows = [r for r in json.load(open("namesake_statutes.json")) if r["section"] not in ("Roman law", "See also")]
NAMED = re.compile(r"\b(named after|named for|in memory of|in honou?r of|after the (death|murder|killing|disappearance|case) of|following the (death|murder|killing|disappearance|case) of|prompted by|in response to|after (\w+ ){0,4}(was|were) (killed|murdered|abducted|died))\b", re.I)
out = []
for r in rows:
    d = get({"action": "parse", "page": r["law"], "prop": "wikitext", "section": 0, "redirects": 1})
    if "error" in d: out.append({**r, "status": "no article"}); continue
    wt = d["parse"]["wikitext"]["*"]; txt, _ = clean(wt)
    m = NAMED.search(txt); years = re.findall(r"\b(1[7-9]\d\d|20\d\d)\b", txt)
    enact = re.search(r"\|\s*(enacted|date_enacted|date_signed|signed|effective|royal_assent|date_of_royal_assent|passed)\s*=\s*[^\n]*?(1[7-9]\d\d|20\d\d)", wt, re.I)
    sent = ""
    if m:
        i = m.start(); a = txt.rfind(".", 0, i) + 1; b = txt.find(".", i); sent = txt[a:b + 1].strip()[:240]
    out.append({**r, "status": "ok", "names_cause": bool(m), "cause_sentence": sent, "enacted": enact.group(2) if enact else (years[0] if years else None), "n_years": len(set(years))})
ok = [o for o in out if o["status"] == "ok"]; nc = [o for o in ok if o["names_cause"]]
print(f"statutes {len(rows)}: articles {len(ok)}, lead names its cause with a connective {len(nc)} ({len(nc)/max(1,len(ok)):.0%}), with an enactment year {sum(1 for o in ok if o['enacted'])}")
for o in nc[:18]: print(f"  {o['law'][:36]:36s} ({o['enacted']}) | {o['cause_sentence'][:150]}")
json.dump(out, open("namesake_results.json", "w"), indent=1)
