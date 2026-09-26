// Ripple Map v6 line page (WS-D): the staircase, the stop cards and the evidence sheet. Loaded on /line/… routes and by /week/.
import * as C from './config.js';
import * as L from './lib.js';
import { $, add, h, S, em, sep, joinSep, put, icon, IC, RM, desk, ls, today, INLINE, D, rpc, load, event, toast, copy, share, prefetchImg, shareImage, landing, flaps, countUp, tt_, pips, stamp, dtile, strip, legend, spark, theme, help, wander, chrome, visits, seedChart, getBip } from './ui.js';

// ---------- the staircase (one inline SVG; the Week card uses the same drawing) ----------
export function staircase(c, entries, opts = {}) {
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
    const dEnd = Math.max(tD + 2, 10, ...lanes.map(l => l.due ?? -99).filter(d => d > -99 && d <= tD + 14));
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
    const placed = [];
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
        if (l.due <= X.end) S('rect', { x: X(l.due) - 5, y: y0 - 5, width: 10, height: 10, rx: 2, fill: 'var(--card)', stroke: 'var(--ink)', 'stroke-width': 1.75 }, g);
        else S('path', { d: `M${X(X.end) + 2} ${y0 - 5}l6 5-6 5z`, fill: 'var(--ink)' }, g);
      }
      // lane label: icon (and the name on desktop)
      const lab = S('text', { x: 2, y: y0 + 4, class: 'lane-lbl' }, g);
      lab.textContent = desk() ? `${l.shock ? c.event.emoji || '' : L.domIcon(n0.domain)} ${L.plainParts([{ t: n0.label }]).slice(0, 20)}` : l.shock ? c.event.emoji || '●' : L.domIcon(n0.domain);
      if (!desk()) lab.setAttribute('font-size', 11);
      // onset dot + connector from the parent's onset, with the lag as a small flap
      if (l.od != null && l.od >= X.start) {
        const par = l.shock ? null : lanes.findIndex(q => (n0.parent_hop ? q.n.hop_id === n0.parent_hop : q.shock));
        if (par != null && par >= 0 && lanes[par].od != null) {
          const x1 = X(lanes[par].od), y1 = b[par], x2 = X(l.od), y2 = y0;
          S('path', { d: `M${x1} ${y1}L${x2} ${y2}`, stroke: 'var(--ink)', 'stroke-width': 1.25, opacity: 0.45, fill: 'none' }, g);
          const lag = n0.lag_days != null ? (n0.lag_days === 0 ? '0 d' : `+${Math.round(n0.lag_days)} d`) : '';
          const mx = x2 + 7, my = y2 - 9, bw = lag.length * 6 + 6;
          if (lag && !placed.some(r => mx < r[0] + r[2] + 2 && mx + bw + 2 > r[0] && Math.abs(my - r[1]) < 15)) {
            placed.push([mx, my, bw]);
            S('rect', { x: mx, y: my - 7, width: bw, height: 14, rx: 2.5, fill: 'var(--marigold)' }, g);
            const lt = S('text', { x: mx + 3, y: my + 4, class: 'ax', style: 'fill:#0B3A40' }, g); lt.textContent = lag;
          }
        }
        l.dot = S('circle', { cx: X(l.od), cy: y0, r: l.shock ? 4.5 : 4, fill: l.shock ? 'var(--marigold)' : 'var(--card)', stroke: 'var(--ink)', 'stroke-width': 2 }, g);
      }
      l.val = null;
      if (l.shock && post.length) {
        const pk = post.reduce((a, p) => (p.v > a.v ? p : a), post[0]);
        const st = S('text', { x: X(pk.d) + 7, y: y0 - k * L.log2(pk.v) + 4, class: 'ax', style: 'font-size:12px;fill:var(--marigold-ink);paint-order:stroke;stroke:var(--card);stroke-width:3px' }, g);
        st.textContent = L.num(pk.v) + '×';
      }
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
      n.channels && n.channels.of ? `${n.channels.agree} of ${n.channels.of} ${n.channels.of === 1 ? 'source agrees' : 'sources agree'}` : null,
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
export async function linePage(r) {
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
  const head = h('header', { class: 'lh mob' }, h('span', { class: 'tk-emo', 'aria-hidden': 'true' }, em(c.event.emoji || '🌀')), h('div', null, h('h1', null, c.event.label), h('p', { class: 'meta' }, meta)));
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
      stripEl.append(h('span', { class: `trk${n.tier === 'watching' ? ' dash' : n.tier === 'likely' ? ' l' : ''}${n.attention_ripple ? ' att' : ''}`, 'aria-hidden': 'true' }));
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
    (c.rivals || []).length ? h('p', { style: 'margin-top:6px' }, 'Also active this week: ', c.rivals.map(x => x.label).join(', '), '. A stop shared with it could be a common cause.') : null,
    h('p', { class: 'xs', style: 'margin-top:6px' }, `Method ${c.method || C.METHOD}`, c.ledger?.seq ? [sep(), `ledger entry ${L.fmtInt(c.ledger.seq)}`] : null, sep(), h('a', { class: 'lnk', href: '/ripples/methods/' }, 'How we test')));
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
  const tsvg = S('svg', { class: 'tk-chart', role: 'img', 'aria-label': `${c.event.label}: attention against its own normal, peaking at ${L.num(c.event.magnitude_x)} times normal.` });
  const hasT = c.event.spark ? seedChart(tsvg, c.event.spark, quiet, L.num(c.event.magnitude_x) + '×') : false;
  const side = h('section', { class: 'ticket hero grain side', 'aria-labelledby': 'side-t' },
    h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, c.event.reconstructed ? 'From the archive, reconstructed' : 'The line'), h('span', { class: 'ver' }, 'v' + c.version)),
    h('div', { class: 'tk-body' }, h('div', { class: 'tk-row' }, h('span', { class: 'tk-emo', 'aria-hidden': 'true' }, em(c.event.emoji || '🌀')), h('h1', { class: 'tk-title', id: 'side-t' }, c.event.label)),
      h('p', { class: 'tk-sub' }, meta.map(x => (x.nodeType ? x.cloneNode(true) : x))), hasT ? tsvg : null),
    h('div', { class: 'tk-perf', 'aria-hidden': 'true' }, h('span', { class: 'notch l' }), h('span', { class: 'notch r' })),
    h('div', { class: 'tk-foot' }, h('p', { class: 'tk-meta' }, joinSep(L.lineMeta(c))), h('button', { class: 'btn', onclick: () => share(L.shareLine(c), 'line') }, icon('share'), 'Share this line')));
  const aside = h('aside', null, head, note,
    h('div', { class: 'dsk' }, side, denEl.cloneNode(true)));
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
  requestAnimationFrame(() => {
    if (!cards[0]) return;
    sc.reveal(1, quiet); sc.focus(1); tiles[0]?.setAttribute('aria-current', 'true');
    // desktop has room for the whole line: replay every lane in the order the stops moved (≈ 2.5 s)
    if (desk()) { const n = sc.lanes.length; for (let i = 2; i < n; i++) setTimeout(() => sc.reveal(i, quiet), RM ? 0 : (i - 1) * Math.min(320, 2500 / n)); }
  });
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
  put(el, h('div', { class: 'grab' }, h('b', null, node ? `${L.tierWord(node.tier)} stop, ${L.domWord(node.domain)}` : 'Evidence'), h('button', { class: 'xb', 'aria-label': 'Close the evidence', onclick: () => closeSheet() }, icon('x'))),
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
      h('p', { class: 'ev-say' }, d.retracted ? 'Before the retraction: ' + L.evidenceHeadline(d) : L.evidenceHeadline(d)),
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
        ['Method', m.method || c.method], ['Ledger', m.ledger ? h('span', null, `entry ${m.ledger.seq} `, h('span', { class: 'hash' }, m.ledger.chain_hash)) : null], ['Failed conditions', (m.fails || []).join(', ') || 'none']]),
      zRows.length ? h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, ['Channel', 'ž', 'S', 'κ', 'weight', 'sources'].map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, zRows))) : null,
      h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, ['Placebo family', 'tested', 'as strong'].map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, placebo.fam.map(f => h('tr', null, h('td', null, L.FAM_WORD[f.k]), h('td', { class: 'n' }, L.fmtInt(f.n)), h('td', { class: 'n' }, L.fmtInt(f.exceed))))))),
      (m.licences || []).length ? h('p', { class: 'xs', style: 'color:var(--on-panel-2)' }, 'Sources: ', m.licences.map(l => `${l.attribution} (${l.licence})`).join('; ')) : null,
      q1rows.length ? h('details', null, h('summary', null, 'Q1 chart as a table'), h('div', { class: 'tw' }, h('table', { class: 't' }, h('thead', null, h('tr', null, ['Day', '× normal', 'normal low', 'normal high', 'last year'].map(t => h('th', { scope: 'col' }, t)))), h('tbody', null, q1rows)))) : null,
      h('div', { class: 'btns' }, h('a', { class: 'btn sec sm', href: csv, download: `stop-${d.hop_id}.csv` }, 'Download CSV'), h('a', { class: 'btn sec sm', href: issue, target: '_blank', rel: 'noopener' }, 'Something wrong?'))),
    h('div', { class: 'btns' }, h('button', { class: 'btn', onclick: () => share(L.shareStop(d), 'stop') }, icon('share'), 'Share this stop'), h('a', { class: 'btn sec', href: `/ripples/lands/${d.node.domain}/` }, 'Start from here')),
    h('p', { class: 'ctx' }, h('b', null, 'Knock⌃On'), sep(), `${c.event.label} → ${d.node.label}`, sep(), 'bensunter.com/ripples', sep(), L.FOOT));
  setTimeout(() => { live.textContent = d.sr_sentence || ''; }, 60);
  if (fig && !d.retracted) countUp(fig, L.mult(x.rho, u), quiet);
}

// ---------- WEEK (uses the staircase) ----------
export async function weekPage(r) {
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
    h('div', { class: 'list' }, (wk.lines || []).map(x => weekRow({ ...x, measured: x.stops?.measured || 0, stops: (x.stops?.measured || 0) + (x.stops?.likely || 0), watching: x.stops?.watching || 0 }))), nav);
}
function weekRow(a) {
  const st = { measured: a.measured || 0, likely: Math.max(0, (a.stops || 0) - (a.measured || 0)), watching: a.watching || 0 };
  return h('a', { class: 'li' + (a.reconstructed ? ' recon' : ''), href: L.lineUrl(a.slug) },
    h('span', { class: 'ic' + (a.measured ? ' m' : ''), 'aria-hidden': 'true' }, em(a.emoji || '▫️')),
    h('span', null, h('span', { class: 'nm' }, a.label), h('span', { class: 'sub' }, a.reconstructed ? h('span', { class: 'tagr' }, 'reconstructed') : null, joinSep([L.fmtDayY(a.onset), L.STATUS[a.status] || a.status]))),
    h('span', { class: 'rt' }, strip(st, 6)));
}
