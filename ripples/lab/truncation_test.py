"""Truncation test (the roundtable's idea 4): do the measured Wikipedia grades hold when the series is cut off at an
earlier date? Each measured wiki step is recomputed as it would have been with data ending Dec 31, 2024, Dec 31, 2025
and today. The placebo pool is drawn from history before the step, so only the post-step window can change; this test
checks that claim against the data. Writes ripples/docs/results/truncation_v1.json. Honest UA, no keys."""
import datetime as dt, json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import chain_check as cc

ROOT = os.path.join(os.path.dirname(__file__), "..")
CUTOFFS = [dt.date(2024, 12, 31), dt.date(2025, 12, 31), dt.date.today()]

def main():
    res = json.load(open(os.path.join(ROOT, "docs", "results", "chain_check_v1.json")))
    rows = []
    for ch in res["chains"]:
        for st in ch["steps"]:
            if st.get("verdict") == "measured" and st["test"].get("type") == "wiki":
                rows.append((ch["slug"], st["n"], st["test"]["articles"], cc.D(st["ref"]), st["test"].get("lag", 150), st.get("p"), st.get("ratio")))
    out = {"protocol": "ripples/lab/truncation_test.py", "run": dt.date.today().isoformat(), "cutoffs": [c.isoformat() for c in CUTOFFS], "steps": []}
    flips = 0
    for slug, n, arts, ref, lag, p0, r0 in rows:
        row = {"slug": slug, "n": n, "articles": arts, "ref": ref.isoformat(), "lag": lag, "committed": {"p": p0, "ratio": r0}, "at": {}}
        for c in CUTOFFS:
            if c < ref:
                row["at"][c.isoformat()] = {"note": "before the step"}; continue
            try:
                r = cc.wiki_test(arts, ref, lag, today=c)
            except Exception as e:  # noqa: BLE001
                row["at"][c.isoformat()] = {"error": str(e)[:120]}; continue
            grade = "measured" if r.get("p") is not None and r["p"] <= 0.05 else ("no sustained rise" if r.get("result") else "within chance" if r.get("p") is not None else "no p")
            row["at"][c.isoformat()] = {"p": r.get("p"), "ratio": r.get("ratio"), "n_placebo": r.get("n_placebo"), "onset": r.get("onset"), "grade": grade,
                                        "complete_window": (ref + dt.timedelta(days=lag + 30)) <= c - dt.timedelta(days=2)}
        grades = {k: v.get("grade") for k, v in row["at"].items() if v.get("grade")}
        row["holds"] = len(set(grades.values())) <= 1
        flips += 0 if row["holds"] else 1
        out["steps"].append(row)
        print(slug, n, grades, "holds" if row["holds"] else "FLIPS", flush=True)
    out["summary"] = {"steps": len(rows), "flips": flips, "verdict": "grades hold; drift is a theory" if flips < 3 else "three or more flipped; a grade needs a history"}
    os.makedirs(os.path.join(ROOT, "docs", "results"), exist_ok=True)
    json.dump(out, open(os.path.join(ROOT, "docs", "results", "truncation_v1.json"), "w"), indent=1)
    print(out["summary"])
    return 0

if __name__ == "__main__":
    sys.exit(main())
