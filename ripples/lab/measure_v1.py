"""Measure v1: re-test the ladder's two marks under the standard test v2, then run the outcome-first scan on the two
highest-power behavior series that were reachable on Oct 5, 2026 (CDC WONDER monthly deaths; NPS monthly park visits).
Pre-registered in ripples/docs/measure_plan_v1.md before any outcome value was fetched. Stones, pools and groups are in
ripples/lab/measure_registry.py; the test is ripples/lab/ladder2.py.

Network: honest UA, at least 1.1 s between requests (2 minutes between CDC WONDER queries, as WONDER asks), and a host is
stopped for the run on any 4xx or 5xx (the ladder's fetcher), with no retry and no other agent. Hosts that refused earlier
the same day are passed in LADDER_SKIP_HOSTS and are never called.
CDC WONDER: the owner accepted the data use restrictions on Oct 5, 2026; every query sends accept_datause_restrictions=true.
Only national aggregate counts are requested (the API allows nothing else), any published count of 9 or fewer is withheld,
and nothing here tries to identify anyone. Output: ripples/docs/results/measure_v1.json.
MEASURE_DRY=1 runs the whole pipeline on synthetic series with no network call (used to test the code before registration).
"""
from __future__ import annotations

import datetime as dt
import json
import math
import os
import re
import sys
import time
import urllib.parse
import xml.etree.ElementTree as ET

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import ladder as L  # noqa: E402
import ladder2 as V  # noqa: E402
import measure_registry as R  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.environ.get("MEASURE_OUT") or os.path.join(ROOT, "docs", "results", "measure_v1.json")
WIKI = os.path.join(ROOT, "demo", "discovered_wiki.json")
DRY = os.environ.get("MEASURE_DRY") == "1"
D = dt.date.fromisoformat

WONDER_URL = "https://wonder.cdc.gov/controller/datarequest/D76"
WONDER_GAP = float(os.environ.get("WONDER_GAP", "120"))
NPS_URL = "https://irmaservices.nps.gov/v3/rest/stats/visitation?unitCodes={u}&startMonth=1&startYear=1979&endMonth=12&endYear=2024"
NPS_TOTAL_URL = "https://irmaservices.nps.gov/v3/rest/stats/total/{y}"
SHUTDOWN_MONTHS = {"1995-11", "1995-12", "1996-01", "2013-10", "2018-12", "2019-01"}  # federal shutdowns: NaN in NPS series
SUPPRESS_MAX = 9  # CDC data use restrictions: never present a count of nine or fewer deaths


def months(a, b):
    y, m = a
    out = []
    while (y, m) <= b:
        out.append(f"{y}-{m:02d}")
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)
    return out


def monthly(vals, labels, nan_months=()):
    dates = [dt.date(int(x[:4]), int(x[5:7]), 1) for x in labels]
    v = [(vals.get(x) if (vals.get(x) or 0) > 0 and x not in nan_months else np.nan) for x in labels]
    return L.Series(dates, v, [L.month_excluded(d) for d in dates], period_days=31, seasonal=True, labels=labels)


def suppress(n):
    if n is None or (isinstance(n, float) and not np.isfinite(n)):
        return None
    return int(round(n)) if n > SUPPRESS_MAX else "suppressed (9 or fewer)"


# ---------------------------------------------------------------- CDC WONDER
WONDER_LAST = [0.0]


