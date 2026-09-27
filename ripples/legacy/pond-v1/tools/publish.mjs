/* Generates the static per-event ripple pages r/{slug}/index.html (GitHub Pages needs a real directory per URL) from r/index.html,
   with the OG meta baked in from the pond payload, and the root-relative asset paths adjusted. Run after each data publish:
     node tools/publish.mjs            -> uses data/pond/index.json + data/pond/{slug}.json (+ the Milton overlay for the flagship)
   404.html is not used: every published slug gets its own folder; unknown slugs fall back to r/?e=slug via the JS router. */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = dirname(fileURLToPath(import.meta.url)), ROOT = join(HERE, '..');
const SITE = 'https://bensunter.com/ripples/pond/';
const tpl = readFileSync(join(ROOT, 'r', 'index.html'), 'utf8');
const idx = JSON.parse(readFileSync(join(ROOT, 'data', 'pond', 'index.json'), 'utf8'));
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const TIER = { measured: 'Measured', likely: 'Likely', watching: 'Watching', flat: 'Stayed flat' };
let n = 0;
for (const row of idx.ponds) {
  const f = join(ROOT, 'data', 'pond', row.slug + '.json'); if (!existsSync(f)) continue;
  const P = JSON.parse(readFileSync(f, 'utf8'));
  const name = (P.event.name || row.name).replace(/ \(positive control\)$/, '');
  const E = (P.effects || []).slice().sort((a, b) => ({ measured: 3, likely: 2 }[(b.published || b).tier] || 0) - ({ measured: 3, likely: 2 }[(a.published || a).tier] || 0))[0];
  const tier = E ? (E.published || E).tier : (P.untested || []).length ? 'watching' : 'flat';
  // the tier word on the meta is the gated published tier; no other tier word may appear
  const sentence = (P.story && P.story.story_sentence || '').replace(/ \(positive control\)/g, '');
  const rho = E && E.engine && E.engine.rho && typeof E.engine.rho === 'object' ? E.engine.rho.shrunk : null;
  const feel = rho != null ? `${rho < 1 ? '−' : '+'}${Math.abs(Math.round((rho - 1) * 100))}% ${E.short || E.title}` : E ? `${E.short || E.title}` : '';
  const desc = `${sentence} ${E ? feel + '. ' + (TIER[tier] || tier) + '.' : ''} ${(P.flats || []).length ? (P.flats.length + ' things stayed flat. ') : ''}Consistent with, never proof of cause.`.replace(/\s+/g, ' ').trim();
  const og = row.slug === idx.flagship ? 'milton' : 'ripple-' + row.event_id;
  const ogFile = existsSync(join(ROOT, 'og', og + '.png')) ? og : 'milton';
  const meta = `<title>${esc(name)}, traced: Ripple Map</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${SITE}r/${row.slug}/">
<meta property="og:type" content="article">
<meta property="og:title" content="${esc((P.story && P.story.short_title || name).replace(/ \(positive control\)/g, ''))}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${SITE}r/${row.slug}/">
<meta property="og:image" content="${SITE}og/${ogFile}.png">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta property="og:image:alt" content="${esc(`A stone in a pond: ${name} at the centre; ${(P.effects || []).length} lily pad${(P.effects || []).length === 1 ? '' : 's'} for the things that moved, ${(P.flats || []).length} reed beds for the things that stayed flat.`)}">
<meta name="twitter:card" content="summary_large_image">`;
  let html = tpl.replace(/<!--META-->[\s\S]*?<!--\/META-->/, meta);
  html = html.replace(/(href|src)="\.\.\//g, '$1="../../').replace(/href="\.\.\/\.\.\/\.\.\/icon-192\.png"/, 'href="../../../icon-192.png"');
  mkdirSync(join(ROOT, 'r', row.slug), { recursive: true });
  writeFileSync(join(ROOT, 'r', row.slug, 'index.html'), html); n++;
}
console.log(`wrote ${n} ripple pages under r/{slug}/`);
