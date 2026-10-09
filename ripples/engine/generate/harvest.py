"""Harvest: run a frozen query file on OpenAlex or PubMed. Resumable; appends to data/harvest.jsonl.

    python3 ripples/engine/generate/harvest.py pubmed                 # the PubMed queries (cells that carry them)
    python3 ripples/engine/generate/harvest.py openalex               # the OpenAlex queries
    python3 ripples/engine/generate/harvest.py openalex --dry-run     # list what would be sent; no request
    python3 ripples/engine/generate/harvest.py summary                # metadata-only copy and counts by cell

Options: --queries FILE (default generate/queries/discovery_v4.json), --max-searches N (stop after N new searches),
--work DIR. A work directory is tied to the first query file harvested into it; a different file needs a new one.

OpenAlex: before each search the harvester reads X-RateLimit-Remaining from the last OpenAlex reply and stops when fewer
than 10 credits are left (a search costs 10), so the daily budget is never overrun on purpose. Keyless use gets 1,000
credits a day, reset at 00:00 UTC. With OPENALEX_API_KEY set, the key goes to api.openalex.org only (see fetch.py).
Any 4xx or 5xx stops the host for the UTC day; rerun on a later day and the harvest resumes where it stopped.

summary writes data/harvest_meta.jsonl: every record without its abstract (id, DOI, PMID, title, year, venue, citations,
query cell, abstract length). It prints records and unique papers by cell, and appends the same table to
$GITHUB_STEP_SUMMARY when that is set.
"""
import argparse
import datetime
import hashlib
import json
import os
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from collections import defaultdict

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import fetch  # noqa: E402
import workdir  # noqa: E402

DEFAULT_QUERIES = os.path.join(ENGINE, "generate", "queries", "discovery_v4.json")


def utc():
    return datetime.datetime.now(datetime.timezone.utc)


class Run:
    def __init__(self, work, queries_path):
        self.work = work
        self.out = os.path.join(work, "data", "harvest.jsonl")
        self.done_p = os.path.join(work, "data", "harvest_done.json")
        self.runlog = os.path.join(work, "logs", "harvest_run.log")
        self.done = json.load(open(self.done_p)) if os.path.exists(self.done_p) else {}
        self.queries_path = queries_path
        self.Q = json.load(open(queries_path))
        self.q_sha = hashlib.sha256(open(queries_path, "rb").read()).hexdigest()

    def log(self, msg):
        line = utc().strftime("%m/%d/%Y %H:%M:%S UTC") + "\t" + fetch.redact(msg)
        print(line, flush=True)
        open(self.runlog, "a").write(line + "\n")

    def bind_queries(self):
        """Tie the work directory to one query file, so resumed keys always mean the same query."""
        p = os.path.join(self.work, "data", "harvest_queries.json")
        if os.path.exists(p):
            prev = json.load(open(p))
            if prev["sha256"] != self.q_sha:
                raise SystemExit(f"this work directory was harvested with {prev['file']} (sha256 {prev['sha256'][:12]}); "
                                 f"use a new --work for {os.path.basename(self.queries_path)}")
        else:
            json.dump({"file": os.path.basename(self.queries_path), "sha256": self.q_sha,
                       "first_utc": utc().strftime("%Y-%m-%dT%H:%M:%SZ")}, open(p, "w"), indent=1)

    def save_done(self):
        json.dump(self.done, open(self.done_p, "w"), indent=1)


def deinvert(inv):
    if not inv:
        return ""
    pos = {}
    for w, idx in inv.items():
        for i in idx:
            pos[i] = w
    return " ".join(pos[i] for i in sorted(pos))


def openalex_url(q):
    return "https://api.openalex.org/works?" + urllib.parse.urlencode({
        "search": q, "per-page": 50,
        "select": "id,doi,title,publication_year,cited_by_count,abstract_inverted_index,primary_location"})


def openalex(q):
    st, body, _ = fetch.get(openalex_url(q))
    if st != 200:
        return st, []
    out = []
    for w in json.loads(body).get("results", []):
        pl = w.get("primary_location") or {}
        src = (pl.get("source") or {}).get("display_name")
        out.append({"src": "openalex", "id": w["id"], "doi": (w.get("doi") or "").replace("https://doi.org/", "").lower(),
                    "title": w.get("title"), "year": w.get("publication_year"), "cites": w.get("cited_by_count"),
                    "abstract": deinvert(w.get("abstract_inverted_index")), "venue": src,
                    "landing": pl.get("landing_page_url"), "pmid": None})
    return st, out


def pubmed_search_url(q):
    return "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?" + urllib.parse.urlencode(
        {"db": "pubmed", "term": q, "retmax": 40, "sort": "relevance", "retmode": "json"})


def pubmed(q):
    st, body, _ = fetch.get(pubmed_search_url(q))
    if st != 200:
        return st, []
    ids = json.loads(body)["esearchresult"].get("idlist", [])
    if not ids:
        return st, []
    url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?" + urllib.parse.urlencode(
        {"db": "pubmed", "id": ",".join(ids), "rettype": "abstract", "retmode": "xml"})
    st, body, _ = fetch.get(url)
    if st != 200:
        return st, []
    out = []
    root = ET.fromstring(body)
    for art in root.findall(".//PubmedArticle"):
        pmid = art.findtext(".//PMID")
        t = art.find(".//ArticleTitle")
        title = "".join(t.itertext()) if t is not None else ""
        abst = " ".join("".join(a.itertext()) for a in art.findall(".//Abstract/AbstractText"))
        year = art.findtext(".//JournalIssue/PubDate/Year") or (art.findtext(".//JournalIssue/PubDate/MedlineDate") or "")[:4]
        doi = ""
        for aid in art.findall(".//PubmedData/ArticleIdList/ArticleId"):
            if aid.get("IdType") == "doi":
                doi = (aid.text or "").lower()
        out.append({"src": "pubmed", "id": "PMID:" + pmid, "doi": doi, "title": title,
                    "year": int(year) if year[:4].isdigit() else None, "cites": None, "abstract": abst,
                    "venue": art.findtext(".//Journal/Title"), "landing": None, "pmid": pmid})
    return st, out


