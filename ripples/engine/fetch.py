"""The engine's polite fetcher (from the studies pilot and the discovery v4 pilot).

  - An honest user agent on every request.
  - At most one request a second per host; OpenAlex one per 2 seconds; NCBI three a second.
  - Redirects are followed one hop at a time, and every hop is checked against the forbidden hosts and the day's stops.
  - A 5xx, a 429, a timeout or a connection error gets one retry after a wait (Retry-After when it is 300 s or less,
    otherwise 60 s). A second failure, or any other 4xx, stops that host for the rest of the UTC day
    (logs/blocked_hosts.log). Never more than one retry, never another agent.
  - No Wikipedia, Wikimedia, Wikidata, Reddit, Merriam-Webster or Etymonline requests.
  - Responses with status 200 are cached under raw/, keyed by the request URL, so a stopped run resumes.

Keys: no email address and no key is sent anywhere, with one exception. When OPENALEX_API_KEY is set in the
environment, it is added as the api_key parameter to requests whose host is exactly api.openalex.org, at the moment of
sending. It never appears in a logged URL, a cache key, a cached file or an error line, and it is stripped from any
redirect target before that target is requested.

Call configure(work_dir) before the first request.
"""
import datetime
import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "ripple-research (bensunter.com)"
FORBIDDEN = ["reddit.com", "wikipedia.org", "wikimedia.org", "wikidata.org", "merriam-webster.com", "etymonline.com"]
OPENALEX_HOST = "api.openalex.org"
KEY_ENV = "OPENALEX_API_KEY"

LOG = BLOCK = RAW = None
_last = {}
last_headers = {}


def configure(work):
    global LOG, BLOCK, RAW
    LOG = os.path.join(work, "logs", "requests.log")
    BLOCK = os.path.join(work, "logs", "blocked_hosts.log")
    RAW = os.path.join(work, "raw")
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    os.makedirs(RAW, exist_ok=True)


def _need():
    if LOG is None:
        raise RuntimeError("fetch.configure(work_dir) was not called")


def _utc():
    return datetime.datetime.now(datetime.timezone.utc)


def _stamp():
    return _utc().strftime("%m/%d/%Y %H:%M:%S UTC")


def _key():
    return os.environ.get(KEY_ENV, "").strip()


def key_present():
    return bool(_key())


def _strip_key(url):
    """Remove any api_key parameter from a URL (used on redirect targets and before logging)."""
    p = urllib.parse.urlsplit(url)
    if "api_key" not in p.query:
        return url
    q = [(k, v) for k, v in urllib.parse.parse_qsl(p.query, keep_blank_values=True) if k != "api_key"]
    return urllib.parse.urlunsplit((p.scheme, p.netloc, p.path, urllib.parse.urlencode(q), p.fragment))


def redact(text):
    """Remove the key's value and any api_key=... from text that is about to be written or printed."""
    if not text:
        return text
    k = _key()
    if k:
        text = text.replace(k, "REDACTED")
    return re.sub(r"(api_key=)[^&\s'\"]+", r"\1REDACTED", text)


def _with_key(url):
    """Add the OpenAlex key at send time, only for the OpenAlex API host."""
    k = _key()
    host = (urllib.parse.urlsplit(url).hostname or "").lower()
    if not k or host != OPENALEX_HOST:
        return url
    sep = "&" if urllib.parse.urlsplit(url).query else "?"
    return url + sep + urllib.parse.urlencode({"api_key": k})


def blocked_hosts():
    """Hosts stopped for the current UTC day."""
    _need()
    today = _utc().strftime("%m/%d/%Y")
    s = set()
    if os.path.exists(BLOCK):
        for line in open(BLOCK):
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and parts[0].startswith(today):
                s.add(parts[1])
    return s


def _interval(host):
    if host == OPENALEX_HOST:
        return 2.05
    if host.endswith("ncbi.nlm.nih.gov"):
        return 0.36
    return 1.05


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_opener = urllib.request.build_opener(_NoRedirect)


