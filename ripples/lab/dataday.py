"""Data day: registered tests that stopped on a refusal run again on a later day, within the rules
(ripples/docs/dataday_v1.md). The job registry is ripples/lab/dataday_jobs.json; the network rules live in polite.py.

  python3 ripples/lab/dataday.py run [--job ID] [--dry-run]   decide every job and run the due ones once, in registry order
  python3 ripples/lab/dataday.py status                        one line per job, from the last run
  python3 ripples/lab/dataday.py merge-ledger THEIRS OURS      union of two stop ledgers, written to OURS (the workflow)
  python3 ripples/lab/dataday.py selftest                      an end-to-end run against a local server on 127.0.0.1

A job runs only when all of these hold: its done marker is absent (a job finishes once and never runs again); its gate,
if it has one, is cleared; no hold from an earlier attempt applies to its current revision; none of its hosts is parked
or stopped today, by the ledger or by a stop-marker file the job names; and it has not been attempted today (UTC). Its
code comes from the registered commit by `git archive`, is checked against the registered sha256, and runs unchanged
under polite.py. A dry run decides and reports, and sends nothing.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import polite  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
REGISTRY = os.path.join(HERE, "dataday_jobs.json")
TAIL = 30          # lines of each job's log printed to the console (the job-log API keeps only the last 5,000)
LOG_KEEP = 400     # lines of each job's log committed
URL_RX = re.compile(r"https?://[^\s'\"<>)]+")
SECRET_ENV = re.compile(r"TOKEN|SECRET|PASSW|KEY|CREDENTIAL", re.I)


def git(*args, repo=None, check=True, data=None):
    return subprocess.run(["git", *args], cwd=repo or REPO, check=check, capture_output=True, input=data)


def load_json(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def dump_json(obj, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
        f.write("\n")


def fill(s, ctx):
    for k, v in ctx.items():
        s = s.replace("{" + k + "}", v)
    return s


def pick(obj, dotted):
    for part in dotted.split("."):
        if not isinstance(obj, dict) or part not in obj:
            return False, None
        obj = obj[part]
    return True, obj


def scrub(line):
    return URL_RX.sub(lambda m: polite.redact(m.group(0)), line)


def dir_kb(path):
    return sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(path) for f in fs) / 1024 if os.path.isdir(path) else 0.0


# ------------------------------------------------------------------------------------------------ decisions
def marker_dates(m, repo):
    """Dates listed in a stop-marker file at the tip of a job's branch. The registry names the branch by its last part
    (eng-surprise); `git ls-remote` finds the full ref, which is fetched read-only into refs/dataday/."""
    r = git("ls-remote", "--heads", "origin", m["branch"], repo=repo, check=False)
    refs = [ln.split("\t")[1] for ln in r.stdout.decode().splitlines() if "\t" in ln]
    ref = next((x for x in refs if x == "refs/heads/" + m["branch"]), refs[0] if refs else None)
    if not ref:
        return None
    local = "refs/dataday/" + m["branch"]
    git("fetch", "-q", "--depth=1", "--no-tags", "origin", f"+{ref}:{local}", repo=repo, check=False)
    r = git("show", f"{local}:{m['path']}", repo=repo, check=False)
    if r.returncode != 0:
        return None
    return {ln.strip() for ln in r.stdout.decode("utf-8", "replace").splitlines() if ln.strip() and not ln.startswith("#")}


def host_notes(job, led, today, park_days, repo, marker_cache):
    """(worst state, notes) over the job's hosts: parked beats stopped beats clear."""
    worst, notes = "clear", []
    for host in job["hosts"]:
        state, why = polite.host_state(led, host, today, park_days)
        if state != "clear":
            notes.append(why)
            worst = "parked" if "parked" in (worst, state) else "stopped"
    for m in job.get("stop_markers") or []:
        key = (m["branch"], m["path"])
        if key not in marker_cache:
            marker_cache[key] = marker_dates(m, repo)
        dates = marker_cache[key]
        if dates is None:
            notes.append(f"stop-marker file {m['path']} on {m['branch']} not found (the ledger still applies)")
        elif today.isoformat() in dates:
            notes.append(f"{m['path']} on {m['branch']} lists {polite.us_date(today)}: no request to {m['host']} today")
            worst = "parked" if worst == "parked" else "stopped"
    return worst, notes