def planned(Q, kind):
    for c in Q["cells"]:
        for k, q in enumerate(c.get(kind, [])):
            yield f"{kind}:{c['cell']}:{k}", c["cell"], k, q


def run(R, kind, max_searches=0, dry=False):
    todo = [p for p in planned(R.Q, kind) if p[0] not in R.done]
    if dry:
        n_all = sum(1 for _ in planned(R.Q, kind))
        print(f"{os.path.basename(R.queries_path)} sha256 {R.q_sha[:12]}: {n_all} {kind} queries, {len(todo)} not yet run "
              f"in {R.work}")
        if kind == "openalex":
            print(f"OpenAlex key in environment: {'yes (sent to api.openalex.org only)' if fetch.key_present() else 'no (keyless budget)'}")
        for key, cell, k, q in todo[:3]:
            print(" ", key, (openalex_url(q) if kind == "openalex" else pubmed_search_url(q))[:160])
        if len(todo) > 3:
            print(f"  ... and {len(todo) - 3} more")
        return
    R.bind_queries()
    host = fetch.OPENALEX_HOST if kind == "openalex" else "eutils.ncbi.nlm.nih.gov"
    n = 0
    with open(R.out, "a") as f:
        for key, cell, k, q in todo:
            if max_searches and n >= max_searches:
                R.log(f"{kind}: stopped after {n} searches (--max-searches)")
                return
            if host in fetch.blocked_hosts():
                R.log(f"{kind} stopped for the UTC day (blocked_hosts.log)")
                return
            if kind == "openalex":
                h = fetch.last_headers.get(host, {})
                left = h.get("X-RateLimit-Remaining") or h.get("x-ratelimit-remaining")
                if left is not None and int(float(left)) < 10:
                    R.log(f"openalex budget left {left} credits; stopping before the next search; reset in "
                          f"{h.get('X-RateLimit-Reset') or h.get('x-ratelimit-reset')} s")
                    return
                st, rs = openalex(q)
            else:
                st, rs = pubmed(q)
            n += 1
            if st != 200:
                R.log(f"{key} status {st}; host stopped")
                return
            for r in rs:
                r.update({"query_cell": cell, "query_kind": kind, "query_idx": k, "query": q})
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
            f.flush()
            left = fetch.last_headers.get(host, {}).get("X-RateLimit-Remaining") if kind == "openalex" else None
            R.done[key] = {"n": len(rs), "utc": utc().strftime("%Y-%m-%dT%H:%M:%SZ"), "ratelimit": left}
            R.save_done()
            R.log(f"{key} {len(rs)} records")
    R.log(f"{kind}: all {len(todo)} remaining queries run")


def summary(R):
    if not os.path.exists(R.out):
        print("no harvest yet:", R.out)
        return
    recs = [json.loads(l) for l in open(R.out) if l.strip()]
    meta_p = os.path.join(R.work, "data", "harvest_meta.jsonl")
    by_cell = defaultdict(lambda: {"records": 0, "papers": set(), "with_abstract": 0})
    with open(meta_p, "w") as fo:
        for r in recs:
            m = {k: r.get(k) for k in ("src", "id", "doi", "pmid", "title", "year", "venue", "cites", "landing",
                                       "query_cell", "query_kind", "query_idx")}
            m["abstract_chars"] = len(r.get("abstract") or "")
            fo.write(json.dumps(m, ensure_ascii=False) + "\n")
            b = by_cell[r["query_cell"]]
            b["records"] += 1
            b["papers"].add(r.get("doi") or r["id"])
            b["with_abstract"] += bool(r.get("abstract"))
    unique = {r.get("doi") or r["id"] for r in recs}
    lines = [f"Harvest: {len(recs)} records, {len(unique)} unique papers, {len(R.done)} queries run "
             f"({os.path.basename(R.queries_path)}).", "", "| Cell | Records | Unique papers | With abstract |", "|---|---|---|---|"]
    for cell in sorted(by_cell):
        b = by_cell[cell]
        lines.append(f"| {cell} | {b['records']} | {len(b['papers'])} | {b['with_abstract']} |")
    text = "\n".join(lines) + "\n"
    print(text)
    print("wrote", meta_p)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        open(os.environ["GITHUB_STEP_SUMMARY"], "a").write(text)


def main():
    ap = argparse.ArgumentParser(description="Harvest the frozen queries (script step).")
    ap.add_argument("kind", choices=["openalex", "pubmed", "summary"])
    ap.add_argument("--queries", default=DEFAULT_QUERIES)
    ap.add_argument("--max-searches", type=int, default=0, help="stop after this many new searches (0 = no cap)")
    ap.add_argument("--dry-run", action="store_true", help="list what would be sent; send nothing")
    workdir.add_arg(ap)
    a = ap.parse_args()
    if a.max_searches < 0:
        ap.error("--max-searches must be 0 or more")
    work = workdir.resolve(a.work)
    fetch.configure(work)
    R = Run(work, os.path.abspath(a.queries))
    if a.kind == "summary":
        summary(R)
    else:
        run(R, a.kind, a.max_searches, a.dry_run)


if __name__ == "__main__":
    main()
