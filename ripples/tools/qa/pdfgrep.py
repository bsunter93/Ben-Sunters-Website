import sys, re, zlib, urllib.request
UA = "ripples-research/0.2 (+https://bensunter.com/ripples/methods/)"
def text_of(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    data = urllib.request.urlopen(req, timeout=60).read()
    out = []
    for m in re.finditer(rb"stream\r?\n(.*?)\r?\nendstream", data, re.S):
        try: s = zlib.decompress(m.group(1))
        except Exception: continue
        # text operators: (…) Tj and [(…)…] TJ
        parts = re.findall(rb"\((.*?)(?<!\\)\)", s)
        if parts: out.append(b"".join(parts))
    return b"\n".join(out).decode("latin-1", "replace")
if __name__ == "__main__":
    vol, page, needle = sys.argv[1], sys.argv[2], sys.argv[3]
    url = f"https://www.govinfo.gov/link/statute/{vol}/{page}"
    req = urllib.request.Request(url, headers={"User-Agent": UA}, method="HEAD")
    final = urllib.request.urlopen(req, timeout=60).geturl()
    t = text_of(final)
    print(final, len(t), "FOUND" if re.search(needle, t, re.I) else "not found", repr(t[:200]))
