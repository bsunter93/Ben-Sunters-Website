// node ripples/tools/gen-stubs.mjs [--from=<url|dir>] [--out=<ripples dir>] [--clean-numbered] [--check]
//
// Ripple Map v6 (WS-C): writes a static stub for every published route so each URL has its own <head> (title, description,
// canonical, Open Graph + Twitter tags with og:image:alt), the page's data inlined as JSON, and a no-JS list of the stops:
//   ripples/line/{slug}/index.html              latest version of a line          (og: ripples-og?v=line&e={id})
//   ripples/line/{slug}/v{k}/index.html         frozen version k (what gets shared; canonical → the live line)
//   ripples/line/{slug}/stop/{hop}/index.html   one stop's evidence card          (og: ripples-og?v=stop&h={hop})
//   ripples/lands/{domain}/index.html           the 8 reverse views
//   ripples/week/{yyyy-ww}/index.html           weekly editions that exist
// Data: the published Storage mirror (default https://kffkasnzqcddpystszch.supabase.co/storage/v1/object/public/ripples/v2/)
// or a local directory with the same layout (tests use ripples/contract/fixtures/v2 through --from=fixtures).
//
// Templates: the WS-D shells ripples/line/index.html, ripples/lands/index.html, ripples/week/index.html when they exist, else a
// small built-in page. Contract with the shells (documented in contract/fixtures/v2/README.md):
//   * <title>, <meta name="description">, <link rel="canonical">, og:* and twitter:* tags are replaced or inserted;
//   * <script type="application/json" id="rm-data"> is inserted before </head> (the page reads it before any fetch);
//   * the no-JS list replaces whatever sits between <!--rm:nojs--> and <!--/rm:nojs-->, or is inserted after <body…>;
//   * <body> gets data-route / data-event / data-version / data-hop / data-domain / data-week attributes.
// --clean-numbered removes the v5 numbered share stubs ripples/{n}/ (the daily puzzle is retired, EXPERIENCE §9). It refuses to run
//   until the WS-D shell ripples/line/index.html exists: the live v5 frontend (lib.js share URLs, app.js .ics links, archive/)
//   still links to /ripples/{n}/, so the directories go only in the same release as the v6 shell (--force overrides).
// --check validates every stub written: its own head, ≤ 300 KB, a no-JS list, the footer line; exits 1 on any failure.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const [k, ...v] = a.replace(/^--/, '').split('='); return [k, v.length ? v.join('=') : true]; }));
const ROOT = args.out ? String(args.out).replace(/\/?$/, '/') : fileURLToPath(new URL('..', import.meta.url));
const FROM = args.from === 'fixtures' ? fileURLToPath(new URL('../contract/fixtures/v2/', import.meta.url))
  : String(args.from || 'https://kffkasnzqcddpystszch.supabase.co/storage/v1/object/public/ripples/v2/').replace(/\/?$/, '/');
const SITE = 'https://bensunter.com/ripples';
const OG = 'https://kffkasnzqcddpystszch.supabase.co/functions/v1/ripples-og';
const MAX_BYTES = 300 * 1024;
const DOMAINS = ['reading', 'chatter', 'markets', 'builders', 'real_world', 'jobs', 'institutions', 'stuff'];
const DOMAIN_WORD = { reading: 'Reading', chatter: 'Chatter', markets: 'Markets', builders: 'Builders', real_world: 'Real world', jobs: 'Jobs', institutions: 'Institutions', stuff: 'Stuff' };
const TIER_WORD = { measured: 'Measured', likely: 'Likely', watching: 'Watching', retracted: 'Retracted', flat: 'Stayed flat' };
const FOOT = 'Consistent with, never proof of cause.';

