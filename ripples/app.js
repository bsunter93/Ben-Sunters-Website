// Knock⌃On Ripple Map v6 (WS-D). One module for every /ripples/ page; the page's <body data-route> (set by the shells and by
// ripples/tools/gen-stubs.mjs) picks the renderer. Data: the stub's inlined #rm-data first, then Storage v2/, then the RPC.
import * as C from '/ripples/config.js';
import * as L from '/ripples/lib.js';

// ---------- tiny DOM kit ----------
const $ = (s, r = document) => r.querySelector(s);
const add = (e, k) => { for (const c of k.flat(9)) if (c != null && c !== false && c !== '') e.append(c.nodeType ? c : String(c)); return e; };
function h(t, a, ...k) {
  const e = document.createElement(t);
  if (a) for (const [x, v] of Object.entries(a)) {
    if (v == null || v === false) continue;
    if (x.startsWith('on')) e.addEventListener(x.slice(2), v);
    else if (x === 'class') e.className = v;
    else e.setAttribute(x, v === true ? '' : v);
  }
  return add(e, k);
}
const NS = 'http://www.w3.org/2000/svg';
function S(t, a, p) { const e = document.createElementNS(NS, t); if (a) for (const x in a) if (a[x] != null) e.setAttribute(x, a[x]); if (p) p.append(e); return e; }
const em = x => h('span', { class: 'emo', 'aria-hidden': 'true' }, x);
const sep = () => h('span', { class: 'sepq', 'aria-hidden': 'true' });
const joinSep = xs => xs.filter(Boolean).flatMap((x, i) => (i ? [sep(), x] : [x]));
const put = (el, ...k) => { if (!el) return el; el.replaceChildren(); return add(el, k); };
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
async function getJSON(u) { const r = await fetch(u, { credentials: 'omit' }); if (!r.ok) throw new Error(String(r.status)); return r.json(); }
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
  for (const ch of str) w.append(h('span', { class: 'flap' + (ch === '.' || ch === ',' ? ' nr' : ch === '×' ? ' x' : '') }, h('span', null, ch === ' ' ? ' ' : ch)));
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
  const w = h('span', { class: 'strip' });
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

// ---------- chrome: theme, help, wander ----------
function theme() {
  const r = document.documentElement, dark = r.getAttribute('data-theme') === 'dark' || (!r.hasAttribute('data-theme') && matchMedia('(prefers-color-scheme: dark)').matches);
  r.setAttribute('data-theme', dark ? 'light' : 'dark'); ls.set('ko.theme', dark ? 'light' : 'dark');
}
function help() {
  let d = $('#helpdlg');
  if (!d) {
    const hide = ls.get('ko.hide_middle') === '1';
    d = h('dialog', { id: 'helpdlg', 'aria-labelledby': 'helpt' },
      h('h2', { id: 'helpt' }, 'How to read the Ripple Map'),
      h('p', null, 'Each upstream shock is a line. Each stop is a series in another part of life that moved against its own normal after the shock. We test many paths and show the ones that stayed flat too.'),
      h('h3', null, 'Tiers'),
      h('ul', null, ['measured', 'likely', 'watching', 'flat'].map(t => h('li', null, t === 'flat' ? h('b', { 'aria-hidden': 'true' }, '⊥') : tt_(t), h('span', null, h('b', null, L.TIER[t].w + '. '), L.TIER[t].def)))),
      h('h3', null, 'Two fluke numbers, never merged'),
      h('p', null, h('b', null, 'Lookalikes: '), '"A random pairing looks this strong about 1 in N times" compares the stop with fake dates, fake starts and fake pages.'),
      h('p', null, h('b', null, 'Fluke rate: '), '"Links this strong from decoy starts turn out to be flukes about 1 in K times" comes from calm pages we run through the same tests every day.'),
      h('h3', null, 'Domains'),
      h('ul', null, L.DOMAINS.map(k => h('li', null, em(L.DOM[k].i), h('span', null, h('b', null, L.DOM[k].w + ': '), L.DOM[k].d)))),
      h('label', { class: 'tog' }, h('input', { type: 'checkbox', checked: hide, onchange: e => { ls.set('ko.hide_middle', e.target.checked ? '1' : '0'); } }), 'Hide the middle stops until I open them'),
      h('p', { class: 'xs' }, h('a', { href: '/ripples/methods/', class: 'lnk' }, 'Methods and receipts')),
      h('form', { method: 'dialog' }, h('button', { class: 'btn sec' }, 'Got it')));
    document.body.append(d);
  }
  d.showModal();
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
function chrome() {
  $('#theme')?.addEventListener('click', theme);
  $('#help')?.addEventListener('click', help);
  $('#wander')?.addEventListener('click', wander);
  const dt = $('#today'); if (dt && !dt.textContent.trim()) dt.textContent = L.fmtDate(today());
  if (!$('#toast')) document.body.append(h('div', { id: 'toast', role: 'status', 'aria-live': 'polite' }));
  a2hs();
}
// add to home screen: offered from the second visit (EXPERIENCE §9)
let bip = null;
function a2hs() {
  addEventListener('beforeinstallprompt', e => { e.preventDefault(); bip = e; const s = $('#a2hs'); if (s && visits() >= 2) s.hidden = false; });
  const s = $('#a2hs'); if (s) s.addEventListener('click', () => { if (bip) { bip.prompt(); bip = null; s.hidden = true; } });
}
const visits = () => { const v = +(ls.get('ko.visits') || 0); return v; };

// ---------- HOME ----------
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
  const pl = S('text', { x: x(pk) + 9, y: y(v[pk]) + 6, 'font-size': 17, 'font-weight': 900, fill: 'var(--seed-line)', 'font-family': 'var(--display)' }, svg); pl.textContent = peakLabel;
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
function heroTicket(S0, archive) {
  const hero = S0?.hero;
  const tk = h('section', { class: 'ticket hero grain', 'aria-labelledby': 'hero-t' });
  if (!hero) {
    // Cold start with nothing Measured anywhere: say so, and point at what is being watched (never pad a headline)
    const rows = (S0?.shocks || []);
    const due = rows.map(r => r.next_due).filter(d => d && d >= today()).sort()[0];
    tk.classList.add('empty');
    add(tk, h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, 'Ripple of the week')),
      h('div', { class: 'tk-body' },
        h('h1', { class: 'tk-title', id: 'hero-t' }, 'Nothing Measured yet'),
        h('p', { class: 'tk-hook' }, rows.length ? `${L.plural(rows.length, 'line')} on the board, every stop still Watching or flat.` : 'No lines are published yet.'),
        h('p', { class: 'tk-sub' }, 'A stop lands here only when it passes every test: its own normal, timing, two sources, and the fluke controls.'),
        h('div', { class: 'tk-path', 'aria-hidden': 'true' }, h('span', { class: 'dt shock' }, em(rows[0]?.emoji || '🌀')), h('span', { class: 'trk' }), h('span', { class: 'dt q' }, '?'), h('span', { class: 'lbl' }, due ? `Next result due ${L.fmtDay(due)}` : 'Waiting for the first result'))),
      h('div', { class: 'tk-perf', 'aria-hidden': 'true' }, h('span', { class: 'notch l' }), h('span', { class: 'notch r' })),
      h('div', { class: 'tk-foot' }, h('a', { class: 'btn', href: '#departures' }, 'See what we are watching')));
    return tk;
  }
  const s = (S0.shocks || []).find(x => x.event_id === hero.event_id) || (archive || []).find(x => x.event_id === hero.event_id) || {};
  const quiet = !!(hero.sensitive || s.sensitive);
  if (quiet) tk.classList.add('quiet');
  const svg = S('svg', { class: 'tk-chart', role: 'img', 'aria-label': `${hero.title}: attention against its own normal over the last weeks, peaking at ${L.num(s.magnitude_x)} times normal.` });
  const hasChart = s.spark ? seedChart(svg, s.spark, quiet, L.num(s.magnitude_x) + '×') : false;
  const st = hero.stop || {};
  const path = h('div', { class: 'tk-path', id: 'hero-path' }, h('span', { class: 'dt shock', 'aria-hidden': 'true' }, em(s.emoji || '🌀')), h('span', { class: 'trk', 'aria-hidden': 'true' }),
    h('span', { class: 'dt measured', 'aria-hidden': 'true' }, em(L.domIcon(st.domain))), h('span', { class: 'lbl' }, L.domWord(st.domain), h('br'), h('span', { style: 'font-weight:500' }, 'Measured')));
  const stops = s.stops ? (s.stops.measured || 0) + (s.stops.likely || 0) : null;
  const meta = joinSep([stops != null ? L.plural(stops, 'stop') : null, s.domains_reached ? L.plural(s.domains_reached.length, 'domain') : null, L.STATUS[s.status] || null, hero.reconstructed ? 'reconstructed' : null]);
  add(tk,
    h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, hero.reconstructed ? 'From the archive, reconstructed' : 'Ripple of the week'), hero.version ? h('span', { class: 'ver' }, 'v' + hero.version) : null),
    h('div', { class: 'tk-body' },
      h('div', { class: 'tk-row' }, h('span', { class: 'tk-emo', 'aria-hidden': 'true' }, em(s.emoji || '🌀')), h('h1', { class: 'tk-title', id: 'hero-t' }, hero.title)),
      h('p', { class: 'tk-hook' }, hero.headline),
      s.magnitude_x ? h('p', { class: 'tk-sub' }, joinSep([`Peaked at ${L.num(s.magnitude_x)}× its normal attention`, L.biggest(s) || null])) : null,
      hasChart ? svg : null, path),
    h('div', { class: 'tk-perf', 'aria-hidden': 'true' }, h('span', { class: 'notch l' }), h('span', { class: 'notch r' })),
    h('div', { class: 'tk-foot' }, meta.length ? h('p', { class: 'tk-meta' }, meta) : null, h('a', { class: 'btn', href: L.lineUrl(hero.slug) + (ls.get('ko.hide_middle') === '1' ? '?hide=1' : '') }, 'Trace the line')));
  // "?" tiles hide only the stops between the shock and that Measured stop; they flip once through domain icons (not in quiet mode)
  D.cascade(hero.event_id).then(c => {
    if (!c) return;
    const mid = L.ancestors(c, st.hop_id);
    if (!mid.length) return;
    const trk = path.children[1];
    mid.forEach(() => {
      const q = h('span', { class: 'dt q', 'aria-hidden': 'true' }, '?');
      trk.after(q, h('span', { class: 'trk', 'aria-hidden': 'true' }));
      if (!RM && !quiet) { const ic = L.DOMAINS.map(k => L.DOM[k].i); let i = 0; const t = setInterval(() => { q.textContent = i < 6 ? ic[i++ % ic.length] : '?'; if (i >= 6) { clearInterval(t); q.textContent = '?'; } }, 110); }
    });
  });
  return tk;
}
function depRow(s, fresh) {
  const st = s.stops || {};
  const where = s.farthest_measured_domain ? [em(L.domIcon(s.farthest_measured_domain)), L.domWord(s.farthest_measured_domain)] : s.status === 'nowhere' ? ['went nowhere'] : ['watching'];
  const when = s.next_due && s.next_due >= today() ? `next look ${L.fmtDay(s.next_due)}` : `since ${L.fmtDay(s.onset)}`;
  return h('a', { class: 'dep' + (fresh ? ' new' : ''), href: L.lineUrl(s.slug) },
    h('span', { class: 'ic', 'aria-hidden': 'true' }, em(s.emoji || '▫️')),
    h('span', null, h('span', { class: 'nm' }, s.label, s.reconstructed ? h('span', { class: 'sr' }, ' (reconstructed)') : null), h('span', { class: 'sub' }, ...where, sep(), when, fresh ? [sep(), h('span', { class: 'hl' }, 'new')] : null)),
    strip(st, 6, true), icon('chev', 'chev'));
}
function board(S0, fresh) {
  const rows = (S0?.shocks || []).slice().sort((a, b) => (b.stops?.measured || 0) - (a.stops?.measured || 0) || (b.stops?.likely || 0) - (a.stops?.likely || 0) || String(b.onset).localeCompare(String(a.onset)));
  const pub = S0?.published_at;
  const el = h('section', { class: 'panel board grain', id: 'departures', 'aria-labelledby': 'dep-t' },
    h('div', { class: 'bd-head' }, h('h2', { id: 'dep-t', class: 'fw', 'aria-label': 'Departures' }, [...'Departures'].map(ch => h('b', { 'aria-hidden': 'true' }, ch))),
      h('p', { class: 'bd-time' }, h('b', null, pub ? L.fmtTime(pub) : '--:--'), S0?.day ? L.fmtDate(S0.day) : '')),
    rows.length ? rows.map(s => depRow(s, fresh.has(s.event_id))) : h('p', { class: 'dep' }, h('span'), h('span', { class: 'sub' }, 'No lines published today yet.')));
  const ctl = S0?.control;
  if (ctl) el.append(h('div', { class: 'dep ctl', role: 'group', 'aria-label': 'The control ripple' },
    h('span', { class: 'ic', 'aria-hidden': 'true' }, em('📄')),
    h('span', null, h('span', { class: 'nm' }, L.plural(ctl.n_decoys || 1, 'page') + " that weren't trending"), h('span', { class: 'sub' }, 'the control: same tests, every day')),
    strip(ctl.stops || {}, 6, true), h('span')));
  const dl = L.dayLine(S0?.line), ll = S0?.listed_lines_sum;
  el.append(legend(), h('p', { class: 'bd-foot' },
    dl ? [h('b', null, `Tested ${L.fmtInt(dl.tested)} paths today`), sep(), `${L.fmtInt(dl.moved)} moved`, sep(), `about ${L.expected(dl.expected)} expected by chance`]
      : [h('b', null, "Today's tests are not in yet.")],
    ll && ll.lines ? [h('br'), `On the ${L.plural(ll.lines, 'listed line')}, over all their days: ${L.fmtInt(ll.tested)} paths tested, ${L.fmtInt(ll.moved)} moved, ${L.fmtInt(ll.measured)} Measured.`] : null));
  return el;
}
function sinceSnap(S0) {
  // localStorage ko.seen_at: {t, s:{event_id:[measured, likely, watching, flat]}}; lemon marks what changed since
  let prev = null; try { prev = JSON.parse(ls.get('ko.seen_at') || 'null'); } catch (e) { prev = null; }
  const now = {}, rows = [], fresh = new Set();
  for (const s of S0?.shocks || []) {
    const st = s.stops || {}, cur = [st.measured || 0, st.likely || 0, st.watching || 0, st.flat || 0];
    now[s.event_id] = cur;
    if (prev && prev.s) {
      const p = prev.s[s.event_id];
      if (!p) { rows.push({ s, txt: 'new line' }); fresh.add(s.event_id); continue; }
      const lit = cur[0] + cur[1] - p[0] - p[1], flat = cur[3] - p[3];
      if (lit || flat) { rows.push({ s, txt: [lit ? `${lit > 0 ? '+' : ''}${L.plural(lit, 'stop')}` : '', flat > 0 ? `${flat} stayed flat` : ''].filter(Boolean).join(', ') }); fresh.add(s.event_id); }
    }
  }
  if (S0?.shocks?.length) ls.set('ko.seen_at', JSON.stringify({ t: Date.now(), s: now }));
  return { prev, rows, fresh };
}
function sinceBlock(sn) {
  if (!sn.prev || !sn.rows.length) return null;
  return h('section', { class: 'since', 'aria-labelledby': 'since-t' }, h('h2', { id: 'since-t' }, `Since you were here (${L.fmtDate(L.isoDay(sn.prev.t)).slice(0, 3)})`),
    h('ul', null, sn.rows.slice(0, 6).map(r => h('li', null, h('a', { href: L.lineUrl(r.s.slug) }, em(r.s.emoji), h('b', null, r.s.label), h('span', { class: 'hl' }, 'new'), h('span', { class: 'muted' }, r.txt))))));
}
function domChips(S0) {
  const reached = new Set((S0?.shocks || []).flatMap(s => s.domains_reached || []));
  const order = [...L.DOMAINS].sort((a, b) => (reached.has(b) ? 1 : 0) - (reached.has(a) ? 1 : 0));
  return h('section', { class: 'sec', 'aria-labelledby': 'dom-t' }, h('h2', { class: 'h2', id: 'dom-t' }, 'Where lines landed lately'),
    h('p', { class: 'lede', style: 'margin:-4px 0 10px' }, 'Read the map backwards: what has been moving each part of life.'),
    h('div', { class: 'chips' }, order.map(k => h('a', { class: 'chip' + (reached.has(k) ? '' : ' dim'), href: `/ripples/lands/${k}/` }, em(L.DOM[k].i), L.DOM[k].w))));
}
async function home() {
  ls.set('ko.visits', String(visits() + 1));
  const S0 = INLINE && INLINE.shocks ? INLINE : await D.shocks();
  const main = $('#main');
  if (!S0) { put(main, h('div', { class: 'empty' }, 'The Ripple Map could not load. Please try again in a minute.')); return; }
  const sn = sinceSnap(S0);
  const ar = S0.hero && S0.hero.reconstructed ? await D.archive() : null;
  put(main, h('div', { class: 'home' }, h('div', null, heroTicket(S0, ar), sinceBlock(sn)), h('div', null, board(S0, sn.fresh), domChips(S0))));
  if (visits() >= 2 && bip) $('#a2hs') && ($('#a2hs').hidden = false);
}

