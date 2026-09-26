/* Ripple Map: the pond renderer (vertical slice).
   Pond.render(svg, payload, opts) draws one event's knock-on effects as a pond. Every element encodes a payload field by a stated
   rule (see ../../scratchpad comp P POND_SPEC.md, mirrored in SLICE.md): the stone is the shock, rings are time after the event,
   a thing's angle is its domain and its radius its lag, pad size and crest are the effect size, shape and fill are the tier.
   The story layer never changes what the water says: tiers come from the engine. */
(function (global) {
  const NS = 'http://www.w3.org/2000/svg';
  const el = (n, a = {}, parent, txt) => { const e = document.createElementNS(NS, n); for (const k in a) if (a[k] != null) e.setAttribute(k, a[k]); if (txt != null) e.textContent = txt; if (parent) parent.appendChild(e); return e; };
  const rad = a => (a - 90) * Math.PI / 180;
  const pol = (a, r) => [r * Math.cos(rad(a)), r * Math.sin(rad(a))];
  const f1 = n => Math.round(n * 10) / 10;
  function rng(seed) { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }

  const TIER = { measured: 'Measured', likely: 'Likely', contrast: 'Regional contrast passed', watching: 'Watching', untested: 'Pre-registered, untested', retracted: 'Retracted', pattern: 'World rule' };
  /* what each tier means for the drawing: the trust gradient. A lower tier may never look brighter than a higher one. */
  const DRAW = {
    measured: { crest: 1, glow: 1, fill: 'solid' },
    likely: { crest: .6, glow: .6, fill: 'half' },
    contrast: { crest: .6, glow: .6, fill: 'half' },   // passed a pre-registered regional contrast; the single-event tier is still open
    watching: { crest: .35, glow: .2, fill: 'dotted' },
    untested: { crest: 0, glow: 0, fill: 'dotted' },
    retracted: { crest: 0, glow: 0, fill: 'outline' }
  };

  /* geometry: rings are log-spaced in days */
  function makeScale(rings) {
    const pts = rings.map(r => [Math.log(r.days), r.r]);
    return function radius(days) {
      if (days <= 0) return Math.max(28, pts[0][1] + days * 12);
      const ld = Math.log(days);
      if (ld <= pts[0][0]) return 40 + (pts[0][1] - 40) * (ld / (pts[0][0] || 1));
      for (let i = 0; i < pts.length - 1; i++) if (ld <= pts[i + 1][0]) { const t = (ld - pts[i][0]) / (pts[i + 1][0] - pts[i][0]); return pts[i][1] + t * (pts[i + 1][1] - pts[i][1]); }
      return pts[pts.length - 1][1] + 24;
    };
  }

  /* glyphs */
  function lilyPad(g, x, y, r, tier) {
    const a1 = 90 + 26, a2 = 90 - 26;
    const p1 = pol(a1, r), p2 = pol(a2, r);
    const d = `M0,0 L${f1(p1[0])},${f1(p1[1])} A${r},${r} 0 1 0 ${f1(p2[0])},${f1(p2[1])} Z`;
    const toStone = Math.atan2(-y, -x) * 180 / Math.PI - 90;   // the notch faces the stone
    const pad = el('g', { class: 'pad ' + tier, transform: `translate(${f1(x)},${f1(y)}) rotate(${f1(toStone)})` }, g);
    el('path', { d, class: 'pad-body' }, pad);
    // veins: three short curves from the notch, and a soft highlight on the rim away from the stone
    const v = a => { const p = pol(a, r * .8), m = pol(a + 8, r * .45); return `M0,0 Q${f1(m[0])},${f1(m[1])} ${f1(p[0])},${f1(p[1])}`; };
    el('path', { d: v(215) + v(270) + v(325), class: 'pad-vein' }, pad);
    const h1 = pol(240, r * .72), h2 = pol(300, r * .72);
    el('path', { d: `M${f1(h1[0])},${f1(h1[1])} A${f1(r * .72)},${f1(r * .72)} 0 0 1 ${f1(h2[0])},${f1(h2[1])}`, class: 'pad-hi' }, pad);
    return pad;
  }
  function duck(g, x, y, s, ang) {
    const flip = Math.cos(rad(ang)) < 0 ? -1 : 1;
    const d = el('g', { class: 'duck', transform: `translate(${f1(x)},${f1(y)}) scale(${f1(s * flip)},${f1(s)})` }, g);
    el('path', { d: 'M-17,2 C-15,10 -5,12.5 6,10.5 C12.5,9.4 16.5,6.5 17.5,2 Z', class: 'duck-body' }, d);
    el('path', { d: 'M-17,2 L-22,-6 M9,2 C10,-3 9,-8 11,-11 C13,-15 20,-14 20,-9 C20,-6 18,-5 15,-5 C13,-5 12,-2 12,2 M20,-9 L26.5,-8.2', class: 'duck-line' }, d);
    el('circle', { cx: 16.5, cy: -10.5, r: 1, class: 'duck-eye' }, d);
    el('path', { d: 'M-23,3.5 Q-15,1.5 -7,3.5 T9,3.5 T25,3.5', class: 'duck-water' }, d);
    return d;
  }
  /* reeds: a bed of tapered leaves with one seed head; the honest null */
  function reeds(g, x, y, seed, ang) {
    const r = rng(seed), n = 5 + Math.floor(r() * 2);
    const bed = el('g', { class: 'grass', transform: `translate(${f1(x)},${f1(y)}) rotate(${f1(ang)})` }, g);
    el('circle', { cx: 0, cy: -8, r: 17, class: 'hit' }, bed);
    for (let i = 0; i < n; i++) {
      const bx = (i - (n - 1) / 2) * 4.2 + (r() - .5) * 2.5, h = 16 + r() * 16, lean = (r() - .5) * 14, w = 1.4 + r() * .8;
      const tipx = bx + lean, tipy = -h, c1x = bx + lean * .25, c1y = -h * .45;
      // a leaf: two quadratic edges meeting at the tip
      el('path', { d: `M${f1(bx - w)},6 Q${f1(c1x - w * .4)},${f1(c1y)} ${f1(tipx)},${f1(tipy)} Q${f1(c1x + w * .6)},${f1(c1y)} ${f1(bx + w)},6 Z`, class: 'leaf' }, bed);
      if (i === Math.floor(n / 2)) el('ellipse', { cx: f1(tipx), cy: f1(tipy - 3), rx: 1.6, ry: 4.2, class: 'seed', transform: `rotate(${f1(lean * .8)} ${f1(tipx)} ${f1(tipy - 3)})` }, bed);
    }
    el('path', { d: `M${f1(-n * 2.4)},7 Q0,4 ${f1(n * 2.4)},7`, class: 'reed-water' }, bed);
    return bed;
  }
  function boulder(g, x, y, r, seed) {
    const rr = rng(seed); let d = '';
    for (let i = 0; i < 9; i++) { const a = i * 40, rad_ = r * (0.82 + rr() * .3); const p = pol(a, rad_); d += (i ? 'L' : 'M') + f1(p[0]) + ',' + f1(p[1]); }
    const b = el('g', { class: 'boulder', transform: `translate(${f1(x)},${f1(y)})` }, g);
    el('path', { d: d + 'Z', class: 'boulder-body' }, b);
    el('path', { d: `M${-r * .45},${-r * .35} q${r * .3},${-r * .3} ${r * .7},${-r * .05}`, class: 'boulder-hi' }, b);
    return b;
  }
  function stone(g, x, y, r, cls) {
    const s = el('g', { class: 'stone ' + (cls || ''), transform: `translate(${f1(x)},${f1(y)})` }, g);
    el('ellipse', { cx: 0, cy: 0, rx: r, ry: r * .82, class: 'stone-body', transform: 'rotate(-18)' }, s);
    el('path', { d: `M${-r * .5},${-r * .25} q${r * .35},${-r * .35} ${r * .85},${-r * .12}`, class: 'stone-hi' }, s);
    return s;
  }
  /* an untested, pre-registered series: a small dotted float, no crest */
  function floatMarker(g, x, y, r) {
    const m = el('g', { class: 'float', transform: `translate(${f1(x)},${f1(y)})` }, g);
    el('circle', { cx: 0, cy: 0, r: r + 5, class: 'float-water' }, m);
    el('circle', { cx: 0, cy: 0, r, class: 'float-ring' }, m);
    el('circle', { cx: 0, cy: 0, r: 1.8, class: 'float-dot' }, m);
    return m;
  }

  /* label placement: try eight positions around the marker, keep the one with the least overlap and the most water under it */
  function makePlacer(vb, R0) {
    const boxes = [];
    const est = (txt, fs) => txt.length * fs * .56;
    function place(x, y, gap, lines, prefer, inward) {
      const w = Math.max(...lines.map(l => est(l.text, l.size))), h = lines.reduce((s, l) => s + l.size * 1.25, 0);
      const cands = [];
      const dirs = prefer === 'auto' || !prefer ? [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]] : { right: [[1, 0]], left: [[-1, 0]], below: [[0, 1]], above: [[0, -1]] }[prefer];
      dirs.forEach(([dx, dy]) => {
        const anchor = dx > 0 ? 'start' : dx < 0 ? 'end' : 'middle';
        const lx = x + dx * gap, ly = y + dy * (gap + (dy ? h * .55 : 0)) + (dy === 0 ? -h / 2 + lines[0].size : dy > 0 ? lines[0].size : -h + lines[0].size);
        const bx = anchor === 'start' ? lx : anchor === 'end' ? lx - w : lx - w / 2, by = ly - lines[0].size, bw = w, bh = h;
        let cost = 0;
        boxes.forEach(b => { const ox = Math.max(0, Math.min(bx + bw, b.x + b.w) - Math.max(bx, b.x)), oy = Math.max(0, Math.min(by + bh, b.y + b.h) - Math.max(by, b.y)); cost += ox * oy; });
        // keep inside the viewBox and, softly, inside the pond
        if (bx < vb[0] + 6 || bx + bw > vb[0] + vb[2] - 6 || by < vb[1] + 6 || by + bh > vb[1] + vb[3] - 6) cost += 1e5;
        const cx = bx + bw / 2, cy = by + bh / 2, rr = Math.hypot(cx, cy); if (rr > R0 + 10) cost += (rr - R0) * 40;
        // prefer outward from the stone
        const outward = (x * dx + y * dy) / (Math.hypot(x, y) || 1); cost -= outward * 12 * (inward ? -2.5 : 1);
        cands.push({ cost, lx, ly, anchor, box: { x: bx, y: by, w: bw, h: bh } });
      });
      cands.sort((a, b) => a.cost - b.cost);
      const best = cands[0]; boxes.push(best.box); return best;
    }
    function reserve(x, y, w, h) { boxes.push({ x: x - w / 2, y: y - h / 2, w, h }); }
    return { place, reserve };
  }

  /* the pond */
  function render(svg, P, opts = {}) {
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    const reduce = opts.reduceMotion ?? matchMedia('(prefers-reduced-motion: reduce)').matches;
    const compact = !!opts.compact, thumb = !!opts.thumb;
    const uid = 'p' + Math.random().toString(36).slice(2, 7);
    const R0 = opts.pondRadius || 425;
    const rings = P.rings || [{ days: 1, r: 105, label: 'Day 1' }, { days: 7, r: 185, label: 'Week 1' }, { days: 30, r: 265, label: 'Month 1' }, { days: 90, r: 345, label: 'Month 3' }];
    const radius = makeScale(rings);
    const doms = P.domains, N = doms.length, SW = 360 / N;
    const pos = (dom, days, off = 0) => { const a = dom * SW + off, r = radius(days); const [x, y] = pol(a, r); return { x, y, a, r }; };
    const vb = opts.viewBox || [-560, -480, 1120, 960];
    svg.setAttribute('viewBox', vb.join(' '));
    svg.classList.toggle('reduce', reduce); svg.classList.toggle('compact', compact); svg.classList.toggle('thumb', thumb);
    svg.classList.add('pond');
    // the timeline: the ring front reaches radius r at ringDelay(r). 'fast' is the owner's 1.6 s reveal; 'slow' reads in screenshots.
    const T = opts.timing === 'slow' ? [0.9, 1.5] : [0.25, 0.6];
    const ringDelay = r => T[0] + (r / R0) * T[1];
    const placer = makePlacer(vb, R0);
    const fs = compact ? { lbl: 42, tier: 30 } : { lbl: 15, tier: 12 };   // compact: 960-unit viewBox on a 390 px phone, so 42 units = 17 px

    /* defs */
    const defs = el('defs', {}, svg);
    const water = el('radialGradient', { id: uid + '-water', cx: '50%', cy: '50%', r: '65%' }, defs);
    el('stop', { offset: '0', 'stop-color': '#12484F' }, water); el('stop', { offset: '.5', 'stop-color': '#0B323B' }, water); el('stop', { offset: '1', 'stop-color': '#061C23' }, water);
    const moon = el('radialGradient', { id: uid + '-moon', cx: '72%', cy: '22%', r: '45%' }, defs);
    el('stop', { offset: '0', 'stop-color': '#BFEFE3', 'stop-opacity': '.16' }, moon); el('stop', { offset: '1', 'stop-color': '#BFEFE3', 'stop-opacity': '0' }, moon);
    const glow = el('filter', { id: uid + '-glow', x: '-30%', y: '-30%', width: '160%', height: '160%' }, defs);
    el('feGaussianBlur', { stdDeviation: '3.5', result: 'b' }, glow);
    const mg = el('feMerge', {}, glow); el('feMergeNode', { in: 'b' }, mg); el('feMergeNode', { in: 'SourceGraphic' }, mg);
    if (!reduce && !thumb) {
      const wob = el('filter', { id: uid + '-wobble', x: '-10%', y: '-10%', width: '120%', height: '120%' }, defs);
      el('feTurbulence', { type: 'fractalNoise', baseFrequency: '0.011', numOctaves: '2', seed: '7', result: 'n' }, wob);
      el('feDisplacementMap', { in: 'SourceGraphic', in2: 'n', scale: '7', xChannelSelector: 'R', yChannelSelector: 'G' }, wob);
    }
    const caus = el('filter', { id: uid + '-caustic', x: '0', y: '0', width: '100%', height: '100%' }, defs);
    el('feTurbulence', { type: 'fractalNoise', baseFrequency: '0.008 0.014', numOctaves: '3', seed: '3' }, caus);
    el('feColorMatrix', { values: '0 0 0 0 .55  0 0 0 0 .9  0 0 0 0 .85  0 0 0 .55 -.28' }, caus);

    /* shoreline: organic edge that juts inward to meet every far-shore marker at its true lag radius */
    const far = [...(P.effects || []).filter(e => e.far_shore), ...(P.shore || [])];
    const shorePts = [];
    for (let i = 0; i < 180; i++) {
      const a = i * 2; let r = R0 + 16 * Math.sin(a * Math.PI / 180 * 3 + 1.1) + 10 * Math.sin(a * Math.PI / 180 * 7 + 2.4) + 6 * Math.sin(a * Math.PI / 180 * 11);
      far.forEach(e => { const p = pos(e.domain, e.lag_days, e.offset || 0); let da = ((a - p.a) % 360 + 540) % 360 - 180; const dip = Math.exp(-Math.pow(da / 24, 2)); r -= (r - (p.r - 4)) * dip; });
      shorePts.push(pol(a, r));
    }
    let shore = ''; shorePts.forEach((p, i) => shore += (i ? 'L' : 'M') + f1(p[0]) + ',' + f1(p[1])); shore += 'Z';
    const clip = el('clipPath', { id: uid + '-clip' }, defs); el('path', { d: shore }, clip);

    const gW = el('g', { class: 'water', 'clip-path': `url(#${uid}-clip)` }, svg);
    el('rect', { x: vb[0], y: vb[1], width: vb[2], height: vb[3], fill: `url(#${uid}-water)` }, gW);
    if (!thumb) el('rect', { x: vb[0], y: vb[1], width: vb[2], height: vb[3], class: 'caustic', filter: `url(#${uid}-caustic)` }, gW);
    el('rect', { x: vb[0], y: vb[1], width: vb[2], height: vb[3], fill: `url(#${uid}-moon)` }, gW);
    el('path', { d: shore, class: 'shore-line' }, svg);

    /* sectors */
    const gS = el('g', { class: 'sectors', 'clip-path': `url(#${uid}-clip)` }, svg);
    for (let i = 0; i < N; i++) { const p = pol(i * SW - SW / 2, R0 + 40); el('line', { x1: 0, y1: 0, x2: f1(p[0]), y2: f1(p[1]), class: 'spoke' }, gS); }

    /* rival stones */
    const gRiv = el('g', { class: 'rivals', 'clip-path': `url(#${uid}-clip)` }, svg);
    (P.rivals || []).forEach(rv => {
      const r0 = rv.distance ?? radius(rv.days_before) * 0.9, ang = rv.angle ?? 300;
      const [x, y] = pol(ang, r0);
      const rr = 6 + 24 * (rv.magnitude ?? .5);
      const gr = el('g', { class: 'rival' }, gRiv);
      rings.slice(0, 3).forEach((rg, j) => el('circle', { cx: f1(x), cy: f1(y), r: f1(rg.r * .62 * (0.4 + (rv.magnitude ?? .5) * .6)), class: 'rival-ring', style: `animation-delay:${.1 + j * .35}s;transform-origin:${f1(x)}px ${f1(y)}px` }, gr));
      stone(gr, x, y, rr, 'rival');
      rv._pos = { x, y, r: rr };
      placer.reserve(x, y, rr * 2.4, rr * 2.2);
    });

    /* boulders: common shocks removed; the water behind them is stilled and rings bend round */
    const gB = el('g', { class: 'boulders', 'clip-path': `url(#${uid}-clip)` }, svg);
    (P.filtered || []).forEach(b => {
      const p = pos(b.domain, b.lag_days, b.offset || 0); const br = 14 + 18 * (b.magnitude ?? .6);
      b._pos = { ...p, br };
      const w = Math.atan2(br * 1.1, p.r) * 180 / Math.PI; const a1 = p.a - w, a2 = p.a + w;
      const q1 = pol(a1, p.r), q2 = pol(a2, p.r), q3 = pol(a2 + w * .6, R0 + 60), q4 = pol(a1 - w * .6, R0 + 60);
      el('path', { d: `M${f1(q1[0])},${f1(q1[1])} L${f1(q2[0])},${f1(q2[1])} L${f1(q3[0])},${f1(q3[1])} L${f1(q4[0])},${f1(q4[1])}Z`, class: 'wake' }, gB);
      placer.reserve(p.x, p.y, br * 2.4, br * 2.4);
    });

    /* rings */
    const gR = el('g', { class: 'rings', 'clip-path': `url(#${uid}-clip)`, filter: (reduce || thumb) ? null : `url(#${uid}-wobble)` }, svg);
    rings.forEach(r => {
      el('circle', { cx: 0, cy: 0, r: r.r, class: 'ring-glow', style: `animation-delay:${ringDelay(r.r).toFixed(2)}s` }, gR);
      el('circle', { cx: 0, cy: 0, r: r.r, class: 'ring', style: `animation-delay:${ringDelay(r.r).toFixed(2)}s` }, gR);
    });
    (P.filtered || []).forEach(b => {
      const p = b._pos; rings.forEach(r => { if (Math.abs(r.r - p.r) < p.br * 1.8 && r.r > p.r * .8) {
        const w = Math.atan2(p.br * 1.25, p.r) * 180 / Math.PI;
        [[p.a - w * 1.8, p.a - w * .9], [p.a + w * .9, p.a + w * 1.8]].forEach(([s, e]) => {
          const ps = pol(s, r.r), pm = pol((s + e) / 2, r.r + 10), pe = pol(e, r.r + 18);
          el('path', { d: `M${f1(ps[0])},${f1(ps[1])} Q${f1(pm[0])},${f1(pm[1])} ${f1(pe[0])},${f1(pe[1])}`, class: 'bend' }, gB);
        });
      } });
    });
    (P.filtered || []).forEach((b, i) => boulder(svg, b._pos.x, b._pos.y, b._pos.br, 90 + i));

    /* ring labels along a quiet angle */
    const gRL = el('g', { class: 'ring-labels' }, svg);
    const la = P.ringLabelAngle ?? -22;
    rings.forEach(r => { const [x, y] = pol(la, r.r); el('text', { x: f1(x), y: f1(y) + 4, class: 'ring-label', 'text-anchor': 'middle', style: `animation-delay:${(ringDelay(r.r) + .3).toFixed(2)}s` }, gRL, r.label); placer.reserve(x, y, 52, 14); });

    /* domain labels on the bank */
    const gD = el('g', { class: 'domain-labels' }, svg);
    doms.forEach((d, i) => {
      const c = i * SW, flip = c > 100 && c < 260, Rl = R0 + 34;
      const a1 = flip ? c + SW / 2 - 4 : c - SW / 2 + 4, a2 = flip ? c - SW / 2 + 4 : c + SW / 2 - 4;
      const p1 = pol(a1, Rl), p2 = pol(a2, Rl);
      el('path', { id: `${uid}-arc${i}`, d: `M${f1(p1[0])},${f1(p1[1])} A${Rl},${Rl} 0 0 ${flip ? 0 : 1} ${f1(p2[0])},${f1(p2[1])}`, fill: 'none' }, defs);
      const t = el('text', { class: 'domain-label' }, gD);
      el('textPath', { href: `#${uid}-arc${i}`, startOffset: '50%', 'text-anchor': 'middle' }, t, d);
      const dm = pol(c, Rl); placer.reserve(dm[0], dm[1], d.length * 9 + 20, 40);
    });

    /* the stone (reserve its label space first so nothing lands on it) */
    const mag = P.event.magnitude ?? 0.5;
    const sr = 10 + 30 * mag;
    placer.reserve(0, 0, sr * 2.6, sr * 2.4);
    if (!compact && P.event.label !== false) placer.reserve(sr + 14 + 70, 6, 150, 34);

    /* grass beds: things checked that stayed flat */
    const gG = el('g', { class: 'grass-beds' }, svg);
    const flatGroups = {};
    (P.flats || P.nulls || []).forEach(n => { const k = n.domain + ':' + (n.lag_days > 45 ? 'far' : n.lag_days > 10 ? 'mid' : 'near'); (flatGroups[k] = flatGroups[k] || []).push(n); });
    Object.values(flatGroups).forEach(list => list.forEach((n, j) => { n._off = n.offset ?? (list.length > 1 ? (j - (list.length - 1) / 2) * (SW / (list.length + 1)) * .9 : SW * .28); }));
    (P.flats || P.nulls || []).forEach((n, i) => {
      const p = pos(n.domain, n.lag_days, n._off || 0);
      const bed = reeds(gG, p.x, p.y, 100 + i, p.a);
      if (compact) bed.querySelector('.hit').setAttribute('r', 58);
      bed.setAttribute('tabindex', '0'); bed.setAttribute('role', 'button');
      bed.setAttribute('aria-label', `${n.name}: checked, stayed inside its normal range. The ripple stopped here.`);
      bed.dataset.name = n.name; bed.dataset.id = n.id || ('flat' + i);
      el('title', {}, bed, `The ripple stopped here: ${n.name}`);
      el('text', { x: 0, y: 20, class: 'grass-label', 'text-anchor': 'middle' }, bed, n.name);
      placer.reserve(p.x, p.y - 8, 34, 40);
    });

    /* untested pre-registered series: dotted floats, hover for the name */
    const gU = el('g', { class: 'untested' }, svg);
    const byDom = {};
    (P.untested || []).forEach(u => { const k = u.domain + ':' + u.lag_days; (byDom[k] = byDom[k] || []).push(u); });
    Object.values(byDom).forEach(list => list.forEach((u, j) => {
      const spread = (j - (list.length - 1) / 2) * (SW / (list.length + 1)) * .9;
      const p = pos(u.domain, u.lag_days, spread); u._pos = p;
      const m = floatMarker(gU, p.x, p.y, compact ? 14 : 8.5);
      m.setAttribute('tabindex', '0'); m.setAttribute('role', 'button'); m.dataset.id = u.id;
      m.setAttribute('aria-label', `${u.name}: pre-registered, window closed ${u.window_close}, test not yet run.`);
      el('title', {}, m, `${u.name}: pre-registered, untested`);
      el('circle', { cx: 0, cy: 0, r: compact ? 58 : 16, class: 'hit' }, m);
      placer.reserve(p.x, p.y, 20, 20);
    }));

    /* threads: chain only when mediation is supported; otherwise a fork from the stone (D-14 hard rule) */
    const gT = el('g', { class: 'threads', 'clip-path': `url(#${uid}-clip)` }, svg);
    const byId = {}; (P.effects || []).forEach(e => { byId[e.id] = e; e._pos = pos(e.domain, e.lag_days, e.offset || 0); });
    (P.effects || []).forEach(e => {
      const chain = e.parent && e.parent !== 'event' && e.mediation_supported && byId[e.parent];
      const a = chain ? byId[e.parent]._pos : { x: 0, y: 0 }, b = e._pos;
      const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2, cx = mx * (chain ? .8 : .45), cy = my * (chain ? .8 : .45);
      el('path', { d: `M${f1(a.x)},${f1(a.y)} Q${f1(cx)},${f1(cy)} ${f1(b.x)},${f1(b.y)}`, class: 'thread ' + (chain ? 'chain' : 'fork') + ' ' + e.tier, 'data-for': e.id, style: `animation-delay:${(ringDelay(b.r) - .15).toFixed(2)}s` }, gT);
    });

    /* far-shore markers for world rules: the bank juts in, foam breaks, a sand mark carries the rule. No pad: not this event's evidence. */
    const gSh = el('g', { class: 'shore-marks' }, svg);
    (P.shore || []).forEach(s => {
      const p = pos(s.domain, s.lag_days, s.offset || 0); s._pos = p;
      const wrap = el('g', { class: 'shore-mark pattern', tabindex: 0, role: 'button', 'data-id': s.id, 'aria-label': `${s.headline}. ${s.plain} A world rule about storms like this one, not evidence about this storm.`, style: `--d:${ringDelay(p.r).toFixed(2)}s` }, gSh);
      const w = Math.atan2(26, p.r) * 180 / Math.PI * 1.6;
      const foam = el('g', { class: 'foam' }, wrap);
      for (let k = 0; k < 3; k++) { const rr = p.r + 4 + k * 7, ww = w * (1.15 - k * .28); const a = pol(p.a - ww, rr), b = pol(p.a + ww, rr); el('path', { d: `M${f1(a[0])},${f1(a[1])} A${rr},${rr} 0 0 1 ${f1(b[0])},${f1(b[1])}`, style: `animation-delay:${(ringDelay(p.r) + .25 + k * .12).toFixed(2)}s` }, foam); }
      el('circle', { cx: f1(p.x), cy: f1(p.y), r: 26, class: 'hit' }, wrap);
      // the sand mark: a small cairn (three stacked stones) on the bank, the sign that others have reached here
      const c = el('g', { class: 'cairn', transform: `translate(${f1(p.x)},${f1(p.y)})` }, wrap);
      el('ellipse', { cx: 0, cy: 4, rx: 9, ry: 4 }, c); el('ellipse', { cx: 1, cy: -2, rx: 6.5, ry: 3.2 }, c); el('ellipse', { cx: -.5, cy: -7, rx: 4, ry: 2.4 }, c);
      const lab = el('g', { class: 'label', style: `animation-delay:${(ringDelay(p.r) + .35).toFixed(2)}s` }, wrap);
      if (!compact && !thumb) {
        const best = placer.place(p.x, p.y, 36, [{ text: s.num + ' ' + s.short, size: fs.lbl }, { text: `World rule across ${s.pattern.n_events} ${s.pattern.noun || 'events'}`, size: fs.tier }], s.label_side || 'auto', true);
        const t = el('text', { x: f1(best.lx), y: f1(best.ly), class: 'lbl', 'text-anchor': best.anchor }, lab);
        el('tspan', { class: 'lbl-num' }, t, s.num + ' '); el('tspan', {}, t, s.short);
        el('text', { x: f1(best.lx), y: f1(best.ly) + 16, class: 'lbl-tier', 'text-anchor': best.anchor }, lab, `World rule across ${s.pattern.n_events} ${s.pattern.noun || 'events'}`);
      } else if (compact && !thumb) {
        el('circle', { cx: f1(p.x + 22), cy: f1(p.y - 22), r: 26, class: 'badge' }, lab);
        el('text', { x: f1(p.x + 22), y: f1(p.y - 13), class: 'badge-num', 'text-anchor': 'middle' }, lab, 'R');
      }
      const open = () => opts.onSelect && opts.onSelect(s.id, 'shore');
      wrap.addEventListener('click', open);
      wrap.addEventListener('keydown', ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); } });
    });

    /* effects: pads and ducks */
    const gE = el('g', { class: 'effects' }, svg);
    const nodes = {};
    (P.effects || []).forEach((e, i) => {
      const p = e._pos, dr = DRAW[e.tier] || DRAW.watching;
      const size = 9 + 20 * (e.magnitude ?? 0);
      const wrap = el('g', { class: `effect ${e.tier} ${e.kind || 'pad'}${e.far_shore ? ' far' : ''}`, tabindex: 0, role: 'button', 'data-id': e.id, 'aria-label': `${e.headline}. ${e.plain} ${TIER[e.tier]}.`, style: `--d:${ringDelay(p.r).toFixed(2)}s` }, gE);
      const w = Math.atan2(size + 10, p.r) * 180 / Math.PI * 1.6;
      const c1 = pol(p.a - w, p.r), c2 = pol(p.a + w, p.r);
      const cd = `M${f1(c1[0])},${f1(c1[1])} A${f1(p.r)},${f1(p.r)} 0 0 1 ${f1(c2[0])},${f1(c2[1])}`;
      if (dr.crest > 0) {
        el('path', { d: cd, class: 'crest crest-glow', 'stroke-width': f1((4 + 12 * e.magnitude) * dr.glow), filter: `url(#${uid}-glow)`, style: `opacity:${.28 * dr.glow}` }, wrap);
        el('path', { d: cd, class: 'crest', 'stroke-width': f1((1.4 + 3.2 * e.magnitude) * dr.crest), style: `opacity:${.95 * dr.crest}` }, wrap);
      }
      if (e.tier === 'watching' || e.tier === 'contrast') el('circle', { cx: 0, cy: 0, r: p.r, class: 'watch-ring', style: `--r:${f1(p.r)}` }, wrap);
      el('circle', { cx: f1(p.x), cy: f1(p.y), r: compact ? Math.max(size + 14, 58) : size + 14, class: 'hit' }, wrap);   // 54 units = 22 px radius on a phone: a 44 px tap target
      if (e.kind === 'duck') duck(wrap, p.x, p.y, 0.8 + e.magnitude * .6, p.a); else lilyPad(wrap, p.x, p.y, size, e.tier);
      if (e.far_shore) {
        const foam = el('g', { class: 'foam' }, wrap);
        for (let k = 0; k < 3; k++) { const rr = p.r + size + 5 + k * 7, ww = w * (1.15 - k * .28); const a = pol(p.a - ww, rr), b = pol(p.a + ww, rr); el('path', { d: `M${f1(a[0])},${f1(a[1])} A${rr},${rr} 0 0 1 ${f1(b[0])},${f1(b[1])}`, style: `animation-delay:${(ringDelay(p.r) + .25 + k * .12).toFixed(2)}s` }, foam); }
      }
      const lab = el('g', { class: 'label', style: `animation-delay:${(ringDelay(p.r) + .35).toFixed(2)}s` }, wrap);
      if (compact && !thumb) {
        el('circle', { cx: f1(p.x + size * .7 + 10), cy: f1(p.y - size * .7 - 10), r: 26, class: 'badge' }, lab);
        el('text', { x: f1(p.x + size * .7 + 10), y: f1(p.y - size * .7 - 1), class: 'badge-num', 'text-anchor': 'middle' }, lab, String(i + 1));
      } else if (!thumb) {
        const sub = e.published && e.published.reason ? `${TIER[e.tier]}: ${e.published.reason}` : e.tier === 'contrast' ? 'Regional contrast passed, not yet Measured' : e.far_shore ? `${TIER[e.tier]}, reached the far shore` : e.tier === 'watching' && e.watch ? `Watching, resolves in ${e.watch.days_left} days` : (e.lag_days < 0 ? `${TIER[e.tier]}, ${-e.lag_days} days before` : TIER[e.tier]);
        const numL = e.num_label != null ? e.num_label : (e.num || '');
        const best = placer.place(p.x, p.y, size + 12, [{ text: (numL ? numL + ' ' : '') + e.short, size: fs.lbl }, { text: sub, size: fs.tier }], e.label_side || 'auto');
        const t = el('text', { x: f1(best.lx), y: f1(best.ly), class: 'lbl', 'text-anchor': best.anchor }, lab);
        if (numL) el('tspan', { class: 'lbl-num' }, t, numL + ' '); el('tspan', {}, t, e.short);
        el('text', { x: f1(best.lx), y: f1(best.ly) + 16, class: 'lbl-tier', 'text-anchor': best.anchor }, lab, sub);
      }
      nodes[e.id] = wrap;
      const open = () => opts.onSelect && opts.onSelect(e.id, 'effect');
      wrap.addEventListener('click', open);
      wrap.addEventListener('keydown', ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); } });
    });

    /* untested markers: click opens the honest card */
    gU.querySelectorAll('.float').forEach(m => {
      const open = () => opts.onSelect && opts.onSelect(m.dataset.id, 'untested');
      m.addEventListener('click', open); m.addEventListener('keydown', ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); } });
    });
    gG.querySelectorAll('.grass').forEach(g => {
      const open = () => opts.onSelect && opts.onSelect(g.dataset.id, 'flat');
      g.addEventListener('click', open); g.addEventListener('keydown', ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); } });
    });

    /* rival and boulder labels (placed after everything else) */
    if (!compact && !thumb) {
      (P.rivals || []).forEach(rv => {
        const p = rv._pos; const g = el('g', { class: 'rival-label' }, svg);
        const best = placer.place(p.x, p.y, p.r + 10, [{ text: rv.name, size: fs.lbl }, { text: `${rv.days_before} days earlier, rings overlap`, size: fs.tier }], 'auto');
        el('text', { x: f1(best.lx), y: f1(best.ly), class: 'lbl', 'text-anchor': best.anchor }, g, rv.name);
        el('text', { x: f1(best.lx), y: f1(best.ly) + 15, class: 'lbl-tier', 'text-anchor': best.anchor }, g, `${rv.days_before} days earlier, rings overlap`);
      });
      (P.filtered || []).forEach(b => {
        const p = b._pos; const g = el('g', { class: 'boulder-label' }, svg);
        const best = placer.place(p.x, p.y, p.br + 8, [{ text: b.name, size: fs.tier }, { text: 'filtered out, ripples bend around it', size: fs.tier }], 'auto');
        el('text', { x: f1(best.lx), y: f1(best.ly), class: 'lbl-tier strong', 'text-anchor': best.anchor }, g, b.name);
        el('text', { x: f1(best.lx), y: f1(best.ly) + 14, class: 'lbl-tier', 'text-anchor': best.anchor }, g, 'filtered out, ripples bend around it');
      });
    }

    /* the stone: the shock itself */
    const gSt = el('g', { class: 'shock', tabindex: 0, role: 'img', 'aria-label': `${P.event.name}, the shock.${P.event.magnitude == null ? ' Size not scored.' : ` Size ${Math.round(P.event.magnitude * 100)} of 100 on our scale.`}` }, svg);
    el('circle', { cx: 0, cy: 0, r: sr * 2.2, class: 'halo', filter: `url(#${uid}-glow)` }, gSt);
    el('circle', { cx: 0, cy: 0, r: sr * 1.4, class: 'splash' }, gSt);
    el('circle', { cx: 0, cy: 0, r: sr * .9, class: 'well' }, gSt);
    stone(gSt, 0, 0, sr, 'main');
    if (!compact && !thumb && P.event.label !== false) {
      const t = el('g', { class: 'shock-label' }, gSt);
      el('text', { x: sr + 14, y: -2, class: 'lbl' }, t, P.event.name);
      el('text', { x: sr + 14, y: 14, class: 'lbl-tier' }, t, P.event.sub || '');
    }

    return { nodes, radius, pos, ringDelay, sr };
  }

  global.Pond = { render, TIER };
})(window);
