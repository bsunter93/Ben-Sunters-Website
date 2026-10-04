#!/bin/bash
# Turn a reel recording into the kit's files.
#   encode.sh <name> <recording.webm> <wide|vertical> <start-seconds> <duration-seconds> [out-dir]
# Since Oct 4 the page plays an edited cut in reel mode (?reel=1): a still open, the throw, up to five shots with a camera
# push-in, an end card; about 12.5 s for Tiger King and 14.6 s for Sputnik. reel.js prints each cut's length; start about 0.3 s
# after load (check with: ffmpeg -ss 0 -t 2 -i rec.webm -vf fps=4,tile=8x1 -frames:v 1 start.png). The Oct 4 06:00 kit predates the cut.
# The last frame is held two seconds so the rest state reads. Wide: 1200x676 (16:9), 1080x1080 center crop, 800-px GIF. Vertical: 1080x1920.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
FF=${FFMPEG:-$(node -e "console.log(require('@ffmpeg-installer/ffmpeg').path)" 2>/dev/null || which ffmpeg)}
name=$1; src=$2; kind=$3; ss=$4; dur=$5; out=${6:-$HERE/../../launch}
HOLD="tpad=stop_mode=clone:stop_duration=2"
if [ "$kind" = wide ]; then
  "$FF" -y -loglevel error -ss "$ss" -t "$dur" -i "$src" -vf "scale=1200:676:flags=lanczos,$HOLD,format=yuv420p" -c:v libx264 -preset slow -crf 20 -movflags +faststart -an "$out/ripple-$name-1200.mp4"
  "$FF" -y -loglevel error -ss "$ss" -t "$dur" -i "$src" -vf "crop=720:720:260:0,scale=1080:1080:flags=lanczos,$HOLD,format=yuv420p" -c:v libx264 -preset slow -crf 20 -movflags +faststart -an "$out/ripple-$name-square.mp4"
  "$FF" -y -loglevel error -ss "$ss" -t "$dur" -i "$src" -vf "fps=12,scale=800:-1:flags=lanczos,$HOLD,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$out/ripple-$name.gif"
else
  "$FF" -y -loglevel error -ss "$ss" -t "$dur" -i "$src" -vf "scale=1080:1920:flags=lanczos,$HOLD,format=yuv420p" -c:v libx264 -preset slow -crf 20 -movflags +faststart -an "$out/ripple-$name-vertical.mp4"
fi
ls -la "$out" | grep "ripple-$name"