def decide(job, st, led, today, reg, repo, marker_cache):
    park_days = int(reg.get("park_after_days", polite.PARK_DAYS))
    worst, notes = host_notes(job, led, today, park_days, repo, marker_cache)
    tail = ("; " + "; ".join(notes)) if notes else ""
    if os.path.exists(os.path.join(repo, job["done_marker"])):
        return "done", f"finished; done marker {job['done_marker']}"
    gate = job.get("gate")
    if gate and not gate.get("cleared"):
        return "held", "needs " + gate["needs"] + tail
    hold = st.get("hold")
    if hold and hold.get("revision") == job["revision"]:
        return "held", hold["reason"] + f" (held until the registry entry's revision passes {job['revision']})" + tail
    if not job.get("code"):
        return "held", "no registered code" + tail
    if worst == "parked":
        return "parked", "; ".join(notes)
    if worst == "stopped":
        return "waiting", "; ".join(notes)
    if st.get("last_attempt_date") == today.isoformat():
        return "waiting", "already attempted today (UTC); one attempt per job per data day"
    return "ready", ""


# ------------------------------------------------------------------------------------------------ one job
def materialize(job, tree, repo):
    sha, path = job["code"]["commit"], job["code"]["path"]
    if git("cat-file", "-e", sha + "^{commit}", repo=repo, check=False).returncode != 0:
        git("fetch", "-q", "--depth=1", "--no-tags", "origin", sha, repo=repo, check=False)
    if git("cat-file", "-e", sha + "^{commit}", repo=repo, check=False).returncode != 0:
        return f"the registered commit {sha[:10]} is not reachable"
    arc = git("archive", "--format=tar", sha, *job["tree"], repo=repo, check=False)
    if arc.returncode != 0:
        return f"git archive failed at {sha[:10]}: {arc.stderr.decode()[:200]}"
    os.makedirs(tree, exist_ok=True)
    subprocess.run(["tar", "-x", "-C", tree], input=arc.stdout, check=True)
    with open(os.path.join(tree, path), "rb") as f:
        got = hashlib.sha256(f.read()).hexdigest()
    if got != job["code"]["sha256"]:
        return f"{path} at {sha[:10]} does not match the registered sha256 (got {got[:12]})"
    return None


def done_ok(job, ctx, exit_code):
    dw = job["done_when"]
    if exit_code not in dw.get("exit", [0]):
        return False
    f = fill(dw["file"], ctx)
    if not os.path.exists(f):
        return False
    if dw.get("json_has"):
        return pick(load_json(f), dw["json_has"])[0]
    return True


