// The fold measurements: the first card on screen at load on a laptop (owner, Oct 5), the caption not covering a small
// phone pond, and the first lasting mark on a phone inside 13 s. node fold_test.js [page]   exits 1 on a failure
const { pageUrl, browser } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]); let bad = 0;
  for (const [w, h, need] of [[1093, 614, 'title'], [1440, 800, 'whole']]) {  // the water look (Oct 5): the cards are the anchor, so the first card must be on screen at load; the key sits under the cards
    const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1.25 }); await pg.goto(base + '?m=tiger-king&nointro=1'); await pg.waitForTimeout(1500);
    const r = await pg.evaluate(() => { const c = document.querySelector('#feed .card:not(.off)'), p = document.querySelector('#pond').getBoundingClientRect(); const cb = c ? c.getBoundingClientRect() : {top: 9999, bottom: 9999}; return { cardTop: Math.round(cb.top), cardBottom: Math.round(cb.bottom), pondBottom: Math.round(p.bottom), vh: innerHeight }; });
    const ok = r.pondBottom <= r.vh && (need === 'whole' ? r.cardBottom <= r.vh : r.cardTop + 56 <= r.vh); if (!ok) bad++;
    console.log(`${w}x${h} first card ${r.cardTop}-${r.cardBottom}, pond bottom ${r.pondBottom}, viewport ${r.vh} (${need} card on screen)  ${ok ? 'ok' : 'FAIL'}`); await pg.close(); }
  { const pg = await b.newPage({ viewport: { width: 375, height: 667 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true }); await pg.goto(base + '?c=columbine-active-shooter&s=c3'); await pg.waitForTimeout(1500);
    const r = await pg.evaluate(() => { const c = document.querySelector('#caption').getBoundingClientRect(), p = document.querySelector('#pond').getBoundingClientRect(); return { cover: +(Math.max(0, Math.min(c.bottom, p.bottom) - Math.max(c.top, p.top)) / p.height).toFixed(2), flow: document.querySelector('#caption').classList.contains('flow'), pondH: Math.round(p.height) }; });
    const ok = r.cover <= 0.05; if (!ok) bad++; console.log(`375x667 caption covers ${Math.round(r.cover * 100)}% of a ${r.pondH}-px pond (flow ${r.flow})  ${ok ? 'ok' : 'FAIL'}`); await pg.close(); }
  { const pg = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, hasTouch: true, isMobile: true }); const t0 = Date.now(); await pg.goto(base + '?m=tiger-king&nointro=1'); let first = null, promise = null;
    for (let i = 0; i < 250; i++) { const st = await pg.evaluate(() => ({ mark: !!(typeof cur !== 'undefined' && cur && cur.items.find(x => x.mark && x.state === 'landed')), next: /lasting mark is .* away|Next lasting mark/.test((document.querySelector('#beatline') || {}).textContent || '') })); if (st.next && promise === null) promise = (Date.now() - t0) / 1000; if (st.mark) { first = (Date.now() - t0) / 1000; break; } await pg.waitForTimeout(100); }
    const ok = first !== null && first <= 16 && promise !== null && promise <= 4; if (!ok) bad++; console.log(`390x844 Tiger King: first lasting mark at ${first && first.toFixed(1)} s (16 s allowed; the two measured steps before it keep a 3.2-s hold), "Next lasting mark" line first shown at ${promise && promise.toFixed(1)} s (4 s allowed)  ${ok ? 'ok' : 'FAIL'}`); await pg.close(); }
  await b.close(); process.exit(bad ? 1 : 0);
})();