// ---------- the staircase (one inline SVG; the Week card uses the same drawing) ----------
function staircase(c, entries, opts = {}) {
  const fig = h('figure', { class: 'stair' + (opts.cls ? ' ' + opts.cls : '') });
  const svg = S('svg', { 'aria-hidden': 'true', focusable: 'false' }, fig);
  const cap = h('figcaption', null, h('span', null, opts.caption || 'Each lane: one stop against its own normal, on one shared scale. x = days since the shock.'));
  fig.append(cap);
  const api = { fig, lanes: [], mode: 'day', focus() {}, reveal() {}, setDay() {}, draw() {} };
  const onset = c.event.onset, asOf = c.as_of || today();
  const tD = L.daysBetween(onset, asOf);
  const lanes = [{ shock: true, n: { tier: 'shock', label: c.event.label, domain: null }, pts: L.seriesDays(c.event.spark, asOf, onset), band: null, od: 0 }];
  for (const e of entries.slice(0, desk() ? 16 : 11)) {
    const n = e.n, pts = L.seriesDays(n.spark, asOf, onset);
    const band = n.band && Array.isArray(n.band.lo) ? { lo: L.seriesDays(n.band.lo, asOf, onset), hi: L.seriesDays(n.band.hi, asOf, onset) } : null;
    lanes.push({ n, e, pts, band, od: n.onset ? L.daysBetween(onset, n.onset) : null, due: n.window_closed ? null : n.due || n.window_close ? L.daysBetween(onset, n.due || n.window_close) : null });
  }
  api.lanes = lanes;
  let hot = -1, dayClip = null;
  api.draw = () => {
    svg.replaceChildren();
    const W = Math.max(280, Math.round(fig.clientWidth - 12) || 316), H = desk() ? 320 : fig.classList.contains('min') ? 118 : 180;
    svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
    const gl = desk() ? 150 : 24, gr = 40, top = 8, bot = 18;
    const dEnd = Math.max(tD + 1, ...lanes.map(l => l.due ?? -99).filter(d => d > -99));
    const X = L.xScale(dEnd, gl, W - gr);
    const vis = l => l.pts.filter(p => p.d >= X.start && p.d <= X.end);
    const ext = lanes.map(l => { const v = vis(l).map(p => L.log2(p.v)).concat(l.band ? l.band.hi.filter(p => p.d >= X.start).map(p => L.log2(p.v)) : []); return { up: Math.max(0, ...v), dn: Math.max(0, ...v.map(x => -x)) }; });
    const n = lanes.length;
    const layout = k => { const b = []; let y = top + Math.max(6, ext[0].up * k); b.push(y); for (let i = 1; i < n; i++) { y += Math.max(desk() ? 18 : 13, ext[i - 1].dn * k + ext[i].up * k * 0.4 + 5); b.push(y); } return { b, tot: y + ext[n - 1].dn * k + bot }; };
    let lo = 1, hi = 90, k = 1;
    for (let it = 0; it < 24; it++) { const m = (lo + hi) / 2; if (layout(m).tot <= H) { k = m; lo = m; } else hi = m; }
    let { b } = layout(k);
    const slack = H - layout(k).tot; if (slack > 0) b = b.map((y, i) => y + (slack * (i + 0.5)) / n * 0.9);
    const grid = S('g', null, svg), body = S('g', null, svg), marks = S('g', null, svg);
    // x ticks and today
    for (const t of X.ticks) { S('line', { x1: X(t), x2: X(t), y1: top, y2: H - bot + 2, stroke: 'var(--grid-card)', 'stroke-width': 1 }, grid); const tx = S('text', { x: X(t), y: H - 4, class: 'ax', 'text-anchor': 'middle' }, grid); tx.textContent = t === 0 ? 'd0' : '+' + t; }
    const xt = X(tD); S('line', { x1: xt, x2: xt, y1: top, y2: H - bot + 2, stroke: 'var(--ink-3)', 'stroke-width': 1, opacity: 0.55 }, grid);
    const tl = S('text', { x: Math.min(W - 4, xt + 3), y: top + 8, class: 'lane-lbl', 'text-anchor': xt > W - 40 ? 'end' : 'start' }, grid); tl.textContent = 'today';
    // scale key: one doubling
    const kx = W - gr + 14, ky = H - bot - 4;
    S('path', { d: `M${kx} ${ky}v${-k}m-3 0h6m-6 ${k}h6`, stroke: 'var(--ink-3)', 'stroke-width': 1.5, fill: 'none' }, grid);
    const kt = S('text', { x: kx + 5, y: ky - k / 2 + 3, class: 'ax' }, grid); kt.textContent = '2×';
    const clipId = 'clp' + Math.random().toString(36).slice(2, 7);
    const cp = S('clipPath', { id: clipId }, S('defs', null, svg)); dayClip = S('rect', { x: 0, y: -40, width: W, height: H + 80 }, cp);
    body.setAttribute('clip-path', `url(#${clipId})`);
    const P = (arr, y0) => arr.map((p, i) => `${i ? 'L' : 'M'}${X(p.d).toFixed(1)} ${(y0 - k * L.log2(p.v)).toFixed(1)}`).join('');
    api.X = X; api.W = W;
    lanes.forEach((l, i) => {
      const y0 = b[i], g = S('g', { class: 'lane', opacity: l.shown || opts.all ? 1 : 0 }, body), n0 = l.n;
      l.g = g; l.y0 = y0;
      S('line', { x1: gl, x2: W - gr, y1: y0, y2: y0, stroke: 'var(--grid-card)', 'stroke-width': 1 }, g);
      if (l.band) {
        const lo2 = l.band.lo.filter(p => p.d >= X.start), hi2 = l.band.hi.filter(p => p.d >= X.start);
        if (lo2.length > 1) S('path', { d: P(hi2, y0) + 'L' + lo2.slice().reverse().map(p => `${X(p.d).toFixed(1)} ${(y0 - k * L.log2(p.v)).toFixed(1)}`).join('L') + 'Z', fill: 'var(--band)' }, g);
      }
      const pts = vis(l), cut = l.od ?? 1e9;
      const pre = pts.filter(p => p.d <= cut), post = pts.filter(p => p.d >= cut - 1);
      const flat = n0.tier === 'retracted', watch = n0.tier === 'watching';
      const col = flat ? 'var(--flat)' : 'var(--ink)';
      l.pre = pre.length > 1 ? S('path', { d: P(pre, y0), fill: 'none', stroke: col, 'stroke-width': 1.75, 'stroke-linejoin': 'round', 'stroke-dasharray': watch ? '4 4' : null, class: flat ? 'lane-flat' : null }, g) : null;
      l.post = post.length > 1 && l.od != null ? S('path', { d: P(post, y0), fill: 'none', stroke: l.shock ? 'var(--spike)' : col, 'stroke-width': l.shock ? 2.5 : 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', class: l.shock ? 'lane-hot' : flat ? 'lane-flat' : null }, g) : null;
      if (n0.attention_ripple) g.setAttribute('opacity', l.shown ? 0.5 : 0), l.att = true;
      // Watching: dashed track from today to the due date, hollow tile at the due date
      if (watch && l.due != null) {
        const a = S('line', { x1: X(Math.min(tD, l.due)), x2: X(l.due), y1: y0, y2: y0, stroke: 'var(--ink)', 'stroke-width': 2, 'stroke-dasharray': '4 4', class: RM ? null : 'marching' }, g);
        void a;
        S('rect', { x: X(l.due) - 5, y: y0 - 5, width: 10, height: 10, rx: 2, fill: 'var(--card)', stroke: 'var(--ink)', 'stroke-width': 1.75 }, g);
      }
      // lane label: icon (and the name on desktop)
      const lab = S('text', { x: 2, y: y0 + 4, class: 'lane-lbl' }, g);
      lab.textContent = desk() ? `${l.shock ? c.event.emoji || '' : L.domIcon(n0.domain)} ${L.plainParts([{ t: n0.label }]).slice(0, 20)}` : l.shock ? c.event.emoji || '●' : L.domIcon(n0.domain);
      if (!desk()) lab.setAttribute('font-size', 11);
      // onset dot + connector from the parent's onset, with the lag as a small flap
      if (l.od != null && l.od >= X.start) {
        const par = l.shock ? null : lanes.findIndex(q => (n0.parent_hop ? q.n.hop_id === n0.parent_hop : q.shock));
        if (par >= 0 && lanes[par].od != null) {
          const x1 = X(lanes[par].od), y1 = b[par], x2 = X(l.od), y2 = y0;
          S('path', { d: `M${x1} ${y1}L${x2} ${y2}`, stroke: 'var(--ink)', 'stroke-width': 1.25, opacity: 0.45, fill: 'none' }, g);
          const lag = n0.lag_days != null ? (n0.lag_days === 0 ? '0 d' : `+${Math.round(n0.lag_days)} d`) : '';
          if (lag && Math.abs(y2 - y1) > 12) {
            const mx = (x1 + x2) / 2 + 6, my = (y1 + y2) / 2;
            S('rect', { x: mx, y: my - 7, width: lag.length * 6 + 6, height: 14, rx: 2.5, fill: 'var(--marigold)' }, g);
            const lt = S('text', { x: mx + 3, y: my + 4, class: 'ax', style: 'fill:#0B3A40' }, g); lt.textContent = lag;
          }
        }
        l.dot = S('circle', { cx: X(l.od), cy: y0, r: l.shock ? 4.5 : 4, fill: l.shock ? 'var(--marigold)' : 'var(--card)', stroke: 'var(--ink)', 'stroke-width': 2 }, g);
      }
      l.val = null;
      if (!l.shock && post.length && n0.rho != null) {
        const ex = post.reduce((a, p) => (Math.abs(L.log2(p.v)) > Math.abs(L.log2(a.v)) ? p : a), post[0]);
        const vt = S('text', { x: Math.min(W - gr + 2, X(ex.d) + 6), y: y0 - k * L.log2(ex.v) + (ex.v < 1 ? 12 : -4), class: 'ax', style: 'font-size:11px;paint-order:stroke;stroke:var(--card);stroke-width:3px', opacity: 0 }, g);
        vt.textContent = L.mult(n0.rho, n0.unit); l.val = vt;
      }
    });
    if (hot >= 0) api.focus(hot, true);
    void marks;
  };
  api.focus = (i, silent) => {
    const prev = lanes[hot]; if (prev && prev.post && !prev.shock) { prev.post.setAttribute('stroke', prev.n.tier === 'retracted' ? 'var(--flat)' : 'var(--ink)'); prev.post.setAttribute('stroke-width', 2); prev.post.classList.remove('lane-hot'); if (prev.val) prev.val.setAttribute('opacity', 0); if (prev.dot) prev.dot.setAttribute('fill', 'var(--card)'); }
    hot = i; const l = lanes[i]; if (!l) return;
    if (l.post && !l.shock && l.n.tier !== 'retracted') { l.post.setAttribute('stroke', 'var(--spike)'); l.post.setAttribute('stroke-width', 3); l.post.classList.add('lane-hot'); }
    if (l.val) l.val.setAttribute('opacity', 1);
    if (l.dot && !l.shock) l.dot.setAttribute('fill', 'var(--marigold)');
    void silent;
  };
  api.reveal = (i, quiet) => {
    const l = lanes[i]; if (!l || l.shown) return; l.shown = true;
    if (!l.g) return;
    const op = l.att ? 0.5 : 1;
    if (RM || quiet) { l.g.animate([{ opacity: 0 }, { opacity: op }], { duration: 150, fill: 'forwards' }); l.g.setAttribute('opacity', op); return; }
    l.g.setAttribute('opacity', op);
    let t = 0;
    for (const [el, dur, ease] of [[l.pre, 420, 'cubic-bezier(.2,.8,.2,1)'], [l.post, 180, 'ease-in']]) {
      if (!el) continue; const len = el.getTotalLength();
      el.animate([{ strokeDasharray: `${len} ${len}`, strokeDashoffset: len }, { strokeDasharray: `${len} ${len}`, strokeDashoffset: 0 }], { duration: dur, delay: t, easing: ease, fill: 'backwards' });
      t += dur;
    }
    if (l.dot) l.dot.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 120, delay: Math.max(0, t - 200), fill: 'backwards' });
  };
  api.setDay = d => { if (dayClip && api.X) dayClip.setAttribute('width', d == null ? api.W + 40 : Math.max(0, api.X(d) + 1)); };
  api.showAll = () => lanes.forEach(l => { l.shown = true; if (l.g) l.g.setAttribute('opacity', l.att ? 0.5 : 1); });
  lanes[0].shown = true;
  let rt; addEventListener('resize', () => { clearTimeout(rt); rt = setTimeout(() => { api.draw(); if (opts.all) api.showAll(); }, 150); });
  requestAnimationFrame(() => { api.draw(); if (opts.all) api.showAll(); });
  return api;
}

