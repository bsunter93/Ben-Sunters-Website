import sys
from playwright.sync_api import sync_playwright
ts=[float(x) for x in sys.argv[1:]]
with sync_playwright() as p:
    b=p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome'); pg=b.new_page(viewport={'width':1080,'height':1920})
    pg.goto('file://'+__import__('os').getcwd()+'/scene_built.html'); pg.wait_for_timeout(500)
    for t in ts:
        pg.evaluate(f'render({t})'); pg.screenshot(path=f'still_{t}.png')
    b.close()
