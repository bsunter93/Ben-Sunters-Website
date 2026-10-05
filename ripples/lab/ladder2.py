"""Standard test v2 for a measured grade (pre-registered in ripples/docs/measure_plan_v1.md before any outcome value was
fetched). It reuses the evidence ladder's code (ripples/lab/ladder.py: the Series class, the placebo windows, the onset
rule, the excluded periods, the fetcher) and adds the two rungs the ladder reported but did not require.

A mark is MEASURED only if all three hold:
  (i)   its own outcome series passes the placebo-date test, in order: the change over the outcome window is unusual
        against every admissible window of the same shape in the series' own history before the stone (empirical
        p = (1 + placebo effects at least as large) / (1 + N) <= .05), the change is in the claimed direction, and no
        departure began before the stone (the ladder's onset rule; a rise that began first is busted);
  (ii)  it beats matched control stones: the same change, on the same series, after the nearest control stones of the
        same kind (similar size: drawn from a registered pool of major works of that kind; similar timing: nearest in
        date), none linked to the outcome and none whose windows touch the mark's own window;
        rank p = (1 + controls at least as large) / (1 + n) <= .10 with n >= 9 (so the mark must beat every control
        when n is 9 to 18 and all but one when n is 19);
  (iii) where the outcome has geography or another exposure dimension and an exposure measure is registered for the
        stone, the gradient points the right way: more exposure, bigger change (ordered groups: Spearman rho > 0 and the
        most exposed group changes more than the least exposed; a featured unit: its change exceeds the median change of
        the registered comparison units). Where no exposure measure exists, (iii) is "n/a" and the record says so.
Grade map: busted if the rise began before the stone; measured if (i), (ii) and (iii) all pass ((iii) may be n/a);
timed if (i) passes but (ii) or (iii) fails, or if (i) fails on p but a departure began inside the window, in order;
otherwise no movement (a mark with a citation keeps its reported grade).
Window shapes: "standard" is the ladder's (mean of the next h periods minus the mean of the previous h, in logs; h = 12
for monthly series, so every window holds each calendar month once; h = 1 for annual series). "paired" is the same
12-month window written as twelve year-over-year pairs, so a missing month (a zero, a seasonal closure, a registered
shutdown month) drops its pair from both halves instead of dropping the window; with all 24 months present it equals
"standard". "yoy" compares h months from the reference with the same h months a year earlier, for a short window on a
seasonal monthly series.
Reference period: monthly, the month that contains the stone's date, or the next month when the stone falls on or after
the 25th; annual, the stone's year, or the next year when the stone falls after June 30.
"""
from __future__ import annotations

import datetime as dt
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import ladder as L  # noqa: E402  (the evidence ladder's tested code, reused unchanged)

D = dt.date.fromisoformat
P_OWN, P_CONTROLS, MIN_CONTROLS = 0.05, 0.10, 9


def ref_date(stone, period_days):
    """the first period exposed to the stone"""
    if period_days >= 300:
        return dt.date(stone.year + (1 if stone.month > 6 else 0), 1, 1)
    if stone.day >= 25:
        return (stone.replace(day=28) + dt.timedelta(days=4)).replace(day=1)
    return stone.replace(day=1)


def periods(i, h, design):
    return set(range(i - h, i + h)) if design in ("standard", "paired") else set(range(i, i + h)) | set(range(i - 12, i - 12 + h))


MIN_PAIRS = 4


def eff(s, i, h, design):
    if design == "standard":
        return L.eff(s, i, h)
    if design == "paired":
        # the standard 12-month window written as twelve year-over-year pairs (y[i+k] - y[i+k-12]); a pair with a missing
        # month (a zero, a seasonal closure or a registered shutdown month, all NaN) is dropped from both halves, so the
        # calendar stays balanced; a window that touches an excluded period is dropped whole, as in the ladder
        if i is None or i - h < 0 or i + h > len(s.y) or s.excluded[i - h:i + h].any():
            return None
        if any(i - h < b <= i + h - 1 for b in s.breaks):
            return None
        d = s.y[i:i + h] - s.y[i - h:i]
        d = d[np.isfinite(d)]
        return float(d.mean()) if len(d) >= MIN_PAIRS else None
    if i is None or i - 12 < 0 or i + h > len(s.y):
        return None
    idx = sorted(periods(i, h, design))
    if s.excluded[idx].any() or np.isnan(s.y[idx]).any():
        return None
    if any(i - 12 < b <= i + h - 1 for b in s.breaks):
        return None
    return float(s.y[i:i + h].mean() - s.y[i - 12:i - 12 + h].mean())


