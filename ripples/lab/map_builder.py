"""Ripple map builder: one config (ripples/maps/<slug>.json) -> one time-ordered ripple map page.

For each map:
  1. Daily Wikipedia attention (Wikimedia pageviews, user agent only, anonymous, honest UA, 1 s apart, stop on
     403/429/503) for the event article(s) and every attention step's articles, from 150 days before the event to 210
     after. Onset = first day from 14 days before the event on which the 7-day mean exceeds the pre-period median
     (days -120..-15) by 5 MAD and by 50%.
  2. Behavior steps: Seattle Public Library checkouts for a subject heading (ripples.att_sea via public.att_sea_series;
     a heading not yet fetched is queued with public.att_sea_request and the step shows as pending). Same test as chain
     tests v1 (log1p minus panel median minus same-month 3-year median; effect m0..m0+2 vs m0-6..m0-1; every admissible
     month as a placebo), with CLOSURE MONTHS EXCLUDED: months where the library panel fell below half of the same
     month a year earlier are masked, and a step whose window touches them is "not measurable" (ledger 1504).
  3. Ordering rule (ledger 1497): steps are checked in the config's order; each counted step must start on or after
     the previous counted step (attention by day; behavior by month; records by date). The first reference point is
     the event's own attention onset (trailers and early spread count) or the release date, whichever is earlier. A
     step that starts before it, or before the previous counted step, is shown as "Not counted". Onsets must be
     sustained (5 days above threshold) and at least a fifth of the way to the peak.
  4. Evidence: "tested" when the config cites a registered test for that step (or the behavior test passes),
     "timed" when only the onset is measured, "record" for a dated published fact supplied with a source.
Output: ripples/discover/maps/<slug>/index.html (from ripples/maps/template.html) and ripples/maps/out/<slug>.json.
"""
from __future__ import annotations

import datetime as dt
import glob
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
API = ("https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/"
       "{t}/daily/{a}/{b}")
PRE, POST = 150, 210
_cache: dict = {}


class Stop(Exception):
    pass


def views(title, d0, d1):
    key = (title, d0, d1)
    if key in _cache:
        return _cache[key]
    url = API.format(t=urllib.parse.quote(title, safe=""), a=d0.strftime("%Y%m%d"), b=d1.strftime("%Y%m%d"))
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            out = {i["timestamp"][:8]: i["views"] for i in json.load(r)["items"]}
    except urllib.error.HTTPError as e:
        if e.code in (403, 429, 503):
            raise Stop(f"HTTP {e.code} on {title}")
        out = {}
    time.sleep(1)
    _cache[key] = out
    return out


def attention(titles, ev):
    d0, d1 = ev - dt.timedelta(days=PRE), ev + dt.timedelta(days=POST)
    days = [d0 + dt.timedelta(days=i) for i in range((d1 - d0).days + 1)]
    v = np.zeros(len(days))
    found = False
    for t in titles:
        s = views(t, d0, d1)
        found |= bool(s)
        v += np.array([s.get(d.strftime("%Y%m%d"), 0) for d in days], dtype=float)
    if not found:
        return None
    e0 = PRE
    pre = v[e0 - 120:e0 - 14]
    med = float(np.median(pre))
    mad = 1.4826 * float(np.median(np.abs(pre - med)))
    roll = np.convolve(v, np.ones(7) / 7, mode="full")[:len(v)]
    thr = max(med + 5 * mad, med * 1.5, 20)
    peak = float(roll[e0 - 30:].max()) if len(roll) > e0 else 0.0
    thr = max(thr, med + 0.2 * (peak - med))  # a rise must be a real share of the peak, not a blip
    # sustained: the 7-day mean stays above the threshold for 5 days running (filters anniversaries and holidays)
    on = next((i for i in range(e0 - 30, len(v) - 5) if all(roll[i + k] > thr for k in range(5))), None)
    w0 = e0 - 70
    weekly = [[days[i].isoformat(), round(float(v[i:i + 7].mean()))] for i in range(w0 - (w0 % 7), len(v) - 6, 7)]
    return {"weekly": weekly, "onset": None if on is None else days[on].isoformat(),
            "days": None if on is None else on - e0, "pre": round(med, 1), "peak": int(v[e0:].max())}


