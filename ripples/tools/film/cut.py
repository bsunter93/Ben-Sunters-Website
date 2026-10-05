import os, subprocess, sys
shots = ["intro", "tk_open", "tk_reveal", "sputnik", "bambi", "end"]
F = 0.4
n = [len([f for f in os.listdir(s) if f.endswith(".jpg")]) for s in shots]
d = [k / 30 for k in n]
args = ["ffmpeg", "-loglevel", "error", "-y"]
for s in shots: args += ["-framerate", "30", "-i", f"{s}/%04d.jpg"]
fc = [f"[{i}]scale=1600:900:flags=lanczos:in_range=pc:out_range=tv,setsar=1,format=yuv420p[v{i}]" for i in range(len(shots))]
acc, prev = d[0], "v0"
for i in range(1, len(shots)):
    off = acc - F; out = f"x{i}"
    fc.append(f"[{prev}][v{i}]xfade=transition=fade:duration={F}:offset={off:.4f}[{out}]")
    acc = off + d[i]; prev = out
fc.append(f"[{prev}]fade=t=in:st=0:d=0.5,format=yuv420p[out]")
args += ["-filter_complex", ";".join(fc), "-map", "[out]", "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-r", "30", sys.argv[1]]
subprocess.run(args, check=True)
print("frames", n, "length %.2f s" % acc)