// ---------- data ----------
const isUrl = /^https?:/.test(FROM);
async function get(path) {
  if (!isUrl) {
    // fixtures layout: the fixture files stand in for the Storage paths
    const map = { 'archive.json': 'archive.json', 'shocks/latest.json': 'shocks.json' };
    let f = map[path];
    // only event 1201 has cascade fixtures; the other archive rows (3069, 3121, 138) have none and are skipped, so the
    // stub count is the number of distinct files actually written
    if (!f && path === 'cascade/1201.json') f = 'cascade-1201.json';
    if (!f && /^cascade\/1201\/v\d+\.json$/.test(path)) f = /v2\.json$/.test(path) ? 'cascade-1201-v2.json' : /v3\.json$/.test(path) ? 'cascade-1201.json' : null;
    if (!f && /^hop\/\d+\.json$/.test(path)) f = path === 'hop/9006.json' ? 'hop-9006-retracted.json' : 'hop-9001.json';
    if (!f && /^lands\/real_world\.json$/.test(path)) f = 'lands-real_world.json';
    if (!f && /^week\/2026-39\.json$/.test(path)) f = 'week-2026-39.json';
    if (!f || !existsSync(FROM + f)) return null;
    const j = JSON.parse(readFileSync(FROM + f, 'utf8'));
    if (/^hop\/\d+\.json$/.test(path)) j.hop_id = Number(path.match(/\d+/)[0]);
    return j;
  }
  const r = await fetch(FROM + path);
  if (r.status === 404 || r.status === 400) return null;
  if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
  return r.json();
}

// ---------- html helpers ----------
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const jsonScript = (o) => JSON.stringify(o).replace(/</g, '\\u003c').replace(/[\u2028]/g, '\\u2028').replace(/[\u2029]/g, '\\u2029');
const mult = (x, unit = 'x') => {
  const v = Number(x);
  if (x === null || x === undefined || !isFinite(v)) return '';
  if (unit === 'points') return (v >= 0 ? '+' : '') + v.toFixed(2) + ' pts';
  return v < 1 ? v.toFixed(2) + '×' : v < 10 ? v.toFixed(1).replace(/\.0$/, '') + '×' : Math.round(v) + '×';
};
// "0.91× its normal" / "0.40 points above its normal": a rate's rho is a difference in points, never a multiple
const relNormal = (x, unit, tail) => {
  const v = Number(x);
  if (x === null || x === undefined || !isFinite(v)) return '';
  if (unit === 'points') return `${Math.abs(v).toFixed(2)} ${Math.abs(v).toFixed(2) === '1.00' ? 'point' : 'points'} ${v < 0 ? 'below' : 'above'} ${tail}`;
  return `${mult(v)} ${tail}`;
};
const clip = (s, n) => { const a = Array.from(String(s ?? '')); return a.length > n ? a.slice(0, n - 1).join('') + '…' : a.join(''); };
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const fmtDate = (d) => { const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d ?? '')); return m ? `${+m[3]} ${MON[+m[2] - 1]} ${m[1]}` : ''; };

