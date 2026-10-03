"""Build the portable review kit: one offline HTML of the demo (fonts and data inlined) and a zip of the whole project
minus the multi-megabyte raw search results. Run from anywhere: python ripples/tools/build_portable.py
Writes ripples/dist/ripple-standalone.html and ripples/dist/ripple-review-kit.zip (the zip is not committed)."""
import base64, json, os, re, zipfile, datetime as dt

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
R = lambda *p: os.path.join(ROOT, *p)
OUT_HTML = R("ripples", "dist", "ripple-standalone.html")
OUT_ZIP = R("ripples", "dist", "ripple-review-kit.zip")


def standalone():
    h = open(R("ripples", "demo", "index.html"), encoding="utf-8").read()
    maps = re.findall(r'^  "([a-z0-9-]+)": \{h1:', h, re.M)  # the keys of MAPS
    data = {"/ripples/demo/discovered.json": json.load(open(R("ripples", "demo", "discovered.json"))),
            "/ripples/docs/results/chain_check_v1.json": json.load(open(R("ripples", "docs", "results", "chain_check_v1.json"))),
            "/ripples/docs/results/bill_act_v1.json": json.load(open(R("ripples", "docs", "results", "bill_act_v1.json")))}
    for s in maps:
        p = R("ripples", "maps", "out", f"{s}.json")
        if os.path.exists(p):
            data[f"/ripples/maps/out/{s}.json"] = json.load(open(p))
    for f in ["fraunces-latin-var", "fraunces-latin-var-italic", "plex-sans-latin-var"]:
        b64 = base64.b64encode(open(R("ripples", "fonts", f"{f}.woff2"), "rb").read()).decode()
        h = h.replace(f"url(/ripples/fonts/{f}.woff2)", f"url(data:font/woff2;base64,{b64})")
    h = h.replace('<link rel="icon" href="/favicon.svg">\n', "")
    shim = ("<script>const __D=" + json.dumps(data, ensure_ascii=False).replace("</", "<\\/") +
            ";const __f=window.fetch;window.fetch=(u,...a)=>{const k=String(u).split('?')[0];return k in __D?Promise.resolve({ok:true,json:()=>Promise.resolve(__D[k])}):__f(u,...a)};</script>\n")
    h = h.replace("<script>\n", shim + "<script>\n", 1)
    h = h.replace("</head>", f"<!-- Ripple standalone build {dt.date.today().isoformat()}: open this file directly; no server needed. Share pages and the discover pages link to bensunter.com. -->\n</head>", 1)
    os.makedirs(os.path.dirname(OUT_HTML), exist_ok=True)
    open(OUT_HTML, "w", encoding="utf-8").write(h)
    return len(maps), os.path.getsize(OUT_HTML)


SKIP_DIRS = {"node_modules", ".git", "__pycache__", "cultcache", "labcache"}
MAX_MB = 5


def kit():
    os.makedirs(os.path.dirname(OUT_ZIP), exist_ok=True)
    n = skipped = 0
    with zipfile.ZipFile(OUT_ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(R("ripples", "docs", "REVIEW_GUIDE.md"), "ripple/REVIEW_GUIDE.md")
        for base in ("ripples", ".github/workflows"):
            for dp, dns, fns in os.walk(R(*base.split("/"))):
                dns[:] = [d for d in dns if d not in SKIP_DIRS]
                for fn in fns:
                    p = os.path.join(dp, fn)
                    if p == OUT_ZIP or "/ripples/demo/cards/" in p or "/ripples/demo/s/" in p or "/ripples/dist/" in p and not p.endswith("ripple-standalone.html"):
                        continue  # share cards and stubs are generated; the old dist app is not part of Ripple
                    if os.path.getsize(p) > MAX_MB * 1024 * 1024 and not p.endswith((".mp4", ".html")):
                        skipped += 1; continue
                    z.write(p, os.path.join("ripple", os.path.relpath(p, ROOT)))
                    n += 1
    return n, skipped, os.path.getsize(OUT_ZIP)


if __name__ == "__main__":
    m, sz = standalone()
    print(f"standalone: {m} maps inlined, {sz / 1e6:.1f} MB -> {OUT_HTML}")
    n, sk, zs = kit()
    print(f"kit: {n} files, {sk} large results skipped, {zs / 1e6:.1f} MB -> {OUT_ZIP}")
