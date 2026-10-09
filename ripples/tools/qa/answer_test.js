// The ripple chart (Oct 8, the default): the answer is the title from the first frame, then one chart plays the story row
// by row: one row per step on one clock, each line a page's readers against its own normal, a lasting mark as an amber bar.
// Checks, at a phone, a tablet and a desktop size: no guess anywhere; the title and the chart are on the first screen; the
// story plays to the row it lands on; row names never overlap; nothing scrolls sideways, even with every step open; Skip,
// Play again, a tap on a row, a shelf card, Next and a shared step each work; every story in the catalog draws its chart
// with no error and no "undefined"; ?view=chain and ?view=pond still open the earlier views.
// node answer_test.js [page]   exits 1 on a failure
process.env.QA_VIEW = 'answer';
const { pageUrl, browser } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]); let bad = 0;
  const say = (ok, line) => { if (!ok) bad++; console.log(`${line}  ${ok ? 'ok' : 'FAIL'}`); };
  const layout = () => {  // row names that overlap each other, chart parts outside the panel, and sideways scroll
    const names = [...document.querySelectorAll('#rcchart text.rcn')].map(e => e.getBoundingClientRect());
    let ov = 0; for (let i = 0; i < names.length; i++) for (let j = i + 1; j < names.length; j++) { const a = names[i], c = names[j]; if (a.left < c.right - 1 && c.left < a.right - 1 && a.top < c.bottom - 1 && c.top < a.bottom - 1) ov++; }
    const pan = document.querySelector('.avpaper').getBoundingClientRect(), out = [...document.querySelectorAll('#rcchart text')].filter(t => { const r = t.getBoundingClientRect(); return r.width && (r.left < pan.left - 1 || r.right > pan.right + 1); }).length;
    const route = [...document.querySelectorAll('#avright .avstream > li')].map(e => e.getBoundingClientRect()); let rov = 0; for (let i = 1; i < route.length; i++) if (route[i].height && route[i].top < route[i - 1].bottom - 1) rov++;
    return { ov, out, rov, rows: document.querySelectorAll('#rcchart g.rcrow[data-i]:not(.lab):not(.pk)').length, side: document.documentElement.scrollWidth > innerWidth + 1 };
  };
  for (const [w, h, touch] of [[375, 812, true], [390, 844, true], [768, 1024, true], [1440, 900, false]]) {
    const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2, hasTouch: touch, isMobile: touch && w < 600 });
    const errs = []; pg.on('pageerror', e => errs.push(e.message));
    await pg.goto(base + '?m=tiger-king&nointro=1'); await pg.waitForSelector('#rcchart svg', { timeout: 15000 });
    const pre = await pg.evaluate(() => ({ av: document.documentElement.classList.contains('av'), q: document.querySelector('#avq').textContent, guess: document.querySelectorAll('.avtile, .avskip, #guessrow button').length, chartTop: document.querySelector('#rcchart').getBoundingClientRect().top }));
    const t0 = Date.now();
    await pg.waitForFunction(() => cur && cur.rc && cur.rc.done, null, { timeout: 20000 }).catch(() => {});
    const playMs = Date.now() - t0;
    const post = await pg.evaluate(() => ({ cap: document.querySelector('#rccap').innerText, on: document.querySelectorAll('#rcchart g.rcrow.on:not(.lab):not(.pk)').length, all: cur.rc.rows.length, ember: true }));
    const l1 = await pg.evaluate(layout);
    await pg.evaluate(() => { document.querySelector('#rcsteps').open = true; }); await pg.waitForTimeout(250);
    await pg.click('.avall'); await pg.waitForTimeout(300); const l2 = await pg.evaluate(layout);
    say(pre.av && !pre.guess && /Tiger King → the Big Cat Act/.test(pre.q) && pre.chartTop < h && /Where it landed/.test(post.cap) && /Big Cat Public Safety Act/.test(post.cap) && post.on === post.all && post.all >= 6 && !l1.ov && !l1.out && !l1.side && !l2.rov && !l2.side && !errs.length,
      `tiger-king ${w}x${h}: guess controls ${pre.guess}, chart top ${Math.round(pre.chartTop)} px, played in ${(playMs / 1000).toFixed(1)} s to "${post.cap.split('\n').pop().slice(0, 44)}", ${post.on}/${post.all} rows, name overlaps ${l1.ov}, outside ${l1.out}, route overlaps ${l2.rov}, sideways ${l1.side || l2.side ? 'YES' : 'no'}${errs.length ? `, errors: ${errs.slice(0, 2).join(' | ')}` : ''}`);
    await pg.close();
  }
  // every story in the catalog, at a laptop size and a phone size: the chart at rest
  for (const [w, h] of [[1280, 800], [375, 812]]) {
    const pg = await b.newPage({ viewport: { width: w, height: h } }); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    await pg.goto(base + '?m=tiger-king&nointro=1'); await pg.waitForSelector('#rcchart svg', { timeout: 15000 });
    const r = await pg.evaluate(() => {
      const fails = [], seen = new Set(); let n = 0, lines = 0, onlyDots = 0;
      for (const p of allPonds()) {
        const key = `${p.kind}:${p.slug}`; if (seen.has(key)) continue; seen.add(key);
        if (p.kind === 'map' && !(MAPS[p.slug] && DATA.maps[p.slug]) && !(DATA.disc && DATA.disc.events[p.slug] && DATA.disc.events[p.slug].links.length)) continue;
        try {
          show(p.kind, p.slug); rcEnd(cur);
          const rows = document.querySelectorAll('#rcchart g.rcrow.on:not(.lab):not(.pk)').length, cap = document.querySelector('#rccap').innerText, txt = document.querySelector('#avmain').innerText;
          const names = [...document.querySelectorAll('#rcchart text.rcn')].map(e => e.getBoundingClientRect()); let ov = 0;
          for (let i = 0; i < names.length; i++) for (let j = i + 1; j < names.length; j++) { const a = names[i], c = names[j]; if (a.left < c.right - 1 && c.left < a.right - 1 && a.top < c.bottom - 1 && c.top < a.bottom - 1) ov++; }
          const bad = /\bundefined\b|\bNaN\b|\bnull\b|Invalid Date/.exec(txt);
          if (cur.rc.rows.some(x => x.lift)) lines++; else onlyDots++;
          if (rows < 1 || !cap.trim() || ov || bad || document.querySelector('.avtile')) fails.push(`${key}: rows ${rows}, caption "${cap.slice(0, 30)}", name overlaps ${ov}${bad ? `, prints "${bad[0]}"` : ''}`);
          n++;
        } catch (e) { fails.push(`${key}: ${e.message}`); }
      }
      return { n, fails, lines, onlyDots, side: document.documentElement.scrollWidth > innerWidth + 1 };
    });
    say(!r.fails.length && !errs.length && !r.side && r.n > 190, `every story at ${w}x${h}: ${r.n} drawn (${r.lines} with at least one line, ${r.onlyDots} dots only), ${r.fails.length} failed${r.fails.length ? '\n   ' + r.fails.slice(0, 8).join('\n   ') : ''}${errs.length ? `, errors: ${errs.slice(0, 2).join(' | ')}` : ''}`);
    await pg.close();
  }
  // Skip, Play again, a tap on a row, a shelf card, Next, a shared step
  { const pg = await b.newPage({ viewport: { width: 1440, height: 900 } }); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    await pg.goto(base + '?c=frozen&nointro=1'); await pg.waitForSelector('#rcplay', { timeout: 15000 });
    await pg.click('#rcplay'); await pg.waitForTimeout(300);
    const skip = await pg.evaluate(() => cur.rc.done && document.querySelectorAll('#rcchart g.rcrow.on:not(.lab):not(.pk)').length === cur.rc.rows.length);
    await pg.click('#rcplay'); await pg.waitForTimeout(300);
    const again = await pg.evaluate(() => !cur.rc.done && cur.rc.upto < cur.rc.rows.length - 1);
    await pg.click('#rcchart .rchit[data-i="1"]'); await pg.waitForTimeout(300);
    const tap = await pg.evaluate(() => cur.rc.done && cur.rc.cur === 1 && !!document.querySelector('#rcchart g.rcrow.cur'));
    const card = await pg.evaluate(() => { const c = document.querySelector('.avcard'); return c ? c.dataset.s : null; });
    await pg.click('.avcard'); await pg.waitForTimeout(600);
    const shelf = await pg.evaluate(s => cur.key === s && !!document.querySelector('#rcchart svg'), card);
    await pg.click('.avnext'); await pg.waitForTimeout(600);
    const nxt = await pg.evaluate(s => cur.key !== s && !!document.querySelector('#rcchart svg'), card);
    await pg.goto(base + '?m=tiger-king&s=m5&nointro=1'); await pg.waitForTimeout(1600);
    const step = await pg.evaluate(() => { const li = document.querySelector('#avright li.avn[data-id="m5"]'); return !!li && document.querySelector('#rcsteps').open && !!li.querySelector('details.avmore[open]') && li.getBoundingClientRect().top < innerHeight && li.getBoundingClientRect().bottom > 0; });
    say(skip && again && tap && shelf && nxt && step && !errs.length, `skip ${skip ? 'ends the story' : 'FAILED'}; play again ${again ? 'restarts it' : 'FAILED'}; a tap ${tap ? 'shows that row' : 'FAILED'}; shelf card ${shelf ? 'opens its chart' : 'FAILED'}; next ${nxt ? 'opens another' : 'FAILED'}; shared step ${step ? 'open and in view' : 'FAILED'}${errs.length ? `; errors: ${errs.slice(0, 2).join(' | ')}` : ''}`);
    await pg.close(); }
  // the earlier views
  for (const [v, cls] of [['chain', 'cv'], ['pond', null]]) {
    const pg = await b.newPage({ viewport: { width: 1440, height: 900 } }); await pg.addInitScript(() => { window.__rippleView = undefined; });
    await pg.goto(base + `?m=tiger-king&nointro=1&view=${v}`); await pg.waitForTimeout(900);
    const st = await pg.evaluate(() => ({ av: document.documentElement.classList.contains('av'), cv: document.documentElement.classList.contains('cv'), pond: !!document.querySelector('#pond .node, #pond g') }));
    say(!st.av && (cls ? st.cv : !st.cv && st.pond), `?view=${v}: ${st.av ? 'STILL THE CHART VIEW' : cls ? (st.cv ? 'the list' : 'NOT THE LIST') : (st.pond ? 'the pond' : 'NO POND')}`);
    await pg.close();
  }
  await b.close(); console.log(bad ? `${bad} failed` : 'all passed'); process.exit(bad ? 1 : 0);
})();
