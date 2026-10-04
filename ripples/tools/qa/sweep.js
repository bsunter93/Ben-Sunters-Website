// Screenshots of the main screens, desktop and phone, into an output folder.
// node sweep.js [page] [outDir]
const { pageUrl, browser, path, fs } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]), out = process.argv[3] || 'sweep'; fs.mkdirSync(out, { recursive: true }); const errs = [];
  const shot = (p, n, o = {}) => p.screenshot({ path: path.join(out, n + '.png'), ...o });
  let p = await b.newPage({ viewport: { width: 1300, height: 950 } }); p.on('pageerror', e => errs.push(e.message));
  await p.goto(base); await p.waitForTimeout(2500); await shot(p, 'intro');
  await p.goto(base + '?nointro=1'); await p.waitForTimeout(2000); await shot(p, 'home_start');
  await p.click('#chooserbtn'); await p.click('text=Fact-checks'); await p.click('#picker .chip'); await p.waitForTimeout(14000); await shot(p, 'factchecks');
  await p.click('#chooserbtn'); await p.click('text=Engine leads'); await p.click('#picker .chip'); await p.waitForTimeout(14000); await shot(p, 'leads');
  await p.click('text=How it works'); await p.waitForTimeout(800); await shot(p, 'how', { fullPage: true });
  await p.goto(base + '?c=sputnik-nasa-arpa&nointro=1'); await p.waitForTimeout(16000); await shot(p, 'sputnik_full', { fullPage: true });
  await p.close();
  p = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true }); p.on('pageerror', e => errs.push(e.message));
  await p.goto(base); await p.waitForTimeout(2500); await shot(p, 'phone_intro');
  await p.goto(base + '?m=tiger-king&nointro=1'); await p.waitForTimeout(14000); await shot(p, 'phone_tiger_king', { fullPage: true });
  console.log(errs.length ? 'page errors: ' + JSON.stringify(errs) : 'no page errors', '->', out); await b.close();
})();