// ---------- LINE ----------
function stopCard(c, e, idx, total, sc, laneIdx) {
  const n = e.n, par = L.parentLabel(c, n), quiet = !!c.event.sensitive;
  const card = h('li', { class: `stop ${n.tier}${n.attention_ripple ? ' att' : ''}${e.depth > 1 ? ' d' + Math.min(3, e.depth) : ''}`, id: 'stop-' + n.hop_id, 'data-lane': laneIdx });
  const kick = h('p', { class: 'kick' }, dtile(n), h('span', null, n.tier === 'watching' ? 'Watching' : `Stop ${idx} of ${total}`, sep(), L.domWord(n.domain)));
  const say = h('p', { class: 'say' });
  const parts = L.stopSentence(n, par);
  let firstFlap = null;
  for (const p of parts) {
    if (p.t) say.append(p.t);
    else { const f = flaps(p.flap, null, p.flap.replace('×', ' times').replace('+', 'plus ')); say.append(f); if (!firstFlap) firstFlap = [f, p.flap]; }
  }
  const T = L.TIER[n.tier];
  const facts = h('p', { class: 'facts' }, stamp(n.tier), h('span', { style: 'margin-left:8px' }),
    joinSep([n.tier_reason && n.tier !== 'retracted' && n.tier_reason !== 'attention ripple' ? n.tier_reason : null,
      n.attention_ripple ? 'attention ripple' : null,
      n.channels && n.channels.of ? `${n.channels.agree} of ${n.channels.of} sources agree` : null,
      n.provisional ? h('span', { class: 'prov' }, 'provisional') : null]));
  add(card, kick);
  if (e.depth > 1) card.append(h('p', { class: 'from' }, `↳ after ${par}, if the previous step holds`));
  if (n.tier === 'retracted') card.append(h('p', { class: 'nm' }, n.label), h('p', { class: 'kick', style: 'margin-top:6px' }, h('span', { class: 'flag' }, `retracted ${L.fmtDay(n.retracted?.date)}`)));
  card.append(say, facts);
  if (n.tier === 'measured' || n.tier === 'likely') {
    if (n.p_1_in) card.append(h('p', { class: 'odds' }, L.lookalikes(n.p_1_in)));
    const fr = L.flukeRate(n.f_1_in, n.f_warming); if (fr) card.append(h('p', { class: 'odds' }, fr));
  }
  if (n.tier === 'watching') {
    if (!n.window_closed && n.window_close) {
      const a = L.dayMs(c.event.onset), z = L.dayMs(n.window_close), t = Math.min(z, Math.max(a, L.dayMs(today())));
      const pct = Math.round(((t - a) / Math.max(1, z - a)) * 100);
      const duePct = n.due ? Math.round(((L.dayMs(n.due) - a) / Math.max(1, z - a)) * 100) : null;
      card.append(h('div', { class: 'wt' }, h('p', { class: 'due' }, n.due ? `Next look ${L.fmtDate(n.due)}` : `Window closes ${L.fmtDate(n.window_close)}`),
        h('div', { class: 'track', role: 'img', 'aria-label': `Window ${pct}% gone: opened ${L.fmtDay(c.event.onset)}, closes ${L.fmtDay(n.window_close)}` }, h('i', { style: `width:${pct}%` }), duePct != null ? h('b', { style: `left:calc(${Math.min(99, duePct)}% - 1px)` }) : null),
        h('p', { class: 'lbls' }, h('span', null, `Shock ${L.fmtDay(c.event.onset)}`), h('span', null, `window closes ${L.fmtDay(n.window_close)}`))));
    }
    if (n.sentence) card.append(h('p', { class: 'eng' }, n.sentence));
    if (!n.window_closed && n.due) card.append(h('p', { class: 'xs', style: 'margin-top:6px' }, h('a', { class: 'lnk', href: `${C.STORAGE}ics/hop-${n.hop_id}.ics`, download: `ripple-${n.hop_id}.ics` }, 'Add the next look to my calendar')));
  } else if (n.tier === 'retracted' && n.sentence) {
    /* the reason is already the sentence */
  }
  if (n.path && n.path.length && n.tier !== 'watching') card.append(h('p', { class: 'eng' }, n.path.map(p => `${p.text} (${p.source})`).join('; ')));
  card.append(h('div', { class: 'open' }, h('a', { class: 'btn sec', href: L.stopUrl(c.event.slug, n.hop_id), 'data-hop': n.hop_id }, n.tier === 'watching' ? 'What we are waiting for' : 'Open the evidence')));
  card._flap = firstFlap; card._quiet = quiet; void T; void sc;
  return card;
}
function flatStub(c, parentHop, where) {
  const fl = (c.flat || []).filter(f => (f.parent_hop || null) === (parentHop || null));
  if (!fl.length) return null;
  const list = h('ul', { class: 'flatlist', hidden: true }, fl.map(f => h('li', null, h('span', null, em(L.domIcon(f.domain)), ' ', f.label, h('span', { class: 'sr' }, `: ${L.num(f.rho)} times its normal, ${f.reason}`)), spark(f.spark), h('b', { 'aria-hidden': 'true' }, f.rho != null ? L.num(f.rho) + '×' : ''))));
  const b = h('button', { class: 'stub', 'aria-expanded': 'false', onclick: () => { const o = list.hidden; list.hidden = !o; b.setAttribute('aria-expanded', String(o)); } },
    h('span', { class: 'bot', 'aria-hidden': 'true' }, '⊥'), `${fl.length} stayed flat${where ? ' ' + where : ''}`, icon('chev', 'chev'));
  return h('div', { style: 'margin:4px 0 12px' }, b, list);
}
function shareBlock(c, frozenK) {
  const text = L.shareLine(c);
  const og = `${C.STORAGE}og/line-${c.event.event_id}-v${frozenK || c.version}.png`;
  return h('section', { class: 'sec', 'aria-labelledby': 'sh-t' }, h('h2', { class: 'h2', id: 'sh-t' }, 'Share this line'),
    h('div', { class: 'slip' }, h('small', null, 'What gets shared'), text),
    h('div', { class: 'btns' }, h('button', { class: 'btn', onclick: () => share(text, 'line') }, icon('share'), 'Share'),
      h('button', { class: 'btn sec', onclick: () => copy(text) }, icon('copy'), 'Copy text'),
      c.event.sensitive ? null : h('button', { class: 'btn sec', onpointerenter: () => prefetchImg(og), onclick: () => shareImage(og, text, 'line', `ripple-${c.event.event_id}.png`) }, icon('img'), 'Share image')),
    h('p', { class: 'xs muted', style: 'margin-top:8px' }, c.text_plain || ''));
}
function followBlock(c) {
  const id = c.event.event_id;
  const next = (c.nodes || []).filter(n => n.tier === 'watching' && !n.window_closed && n.window_close).map(n => n.window_close).sort().pop();
  return h('div', { class: 'follow' },
    h('a', { class: 'row', href: `${C.STORAGE}feed/line-${id}.xml` }, h('span', { class: 'ic', 'aria-hidden': 'true' }, em('📰')), h('span', null, 'Follow this line (RSS)', h('small', null, 'One entry per new version')), icon('chev', 'chev')),
    next ? h('a', { class: 'row', href: `${C.STORAGE}ics/line-${id}.ics`, download: `line-${id}.ics` }, h('span', { class: 'ic', 'aria-hidden': 'true' }, em('📅')), h('span', null, 'Calendar: when its windows close', h('small', null, `Last window closes ${L.fmtDate(next)}`)), icon('chev', 'chev')) : null,
    h('a', { class: 'row', href: '/ripples/remind.ics', download: 'ripple-map-daily.ics' }, h('span', { class: 'ic', 'aria-hidden': 'true' }, em('🗓')), h('span', null, 'New lines most mornings', h('small', null, 'A daily calendar note at about 08:45 UTC')), icon('chev', 'chev')),
    h('button', { class: 'row', id: 'a2hs', hidden: true }, h('span', { class: 'ic', 'aria-hidden': 'true' }, em('📲')), h('span', null, 'Add the Ripple Map to your home screen'), icon('chev', 'chev')));
}
function waitlist() {
  const email = h('input', { type: 'email', required: true, maxlength: 254, autocomplete: 'email', placeholder: 'you@example.com', 'aria-label': 'Email address' });
  const out = h('p', { class: 'xs', role: 'status', style: 'margin-top:6px' });
  const f = h('form', { onsubmit: async ev => { ev.preventDefault(); try { await rpc('ripples_join', { p_email: email.value.trim(), p_role: null, p_price: 'free', p_topics: null, p_source: 'line' }); put(out, "Saved. We'll write once, when the email starts."); } catch (e) { put(out, 'That did not save. Please try again later.'); } } }, email, h('button', { class: 'btn sec sm', type: 'submit' }, 'Add me'));
  return h('section', { class: 'wl', 'aria-labelledby': 'wl-t' }, h('h2', { id: 'wl-t', style: 'font:700 15px/1.3 var(--sans)' }, 'Want new lines by email?'),
    h('p', { class: 'sm muted', style: 'margin-top:4px' }, "We don't send email yet. Leave your address and we'll write once, when the daily email starts."), f, out,
    C.STRIPE.support ? h('p', { class: 'sm', style: 'margin-top:12px' }, h('b', null, 'Support Knock⌃On. '), 'Pay what you want, from $2. It unlocks nothing: the map and archive stay free. ', h('a', { class: 'lnk', href: C.STRIPE.support, target: '_blank', rel: 'noopener' }, 'Support')) : null);
}
async function linePage(r) {
  const main = $('#main');
  const isStop = r.route === 'stop';
  let hopDoc = null, c = null;
  if (isStop) { hopDoc = INLINE && INLINE.hop_id ? INLINE : await D.hop(r.hop); c = await D.cascade(r.event || hopDoc?.event?.event_id); }
  else c = INLINE && INLINE.event && (!r.version || INLINE.version === r.version) ? INLINE : await D.cascade(r.event, r.version);
  if (!c || !c.event) {
    put(main, h('div', { class: 'empty' }, r.version ? 'This version is not public. ' : 'This line is not published. ', h('a', { class: 'lnk', href: r.event ? L.lineUrl(r.slug || '') : '/ripples/map/' }, 'See the live map')));
    return;
  }
  landing(r);
  document.title = `${c.event.label}: where it rippled${r.version ? `, version ${r.version}` : ''} | Knock⌃On Ripple Map`;
  const quiet = !!c.event.sensitive;
  const choice = {};
  const hideMid = ls.get('ko.hide_middle') === '1' || new URLSearchParams(location.search).get('hide') === '1';
  const order = () => L.lineOrder(c, choice);
  let entries = order();
  const stations = entries.filter(e => L.isStation(e.n));
  const total = stations.length;
  // header
  const meta = joinSep([`Began ${L.fmtDay(c.event.onset)}`, c.event.magnitude_x ? `${L.num(c.event.magnitude_x)}× its normal attention` : null, `day ${L.lineDays(c)}`, r.version ? `version ${r.version}, frozen` : L.STATUS[c.status], c.event.reconstructed ? 'reconstructed' : null]);
  const head = h('header', { class: 'lh' }, h('span', { class: 'tk-emo', 'aria-hidden': 'true' }, em(c.event.emoji || '🌀')), h('div', null, h('h1', null, c.event.label), h('p', { class: 'meta' }, meta)));
  const note = h('div', { id: 'grown' });
  // sticky strip + staircase
  const stripEl = h('div', { class: 'strip', role: 'list', 'aria-label': 'Stops on this line' });
  const shownEntries = entries.filter(e => e.depth < 3);
  const sc = staircase(c, shownEntries, { caption: null });
  const stick = h('div', { class: 'stick' }, stripEl, sc.fig);
  const tiles = [];
  const buildStrip = () => {
    stripEl.replaceChildren(h('span', { class: 'dt shock', role: 'listitem', 'aria-label': c.event.label, title: c.event.label, onclick: () => scrollTo({ top: 0, behavior: RM ? 'auto' : 'smooth' }) }, em(c.event.emoji || '🌀')));
    tiles.length = 0;
    shownEntries.forEach((e, i) => {
      const n = e.n;
      stripEl.append(h('span', { class: `trk${n.tier === 'watching' ? ' w' : n.tier === 'likely' ? ' l' : ''}${n.attention_ripple ? ' att' : ''}`, 'aria-hidden': 'true' }));
      const t = dtile(n); t.setAttribute('role', 'listitem'); t.removeAttribute('aria-hidden'); t.setAttribute('aria-label', `${L.tierWord(n.tier)}: ${n.label}`); t.title = `${n.label} (${L.tierWord(n.tier)})`;
      t.addEventListener('click', () => document.getElementById('stop-' + n.hop_id)?.scrollIntoView({ behavior: RM ? 'auto' : 'smooth', block: 'start' }));
      if (hideMid && i > 0 && i < shownEntries.length - 1 && L.isMoved(n)) t.replaceChildren('?');
      stripEl.append(t); tiles.push(t);
    });
    stripEl.append(h('span', { class: 'day' }, r.version ? `v${r.version}` : `day ${L.lineDays(c)}`, sep(), r.version ? 'frozen' : c.status === 'running' ? 'live' : L.STATUS[c.status]));
  };
  buildStrip();
  // stop cards
  const list = h('ol', { class: 'stops', 'aria-label': 'Stops, in the order they moved' });
  let k = 0, lane = 0;
  const cards = [];
  const d3 = [];
  for (const e of entries) {
    if (e.depth >= 3) { d3.push(e); continue; }
    lane++;
    const idx = L.isStation(e.n) ? ++k : 0;
    const card = stopCard(c, e, idx, total, sc, lane);
    if (e.folded && e.folded.length) {
      const chips = h('div', { class: 'fork' }, e.folded.map(f => h('button', { class: 'sw', onclick: () => { choice[e.n.hop_id] = f.hop_id; rerender(); } }, h('span', { 'aria-hidden': 'true' }, '⑂'), `1 more branch: ${f.label}`)));
      card.append(chips);
    }
    const fs = flatStub(c, e.n.hop_id, `after ${e.n.label}`); if (fs) card.append(fs);
    cards.push(card); list.append(card);
    if (e.depth === 1 && !entries.some(x => x.depth === 1 && L.isStation(x.n) && entries.indexOf(x) > entries.indexOf(e)) && L.isStation(e.n)) {
      const root = flatStub(c, null, `after ${c.event.label}`); if (root) list.append(h('li', { style: 'list-style:none' }, root));
    }
  }
  if (!stations.length) { const root = flatStub(c, null, `after ${c.event.label}`); if (root) list.prepend(h('li', { style: 'list-style:none' }, root)); }
  const tail = [];
  if (d3.length) tail.push(h('details', { class: 'depth3' }, h('summary', { class: 'sw' }, `… if the previous step holds: ${L.plural(d3.length, 'more stop')}`), h('ol', null, d3.map(e => stopCard(c, e, 0, total, sc, -1)))));
  if (c.held_back && (c.held_back.stops || c.held_back.flat)) tail.push(h('p', { class: 'held' }, `${L.plural(c.held_back.stops + c.held_back.flat, 'more tested path')} ${c.held_back.stops + c.held_back.flat === 1 ? 'is' : 'are'} not listed yet: ${c.held_back.reason}.`));
  for (const ri of c.route_ideas || []) tail.push(h('p', { class: 'idea' }, `Route idea, not measured: ${ri.text} (${ri.source}).`));
  tail.push(h('p', { class: 'lend' + (c.status === 'nowhere' ? ' nowhere' : '') }, L.lineEnd(c)));
  const den = c.denominators || {}, ctl = c.control?.stops;
  const denEl = h('div', { class: 'den' },
    h('p', null, h('b', null, `Tested ${L.plural(den.tested ?? 0, 'path')} on this line`), sep(), `${L.fmtInt(den.moved ?? 0)} moved`, sep(), `${L.fmtInt(den.measured ?? 0)} Measured`, sep(), `about ${L.expected(den.expected_false_links)} expected false links`),
    ctl ? h('p', { style: 'margin-top:6px' }, `The control ripple (${c.control.label || "a page that wasn't trending"}, same tests): ${ctl.measured} Measured, ${ctl.likely} Likely, ${ctl.watching} Watching, ${ctl.flat} flat.`) : null,
    (c.rivals || []).length ? h('p', { style: 'margin-top:6px' }, 'Also active this week: ', c.rivals.map(x => `${x.label} (${x.note})`).join('; '), '. A shared stop could be a common cause.') : null,
    h('p', { class: 'xs', style: 'margin-top:6px' }, `Method ${c.method || C.METHOD}`, c.ledger?.seq ? [sep(), `ledger #${L.fmtInt(c.ledger.seq)}`] : null, sep(), h('a', { class: 'lnk', href: '/ripples/methods/' }, 'How we test')));
  // replay scrubber: stops light as their onset day passes; 2.5 s end to end; any tap skips
  const dMax = L.lineDays(c), dMin = -3;
  const rng = h('input', { type: 'range', min: dMin, max: dMax, value: dMax, step: 1, 'aria-label': 'Replay: day since the shock' });
  const lbl = h('span', null, `Replay: day ${dMax}`);
  let playing = 0;
  const setDay = d => {
    sc.setDay(d); lbl.textContent = d < 0 ? `Replay: ${-d} days before` : `Replay: day ${d}`;
    shownEntries.forEach((e, i) => { const on = e.n.onset ? L.daysBetween(c.event.onset, e.n.onset) <= d : d >= dMax; tiles[i]?.style.setProperty('opacity', on ? '1' : '.35'); });
  };
  rng.addEventListener('input', () => { cancelAnimationFrame(playing); sc.showAll(); setDay(+rng.value); });
  const play = () => {
    sc.showAll(); const t0 = performance.now();
    const step = t => { const f = Math.min(1, (t - t0) / 2500), d = dMin + (dMax - dMin) * f; setDay(d); rng.value = Math.round(d); if (f < 1) playing = requestAnimationFrame(step); else setDay(null); };
    if (RM) { setDay(null); return; }
    playing = requestAnimationFrame(step);
  };
  addEventListener('pointerdown', () => { if (playing) { cancelAnimationFrame(playing); playing = 0; setDay(null); rng.value = dMax; } }, true);
  const replay = h('div', { class: 'replay' }, h('button', { 'aria-label': 'Replay the line from the shock to today', onclick: e => { e.stopPropagation(); play(); } }, icon('play')), h('label', null, lbl, rng));
  // desktop By hop / By day toggle
  const seg = h('span', { class: 'seg dsk-only', role: 'group', 'aria-label': 'Spacing' },
    h('button', { 'aria-pressed': 'false', onclick: ev => { toggleMode('hop', ev); } }, 'By hop'), h('button', { 'aria-pressed': 'true', onclick: ev => { toggleMode('day', ev); } }, 'By day'));
  const toggleMode = (m, ev) => { [...seg.children].forEach(b => b.setAttribute('aria-pressed', String(b === ev.currentTarget))); sc.mode = m; sc.fig.classList.toggle('byhop', m === 'hop'); hopMode(sc, m === 'hop'); };
  const cap = sc.fig.querySelector('figcaption');
  put(cap, h('span', null, 'Each lane is one stop against its own normal, on one shared scale; x is days since the shock.'), h('span', { class: 'sp' }), desk() ? seg : null);
  // assemble
  const aside = h('aside', null, head, note,
    h('div', { class: 'dsk' }, denEl.cloneNode(true)));
  const body = h('div', null, h('div', { class: 'mob' }), stick, list, tail, h('div', { class: 'mob' }, denEl), replay, shareBlock(c, r.version), followBlock(c), waitlist());
  put(main, h('div', { class: 'line' }, aside, body));
  const rerender = () => { linePage(r); };
  // grown since shared (frozen version): compare with the live line
  if (r.version) {
    const g = c.grown_to || (await (async () => { const live = await D.cascade(c.event.event_id); return live ? { ...L.grownSince(c, live), url: L.lineUrl(c.event.slug) } : null; })());
    if (g && g.version > r.version) put(note, h('p', { class: 'note' }, em('🌱'), h('span', null, g.stops_added > 0 ? `It's grown since this was shared: +${L.plural(g.stops_added, 'stop')}. ` : g.stops_added < 0 ? `Since this was shared, ${L.plural(-g.stops_added, 'stop')} came off the line. ` : 'There is a newer version of this line. ', h('a', { href: L.lineUrl(c.event.slug) }, 'See the live line'))));
    else if (c.grown_since && c.grown_since.stops_added > 0) put(note, h('p', { class: 'note soft' }, `Version ${r.version}: ${L.plural(c.grown_since.stops_added, 'stop')} more than version ${c.grown_since.version}.`));
  }
  // scrollytelling: a lane draws as its card enters; the card most in view is the focus (marigold spike, ringed tile)
  const io = new IntersectionObserver(obs => {
    for (const o of obs) {
      if (!o.isIntersecting) continue;
      const li = +o.target.dataset.lane; if (!(li >= 1)) continue;
      sc.reveal(li, quiet); sc.focus(li);
      tiles.forEach((t, i) => t.setAttribute('aria-current', String(i === li - 1)));
      if (o.target._flap && !o.target._counted) { o.target._counted = true; countUp(o.target._flap[0], o.target._flap[1], quiet); }
    }
  }, { rootMargin: '-40% 0px -35% 0px' });
  const io2 = new IntersectionObserver(obs => { for (const o of obs) if (o.isIntersecting) { const li = +o.target.dataset.lane; sc.reveal(li, quiet); if (o.target._flap && !o.target._counted) { o.target._counted = true; countUp(o.target._flap[0], o.target._flap[1], quiet); } } }, { threshold: 0.35 });
  cards.forEach(cd => { io.observe(cd); io2.observe(cd); });
  requestAnimationFrame(() => { if (cards[0]) { sc.reveal(1, quiet); sc.focus(1); tiles[0]?.setAttribute('aria-current', 'true'); } });
  // shrink the sticky chart once the reader is into the stops (no layout animation)
  const sent = h('div', { 'aria-hidden': 'true' }); list.before(sent);
  new IntersectionObserver(([o]) => { if (desk()) return; const min = !o.isIntersecting && o.boundingClientRect.top < 0; if (min !== sc.fig.classList.contains('min')) { sc.fig.classList.toggle('min', min); sc.draw(); sc.showAll(); } }).observe(sent);
  // evidence: open in place (the stop URL is the deep link)
  main.addEventListener('click', ev => {
    const a = ev.target.closest('a[data-hop]'); if (!a || ev.metaKey || ev.ctrlKey || ev.shiftKey) return;
    ev.preventDefault(); openSheet(+a.dataset.hop, c, a, true);
  });
  if (isStop && hopDoc) openSheet(hopDoc, c, null, false);
  addEventListener('popstate', () => { if (!/\/stop\/\d+\/$/.test(location.pathname)) closeSheet(false); });
}
function hopMode(sc, on) {
  // By hop: each lane shifted so its onset sits in its own column; reads the order, not the calendar
  sc.lanes.forEach((l, i) => { if (!l.g || !sc.X) return; const dx = on && l.od != null ? (sc.X(0) + (i * (sc.W - sc.X(0) - 60)) / sc.lanes.length) - sc.X(l.od) : 0; l.g.style.transition = RM ? '' : 'transform 320ms cubic-bezier(.2,.8,.2,1)'; l.g.style.transform = `translateX(${dx}px)`; });
}