def wonder_xml(ages, by_mechanism, title):
    p = [("B_1", ["D76.V1-level2"]), ("B_2", ["D76.V23" if by_mechanism else "*None*"]), ("B_3", ["*None*"]), ("B_4", ["*None*"]),
         ("B_5", ["*None*"])]
    for v in ("V1", "V10", "V2", "V25", "V27", "V9"):
        p.append((f"F_D76.{v}", ["*All*"]))
    p += [("I_D76.V1", ["*All* (All Dates)"]), ("I_D76.V10", ["*All* (The United States)"]), ("I_D76.V2", ["*All* (All Causes of Death)"]),
          ("I_D76.V25", ["All Causes of Death"]), ("I_D76.V27", ["*All* (The United States)"]), ("I_D76.V9", ["*All* (The United States)"]),
          ("M_1", ["D76.M1"]), ("M_2", ["D76.M2"]), ("M_3", ["D76.M3"])]
    for v in ("V10", "V1", "V25", "V27", "V2", "V9"):
        p.append((f"O_{v}_fmode", ["freg"]))
    p += [("O_aar", ["aar_none"]), ("O_aar_pop", ["0000"]), ("O_age", ["D76.V52" if ages else "D76.V5"]), ("O_javascript", ["on"]),
          ("O_location", ["D76.V9"]), ("O_oc-sect1-request", ["close"]), ("O_precision", ["1"]), ("O_rate_per", ["100000"]),
          ("O_show_totals", ["false"]), ("O_show_zeros", ["true"]), ("O_show_suppressed", ["true"]), ("O_timeout", ["600"]),
          ("O_title", [title]), ("O_ucd", ["D76.V22"]), ("O_urban", ["D76.V19"]),
          ("VM_D76.M6_D76.V10", [""]), ("VM_D76.M6_D76.V17", ["*All*"]), ("VM_D76.M6_D76.V1_S", ["*All*"]), ("VM_D76.M6_D76.V7", ["*All*"]),
          ("VM_D76.M6_D76.V8", ["*All*"]), ("V_D76.V1", [""]), ("V_D76.V10", [""]), ("V_D76.V11", ["*All*"]), ("V_D76.V12", ["*All*"]),
          ("V_D76.V17", ["*All*"]), ("V_D76.V19", ["*All*"]), ("V_D76.V2", [""]), ("V_D76.V20", ["*All*"]), ("V_D76.V21", ["*All*"]),
          ("V_D76.V22", ["2"]), ("V_D76.V23", ["*All*"]), ("V_D76.V24", ["*All*"]), ("V_D76.V25", [""]), ("V_D76.V27", [""]),
          ("V_D76.V4", ["*All*"]), ("V_D76.V5", ["*All*"]), ("V_D76.V51", ["*All*"]), ("V_D76.V52", [str(a) for a in ages] if ages else ["*All*"]),
          ("V_D76.V6", ["00"]), ("V_D76.V7", ["*All*"]), ("V_D76.V8", ["*All*"]), ("V_D76.V9", [""]),
          ("accept_datause_restrictions", ["true"]), ("action-Send", ["Send"]), ("dataset_code", ["D76"]),
          ("dataset_label", ["Underlying Cause of Death, 1999-2020"]), ("dataset_vintage", ["2020"])]
    for v in ("V1", "V10", "V2", "V25", "V27", "V9"):
        p.append((f"finder-stage-D76.{v}", ["codeset"]))
    p += [("saved_id", [""]), ("stage", ["request"])]
    root = ET.Element("request-parameters")
    for name, vals in p:
        e = ET.SubElement(root, "parameter")
        ET.SubElement(e, "name").text = name
        for v in vals:
            ET.SubElement(e, "value").text = v
    return "<?xml version='1.0' encoding='utf-8'?>" + ET.tostring(root, encoding="unicode")


