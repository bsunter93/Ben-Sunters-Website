"""Write checked why lines and effect numbers into a chains file (and the checked copy the page reads).

    python3 ripples/engine/enrich/apply.py --chains ripples/chains/batch19.json [--checked] [--dry-run]

Reads enrich/enrich.json (written by enrich/judged.py assemble). For each one-study story it sets test.why, why_kind
and why_quote, and test.fx (with fx.text_url, the copy its quote came from). A story that already has a value keeps it
unless --replace is given. --checked also writes the same fields into ripples/docs/results/chain_check_v1.json, so the
page shows them before the next chain check; the chain check copies test fields through unchanged. The file keeps its
indentation; only the new fields change.
"""
import argparse
import json
import os
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402

CHECKED = os.path.join(workdir.RIPPLES, "docs", "results", "chain_check_v1.json")


def put(test, why, fx, replace):
    n = 0
    if why and (replace or not test.get("why")):
        test.update(why=why["why"], why_kind=why["kind"], why_quote=why["quote"]); n += 1
    if fx and (replace or not test.get("fx")):
        test["fx"] = {k: v for k, v in fx.items() if k != "slug"}; n += 1
    return n


def write(path, data, raw):
    ind = 1 if raw.startswith("[\n {") or raw.startswith('{\n "') else 2
    open(path, "w").write(json.dumps(data, indent=ind, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--chains", required=True)
    ap.add_argument("--checked", action="store_true")
    ap.add_argument("--replace", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    E = json.load(open(os.path.join(work, "enrich", "enrich.json")))
    targets = [(a.chains, lambda d: d)] + ([(CHECKED, lambda d: d["chains"])] if a.checked else [])
    for path, chains_of in targets:
        raw = open(path).read(); data = json.loads(raw); n = 0
        for c in chains_of(data):
            for st in c["steps"]:
                t = st.get("test") or {}
                if t.get("type") == "study":
                    n += put(t, E["why"].get(c["slug"]), E["fx"].get(c["slug"]), a.replace)
        print(f"{os.path.relpath(path, workdir.REPO)}: {n} fields {'would be ' if a.dry_run else ''}written")
        if not a.dry_run and n:
            write(path, data, raw)


if __name__ == "__main__":
    main()
