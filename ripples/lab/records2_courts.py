"""Records 2, courts (ripples/docs/records2_plan_v1.md, section 9 and the Oct 5 addendum): US court opinions on CourtListener.

Runs only inside .github/workflows/ripples-courts.yml, which passes the account token from the repository secret as the
environment variable COURT_LISTENER_API. The token goes only into the documented Authorization header; it is never
printed, logged or written. One run a day at most; the run resumes from the done list in the results file.

Pacing, from the API's documented limits (5 a minute, 50 an hour, 125 a day, rolling windows): 80 seconds between
requests (45 an hour at most), and a run budget of min(100, the day's remaining allowance minus 10) read from the
usage API, which has its own throttle. A stop for the day on any 401, 403, 429 or 5xx, or a timeout; no retry.

Order: the cultural works first, then the famous-film decoys, then events, then things. Per stone: one search of
published opinions (the default), the stone's phrases in quotes, the registered disambiguation, filed on or after the
stone's date; the opinion text is read only for results whose snippet passes the same guard as the Federal Register
run, three opinions per stone at most. Stored: the work, the case name, the court, the date filed, the one sentence,
the URL and the labels. Output: ripples/docs/results/records2_courts_v1.json.
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
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import cite_score  # noqa: E402
import records2 as r2  # noqa: E402

OUT = os.path.join(r2.RES, "records2_courts_v1.json")
API = "https://www.courtlistener.com/api/rest/v4"
SITE = "https://www.courtlistener.com"
GAP = 80.0           # seconds between counted requests: 45 an hour, under the 50-an-hour limit
RUN_CAP = 100        # counted requests per run, under the 125-a-day limit
MARGIN = 10          # left unused from the day's remaining allowance
MAX_OPINIONS = 3     # opinion texts read per stone
WORK_OR = "(film OR movie OR television OR documentary OR novel OR book)"
TOKEN = os.environ.get("COURT_LISTENER_API", "").strip()


class Stop(Exception):
    pass


_last = [0.0]
_n = [0]


def call(path, params=None, counted=True):
    """One authenticated GET. The token is sent in the header and nowhere else."""
    if counted:
        wait = GAP - (time.time() - _last[0])
        if wait > 0:
            time.sleep(wait)
    url = f"{API}{path}" + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"User-Agent": r2.UA, "Accept": "application/json", "Authorization": f"Token {TOKEN}"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            body = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        raise Stop(f"HTTP {e.code} on {path}") from None
    except Exception as e:  # noqa: BLE001
        raise Stop(f"{type(e).__name__} on {path}") from None
    finally:
        if counted:
            _last[0] = time.time(); _n[0] += 1
    try:
        return json.loads(body)
    except ValueError:
        raise Stop(f"not JSON on {path}") from None


def usage():
    """The day's and the hour's allowance for the account, from the usage API (its own throttle)."""
    d = call("/api-usage/", counted=False)
    out = {}
    for u in d.get("current_usage", []):
        if u.get("scope") == "user":
            out[u.get("rate")] = {k: u.get(k) for k in ("used", "limit", "remaining", "reset_at", "blocked")}
    return out


def court_query(rec):
    phrases = [f'"{p}"' for p in rec["phrases"]]
    q = phrases[0] if len(phrases) == 1 else "(" + " OR ".join(phrases) + ")"
    if rec["amb"]:
        if rec["type"] == "work":
            q += f" AND {WORK_OR}"
        elif rec.get("word"):
            q += f" AND {rec['word']}"
    d = rec.get("date")
    gte = d if d and len(d) == 10 else (f"{d[:4]}-01-01" if d else None)
    if gte:
        q += f" AND dateFiled:[{gte} TO *]"
    return q


def plain(s):
    s = re.sub(r"<[^>]+>", " ", s or "")
    return html.unescape(s)


def order(stones):
    rank = {"work": 0, "decoy": 1, "event": 2, "thing": 3}
    live = [s for s in stones if not s.get("skip")]
    return sorted(live, key=lambda s: (rank["decoy"] if s["group"] == "decoy" else rank[s["type"]]))


def main() -> int:
    if not TOKEN:
        print("no token in the environment: this script runs only inside the courts workflow"); return 2
    plan = json.load(open(r2.QUERIES))
    state = json.load(open(OUT)) if os.path.exists(OUT) else {"protocol": r2.PROTOCOL + " (section 9 and the Oct 5 addendum)", "done": [],
                                                              "stones": {}, "runs": [], "requests_total": 0}
    today = dt.datetime.utcnow().date().isoformat()
    if state.get("stopped", {}).get("date") == today:
        print("stopped earlier today:", state["stopped"]["why"], "; no same-day retry"); return 0
    if any(r.get("date") == today for r in state["runs"]):
        print("a run already started today (UTC); one run a day"); return 0
    run = {"date": today, "started": dt.datetime.utcnow().isoformat(timespec="seconds") + "Z"}
    state["runs"].append(run)

    def save():
        run["requests"] = _n[0]
        state["requests_total"] = sum(r.get("requests", 0) for r in state["runs"])
        json.dump(state, open(OUT + ".tmp", "w"), ensure_ascii=False, indent=0)
        os.replace(OUT + ".tmp", OUT)

    try:
        u = usage()
        run["usage_at_start"] = u
        day = u.get("125/day") or next((v for k, v in u.items() if k.endswith("/day")), None)
        hour = u.get("50/hour") or next((v for k, v in u.items() if k.endswith("/hour")), None)
        budget = RUN_CAP if not day else min(RUN_CAP, (day.get("remaining") or 0) - MARGIN)
        if hour and (hour.get("used") or 0) > 5:
            raise Stop("the hourly window already holds requests; waiting for another day")
        run["budget"] = budget
        print(f"usage at start: {json.dumps(u)}; this run's budget {budget} requests", flush=True)
        save()
        for rec in order(plan["stones"]):
            if rec["id"] in state["done"]:
                continue
            if _n[0] + 1 + MAX_OPINIONS > budget:
                print("budget reached; the next run continues from here", flush=True); break
            q = court_query(rec)
            d = call("/search/", {"q": q, "type": "o", "order_by": "score desc", "highlight": "on"})
            results = d.get("results", []) or []
            cands, read = [], []
            for x in results:
                filed = x.get("dateFiled") or ""
                for op in x.get("opinions", []) or []:
                    snip = plain(op.get("snippet"))
                    best, n, fails, _ = r2.extract(rec, snip)
                    if n:
                        cands.append((x, op, filed)); break
            for x, op, filed in cands[:MAX_OPINIONS]:
                o = call(f"/opinions/{op['id']}/", {"fields": "id,html_with_citations,plain_text,html,html_lawbox,html_columbia,xml_harvard"})
                text = next((plain(o.get(k)) for k in ("html_with_citations", "plain_text", "html_lawbox", "html_columbia", "html", "xml_harvard") if o.get(k)), "")
                read.append(item(rec, x, op, filed, text, "opinion text"))
            for x, op, filed in cands[MAX_OPINIONS:]:
                read.append(item(rec, x, op, filed, plain(op.get("snippet")), "snippet only (over the per-stone cap)"))
            state["stones"][rec["id"]] = {"stone": rec["stone"], "group": rec["group"], "type": rec["type"], "date": rec.get("date"),
                                          "query": q, "count": d.get("count"), "results": len(results), "snippet_pass": len(cands), "read": read}
            state["done"].append(rec["id"])
            print(f"{rec['group']:8s} {rec['type']:5s} {rec['stone'][:34]:34s} | hits {d.get('count')} | snippet pass {len(cands)} | "
                  f"surviving {sum(1 for i in read if i.get('passing'))} | strict {sum(1 for i in read if i.get('strict'))}", flush=True)
            save()
    except Stop as e:
        state["stopped"] = {"date": today, "why": str(e)}
        print("STOP:", e, flush=True)
    run["finished"] = dt.datetime.utcnow().isoformat(timespec="seconds") + "Z"
    save()
    left = [s["id"] for s in order(plan["stones"]) if s["id"] not in state["done"]]
    print(f"requests this run {_n[0]}; done {len(state['done'])}; left {len(left)}", flush=True)
    return 0


def item(rec, x, op, filed, text, source):
    best, n, fails, _ = r2.extract(rec, text)
    sd = rec.get("date") or ""
    if not sd or not filed:
        ordered = None
    elif len(sd) == 10:
        ordered = filed > sd
    elif filed[:4] == sd[:4]:
        ordered = "same year"
    else:
        ordered = filed[:4] > sd[:4]
    out = {"case_name": x.get("caseName"), "court": x.get("court"), "court_id": x.get("court_id"), "date_filed": filed,
           "citation": (x.get("citation") or [None])[0], "url": SITE + (x.get("absolute_url") or ""), "opinion_id": op.get("id"),
           "status": x.get("status"), "source": source, "ordered": ordered, "passing": n}
    if best:
        out.update({"sentence": best["sentence"], "cite_score": best["cite_score"], "cite_why": best["cite_why"],
                    "cite_label": best["cite_label"], "guard": best["guard"]})
        out["strict"] = bool(ordered is True and best["cite_label"] == "reason")
    return out


if __name__ == "__main__":
    sys.exit(main())
