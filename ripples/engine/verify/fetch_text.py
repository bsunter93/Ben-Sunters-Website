"""Fetch verification text for each selected candidate (the studies pilot method). A script step.

    python3 ripples/engine/verify/fetch_text.py                          # targets from data/verify_targets.json
    python3 ripples/engine/verify/fetch_text.py --targets FILE --dry-run # list the targets; send nothing

For each target paper, in this order, stopping at the first text that contains the quote (Oct 12, owner: "make the
verification fix now"; v5 amendment A1):
  1. its PubMed abstract (by PMID, or a PMID found by DOI)
  2. the publisher-deposited abstract on Crossref
  3. its Europe PMC abstract (by DOI)
  4. its PubMed Central full text
  5. an open copy: the target's own, then OpenAlex's open locations, repositories first, never SSRN; a PDF is read with
     pdftotext (it used to be read as a web page, which turned it into noise)
  6. the DOI landing page, last, because a publisher's 403 stops its host for every later paper that day
  7. OpenAlex's copy of the abstract, labeled openalex-abstract: the same words extraction read, so a quote found only
     there is reported apart
The first text that contains the quote wins, and every text fetched is saved under verify/ in the work
directory (never committed: these are publishers' words). Writes verify/verify_fetch.jsonl (one line per target and
source tried) and verify/verify_fetch_summary.json. The judgment itself is a judged step (verify/judge.py).
"""
import argparse, html, json, os, re, shutil, subprocess, sys, urllib.parse
import xml.etree.ElementTree as ET

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import fetch  # noqa: E402
import workdir  # noqa: E402

VDIR = None


def text_of(body):
    body = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", body)
    t = re.sub(r"(?s)<[^>]+>", " ", body)
    return re.sub(r"\s+", " ", html.unescape(t))


def norm(t):
    t = t.replace("\u00a0", " ").replace("\u2009", " ").replace("\u2019", "'").replace("\u2018", "'").replace("\u201c", '"').replace("\u201d", '"')
    t = t.replace("\u2013", "-").replace("\u2014", "-").replace("\u2212", "-")
    return re.sub(r"\s+", " ", t).strip().lower()


def has(txt, q):
    return bool(q) and norm(q) in norm(txt)


def log(rec):
    open(os.path.join(VDIR, "verify_fetch.jsonl"), "a").write(json.dumps(rec, ensure_ascii=False) + "\n")


def pmid_for_doi(doi):
    st, body, _ = fetch.get("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?" + urllib.parse.urlencode(
        {"db": "pubmed", "term": doi + "[doi]", "retmode": "json"}))
    if st != 200:
        return None
    ids = json.loads(body)["esearchresult"].get("idlist", [])
    return ids[0] if len(ids) == 1 else None


def pubmed_text(pmid):
    st, body, _ = fetch.get("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?" + urllib.parse.urlencode(
        {"db": "pubmed", "id": pmid, "rettype": "abstract", "retmode": "xml"}))
    if st != 200:
        return st, None
    art = ET.fromstring(body).find(".//PubmedArticle")
    if art is None:
        return st, None
    t = art.find(".//ArticleTitle")
    title = "".join(t.itertext()) if t is not None else ""
    ab = " ".join("".join(a.itertext()) for a in art.findall(".//Abstract/AbstractText"))
    j = art.findtext(".//Journal/Title") or ""
    y = art.findtext(".//JournalIssue/PubDate/Year") or ""
    return st, f"{title}\n{j} {y}\n\n{ab}"


def crossref_text(doi):
    st, body, _ = fetch.get("https://api.crossref.org/works/" + urllib.parse.quote(doi))
    if st != 200:
        return st, None, {}
    m = json.loads(body)["message"]
    ab = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.get("abstract", "") or "")).strip()
    meta = {"title": (m.get("title") or [""])[0], "issued": m.get("issued"), "container": m.get("container-title"),
            "cites": m.get("is-referenced-by-count")}
    return st, (meta["title"] + "\n\n" + ab) if ab else None, meta


