// The answer view (Oct 8, the default): the water opens, a guess opens the answer at once, the route reads top to bottom
// and the shelf says where each stone lands. Checks, at a phone, a tablet and a desktop size: the four guess tiles are
// on the first screen; a guess shows the answer within a second and scores it; the route draws its rows without overlap;
// nothing scrolls sideways, even with every step open; Skip, a shelf card, Next and a shared step each work; every story
// in the catalog renders its answer and route with no error and no "undefined"; ?view=chain and ?view=pond still open
// the earlier views.
// node answer_test.js [page]   exits 1 on a failure
process.env.QA_VIEW = 'answer';
const { pageUrl, browser } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]); let bad = 0;
  const say = (ok, line) => { if (!ok) bad++; console.log(`${line}  ${ok ? 'ok' : 'FAIL'}`); };
  const layout = () => {
    const rows = [...document.querySelectorAll('#avright .avstream > li')].map(e => e.getBoundingClientRect());
    let ov = 0; for (let i = 1; i < rows.length; i++) if (rows[i].top < rows[i - 1].bottom - 1) ov++;
    return { ov, rows: rows.length, side: document.documentElement.scrollWidth > innerWidth + 1 };
  };
  for (const [w, h, touch] of [[375, 812, true], [390, 844, true], [768, 1024, true], [1440, 900, false]]) {
    const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2, hasTouch: touch, isMobile: touch && w < 600 });
    const errs = []; pg.on('pageerror', e => errs.push(e.message));
    await pg.goto(base + '?m=tiger-king&nointro=1'); await pg.waitForSelector('.avtile', { timeout: 15000 });
    const pre = await pg.evaluate(() => ({ av: document.documentElement.classList.contains('av'), tiles: [...document.querySelectorAll('.avtile')].filter(t => t.getBoundingClientRect().bottom <= innerHeight).length, q: document.querySelector('#avq').textContent }));
    await pg.click('.avtile[data-g="law"]'); const t0 = Date.now();
    await pg.waitForFunction(() => /Big Cat/.test(document.querySelector('#avleft .avhead')?.textContent || ''), null, { timeout: 3000 }).catch(() => {});
    const answerMs = Date.now() - t0; await pg.waitForTimeout(1900);
    const post = await pg.evaluate(() => ({ head: document.querySelector('#avleft .avhead')?.textContent || '', right: !!document.querySelector('.avverdict.right'), title: document.querySelector('#avq').textContent, line: !!document.querySelector('#avright svg.avline') }));
    const l1 = await pg.evaluate(layout);
    await pg.click('.avall'); await pg.waitForTimeout(300); const l2 = await pg.evaluate(layout);
    say(pre.av && pre.tiles === 4 && /What did Tiger King change/.test(pre.q) && /Big Cat/.test(post.head) && answerMs < 1000 && post.right && /→/.test(post.title) && post.line && !l1.ov && !l1.side && l2.rows > l1.rows && !l2.ov && !l2.side && !errs.length,
      `tiger-king ${w}x${h}: ${pre.tiles} tiles on the first screen, answer in ${answerMs} ms, verdict ${post.right ? 'right' : 'MISSING'}, ${l1.rows} rows (${l2.rows} with every step), overlap ${l1.ov + l2.ov}, sideways ${l1.side || l2.side ? 'YES' : 'no'}${errs.length ? `, errors: ${errs.slice(0, 2).join(' | ')}` : ''}`);
    await pg.close();
  }
  // every story in the catalog, at a laptop size: guess state, then the answer
  { const pg = await b.newPage({ viewport: { width: 1280, height: 800 } }); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    await pg.goto(base + '?m=tiger-king&nointro=1'); await pg.waitForSelector('.avtile', { timeout: 15000 });
    const r = await pg.evaluate(() => {
      const fails = [], seen = new Set(); let n = 0;
      for (const p of allPonds()) {
        const key = `${p.kind}:${p.slug}`; if (seen.has(key)) continue; seen.add(key);
        if (p.kind === 'map' && !(MAPS[p.slug] && DATA.maps[p.slug]) && !(DATA.disc && DATA.disc.events[p.slug] && DATA.disc.events[p.slug].links.length)) continue;
        try {
          show(p.kind, p.slug); const tiles = document.querySelectorAll('#avleft .avtile').length; avReveal('skip');
          const head = document.querySelector('#avleft .avhead')?.textContent || '', rows = document.querySelectorAll('#avright li.avn').length, txt = document.querySelector('#avmain').innerText;
          const bad = /\bundefined\b|\bNaN\b|\bnull\b|Invalid Date/.exec(txt);
          if (!tiles || !head.trim() || rows < 2 || bad) fails.push(`${key}: tiles ${tiles}, rows ${rows}, head "${head.slice(0, 30)}"${bad ? `, prints "${bad[0]}"` : ''}`);
          avAll = true; avRoute(cur, false); if (/\bundefined\b|\bNaN\b|Invalid Date/.test(document.querySelector('#avright').innerText)) fails.push(`${key}: every step prints undefined or NaN`); avAll = false;
          n++;
        } catch (e) { fails.push(`${key}: ${e.message}`); }
      }
      return { n, fails };
    });
    say(!r.fails.length && !errs.length && r.n > 190, `every story: ${r.n} rendered, ${r.fails.length} failed${r.fails.length ? '\n   ' + r.fails.slice(0, 8).join('\n   ') : ''}${errs.length ? `, errors: ${errs.slice(0, 2).join(' | ')}` : ''}`);
    await pg.close(); }
  // Skip, a shelf card, Next, a shared step
  { const pg = await b.newPage({ viewport: { width: 1440, height: 900 } }); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    await pg.goto(base + '?c=frozen&nointro=1'); await pg.waitForSelector('.avskip', { timeout: 15000 });
    await pg.click('.avskip'); await pg.waitForTimeout(400);
    const skip = await pg.evaluate(() => !!document.querySelector('#avleft .avhead') && !document.querySelector('.avverdict'));
    const card = await pg.evaluate(() => { const c = document.querySelector('.avcard'); return c ? c.dataset.s : null; });
    await pg.click('.avcard'); await pg.waitForTimeout(600);
    const shelf = await pg.evaluate(s => cur.key === s && !!document.querySelector('#avleft .avhead') && !document.querySelector('#avleft .avtile'), card);
    await pg.click('.avnext'); await pg.waitForTimeout(600);
    const nxt = await pg.evaluate(s => cur.key !== s && document.querySelectorAll('#avleft .avtile').length === 4, card);
    await pg.goto(base + '?m=tiger-king&s=m5&nointro=1'); await pg.waitForTimeout(1600);
    const step = await pg.evaluate(() => { const li = document.querySelector('#avright li.avn[data-id="m5"]'); return !!li && !!li.querySelector('details.avmore[open]') && li.getBoundingClientRect().top < innerHeight && li.getBoundingClientRect().bottom > 0; });
    say(skip && shelf && nxt && step && !errs.length, `skip ${skip ? 'shows the answer, no verdict' : 'FAILED'}; shelf card ${shelf ? 'opens its answer' : 'FAILED'}; next ${nxt ? 'opens a guess' : 'FAILED'}; shared step ${step ? 'open and in view' : 'FAILED'}${errs.length ? `; errors: ${errs.slice(0, 2).join(' | ')}` : ''}`);
    await pg.close(); }
  // the earlier views
  for (const [v, cls] of [['chain', 'cv'], ['pond', null]]) {
    const pg = await b.newPage({ viewport: { width: 1440, height: 900 } }); await pg.addInitScript(() => { window.__rippleView = undefined; });
    await pg.goto(base + `?m=tiger-king&nointro=1&view=${v}`); await pg.waitForTimeout(900);
    const st = await pg.evaluate(() => ({ av: document.documentElement.classList.contains('av'), cv: document.documentElement.classList.contains('cv'), pond: !!document.querySelector('#pond .node, #pond g') }));
    say(!st.av && (cls ? st.cv : !st.cv && st.pond), `?view=${v}: ${st.av ? 'STILL THE ANSWER VIEW' : cls ? (st.cv ? 'the list' : 'NOT THE LIST') : (st.pond ? 'the pond' : 'NO POND')}`);
    await pg.close();
  }
  await b.close(); console.log(bad ? `${bad} failed` : 'all passed'); process.exit(bad ? 1 : 0);
})();
