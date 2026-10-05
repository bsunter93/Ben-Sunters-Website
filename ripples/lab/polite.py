"""The polite network layer for Ripple's data day (ripples/docs/dataday_v1.md).

Every request a data-day job makes passes through here, including the requests of frozen registered code, which runs
unchanged: `polite.py exec --config CFG -- SCRIPT ARGS` installs a hook on urllib before the script starts. The script's
own rules (its pause, its stop conditions, its outputs) still apply, and these apply on top of them:

  - the honest user agent and no other: a request that carries a different agent is not sent
  - at most one request a second per host; a host can be set slower, never faster
  - robots.txt, read once per host per run: a Crawl-delay slows the host, and a disallowed path is not requested unless
    the job registry names an exception for that host and path with the published policy that allows it
  - a request budget for the job and for the whole run
  - the shared stop ledger ripples/docs/results/host_stops.json, read before every request: a 401, 403, 429, 5xx,
    timeout or connection error is written to it at once and the host gets no further request that UTC day; a host with
    stops on three UTC days in a row is parked and gets no request until the owner clears it in the ledger
  - an optional on-disk cache keyed by URL, so a job that stopped resumes without asking again for what it already has
  - only the hosts the job declares; a connection that does not pass through this layer ends the job

When this layer will not send a request it raises PoliteHalt, a BaseException, so a script's own `except Exception` cannot
swallow it and carry on: the job ends and the data day records why.

  python3 ripples/lab/polite.py selftest    offline checks against a local server on 127.0.0.1 (no outside host)
"""
from __future__ import annotations

import datetime as dt
import hashlib
import http.client
import http.server
import io
import json
import os
import re
import runpy
import socket
import sys
import threading
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
import urllib.response
import urllib.robotparser

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
MIN_INTERVAL = 1.0          # seconds between requests to one host, the floor
PARK_DAYS = 3               # stops on this many UTC days in a row park a host
REFUSAL = {401, 403, 429}   # with every 5xx, a timeout and a connection error: a stop for the day
HALT_EXIT = 75              # exit code of `exec` when this layer ended the job
HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "..", "docs", "results", "host_stops.json")
SECRETISH = re.compile(r"key|token|secret|passw|auth|signature|sig$|session", re.I)

_REAL_URLOPEN = urllib.request.urlopen
_REAL_CONNECT = http.client.HTTPConnection.connect
_GUARD = threading.local()


class PoliteHalt(BaseException):
    def __init__(self, kind: str, host: str, detail: str):
        super().__init__(f"{kind} ({host}): {detail}")
        self.kind, self.host, self.detail = kind, host, detail


def utc_today(override: str | None = None) -> dt.date:
    return dt.date.fromisoformat(override) if override else dt.datetime.now(dt.timezone.utc).date()


def us_date(d) -> str:
    """Oct 5, 2026: the date as prose writes it (data fields stay ISO)."""
    d = dt.date.fromisoformat(d) if isinstance(d, str) else d
    return f"{d:%b} {d.day}, {d.year}"


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def host_of(url: str) -> str:
    return (urllib.parse.urlsplit(url).hostname or "").lower()


def redact(url: str) -> str:
    """The URL with credentials removed and the value of any key-like query parameter replaced, for logs and the ledger."""
    p = urllib.parse.urlsplit(url)
    q = [(k, "REDACTED" if SECRETISH.search(k) else v) for k, v in urllib.parse.parse_qsl(p.query, keep_blank_values=True)]
    netloc = p.hostname or ""
    if p.port:
        netloc += f":{p.port}"
    return urllib.parse.urlunsplit((p.scheme, netloc, p.path, urllib.parse.urlencode(q), ""))


# ------------------------------------------------------------------------------------------------------ the ledger
def load_ledger(path: str = LEDGER) -> dict:
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            led = json.load(f)
    else:
        led = {}
    led.setdefault("stops", [])
    led.setdefault("clears", [])
    return led


