"""Ripple Map prototype (exploratory; ripples/docs/cs_ripples_explore.md, ledger 1466): ripple maps from the full
monthly English Wikipedia Clickstream.

Fetch (mode "fetch"): every monthly file from 2017-11 is streamed once, one at a time, honest User-Agent; only pairs with
at least MIN_N clicks are kept ($LAB_CACHE/csall/YYYY-MM.tsv.gz). 403/429/503 stops (no retry); 404 = month missing.
Resumable: months already cached are skipped; --budget-min stops fetching before the job's time limit.

Analyze (mode "analyze"): for each month m, against the median of the 6 months before it (absent = below MIN_N):
  event    A: an article whose total arrivals are >= EV_X times its baseline and >= EV_MIN;
  ripple A->B: a link A->B with >= EDGE_MIN clicks in m and >= EDGE_X times its own baseline (+100), where B's arrivals
           rose too (>= B_X times baseline);
  carried: the share of B's extra arrivals that came straight from A;
  surprise: 1 - overlap between A's neighbors this month and B's usual neighbors (baseline months), so a ripple into
           a part of Wikipedia the event's readers do not normally visit scores high;
  ring 2:  B->C links that surged the same month into an article A does not link to.
Output: ripples/docs/results/map/index.json and one file per month (top events with their maps, top ripples overall).
Exploratory: nothing here is a confirmed ripple. Candidates are confirmed later on held-out months with the timing test.
"""
from __future__ import annotations

import collections
import gzip
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
BASE = "https://dumps.wikimedia.org/other/clickstream/{m}/clickstream-enwiki-{m}.tsv.gz"
CACHE = os.path.join(os.environ.get("LAB_CACHE", ".cs-cache"), "csall")
MIN_N = 200
BASE_MONTHS = 6
EV_X, EV_MIN = 4.0, 60000
EDGE_MIN, EDGE_X, B_X = 1000, 3.0, 1.5
TOP_EVENTS, RING1, RING2 = 30, 15, 4
SKIP = re.compile(r"^(other-|Main_Page$|-$|Special:|Deaths_in_|\d{4}$|(January|February|March|April|May|June|July|August|"
                  r"September|October|November|December)_\d{1,2}$|List_of_|Portal:|Wikipedia:|Help:|File:|Template:)")


class Stop(Exception):
    pass


# Discovery-funnel prototype (owner direction 2026-09-29): a few culturally salient events, all in exploration months.
FUNNEL_V1 = [("The_Queen's_Gambit_(miniseries)", "2020-11"), ("Chernobyl_(miniseries)", "2019-05"),
             ("James_Webb_Space_Telescope", "2022-07"), ("ChatGPT", "2022-12")]
# v2 (ledger 1468): four new events of different kinds, all in exploration months; alternate titles are tried and the
# one with most arrivals that month is used (article titles at the time can differ from today's).
FUNNEL_EVENTS = [("2020_Beirut_explosion|2020_Beirut_explosions", "2020-08"),
                 ("GameStop_short_squeeze|2021_GameStop_short_squeeze", "2021-01"),
                 ("Wordle", "2022-01"), ("2020_Summer_Olympics", "2021-07")]
F_EDGE_MIN, F_EDGE_X, F_B_X, F_HOPS, F_KIDS, F_ROOT_KIDS = 300, 3.0, 1.2, 3, 6, 12


def shift(m, k):
    y, mo = map(int, m.split("-"))
    t = y * 12 + (mo - 1) + k
    return f"{t // 12}-{t % 12 + 1:02d}"


def window_months(m0):
    return [shift(m0, k) for k in range(-BASE_MONTHS, 2)]


def months(first="2017-11", last="2026-08"):
    y, m = map(int, first.split("-"))
    ly, lm = map(int, last.split("-"))
    out = []
    while (y, m) <= (ly, lm):
        out.append(f"{y}-{m:02d}")
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)
    return out