def run_job(job, reg, st, today, repo, results, cache_root, run_left, state_path, today_override):
    jid = job["id"]
    work = tempfile.mkdtemp(prefix=f"dataday-{jid}-")
    tree, out = os.path.join(work, "tree"), os.path.join(work, "out")
    cache = os.path.join(cache_root, jid)
    jdir = os.path.join(results, jid)
    mirror = os.path.join(jdir, "cache")
    os.makedirs(out, exist_ok=True)
    if not os.path.isdir(cache) and os.path.isdir(mirror):
        shutil.copytree(mirror, cache)
    os.makedirs(cache, exist_ok=True)
    ctx = {"tree": tree, "out": out, "cache": cache}
    o = {"date": today.isoformat(), "started_utc": polite.now_utc(), "revision": job["revision"],
         "code_commit": job["code"]["commit"]}
    err = materialize(job, tree, repo)
    if err:
        o.update(result="held", why=err, hold=True)
        return o, []
    report_path = os.path.join(work, "report.json")
    cfg = {"job": jid, "hosts": job["hosts"], "budget": min(int(job["budget"]), run_left),
           "run_budget_left": run_left, "ledger": os.path.join(repo, reg["ledger"]), "cache_dir": cache,
           "use_cache": bool(job.get("polite_cache")), "stop_any_4xx": job.get("stop_rule") == "any_4xx",
           "robots_exceptions": reg.get("robots_exceptions") or [], "state_path": state_path, "report_path": report_path,
           "park_days": int(reg.get("park_after_days", polite.PARK_DAYS))}
    if today_override:
        cfg["today"] = today_override
    cfg_path = os.path.join(work, "polite.json")
    dump_json(cfg, cfg_path)
    env = {k: v for k, v in os.environ.items() if not SECRET_ENV.search(k)}
    env.update({k: fill(v, ctx) for k, v in (job.get("env") or {}).items()})
    env.update(PYTHONUNBUFFERED="1", PYTHONDONTWRITEBYTECODE="1")
    cmd = [sys.executable, os.path.join(HERE, "polite.py"), "exec", "--config", cfg_path, "--",
           os.path.join(tree, job["code"]["path"]), *[fill(a, ctx) for a in job.get("args", [])]]
    log_path = os.path.join(work, "job.log")
    timed_out = False
    with open(log_path, "w") as logf:
        try:
            p = subprocess.run(cmd, cwd=tree, env=env, stdout=logf, stderr=subprocess.STDOUT,
                               timeout=float(job.get("timeout_min", 60)) * 60)
            code = p.returncode
        except subprocess.TimeoutExpired:
            timed_out, code = True, None
    rep = load_json(report_path, {}) or {}
    with open(log_path, encoding="utf-8", errors="replace") as f:
        lines = [scrub(ln.rstrip("\n")) for ln in f]
    o.update(exit=code, requests=rep.get("requests", 0), cache_hits=rep.get("cache_hits", 0), hosts=rep.get("hosts", {}),
             robots=rep.get("robots", {}), stops=rep.get("stops", []), client_errors=rep.get("client_errors", [])[:20],
             halt=rep.get("halt"), finished_utc=polite.now_utc())
    # a stop the script decided on its own (an access-request page, an API error inside a 200): into the ledger too
    if not o["stops"] and job.get("script_stop"):
        rx = re.compile(job["script_stop"])
        hit = next((ln for ln in lines if rx.search(ln)), None)
        if hit:
            hosts = [polite.host_of(u) for u in URL_RX.findall(hit)]
            host = next((h for h in hosts if h in job["hosts"]), next(iter(job["hosts"])))
            o["stops"] = [polite.record_stop(os.path.join(repo, reg["ledger"]), host, "script stop", jid, "",
                                             polite.utc_today(today_override))]
            o["script_stop_line"] = hit[:240]
    halt = o["halt"] or {}
    nxt = polite.us_date(today + dt.timedelta(days=1))
    if done_ok(job, ctx, code):
        o.update(result="done", why="the done condition holds")
        os.makedirs(jdir, exist_ok=True)
        copied = []
        for spec in job["outputs"]:
            data = load_json(fill(spec["from"], ctx)) if spec.get("pick") else None
            dest = os.path.join(jdir, spec["to"])
            if spec.get("pick"):
                dump_json({"picked": spec["pick"], "from": spec["from"].replace("{tree}/", ""), "value": pick(data, spec["pick"])[1]}, dest)
            else:
                shutil.copyfile(fill(spec["from"], ctx), dest)
            copied.append(os.path.relpath(dest, repo))
        dump_json({"job": jid, "title": job["title"], "finished_utc": o["finished_utc"], "revision": job["revision"],
                   "plan": job["plan"], "code": job["code"], "args": job.get("args", []), "outputs": copied,
                   "requests_this_run": o["requests"], "cache_hits_this_run": o["cache_hits"],
                   "attempts": len(st.get("attempts", [])) + 1}, os.path.join(repo, job["done_marker"]))
        o["outputs"] = copied
    elif o["stops"]:
        s = o["stops"][0]
        o.update(result="stopped", why=f"{s['host']} answered {s['status']}; no request to it before {nxt} (UTC)")
        if isinstance(s["status"], int) and 400 <= s["status"] < 500 and s["status"] not in polite.REFUSAL:
            o["hold"] = True
            o["why"] += "; a 4xx under the plan's own rule repeats on the same request, so the job waits for a registry revision"
    elif halt.get("kind") in ("budget", "run_budget"):
        o.update(result="paused", why=halt["detail"])
    elif timed_out:
        o.update(result="paused", why=f"the job's time limit ({job.get('timeout_min', 60)} min) ended this attempt; the next data day resumes")
    elif halt:
        o.update(result="held", why=f"polite layer: {halt['kind']}: {halt['detail']}", hold=True)
    else:
        o.update(result="failed", hold=True,
                 why=f"exit {code} without a stop and without the done condition; see the log (frozen code repeats a failure)")
    # the cache: committed when small (and when the job allows it), otherwise kept only in the Actions cache; a finished
    # job never runs again, so its cache is deleted
    kb = dir_kb(cache)
    if o["result"] == "done":
        shutil.rmtree(cache, ignore_errors=True)
        shutil.rmtree(mirror, ignore_errors=True)
    elif job.get("commit_cache", True) and 0 < kb <= float(reg.get("commit_cache_max_kb", 256)):
        shutil.rmtree(mirror, ignore_errors=True)
        shutil.copytree(cache, mirror)
    elif os.path.isdir(mirror):
        shutil.rmtree(mirror)
    o["cache_kb"] = round(kb, 1)
    shutil.rmtree(work, ignore_errors=True)
    return o, lines


