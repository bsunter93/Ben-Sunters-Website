// Ripple Map v6 evidence sheet (WS-D): the five questions, loaded on the first sheet open or on a /stop/ route so the line
// page's shell stays inside the 120 KB budget (EXPERIENCE §11: the evidence is lazy, like its hop JSON).
import * as C from './config.js';
import * as L from './lib.js';
import { $, add, h, S, em, sep, put, icon, RM, D, share, flaps, countUp, stamp, spark, axText } from './ui.js';

// ---------- evidence sheet ----------
let sheetState = null;
const getSheet = () => sheetState;
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
// the spike wordmark (the same SVG as the top bar) for the context strip that survives a cropped screenshot
function wordmark() {
  const s = S('svg', { viewBox: '0 0 15 11', 'aria-hidden': 'true' }); s.innerHTML = '<path d="M0 9.5H5L7.4 1.5L9.8 9.5H15"/>';
  return h('b', { class: 'wm2' }, 'Knock', s, 'On', h('span', { class: 'sr' }, 'Knock-On'));
}
function q1Chart(q, parentOnset) {
  const svg = S('svg', { class: 'q1', viewBox: '0 0 340 150', role: 'img', preserveAspectRatio: 'none' });
  const s = (q.series || []).map(Number), n = s.length; if (n < 3) return null;
  // Show the after, not 94 days of noise: the x-domain is onset − 42 … onset + 14 days (ART §3.2). Data ends at as_of; the
  // empty right margin is the part of the window still open, not invented future.
  const oi0 = q.onset_index ?? n - 1, i0 = Math.max(0, oi0 - 42), i1 = oi0 + 14, span = Math.max(8, i1 - i0), inD = i => i >= i0 && i <= i1, last = Math.min(n - 1, i1);
  const all = s.slice(i0, i1 + 1).concat((q.band_lo || []).slice(i0, i1 + 1), (q.band_hi || []).slice(i0, i1 + 1), (q.last_year || []).slice(i0, i1 + 1)).filter(v => v > 0 && isFinite(v));
  const lo = Math.min(0.7, ...all), hi = Math.max(1.4, ...all);
  const pl = 30, pr = 30, pt = 8, pb = 20, W = 340, H = 150;
  const x = i => pl + ((i - i0) / span) * (W - pl - pr), y = v => pt + (1 - (L.log2(v) - L.log2(lo)) / (L.log2(hi) - L.log2(lo))) * (H - pt - pb);
  const P = (arr, a = 0) => arr.map((v, i) => (v > 0 && inD(i + a) ? `${i ? 'L' : 'M'}${x(i + a).toFixed(1)} ${y(v).toFixed(1)}` : '')).join('').replace(/^L/, 'M');
  if (q.window) S('rect', { x: x(Math.max(i0, q.window[0])), y: pt, width: Math.max(2, x(Math.min(i0 + span, q.window[1])) - x(Math.max(i0, q.window[0]))), height: H - pt - pb, fill: 'var(--spike-wash)' }, svg);
  for (const g of [0.5, 1, 2, 4, 8].filter(v => v >= lo && v <= hi)) { S('line', { x1: pl, x2: W - pr, y1: y(g), y2: y(g), stroke: 'var(--grid-panel)' }, svg); const t = S('text', { x: pl - 4, y: y(g) + 3.5, 'text-anchor': 'end', 'font-size': 10, fill: 'var(--on-panel-3)', 'font-family': 'var(--display)', 'font-weight': 800 }, svg); axText(t, g + '×'); }
  if (q.band_lo && q.band_hi) S('path', { d: P(q.band_hi) + 'L' + q.band_lo.map((v, i) => [x(i), y(v), i]).filter(p => inD(p[2]) && p[1] === p[1]).reverse().map(p => p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join('L') + 'Z', fill: 'rgba(234,243,240,.20)' }, svg);
  if (q.last_year) S('path', { d: P(q.last_year), fill: 'none', stroke: 'var(--on-panel-3)', 'stroke-width': 1.25, 'stroke-dasharray': '2 3', opacity: 0.8 }, svg);
  const oi = q.onset_index ?? n;
  S('path', { d: P(s.slice(0, oi + 1)), fill: 'none', stroke: 'var(--on-panel-2)', 'stroke-width': 1.5, 'stroke-linejoin': 'round' }, svg);
  if (oi < n) S('path', { d: P(s.slice(oi), oi), fill: 'none', stroke: 'var(--spike)', 'stroke-width': 2.75, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', class: 'lane-hot' }, svg);
  if (q.onset_index != null) { S('line', { x1: x(oi), x2: x(oi), y1: pt, y2: H - pb, stroke: 'var(--event)', 'stroke-width': 1.25 }, svg); }
  // the direct label on the after-segment's end, so the chart and the flap agree at a glance
  if (oi < n && q.rho != null) { const lv = s[last]; const t = S('text', { x: x(last) + 5, y: y(lv) + 4, 'font-size': 11, fill: 'var(--marigold-ink)', 'font-family': 'var(--display)', 'font-weight': 800, style: 'paint-order:stroke;stroke:var(--panel);stroke-width:3px' }, svg); axText(t, L.num(q.rho) + '×'); }
  const d0 = S('text', { x: pl, y: H - 5, 'font-size': 10.5, fill: 'var(--on-panel-3)', 'font-family': 'var(--sans)' }, svg); d0.textContent = L.fmtDay(L.addDays(q.from, i0));
  const d1 = S('text', { x: W - pr, y: H - 5, 'text-anchor': 'end', 'font-size': 10.5, fill: 'var(--on-panel-3)', 'font-family': 'var(--sans)' }, svg); d1.textContent = L.fmtDay(L.addDays(q.from, i0 + span));
  if (q.onset_index != null) { const t = S('text', { x: x(oi) - 4, y: pt + 10, 'text-anchor': 'end', 'font-size': 10.5, fill: 'var(--on-panel-2)', 'font-family': 'var(--sans)' }, svg); t.textContent = parentOnset ? `shock ${L.fmtDay(parentOnset)}` : 'shock'; }
  svg.setAttribute('aria-label', `The series against its normal band, six weeks before the shock to two weeks after, with the same weeks last year; the part after the shock is highlighted. Values are in the table under Show the math.`);
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
  sheetState = { el, scrim, opener, pushed: push, lineHref, keyh, hop: hopId };
  if (push) history.pushState({ sheet: hopId }, '', L.stopUrl(c.event.slug, hopId));
  document.body.style.overflow = 'hidden';
  const info = node || (typeof hopOrDoc === 'object' ? { tier: hopOrDoc.tier, domain: hopOrDoc.node?.domain, label: hopOrDoc.node?.label } : null);
  put(el, h('div', { class: 'grab' }, h('b', null, info ? `${L.tierWord(info.tier)} stop, ${L.domWord(info.domain)}` : 'Evidence'), h('button', { class: 'xb', 'aria-label': 'Close the evidence', onclick: () => closeSheet() }, icon('x'))),
    h('p', { class: 'ev-h', id: 'ev-t' }, info ? info.label : 'Loading the evidence…'));
  // a deep link lands with the sheet already open (no slide); a tap on the line slides it up
  if (!push && !opener) { scrim.classList.add('on'); el.classList.add('on'); el.focus(); } else requestAnimationFrame(() => { scrim.classList.add('on'); el.classList.add('on'); el.focus(); });
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
  const chan = ch => { const nod = ch.zhat == null || (ch.kappa != null && ch.kappa < 0.5); return h('div', { class: `ch ${ch.agree ? 'agree' : nod ? 'nodata' : ''}` }, ch.label || ch.code, h('small', null, ch.agree ? `agrees${ch.zhat != null ? `, z ${Number(ch.zhat).toFixed(1)}` : ''}` : nod ? 'still warming up' : `below the bar${ch.zhat != null ? ` (z ${Number(ch.zhat).toFixed(1)})` : ''}`)); };
  const q1 = d.q1_normal ? q1Chart({ ...d.q1_normal, rho: x.rho }, q2.parent_onset) : null;
  const untested = x.rho == null && !d.retracted;
  const node = (c.nodes || []).find(n => n.hop_id === d.hop_id);
  const csv = m.csv || `${C.STORAGE}hop/${d.hop_id}.csv`;
  const issue = `https://github.com/bsunter93/Ben-Sunters-Website/issues/new?title=${encodeURIComponent(`Ripple Map: stop ${d.hop_id} (${d.node.label})`)}&body=${encodeURIComponent(`What looks wrong on https://bensunter.com${L.stopUrl(d.event.slug, d.hop_id)} ?\n\n`)}`;
  const rows = (arr) => h('div', { class: 'tw' }, h('table', { class: 't' }, h('tbody', null, arr.filter(Boolean).map(([k, v]) => h('tr', null, h('th', { scope: 'row' }, k), h('td', null, v ?? '–'))))));
  const zRows = Object.entries(m.z_by_source || {}).map(([k, v]) => h('tr', null, h('th', { scope: 'row' }, k), h('td', { class: 'n' }, v.zhat != null ? Number(v.zhat).toFixed(2) : '–'), h('td', { class: 'n' }, v.S != null ? Number(v.S).toFixed(2) : '–'), h('td', { class: 'n' }, v.kappa ?? '–'), h('td', { class: 'n' }, m.weights?.[k] ?? '–'), h('td', null, (v.sources || []).join(', '))));
  const q1rows = d.q1_normal ? d.q1_normal.series.map((v, i) => h('tr', null, h('td', null, L.fmtDay(L.addDays(d.q1_normal.from, i))), h('td', { class: 'n' }, v), h('td', { class: 'n' }, d.q1_normal.band_lo?.[i] ?? '–'), h('td', { class: 'n' }, d.q1_normal.band_hi?.[i] ?? '–'), h('td', { class: 'n' }, d.q1_normal.last_year?.[i] ?? '–'))) : [];
  put(el, el.firstChild,
    h('div', { class: 'ev-h' },
      // the tier's plain-language definition lives on the stamp's tooltip/long-press and in the ? sheet (EXPERIENCE §10), not
      // as a third statement of the same fact above the fold
      h('div', { class: 'ev-stamp' }, stamp(d.tier), d.provisional ? h('span', { class: 'prov' }, 'provisional') : null, d.tier_reason && d.tier !== 'retracted' ? h('span', { class: 'xs', style: 'color:var(--on-panel-2)' }, d.tier_reason) : null),
      h('p', { class: 'sr' }, `${T.w}: ${T.def}`),
      h('h2', { class: 'ev-name', id: 'ev-t' }, em(L.domIcon(d.node.domain)), ' ', d.node.label),
      d.retracted ? h('p', { class: 'retban', role: 'note' }, `Retracted ${L.fmtDate(d.retracted.date)}: ${d.retracted.reason}. Everything below stays visible.`) : null,
      fig ? h('div', { class: 'ev-fig' }, L.dirGlyph(x.rho, u) ? h('span', { class: 'dir', 'aria-hidden': 'true' }, L.dirGlyph(x.rho, u)) : null, fig, h('p', null, u === 'points' ? 'points against its normal' : 'its normal', L.pctGloss(x.rho, u) ? h('span', { class: 'gloss' }, ` (${L.pctGloss(x.rho, u)})`) : null, u === 'points' ? '' : ',', h('br'), h('b', null, x.lag_days === 0 ? 'the same day as' : `+${L.plural(x.lag_days, 'day')} after`), ' ', x.parent_label || d.parent?.label)) : null,
      h('p', { class: 'ev-say' }, d.retracted ? 'Before the retraction: ' + L.evidenceHeadline(d) : L.evidenceHeadline(d)),
      live),
    d.q1_normal ? sec('Q1', 'Is this normal for it?', q1, h('p', { class: 'q1k' }, h('span', null, h('i', { style: 'background:var(--on-panel)' }), 'this series'), h('span', null, h('i', { style: 'background:var(--spike)' }), 'after the shock'), h('span', null, h('i', { style: 'background:rgba(234,243,240,.3);height:8px' }), 'its normal range'), h('span', null, h('i', { style: 'background:var(--on-panel-3);height:1.5px' }), 'same weeks last year')),
      h('p', null, `Its normal is measured over ${d.q1_normal.baseline ? L.daysBetween(d.q1_normal.baseline.from, d.q1_normal.baseline.to) + 1 : 91} days ending ${d.q1_normal.baseline ? L.fmtDay(d.q1_normal.baseline.to) : 'three weeks before the shock'}, matched by weekday${d.q1_normal.baseline?.year_ago_term ? ', with a year-ago term' : ''}. The faint line is the same weeks last year: the placebo you can see.`)) : null,
    untested ? h('section', { class: 'qs' }, h('h3', null, 'What we are waiting for'), h('p', null, d.sentence || ''),
      d.look && d.look.window_close ? h('p', null, d.look.window_closed ? `Its window closed ${L.fmtDate(d.look.window_close)}.` : `Its window runs from ${L.fmtDate(q2.parent_onset)} to ${L.fmtDate(d.look.window_close)}. `, !d.look.window_closed && (node?.due || d.look.next) ? `${L.lookWord(node?.due || d.look.next, d.look.window_close)} ${L.fmtDate(node?.due || d.look.next)}.` : '') : null,
      h('p', null, 'Nothing has moved yet, so there is no size, timing or luck check to show. The tests below run the moment a look finds a move.')) : null,
    untested ? null : sec('Q2', 'Did it move after, not before?',
      h('div', { class: 'ruler' }, h('span', { class: 'd' }, L.fmtDate(q2.parent_onset)), h('span', { class: 'ln', 'aria-hidden': 'true' }), h('span', { class: 'd' }, L.fmtDate(q2.node_onset)), h('span', { class: q2.order_ok ? 'ok' : '' }, q2.lag_days != null ? (q2.lag_days === 0 ? 'same day' : `+${L.plural(q2.lag_days, 'day')}`) : '', q2.order_ok ? ' ✓' : '')),
      h('p', null, q2.pre_trend?.flag ? 'Already moving before the shock: capped at Likely.' : `Not already moving: its pre-trend score was ${q2.pre_trend?.s ?? '–'} (the flag is at 2).`)),
    untested ? null : sec('Q3', 'Who else saw it?', h('div', { class: 'chs' }, (q3.channels || []).map(chan)),
      h('p', null, h('b', null, `${q3.agree ?? 0} of ${q3.of ?? 0} independent sources agree.`), q3.loso_ok === false ? ' It drops below the bar without its strongest source.' : '', q3.common_shock ? ' The onset day was a common-shock day.' : ''),
      (q3.excluded || []).length ? h('p', null, 'Not counted: ', q3.excluded.map(e => `${e.label} (${e.why})`).join('; '), '.') : null),
    sec('Q4', 'Why these two?', h('ul', { class: 'path' }, (q4.path || []).map(p => h('li', null, p.text, h('small', null, p.source ? p.source[0].toUpperCase() + p.source.slice(1) : '')))),
      q4.replication?.text ? h('p', null, h('b', null, q4.replication.text)) : null,
      q4.rival_note ? h('p', null, q4.rival_note) : (q5.attribution && q5.attribution.share < 0.5 && q5.attribution.rivals?.length ? h('p', null, `Also consistent with: ${q5.attribution.rivals.map(r => r.label).join(', ')} (active the same week).`) : null),
      (q4.route_ideas || []).map(ri => h('p', { class: 'idea' }, `Route idea, not measured: ${ri.text} (${ri.source}).`))),
    untested ? null : sec('Q5', 'Could it be luck?',
      h('div', { class: 'luck' }, h('p', null, h('b', null, 'Lookalikes. '), L.lookalikes(q5.p_1_in) || 'Not tested yet.'), pstrip,
        placebo.fam.length ? h('p', { class: 'xs' }, placebo.fam.map(f => `${L.fmtInt(f.exceed)} of ${L.fmtInt(f.n)} ${L.FAM_WORD[f.k]}`).join(', '), ' looked this strong.') : null),
      h('div', { class: 'luck' }, h('p', null, h('b', null, 'Fluke rate. '), L.flukeRate(q5.f_1_in, q5.f_warming) || 'Not measured yet.'), meter),
      q5.day && q5.day.tested ? h('p', null, `We tested ${L.fmtInt(q5.day.tested)} paths that day. Expect about ${L.expected(q5.day.expected_flukes)} of that day's ${L.plural(q5.day.measured, 'Measured stop')} to be wrong.`) : null,
      (q5.flat_siblings || []).length ? [h('p', null, h('b', null, 'The ones that stayed flat')), h('ul', { class: 'sibs' }, q5.flat_siblings.map(s => h('li', null, s.label, spark(flatById.get(s.label)?.spark, 64, 20), h('b', null, L.num(s.rho) + '×'))))] : null),
    h('details', { class: 'math' }, h('summary', null, 'Show the math'),
      rows([m.stat_kind ? ['Statistic', `${m.stat_kind}${m.s != null ? `, S = ${m.s}` : ''}`] : null, m.sigma != null ? ['Scale σ', m.sigma] : null, m.window_days != null ? ['Window', L.plural(m.window_days, 'day')] : null,
        x.rho != null ? ['Multiple', `shrunk ${L.mult(x.rho, u)} [${L.mult(x.rho_lo, u)}–${L.mult(x.rho_hi, u)}]${m.raw_rho != null ? `, raw ${L.mult(m.raw_rho, u)}` : ''}`] : null,
        d.look && d.look.no != null ? ['Look', `${d.look.no} of ${d.look.of}${d.look.final ? ', final' : ''}${m.look_day ? `, ${L.fmtDay(m.look_day)}` : ''}`] : null,
        q5.p != null ? ['Placebo p', `${q5.p}${q5.p_floor != null ? ` (floor ${q5.p_floor})` : ''}`] : null, q5.q != null ? ['q (weighted BH)', q5.q] : null,
        q5.bh && q5.bh.m != null ? ['BH', `rank ${q5.bh.rank} of ${q5.bh.m}, weight ${q5.bh.weight}`] : null, q5.f_bin ? ['Fluke bin', q5.f_bin] : null, untested ? null : ['ρ̂₁', m.rho1 ?? 'not stored'],
        ['Method', m.method || c.method], m.ledger ? ['Ledger', h('span', null, `entry ${m.ledger.seq} `, h('span', { class: 'hash' }, m.ledger.chain_hash))] : null, untested ? null : ['Failed conditions', (m.fails || []).join(', ') || 'none']]),
      zRows.length ? h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, ['Channel', 'z (robust)', 'S', 'κ', 'weight', 'sources'].map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, zRows))) : null,
      untested ? null : h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, ['Placebo family', 'tested', 'as strong'].map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, placebo.fam.map(f => h('tr', null, h('td', null, L.FAM_WORD[f.k]), h('td', { class: 'n' }, L.fmtInt(f.n)), h('td', { class: 'n' }, L.fmtInt(f.exceed))))))),
      (m.licences || []).length ? h('p', { class: 'xs', style: 'color:var(--on-panel-2)' }, 'Sources: ', m.licences.map(l => `${l.attribution} (${l.licence})`).join('; ')) : null,
      q1rows.length ? h('details', null, h('summary', null, 'Q1 chart as a table'), h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, ['Day', '× normal', 'normal low', 'normal high', 'last year'].map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, q1rows)))) : null,
      h('div', { class: 'btns' }, h('a', { class: 'btn sec sm', href: csv, download: `stop-${d.hop_id}.csv` }, 'Download CSV'), h('a', { class: 'btn sec sm', href: issue, target: '_blank', rel: 'noopener' }, 'Something wrong?'))),
    h('div', { class: 'btns' }, h('button', { class: 'btn', onclick: () => share(L.shareStop(d), 'stop') }, icon('share'), 'Share this stop'), h('a', { class: 'btn sec', href: `/ripples/lands/${d.node.domain}/` }, 'Start from here')),
    h('p', { class: 'ctx' }, wordmark(), sep(), `${c.event.label} → ${d.node.label}`, sep(), 'bensunter.com/ripples', sep(), L.FOOT));
  setTimeout(() => { live.textContent = d.sr_sentence || ''; }, 60);
  if (fig && !d.retracted) countUp(fig, L.mult(x.rho, u), quiet);
}


export { openSheet, closeSheet, getSheet };