def status(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code


def fetch(budget_min: float) -> dict:
    os.makedirs(CACHE, exist_ok=True)
    t0, log = time.time(), {}
    pri = sorted({mm for _, m0 in FUNNEL_EVENTS for mm in window_months(m0)})
    for m in pri + [x for x in months() if x not in pri]:
        out = os.path.join(CACHE, f"{m}.tsv.gz")
        if os.path.exists(out) or os.path.exists(out + ".missing"):
            continue
        if (time.time() - t0) / 60 > budget_min:
            log["budget"] = f"stopped at {m} (time budget)"
            break
        url = BASE.format(m=m)
        code = status(url)
        if code in (403, 429, 503):
            raise Stop(f"{m}: HTTP {code}")
        if code == 404:
            open(out + ".missing", "w").close()
            log[m] = "missing"
            continue
        tmp = out + ".part"
        cmd = (f"curl -fsS --retry 0 -A '{UA}' '{url}' | gzip -dc | "
               f"awk -F'\\t' '$4+0 >= {MIN_N}' | gzip -1 > '{tmp}'")
        r = subprocess.run(["bash", "-o", "pipefail", "-c", cmd], capture_output=True, text=True)
        if r.returncode != 0:
            if os.path.exists(tmp):
                os.remove(tmp)
            raise Stop(f"{m}: stream failed ({r.returncode}) {r.stderr.strip()[:200]}")
        os.replace(tmp, out)
        log[m] = "fetched"
        print(f"{m}: fetched ({os.path.getsize(out) // 1_000_000} MB)", flush=True)
    return log


def load(m):
    p = os.path.join(CACHE, f"{m}.tsv.gz")
    if not os.path.exists(p):
        return None
    inb, edges = collections.Counter(), {}
    with gzip.open(p, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            a = line.rstrip("\n").split("\t")
            if len(a) != 4:
                continue
            prev, curr, typ, n = a[0], a[1], a[2], int(a[3])
            inb[curr] += n
            if typ == "link" and not SKIP.match(prev) and not SKIP.match(curr):
                edges[(prev, curr)] = n
    out = collections.defaultdict(dict)
    for (p_, c), n in edges.items():
        out[p_][c] = n
    return {"in": inb, "out": dict(out)}


def median(xs):
    xs = sorted(xs)
    k = len(xs)
    return 0.0 if not k else (xs[k // 2] if k % 2 else 0.5 * (xs[k // 2 - 1] + xs[k // 2]))


def neighbors(month_data, title, k=60):
    """Top linked destinations of title plus its top internal referrers, in one month."""
    outs = month_data["out"].get(title, {})
    top = sorted(outs, key=outs.get, reverse=True)[:k]
    return set(top)


def analyze(outdir: str) -> dict:
    ms = [m for m in months() if os.path.exists(os.path.join(CACHE, f"{m}.tsv.gz"))]
    os.makedirs(outdir, exist_ok=True)
    window, index = collections.deque(maxlen=BASE_MONTHS), []
    # reverse index for baseline neighbors of B: who linked to B (internal referrers), per month
    for m in ms:
        cur = load(m)
        if cur is None:
            continue
        if len(window) < 3:
            window.append(cur)
            continue
        base_in = lambda t: median([w["in"].get(t, 0) for w in window])  # noqa: E731
        base_edge = lambda a, b: median([w["out"].get(a, {}).get(b, 0) for w in window])  # noqa: E731
        # referrers of B in baseline months (B's usual neighborhood)
        events = []
        for a, n in cur["in"].most_common(4000):
            if SKIP.match(a) or n < EV_MIN:
                continue
            b0 = base_in(a)
            if n >= EV_X * max(b0, MIN_N):
                events.append((a, n, b0))
        events.sort(key=lambda e: -e[1])
        month_events, all_edges = [], []
        for a, n, b0 in events[:TOP_EVENTS * 3]:
            outs = cur["out"].get(a, {})
            nb_a = neighbors(cur, a) | {a}
            ring = []
            for b, c in sorted(outs.items(), key=lambda kv: -kv[1]):
                if c < EDGE_MIN:
                    break
                e0 = base_edge(a, b)
                if c < EDGE_X * (e0 + 100):
                    continue
                bin_, bb0 = cur["in"].get(b, 0), base_in(b)
                if bin_ < B_X * max(bb0, MIN_N):
                    continue
                nb_b = set()
                for w in window:
                    ob = w["out"].get(b, {})
                    nb_b |= set(sorted(ob, key=ob.get, reverse=True)[:30])
                surprise = None
                if nb_b:
                    nb_b.add(b)
                    inter = len((nb_a - {b}) & nb_b)
                    surprise = 1.0 - inter / max(1, min(len(nb_a), len(nb_b)))
                    if e0 > 0 or a in nb_b:  # readers already went this way before the event
                        surprise *= 0.5
                extra = bin_ - bb0
                ring.append({"to": b, "clicks": c, "base": round(e0), "to_arrivals": bin_, "to_base": round(bb0),
                             "carried": round(min(1.0, c / extra), 3) if extra > 0 else None,
                             "surprise": None if surprise is None else round(surprise, 3)})
            if not ring:
                continue
            ring = ring[:RING1]
            for r1 in ring:
                r2 = []
                for c2, n2 in sorted(cur["out"].get(r1["to"], {}).items(), key=lambda kv: -kv[1]):
                    if n2 < EDGE_MIN // 2:
                        break
                    if c2 == a or c2 in outs:
                        continue
                    if n2 < EDGE_X * (base_edge(r1["to"], c2) + 100):
                        continue
                    if cur["in"].get(c2, 0) < B_X * max(base_in(c2), MIN_N):
                        continue
                    r2.append({"to": c2, "clicks": n2})
                    if len(r2) >= RING2:
                        break
                if r2:
                    r1["ring2"] = r2
            ev = {"event": a, "arrivals": n, "base": round(b0), "ring1": ring}
            month_events.append(ev)
            for r in ring:
                all_edges.append({"from": a, **{k: v for k, v in r.items() if k != "ring2"}})
            if len(month_events) >= TOP_EVENTS:
                break
        top = sorted([e for e in all_edges if e["surprise"] is not None],
                     key=lambda e: -(e["surprise"] * (e["carried"] or 0) ** 0.5 * min(1, e["clicks"] / 5000)))[:40]
        json.dump({"month": m, "events": month_events, "top_surprising": top},
                  open(os.path.join(outdir, f"{m}.json"), "w"), ensure_ascii=False, separators=(",", ":"))
        index.append({"month": m, "events": len(month_events), "ripples": len(all_edges)})
        print(f"{m}: {len(month_events)} events, {len(all_edges)} ripples", flush=True)
        window.append(cur)
    idx = {"version": "cs_ripples v0 (exploratory)", "ledger": 1466, "months": index,
           "settings": {"min_n": MIN_N, "base_months": BASE_MONTHS, "ev_x": EV_X, "ev_min": EV_MIN,
                        "edge_min": EDGE_MIN, "edge_x": EDGE_X, "b_x": B_X}}
    json.dump(idx, open(os.path.join(outdir, "index.json"), "w"), indent=1)
    return idx


# Wikidata typing (v1): cast and crew of a work are expected destinations by construction, so they are discounted and
# not expanded (their filmographies are obvious). Occupations: actor, film/TV/stage/voice actor, director, screenwriter,
# producer, showrunner, comedian, presenter, model, singer, musician.
CREW_OCC = {"Q33999", "Q10800557", "Q10798782", "Q2259451", "Q2405480", "Q2526255", "Q3455803", "Q28389", "Q3282637",
            "Q578109", "Q947873", "Q245068", "Q13590141", "Q4610556", "Q177220", "Q639669", "Q3387717", "Q1053574"}
WORK_P31 = {"Q11424", "Q5398426", "Q1259759", "Q21191270", "Q7725634", "Q24856", "Q202866", "Q1261214", "Q7889"}
# v2: destinations the owner called "material" (things in the world people use or are affected by), by direct P31:
# companies and organizations, brands and products, software and apps, technologies, industries, chemicals, drugs,
# laws, currencies, commodities, foods, sports, websites, professions, games and toys.
MATERIAL_P31 = {"Q4830453", "Q783794", "Q891723", "Q6881511", "Q43229", "Q163740", "Q431289", "Q2424752", "Q10929058",
                "Q7397", "Q620615", "Q11016", "Q8148", "Q268592", "Q11173", "Q79529", "Q113145171", "Q7748",
                "Q820655", "Q8142", "Q13479982", "Q11691", "Q317088", "Q12140", "Q2095", "Q746549", "Q349",
                "Q35127", "Q3220391", "Q28640", "Q12737077", "Q131436", "Q11422", "Q11446", "Q17210"}
WD = "https://www.wikidata.org/w/api.php"
_WD_CACHE = {}


def wd_kinds(titles):
    """Kind per enwiki title: 'crew' (a person whose occupation is acting/directing/producing etc.), 'person', 'work'
    (film, series, episode, novel, game), or 'other'. Batched wbgetentities (50 per request), honest UA, 1 s apart,
    cached; a refusal leaves kinds unknown (None) rather than stopping the map."""
    path = os.path.join(os.path.dirname(CACHE), "wd_kinds_v2.json")
    if not _WD_CACHE and os.path.exists(path):
        _WD_CACHE.update(json.load(open(path)))
    todo = [t for t in titles if t not in _WD_CACHE]
    for i in range(0, len(todo), 50):
        batch = todo[i:i + 50]
        q = urllib.parse.urlencode({"action": "wbgetentities", "sites": "enwiki", "props": "claims|sitelinks",
                                    "sitefilter": "enwiki", "format": "json",
                                    "titles": "|".join(t.replace("_", " ") for t in batch)})
        req = urllib.request.Request(f"{WD}?{q}", headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.load(r)
        except Exception as e:  # noqa: BLE001
            print(f"wikidata: {str(e)[:120]}", flush=True)
            break
        for ent in data.get("entities", {}).values():
            t = ent.get("sitelinks", {}).get("enwiki", {}).get("title")
            if not t:
                continue
            cl = ent.get("claims", {})
            ids = lambda p: {c.get("mainsnak", {}).get("datavalue", {}).get("value", {}).get("id") for c in cl.get(p, [])}  # noqa: E731
            p31, occ = ids("P31"), ids("P106")
            kind = ("crew" if occ & CREW_OCC else "person") if "Q5" in p31 else \
                ("work" if p31 & WORK_P31 else "material" if p31 & MATERIAL_P31 else "other")
            _WD_CACHE[t.replace(" ", "_")] = {"kind": kind, "p31": sorted(x for x in p31 if x)}
        for t in batch:
            _WD_CACHE.setdefault(t, {"kind": "other", "p31": []})
        time.sleep(1)
    try:
        json.dump(_WD_CACHE, open(path, "w"))
    except OSError:
        pass
    return {t: _WD_CACHE.get(t) for t in titles}


def out_totals(md):
    return {a: sum(v.values()) for a, v in md["out"].items()}


def funnel(outdir: str) -> dict:
    """Event -> unusual 1-hop destinations -> their unusual destinations (up to F_HOPS), ranked by surprise
    (observed minus expected clicks) and a weirdness priority score, not by size. Exploratory."""
    os.makedirs(outdir, exist_ok=True)
    res = {"version": "funnel v2 (exploratory; material endpoints up, people endpoints and same-kind hops down, "
                      "cross-field weighted)", "ledger": 1468, "events": []}
    for evs, m0 in FUNNEL_EVENTS:
        mons = {m: load(m) for m in window_months(m0)}
        base = [mons[m] for m in window_months(m0)[:BASE_MONTHS] if mons.get(m)]
        cur, nxt = mons.get(m0), mons.get(shift(m0, 1))
        if cur is None or len(base) < 3:
            res["events"].append({"event": evs, "month": m0, "skip": "months missing"})
            continue
        ev = max(evs.split("|"), key=lambda t: cur["in"].get(t, 0))
        cur_tot, base_tot = out_totals(cur), [out_totals(b) for b in base]
        bin_ = lambda t: median([b["in"].get(t, 0) for b in base])  # noqa: E731
        bedge = lambda a, c: median([b["out"].get(a, {}).get(c, 0) for b in base])  # noqa: E731
        surging = {t for t, n in cur["in"].items() if n >= F_B_X * MIN_N and n >= F_B_X * bin_(t)}
        referrers = collections.defaultdict(list)  # surging child -> baseline shares from each referrer
        for b, bt in zip(base, base_tot):
            for a, outs in b["out"].items():
                t = bt.get(a, 0)
                if t:
                    for c, n in outs.items():
                        if c in surging:
                            referrers[c].append(n / t)
        hub = lambda c: median(referrers.get(c, [])) if referrers.get(c) else 0.0  # noqa: E731

        def nbhd(md_list, t, k=40):
            s_ = set()
            for md in md_list:
                o = md["out"].get(t, {})
                s_ |= set(sorted(o, key=o.get, reverse=True)[:k])
            return s_ | {t}

        nodes, edges, seen = {ev: {"hop": 0, "arrivals": cur["in"].get(ev, 0), "base": round(bin_(ev))}}, [], {ev}
        frontier = [ev]
        for hop in range(1, F_HOPS + 1):
            nxt_frontier = []
            for a in frontier:
                a_nb = nbhd([cur], a) | nbhd(base, a)
                p0tot = median([bt.get(a, 0) for bt in base_tot])
                cands = []
                for c, n in cur["out"].get(a, {}).items():
                    if n < F_EDGE_MIN or c in seen:
                        continue
                    e0 = bedge(a, c)
                    if n < F_EDGE_X * (e0 + 50):
                        continue
                    cin, cb = cur["in"].get(c, 0), bin_(c)
                    if cin < F_B_X * max(cb, MIN_N):
                        continue
                    p0 = e0 / p0tot if p0tot else 0.0
                    tot = cur_tot.get(a, 0) or 1
                    s0 = max(p0, hub(c))  # expected share of a's outgoing clicks that c receives
                    expected = tot * s0
                    surprise = float(__import__("math").log2((n / tot + 0.001) / (s0 + 0.001)))
                    c_nb = nbhd(base, c)
                    overlap = len((a_nb - {c}) & c_nb) / max(1, min(len(a_nb), len(c_nb))) if len(c_nb) > 1 else None
                    distance = None if overlap is None else round(1 - overlap, 3)
                    spec = None
                    if nxt is not None:
                        spec = round(cin / max(cb, nxt["in"].get(c, 0), 1), 2)
                    weird = max(0.0, surprise) * (1 + 0.5 * (hop - 1)) * (0.25 + 1.5 * (distance if distance is not None else 0.5)) \
                        * (min(2.0, spec) / 2 if spec is not None else 0.5)
                    cands.append({"from": a, "to": c, "hop": hop, "clicks": n, "base_clicks": round(e0),
                                  "expected": round(expected), "surprise": round(surprise, 2), "distance": distance,
                                  "to_arrivals": cin, "to_base": round(cb), "specificity": spec,
                                  "carried": round(min(1.0, n / (cin - cb)), 3) if cin > cb else None,
                                  "weirdness": round(weird, 3)})
                info = wd_kinds([e["to"] for e in cands] + [a])
                pa = set((info.get(a) or {}).get("p31", []))
                for e in cands:
                    ci = info.get(e["to"]) or {}
                    e["kind"] = ci.get("kind")
                    f = 1.0
                    if e["kind"] == "crew":
                        f *= 0.2
                    if pa & set(ci.get("p31", [])):  # same kind of thing as its parent (galaxy -> galaxy, person -> person)
                        f *= 0.4
                        e["same_kind"] = True
                    if e["kind"] == "material":
                        f *= 2.0
                    e["weirdness"] = round(e["weirdness"] * f, 3)
                cands.sort(key=lambda e: -e["weirdness"])
                for e in cands[:F_ROOT_KIDS if hop == 1 else F_KIDS]:
                    edges.append(e)
                    seen.add(e["to"])
                    nodes[e["to"]] = {"hop": hop, "arrivals": e["to_arrivals"], "base": e["to_base"], "kind": e["kind"]}
                    if e["kind"] != "crew":
                        nxt_frontier.append(e["to"])
            frontier = nxt_frontier
        # candidate paths: root -> ... -> node, scored by mean weirdness with a length bonus
        parent = {e["to"]: e for e in edges}
        paths = []
        for e in edges:
            chain, x = [e], e
            while x["from"] in parent:
                x = parent[x["from"]]
                chain.append(x)
            chain.reverse()
            score = sum(c["weirdness"] for c in chain) / len(chain) * (1 + 0.3 * (len(chain) - 1))
            end = chain[-1].get("kind")
            if end in ("person", "crew"):  # a single person as the endpoint is rarely the ripple
                score *= 0.2
            if len(chain) == 1:
                score *= 0.6
            paths.append({"path": [ev] + [c["to"] for c in chain], "score": round(score, 3),
                          "min_surprise": min(c["surprise"] for c in chain)})
        paths.sort(key=lambda p: -p["score"])
        picked, per_prefix = [], collections.Counter()
        for p_ in paths:  # at most 2 paths per shared prefix, none ending on cast/crew
            if nodes.get(p_["path"][-1], {}).get("kind") == "crew":
                continue
            key = tuple(p_["path"][:-1])
            if per_prefix[key] >= 2:
                continue
            per_prefix[key] += 1
            picked.append(p_)
        res["events"].append({"event": ev, "month": m0, "nodes": nodes, "edges": edges, "top_paths": picked[:10],
                              "biggest_by_clicks": sorted(edges, key=lambda e: -e["clicks"])[:5]})
        print(f"{ev} {m0}: {len(edges)} edges; top path {paths[0]['path'] if paths else None}", flush=True)
    json.dump(res, open(os.path.join(outdir, "funnel_v2.json"), "w"), ensure_ascii=False, indent=1)
    return res


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "fetch"
    if mode == "fetch":
        budget = float(sys.argv[2]) if len(sys.argv) > 2 else 300
        try:
            print(json.dumps(fetch(budget)), flush=True)
        except Stop as e:
            print(f"stopped: {e}", flush=True)
        return 0
    if mode == "funnel":
        funnel(sys.argv[2] if len(sys.argv) > 2 else "map")
        return 0
    analyze(sys.argv[2] if len(sys.argv) > 2 else "map")
    return 0


if __name__ == "__main__":
    sys.exit(main())