# ------------------------------------------------------------------------------------------------ the run
def cmd_run(a):
    repo = os.path.abspath(a.repo)
    reg = load_json(a.registry)
    today = polite.utc_today(a.today)
    results = os.path.join(repo, reg["results_dir"])
    status_path = os.path.join(results, "status.json")
    status = load_json(status_path, {"jobs": {}})
    led_path = os.path.join(repo, reg["ledger"])
    cache_root = os.path.expanduser(os.environ.get("DATADAY_CACHE", "~/.cache/ripples-dataday"))
    state_path = os.path.join(tempfile.mkdtemp(prefix="dataday-run-"), "state.json")
    run_left = int(reg.get("run_budget", 2000))
    mode = "dry run" if a.dry_run else "run"
    print(f"data day {polite.us_date(today)} (UTC), {mode}, {len(reg['jobs'])} registered jobs, run budget {run_left}", flush=True)
    rows, marker_cache = [], {}
    for job in reg["jobs"]:
        if a.job and job["id"] != a.job:
            continue
        st = status["jobs"].setdefault(job["id"], {"attempts": []})
        state, why = decide(job, st, polite.load_ledger(led_path), today, reg, repo, marker_cache)
        if state != "ready" or a.dry_run:
            rows.append((job["id"], state if state != "ready" else "due", why))
            if not a.dry_run:
                st.update(state=state, why=why)
            print(f"- {job['id']}: {rows[-1][1]}: {why}", flush=True)
            continue
        if run_left <= 0:
            rows.append((job["id"], "waiting", "the run's request budget is spent; the next data day"))
            st.update(state="waiting", why=rows[-1][2])
            print(f"- {job['id']}: waiting: {rows[-1][2]}", flush=True)
            continue
        print(f"- {job['id']}: running {job['code']['path']} at {job['code']['commit'][:10]} (budget {min(int(job['budget']), run_left)})", flush=True)
        o, lines = run_job(job, reg, st, today, repo, results, cache_root, run_left, state_path, a.today)
        run_left -= o.get("requests", 0)
        if lines:
            log = os.path.join(results, job["id"], "logs", f"{today.isoformat()}.log")
            os.makedirs(os.path.dirname(log), exist_ok=True)
            with open(log, "a", encoding="utf-8") as f:
                f.write(f"## attempt {o['started_utc']} to {o.get('finished_utc')}, exit {o.get('exit')}\n")
                f.write("\n".join(lines[-LOG_KEEP:]) + "\n")
            print("  " + "\n  ".join(lines[-TAIL:]), flush=True)
        hold = o.pop("hold", False)
        if hold:
            st["hold"] = {"revision": job["revision"], "reason": o["why"], "since": today.isoformat()}
        st["attempts"] = (st.get("attempts", []) + [o])[-30:]
        st.update(state=o["result"], why=o["why"], last_attempt_date=today.isoformat())
        rows.append((job["id"], o["result"], o["why"] + f" ({o.get('requests', 0)} requests, {o.get('cache_hits', 0)} from cache)"))
        print(f"  -> {o['result']}: {rows[-1][2]}", flush=True)
        time.sleep(polite.MIN_INTERVAL)
    status["last_run"] = {"utc": polite.now_utc(), "date": today.isoformat(), "mode": mode,
                          "event": os.environ.get("GITHUB_EVENT_NAME", "local"),
                          "decisions": [{"job": j, "state": s, "why": w} for j, s, w in rows]}
    status["updated_utc"] = polite.now_utc()
    dump_json(status, status_path)
    summary = ["| job | state | why |", "|---|---|---|"] + [f"| {j} | {s} | {w.replace('|', '/')} |" for j, s, w in rows]
    print("\n".join(summary), flush=True)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(f"### Data day {polite.us_date(today)} ({mode})\n\n" + "\n".join(summary) + "\n")
    return 0


