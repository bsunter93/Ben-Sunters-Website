// Ripple Map v6 list pages (WS-D): map, every line, archive, lands, week and the methods Receipts.
import * as C from './config.js';
import * as L from './lib.js';
import { $, add, h, S, em, sep, joinSep, put, icon, IC, RM, desk, ls, today, INLINE, D, rpc, load, event, toast, copy, share, prefetchImg, shareImage, landing, flaps, countUp, untilLook, tt_, pips, stamp, dtile, strip, legend, spark, theme, wander, chrome, visits, seedChart, getBip } from './ui.js';

// ---------- LISTS: map, lines, archive, lands, week ----------
export function lineRow(a, extra) {
  const st = { measured: a.measured || 0, likely: Math.max(0, (a.stops || 0) - (a.measured || 0)), watching: a.watching || 0 };
  return h('a', { class: 'li' + (a.reconstructed ? ' recon' : ''), href: L.lineUrl(a.slug) },
    h('span', { class: 'ic' + (a.measured ? ' m' : ''), 'aria-hidden': 'true' }, em(a.emoji || '▫️')),
    h('span', null, h('span', { class: 'nm' }, a.label), h('span', { class: 'sub' }, a.reconstructed ? h('span', { class: 'tagr' }, 'reconstructed') : null, joinSep([L.fmtDayY(a.onset), L.STATUS[a.status] || a.status, (a.domains || []).length ? h('span', null, a.domains.map(d => em(L.domIcon(d)))) : null])), extra || null),
    h('span', { class: 'rt' }, strip(st, 6)));
}
export async function mapPage(title) {
  const main = $('#main');
  const a = (await D.archive()) || [];
  const cut = L.addDays(today(), -30);
  const rows = a.filter(x => !x.reconstructed && (x.onset >= cut || x.status === 'running')).sort((x, y) => String(y.onset).localeCompare(String(x.onset)));
  const minis = new Map();
  const list = h('div', { class: 'list' }, rows.map(x => { const m = h('span', { class: 'mini', 'aria-hidden': 'true' }); minis.set(x.event_id, m); return lineRow(x, m); }));
  const rng = h('input', { type: 'range', min: 0, max: 30, value: 30, 'aria-label': 'Rewind the month: day' });
  const dl = h('span', null, L.fmtDate(today()));
  put(main, h('h1', { class: 'h1' }, title || 'The map'), h('p', { class: 'lede' }, 'Every line from the last 30 days, newest first. Drag the dial to rewind the month: each stop lights on the day it moved.'),
    legend('onstage'), h('div', { class: 'scrub' }, h('p', null, h('span', null, 'Rewind the month'), dl), rng),
    rows.length ? list : h('p', { class: 'empty', style: 'margin-top:12px' }, 'No lines in the last 30 days yet.'),
    h('p', { class: 'sm', style: 'margin-top:16px' }, h('a', { class: 'lnk', href: '/ripples/archive/' }, 'Older and reconstructed lines are in the archive')));
  const dots = [];
  const start = L.dayMs(L.addDays(today(), -30));
  await Promise.all(rows.slice(0, 30).map(async x => {
    const c = await D.cascade(x.event_id); const m = minis.get(x.event_id); if (!c || !m) return;
    const xo = d => Math.max(0, Math.min(100, ((L.dayMs(d) - start) / (30 * 864e5)) * 100));
    m.append(h('i', { class: 'sh', style: `left:${xo(c.event.onset)}%` }));
    for (const n of c.nodes || []) {
      if (!n.onset || !L.isStation(n)) continue;
      const el = h('i', { class: n.tier, style: `left:${xo(n.onset)}%` }); m.append(el);
      dots.push([el, n.onset]);
    }
  }));
  rng.addEventListener('input', () => { const d = L.addDays(today(), -30 + +rng.value); dl.textContent = L.fmtDate(d); for (const [el, o] of dots) el.style.opacity = o <= d ? 1 : 0.12; });
}
export async function archivePage() {
  const main = $('#main');
  const a = (await D.archive()) || [];
  const recon = a.filter(x => x.reconstructed).sort((x, y) => String(x.onset).localeCompare(String(y.onset)));
  const closed = a.filter(x => !x.reconstructed && x.status !== 'running').sort((x, y) => String(x.onset).localeCompare(String(y.onset)));
  put(main, h('h1', { class: 'h1' }, 'Archive'), h('p', { class: 'lede' }, 'Closed lines, oldest to newest, including the ones that went nowhere. Reconstructed lines were run afterwards on past shocks with the same frozen method; they are labelled every time they appear.'),
    h('h2', { class: 'h2 sec' }, 'Reconstructed archive'), recon.length ? h('div', { class: 'list' }, recon.map(x => lineRow(x))) : h('p', { class: 'empty' }, 'The reconstructed archive is not published yet.'),
    h('h2', { class: 'h2 sec' }, 'Closed lines'), closed.length ? h('div', { class: 'list' }, closed.map(x => lineRow(x))) : h('p', { class: 'empty' }, 'No live line has closed yet. Lines close when every window has shut.'),
    h('p', { class: 'sm', style: 'margin-top:16px' }, h('a', { class: 'lnk', href: '/ripples/map/' }, 'Lines from the last 30 days')));
}
export async function landsPage(r) {
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
    legend('onstage'), watchingHere(dom));
}
// The page never ends at one sentence: the running lines' Watching stops in this domain, with their next look
// (scanned client-side from the running lines' cascades until the lands payload carries a watching[] array)
function watchingHere(dom) {
  const box = h('section', { class: 'sec', 'aria-labelledby': 'wh-t' }, h('h2', { class: 'h2', id: 'wh-t' }, `Being watched in ${L.domWord(dom)}`), h('p', { class: 'lede', style: 'margin:-4px 0 10px' }, 'Windows still open: nothing has moved yet, and the look is scheduled.'));
  (async () => {
    const a = ((await D.archive()) || []).filter(x => x.status === 'running').sort((x, y) => String(y.onset).localeCompare(String(x.onset))).slice(0, 12);
    const rows = [];
    await Promise.all(a.map(async x => { const c = await D.cascade(x.event_id); if (!c) return; for (const n of c.nodes || []) if (n.tier === 'watching' && n.domain === dom && !n.window_closed && (n.due || n.window_close)) rows.push({ x, c, n, due: n.due || n.window_close }); }));
    rows.sort((p, q) => String(p.due).localeCompare(String(q.due)));
    if (!rows.length) { box.remove(); return; }
    box.append(h('div', { class: 'list' }, rows.slice(0, 12).map(r => h('a', { class: 'li', href: L.stopUrl(r.x.slug, r.n.hop_id) },
      h('span', { class: 'ic', 'aria-hidden': 'true' }, em(r.x.emoji || '▫️')),
      h('span', null, h('span', { class: 'nm' }, r.n.label), h('span', { class: 'sub' }, joinSep([`after ${r.x.label}`, `${L.lookWord(r.n.due, r.n.window_close).toLowerCase()} ${L.fmtDate(r.due)}`]))),
      h('span', { class: 'rt' }, flaps(untilLook(r.due), 'mute', `${untilLook(r.due)} to the look`), stamp('watching'))))));
  })().catch(() => box.remove());
  return box;
}