MON = {m: i + 1 for i, m in enumerate(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"])}


def month_key(label):
    m = re.match(r"\s*(\d{4})/(\d{1,2})", label or "")
    if m:
        return f"{m.group(1)}-{int(m.group(2)):02d}"
    m = re.match(r"\s*([A-Za-z]{3})[a-z]*\.?,?\s*(\d{4})", label or "")
    if m and m.group(1).lower() in MON:
        return f"{m.group(2)}-{MON[m.group(1).lower()]:02d}"
    return None


def parse_wonder(body, by_mechanism):
    """{month: deaths} or {mechanism label: {month: deaths}}; also the citation, caveats and any message"""
    root = ET.fromstring(body)
    msgs = [e.text.strip() for e in root.iter() if e.tag in ("message", "error") and e.text and e.text.strip()]
    table = next(root.iter("data-table"), None)
    out, cur = {}, None
    if table is None:
        return None, {"messages": msgs[:5]}
    width = 3 if by_mechanism else 2
    for r in table.iter("r"):
        cells = list(r.iter("c"))
        if any(c.get("c") for c in cells):  # a subtotal or total row
            continue
        labels = [c.get("l") for c in cells if c.get("l") is not None]
        vals = [c.get("v") for c in cells if c.get("v") is not None]
        if by_mechanism:
            if len(labels) >= 2:
                cur, mech = labels[0], labels[1]
            elif len(labels) == 1:
                mech = labels[0]
            else:
                continue
            mk = month_key(cur)
        else:
            if not labels:
                continue
            mk, mech = month_key(labels[0]), None
        if not mk or not vals:
            continue
        v = vals[0].replace(",", "")
        n = float(v) if re.match(r"^\d+(\.\d+)?$", v) else None
        if by_mechanism:
            out.setdefault(mech, {})[mk] = n
        else:
            out[mk] = n
    meta = {"messages": msgs[:5]}
    cit = [e.text.strip() for e in root.iter() if e.tag in ("citation", "suggested-citation") and e.text]
    if cit:
        meta["citation"] = cit[0][:600]
    _ = width
    return out, meta


def wonder_fetch(key, rep):
    label, ages, _, mech = R.WONDER_SERIES[key]
    if DRY:
        return synth_wonder(key), {"dry": True}
    wait = WONDER_GAP - (time.time() - WONDER_LAST[0])
    if WONDER_LAST[0] and wait > 0:
        time.sleep(wait)
    xml = wonder_xml(ages, mech == "by mechanism", f"ripples measure v1: {label}")
    data = urllib.parse.urlencode({"request_xml": xml, "accept_datause_restrictions": "true"}).encode()
    body = L.fetch(WONDER_URL, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
    WONDER_LAST[0] = time.time()
    if body is None:
        return None, {"status": "no response (see requests and stopped_hosts)"}
    try:
        return parse_wonder(body, mech == "by mechanism")
    except ET.ParseError as e:
        return None, {"parse_error": str(e)[:120], "head": body[:200].decode("utf-8", "replace")}


# ---------------------------------------------------------------- NPS
def nps_fetch(code):
    if DRY:
        return synth_nps(code)
    body = L.fetch(NPS_URL.format(u=code))
    if body is None:
        return None
    try:
        js = json.loads(body)
    except ValueError:
        return None
    rows = js if isinstance(js, list) else next((v for v in js.values() if isinstance(v, list)), []) if isinstance(js, dict) else []
    out = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        k = {x.lower(): x for x in row}
        yk = next((k[x] for x in k if x == "year"), None)
        mk = next((k[x] for x in k if x == "month"), None)
        vk = next((k[x] for x in k if "recreation" in x and "visit" in x and "hour" not in x), None)
        uk = next((k[x] for x in k if x in ("unitcode", "unit_code", "parkcode")), None)
        if not (yk and mk and vk):
            continue
        if uk and str(row[uk]).upper() != code.upper():
            continue
        try:
            out[f"{int(row[yk])}-{int(row[mk]):02d}"] = float(row[vk])
        except (TypeError, ValueError):
            continue
    return out or None


# ---------------------------------------------------------------- synthetic data for the dry run (no network)
RNG = np.random.default_rng(7)


def synth_wonder(key):
    ms = months((1999, 1), (2020, 12))
    if key == "suicide_all_by_mechanism":
        base = {"Suffocation": 900.0, "Firearm": 1800.0, "Poisoning": 600.0, "Other specified, classifiable Injury": 200.0}
        return {m: {x: float(RNG.poisson(b * (1 + 0.02 * i / 12))) for i, x in enumerate(ms)} for m, b in base.items()}
    b = {"suicide_10_17": 100.0, "suicide_10_19": 160.0, "suicide_18_29": 600.0, "suicide_30_64": 2200.0}[key]
    return {x: float(RNG.poisson(b * (1 + 0.03 * i / 12) * (1 + 0.08 * math.sin(i * math.pi / 6)))) for i, x in enumerate(ms)}


def synth_nps(code):
    ms = months((1979, 1), (2024, 12))
    b = 5000 + (hash(code) % 50000)
    return {x: float(max(0, RNG.normal(b * (1 + 0.5 * math.sin((int(x[5:7]) - 4) * math.pi / 6)), b * 0.1))) for x in ms}


# ---------------------------------------------------------------- helpers
def raw_monthly(s, r, h, design, publish=lambda n: None if n is None else int(round(n))):
    """raw counts beside the result: the window sums and the yearly totals (complete years only)"""
    if design == "yoy":
        a, b = list(range(r, r + h)), list(range(r - 12, r - 12 + h))
    else:
        a, b = list(range(r, r + h)), list(range(r - h, r))
    if a[-1] >= len(s.values) or b[0] < 0:
        return {"result": "window outside the series"}
    # the months that enter the effect: pairs (after month, the month 12 earlier) with both present
    keep = [k for k in range(h) if np.isfinite(s.values[a[k]]) and np.isfinite(s.values[b[k]])]
    sa = float(sum(s.values[a[k]] for k in keep))
    sb = float(sum(s.values[b[k]] for k in keep))
    by_year = {}
    for d, v in zip(s.dates, s.values):
        by_year.setdefault(d.year, []).append(v)
    return {"after_window": [s.labels[a[0]], s.labels[min(a[-1], len(s.labels) - 1)]], "after_count": publish(sa),
            "before_window": [s.labels[b[0]], s.labels[b[-1]]], "before_count": publish(sb),
            "pairs_used": len(keep), "pairs_dropped": h - len(keep),
            "by_year": {str(y): publish(float(np.nansum(v))) for y, v in sorted(by_year.items()) if len(v) == 12 and np.isfinite(v).sum() >= 6}}


def plain_line(stone, outcome_label, res, raw):
    o, c, g = res["own"], res["controls"], res["gradient"]
    if o.get("effect") is None:
        return f"{stone}: not run ({o.get('result')})."
    fmt = lambda n: f"{n:,}" if isinstance(n, (int, float)) else str(n)  # noqa: E731
    s = (f"{outcome_label} changed {o['effect_pct']:+.1f}% ({fmt(raw.get('before_count'))} to {fmt(raw.get('after_count'))}); "
         f"p = {o['p']} against {o['n_placebo']} earlier windows")
    if c.get("p_rank") is not None:
        s += f"; rank {c['rank']} of {c['of']} against matched controls (p = {c['p_rank']})"
    elif c.get("result"):
        s += f"; controls: {c['result']}"
    if g:
        if g.get("mode") == "featured" and g.get("featured_effect") is not None:
            s += f"; featured unit {100 * (math.exp(g['featured_effect']) - 1):+.1f}% vs comparison median {100 * (math.exp(g['comparison_median']) - 1):+.1f}%"
        elif g.get("mode") == "ordered" and g.get("spearman_rho") is not None:
            s += f"; exposure gradient rho = {g['spearman_rho']}"
        else:
            s += f"; gradient: {g.get('result')}"
    return s + f". Grade: {res['grade_v2']}."


def linked_title(t, linked):
    return t in linked


# ---------------------------------------------------------------- arm A
def run_arm_a(rep, wiki):
    ser, meta = {}, {}
    order = ["suicide_10_17", "suicide_18_29", "suicide_30_64", "suicide_all_by_mechanism", "suicide_10_19"]
    ms = months((1999, 1), (2020, 12))
    for key in order:
        vals, m = wonder_fetch(key, rep)
        meta[key] = m
        if not vals:
            continue
        if key == "suicide_all_by_mechanism":
            mech = {k: v for k, v in vals.items() if k}
            tot = {x: sum((mech[k].get(x) or 0) for k in mech) for x in ms if any(mech[k].get(x) is not None for k in mech)}
            rep_key = next((k for k in mech if "suffocation" in k.lower()), None)
            ser["suicide_all"] = monthly(tot, ms)
            if rep_key:
                rp = mech[rep_key]
                ser["suicide_mech_reported"] = monthly(rp, ms)
                ser["suicide_mech_other"] = monthly({x: tot[x] - (rp.get(x) or 0) for x in tot}, ms)
            meta[key]["mechanisms"] = sorted(mech)
        else:
            ser[key] = monthly(vals, ms)
    rep["wonder"] = {"database": "D76, Underlying Cause of Death 1999-2020 (CDC WONDER)", "credit": "powered by CDC WONDER",
                     "meta": meta, "data_use": "national aggregate counts only; counts of 9 or fewer withheld; no attempt to identify anyone"}
    if "suicide_10_17" in ser:
        rep["wonder"]["monthly_published"] = {k: {s.labels[i]: suppress(s.values[i]) for i in range(len(s.labels))} for k, s in ser.items()
                                              if k in ("suicide_10_17", "suicide_all")}
    stones = sorted(wiki["stones"].items(), key=lambda kv: kv[1]["date"])
    for mk in R.WONDER_MARKS:
        stone = D(mk["stone_date"])
        s = ser.get(mk["outcome"])
        row = {k: mk[k] for k in ("id", "stone", "slug", "engine_mark", "stone_date", "kind", "outcome", "design", "h", "direction", "what", "known_positive")}
        row["arm"] = "A: CDC WONDER monthly deaths"
        if s is None:
            row.update({"grade_v2": "not run", "line": f"{mk['stone']}: the outcome series was not returned"})
            rep["marks"].append(row)
            continue
        pool = [(t, d) for t, d in R.POOLS[mk["kind"]] if t not in R.LINKED_A and t != mk["stone"]]

        def grad(mk=mk, stone=stone):
            gs = [(lab, x, ser[k]) for k, x, lab in mk["gradient"]["groups"] if k in ser]
            return V.gradient_ordered(gs, stone, mk["h"], mk["design"], mk["direction"])
        res = V.v2(s, stone, mk["h"], mk["design"], mk["direction"], pool, gradient=grad)
        r = s.index_of(V.ref_date(stone, 31))
        raw = raw_monthly(s, r, mk["h"], mk["design"], publish=suppress)
        row.update(res)
        row["raw"] = raw
        row["line"] = plain_line(mk["stone"], R.WONDER_SERIES.get(mk["outcome"], ("Suicide deaths, all ages",))[0] if mk["outcome"] in R.WONDER_SERIES else "Suicide deaths, all ages", res, raw)
        row["secondary"] = []
        for sec in mk.get("secondary", []):
            s2 = ser.get(sec["outcome"])
            if s2 is None:
                row["secondary"].append({**sec, "result": "series not returned"})
                continue
            o2 = V.own_test(s2, stone, sec["h"], sec["design"], mk["direction"])
            row["secondary"].append({**sec, **{k: o2.get(k) for k in ("effect_pct", "p", "n_placebo", "onset", "busted", "pass", "window", "result")},
                                     "raw": raw_monthly(s2, s2.index_of(V.ref_date(stone, 31)), sec["h"], sec["design"], publish=suppress)})
        # decoys: wrong stones on the same outcome, full v2
        real_p = V.periods(r, mk["h"], mk["design"])
        cands = [(st["stone"], st["date"], sl) for sl, st in stones if sl not in R.LINKED_A]
        other_pool = R.POOLS["celebrity_death" if mk["kind"] == "teen_tv" else "teen_tv"]
        cands += [(t, d, None) for t, d in other_pool if t not in R.LINKED_A]
        seen, drows = set(), []
        for title, when, sl in cands:
            d0 = D(when)
            rr = s.index_of(V.ref_date(d0, 31))
            if rr is None or rr in seen or V.periods(rr, mk["h"], mk["design"]) & real_p:
                continue
            seen.add(rr)
            dres = V.v2(s, d0, mk["h"], mk["design"], mk["direction"], [(t, dd) for t, dd in pool if t != title],
                        gradient=lambda d0=d0, mk=mk: V.gradient_ordered([(lab, x, ser[k]) for k, x, lab in mk["gradient"]["groups"] if k in ser], d0, mk["h"], mk["design"], mk["direction"]))
            if dres["grade_v2"] == "not run":
                continue
            drows.append({"decoy": title, "date": when, "grade_v2": dres["grade_v2"], "p": dres["own"].get("p"),
                          "own_pass": dres["own"].get("pass"), "p_rank": dres["controls"].get("p_rank"),
                          "gradient_pass": (dres["gradient"] or {}).get("pass")})
        rep["decoys"][mk["id"]] = summarize_decoys(drows)
        rep["marks"].append(row)
    return ser


def summarize_decoys(rows):
    c = {}
    for x in rows:
        c[x["grade_v2"]] = c.get(x["grade_v2"], 0) + 1
    return {"n": len(rows), "grades": c, "own_test_pass": sum(1 for x in rows if x.get("own_pass")), "rows": rows}


# ---------------------------------------------------------------- arm B
def run_arm_b(rep, wiki):
    codes = []
    for mk in R.NPS_MARKS:
        for u in mk["units"]:
            codes += [u] + mk.get("alt_codes", {}).get(u, [])
    for g in R.NPS_GROUPS.values():
        codes += g
    seen, order = set(), []
    for c in codes:
        if c not in seen:
            seen.add(c)
            order.append(c)
    raw_units, status = {}, {}
    alt_of = {a: u for mk in R.NPS_MARKS for u, alts in mk.get("alt_codes", {}).items() for a in alts}
    for c in order:
        if c in alt_of and raw_units.get(alt_of[c]):
            continue  # the primary code returned data; the alternative is not needed
        v = nps_fetch(c)
        status[c] = "data" if v else "no data"
        if v:
            raw_units[c] = v
    for mk in R.NPS_MARKS:  # an alternative code stands in for a primary code that returned nothing
        for u, alts in mk.get("alt_codes", {}).items():
            if u not in raw_units:
                for a in alts:
                    if a in raw_units:
                        raw_units[u] = raw_units[a]
                        status[u] = f"data under {a}"
                        break
    ms = months((1979, 1), (2024, 12))
    units = {c: monthly(v, ms, SHUTDOWN_MONTHS) for c, v in raw_units.items()}
    rep["nps"] = {"source": "NPS Visitor Use Statistics, monthly recreation visits (irmaservices.nps.gov/v3/rest/stats)", "unit_status": status,
                  "shutdown_months_set_missing": sorted(SHUTDOWN_MONTHS)}
    stones = sorted(wiki["stones"].items(), key=lambda kv: kv[1]["date"])
    arm_stones = [(m["stone"], m["date"], m["kind"], set(m["units"])) for m in R.NPS_MARKS]
    for mk in R.NPS_MARKS:
        stone = D(mk["date"])
        row = {k: mk.get(k) for k in ("id", "stone", "date", "kind", "units", "group", "why", "known_positive")}
        row.update({"arm": "B: NPS monthly recreation visits", "design": "paired", "h": 12, "direction": "up",
                    "what": f"Recreation visits to {', '.join(mk['units'])} in the 12 months from the stone against the 12 months before, compared with every earlier 12-month change since 1980"})
        have = [u for u in mk["units"] if u in units]
        if len(have) < len(mk["units"]):
            row.update({"grade_v2": "not run", "line": f"{mk['stone']}: no NPS data for {', '.join(u for u in mk['units'] if u not in units)}"})
            rep["marks"].append(row)
            continue
        fs = aggregate([units[u] for u in have], ms)
        mine = set(mk["units"])
        pool = [(t, d) for t, d in R.POOLS[mk["kind"]] if t != mk["stone"]]
        pool += [(t, d) for t, d, k, us in arm_stones if k == mk["kind"] and t != mk["stone"] and not (us & mine)]
        comps = [(c, units[c]) for c in R.NPS_GROUPS[mk["group"]] if c in units and c not in mine]

        def grad(stone=stone, fs=fs, comps=comps, mk=mk):
            return V.gradient_featured(("+".join(mk["units"]), fs), comps, stone, 12, "paired", "up")
        res = V.v2(fs, stone, 12, "paired", "up", pool, gradient=grad)
        r = fs.index_of(V.ref_date(stone, 31))
        raw = raw_monthly(fs, r, 12, "paired") if r is not None and r + 12 <= len(fs.values) else {}
        row.update(res)
        row["raw"] = raw
        row["line"] = plain_line(mk["stone"], f"Visits to {'+'.join(mk['units'])}", res, raw)
        # decoys: this unit at wrong stones' dates (engine stones and the other arm-B stones), full v2
        if res["grade_v2"] != "not run":
            real_p = V.periods(r, 12, "paired")
            cands = [(st["stone"], st["date"]) for _, st in stones]
            cands += [(t, d) for t, d, k, us in arm_stones if not (us & mine)]
            seen_r, drows = set(), []
            for title, when in cands:
                d0 = D(when)
                rr = fs.index_of(V.ref_date(d0, 31))
                if rr is None or rr in seen_r or V.periods(rr, 12, "paired") & real_p:
                    continue
                seen_r.add(rr)
                dres = V.v2(fs, d0, 12, "paired", "up", [(t, dd) for t, dd in pool if t != title],
                            gradient=lambda d0=d0, fs=fs, comps=comps, mk=mk: V.gradient_featured(("+".join(mk["units"]), fs), comps, d0, 12, "paired", "up"))
                if dres["grade_v2"] == "not run":
                    continue
                drows.append({"decoy": title, "date": when, "grade_v2": dres["grade_v2"], "p": dres["own"].get("p"),
                              "own_pass": dres["own"].get("pass"), "p_rank": dres["controls"].get("p_rank"),
                              "gradient_pass": (dres["gradient"] or {}).get("pass")})
            rep["decoys"][mk["id"]] = summarize_decoys(drows)
        rep["marks"].append(row)
    run_annual_b(rep, units)
    return units


def aggregate(series, labels):
    vals = np.vstack([s.values for s in series])
    tot = np.where(np.isfinite(vals).all(axis=0), np.nansum(vals, axis=0), np.nan)
    return monthly({labels[i]: tot[i] for i in range(len(labels)) if np.isfinite(tot[i])}, labels)


def run_annual_b(rep, units):
    """Close Encounters -> Devils Tower: only if the API gives annual values before 1979 (registered as conditional)"""
    for mk in R.NPS_ANNUAL_MARKS:
        row = {k: mk.get(k) for k in ("id", "stone", "date", "kind", "units", "group", "why", "known_positive")}
        row["arm"] = "B: NPS annual recreation visits (conditional)"
        if DRY:
            row.update({"grade_v2": "not run", "line": "dry run"})
            rep["marks"].append(row)
            continue
        body = L.fetch(NPS_TOTAL_URL.format(y=1977))
        probe = None
        try:
            probe = json.loads(body) if body else None
        except ValueError:
            probe = None
        per_unit = isinstance(probe, list) and probe and isinstance(probe[0], dict) and any("unit" in k.lower() for k in probe[0])
        if not per_unit:
            row.update({"grade_v2": "not run", "line": "the NPS API returned no per-unit annual values for 1977; the annual design cannot run",
                        "probe": (json.dumps(probe)[:300] if probe is not None else None)})
            rep["marks"].append(row)
            continue
        by_year = {}
        for y in range(1955, 1991):
            b = L.fetch(NPS_TOTAL_URL.format(y=y))
            if not b:
                break
            for rw in json.loads(b):
                k = {x.lower(): x for x in rw}
                uk = next((k[x] for x in k if "unitcode" in x), None)
                vk = next((k[x] for x in k if "recreation" in x and "visit" in x and "hour" not in x), None)
                if uk and vk and str(rw[uk]).upper() == "DETO":
                    by_year[y] = float(rw[vk])
        if len(by_year) < 20:
            row.update({"grade_v2": "not run", "line": f"only {len(by_year)} annual values for DETO"})
            rep["marks"].append(row)
            continue
        s = L.annual_series(by_year)
        stone = D(mk["date"])
        pool = [(t, d) for t, d in R.FILM_POOL if t != mk["stone"]]
        res = V.v2(s, stone, 1, "standard", "up", pool, gradient=None)
        r = s.index_of(V.ref_date(stone, 365))
        row.update(res)
        row["raw"] = L.raw_block(s, r, 1)
        row["gradient_note"] = "n/a: the annual totals carry no comparison set registered for this mark"
        row["line"] = plain_line(mk["stone"], "Visits to DETO (annual)", res, {"before_count": row["raw"]["before"], "after_count": row["raw"]["after"]})
        rep["marks"].append(row)


# ---------------------------------------------------------------- re-tests of the ladder's two marks
def retests(rep):
    out = {}
    if DRY:
        rep["retests"] = {"dry": True}
        return
    fl = L.defra_flour()
    if fl and fl.get("points"):
        s = L.defra_series(fl["points"])
        stone = D("2010-08-17")
        tv = [(t, d) for t, d in R.TV_POOL]
        res = V.v2(s, stone, 1, "standard", "up", tv, gradient=None)
        ladder_ctrl = V.control_test(s, stone, 1, "standard", "up", res["own"].get("effect"), [(t, y) for t, y in L.CONTROLS[("bake-off", "w0")]], n_max=19)
        r = s.index_of(V.ref_date(stone, 365))
        out["bake-off/w0"] = {**res, "what": "Flour bought by UK households (Defra Family Food, g per person per week), 2011 against 2010",
                              "ladder_v1_controls": ladder_ctrl, "raw": L.raw_block(s, r, 1), "source_url": fl.get("url"),
                              "gradient_note": "n/a: no exposure measure is registered for the Bake Off (no regional viewing series)"}
    else:
        out["bake-off/w0"] = {"grade_v2": "not run", "why": ["Defra file not parsed or host refused", str(fl)[:200]]}
    ssb = L.ssb_08402()
    if ssb:
        vals, ms = ssb
        foreign = {m: vals.get(("0", "ccc", m)) for m in ms}
        fjord = {m: sum(vals.get((rg, "ccc", m)) or 0 for rg in ("12", "14", "15")) or None for m in ms}
        rest = {m: (foreign[m] - fjord[m]) if foreign[m] and fjord[m] else None for m in ms}
        sf, sj, sr = L.monthly_series(foreign, ms), L.monthly_series(fjord, ms), L.monthly_series(rest, ms)
        stone = D("2013-11-27")
        films = [(t, d) for t, d in R.FILM_POOL if "Frozen" not in t]
        res = V.v2(sf, stone, 12, "standard", "up", films,
                   gradient=lambda: V.gradient_ordered([("fjord counties (Arendelle's model)", 1, sj), ("rest of Norway", 0, sr)], stone, 12, "standard", "up"))
        ladder_ref = V.own_test(sf, stone, 12, "standard", "up", ref=D("2013-11-01"))
        ladder_ctrl = V.control_test(sf, stone, 12, "standard", "up", res["own"].get("effect"), list(L.CULTURE_FILMS.items()), n_max=19)
        r = sf.index_of(V.ref_date(stone, 31))
        out["frozen-culture/w0"] = {**res, "what": "Foreign guests' hotel nights in Norway (Statistics Norway table 08402), 12 months from December 2013 against the 12 months before",
                                    "ladder_reference_nov_2013": {k: ladder_ref.get(k) for k in ("effect_pct", "p", "n_placebo", "onset", "pass")},
                                    "ladder_v1_controls": ladder_ctrl, "raw": L.raw_block(sf, r, 12), "source_url": L.SSB_URL}
    else:
        out["frozen-culture/w0"] = {"grade_v2": "not run", "why": ["Statistics Norway did not answer"]}
    rep["retests"] = out


def main() -> int:
    wiki = json.load(open(WIKI))
    rep = {"protocol": "ripples/docs/measure_plan_v1.md", "code": ["ripples/lab/ladder2.py", "ripples/lab/measure_v1.py", "ripples/lab/measure_registry.py"],
           "run": dt.date.today().isoformat(), "registered_sha": os.environ.get("MEASURE_PLAN_SHA", ""), "user_agent": L.UA, "dry_run": DRY,
           "marks": [], "decoys": {}, "requests": L.REQUESTS, "stopped_hosts": L.STOPPED}
    retests(rep)
    run_arm_a(rep, wiki)
    run_arm_b(rep, wiki)
    rep["summary"] = summary(rep)
    json.dump(rep, open(OUT, "w"), indent=1, ensure_ascii=False, default=lambda o: o.item() if hasattr(o, "item") else str(o))
    print(json.dumps(rep["summary"], indent=1), flush=True)
    return 0


def summary(rep):
    marks = rep["marks"]
    kp = [m for m in marks if (m.get("known_positive") or {}).get("published")]
    doc = [m for m in marks if m.get("known_positive") and not m["known_positive"].get("published")]
    new = [m for m in marks if not m.get("known_positive")]
    dec = [x for d in rep["decoys"].values() for x in d["rows"]]
    g = lambda ms: {k: sum(1 for m in ms if m.get("grade_v2") == k) for k in ("measured", "timed", "busted", "no movement", "not run")}  # noqa: E731
    n_dec = len(dec)
    dm = sum(1 for x in dec if x["grade_v2"] == "measured")
    return {"published_positives": {"n": len(kp), "grades": g(kp), "measured": [m["id"] for m in kp if m.get("grade_v2") == "measured"]},
            "documented_positives": {"n": len(doc), "grades": g(doc)},
            "scan_marks": {"n": len(new), "grades": g(new), "measured": [m["id"] for m in new if m.get("grade_v2") == "measured"]},
            "decoys": {"n": n_dec, "measured": dm, "rate": round(dm / n_dec, 4) if n_dec else None,
                       "own_test_pass": sum(1 for x in dec if x.get("own_pass")),
                       "own_test_rate": round(sum(1 for x in dec if x.get("own_pass")) / n_dec, 4) if n_dec else None},
            "bar": {"recover_published_positive": any(m.get("grade_v2") == "measured" for m in kp),
                    "two_new_measured": sum(1 for m in new if m.get("grade_v2") == "measured") >= 2,
                    "decoys_at_or_under_nominal": (dm / n_dec <= 0.05) if n_dec else None}}


if __name__ == "__main__":
    sys.exit(main())
