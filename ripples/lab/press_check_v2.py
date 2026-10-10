"""Press share check v2. Runs only in .github/workflows/ripples-press-check-v2.yml.

For every item in ripples/lab/press_check_v2_queries.json: how many newspaper articles name both the stone and the
outcome (the pair query), and how many name the stone at all (the stone query, one per stone). The share is the first
divided by the second. Two sources: the Guardian Content API (response.total) and the NYT Article Search API
(response.metadata.hits, or response.meta.hits). Counts only: no article text, no article lists, no URLs are kept.

What changed from v1 (ripples/lab/press_check_v1.py):
  - New items: the candidates of discovery v4 and of the recent-events pilot, plus the 20 planted controls.
  - NYT syntax. v1's ("s1" | "s2") +("o1" | "o2") failed the operator check (OR 287, AND 287, single 790). v2 sends the
    single phrase once, then tries these renderers in order and keeps the first that passes the check:
      lucene   ("s1" OR "s2") AND ("o1" OR "o2")
      sqs_plus +("s1" | "s2") +("o1" | "o2")
      double   ("s1" || "s2") && ("o1" || "o2")
    If none passes, NYT stops after at most 7 requests and records why.
  - The repo's retry rule (ripples/engine/fetch.py): a 5xx, a 429, a timeout or a connection error gets one retry after
    a wait (Retry-After when it is 300 s or less, else 60 s). A second failure, or any other 4xx, stops that source.
The Guardian renderer is v1's: ("s1" OR "s2") AND ("o1" OR "o2").

Politeness: honest user agent; Guardian at most one request a second; NYT one request every 12.5 seconds (its published
limit is 5 a minute and 500 a day); at most 480 requests per source in a run, retries included. Order per source: the
operator check, then pair queries, then stone queries, items and stones in the order of the sha256 of their id.

Keys come from the environment (repository secrets GUARDIAN_API_KEY and NYT_API_KEY). Both APIs take the key only as a
query parameter, so request URLs are never printed, logged or written. A source without a key is skipped.

Resumable: when the output already holds results for the same queries file, counts it has are kept and only the rest
are requested.

  python ripples/lab/press_check_v2.py             run
  python ripples/lab/press_check_v2.py --dry-run   print the plan and the query strings; no network
Output: ripples/docs/results/press_check_v2.json.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
QUERIES = os.path.join(ROOT, "lab", "press_check_v2_queries.json")
OUT = os.path.join(ROOT, "docs", "results", "press_check_v2.json")
UA = "ripple-research (bensunter.com)"
TIMEOUT = 60
PROBE = ("Silent Spring", "Rachel Carson")
RETRY_DEFAULT = 60
RETRY_MAX_WAIT = 300

SOURCES = {
    "guardian": {"base": "https://content.guardianapis.com/search", "env": "GUARDIAN_API_KEY", "spacing": 1.0,
                 "cap": 480, "extra": {"page-size": "1"}, "count_field": "response.total"},
    "nyt": {"base": "https://api.nytimes.com/svc/search/v2/articlesearch.json", "env": "NYT_API_KEY", "spacing": 12.5,
            "cap": 480, "extra": {}, "count_field": "response.metadata.hits", "ceiling": 10000},
}
NYT_SYNTAXES = ("lucene", "sqs_plus", "double")


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def quoted(phrases: list[str]) -> list[str]:
    return ['"' + p + '"' for p in phrases]


def render(syntax: str, stone: list[str], outcome: list[str] | None = None) -> str:
    """The query string for a stone alone, or for a stone and an outcome together, in one syntax."""
    if syntax == "lucene":  # the Guardian's syntax, and NYT candidate 1
        s = "(" + " OR ".join(quoted(stone)) + ")"
        return s if outcome is None else s + " AND (" + " OR ".join(quoted(outcome)) + ")"
    if syntax == "sqs_plus":
        s = "+(" + " | ".join(quoted(stone)) + ")"
        return s if outcome is None else s + " +(" + " | ".join(quoted(outcome)) + ")"
    if syntax == "double":
        s = "(" + " || ".join(quoted(stone)) + ")"
        return s if outcome is None else s + " && (" + " || ".join(quoted(outcome)) + ")"
    raise ValueError(syntax)


def probe_ok(single, or_, and_) -> bool:
    try:
        a, o, n = single["count"], or_["count"], and_["count"]
    except (KeyError, TypeError):
        return False
    return a > 0 and o >= a and n <= a and n < o


class Stop(Exception):
    pass


class Client:
    def __init__(self, name: str, key: str):
        self.name = name
        self.cfg = SOURCES[name]
        self._key = key
        self.used = 0
        self.retries = 0
        self._last_end = 0.0

    def _attempt(self, q: str):
        """One request. Returns (status, body, retry_after). status 0 means a timeout or connection error."""
        if self.used >= self.cfg["cap"]:
            raise Stop(f"request cap of {self.cfg['cap']} reached")
        wait = self._last_end + self.cfg["spacing"] - time.time()
        if wait > 0:
            time.sleep(wait)
        params = {"q": q, **self.cfg["extra"], "api-key": self._key}
        url = self.cfg["base"] + "?" + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
        self.used += 1
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                return r.status, r.read(), None
        except urllib.error.HTTPError as e:
            ra = (e.headers.get("Retry-After") or "").strip() if e.headers else ""
            return e.code, b"", int(ra) if ra.isdigit() else None
        except Exception as e:  # timeouts, connection errors; the message is not kept in case it repeats the URL
            return 0, type(e).__name__.encode(), None
        finally:
            self._last_end = time.time()

    def count(self, q: str) -> dict:
        """One search, with at most one retry. Returns {"count": n, ...}; raises Stop on anything that ends this source."""
        status, body, retry_after = self._attempt(q)
        if status == 0 or status == 429 or status >= 500:
            pause = retry_after if retry_after is not None and retry_after <= RETRY_MAX_WAIT else RETRY_DEFAULT
            print(f"{self.name}: retry in {pause} s after {status or body.decode()}", flush=True)
            time.sleep(pause)
            self.retries += 1
            status, body, retry_after = self._attempt(q)
        if status == 0:
            raise Stop(body.decode() or "connection error")
        if status != 200:
            raise Stop(f"HTTP {status}")
        try:
            js = json.loads(body)
        except ValueError:
            raise Stop("answer was not JSON")
        resp = js.get("response") if isinstance(js, dict) else None
        if not isinstance(resp, dict):
            raise Stop("answer had no response object")
        if self.name == "guardian":
            if resp.get("status") not in (None, "ok"):
                raise Stop(f"status {resp.get('status')!r}")
            n, path = resp.get("total"), "response.total"
        else:
            meta, path = resp.get("metadata"), "response.metadata.hits"
            if not isinstance(meta, dict):
                meta, path = resp.get("meta"), "response.meta.hits"
            n = meta.get("hits") if isinstance(meta, dict) else None
        if not isinstance(n, int) or isinstance(n, bool):
            raise Stop(f"count field {self.cfg['count_field']} missing")
        rec = {"count": n, "status": "ok", "field": path}
        ceiling = self.cfg.get("ceiling")
        if ceiling and n >= ceiling:
            rec["at_ceiling"] = True
        return rec


def load_queries() -> tuple[dict, str]:
    raw = open(QUERIES, "rb").read()
    reg = json.loads(raw)
    stones = {s["key"]: s for s in reg["stones"]}
    for it in reg["items"]:
        if it["stone"] not in stones:
            raise SystemExit(f"item {it['id']} names an unknown stone {it['stone']}")
    return reg, hashlib.sha256(raw).hexdigest()


def plan(reg: dict, src: str, syntax: str) -> list[dict]:
    """Every count request one source needs after its operator check, in the registered order."""
    stones = {s["key"]: s for s in reg["stones"]}
    items = sorted(reg["items"], key=lambda it: sha(it["id"]))
    used = sorted({it["stone"] for it in reg["items"]}, key=sha)
    out = [{"source": src, "kind": "pair", "key": it["id"],
            "q": render(syntax, stones[it["stone"]]["phrases"], it["outcome_phrases"])} for it in items]
    out += [{"source": src, "kind": "stone", "key": sk, "q": render(syntax, stones[sk]["phrases"])} for sk in used]
    return out


def probe_plan(src: str) -> list[tuple[str, dict]]:
    """(syntax, {single, or, and}) in the order they are tried."""
    a, b = PROBE
    if src == "guardian":
        return [("lucene", {"single": render("lucene", [a]), "or": render("lucene", [a, b]),
                            "and": render("lucene", [a], [b])})]
    single = '"' + a + '"'
    return [(syn, {"single": single, "or": render(syn, [a, b]), "and": render(syn, [a], [b])}) for syn in NYT_SYNTAXES]


def main() -> int:
    reg, qsha = load_queries()
    if "--dry-run" in sys.argv:
        for src in SOURCES:
            pp = probe_plan(src)
            probes = 1 + 2 * len(pp) if src == "nyt" else 3
            reqs = plan(reg, src, pp[0][0])
            unique = len({r["q"] for r in reqs})
            print(f"{src}: probe up to {probes}, {len(reqs)} count queries, {unique} distinct, "
                  f"at least {(unique + probes) * SOURCES[src]['spacing'] / 60:.0f} min of spacing", flush=True)
            for syn, qs in pp:
                print(src, "probe", syn, json.dumps(qs))
        for r in plan(reg, "guardian", "lucene"):
            print(r["source"], r["kind"], r["key"], r["q"])
        return 0

    keys = {src: os.environ.get(cfg["env"], "").strip() for src, cfg in SOURCES.items()}
    if not any(keys.values()):
        print("no key for either source in the environment; nothing run", flush=True)
        return 1

    out = None
    if os.path.exists(OUT):
        try:
            prev = json.load(open(OUT))
            if prev.get("queries_sha256") == qsha:
                out = prev
        except ValueError:
            out = None
    if out is None:
        out = {"check": "press share check v2", "script": "ripples/lab/press_check_v2.py",
               "queries": "ripples/lab/press_check_v2_queries.json", "queries_sha256": qsha, "user_agent": UA,
               "sources": {src: {"endpoint": cfg["base"], "count_field": cfg["count_field"], "spacing_s": cfg["spacing"],
                                 "cap_per_run": cfg["cap"], **({"ceiling": cfg["ceiling"]} if cfg.get("ceiling") else {})}
                           for src, cfg in SOURCES.items()},
               "syntax": {}, "runs": [], "probe": {src: {} for src in SOURCES},
               "pairs": {it["id"]: {"stone": it["stone"], "q": {}, "counts": {}} for it in reg["items"]},
               "stones": {s["key"]: {"q": {}, "counts": {}} for s in reg["stones"]}}
    run = {"started": now(), "finished": None, "sources": {}}
    out["runs"].append(run)

    def save():
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        tmp = OUT + ".tmp"
        with open(tmp, "w") as f:
            json.dump(out, f, indent=1, ensure_ascii=False)
        os.replace(tmp, OUT)

    for src in SOURCES:
        rs = {"status": None, "stop": None, "requests": 0, "retries": 0}
        run["sources"][src] = rs
        if not keys[src]:
            rs["status"] = "skipped: no key"
            print(f"{src}: no key in the environment; skipped", flush=True)
            save()
            continue
        c = Client(src, keys[src])
        cache: dict = {}

        def ask(q: str) -> dict:
            if q not in cache:
                res = c.count(q)
                res["at"] = now()
                cache[q] = res
            return dict(cache[q])

        try:
            # operator check: keep the first syntax that passes (a passed syntax from an earlier run is reused)
            syntax = out["syntax"].get(src)
            if not syntax:
                for syn, qs in probe_plan(src):
                    rec = out["probe"][src].setdefault(syn, {})
                    for k in ("single", "or", "and"):
                        try:
                            rec[k] = {**ask(qs[k]), "q": qs[k]}
                        except Stop as e:
                            rec[k] = {"status": f"stopped: {e}", "q": qs[k]}
                            raise
                        print(f"{src} probe {syn} {k} {rec[k]['count']}", flush=True)
                    rec["passed"] = probe_ok(rec["single"], rec["or"], rec["and"])
                    save()
                    if rec["passed"]:
                        syntax = syn
                        break
                if not syntax:
                    raise Stop("operator check failed for every syntax: OR did not widen or AND did not narrow")
                out["syntax"][src] = syntax
            reqs = plan(reg, src, syntax)
            for i, r in enumerate(reqs):
                slot = (out["pairs"] if r["kind"] == "pair" else out["stones"])[r["key"]]
                slot["q"][src] = r["q"]
                have = slot["counts"].get(src)
                if have and have.get("status") == "ok":
                    continue
                try:
                    res = ask(r["q"])
                except Stop as e:
                    slot["counts"][src] = {"status": f"stopped: {e}", "at": now()}
                    raise
                slot["counts"][src] = res
                print(f"{src} {i + 1}/{len(reqs)} {r['kind']} {r['key']} {res['status']} {res['count']}", flush=True)
                if c.used % 10 == 0:
                    rs["requests"], rs["retries"] = c.used, c.retries
                    save()
            rs["status"] = "done"
        except Stop as e:
            rs["status"] = "stopped"
            rs["stop"] = str(e)
            print(f"{src}: stopped: {e}", flush=True)
        rs["requests"], rs["retries"] = c.used, c.retries
        save()

    run["finished"] = now()
    for src in SOURCES:
        ok = sum(1 for p in out["pairs"].values() if (p["counts"].get(src) or {}).get("status") == "ok")
        out["sources"][src]["pairs_ok"] = ok
        out["sources"][src]["stones_ok"] = sum(1 for s in out["stones"].values()
                                               if (s["counts"].get(src) or {}).get("status") == "ok")
        out["sources"][src]["syntax"] = out["syntax"].get(src)
        print(f"{src}: {ok}/{len(out['pairs'])} pair counts, syntax {out['syntax'].get(src)}, "
              f"run status {run['sources'][src]['status']}", flush=True)
    save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