def supabase(fn, args):
    url, key = os.environ.get("SUPABASE_URL", "").rstrip("/"), os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        return None
    h = {"apikey": key, "Content-Type": "application/json"}
    if key.startswith("eyJ"):
        h["Authorization"] = "Bearer " + key
    req = urllib.request.Request(f"{url}/rest/v1/rpc/{fn}", data=json.dumps(args).encode(), headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def months(a="2005-04", b="2026-08"):
    y, m = map(int, a.split("-"))
    out = []
    while f"{y}-{m:02d}" <= b:
        out.append(f"{y}-{m:02d}")
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)
    return out


def behavior(series, panel, m0):
    M = months(b=max(panel))
    idx = {m: i for i, m in enumerate(M)}
    med = np.array([panel.get(m, np.nan) for m in M], dtype=float)
    closed = np.zeros(len(M), bool)  # library panel below half of the same month a year earlier
    for i in range(12, len(M)):
        if np.isfinite(med[i]) and np.isfinite(med[i - 12]) and np.expm1(med[i]) < 0.5 * np.expm1(med[i - 12]):
            closed[i] = True
    raw = np.array([np.log1p(series.get(m, 0)) for m in M]) - med
    raw[closed] = np.nan
    x = np.full(len(M), np.nan)
    for i in range(36, len(M)):
        prev = [raw[i - 12 * k] for k in (1, 2, 3) if np.isfinite(raw[i - 12 * k])]
        if len(prev) >= 2 and np.isfinite(raw[i]):
            x[i] = raw[i] - np.median(prev)

    def effect(i):
        post, pre = x[i:i + 3], x[i - 6:i]
        if np.isfinite(post).sum() < 3 or np.isfinite(pre).sum() < 4:
            return np.nan
        return float(np.nanmean(post) - np.nanmean(pre))

    i0 = idx[m0]
    shown = {m: int(series.get(m, 0)) for m in M[max(0, i0 - 12):min(len(M), i0 + 7)]}
    if closed[i0 - 6:i0 + 3].any():
        return {"measurable": False, "why": "the library was closed or barely open in this window", "monthly": shown}
    obs = effect(i0)
    pool = [i for i in range(max(idx["2008-01"], 42), len(M) - 3) if abs(i - i0) >= 7 and np.isfinite(effect(i))]
    P = np.array([effect(i) for i in pool])
    if not np.isfinite(obs) or not len(P):
        return {"measurable": False, "why": "too few months of data", "monthly": shown}
    p = float((1 + (P >= obs).sum()) / (1 + len(P)))
    pre = x[i0 - 12:i0]
    thr = np.nanmean(pre) + 2 * 1.4826 * np.nanmedian(np.abs(pre - np.nanmedian(pre)))
    onset = next((M[i] for i in range(i0 - 3, min(i0 + 7, len(M))) if np.isfinite(x[i]) and x[i] > thr), None)
    return {"measurable": True, "p": round(p, 4), "onset": onset, "monthly": shown,
            "passes": bool(p <= 0.05 and onset is not None and onset >= m0)}


