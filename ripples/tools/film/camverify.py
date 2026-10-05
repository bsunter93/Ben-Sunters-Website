import json
import os; exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "camsearch.py")).read().split("JOBS =")[0])
CAM = eval(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "cam.py")).read().split("CAM = ")[1].split("\ndef view")[0])
for shot, c in CAM.items():
    m = json.load(open(f"filmout/{shot}/meta.json")); PW, PH = m["vw"], m["vh"]; ks = c["keys"]
    for a, b in zip(ks, ks[1:] + [(len(m["frames"]) - 1,) + ks[-1][1:]]):
        if a[1:] != b[1:] or a[1] <= 1.0: continue  # only holds: moving frames may cross an edge
        off = c["keep"][0] - c.get("pad", 0); fa, fb = max(0, a[0] + off), max(0, b[0] + off)  # output frames back to recorded frames (a held first frame counts as frame 0)
        v = rect(a[1], a[2], a[3], PW, PH); print(shot, "hold", fa, "-", fb, "CUT:", cuts(texts(m, fa, fb), v))
