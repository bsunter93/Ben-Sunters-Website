import json
def rect(z, fx, fy, PW, PH):
    w, h = PW / z, PH / z; x0 = min(max(fx - w / 2, 0), PW - w); y0 = min(max(fy - h / 2, 0), PH - h); return x0, y0, x0 + w, y0 + h
def texts(m, a, b):
    seen = {}
    for f in m["frames"][a:b + 1]:
        for t in f["texts"]:
            if t[0].startswith("Clue") or t[0].startswith("A lasting"): t = [t[0], t[1] + t[3] / 2 - 150, t[2], 300, t[4]]  # the lower third's box spans the pond; its words sit in the middle
            seen[tuple(t)] = t
    return list(seen.values())
def cuts(ts, v, tol=2):
    x0, y0, x1, y1 = v; out = []
    for name, l, t, w, h in ts:
        r, b = l + w, t + h
        inside = l >= x0 - tol and r <= x1 + tol and t >= y0 - tol and b <= y1 + tol
        outside = r <= x0 + tol or l >= x1 - tol or b <= y0 + tol or t >= y1 - tol
        if not inside and not outside: out.append(name)
    return out
JOBS = [("tk_open", (46, 92), (440, 200, 800, 420)), ("tk_reveal", (0, 54), (100, 480, 520, 680)),
        ("sputnik", (52, 111), (1000, 440, 1420, 800)), ("bambi", (0, 10), (700, 420, 900, 600))]
for shot, (a, b), need in JOBS:
    m = json.load(open(f"filmout/{shot}/meta.json")); PW, PH = m["vw"], m["vh"]; ts = texts(m, a, b); best = None
    for zi in range(230, 120, -5):
        z = zi / 100
        for fx in range(0, PW, 6):
            for fy in range(0, PH, 6):
                v = rect(z, fx, fy, PW, PH)
                if not (v[0] <= need[0] and v[1] <= need[1] and v[2] >= need[2] and v[3] >= need[3]): continue
                if cuts(ts, v): continue
                cx, cy = (need[0] + need[2]) / 2, (need[1] + need[3]) / 2; d = ((v[0] + v[2]) / 2 - cx) ** 2 + ((v[1] + v[3]) / 2 - cy) ** 2
                if best is None or d < best[0]: best = (round(d), z, fx, fy, [int(q) for q in v])
        if best: break
    print(shot, best, "texts", len(ts))