def own_test(s, stone, h, design, direction, ref=None):
    """rung (i): placebo-date test against windows that end before the stone's own period, plus the ordering rule"""
    sign = 1 if direction == "up" else -1
    ref = ref or ref_date(stone, s.period_days)
    r, stone_i = s.index_of(ref), s.index_of(stone)
    if r is None or stone_i is None:
        return {"result": "the series does not cover the stone", "pass": False}
    obs = eff(s, r, h, design)
    if obs is None:
        return {"result": "the outcome window touches an excluded period, a break or missing data", "pass": False}
    pool = []
    for i in range(0, len(s.y)):
        ps = periods(i, h, design)
        if min(ps) < 0 or max(ps) >= stone_i or abs(i - r) <= 2 * h:
            continue
        e = eff(s, i, h, design)
        if e is not None:
            pool.append(e)
    n = len(pool)
    if n == 0:
        return {"result": "no admissible placebo window before the stone", "effect": round(obs, 4), "pass": False}
    p = (1 + sum(1 for x in pool if sign * x >= sign * obs)) / (1 + n)
    out = {"effect": round(obs, 4), "effect_pct": round(100 * (math.exp(obs) - 1), 1), "p": round(p, 4), "n_placebo": n,
           "p_floor": round(1 / (1 + n), 4), "ref": s.labels[r], "design": design, "h": h}
    out.update(L.onset(s, r, h, direction))
    tol = dt.timedelta(days=max(3, s.period_days))
    pos = sign * obs > 0
    on = D(out["onset"]) if out.get("onset") else None
    end = s.dates[min(r + h - 1, len(s.dates) - 1)]
    out["busted"] = bool(pos and on and on < stone - tol)
    out["onset_in_window"] = bool(pos and on and stone - tol <= on <= end)
    out["pass"] = bool(pos and p <= P_OWN and not out["busted"])
    out["window"] = {"after": [s.labels[r], s.labels[min(r + h - 1, len(s.labels) - 1)]],
                     "before": [s.labels[max(r - h, 0)], s.labels[r - 1]] if design == "standard" else
                     [s.labels[max(r - 12, 0)], s.labels[max(r - 12 + h - 1, 0)]]}
    return out


def control_test(s, stone, h, design, direction, real_effect, pool, n_max=19, ref=None):
    """rung (ii): pool = [(title, date)] already filtered to the same kind and to stones with no link to the outcome"""
    sign = 1 if direction == "up" else -1
    ref = ref or ref_date(stone, s.period_days)
    r = s.index_of(ref)
    if real_effect is None or r is None:
        return {"pass": False, "result": "no real effect to compare"}
    real_p = periods(r, h, design)
    cands = []
    for title, when in pool:
        d = D(when) if isinstance(when, str) else dt.date(int(when), 7, 1)
        if d == stone:
            continue
        c = s.index_of(ref_date(d, s.period_days))
        if c is None or periods(c, h, design) & real_p:
            continue
        e = eff(s, c, h, design)
        if e is None:
            continue
        cands.append((abs((d - stone).days), title, d.isoformat(), e))
    cands.sort()
    rows = cands[:n_max]
    n = len(rows)
    out = {"n": n, "controls": [{"control": t, "date": d, "effect": round(e, 4)} for _, t, d, e in rows]}
    if n < MIN_CONTROLS:
        out.update({"pass": False, "p_rank": None, "result": f"only {n} eligible controls; {MIN_CONTROLS} are needed to reach p <= .1"})
        return out
    k = sum(1 for *_, e in rows if sign * e >= sign * real_effect)
    out.update({"rank": 1 + sum(1 for *_, e in rows if sign * e > sign * real_effect), "of": n + 1,
                "p_rank": round((1 + k) / (1 + n), 4), "pass": (1 + k) / (1 + n) <= P_CONTROLS})
    return out


def spearman(x, y):
    rx, ry = _ranks(x), _ranks(y)
    if np.std(rx) == 0 or np.std(ry) == 0:
        return 0.0
    return float(np.corrcoef(rx, ry)[0, 1])


def _ranks(v):
    v = np.asarray(v, dtype=float)
    order = v.argsort()
    r = np.empty(len(v))
    r[order] = np.arange(len(v))
    for x in set(v.tolist()):  # average ties
        m = v == x
        r[m] = r[m].mean()
    return r


