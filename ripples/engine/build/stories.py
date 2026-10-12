"""The story builder: verified findings to study stories the page can show, checked by script before anything ships.

    python3 ripples/engine/build/stories.py select --run v5 [--owner-ratings DIR] [--ids CR0082,CR0111] [--all-defensible]
    python3 ripples/engine/enrich/fulltext.py --targets build/targets.json     # each paper's text (PMC, open copies)
    python3 ripples/engine/build/stories.py inputs                              # build/story_in/*.json and enrich/fx_in/build_*.json
    python3 ripples/engine/runner.py story build/story_in/<file>.json         # the words, one fresh context per batch
    python3 ripples/engine/runner.py fx enrich/fx_in/<file>.json              # the effect numbers (enrich's step)
    python3 ripples/engine/enrich/judged.py assemble                           # checks the numbers and the why lines
    python3 ripples/engine/build/stories.py assemble --batch 20                 # checks the words; build/drafts.json, build/report.json
    python3 ripples/engine/build/stories.py preview                             # build/preview.html: the demo with every draft in it
    python3 ripples/engine/build/stories.py apply --to ripples/chains/batch20.json [--rule owner-good-peer | --ids ...] [--checked]

select reads a run's verified candidates (data/candidates_core.json, data/verified.json, data/papers.json) and, with
--owner-ratings, the owner's blind ratings (rate/human/key.json maps them to candidates). It keeps defensible
candidates only: the owner's rated ones by default, every defensible one with --all-defensible, or the --ids given.
The author why lines come from enrich/enrich.json (enrich/judged.py inputs --candidates, then assemble).

assemble checks every story the judged step wrote, and repairs nothing. A draft fails when: it was skipped; a field is
missing or too long; a text has an em dash or a semicolon; a date does not parse, the window runs backwards or past
today, or the stone comes after the paper; a quote is not in the abstract or full text word for word (whitespace
collapsed); a number in the headline, the effect or the big number is not in the effect quote (the headline may round
to a whole number); or the slug is taken. When the texts date the stone but give no study window, the window is the
stone's own year and the step's note says so. The source line, the DOI, the grade and the working-paper label are set by
the script from the paper's record and the verification verdict, never by the judged step.

apply copies passing drafts into a chains file. The default rule, owner-good-peer, ships a draft only when the owner
rated it good (surprise 4 or more, belief 4 or more) and it is a peer-reviewed article; working papers, theses and
repository copies stay drafts. --ids ships exactly the drafts named. --checked also writes the chain check's own
entries for them into ripples/docs/results/chain_check_v1.json (record and study steps are checked offline), so the
page shows them before the next chain check.
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402

CHAINS = os.path.join(workdir.RIPPLES, "chains")
CHECKED = os.path.join(workdir.RIPPLES, "docs", "results", "chain_check_v1.json")
NOT_PEER = re.compile(r"ssrn|national bureau|nber|repec|working paper|research papers|archive|repositor|scholar|commons|"
                      r"digital|uknowledge|tuwhera|creative matter|econstor|osf|icpsr|dataverse|figshare|zenodo|preprint|"
                      r"thesis|dissertation|apsa|proceedings|iza|cepr|discussion paper|mpra", re.I)
col = lambda x: re.sub(r"\s+", " ", x or "").strip()
LIMITS = {"label": 5, "stone_claim": 18, "claim": 12, "short": 4, "design": 20, "effect": 30, "note_more": 50}


def J(p, default=None):
    return json.load(open(p)) if os.path.exists(p) else default


def nums(s):
    return [float(x.replace(",", "")) for x in re.findall(r"(?<![\w.])\d[\d,]*(?:\.\d+)?", s or "")]


def peer_reviewed(venue):
    return bool(venue) and not NOT_PEER.search(venue)


def owner_scores(work, d):
    key = J(os.path.join(work, "rate", "human", "key.json"), {})
    out = {}
    for f in glob.glob(os.path.join(d, "**", "*.json"), recursive=True):
        r = json.load(open(f))
        k = key.get(r.get("item"))
        if k and k.get("group") in ("gate_pass", "audit_reject") and all(r.get(x) for x in ("s", "b", "t")):  # planted controls are not findings
            out[k["ref"]] = {"s": r["s"], "b": r["b"], "t": r["t"], "good": r["s"] >= 4 and r["b"] >= 4}
    return out


def cmd_select(a, work):
    C = {c["candidate_id"]: c for c in J(os.path.join(work, "data", "candidates_core.json"))}
    V = J(os.path.join(work, "data", "verified.json"))
    V = V.get("items", V)
    P = {p["paper_id"]: p for p in J(os.path.join(work, "data", "papers.json"))}
    why = (J(os.path.join(work, "enrich", "enrich.json"), {}) or {}).get("why", {})
    own = owner_scores(work, a.owner_ratings) if a.owner_ratings else {}
    if a.ids:
        ids = [x for x in a.ids.split(",") if x]
    elif a.all_defensible:
        ids = sorted(c for c in C if (V.get(c) or {}).get("defensible"))
    elif own:
        ids = sorted(own)
    else:
        raise SystemExit("give --owner-ratings, --all-defensible or --ids")
    sel, targets = [], []
    for cid in ids:
        c, v = C[cid], V.get(cid) or {}
        if not v.get("defensible"):
            print("not defensible, left out:", cid)
            continue
        p = P.get(c["paper_id"], {})
        oa = next((x.rsplit("/", 1)[-1] for x in re.findall(r"https://openalex\.org/W\d+", str(p.get("ids", "")))), None)
        sel.append({"slug": cid, "run": a.run, "candidate": c, "verified": v, "paper": {k: p.get(k) for k in ("title", "venue", "year", "doi", "abstract")},
                    "openalex": oa, "why": why.get(cid), "owner": own.get(cid)})
        targets.append({"slug": cid, "doi": c.get("doi") or "", "openalex": None if c.get("doi") else oa})
    d = os.path.join(work, "build"); os.makedirs(d, exist_ok=True)
    json.dump(sel, open(os.path.join(d, "selected.json"), "w"), indent=1, ensure_ascii=False)
    json.dump(targets, open(os.path.join(d, "targets.json"), "w"), indent=1)
    print(f"selected {len(sel)} -> build/selected.json; texts to fetch: build/targets.json")


def texts(work, cid):
    t = os.path.join(work, "enrich", "texts")
    meta = J(os.path.join(t, cid + ".json"), {}) or {}
    full = os.path.join(t, cid + ".txt") if str(meta.get("kind", "")).startswith("full text") else None
    ab = os.path.join(t, cid + ".abstract.txt")
    return full, (open(ab).read() if os.path.exists(ab) else None), meta


def cmd_inputs(a, work):
    sel = J(os.path.join(work, "build", "selected.json"))
    story, fx = [], []
    for s in sel:
        c, cid = s["candidate"], s["slug"]
        full, oa_abstract, _ = texts(work, cid)
        abstract = s["paper"].get("abstract") or oa_abstract
        story.append({"slug": cid, "stone": {"name": c["stone_name"], "date": c["stone_date"]}, "outcome": c["outcome"],
                      "direction": c["direction"], "effect": c.get("effect", ""), "design": c.get("design", ""), "quote": c.get("quote", ""),
                      "population_place": c.get("population_place", ""), "paper": {k: s["paper"].get(k) for k in ("title", "venue", "year")},
                      "abstract": abstract, "fulltext": full})
        src = full or os.path.join(work, "enrich", "texts", cid + ".txt")
        if os.path.exists(src):
            fx.append({"slug": cid, "headline": c["outcome"], "stone": c["stone_name"], "claim": c["outcome"], "grade": "measured",
                       "effect": c.get("effect", ""), "note": "", "fulltext": src})
    for step, rows, d in (("story", story, os.path.join(work, "build", "story_in")), ("fx", fx, os.path.join(work, "enrich", "fx_in"))):
        os.makedirs(d, exist_ok=True)
        for k in range(0, len(rows), a.size):
            p = os.path.join(d, f"build_{k // a.size + 1:02d}.json")
            json.dump(rows[k:k + a.size], open(p, "w"), indent=1, ensure_ascii=False)
            print(step, os.path.relpath(p, work), len(rows[k:k + a.size]), "items")


def taken_slugs():
    out = set()
    for f in glob.glob(os.path.join(CHAINS, "*.json")):
        out |= {c["slug"] for c in json.load(open(f))}
    return out


def day(x):
    return dt.date.fromisoformat(x)


def check(r, item, taken):
    if r.get("skip"):
        return "skipped: " + r["skip"]
    for k in ("slug_hint", "label", "years", "stone_claim", "stone_date", "date_precision", "claim", "short", "design", "note_quote", "range"):
        if not r.get(k):
            return f"missing {k}"
    for k, n in LIMITS.items():
        if len(str(r.get(k) or "").split()) > n:
            return f"{k} longer than {n} words"
    if len(r.get("effect_short") or "") > 12:
        return "effect_short longer than 12 characters"
    for k, v in r.items():  # the paper's own words may carry a semicolon; nothing shown may carry an em dash
        if k != "effect_quote" and isinstance(v, str) and ("\u2014" in v or (";" in v and k != "note_quote")):
            return f"em dash or semicolon in {k}"
    if r["date_precision"] not in ("day", "month", "year"):
        return "date_precision"
    try:
        sd, r0, r1 = day(r["stone_date"]), day(r["range"][0]), day(r["range"][1])
    except Exception:  # noqa: BLE001
        return "a date does not parse"
    if r1 < r0 or r1 > dt.date.today() or sd > r1:
        return "dates out of order"
    yr = int(str(item["paper"].get("year") or 9999)[:4])
    if sd.year > yr:
        return "the stone comes after the paper"
    hay = col((item.get("abstract") or "") + " " + (open(item["fulltext"], errors="ignore").read() if item.get("fulltext") else ""))
    for k in ("effect_quote", "note_quote"):
        q = col(r.get(k))
        if q and q not in hay and q.replace(" ", "") not in hay.replace(" ", ""):
            return f"{k} not in the paper's text"
    eq = nums(r.get("effect_quote"))
    years = {float(y) for y in re.findall(r"\b(1[89]\d\d|20\d\d)\b", " ".join([r["years"], r["stone_date"], *r["range"], r.get("effect_quote") or ""]))}
    for k in ("effect", "effect_short", "claim"):
        for n in nums(r.get(k)):
            if n in years:
                continue
            if any(abs(n - q) < 1e-9 for q in eq):
                continue
            if k == "claim" and n == int(n) and any(abs(n - q) <= 0.5 for q in eq):
                continue
            return f"{k}: {n:g} is not in the effect quote"
    if (r.get("effect") or r.get("effect_short")) and not r.get("effect_quote"):
        return "an effect with no quote"
    slug = "study-" + r["slug_hint"]
    if not re.fullmatch(r"study-[a-z0-9]+(-[a-z0-9]+){1,4}", slug) or len(slug) > 48:
        return "slug_hint"
    if slug in taken:
        return "slug taken: " + slug
    return None


SMALL = {"a", "an", "the", "and", "or", "of", "in", "on", "to", "for", "at", "by", "from", "with", "as", "vs"}


def title_case(t):  # a title stored in capitals reads as shouting: case it the way a journal prints it
    if not t.isupper():
        return t
    words, out, start = t.lower().split(" "), [], True
    for w in words:
        out.append(w if (w in SMALL and not start) else w[:1].upper() + w[1:])
        start = w.endswith(":")
    return " ".join(out)


def story_chain(r, s, fx, why, batch):
    p, v = s["paper"], s["verified"]
    title = title_case((p.get("title") or "").strip().rstrip("."))
    venue, year = (p.get("venue") or "").strip(), str(p.get("year") or "")[:4]
    source = f"\u201c{title},\u201d {venue or 'a working paper'}, {year}"
    doi = (s["candidate"].get("doi") or "").lower()
    grade = "measured" if str(v.get("grade", "")).lower().startswith("measured") else "reported"
    prec = {} if r["date_precision"] == "day" else {"date_precision": r["date_precision"]}
    rec = {"type": "record", "date": r["stone_date"], **prec, "source": source, **({"doi": doi} if doi else {})}
    test = {"type": "study", "date": r["stone_date"], **prec, "window": r["years"], "grade": grade, "design": r["design"], "source": source}
    if not peer_reviewed(venue):
        test["review"] = "working paper"
    if r.get("effect"):
        test.update(effect=r["effect"], effect_short=r.get("effect_short") or "")
    if doi:
        test["doi"] = doi
    test["rows"] = [f"{s['run']}:{s['slug']}"]
    if why and why.get("kind") in ("tested", "suggested"):
        test.update(why=why["why"], why_kind=why["kind"], why_quote=why["quote"])
    if fx and fx.get("kind") in ("pct", "levels", "groups") and not re.search(r"\bratio\b", str(fx.get("unit", "")), re.I):  # a ratio has no zero to grow a bar from: the result card says it
        test["fx"] = {k: x for k, x in fx.items() if k != "slug"}
    q = r["note_quote"].strip()
    note = f"From the paper: \u201c{q if q[-1] in '.!?' else q + '.'}\u201d" + (f" {r['note_more'].strip()}" if r.get("note_more") else "")
    step1 = {"n": 1, "claim": r["stone_claim"], "test": rec, **({"note": r["date_note"]} if r.get("date_note") else {})}
    step2 = {"n": 2, "claim": r["claim"], "short": r["short"], "test": test, "range": list(r["range"]), "note": note}
    head = r["label"] if r["years"] in r["label"] else f"{r['label']} ({r['years']})"  # no year twice
    return {"slug": "study-" + r["slug_hint"], "title": head, "date": r["stone_date"], "batch": batch,
            "vertical": "Published studies", "steps": [step1, step2]}


def cmd_assemble(a, work):
    sel = {s["slug"]: s for s in J(os.path.join(work, "build", "selected.json"))}
    enr = J(os.path.join(work, "enrich", "enrich.json"), {}) or {}
    items = {}
    for f in glob.glob(os.path.join(work, "build", "story_in", "*.json")):
        items.update({i["slug"]: i for i in json.load(open(f))})
    taken, drafts, report = taken_slugs(), [], {}
    for f in sorted(glob.glob(os.path.join(work, "build", "story_raw", "*.json"))):
        for r in json.load(open(f)):
            cid = r.get("slug")
            if cid not in sel or cid not in items:
                report[str(cid)] = {"ok": False, "why": "unknown slug"}
                continue
            if not r.get("skip") and r.get("stone_date") and not r.get("years") and not any(r.get("range") or []):  # the texts date the stone but give no window
                r = {**r, "years": r["stone_date"][:4], "range": [r["stone_date"], r["stone_date"]],
                     "date_note": (r.get("date_note") or "") + (" " if r.get("date_note") else "") + "The paper's abstract gives no study window, so the finding is dated to the stone."}
            bad = check(r, items[cid], taken)
            if bad:
                report[cid] = {"ok": False, "why": bad}
                print("FAIL", cid, bad)
                continue
            ch = story_chain(r, sel[cid], enr.get("fx", {}).get(cid), enr.get("why", {}).get(cid) or sel[cid].get("why"), a.batch)
            taken.add(ch["slug"])
            s = sel[cid]
            report[cid] = {"ok": True, "slug": ch["slug"], "title": ch["title"], "claim": r["claim"], "card": "effect chart" if ch["steps"][1]["test"].get("fx") else "result card",
                           "why": bool(ch["steps"][1]["test"].get("why")), "peer_reviewed": peer_reviewed(s["paper"].get("venue")), "owner": s.get("owner")}
            drafts.append(ch)
    missing = [c for c in sel if c not in report]
    for c in missing:
        report[c] = {"ok": False, "why": "no story written yet"}
    json.dump(drafts, open(os.path.join(work, "build", "drafts.json"), "w"), indent=1, ensure_ascii=False)
    json.dump(report, open(os.path.join(work, "build", "report.json"), "w"), indent=1, ensure_ascii=False)
    ok = [v for v in report.values() if v["ok"]]
    print(f"drafts {len(ok)} of {len(report)} passed ({sum(v['card'] == 'effect chart' for v in ok)} with an effect chart, "
          f"{sum(v['why'] for v in ok)} with a why line) -> build/drafts.json, build/report.json")


def checked_entry(ch):
    sys.path.insert(0, os.path.join(workdir.RIPPLES, "lab"))
    import chain_check as cc  # noqa: E402  (record and study steps need no network)
    ref = cc.D(ch["date"])
    out = {k: ch.get(k) for k in ("slug", "title", "date", "batch", "vertical")}
    out["steps"] = []
    for st in ch["steps"]:
        assert st["test"]["type"] in ("record", "study"), "only record and study steps are checked offline"
        r = cc.run_step(st, ref)
        v = cc.verdict(st, r, ref)
        out["steps"].append({"n": st["n"], "claim": st["claim"], "test": {k: st["test"][k] for k in st["test"] if k != "counts"},
                             "ref": ref.isoformat(), "verdict": v, "note": st.get("note"), "link": st.get("link"), "link_why": st.get("link_why"),
                             "branch": st.get("branch", False), "vertical": st.get("vertical"), "after": st.get("after"), "slice": st.get("slice"),
                             "short": st.get("short"), "mark": st.get("mark"), **r})
        if v in ("measured", "reported") and r.get("onset"):
            ref = max(ref, cc.D(r["onset"]))
    return out


def write_json(path, data, raw):
    ind = 1 if raw.startswith("[\n {") or raw.startswith('{\n "') else 2
    open(path, "w").write(json.dumps(data, indent=ind, ensure_ascii=False) + ("\n" if raw.endswith("\n") or not raw else ""))


def cmd_apply(a, work):
    drafts = {d["slug"]: d for d in J(os.path.join(work, "build", "drafts.json"), [])}
    report = J(os.path.join(work, "build", "report.json"), {})
    if a.ids:
        want = [s for s in a.ids.split(",") if s]
    else:  # owner-good-peer
        want = [v["slug"] for v in report.values() if v.get("ok") and v.get("peer_reviewed") and (v.get("owner") or {}).get("good")]
    raw = open(a.to).read() if os.path.exists(a.to) else ""
    chains = json.loads(raw) if raw else []
    have = {c["slug"] for c in chains}
    new = [drafts[s] for s in want if s in drafts and s not in have]
    for s in want:
        if s not in drafts:
            print("no passing draft:", s)
    if a.dry_run:
        print("would add", [c["slug"] for c in new]); return
    chains += new
    write_json(a.to, chains, raw or "[\n {")
    print(f"added {len(new)} to {os.path.relpath(a.to, workdir.REPO)}:", ", ".join(c["slug"] for c in new))
    if a.checked and new:
        raw2 = open(CHECKED).read(); rep = json.loads(raw2)
        done = {c["slug"] for c in rep["chains"]}
        rep["chains"] += [checked_entry(c) for c in new if c["slug"] not in done]
        write_json(CHECKED, rep, raw2)
        print("and their chain check entries to", os.path.relpath(CHECKED, workdir.REPO))


def cmd_preview(a, work):
    sys.path.insert(0, os.path.join(workdir.RIPPLES, "tools"))
    import build_portable as bp  # noqa: E402
    have = {c["slug"] for c in J(CHECKED)["chains"]}  # a draft already applied is in the page's data once
    drafts = [d for d in J(os.path.join(work, "build", "drafts.json"), []) if d["slug"] not in have]
    out = os.path.join(work, "build", "preview.html")
    n, size = bp.standalone(extra_chains=[checked_entry(c) for c in drafts], out=out)
    print(f"{len(drafts)} drafts in {os.path.relpath(out, work)} ({size // 1024} KB); open ?c=<slug>&nointro=1")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cmd", choices=["select", "inputs", "assemble", "apply", "preview"])
    ap.add_argument("--run", default="")
    ap.add_argument("--owner-ratings")
    ap.add_argument("--ids", default="")
    ap.add_argument("--all-defensible", action="store_true")
    ap.add_argument("--size", type=int, default=6)
    ap.add_argument("--batch", type=int, default=20)
    ap.add_argument("--to")
    ap.add_argument("--rule", default="owner-good-peer", choices=["owner-good-peer"])
    ap.add_argument("--checked", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    if a.cmd == "select" and not a.run:
        ap.error("--run names the discovery run (it prefixes the candidate ids the stories keep)")
    if a.cmd == "apply" and not a.to:
        ap.error("--to is the chains file to add to")
    {"select": cmd_select, "inputs": cmd_inputs, "assemble": cmd_assemble, "apply": cmd_apply, "preview": cmd_preview}[a.cmd](a, work)


if __name__ == "__main__":
    main()
