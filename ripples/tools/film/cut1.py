# one continuous take: no cuts, a short fade in from the page's own dark and out at the end so the loop closes softly
import os, subprocess, sys
src, out = sys.argv[1], sys.argv[2]
n = len([f for f in os.listdir(src) if f.endswith(".jpg")]); d = n / 30
vf = f"scale=1600:900:flags=lanczos:in_range=pc:out_range=tv,setsar=1,fade=t=in:st=0:d=0.4,fade=t=out:st={d - 0.6:.3f}:d=0.6,format=yuv420p"
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", "30", "-i", f"{src}/%04d.jpg", "-vf", vf, "-c:v", "libx264", "-preset", "slow", "-crf", "17",
                "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-r", "30", out], check=True)
print(n, "frames, %.1f s" % d)
