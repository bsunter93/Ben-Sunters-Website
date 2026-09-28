"""More outcome lenses for the discovery engine (ripples/docs/q3_protocol_more.md). Builds one panel per call:

  python more_panels.py daily2   -> $LAB_CACHE/daily2_pv.npz   Hacker News topic mentions, npm downloads, NYC transit
                                                               ridership, FEMA disaster declarations (daily grid)
  python more_panels.py weekly   -> $LAB_CACHE/weekly_pv.npz   state jobless claims, business applications, deaths,
                                                               weekly fuel prices (weeks starting Sunday)
  python more_panels.py monthly  -> $LAB_CACHE/monthly_pv.npz  state labour, housing and permit series, national jobs
                                                               by industry, consumer prices by item (calendar months)

Input: Supabase RPC att_q3_export(source) (ripples/attention/sql/51_att_q3_export.sql), service role, read-only.
All panels are written pre-transformed (raw = True). Transforms, fixed before any event is scored:
- daily2: log(1 + count), gaps up to 4 days carried forward, minus the median of the same weekday over the previous
  8 weeks (as econ_panel.py);
- weekly and monthly: log of levels (unemployment rates stay in percentage points), minus the median of the same
  period in the previous three years (at least two available), which removes the yearly cycle using only the past.
Coarse panels also carry step (nominal days per period) and the event window in periods (ct_lo..ct_hi): weekly -2..13,
monthly -1..3, the daily window of -14..90 days in coarser units.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys

import numpy as np

from econ_panel import CACHE, ffill, weekday_adjust  # noqa: E402  (also puts tools/bq on the path)
from common import Supabase  # noqa: E402

BASE = dt.date(2012, 1, 1)
END = dt.date(2026, 8, 31)
SETS = {
    "daily2": ["hn.algolia", "npm.dl", "mta.ridership", "fema.decl"],
    "weekly": ["dol.claims", "census.bfs", "cdc.deaths", "fred.weekly"],
    "monthly": ["fred.state", "bls.ces", "bls.cpi_items"],
}
STATE_METRIC = {"ur": "unemployment rate", "nonfarm": "jobs, all", "cons": "construction jobs",
                "mfg": "manufacturing jobs", "trad": "trade and transport jobs", "pbsv": "business services jobs",
                "eduh": "education and health jobs", "leih": "leisure and hospitality jobs",
                "fire": "finance jobs", "govt": "government jobs", "srvo": "other services jobs",
                "bppriv": "building permits", "listings": "active home listings", "newlist": "new home listings",
                "dom": "days on market (homes)", "minwage": "minimum wage"}
RATE_METRICS = {"ur"}


def label(name: str) -> str:
    src, metric, key, geo = name.split("|")
    st = geo.replace("US-", "") if geo.startswith("US-") else "US"
    if src == "hn.algolia":
        return "hn:" + ("all stories" if key == "__total__" else key)
    if src == "npm.dl":
        return "npm downloads: " + ("all packages" if key == "__total__" else key)
    if src == "mta.ridership":
        return f"NYC transit ridership: {key}"
    if src == "fema.decl":
        return f"FEMA declarations: {key.replace('it:', '')} ({st})"
    if src == "dol.claims":
        return f"{'Initial' if metric == 'ic' else 'Continuing'} jobless claims ({key})"
    if src == "census.bfs":
        return f"Business applications ({key})"
    if src == "cdc.deaths":
        return f"Deaths, all causes ({st})"
    if src == "fred.weekly":
        return {"GASREGW": "Gasoline price, regular (weekly)", "GASDESW": "Diesel price (weekly)"}.get(key, key)
    if src == "fred.state":
        return f"{st}: {STATE_METRIC.get(metric, metric)}"
    if src == "bls.ces":
        return f"US jobs, BLS series {key}"
    if src == "bls.cpi_items":
        return f"US prices, CPI item {key}"
    return name


def grid(kind: str, pv_days: np.ndarray):
    if kind == "daily2":
        return pv_days
    if kind == "weekly":
        d = dt.date(2015, 7, 1)
        d += dt.timedelta(days=(6 - d.weekday()) % 7)  # first Sunday on or after the Wikipedia panel start
        out = []
        while d + dt.timedelta(days=6) <= END:
            out.append(d.toordinal())
            d += dt.timedelta(days=7)
        return np.array(out)
    out, y, m = [], 2015, 7
    while (y, m) <= (END.year, END.month):
        out.append(dt.date(y, m, 1).toordinal())
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)
    return np.array(out)


def period_of(kind: str, day: dt.date) -> int:
    if kind == "weekly":  # the Sunday that starts the week containing the day
        return (day - dt.timedelta(days=(day.weekday() + 1) % 7)).toordinal()
    return dt.date(day.year, day.month, 1).toordinal()


def ext_grid(kind: str) -> np.ndarray:
    d = BASE - dt.timedelta(days=(BASE.weekday() + 1) % 7) if kind == "weekly" else BASE
    out = []
    while d <= END:
        out.append(d.toordinal())
        d = d + dt.timedelta(days=7) if kind == "weekly" else dt.date(d.year + d.month // 12, d.month % 12 + 1, 1)
    return np.array(out)


def seasonal_adjust(v: np.ndarray, lag: int) -> np.ndarray:
    lags = np.stack([np.concatenate([np.full(k * lag, np.nan), v[:len(v) - k * lag]]) for k in (1, 2, 3)])
    ok = np.isfinite(lags).sum(0) >= 2
    with np.errstate(all="ignore"):
        base = np.nanmedian(np.where(ok[None, :], lags, 0.0), axis=0)
    return np.where(ok & np.isfinite(v), v - base, np.nan)


def main() -> int:
    kind = sys.argv[1] if len(sys.argv) > 1 else ""
    if kind not in SETS:
        print(f"usage: more_panels.py {'|'.join(SETS)}")
        return 2
    pv_days = np.load(os.path.join(CACHE, "pv.npz"), allow_pickle=False)["days"]
    g = grid(kind, pv_days)
    sb = Supabase()
    names, rows, per_source = [], [], {}
    for src in SETS[kind]:
        data = sb.rpc("att_q3_export", {"p_source": src}, timeout=300) or {}
        kept = 0
        for name, obj in sorted(data.items()):
            metric = name.split("|")[1]
            days = [BASE + dt.timedelta(days=int(k)) for k in obj["d"]]
            vals = np.array([np.nan if x is None else float(x) for x in obj["v"]])
            if kind == "daily2":
                full = np.full((END - BASE).days + 1, np.nan)
                for d, x in zip(days, vals):
                    full[(d - BASE).days] = x
                v = ffill(np.log1p(np.clip(full, 0, None)), 4)
                v = weekday_adjust(v)
                off = (dt.date.fromordinal(int(g[0])) - BASE).days
                v = v[off:off + len(g)]
            else:
                ext = ext_grid(kind)  # this panel's periods extended back to 2012 for the seasonal baseline
                acc, cnt = np.zeros(len(ext)), np.zeros(len(ext))
                for d, x in zip(days, vals):
                    if not np.isfinite(x):
                        continue
                    i = int(np.searchsorted(ext, period_of(kind, d)))
                    if i < len(ext) and ext[i] == period_of(kind, d):
                        y = x if metric in RATE_METRICS else (np.log(x) if x > 0 else np.nan)
                        if np.isfinite(y):
                            acc[i] += y
                            cnt[i] += 1
                v = np.where(cnt > 0, acc / np.maximum(cnt, 1), np.nan)
                v = seasonal_adjust(v, 52 if kind == "weekly" else 12)
                pos = {p: i for i, p in enumerate(ext)}
                v = np.array([v[pos[p]] if p in pos else np.nan for p in g])
            if np.isfinite(v).sum() < (365 if kind == "daily2" else 52 if kind == "weekly" else 12):
                continue
            names.append(label(name))
            rows.append(v.astype(np.float32))
            kept += 1
        per_source[src] = {"series": len(data), "kept": kept}
    out = {"articles": np.array(names), "days": g, "views": np.stack(rows), "raw": np.array(True)}
    if kind != "daily2":
        out.update(step=np.array(7 if kind == "weekly" else 30),
                   ct_lo=np.array(-2 if kind == "weekly" else -1), ct_hi=np.array(13 if kind == "weekly" else 3))
    np.savez_compressed(os.path.join(CACHE, f"{kind}_pv.npz"), **out)
    print(json.dumps({"panel": kind, "periods": len(g), "series": len(names), "per_source": per_source,
                      "examples": names[:3] + names[-3:]}, indent=1), flush=True)
    return 0 if names else 1


if __name__ == "__main__":
    sys.exit(main())