// ---------- evidence sheet ----------
let sheetState = null;
function closeSheet(nav = true) {
  if (!sheetState) return;
  const { el, scrim, opener, pushed, lineHref, keyh } = sheetState; sheetState = null;
  el.classList.remove('on'); scrim.classList.remove('on');
  document.removeEventListener('keydown', keyh, true);
  setTimeout(() => { el.remove(); scrim.remove(); }, RM ? 0 : 320);
  document.body.style.overflow = '';
  if (nav) { if (pushed) history.back(); else history.replaceState(null, '', lineHref); }
  opener?.focus?.();
}
function q1Chart(q, parentOnset) {
  const svg = S('svg', { class: 'q1', viewBox: '0 0 340 150', role: 'img', preserveAspectRatio: 'none' });
  const s = (q.series || []).map(Number), n = s.length; if (n < 3) return null;
  const all = s.concat(q.band_lo || [], q.band_hi || [], q.last_year || []).filter(v => v > 0 && isFinite(v));
  const lo = Math.min(0.7, ...all), hi = Math.max(1.4, ...all);
  const pl = 30, pr = 8, pt = 8, pb = 20, W = 340, H = 150;
  const x = i => pl + (i / (n - 1)) * (W - pl - pr), y = v => pt + (1 - (L.log2(v) - L.log2(lo)) / (L.log2(hi) - L.log2(lo))) * (H - pt - pb);
  const P = (arr, a = 0) => arr.map((v, i) => (v > 0 ? `${i ? 'L' : 'M'}${x(i + a).toFixed(1)} ${y(v).toFixed(1)}` : '')).join('').replace(/^L/, 'M');
  if (q.window) S('rect', { x: x(q.window[0]), y: pt, width: Math.max(2, x(Math.min(n - 1, q.window[1])) - x(q.window[0])), height: H - pt - pb, fill: 'var(--spike-wash)' }, svg);
  for (const g of [0.5, 1, 2, 4, 8].filter(v => v >= lo && v <= hi)) { S('line', { x1: pl, x2: W - pr, y1: y(g), y2: y(g), stroke: 'var(--grid-panel)' }, svg); const t = S('text', { x: pl - 4, y: y(g) + 3.5, 'text-anchor': 'end', 'font-size': 10, fill: 'var(--on-panel-3)', 'font-family': 'var(--display)', 'font-weight': 800 }, svg); t.textContent = g + '×'; }
  if (q.band_lo && q.band_hi) S('path', { d: P(q.band_hi) + 'L' + q.band_lo.map((v, i) => [x(i), y(v)]).reverse().map(p => p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join('L') + 'Z', fill: 'rgba(234,243,240,.13)' }, svg);
  if (q.last_year) S('path', { d: P(q.last_year), fill: 'none', stroke: 'var(--on-panel-3)', 'stroke-width': 1.25, opacity: 0.8 }, svg);
  const oi = q.onset_index ?? n;
  S('path', { d: P(s.slice(0, oi + 1)), fill: 'none', stroke: 'var(--on-panel)', 'stroke-width': 2, 'stroke-linejoin': 'round' }, svg);
  if (oi < n) S('path', { d: P(s.slice(oi), oi), fill: 'none', stroke: 'var(--spike)', 'stroke-width': 2.75, 'stroke-linejoin': 'round', class: 'lane-hot' }, svg);
  if (q.onset_index != null) { S('line', { x1: x(oi), x2: x(oi), y1: pt, y2: H - pb, stroke: 'var(--event)', 'stroke-width': 1.25 }, svg); }
  const d0 = S('text', { x: pl, y: H - 5, 'font-size': 10.5, fill: 'var(--on-panel-3)', 'font-family': 'var(--sans)' }, svg); d0.textContent = L.fmtDay(q.from);
  const d1 = S('text', { x: W - pr, y: H - 5, 'text-anchor': 'end', 'font-size': 10.5, fill: 'var(--on-panel-3)', 'font-family': 'var(--sans)' }, svg); d1.textContent = L.fmtDay(L.addDays(q.from, n - 1));
  if (q.onset_index != null) { const t = S('text', { x: x(oi) - 4, y: pt + 10, 'text-anchor': 'end', 'font-size': 10.5, fill: 'var(--on-panel-2)', 'font-family': 'var(--sans)' }, svg); t.textContent = parentOnset ? `shock ${L.fmtDay(parentOnset)}` : 'shock'; }
  svg.setAttribute('aria-label', `The series against its normal band over ${n} days, with the same weeks last year; the part after the shock is highlighted. Values are in the table under Show the math.`);
  return svg;
}
async function openSheet(hopOrDoc, c, opener, push) {
  if (sheetState) closeSheet(false);
  const scrim = h('div', { class: 'scrim', onclick: () => closeSheet() });
  const el = h('div', { class: 'sheet', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'ev-t', tabindex: '-1' });
  document.body.append(scrim, el);
  const lineHref = L.lineUrl(c.event.slug);
  const hopId = typeof hopOrDoc === 'number' ? hopOrDoc : hopOrDoc.hop_id;
  const node = (c.nodes || []).find(n => n.hop_id === hopId);
  const keyh = e => {
    if (e.key === 'Escape') { e.preventDefault(); closeSheet(); return; }
    if (e.key !== 'Tab') return;
    const f = [...el.querySelectorAll('a[href],button:not([disabled]),summary,input,[tabindex="0"]')].filter(x => x.offsetParent !== null);
    if (!f.length) return; const a = f[0], z = f[f.length - 1];
    if (e.shiftKey && document.activeElement === a) { e.preventDefault(); z.focus(); } else if (!e.shiftKey && document.activeElement === z) { e.preventDefault(); a.focus(); }
  };
  document.addEventListener('keydown', keyh, true);
  sheetState = { el, scrim, opener, pushed: push, lineHref, keyh };
  if (push) history.pushState({ sheet: hopId }, '', L.stopUrl(c.event.slug, hopId));
  document.body.style.overflow = 'hidden';
  put(el, h('div', { class: 'grab' }, h('b', null, node ? `${L.tierWord(node.tier)} stop, ${L.domWord(node.domain)}` : 'Evidence'), h('button', { class: 'x', 'aria-label': 'Close the evidence', onclick: () => closeSheet() }, icon('x'))),
    h('p', { class: 'ev-h', id: 'ev-t' }, node ? node.label : 'Loading the evidence…'));
  requestAnimationFrame(() => { scrim.classList.add('on'); el.classList.add('on'); el.focus(); });
  const d = typeof hopOrDoc === 'number' ? await D.hop(hopOrDoc) : hopOrDoc;
  if (!sheetState || sheetState.el !== el) return;
  if (!d || !d.node) { add(el, h('p', { class: 'qs' }, 'The evidence file is not published yet.')); return; }
  renderEvidence(el, d, c);
}
function renderEvidence(el, d, c) {
  const T = L.TIER[d.tier] || L.TIER.watching, u = d.q1_normal?.unit || 'x', x = d.headline || {}, q5 = d.q5_luck || {}, q3 = d.q3_who || {}, q4 = d.q4_why || {}, q2 = d.q2_after || {}, m = d.math || {};
  const quiet = !!(d.event?.sensitive || c.event.sensitive);
  const fig = x.rho != null ? flaps(L.mult(x.rho, u), null, L.mult(x.rho, u).replace('×', ' times')) : null;
  const live = h('p', { class: 'sr', 'aria-live': 'polite' });
  const sec = (num, title, ...k) => h('section', { class: 'qs' }, h('h3', null, h('i', { 'aria-hidden': 'true' }, num), title), ...k);
  const placebo = L.placeboStrip(q5.placebo);
  const pstrip = placebo.tiles ? h('div', { class: 'pstrip', role: 'img', 'aria-label': `${placebo.exceed} of ${placebo.n} placebo tests looked this strong` }, Array.from({ length: placebo.tiles }, (_, i) => h('i', { class: i >= placebo.tiles - placebo.lit ? 'lit' : '' }))) : null;
  const ft = L.flukeTiles(q5.f_1_in);
  const meter = ft && !q5.f_warming ? h('div', { class: 'meter', role: 'img', 'aria-label': `One tile in ${ft} marked` }, Array.from({ length: ft }, (_, i) => h('i', { class: i === Math.floor(ft / 2) ? 'lit' : '' }))) : null;
  const flatById = new Map((c.flat || []).map(f => [f.label, f]));
  const chan = ch => { const nod = ch.zhat == null || (ch.kappa != null && ch.kappa < 0.5); return h('div', { class: `ch ${ch.agree ? 'agree' : nod ? 'nodata' : ''}` }, ch.label || ch.code, h('small', null, ch.agree ? 'agrees' : nod ? 'still warming up' : "didn't move", ch.zhat != null ? `, ž ${Number(ch.zhat).toFixed(1)}` : '')); };
  const q1 = d.q1_normal ? q1Chart(d.q1_normal, q2.parent_onset) : null;
  const csv = m.csv || `${C.STORAGE}hop/${d.hop_id}.csv`;
  const issue = `https://github.com/bsunter93/Ben-Sunters-Website/issues/new?title=${encodeURIComponent(`Ripple Map: stop ${d.hop_id} (${d.node.label})`)}&body=${encodeURIComponent(`What looks wrong on https://bensunter.com${L.stopUrl(d.event.slug, d.hop_id)} ?\n\n`)}`;
  const rows = (arr) => h('div', { class: 'tw' }, h('table', { class: 't' }, h('tbody', null, arr.filter(Boolean).map(([k, v]) => h('tr', null, h('th', { scope: 'row' }, k), h('td', null, v ?? '–'))))));
  const zRows = Object.entries(m.z_by_source || {}).map(([k, v]) => h('tr', null, h('th', { scope: 'row' }, k), h('td', { class: 'n' }, v.zhat != null ? Number(v.zhat).toFixed(2) : '–'), h('td', { class: 'n' }, v.S != null ? Number(v.S).toFixed(2) : '–'), h('td', { class: 'n' }, v.kappa ?? '–'), h('td', { class: 'n' }, m.weights?.[k] ?? '–'), h('td', null, (v.sources || []).join(', '))));
  const q1rows = d.q1_normal ? d.q1_normal.series.map((v, i) => h('tr', null, h('td', null, L.fmtDay(L.addDays(d.q1_normal.from, i))), h('td', { class: 'n' }, v), h('td', { class: 'n' }, d.q1_normal.band_lo?.[i] ?? '–'), h('td', { class: 'n' }, d.q1_normal.band_hi?.[i] ?? '–'), h('td', { class: 'n' }, d.q1_normal.last_year?.[i] ?? '–'))) : [];
  put(el, el.firstChild,
    h('div', { class: 'ev-h' },
      h('div', { class: 'ev-stamp' }, stamp(d.tier, false), d.provisional ? h('span', { class: 'prov' }, 'provisional') : null, d.tier_reason && d.tier !== 'retracted' ? h('span', { class: 'xs', style: 'color:var(--on-panel-2)' }, d.tier_reason) : null),
      h('p', { class: 'ev-def' }, `${T.w}: ${T.def}`),
      h('h2', { class: 'ev-name', id: 'ev-t' }, em(L.domIcon(d.node.domain)), ' ', d.node.label),
      d.retracted ? h('p', { class: 'retban', role: 'note' }, `Retracted ${L.fmtDate(d.retracted.date)}: ${d.retracted.reason}. Everything below stays visible.`) : null,
      fig ? h('div', { class: 'ev-fig' }, fig, h('p', null, u === 'points' ? 'points against its normal' : 'its normal,', h('br'), h('b', null, x.lag_days === 0 ? 'the same day as' : `+${L.plural(x.lag_days, 'day')} after`), ' ', x.parent_label || d.parent?.label)) : null,
      h('p', { class: 'ev-say' }, L.evidenceHeadline(d)),
      live),
    d.q1_normal ? sec('Q1', 'Is this normal for it?', q1, h('p', { class: 'q1k' }, h('span', null, h('i', { style: 'background:var(--on-panel)' }), 'this series'), h('span', null, h('i', { style: 'background:var(--spike)' }), 'after the shock'), h('span', null, h('i', { style: 'background:rgba(234,243,240,.3);height:8px' }), 'its normal range'), h('span', null, h('i', { style: 'background:var(--on-panel-3);height:1.5px' }), 'same weeks last year')),
      h('p', null, `Its normal is measured over ${d.q1_normal.baseline ? L.daysBetween(d.q1_normal.baseline.from, d.q1_normal.baseline.to) + 1 : 91} days ending ${d.q1_normal.baseline ? L.fmtDay(d.q1_normal.baseline.to) : 'three weeks before the shock'}, matched by weekday${d.q1_normal.baseline?.year_ago_term ? ', with a year-ago term' : ''}. The faint line is the same weeks last year: the placebo you can see.`)) : null,
    sec('Q2', 'Did it move after, not before?',
      h('div', { class: 'ruler' }, h('span', { class: 'd' }, L.fmtDate(q2.parent_onset)), h('span', { class: 'ln', 'aria-hidden': 'true' }), h('span', { class: 'd' }, L.fmtDate(q2.node_onset)), h('span', { class: q2.order_ok ? 'ok' : '' }, q2.lag_days != null ? (q2.lag_days === 0 ? 'same day' : `+${L.plural(q2.lag_days, 'day')}`) : '', q2.order_ok ? ' ✓' : '')),
      h('p', null, q2.pre_trend?.flag ? 'Already moving before the shock: capped at Likely.' : `Not already moving: its pre-trend score was ${q2.pre_trend?.s ?? '–'} (the flag is at 2).`)),
    sec('Q3', 'Who else saw it?', h('div', { class: 'chs' }, (q3.channels || []).map(chan)),
      h('p', null, h('b', null, `${q3.agree ?? 0} of ${q3.of ?? 0} independent sources agree.`), q3.loso_ok === false ? ' It drops below the bar without its strongest source.' : '', q3.common_shock ? ' The onset day was a common-shock day.' : ''),
      (q3.excluded || []).length ? h('p', null, 'Not counted: ', q3.excluded.map(e => `${e.label} (${e.why})`).join('; '), '.') : null),
    sec('Q4', 'Why these two?', h('ul', { class: 'path' }, (q4.path || []).map(p => h('li', null, p.text, h('small', null, p.source ? p.source[0].toUpperCase() + p.source.slice(1) : '')))),
      q4.replication?.text ? h('p', null, h('b', null, q4.replication.text)) : null,
      q4.rival_note ? h('p', null, q4.rival_note) : (q5.attribution && q5.attribution.share < 0.5 && q5.attribution.rivals?.length ? h('p', null, `Also consistent with: ${q5.attribution.rivals.map(r => r.label).join(', ')} (active the same week).`) : null),
      (q4.route_ideas || []).map(ri => h('p', { class: 'idea' }, `Route idea, not measured: ${ri.text} (${ri.source}).`))),
    sec('Q5', 'Could it be luck?',
      h('div', { class: 'luck' }, h('p', null, h('b', null, 'Lookalikes. '), L.lookalikes(q5.p_1_in) || 'Not tested yet.'), pstrip,
        placebo.fam.length ? h('p', { class: 'xs' }, placebo.fam.map(f => `${L.fmtInt(f.exceed)} of ${L.fmtInt(f.n)} ${L.FAM_WORD[f.k]}`).join(', '), ' looked this strong.') : null),
      h('div', { class: 'luck' }, h('p', null, h('b', null, 'Fluke rate. '), L.flukeRate(q5.f_1_in, q5.f_warming) || 'Not measured yet.'), meter),
      q5.day && q5.day.tested ? h('p', null, `We tested ${L.fmtInt(q5.day.tested)} paths that day. Expect about ${L.expected(q5.day.expected_flukes)} of that day's ${L.plural(q5.day.measured, 'Measured stop')} to be wrong.`) : null,
      (q5.flat_siblings || []).length ? [h('p', null, h('b', null, 'The ones that stayed flat')), h('ul', { class: 'sibs' }, q5.flat_siblings.map(s => h('li', null, s.label, spark(flatById.get(s.label)?.spark, 64, 20), h('b', null, L.num(s.rho) + '×'))))] : null),
    h('details', { class: 'math' }, h('summary', null, 'Show the math'),
      rows([['Statistic', `${m.stat_kind || '–'}${m.s != null ? `, S = ${m.s}` : ''}`], ['Scale σ', m.sigma], ['Window', m.window_days != null ? L.plural(m.window_days, 'day') : null],
        ['Multiple', `shrunk ${L.mult(x.rho, u)} [${L.mult(x.rho_lo, u)}–${L.mult(x.rho_hi, u)}], raw ${L.mult(m.raw_rho, u)}`], ['Look', d.look ? `${d.look.no} of ${d.look.of}${d.look.final ? ', final' : ''}${m.look_day ? `, ${L.fmtDay(m.look_day)}` : ''}` : null],
        ['Placebo p', `${q5.p ?? '–'} (floor ${q5.p_floor ?? '–'})`], ['q (weighted BH)', q5.q], ['BH', q5.bh ? `rank ${q5.bh.rank} of ${q5.bh.m}, weight ${q5.bh.weight}` : null], ['Fluke bin', q5.f_bin], ['ρ̂₁', m.rho1 ?? 'not stored'],
        ['Method', m.method || c.method], ['Ledger', m.ledger ? h('span', null, `#${m.ledger.seq} `, h('span', { class: 'hash' }, m.ledger.chain_hash)) : null], ['Failed conditions', (m.fails || []).join(', ') || 'none']]),
      zRows.length ? h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, ['Channel', 'ž', 'S', 'κ', 'weight', 'sources'].map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, zRows))) : null,
      h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, ['Placebo family', 'tested', 'as strong'].map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, placebo.fam.map(f => h('tr', null, h('td', null, L.FAM_WORD[f.k]), h('td', { class: 'n' }, L.fmtInt(f.n)), h('td', { class: 'n' }, L.fmtInt(f.exceed))))))),
      (m.licences || []).length ? h('p', { class: 'xs', style: 'color:var(--on-panel-2)' }, 'Sources: ', m.licences.map(l => `${l.attribution} (${l.licence})`).join('; ')) : null,
      q1rows.length ? h('details', null, h('summary', null, 'Q1 chart as a table'), h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, ['Day', '× normal', 'normal low', 'normal high', 'last year'].map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, q1rows)))) : null,
      h('div', { class: 'btns' }, h('a', { class: 'btn sec sm', href: csv, download: `stop-${d.hop_id}.csv` }, 'Download CSV'), h('a', { class: 'btn sec sm', href: issue, target: '_blank', rel: 'noopener' }, 'Something wrong?'))),
    h('div', { class: 'btns' }, h('button', { class: 'btn', onclick: () => share(L.shareStop(d), 'stop') }, icon('share'), 'Share this stop'), h('a', { class: 'btn sec', href: `/ripples/lands/${d.node.domain}/` }, 'Start from here')),
    h('p', { class: 'ctx' }, h('b', null, 'Knock⌃On'), sep(), `${c.event.label} → ${d.node.label}`, sep(), 'bensunter.com/ripples', sep(), L.FOOT));
  setTimeout(() => { live.textContent = d.sr_sentence || ''; }, 60);
  if (fig) countUp(fig, L.mult(x.rho, u), quiet);
}