RETRY_DEFAULT = 60      # seconds to wait before the one retry
RETRY_MAX_WAIT = 300    # a longer Retry-After is not honored; the default wait is used instead


def _retryable(status):
    """A 5xx, a 429, a timeout or a connection error (status 0) earns one retry. Other 4xx stop at once."""
    return status == 0 or status == 429 or status >= 500


def _attempt(url, accept, host):
    """One request, no redirect following. Returns (status, body, location, retry_after_seconds or None)."""
    wait = _interval(host) - (time.time() - _last.get(host, 0))
    if wait > 0:
        time.sleep(wait)
    headers = {"User-Agent": UA}
    if accept:
        headers["Accept"] = accept
    req = urllib.request.Request(_with_key(url), headers=headers)
    status, body, loc, retry_after = 0, b"", None, None
    try:
        with _opener.open(req, timeout=45) as r:
            status = r.status
            last_headers[host] = {k: v for k, v in r.headers.items() if k.lower().startswith("x-ratelimit")}
            body = r.read(4_000_000)
    except urllib.error.HTTPError as e:
        status = e.code
        last_headers[host] = {k: v for k, v in e.headers.items() if k.lower().startswith("x-ratelimit")}
        loc = e.headers.get("Location") if 300 <= e.code < 400 else None
        if loc:
            loc = _strip_key(urllib.parse.urljoin(url, loc))
        ra = (e.headers.get("Retry-After") or "").strip()
        retry_after = int(ra) if ra.isdigit() else None
        try:
            body = e.read(20000)
        except Exception:
            body = b""
    except Exception as e:
        status = 0
        body = redact(str(e)).encode()
    _last[host] = time.time()
    with open(LOG, "a") as f:
        f.write(redact(f"{_stamp()}\t{status}\t{url}\t{loc or ''}") + "\n")
    return status, body, loc, retry_after


def _one(url, accept):
    """One hop, no redirect following, at most one retry. Returns (status, body, location)."""
    host = (urllib.parse.urlsplit(url).hostname or "").lower()
    if any(host == f or host.endswith("." + f) for f in FORBIDDEN):
        raise RuntimeError("forbidden host " + host)
    if host in blocked_hosts():
        return -1, b"", None
    status, body, loc, retry_after = _attempt(url, accept, host)
    if status >= 400 or status == 0:
        if _retryable(status):
            pause = retry_after if retry_after is not None and retry_after <= RETRY_MAX_WAIT else RETRY_DEFAULT
            with open(LOG, "a") as f:
                f.write(redact(f"{_stamp()}\tretry in {pause} s after {status}\t{url}\t") + "\n")
            time.sleep(pause)
            status, body, loc, retry_after = _attempt(url, accept, host)
        if status >= 400 or status == 0:
            with open(BLOCK, "a") as f:
                f.write(redact(f"{_stamp()}\t{host}\t{status}\t{url}\t{body[:300].decode('utf-8', 'replace')!r}") + "\n")
    return status, body, loc


def get(url, accept=None, cache=True):
    """GET with the rules above. Returns (status, text, final_url). url must not carry a key."""
    _need()
    url = _strip_key(url)
    key = hashlib.sha1(url.encode()).hexdigest()
    path = os.path.join(RAW, key)
    if cache and os.path.exists(path) and os.path.exists(path + ".meta"):
        meta = json.load(open(path + ".meta"))
        return meta["status"], open(path, "rb").read().decode("utf-8", "replace"), meta.get("final_url", url)
    cur = url
    status, body = 0, b""
    for _ in range(8):
        status, body, loc = _one(cur, accept)
        if status in (301, 302, 303, 307, 308) and loc:
            cur = loc
            continue
        break
    text = body.decode("utf-8", "replace")
    if status == 200:
        k = _key()
        if k and k in text:
            text = text.replace(k, "REDACTED")
        open(path, "wb").write(text.encode("utf-8"))
        json.dump({"url": url, "status": status, "final_url": cur, "time": _stamp()}, open(path + ".meta", "w"))
    return status, text, cur
