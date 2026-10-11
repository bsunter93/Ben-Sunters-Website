// The study's own reason under the answer (Oct 11): shown on every study story whose step carries test.why, hidden on
// the rest, the right label for tested vs suggested, and no sideways scroll. Usage: node why_test.js [page or URL]
process.env.QA_VIEW = 'answer';
const { pageUrl, browser, REPO, path, fs } = require('./common');
const base = pageUrl(process.argv[2]);
const want = {};
for (const b of ['batch18', 'batch19'])
  for (const c of JSON.parse(fs.readFileSync(path.join(REPO, 'ripples', 'chains', `${b}.json`))))
    for (const s of c.steps) if (s.test && s.test.type === 'study') want[c.slug] = s.test.why ? [s.test.why_kind === 'suggested' ? "The authors' best guess:" : 'Why, per the authors:', s.test.why] : null;
(async () => {
  const br = await browser(); let bad = 0, shown = 0, hidden = 0;
  for (const [w, h] of [[1440, 900], [375, 812]]) {
    const pg = await br.newPage({ viewport: { width: w, height: h } });
    for (const [slug, exp] of Object.entries(want)) {
      await pg.goto(base + (base.includes('?') ? '&' : '?') + `c=${slug}&nointro=1`);
      await pg.waitForSelector('#avq', { timeout: 15000 }); await pg.waitForTimeout(250);
      const r = await pg.evaluate(() => { const e = document.querySelector('#avwhyl'); const b = e && e.getBoundingClientRect();
        return { hidden: !e || e.hidden, text: e ? e.textContent : '', right: b ? b.right : 0, sideways: document.scrollingElement.scrollWidth > innerWidth + 1 }; });
      const ok = exp ? (!r.hidden && r.text === `${exp[0]} ${exp[1]}` && r.right <= w) : r.hidden;
      if (!ok || r.sideways) { bad++; console.log(`FAIL ${slug} ${w}: ${JSON.stringify(r)}`); }
      exp ? shown++ : hidden++;
    }
    await pg.close();
  }
  await br.close();
  console.log(`${shown} shown, ${hidden} hidden across two sizes, ${bad} failed  ${bad ? 'FAIL' : 'ok'}`);
  process.exit(bad ? 1 : 0);
})();
