// Ripple Map v6 shared UI kit (WS-D): DOM helpers, data loading (inline → Storage → RPC), count-only events, share, tiles, flaps.
import * as C from './config.js';
import * as L from './lib.js';

// ---------- tiny DOM kit ----------
const $ = (s, r = document) => r.querySelector(s);
const add = (e, ...k) => { for (const c of k.flat(9)) if (c != null && c !== false && c !== '') e.append(c.nodeType ? c : String(c)); return e; };
function h(t, a, ...k) {
  const e = document.createElement(t);
  if (a) for (const [x, v] of Object.entries(a)) {
    if (v == null || v === false) continue;
    if (x.startsWith('on')) e.addEventListener(x.slice(2), v);
    else if (x === 'class') e.className = v;
    else e.setAttribute(x, v === true ? '' : v);
  }
  return add(e, ...k);
}
const NS = 'http://www.w3.org/2000/svg';
function S(t, a, p) { const e = document.createElementNS(NS, t); if (a) for (const x in a) if (a[x] != null) e.setAttribute(x, a[x]); if (p) p.append(e); return e; }
const em = x => h('span', { class: 'emo', 'aria-hidden': 'true' }, x);
const sep = () => h('span', { class: 'sepq', 'aria-hidden': 'true' });
const joinSep = xs => xs.filter(Boolean).flatMap((x, i) => (i ? [sep(), x] : [x]));
const put = (el, ...k) => { if (!el) return el; el.replaceChildren(); return add(el, ...k); };
const IC = {
  chev: '<path d="M6 4l4 4-4 4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
  share: '<path d="M8 10V2M5 5l3-3 3 3M3 8v5.5h10V8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  x: '<path d="M4 4l8 8M12 4l-8 8" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  play: '<path d="M4.5 2.8v10.4L13 8z" fill="currentColor"/>',
  back: '<path d="M10 4L6 8l4 4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
  img: '<rect x="2" y="3" width="12" height="10" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M3 12l3.5-4 3 3 2-2 2.5 3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
  copy: '<rect x="5" y="5" width="8.5" height="8.5" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M3 10.5V3.8C3 3.3 3.3 3 3.8 3h6.7" fill="none" stroke="currentColor" stroke-width="1.6"/>',
};
function icon(n, cls) { const s = S('svg', { viewBox: '0 0 16 16', 'aria-hidden': 'true', class: cls || null }); s.innerHTML = IC[n]; return s; }
const RM = matchMedia('(prefers-reduced-motion: reduce)').matches;
const desk = () => matchMedia('(min-width: 960px)').matches;
const ls = { get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private mode */ } } };
const today = () => new Date().toISOString().slice(0, 10);
// ---------- data: inline → Storage → RPC ----------
const INLINE = (() => { try { const e = document.getElementById('rm-data'); return e ? JSON.parse(e.textContent) : null; } catch (e) { return null; } })();
const memo = new Map();
async function getJSON(u) { const r = await fetch(u); if (!r.ok) throw new Error(String(r.status)); return r.json(); }
async function rpc(fn, args) {
  const r = await fetch(`${C.SB_URL}/rest/v1/rpc/${fn}`, { method: 'POST', credentials: 'omit', headers: { apikey: C.SB_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(args || {}) });
  if (!r.ok) throw new Error(String(r.status));
  return r.json();
}
function load(path, fn, args) {
  if (!memo.has(path)) memo.set(path, getJSON(C.STORAGE + path).catch(() => (fn ? rpc(fn, args) : null)).catch(() => null));
  return memo.get(path);
}
const D = {
  shocks: () => load('shocks/latest.json', 'rm_shocks', { p_day: null }),
  cascade: (e, k) => load(k ? `cascade/${e}/v${k}.json` : `cascade/${e}.json`, 'rm_cascade', { p_event: e, p_version: k || null }),
  hop: x => load(`hop/${x}.json`, 'rm_hop', { p_hop: x }),
  lands: d => load(`lands/${d}.json`, 'rm_lands', { p_domain: d, p_days: 30 }),
  archive: () => load('archive.json', 'rm_archive', { p_days: null, p_status: null }),
  week: w => load(`week/${w}.json`, 'rm_week', { p_week: w }),
  calib: () => load('calibration.json', 'rm_calibration', {}),
  health: () => load('health.json', 'rm_health', {}),
};
// ---------- count-only events (rm_event): a daily count per kind × source; no IP, no URL, no history ----------
function client() {
  let c = ls.get('ko.client');
  if (!c) { const a = new Uint8Array(12); crypto.getRandomValues(a); c = btoa(String.fromCharCode(...a)).replace(/[+/=]/g, m => ({ '+': '-', '/': '_', '=': '' })[m]); ls.set('ko.client', c); }
  return c;
}
function event(kind, src) { try { rpc('rm_event', { p_kind: kind, p_src: String(src || 'other').slice(0, 24), p_client: client() }).catch(() => {}); } catch (e) { /* never block */ } }
// ---------- toast, share ----------
let tt;
function toast(msg) {
  const t = $('#toast'); if (!t) return;
  put(t, msg); t.classList.add('on'); clearTimeout(tt); tt = setTimeout(() => t.classList.remove('on'), 2400);
}
function copy(text) {
  const ok = () => toast('Copied: paste it anywhere');
  if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text).then(ok, () => fallbackCopy(text, ok));
  fallbackCopy(text, ok);
}
function fallbackCopy(text, ok) {
  const ta = h('textarea', { style: 'position:fixed;top:-100px;opacity:0', 'aria-hidden': 'true' }, text);
  document.body.append(ta); ta.select();
  try { document.execCommand('copy'); ok(); } catch (e) { toast('Select the text to copy it'); }
  ta.remove();
}
// Text share with the URL inside the text (playbook §3.4); clipboard is a main path, not an error path.
function share(text, src) {
  event('share_tap', src);
  if (navigator.share) { navigator.share({ text }).catch(e => { if (!e || e.name !== 'AbortError') copy(text); }); return; }
  copy(text);
}
const blobs = new Map();
function prefetchImg(url) { if (!blobs.has(url)) blobs.set(url, fetch(url, { credentials: 'omit' }).then(r => (r.ok ? r.blob() : null)).catch(() => null)); return blobs.get(url); }
async function shareImage(url, text, src, name) {
  event('share_tap', src + '_img');
  const b = await prefetchImg(url);
  const f = b ? new File([b], name, { type: 'image/png' }) : null;
  if (f && navigator.canShare && navigator.canShare({ files: [f] })) { navigator.share({ files: [f], text }).catch(() => {}); return; }
  window.open(url, '_blank', 'noopener');
}
function landing(r) {
  try {
    const q = new URLSearchParams(location.search).get('src');
    const ext = document.referrer && !/bensunter\.com/.test(document.referrer);
    if ((q || ext) && !sessionStorage.getItem('ko.land')) { sessionStorage.setItem('ko.land', '1'); event('landing', q || (r.version ? 'shared' : r.route)); }
  } catch (e) { /* ignore */ }
}
// ---------- shared pieces ----------
function flaps(str, cls, label) {
  const w = h('span', { class: 'flaps' + (cls ? ' ' + cls : ''), 'aria-hidden': 'true' });
  for (const ch of str) w.append(h('span', { class: 'flap' + (ch === '.' || ch === ',' ? ' nr' : '×+−-'.includes(ch) ? ' x' : '') }, h('span', null, ch === ' ' ? ' ' : ch)));
  return label === false ? w : h('span', null, w, h('span', { class: 'sr' }, label || str.replace('×', ' times')));
}
// flip-digit count-up to the final value (ART §4.3): changed digits fold; ends with a 2 px thunk. Never under reduced motion.
function countUp(wrap, final, quiet) {
  const box = wrap.querySelector('.flaps') || wrap; const cells = [...box.querySelectorAll('.flap>span')];
  const m = /^([+−-]?)([\d.]+)(.*)$/.exec(final);
  if (RM || quiet || !m || !cells.length) return;
  const target = parseFloat(m[2]), dec = (m[2].split('.')[1] || '').length, from = m[1] ? 0 : 1;
  const steps = 9, fmt = v => (m[1] + v.toFixed(dec) + m[3]).padStart(final.length, ' ');
  let i = 0;
  const tick = () => {
    i++;
    const t = i / steps, v = from + (target - from) * (1 - Math.pow(1 - t, 2.2));
    const s = i >= steps ? final : fmt(v);
    [...s].forEach((ch, j) => { const c = cells[j]; if (c && c.textContent !== ch) { c.textContent = ch; c.parentElement.animate([{ transform: 'rotateX(0)' }, { transform: 'rotateX(-80deg)' }, { transform: 'rotateX(0)' }], { duration: i >= steps ? 140 : 70, easing: 'ease-in' }); } });
    if (i < steps) setTimeout(tick, 40 + i * 6); else box.animate([{ transform: 'translateY(0)' }, { transform: 'translateY(2px)' }, { transform: 'translateY(0)' }], { duration: 90, easing: 'cubic-bezier(.5,0,.1,1)' });
  };
  [...fmt(from)].forEach((ch, j) => { if (cells[j]) cells[j].textContent = ch; });
  setTimeout(tick, 60);
}
const tt_ = (tier, extra) => h('span', { class: `tt ${tier}${extra ? ' ' + extra : ''}`, 'aria-hidden': 'true' });
function pips(n) { const w = h('span', { class: 'pips', 'aria-hidden': 'true' }); for (let i = 0; i < 3; i++) w.append(h('i', { class: i < n ? 'on' : '' })); return w; }
function stamp(tier, title) {
  const T = L.TIER[tier] || L.TIER.watching;
  return h('span', { class: `stamp ${tier}`, title: title === false ? null : `${T.w}: ${T.def}` }, tier === 'retracted' ? null : pips(T.pips), T.w);
}
function dtile(n, cls = '') {
  const t = h('span', { class: `dt ${n.tier}${cls ? ' ' + cls : ''}`, 'aria-hidden': 'true' }, em(L.domIcon(n.domain)));
  if (n.attention_ripple) t.append(h('span', { class: 'ar emo' }, '📖'));
  return t;
}
function strip(st, max = 8, panel) {
  const w = h('span', { class: 'tstrip' });
  const seq = [...Array(st.measured || 0).fill('measured'), ...Array(st.likely || 0).fill('likely'), ...Array(st.watching || 0).fill('watching')];
  seq.slice(0, max).forEach(t => w.append(tt_(t)));
  if (seq.length > max) w.append(h('small', null, `+${seq.length - max}`));
  if (st.flat) w.append(h('small', null, `⊥${st.flat}`));
  w.append(h('span', { class: 'sr' }, `${st.measured || 0} Measured, ${st.likely || 0} Likely, ${st.watching || 0} Watching, ${st.flat || 0} stayed flat`));
  return w;
}
const legend = cls => h('p', { class: 'legend' + (cls ? ' ' + cls : '') }, h('span', null, tt_('measured'), 'Measured'), h('span', null, tt_('likely'), 'Likely'), h('span', null, tt_('watching'), 'Watching'), h('span', null, h('b', { 'aria-hidden': 'true' }, '⊥'), 'stayed flat'));
function spark(vals, w = 64, hgt = 22, cls = 'lane-flat') {
  const s = S('svg', { viewBox: `0 0 ${w} ${hgt}`, 'aria-hidden': 'true', preserveAspectRatio: 'none' });
  const v = (vals || []).filter(x => x != null && isFinite(x)); if (v.length < 2) return s;
  const lo = Math.min(0.8, ...v), hi = Math.max(1.25, ...v), y = x => hgt - 2 - ((L.log2(x) - L.log2(lo)) / (L.log2(hi) - L.log2(lo))) * (hgt - 4);
  S('line', { x1: 0, x2: w, y1: y(1), y2: y(1), stroke: 'var(--hair)', 'stroke-width': 1 }, s);
  S('path', { d: v.map((x, i) => `${i ? 'L' : 'M'}${(i / (v.length - 1) * w).toFixed(1)} ${y(x).toFixed(1)}`).join(''), fill: 'none', stroke: 'var(--flat)', 'stroke-width': 1.75, 'stroke-linejoin': 'round', class: cls }, s);
  return s;
}
// ---------- chrome: theme, wander (help is in help.js) ----------
function theme() {
  const r = document.documentElement, dark = r.getAttribute('data-theme') === 'dark' || (!r.hasAttribute('data-theme') && matchMedia('(prefers-color-scheme: dark)').matches);
  r.setAttribute('data-theme', dark ? 'light' : 'dark'); ls.set('ko.theme', dark ? 'light' : 'dark');
}
async function wander() {
  toast('Finding a Measured stop…');
  const a = (await D.archive()) || [];
  const cut = L.addDays(today(), -90);
  let pool = a.filter(x => x.measured > 0 && !x.sensitive && !x.reconstructed && x.onset >= cut);
  if (!pool.length) pool = a.filter(x => x.measured > 0 && !x.sensitive);
  if (!pool.length) { toast('Nothing Measured in the last 90 days yet'); return; }
  const line = pool[Math.floor(Math.random() * pool.length)];
  const c = await D.cascade(line.event_id);
  const ms = (c?.nodes || []).filter(n => n.tier === 'measured');
  if (!ms.length) { location.href = L.lineUrl(line.slug); return; }
  location.href = L.stopUrl(line.slug, ms[Math.floor(Math.random() * ms.length)].hop_id) + '?src=wander';
}
// Fonts (self-hosted, OFL): registered after first paint so they never delay it; swap in when they arrive (cached after).
function fonts() {
  try {
    if (!window.FontFace || !document.fonts) return;
    for (const [fam, file, d] of [['Anybody', 'anybody-latin-var.woff2', { weight: '100 900', stretch: '50% 150%' }], ['IBM Plex Sans', 'plex-sans-latin-var.woff2', { weight: '100 700' }]]) {
      const f = new FontFace(fam, `url(/ripples/fonts/${file}) format("woff2")`, { ...d, display: 'swap' });
      document.fonts.add(f); f.load().catch(() => {});
    }
  } catch (e) { /* the system fonts stay */ }
}
function chrome() {
  requestAnimationFrame(() => setTimeout(fonts, 0));
  $('#theme')?.addEventListener('click', theme);
  // the help dialog is loaded on first tap (it is not needed to draw any page)
  $('#help')?.addEventListener('click', () => import('./help.js').then(m => m.help()));
  $('#wander')?.addEventListener('click', wander);
  const dt = $('#today'); if (dt && !dt.textContent.trim()) dt.textContent = L.fmtDate(today());
  if (!$('#toast')) document.body.append(h('div', { id: 'toast', role: 'status', 'aria-live': 'polite' }));
  a2hs();
}
// add to home screen: offered from the second visit (EXPERIENCE §9)
let bip = null;
const getBip = () => bip;
function a2hs() {
  addEventListener('beforeinstallprompt', e => { e.preventDefault(); bip = e; const s = $('#a2hs'); if (s && visits() >= 2) s.hidden = false; });
  const s = $('#a2hs'); if (s) s.addEventListener('click', () => { if (bip) { bip.prompt(); bip = null; s.hidden = true; } });
}
const visits = () => { const v = +(ls.get('ko.visits') || 0); return v; };
// SVG axis labels: the display face draws + × − tiny next to its tall digits, so those three glyphs go in a sans tspan
function axText(el, str) {
  el.replaceChildren(...String(str).split(/([+×−])/).filter(Boolean).map(t => ('+×−'.includes(t) ? Object.assign(S('tspan', { class: 'ax-g' }), { textContent: t }) : document.createTextNode(t))));
}
function seedChart(svg, vals, quiet, peakLabel) {
  const W = 320, H = 84; svg.setAttribute('viewBox', `0 0 ${W} ${H}`); svg.setAttribute('preserveAspectRatio', 'none');
  const v = (vals || []).map(Number).filter(isFinite); if (v.length < 8) return false;
  const pk = v.indexOf(Math.max(...v)), D0 = Math.max(0, pk - 62), D1 = pk + 14;
  const x = i => ((i - D0) / (D1 - D0)) * W, top = 12, bot = H - 22, max = v[pk] * 1.07, y = val => bot - (val / max) * (bot - top);
  const pts = []; for (let i = D0; i < v.length; i++) pts.push([x(i), y(v[i])]);
  const P = a => a.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join('');
  const kick = Math.max(0, pts.length - (v.length - pk) - 4);
  S('path', { d: P(pts) + `L${pts[pts.length - 1][0].toFixed(1)} ${bot}L${pts[0][0].toFixed(1)} ${bot}Z`, fill: 'var(--seed-band)' }, svg);
  const base = S('path', { d: P(pts.slice(0, kick + 1)), fill: 'none', stroke: 'var(--seed-line)', 'stroke-width': 2.25, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', 'vector-effect': 'non-scaling-stroke' }, svg);
  const needle = S('path', { d: P(pts.slice(kick)), fill: 'none', stroke: 'var(--seed-line)', 'stroke-width': 2.5, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', 'vector-effect': 'non-scaling-stroke' }, svg);
  const by = H - 8;
  S('path', { d: `M4 ${by - 3}L0 ${by}L4 ${by + 3}M0 ${by}H${x(Math.max(D0, pk - 21)).toFixed(1)}V${by - 5}`, fill: 'none', stroke: 'var(--seed-line)', 'stroke-width': 1.5, opacity: 0.6, 'vector-effect': 'non-scaling-stroke' }, svg);
  const lbl = h('span', { class: 'sr' });
  const t = S('text', { x: 10, y: by - 2, 'font-size': 10.5, 'font-weight': 600, fill: 'var(--seed-line)', 'font-family': 'var(--sans)' }, svg); t.textContent = 'Its normal';
  const today = S('text', { x: x(v.length - 1), y: by + 1, 'font-size': 10.5, 'font-weight': 500, fill: 'var(--seed-line)', 'text-anchor': 'middle', opacity: 0.8, 'font-family': 'var(--sans)' }, svg); today.textContent = 'today';
  const dot = S('circle', { cx: x(pk), cy: y(v[pk]), r: 4.5, fill: 'var(--seed-line)', stroke: 'var(--marigold)', 'stroke-width': 2 }, svg);
  const pl = S('text', { x: x(pk) + 9, y: y(v[pk]) + 6, 'font-size': 17, 'font-weight': 900, fill: 'var(--seed-line)', 'font-family': 'var(--display)' }, svg); axText(pl, peakLabel);
  void lbl;
  if (!RM && !quiet) {
    for (const [el, d0, dur, ease] of [[base, 150, 250, 'cubic-bezier(.2,.8,.2,1)'], [needle, 400, 150, 'ease-in']]) {
      const len = el.getTotalLength(); el.style.strokeDasharray = len; el.style.strokeDashoffset = len;
      el.animate([{ strokeDashoffset: len }, { strokeDashoffset: 0 }], { duration: dur, delay: d0, easing: ease, fill: 'forwards' });
    }
    dot.animate([{ transform: 'scale(0)' }, { transform: 'scale(1.15)' }, { transform: 'scale(1)' }], { duration: 160, delay: 550, fill: 'backwards', easing: 'cubic-bezier(.34,1.56,.64,1)' });
    dot.style.transformOrigin = `${x(pk)}px ${y(v[pk])}px`; dot.style.transformBox = 'view-box';
    pl.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 120, delay: 560, fill: 'backwards' });
  }
  return true;
}

export { $, add, h, S, em, sep, joinSep, put, icon, IC, RM, desk, ls, today, INLINE, D, rpc, load, event, toast, copy, share, prefetchImg, shareImage, landing, flaps, countUp, tt_, pips, stamp, dtile, strip, legend, spark, theme, wander, chrome, visits, seedChart, getBip, axText };
