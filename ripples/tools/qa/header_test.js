// How far down the pond starts on a phone, and what sits above it.
// node header_test.js [page]
const { pageUrl, browser } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]);
  for (const [w, h] of [[390, 844], [375, 667]]) for (const q of ['?c=squid-game-ripples&nointro=1', '?c=sputnik-nasa-arpa&nointro=1', '?m=tiger-king&nointro=1']) {
    const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2, hasTouch: true, isMobile: true });
    await pg.goto(base + q); await pg.waitForTimeout(1500);
    const r = await pg.evaluate(() => { const o = {}; for (const s of ['header', 'h1', '#sub', '.bar', '#pond']) { const e = document.querySelector(s); if (e) { const bb = e.getBoundingClientRect(); o[s] = [Math.round(bb.top), Math.round(bb.height)]; } } return o; });
    console.log(`${w}x${h} ${q}  pond top ${r['#pond'][0]} px  header ${r.header[1]} px  bar at ${r['.bar'][0]} (${r['.bar'][0] > r['#pond'][0] ? 'under the pond' : 'above the pond'})`);
    await pg.close();
  }
  await b.close();
})();
