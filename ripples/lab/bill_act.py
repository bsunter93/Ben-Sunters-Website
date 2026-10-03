"""Bill -> Act resolver v1: for every bill a cultural work was cited in (mark-text results), find the Act it became.

Sources, keyless: the UK Parliament Bills API (bills from 2001; stages with dates, Royal Assent among them) and
legislation.gov.uk (title search within a year range, as an Atom feed) for older bills and for the Act's own page.
Output: ripples/docs/results/bill_act_v1.json: per bill, the Act, its Royal Assent date, the page, the method; per
(work, bill) pair, whether the work came before the Act. Honest UA, 1 s between requests, stop on refusal.
"""
from __future__ import annotations

import datetime as dt
import glob
import html
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(__file__))
import mark_first as mf  # noqa: E402
import cite_score  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.environ.get("OUT_JSON") or os.path.join(ROOT, "docs", "results", "bill_act_v1.json")
BILLS = "https://bills-api.parliament.uk/api/v1"
UKL = "https://www.legislation.gov.uk"


def clean_bill(name):
    s = re.sub(r"\s*\[(HL|Lords)\]|\s*\((First|Second|Third|Fourth|Fifth|Sixth|Seventh|Eighth|Ninth|Tenth|\w+) sitting\)|\s+Lords$", "", name).strip()
    s = re.sub(r"\s+", " ", s)
    return s


def bills_api(title, when):
    """Best match in the Bills API: same short title (less 'Bill'), session not before the debate year."""
    q = urllib.parse.urlencode({"SearchTerm": re.sub(r"\s+Bill$", "", title), "Take": 20, "SortOrder": "DateUpdatedDescending"})
    body = mf.get(f"{BILLS}/Bills?{q}")
    try:
        items = json.loads(body).get("items", [])
    except (ValueError, TypeError, AttributeError):
        return None
    want = re.sub(r"\s+Bill$", "", title).lower()
    year = int(when[:4]) if when else None
    best = None
    for it in items:
        st = re.sub(r"\s+Bill$", "", it.get("shortTitle", "")).lower()
        if st != want and not (want in st or st in want):
            continue
        upd = (it.get("lastUpdate") or "")[:4]
        if year and upd and int(upd) < year - 1:
            continue
        if best is None or it.get("isAct"):
            best = it
            if it.get("isAct"):
                break
    if not best:
        return None
    stages = []
    body = mf.get(f"{BILLS}/Bills/{best['billId']}/Stages?Take=60")
    try:
        stages = json.loads(body).get("items", [])
    except (ValueError, TypeError, AttributeError):
        pass
    ra = None
    for s in stages:
        if (s.get("description") or "").lower().startswith("royal assent"):
            ds = [x.get("date") for x in s.get("stageSittings", []) if x.get("date")]
            if ds:
                ra = min(ds)[:10]
    return {"bill_id": best["billId"], "short_title": best.get("shortTitle"), "is_act": bool(best.get("isAct")), "royal_assent": ra,
            "current_stage": (best.get("currentStage") or {}).get("description"), "source": f"{BILLS}/Bills/{best['billId']}"}


def legislation_feed(act_title, y0, y1):
    """UK public general acts whose title matches, in [y0, y1]: (title, year, url) list."""
    out = []
    for y in range(y0, y1 + 1):
        q = urllib.parse.urlencode({"title": act_title})
        body = mf.get(f"{UKL}/ukpga/{y}/data.feed?{q}", headers={"Accept": "application/atom+xml"})
        if not body or "<entry" not in body:
            continue
        for e in re.findall(r"<entry>(.*?)</entry>", body, re.S):
            t = re.search(r"<title[^>]*>(.*?)</title>", e, re.S)
            i = re.search(r"<id>(.*?)</id>", e)
            if not (t and i):
                continue
            # the feed can answer across years; keep only an Act whose own year is in range
            ym = re.search(r"/ukpga/(\d{4})/", i.group(1))
            if not ym or not (y0 <= int(ym.group(1)) <= y1):
                continue
            out.append((html.unescape(re.sub(r"<[^>]+>", "", t.group(1))).strip(), int(ym.group(1)), i.group(1).replace("/id/", "/")))
    return out