// ---------- LISTS: map, lines, archive, lands, week ----------
function lineRow(a, extra) {
  const st = { measured: a.measured || 0, likely: Math.max(0, (a.stops || 0) - (a.measured || 0)), watching: a.watching || 0 };
  return h('a', { class: 'li' + (a.reconstructed ? ' recon' : ''), href: L.lineUrl(a.slug) },
    h('span', { class: 'ic' + (a.measured ? ' m' : ''), 'aria-hidden': 'true' }, em(a.emoji || '▫️')),
    h('span', null, h('span', { class: 'nm' }, a.label), h('span', { class: 'sub' }, a.reconstructed ? h('span', { class: 'tagr' }, 'reconstructed') : null, joinSep([L.fmtDayY(a.onset), L.STATUS[a.status] || a.status, (a.domains || []).length ? h('span', null, a.domains.map(d => em(L.domIcon(d)))) : null])), extra || null),
    h('span', { class: 'rt' }, strip(st, 6)));
}
async function mapPage(title) {
  const main = $('#main');
  const a = (await D.archive()) || [];
  const cut = L.addDays(today(), -30);
  const rows = a.filter(x => !x.reconstructed && (x.onset >= cut || x.status === 'running')).sort((x, y) => String(y.onset).localeCompare(String(x.onset)));
  const minis = new Map();
  const list = h('div', { class: 'list' }, rows.map(x => { const m = S('svg', { class: 'mini', viewBox: '0 0 300 26', preserveAspectRatio: 'none', 'aria-hidden': 'true' }); minis.set(x.event_id, m); return lineRow(x, m); }));
  const rng = h('input', { type: 'range', min: 0, max: 30, value: 30, 'aria-label': 'Rewind the month: day' });
  const dl = h('span', null, L.fmtDate(today()));
  put(main, h('h1', { class: 'h1' }, title || 'The map'), h('p', { class: 'lede' }, 'Every line from the last 30 days, newest first. Drag the dial to rewind the month: each stop lights on the day it moved.'),
    legend('card'), h('div', { class: 'scrub' }, h('p', null, h('span', null, 'Rewind the month'), dl), rng),
    rows.length ? list : h('p', { class: 'empty', style: 'margin-top:12px' }, 'No lines in the last 30 days yet.'),
    h('p', { class: 'sm', style: 'margin-top:16px' }, h('a', { class: 'lnk', href: '/ripples/archive/' }, 'Older and reconstructed lines are in the archive')));
  const dots = [];
  const start = L.dayMs(L.addDays(today(), -30));
  await Promise.all(rows.slice(0, 30).map(async x => {
    const c = await D.cascade(x.event_id); const m = minis.get(x.event_id); if (!c || !m) return;
    S('line', { x1: 0, x2: 300, y1: 13, y2: 13, stroke: 'var(--hair)', 'stroke-width': 2 }, m);
    const xo = d => Math.max(0, Math.min(300, ((L.dayMs(d) - start) / (30 * 864e5)) * 300));
    S('rect', { x: xo(c.event.onset) - 4, y: 9, width: 8, height: 8, rx: 2, fill: 'var(--marigold)', stroke: 'var(--petrol)', 'stroke-width': 1.5 }, m);
    for (const n of c.nodes || []) {
      if (!n.onset || !L.isStation(n)) continue;
      const el = S('rect', { x: xo(n.onset) - 4, y: 9, width: 8, height: 8, rx: 2, fill: n.tier === 'measured' ? 'var(--ink)' : 'var(--card)', stroke: n.tier === 'retracted' ? 'var(--flat)' : 'var(--ink)', 'stroke-width': 1.5 }, m);
      dots.push([el, n.onset]);
    }
  }));
  rng.addEventListener('input', () => { const d = L.addDays(today(), -30 + +rng.value); dl.textContent = L.fmtDate(d); for (const [el, o] of dots) el.style.opacity = o <= d ? 1 : 0.12; });
}
async function archivePage() {
  const main = $('#main');
  const a = (await D.archive()) || [];
  const recon = a.filter(x => x.reconstructed).sort((x, y) => String(x.onset).localeCompare(String(y.onset)));
  const closed = a.filter(x => !x.reconstructed && x.status !== 'running').sort((x, y) => String(x.onset).localeCompare(String(y.onset)));
  put(main, h('h1', { class: 'h1' }, 'Archive'), h('p', { class: 'lede' }, 'Closed lines, oldest to newest, including the ones that went nowhere. Reconstructed lines were run afterwards on past shocks with the same frozen method; they are labelled every time they appear.'),
    h('h2', { class: 'h2 sec' }, 'Reconstructed archive'), recon.length ? h('div', { class: 'list' }, recon.map(x => lineRow(x))) : h('p', { class: 'empty' }, 'The reconstructed archive is not published yet.'),
    h('h2', { class: 'h2 sec' }, 'Closed lines'), closed.length ? h('div', { class: 'list' }, closed.map(x => lineRow(x))) : h('p', { class: 'empty' }, 'No live line has closed yet. Lines close when every window has shut.'),
    h('p', { class: 'sm', style: 'margin-top:16px' }, h('a', { class: 'lnk', href: '/ripples/map/' }, 'Lines from the last 30 days')));
}
async function landsPage(r) {
  const main = $('#main');
  const dom = r.domain;
  const chips = h('div', { class: 'chips', style: 'margin-top:12px' }, L.DOMAINS.map(k => h('a', { class: 'chip', href: `/ripples/lands/${k}/`, 'aria-current': k === dom ? 'page' : null }, em(L.DOM[k].i), L.DOM[k].w)));
  if (!dom) { put(main, h('h1', { class: 'h1' }, 'Where it lands'), h('p', { class: 'lede' }, 'Read the map backwards: pick a part of life and see which shocks moved it.'), chips); return; }
  const l = INLINE && INLINE.domain === dom ? INLINE : await D.lands(dom);
  const hops = (l?.hops || []).slice().sort((a, b) => ({ measured: 0, likely: 1 }[a.tier] ?? 2) - ({ measured: 0, likely: 1 }[b.tier] ?? 2) || String(b.onset).localeCompare(String(a.onset)));
  document.title = `What's been moving ${L.domWord(dom)}? | Knock⌃On Ripple Map`;
  put(main, h('h1', { class: 'h1' }, em(L.domIcon(dom)), ` What's been moving ${L.domWord(dom)}?`), h('p', { class: 'lede' }, `${L.DOM[dom].d[0].toUpperCase() + L.DOM[dom].d.slice(1)}. Stops that moved after an upstream shock${l?.from ? `, ${L.fmtDay(l.from)} to ${L.fmtDay(l.to)}` : ' in the last 30 days'}.`), chips,
    hops.length ? h('div', { class: 'list' }, hops.map(x => h('a', { class: 'li', href: L.stopUrl(x.slug, x.hop_id) },
      h('span', { class: 'ic' + (x.tier === 'measured' ? ' m' : ''), 'aria-hidden': 'true' }, em(x.emoji || '▫️')),
      h('span', null, h('span', { class: 'nm', style: x.retracted ? 'text-decoration:line-through' : null }, x.label), h('span', { class: 'sub' }, x.reconstructed ? h('span', { class: 'tagr' }, 'reconstructed') : null, joinSep([`after ${x.event_label}`, x.lag_days != null ? L.lagShort(x.lag_days) : null, L.fmtDay(x.onset), x.attention_ripple ? 'attention ripple' : null, x.retracted ? `retracted ${L.fmtDay(x.retracted.date)}` : null]))),
      h('span', { class: 'rt' }, x.rho != null ? flaps(L.mult(x.rho, x.unit), 'mute') : null, stamp(x.retracted ? 'retracted' : x.tier)))))
      : h('p', { class: 'empty', style: 'margin-top:12px' }, `No Measured or Likely stop in ${L.domWord(dom)} in the last 30 days. That is a result too.`),
    legend('card'));
}
async function weekPage(r) {
  const main = $('#main');
  const w = r.week || L.isoWeek(L.addDays(today(), -7));
  const wk = INLINE && INLINE.week === w ? INLINE : await D.week(w);
  const rg = L.weekRange(w) || {};
  const [y, n] = w.split('-').map(Number);
  const prev = L.isoWeek(L.addDays(rg.from || today(), -7)), next = L.isoWeek(L.addDays(rg.from || today(), 7));
  const nav = h('p', { class: 'btns' }, h('a', { class: 'btn sec sm', href: `/ripples/week/${prev}/` }, '‹ Week ' + prev.slice(5)), next <= L.isoWeek(today()) ? h('a', { class: 'btn sec sm', href: `/ripples/week/${next}/` }, 'Week ' + next.slice(5) + ' ›') : null);
  const head = [h('h1', { class: 'h1' }, `Week ${n}, ${y}`), h('p', { class: 'lede' }, `${L.fmtDay(rg.from)} to ${L.fmtDay(rg.to)}. Where the week's lines landed, including the ones that went nowhere.`)];
  if (!wk || !wk.ripple_of_week) { put(main, head, h('p', { class: 'empty', style: 'margin-top:12px' }, wk?.note || 'No edition for this week yet.'), nav); return; }
  const c = wk.ripple_of_week;
  const entries = L.lineOrder(c).filter(e => e.depth < 3);
  const sc = staircase(c, entries, { all: true, cls: 'wk' });
  put(main, head,
    h('section', { class: 'ticket hero grain', style: 'margin-top:14px' }, h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, c.event.reconstructed ? 'Ripple of the week, reconstructed' : 'Ripple of the week'), h('span', { class: 'ver' }, 'v' + c.version)),
      h('div', { class: 'tk-body' }, h('div', { class: 'tk-row' }, h('span', { class: 'tk-emo', 'aria-hidden': 'true' }, em(c.event.emoji)), h('h2', { class: 'tk-title' }, c.event.label)), h('p', { class: 'tk-sub' }, joinSep(L.lineMeta(c)))),
      h('div', { class: 'tk-foot' }, sc.fig, h('p', { class: 'xs', style: 'margin:10px 0' }, `The rule, published in advance: ${wk.rule}.${wk.qualified === false ? ' Nothing qualified this week, so this is the best single-stop line.' : ''}`), h('a', { class: 'btn', href: L.lineUrl(c.event.slug, c.version) }, 'Trace the line'))),
    h('ol', { class: 'sr' }, entries.map(e => h('li', null, `${e.n.label}: ${L.tierWord(e.n.tier)}${e.n.rho != null ? ', ' + L.rel(e.n.rho, e.n.unit) : ''}`))),
    h('h2', { class: 'h2 sec' }, "The week's lines"),
    h('div', { class: 'list' }, (wk.lines || []).map(x => lineRow({ ...x, measured: x.stops?.measured || 0, stops: (x.stops?.measured || 0) + (x.stops?.likely || 0), watching: x.stops?.watching || 0 }))), nav);
}

