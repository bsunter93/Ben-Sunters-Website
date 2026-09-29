"""Reader paths from the Wikipedia Clickstream (ripples/docs/clickstream_protocol_v1.md, ledger 1462).

Fetch: each monthly English file (dumps.wikimedia.org/other/clickstream/YYYY-MM/clickstream-enwiki-YYYY-MM.tsv.gz)
is streamed once, one file at a time, with an honest User-Agent. Only rows whose source or target is a focus title are
kept ($LAB_CACHE/clickstream/YYYY-MM.tsv); the full file is never stored. 403/429/503 stops the run (no retry); a 404 is
recorded as a missing month. Rows in the source files already carry Wikimedia's own floor (pairs with >= 10 clicks).

Analysis (registered): A. Super Bowl -> numerals mechanism (Q5 test 3); B. per-event reader paths for five named
ripples. Descriptive: no p-values, no pass/fail beyond the registered "supporting" rules.
"""
from __future__ import annotations

import collections
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
BASE = "https://dumps.wikimedia.org/other/clickstream/{m}/clickstream-enwiki-{m}.tsv.gz"
CACHE = os.path.join(os.environ.get("LAB_CACHE", ".cult-cache"), "clickstream")

SB_GAMES = {2018: "Super_Bowl_LII", 2019: "Super_Bowl_LIII", 2020: "Super_Bowl_LIV", 2021: "Super_Bowl_LV",
            2022: "Super_Bowl_LVI", 2023: "Super_Bowl_LVII", 2024: "Super_Bowl_LVIII", 2025: "Super_Bowl_LIX",
            2026: "Super_Bowl_LX"}
NUMERALS = ["Roman_numerals", "Arabic_numerals"]
# Comparison month for each February: August of the same year (2026: August 2025, the latest before it).
SB_COMPARE = {y: f"{min(y, 2025)}-08" for y in SB_GAMES}

# Per-event reader paths: (event article, outcome, pre month, event months). Outcomes are the named subjects already
# tested (Q4 subjects; screen v2 space -> Speed of light confirmation).
EVENTS = [
    ("The_Queen's_Gambit_(miniseries)", "Chess", "2020-09", ["2020-10", "2020-11", "2020-12"]),
    ("Chernobyl_(miniseries)", "Chernobyl_disaster", "2019-04", ["2019-05", "2019-06"]),
    ("Parker_Solar_Probe", "Speed_of_light", "2018-07", ["2018-08"]),
    ("Voyager_2", "Speed_of_light", "2018-11", ["2018-12"]),
    ("Artemis_I", "Speed_of_light", "2022-10", ["2022-11"]),
    ("Chandrayaan-3", "Speed_of_light", "2023-07", ["2023-08"]),
]


class Stop(Exception):
    pass


def months() -> list[str]:
    ms = {f"{y}-02" for y in SB_GAMES} | set(SB_COMPARE.values())
    for _, _, pre, evm in EVENTS:
        ms |= {pre, *evm}
    return sorted(ms)


def focus() -> set[str]:
    f = {"Super_Bowl", *SB_GAMES.values(), *NUMERALS}
    for ev, out, _, _ in EVENTS:
        f |= {ev, out}
    return f


def status(url: str) -> int:
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code


def fetch(m: str, fset: set[str]) -> str:
    out = os.path.join(CACHE, f"{m}.tsv")
    if os.path.exists(out):
        return "cached"
    url = BASE.format(m=m)
    code = status(url)
    if code in (403, 429, 503):
        raise Stop(f"{m}: HTTP {code}")
    if code == 404:
        return "missing"
    if code != 200:
        return f"http {code}"
    ffile = os.path.join(CACHE, "focus.txt")
    open(ffile, "w").write("\n".join(sorted(fset)) + "\n")
    tmp = out + ".part"
    cmd = (f"curl -fsS --retry 0 -A '{UA}' '{url}' | gzip -dc | "
           f"awk -F'\\t' 'NR==FNR{{f[$0];next}} ($1 in f)||($2 in f)' '{ffile}' - > '{tmp}'")
    r = subprocess.run(["bash", "-o", "pipefail", "-c", cmd], capture_output=True, text=True)
    if r.returncode != 0:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise Stop(f"{m}: stream failed ({r.returncode}) {r.stderr.strip()[:200]}")
    os.replace(tmp, out)
    return "fetched"


def load(m: str):
    """Rows (prev, curr, type, n) for month m, or None if the month is not available."""
    p = os.path.join(CACHE, f"{m}.tsv")
    if not os.path.exists(p):
        return None
    rows = []
    for line in open(p, encoding="utf-8"):
        a = line.rstrip("\n").split("\t")
        if len(a) == 4 and a[3].isdigit():
            rows.append((a[0], a[1], a[2], int(a[3])))
    return rows


