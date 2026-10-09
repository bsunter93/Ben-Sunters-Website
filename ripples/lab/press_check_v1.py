"""Press co-mention check v1. Runs only in .github/workflows/ripples-press-check.yml.

For every item in ripples/lab/press_check_v1_queries.json: how many newspaper articles name both the stone and the
outcome (the pair query), and how many name the stone at all (the stone query, one per stone, for normalization). Two
sources: the Guardian Content API (response.total) and the NYT Article Search API (response.meta.hits). Counts only: no
article text, no article lists, no URLs are kept.

Query syntax per source, built from the phrase sets in the queries file:
  Guardian  ("s1" OR "s2") AND ("o1" OR "o2")       q supports AND, OR, NOT and quoted phrases
  NYT       ("s1" | "s2") +("o1" | "o2")            q uses simple query string syntax: | is OR, + is AND
Before the counts, each source gets a three-request operator check ("Silent Spring", then OR and AND with
"Rachel Carson"). If OR does not widen and AND does not narrow, that source stops and records why.

Politeness: honest user agent; Guardian at most one request a second and at most 480 requests in a run; NYT one request
every 12.5 seconds (its published limit is 5 a minute and 500 a day) and at most 480 in a run. A source stops on any
4xx or 5xx answer, a timeout, a connection error or an answer without the count field, and the stop is recorded. Order:
the operator check, then pair queries, then stone queries, items in the order of the sha256 of their id.

Keys come from the environment (repository secrets GUARDIAN_API_KEY and NYT_API_KEY). Both APIs take the key only as a
query parameter, so request URLs are never printed, logged or written. A source without a key is skipped.

Resumable: when the output already holds results for the same queries file, counts it has are kept and only the rest
are requested.

  python ripples/lab/press_check_v1.py             run
  python ripples/lab/press_check_v1.py --dry-run   print the plan and the query strings; no network
Output: ripples/docs/results/press_check_v1.json.
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
QUERIES = os.path.join(ROOT, "lab", "press_check_v1_queries.json")
OUT = os.path.join(ROOT, "docs", "results", "press_check_v1.json")
UA = "ripple-research (bensunter.com)"
TIMEOUT = 60
PROBE = ("Silent Spring", "Rachel Carson")

SOURCES = {
    "guardian": {"base": "https://content.guardianapis.com/search", "env": "GUARDIAN_API_KEY", "spacing": 1.0,
                 "cap": 480, "extra": {"page-size": "1"}, "count_field": "response.total"},
    "nyt": {"base": "https://api.nytimes.com/svc/search/v2/articlesearch.json", "env": "NYT_API_KEY", "spacing": 12.5,
            "cap": 480, "extra": {}, "count_field": "response.meta.hits", "ceiling": 10000},
}


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def quoted(phrases: list[str]) -> list[str]:
    return ['"' + p + '"' for p in phrases]


def render(source: str, stone: list[str], outcome: list[str] | None = None) -> str:
    """The query string for a stone alone, or for a stone and an outcome together."""
    if source == "guardian":
        s = "(" + " OR ".join(quoted(stone)) + ")"
        return s if outcome is None else s + " AND (" + " OR ".join(quoted(outcome)) + ")"
    s = "(" + " | ".join(quoted(stone)) + ")"
    return s if outcome is None else s + " +(" + " | ".join(quoted(outcome)) + ")"


def probe_queries(source: str) -> dict:
    a, b = PROBE
    return {"single": render(source, [a]), "or": render(source, [a, b]), "and": render(source, [a], [b])}


class Stop(Exception):
    pass


class Client:
    def __init__(self, name: str, key: str):
        self.name = name
        self.cfg = SOURCES[name]
        self._key = key
        self.used = 0
        self._last_end = 0.0

    def count(self, q: str) -> dict:
        """One search request. Returns {"count": n, ...}; raises Stop on anything that should end this source."""
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
                body = r.read()
        except urllib.error.HTTPError as e:
            raise Stop(f"HTTP {e.code}")
        except Exception as e:  # timeouts, connection errors; the message is not kept in case it repeats the URL
            raise Stop(type(e).__name__)
        finally:
            self._last_end = time.time()
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
            meta = resp.get("meta")
            path = "response.meta.hits"
            if not isinstance(meta, dict):
                meta, path = resp.get("metadata"), "response.metadata.hits"
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


def plan(reg: dict) -> list[dict]:
    """Every request the run needs, per source, in the registered order."""
    stones = {s["key"]: s for s in reg["stones"]}
    items = sorted(reg["items"], key=lambda it: sha(it["id"]))
    used = sorted({it["stone"] for it in reg["items"]}, key=sha)
    out = []
    for src in SOURCES:
        for k, q in probe_queries(src).items():
            out.append({"source": src, "kind": "probe", "key": k, "q": q})
        for it in items:
            out.append({"source": src, "kind": "pair", "key": it["id"],
                        "q": render(src, stones[it["stone"]]["phrases"], it["outcome_phrases"])})
        for sk in used:
            out.append({"source": src, "kind": "stone", "key": sk, "q": render(src, stones[sk]["phrases"])})
    return out


def probe_ok(p: dict) -> bool:
    try:
        a, o, n = p["single"]["count"], p["or"]["count"], p["and"]["count"]
    except (KeyError, TypeError):
        return False
    return a > 0 and o >= a and n <= a and n < o


def main() -> int:
    reg, qsha = load_queries()
    reqs = plan(reg)
    if "--dry-run" in sys.argv:
        for src in SOURCES:
            mine = [r for r in reqs if r["source"] == src]
            kinds = {k: sum(1 for r in mine if r["kind"] == k) for k in ("probe", "pair", "stone")}
            unique = len({r["q"] for r in mine})
            secs = unique * SOURCES[src]["spacing"]
            print(f"{src}: {len(mine)} queries {kinds}, {unique} distinct requests, at least {secs / 60:.0f} min of spacing",
                  flush=True)
        for r in reqs:
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
        out = {"check": "press co-mention check v1", "script": "ripples/lab/press_check_v1.py",
               "queries": "ripples/lab/press_check_v1_queries.json", "queries_sha256": qsha, "user_agent": UA,
               "sources": {src: {"endpoint": cfg["base"], "count_field": cfg["count_field"], "spacing_s": cfg["spacing"],
                                 "cap_per_run": cfg["cap"], **({"ceiling": cfg["ceiling"]} if cfg.get("ceiling") else {})}
                           for src, cfg in SOURCES.items()},
               "syntax": {src: render(src, ["s1", "s2"], ["o1", "o2"]) for src in SOURCES},
               "runs": [], "probe": {src: {} for src in SOURCES},
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

    def slot(r: dict) -> dict:
        if r["kind"] == "probe":
            return out["probe"][r["source"]]
        return (out["pairs"] if r["kind"] == "pair" else out["stones"])[r["key"]]["counts"]

    for src in SOURCES:
        rs = {"status": None, "stop": None, "requests": 0}
        run["sources"][src] = rs
        if not keys[src]:
            rs["status"] = "skipped: no key"
            print(f"{src}: no key in the environment; skipped", flush=True)
            save()
            continue
        c = Client(src, keys[src])
        mine = [r for r in reqs if r["source"] == src]
        cache: dict = {}
        try:
            for i, r in enumerate(mine):
                if r["kind"] != "probe":
                    (out["pairs"] if r["kind"] == "pair" else out["stones"])[r["key"]]["q"][src] = r["q"]
                    have = slot(r).get(src)
                    if have and have.get("status") == "ok":
                        continue
                elif probe_ok(out["probe"][src]):
                    continue
                if r["q"] in cache:
                    res = dict(cache[r["q"]])
                else:
                    try:
                        res = c.count(r["q"])
                    except Stop as e:
                        if r["kind"] == "probe":
                            out["probe"][src][r["key"]] = {"status": f"stopped: {e}"}
                        else:
                            slot(r)[src] = {"status": f"stopped: {e}", "at": now()}
                        raise
                    res["at"] = now()
                    cache[r["q"]] = res
                if r["kind"] == "probe":
                    out["probe"][src][r["key"]] = {**res, "q": r["q"]}
                    if r["key"] == "and" and not probe_ok(out["probe"][src]):
                        raise Stop("operator check failed: OR did not widen or AND did not narrow")
                else:
                    slot(r)[src] = res
                print(f"{src} {i + 1}/{len(mine)} {r['kind']} {r['key']} {res['status']} {res['count']}", flush=True)
                if c.used % 10 == 0:
                    rs["requests"] = c.used
                    save()
            rs["status"] = "done"
        except Stop as e:
            rs["status"] = "stopped"
            rs["stop"] = str(e)
            print(f"{src}: stopped: {e}", flush=True)
        rs["requests"] = c.used
        save()

    run["finished"] = now()
    for src in SOURCES:
        ok = sum(1 for p in out["pairs"].values() if (p["counts"].get(src) or {}).get("status") == "ok")
        out["sources"][src]["pairs_ok"] = ok
        out["sources"][src]["stones_ok"] = sum(1 for s in out["stones"].values()
                                               if (s["counts"].get(src) or {}).get("status") == "ok")
        out["sources"][src]["operator_check_passed"] = probe_ok(out["probe"][src])
        print(f"{src}: {ok}/{len(out['pairs'])} pair counts, run status {run['sources'][src]['status']}", flush=True)
    save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
