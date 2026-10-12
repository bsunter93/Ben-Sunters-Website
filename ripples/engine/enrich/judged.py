"""Inputs and checks for the two enrich judged steps: the authors' reason (why) and the effect numbers (fx).

    python3 ripples/engine/enrich/judged.py inputs --chains ripples/chains/batch19.json [--slugs a,b] [--size 6]
    python3 ripples/engine/enrich/judged.py inputs --candidates [--size 10]    # a run's defensible candidates (why only)
    python3 ripples/engine/runner.py why enrich/why_in/<batch>.json     # one fresh context per batch
    python3 ripples/engine/runner.py fx  enrich/fx_in/<batch>.json
    python3 ripples/engine/enrich/judged.py assemble

inputs reads the texts enrich/fulltext.py saved. assemble checks every output and writes enrich/enrich.json:
  why  the quote is in the abstract word for word (whitespace collapsed); at most 22 words; no em dash; kind is
       tested, suggested or none, and none has no sentence.
  fx   the quote is in the text the step read (whitespace collapsed, or with a line-end hyphen rejoined); every number
       on a bar appears in the quote as written (only the sign may change); labels at most 5 words; no em dash.
A row that fails is kept out and printed, so a person can read it. Nothing is ever repaired by the script.
"""
import argparse
import glob
import json
import os
import re
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402

col = lambda x: re.sub(r"\s+", " ", x or "").strip()
NUM = lambda q: {float(x.replace(",", "")) for x in re.findall(r"\d[\d,]*\.?\d*", q)}
KINDS = {"pct", "levels", "groups", "none"}


def one_study(c):
    st = [x for x in c["steps"] if (x.get("test") or {}).get("type") == "study"]
    return st[0] if len(st) == 1 else None


def cmd_inputs_candidates(a, work):
    """Why lines for a run's rated candidates (gate passers and audited rejects), from the abstract extraction read."""
    key = json.load(open(os.path.join(work, "data", "rate_key.json")))
    cands = {c["candidate_id"]: c for c in json.load(open(os.path.join(work, "data", "candidates_core.json")))}
    papers = {p["paper_id"]: p for p in json.load(open(os.path.join(work, "data", "papers.json")))}
    rows = []
    for v in key.values():
        c = cands.get(v.get("ref"))
        if v.get("group") not in ("gate_pass", "audit_reject") or not c:
            continue
        abstract = (papers.get(c["paper_id"]) or {}).get("abstract")
        if abstract:
            rows.append({"slug": c["candidate_id"], "stone": c["stone_name"], "claim": c["outcome"], "effect": c.get("effect", ""), "abstract": abstract})
    rows.sort(key=lambda r: r["slug"])
    d = os.path.join(work, "enrich", "why_in")
    os.makedirs(d, exist_ok=True)
    for k in range(0, len(rows), a.size):
        p = os.path.join(d, f"candidates_{k // a.size + 1:02d}.json")
        json.dump(rows[k:k + a.size], open(p, "w"), indent=1, ensure_ascii=False)
        print("why", os.path.relpath(p, work), len(rows[k:k + a.size]), "items")


def cmd_inputs(a, work):
    if a.candidates:
        return cmd_inputs_candidates(a, work)
    texts = os.path.join(work, "enrich", "texts")
    want = set(filter(None, a.slugs.split(",")))
    why, fx = [], []
    for c in json.load(open(a.chains)):
        st = one_study(c)
        if not st or (want and c["slug"] not in want):
            continue
        t = st["test"]
        path, apath = os.path.join(texts, c["slug"] + ".txt"), os.path.join(texts, c["slug"] + ".abstract.txt")
        has = os.path.exists(path)
        abstract = open(apath).read() if os.path.exists(apath) else None
        if not t.get("why") and abstract:
            why.append({"slug": c["slug"], "stone": c["steps"][0]["claim"], "claim": st["claim"], "effect": t.get("effect", ""), "abstract": abstract})
        if not t.get("fx") and has:
            fx.append({"slug": c["slug"], "headline": c.get("title", ""), "stone": c["steps"][0]["claim"], "claim": st["claim"],
                       "grade": t.get("grade"), "effect": t.get("effect", ""), "note": st.get("note", ""), "fulltext": path})
    name = os.path.splitext(os.path.basename(a.chains))[0]
    for step, rows in (("why", why), ("fx", fx)):
        d = os.path.join(work, "enrich", step + "_in")
        os.makedirs(d, exist_ok=True)
        for k in range(0, len(rows), a.size):
            p = os.path.join(d, f"{name}_{k // a.size + 1:02d}.json")
            json.dump(rows[k:k + a.size], open(p, "w"), indent=1, ensure_ascii=False)
            print(step, os.path.relpath(p, work), len(rows[k:k + a.size]), "items")
    if not why:
        print("why: nothing to do (every story has a line, or no abstract was saved)")