def build(cfg_path):
    cfg = json.load(open(cfg_path))
    ev = dt.date.fromisoformat(cfg["release"])
    out = {"slug": cfg["slug"], "title": cfg["title"], "release": cfg["release"], "steps": []}
    ea = attention(cfg["event_articles"], ev)
    # The stone hits the water when attention to the event itself starts (trailers and early spread count), so the
    # ordering rule compares every step with the event's own onset, not only the release date.
    ev_on = dt.date.fromisoformat(ea["onset"]) if ea and ea.get("onset") else ev
    ev_on = min(ev_on, ev)
    lead = (ev - ev_on).days
    note = cfg.get("event_note", "") or (f"Attention to the event began {lead} days before this date." if lead > 0 else "")
    out["steps"].append({"kind": "event", "title": cfg["event_title"], "date": cfg["release"], "days": 0,
                         "evidence": "event", "series": ea, "measure": "daily Wikipedia views of the event article",
                         "note": note})
    out["event_onset"] = ev_on.isoformat()
    last_day, last_month = ev_on, ev_on.isoformat()[:7]
    heads = [s["heading"] for s in cfg["steps"] if s["type"] == "behavior"]
    lib = supabase("att_sea_series", {"p_terms": heads}) if heads else None
    if lib and lib.get("series") is not None:
        missing = [h for h in heads if h not in lib["series"]]
        if missing:
            supabase("att_sea_request", {"p_terms": missing})
    for s in cfg["steps"]:
        st = {k: s[k] for k in ("title", "note", "test", "source", "facts") if k in s}
        if s["type"] == "attention":
            a = attention(s["articles"], ev)
            also = []
            for t in s.get("also", []):
                b = attention([t], ev)
                if b and b["onset"]:
                    also.append({"name": t.replace("_", " "), "days": b["days"]})
            st.update(kind="attention", series=a, also=also or None,
                      measure=f"daily Wikipedia views of “{s['articles'][0].replace('_', ' ')}”")
            if not a or not a["onset"]:
                st.update(evidence="excluded", date=cfg["release"], days=None,
                          why="no clear rise in attention after the event")
            else:
                day = dt.date.fromisoformat(a["onset"])
                st.update(date=a["onset"], days=a["days"])
                ref = ev_on if s.get("branch") else last_day  # a branch starts a new line from the event itself
                if day < ref:
                    st.update(evidence="excluded", why="its rise began before attention to the event did, or before the previous step")
                else:
                    st["evidence"] = "tested" if s.get("test") else "timed"
                    if not s.get("branch"):
                        last_day, last_month = day, a["onset"][:7]
                    else:
                        st["branch"] = True
        elif s["type"] == "behavior":
            ser = (lib or {}).get("series", {}).get(s["heading"])
            st.update(kind="behavior", measure=f"monthly checkouts of books on “{s['heading']}”, Seattle Public Library")
            if not ser:
                st.update(evidence="na", date=cfg["release"][:7], days=None,
                          why="library data for this subject is being fetched; it appears on the next build")
            else:
                b = behavior(ser, lib["panel_median"], cfg["release"][:7])
                st.update(monthly=b["monthly"], days=None)
                if not b["measurable"]:
                    st.update(evidence="na", date=cfg["release"][:7], why=b["why"])
                elif not b["passes"] or b["onset"] < last_month:
                    st.update(evidence="excluded", date=b["onset"] or cfg["release"][:7],
                              why=(f"no rise beyond normal (p = {b['p']})" if b["p"] > 0.05 else
                                   "no clear start to the rise" if b["onset"] is None else
                                   "its rise began before the event" if not b["passes"] else
                                   "its rise began before the previous step"),
                              test=f"Chain test: p = {b['p']} against every other month; rise began {b['onset'] or 'never'}.")
                else:
                    st.update(evidence="tested", date=b["onset"],
                              test=f"Chain test: rise beyond the seasonal normal, p = {b['p']} against every other "
                                   f"month; rise began {b['onset']}, after the event. Closure months excluded.")
                    last_month = b["onset"]
        elif s["type"] == "record":
            d = dt.date.fromisoformat(s["date"])
            st.update(kind="real", date=s["date"], days=(d - ev).days, measure=s.get("measure", ""))
            st["evidence"] = "record" if d >= last_day else "excluded"
            if d >= last_day:
                last_day = d
        if st.get("why"):
            st["note"] = (st.get("note", "") + f" Not counted: {st['why']}." if st["evidence"] == "excluded"
                          else st.get("note", "") + f" Not measurable here: {st['why']}.").strip()
        out["steps"].append(st)
    os.makedirs(os.path.join(ROOT, "maps", "out"), exist_ok=True)
    json.dump(out, open(os.path.join(ROOT, "maps", "out", cfg["slug"] + ".json"), "w"), indent=1, ensure_ascii=False)
    tpl = open(os.path.join(ROOT, "maps", "template.html"), encoding="utf-8").read()
    page = (tpl.replace("__TITLE__", cfg["title"]).replace("__DESC__", cfg["description"])
            .replace("__LEDE__", cfg["lede"]).replace("__LIMITS__", cfg["limits"]).replace("__DATALINE__", cfg["dataline"])
            .replace("__DATA__", json.dumps(out, ensure_ascii=False).replace("</", "<\\/")))
    d = os.path.join(ROOT, "discover", "maps", cfg["slug"])
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "index.html"), "w", encoding="utf-8").write(page)
    counted = [s for s in out["steps"] if s["evidence"] in ("tested", "timed", "record")]
    print(f"{cfg['slug']}: {len(counted)} counted steps of {len(out['steps']) - 1}", flush=True)
    return {"slug": cfg["slug"], "title": cfg["title"], "release": cfg["release"], "counted": len(counted),
            "steps": len(out["steps"]) - 1,
            "measured_behavior": any(s.get("kind") == "behavior" and s["evidence"] == "tested" for s in out["steps"])}


