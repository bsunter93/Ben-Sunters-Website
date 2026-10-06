// The search (a visitor, Oct 5: "the search bar should be more visible"). On a laptop or tablet the box is in the header
// at load, on screen and clear of the title (answered, the longest state), the tagline and the tally. On a phone a
// search button sits at the top of the header, opens the chooser and focuses the box. Typing a word shows results.
// node search_test.js [page]   exits 1 on a failure
const { pageUrl, browser } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]); let bad = 0;
  const sizes = [[1024, 768, 1], [1093, 614, 1.25], [1280, 800, 1], [1366, 768, 1], [1440, 900, 1], [820, 1180, 2, true], [390, 844, 3, true], [375, 667, 2, true]];
  for (const [w, h, dpr, touch] of sizes) for (const story of ['?m=tiger-king', '?c=sputnik-nasa-arpa']) {
    const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: dpr, hasTouch: !!touch, isMobile: !!touch && w < 600 });
    await pg.goto(base + story + '&nointro=1'); await pg.waitForTimeout(1200);
    const phone = w <= 560;
    const r = await pg.evaluate(phone => {
      const box = e => { if (!e) return null; const q = e.getBoundingClientRect(); return { l: q.left, t: q.top, r: q.right, b: q.bottom }; };
      const text = e => { if (!e) return null; const g = document.createRange(); g.selectNodeContents(e); return box(g); };
      const lines = e => { const g = document.createRange(); g.selectNodeContents(e); return [...g.getClientRects()].map(q => ({ l: q.left, t: q.top, r: q.right, b: q.bottom })); };  // each line of the title on its own: a long title wraps under the button's row
      const hit = (a, c) => !!(a && c && a.l < c.r - 4 && a.r > c.l + 4 && a.t < c.b - 4 && a.b > c.t + 4);  // 4 px: a text box includes the space above the capitals
      setPlaying(false); setMystery(false);  // the answered title is the widest the header gets
      const el = phone ? document.querySelector('#searchbtn') : document.querySelector('#search'), sb = box(el), cs = getComputedStyle(el);
      const tag = text(document.querySelector('.brand .tag')), wm = box(document.querySelector('.brand svg')), h1 = lines(document.querySelector('#h1')), tally = box(document.querySelector('#tally'));
      return { w: Math.round(sb.r - sb.l), h: Math.round(sb.b - sb.t), top: Math.round(sb.t), shown: cs.display !== 'none' && cs.visibility !== 'hidden', onScreen: sb.t >= 0 && sb.b <= innerHeight,
        hits: [h1.some(q => hit(sb, q)) && 'title', hit(sb, tag) && 'tagline', hit(sb, wm) && 'wordmark', !phone && hit(sb, tally) && 'tally'].filter(Boolean), ph: document.querySelector('#search').placeholder };
    }, phone);
    if (phone) await pg.tap('#searchbtn'); else await pg.click('#search');
    await pg.keyboard.type('prohibition'); await pg.waitForTimeout(900);
    const s = await pg.evaluate(() => { const i = document.querySelector('#search'), q = i.getBoundingClientRect(); return { focused: document.activeElement === i, inView: q.top >= 0 && q.bottom <= innerHeight, open: !document.querySelector('#chooser').hidden, results: document.querySelectorAll('#picker .chip').length }; });
    const ok = r.shown && r.onScreen && !r.hits.length && (phone ? r.w >= 40 && r.h >= 40 && r.top <= 60 : r.w >= 160 && r.h >= 30) && s.focused && s.open && s.results > 0;
    if (!ok) bad++;
    console.log(`${w}x${h} ${story.slice(3)}  ${phone ? 'button' : 'box'} ${r.w}x${r.h} at y ${r.top}${r.onScreen ? '' : ' (off screen)'}${r.hits.length ? ', overlaps ' + r.hits.join(', ') : ''}; "${r.ph}"; typed: focused ${s.focused}, in view ${s.inView}, ${s.results} results  ${ok ? 'ok' : 'FAIL'}`);
    await pg.close();
  }
  await b.close(); process.exit(bad ? 1 : 0);
})();
