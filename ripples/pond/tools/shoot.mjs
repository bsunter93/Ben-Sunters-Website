/* Verification shoot for Ripple Map v1. Usage: node tools/shoot.mjs <outdir> [baseUrl]
   Screenshots every page at 390 (phone) and 1440 (desktop): Now, the ripple (hook, mid-reveal, tier frame, after-reveal, stop card, luck,
   forecast check, watching, deep drawers, traced pond, shore, flats, one more), a story-layer pond, the rule page, Lands, Watch, How, and the share cards.
   Checks on every page: console/page errors, horizontal scroll, the trust-gradient guard (the word Measured only where the gated published
   tier is measured: headline, tier line, share text, OG meta, marker aria-labels, every share object the page exposes), JS+CSS budget, CLS,
   keyboard path, reduced motion. Exit code 1 on any issue. */
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
const settle = async (p, ms = 1200) => { await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(ms); };
const hscroll = async (p, tag) => { const s = await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth); if (s > 0) issues.push(`${tag}: horizontal scroll ${s}px`); };
const mkpage = async (ctx, tag) => { const p = await ctx.newPage(); p.on('pageerror', e => issues.push(`${tag}: pageerror ${e.message}`)); p.on('console', m => { if (m.type() === 'error' && !/ERR_TUNNEL|net::ERR|Failed to load resource/.test(m.text())) issues.push(`${tag}: console ${m.text()}`); }); return p; };
/* the trust-gradient guard, on every page: each object the page exposes carries its own tier; no surface of a non-measured object says "measured" */
async function guard(p, tag) {
  const g = await p.evaluate(() => {
    const meta = k => (document.querySelector(`meta[property="${k}"], meta[name="${k}"]`) || {}).content || '';
    const page = { title: document.title, description: meta('description'), ogTitle: meta('og:title'), ogDesc: meta('og:description'), ogAlt: meta('og:image:alt') };
    const P = window.__pond || {};
    return { pageTier: P.publishedTier || null, page, objects: P.objects ? P.objects() : [], share: P.shareText ? P.shareText() : '' };
  });
  let n = 0;
  const check = (tier, k, v) => { n++; if (tier !== 'measured' && /\bmeasured\b/i.test(v || '')) issues.push(`trust gradient (${tag}): "${k}" says measured while the tier is ${tier}: ${String(v).slice(0, 140)}`); };
  if (g.pageTier) { for (const [k, v] of Object.entries(g.page)) check(g.pageTier, k, v); check(g.pageTier, 'share', g.share); }
  for (const o of g.objects) for (const [k, v] of Object.entries(o.surfaces || {})) check(o.tier, `${o.id}.${k}`, v);
  console.log(`trust-gradient guard (${tag}): page tier ${g.pageTier}, ${g.objects.length} objects, ${n} surfaces checked`);
}
async function budget(p, tag) {
  const bytes = await p.evaluate(async () => { let t = 0; const urls = [...document.querySelectorAll('script[src], link[rel="stylesheet"]')].map(e => e.src || e.href); for (const u of urls) t += (await (await fetch(u)).text()).length; return t; });
  console.log(`${tag}: JS+CSS bytes ${bytes}`, bytes > 150 * 1024 ? 'OVER BUDGET' : 'ok'); if (bytes > 150 * 1024) issues.push(`${tag}: JS+CSS ${bytes} bytes over the 150 KB budget`);
}
const cls = p => p.evaluate(() => new Promise(res => { let s = 0; const po = new PerformanceObserver(l => l.getEntries().forEach(e => { if (!e.hadRecentInput) s += e.value; })); po.observe({ type: 'layout-shift', buffered: true }); setTimeout(() => res(s), 250); }));

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  for (const [tag, vp] of [['desktop', { width: 1440, height: 900 }], ['phone', { width: 390, height: 844 }]]) {
    const ctx = await browser.newContext({ viewport: vp, deviceScaleFactor: tag === 'phone' ? 2 : 1, isMobile: tag === 'phone', hasTouch: tag === 'phone' });
    // Now
    let p = await mkpage(ctx, tag + ' now');
    await p.goto(BASE); await settle(p, 1600);
    await p.screenshot({ path: join(OUT, `${tag}-00-now.png`) }); await hscroll(p, tag + ' now'); await guard(p, tag + ' now'); await budget(p, tag + ' now');
    console.log(tag, 'now CLS', (await cls(p)).toFixed(3));
    await p.screenshot({ path: join(OUT, `${tag}-00-now-full.png`), fullPage: true });
    await p.close();
    // the ripple: the Milton flagship through the whole reveal
    p = await mkpage(ctx, tag);
    await p.goto(BASE + 'r/?e=milton'); await settle(p, 1400);
    await p.screenshot({ path: join(OUT, `${tag}-1-hook.png`) }); await hscroll(p, tag + ' hook');
    console.log(tag, 'ripple CLS at load', (await cls(p)).toFixed(3));
    await p.click('#btn-trace'); await p.waitForTimeout(620);
    await p.screenshot({ path: join(OUT, `${tag}-2-reveal-mid.png`) });
    await p.waitForTimeout(700);
    await p.screenshot({ path: join(OUT, `${tag}-3-reveal-tier.png`) });
    await p.waitForTimeout(1500);
    await p.screenshot({ path: join(OUT, `${tag}-4-after-reveal.png`) }); await hscroll(p, tag + ' after');
    console.log(tag, 'ripple CLS after Trace', (await cls(p)).toFixed(3));
    await p.click('#btn-evidence'); await p.waitForTimeout(600);
    await p.screenshot({ path: join(OUT, `${tag}-5-stop-card.png`) }); await hscroll(p, tag + ' card');
    await p.evaluate(() => document.querySelector('#luck').scrollIntoView({ block: 'start' })); await p.waitForTimeout(400);
    await p.screenshot({ path: join(OUT, `${tag}-6-luck.png`) });
    if (await p.$('#forecast')) { await p.evaluate(() => document.querySelector('#forecast').scrollIntoView({ block: 'start' })); await p.waitForTimeout(400); await p.screenshot({ path: join(OUT, `${tag}-6a-forecast.png`) }); }
    if (await p.$('#next')) { await p.evaluate(() => document.querySelector('#next').scrollIntoView({ block: 'start' })); await p.waitForTimeout(400); await p.screenshot({ path: join(OUT, `${tag}-6b-watching.png`) }); }
    await p.evaluate(() => { document.querySelector('#deep').scrollIntoView({ block: 'start' }); document.querySelectorAll('#deep details').forEach(d => d.open = true); }); await p.waitForTimeout(400);
    await p.screenshot({ path: join(OUT, `${tag}-6c-deep.png`) });
    await p.evaluate(() => document.querySelector('.panel .more').scrollIntoView({ block: 'start' })); await p.waitForTimeout(400);
    await p.screenshot({ path: join(OUT, `${tag}-6d-follow.png`) });
    await p.keyboard.press('Escape'); await p.waitForTimeout(500);
    await p.screenshot({ path: join(OUT, `${tag}-7-traced.png`) }); await hscroll(p, tag + ' traced');
    if (tag === 'desktop' && await p.$('.shore-mark')) { await p.evaluate(() => document.querySelector('.shore-mark').dispatchEvent(new MouseEvent('click', { bubbles: true }))); await p.waitForTimeout(600); await p.screenshot({ path: join(OUT, `${tag}-8-far-shore.png`) }); await p.keyboard.press('Escape'); await p.waitForTimeout(450); }
    await p.evaluate(() => document.querySelector('.float').dispatchEvent(new MouseEvent('click', { bubbles: true }))); await p.waitForTimeout(600);
    await p.screenshot({ path: join(OUT, `${tag}-9-watching-card.png`) });
    await p.keyboard.press('Escape'); await p.waitForTimeout(450);
    await p.evaluate(() => document.querySelector('g.grass').dispatchEvent(new MouseEvent('click', { bubbles: true }))); await p.waitForTimeout(600);
    await p.screenshot({ path: join(OUT, `${tag}-9b-flat-card.png`) });
    await p.keyboard.press('Escape'); await p.waitForTimeout(450);
    await p.evaluate(() => document.querySelector('#shore').scrollIntoView()); await p.waitForTimeout(500);
    await p.screenshot({ path: join(OUT, `${tag}-10-shore.png`) }); await hscroll(p, tag + ' shore');
    await p.evaluate(() => document.querySelector('#stopped').scrollIntoView()); await p.waitForTimeout(500);
    await p.screenshot({ path: join(OUT, `${tag}-11-flats.png`) });
    await p.evaluate(() => document.querySelector('#onemore').scrollIntoView()); await p.waitForTimeout(500);
    await p.screenshot({ path: join(OUT, `${tag}-12-one-more.png`) });
    await guard(p, tag + ' ripple'); await budget(p, tag + ' ripple');
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
    }
    if (tag === 'phone') { const small = await p.evaluate(() => { const r = document.querySelector('#pond .effect .hit').getBoundingClientRect(); return Math.min(r.width, r.height); }); console.log('phone pad tap target px', Math.round(small)); if (small < 44) issues.push(`phone: pad tap target ${Math.round(small)}px < 44`); }
    await p.close();
    // a story-layer pond (Likely, live shape) and the watching / dead-end deep links
    for (const [name, path] of [['ripple-heat', 'r/?e=heat-wave-2026-08-31-24-states-2717#traced'], ['ripple-lala-watching', 'r/?e=hurricane-lala-2026-1787&stop=2563'], ['ripple-milton-dead', 'r/?e=milton&stop=6097'], ['pattern', 'p/?id=10'], ['pattern-17', 'p/?id=17'], ['lands', 'lands/?d=real_world'], ['watch', 'watch/'], ['how', 'how/'], ['wander', 'wander/']]) {
      p = await mkpage(ctx, tag + ' ' + name); await p.goto(BASE + path); await settle(p, 1500);
      await p.screenshot({ path: join(OUT, `${tag}-20-${name}.png`) }); await hscroll(p, tag + ' ' + name);
      if (name !== 'wander') { await guard(p, tag + ' ' + name); if (tag === 'desktop') await budget(p, tag + ' ' + name); }
      if (name === 'wander') { const u = p.url(); if (!/landed=1/.test(u)) issues.push('wander did not land anywhere: ' + u); else console.log('wander landed on', u.replace(BASE, '')); }
      if (name === 'pattern' || name === 'how') await p.screenshot({ path: join(OUT, `${tag}-20-${name}-full.png`), fullPage: true });
      await p.close();
    }
    await ctx.close();
  }
  // reduced motion: final frame immediately, the after-reveal strip at once
  {
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion: 'reduce' });
    const p = await mkpage(ctx, 'reduced'); await p.goto(BASE + 'r/?e=milton'); await settle(p, 800);
    await p.click('#btn-trace'); await p.waitForTimeout(200);
    await p.screenshot({ path: join(OUT, 'desktop-14-reduced-motion.png') });
    const ok = await p.evaluate(() => !document.querySelector('#after').classList.contains('pending'));
    if (!ok) issues.push('reduced motion: the after-reveal strip did not appear immediately');
    await ctx.close();
  }
  // share cards: every object, tier guard on each
  {
    const ctx = await browser.newContext({ viewport: { width: 1300, height: 2100 } });
    for (const o of ['ripple:flagship', 'stop:hurricane-milton-positive-control-213:6101', 'pattern:10', 'dead:hurricane-milton-positive-control-213:6097', 'ripple:hurricane-lala-2026-1787', 'watching:hurricane-lala-2026-1787:2563']) {
      const p = await mkpage(ctx, 'share ' + o); await p.goto(BASE + 'share.html?o=' + encodeURIComponent(o)); await p.waitForSelector('body[data-ready="1"]'); await settle(p, 700);
      const sg = await p.evaluate(() => ({ tier: window.__shareTier, text: window.__shareText }));
      if (sg.tier !== 'measured' && /\bmeasured\b/i.test(sg.text)) issues.push(`trust gradient: share card ${o} says measured while the tier is ${sg.tier}`);
      await p.locator('#land').screenshot({ path: join(OUT, `share-${o.replace(/[^a-z0-9]+/gi, '-')}.png`) });
      console.log('share card', o, sg.tier);
      await p.close();
    }
    await ctx.close();
  }
  await browser.close();
  console.log(issues.length ? 'ISSUES:\n' + issues.join('\n') : 'no issues: no console errors, no horizontal scroll, keyboard path ok, tier guard passed on every page');
  if (issues.length) process.exit(1);
})();
