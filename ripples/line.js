// Ripple Map v6 line page (WS-D): the staircase, the stop cards and the evidence sheet. Loaded on /line/… routes and by /week/.
import * as C from './config.js';
import * as L from './lib.js';
import { $, add, h, S, em, sep, joinSep, put, icon, IC, RM, desk, ls, today, INLINE, D, rpc, load, event, toast, copy, share, prefetchImg, shareImage, landing, flaps, countUp, tt_, pips, stamp, dtile, strip, legend, spark, theme, wander, chrome, visits, seedChart, getBip, axText } from './ui.js';

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
    const tkt = fig.classList.contains('tk'), min = fig.classList.contains('min');
    const W = Math.max(280, Math.round(fig.clientWidth - 12) || 316), H = tkt ? 150 : desk() ? 320 : min ? 118 : 200;
    svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
    const wide = desk() && !opts.narrow;
    const gl = wide ? 150 : 24, gr = 40, top = 8, bot = 18;
    const dEnd = Math.max(tD + 2, 10, ...lanes.map(l => l.due ?? -99).filter(d => d > -99 && d <= tD + 14));
    const X = L.xScale(dEnd, gl, W - gr);
    // By hop (desktop toggle): each lane keeps its own days but is centred on its own column, so the order reads left to right
    const byHop = api.mode === 'hop', n = lanes.length;
    const anchor = l => l.od ?? l.due ?? tD;
    const colW = (W - gl - gr) / n, pxDay = colW / 5;
    const cx = i => gl + colW * (i + 0.5);
    const XL = i => (byHop ? (dd => cx(i) + (dd - anchor(lanes[i])) * pxDay) : X);
    const vis = (l, i) => l.pts.filter(p => (byHop ? Math.abs(p.d - anchor(l)) <= 6 : p.d >= X.start && p.d <= X.end));
    const ext = lanes.map((l, i) => { const v = vis(l, i).map(p => L.log2(p.v)).concat(l.band ? l.band.hi.filter(p => p.d >= X.start).map(p => L.log2(p.v)) : []); return { up: Math.max(0, ...v), dn: Math.max(0, ...v.map(x => -x)) }; });
    // The shock's job is to mark when, not to own the scale: its lane is capped at ≈3× (1.6 doublings) and the peak beyond
    // the cap is drawn as a clipped spike with its label at the cap. The stop lanes get a floor on their pitch instead.
    const CAP = 1.6; ext[0].up = Math.min(ext[0].up, CAP);
    const pitch = tkt ? 20 : desk() ? 34 : min ? 14 : 18;
    const layout = k => { const b = []; let y = top + Math.max(6, ext[0].up * k); b.push(y); for (let i = 1; i < n; i++) { y += Math.max(pitch, ext[i - 1].dn * k + ext[i].up * k * 0.4 + 5); b.push(y); } return { b, tot: y + ext[n - 1].dn * k + bot }; };
    let lo = 1, hi = 90, k = 1;
    for (let it = 0; it < 24; it++) { const m = (lo + hi) / 2; if (layout(m).tot <= H) { k = m; lo = m; } else hi = m; }
    let { b } = layout(k);
    const slack = H - layout(k).tot; if (slack > 0) b = b.map((y, i) => y + (slack * (i + 0.5)) / n * 0.9);
    const grid = S('g', null, svg), body = S('g', null, svg), marks = S('g', null, svg);
    // x ticks and today
    if (byHop) lanes.forEach((l, i) => { S('line', { x1: cx(i), x2: cx(i), y1: top, y2: H - bot + 2, stroke: 'var(--grid-card)', 'stroke-width': 1 }, grid); const tx = S('text', { x: cx(i), y: H - 4, class: 'ax', 'text-anchor': 'middle' }, grid); tx.textContent = i ? String(i) : 'shock'; });
    else {
      for (const t of X.ticks) { S('line', { x1: X(t), x2: X(t), y1: top, y2: H - bot + 2, stroke: 'var(--grid-card)', 'stroke-width': 1 }, grid); const tx = S('text', { x: X(t), y: H - 4, class: 'ax', 'text-anchor': 'middle' }, grid); axText(tx, t === 0 ? 'd0' : '+' + t); }
      const xt = X(tD); S('line', { x1: xt, x2: xt, y1: top, y2: H - bot + 2, stroke: 'var(--ink-3)', 'stroke-width': 1, opacity: 0.55 }, grid);
      const tl = S('text', { x: Math.min(W - 4, xt + 3), y: top + 8, class: 'lane-lbl', 'text-anchor': xt > W - 40 ? 'end' : 'start' }, grid); tl.textContent = 'today';
    }
    // scale key: one doubling
    const anyData = lanes.some(l => l.pts.length > 1);
    const kx = anyData ? W - gr + 14 : -99, ky = H - bot - 4;
    S('path', { d: `M${kx} ${ky}v${-k}m-3 0h6m-6 ${k}h6`, stroke: 'var(--ink-3)', 'stroke-width': 1.5, fill: 'none' }, grid);
    const kt = S('text', { x: kx + 5, y: ky - k / 2 + 3, class: 'ax' }, grid); axText(kt, '2×');
    const clipId = 'clp' + Math.random().toString(36).slice(2, 7);
    const cp = S('clipPath', { id: clipId }, S('defs', null, svg)); dayClip = S('rect', { x: 0, y: -40, width: W, height: H + 80 }, cp);
    body.setAttribute('clip-path', `url(#${clipId})`);
    const P = (arr, y0, Xf = X, cap = 99) => arr.map((p, i) => `${i ? 'L' : 'M'}${Xf(p.d).toFixed(1)} ${(y0 - k * Math.min(cap, L.log2(p.v))).toFixed(1)}`).join('');
    api.X = X; api.W = W; api.k = k;
    const placed = [], lagText = b.length > 1 && (b[1] - b[0]) < 22 || (n > 2 && (b[2] - b[1]) < 22);
    // lanes not yet revealed are painted faint (.28) so the fold shows the shape of the staircase at first paint
    const dim = l => (l.att ? 0.2 : 0.28);
    lanes.forEach((l, i) => {
      const y0 = b[i], g = S('g', { class: 'lane', opacity: l.shown || opts.all ? 1 : dim(l) }, body), n0 = l.n, Xi = XL(i);
      l.g = g; l.y0 = y0;
      S('line', { x1: gl, x2: W - gr, y1: y0, y2: y0, stroke: 'var(--grid-card)', 'stroke-width': 1 }, g);
      if (l.band) {
        const inb = p => (byHop ? Math.abs(p.d - anchor(l)) <= 6 : p.d >= X.start);
        const lo2 = l.band.lo.filter(inb), hi2 = l.band.hi.filter(inb);
        if (lo2.length > 1) S('path', { d: P(hi2, y0, Xi) + 'L' + lo2.slice().reverse().map(p => `${Xi(p.d).toFixed(1)} ${(y0 - k * L.log2(p.v)).toFixed(1)}`).join('L') + 'Z', fill: 'var(--band)' }, g);
      }
      const pts = vis(l, i), cut = l.od ?? 1e9;
      const pre = pts.filter(p => p.d <= cut), post = pts.filter(p => p.d >= cut - 1);
      const flat = n0.tier === 'retracted', watch = n0.tier === 'watching';
      const col = flat ? 'var(--flat)' : 'var(--ink)';
      const cap = l.shock ? CAP : 99;
      l.pre = pre.length > 1 ? S('path', { d: P(pre, y0, Xi, cap), fill: 'none', stroke: col, 'stroke-width': 1.75, 'stroke-linejoin': 'round', 'stroke-dasharray': watch ? '4 4' : null, class: flat ? 'lane-flat' : null }, g) : null;
      l.post = post.length > 1 && l.od != null ? S('path', { d: P(post, y0, Xi, cap), fill: 'none', stroke: l.shock ? 'var(--spike)' : col, 'stroke-width': l.shock ? 2.5 : 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', class: l.shock ? 'lane-hot' : flat ? 'lane-flat' : null }, g) : null;
      if (n0.attention_ripple) { l.att = true; g.setAttribute('opacity', l.shown || opts.all ? 0.5 : dim(l)); }
      // Watching: dashed track from today to the due date, hollow tile at the due date
      if (watch && l.due != null) {
        const a = S('line', { x1: Xi(byHop ? l.due - 3 : Math.min(tD, l.due)), x2: Xi(l.due), y1: y0, y2: y0, stroke: 'var(--ink)', 'stroke-width': 2, 'stroke-dasharray': '4 4', class: RM ? null : 'marching' }, g);
        void a;
        if (byHop || l.due <= X.end) S('rect', { x: Xi(l.due) - 5, y: y0 - 5, width: 10, height: 10, rx: 2, fill: 'var(--card)', stroke: 'var(--ink)', 'stroke-width': 1.75 }, g);
        else S('path', { d: `M${X(X.end) + 2} ${y0 - 5}l6 5-6 5z`, fill: 'var(--ink)' }, g);
      }
      // lane label: icon (and the name on desktop)
      const lab = S('text', { x: 2, y: y0 + 4, class: 'lane-lbl' }, g);
      lab.textContent = wide ? `${l.shock ? c.event.emoji || '' : L.domIcon(n0.domain)} ${L.plainParts([{ t: n0.label }]).slice(0, 20)}` : l.shock ? c.event.emoji || '●' : L.domIcon(n0.domain);
      if (!wide) lab.setAttribute('font-size', 11);
      // onset dot + connector from the parent's onset, with the lag as a small flap
      if (l.od != null && (byHop || l.od >= X.start)) {
        const par = l.shock ? null : lanes.findIndex(q => (n0.parent_hop ? q.n.hop_id === n0.parent_hop : q.shock));
        if (par != null && par >= 0 && lanes[par].od != null) {
          const x1 = XL(par)(lanes[par].od), y1 = b[par], x2 = Xi(l.od), y2 = y0;
          S('path', { d: `M${x1} ${y1}L${x2} ${y2}`, stroke: 'var(--ink)', 'stroke-width': 1.25, opacity: 0.45, fill: 'none' }, g);
          const lag = n0.lag_days != null ? (n0.lag_days === 0 ? '0 d' : `+${Math.round(n0.lag_days)} d`) : '';
          const mx = x2 + 7, my = y2 - 9, bw = lag.length * 6 + 6;
          if (lag && !placed.some(r => mx < r[0] + r[2] + 2 && mx + bw + 2 > r[0] && Math.abs(my - r[1]) < 15)) {
            // tight lanes (pitch < 22 px): the lag is plain axis text beside the dot, so flaps never stack on each other
            const fr = lagText ? null : S('rect', { x: mx, y: my - 7, width: bw, height: 14, rx: 2.5, fill: 'var(--marigold)' }, g);
            const lt = S('text', { x: lagText ? x2 + 6 : mx + 3, y: lagText ? y2 - 4 : my + 4, class: 'ax', style: lagText ? 'fill:var(--marigold-ink);paint-order:stroke;stroke:var(--card);stroke-width:3px' : 'fill:#0B3A40' }, g); axText(lt, lag);
            placed.push([mx, my, bw, fr || lt, lt]);
          }
        }
        l.dot = S('circle', { cx: Xi(l.od), cy: y0, r: l.shock ? 4.5 : 4, fill: l.shock ? 'var(--marigold)' : 'var(--card)', stroke: 'var(--ink)', 'stroke-width': 2 }, g);
      }
      l.val = null;
      if (l.shock && post.length) {
        // the peak label sits at the (capped) peak; it moves to the left of the dot when the "today" rule is in the way
        const pk = post.reduce((a, p) => (p.v > a.v ? p : a), post[0]);
        const px = Xi(pk.d), left = !byHop && px > X(tD) - 40, py = y0 - k * Math.min(CAP, L.log2(pk.v));
        const st = S('text', { x: left ? px - 7 : px + 7, y: py + 4, class: 'ax', 'text-anchor': left ? 'end' : 'start', style: 'font-size:12px;fill:var(--marigold-ink);paint-order:stroke;stroke:var(--card);stroke-width:3px' }, g);
        axText(st, L.num(pk.v) + '×');
        if (L.log2(pk.v) > CAP) S('path', { d: `M${(px - 4).toFixed(1)} ${(py - 2).toFixed(1)}l4 -4 4 4`, fill: 'none', stroke: 'var(--spike)', 'stroke-width': 1.5, 'stroke-linecap': 'round' }, g);
      }
      if (!l.shock && post.length && n0.rho != null) {
        const ex = post.reduce((a, p) => (Math.abs(L.log2(p.v)) > Math.abs(L.log2(a.v)) ? p : a), post[0]);
        const vt = S('text', { x: Math.min(W - gr + 2, Xi(ex.d) + 6), y: y0 - k * L.log2(ex.v) + (ex.v < 1 ? 12 : -4), class: 'ax', style: 'font-size:11px;paint-order:stroke;stroke:var(--card);stroke-width:3px', opacity: 0 }, g);
        axText(vt, L.mult(n0.rho, n0.unit)); l.val = vt;
        // other places the value can sit if a lag flap is in the way: past the lane's last point, then above it
        const lp = post[post.length - 1], ly = y0 - k * L.log2(lp.v);
        l.valAlt = [[Math.min(W - gr + 2, Xi(lp.d) + 8), ly + 4], [Math.min(W - gr + 2, Xi(ex.d) + 6), y0 - k * L.log2(ex.v) - (ex.v < 1 ? 6 : 16)]];
      }
    });
    // the focused value label must never sit under a lag flap: try the other spots, else hide the clashing flaps while focused
    const hit = (x, y, w) => placed.filter(r => x < r[0] + r[2] + 1 && x + w + 1 > r[0] && y - 10 < r[1] + 8 && y + 3 > r[1] - 8);
    lanes.forEach(l => {
      if (!l.val) return;
      const w = l.val.textContent.length * 6.6 + 2, x0 = +l.val.getAttribute('x'), y0v = +l.val.getAttribute('y');
      const spots = [[x0, y0v], ...(l.valAlt || [])];
      const ok = spots.find(([x, y]) => !hit(x, y, w).length);
      if (ok) { l.val.setAttribute('x', ok[0].toFixed(1)); l.val.setAttribute('y', ok[1].toFixed(1)); l.clash = []; }
      else l.clash = hit(x0, y0v, w).flatMap(r => [r[3], r[4]]);
    });
    if (hot >= 0) api.focus(hot, true);
    void marks;
  };
  api.focus = (i, silent) => {
    if (lanes[hot]) (lanes[hot].clash || []).forEach(e => e.removeAttribute('opacity'));
    const prev = lanes[hot]; if (prev && prev.post && !prev.shock) { prev.post.setAttribute('stroke', prev.n.tier === 'retracted' ? 'var(--flat)' : 'var(--ink)'); prev.post.setAttribute('stroke-width', 2); prev.post.classList.remove('lane-hot'); if (prev.val) prev.val.setAttribute('opacity', 0); if (prev.dot) prev.dot.setAttribute('fill', 'var(--card)'); }
    hot = i; const l = lanes[i]; if (!l) return;
    if (l.post && !l.shock && l.n.tier !== 'retracted') { l.post.setAttribute('stroke', 'var(--spike)'); l.post.setAttribute('stroke-width', 3); l.post.classList.add('lane-hot'); }
    if (l.val) { l.val.setAttribute('opacity', 1); (l.clash || []).forEach(e => e.setAttribute('opacity', 0)); }
    if (l.dot && !l.shock) l.dot.setAttribute('fill', 'var(--marigold)');
    void silent;
  };
  // a lane is already there, faint; revealing brings it to full ink and draws its after-the-shock segment and onset dot
  api.reveal = (i, quiet) => {
    const l = lanes[i]; if (!l || l.shown) return; l.shown = true;
    if (!l.g) return;
    const op = l.att ? 0.5 : 1, from = l.att ? 0.2 : 0.28;
    l.g.setAttribute('opacity', op);
    if (RM || quiet) { l.g.animate([{ opacity: from }, { opacity: op }], { duration: 150 }); return; }
    l.g.animate([{ opacity: from }, { opacity: op }], { duration: 150, easing: 'ease-out' });
    let t = 60;
    if (l.post) { const len = l.post.getTotalLength(); l.post.animate([{ strokeDasharray: `${len} ${len}`, strokeDashoffset: len }, { strokeDasharray: `${len} ${len}`, strokeDashoffset: 0 }], { duration: 260, delay: t, easing: 'ease-in', fill: 'backwards' }); t += 260; }
    if (l.dot) l.dot.animate([{ transform: 'scale(0)' }, { transform: 'scale(1.2)' }, { transform: 'scale(1)' }], { duration: 160, delay: Math.max(0, t - 120), fill: 'backwards', easing: 'cubic-bezier(.34,1.56,.64,1)' }), l.dot.style.transformOrigin = `${l.dot.getAttribute('cx')}px ${l.dot.getAttribute('cy')}px`, l.dot.style.transformBox = 'view-box';
  };
  api.setDay = d => { if (dayClip && api.X) dayClip.setAttribute('width', d == null ? api.W + 40 : Math.max(0, api.X(d) + 1)); };
  api.showAll = () => lanes.forEach(l => { l.shown = true; if (l.g) l.g.setAttribute('opacity', l.att ? 0.5 : 1); });
  // Signature B: replay the staircase on a loop (lanes draw in order over ≈2.5 s, hold, repeat); off while the tab is hidden
  let loopT = 0, loopQ = [];
  const runOnce = () => {
    loopQ.forEach(clearTimeout); loopQ = [];
    lanes.forEach((l, i) => { if (i) { l.shown = false; if (l.g) l.g.setAttribute('opacity', l.att ? 0.2 : 0.28); } });
    const n = lanes.length, step = Math.min(420, 2500 / Math.max(1, n - 1));
    for (let i = 1; i < n; i++) loopQ.push(setTimeout(() => api.reveal(i, false), 200 + (i - 1) * step));
  };
  api.loop = (period = 6000) => { if (RM) { api.showAll(); return; } api.stopLoop(); runOnce(); loopT = setInterval(() => { if (!document.hidden) runOnce(); }, period); };
  api.stopLoop = () => { clearInterval(loopT); loopT = 0; loopQ.forEach(clearTimeout); loopQ = []; api.showAll(); };
  lanes[0].shown = true;
  let rt; addEventListener('resize', () => { clearTimeout(rt); rt = setTimeout(() => { api.draw(); if (opts.all) api.showAll(); }, 150); });
  requestAnimationFrame(() => { api.draw(); if (opts.all) api.showAll(); });
  return api;
}
// ---------- LINE ----------
function stopCard(c, e, idx, total, sc, laneIdx) {
  const n = e.n, par = L.parentLabel(c, n), quiet = !!c.event.sensitive;
  const card = h('li', { class: `stop ${n.tier}${n.attention_ripple ? ' att' : ''}${e.depth > 1 ? ' d' + Math.min(3, e.depth) : ''}`, id: 'stop-' + n.hop_id, 'data-lane': laneIdx });
  // "Stop k of N" counts Measured + Likely stops only (the same count the home ticket and board show, L.stopCount);
  // Watching and Retracted stops are named by their tier instead of taking a number
  const kick = h('p', { class: 'kick' }, dtile(n), h('span', null, idx && L.isMoved(n) ? `Stop ${idx} of ${total}` : L.tierWord(n.tier), sep(), L.domWord(n.domain)));
  const say = h('p', { class: 'say' });
  const parts = L.stopSentence(n, par);
  let firstFlap = null;
  for (const p of parts) {
    if (p.t) say.append(p.t);
    else if (p.g) say.append(h('span', { class: 'gloss', 'aria-hidden': 'true' }, p.g));
    else if (p.dir) say.append(h('span', { class: 'dir', 'aria-hidden': 'true' }, p.dir));
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
    // A Watching stop is a moment, not a caption: the countdown to the next look leads (flaps, the same voice as the
    // Measured sentence), then the window track with the look marked, then the pre-registered base rate in words
    const look = !n.window_closed ? (n.due || n.window_close) : null;
    if (look) {
      const dl = Math.max(0, L.daysBetween(today(), look));
      const cnt = h('p', { class: 'say wait' }, `${n.label}: `, flaps(String(dl), null, `${dl} days`), ` ${dl === 1 ? 'day' : 'days'} until the ${L.lookWord(n.due, n.window_close).toLowerCase()}${dl === 0 ? ', today' : ''}.`);
      if (!firstFlap) firstFlap = [cnt, String(dl)];
      say.replaceWith(cnt);
    }
    if (!n.window_closed && n.window_close) {
      const a = L.dayMs(c.event.onset), z = L.dayMs(n.window_close), t = Math.min(z, Math.max(a, L.dayMs(today())));
      const pct = Math.round(((t - a) / Math.max(1, z - a)) * 100);
      const duePct = n.due ? Math.round(((L.dayMs(n.due) - a) / Math.max(1, z - a)) * 100) : null;
      card.append(h('div', { class: 'wt' },
        h('div', { class: 'track', role: 'img', 'aria-label': `Window ${pct}% gone: opened ${L.fmtDay(c.event.onset)}, closes ${L.fmtDay(n.window_close)}${n.due ? `; ${L.lookWord(n.due, n.window_close).toLowerCase()} ${L.fmtDay(n.due)}` : ''}` }, h('i', { style: `width:${pct}%` }),
          duePct != null ? h('b', { style: `left:${Math.min(97, Math.max(3, duePct))}%` }, h('span', { class: 'cap' }), h('span', { class: 'dl' }, `${L.lookWord(n.due, n.window_close)} ${L.fmtDay(n.due)}`)) : null),
        h('p', { class: 'lbls' }, h('span', null, `Shock ${L.fmtDay(c.event.onset)}`), h('span', null, `window closes ${L.fmtDay(n.window_close)}`))));
    }
    if (n.sentence) card.append(h('p', { class: 'eng base' }, n.sentence));
    if (!n.window_closed && n.due) card.append(h('p', { class: 'xs', style: 'margin-top:6px' }, h('a', { class: 'lnk', href: `${C.STORAGE}ics/hop-${n.hop_id}.ics`, download: `ripple-${n.hop_id}.ics` }, `Add the ${L.lookWord(n.due, n.window_close).toLowerCase()} to my calendar`)));
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
  // Signature C: the null is the product. The flat paths are a grid of grey tiles (icon, flat sparkline, multiple) that flip
  // face-up in a 40 ms stagger when the stub opens; the row reads "N moved, M didn't", and the null can be shared as such.
  const moved = (c.nodes || []).filter(n => L.isMoved(n) && (n.parent_hop || null) === (parentHop || null)).length;
  const tiles = fl.map(f => h('li', { class: 'ft', title: `${f.label}: ${L.num(f.rho)}× its normal, ${f.reason}` }, h('span', { class: 'fi', 'aria-hidden': 'true' }, em(L.domIcon(f.domain))), spark(f.spark, 64, 22),
    h('b', { 'aria-hidden': 'true' }, f.rho != null ? L.num(f.rho) + '×' : ''), h('span', { class: 'fl' }, f.label, h('span', { class: 'sr' }, `: ${L.num(f.rho)} times its normal, ${f.reason}`))));
  const nullText = `${L.shareLine(c).split('\n')[0]}\n⊥${fl.length} stayed flat${where ? ' ' + where : ''}, ${L.plural(moved, 'path')} moved. Every path we tried is counted.\nconsistent with, not proof of cause\n${L.SITE}${L.lineUrl(c.event.slug, c.version)}`;
  const list = h('div', { class: 'flatbox', hidden: true }, h('p', { class: 'flatsum' }, h('b', null, `${L.fmtInt(moved)} moved, ${L.fmtInt(fl.length)} didn't.`), ' Each tile is one path tested against its own normal; grey means it stayed inside its range.'),
    h('ul', { class: 'flatlist' }, tiles), h('button', { class: 'btn sec sm', onclick: () => share(nullText, 'null') }, icon('share'), 'Share the null'));
  let flipped = false;
  const b = h('button', { class: 'stub', 'aria-expanded': 'false', onclick: () => {
    const o = list.hidden; list.hidden = !o; b.setAttribute('aria-expanded', String(o));
    if (o && !flipped && !RM && !c.event.sensitive) { flipped = true; tiles.forEach((t, i) => t.animate([{ transform: 'rotateY(90deg)', opacity: 0.3 }, { transform: 'rotateY(0)', opacity: 1 }], { duration: 140, delay: i * 40, fill: 'backwards', easing: 'ease-out' })); }
  } }, h('span', { class: 'bot', 'aria-hidden': 'true' }, '⊥'), `${fl.length} stayed flat${where ? ' ' + where : ''}`, icon('chev', 'chev'));
  return h('div', { style: 'margin:4px 0 12px' }, b, list);
}
function shareBlock(c, frozenK) {
  const text = L.shareLine(c);
  const og = `${C.STORAGE}og/line-${c.event.event_id}-v${frozenK || c.version}.png`;
  return h('section', { class: 'sec', 'aria-labelledby': 'sh-t' }, h('h2', { class: 'h2', id: 'sh-t' }, 'Share this line'),
    h('div', { class: 'slip' }, h('small', null, 'What gets shared'), text),
    h('div', { class: 'btns' }, h('button', { class: 'btn', onclick: () => share(text, 'line') }, icon('share'), 'Share'),
      h('button', { class: 'btn sec', onclick: () => copy(text) }, icon('copy'), 'Copy text'),
      h('button', { class: 'btn sec', onpointerenter: () => prefetchImg(og), onclick: () => shareImage(og, text, 'line', `ripple-${c.event.event_id}.png`) }, icon('img'), 'Share image')),
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
  const note = h('p', { class: 'xs muted', style: 'margin-top:6px' }, 'We keep the address for this list only; it cannot be read back through the site. ', h('a', { class: 'lnk', href: '/ripples/methods/#privacy' }, 'Privacy'));
  return h('section', { class: 'wl', 'aria-labelledby': 'wl-t' }, h('h2', { id: 'wl-t', style: 'font:700 15px/1.3 var(--sans)' }, 'Want new lines by email?'),
    h('p', { class: 'sm muted', style: 'margin-top:4px' }, "We don't send email yet. Leave your address and we'll write once, when the daily email starts."), f, note, out,
    C.STRIPE.support ? h('p', { class: 'sm', style: 'margin-top:12px' }, h('b', null, 'Support Knock⌃On. '), 'Pay what you want, from $2. It unlocks nothing: the map and archive stay free. ', h('a', { class: 'lnk', href: C.STRIPE.support, target: '_blank', rel: 'noopener' }, 'Support')) : null);
}
// the evidence sheet is its own chunk (evidence.js): fetched on the first sheet open, or at once on a /stop/ route
const evidence = () => import('./evidence.js');
export async function linePage(r) {
  const main = $('#main');
  const isStop = r.route === 'stop';
  const ev = isStop ? (p => () => p)(evidence()) : evidence;
  let hopDoc = null, c = null;
  if (isStop) {
    hopDoc = INLINE && INLINE.hop_id ? INLINE : await D.hop(r.hop);
    const cp = D.cascade(r.event || hopDoc?.event?.event_id);
    // the deep-linked evidence opens at once; the line fills in underneath when it arrives
    if (hopDoc && hopDoc.event) (await ev()).openSheet(hopDoc, { event: hopDoc.event, nodes: [], flat: [], method: hopDoc.math?.method }, null, false);
    c = await cp;
  }
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
  const order = () => L.lineOrder(c, choice, desk());
  let entries = order();
  const stations = entries.filter(e => L.isStation(e.n));
  const total = L.stopCount(c), shownMoved = entries.filter(e => e.depth < 3 && L.isMoved(e.n)).length;
  // header
  const meta = joinSep([`Began ${L.fmtDay(c.event.onset)}`, c.event.magnitude_x ? `${L.num(c.event.magnitude_x)}× its normal readers` : null, `day ${L.lineDays(c)}`, r.version ? `version ${r.version}, frozen` : L.STATUS[c.status], c.event.reconstructed ? 'reconstructed' : null]);
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
    const idx = L.isMoved(e.n) ? ++k : 0;
    const card = stopCard(c, e, idx, total, sc, lane);
    if (e.folded && e.folded.length) {
      const chips = h('div', { class: 'fork' }, e.folded.map(f => h('button', { class: 'sw', onclick: () => { choice[e.n.hop_id] = f.hop_id; rerender(); } }, h('span', { 'aria-hidden': 'true' }, '⑂'), `1 more branch: ${f.label}`)));
      card.append(chips);
    }
    const fs = flatStub(c, e.n.hop_id, `after ${e.n.label}`); if (fs) card.append(fs);
    if (hideMid && L.isMoved(e.n) && idx > 1 && idx < shownMoved) {
      const hidEls = () => card.querySelectorAll('.say,.facts,.odds,.eng');
      card.classList.add('hid'); hidEls().forEach(x => x.setAttribute('aria-hidden', 'true'));
      card.append(h('button', { class: 'btn sec sm rev', onclick: ev => { card.classList.remove('hid'); hidEls().forEach(x => x.removeAttribute('aria-hidden')); ev.currentTarget.remove(); } }, 'Reveal this stop'));
    }
    cards.push(card);
    // desktop: sibling branches below the same stop sit side by side (at most 3 shown, the rest behind "+N branches")
    const sibs = desk() && e.depth === 2 ? entries.filter(x => x.depth === 2 && x.n.parent_hop === e.n.parent_hop) : [];
    if (sibs.length > 1) {
      let row = list.querySelector(`[data-kids="${e.n.parent_hop}"]`);
      if (!row) { row = h('li', { class: 'kidrow', 'data-kids': e.n.parent_hop }, h('ol', { class: 'kids' })); list.append(row); }
      const ol = row.firstChild, n = ol.children.length;
      if (n >= 3) card.hidden = true;
      ol.append(card);
      if (n === 3) row.append(h('button', { class: 'sw', onclick: ev => { ol.querySelectorAll('[hidden]').forEach(x => { x.hidden = false; }); ev.currentTarget.remove(); } }, `+${sibs.length - 3} branches`));
    } else list.append(card);
    if (e.depth === 1 && !entries.some(x => x.depth === 1 && L.isStation(x.n) && entries.indexOf(x) > entries.indexOf(e)) && L.isStation(e.n)) {
      const root = flatStub(c, null, `after ${c.event.label}`); if (root) list.append(h('li', { style: 'list-style:none' }, root));
    }
  }
  if (!stations.length) { const root = flatStub(c, null, `after ${c.event.label}`); if (root) list.prepend(h('li', { style: 'list-style:none' }, root)); }
  const tail = [];
  if (d3.length) tail.push(h('details', { class: 'depth3' }, h('summary', { class: 'sw' }, `… if the previous step holds: ${L.plural(d3.length, 'more stop')}`), h('ol', null, d3.map(e => stopCard(c, e, L.isMoved(e.n) ? ++k : 0, total, sc, -1)))));
  if (c.held_back && (c.held_back.stops || c.held_back.flat)) tail.push(h('p', { class: 'held' }, `${L.plural(c.held_back.stops + c.held_back.flat, 'more tested path')} ${c.held_back.stops + c.held_back.flat === 1 ? 'is' : 'are'} not listed yet: ${c.held_back.reason}.`));
  for (const ri of c.route_ideas || []) tail.push(h('p', { class: 'idea' }, `Route idea, not measured: ${ri.text} (${ri.source}).`));
  tail.push(h('p', { class: 'lend' + (c.status === 'nowhere' ? ' nowhere' : '') }, L.lineEnd(c)));
  const den = c.denominators || {}, ctl = c.control?.stops;
  const denEl = h('div', { class: 'den' },
    h('p', null, h('b', null, `Tested ${L.plural(den.tested ?? 0, 'path')} on this line`), sep(), `${L.fmtInt(den.moved ?? 0)} moved`, sep(), `${L.fmtInt(den.measured ?? 0)} Measured`, L.flukeClause(den.expected_false_links, den.measured) ? [sep(), L.flukeClause(den.expected_false_links, den.measured)] : null),
    ctl ? h('p', { style: 'margin-top:6px' }, `The control ripple (${c.control.label || "a page that wasn't trending"}, same tests): ${ctl.measured} Measured, ${ctl.likely} Likely, ${ctl.watching} Watching, ${ctl.flat} flat.`) : null,
    (c.rivals || []).length ? h('p', { style: 'margin-top:6px' }, 'Also active this week: ', c.rivals.map(x => x.label).join(', '), '. A stop shared with it could be a common cause.') : null,
    h('p', { class: 'xs', style: 'margin-top:6px' }, `Method ${c.method || C.METHOD}`, c.ledger?.seq ? [sep(), `ledger entry ${L.fmtInt(c.ledger.seq)}`] : null, sep(), h('a', { class: 'lnk', href: '/ripples/methods/' }, 'How we test')));
  // replay scrubber: stops light as their onset day passes; 2.5 s end to end; any tap skips
  const dMax = L.lineDays(c), dMin = -3;
  const rng = h('input', { type: 'range', min: dMin, max: dMax, value: dMax, step: 1, 'aria-label': 'Replay: day since the shock', 'aria-valuetext': `day ${dMax} of ${dMax}` });
  const lbl = h('span', null, `Replay: day ${dMax}`);
  let playing = 0;
  const dayWord = d => { const r = Math.round(d); return r < 0 ? `${-r} ${-r === 1 ? 'day' : 'days'} before` : `day ${r}`; };
  const setDay = (d, counting) => {
    sc.setDay(d); const r = d == null ? dMax : Math.round(d); lbl.textContent = `Replay: ${dayWord(r)}`; rng.setAttribute('aria-valuetext', `${dayWord(r)} of ${dMax}`);
    shownEntries.forEach((e, i) => {
      const on = e.n.onset ? L.daysBetween(c.event.onset, e.n.onset) <= r : r >= dMax; tiles[i]?.style.setProperty('opacity', on ? '1' : '.35');
      // play also replays the flap count-up on the card as its lane lights (once per pass)
      if (counting && on && cards[i] && cards[i]._flap && !cards[i]._replayed) { cards[i]._replayed = true; countUp(cards[i]._flap[0], cards[i]._flap[1], quiet); }
    });
  };
  rng.addEventListener('input', () => { cancelAnimationFrame(playing); playing = 0; sc.showAll(); setDay(+rng.value); });
  const play = () => {
    sc.showAll(); const t0 = performance.now(); cards.forEach(cd => { cd._replayed = false; });
    const step = t => { const f = Math.min(1, (t - t0) / 2500), d = dMin + (dMax - dMin) * f; setDay(d, true); rng.value = Math.round(d); if (f < 1) playing = requestAnimationFrame(step); else { playing = 0; setDay(null); } };
    if (RM) { setDay(null); return; }
    playing = requestAnimationFrame(step);
  };
  addEventListener('pointerdown', () => { if (playing) { cancelAnimationFrame(playing); playing = 0; setDay(null); rng.value = dMax; } }, true);
  // the scrubber lives under the chart it drives (in the sticky block on phone), never 900 px below it
  const replay = h('div', { class: 'replay' }, h('button', { 'aria-label': 'Replay the line from the shock to today', onclick: e => { e.stopPropagation(); play(); } }, icon('play')), h('label', null, lbl, rng));
  // desktop By hop / By day toggle
  const seg = h('span', { class: 'seg dsk-only', role: 'group', 'aria-label': 'Spacing' },
    h('button', { 'aria-pressed': 'false', onclick: ev => { toggleMode('hop', ev); } }, 'By hop'), h('button', { 'aria-pressed': 'true', onclick: ev => { toggleMode('day', ev); } }, 'By day'));
  const toggleMode = (m, ev) => { [...seg.children].forEach(b => b.setAttribute('aria-pressed', String(b === ev.currentTarget))); sc.mode = m; sc.draw(); sc.showAll(); capTxt.textContent = m === 'hop' ? 'Each lane is one stop against its own normal, on one shared scale; lanes sit in the order the stops moved, 6 days either side of each onset.' : 'Each lane is one stop against its own normal, on one shared scale; x is days since the shock.'; };
  const cap = sc.fig.querySelector('figcaption');
  const capTxt = h('span', null, 'Each lane is one stop against its own normal, on one shared scale; x is days since the shock.');
  put(cap, capTxt, h('span', { class: 'sp' }), desk() ? seg : null);
  sc.fig.append(replay);
  // assemble
  const tsvg = S('svg', { class: 'tk-chart', role: 'img', 'aria-label': `${c.event.label}: attention against its own normal, peaking at ${L.num(c.event.magnitude_x)} times normal.` });
  const hasT = c.event.spark ? seedChart(tsvg, c.event.spark, quiet, L.num(c.event.magnitude_x) + '×') : false;
  const side = h('section', { class: 'ticket hero grain side', 'aria-labelledby': 'side-t' },
    h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, c.event.reconstructed ? 'From the archive, reconstructed' : 'The line'), h('span', { class: 'ver' }, 'v' + c.version)),
    h('div', { class: 'tk-body' }, h('div', { class: 'tk-row' }, h('span', { class: 'tk-emo', 'aria-hidden': 'true' }, em(c.event.emoji || '🌀')), h('h2', { class: 'tk-title', id: 'side-t' }, c.event.label)),
      h('p', { class: 'tk-sub' }, meta.map(x => (x.nodeType ? x.cloneNode(true) : x))), hasT ? tsvg : null),
    h('div', { class: 'tk-perf', 'aria-hidden': 'true' }, h('span', { class: 'notch l' }), h('span', { class: 'notch r' })),
    h('div', { class: 'tk-foot' }, h('p', { class: 'tk-meta' }, joinSep(L.lineMeta(c))), h('button', { class: 'btn', onclick: () => share(L.shareLine(c), 'line') }, icon('share'), 'Share this line')));
  const aside = h('aside', null, head, note,
    h('div', { class: 'dsk' }, side, denEl.cloneNode(true)));
  const body = h('div', null, h('div', { class: 'mob' }), stick, list, tail, h('div', { class: 'mob' }, denEl), shareBlock(c, r.version), followBlock(c), waitlist());
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
    if (desk() || !stations.length) { const n = sc.lanes.length; for (let i = 2; i < n; i++) setTimeout(() => sc.reveal(i, quiet), RM ? 0 : (i - 1) * Math.min(320, 2500 / n)); }
  });
  // shrink the sticky chart once the reader is into the stops (no layout animation)
  const sent = h('div', { 'aria-hidden': 'true' }); list.before(sent);
  new IntersectionObserver(([o]) => { if (desk()) return; const min = !o.isIntersecting && o.boundingClientRect.top < 0; if (min !== sc.fig.classList.contains('min')) { sc.fig.classList.toggle('min', min); sc.draw(); sc.showAll(); } }).observe(sent);
  // evidence: open in place (the stop URL is the deep link)
  main.addEventListener('click', ev => {
    const a = ev.target.closest('a[data-hop]'); if (!a || ev.metaKey || ev.ctrlKey || ev.shiftKey) return;
    ev.preventDefault(); evidence().then(m => m.openSheet(+a.dataset.hop, c, a, true));
  });
  if (isStop && hopDoc) {
    const m = await evidence(), sheetState = m.getSheet();
    if (sheetState && sheetState.hop === hopDoc.hop_id) {
      // fill in what needed the line (the flat siblings' sparklines) without repainting the sheet
      const fl = new Map((c.flat || []).map(f => [f.label, f]));
      sheetState.el.querySelectorAll('.sibs li').forEach(li => { const f = fl.get(li.firstChild?.textContent); const old = li.querySelector('svg'); if (f && old) old.replaceWith(spark(f.spark, 64, 20)); });
    } else m.openSheet(hopDoc, c, null, false);
  }
  addEventListener('popstate', () => { if (!/\/stop\/\d+\/$/.test(location.pathname)) evidence().then(m => m.closeSheet(false)); });
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
    h('section', { class: 'ticket hero', style: 'margin-top:14px' }, h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, c.event.reconstructed ? 'Ripple of the week, reconstructed' : 'Ripple of the week'), h('span', { class: 'ver' }, 'v' + c.version)),
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