def main() -> int:
    only = sys.argv[1:]
    index = []
    for p in sorted(glob.glob(os.path.join(ROOT, "maps", "*.json"))):
        slug = os.path.basename(p)[:-5]
        if only and slug not in only:
            continue
        try:
            index.append(build(p))
        except Stop as e:
            print(f"stopped: {e}", flush=True)
            break
    idx_path = os.path.join(ROOT, "maps", "out", "index.json")
    old = {m["slug"]: m for m in (json.load(open(idx_path)) if os.path.exists(idx_path) else [])}
    old.update({m["slug"]: m for m in index})
    maps = sorted(old.values(), key=lambda m: m["release"])
    json.dump(maps, open(idx_path, "w"), indent=1, ensure_ascii=False)
    write_index(maps)
    return 0


def write_index(maps):
    """ripples/discover/maps/index.html: every map, newest event first, with how many steps were counted."""
    tpl = open(os.path.join(ROOT, "maps", "template.html"), encoding="utf-8").read()
    head = tpl.split("<main>")[0].replace("__TITLE__", "Ripple maps").replace(
        "__DESC__", "Every ripple map: one event each, followed step by step in time order.")
    rows = "".join(
        f'<a class="stop" href="/ripples/discover/maps/{m["slug"]}/" style="display:block;text-decoration:none">'
        f'<div class="when"><b>{m["release"]}</b><span>{m["counted"]} of {m["steps"]} steps counted'
        f'{" · measured behavior" if m["measured_behavior"] else ""}</span></div><h2>{m["title"]}</h2></a>'
        for m in reversed(maps))
    page = (head + '<main><div class="kicker">Ripple Map · prototype</div><h1>Ripple maps</h1>'
            '<p class="lede">One event each, followed step by step: what people looked up, what they reached for, '
            'what they borrowed, and what happened in the world. A step counts only if it starts after the one '
            'before it.</p><div class="route" style="margin-top:1.4rem">' + rows + '</div>'
            '<div class="foot"><p>Built by <code>ripples/lab/map_builder.py</code> from the configs in '
            '<code>ripples/maps/</code>. More results on <a href="/ripples/discover/">Discoveries</a>.</p></div>'
            '</main></body></html>')
    d = os.path.join(ROOT, "discover", "maps")
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "index.html"), "w", encoding="utf-8").write(page)


if __name__ == "__main__":
    sys.exit(main())
