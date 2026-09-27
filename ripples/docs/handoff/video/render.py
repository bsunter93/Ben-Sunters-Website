import subprocess, os, imageio_ffmpeg
from playwright.sync_api import sync_playwright
FF=imageio_ffmpeg.get_ffmpeg_exe(); FPS=30; N=60*FPS
cmd=[FF,'-y','-f','image2pipe','-framerate',str(FPS),'-c:v','mjpeg','-i','-','-f','lavfi','-i','anullsrc=r=48000:cl=stereo',
     '-shortest','-c:v','libx264','-pix_fmt','yuv420p','-preset','medium','-crf','20','-movflags','+faststart','-c:a','aac','milton-60s.mp4']
ff=subprocess.Popen(cmd,stdin=subprocess.PIPE,stderr=subprocess.DEVNULL)
with sync_playwright() as p:
    b=p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    pg=b.new_page(viewport={'width':1080,'height':1920})
    pg.goto('file://'+os.getcwd()+'/scene_built.html'); pg.wait_for_timeout(600)
    for i in range(N):
        pg.evaluate(f'render({i/FPS})')
        ff.stdin.write(pg.screenshot(type='jpeg',quality=93))
    b.close()
ff.stdin.close(); ff.wait(); print('rc',ff.returncode)