def europepmc_text(doi):
    st, body, _ = fetch.get("https://www.ebi.ac.uk/europepmc/webservices/rest/search?" + urllib.parse.urlencode(
        {"query": f'DOI:"{doi}"', "resultType": "core", "format": "json"}))
    if st != 200:
        return st, None
    r = (json.loads(body).get("resultList") or {}).get("result") or []
    ab = text_of(r[0].get("abstractText") or "") if r else ""
    return st, (r[0].get("title", "") + "\n\n" + ab) if ab else None


def pmc_text(doi, pmid):
    ids = pmid or doi
    st, body, _ = fetch.get("https://www.ncbi.nlm.nih.gov/pmc/utils/idconv/v1.0/?" + urllib.parse.urlencode({"format": "json", "tool": "ripple", "ids": ids}))
    if st != 200:
        return st, None, None
    pmc = ((json.loads(body).get("records") or [{}])[0]).get("pmcid")
    if not pmc:
        return st, None, None
    st, body, url = fetch.get("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?" + urllib.parse.urlencode({"db": "pmc", "id": pmc[3:], "tool": "ripple"}))
    return (st, text_of(body), f"https://pmc.ncbi.nlm.nih.gov/articles/{pmc}/") if st == 200 and "<body" in body else (st, None, None)


_OA = {}


def openalex_work(doi):
    if doi not in _OA:
        st, body, _ = fetch.get("https://api.openalex.org/works/doi:" + urllib.parse.quote(doi))
        _OA[doi] = json.loads(body) if st == 200 else {}
    return _OA[doi]


def openalex_copies(doi):
    locs = []
    for l in openalex_work(doi).get("locations") or []:
        u = l.get("pdf_url") or l.get("landing_page_url")
        if l.get("is_oa") and u and "ssrn.com" not in u and "doi.org/" not in u:
            locs.append((0 if (l.get("source") or {}).get("type") == "repository" else 1, u))
    return [u for _, u in sorted(locs)]


def openalex_abstract(doi):
    inv = openalex_work(doi).get("abstract_inverted_index") or {}
    return " ".join(w for _, w in sorted((p, w) for w, ps in inv.items() for p in ps)) or None


def copy_text(url):
    """An open copy: a PDF goes through pdftotext, anything else is read as a page."""
    if url.lower().split("?")[0].endswith(".pdf") or "/pdf" in url.lower():
        try:
            st, data, final = fetch.get_bytes(url)
        except RuntimeError:
            return -2, None, url
        if st == 200 and data[:4] == b"%PDF" and shutil.which("pdftotext"):
            pdf = os.path.join(VDIR, "_tmp.pdf"); open(pdf, "wb").write(data)
            out = subprocess.run(["pdftotext", "-layout", pdf, "-"], capture_output=True).stdout.decode("utf-8", "ignore")
            os.remove(pdf)
            return st, (re.sub(r"\s+", " ", out) if len(out) > 2000 else None), final
        if st != 200 or data[:4] == b"%PDF":
            return st, None, final
    return landing_text(url)


def landing_text(url):
    try:
        st, body, final = fetch.get(url)
    except RuntimeError:  # a forbidden host (SSRN, say), reached directly or by a redirect: no text from it
        return -2, None, url
    if st != 200:
        return st, None, final
    return st, text_of(body)[:80000], final


