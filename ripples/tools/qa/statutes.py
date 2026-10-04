"""Confirm a Statutes at Large cite on govinfo before linking it.

    python3 statutes.py 72 426 85-568        -> fetches govinfo's page scan and looks for "Public Law 85-568" in its text layer
    python3 statutes.py --all                -> every Pub. L. on a chain step's source line, with the cite from the line or from SUPPLIED

Volumes before 1951 are scans without a readable text layer; for those the check is only that govinfo's granule begins at the cited page,
and the result says so. Honest user agent, one request a second, stop on any 4xx/5xx. See docs/sources_pass_v1.md.
"""
import glob, json, os, re, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
from pdfgrep import text_of, UA
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SUPPLIED = {"74-461": (49, 1148), "103-354": (108, 3178), "85-325": (72, 11), "91-605": (84, 1713), "102-240": (105, 1914), "92-500": (86, 816), "99-499": (100, 1613), "89-564": (80, 731), "99-509": (100, 1874)}

def norm(t): return re.sub(r"[^A-Za-z0-9]", "", t).upper()

def check(vol, page, pl):
    url = f"https://www.govinfo.gov/link/statute/{vol}/{page}"
    req = urllib.request.Request(url, headers={"User-Agent": UA}, method="HEAD")
    final = urllib.request.urlopen(req, timeout=60).geturl()
    if vol < 65:  # no text layer before 1951
        starts = f"Pg{page}" in final
        return final, ("granule starts at the cited page" if starts else "granule starts elsewhere"), starts
    cong, num = pl.split("-")
    ok = re.search("PUBLICLAW" + cong + num + r"(?!\d)", norm(text_of(final))) is not None
    return final, ("text names the law" if ok else "text does not name the law"), ok

def main():
    if sys.argv[1:2] == ["--all"]:
        rows = []
        for f in sorted(glob.glob(os.path.join(ROOT, "ripples", "chains", "*.json"))):
            d = json.load(open(f)); cs = d if isinstance(d, list) else d.get("chains", [d])
            for c in cs:
                for st in c.get("steps", []):
                    src = (st.get("test") or {}).get("source", "") or st.get("source", "")
                    for pl in re.findall(r"Pub\. L\. (\d+-\d+)", src):
                        m = re.search(r"Pub\. L\. " + re.escape(pl) + r", (\d+) Stat\. (\d+)", src)
                        rows.append((c["slug"], st["n"], pl, (int(m.group(1)), int(m.group(2))) if m else SUPPLIED.get(pl)))
    else:
        vol, page, pl = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]; rows = [("-", 0, pl, (vol, page))]
    for slug, n, pl, vp in rows:
        if not vp: print(f"{slug:24} {n:>2} {pl:8} no Stat. page known"); continue
        try: final, how, ok = check(vp[0], vp[1], pl)
        except Exception as e: final, how, ok = "", str(e), False
        print(f"{slug:24} {n:>2} {pl:8} {vp[0]:>3} Stat. {vp[1]:<5} {'OK ' if ok else 'NO '} {how}  {final}")
        time.sleep(1)

if __name__ == "__main__":
    main()
