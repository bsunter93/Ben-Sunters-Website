"""The screen, automated: apply lab/discovery/screen_rubric.md to discovery candidates through a language-model API.

Not run in the pass that wrote it (docs/screen_v1.md): the repository's secrets hold no key for such an API, and no
workflow calls this script. It reproduces what a language model did by hand in screen_labels_v1.json, one candidate per
request, and derives the gate, the decision and the duplicate rule in code, so the model only answers the rubric's
fields and every derived value can be checked.

Configuration, all from the environment (nothing has a default that names a provider or a model):

    RIPPLE_SCREEN_MODEL      the model identifier to send (required; no default)
    RIPPLE_SCREEN_ENDPOINT   the HTTPS URL of a messages-style endpoint (required)
    RIPPLE_SCREEN_API_KEY    the key (required; never printed, logged or written)
    RIPPLE_SCREEN_KEY_HEADER the header that carries the key (default "Authorization", sent as "Bearer <key>";
                             any other header name is sent with the bare key)
    RIPPLE_SCREEN_HEADERS    optional JSON object of extra headers the endpoint requires (a version header, say)

Request shape: {"model", "max_tokens", "system", "messages": [{"role": "user", "content": ...}]}. The reply text is
read from either a "content" list of text blocks or a "choices[0].message.content" string, whichever the endpoint returns.

Rules carried from HANDOFF.md section 6: the honest user agent, at most one request a second, and a stop on any 4xx or
5xx with no retry. Usage, from ripples/docs/results:

    python3 ../../lab/discovery/screen.py screen_candidates_v1.json screen_labels_auto.json [--set E3_wider] [--limit 20]
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
RUBRIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "screen_rubric.md")
CODES = ["wrong_entity", "attention_only", "not_a_mark", "aside", "context", "bad_timing", "undated", "disputed",
         "weak_evidence", "duplicate"]
FLAGS = {"obvious", "confounded"}
LINKS = {"reason", "context", "aside"}
SCORES = ("interest", "surprise", "evidence", "novelty")

ASK = """Apply the rubric to this candidate. Judge from these fields only.

{fields}

Reply with one JSON object and nothing else, with exactly these keys:
"mark_stated" (string or null), "is_mark" (true/false), "link_label" ("reason", "context" or "aside"),
"date_ok" (true/false), "disputed" (true/false), "wrong_entity" (true/false), "weak_evidence" (true/false),
"not_mark_code" ("attention_only", "not_a_mark" or null; null when is_mark is true),
"date_code" ("bad_timing", "undated" or null; null when date_ok is true),
"flags" (a list drawn from "obvious" and "confounded"),
"scores" ({{"interest": 0-100, "surprise": 0-100, "evidence": 0-100, "novelty": 0-100}}),
"justification" (one line)."""


def env(name, required=True, default=None):
    v = os.environ.get(name, default)
    if required and not v:
        sys.exit(f"missing environment variable {name}")
    return v


def fields_text(c):
    keep = ("stone", "stone_year", "reading", "mark", "mark_year", "mark_dated_by", "section", "years_in_sentence", "source", "sentence")
    return "\n".join(f"{k}: {json.dumps(c.get(k), ensure_ascii=False)}" for k in keep)


def call(system, user, cfg, last):
    wait = 1.0 - (time.time() - last[0])
    if wait > 0:
        time.sleep(wait)
    body = json.dumps({"model": cfg["model"], "max_tokens": 600, "system": system,
                       "messages": [{"role": "user", "content": user}]}).encode()
    headers = {"Content-Type": "application/json", "User-Agent": UA}
    headers.update(cfg["extra"])
    if cfg["key_header"].lower() == "authorization":
        headers["Authorization"] = "Bearer " + cfg["key"]
    else:
        headers[cfg["key_header"]] = cfg["key"]
    req = urllib.request.Request(cfg["endpoint"], data=body, headers=headers, method="POST")
    last[0] = time.time()
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        # a 4xx or 5xx is a stop for the run, never a retry (the key is not in the message)
        sys.exit(f"stopped: HTTP {e.code} from the endpoint; no retry")
    except urllib.error.URLError as e:
        sys.exit(f"stopped: {e.reason}; no retry")
    if isinstance(data.get("content"), list):
        return "".join(b.get("text", "") for b in data["content"] if isinstance(b, dict))
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        sys.exit("stopped: the reply had no text in a recognized shape")


def parse(text):
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        raise ValueError("no JSON object in the reply")
    a = json.loads(m.group(0))
    if a.get("link_label") not in LINKS:
        raise ValueError("bad link_label")
    for k in ("is_mark", "date_ok", "disputed", "wrong_entity", "weak_evidence"):
        if not isinstance(a.get(k), bool):
            raise ValueError(f"bad {k}")
    s = a.get("scores") or {}
    if any(not isinstance(s.get(d), (int, float)) or not 0 <= s[d] <= 100 for d in SCORES):
        raise ValueError("bad scores")
    a["flags"] = [f for f in a.get("flags") or [] if f in FLAGS]
    return a


def derive(a):
    """The gate and the first reason code that applies, in the rubric's order (section 5)."""
    reasons = []
    if a["wrong_entity"]:
        reasons.append("wrong_entity")
    if not a["is_mark"]:
        reasons.append(a.get("not_mark_code") if a.get("not_mark_code") in ("attention_only", "not_a_mark") else "not_a_mark")
    if a["link_label"] == "aside":
        reasons.append("aside")
    if a["link_label"] == "context":
        reasons.append("context")
    if not a["date_ok"]:
        reasons.append(a.get("date_code") if a.get("date_code") in ("bad_timing", "undated") else "undated")
    if a["disputed"]:
        reasons.append("disputed")
    if a["weak_evidence"]:
        reasons.append("weak_evidence")
    reasons.sort(key=CODES.index)
    return (not reasons), (reasons[0] if reasons else None)


