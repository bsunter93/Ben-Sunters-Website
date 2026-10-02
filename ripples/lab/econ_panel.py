"""Real-world outcome panel for the discovery engine: daily behavior-side series on the Wikipedia panel's day grid, so
q3_run.py can score event families against electricity demand, markets and air travel (ripples/docs/q3_protocol_econ.md).

Input: Supabase RPC att_q3_econ_export (ripples/attention/sql/50_att_q3_econ_export.sql), service role, read-only.
Output: $LAB_CACHE/econ_pv.npz with articles = readable series names, days = the Wikipedia panel's day ordinals,
views = the transformed series, raw = True (q3_run.py then uses the values as they are: no log, no cross-series median).

Transform (fixed before any event is scored):
- level series (electricity demand, TSA passengers, prices, exchange rates): natural log; rates stay in percentage points;
- gaps of up to 4 days (weekends, holidays) are carried forward; longer gaps stay missing;
- electricity demand and TSA passengers: minus the median of the same weekday over the previous 8 weeks, which removes
  the weekly cycle and slow seasonal drift using only the past.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools", "bq"))
from common import Supabase  # noqa: E402

CACHE = os.path.expanduser(os.environ.get("LAB_CACHE", "~/.cache/ripples-lab"))
FILL_MAX, WEEKS = 4, 8
FRED = {"DCOILBRENTEU": "Brent crude oil price", "DCOILWTICO": "WTI crude oil price", "DEXCAUS": "US dollar in Canadian dollars",
        "DEXCHUS": "US dollar in Chinese yuan", "DEXJPUS": "US dollar in Japanese yen", "DEXMXUS": "US dollar in Mexican pesos",
        "DEXUSEU": "Euro in US dollars", "DEXUSUK": "Pound in US dollars", "DHHNGSP": "Natural gas price (Henry Hub)",
        "DJFUELUSGULF": "Jet fuel price (Gulf Coast)", "DTWEXBGS": "Trade-weighted US dollar", "DFF": "Fed funds rate",
        "DGS10": "10-year Treasury yield", "DGS2": "2-year Treasury yield", "DGS30": "30-year Treasury yield",
        "DGS3MO": "3-month Treasury yield", "DGS5": "5-year Treasury yield", "SOFR": "SOFR overnight rate",
        "T10Y2Y": "10y-2y Treasury spread", "T10YIE": "10-year breakeven inflation", "T5YIE": "5-year breakeven inflation"}


def label(name: str) -> str:
    src, metric, key = name.split("|")
    if src == "eia.930":
        return f"Electricity demand: {key}" if metric == "demand" else f"Electricity demand (subregion): {key}"
    if src == "tsa.pax":
        return "Air travel: TSA checkpoint passengers"
    return f"Market: {FRED.get(key, key)}"


def ffill(v: np.ndarray, limit: int) -> np.ndarray:
    out, last, gap = v.copy(), np.nan, 0
    for i, x in enumerate(v):
        if np.isfinite(x):
            last, gap = x, 0
        else:
            gap += 1
            if np.isfinite(last) and gap <= limit:
                out[i] = last
    return out


def weekday_adjust(v: np.ndarray) -> np.ndarray:
    D = len(v)
    lags = np.full((WEEKS, D), np.nan)
    for k in range(1, WEEKS + 1):
        lags[k - 1, 7 * k:] = v[:D - 7 * k]
    ok = np.isfinite(lags).sum(0) >= WEEKS // 2
    with np.errstate(all="ignore"):
        base = np.nanmedian(np.where(np.isfinite(lags), lags, np.nan), axis=0)
    return np.where(ok, v - base, np.nan)


def main() -> int:
    grid = np.load(os.path.join(CACHE, "pv.npz"), allow_pickle=False)["days"]
    start = dt.date.fromordinal(int(grid[0]))
    data = Supabase().rpc("att_q3_econ_export", {}, timeout=300) or {}
    if dt.date.fromisoformat(data.get("start", "1900-01-01")) != start:
        print(f"export starts {data.get('start')}, panel starts {start}", flush=True)
        return 1
    names, rows = [], []
    for name, vals in sorted(data["series"].items()):
        v = np.array([np.nan if x is None else float(x) for x in vals], np.float64)[:len(grid)]
        v = np.concatenate([v, np.full(len(grid) - len(v), np.nan)])
        src, metric, _ = name.split("|")
        if metric != "rate":
            v = np.where(v > 0, np.log(np.where(v > 0, v, 1)), np.nan)
        v = ffill(v, FILL_MAX)
        if src in ("eia.930", "tsa.pax"):
            v = weekday_adjust(v)
        if np.isfinite(v).sum() < 365:
            continue
        names.append(label(name))
        rows.append(v.astype(np.float32))
    np.savez_compressed(os.path.join(CACHE, "econ_pv.npz"), articles=np.array(names), days=grid, views=np.stack(rows),
                        raw=np.array(True))
    cov = {k: int(np.isfinite(r).sum()) for k, r in zip(names, rows)}
    print(json.dumps({"series": len(names), "dropped": len(data["series"]) - len(names),
                      "median_days_with_data": int(np.median(list(cov.values()))),
                      "examples": names[:3] + names[-3:]}, indent=1), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
