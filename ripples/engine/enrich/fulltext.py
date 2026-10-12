"""Find and fetch an open copy of each study's text, for the why line and the effect numbers.

    python3 ripples/engine/enrich/fulltext.py --chains ripples/chains/batch19.json [--slugs a,b] [--dry-run]
    python3 ripples/engine/enrich/fulltext.py --targets build/targets.json [--dry-run]   # [{slug, doi, openalex}] (build stage)

For each one-study story in the chains file it tries, in order: PubMed Central (the NCBI id converter, then efetch),
then the open locations OpenAlex lists for the DOI (repository copies before publisher PDFs). SSRN is never fetched.
Every request goes through fetch.py: one retry on a 5xx, a 429 or a timeout, then the host stops for the UTC day. A PDF
is turned into text with pdftotext (poppler); XML and HTML lose their tags. The abstract (OpenAlex's inverted index)
is kept too, so a story with no reachable full text still has a text to read.

Writes enrich/texts/<slug>.txt (full text, else the abstract), <slug>.abstract.txt and <slug>.json (where it came
from) in the work directory, and enrich/texts/index.json. Prints one line per story.
"""
import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import fetch  # noqa: E402
import workdir  # noqa: E402

NEVER = ("ssrn.com",)


def plain(s):
    s = re.sub(r"<script.*?</script>|<style.*?</style>", " ", s, flags=re.S)
    return re.sub(r"[ \t]+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s)))


def one_study(c):
    st = [x for x in c["steps"] if (x.get("test") or {}).get("type") == "study"]
    return st[0] if len(st) == 1 else None


def openalex(doi, work_id=None):
    key = work_id if work_id else "doi:" + urllib.parse.quote(doi)  # a paper with no DOI is looked up by its OpenAlex id
    st, txt, _ = fetch.get("https://api.openalex.org/works/" + key)
    if st != 200:
        return None, []
    w = json.loads(txt)
    inv = w.get("abstract_inverted_index") or {}
    abstract = " ".join(word for _, word in sorted((p, word) for word, ps in inv.items() for p in ps)) or None
    locs = []
    for l in w.get("locations") or []:
        u = l.get("pdf_url")
        if l.get("is_oa") and u and not any(n in u for n in NEVER):
            repo = (l.get("source") or {}).get("type") == "repository"
            locs.append((0 if repo else 1, u))
    return abstract, [u for _, u in sorted(locs)]


def pmc(doi):
    st, txt, _ = fetch.get("https://www.ncbi.nlm.nih.gov/pmc/utils/idconv/v1.0/?format=json&tool=ripple&ids=" + urllib.parse.quote(doi))
    if st != 200:
        return None
    rec = (json.loads(txt).get("records") or [{}])[0]
    pid = rec.get("pmcid")
    if not pid:
        return None
    st, xml, url = fetch.get(f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id={pid[3:]}&tool=ripple")
    return (plain(xml), url) if st == 200 and "<body" in xml else None


def pdf_text(data, path):
    if not shutil.which("pdftotext"):
        return None
    open(path, "wb").write(data)
    subprocess.run(["pdftotext", "-layout", path, path[:-4] + ".pdftxt"], check=False)
    out = path[:-4] + ".pdftxt"
    return open(out, errors="ignore").read() if os.path.exists(out) else None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--chains")
    ap.add_argument("--targets", help="a JSON list of {slug, doi, openalex} instead of a chains file")
    ap.add_argument("--slugs", default="")
    ap.add_argument("--dry-run", action="store_true")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    fetch.configure(work)
    out = os.path.join(work, "enrich", "texts")
    os.makedirs(out, exist_ok=True)
    want = set(filter(None, a.slugs.split(",")))
    if bool(a.chains) == bool(a.targets):
        ap.error("give --chains or --targets")
    if a.targets:
        todo = [(t["slug"], (t.get("doi") or "").lower(), t.get("openalex")) for t in json.load(open(a.targets))]
    else:
        todo = []
        for c in json.load(open(a.chains)):
            st = one_study(c)
            if st and (not want or c["slug"] in want):
                todo.append((c["slug"], (st["test"].get("doi") or "").lower(), None))
    ipath = os.path.join(out, "index.json")
    index = json.load(open(ipath)) if a.targets and os.path.exists(ipath) else {}
    for slug, doi, wid in todo:
        c = {"slug": slug}
        if a.dry_run:
            print(slug, doi or wid or "(no DOI)")
            continue
        text, src, kind, abstract = None, None, None, None
        if doi or wid:
            got = pmc(doi) if doi else None
            if got:
                text, src, kind = got[0], got[1], "full text (PubMed Central)"
            abstract, locs = openalex(doi, wid)
            for u in [] if text else locs:
                stt, data, final = fetch.get_bytes(u)
                if stt == 200 and data[:4] == b"%PDF":
                    t = pdf_text(data, os.path.join(out, c["slug"] + ".pdf"))
                    if t and len(t) > 5000:
                        text, src, kind = t, final, "full text (open PDF)"
                        break
        if not text and abstract:
            text, src, kind = abstract, "https://api.openalex.org/works/" + (wid or "doi:" + doi), "abstract only"
        if text:
            open(os.path.join(out, c["slug"] + ".txt"), "w").write(text)
        if abstract:  # the why line reads the abstract only
            open(os.path.join(out, c["slug"] + ".abstract.txt"), "w").write(abstract)
        meta = {"slug": c["slug"], "doi": doi, "kind": kind or "nothing reachable", "url": src, "chars": len(text or "")}
        json.dump(meta, open(os.path.join(out, c["slug"] + ".json"), "w"), indent=1)
        index[c["slug"]] = meta
        print(c["slug"], "|", meta["kind"], "|", meta["chars"], "chars")
    if not a.dry_run:
        json.dump(index, open(ipath, "w"), indent=1)


if __name__ == "__main__":
    main()