def norm_mark(t):
    return re.sub(r"[^a-z0-9 ]", "", (t or "").lower()).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("candidates")
    ap.add_argument("out")
    ap.add_argument("--set", default=None)
    ap.add_argument("--limit", type=int, default=None)
    args = ap.parse_args()
    cfg = {"model": env("RIPPLE_SCREEN_MODEL"), "endpoint": env("RIPPLE_SCREEN_ENDPOINT"), "key": env("RIPPLE_SCREEN_API_KEY"),
           "key_header": env("RIPPLE_SCREEN_KEY_HEADER", required=False, default="Authorization"),
           "extra": json.loads(env("RIPPLE_SCREEN_HEADERS", required=False, default="{}"))}
    if not cfg["endpoint"].startswith("https://"):
        sys.exit("the endpoint must be https")
    system = open(RUBRIC).read()
    cands = json.load(open(args.candidates))
    cands = cands["candidates"] if isinstance(cands, dict) else cands
    if args.set:
        cands = [c for c in cands if c.get("set") == args.set]
    if args.limit:
        cands = cands[: args.limit]
    out, accepted, last = [], {}, [0.0]
    for c in cands:
        text = call(system, ASK.format(fields=fields_text(c)), cfg, last)
        try:
            a = parse(text)
        except (ValueError, json.JSONDecodeError) as e:
            out.append({"id": c["id"], "set": c.get("set"), "error": f"unparsed reply: {e}"})
            continue
        gate, code = derive(a)
        decision = "accepted" if gate else "rejected"
        key = (c.get("set"), c.get("stone"), norm_mark(a.get("mark_stated")))
        if gate and key in accepted:
            decision, code = "rejected", "duplicate"
        elif gate:
            accepted[key] = c["id"]
        out.append({"id": c["id"], "set": c.get("set"), "mark_stated": a.get("mark_stated"), "is_mark": a["is_mark"],
                    "link_label": a["link_label"], "date_ok": a["date_ok"], "disputed": a["disputed"],
                    "gate": "pass" if gate else "fail", "decision": decision, "reason_code": code, "flags": a["flags"],
                    "scores": {d: int(a["scores"][d]) for d in SCORES}, "justification": a.get("justification", "")})
        json.dump({"_about": "Screen labels from lab/discovery/screen.py: screened by a language model, not by a person.",
                   "rubric": "lab/discovery/screen_rubric.md", "labels": out}, open(args.out, "w"), ensure_ascii=False, indent=1)
    print(f"{len(out)} labeled, {sum(1 for o in out if o.get('decision') == 'accepted')} accepted, "
          f"{sum(1 for o in out if 'error' in o)} unparsed -> {args.out}")


if __name__ == "__main__":
    main()