def run(targets):
    out = {}
    for t in targets:
        pid, doi, q = t.get("target_id") or t["paper_key"], t.get("doi") or "", t["quote"]
        safe = re.sub(r"[^A-Za-z0-9]+", "_", pid)[:80]
        res = {"target_id": pid, "paper_id": t.get("paper_id"), "found_in": None, "sources_tried": []}
        texts = []
        pmid = t.get("pmid") or (pmid_for_doi(doi) if doi else None)
        if pmid:
            st, txt = pubmed_text(pmid)
            res["sources_tried"].append({"source": "pubmed", "pmid": pmid, "status": st, "has_text": bool(txt)})
            if txt:
                open(f"{VDIR}/{safe}__pubmed.txt", "w").write(f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/\n\n" + txt)
                texts.append(("pubmed", f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/", txt))
        if doi and not any(has(x[2], q) for x in texts):
            st, txt, meta = crossref_text(doi)
            res["sources_tried"].append({"source": "crossref-abstract", "status": st, "has_text": bool(txt)})
            res["crossref_meta"] = meta
            if txt:
                open(f"{VDIR}/{safe}__crossref.txt", "w").write(f"crossref {doi}\n{json.dumps(meta)}\n\n" + txt)
                texts.append(("crossref-abstract", "https://api.crossref.org/works/" + doi, txt))
        def want():
            return not any(has(x[2], q) for x in texts)

        def keep(src, suffix, url, txt, extra):
            res["sources_tried"].append({"source": src, "url": url, "has_text": bool(txt), **extra})
            if txt:
                open(f"{VDIR}/{safe}__{suffix}.txt", "w").write(f"{url}\n\n" + txt)
                texts.append((src, url, txt))

        if doi and want():
            st, txt = europepmc_text(doi)
            keep("europepmc", "europepmc", "https://europepmc.org/search?query=DOI:" + doi, txt, {"status": st})
        if (doi or pmid) and want():
            st, txt, url = pmc_text(doi, pmid)
            keep("pmc-fulltext", "pmc", url or "", txt, {"status": st})
        copies = list(t.get("open_copies", [])) + ([u for u in openalex_copies(doi) if u not in t.get("open_copies", [])] if doi else [])
        for alt in copies:
            if not want():
                break
            st, txt, final = copy_text(alt)
            keep("open-copy", "open", final, txt, {"status": st, "asked": alt})
        if doi and want():
            st, txt, final = landing_text("https://doi.org/" + doi)
            keep("landing", "landing", final, txt, {"status": st})
        if doi and want():
            txt = openalex_abstract(doi)
            keep("openalex-abstract", "openalex", "https://api.openalex.org/works/doi:" + doi, txt, {})
        for src, url, txt in texts:
            if has(txt, q):
                res["found_in"] = {"source": src, "url": url}
                break
        res["any_text"] = [{"source": s, "url": u, "chars": len(x)} for s, u, x in texts]
        res["safe"] = safe
        log(res)
        out[pid] = res
        print(("OK  " if res["found_in"] else ("TEXT" if texts else "NONE")), pid, (res["found_in"] or {}).get("source"), flush=True)
    return out


def main():
    global VDIR
    ap = argparse.ArgumentParser(description="Fetch verification text (script step).")
    ap.add_argument("--targets", help="targets file (default data/verify_targets.json in the work directory)")
    ap.add_argument("--dry-run", action="store_true")
    workdir.add_arg(ap)
    a = ap.parse_args()
    W = workdir.resolve(a.work)
    fetch.configure(W)
    VDIR = os.path.join(W, "verify")
    targets = json.load(open(a.targets or os.path.join(W, "data", "verify_targets.json")))
    if a.dry_run:
        print(len(targets), "targets;", sum(1 for t in targets if t.get("pmid")), "with a PMID,",
              sum(1 for t in targets if t.get("doi")), "with a DOI; blocked today:", sorted(fetch.blocked_hosts()))
        return
    r = run(targets)
    p = os.path.join(VDIR, "verify_fetch_summary.json")
    old = json.load(open(p)) if os.path.exists(p) else {}
    old.update(r)
    json.dump(old, open(p, "w"), indent=1, ensure_ascii=False)
    print("blocked today:", sorted(fetch.blocked_hosts()))


if __name__ == "__main__":
    main()
