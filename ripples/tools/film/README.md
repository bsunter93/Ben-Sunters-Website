# The launch film

A 20-second cut of the demo working: a title card, Tiger King playing in the full page, close-ups on the floor citation and the law, Sputnik out to ARPANET, the Bambi splash, and an end card. Every frame is captured on a controlled clock, so a re-record after a UI change gives the same timing.

1. Serve the site root at `http://127.0.0.1:8748` (for example `python3 -m http.server 8748` from the repo root).
2. From an empty working folder: `node <repo>/ripples/tools/film/film.js <repo>/ripples/tools/qa "$PWD/filmout"` (add a shot name to record one shot). It also writes, per shot, where each step and every visible line of text sits on the frame.
3. `python3 <repo>/ripples/tools/film/camverify.py` checks that no camera hold cuts a word at the frame's edge; `camsearch.py` finds the tightest framing that cuts nothing.
4. `python3 <repo>/ripples/tools/film/cam.py` applies the camera (push-ins and pull-backs, eased) to the 2x frames.
5. `cd filmcam && python3 <repo>/ripples/tools/film/cut.py ../ripple-launch.mp4` joins the shots with dissolves (1600x900, 30 fps, H.264).
6. The GIF: `ffmpeg -i ripple-launch.mp4 -vf "fps=12,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -loop 0 ripple-launch.gif`

Needs Playwright (the qa folder's), ffmpeg and Pillow. The capture runs headless Chromium on the GPU (`--use-angle=metal`); the software renderer is too slow for the water.