def gradient_ordered(groups, stone, h, design, direction, ref=None):
    """rung (iii), ordered exposure groups: groups = [(label, exposure, Series)]"""
    sign = 1 if direction == "up" else -1
    rows = []
    for label, x, s in groups:
        rr = s.index_of(ref or ref_date(stone, s.period_days))
        e = eff(s, rr, h, design) if rr is not None else None
        rows.append({"group": label, "exposure": x, "effect": None if e is None else round(e, 4),
                     "effect_pct": None if e is None else round(100 * (math.exp(e) - 1), 1)})
    ok = [g for g in rows if g["effect"] is not None]
    if len(ok) < 2:
        return {"mode": "ordered", "groups": rows, "pass": False, "result": "fewer than two groups with an effect"}
    hi = max(ok, key=lambda g: g["exposure"])
    lo = min(ok, key=lambda g: g["exposure"])
    rho = spearman([g["exposure"] for g in ok], [sign * g["effect"] for g in ok])
    passed = rho > 0 and sign * (hi["effect"] - lo["effect"]) > 0
    return {"mode": "ordered", "groups": rows, "spearman_rho": round(rho, 3), "most_minus_least": round(hi["effect"] - lo["effect"], 4), "pass": bool(passed)}


def gradient_featured(featured, comparison, stone, h, design, direction, ref=None):
    """rung (iii), a featured unit against registered comparison units: featured = (label, Series); comparison = [(label, Series)]"""
    sign = 1 if direction == "up" else -1
    lab, fs = featured
    rr = fs.index_of(ref or ref_date(stone, fs.period_days))
    fe = eff(fs, rr, h, design) if rr is not None else None
    comp = []
    for cl, cs in comparison:
        cr = cs.index_of(ref or ref_date(stone, cs.period_days))
        e = eff(cs, cr, h, design) if cr is not None else None
        if e is not None:
            comp.append((cl, e))
    if fe is None or len(comp) < 3:
        return {"mode": "featured", "featured": lab, "pass": False, "n_comparison": len(comp),
                "result": "no featured effect" if fe is None else "fewer than three comparison units with data"}
    med = float(np.median([e for _, e in comp]))
    k = sum(1 for _, e in comp if sign * e >= sign * fe)
    return {"mode": "featured", "featured": lab, "featured_effect": round(fe, 4), "comparison_median": round(med, 4),
            "n_comparison": len(comp), "in_space_rank": 1 + sum(1 for _, e in comp if sign * e > sign * fe),
            "in_space_p": round((1 + k) / (1 + len(comp)), 4), "pass": bool(sign * (fe - med) > 0),
            "comparison": [{"unit": c, "effect": round(e, 4)} for c, e in sorted(comp, key=lambda t: -sign * t[1])]}


def grade(own, ctrl, grad):
    """the v2 grade and the reasons, rung by rung"""
    if own.get("effect") is None:
        return "not run", [own.get("result", "no effect")]
    why = []
    if own.get("busted"):
        return "busted", ["the rise began before the stone"]
    g_ok = grad is None or grad.get("pass")
    why.append(f"(i) own series: p = {own.get('p')} (floor {own.get('p_floor')}), " + ("pass" if own["pass"] else "fail"))
    why.append("(ii) controls: " + (f"rank {ctrl.get('rank')} of {ctrl.get('of')}, p = {ctrl.get('p_rank')}, " if ctrl.get("p_rank") is not None else
                                    (ctrl.get("result") or "") + ", ") + ("pass" if ctrl.get("pass") else "fail"))
    why.append("(iii) gradient: " + ("n/a (no exposure measure registered)" if grad is None else ("pass" if grad.get("pass") else "fail")))
    if own["pass"] and ctrl.get("pass") and g_ok:
        return "measured", why
    if own["pass"] or own.get("onset_in_window"):
        return "timed", why
    return "no movement", why


def v2(s, stone, h, design, direction, control_pool, gradient=None, ref=None, n_controls=19):
    """run all three rungs on one mark. gradient = None or a callable returning a rung-(iii) dict"""
    own = own_test(s, stone, h, design, direction, ref=ref)
    ctrl = control_test(s, stone, h, design, direction, own.get("effect"), control_pool, n_max=n_controls, ref=ref) if own.get("effect") is not None else {"pass": False, "result": "not run"}
    grad = gradient() if (gradient and own.get("effect") is not None) else None
    g, why = grade(own, ctrl, grad)
    return {"grade_v2": g, "why": why, "own": own, "controls": ctrl, "gradient": grad}
