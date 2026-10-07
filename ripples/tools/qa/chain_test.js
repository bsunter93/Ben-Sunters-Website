// The chain view (Oct 7, the default): the story reads as a list in date order beside the water. Plays Tiger King and
// Sputnik from the start at a phone, a tablet, a laptop and a desktop size and checks: the question row is up while the
// answer is withheld; the answer arrives within the time set below; the pond carries no words; rows never overlap and
// nothing scrolls sideways; a phone's guess closes when the answer shows; the story ends on what stayed and a next
// stone that opens one; ?view=pond still opens the pond.
// node chain_test.js [page]   exits 1 on a failure
process.env.QA_VIEW = 'chain';
const { pageUrl, browser } = require('./common');
const REVEAL_MAX = { 'tiger-king': 18, 'sputnik-nasa-arpa': 24 };  // seconds from load; the pond view took 26 and 30
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]); let bad = 0;
  const sizes = [[375, 812, true], [390, 844, true], [768, 1024, true], [1024, 768, false], [1440, 900, false]];
  const runs = [['?m=tiger-king&nointro=1', 'tiger-king', /Big Cat/], ['?c=sputnik-nasa-arpa&nointro=1', 'sputnik-nasa-arpa', /NASA/]];
  for (const [q, slug, answer] of runs) for (const [w, h, touch] of sizes) {
    if (slug !== 'tiger-king' && w !== 390 && w !== 1440) continue;
    const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2, hasTouch: touch, isMobile: touch && w < 600 });
    const errs = []; pg.on('pageerror', e => errs.push(e.message));
    const t0 = Date.now(); await pg.goto(base + q);
    let revealAt = null, qSeen = false, words = 0, overlap = 0, sideways = 0, chipsAfter = 0, end = null;
    for (let i = 0; i < 900; i++) {
      const st = await pg.evaluate(() => {
        const vis = e => { const r = e.getBoundingClientRect(), cs = getComputedStyle(e); return r.width > 0 && r.height > 0 && cs.display !== 'none' && cs.visibility !== 'hidden' && +cs.opacity > 0.05; };
        const rows = [...document.querySelectorAll('#feed > .card')].filter(vis).map(e => e.getBoundingClientRect());
        let ov = 0; for (let i = 1; i < rows.length; i++) if (rows[i].top < rows[i - 1].bottom - 1) ov++;
        const tl = document.querySelector('#tail');
        return { cv: document.documentElement.classList.contains('cv'), h1: document.querySelector('#h1').textContent, playing,
          q: !!tl && !tl.hidden && tl.classList.contains('q'), end: !!tl && !tl.hidden && tl.classList.contains('end') && !!tl.querySelector('.bnext'),
          words: [...document.querySelectorAll('#pond .nlab, #pond .callout, #pond .ringlbl, #pond .rimlbl, #pond .crestdate')].filter(vis).length,
          ov, side: document.documentElement.scrollWidth > innerWidth + 1 ? 1 : 0, wide: rows.filter(r => r.right > innerWidth + 1).length,
          chips: document.querySelectorAll('#guessrow:not([hidden]) .guess button, #sub .guess button').length };
      });
      const now = (Date.now() - t0) / 1000;
      if (!st.cv) { console.log(`${slug} ${w}x${h}: not the chain view  FAIL`); bad++; break; }
      if (st.q && revealAt === null) qSeen = true;
      if (revealAt === null && answer.test(st.h1)) revealAt = now;
      if (revealAt !== null && now > revealAt + 0.5 && st.chips) chipsAfter++;
      words = Math.max(words, st.words); overlap = Math.max(overlap, st.ov); sideways = Math.max(sideways, st.side + st.wide);
      if (!st.playing && st.end) { end = now; break; }
      await pg.waitForTimeout(100);
    }
    let next = false;
    if (end !== null) { const before = await pg.evaluate(() => document.querySelector('#h1').textContent); await pg.click('#tail .bnext'); await pg.waitForTimeout(800); next = await pg.evaluate(b4 => document.querySelector('#h1').textContent !== b4, before); }
    const ok = qSeen && revealAt !== null && revealAt <= REVEAL_MAX[slug] && !words && !overlap && !sideways && !chipsAfter && end !== null && next && !errs.length;
    if (!ok) bad++;
    console.log(`${slug} ${w}x${h}: question row ${qSeen ? 'up' : 'MISSING'}, answer at ${revealAt === null ? 'never' : revealAt.toFixed(1) + ' s'} (max ${REVEAL_MAX[slug]}), ended ${end === null ? 'never' : end.toFixed(1) + ' s'}, next stone ${next ? 'opens' : 'NO'}, words on the pond ${words}, overlapping rows ${overlap}, sideways ${sideways}, chips after the answer ${chipsAfter}, errors ${errs.length}  ${ok ? 'ok' : 'FAIL'}`);
    if (errs.length) console.log('   ' + errs.slice(0, 3).join('\n   '));
    await pg.close();
  }
  { const pg = await b.newPage({ viewport: { width: 1440, height: 900 } }); await pg.goto(base + '?m=tiger-king&nointro=1&view=pond'); await pg.waitForTimeout(800);
    const pond = await pg.evaluate(() => !document.documentElement.classList.contains('cv') && !document.querySelector('#tail'));
    if (!pond) bad++; console.log(`?view=pond: ${pond ? 'the pond' : 'STILL THE LIST'}  ${pond ? 'ok' : 'FAIL'}`); await pg.close(); }
  await b.close(); process.exit(bad ? 1 : 0);
})();