def cmd_status(a):
    reg = load_json(a.registry)
    status = load_json(os.path.join(os.path.abspath(a.repo), reg["results_dir"], "status.json"), {"jobs": {}})
    for job in reg["jobs"]:
        st = status["jobs"].get(job["id"], {})
        print(f"{job['id']:24s} {st.get('state', 'never run'):8s} {st.get('why', '')}")
    return 0


def cmd_merge_ledger(theirs, ours):
    a, b = polite.load_ledger(theirs), polite.load_ledger(ours)
    for k in ("stops", "clears"):
        seen = {json.dumps(x, sort_keys=True) for x in b[k]}
        b[k] += [x for x in a[k] if json.dumps(x, sort_keys=True) not in seen]
    polite.save_ledger(b, ours)
    return 0


# ------------------------------------------------------------------------------------------------ self-test
def selftest():
    import http.server
    import threading
    routes = {"/robots.txt": (200, b"User-agent: *\nDisallow: /private\n"), "/a": (200, b'{"n": 1}'),
              "/b": (429, b"slow down"), "/c": (200, b'{"n": 3}')}

    class H(http.server.BaseHTTPRequestHandler):
        hits: list = []

        def do_GET(self):  # noqa: N802
            H.hits.append(self.path)
            code, body = routes.get(self.path, (404, b"no"))
            self.send_response(code)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *x):
            pass

    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_address[1]}"
    tmp = tempfile.mkdtemp(prefix="dataday-selftest-")
    repo = os.path.join(tmp, "repo")
    os.makedirs(os.path.join(repo, "ripples", "lab"))
    with open(os.path.join(repo, "ripples", "lab", "frozen.py"), "w") as f:
        f.write("import json, sys, urllib.request\n"
                "out = {}\n"
                "for p in ('/a', '/b', '/c'):\n"
                "    with urllib.request.urlopen(sys.argv[1] + p, timeout=10) as r:\n"
                "        out[p] = json.load(r)['n']\n"
                "json.dump(out, open(sys.argv[2], 'w'))\n")
    for c in (["init", "-q"], ["add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "frozen"]):
        git(*c, repo=repo)
    sha = git("rev-parse", "HEAD", repo=repo).stdout.decode().strip()
    with open(os.path.join(repo, "ripples", "lab", "frozen.py"), "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    os.makedirs(os.path.join(repo, "res"))
    job = {"id": "t1", "revision": 1, "title": "test", "plan": {}, "code": {"path": "ripples/lab/frozen.py", "commit": sha, "sha256": digest},
           "tree": ["ripples/lab/frozen.py"], "args": [base, "{out}/r.json"], "hosts": {"127.0.0.1": {}}, "budget": 20,
           "timeout_min": 2, "stop_rule": "project", "polite_cache": True, "commit_cache": True,
           "done_when": {"exit": [0], "file": "{out}/r.json", "json_has": "/c"}, "outputs": [{"from": "{out}/r.json", "to": "r.json"}],
           "done_marker": "res/t1/DONE.json"}
    held = dict(job, id="t2", gate={"cleared": False, "needs": "an addendum"}, done_marker="res/t2/DONE.json")
    reg = {"ledger": "res/stops.json", "results_dir": "res", "run_budget": 50, "park_after_days": 3, "commit_cache_max_kb": 64,
           "robots_exceptions": [], "jobs": [job, held]}
    regp = os.path.join(tmp, "jobs.json")
    dump_json(reg, regp)
    os.environ["DATADAY_CACHE"] = os.path.join(tmp, "cache")
    os.environ.pop("GITHUB_STEP_SUMMARY", None)  # the test's own runs stay out of the workflow's summary
    d0 = polite.utc_today()
    fails = []

    def run(day, dry=False):
        ns = argparse.Namespace(repo=repo, registry=regp, today=day.isoformat(), job=None, dry_run=dry)
        cmd_run(ns)
        return load_json(os.path.join(repo, "res", "status.json"))["jobs"]

    def check(name, ok):
        print(("ok   " if ok else "FAIL ") + name, flush=True)
        if not ok:
            fails.append(name)

    try:
        s = run(d0)
        check("day 1: the job stops on a 429 and the ledger records it", s["t1"]["state"] == "stopped"
              and polite.load_ledger(os.path.join(repo, "res", "stops.json"))["stops"][0]["status"] == 429)
        check("day 1: a gated job is held", s["t2"]["state"] == "held")
        n = len(H.hits)
        s = run(d0)
        check("day 1 again: the job waits and the host gets nothing", s["t1"]["state"] == "waiting" and len(H.hits) == n)
        routes["/b"] = (200, b'{"n": 2}')
        s = run(d0 + dt.timedelta(days=1))
        last = s["t1"]["attempts"][-1]
        check("day 2: the job resumes, /a comes from the cache, and it finishes", s["t1"]["state"] == "done" and last["cache_hits"] == 1
              and H.hits.count("/a") == 1 and os.path.exists(os.path.join(repo, "res", "t1", "DONE.json")))
        check("day 2: the outputs are copied", load_json(os.path.join(repo, "res", "t1", "r.json")) == {"/a": 1, "/b": 2, "/c": 3})
        n = len(H.hits)
        s = run(d0 + dt.timedelta(days=2))
        check("day 3: a finished job never runs again", s["t1"]["state"] == "done" and len(H.hits) == n)
        led = os.path.join(repo, "res", "stops.json")
        L = polite.load_ledger(led)
        L["stops"] += [{"host": "127.0.0.1", "date": (d0 + dt.timedelta(days=i)).isoformat(), "status": 503, "job": "x"} for i in (3, 4, 5)]
        polite.save_ledger(L, led)
        os.remove(os.path.join(repo, "res", "t1", "DONE.json"))
        s = run(d0 + dt.timedelta(days=6))
        check("three stop days in a row park the host and its jobs", s["t1"]["state"] == "parked" and len(H.hits) == n)
        other = os.path.join(tmp, "other.json")
        polite.save_ledger({"stops": [{"host": "z", "date": "2026-01-01", "status": 429, "job": "y"}], "clears": []}, other)
        cmd_merge_ledger(other, led)
        check("merge-ledger keeps both sides", any(x["host"] == "z" for x in polite.load_ledger(led)["stops"])
              and len(polite.load_ledger(led)["stops"]) == len(L["stops"]) + 1)
    finally:
        srv.shutdown()
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"dataday selftest: {'all passed' if not fails else str(len(fails)) + ' failed'}", flush=True)
    return 1 if fails else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "status", "merge-ledger", "selftest"])
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--job")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--registry", default=REGISTRY)
    ap.add_argument("--repo", default=REPO)
    ap.add_argument("--today", help=argparse.SUPPRESS)  # tests only: decide as if this were the UTC date
    a = ap.parse_args()
    if a.cmd == "run":
        return cmd_run(a)
    if a.cmd == "status":
        return cmd_status(a)
    if a.cmd == "merge-ledger":
        return cmd_merge_ledger(*a.paths)
    return selftest()


if __name__ == "__main__":
    sys.exit(main())