def resolve(bill, when):
    """Act name, Royal Assent date (or year), page and method for a bill debated on `when`."""
    title = clean_bill(bill)
    base = re.sub(r"\s+Bill$", "", title)
    year = int(when[:4]) if when else None
    res = {"bill": bill, "clean": title, "debated": when, "act": None, "royal_assent": None, "url": None, "method": None, "note": None}
    if year and year >= 2001:
        b = bills_api(title, when)
        if b:
            res["bills_api"] = b
            if b["is_act"] and b["royal_assent"]:
                res.update(act=f"{base} Act {b['royal_assent'][:4]}", royal_assent=b["royal_assent"], method="bills-api")
            elif b["is_act"]:
                res.update(act=f"{base} Act", method="bills-api (no assent date)")
            else:
                res.update(note=f"not an Act: {b['current_stage']}", method="bills-api")
                return res  # a bill the API knows and that did not pass: no fallback guessing
    if not res["act"] or not res["url"]:
        hits = legislation_feed(base, year or 1900, (year or 1900) + 2) if year else []
        # the Act's title must begin with the bill's title (less 'Bill'), so 'Housing Bill' cannot land on 'Housing (Scotland) Act'
        hits = [h for h in hits if re.sub(r"\s+act\s+\d{4}.*$", "", h[0].lower()).strip() == base.lower().strip()]
        if hits:
            t, y, u = sorted(hits, key=lambda h: h[1])[0]
            res.update(act=res["act"] or t, url=u, method=(res["method"] or "") + "+legislation.gov.uk")
            if not res["royal_assent"]:
                res["royal_assent"] = f"{y}-07-01"
                res["note"] = (res["note"] or "") + " assent date approximate (year from the Act's title)"
    return res


def main() -> int:
    pairs = []
    for f in sorted(glob.glob(os.path.join(ROOT, "docs", "results", "mark_text_v1*.json"))):
        try:
            pairs += json.load(open(f)).get("pairs", [])
        except ValueError:
            pass
    bills = {}
    # one resolution per bill name and session year: "Criminal Justice Bill" is a different bill in 1982 and in 2024
    for p in pairs:
        if p.get("source") == "HAN" and p.get("tier") in ("bill debate", "bill stage") and re.search(r"\bBill\b", p["mark"]):
            key = f"{clean_bill(p['mark'])} ({(p.get('mark_date') or '')[:4]})"
            if key not in bills or (p.get("mark_date") or "") < (bills[key] or ""):
                bills[key] = p.get("mark_date")
    print(len(bills), "bills to resolve", flush=True)
    state = json.load(open(OUT)) if os.path.exists(OUT) else {"started": dt.date.today().isoformat(), "bills": {}}
    try:
        for key in sorted(bills, key=lambda k: bills[k] or ""):
            if key in state["bills"]:
                continue
            r = resolve(re.sub(r" \(\d{4}\)$", "", key), bills[key])
            state["bills"][key] = r
            print(f"  {key} ({bills[key]}) -> {r['act']} {r['royal_assent']} [{r['method']}] {r['note'] or ''}", flush=True)
            json.dump(state, open(OUT, "w"), ensure_ascii=False, indent=0)
    except mf.Stop as e:
        state["stopped"] = str(e); print("stopped:", e, flush=True)
    # pairs enriched with the Act
    out_pairs = []
    for p in pairs:
        if p.get("source") != "HAN" or p.get("tier") not in ("bill debate", "bill stage"):
            continue
        r = state["bills"].get(f"{clean_bill(p['mark'])} ({(p.get('mark_date') or '')[:4]})")
        if not r or not r.get("act"):
            continue
        ra = r.get("royal_assent")
        ordered = bool(p.get("work_date") and ra and p["work_date"] <= ra)
        cs, cwhy = cite_score.score(p.get("sentence") or "", p["work"])
        out_pairs.append({"work": p["work"], "work_date": p["work_date"], "bill": p["mark"], "debated": p["mark_date"], "act": r["act"], "cite_score": cs, "cite_why": cwhy, "cite_label": cite_score.label(cs),
                          "royal_assent": ra, "act_url": r.get("url"), "ordered": ordered, "causal_score": p.get("causal_score"),
                          "sentence": p.get("sentence"), "debate_url": p.get("url")})
    seen = set(); uniq = []
    for q in sorted(out_pairs, key=lambda q: (-(q["cite_score"] or 0), -(q["causal_score"] or 0), q["royal_assent"] or "")):
        k = (q["work"], q["act"])
        if k not in seen:
            seen.add(k); uniq.append(q)
    state["pairs"] = uniq
    state["summary"] = {"bills": len(bills), "resolved": sum(1 for r in state["bills"].values() if r.get("act")),
                        "enacted_pairs": len(uniq), "ordered_pairs": sum(1 for q in uniq if q["ordered"])}
    json.dump(state, open(OUT, "w"), ensure_ascii=False, indent=0)
    print(json.dumps(state["summary"]))
    for q in uniq[:40]:
        print(f"  {q['work']} ({q['work_date']}) -> {q['act']} ({q['royal_assent']}) via '{q['bill'][:50]}' {q['debated']} c{q['causal_score']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
