#!/usr/bin/env python3
"""Hand-cut launch GIF / MP4 for Ripple Map v6 (ART_DIRECTION §5.1 storyboard, re-cut for the Ripple Map per EXPERIENCE §7).

Run once, locally, by hand. It is NOT part of the pipeline. Input is a JSON file exported by SQL from one published,
reconstructed archive line (every number in it comes from att_cascade_versions / att_zvec; nothing is typed in here).

    python3 render_launch_gif.py line.json out_dir/

Outputs: launch-poster.png (frame 1), launch.gif (600x750, 15 fps, <= 64 colours, loop) and launch.mp4 (1080x1350, H.264,
silent, 7 s) when an ffmpeg binary is available (imageio-ffmpeg). "Reconstructed" is burned into every frame, and so is the
disclaimer "Consistent with, never proof of cause." (>= 18 px at 600 wide).

Fonts: the static OG TTFs from art/final/fonts (Anybody 900, IBM Plex Sans 500/700; OFL). Pass FONT_DIR to override.
"""
import json, math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

FONT_DIR = os.environ.get("FONT_DIR", os.path.join(os.path.dirname(__file__), "..", "..", "fonts"))
PETROL = (11, 58, 64); MARIGOLD = (242, 174, 46); STAGE = (237, 241, 238); CARD = (255, 255, 255)
ON_PANEL = (234, 243, 240); ON_PANEL_2 = (169, 196, 193); ON_PANEL_3 = (143, 176, 178); FLAT = (124, 156, 158)
PANEL_2 = (17, 72, 80); INK_2 = (60, 94, 98); INK_3 = (85, 114, 117)
W, H = 600, 750
FPS = 15


def font(name, size):
    return ImageFont.truetype(os.path.join(FONT_DIR, name), size)


def F(kind, size):
    return font({"display": "og-anybody-900.ttf", "bold": "og-plex-sans-700.ttf", "med": "og-plex-sans-500.ttf"}[kind], size)


def ease_out(t):
    return 1 - (1 - t) ** 3


def back_out(t, s=1.70158 * 0.6):   # ~6 % overshoot
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1


def fmt_x(v):
    return f"{v:.2f}".rstrip("0").rstrip(".") if v < 10 else f"{v:.0f}"


