// The second roundtable's three measurements: the legend inside a 614-px laptop fold, the caption not covering a small
// phone pond, and the first lasting mark on a phone inside 13 s. node fold_test.js [page]   exits 1 on a failure
const { pageUrl, browser } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]); let bad = 0;
  { const pg = await b.newPage({ viewport: { width: 1093, height: 614 }, deviceScaleFactor: 1.25 }); await pg.goto(base + '?m=tiger-king&nointro=1'); await pg.waitForTimeout(1200);
    const r = await pg.evaluate(() => { const l = document.querySelector('.legend').getBoundingClientRect(), p = document.querySelector('#pond').getBoundingClientRect(); return { legendBottom: Math.round(l.bottom), pondBottom: Math.round(p.bottom), vh: innerHeight }; });
    const ok = r.legendBottom <= r.vh && r.pondBottom <= r.vh; if (!ok) bad++; console.log(`1093x614 legend bottom ${r.legendBottom}, pond bottom ${r.pondBottom}, viewport ${r.vh}  ${ok ? 'ok' : 'FAIL'}`); await pg.close(); }
  { const pg = await b.newPage({ viewport: { width: 375, height: 667 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true }); await pg.goto(base + '?c=columbine-active-shooter&s=c3'); await pg.waitForTimeout(1500);
    const r = await pg.evaluate(() => { const c = document.querySelector('#caption').getBoundingClientRect(), p = document.querySelector('#pond').getBoundingClientRect(); return { cover: +(Math.max(0, Math.min(c.bottom, p.bottom) - Math.max(c.top, p.top)) / p.height).toFixed(2), flow: document.querySelector('#caption').classList.contains('flow'), pondH: Math.round(p.height) }; });
    const ok = r.cover <= 0.05; if (!ok) bad++; console.log(`375x667 caption covers ${Math.round(r.cover * 100)}% of a ${r.pondH}-px pond (flow ${r.flow})  ${ok ? 'ok' : 'FAIL'}`); await pg.close(); }
  { const pg = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, hasTouch: true, isMobile: true }); const t0 = Date.now(); await pg.goto(base + '?m=tiger-king&nointro=1'); let first = null, promise = null;
    for (let i = 0; i < 250; i++) { const st = await pg.evaluate(() => ({ mark: !!cur.items.find(x => x.mark && x.state === 'landed'), next: /Next lasting mark/.test(document.querySelector('#beatline').textContent) })); if (st.next && promise === null) promise = (Date.now() - t0) / 1000; if (st.mark) { first = (Date.now() - t0) / 1000; break; } await pg.waitForTimeout(100); }
    const ok = first !== null && first <= 16 && promise !== null && promise <= 4; if (!ok) bad++; console.log(`390x844 Tiger King: first lasting mark at ${first && first.toFixed(1)} s (16 s allowed; the two measured steps before it keep a 3.2-s hold), "Next lasting mark" line first shown at ${promise && promise.toFixed(1)} s (4 s allowed)  ${ok ? 'ok' : 'FAIL'}`); await pg.close(); }
  await b.close(); process.exit(bad ? 1 : 0);
})();
