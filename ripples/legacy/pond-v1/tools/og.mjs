/* Renders the OG images for every share object into og/. Run after each publish: node tools/og.mjs [baseUrl] [outdir]
   Objects: the flagship ripple and its hero stop, every pond in the index with a Measured/Likely stop, every strong pattern, the top dead ends.
   Each image is checked against the tier guard: the word Measured may appear only when the object's published tier is measured. */
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire('/opt/node22/lib/node_modules/');
const { chromium } = require('playwright');
const HERE = dirname(fileURLToPath(import.meta.url)), ROOT = join(HERE, '..');
const BASE = process.argv[2] || 'http://127.0.0.1:8765/ripples/pond/';
const OUT = process.argv[3] || join(ROOT, 'og'); mkdirSync(OUT, { recursive: true });
const idx = JSON.parse(readFileSync(join(ROOT, 'data', 'pond', 'index.json'), 'utf8'));
const pats = JSON.parse(readFileSync(join(ROOT, 'data', 'patterns.json'), 'utf8')).patterns;
const objects = [];
for (const p of idx.ponds) {
  if (p.slug === idx.flagship) { objects.push(['ripple:' + p.slug, 'milton'], ['stop:' + p.slug + ':6101', 'stop-6101']); continue; }
  if (p.stops.measured + p.stops.likely > 0) objects.push(['ripple:' + p.slug, 'ripple-' + p.event_id]);
}
for (const p of pats) if (/pattern$/.test(p.strength)) objects.push(['pattern:' + p.id, 'pattern-' + p.id]);
objects.push(['dead:' + idx.flagship + ':6097', 'dead-6097']);   // US air travellers stayed flat after Milton: the counter-intuitive one
const only = process.argv[4]; const issues = [];
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const ctx = await browser.newContext({ viewport: { width: 1300, height: 2100 } });
for (const [o, name] of objects) {
  if (only && !name.includes(only)) continue;
  const p = await ctx.newPage();
  await p.goto(BASE + 'share.html?o=' + encodeURIComponent(o) + '&local=1'); await p.waitForSelector('body[data-ready="1"]', { timeout: 15000 }); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(600);
  const g = await p.evaluate(() => ({ tier: window.__shareTier, text: window.__shareText }));
  if (g.tier !== 'measured' && /\bmeasured\b/i.test(g.text)) issues.push(`${o}: card says measured while tier is ${g.tier}`);
  await p.locator('#land').screenshot({ path: join(OUT, name + '.png') });
  await p.locator('#port').screenshot({ path: join(OUT, name + '-portrait.png') });
  console.log('og', name, g.tier);
  await p.close();
}
await browser.close();
console.log(issues.length ? 'ISSUES:\n' + issues.join('\n') : `ok: ${objects.length} share objects, tier guard passed`);
if (issues.length) process.exit(1);
