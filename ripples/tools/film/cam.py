# the camera, in post: each shot gets keyframes (frame, zoom, focus x, focus y in CSS px); between keys the view eases in and out
import json, os, shutil, sys
from PIL import Image
SRC, DST = "filmout", "filmcam"
def ease(u): return u * u * u * (u * (u * 6 - 15) + 10)  # smootherstep: starts and lands without a jolt
CAM = {
  # the product: wide on the page, in on the pond while the first steps land, back out to the cards
  "tk_open":   dict(keep=(0, 112), keys=[(0, 1.0, 640, 360), (14, 1.0, 640, 360), (40, 2.3, 618, 312), (78, 2.3, 618, 312), (102, 1.0, 640, 360)]),
  # the citation and the law, close; then back for the title's answer
  "tk_reveal": dict(keep=(0, 157), keys=[(0, 2.3, 510, 600), (54, 2.3, 510, 600), (102, 1.0, 800, 450)]),
  # the whole map while the title answers, then in on ARPANET as it lands and glows
  "sputnik":   dict(keep=(0, 112), keys=[(0, 1.0, 800, 450), (14, 1.0, 800, 450), (52, 2.25, 1212, 612)]),
  # tight on the stone and splash, pulled back as the wave reaches Smokey Bear
  "bambi":     dict(keep=(0, 130), pad=12, keys=[(0, 2.3, 804, 510), (30, 2.3, 804, 510), (70, 1.0, 800, 450)]),
}
def view(keys, i):
    if i <= keys[0][0]: return keys[0][1:]
    for a, b in zip(keys, keys[1:]):
        if i <= b[0]:
            u = ease((i - a[0]) / (b[0] - a[0]))
            wa, wb = 1 / a[1], 1 / b[1]  # the view's width moves evenly, so a zoom never seems to speed up at the end
            return (1 / (wa + (wb - wa) * u), a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u)
    return keys[-1][1:]
for shot in ["intro", "tk_open", "tk_reveal", "sputnik", "bambi", "end"]:
    out = os.path.join(DST, shot); shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
    files = sorted(f for f in os.listdir(os.path.join(SRC, shot)) if f.endswith(".jpg"))
    c = CAM.get(shot); meta = json.load(open(os.path.join(SRC, shot, "meta.json"))) if c else None
    if c: files = [files[c["keep"][0]]] * c.get("pad", 0) + files[c["keep"][0]:c["keep"][1]]  # a held first frame lets the dissolve land before the splash
    for k, f in enumerate(files):
        im = Image.open(os.path.join(SRC, shot, f)); W, H = im.size
        if c:
            z, fx, fy = view(c["keys"], k); s = meta["dsf"]; PW, PH = meta["vw"], meta["vh"]
            w, h = PW / z, PH / z; x0 = min(max(fx - w / 2, 0), PW - w); y0 = min(max(fy - h / 2, 0), PH - h)
            box = (x0 * s, y0 * s, (x0 + w) * s, (y0 + h) * s)
        else: box = (0, 0, W, H)
        im.resize((1600, 900), Image.LANCZOS, box=box).save(os.path.join(out, "%04d.jpg" % k), quality=94)
    print(shot, len(files))