def check_why(w, item):
    if w.get("kind") not in ("tested", "suggested", "none"):
        return "kind"
    if w["kind"] == "none":
        return None if not w.get("why") else "none with a sentence"
    if not w.get("quote") or col(w["quote"]) not in col(item["abstract"]):
        return "quote not in the abstract"
    if len(w["why"].split()) > 22 or "—" in w["why"]:
        return "style"
    return None


def check_fx(f, item):
    if f.get("kind") not in KINDS:
        return "kind"
    if f["kind"] == "none":
        return None
    text = col(open(item["fulltext"], errors="ignore").read()) if item.get("fulltext") else ""
    q = col(f.get("quote"))
    if not q or (q not in text and q.replace(" ", "") not in text.replace(" ", "")):
        return "quote not in the text"
    ns = NUM(q)
    for b in f.get("bars") or []:
        for k in ("pct", "pct_lo", "pct_hi", "v", "lo", "hi"):
            if k in b and abs(b[k]) not in ns:
                return f"{k} {b[k]} not in the quote"
        if len(str(b.get("label", "")).split()) > 5:
            return "label longer than 5 words"
    if "—" in json.dumps(f, ensure_ascii=False) or not f.get("bars"):
        return "style or no bars"
    return None


def cmd_assemble(a, work):
    out = {"why": {}, "fx": {}}
    bad = 0
    for step, check in (("why", check_why), ("fx", check_fx)):
        for inp in sorted(glob.glob(os.path.join(work, "enrich", step + "_in", "*.json"))):
            raw = os.path.join(work, "enrich", step + "_raw", os.path.basename(inp))
            if not os.path.exists(raw):
                print("waiting:", os.path.relpath(raw, work))
                continue
            items = {i["slug"]: i for i in json.load(open(inp))}
            for r in json.load(open(raw)):
                why = check(r, items.get(r.get("slug"), {})) if r.get("slug") in items else "unknown slug"
                if why:
                    bad += 1
                    print(f"{step} FAIL {r.get('slug')}: {why}")
                    continue
                if r.get("kind") != "none":
                    if step == "fx":
                        meta = os.path.join(work, "enrich", "texts", r["slug"] + ".json")
                        if os.path.exists(meta):
                            r["text_url"] = json.load(open(meta)).get("url")
                    out[step][r["slug"]] = r
    json.dump(out, open(os.path.join(work, "enrich", "enrich.json"), "w"), indent=1, ensure_ascii=False)
    print(f"why {len(out['why'])}, fx {len(out['fx'])} passed; {bad} failed -> enrich/enrich.json")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cmd", choices=["inputs", "assemble"])
    ap.add_argument("--chains")
    ap.add_argument("--candidates", action="store_true", help="inputs: a run's rated candidates instead of a chains file")
    ap.add_argument("--slugs", default="")
    ap.add_argument("--size", type=int, default=6)
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    if a.cmd == "inputs":
        if not a.chains and not a.candidates:
            ap.error("--chains or --candidates is required for inputs")
        cmd_inputs(a, work)
    else:
        cmd_assemble(a, work)


if __name__ == "__main__":
    main()
