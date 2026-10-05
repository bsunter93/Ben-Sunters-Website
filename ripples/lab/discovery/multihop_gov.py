"""Multi-hop ripples v1, H4: the Congressional Record (ripples/docs/multihop_plan_v1.md, section 4).

Runs in a GitHub workflow (.github/workflows/ripples-multihop-gov.yml) because the GovInfo key lives in Actions secrets.
Reads docs/results/multihop_stage1_v1.json. For every hop-1 survivor whose intermediate or stone is tied to the United
States in Wikidata: its first guarded name as an exact phrase in the CREC collection, newest first, 50 results; items
dated on or after the hop-1 step (and after Jan 1, 1995) whose title is bill-shaped; at most five text fetches per name;
the window around the name scored by cite_score; a "reason" window's title resolved by bill_act.us_resolve to a public
law enacted on or after the item. Four seconds between requests (the key's hourly cap); a 403, 429 or any 5xx stops the
run. The key is read from the environment and never printed. Writes docs/results/multihop_gov_v1.json as it goes.
"""
from __future__ import annotations

import datetime as dt
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
LAB = os.path.dirname(HERE)
ROOT = os.path.dirname(LAB)
sys.path.insert(0, LAB)
os.environ.setdefault("BUDGET_MIN", "300")
import mark_first as mf  # noqa: E402
import cite_score  # noqa: E402
import bill_act  # noqa: E402

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
GOV = "https://api.govinfo.gov"
KEY = os.environ.get("DATA_GOV_KEY", "").strip()
STAGE1 = os.path.join(ROOT, "docs", "results", "multihop_stage1_v1.json")
OUT = os.path.join(ROOT, "docs", "results", "multihop_gov_v1.json")
SPACING = 4.0
BUDGET_S = 300 * 60
T0 = time.time()
BILLISH = re.compile(r"\bACT\b|\bBILL\b|\bH\.R\.|\bS\. ?\d")
LAST = [0.0]
N = [0]


class Stop(Exception):
    pass


def pace():
    if time.time() - T0 > BUDGET_S:
        raise Stop("time budget reached")
    wait = SPACING - (time.time() - LAST[0])
    if wait > 0:
        time.sleep(wait)


def call(url, payload=None):
    """One GovInfo request with the key appended; the key never reaches a log."""
    pace()
    sep = "&" if "?" in url else "?"
    req = urllib.request.Request(f"{url}{sep}api_key={KEY}", data=json.dumps(payload).encode() if payload else None,
                                 headers={"User-Agent": UA, **({"Content-Type": "application/json"} if payload else {})})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            body = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        LAST[0] = time.time(); N[0] += 1
        if e.code in (403, 429) or e.code >= 500:
            raise Stop(f"GovInfo HTTP {e.code}")
        print(f"  GovInfo HTTP {e.code}", flush=True)
        return None
    except Exception as e:  # noqa: BLE001
        LAST[0] = time.time(); N[0] += 1
        print(f"  GovInfo network error: {type(e).__name__}", flush=True)
        return None
    LAST[0] = time.time(); N[0] += 1
    return body


def clean(text):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", text or ""))).strip()


def bare(t):
    return re.sub(r"\s*\([^)]*\)\s*$", "", t or "").strip()


def search(name, v, st, floor):
    body = call(f"{GOV}/search", {"query": f'"{name}" collection:(CREC)', "pageSize": 50, "offsetMark": "*",
                                  "sorts": [{"field": "publishdate", "sortOrder": "DESC"}]})
    try:
        d = json.loads(body) if body else {}
    except ValueError:
        d = {}
    res = d.get("results", [])
    keep = [x for x in res if (x.get("dateIssued") or "")[:10] >= floor and BILLISH.search((x.get("title") or "").upper())]
    out = {"count": d.get("count"), "returned": len(res), "bill_shaped_after": len(keep), "hits": []}
    stone_names = {bare(st.get("real") or ""), st.get("title") or ""} - {""}
    for x in keep[:5]:
        link = (x.get("download") or {}).get("txtLink")
        if not link:
            continue
        text = clean(call(link) or "")
        if name.lower() not in text.lower():
            continue
        win, _ = cite_score.near(text, name)
        sc, why = cite_score.score(win, name)
        date = (x.get("dateIssued") or "")[:10]
        hit = {"name": name, "title": x.get("title"), "date": date, "package": x.get("packageId"), "granule": x.get("granuleId"),
               "url": f"https://www.govinfo.gov/app/details/{x.get('packageId')}/{x.get('granuleId')}" if x.get("granuleId") else None,
               "window": win[:700], "cite_score": sc, "cite_why": why, "label": cite_score.label(sc),
               "names_stone": any(n.lower() in win.lower() for n in stone_names)}
        if hit["label"] == "reason":
            pace()
            r = bill_act.us_resolve(x.get("title") or "", date)
            LAST[0] = time.time(); N[0] += 1
            hit.update(act=r.get("act"), enacted=r.get("royal_assent"), act_url=r.get("url"), resolve_note=r.get("note"))
            hit["verdict"] = ("no public law" if not r.get("act") or not r.get("royal_assent") else
                              "busted: law before the record" if r["royal_assent"] < date else "in order")
        else:
            hit["verdict"] = "not cited as a reason"
        out["hits"].append(hit)
    return out


def main() -> int:
    if not KEY:
        print("DATA_GOV_KEY not set: nothing to do", flush=True)
        return 0
    s1 = json.load(open(STAGE1))
    state = json.load(open(OUT)) if os.path.exists(OUT) else {"protocol": "ripples/docs/multihop_plan_v1.md", "results": {}}
    state["run"] = dt.date.today().isoformat()
    state.pop("stopped", None)
    todo = []
    for st in s1["stones"]:
        for v in st.get("survivors", []):
            if v.get("us") and v.get("names"):
                todo.append((st, v))
    state["survivors_tied_to_us"] = len(todo)
    print(len(todo), "survivors tied to the United States", flush=True)
    try:
        for st, v in todo:
            key = f"{st['real']}|{v['title']}"
            if key in state["results"]:
                continue
            h1 = v["date"] if len(v["date"]) == 10 else f"{v['date'][:4]}-01-01"
            floor = max(h1, st["date"] if len(st["date"]) == 10 else f"{st['date'][:4]}-01-01", "1995-01-01")
            r = search(v["names"][0], v, st, floor)
            r.update(stone=st["real"], set=st["set"], intermediate=v["title"], floor=floor)
            state["results"][key] = r
            ok = [h for h in r["hits"] if h.get("verdict") == "in order"]
            print(f"  {st['set']:6s} {st['real'][:28]:28s} -> {v['title'][:30]:30s} | CREC {r['count']} | bill-shaped after {r['bill_shaped_after']} "
                  f"| in order {len(ok)} {'; '.join((h.get('act') or '')[:50] for h in ok[:2])}", flush=True)
            state["requests"] = N[0]
            json.dump(state, open(OUT, "w"), ensure_ascii=False, indent=0)
    except (Stop, mf.Stop) as e:
        state["stopped"] = str(e)
        print("stopped:", e, flush=True)
    state["requests"] = N[0]
    json.dump(state, open(OUT, "w"), ensure_ascii=False, indent=0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
