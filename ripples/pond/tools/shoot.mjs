/* Verification shoot for the pond slice. Usage: node tools/shoot.mjs <outdir> [baseUrl]
   Screenshots at 390 (phone) and 1440 (desktop): hook, mid-reveal, traced pond, stop card, luck panel, flats, watching, share cards.
   Also checks: console errors, horizontal scroll, reduced motion, a keyboard path. Renders og/milton.png and og/milton-portrait.png. */
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire('/opt/node22/lib/node_modules/');
const { chromium } = require('playwright');
const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = process.argv[2] || join(HERE, '..', '..', '..', 'shots'); const BASE = process.argv[3] || 'http://127.0.0.1:8765/ripples/pond/';
mkdirSync(OUT, { recursive: true });
const issues = [];
(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const settle = async (p, ms = 1200) => { await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(ms); };
  const hscroll = async (p, tag) => { const s = await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth); if (s > 0) issues.push(`${tag}: horizontal scroll ${s}px`); };
  const mkpage = async (ctx, tag) => { const p = await ctx.newPage(); p.on('pageerror', e => issues.push(`${tag}: pageerror ${e.message}`)); p.on('console', m => { if (m.type() === 'error') issues.push(`${tag}: console ${m.text()}`); }); return p; };

  for (const [tag, vp] of [['desktop', { width: 1440, height: 900 }], ['phone', { width: 390, height: 844 }]]) {
    const ctx = await browser.newContext({ viewport: vp, deviceScaleFactor: tag === 'phone' ? 2 : 1, isMobile: tag === 'phone', hasTouch: tag === 'phone' });
    const p = await mkpage(ctx, tag);
    await p.goto(BASE); await settle(p, 1400);
    await p.screenshot({ path: join(OUT, `${tag}-1-hook.png`) }); await hscroll(p, tag + ' hook');
    const clsLoad = await p.evaluate(() => new Promise(res => { let s = 0; const po = new PerformanceObserver(l => l.getEntries().forEach(e => { if (!e.hadRecentInput) s += e.value; })); po.observe({ type: 'layout-shift', buffered: true }); setTimeout(() => res(s), 200); }));
    console.log(tag, 'CLS at load', clsLoad.toFixed(3));
    await p.click('#btn-trace'); await p.waitForTimeout(620);
    await p.screenshot({ path: join(OUT, `${tag}-2-reveal-mid.png`) });
    await p.waitForTimeout(700);
    await p.screenshot({ path: join(OUT, `${tag}-3-reveal-tier.png`) });
    await p.waitForTimeout(1500);
    await p.screenshot({ path: join(OUT, `${tag}-4-stop-card.png`) }); await hscroll(p, tag + ' card');
    await p.evaluate(() => document.querySelector('#luck').scrollIntoView({ block: 'start' })); await p.waitForTimeout(400);
    await p.screenshot({ path: join(OUT, `${tag}-5-luck.png`) });
    await p.evaluate(() => document.querySelector('#next').scrollIntoView({ block: 'start' })); await p.waitForTimeout(400);
    await p.screenshot({ path: join(OUT, `${tag}-6-watching.png`) });
    await p.evaluate(() => { document.querySelector('#deep').scrollIntoView({ block: 'start' }); document.querySelectorAll('#deep details').forEach(d => d.open = true); }); await p.waitForTimeout(400);
    await p.screenshot({ path: join(OUT, `${tag}-6b-deep.png`) });
    await p.keyboard.press('Escape'); await p.waitForTimeout(500);
    await p.screenshot({ path: join(OUT, `${tag}-7-traced.png`) }); await hscroll(p, tag + ' traced');
    if (tag === 'desktop') { await p.evaluate(() => document.querySelector('.shore-mark').dispatchEvent(new MouseEvent('click', { bubbles: true }))); await p.waitForTimeout(600); await p.screenshot({ path: join(OUT, `${tag}-8-far-shore.png`) }); await p.keyboard.press('Escape'); await p.waitForTimeout(450); }
    await p.evaluate(() => document.querySelector('.float').dispatchEvent(new MouseEvent('click', { bubbles: true }))); await p.waitForTimeout(600);
    await p.screenshot({ path: join(OUT, `${tag}-9-untested.png`) });
    await p.keyboard.press('Escape'); await p.waitForTimeout(450);
    await p.evaluate(() => document.querySelector('#shore').scrollIntoView()); await p.waitForTimeout(500);
    await p.screenshot({ path: join(OUT, `${tag}-10-shore.png`) }); await hscroll(p, tag + ' shore');
    await p.evaluate(() => document.querySelector('#stopped').scrollIntoView()); await p.waitForTimeout(500);
    await p.screenshot({ path: join(OUT, `${tag}-11-flats.png`) });
    await p.evaluate(() => document.querySelector('#onemore').scrollIntoView()); await p.waitForTimeout(500);
    await p.screenshot({ path: join(OUT, `${tag}-12-one-more.png`) });
    await p.screenshot({ path: join(OUT, `${tag}-full.png`), fullPage: true });
    // keyboard path: Tab to the pad, Enter opens the card, Escape returns focus
    if (tag === 'desktop') {
      await p.evaluate(() => scrollTo(0, 0)); await p.focus('#pond .effect'); await p.keyboard.press('Enter'); await p.waitForTimeout(500);
      const open1 = await p.evaluate(() => document.querySelector('#panel').classList.contains('open') && document.activeElement.id === 'close');
      await p.keyboard.press('Escape'); await p.waitForTimeout(450);
      const back = await p.evaluate(() => document.activeElement && document.activeElement.classList.contains('effect'));
      if (!open1) issues.push('keyboard: Enter on the pad did not open the card with focus on close');
      if (!back) issues.push('keyboard: Escape did not return focus to the pad');
      await p.focus('#pond .effect'); await p.screenshot({ path: join(OUT, `${tag}-13-focus.png`) });
      const aria = await p.evaluate(() => [...document.querySelectorAll('#pond [tabindex="0"]')].map(g => g.getAttribute('aria-label')).filter(x => !x));
      if (aria.length) issues.push('a11y: markers without aria-label ' + aria.length);
      // budget
      const bytes = await p.evaluate(async () => { let t = 0; for (const f of ['pond.js', 'app.js', 'pond.css', 'app.css']) t += (await (await fetch(f)).text()).length; return t; });
      console.log('JS+CSS bytes', bytes, bytes > 150 * 1024 ? 'OVER BUDGET' : 'ok');
      const cls = await p.evaluate(() => new Promise(res => { let s = 0; const po = new PerformanceObserver(l => l.getEntries().forEach(e => { if (!e.hadRecentInput) s += e.value; })); po.observe({ type: 'layout-shift', buffered: true }); setTimeout(() => res(s), 300); }));
      console.log('CLS so far', cls.toFixed(3));
    }
    await ctx.close();
  }
  // reduced motion: final frame immediately, card opens at once
  {
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion: 'reduce' });
    const p = await mkpage(ctx, 'reduced'); await p.goto(BASE); await settle(p, 800);
    await p.click('#btn-trace'); await p.waitForTimeout(150);
    await p.screenshot({ path: join(OUT, 'desktop-14-reduced-motion.png') });
    const ok = await p.evaluate(() => document.querySelector('#panel').classList.contains('open'));
    if (!ok) issues.push('reduced motion: the card did not open immediately');
    await ctx.close();
  }
  // share cards -> OG images
  {
    const ctx = await browser.newContext({ viewport: { width: 1300, height: 2100 } });
    const p = await mkpage(ctx, 'share'); await p.goto(BASE + 'share.html'); await p.waitForSelector('body[data-ready="1"]'); await settle(p, 900);
    await p.locator('#land').screenshot({ path: join(HERE, '..', 'og', 'milton.png') });
    await p.locator('#port').screenshot({ path: join(HERE, '..', 'og', 'milton-portrait.png') });
    await p.locator('#land').screenshot({ path: join(OUT, 'share-1200x630.png') });
    await p.locator('#port').screenshot({ path: join(OUT, 'share-1080x1350.png') });
    await ctx.close();
  }
  await browser.close();
  console.log(issues.length ? 'ISSUES:\n' + issues.join('\n') : 'no issues: no console errors, no horizontal scroll, keyboard path ok');
})();