function lineMeta(c) {
  const moved = (c.nodes || []).filter((n) => n.tier === 'measured' || n.tier === 'likely');
  const doms = new Set(moved.map((n) => n.domain));
  const days = Math.max(0, Math.round((Date.parse(c.as_of) - Date.parse(c.event.onset)) / 86400000));
  const st = c.status === 'running' ? 'still running' : c.status === 'nowhere' ? 'went nowhere' : 'line ended';
  return `${moved.length} ${moved.length === 1 ? 'stop' : 'stops'}${doms.size ? `, ${doms.size} ${doms.size === 1 ? 'domain' : 'domains'}` : ''}, ${days} ${days === 1 ? 'day' : 'days'}, ${st}`;
}
function stopItem(n, href) {
  const t = TIER_WORD[n.tier] || n.tier;
  const m = n.rho !== null && n.rho !== undefined ? ` ${relNormal(n.rho, n.unit, 'its normal')}` : '';
  const dom = DOMAIN_WORD[n.domain] || n.domain;
  const extra = [n.provisional ? 'provisional' : '', n.attention_ripple ? 'attention ripple' : '',
    n.tier === 'watching' && n.window_close ? (n.window_closed ? `window closed ${fmtDate(n.window_close)}` : `window closes ${fmtDate(n.window_close)}`) : '',
    n.retracted ? `retracted ${fmtDate(n.retracted.date)}` : ''].filter(Boolean).join('; ');
  return `<li><a href="${esc(href)}"><b>${esc(n.label)}</b></a> <span>(${esc(dom)})</span>: <b>${esc(t)}</b>${esc(m)}${extra ? ` <span>(${esc(extra)})</span>` : ''}.` +
    (n.sentence ? ` <span>${esc(n.sentence)}</span>` : '') + `</li>`;
}
function lineNoJs(c, k, latestK) {
  const slug = c.event.slug, base = `/ripples/line/${slug}/`;
  const stops = (c.nodes || []).slice().sort((a, b) => (a.depth - b.depth) || String(a.onset || '').localeCompare(String(b.onset || '')));
  const flat = c.flat || [];
  const d = c.denominators || {};
  return `<section class="rm-nojs" aria-labelledby="rm-h">
<h1 id="rm-h">${esc(c.event.emoji || '')} ${esc(c.event.label)}</h1>
<p>${c.event.reconstructed ? '<b>From the archive, reconstructed.</b> ' : ''}Shock started ${esc(fmtDate(c.event.onset))}. ${esc(lineMeta(c))}.${k && latestK && k < latestK ? ` This is version ${k}; the line has grown since. <a href="${esc(base)}">See the live line</a>.` : ''}</p>
${stops.length ? `<ol class="rm-stops">${stops.map((n) => stopItem(n, `${base}stop/${n.hop_id}/`)).join('\n')}</ol>` : '<p>No stop yet.</p>'}
${flat.length ? `<p>${flat.length} ${flat.length === 1 ? 'path' : 'paths'} stayed flat: ${esc(flat.slice(0, 12).map((f) => f.label).join(', '))}${flat.length > 12 ? ', …' : ''}.</p>` : ''}
${c.held_back && (c.held_back.stops || c.held_back.flat) ? `<p>${esc(c.held_back.stops + c.held_back.flat)} more tested ${c.held_back.stops + c.held_back.flat === 1 ? 'path is' : 'paths are'} not listed yet: ${esc(c.held_back.reason)}.</p>` : ''}
<p>Tested ${esc(d.tested ?? 0)} paths; ${esc(d.moved ?? 0)} moved; ${esc(d.measured ?? 0)} Measured; about ${esc(d.expected_false_links ?? 0)} expected false links. The control ripple (a page that wasn't trending): ${esc(c.control?.stops?.measured ?? 0)} Measured, ${esc(c.control?.stops?.likely ?? 0)} Likely.</p>
<p><b>${esc(FOOT)}</b> <a href="/ripples/methods/">How we test</a>.</p>
</section>`;
}
function hopNoJs(h, c) {
  const base = `/ripples/line/${h.event.slug}/`;
  const q5 = h.q5_luck || {};
  const lines = [
    `<h1 id="rm-h">${esc(h.node.label)}</h1>`,
    `<p>${h.event.reconstructed ? '<b>From the archive, reconstructed.</b> ' : ''}A stop on <a href="${esc(base)}">${esc(h.event.emoji || '')} ${esc(h.event.label)}</a> (${esc(DOMAIN_WORD[h.node.domain] || h.node.domain)}). Tier: <b>${esc(TIER_WORD[h.tier] || h.tier)}</b>${h.provisional ? ' (provisional)' : ''}.</p>`,
    h.sentence ? `<p>${esc(h.sentence)}</p>` : '',
    h.headline?.rho !== null && h.headline?.rho !== undefined ? `<p>${h.tier === 'retracted' ? 'Before the retraction: ' : ''}${esc(relNormal(h.headline.rho, h.q1_normal?.unit, 'its own normal'))} (interval ${esc(mult(h.headline.rho_lo, h.q1_normal?.unit))} to ${esc(mult(h.headline.rho_hi, h.q1_normal?.unit))}), ${h.headline.lag_days === null || h.headline.lag_days === undefined ? '' : `${esc(Math.round(h.headline.lag_days))} day(s) after ${esc(h.parent?.label)}`}.</p>` : '',
    q5.p_1_in ? `<p>Lookalikes: a random pairing looks this strong about 1 in ${esc(q5.p_1_in)} times.</p>` : '',
    q5.f_1_in ? `<p>Fluke rate: links this strong from decoy starts turn out to be flukes about 1 in ${esc(q5.f_1_in)} times.</p>` : (q5.f_warming ? '<p>Fluke rate: still warming up.</p>' : ''),
    h.q3_who ? `<p>${esc(h.q3_who.agree)} of ${esc(h.q3_who.of)} independent sources agree.</p>` : '',
    h.q4_why?.path?.length ? `<p>Why these two: ${esc(h.q4_why.path.map((p) => `${p.text} (${p.source})`).join('; '))}.</p>` : '',
    h.retracted ? `<p><b>Retracted ${esc(fmtDate(h.retracted.date))}:</b> ${esc(h.retracted.reason)}.</p>` : '',
    `<p><b>Measured movement, not proof of cause.</b> <a href="/ripples/methods/">How we test</a>.</p>`,
  ];
  return `<section class="rm-nojs" aria-labelledby="rm-h">\n${lines.filter(Boolean).join('\n')}\n</section>`;
}