// ---------- METHODS: the Receipts ----------
async function methodsPage() {
  const box = $('#receipts'); if (!box) return;
  const [cal, hl] = await Promise.all([D.calib(), D.health()]);
  if (!cal) { put(box, h('p', { class: 'empty' }, 'The calibration payload is not published yet. The rules below apply either way.')); return; }
  const o = cal.decoy_fdr?.overall || {}, rc = cal.receipts || {}, neg = cal.controls?.negative || {};
  const pct = v => (v == null ? '–' : (v * 100).toFixed(1).replace(/\.0$/, '') + '%');
  const brk = (cal.breaker || []).length || (hl?.breaker || []).length;
  const ks = cal.null_ks || {};
  const ksSvg = S('svg', { viewBox: '0 0 200 60', preserveAspectRatio: 'none', role: 'img', 'aria-label': `Histogram of ${ks.n || 0} held-out null p-values in 20 bins; a flat shape means the test is calibrated.` });
  const hist = ks.hist || [], hm = Math.max(1, ...hist);
  hist.forEach((v, i) => S('rect', { x: i * 10 + 1, y: 58 - (v / hm) * 54, width: 8, height: (v / hm) * 54, fill: 'var(--ink)', opacity: 0.8 }, ksSvg));
  const tbl = (head, body) => h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, head.map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, body)));
  put(box,
    brk ? h('p', { class: 'brk', role: 'alert' }, 'Circuit breaker tripped: ', (cal.breaker || hl.breaker).map(b => b.cell || b).join(', '), '. Measured stops in those cells are shown as Likely until the cell recovers.') : null,
    h('p', { class: 'sm muted' }, `As of ${L.fmtDate(cal.as_of)}, method ${cal.method}. Every number here is read from the calibration file the engine publishes.`),
    h('div', { class: 'rc' },
      h('div', null, h('b', null, pct(o.rate)), h('span', null, `Decoy false-pass rate (${L.fmtInt(o.decoy_measured)} of ${L.fmtInt(o.decoy_tested)} decoy tests; Wilson interval ${pct(o.lo)}–${pct(o.hi)})`)),
      h('div', null, h('b', null, `${L.fmtInt(rc.hits)} of ${L.fmtInt(rc.resolved)}`), h('span', null, `Pre-registered calls resolved as a hit (${L.fmtInt(rc.registered)} registered; the base rate predicted ${rc.base_rate_hits ?? '–'})`)),
      h('div', null, h('b', null, ks.p != null ? ks.p : '–'), h('span', null, `Null check: KS p on ${L.fmtInt(ks.n)} held-out pairs (KS ${ks.stat ?? '–'}); we want p ≥ 0.05`)),
      h('div', null, h('b', null, pct(neg.pass_rate)), h('span', null, `Negative controls passing (decoy rate ${pct(neg.decoy_rate)}, n ${L.fmtInt(neg.n)})`))),
    h('div', { class: 'ks' }, ksSvg),
    rc.show_reliability ? null : h('p', { class: 'sm muted' }, 'Reliability and Brier scores appear once enough pre-registered calls resolve; until then only the raw counts are shown.'),
    h('h3', null, 'Positive controls'), tbl(['Control', 'Result', 'Last run'], (cal.controls?.positive || []).map(p => h('tr', null, h('td', null, p.name), h('td', null, p.passed ? 'passed' : 'not passed'), h('td', null, L.fmtDay(p.last_run))))),
    h('h3', null, 'Decoy false-pass rate by cell'), tbl(['Cell', 'Decoy tests', 'Decoy Measured', 'Real tests', 'Real Measured'], (cal.decoy_fdr?.cells || []).map(x => h('tr', null, h('td', null, x.cell), h('td', { class: 'n' }, x.decoy_tested), h('td', { class: 'n' }, x.decoy_measured), h('td', { class: 'n' }, x.real_tested), h('td', { class: 'n' }, x.real_measured)))),
    h('h3', null, 'Power'), tbl(['Channel', 'Size', 'Lag', 'Found', 'Tested'], (cal.power || []).map(p => h('tr', null, h('td', null, p.channel), h('td', { class: 'n' }, p.delta), h('td', { class: 'n' }, p.lag), h('td', { class: 'n' }, pct(p.recall)), h('td', { class: 'n' }, p.tested ?? '–')))),
    h('h3', null, 'Replication by family'), tbl(['Family', 'Edge class', 'Seen', 'Of'], (cal.refire || []).map(p => h('tr', null, h('td', null, p.family), h('td', null, p.edge_class), h('td', { class: 'n' }, p.hits), h('td', { class: 'n' }, p.n)))),
    h('h3', null, 'Day lines'), tbl(['Day', 'Tested', 'Moved', 'Measured', 'Expected flukes'], (cal.day_lines || []).map(x => h('tr', null, h('td', null, L.fmtDay(x.day)), h('td', { class: 'n' }, x.line?.tested), h('td', { class: 'n' }, x.line?.moved), h('td', { class: 'n' }, x.line?.measured), h('td', { class: 'n' }, x.line?.expected_flukes)))),
    h('h3', null, 'Retractions'), (cal.retractions || []).length ? tbl(['Stop', 'Date', 'Reason'], cal.retractions.map(x => h('tr', null, h('td', null, '#' + x.hop_id), h('td', null, L.fmtDay(x.date)), h('td', null, x.reason)))) : h('p', null, 'None yet.'),
    h('h3', null, 'Ledger'), h('p', { class: 'sm' }, `Head #${L.fmtInt(cal.ledger?.seq)}: `, h('span', { class: 'hash', style: 'color:var(--ink-3)' }, cal.ledger?.head || '–')),
    cal.archive ? h('p', { class: 'sm muted' }, `Reconstructed archive: ${cal.archive.label || ''} (as of ${L.fmtDay(cal.archive.as_of)}).`) : null,
    hl ? h('p', { class: 'sm muted' }, `Pipeline: ${hl.stage || '–'} for ${L.fmtDay(hl.latest_day)}${hl.stale ? ', running late' : ''}. Disabled sources: ${(hl.sources_disabled || []).join(', ') || 'none'}.`) : null);
}

// ---------- boot ----------
async function boot() {
  chrome();
  const r = L.parseRoute(location.pathname, document.body.dataset);
  try {
    if (r.route === 'home') await home();
    else if (r.route === 'line' || r.route === 'stop') await linePage(r);
    else if (r.route === 'lines') await mapPage('Every line');
    else if (r.route === 'map') await mapPage();
    else if (r.route === 'archive') await archivePage();
    else if (r.route === 'lands') await landsPage(r);
    else if (r.route === 'week') await weekPage(r);
    else if (r.route === 'methods') await methodsPage();
  } catch (e) {
    console.error(e);
    put($('#main'), h('p', { class: 'empty' }, 'Something went wrong loading this page. Please reload.'));
  }
  const a = $('#a2hs'); if (a && visits() >= 2 && bip) a.hidden = false;
}
boot();
