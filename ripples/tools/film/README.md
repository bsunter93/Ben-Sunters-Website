# The launch film

The launch video is one take: Tiger King playing at the product's real pace in a 1280x720 page (33 s), with a slow push onto the water, back out for the cards, in for the House floor citation, and out for the answer. Every frame is captured on a paused clock that moves only when a frame asks, and CSS fades are stepped to the same clock, so a re-record after a UI change gives the same timing and smooth fades. The older multi-story cut (`cam.py`, `cut.py`, the title and end card) is kept for reference.

1. Serve the site root at `http://127.0.0.1:8748` (for example `python3 -m http.server 8748` from the repo root).
2. From an empty working folder: `node <repo>/ripples/tools/film/film.js <repo>/ripples/tools/qa "$PWD/filmout"` (add a shot name to record one shot). It also writes, per shot, where each step and every visible line of text sits on the frame.
3. `python3 <repo>/ripples/tools/film/camverify.py` checks that no camera hold cuts a word at the frame's edge; `camsearch.py` finds the tightest framing that cuts nothing.
4. Record only the take: add `take` after the output folder in step 2. Then `python3 <repo>/ripples/tools/film/cam_take.py` applies its camera (eased moves, about 3 s each) and `python3 <repo>/ripples/tools/film/cut1.py filmcam/take ripple-launch.mp4` encodes it (1600x900, 30 fps, H.264, BT.709).
5. If the story's timing changes, move the keyframes in `cam_take.py`: `meta.json` lists the frame where each step lands, and `camsearch.py` finds framings that cut no text.
6. The GIF (about 13 MB, under the 15-MB limit on X): `ffmpeg -i ripple-launch.mp4 -vf "fps=15,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -loop 0 ripple-launch.gif`

Needs Playwright (the qa folder's), ffmpeg and Pillow. The capture runs headless Chromium on the GPU (`--use-angle=metal`); the software renderer is too slow for the water.