// built-in page when the WS-D shell for a route does not exist yet
function builtin(route) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Ripple Map</title>
<meta name="description" content="Ripple Map">
<link rel="canonical" href="${SITE}/">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<meta name="theme-color" content="#0B3A40">
<style>body{margin:0;font:16px/1.5 "IBM Plex Sans",-apple-system,"Segoe UI",system-ui,sans-serif;color:#0B3A40;background:#EDF1EE}main{max-width:720px;margin:0 auto;padding:16px}h1{font-size:28px;line-height:1.15}a{color:#0B3A40;min-height:24px}li{margin:10px 0}footer{max-width:720px;margin:0 auto;padding:16px;font-size:14px}</style>
</head>
<body data-route="${route}">
<header><p style="max-width:720px;margin:0 auto;padding:16px 16px 0"><a href="/ripples/"><b>Knock⌃On</b> Ripple Map</a></p></header>
<main id="main">
<!--rm:nojs--><!--/rm:nojs-->
</main>
<footer><p>${FOOT}</p><p><a href="/ripples/methods/">Methods</a> <a href="/ripples/archive/">Archive</a></p></footer>
</body>
</html>
`;
}
function template(route) {
  const p = join(ROOT, route, 'index.html');
  return existsSync(p) ? readFileSync(p, 'utf8') : builtin(route);
}
function setTag(html, re, tag) { return re.test(html) ? html.replace(re, tag) : html.replace(/<\/head>/i, `${tag}\n</head>`); }
function stub(route, head, data, nojs, attrs) {
  let h = template(route);
  h = setTag(h, /<title>[^<]*<\/title>/i, `<title>${esc(head.title)}</title>`);
  h = setTag(h, /<meta name="description" content="[^"]*">/i, `<meta name="description" content="${esc(head.desc)}">`);
  h = setTag(h, /<link rel="canonical" href="[^"]*">/i, `<link rel="canonical" href="${esc(head.canonical)}">`);
  h = h.replace(/<meta name="robots" content="[^"]*">\n?/gi, '');
  if (head.noindex) h = h.replace(/<\/title>/i, '</title>\n<meta name="robots" content="noindex,follow">');
  // Open Graph / Twitter
  h = h.replace(/<meta (property|name)="(og:[^"]+|twitter:[^"]+)" content="[^"]*">\n?/gi, '');
  const og = [
    ['property', 'og:title', head.title], ['property', 'og:description', head.desc], ['property', 'og:url', head.url], ['property', 'og:type', 'article'],
    ['property', 'og:site_name', 'Knock⌃On Ripple Map'], ['property', 'og:image', head.image], ['property', 'og:image:width', '1200'], ['property', 'og:image:height', '630'],
    ['property', 'og:image:alt', head.alt], ['name', 'twitter:card', 'summary_large_image'], ['name', 'twitter:title', head.title],
    ['name', 'twitter:description', head.desc], ['name', 'twitter:image', head.image], ['name', 'twitter:image:alt', head.alt],
  ].map(([a, k, v]) => `<meta ${a}="${k}" content="${esc(v)}">`).join('\n');
  h = h.replace(/<\/head>/i, `${og}\n<!-- generated by ripples/tools/gen-stubs.mjs; edit the template or the generator, not this file -->\n<script type="application/json" id="rm-data">${jsonScript(data)}</script>\n</head>`);
  if (/<!--rm:nojs-->[\s\S]*?<!--\/rm:nojs-->/.test(h)) h = h.replace(/<!--rm:nojs-->[\s\S]*?<!--\/rm:nojs-->/, `<!--rm:nojs-->\n${nojs}\n<!--/rm:nojs-->`);
  else h = h.replace(/(<body[^>]*>)/i, `$1\n${nojs}`);
  const a = Object.entries(attrs).filter(([, v]) => v !== null && v !== undefined).map(([k, v]) => ` data-${k}="${esc(v)}"`).join('');
  h = h.replace(/<body([^>]*)>/i, (m, rest) => `<body${rest.replace(/ data-(route|event|version|hop|domain|week)="[^"]*"/g, '')}${a}>`);
  return h;
}

// ---------- write + check ----------
const written = [];
function write(rel, html) {
  const dir = join(ROOT, rel);
  const f = join(rel, 'index.html');
  if (written.includes(f)) throw new Error(`${f} written twice (two routes map to one slug)`);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'index.html'), html);
  written.push(f);
}
function check(file) {
  const html = readFileSync(join(ROOT, file), 'utf8');
  const errs = [];
  const bytes = Buffer.byteLength(html);
  if (bytes > MAX_BYTES) errs.push(`${bytes} bytes > 300 KB`);
  for (const [name, re] of [['title', /<title>[^<]{3,}<\/title>/], ['description', /<meta name="description" content="[^"]{20,}">/],
    ['canonical', /<link rel="canonical" href="https:\/\/bensunter\.com\/ripples\/[^"]*">/], ['og:image', /<meta property="og:image" content="https:[^"]+">/],
    ['og:image:alt', /<meta property="og:image:alt" content="[^"]{10,}">/], ['twitter:card', /<meta name="twitter:card" content="summary_large_image">/],
    ['viewport', /<meta name="viewport"/], ['lang', /<html lang="en"/], ['no-JS list', /class="rm-nojs"/], ['rm-data', /id="rm-data"/],
    ['footer line', /Consistent with, never proof of cause|Measured movement, not proof of cause/]]) {
    if (!re.test(html)) errs.push(`missing ${name}`);
  }
  if (/\b(caused|drove|because of)\b/i.test(html.replace(/<script[\s\S]*?<\/script>/g, ''))) errs.push('banned causal wording');
  return errs.length ? `${file}: ${errs.join(', ')}` : null;
}

