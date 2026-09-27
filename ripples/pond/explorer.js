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
  function titleHTML(t) {   // italicise what the shock touched
    const m = t.match(/^(.*?(?:clearest mark was on|probably moved))\s(.+?)\.?$/);
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

  function pond(s, openIdx) {
    const W = 520, C = 260, R0 = 26, R1 = 236;
    const svg = document.createElementNS(NS, 'svg'); svg.setAttribute('viewBox', `0 0 ${W} ${W}`); svg.setAttribute('role', 'img');
    const edge = reachRing(s);
    svg.setAttribute('aria-label', `${s.name}: the ripple reached a ${edge.l.toLowerCase()}`);
    const defs = svgEl('defs', {}, svg); const rg = svgEl('radialGradient', { id: 'pg' }, defs);
    svgEl('stop', { offset: '0%', 'stop-color': '#13252D' }, rg); svgEl('stop', { offset: '70%', 'stop-color': '#0C161B' }, rg); svgEl('stop', { offset: '100%', 'stop-color': '#090D10', 'stop-opacity': 0 }, rg);
    const gl = svgEl('filter', { id: 'gl', x: '-50%', y: '-50%', width: '200%', height: '200%' }, defs); svgEl('feGaussianBlur', { stdDeviation: 3 }, gl);
    svgEl('circle', { cx: C, cy: C, r: R1 + 18, fill: 'url(#pg)' }, svg);
    RINGS.filter(r => r.d <= edge.d).forEach((r, i) => {
      const rr = rOf(r.d, R0, R1), last = r === edge;
      if (last) svgEl('circle', { cx: C, cy: C, r: rr, fill: 'none', stroke: '#A9D3DF', 'stroke-width': 3, opacity: 0.25, filter: 'url(#gl)' }, svg);
      const c = svgEl('circle', { cx: C, cy: C, r: rr, fill: 'none', stroke: '#A9D3DF', 'stroke-width': last ? 1.3 : 0.7, opacity: last ? 0.95 : 0.4 }, svg);
      if (!reduce && openIdx === -2) { c.style.transformOrigin = `${C}px ${C}px`; c.animate([{ transform: 'scale(.2)', opacity: 0 }, { transform: 'scale(1)', opacity: last ? 0.95 : 0.4 }], { duration: 900, delay: 180 + i * 260, easing: 'cubic-bezier(.2,.7,.2,1)', fill: 'both' }); }
      const t = svgEl('text', { x: C, y: C - rr - 7, 'text-anchor': 'middle', 'font-family': 'Geist Mono, monospace', 'font-size': 10, 'letter-spacing': 1.4, fill: last ? '#A9D3DF' : '#6B7A81' }, svg); t.textContent = r.l.toUpperCase();
    });
    svgEl('circle', { cx: C, cy: C, r: 4, fill: '#E7ECEE' }, svg);
    svgEl('circle', { cx: C, cy: C, r: 9, fill: 'none', stroke: '#E7ECEE', 'stroke-width': 0.6, opacity: 0.35 }, svg);
    const shown = s.impacts.map((im, i) => ({ im, i })).filter(x => x.im.tier !== 'watch');
    shown.forEach(({ im, i }, k) => {
      const beyond = im.tier === 'possible'; const d = beyond ? Math.max(im.at || 28, edge.d * 1.8) : Math.min(im.at || 1, edge.d);
      const r = Math.min(rOf(d, R0, R1), R1 + 6);
      const a = (-58 + k * (shown.length > 1 ? 300 / shown.length : 0)) * Math.PI / 180, x = C + r * Math.cos(a), y = C + r * Math.sin(a);
      const g = svgEl('g', { tabindex: 0, role: 'button', 'aria-label': `${im.name}, ${TIER[im.tier].label}`, style: 'cursor:pointer' }, svg);
      const col = TIER[im.tier].c;
      if (im.tier === 'confirmed') { svgEl('circle', { cx: x, cy: y, r: 10, fill: col, opacity: 0.18, filter: 'url(#gl)' }, g); svgEl('circle', { cx: x, cy: y, r: 5.5, fill: col }, g); }
      else if (im.tier === 'likely') { svgEl('circle', { cx: x, cy: y, r: 6, fill: 'none', stroke: col, 'stroke-width': 1.4 }, g); svgEl('path', { d: `M${x} ${y - 6} a6 6 0 0 0 0 12 z`, fill: col }, g); }
      else svgEl('circle', { cx: x, cy: y, r: 6, fill: 'none', stroke: col, 'stroke-width': 1.1, 'stroke-dasharray': '2 2.5' }, g);
      if (openIdx === i) svgEl('circle', { cx: x, cy: y, r: 13, fill: 'none', stroke: '#E7ECEE', 'stroke-width': 0.8 }, g);
      const right = Math.cos(a) > -0.3;
      svgEl('text', { x: right ? x + 14 : x - 14, y: y + 4, 'text-anchor': right ? 'start' : 'end', 'font-family': 'Geist, sans-serif', 'font-size': 13, fill: '#E7ECEE' }, g).textContent = im.short || im.name;
      svgEl('text', { x: right ? x + 14 : x - 14, y: y + 19, 'text-anchor': right ? 'start' : 'end', 'font-family': 'Geist Mono, monospace', 'font-size': 10.5,
        fill: im.dir === 'up' ? '#E2B170' : im.dir === 'down' ? '#8FB9E8' : '#6B7A81' }, g).textContent = `${SYM[im.dir] ? SYM[im.dir] + ' ' : ''}${im.mag}`;
      const open = () => toggleImpact(i, true);
      g.addEventListener('click', open); g.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(); } });
    });
    return svg;
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
          <div class="verdict"><span class="conf"><i class="dot" style="background:${TIER[s.confidence].css}"></i>${TIER[s.confidence].label}</span>${esc(s.verdict)}</div>
          <p class="synth">${esc(s.synth)}</p>
          ${s.is_control ? `<p class="note">One of our test cases: a shock whose effect we expected. We use it to check the engine finds real effects before we trust it on surprising ones.</p>` : ''}
          <div class="actions"><button class="btn primary" id="send">Send this</button><a class="btn" href="#/" id="another">Find another ripple</a></div>
        </div>
        <div class="viz"><div id="pond"></div>
          <div class="scale">${RINGS.map((r, i) => `<span class="${i < ei ? 'on' : i === ei ? 'edge' : ''}">${r.l}</span>`).join('')}</div>
          <p class="reachline">${moved(s).length ? `Reached a ${edge.l.toLowerCase()}, then calm.` : 'No measured ripple yet.'}</p></div>
      </section>
      <section class="groups" id="groups"></section>
      ${s.context ? `<div class="context"><div class="eyebrow">${esc(s.context.title)}</div><p>${esc(s.context.text)}</p></div>` : ''}`;
    $('#pond').appendChild(pond(s, -2));
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
        b.innerHTML = `<span><span class="iname">${esc(im.name)}</span><span class="isub">${esc(im.sub)}</span></span><span class="dir ${esc(im.dir)}">${SYM[im.dir] ? SYM[im.dir] + ' ' : ''}${esc(im.mag)}</span><span class="chev" aria-hidden="true">${openI === i ? '−' : '+'}</span>`;
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
      const ns = document.createElement('div'); ns.className = 'group';
      const first = s.none.slice(0, 3).map(x => x.toLowerCase());
      ns.innerHTML = `<h3><i class="dot" style="background:var(--c-none)"></i>No sign</h3>
        <p class="nosign">Didn’t move: ${esc(first.join(', '))}${s.none.length > 3 ? ` and ${s.none.length - 3} more` : ''}.${s.none.length > 3 ? '<button id="allnone">See all</button>' : ''}</p>
        <ul class="nosign-list" id="nonelist" hidden>${s.none.map(x => `<li>${esc(x)}</li>`).join('')}</ul>`;
      G.appendChild(ns);
      const b = $('#allnone'); if (b) b.onclick = e => { const l = $('#nonelist'); l.hidden = !l.hidden; e.target.textContent = l.hidden ? 'See all' : 'Hide'; };
    }
  }
  function toggleImpact(i, scroll) {
    openI = openI === i ? -1 : i; if (openI >= 0) ping('stop_open');
    const p = $('#pond'); p.innerHTML = ''; p.appendChild(pond(cur, openI)); renderGroups();
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
