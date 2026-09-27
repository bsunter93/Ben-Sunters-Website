/* Ripple Map explorer.
 * Data: public.rm_explorer() (story layer v2, 34_att_story_explorer.sql), falling back to data/explorer.json.
 * Every sentence shown here comes from the story layer; this file only lays it out. Tiers are the engine's.
 * Routes: #/  ·  #/s/<slug>  ·  #/o/<outcome>  ·  #/watching  ·  #/how
 */
(() => {
  'use strict';
  const SB_URL = 'https://kffkasnzqcddpystszch.supabase.co';
  const SB_KEY = 'sb_publishable_3UtNDc2vPbCIcG1t5K4YEQ_KUyTKucv';   // publishable (browser-safe) key
  const NS = 'http://www.w3.org/2000/svg';
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const RINGS = [{ d: 1, l: 'Day' }, { d: 7, l: 'Week' }, { d: 30, l: 'Month' }, { d: 91, l: 'Quarter' }];
  const TIER = {
    confirmed: { label: 'Confirmed', c: '#DCEBEF', css: 'var(--c-confirmed)' },
    likely: { label: 'Likely', c: '#A9D3DF', css: 'var(--c-likely)' },
    possible: { label: 'Possible', c: '#6F95A1', css: 'var(--c-possible)' },
    watch: { label: 'Too early', c: '#8A979D', css: 'var(--c-watch)' },
    none: { label: 'No sign', c: '#3A474E', css: 'var(--c-none)' },
  };
  const ORDER = ['confirmed', 'likely', 'possible', 'watch'];
  const STORY = { surprise: 'Surprise', absorbed: 'Absorbed', expected: 'Expected only' };   // story layer v2.1 (35_att_story_surprise.sql)
  const SYM = { up: '↑', down: '↓' };
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const svgEl = (n, a, p) => { const e = document.createElementNS(NS, n); for (const k in a) if (a[k] != null) e.setAttribute(k, a[k]); if (p) p.appendChild(e); return e; };
  const ls = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } } };

  let D = null, findMode = 'shock', query = '';
  const trail = [];

  /* ---------- data ---------- */
  async function load() {
    if (window.__RM_EXPLORER) { const j = window.__RM_EXPLORER; j._src = 'bundled'; return j; }   // offline previews
    const live = (async () => {
      const c = new AbortController(); const t = setTimeout(() => c.abort(), 3500);
      try {
        const r = await fetch(`${SB_URL}/rest/v1/rpc/rm_explorer`, { method: 'POST', signal: c.signal, credentials: 'omit',
          headers: { apikey: SB_KEY, 'Content-Type': 'application/json' }, body: '{}' });
        if (!r.ok) throw new Error(r.status); const j = await r.json(); if (!j || !j.shocks) throw new Error('empty'); j._src = 'live'; return j;
      } finally { clearTimeout(t); }
    })();
    try { return await live; } catch {
      const r = await fetch('data/explorer.json', { cache: 'no-cache' }); const j = await r.json(); j._src = 'snapshot'; return j;
    }
  }
  function ping(kind) {   // aggregate counts only (rm_event); never blocks
    try { fetch(`${SB_URL}/rest/v1/rpc/rm_event`, { method: 'POST', credentials: 'omit', keepalive: true, headers: { apikey: SB_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_kind: kind, p_src: 'explorer', p_client: null }) }).catch(() => {}); } catch { /* ignore */ }
  }

  /* ---------- helpers ---------- */
  const shock = slug => D.shocks.find(s => s.slug === slug);
  const outcome = key => D.outcomes[key];
  const reachRing = s => RINGS.filter(r => r.d <= Math.max(1, s.reach || 1)).slice(-1)[0] || RINGS[0];
  const rOf = (d, R0, R1) => { const lo = Math.log(0.5), hi = Math.log(91); const t = (Math.log(Math.max(d || 1, 0.5)) - lo) / (hi - lo); return R0 + (R1 - R0) * Math.min(1, Math.max(0, t)); };
  const moved = s => s.impacts.filter(i => i.tier === 'confirmed' || i.tier === 'likely');
  function titleHTML(t) {   // italicise only the surprising place a shock reached
    const m = t.match(/^(.*?\breached)\s(.+?)\.?$/);
    return m ? `${esc(m[1])} <em>${esc(m[2])}.</em>` : esc(t);
  }
  function tallyHTML(s) {
    const c = s.counts || {};
    return `<div class="tallyline">${ORDER.filter(k => c[k]).map(k => `<span><i class="dot" style="background:${TIER[k].css}"></i>${c[k]} ${TIER[k].label.toLowerCase()}</span>`).join('')}${c.none ? `<span><i class="dot" style="background:var(--c-none)"></i>${c.none} no sign</span>` : ''}</div>`;
  }
  function toast(msg) { let t = $('.toast'); if (!t) { t = document.createElement('div'); t.className = 'toast'; t.setAttribute('role', 'status'); document.body.appendChild(t); } t.textContent = msg; t.classList.add('on'); setTimeout(() => t.classList.remove('on'), 1800); }
  async function send(text, url) {
    ping('send');
    try { if (navigator.share) { await navigator.share({ title: 'Ripple Map', text, url }); return; } } catch { /* cancelled */ }
    try { await navigator.clipboard.writeText(`${text} ${url}`); toast('Link copied'); } catch { toast('Copy failed: ' + url); }
  }

  /* glyph for list rows: rings only to the reach */
  function glyph(s) {
    const g = document.createElementNS(NS, 'svg'); g.setAttribute('viewBox', '0 0 72 72'); g.classList.add('glyph'); g.setAttribute('aria-hidden', 'true');
    const edge = reachRing(s);
    RINGS.forEach(r => { if (r.d > edge.d) return; const last = r === edge;
      svgEl('circle', { cx: 36, cy: 36, r: rOf(r.d, 6, 33), fill: 'none', stroke: '#A9D3DF', 'stroke-width': last ? 1.4 : 0.7, opacity: last ? 0.95 : 0.45 }, g); });
    svgEl('circle', { cx: 36, cy: 36, r: 2.6, fill: '#E7ECEE' }, g);
    s.impacts.filter(i => i.tier !== 'watch').forEach((im, i, arr) => {
      const a = (-60 + i * (300 / Math.max(arr.length, 1))) * Math.PI / 180, r = rOf(Math.min(im.at || 1, s.reach || 1), 6, 33);
      svgEl('circle', { cx: 36 + r * Math.cos(a), cy: 36 + r * Math.sin(a), r: 2.4, fill: im.tier === 'possible' ? 'none' : TIER[im.tier].c, stroke: '#A9D3DF', 'stroke-width': im.tier === 'possible' ? 0.8 : 0 }, g);
    });
    return g;
  }

  /* ---------- views ---------- */
  function setNav(k) { document.querySelectorAll('nav.tabs a').forEach(a => a.toggleAttribute('aria-current', a.dataset.nav === k)); if (k) document.querySelectorAll('nav.tabs a').forEach(a => { if (a.dataset.nav === k) a.setAttribute('aria-current', 'page'); }); }
  function setCrumbs() {
    const c = $('#crumbs'); if (!trail.length) { c.innerHTML = ''; return; }
    c.innerHTML = `<a href="#/">Find</a>` + trail.map((t, i) => `<span class="sep">/</span>${i === trail.length - 1 ? `<span style="color:var(--text)">${esc(t.label)}</span>` : `<a href="${t.href}">${esc(t.label)}</a>`}`).join('');
  }
  function pushTrail(x) { const i = trail.findIndex(t => t.href === x.href); if (i >= 0) trail.splice(i + 1); else trail.push(x); if (trail.length > 6) trail.splice(0, trail.length - 6); setCrumbs(); }

  function viewFind() {
    trail.length = 0; setCrumbs(); setNav('find'); document.title = 'Ripple Map';
    $('#main').innerHTML = `
      <section class="hero fade">
        <div class="eyebrow">What did that event change?</div>
        <h1 style="margin-top:14px">Every shock sends out <em>ripples.</em><br>Pick one to follow.</h1>
        <p class="lede">Start from something that happened, or from something that changed. We trace what moved, how far it travelled, and how sure we are.</p>
        <label class="search"><svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><circle cx="9" cy="9" r="6"/><path d="M13.5 13.5 18 18"/></svg>
          <input id="q" type="search" placeholder="Try “hurricane”, “electricity”, “AI”…" value="${esc(query)}" aria-label="Search shocks and outcomes" autocomplete="off"></label>
        <div class="modes" role="group" aria-label="Start from">
          <button data-mode="shock" aria-pressed="${findMode === 'shock'}">Start from a shock</button>
          <button data-mode="outcome" aria-pressed="${findMode === 'outcome'}">Start from what changed</button>
        </div>
        <p class="hint" id="hint"></p>
        <div id="list"></div>
      </section>`;
    $('#q').addEventListener('input', e => { query = e.target.value; renderList(); });
    document.querySelectorAll('[data-mode]').forEach(b => b.onclick = () => { findMode = b.dataset.mode; document.querySelectorAll('[data-mode]').forEach(x => x.setAttribute('aria-pressed', x === b)); renderList(); });
    renderList();
  }
  function renderList() {
    const q = query.trim().toLowerCase(), L = $('#list');
    if (findMode === 'shock') {
      $('#hint').textContent = 'Shocks with results first. The rings show how far each one travelled.';
      const hit = s => !q || [s.name, s.kind, s.where, s.plural, ...s.impacts.map(i => i.name)].join(' ').toLowerCase().includes(q);
      const main = D.shocks.filter(s => s.confidence !== 'watch' && hit(s)), later = D.shocks.filter(s => s.confidence === 'watch' && hit(s));
      L.innerHTML = `<div class="list">${main.map(s => `
        <a class="row" href="#/s/${encodeURIComponent(s.slug)}" data-slug="${esc(s.slug)}"><span class="g"></span>
          <div><div class="name">${esc(s.name)}</div><div class="meta">${esc(s.kind)} · ${esc(s.when)}${s.where ? ' · ' + esc(s.where) : ''} · reached ${reachRing(s).l.toLowerCase()}</div>
          <div class="one">${esc(s.title)}</div>${tallyHTML(s)}</div><span class="go" aria-hidden="true">→</span></a>`).join('')}
        ${later.length ? `<details class="more"${q ? ' open' : ''}><summary>Still unfolding: ${later.length} shock${later.length > 1 ? 's' : ''} waiting for data <span>show</span></summary>
          <div class="compact">${later.map(s => `<a href="#/s/${encodeURIComponent(s.slug)}">${esc(s.name)} <span class="eyebrow" style="letter-spacing:.06em">${esc(s.when)}</span></a>`).join('')}</div></details>` : ''}</div>`;
      L.querySelectorAll('.row').forEach(r => r.querySelector('.g').replaceWith(glyph(shock(r.dataset.slug))));
      if (!main.length && !later.length) L.innerHTML = `<p class="hint" style="padding:18px 4px">Nothing traced for that yet.</p>`;
    } else {
      $('#hint').textContent = 'Things that changed, and the shocks we’ve traced to them.';
      const items = Object.values(D.outcomes).filter(o => !q || o.name.toLowerCase().includes(q)).sort((a, b) => (b.n_moved || 0) - (a.n_moved || 0));
      L.innerHTML = `<div class="list">${items.map(o => `
        <a class="row" href="#/o/${encodeURIComponent(o.key)}" data-key="${esc(o.key)}"><span class="g"></span>
          <div><div class="name">${esc(o.name)}</div><div class="meta">${o.up.length} upstream · ${o.down.length} downstream lead${o.down.length === 1 ? '' : 's'}</div><div class="one">${esc(o.synth)}</div></div>
          <span class="go" aria-hidden="true">→</span></a>`).join('')}</div>`;
      L.querySelectorAll('.row').forEach(r => r.querySelector('.g').replaceWith(outGlyph(outcome(r.dataset.key))));
      if (!items.length) L.innerHTML = `<p class="hint" style="padding:18px 4px">Nothing traced for that yet.</p>`;
    }
  }
  function outGlyph(o) {
    const g = document.createElementNS(NS, 'svg'); g.setAttribute('viewBox', '0 0 72 72'); g.classList.add('glyph'); g.setAttribute('aria-hidden', 'true');
    const n = Math.max(1, o.up.length);
    o.up.forEach((u, i) => { const y = n > 1 ? 14 + i * (44 / (n - 1)) : 36;
      svgEl('path', { d: `M8 ${y} C 36 ${y}, 40 36, 60 36`, fill: 'none', stroke: '#A9D3DF', 'stroke-width': u.tier === 'confirmed' ? 1.4 : 0.8, 'stroke-dasharray': (u.tier === 'possible' || u.tier === 'watch') ? '2 3' : null, opacity: 0.8 }, g); });
    svgEl('circle', { cx: 62, cy: 36, r: 3.2, fill: '#E7ECEE' }, g);
    return g;
  }

  /* ---------- the pond: a stone dropped in dark water, drawn on canvas ----------
   * Distance from the centre is time (day → quarter). The wave travels as far as the shock's reach, then dies out.
   * The surface is a small height field (ambient swell + the wave packet + marker ripples), lit by its slope and upscaled;
   * markers and their labels are DOM buttons laid over it, so they stay crisp, focusable and clickable. */
  const WORD = { up: 'rose', down: 'fell', moved: 'moved', flat: 'moved' };
  const SPAN = { Day: 'a day', Week: 'a week', Month: 'a month', Quarter: 'three months' };
  const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
  let pondCtl = null;
  const POND_T = [0.22, 0.48, 0.74, 1];   // day, week, month, quarter sit evenly along the radius, like the scrubber under it
  function rPond(d, R1) {
    if (d <= RINGS[0].d) return R1 * POND_T[0] * Math.max(0, d) / RINGS[0].d;
    for (let k = 1; k < RINGS.length; k++) if (d <= RINGS[k].d) {
      const f = Math.log(d / RINGS[k - 1].d) / Math.log(RINGS[k].d / RINGS[k - 1].d); return R1 * (POND_T[k - 1] + (POND_T[k] - POND_T[k - 1]) * f);
    }
    return R1;
  }

  function Pond(s, host, ui) {
    const TILT = 0.5, PERS = 0.2, T_IMP = 0.5, DPR = Math.min(2, window.devicePixelRatio || 1), TAU = Math.PI * 2;
    const mv = moved(s), edge = reachRing(s);
    const reachD = mv.length ? Math.max(s.reach || 1, ...mv.map(m => m.at || 1)) : 0;
    const marks = [
      ...s.impacts.map((im, i) => { const m = mv.includes(im);
        return { i, im, name: im.short || im.name, tier: im.tier, moves: m, d: m ? Math.min(im.at || 1, reachD) : (im.at || 91),
          word: m ? (WORD[im.dir] || 'moved') : im.tier === 'possible' ? 'maybe' : 'too early', dir: m ? im.dir : '' }; }),
      ...(s.none || []).map(nm => ({ i: -1, name: nm, tier: 'none', moves: false, d: 91, word: 'still', dir: '' })),
    ];
    const n = marks.length, stepA = TAU / Math.max(1, n), th0 = stepA * (Math.floor(n / 2) + 0.5);   // evenly spread, clear of the time axis
        // angle slots only spread things out for legibility: the things that moved take evenly spaced slots, the rest fill in
    const nm = marks.filter(m => m.moves).length, slots = [], free = [];
    marks.forEach((m, k) => { m.k = k; });
    for (let j = 0; j < nm; j++) slots.push(Math.round(j * n / nm));
    for (let q = 0; q < n; q++) if (!slots.includes(q)) free.push(q);
    let a = 0, b = 0;
    marks.forEach(m => { const q = m.moves ? slots[a++] : free[b++]; m.th = th0 + q * stepA + (m.tier === 'none' ? (((m.k * 0.377) % 1) - 0.5) * stepA * 0.5 : 0); });

    const edgeTxt = SPAN[edge.l];
    const summary = mv.length
      ? `${s.name}: a stone dropped in still water. The ripple reached about ${edgeTxt}, then died out. ${mv.map(m => `${m.short || m.name} ${WORD[m.dir] || 'moved'}`).join('; ')}.`
      : `${s.name}: a stone dropped in still water. The water absorbed it: no measured ripple yet.`;
    host.innerHTML = `<canvas role="img" aria-label="${esc(summary)}"></canvas><div class="marks"></div>`;
    const cv = host.querySelector('canvas'), ctx = cv.getContext('2d'), layer = host.querySelector('.marks');
    const off = document.createElement('canvas'), octx = off.getContext('2d');

    marks.forEach(m => {
      const b = document.createElement('button'); b.type = 'button';
      b.className = `mk t-${m.tier}${m.moves ? ' mover' : ''}`;
      b.setAttribute('aria-label', `${m.im ? m.im.name : m.name}: ${m.word}${m.im ? ', ' + TIER[m.tier].label.toLowerCase() : ''}`);
      b.innerHTML = `<i class="buoy" aria-hidden="true"></i><span class="lb" aria-hidden="true">${esc(m.name)}<em class="${esc(m.dir)}">${esc(m.word)}</em></span>`;
      b.onclick = () => (m.i >= 0 ? ui.pick(m.i) : ui.none());
      layer.appendChild(b); m.el = b; m.buoy = b.firstChild; m.lb = b.lastChild;
    });

    /* ---- geometry (CSS px) ---- */
    let W = 0, H = 0, cx = 0, cy = 0, R0 = 0, R1 = 0, LAM = 16, reachR = 0, Rend = 0, bw = 0, bh = 0, sc = 3;
    let RR, PX, PZ, PH1, PH2, PH3, PATCH, BASE, ALPHA, HGT, img, ticks = [], stopsR = [];
    function layout() {
      const w = Math.round(host.clientWidth); if (!w || w === W) return false;
      W = w; H = Math.round(W * (W < 520 ? 0.8 : 0.68)); host.style.height = H + 'px';
      cv.width = Math.round(W * DPR); cv.height = Math.round(H * DPR); cv.style.width = W + 'px'; cv.style.height = H + 'px';
      cx = W / 2; R1 = Math.min(W * 0.435, (H - 64) / (TILT * (1 / (1 + PERS) + 1 / (1 - PERS)))); R0 = R1 * 0.1;
      const far = R1 * TILT / (1 + PERS), near = R1 * TILT / (1 - PERS); cy = (H - far - near) / 2 + far;
      LAM = Math.max(16, R1 * 0.1);
      reachR = mv.length ? rPond(reachD, R1) : R0 * 0.8; Rend = reachR + Math.max(LAM * 1.6, R1 * 0.12);
      stopsR = RINGS.map(r => rPond(r.d, R1));
      // the small surface buffer
      sc = W > 480 ? 3 : 2.5; bw = Math.ceil(W / sc); bh = Math.ceil(H / sc);
      off.width = bw; off.height = bh; img = octx.createImageData(bw, bh);
      const N = bw * bh; RR = new Float32Array(N); PX = new Float32Array(N); PZ = new Float32Array(N); PH1 = new Float32Array(N); PH2 = new Float32Array(N); PH3 = new Float32Array(N); PATCH = new Float32Array(N);
      BASE = new Float32Array(N * 3); ALPHA = new Float32Array(N); HGT = new Float32Array(N);
      for (let y = 0; y < bh; y++) for (let x = 0; x < bw; x++) {
        const i = y * bw + x, sx = (x + 0.5) * sc, sy = (y + 0.5) * sc, v = (sy - cy) / TILT, pz = v / (1 + PERS * v / R1), px = (sx - cx) * (1 - PERS * pz / R1);
        RR[i] = Math.hypot(px, pz);
        PX[i] = px; PZ[i] = pz;   // plane coordinates under this pixel (the water is seen at an angle)
        PH1[i] = 0.11 * px + 0.8 * Math.sin(0.05 * pz + 1.3);
        PH2[i] = 0.09 * (0.55 * px + 0.83 * pz) + 0.7 * Math.sin(0.06 * px);
        PH3[i] = 0.14 * (-0.8 * px + 0.6 * pz) + 0.5 * Math.sin(0.07 * pz - 0.04 * px);
        PATCH[i] = 0.3 + 0.7 * (0.5 + 0.5 * Math.sin(0.012 * px + 0.9) * Math.sin(0.017 * pz - 0.4));
        const fy = sy / H, far = 1 - fy;   // the far water holds a little sky
        const e = RR[i] / (R1 * 1.25), fall = 1 - 0.35 * smooth(0.6, 1.2, e);
        BASE[i * 3] = (9 + 9 * far) * fall; BASE[i * 3 + 1] = (14 + 15 * far) * fall; BASE[i * 3 + 2] = (17 + 18 * far) * fall;
        const edgeD = Math.min(sx, W - sx, sy, H - sy);   // no box: the water thins out towards every edge
        ALPHA[i] = 255 * smooth(0, W * 0.14, edgeD) * (1 - smooth(1.0, 1.45, e * 1.25));
      }
      ticks = RINGS.map((r, k) => ({ l: r.l.toUpperCase(), x: cx + stopsR[k], edge: r === edge && mv.length > 0 }));
      placeMarks();
      return true;
    }
    const proj = (x, z) => { const f = 1 / (1 - PERS * z / R1); return [cx + x * f, cy + z * TILT * f]; };
    function placeMarks() {
      const boxes = [];
      ctx.font = '500 9.5px "Geist Mono", ui-monospace, monospace';
      let prev = -1e9;
      ticks.forEach(t => {   // time labels sit under the axis; one that would touch its neighbour steps above it
        t.w = ctx.measureText(t.l).width + t.l.length * 1.2; t.lx = Math.min(t.x - t.w / 2, W - t.w - 4);
        t.up = t.lx < prev + 6 && !ticks[ticks.indexOf(t) - 1]?.up; t.ly = t.up ? cy - 19 : cy + 8; if (!t.up) prev = t.lx + t.w;
        boxes.push({ x: t.lx - 3, y: t.ly - 2, w: t.w + 6, h: 14 });
      });
      const lo = Math.max(Rend + LAM * 0.5, R1 * 0.55), hi = R1 * 1.08;
      marks.forEach(m => {
        // no-sign markers float out in the calm water beyond the reach, scattered (their distance means nothing)
        m.r = m.tier === 'none' ? lo + (hi - lo) * ((0.31 + m.k * 0.618) % 1) : Math.min(rPond(m.d, R1), R1 * 1.02);
        m.px = m.r * Math.cos(m.th); m.pz = m.r * Math.sin(m.th); [m.x, m.y] = proj(m.px, m.pz);
        m.el.style.left = m.x.toFixed(1) + 'px'; m.el.style.top = m.y.toFixed(1) + 'px';
        const bb = { x: m.x - 7, y: m.y - 7, w: 14, h: 14 }; boxes.push(bb);
        ticks.forEach(t => { if (bb.x < t.lx + t.w && bb.x + bb.w > t.lx && bb.y < t.ly + 11 && bb.y + bb.h > t.ly) t.hide = true; });   // a buoy sitting on a time label wins
      });
      const hit = (a) => a.x < 2 || a.y < 2 || a.x + a.w > W - 2 || a.y + a.h > H - 2 || boxes.some(b => a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y);
      const order = marks.slice().sort((a, b) => (b.moves - a.moves) || ((b.tier !== 'none') - (a.tier !== 'none')) || a.k - b.k);
      order.forEach(m => {
        if (m.tier === 'none') { m.lb.hidden = true; return; }   // still water stays quiet: no-sign names live in the list below
        m.lb.hidden = false; const w = m.lb.offsetWidth, h = m.lb.offsetHeight, out = Math.cos(m.th) >= 0;
        const c = { r: [11, -h / 2], l: [-11 - w, -h / 2], b: [-w / 2, 9], t: [-w / 2, -9 - h], tr: [6, -8 - h], tl: [-6 - w, -8 - h], br: [6, 8], bl: [-6 - w, 8] };
        const lo2 = Math.sin(m.th) > 0, pref = (out ? ['r', 'l'] : ['l', 'r']).concat(lo2 ? ['b', 't'] : ['t', 'b'],
          out ? (lo2 ? ['br', 'tr', 'bl', 'tl'] : ['tr', 'br', 'tl', 'bl']) : (lo2 ? ['bl', 'tl', 'br', 'tr'] : ['tl', 'bl', 'tr', 'br']));
        let pick = pref.find(k => !hit({ x: m.x + c[k][0], y: m.y + c[k][1], w, h }));
        if (!pick && m.tier !== 'none') pick = pref.find(k => { const a = { x: m.x + c[k][0], y: m.y + c[k][1], w, h }; return a.x >= 0 && a.x + a.w <= W; }) || pref[0];
        if (!pick) { m.lb.hidden = true; return; }
        m.lb.style.left = c[pick][0] + 'px'; m.lb.style.top = c[pick][1] + 'px';
        boxes.push({ x: m.x + c[pick][0] - 3, y: m.y + c[pick][1] - 2, w: w + 6, h: h + 4 });
      });
    }

    /* ---- the wave ---- */
    const amp = r => (1 / Math.sqrt(1 + r / (R1 * 0.16))) * (1 - smooth(reachR, Rend, r)) * smooth(0, LAM * 0.8, r);
    let LUT = new Float32Array(1), lutN = 0;
    function buildLUT(front, A, ph, t, still) {
      lutN = Math.ceil(R1 * 1.5) + 2; if (LUT.length < lutN) LUT = new Float32Array(lutN);
      const splashT = t - T_IMP, resid = still ? 0 : 0.07 * smooth(0, 1.5, t - T_IMP);
      for (let r = 0; r < lutN; r++) {
        let h = 0;
        if (still) {   // reduced motion: the settled record of how far it went
          h = amp(r) * Math.cos(TAU * r / (LAM * 1.3)) * smooth(LAM * 0.4, LAM * 1.4, r) * (0.15 + 0.35 * r / Math.max(1, reachR));
        }
        if (A > 0.002) {
          const d = front - r;   // distance behind the leading edge
          if (d > -LAM && d < LAM * 5) h += A * smooth(-0.6 * LAM, 0.3 * LAM, d) * Math.exp(-Math.max(d, 0) / (1.05 * LAM)) * Math.cos(TAU * d / LAM + ph);
        }
        if (splashT > 0 && splashT < 1.2) {   // the plunge: a small crater that springs back
          const g = Math.exp(-(r * r) / (LAM * LAM * 0.35));
          h += g * (-1.6 * Math.exp(-splashT / 0.16) + 0.7 * Math.sin(splashT * 14) * Math.exp(-splashT / 0.3));
        }
        if (resid > 0 && r < reachR) h += resid * (1 - smooth(reachR * 0.55, reachR, r)) * Math.sin(TAU * r / (LAM * 1.7) - t * 1.3) * Math.exp(-r / (R1 * 0.5));
        LUT[r] = h;
      }
    }
    const rips = [];
    function surface(t, front, A, ph, still) {
      buildLUT(front, A, ph, t, still);
      const N = bw * bh, a1 = 0.9 * t * 0.35, a2 = 0.6 * t * 0.35, a3 = 1.3 * t * 0.35, amb = 0.06;
      for (let i = 0; i < N; i++) {
        const r = RR[i], j = r | 0, f = r - j;
        const w = j + 1 < lutN ? LUT[j] + (LUT[j + 1] - LUT[j]) * f : 0;
        HGT[i] = w + amb * PATCH[i] * (Math.sin(PH1[i] + a1) + Math.sin(PH2[i] - a2) + 0.6 * Math.sin(PH3[i] + a3));
      }
      for (let q = rips.length - 1; q >= 0; q--) {   // each touched marker sends out its own small ring
        const p = rips[q], age = t - p.t0, ra = age * LAM * 3.2, a = 0.55 * Math.exp(-age / 0.9);
        if (a < 0.01) { rips.splice(q, 1); continue; }
        const l2 = LAM * 0.55, ext = ra + l2 * 2;
        const [ax, ay] = proj(p.px - ext, p.pz - ext), [bx, by] = proj(p.px + ext, p.pz + ext), [ex] = proj(p.px - ext, p.pz + ext), [fx] = proj(p.px + ext, p.pz - ext);
        const x0 = Math.max(0, (Math.min(ax, ex) / sc) | 0), x1 = Math.min(bw - 1, Math.ceil(Math.max(bx, fx) / sc));
        const y0 = Math.max(0, (ay / sc) | 0), y1 = Math.min(bh - 1, Math.ceil(by / sc));
        for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
          const i = y * bw + x, d = ra - Math.hypot(PX[i] - p.px, PZ[i] - p.pz);
          if (d > -l2 && d < l2 * 3) HGT[i] += a * smooth(-l2, 0.3 * l2, d) * Math.exp(-Math.max(d, 0) / l2) * Math.cos(TAU * d / l2);
        }
      }
      // light the slope: light from the far side, low over the water
      const D = img.data, G = 0.95 * (3 / sc);
      for (let y = 0; y < bh; y++) {
        const ym = y > 0 ? -bw : 0, yp = y < bh - 1 ? bw : 0;
        for (let x = 0; x < bw; x++) {
          const i = y * bw + x, hx = HGT[x < bw - 1 ? i + 1 : i] - HGT[x > 0 ? i - 1 : i], hy = HGT[i + yp] - HGT[i + ym];
          const v = (0.42 * hx + 0.9 * hy) * G, h = HGT[i];
          const lit = v > 0 ? Math.min(1, v * 0.55 + v * v * 0.9) : 0, dk = v < 0 ? Math.min(0.75, -v * 0.7) : 0;
          const lift = h > 0 ? Math.min(0.12, h * 0.07) : 0;
          const k = i * 3, o = i * 4, br = BASE[k], bg = BASE[k + 1], bb = BASE[k + 2], m = lit * 0.82 + lift;
          D[o] = br + (169 - br) * m - br * dk; D[o + 1] = bg + (211 - bg) * m - bg * dk; D[o + 2] = bb + (223 - bb) * m - bb * dk; D[o + 3] = ALPHA[i];
        }
      }
      octx.putImageData(img, 0, 0);
    }

    /* ---- state ---- */
    let mode = reduce ? 'still' : 'anim', simT = 0, last = 0, raf = 0, vis = true, dragging = false, frames = 0;
    let scrubR = 0, shownR = 0, front = 0, settled = false;
    const TRAVEL = () => 1.1 + 2.7 * Math.min(1, Rend / R1);
    const U = [0, 0.125, 0.375, 0.625, 0.875, 1];
    const RV = () => [0, ...stopsR, R1 * 1.1];
    const uToR = u => { const rv = RV(); for (let k = 1; k < U.length; k++) if (u <= U[k]) return rv[k - 1] + (rv[k] - rv[k - 1]) * (u - U[k - 1]) / (U[k] - U[k - 1]); return rv[5]; };
    const rToU = r => { const rv = RV(); for (let k = 1; k < rv.length; k++) if (r <= rv[k]) return U[k - 1] + (U[k] - U[k - 1]) * (r - rv[k - 1]) / (rv[k] - rv[k - 1]); return 1; };

    function frontNow() {
      if (mode === 'scrub') return shownR;
      if (mode === 'still') return Rend;
      const u = (simT - T_IMP) / TRAVEL(); if (u <= 0) return 0; if (u >= 1) { settled = true; return Rend + 1; }
      return Rend * (1 - Math.pow(1 - u, 1.8));
    }
    function draw() {
      if (!W) return;
      front = frontNow();
      const live = mode === 'scrub' || (mode === 'anim' && !settled);
      const A = live ? amp(front) : 0, ph = reduce ? 0 : -simT * 2.4;
      surface(reduce ? 4 : simT, front, A, ph, mode === 'still');
      ctx.setTransform(DPR, 0, 0, DPR, 0, 0); ctx.clearRect(0, 0, W, H);
      ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(off, 0, 0, bw * sc, bh * sc);
      // the stone, falling, then the point it went in
      if (mode === 'anim' && simT < T_IMP) {
        const p = simT / T_IMP;
        ctx.fillStyle = `rgba(0,0,0,${0.35 * p})`; ctx.beginPath(); ctx.ellipse(cx, cy, 5 + 4 * (1 - p), (5 + 4 * (1 - p)) * TILT, 0, 0, TAU); ctx.fill();
        ctx.fillStyle = `rgba(231,236,238,${0.3 + 0.7 * p})`; ctx.beginPath(); ctx.arc(cx, cy - 40 * (1 - p) * (1 - p), 2.2 + 2.6 * (1 - p), 0, TAU); ctx.fill();
      } else {
        ctx.fillStyle = 'rgba(231,236,238,.55)'; ctx.beginPath(); ctx.arc(cx, cy, 1.6, 0, TAU); ctx.fill();
      }
      // time along one radius only: faint, brightening as the wave passes
      ctx.font = '500 9.5px "Geist Mono", ui-monospace, monospace'; ctx.textBaseline = 'top';
      if ('letterSpacing' in ctx) ctx.letterSpacing = '1.2px';
      ticks.forEach((t, k) => {
        const near = A > 0.02 ? Math.max(0, 1 - Math.abs(front - stopsR[k]) / (LAM * 2.5)) : 0;
        const done = (mode !== 'scrub' && (settled || mode === 'still')) && t.edge;
        const al = Math.min(0.9, 0.26 + 0.6 * near + (done ? 0.34 : 0));
        ctx.fillStyle = t.edge && (done || near > 0) ? `rgba(169,211,223,${al})` : `rgba(163,176,182,${al})`;
        ctx.fillRect(Math.round(t.x), cy - 3, 1, 6);
        if (!t.hide) ctx.fillText(t.l, t.lx, t.ly);
      });
      if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
      // markers: touched when the wave reaches them
      marks.forEach(m => {
        if (m.moves) {
          const on = front >= m.r - LAM * 0.3;
          if (on && !m.hit) { m.hit = true; m.tHit = simT; m.el.classList.add('hit'); if (!reduce && mode !== 'still') rips.push({ px: m.px, pz: m.pz, t0: simT }); }
          else if (!on && m.hit && mode === 'scrub') { m.hit = false; m.el.classList.remove('hit'); }
        }
        if (!reduce) {
          const a = m.hit ? simT - m.tHit : 0;
          const dy = m.hit ? -3 * Math.sin(a * 10) * Math.exp(-a / 0.6) + 0.6 * Math.sin(simT * 1.4 + m.k * 1.7) : 0;
          m.buoy.style.transform = `translate(-50%,calc(-50% + ${dy.toFixed(2)}px))`;
        }
      });
      // the scrubber follows the wave
      const u = rToU(Math.min(front, R1 * 1.1));
      ui.fill.style.width = (u * 100).toFixed(2) + '%'; ui.knob.style.left = (u * 100).toFixed(2) + '%';
    }
    function sayLine() {
      if (mode !== 'scrub') {
        ui.line.textContent = mv.length ? `The ripple reached about ${edgeTxt}, then died out.` : 'No measured ripple yet: the water settled almost at once.';
        return;
      }
      const k = Math.max(0, stopsR.findIndex((r, i) => Math.abs(r - scrubR) === Math.min(...stopsR.map(q => Math.abs(q - scrubR)))));
      const c = marks.filter(m => m.moves && m.r <= scrubR + LAM * 0.3).length;
      const by = `By ${SPAN[RINGS[k].l]}: `;
      ui.line.textContent = scrubR >= Rend - LAM * 0.5 ? by + 'calm again. The ripple had died out.'
        : scrubR > reachR + 1 ? by + 'fading out, almost calm.'
          : by + (c ? `still spreading. ${c} thing${c > 1 ? 's' : ''} had moved.` : 'still spreading. Nothing had moved yet.');
      ui.scrub.setAttribute('aria-valuenow', k); ui.scrub.setAttribute('aria-valuetext', `${RINGS[k].l}. ${ui.line.textContent}`);
    }

    /* ---- loop: only while visible, only while something moves ---- */
    function frame(now) {
      raf = 0; if (!host.isConnected) return stop();
      const dt = last ? Math.min(0.05, (now - last) / 1000) : 1 / 60; last = now; simT += dt;
      if (mode === 'scrub' && !dragging) shownR += (scrubR - shownR) * Math.min(1, dt * 7);
      if (!(settled && mode === 'anim' && (frames++ & 1))) draw();   // settled water only needs half the frames
      kick();
    }
    function kick() { if (reduce || raf || !vis || document.hidden || !host.isConnected) { if (!raf) last = 0; return; } raf = requestAnimationFrame(frame); }
    const io = 'IntersectionObserver' in window ? new IntersectionObserver(e => { vis = e[e.length - 1].isIntersecting; kick(); }) : null;
    const ro = 'ResizeObserver' in window ? new ResizeObserver(() => { if (layout()) { draw(); sayLine(); } }) : null;
    const onVis = () => kick();
    function stop() { if (raf) cancelAnimationFrame(raf); raf = 0; io && io.disconnect(); ro && ro.disconnect(); document.removeEventListener('visibilitychange', onVis); }
    io && io.observe(host); ro && ro.observe(host); document.addEventListener('visibilitychange', onVis);

    /* ---- scrubber + replay ---- */
    function scrubTo(r, snap) {
      if (mode !== 'scrub') { shownR = Math.min(front, R1 * 1.1); mode = 'scrub'; }
      scrubR = r; if (snap || reduce) shownR = r;
      sayLine(); if (reduce) draw(); else kick();
    }
    const uAt = e => { const b = ui.rail.getBoundingClientRect(); return Math.min(1, Math.max(0, (e.clientX - b.left) / b.width)); };
    const nearest = u => Math.min(3, Math.max(0, Math.round((u - 0.125) / 0.25)));
    ui.scrub.addEventListener('pointerdown', e => { dragging = true; ui.scrub.setPointerCapture?.(e.pointerId); scrubTo(uToR(uAt(e)), true); e.preventDefault(); });
    ui.scrub.addEventListener('pointermove', e => { if (dragging) scrubTo(uToR(uAt(e)), true); });
    const end = e => { if (!dragging) return; dragging = false; scrubTo(stopsR[nearest(uAt(e))], false); };
    ui.scrub.addEventListener('pointerup', end); ui.scrub.addEventListener('pointercancel', end);
    ui.scrub.addEventListener('keydown', e => {
      const cur = mode === 'scrub' ? nearest(rToU(scrubR)) : -1;
      const k = { ArrowRight: cur + 1, ArrowUp: cur + 1, ArrowLeft: cur - 1, ArrowDown: cur - 1, Home: 0, End: 3 }[e.key];
      if (k == null) return; e.preventDefault(); scrubTo(stopsR[Math.min(3, Math.max(0, k))], false);
    });
    ui.replay.onclick = () => {
      mode = reduce ? 'still' : 'anim'; simT = 0; settled = false; rips.length = 0;
      marks.forEach(m => { m.hit = false; m.el.classList.remove('hit'); });
      sayLine(); draw(); kick();
    };

    layout(); sayLine(); draw(); kick();
    return {
      setOpen(i) { marks.forEach(m => m.el.classList.toggle('sel', m.i >= 0 && m.i === i)); },
    };
  }

  let cur = null, openI = -1;
  function viewShock(slug) {
    const s = shock(slug); if (!s) return viewMissing();
    cur = s; openI = -1; pushTrail({ href: `#/s/${encodeURIComponent(slug)}`, label: s.name }); setNav(null);
    document.title = `${s.name}: Ripple Map`; ping('trace'); if (trail.length > 1) ping('second_ripple');
    const edge = reachRing(s), ei = RINGS.indexOf(edge);
    const url = `https://bensunter.com/ripples/pond/r/${encodeURIComponent(slug)}/`;
    $('#main').innerHTML = `
      <section class="shock fade">
        <div class="headcol">
          <div class="eyebrow">${esc(s.kind)} · ${esc(s.when)}${s.where ? ' · ' + esc(s.where) : ''}</div>
          <h1 class="sm" style="margin-top:14px">${titleHTML(s.title)}</h1>
          <div class="verdict"><span class="conf"><i class="dot" style="background:${TIER[s.confidence].css}"></i>${STORY[s.story] || TIER[s.confidence].label}</span>${esc(s.verdict)}</div>
          <p class="synth">${esc(s.synth)}</p>
          ${s.is_control ? `<p class="note">One of our test cases: a shock whose effect we expected. We use it to check the engine finds real effects before we trust it on surprising ones.</p>` : ''}
          <div class="actions"><button class="btn primary" id="send">Send this</button><a class="btn" href="#/" id="another">Find another ripple</a></div>
        </div>
        <div class="viz"><div class="pond" id="pond"></div>
          <div class="scrub" id="scrub" role="slider" tabindex="0" aria-label="How far the ripple had travelled by then" aria-valuemin="0" aria-valuemax="3" aria-valuenow="${ei}" aria-valuetext="${edge.l}">
            <div class="rail" id="rail"><i class="fill" id="fill"></i><i class="knob" id="knob"></i></div>
            <div class="stops">${RINGS.map((r, i) => `<span class="${i < ei ? 'on' : i === ei && moved(s).length ? 'edge' : ''}">${r.l}</span>`).join('')}</div>
          </div>
          <div class="pondfoot"><p class="reachline" id="reachline"></p><button type="button" class="replay" id="replay">Drop again</button></div></div>
      </section>
      <section class="groups" id="groups"></section>
      ${s.context ? `<div class="context"><div class="eyebrow">${esc(s.context.title)}</div><p>${esc(s.context.text)}</p></div>` : ''}`;
    pondCtl = Pond(s, $('#pond'), { scrub: $('#scrub'), rail: $('#rail'), fill: $('#fill'), knob: $('#knob'), line: $('#reachline'), replay: $('#replay'),
      pick: i => toggleImpact(i, true), none: showNone });
    $('#send').onclick = () => send(s.title, url);
    renderGroups();
    window.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' });
  }
  function renderGroups() {
    const s = cur, G = $('#groups'); G.innerHTML = '';
    ORDER.forEach(t => {
      const list = s.impacts.map((im, i) => ({ im, i })).filter(x => x.im.tier === t); if (!list.length) return;
      const sec = document.createElement('div'); sec.className = 'group';
      sec.innerHTML = `<h3><i class="dot" style="background:${TIER[t].css}"></i>${TIER[t].label}</h3><p class="gnote">${esc(D.tiers[t])}</p>`;
      list.forEach(({ im, i }) => {
        const b = document.createElement('button'); b.className = 'impact'; b.id = `imp-${i}`; b.setAttribute('aria-expanded', openI === i);
        b.innerHTML = `<span><span class="iname">${esc(im.name)}${im.expected ? '<span class="exp">Expected</span>' : ''}</span><span class="isub">${esc(im.sub)}</span></span><span class="dir ${esc(im.dir)}">${SYM[im.dir] ? SYM[im.dir] + ' ' : ''}${esc(im.mag)}</span><span class="chev" aria-hidden="true">${openI === i ? '−' : '+'}</span>`;
        b.onclick = () => toggleImpact(i, false); sec.appendChild(b);
        if (openI === i) {
          const o = outcome(im.group); const d = document.createElement('div'); d.className = 'drawer fade';
          d.innerHTML = `<p>${esc(im.say)}</p>
            ${im.why ? `<div class="q">Why it happens</div><p class="a">${esc(im.why)}</p>` : ''}
            <div class="q">How sure are we</div><p class="a">${esc(im.sure)}</p>
            ${o ? `<div class="next"><a class="linkbtn" href="#/o/${encodeURIComponent(im.group)}">What else moves ${esc(o.name.toLowerCase())} →</a></div>` : ''}
            <details class="evidence"><summary>SEE THE EVIDENCE</summary><table>${(im.evidence || []).map(r => `<tr><td>${esc(r[0])}</td><td>${esc(r[1])}</td></tr>`).join('')}</table></details>`;
          d.querySelector('details').addEventListener('toggle', e => { if (e.target.open) ping('luck_open'); });
          sec.appendChild(d);
        }
      });
      G.appendChild(sec);
    });
    if (s.none && s.none.length) {
      const ns = document.createElement('div'); ns.className = 'group'; ns.id = 'nonegroup';
      const first = s.none.slice(0, 3).map(x => x.toLowerCase());
      ns.innerHTML = `<h3><i class="dot" style="background:var(--c-none)"></i>No sign</h3>
        <p class="nosign">Didn’t move: ${esc(first.join(', '))}${s.none.length > 3 ? ` and ${s.none.length - 3} more` : ''}.${s.none.length > 3 ? '<button id="allnone">See all</button>' : ''}</p>
        <ul class="nosign-list" id="nonelist" hidden>${s.none.map(x => `<li>${esc(x)}</li>`).join('')}</ul>`;
      G.appendChild(ns);
      const b = $('#allnone'); if (b) b.onclick = e => { const l = $('#nonelist'); l.hidden = !l.hidden; e.target.textContent = l.hidden ? 'See all' : 'Hide'; };
    }
  }
  function showNone() {   // a still marker: open the full no-sign list
    const l = $('#nonelist'), b = $('#allnone'); if (l && l.hidden) { l.hidden = false; if (b) b.textContent = 'Hide'; }
    $('#nonegroup')?.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' });
  }
  function toggleImpact(i, scroll) {
    openI = openI === i ? -1 : i; if (openI >= 0) ping('stop_open');
    if (pondCtl) pondCtl.setOpen(openI); renderGroups();
    if (scroll && openI >= 0) document.getElementById(`imp-${i}`)?.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' });
  }

  function flow(o) {
    const n = Math.max(1, o.up.length), m = o.down.length, H = Math.max(180, 70 * Math.max(n, m) + 40), W = 900, cx = W / 2, cy = H / 2;
    const svg = document.createElementNS(NS, 'svg'); svg.setAttribute('viewBox', `0 0 ${W} ${H}`); svg.setAttribute('role', 'img'); svg.setAttribute('aria-label', `What pushed ${o.name}, and what it might move next`);
    svgEl('text', { x: 24, y: 22, 'font-family': 'Geist Mono, monospace', 'font-size': 11, 'letter-spacing': 1.6, fill: '#6B7A81' }, svg).textContent = 'UPSTREAM · WHAT PUSHED IT';
    svgEl('text', { x: W - 24, y: 22, 'text-anchor': 'end', 'font-family': 'Geist Mono, monospace', 'font-size': 11, 'letter-spacing': 1.6, fill: '#6B7A81' }, svg).textContent = 'DOWNSTREAM · WHAT IT MIGHT MOVE';
    o.up.forEach((u, i) => {
      const y = 50 + (i + 0.5) * ((H - 60) / n), col = TIER[u.tier].c;
      svgEl('path', { d: `M 250 ${y} C ${cx - 120} ${y}, ${cx - 120} ${cy}, ${cx - 14} ${cy}`, fill: 'none', stroke: col, 'stroke-width': u.tier === 'confirmed' ? 2 : u.tier === 'likely' ? 1.4 : 1, opacity: 0.85, 'stroke-dasharray': (u.tier === 'possible' || u.tier === 'watch') ? '3 4' : null }, svg);
      const g = svgEl('g', u.shock ? { tabindex: 0, role: 'link', style: 'cursor:pointer', 'aria-label': u.name } : {}, svg);
      svgEl('circle', { cx: 250, cy: y, r: 4, fill: col }, g);
      svgEl('text', { x: 236, y: y - 3, 'text-anchor': 'end', 'font-family': 'Geist, sans-serif', 'font-size': 15, fill: '#E7ECEE' }, g).textContent = u.name;
      svgEl('text', { x: 236, y: y + 15, 'text-anchor': 'end', 'font-family': 'Geist Mono, monospace', 'font-size': 11, fill: u.dir === 'up' ? '#E2B170' : u.dir === 'down' ? '#8FB9E8' : '#6B7A81' }, g).textContent = `${SYM[u.dir] ? SYM[u.dir] + ' ' : ''}${u.txt.replace(/^(up|down)\s+/, '')}`;
      if (u.shock) { const go = () => { location.hash = `#/s/${encodeURIComponent(u.shock)}`; }; g.addEventListener('click', go); g.addEventListener('keydown', e => { if (e.key === 'Enter') go(); }); }
    });
    svgEl('circle', { cx, cy, r: 16, fill: '#A9D3DF', opacity: 0.12 }, svg); svgEl('circle', { cx, cy, r: 7, fill: '#E7ECEE' }, svg);
    svgEl('text', { x: cx, y: cy + 40, 'text-anchor': 'middle', 'font-family': 'Instrument Serif, serif', 'font-size': 22, fill: '#E7ECEE', 'paint-order': 'stroke', stroke: '#0D1317', 'stroke-width': 10, 'stroke-linejoin': 'round' }, svg).textContent = o.name;
    o.down.forEach((d, i) => {
      const y = 50 + (i + 0.5) * ((H - 60) / Math.max(1, m)), col = TIER[d.tier].c;
      svgEl('path', { d: `M ${cx + 14} ${cy} C ${cx + 120} ${cy}, ${cx + 120} ${y}, ${W - 250} ${y}`, fill: 'none', stroke: col, 'stroke-width': 1, opacity: 0.8, 'stroke-dasharray': '3 4' }, svg);
      const has = !!outcome(d.group);
      const g = svgEl('g', has ? { tabindex: 0, role: 'link', style: 'cursor:pointer', 'aria-label': d.name } : {}, svg);
      svgEl('circle', { cx: W - 250, cy: y, r: 4, fill: 'none', stroke: col, 'stroke-width': 1.2 }, g);
      svgEl('text', { x: W - 236, y: y - 3, 'font-family': 'Geist, sans-serif', 'font-size': 15, fill: '#E7ECEE' }, g).textContent = d.name;
      svgEl('text', { x: W - 236, y: y + 15, 'font-family': 'Geist Mono, monospace', 'font-size': 11, fill: '#6B7A81' }, g).textContent = TIER[d.tier].label.toLowerCase();
      if (has) { const go = () => { location.hash = `#/o/${encodeURIComponent(d.group)}`; }; g.addEventListener('click', go); g.addEventListener('keydown', e => { if (e.key === 'Enter') go(); }); }
    });
    if (!m) svgEl('text', { x: W - 250, y: cy + 4, 'font-family': 'Geist, sans-serif', 'font-size': 14, fill: '#6B7A81' }, svg).textContent = 'Nothing traced beyond this yet';
    return svg;
  }
  function viewOutcome(key) {
    const o = outcome(key); if (!o) return viewMissing();
    pushTrail({ href: `#/o/${encodeURIComponent(key)}`, label: o.name }); setNav(null); document.title = `${o.name}: Ripple Map`;
    $('#main').innerHTML = `
      <section class="outcome fade">
        <div class="eyebrow">Something that changed</div>
        <h1 class="sm" style="margin-top:14px">What moves <em>${esc(o.name.toLowerCase())}?</em></h1>
        <p class="synth" style="max-width:56ch">${esc(o.synth)}</p>
        <div class="flow" id="flow"></div>
        <div class="cols">
          <div><div class="eyebrow" style="margin-bottom:8px">Upstream: what pushed it</div>
            ${o.up.length ? o.up.map(u => u.shock
              ? `<a class="impact" href="#/s/${encodeURIComponent(u.shock)}"><span><span class="iname">${esc(u.name)}</span><span class="isub">${TIER[u.tier].label}</span></span><span class="dir ${esc(u.dir)}">${SYM[u.dir] ? SYM[u.dir] + ' ' : ''}${esc(u.txt.replace(/^(up|down)\s+/, ''))}</span><span class="chev">→</span></a>`
              : `<div class="impact" aria-disabled="true"><span><span class="iname">${esc(u.name)}</span><span class="isub">${TIER[u.tier].label} · a pattern across many past events</span></span><span class="dir ${esc(u.dir)}">${SYM[u.dir] ? SYM[u.dir] + ' ' : ''}${esc(u.txt.replace(/^(up|down)\s+/, ''))}</span><span></span></div>`).join('')
              : `<p class="nosign">Nothing traced yet.</p>`}</div>
          <div><div class="eyebrow" style="margin-bottom:8px">Downstream: what it might move next</div>
            ${o.down.length ? o.down.map(d => outcome(d.group)
              ? `<a class="impact" href="#/o/${encodeURIComponent(d.group)}"><span><span class="iname">${esc(d.name)}</span><span class="isub">${esc(d.txt)}</span></span><span class="dir flat">${TIER[d.tier].label}</span><span class="chev">→</span></a>`
              : `<div class="impact" aria-disabled="true"><span><span class="iname">${esc(d.name)}</span><span class="isub">${esc(d.txt)}</span></span><span class="dir flat">${TIER[d.tier].label}</span><span></span></div>`).join('')
              : `<p class="nosign">Nothing traced beyond this yet.</p>`}
            <p class="gnote" style="margin-top:12px">${esc(D.tiers.possible)}</p></div>
        </div>
      </section>`;
    $('#flow').appendChild(flow(o));
    window.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' });
  }
  function viewWatching() {
    trail.length = 0; setCrumbs(); setNav('watching'); document.title = 'Watching: Ripple Map';
    const items = [];
    D.shocks.forEach(s => s.impacts.forEach(im => { if (im.tier === 'possible' || (im.tier === 'watch' && s.confidence !== 'watch')) items.push({ s, im }); }));
    const pending = D.shocks.filter(s => s.confidence === 'watch');
    $('#main').innerHTML = `<section class="hero fade"><div class="eyebrow">Open questions</div><h1 style="margin-top:14px">Ripples still <em>travelling.</em></h1>
      <p class="lede">Leads we’re following and tests waiting for data. Come back and see how they land.</p>
      <div class="list" style="margin-top:28px">${items.map(x => `<a class="row" style="grid-template-columns:1fr auto" href="#/s/${encodeURIComponent(x.s.slug)}"><div>
        <div class="name" style="font-size:22px">${esc(x.im.name)}</div><div class="meta">${esc(x.s.name)} · ${TIER[x.im.tier].label}</div><div class="one">${esc(x.im.sure)}</div></div><span class="go">→</span></a>`).join('')}
      ${pending.length ? `<details class="more"><summary>${pending.length} more shock${pending.length > 1 ? 's' : ''} waiting for their first results <span>show</span></summary><div class="compact">${pending.map(s => `<a href="#/s/${encodeURIComponent(s.slug)}">${esc(s.name)}</a>`).join('')}</div></details>` : ''}</div></section>`;
  }
  function viewHow() {
    trail.length = 0; setCrumbs(); setNav('how'); document.title = 'How it works: Ripple Map';
    $('#main').innerHTML = `<section class="hero how fade"><div class="eyebrow">How it works</div><h1 style="margin-top:14px">We read <em>many signals,</em> then say it plainly.</h1>
      <p class="lede">For every shock we check dozens of things that might have moved, compare them with places and times the shock didn’t touch, and only then decide what to tell you.</p>
      <ol class="steps">
        <li><div><b>Write the test down first.</b>Before any result exists, we record what we’ll check, where, and for how long, in a log that can’t be quietly edited.</div></li>
        <li><div><b>Compare with places it missed.</b>If a storm hit Florida, we compare Florida with states it didn’t touch over the same days.</div></li>
        <li><div><b>Try to fool ourselves.</b>We run the same test on fake events and random dates. If fakes pass too, the real one doesn’t count.</div></li>
        <li><div><b>Get a second opinion.</b>For the strongest results, an independent forecasting model has to agree.</div></li>
        <li><div><b>Say it plainly, keep the receipts.</b>You see one sentence and how sure we are. The numbers are one tap away for anyone who wants them.</div></li>
      </ol>
      <div class="groups" style="margin-top:40px">${ORDER.map(t => `<div class="group"><h3><i class="dot" style="background:${TIER[t].css}"></i>${TIER[t].label}</h3><p class="nosign">${esc(D.tiers[t])}</p></div>`).join('')}
        <div class="group"><h3><i class="dot" style="background:var(--c-none)"></i>No sign</h3><p class="nosign">${esc(D.tiers.none)}</p></div></div>
      <p class="note" style="margin-top:34px">${esc(D.note)} <a class="linkbtn" href="../methods/">Full methods</a></p></section>`;
  }
  function viewMissing() { $('#main').innerHTML = `<section class="hero fade"><h1 class="sm">That ripple isn’t here.</h1><p class="lede">It may have been renamed or withdrawn. <a class="linkbtn" href="#/">Find another</a></p></section>`; }

  /* ---------- router ---------- */
  function route() {
    const h = location.hash.replace(/^#\/?/, ''); const [k, v] = h.split('/');
    if (k === 's' && v) return viewShock(decodeURIComponent(v));
    if (k === 'o' && v) return viewOutcome(decodeURIComponent(v));
    if (k === 'watching') return viewWatching();
    if (k === 'how') return viewHow();
    return viewFind();
  }
  window.addEventListener('hashchange', route);
  load().then(d => {
    D = d; route();
    const b = d.built_at ? new Date(d.built_at) : null;
    $('#asof').textContent = b ? `Updated ${b.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}${d._src === 'snapshot' ? ' (saved copy)' : ''}.` : '';
    if (!ls.get('rm.seen')) { ls.set('rm.seen', '1'); ping('landing'); }
  }).catch(() => { $('#main').innerHTML = `<p class="loading">Couldn’t load the ripples. Please try again in a moment.</p>`; });
})();
