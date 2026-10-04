// The spikes chart above the cards stays inside its column and carries no animation.
// Regression for the Oct 4 bug: the chart and the pond's expanding ring shared the class name .pulse,
// so the chart inherited a 7-second scale-and-fade and ballooned 7.5x over the pond as ghost text.
// node chart_test.js [page]   exits 1 on a failure
const { pageUrl, browser } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]); let bad = 0;
  for (const [w, h] of [[1440, 900], [1100, 825]]) for (const q of ['?m=tiger-king&nointro=1', '?c=sputnik-nasa-arpa&nointro=1', '?c=america-and-alcohol&nointro=1']) {
    const pg = await b.newPage({ viewport: { width: w, height: h } });
    await pg.goto(base + q); await pg.waitForTimeout(1200);
    const worst = { over: 0, anim: 'none', rings: 0 };
    for (let i = 0; i < 6; i++) {  // sample across the 7-second cycle the old bug ran on
      const r = await pg.evaluate(() => {
        const feed = document.querySelector('#feed'), ch = document.querySelector('.feed .pulse');
        if (!feed || !ch) return null;
        const fb = feed.getBoundingClientRect(), cb = ch.getBoundingClientRect(), svg = ch.querySelector('svg'), sb = svg ? svg.getBoundingClientRect() : cb;
        return { over: Math.max(cb.width - fb.width, sb.width - fb.width, 0), anim: getComputedStyle(ch).animationName, rings: document.querySelectorAll('#pond .wake').length };
      });
      if (!r) break;
      worst.over = Math.max(worst.over, r.over); if (r.anim !== 'none') worst.anim = r.anim; worst.rings = r.rings;
      await pg.waitForTimeout(1200);
    }
    const ok = worst.over < 2 && worst.anim === 'none' && worst.rings === 1;
    if (!ok) bad++;
    console.log(`${w}x${h} ${q}  chart over its column by ${worst.over.toFixed(1)} px, animation ${worst.anim}, pond rings ${worst.rings}  ${ok ? 'ok' : 'FAIL'}`);
    await pg.close();
  }
  await b.close(); process.exit(bad ? 1 : 0);
})();