// ---------- METHODS: the Receipts ----------
export async function methodsPage() {
  const box = $('#receipts'); if (!box) return;
  const [cal, hl] = await Promise.all([D.calib(), D.health()]);
  if (!cal) { put(box, h('p', { class: 'empty' }, 'The calibration payload is not published yet. The rules below apply either way.')); return; }
  const o = cal.decoy_fdr?.overall || {}, rc = cal.receipts || {}, neg = cal.controls?.negative || {};
  const pct = v => (v == null ? '–' : (v * 100).toFixed(1).replace(/\.0$/, '') + '%');
  const brk = (cal.breaker || []).length || (hl?.breaker || []).length;
  const ks = cal.null_ks || {};
  const ksSvg = S('svg', { viewBox: '0 0 200 64', preserveAspectRatio: 'none', role: 'img', 'aria-label': `Histogram of ${ks.n || 0} held-out null p-values in 20 bins; a flat shape means the test is calibrated.` });
  const hist = ks.hist || [], hm = Math.max(1, ...hist);
  hist.forEach((v, i) => S('rect', { x: i * 10 + 1, y: 58 - (v / hm) * 54, width: 8, height: (v / hm) * 54, fill: 'var(--ink)', opacity: 0.8 }, ksSvg));
  const tbl = (head, body) => h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, head.map((t, i) => h('th', { scope: 'col', class: i && /tests|Measured|Size|Lag|Found|Tested|Seen|Of|Moved|flukes|Count/.test(t) ? 'n' : null }, t)))), h('tbody', null, body)));
  put(box,
    brk ? h('p', { class: 'brk', role: 'alert' }, 'Circuit breaker tripped: ', (cal.breaker || hl.breaker).map(b => b.cell || b).join(', '), '. Measured stops in those cells are shown as Likely until the cell recovers.') : null,
    h('p', { class: 'sm muted' }, `As of ${L.fmtDate(cal.as_of)}, method ${cal.method}. Every number here is read from the calibration file the engine publishes.`),
    h('div', { class: 'rc' },
      h('div', null, h('b', null, pct(o.rate)), h('span', null, `Decoy false-pass rate (${L.fmtInt(o.decoy_measured)} of ${L.fmtInt(o.decoy_tested)} decoy tests; Wilson interval ${pct(o.lo)}–${pct(o.hi)})`)),
      h('div', null, h('b', null, `${L.fmtInt(rc.hits)} of ${L.fmtInt(rc.resolved)}`), h('span', null, `Pre-registered calls resolved as a hit (${L.fmtInt(rc.registered)} registered; the base rate predicted ${rc.base_rate_hits ?? '–'})`)),
      h('div', null, h('b', null, ks.p != null ? ks.p : '–'), h('span', null, `Null check: KS p on ${L.fmtInt(ks.n)} held-out pairs (KS ${ks.stat ?? '–'}); we want p ≥ 0.05`)),
      h('div', null, h('b', null, pct(neg.pass_rate)), h('span', null, `Negative controls passing (decoy rate ${pct(neg.decoy_rate)}, n ${L.fmtInt(neg.n)})`))),
    h('figure', { class: 'ks' }, ksSvg, h('figcaption', { class: 'xs muted' }, `Held-out null p-values in 20 bins, from 0 (left) to 1 (right). A flat row means the placebo test is calibrated.`),
      hist.length ? h('details', null, h('summary', { class: 'lnk' }, 'The histogram as a table'), tbl(['p from', 'p to', 'Count'], hist.map((v, i) => h('tr', null, h('td', null, (i / 20).toFixed(2)), h('td', null, ((i + 1) / 20).toFixed(2)), h('td', { class: 'n' }, v))))) : null),
    rc.show_reliability ? null : h('p', { class: 'sm muted' }, 'Reliability and Brier scores appear once enough pre-registered calls resolve; until then only the raw counts are shown.'),
    h('h3', null, 'Positive controls'), tbl(['Control', 'Result', 'Last run'], (cal.controls?.positive || []).map(p => h('tr', null, h('td', null, p.name), h('td', null, p.passed ? 'passed' : 'not passed'), h('td', null, L.fmtDay(p.last_run))))),
    h('h3', null, 'Decoy false-pass rate by cell'), tbl(['Cell', 'Decoy tests', 'Decoy Measured', 'Real tests', 'Real Measured'], (cal.decoy_fdr?.cells || []).map(x => h('tr', null, h('td', null, x.cell), h('td', { class: 'n' }, x.decoy_tested), h('td', { class: 'n' }, x.decoy_measured), h('td', { class: 'n' }, x.real_tested), h('td', { class: 'n' }, x.real_measured)))),
    h('h3', null, 'Power'), tbl(['Channel', 'Size', 'Lag', 'Found', 'Tested'], (cal.power || []).map(p => h('tr', null, h('td', null, p.channel), h('td', { class: 'n' }, p.delta), h('td', { class: 'n' }, p.lag), h('td', { class: 'n' }, pct(p.recall)), h('td', { class: 'n' }, p.tested ?? '–')))),
    h('h3', null, 'Replication by family'), tbl(['Family', 'Edge class', 'Seen', 'Of'], (cal.refire || []).map(p => h('tr', null, h('td', null, p.family), h('td', null, p.edge_class), h('td', { class: 'n' }, p.hits), h('td', { class: 'n' }, p.n)))),
    h('h3', null, 'Day lines'), tbl(['Day', 'Tested', 'Moved', 'Measured', 'Expected flukes'], (cal.day_lines || []).map(x => h('tr', null, h('td', null, L.fmtDay(x.day)), h('td', { class: 'n' }, x.line?.tested), h('td', { class: 'n' }, x.line?.moved), h('td', { class: 'n' }, x.line?.measured), h('td', { class: 'n' }, x.line?.expected_flukes)))),
    h('h3', null, 'Retractions'), (cal.retractions || []).length ? tbl(['Stop', 'Date', 'Reason'], cal.retractions.map(x => h('tr', null, h('td', null, 'stop ' + x.hop_id), h('td', null, L.fmtDay(x.date)), h('td', null, x.reason)))) : h('p', null, 'None yet.'),
    h('h3', null, 'Ledger'), h('p', { class: 'sm' }, `Head, entry ${L.fmtInt(cal.ledger?.seq)}: `, h('span', { class: 'hash', style: 'color:var(--ink-3)' }, cal.ledger?.head || '–')),
    cal.archive ? h('p', { class: 'sm muted' }, `Reconstructed archive: ${cal.archive.label || ''} (as of ${L.fmtDay(cal.archive.as_of)}).`) : null,
    hl ? h('p', { class: 'sm muted' }, `Pipeline: ${hl.stage || '–'} for ${L.fmtDay(hl.latest_day)}${hl.stale ? ', running late' : ''}. Disabled sources: ${(hl.sources_disabled || []).join(', ') || 'none'}.`) : null);
}
