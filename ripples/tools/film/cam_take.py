# the camera for the single take: open wide, push onto the water, back out for the cards, in for the floor citation, out for the answer
import json, os, shutil
from PIL import Image
import os; HERE = os.path.dirname(os.path.abspath(__file__)); exec(open(os.path.join(HERE, "cam.py")).read().split("CAM = {")[0].split("from PIL import Image")[1])  # ease()
src = open(os.path.join(HERE, "cam.py")).read(); exec("def view" + src.split("def view")[1].split("\nfor shot in")[0])
W0 = (1.0, 640, 360)
KEYS = [(0,) + W0, (90,) + W0,                       # 0-3 s: the whole page, the stone falls, the first card arrives
        (195, 2.3, 640, 344), (345, 2.3, 640, 344),  # 3-6.5 s in, 6.5-11.5 s on the water while the first steps land
        (450,) + W0, (585,) + W0,                     # 11.5-15 s back out: the first lasting mark lands with its card
        (680, 2.3, 572, 344), (752, 2.3, 572, 344),  # 19.5-22.7 s in: the House floor citation
        (857,) + W0]                                  # 25-28.6 s out as the law lands and the title answers; wide to the end
m = json.load(open("filmout/take/meta.json")); s = m["dsf"]; PW, PH = m["vw"], m["vh"]
out = "filmcam/take"; shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
files = sorted(f for f in os.listdir("filmout/take") if f.endswith(".jpg"))
for k, f in enumerate(files):
    z, fx, fy = view(KEYS, k); w, h = PW / z, PH / z; x0 = min(max(fx - w / 2, 0), PW - w); y0 = min(max(fy - h / 2, 0), PH - h)
    Image.open(os.path.join("filmout/take", f)).resize((1600, 900), Image.LANCZOS, box=(x0 * s, y0 * s, (x0 + w) * s, (y0 + h) * s)).save(os.path.join(out, "%04d.jpg" % k), quality=94)
print(len(files), "frames")