// ---------- main ----------
if (args['clean-numbered']) {
  if (!existsSync(join(ROOT, 'line', 'index.html')) && !args.force) {
    console.error('refusing --clean-numbered: ripples/line/index.html (the WS-D shell) does not exist yet, and the v5 frontend still links to /ripples/{n}/. Ship both together, or pass --force.');
    process.exit(2);
  }
  let n = 0;
  for (const d of readdirSync(ROOT)) if (/^\d+$/.test(d) && statSync(join(ROOT, d)).isDirectory()) { rmSync(join(ROOT, d), { recursive: true, force: true }); n++; }
  console.log(`removed ${n} numbered v5 stub directories`);
}

const archive = (await get('archive.json')) || [];
let lines = 0, versions = 0, stops = 0;
for (const a of archive) {
  const c = await get(`cascade/${a.event_id}.json`);
  if (!c || !c.event) continue;
  const slug = c.event.slug, k = c.version;
  const title = `${c.event.label}: where it rippled${c.event.reconstructed ? ' (reconstructed)' : ''}`;
  const desc = `${lineMeta(c)}. ${c.event.reconstructed ? 'A reconstructed archive line. ' : ''}Each stop is tested against its own normal with fluke controls. ${FOOT}`;
  const altFor = (cc) => `${cc.event.label}${cc.event.reconstructed ? ' (reconstructed)' : ''}: ${lineMeta(cc)}. ${FOOT}`;
  write(`line/${slug}`, stub('line', { title, desc, canonical: `${SITE}/line/${slug}/`, url: `${SITE}/line/${slug}/`, image: `${OG}?v=line&e=${c.event.event_id}`, alt: altFor(c) },
    c, lineNoJs(c, k, k), { route: 'line', event: c.event.event_id, version: k }));
  lines++;
  for (let v = 1; v <= k; v++) {
    const cv = v === k ? c : await get(`cascade/${a.event_id}/v${v}.json`);
    if (!cv || !cv.event) continue;
    write(`line/${slug}/v${v}`, stub('line', { title: `${title}, version ${v}`, desc: `${lineMeta(cv)}. Frozen version ${v}. ${FOOT}`, canonical: `${SITE}/line/${slug}/`,
      url: `${SITE}/line/${slug}/v${v}/`, image: `${OG}?v=line&e=${c.event.event_id}&k=${v}`, alt: altFor(cv) },
      cv, lineNoJs(cv, v, k), { route: 'line', event: c.event.event_id, version: v }));
    versions++;
  }
  for (const n of c.nodes || []) {
    const h = await get(`hop/${n.hop_id}.json`);
    if (!h || !h.node) continue;
    const t = `${h.node.label}: ${TIER_WORD[h.tier] || h.tier} stop on ${c.event.label}`;
    // a retracted stop leads with the retraction, never with its old numbers
    const rt = h.tier === 'retracted' || h.retracted ? `Retracted ${fmtDate(h.retracted?.date)}${h.retracted?.reason ? `: ${h.retracted.reason}` : ''}. ` : '';
    const size = h.headline?.rho !== null && h.headline?.rho !== undefined ? `${rt ? 'Before the retraction: ' : ''}${relNormal(h.headline.rho, h.q1_normal?.unit, 'its own normal')}. ` : '';
    const d = `${rt}${size}${h.q5_luck?.p_1_in && !rt ? `Lookalikes about 1 in ${h.q5_luck.p_1_in}. ` : ''}Measured movement, not proof of cause.`;
    write(`line/${slug}/stop/${n.hop_id}`, stub('line', { title: t, desc: d.length >= 20 ? d : `${d} ${FOOT}`, canonical: `${SITE}/line/${slug}/stop/${n.hop_id}/`,
      url: `${SITE}/line/${slug}/stop/${n.hop_id}/`, image: `${OG}?v=stop&h=${n.hop_id}`,
      alt: rt ? `${h.node.label}: ${rt}A stop on ${c.event.label}. Measured movement, not proof of cause.`
        : `${h.node.label}: ${TIER_WORD[h.tier] || h.tier}${h.headline?.rho !== null && h.headline?.rho !== undefined ? `, ${relNormal(h.headline.rho, h.q1_normal?.unit, 'its normal')}` : ''}, after ${c.event.label}. Measured movement, not proof of cause.` },
      h, hopNoJs(h, c), { route: 'stop', event: c.event.event_id, hop: n.hop_id }));
    stops++;
  }
}
let landsN = 0;
for (const d of DOMAINS) {
  const l = await get(`lands/${d}.json`);
  const hops = l?.hops || [];
  const word = DOMAIN_WORD[d];
  const nojs = `<section class="rm-nojs" aria-labelledby="rm-h">\n<h1 id="rm-h">What's been moving ${esc(word)}?</h1>\n` +
    (hops.length ? `<ol>${hops.map((x) => `<li><a href="/ripples/line/${esc(x.slug)}/stop/${esc(x.hop_id)}/"><b>${esc(x.label)}</b></a>: ${esc(TIER_WORD[x.tier] || x.tier)}${x.rho !== null && x.rho !== undefined ? ` ${esc(relNormal(x.rho, x.unit, 'its normal'))}` : ''}, after ${esc(x.emoji || '')} ${esc(x.event_label)}${x.reconstructed ? ' (reconstructed)' : ''}.</li>`).join('\n')}</ol>`
      : '<p>No Measured or Likely stop in this domain in the last 30 days.</p>') +
    `\n<p><b>${esc(FOOT)}</b></p>\n</section>`;
  write(`lands/${d}`, stub('lands', { title: `What's been moving ${word}? Ripple Map`, desc: `Stops in ${word} that moved after an upstream shock in the last 30 days. ${FOOT}`,
    canonical: `${SITE}/lands/${d}/`, url: `${SITE}/lands/${d}/`, image: `${OG}?v=brand`, alt: `Knock⌃On Ripple Map: where did it ripple? ${FOOT}` },
    l || { v: 2, domain: d, hops: [] }, nojs, { route: 'lands', domain: d }));
  landsN++;
}
// weeks: the ISO weeks of the published lines' onsets plus the current week (only editions that exist)
const isoWeek = (dstr) => {
  const d = new Date(Date.parse(dstr.slice(0, 10) + 'T00:00:00Z'));
  const day = (d.getUTCDay() + 6) % 7; d.setUTCDate(d.getUTCDate() - day + 3);
  const y = d.getUTCFullYear(), j4 = new Date(Date.UTC(y, 0, 4)); const w = 1 + Math.round(((d - j4) / 86400000 - 3 + ((j4.getUTCDay() + 6) % 7)) / 7);
  return `${y}-${String(w).padStart(2, '0')}`;
};
const weeks = new Set([isoWeek(new Date().toISOString())]);
for (const a of archive) if (a.onset) weeks.add(isoWeek(a.onset));
let weeksN = 0;
for (const w of [...weeks].sort()) {
  const wk = await get(`week/${w}.json`);
  if (!wk || !wk.ripple_of_week) continue;
  const c = wk.ripple_of_week;
  const nojs = `<section class="rm-nojs" aria-labelledby="rm-h">\n<h1 id="rm-h">Ripple of the week ${esc(w)}: ${esc(c.event.emoji || '')} ${esc(c.event.label)}</h1>\n` +
    `<p>${c.event.reconstructed ? '<b>Reconstructed.</b> ' : ''}Rule: ${esc(wk.rule)}.${wk.note ? ' ' + esc(wk.note) : ''}</p>\n` +
    `<p><a href="/ripples/line/${esc(c.event.slug)}/v${esc(c.version)}/">${esc(c.event.label)}, version ${esc(c.version)}</a>: ${esc(lineMeta(c))}.</p>\n` +
    `<ol>${(wk.lines || []).map((x) => `<li><a href="/ripples/line/${esc(x.slug)}/">${esc(x.emoji || '')} ${esc(x.label)}</a>${x.reconstructed ? ' (reconstructed)' : ''}: ${esc(x.status)}.</li>`).join('\n')}</ol>\n<p><b>${esc(FOOT)}</b></p>\n</section>`;
  write(`week/${w}`, stub('week', { title: `Ripple of the week ${w}: ${c.event.label}`, desc: `${lineMeta(c)}. The week's lines, including the ones that went nowhere. ${FOOT}`,
    canonical: `${SITE}/week/${w}/`, url: `${SITE}/week/${w}/`, image: `${OG}?v=week&w=${w.replace('-', '')}`, alt: `Ripple of the week ${w}: ${c.event.label}. ${FOOT}` },
    wk, nojs, { route: 'week', week: w }));
  weeksN++;
}
console.log(`wrote ${written.length} stubs: ${lines} lines, ${versions} versions, ${stops} stops, ${landsN} lands, ${weeksN} weeks (from ${FROM})`);
if (args.check) {
  const bad = written.map(check).filter(Boolean);
  const sizes = written.map((f) => Buffer.byteLength(readFileSync(join(ROOT, f)))).sort((a, b) => b - a);
  console.log(`check: ${written.length - bad.length}/${written.length} ok; largest ${sizes[0] ?? 0} bytes`);
  if (bad.length) { console.log(bad.slice(0, 20).join('\n')); process.exit(1); }
}