def save_ledger(led: dict, path: str = LEDGER) -> None:
    led["stops"].sort(key=lambda s: (s["date"], s.get("at_utc") or "", s["host"]))
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(led, f, indent=1, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def record_stop(path: str, host: str, status, job: str, url: str = "", today: dt.date | None = None) -> dict:
    led = load_ledger(path)
    entry = {"host": host, "date": (today or utc_today()).isoformat(), "status": status, "job": job,
             "at_utc": now_utc(), "path": urllib.parse.urlsplit(url).path[:160] if url else ""}
    led["stops"].append(entry)
    save_ledger(led, path)
    return entry


def stopped_on(led: dict, host: str, day: dt.date) -> dict | None:
    """The first stop recorded for host on that UTC day. A clear never lifts a same-day stop."""
    return next((s for s in led["stops"] if s["host"] == host and s["date"] == day.isoformat()), None)


def parked(led: dict, host: str, days: int = PARK_DAYS) -> tuple[str, str] | None:
    """(first, last) of a run of `days` consecutive UTC days with stops, counting only days after the host's latest clear."""
    cleared = max((c["date"] for c in led["clears"] if c["host"] == host), default="")
    ds = sorted({dt.date.fromisoformat(s["date"]) for s in led["stops"] if s["host"] == host and s["date"] > cleared})
    run = 1
    for a, b in zip(ds, ds[1:]):
        run = run + 1 if (b - a).days == 1 else 1
        if run >= days:
            return (b - dt.timedelta(days=days - 1)).isoformat(), b.isoformat()
    return None


def host_state(led: dict, host: str, today: dt.date, days: int = PARK_DAYS) -> tuple[str, str]:
    p = parked(led, host, days)
    if p:
        return "parked", f"{host} stopped on {days} UTC days in a row ({us_date(p[0])} to {us_date(p[1])}); parked until cleared in the ledger"
    s = stopped_on(led, host, today)
    if s:
        nxt = today + dt.timedelta(days=1)
        return "stopped", f"{host} answered {s['status']} on {us_date(s['date'])} (UTC); no request before {us_date(nxt)}"
    return "clear", ""


# ------------------------------------------------------------------------------------------------------ the policy
class Policy:
    """One job's rules for one run. `cfg` keys: job, hosts {host: {min_interval_s}}, budget, run_budget_left, ledger,
    cache_dir, use_cache, stop_any_4xx, robots_exceptions [{host, path_prefix, policy_url}], state_path, report_path,
    today (tests only), park_days."""

    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.job = cfg["job"]
        self.ledger = cfg.get("ledger") or LEDGER
        self.hosts = {h.lower(): max(MIN_INTERVAL, float((v or {}).get("min_interval_s", MIN_INTERVAL)))
                      for h, v in cfg["hosts"].items()}
        self.budget = int(cfg["budget"])
        self.run_left = int(cfg.get("run_budget_left", self.budget))
        self.cache_dir = cfg.get("cache_dir")
        self.use_cache = bool(cfg.get("use_cache")) and bool(self.cache_dir)
        self.any_4xx = bool(cfg.get("stop_any_4xx"))
        self.exceptions = cfg.get("robots_exceptions") or []
        self.park_days = int(cfg.get("park_days", PARK_DAYS))
        self.robots: dict = {}
        self.state = {"last_at": {}}
        sp = cfg.get("state_path")
        if sp and os.path.exists(sp):
            with open(sp) as f:
                self.state.update(json.load(f))
        self.report = {"job": self.job, "started_utc": now_utc(), "requests": 0, "cache_hits": 0, "hosts": {},
                       "stops": [], "client_errors": [], "robots": {}, "redirects": [], "halt": None}

    def today(self) -> dt.date:
        return utc_today(self.cfg.get("today"))

    # -- checks
    def check_host(self, host: str) -> None:
        if host not in self.hosts:
            raise PoliteHalt("undeclared_host", host, "the job does not declare this host")
        state, why = host_state(load_ledger(self.ledger), host, self.today(), self.park_days)
        if state != "clear":
            raise PoliteHalt(state, host, why)

    def check_robots(self, host: str, url: str) -> None:
        parts = urllib.parse.urlsplit(url)
        if host not in self.robots:
            rurl = f"{parts.scheme}://{parts.netloc}/robots.txt"
            rp = urllib.robotparser.RobotFileParser(rurl)
            try:
                r = self.send(urllib.request.Request(rurl, headers={"User-Agent": UA}), host, 30, robots=True)
                rp.parse(r.read().decode("utf-8", "replace").splitlines())
                verdict = "read"
            except urllib.error.HTTPError as e:
                if e.code in REFUSAL or e.code >= 500:
                    raise PoliteHalt("stopped", host, f"robots.txt answered {e.code}") from None
                rp.allow_all = True  # RFC 9309: an unavailable robots.txt (4xx) allows everything
                verdict = f"HTTP {e.code}: no robots.txt, everything allowed"
            except (urllib.error.URLError, OSError, http.client.HTTPException) as e:
                raise PoliteHalt("stopped", host, f"robots.txt unreachable: {type(e).__name__}") from None
            self.robots[host] = rp
            self.report["robots"][host] = {"verdict": verdict, "exceptions_used": 0}
            delay = rp.crawl_delay(UA) if verdict == "read" else None
            if delay:  # a Crawl-delay for this agent (or for all) slows the host further, never speeds it up
                self.hosts[host] = max(self.hosts[host], float(delay))
                self.report["robots"][host]["crawl_delay_s"] = float(delay)
        if self.robots[host].can_fetch(UA, url):
            return
        exc = next((x for x in self.exceptions if x["host"] == host and parts.path.startswith(x["path_prefix"])), None)
        if exc:
            self.report["robots"][host]["exceptions_used"] += 1
            self.report["robots"][host]["exception"] = exc.get("policy_url")
            return
        raise PoliteHalt("robots", host, f"robots.txt disallows {parts.path} for this agent")

    # -- the one place a request leaves the machine
    def send(self, req: urllib.request.Request, host: str, timeout, robots: bool = False):
        self.check_host(host)
        if self.report["requests"] >= self.budget:
            raise PoliteHalt("budget", host, f"the job's budget of {self.budget} requests is spent; the next data day resumes")
        if self.report["requests"] >= self.run_left:
            raise PoliteHalt("run_budget", host, "the run's request budget is spent; the next data day resumes")
        wait = self.hosts[host] - (time.time() - self.state["last_at"].get(host, 0.0))
        if wait > 0:
            time.sleep(wait)
        self.report["requests"] += 1
        h = self.report["hosts"].setdefault(host, {"requests": 0, "statuses": {}})
        h["requests"] += 1
        status = None
        _GUARD.inside = True
        try:
            resp = _REAL_URLOPEN(req, timeout=timeout)
            status = resp.status
        except urllib.error.HTTPError as e:
            status = e.code
            raise
        except (urllib.error.URLError, OSError, http.client.HTTPException) as e:
            reason = getattr(e, "reason", e)
            status = "timeout" if isinstance(e, TimeoutError) or isinstance(reason, (TimeoutError, socket.timeout)) else \
                f"connection error ({type(reason).__name__})"
            raise
        finally:
            _GUARD.inside = False
            self.state["last_at"][host] = time.time()
            h["statuses"][str(status)] = h["statuses"].get(str(status), 0) + 1
            self.after(host, status, req.full_url, robots)
            self.save_state()
        final = resp.geturl()
        if final and host_of(final) != host:
            self.report["redirects"].append({"from": redact(req.full_url)[:200], "to_host": host_of(final)})
        return resp

    def after(self, host: str, status, url: str, robots: bool) -> None:
        if status is None or (isinstance(status, int) and status < 400):
            return  # None: the request never left (a malformed URL, say), so there is no answer to record
        is_stop = not isinstance(status, int) or status in REFUSAL or status >= 500 or (self.any_4xx and not robots)
        if is_stop:
            self.report["stops"].append(record_stop(self.ledger, host, status, self.job, url, self.today()))
        else:
            self.report["client_errors"].append({"host": host, "status": status, "url": redact(url)[:200]})

    # -- cache
    def cache_key(self, req: urllib.request.Request) -> str:
        body = req.data if isinstance(req.data, bytes) else (str(req.data).encode() if req.data else b"")
        return hashlib.sha256(f"{req.get_method()} {req.full_url}\n".encode() + body).hexdigest()

    def cache_get(self, key: str):
        base = os.path.join(self.cache_dir, "polite", key[:2], key)
        if not os.path.exists(base + ".json"):
            return None
        with open(base + ".json") as f:
            meta = json.load(f)
        with open(base + ".body", "rb") as f:
            return canned(f.read(), meta)

    def cache_put(self, key: str, url: str, resp) -> object:
        body = resp.read()
        resp.close()
        meta = {"url": redact(url), "final_url": resp.geturl(), "status": resp.status, "fetched_utc": now_utc(),
                "headers": {k: v for k, v in resp.headers.items() if k.lower() in ("content-type", "content-encoding", "last-modified")}}
        base = os.path.join(self.cache_dir, "polite", key[:2], key)
        os.makedirs(os.path.dirname(base), exist_ok=True)
        with open(base + ".body", "wb") as f:
            f.write(body)
        with open(base + ".json", "w") as f:
            json.dump(meta, f, indent=1)
        return canned(body, meta)

    # -- urlopen's replacement
    def open(self, url, data=None, timeout=socket._GLOBAL_DEFAULT_TIMEOUT, *args, **kwargs):
        req = url if isinstance(url, urllib.request.Request) else urllib.request.Request(url)
        if data is not None:
            req.data = data
        host = host_of(req.full_url)
        ua = req.get_header("User-agent")
        if ua is None:
            req.add_header("User-Agent", UA)
        elif ua != UA:
            raise PoliteHalt("user_agent", host, "the request carries a different user agent; only the honest one is sent")
        self.check_host(host)
        key = self.cache_key(req) if self.use_cache and req.get_method() in ("GET", "POST") else None
        if key:
            hit = self.cache_get(key)
            if hit is not None:
                self.report["cache_hits"] += 1
                return hit
        self.check_robots(host, req.full_url)
        resp = self.send(req, host, timeout)
        if key and 200 <= resp.status < 300:
            return self.cache_put(key, req.full_url, resp)
        return resp

    def save_state(self) -> None:
        sp = self.cfg.get("state_path")
        if sp:
            with open(sp, "w") as f:
                json.dump(self.state, f)

    def write_report(self, exit_code) -> None:
        self.report["exit"] = exit_code
        self.report["finished_utc"] = now_utc()
        rp = self.cfg.get("report_path")
        if rp:
            with open(rp, "w") as f:
                json.dump(self.report, f, indent=1)


def canned(body: bytes, meta: dict):
    msg = http.client.HTTPMessage()
    for k, v in (meta.get("headers") or {}).items():
        msg[k] = v
    return urllib.response.addinfourl(io.BytesIO(body), msg, meta.get("final_url") or meta.get("url"), meta.get("status", 200))


def install(policy: Policy) -> None:
    """Route urllib through the policy, and end the job on any HTTP connection opened some other way."""
    urllib.request.urlopen = policy.open

    def connect(conn):
        if not getattr(_GUARD, "inside", False):
            raise PoliteHalt("bypass", str(getattr(conn, "host", "?")), "a connection that did not pass through the polite layer")
        return _REAL_CONNECT(conn)

    http.client.HTTPConnection.connect = connect


def uninstall() -> None:
    urllib.request.urlopen = _REAL_URLOPEN
    http.client.HTTPConnection.connect = _REAL_CONNECT


# --------------------------------------------------------------------------------------------- exec: run frozen code
def cmd_exec(argv: list[str]) -> int:
    """polite.py exec --config CFG.json -- SCRIPT [ARGS...]: run SCRIPT as __main__ with this layer installed."""
    if "--" not in argv or argv[:1] != ["--config"]:
        print("usage: polite.py exec --config CFG.json -- SCRIPT [ARGS...]", file=sys.stderr)
        return 2
    cut = argv.index("--")
    with open(argv[1]) as f:
        policy = Policy(json.load(f))
    script, args = os.path.abspath(argv[cut + 1]), argv[cut + 2:]
    install(policy)
    code = 0
    try:
        sys.argv = [script] + args
        sys.path.insert(0, os.path.dirname(script))
        runpy.run_path(script, run_name="__main__")
    except SystemExit as e:
        code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
        if not isinstance(e.code, (int, type(None))):
            print(e.code, file=sys.stderr)
    except PoliteHalt as e:
        policy.report["halt"] = {"kind": e.kind, "host": e.host, "detail": e.detail}
        print(f"POLITE HALT: {e}", flush=True)
        code = HALT_EXIT
    except Exception:  # noqa: BLE001  (the script failed; its traceback goes to the log)
        traceback.print_exc()
        code = 1
    finally:
        uninstall()
        policy.write_report(code)
    sys.stdout.flush()
    return code


# ------------------------------------------------------------------------------------------------------- self-test
class _Handler(http.server.BaseHTTPRequestHandler):
    hits: list = []

    def do_GET(self):  # noqa: N802
        _Handler.hits.append((self.path, self.headers.get("User-Agent")))
        routes = {"/robots.txt": (200, b"User-agent: *\nCrawl-delay: 2\nDisallow: /private\nDisallow: /api/\n"), "/ok": (200, b"ok"),
                  "/ok2": (200, b"ok2"), "/ok3": (200, b"ok3"), "/private/x": (200, b"secret"), "/api/q": (200, b"api"),
                  "/limit": (429, b"slow down"), "/gone": (404, b"no"), "/boom": (500, b"err")}
        code, body = routes.get(self.path.split("?")[0], (404, b"no"))
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def selftest() -> int:
    import tempfile
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    port = srv.server_address[1]
    A, B = f"http://127.0.0.1:{port}", f"http://localhost:{port}"
    tmp = tempfile.mkdtemp(prefix="polite-")
    led = os.path.join(tmp, "stops.json")
    fails = []

    def check(name, ok):
        print(("ok   " if ok else "FAIL ") + name, flush=True)
        if not ok:
            fails.append(name)

    def policy(**kw):
        cfg = {"job": "selftest", "hosts": {"127.0.0.1": {}}, "budget": 50, "ledger": led, "cache_dir": tmp,
               "use_cache": True, "state_path": os.path.join(tmp, "state.json"),
               "robots_exceptions": [{"host": "127.0.0.1", "path_prefix": "/api/", "policy_url": "https://example.invalid/api-terms"}]}
        cfg.update(kw)
        p = Policy(cfg)
        install(p)
        return p

    def halted(fn, kind):
        try:
            fn()
        except PoliteHalt as e:
            return e.kind == kind
        except Exception:  # noqa: BLE001
            return False
        return False

    try:
        p = policy()
        t0 = time.time()
        b1 = urllib.request.urlopen(A + "/ok").read()
        b2 = urllib.request.urlopen(A + "/ok2").read()
        check("requests to one host are spaced by the larger of 1 s and robots.txt's Crawl-delay (2 s here)",
              time.time() - t0 >= 4.0 and b1 == b"ok" and b2 == b"ok2" and p.hosts["127.0.0.1"] == 2.0)
        check("the honest user agent is sent when the script sets none", all(ua == UA for _, ua in _Handler.hits))
        n = len(_Handler.hits)
        check("a repeated URL comes from the cache, with no request", urllib.request.urlopen(A + "/ok").read() == b"ok" and len(_Handler.hits) == n and p.report["cache_hits"] == 1)
        check("robots.txt: a disallowed path is not requested", halted(lambda: urllib.request.urlopen(A + "/private/x"), "robots") and len(_Handler.hits) == n)
        check("robots.txt: a named API exception is allowed and reported", urllib.request.urlopen(A + "/api/q").read() == b"api" and p.report["robots"]["127.0.0.1"]["exceptions_used"] == 1)
        check("another user agent is refused before sending", halted(lambda: urllib.request.urlopen(urllib.request.Request(A + "/ok3", headers={"User-Agent": "Mozilla/5.0"})), "user_agent"))
        check("an undeclared host is refused", halted(lambda: urllib.request.urlopen(B + "/ok"), "undeclared_host"))
        check("a connection outside the layer ends the job", halted(lambda: http.client.HTTPConnection("127.0.0.1", port).request("GET", "/ok"), "bypass"))
        try:
            urllib.request.urlopen(A + "/gone")
        except urllib.error.HTTPError as e:
            check("a 404 reaches the script and is not a stop under the project rule", e.code == 404 and not load_ledger(led)["stops"])
        n = len(_Handler.hits)
        try:
            urllib.request.urlopen(A + "/limit")
        except urllib.error.HTTPError as e:
            check("a 429 reaches the script as itself and is written to the ledger", e.code == 429 and load_ledger(led)["stops"][-1]["status"] == 429)
        check("after a stop the host gets no request that UTC day", halted(lambda: urllib.request.urlopen(A + "/ok3"), "stopped") and len(_Handler.hits) == n + 1)
        uninstall()
        p2 = policy()
        check("a new run the same day is refused too (the ledger is on disk)", halted(lambda: urllib.request.urlopen(A + "/ok3"), "stopped"))
        uninstall()
        tomorrow = (utc_today() + dt.timedelta(days=1)).isoformat()
        p3 = policy(today=tomorrow, budget=2, use_cache=False)
        urllib.request.urlopen(A + "/ok3").read()
        check("the next UTC day the host is asked again", p3.report["requests"] == 2)
        check("the job's budget halts the next request (robots.txt counted)", halted(lambda: urllib.request.urlopen(A + "/ok2"), "budget"))
        uninstall()
        p4 = policy(today=tomorrow, stop_any_4xx=True, state_path=os.path.join(tmp, "state2.json"))
        p4.robots["127.0.0.1"] = p3.robots["127.0.0.1"]
        try:
            urllib.request.urlopen(A + "/gone")
        except urllib.error.HTTPError:
            pass
        check("under a plan's any-4xx rule a 404 is a stop", load_ledger(led)["stops"][-1]["status"] == 404)
        uninstall()
        d0 = utc_today()
        lg = {"stops": [{"host": "h", "date": (d0 + dt.timedelta(days=i)).isoformat(), "status": 429} for i in (0, 1, 2)], "clears": []}
        check("stops on three UTC days in a row park the host", host_state(lg, "h", d0 + dt.timedelta(days=5))[0] == "parked")
        lg["clears"].append({"host": "h", "date": (d0 + dt.timedelta(days=3)).isoformat(), "by": "owner"})
        check("a clear in the ledger lifts the park", host_state(lg, "h", d0 + dt.timedelta(days=5))[0] == "clear")
        lg2 = {"stops": [{"host": "h", "date": (d0 + dt.timedelta(days=i)).isoformat(), "status": 500} for i in (0, 2, 4)], "clears": []}
        check("stops on days that are not consecutive do not park", host_state(lg2, "h", d0 + dt.timedelta(days=6))[0] == "clear")
        check("key-like query values are redacted", "REDACTED" in redact("https://x.org/a?api_key=abc&q=1") and "abc" not in redact("https://x.org/a?api_key=abc&q=1"))
        cfg = os.path.join(tmp, "cfg.json")
        with open(cfg, "w") as f:
            json.dump({"job": "selftest", "hosts": {"127.0.0.1": {}}, "budget": 5, "ledger": led, "report_path": os.path.join(tmp, "rep.json")}, f)
        script = os.path.join(tmp, "frozen.py")
        with open(script, "w") as f:
            f.write("import sys, urllib.request\n"
                    "try:\n    urllib.request.urlopen(sys.argv[1])\nexcept Exception as e:\n    print('swallowed', e)\n"
                    "print('the script went on')\n")
        import subprocess
        out = subprocess.run([sys.executable, __file__, "exec", "--config", cfg, "--", script, A + "/ok"], capture_output=True, text=True)
        rep = json.load(open(os.path.join(tmp, "rep.json")))
        check("exec: a halt cannot be swallowed by the script's own except clause", out.returncode == HALT_EXIT and "went on" not in out.stdout and rep["halt"]["kind"] == "stopped")
    finally:
        uninstall()
        srv.shutdown()
    print(f"polite selftest: {'all passed' if not fails else str(len(fails)) + ' failed'}", flush=True)
    return 1 if fails else 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "exec":
        sys.exit(cmd_exec(sys.argv[2:]))
    if cmd == "selftest":
        sys.exit(selftest())
    print(__doc__)
    sys.exit(2)