def clicks(rows, prev, curr) -> int:
    return sum(n for p, c, _, n in rows if p == prev and c == curr)


def inbound(rows, curr) -> collections.Counter:
    c = collections.Counter()
    for p, q, _, n in rows:
        if q == curr:
            c[p] += n
    return c


def outbound(rows, prev) -> collections.Counter:
    c = collections.Counter()
    for p, q, t, n in rows:
        if p == prev and t == "link":
            c[q] += n
    return c


def superbowl(data) -> dict:
    res = {"years": [], "note": "Clickstream lists only pairs with >= 10 clicks in the month; absent means < 10."}
    support = {o: 0 for o in NUMERALS}
    usable = 0
    for y, game in SB_GAMES.items():
        feb, cmp_m = f"{y}-02", SB_COMPARE[y]
        F, A = data.get(feb), data.get(cmp_m)
        row = {"year": y, "game": game, "feb": feb, "compare": cmp_m}
        if F is None or A is None:
            row["skip"] = "month missing"
            res["years"].append(row)
            continue
        usable += 1
        for o in NUMERALS:
            f = clicks(F, game, o) + clicks(F, "Super_Bowl", o)
            a = clicks(A, game, o) + clicks(A, "Super_Bowl", o)
            ok = f >= 10 and a <= f / 4
            support[o] += ok
            inf, ina = inbound(F, o), inbound(A, o)
            sb_share = sum(v for k, v in inf.items() if k.startswith("Super_Bowl")) / max(1, sum(inf.values()))
            row[o] = {"feb_from_super_bowl": f, "compare_from_super_bowl": a, "supports": bool(ok),
                      "feb_inbound_total": sum(inf.values()), "compare_inbound_total": sum(ina.values()),
                      "feb_share_from_super_bowl_articles": round(sb_share, 4),
                      "feb_from_search": inf.get("other-search", 0), "compare_from_search": ina.get("other-search", 0),
                      "feb_top_referrers": inf.most_common(12), "compare_top_referrers": ina.most_common(12)}
        row["roman_to_arabic"] = {"feb": clicks(F, "Roman_numerals", "Arabic_numerals"),
                                  "compare": clicks(A, "Roman_numerals", "Arabic_numerals")}
        row["game_outbound_top"] = outbound(F, game).most_common(20)
        res["years"].append(row)
    res["years_usable"] = usable
    res["years_supporting"] = support
    res["verdict_roman"] = ("supporting" if usable and support["Roman_numerals"] >= max(1, (2 * usable + 2) // 3)
                            else "not supporting" if usable else "not run")
    return res


def events(data) -> list:
    out = []
    for ev, oc, pre, evm in EVENTS:
        P = data.get(pre)
        row = {"event": ev, "outcome": oc, "pre": pre, "months": []}
        if P is None:
            row["skip"] = "pre month missing"
            out.append(row)
            continue
        pin = inbound(P, oc)
        for m in evm:
            M = data.get(m)
            if M is None:
                row["months"].append({"month": m, "skip": "missing"})
                continue
            min_ = inbound(M, oc)
            growth = {k: min_.get(k, 0) - pin.get(k, 0) for k in set(min_) | set(pin)}
            d_total = sum(min_.values()) - sum(pin.values())
            direct = clicks(M, ev, oc)
            row["months"].append({
                "month": m, "event_to_outcome": direct, "direct_path": bool(direct >= 10),
                "outcome_inbound": sum(min_.values()), "outcome_inbound_pre": sum(pin.values()),
                "outcome_inbound_change": d_total,
                "share_of_change_direct": round(direct / d_total, 4) if d_total > 0 else None,
                "outcome_from_search": min_.get("other-search", 0), "outcome_from_search_pre": pin.get("other-search", 0),
                "top_growing_referrers": sorted(growth.items(), key=lambda kv: -kv[1])[:12],
                "event_outbound_top": outbound(M, ev).most_common(25),
                "event_inbound_total": sum(inbound(M, ev).values())})
        out.append(row)
    return out


def main() -> int:
    os.makedirs(CACHE, exist_ok=True)
    fset = focus()
    report = {"protocol": "ripples/docs/clickstream_protocol_v1.md", "ledger": 1462, "source": BASE,
              "focus_titles": sorted(fset), "fetch": {}}
    try:
        for m in months():
            s = fetch(m, fset)
            report["fetch"][m] = s
            print(f"{m}: {s}", flush=True)
    except Stop as e:
        report["stopped"] = str(e)
        print(f"stopped: {e}", flush=True)
    data = {m: load(m) for m in months()}
    data = {m: r for m, r in data.items() if r is not None}
    report["superbowl_numerals"] = superbowl(data)
    report["event_paths"] = events(data)
    txt = json.dumps(report, indent=1)
    open(os.environ.get("CS_OUT", "clickstream_paths_v1.json"), "w").write(txt)
    print(txt[:20000], flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
