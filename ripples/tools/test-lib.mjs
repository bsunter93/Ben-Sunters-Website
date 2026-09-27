// node ripples/tools/test-lib.mjs [--fold]   (exits non-zero on any failure)
// Ripple Map v6 (WS-D): lib.js against the WS-C v2 fixtures, the copy rules, the performance budget (EXPERIENCE §11) and,
// with --fold, the 360 × 640 fold check in headless Chromium (needs the global `playwright` package; skipped if absent).
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, extname } from 'node:path';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import * as L from '../lib.js';

const root = fileURLToPath(new URL('..', import.meta.url));
const FX = join(root, 'contract/fixtures/v2/');
const fx = f => JSON.parse(readFileSync(FX + f, 'utf8'));
let fails = 0, passes = 0;
const eq = (name, got, want) => {
  const g = JSON.stringify(got), w = JSON.stringify(want);
  if (g === w) { passes++; return; }
  fails++; console.error(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
};
const ok = (name, cond, info = '') => { if (cond) passes++; else { fails++; console.error(`FAIL ${name} ${info}`); } };

// ---------- lib against the fixtures ----------
const c = fx('cascade-1201.json'), v2 = fx('cascade-1201-v2.json'), hop = fx('hop-9001.json'), ret = fx('hop-9006-retracted.json'), shocks = fx('shocks.json');
const order = L.lineOrder(c);
eq('line order: outcome stations by onset, child after parent, attention ripple after, Watching last',
  order.map(e => `${e.n.hop_id}:${e.depth}`), ['9001:1', '9004:2', '9006:1', '9002:1', '9003:1', '9005:1']);
eq('all three tiers + retracted present in order', [...new Set(order.map(e => e.n.tier))].sort(), ['likely', 'measured', 'retracted', 'watching']);
eq('counts', L.counts(c), { measured: 1, likely: 3, watching: 1, retracted: 1, flat: 3 });
eq('stop count = Measured + Likely', L.stopCount(c), 4);
eq('line meta', L.lineMeta(c), ['4 stops', '3 domains', '3 days', 'still running']);
eq('line end: running', L.lineEnd(c), 'Line ends here for now.');
eq('line end: nowhere', L.lineEnd({ status: 'nowhere', denominators: { tested: 12 } }), 'Went nowhere: 12 paths tested, none moved.');
eq('line end: ended', L.lineEnd({ status: 'ended' }), 'Line ends: nothing downstream passed.');
eq('stop sentence (Measured)', L.plainParts(L.stopSentence(c.nodes[0], 'Hurricane Polo')), 'US air travellers ran 0.91× its normal, +1 day after Hurricane Polo.');
eq('stop sentence (same day)', L.plainParts(L.stopSentence(c.nodes[3], 'US air travellers')), 'Florida grid demand ran 0.84× its normal, the same day as US air travellers.');
eq('stop sentence (retracted)', L.plainParts(L.stopSentence(c.nodes[5], 'x')), 'Retracted 25 Sep: a later data revision pushed it below the bar.');
eq('stop sentence (Watching)', L.plainParts(L.stopSentence(c.nodes[4], 'x')), 'Florida jobless claims: no measurable move yet.');
eq('stop sentence (closed window, past tense)', L.plainParts(L.stopSentence({ ...c.nodes[4], window_closed: true }, 'x')), 'Florida jobless claims: its window closed 20 Oct. The result is pending.');
eq('points unit is never a multiple', L.plainParts(L.stopSentence({ ...c.nodes[0], unit: 'points', rho: 0.4 }, 'P')), 'US air travellers ran +0.40 points above its normal, +1 day after P.');
eq('rel points', L.rel(-0.4, 'points'), '0.40 points below its normal');
eq('evidence headline (shrunk + interval)', L.evidenceHeadline(hop), 'US air travellers at 0.91× [0.88–0.95] its normal, consistent with Hurricane Polo 1 day earlier.');
// ENGINE §8: the two fluke labels, exactly
eq('lookalikes label', L.lookalikes(58), 'A random pairing looks this strong about 1 in 58 times.');
eq('fluke-rate label (ENGINE §8 verbatim)', L.flukeRate(20, false), 'Links like this turn out to be flukes about 1 in 20 times.');
ok('fixture sentence carries both labels verbatim', c.nodes[0].sentence.includes(L.lookalikes(58)) && c.nodes[0].sentence.includes(L.flukeRate(20, false)));
eq('fluke rate capped at 1 in 50+ (ENGINE §5.4)', [L.flukeRate(50, false), L.flukeRate(312, false), L.flukeRate(49.7, false)], ['Links like this turn out to be flukes about 1 in 50+ times.', 'Links like this turn out to be flukes about 1 in 50+ times.', 'Links like this turn out to be flukes about 1 in 49 times.']);
eq('expected flukes are phrased against the Measured count', [L.flukeClause(0.7, 4), L.flukeClause(0.3, 1), L.flukeClause(0, 0), L.flukeClause(null, 3)], ['about 0.7 of those 4 expected to be flukes', 'about 0.3 expected to be a fluke', null, null]);
eq('a look after the window closes is the final look', [L.lookWord('2026-09-29', '2026-09-28'), L.lookWord('2026-09-27', '2026-09-28'), L.lookWord('2026-09-29', null)], ['Final look', 'Next look', 'Next look']);
eq('fluke warming', L.flukeRate(null, true), 'Fluke rate still warming up: too few decoy links this strong yet.');
eq('placebo strip', (({ n, exceed, lit }) => ({ n, exceed, lit }))(L.placeboStrip(hop.q5_luck.placebo)), { n: 2429, exceed: 39, lit: 3 });
eq('fluke meter tiles', [L.flukeTiles(20), L.flukeTiles(50), L.flukeTiles(250), L.flukeTiles(null)], [20, 0, 0, 0]);
eq('grown since (v2 → v3)', L.grownSince(v2, c), { version: 3, stops_added: 1 });
eq('grown since same version', L.grownSince(c, c), null);
eq('day line not available', L.dayLine({ source: 'not available', tested: null }), null);
eq('day line', L.dayLine(shocks.line), { tested: 612, moved: 23, measured: 4, expected: 0.7 });
eq('biggest (days since higher)', L.biggest(shocks.shocks[0]), 'Biggest day in 410 days');
eq('biggest (window)', L.biggest(shocks.shocks[3]), 'Highest in the 400 days we store');
eq('biggest (no data)', L.biggest({ biggest_basis: 'no_data' }), '');
eq('ancestors of a depth-2 stop', L.ancestors(c, 9004).map(n => n.hop_id), [9001]);
eq('route: line', L.parseRoute('/ripples/line/hurricane-polo-1201/'), { route: 'line', slug: 'hurricane-polo-1201', event: 1201 });
eq('route: version', L.parseRoute('/ripples/line/hurricane-polo-1201/v2/'), { route: 'line', slug: 'hurricane-polo-1201', event: 1201, version: 2 });
eq('route: stop', L.parseRoute('/ripples/line/hurricane-polo-1201/stop/9001/'), { route: 'stop', slug: 'hurricane-polo-1201', event: 1201, hop: 9001 });
eq('route: shell fallback keeps the path', L.parseRoute('/ripples/line/x-7/', { route: 'lines' }).route, 'line');
eq('route: stub attrs win', L.parseRoute('/ripples/line/x-7/stop/9/', { route: 'stop', event: '7', hop: '9' }).hop, 9);
eq('route: lands', L.parseRoute('/ripples/lands/real_world/'), { route: 'lands', domain: 'real_world' });
eq('route: week', L.parseRoute('/ripples/week/2026-39/'), { route: 'week', week: '2026-39' });
eq('iso week', [L.isoWeek('2026-09-26'), L.isoWeek('2027-01-01')], ['2026-39', '2026-53']);
eq('week range', L.weekRange('2026-39'), { from: '2026-09-21', to: '2026-09-27' });
eq('multiples', [L.mult(0.914), L.mult(3.42), L.mult(12.4), L.mult(null)], ['0.91×', '3.4×', '12×', '']);
eq('eight domains', L.DOMAINS.length, 8);
eq('share line uses the frozen text', L.shareLine(c), c.text_share);
ok('stop share has URL inside text and the disclaimer', /consistent with, not proof of cause\nhttps:\/\/bensunter\.com\/ripples\/line\/hurricane-polo-1201\/stop\/9001\/$/.test(L.shareStop(hop)));
ok('retracted stop share leads with the retraction', L.shareStop(ret).includes('Retracted: retracted 25 Sep'));
const X = L.xScale(28, 0, 100);
ok('x scale: linear to +7 then log', Math.abs(X(7) - 60) < 1e-9 && X(3.5) - X(0) === (X(7) - X(0)) / 2 && X(28) === 100 && X(14) < 100);

// ---------- copy rules over the built site (the files WS-D ships) ----------
const SHIP = ['index.html', 'app.js', 'ui.js', 'line.js', 'lists.js', 'help.js', 'app.css', 'lib.js', 'config.js', 'line/index.html', 'map/index.html', 'lands/index.html', 'week/index.html', 'archive/index.html', 'methods/index.html', 'manifest.webmanifest', 'remind.ics'];
const BANNED = [[/\bcaused\b/i, 'caused'], [/\bdrove\b/i, 'drove'], [/because of/i, 'because of'], [/passes like this are chance/i, 'passes like this are chance'],
  [/streak/i, 'streak'], [/🟩|🟨|🟥/u, 'share squares'], [/Knock-?⌃?On #\d|#\d+ ?(answer|puzzle)|puzzle #\d/i, '#N numbering'], [/\$[A-Z]{1,5}\b|\b(NASDAQ|NYSE)\b/, 'ticker symbol'],
  [/flooded into/i, 'flooded into'], [/chance this is chance/i, 'chance this is chance']];
// "points" is banned as a game score; the only allowed uses are the rate unit ("0.40 points above its normal") and its code token
const pointsOk = s => s.replace(/(point|points) (above|below|against) (its|their) (own )?normal/g, '').replace(/'points'|"points"|=== 'points'|unit: 'points'|points'\)|\? 'point' : 'points'|'1\.00' \? 'point'/g, '');
for (const f of SHIP) {
  const p = join(root, f); if (!existsSync(p)) { ok(`ships ${f}`, false); continue; }
  const s = readFileSync(p, 'utf8');
  for (const [re, name] of BANNED) ok(`${f}: no ${name}`, !re.test(s), (s.match(re) || [])[0]);
  ok(`${f}: no game points`, !/\bpoints\b|\b\d+ point\b/i.test(pointsOk(s)), (pointsOk(s).match(/.{30}(\bpoints\b|\b\d+ point\b).{30}/i) || [])[0]);
}

// the whole deployable /ripples/ tree, not only the files above: no retired v5 numbered stubs (ripples/{n}/), and every page
// and built file passes the same copy rules. Out of this sweep: tools/, contract/, attention/ (not served as pages), and docs/
// (the owner's print summary, which quotes the banned words as a list on purpose). /pro/ is in the sweep.
const SKIP = new Set(['tools', 'contract', 'attention', 'docs', 'node_modules']);
ok('no v5 numbered stub directories ripples/{n}/', !readdirSync(root).some(d => /^\d+$/.test(d) && statSync(join(root, d)).isDirectory()), readdirSync(root).filter(d => /^\d+$/.test(d)).length + ' found');
const walk = (d, out = []) => { for (const e of readdirSync(join(root, d), { withFileTypes: true })) { const r = d ? `${d}/${e.name}` : e.name; if (e.isDirectory()) { if (!(d === '' && SKIP.has(e.name))) walk(r, out); } else if (/\.(html|js|css)$/.test(e.name)) out.push(r); } return out; };
const site = walk('').filter(f => !SHIP.includes(f) && !/^(og|pipeline|ops)\//.test(f));
let siteBad = [];
for (const f of site) {
  const s = readFileSync(join(root, f), 'utf8');
  for (const [re, name] of BANNED) if (re.test(s)) siteBad.push(`${f}: ${name}`);
  if (/\bpoints\b|\b\d+ point\b/i.test(pointsOk(s))) siteBad.push(`${f}: game points`);
  if (f.endsWith('.html') && /fonts\.googleapis|fonts\.gstatic|<script[^>]+src="https?:/i.test(s)) siteBad.push(`${f}: external font or script`);
}
ok(`whole /ripples/ tree (${site.length} more files): copy rules`, !siteBad.length, siteBad.slice(0, 5).join('; '));
// /pro/ is kept as D-1 left it, but under the Ripple Map: no retired game vocabulary or v5 puzzle numbering
{ const s = readFileSync(join(root, 'pro/index.html'), 'utf8').replace(/value="player"/g, '').replace(/(content="|:\s*)#[0-9a-f]{3,8}\b/gi, '');
  const m = s.match(/.{0,30}(\bgames?\b|\bpuzzles?\b|\bplay(ing)?\b|\bBoard\b|'#' \+|[^&\w]#\d).{0,30}/i);
  ok('pro/index.html: no v5 game copy (game, puzzle, play, Board, #N)', !m, m && m[0]); }

// ---------- budget (EXPERIENCE §11): per route, shell HTML + CSS + every JS file it loads ≤ 120 KB uncompressed ----------
const size = f => statSync(join(root, f)).size;
const { srcHash } = await import('./build.mjs');
const dist = join(root, 'dist');
const banner = f => (readFileSync(join(dist, f), 'utf8').match(/Ripple Map ([0-9a-f]{16})/) || [])[1];
ok('dist/ is built from the current sources (run node ripples/tools/build.mjs)', banner('app.js') === srcHash() && banner('app.css') === srcHash(), `${banner('app.js')} vs ${srcHash()}`);
const deps = (f, seen = new Set()) => {
  if (seen.has(f)) return seen; seen.add(f);
  const t = readFileSync(join(dist, f), 'utf8');
  for (const m of t.matchAll(/(?:from|import)\s*"\.\/([\w.-]+\.js)"/g)) deps(m[1], seen);
  return seen;
};
const dyn = name => readdirSync(dist).find(f => f === name + '.js' || (f.startsWith(name + '-') && f.endsWith('.js')));
const routeJs = { 'index.html': [], 'line/index.html': ['line'], 'week/index.html': ['line'], 'map/index.html': ['lists'], 'lands/index.html': ['lists'], 'archive/index.html': ['lists'], 'methods/index.html': ['lists'] };
let js = 0;
for (const [shell, extra] of Object.entries(routeJs)) {
  const files = deps('app.js'); for (const x of extra) deps(dyn(x), files);
  const bytes = [...files].reduce((a, f) => a + statSync(join(dist, f)).size, 0);
  const inl = /<style id="rm-css">/.test(readFileSync(join(root, shell), 'utf8'));
  ok(`${shell}: CSS inlined from the current build`, inl && readFileSync(join(root, shell), 'utf8').includes(`Ripple Map ${srcHash()}: built from ripples/app.css`));
  const tot = size(shell) + (inl ? 0 : size('dist/app.css')) + bytes; js = Math.max(js, bytes);
  ok(`budget ${shell}: ${(tot / 1024).toFixed(1)} KB ≤ 120 KB`, tot <= 120 * 1024, `${tot}`);
}
ok('no external JS in shells', SHIP.filter(f => f.endsWith('.html')).every(f => !/<script[^>]+src="https?:/i.test(readFileSync(join(root, f), 'utf8'))));
ok('fonts self-hosted', !/fonts\.googleapis|fonts\.gstatic/.test(SHIP.filter(f => /html|css$/.test(f)).map(f => readFileSync(join(root, f), 'utf8')).join('')));
for (const [f, max] of [['shocks.json', 40], ['cascade-1201.json', 80], ['hop-9001.json', 40]]) ok(`payload ${f} ≤ ${max} KB`, size('contract/fixtures/v2/' + f) <= max * 1024);
console.log(`budget: largest JS set ${(js / 1024).toFixed(1)} KB, CSS ${(size('dist/app.css') / 1024).toFixed(1)} KB`);

// ---------- fold (headless Chromium, 360 × 640) ----------
if (process.argv.includes('--fold')) {
  let pw = null;
  try { pw = createRequire(import.meta.url)('playwright'); } catch (e) { try { pw = createRequire('/opt/node22/lib/node_modules/')('playwright'); } catch (e2) { pw = null; } }
  if (!pw) console.log('fold: skipped (playwright not installed)');
  else {
    const site = join(root, '..');
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
    const srv = createServer((q, r) => {
      let u = decodeURIComponent(q.url.split('?')[0]);
      // every /ripples/line/…/ URL falls back to the line shell, the way a host 404 fallback would
      if (/^\/ripples\/line\/.+\/$/.test(u) && !existsSync(join(site, u, 'index.html'))) u = '/ripples/line/';
      let f = join(site, u); if (u.endsWith('/')) f = join(f, 'index.html');
      if (!existsSync(f)) { r.writeHead(404); r.end(); return; }
      r.writeHead(200, { 'Content-Type': types[extname(f)] || 'application/octet-stream' }); r.end(readFileSync(f));
    }).listen(0);
    const port = srv.address().port;
    const MAP = { 'shocks/latest.json': 'shocks.json', 'cascade/1201.json': 'cascade-1201.json', 'archive.json': 'archive.json' };
    const exe = ['/opt/pw-browsers/chromium-1194/chrome-linux/chrome'].find(existsSync);
    const b = await pw.chromium.launch(exe ? { executablePath: exe } : {});
    for (const motion of ['no-preference', 'reduce']) {
      const ctx = await b.newContext({ viewport: { width: 360, height: 640 }, reducedMotion: motion });
      await ctx.route('https://kffkasnzqcddpystszch.supabase.co/**', rt => {
        const m = rt.request().url().split('/ripples/v2/')[1];
        const f = m && MAP[m.split('?')[0]];
        return f ? rt.fulfill({ status: 200, contentType: 'application/json', body: readFileSync(FX + f, 'utf8') }) : rt.fulfill({ status: 404, body: '{}' });
      });
      const pg = await ctx.newPage();
      await pg.goto(`http://127.0.0.1:${port}/ripples/`, { waitUntil: 'networkidle' });
      const home = await pg.evaluate(() => { const t = document.querySelector('.hero'), bt = document.querySelector('.hero .btn'); return { t: t && t.getBoundingClientRect().top, b: bt && bt.getBoundingClientRect().bottom, sw: document.documentElement.scrollWidth }; });
      ok(`fold (${motion}): hero ticket and Trace button above 640`, home.t != null && home.t >= 0 && home.b != null && home.b <= 640, JSON.stringify(home));
      ok(`fold (${motion}): no horizontal scroll on home at 360`, home.sw <= 360, String(home.sw));
      await pg.goto(`http://127.0.0.1:${port}/ripples/line/hurricane-polo-1201/`, { waitUntil: 'networkidle' });
      const line = await pg.evaluate(() => { const s = document.querySelector('.stop'), k = s && s.querySelector('.say'); return { top: s && s.getBoundingClientRect().top, say: k && k.getBoundingClientRect().top, sw: document.documentElement.scrollWidth }; });
      ok(`fold (${motion}): first stop card visible without scrolling`, line.top != null && line.top < 640 && line.say < 640, JSON.stringify(line));
      ok(`fold (${motion}): no horizontal scroll on the line at 360`, line.sw <= 360, String(line.sw));
      await ctx.close();
    }
    await b.close(); srv.close();
  }
}

console.log(`${passes} passed, ${fails} failed`);
process.exit(fails ? 1 : 0);
