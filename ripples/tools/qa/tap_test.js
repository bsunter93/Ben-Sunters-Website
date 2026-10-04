// Every ripple's tap target must answer to its own ripple, on the densest phone ponds.
// node tap_test.js [page]   (exit 1 if any tap lands on a neighbor)
const { pageUrl, browser, toEnd } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]); let failed = false;
  for (const [slug, w, h] of [['squid-game-ripples', 360, 800], ['tiger-king', 390, 844], ['america-and-alcohol', 390, 844], ['tiger-king', 1280, 900]]) {
    const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2, hasTouch: w < 800, isMobile: w < 800 });
    await pg.goto(`${base}?c=${slug}&nointro=1`); await pg.waitForTimeout(1200); await toEnd(pg);
    const centersNow = () => pg.evaluate(() => [...document.querySelectorAll('.node')].map(n => { const r = n.querySelector('.hit').getBoundingClientRect(); return [n.getAttribute('aria-label'), r.x + r.width / 2, r.y + r.height / 2, +r.width.toFixed(1)]; }));
    const centers = await centersNow();
    let wrong = 0;
    for (let i = 0; i < centers.length; i++) {
      if (await pg.evaluate(() => !!hot)) { await pg.evaluate(() => clearFocus()); await pg.waitForTimeout(200); }  // put the pond back between taps (a tap on the caption body does the same for a reader)
      const [label, x, y] = (await centersNow())[i];  // re-measure: focusing can scroll the page, and a reader taps what they see
      await pg.mouse.click(x, y); await pg.waitForTimeout(250);
      const got = await pg.evaluate(() => hot && hot.label);
      if (!got || !label.startsWith(got)) { wrong++; console.log(`  tap on "${label}" focused "${got}"`); }
    }
    const sizes = centers.map(c => c[3]);
    console.log(`${slug} ${w}x${h}: ${centers.length} ripples, targets ${Math.min(...sizes)}–${Math.max(...sizes)} px, taps wrong ${wrong}`);
    if (wrong) failed = true; await pg.close();
  }
  await b.close(); process.exit(failed ? 1 : 0);
})();
