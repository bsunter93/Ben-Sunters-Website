/* Minifies the pond's own sources into x.min.js / x.min.css (the pages load the .min files). Uses terser + csso when they are
   installed (npm i terser csso, anywhere on NODE_PATH or in the scratchpad tooling folder); otherwise falls back to a conservative
   comment-and-indentation strip. Run after any edit: node tools/minify.mjs [--check] */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const candidates = [ROOT, process.env.RM_TOOLING, '/tmp/claude-0/-home-user-Ben-Sunters-Website/2127681c-c6f5-5a11-a25b-dc64100bf0d0/scratchpad/tooling', '/opt/node22/lib/node_modules'].filter(Boolean);
let terser = null, csso = null;
for (const c of candidates) { try { const req = createRequire(join(c, 'package.json')); terser = terser || req('terser'); csso = csso || req('csso'); } catch { /* try the next */ } }
function jsFallback(src) { const out = []; let inBlock = false; for (const line of src.split('\n')) { const t = line.trim(); if (inBlock) { if (t.includes('*/')) inBlock = false; continue; } if (t.startsWith('/*')) { if (!t.includes('*/')) inBlock = true; continue; } if (t.startsWith('//') || !t) continue; out.push(t); } return out.join('\n'); }
const cssFallback = src => src.replace(/\/\*[\s\S]*?\*\//g, '').split('\n').map(l => l.trim()).filter(Boolean).join('\n');
const sizes = {};
for (const f of ['pond.js', 'site.js', 'ripple.js', 'now.js', 'evidence.js']) {
  const src = readFileSync(join(ROOT, f), 'utf8');
  const out = terser ? (await terser.minify(src, { compress: { passes: 2 }, mangle: true, format: { comments: false } })).code : jsFallback(src);
  writeFileSync(join(ROOT, f.replace('.js', '.min.js')), out); sizes[f] = out.length;
}
for (const f of ['app.css', 'pond.css', 'site.css']) {
  const src = readFileSync(join(ROOT, f), 'utf8');
  const out = csso ? csso.minify(src).css : cssFallback(src);
  writeFileSync(join(ROOT, f.replace('.css', '.min.css')), out); sizes[f] = out.length;
}
console.log(terser ? 'terser + csso' : 'fallback strip', JSON.stringify(sizes));
const ripple = ['pond.js', 'site.js', 'ripple.js', 'app.css', 'pond.css', 'site.css'].reduce((a, f) => a + sizes[f], 0);
console.log('ripple page initial JS+CSS:', ripple, ripple > 150 * 1024 ? 'OVER BUDGET' : 'ok (evidence.js loads on the first card open)');
