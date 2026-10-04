// The pace of a story: when each ripple arrives, how long it holds, how long the whole thing runs, and that the line
// under the pond names each beat. Guards the Oct 4 beat schedule (BEAT in the page): no two beats closer than 2 s,
// a story between 15 and 95 s, a narration line on every hold.
// node pace_test.js [page]   exits 1 on a failure
const { pageUrl, browser } = require('./common');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]); let bad = 0;
  for (const q of ['?m=tiger-king&nointro=1', '?c=sputnik-nasa-arpa&nointro=1', '?c=america-and-alcohol&nointro=1']) {
    const pg = await b.newPage({ viewport: { width: 1440, height: 900 } });
    await pg.goto(base + q); await pg.waitForTimeout(300);
    const t0 = Date.now(), seen = new Map(), lines = []; let total = null, lastLine = '';
    for (let i = 0; i < 1000; i++) {
      const st = await pg.evaluate(() => ({ playing, landed: cur.items.filter(x => x.state === 'landed').map(x => x.id), line: (document.querySelector('#beatline') || {}).textContent || '', off: document.querySelector('#beatline').classList.contains('off'), beat: document.querySelector('#pond').classList.contains('beat') }));
      const now = (Date.now() - t0) / 1000;
      for (const id of st.landed) if (!seen.has(id)) seen.set(id, now);
      if (!st.off && st.line && st.line !== lastLine) { lines.push([now, st.line.slice(0, 70)]); lastLine = st.line; }
      if (!st.playing && seen.size) { total = now; break; }
      await pg.waitForTimeout(100);
    }
    const arrivals = [...seen.values()].sort((a, c) => a - c);
    const beats = arrivals.filter((v, i) => i === 0 || v - arrivals[i - 1] > 0.5);  // ripples landing together are one beat
    const gaps = beats.slice(1).map((v, i) => v - beats[i]);
    const minGap = gaps.length ? Math.min(...gaps) : 99;
    const ok = total !== null && total >= 15 && total <= 95 && minGap >= 2.0 && lines.length >= beats.length - 1;
    if (!ok) bad++;
    console.log(`${q}  ${seen.size} ripples in ${beats.length} beats, ${total === null ? 'did not finish' : total.toFixed(1) + ' s'}, shortest gap ${minGap.toFixed(1)} s, ${lines.length} narration lines  ${ok ? 'ok' : 'FAIL'}`);
    console.log('   arrivals (s): ' + arrivals.map(v => v.toFixed(1)).join(' '));
    for (const [at, ln] of lines.slice(0, 4)) console.log(`   ${at.toFixed(1).padStart(5)} s  ${ln}`);
    await pg.close();
  }
  await b.close(); process.exit(bad ? 1 : 0);
})();