def wordmark(d, x, y, size=26, ink=PETROL, accent=MARIGOLD):
    f = F("display", size)
    d.text((x, y), "Knock", font=f, fill=ink)
    w = d.textlength("Knock", font=f)
    # the caret / spike hyphen, drawn (the TTFs have no U+2303)
    cx, top, bot = x + w + size * 0.32, y + size * 0.28, y + size * 0.62
    d.line([(x + w + 3, bot), (cx, top), (cx + size * 0.32 - 3, bot)], fill=accent, width=max(3, size // 8), joint="curve")
    d.text((x + w + size * 0.64 + 2, y), "On", font=f, fill=ink)


def stamp(d, x, y, text="RECONSTRUCTED", ink=PETROL):
    # the one permitted all-caps label: a 3 px bordered stamp (ART §5 "PRACTICE" stamp precedent)
    f = F("bold", 15)
    tw = d.textlength(text, font=f)
    d.rectangle([x - tw - 16, y, x, y + 28], outline=ink, width=3)
    d.text((x - tw - 8, y + 4), text, font=f, fill=ink)


def tile(d, x, y, s, kind, ink=PETROL, fill_marigold=False):
    """kind: shock | measured | likely | watching | unknown"""
    r = 6
    if kind == "shock":
        d.rounded_rectangle([x, y, x + s, y + s], r, fill=PETROL if not fill_marigold else MARIGOLD, outline=PETROL, width=3)
        # three concentric rings = 'start'
        c = (x + s / 2, y + s / 2)
        for k, rad in enumerate((s * 0.18, s * 0.30)):
            d.ellipse([c[0] - rad, c[1] - rad, c[0] + rad, c[1] + rad], outline=MARIGOLD if not fill_marigold else PETROL, width=3)
    elif kind == "measured":
        d.rounded_rectangle([x, y, x + s, y + s], r, fill=PETROL)
        pips(d, x + s * 0.18, y + s * 0.62, s * 0.64, 3, ON_PANEL)
    elif kind == "likely":
        d.rounded_rectangle([x, y, x + s, y + s], r, fill=CARD, outline=PETROL, width=3)
        for yy in range(int(y + 6), int(y + s - 4), 6):       # halftone rows
            for xx in range(int(x + 6 + (yy // 6 % 2) * 3), int(x + s - 4), 6):
                d.ellipse([xx - 1.4, yy - 1.4, xx + 1.4, yy + 1.4], fill=PETROL)
    elif kind == "watching":
        d.rounded_rectangle([x, y, x + s, y + s], r, fill=None, outline=PETROL, width=3)
    else:  # unknown '?'
        d.rounded_rectangle([x, y, x + s, y + s], r, fill=None, outline=PETROL, width=3)
        f = F("display", int(s * 0.55))
        tw = d.textlength("?", font=f)
        d.text((x + (s - tw) / 2, y + s * 0.14), "?", font=f, fill=PETROL)


def pips(d, x, y, w, n_on, ink):
    pw = w / 3 - 4
    for i in range(3):
        box = [x + i * (pw + 6), y, x + i * (pw + 6) + pw, y + pw * 0.9]
        if i < n_on:
            d.rectangle(box, fill=ink)
        else:
            d.rectangle(box, outline=ink, width=2)


def log_y(v, lo, hi, top, bot):
    v = max(lo, min(hi, v))
    return bot - (math.log(v) - math.log(lo)) / (math.log(hi) - math.log(lo)) * (bot - top)


def render(line, t_frame, total, spec):
    """Draw one frame. spec carries the timeline positions (in frames)."""
    img = Image.new("RGB", (W, H), STAGE)
    d = ImageDraw.Draw(img)
    # top strip
    wordmark(d, 20, 18)
    stamp(d, W - 20, 18)
    # the ticket (marigold): title, archive label, tile row
    d.rounded_rectangle([16, 62, W - 16, 262], 18, fill=MARIGOLD)
    title = line["title"]
    ft = F("display", 34 if len(title) <= 22 else 28)
    d.text((34, 78), title, font=ft, fill=PETROL)
    d.text((34, 124), line["kicker"], font=F("bold", 19), fill=PETROL)
    d.text((34, 150), "From the archive, reconstructed", font=F("med", 16), fill=PETROL)
    stops = line["stops"]
    n_rev = sum(1 for s in spec["kick"] if t_frame >= s[1])
    x = 34
    tile(d, x, 184, 58, "shock")
    for i, s in enumerate(stops):
        d.line([(x + 60, 213), (x + 92, 213)], fill=PETROL, width=6)
        x += 94
        tile(d, x, 184, 58, s["tier"] if i < n_rev else "unknown")
    # the staircase panel (petrol): y = x its own normal (log), x = days since the shock began
    top, bot, left, right = 290, 540, 66, W - 26
    d.rounded_rectangle([16, 276, W - 16, 636], 18, fill=PETROL)
    lo, hi = line["y_lo"], line["y_hi"]
    for g in line["grid"]:
        yy = log_y(g, lo, hi, top, bot)
        d.line([(left, yy), (right, yy)], fill=PANEL_2, width=1)
        d.text((24, yy - 9), fmt_x(g) + "×", font=F("bold", 14), fill=ON_PANEL_3)
    d0, d1 = line["x_from"], line["x_to"]
    def X(day):
        return left + (day - d0) / (d1 - d0) * (right - left)
    # onset line
    d.line([(X(0), top - 4), (X(0), bot + 4)], fill=ON_PANEL_3, width=2)
    d.text((X(0) + 5, bot + 8), "d0", font=F("bold", 13), fill=ON_PANEL_3)
    d.text((right - 70, bot + 8), f"+{d1} days", font=F("bold", 13), fill=ON_PANEL_3)
    d.text((24, 284), "× its own normal", font=F("med", 13), fill=ON_PANEL_2)
    # lanes: normal band + series; each lane draws flat first (clipped reveal), then its kick
    draw_p = min(1.0, max(0.0, (t_frame - spec["draw"][0]) / max(1, spec["draw"][1] - spec["draw"][0])))
    for i, s in enumerate(stops):
        ser = s["series"]
        kick0, kick1 = spec["kick"][i]
        kp = 0.0 if t_frame < kick0 else (1.0 if t_frame >= kick1 else back_out((t_frame - kick0) / (kick1 - kick0)))
        focus = kick0 <= t_frame < (spec["kick"][i + 1][0] if i + 1 < len(stops) else 10 ** 9)
        # band (its normal)
        bl, bh = s["band_lo"], s["band_hi"]
        d.rectangle([left, log_y(bh, lo, hi, top, bot), right, log_y(bl, lo, hi, top, bot)], fill=(27, 80, 87))
        pts = []
        xmax = d0 + draw_p * (d1 - d0)
        for k, v in enumerate(ser):
            day = s["from_day"] + k
            if day > xmax or day < d0 or v is None:
                continue
            vv = v if day < s["lag_days"] else 1 + (v - 1) * kp if v >= 1 else 1 - (1 - v) * kp
            pts.append((X(day), log_y(vv, lo, hi, top, bot)))
        if len(pts) > 1:
            d.line(pts, fill=MARIGOLD if (focus and kp > 0) else ON_PANEL, width=4 if focus else 3, joint="curve")
        if kp > 0:
            yy = log_y(1 + (s["peak"] - 1) * kp if s["peak"] >= 1 else 1 - (1 - s["peak"]) * kp, lo, hi, top, bot)
            d.text((min(right - 150, X(s["peak_day"]) + 8), yy - 30 if s["peak"] >= 1 else yy + 6), s["short"], font=F("bold", 15), fill=ON_PANEL)
    # the readout for the stop in focus: flap multiple, lag, tier, lookalikes
    cur = None
    for i, (k0, k1) in enumerate(spec["kick"]):
        if t_frame >= k0:
            cur = i
    if cur is not None:
        s = stops[cur]
        k0, k1 = spec["kick"][cur]
        p = min(1.0, (t_frame - k0) / max(1, k1 - k0))
        val = 1 + (s["rho"] - 1) * ease_out(p)
        flap = fmt_x(val) + "×"
        ff = F("display", 44)
        fw = d.textlength(flap, font=ff)
        d.rounded_rectangle([28, 568, 44 + fw, 624], 6, fill=MARIGOLD)
        d.text((36, 570), flap, font=ff, fill=PETROL)
        d.text((60 + fw, 570), s["label"], font=F("bold", 17), fill=ON_PANEL)
        d.text((60 + fw, 594), f"+{s['lag_days']} day{'s' if s['lag_days'] != 1 else ''} after the shock", font=F("med", 15), fill=ON_PANEL_2)
        if p >= 1:
            pips(d, W - 150, 574, 42, 3 if s["tier"] == "measured" else 2, ON_PANEL)
            d.text((W - 100, 572), s["tier"].capitalize(), font=F("bold", 16), fill=ON_PANEL)
    else:
        d.text((28, 578), line["question"], font=F("bold", 20), fill=ON_PANEL)
    # below the panel: the honest line
    if t_frame >= spec["hold"]:
        dl = line["day_line"]
        d.text((20, 648), dl, font=F("bold", 16), fill=PETROL)
        d.text((20, 672), line["lookalike"], font=F("med", 15), fill=INK_2)
    else:
        d.text((20, 652), line["sub"], font=F("med", 16), fill=INK_2)
    # footer disclaimer, every frame (>= 18 px)
    d.line([(16, 700), (W - 16, 700)], fill=(211, 221, 218), width=1)
    d.text((20, 712), "bensunter.com/ripples", font=F("bold", 18), fill=PETROL)
    d.text((W - 20 - d.textlength("Consistent with, never proof of cause.", font=F("med", 18)), 712),
           "Consistent with, never proof of cause.", font=F("med", 18), fill=INK_2)
    return img


def main(src, out):
    line = json.load(open(src))
    os.makedirs(out, exist_ok=True)
    n = len(line["stops"])
    spec = {"draw": (8, 14)}
    t = 16
    kicks = []
    for i in range(n):
        dur = 9 if i == 0 else 6
        kicks.append((t, t + dur))
        t += dur + 2
    spec["kick"] = kicks
    spec["hold"] = t
    total = t + 16          # hold ~1 s on the settled line and the honest day line
    frames = [render(line, 0 if f < 8 else f, total, spec) for f in range(total)]
    # crossfade back to the poster so the loop seam is invisible
    poster = frames[0]
    for k in range(1, 6):
        frames.append(Image.blend(frames[total - 1], poster, k / 6))
    poster.save(os.path.join(out, "launch-poster.png"), optimize=True)
    pal = poster.convert("P", palette=Image.ADAPTIVE, colors=64)
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    q[0].save(os.path.join(out, "launch.gif"), save_all=True, append_images=q[1:], duration=int(1000 / FPS), loop=0, optimize=True, disposal=1)
    # MP4 1080x1350, 7 s: 1 s poster hold, the beats, 2 s on the final hold
    try:
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        ff = None
    if ff:
        seq = [frames[0]] * FPS + frames[1:total] + [frames[total - 1]] * (2 * FPS)
        need = 7 * FPS
        seq = (seq + [frames[total - 1]] * need)[:need]
        tmp = os.path.join(out, "_mp4")
        os.makedirs(tmp, exist_ok=True)
        for i, f in enumerate(seq):
            f.resize((1080, 1350), Image.LANCZOS).save(os.path.join(tmp, f"f{i:04d}.png"))
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%04d.png"), "-c:v", "libx264",
                        "-pix_fmt", "yuv420p", "-an", "-movflags", "+faststart", os.path.join(out, "launch.mp4")], check=True)
        for fn in os.listdir(tmp):
            os.remove(os.path.join(tmp, fn))
        os.rmdir(tmp)
    print(json.dumps({"frames": len(frames), "gif_bytes": os.path.getsize(os.path.join(out, "launch.gif")),
                      "mp4": os.path.exists(os.path.join(out, "launch.mp4"))}))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
