/* Ripple Map pond slice: page logic. Loads data/milton.json (the engine snapshot), draws the pond, runs the signature reveal,
   opens the stop card, and handles Send / Watch / While you were gone / analytics. No number on the page is typed here. */
(async function () {
  const $ = (s, r = document) => r.querySelector(s);
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const compact = innerWidth <= 900;
  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const ls = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } } };
  const fmtDay = iso => new Date(iso + 'T00:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' });
  const fmtDayY = iso => new Date(iso + 'T00:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });

  /* ---------- analytics: aggregate counts only, through the site's existing rm_event RPC ----------
     rm_event accepts two kinds today ('share_tap', 'landing'). Discovery-depth kinds are counted on this device and sent only
     where the RPC allows; the rest wait for the kinds to be whitelisted server-side (see SLICE.md). Nothing personal leaves the page. */
  const SB = { url: 'https://kffkasnzqcddpystszch.supabase.co', key: 'sb_publishable_3UtNDc2vPbCIcG1t5K4YEQ_KUyTKucv' };
  function clientId() { let c = ls.get('ko.client'); if (!c) { const a = new Uint8Array(12); crypto.getRandomValues(a); c = btoa(String.fromCharCode(...a)).replace(/[+/=]/g, m => ({ '+': '-', '/': '_', '=': '' })[m]); ls.set('ko.client', c); } return c; }
  const ALLOWED = { send: ['share_tap', 'pond_send'], landing: ['landing', 'pond'] };
  const depth = new Set();
  function track(kind) {
    depth.add(kind); ls.set('rm.pond.depth', JSON.stringify([...depth]));
    const m = ALLOWED[kind]; if (!m || location.protocol === 'file:') return;
    try { fetch(`${SB.url}/rest/v1/rpc/rm_event`, { method: 'POST', credentials: 'omit', keepalive: true, headers: { apikey: SB.key, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_kind: m[0], p_src: m[1], p_client: clientId() }) }).catch(() => {}); } catch { /* never block */ }
  }

  /* ---------- data ---------- */
  let P;
  try { P = await (await fetch('data/milton.json', { cache: 'no-cache' })).json(); }
  catch (e) { $('#h1').textContent = 'The snapshot did not load.'; $('#trust').textContent = 'Reload the page, or open data/milton.json to check it is being served.'; return; }
  const E = P.effects[0], S = P.shore[0];
  const TIER = window.Pond.TIER;
  const tierWord = e => e.contrast && e.contrast.pass ? 'Regional contrast passed' : TIER[e.tier];
  const drawTier = e => e.contrast && e.contrast.pass ? 'contrast' : e.tier;   // what the pond draws: never above the engine tier's evidence level
  E.tier = drawTier(E);

  /* ---------- hero copy (from the story fields in the snapshot) ---------- */
  /* the hook copy is static in index.html so nothing shifts on load; it is checked against the snapshot and rewritten only if stale */
  const H1 = { hook: $('#h1').innerHTML, traced: `One storm.<br>One ripple, measured against the rest of the country.<br><span class="quiet">${P.untested.length === 12 ? 'Twelve' : P.untested.length} things still waiting for their test.</span>` };
  const trustWant = `${E.replication.n_seen} of ${E.replication.n_similar}`;
  if (!$('#trust').textContent.includes(trustWant) || !$('#trust').textContent.includes(String(E.contrast.n_donors))) $('#trust').innerHTML = `<b>${esc(tierWord(E))}.</b> Florida against ${E.contrast.n_donors} regions the storm missed. <span class="no">Not yet Measured: the single-event test is queued.</span> Passed after <span class="num">${trustWant}</span> similar storms tested.`;
  if (!$('#reach').textContent.includes(`${P.travel.days} days`)) $('#reach').innerHTML = `<span class="num">${P.travel.domains}</span> domain · <span class="num">${P.travel.days}</span> days · 1st-order<small>How far the ripple travelled. ${esc(P.travel.usual_reach)}.</small>`;
  $('#traced-sub').textContent = P.story.story_sentence;
  $('#foot-src').textContent = `Sources: EIA-930 hourly demand, FEMA, NWS/IEM, TSA, DOL, Census BFS. Engine ${P.engine.method_hop} tests, ${P.engine.method_contrast} regional contrasts, batch ${P.engine.batch}. Ledger head ${P.ledger_head.chain_hash.slice(0, 12)}…`;

  /* ---------- the pond ---------- */
  const svg = $('#pond');
  let pond = Pond.render(svg, P, { compact, viewBox: compact ? [-480, -480, 960, 960] : [-560, -470, 1120, 940], onSelect: open, timing: 'fast' });
  svg.classList.add('hook');
  track('hero_view');

  /* phone: numbered list under the pond */
  const list = $('#pond-list');
  list.innerHTML = [`<li><button type="button" data-open="${E.id}" data-kind="effect"><span class="i">1</span><span class="t"><b>${esc(E.num)}</b> ${esc(E.short)}</span><span class="c">${esc(tierWord(E))}</span></button></li>`,
    `<li><button type="button" data-open="${S.id}" data-kind="shore"><span class="i r">R</span><span class="t"><b>${esc(S.num)}</b> ${esc(S.short)}, far shore</span><span class="c">World rule, ${S.pattern.n_events} storms</span></button></li>`,
    `<li><button type="button" data-open="${P.untested[0].id}" data-kind="untested"><span class="i u">⋯</span><span class="t">${P.untested.length} series pre-registered</span><span class="c">untested</span></button></li>`].join('');
  list.querySelectorAll('button').forEach(b => b.addEventListener('click', () => open(b.dataset.open, b.dataset.kind)));

  /* ---------- the reveal (signature moment): drop, ring reaches the pad, count-up, lag, tier, settle ---------- */
  function trace() {
    document.body.classList.remove('hook'); track('trace');
    $('#h1').innerHTML = H1.traced;
    svg.classList.remove('hook');
    const g = pond.nodes[E.id], p = E._pos;
    svg.classList.add('revealing'); g.classList.add('reveal-target');
    const th = svg.querySelector(`.thread[data-for="${E.id}"]`); if (th) th.classList.add('reveal-thread');
    const fresh = svg.cloneNode(true); svg.parentNode.replaceChild(fresh, svg);   // restart the CSS timeline
    const Sv = $('#pond'); rebind(Sv);
    const NS = 'http://www.w3.org/2000/svg';
    const rv = document.createElementNS(NS, 'g'); rv.setAttribute('class', 'reveal'); rv.setAttribute('aria-hidden', 'true'); Sv.appendChild(rv);
    const side = p.x >= 0 ? 1 : -1, lx = p.x + side * 44, anchor = side > 0 ? 'start' : 'end';
    const mk = (cls, y, txt) => { const t = document.createElementNS(NS, 'text'); t.setAttribute('class', 'rv ' + cls); t.setAttribute('x', lx); t.setAttribute('y', p.y + y); t.setAttribute('text-anchor', anchor); t.textContent = txt; rv.appendChild(t); return t; };
    const num = mk('rv-num', -6, ''), what = mk('rv-what', 18, E.short), lag = mk('rv-lag', 40, E.lag_text), tier = mk('rv-tier', 60, tierWord(E));
    // D-15 timeline: shock 0, line 250 ms, stop 500, count-up 800, lag 1100, tier 1300, settle 1600
    const hit = reduce ? 0 : pond.ringDelay(p.r) * 1000;   // the ring front reaches the pad (~0.5 s)
    const T = reduce ? [0, 0, 0, 0, 0] : [hit + 300, 500, hit + 600, hit + 800, hit + 1100];
    const target_v = parseFloat(E.num.replace(/[^\d.\-]/g, '')) * (E.num.startsWith('−') || E.num.startsWith('-') ? -1 : 1);
    const prefix = target_v < 0 ? '−' : '+', suffix = E.num.endsWith('%') ? '%' : '';
    const t0 = performance.now() + T[0];
    function tick(now) { const k = Math.min(1, Math.max(0, (now - t0) / T[1])); const v = Math.abs(target_v) * (1 - Math.pow(1 - k, 3)); num.textContent = prefix + Math.round(v) + suffix; if (k < 1) requestAnimationFrame(tick); }
    if (reduce) num.textContent = E.num; else requestAnimationFrame(tick);
    setTimeout(() => lag.classList.add('on'), T[2]);
    setTimeout(() => tier.classList.add('on'), T[3]);
    setTimeout(() => { Sv.classList.add('settling'); Sv.classList.remove('revealing'); rv.remove(); open(E.id, 'effect'); }, T[4] + (reduce ? 10 : 500));
  }
  function rebind(Sv) {
    Sv.querySelectorAll('.effect').forEach(g => { g.addEventListener('click', () => open(g.dataset.id, 'effect')); g.addEventListener('keydown', ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(g.dataset.id, 'effect'); } }); pond.nodes[g.dataset.id] = g; });
    Sv.querySelectorAll('.shore-mark').forEach(g => { g.addEventListener('click', () => open(g.dataset.id, 'shore')); g.addEventListener('keydown', ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(g.dataset.id, 'shore'); } }); });
    Sv.querySelectorAll('.float').forEach(g => { g.addEventListener('click', () => open(g.dataset.id, 'untested')); g.addEventListener('keydown', ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(g.dataset.id, 'untested'); } }); });
    Sv.querySelectorAll('.grass').forEach(g => { g.addEventListener('click', () => open(g.dataset.id, 'flat')); g.addEventListener('keydown', ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(g.dataset.id, 'flat'); } }); });
  }
  $('#btn-trace').addEventListener('click', trace);
  if (location.hash === '#traced' || new URLSearchParams(location.search).get('stop')) { document.body.classList.remove('hook'); svg.classList.remove('hook'); $('#h1').innerHTML = H1.traced; }

  /* ---------- charts (actual vs normal range, direct labels, no chartjunk) ---------- */
  function seriesChart(e, w = 420, h = 170, mini = false) {
    const c = e.chart, S = c.series, m = { t: mini ? 6 : 24, r: mini ? 6 : 96, b: mini ? 4 : 22, l: mini ? 4 : 30 };
    const xs = S.map((_, i) => i), x = i => m.l + i / (S.length - 1) * (w - m.l - m.r);
    const vals = S.flatMap(s => [s.t, s.o]).concat([c.band.lo, c.band.hi]);
    let ymin = Math.min(...vals), ymax = Math.max(...vals); const pad = (ymax - ymin) * .1; ymin -= pad; ymax += pad;
    const y = v => h - m.b - (v - ymin) / (ymax - ymin) * (h - m.t - m.b);
    const idx = d => S.findIndex(s => s.d === d);
    // the normal range: the pre-window gap (treated minus donors) around the donor line, so a drop below the band is a drop the donors did not share
    let band = ''; S.forEach((s, i) => band += (i ? 'L' : 'M') + x(i) + ',' + y(s.o + (c.band.hi - 1))); for (let i = S.length - 1; i >= 0; i--) band += 'L' + x(i) + ',' + y(S[i].o + (c.band.lo - 1));
    let l1 = '', l2 = ''; S.forEach((s, i) => { l1 += (i ? 'L' : 'M') + x(i) + ',' + y(s.t); l2 += (i ? 'L' : 'M') + x(i) + ',' + y(s.o); });
    const pk = idx(c.peak.d), on = idx(c.onset), lf = idx(c.landfall), pw = [idx(c.post_window[0]), idx(c.post_window[1])];
    let s = `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(e.title)}: Florida's two grids against 51 unaffected regions, both indexed to their own late-summer normal. At the peak on ${fmtDay(c.peak.d)} Florida sat at ${Math.round(c.peak.t * 100)}% of normal while the other regions sat at ${Math.round(c.peak.o * 100)}%.">`;
    s += `<rect class="win" x="${x(pw[0])}" y="${m.t - 4}" width="${x(pw[1]) - x(pw[0])}" height="${h - m.b - m.t + 4}"/>`;
    s += `<path class="band" d="${band}Z"/>`;
    s += `<line class="onset" x1="${x(lf)}" x2="${x(lf)}" y1="${m.t - 4}" y2="${h - m.b}"/>`;
    s += `<path class="line2" d="${l2}"/><path class="line" d="${l1}"/><circle class="pk" cx="${x(pk)}" cy="${y(S[pk].t)}" r="3.5"/>`;
    if (!mini) {
      s += `<text class="lab strong" x="${x(lf)}" y="${m.t - 8}" text-anchor="middle">landfall</text>`;
      s += `<text class="lab acc" x="${x(pk) - 9}" y="${y(S[pk].t) + 4}" text-anchor="end">${Math.round((1 - S[pk].t / S[pk].o) * 100)}% below, ${fmtDay(c.peak.d)}</text>`;
      s += `<text class="lab" x="${w - m.r + 8}" y="${y(S[S.length - 1].o) - 6}">51 other regions</text><text class="lab" x="${w - m.r + 8}" y="${y(S[S.length - 1].o) + 8}">(their normal)</text>`;
      s += `<text class="lab acc" x="${w - m.r + 8}" y="${y(S[S.length - 1].t) + 14}">Florida</text>`;
      [1, .8, .6].forEach(v => { if (v > ymin && v < ymax) s += `<text class="lab" x="${m.l - 6}" y="${y(v) + 4}" text-anchor="end">${Math.round(v * 100)}%</text>`; });
      s += `<text class="lab" x="${m.l}" y="${h - 4}">${fmtDay(S[0].d)}</text><text class="lab" x="${w - m.r}" y="${h - 4}" text-anchor="end">${fmtDay(S[S.length - 1].d)}</text>`;
      s += `<text class="lab" x="${x(pw[1]) + 5}" y="${m.t + 8}">7-day test window</text>`;
    }
    return s + '</svg>';
  }
  function luckPanel(e) {
    const c = e.contrast, v = c.in_time.values_logpts.map(x => Math.abs(x - c.in_time.centre) * 100), real = Math.abs(c.d_logpts - c.in_time.centre) * 100;
    const w = 420, h = 100, bins = 26, mx = Math.max(real * 1.08, Math.max(...v) * 1.1), cnt = new Array(bins).fill(0);
    v.forEach(x => cnt[Math.min(bins - 1, Math.floor(x / mx * bins))]++);
    const top = Math.max(...cnt), bw = (w - 20) / bins;
    let sv = `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${c.in_time.n} pseudo-storms at the same date in other years: the size of the Florida-minus-donors gap each produced. The real storm's gap of ${Math.round(real)} points sits beyond every one of them.">`;
    cnt.forEach((n, i) => { const bx = i * bw, bh = n / top * (h - 34); sv += `<rect class="bar ${i * mx / bins >= real ? 'tail' : ''}" x="${bx + 1}" y="${h - 20 - bh}" width="${bw - 2}" height="${bh}" rx="1.5"/>`; });
    const rx = Math.min(w - 20, real / mx * (w - 20));
    sv += `<line class="you" x1="${rx}" x2="${rx}" y1="4" y2="${h - 20}"/><text class="lab strong" x="${rx - 6}" y="12" text-anchor="end">this storm, ${Math.round(real)} pts</text><text class="lab" x="0" y="${h - 5}">${c.in_time.n} pseudo-storms, same dates in other years</text><text class="lab" x="${w - 20}" y="${h - 5}" text-anchor="end">bigger gap →</text></svg>`;
    return `<div class="luck">${sv}<p>${c.in_time.n_bigger === 0 ? 'None' : c.in_time.n_bigger} of the ${c.in_time.n} pseudo-storms came close (in-time p ${c.p_time}). Against ${c.n_donors} unaffected regions shuffled into 30 fake Floridas, the real pair ranked first: about <b>1 in ${c.p_space_odds}</b>. Both placebo families agree, which is what the engine calls a strong regional pass.</p></div>`;
  }
  function replicationRow(r) {
    const pips = r.all.map(s => `<i class="${s.pass ? '' : s.effect_pct < 0 ? 'dir' : 'no'}" title="${esc(s.label)} ${s.year}: ${s.effect_pct}%"></i>`).join('');
    return `<div class="repl"><span class="pips" aria-hidden="true">${pips}</span><span>Passed after <b class="num">${r.n_seen} of ${r.n_similar}</b> past storms tested; <span class="num">${r.n_same_direction}</span> moved the same way</span></div>
      <p style="font-size:13px;color:var(--muted);margin-top:6px">${r.examples.map(x => `${esc(x.label)}, ${x.effect_pct}%`).join('; ')}. ${esc(r.family.note)} <a href="#past" data-scroll="past" style="color:var(--accent-ink);font-weight:500">Flip through them</a>.</p>`;
  }
  function watchRow(hop) {
    const w = hop ? { ...P.watching, window_close: hop.window_close, prior: hop.prior, name: hop.name } : P.watching, a = new Date(w.window_start), b = new Date(w.window_close), now = new Date(), total = Math.max(1, (b - a) / 864e5), done = Math.min(1, Math.max(0, (now - a) / 864e5 / total));
    return `<div class="sect" id="next"><h3>What happens next</h3><div class="win"><div class="bar"><span class="fill" style="width:${Math.round(done * 100)}%"></span><i style="left:0"></i><b style="left:0;transform:none">${fmtDayY(w.window_start)}, registered</b><i class="q" style="left:100%"></i><b style="left:100%;transform:translateX(-100%)">${fmtDayY(w.window_close)}, window closed</b></div>
      <p>${esc(w.text)} Prior for ${esc(w.name.toLowerCase())}: <b class="num">${Math.round(w.prior * 100)}%</b>.</p></div><div class="why keep"><button class="btn primary" type="button" data-watch>${watched() ? 'Watching this ripple' : 'Keep watching'}</button></div></div>`;
  }
  function drawers(e) {
    const c = e.contrast, L = e.ledger, led = P.ledger;
    const row = (k, v, h) => `<dt>${k}</dt><dd${h ? ' class="h"' : ''}>${v}</dd>`;
    return `<details class="drawer"><summary>The raw numbers</summary><dl class="dl">
      ${row('Treated regions', c.treated.join(' + ') + ' (Florida)')}${row('Donor regions', c.n_donors)}${row('Window', `${c.window.pre_days} d before, ${c.window.post_days} d after ${fmtDayY(c.window.onset)}`)}
      ${row('Treated change alone', c.treated_only_pct + '%')}${row('Contrast (treated − donors)', c.d_logpts + ' log pts = ' + c.effect_pct + '%')}${row('Centred on in-time median', c.d_centred + ' log pts')}
      ${row('Robust se (1.4826 · MAD)', c.se)}${row('z', c.z)}${row('Peak day', fmtDayY(e.chart.peak.d) + ', Florida ' + Math.round(e.chart.peak.t * 100) + '% vs donors ' + Math.round(e.chart.peak.o * 100) + '%')}
      </dl><p><a href="${esc(P.links.csv)}" download>Download the daily series (CSV)</a>. Values are each region’s demand divided by its own mean over ${fmtDay(e.chart.pre_window[0])}–${fmtDay(e.chart.pre_window[1])}.</p></details>
      <details class="drawer"><summary>Baseline, lag and pre-trends</summary><dl class="dl">${row('Baseline', 'season-matched: the same dates in every other panel year, never after the event')}${row('Lag', `${e.lag_days} days to the peak gap; the pre-registered window has no lag`)}
      ${row('Leads (3 blocks before onset)', c.leads.join(', '))}${row('Pre-trend p', c.p_pre + ' (flat: p ≥ 0.10)')}</dl></details>
      <details class="drawer"><summary>Placebos, synthetic control, multiple testing</summary><dl class="dl">${row('In-space p (30 fake Floridas)', `${c.p_space} (1 in ${c.p_space_odds})`)}${row('In-time p (' + c.in_time.n + ' pseudo-storms)', c.p_time)}
      ${row('Synthetic control', `${c.synth_d} log pts, same sign; RMSPE ratio ${c.synth_ratio}, rank p ${c.synth_p}`)}${row('Family q (24 hurricanes, BH)', e.replication.family.q + ' — ' + e.replication.family.strength)}
      ${row('Decoy false-alarm rate (120 sets)', `${Math.round(P.calibration.decoy_fp_rate * 1000) / 10}% [${P.calibration.wilson.map(x => Math.round(x * 1000) / 10).join(', ')}]`)}</dl>
      <p>The single-event test (engine ${P.engine.method_hop}) that gives Measured or Likely has not run on this hop; its channels, fluke rate and FDR q are therefore empty. The forecast gate has not evaluated it.</p></details>
      <details class="drawer"><summary>Ledger and provenance</summary><dl class="dl">${row('Hop ids', e.hop_ids.join(', '))}${row('Registered', `seq ${L.register_seq}, ${fmtDayY(led[0].day)}`)}${row('Register hash', led[0].payload_hash, 1)}
      ${row('Grid frozen', `seq ${L.freeze_seq}, batch ${esc(P.engine.batch)}`)}${row('Grid hash', L.frozen_hash, 1)}${row('Model versions', L.model_seq.join(', ') + ' (6.2, 6.2.1)')}${row('Calibration', 'seq ' + L.calibration_seq)}
      ${row('Chain head', `seq ${L.head.seq}`)}${row('Head hash', L.head.chain_hash, 1)}${row('Computed', c.computed_at.slice(0, 16).replace('T', ' ') + ' UTC')}</dl><p><a href="${esc(P.links.method)}">How Ripple Map knows</a>.</p></details>`;
  }
  const glyph = t => `<svg aria-hidden="true"><use href="#g-${t === 'measured' ? 'measured' : t === 'likely' || t === 'contrast' ? 'half' : t === 'pattern' ? 'rule' : 'dotted'}"/></svg>`;

  /* ---------- the stop card ---------- */
  const panel = $('#panel'), body = $('#panel-body'), scrim = $('#scrim');
  let current = null, currentKind = null;
  function showPanel() { panel.hidden = false; requestAnimationFrame(() => { panel.classList.add('open'); if (compact) scrim.classList.add('on'); document.body.classList.add('panel-open'); panel.scrollTo({ top: 0 }); $('#close').focus({ preventScroll: true }); }); }
  function highlight(id) {
    const Sv = $('#pond');
    Sv.querySelectorAll('.effect, .shore-mark, .float').forEach(g => { g.classList.toggle('active', g.dataset.id === id); g.classList.toggle('dim', g.dataset.id !== id); });
  }
  function open(id, kind) {
    if (kind === 'effect' || (!kind && id === E.id)) return openEffect(id);
    if (kind === 'shore') return openShore(id);
    if (kind === 'untested') return openUntested(id);
    if (kind === 'flat') return openFlat(id);
  }
  function openEffect(id) {
    const e = P.effects.find(x => x.id === id); if (!e) return; current = id; currentKind = 'effect'; track('stop_open');
    const r = e.replication;
    body.innerHTML = `
      <p class="crumb">${esc(P.domains[e.domain])}, ${esc(e.lag_text)}. This ripple <b>forks straight from the storm</b>: no chain through another stop is claimed.</p>
      <span class="chip contrast">${glyph('contrast')}${esc(tierWord(e))}<em>engine tier ${esc(TIER[P.effects[0].tier === 'contrast' ? 'watching' : e.tier])}, test queued</em></span>
      <h2>${esc(e.title)}</h2>
      <div class="big num">${esc(e.num)}<small>${esc(e.unit)}</small></div>
      <p class="find">${esc(e.plain)}</p>
      <div class="agree"><span><i></i>Moved against ${e.contrast.n_donors} unaffected regions, pre-trends flat</span><span><i class="o"></i>${esc(e.sources.text)}</span><span><i class="${r.n_seen ? '' : 'o'}"></i>Passed after ${r.n_seen} of ${r.n_similar} similar storms</span></div>
      <div class="why"><button class="btn primary" type="button" data-why>Why?</button><button class="btn" type="button" data-send>Send this</button><button class="btn" type="button" data-watch aria-pressed="${watched()}">${watched() ? 'Watching' : 'Watch'}</button></div>
      <div class="chart">${seriesChart(e)}</div>
      <div class="legend"><span><i class="l"></i>Florida (FPL + Duke Florida)</span><span><i class="l2"></i>51 unaffected regions</span><span><i></i>Normal gap before the storm</span></div>
      <div class="sect" id="why"><h3>Why? How the ripple got there</h3><ul class="steps">${e.mechanism.map((m, i) => `<li><i class="${i === 0 ? 'f' : ''}"></i><span>${esc(m.step)}<small>${esc(m.why)} Source: ${esc(m.source)}.</small></span></li>`).join('')}</ul></div>
      <div class="sect" id="luck"><h3>Could it be luck?</h3>${luckPanel(e)}<p style="margin-top:8px">${esc(e.how)}</p></div>
      <div class="sect"><h3>What would change our mind</h3><p>${esc(e.mind)}</p></div>
      <div class="sect" id="seen"><h3>Seen before?</h3>${replicationRow(r)}</div>
      ${watchRow()}
      <div class="sect"><h3>In plain words</h3><p><b>Regional contrast passed.</b> Florida’s grids fell while 51 regions the storm missed did not, and fake storms at the same dates in other years never produce a gap this size. <b>Not Measured.</b> Measured needs the single-event test and an independent forecast model to agree, and neither has run on this storm yet. Consistent with, never proof of cause.</p></div>
      <div class="sect" id="deep"><h3>Deep evidence</h3>${drawers(e)}</div>
      <div class="sect more"><h3>This wasn’t the end</h3><p>What else did Milton touch? Storms like it usually reach one more shore.</p><button class="btn" type="button" data-more="${S.id}" data-more-kind="shore">One more<svg width="14" height="14" aria-hidden="true"><use href="#i-arrow"/></svg></button></div>`;
    wire(); highlight(id); showPanel();
  }
  function openShore(id) {
    const s = P.shore.find(x => x.id === id); if (!s) return; current = id; currentKind = 'shore'; track('stop_open');
    const p = s.pattern;
    const pips = p.all.map(x => `<i class="${x.pass ? '' : x.effect_pct < 0 ? 'dir' : 'no'}" title="${esc(x.label)} ${x.year}: ${x.effect_pct}%"></i>`).join('');
    body.innerHTML = `
      <p class="crumb">${esc(P.domains[s.domain])}, four weeks on. <b>The far shore.</b> A rule about ${p.n_events} past hurricanes, drawn on the bank because it is not evidence about Milton.</p>
      <span class="chip pattern">${glyph('pattern')}${esc(p.strength)}<em>${esc(p.fluke_note)}</em></span>
      <h2>${esc(s.title)}</h2>
      <div class="big num">${esc(s.num)}<small>${esc(s.unit)}</small></div>
      <p class="find">${esc(s.plain)}</p>
      <div class="agree"><span><i></i>Pooled across ${p.n_events} hurricanes since 2019 (${p.n_clustered_out} overlapping storms removed)</span><span><i></i>Survives correction over 25 pre-registered pairs (q ${Math.round(p.q * 1000) / 1000})</span><span><i class="o"></i>Milton: not pre-registered for this series, untested</span></div>
      <div class="why"><button class="btn primary" type="button" data-why>Why?</button><button class="btn" type="button" data-send>Send this</button></div>
      <div class="sect" id="why"><h3>Why? How storms reach here</h3><ul class="steps"><li><i class="f"></i><span>Would-be founders lose premises, savings and customers<small>Uninsured losses and closed storefronts delay new ventures. Source: mechanism library.</small></span></li><li><i></i><span>Applications to start a business slip for about a month<small>Weekly Census filings in the hit states run below unaffected states, then recover. Source: Census Business Formation Statistics, weekly by state.</small></span></li><li><i></i><span>The effect is concentrated in the big landfalls<small>Marco, Laura, Sally, Delta and Hilary carry most of it (heterogeneity I² ${p.i2}). Source: engine 6.2 pool.</small></span></li></ul></div>
      <div class="sect" id="luck"><h3>Could it be luck?</h3><p>300 fake pools, each built from one pseudo-storm per real storm at the same dates in other years, produced an effect this large about <b class="num">1 in ${Math.round(1 / p.p_placebo)}</b> times (placebo p ${p.p_placebo.toFixed(3)}). Across 120 decoy families the engine raised a false alarm ${Math.round(P.calibration.decoy_fp_rate * 100)}% of the time, so a single strong pattern still carries roughly that fluke risk: ${esc(p.fluke_note)}.</p></div>
      <div class="sect" id="seen"><h3>Seen before?</h3><div class="repl"><span class="pips" aria-hidden="true">${pips}</span><span>Fell after <b class="num">${p.fell_after} of ${p.of}</b> hurricanes</span></div><p style="font-size:13px;color:var(--muted);margin-top:6px">Largest: ${p.examples.map(x => `${esc(x.label)} ${x.effect_pct}%`).join('; ')}. Confidence interval ${p.ci[0]}% to ${p.ci[1]}%: the top end touches zero.</p></div>
      <div class="sect"><h3>In plain words</h3><p><b>Strong pattern.</b> Across many storms, new-business filings in the hit states dip for a month. <b>Not a finding about Milton:</b> nobody registered this series for it, so the pond shows it on the bank, where the ripple would land if it reaches. Consistent with, never proof of cause.</p></div>
      <div class="sect" id="deep"><h3>Deep evidence</h3><details class="drawer"><summary>The raw numbers</summary><dl class="dl"><dt>Pooled effect</dt><dd>${p.effect_logpts} log pts = ${p.effect}%</dd><dt>95% CI</dt><dd>${p.ci[0]}% to ${p.ci[1]}%</dd><dt>Events (after overlap rule)</dt><dd>${p.n_events} (${p.n_clustered_out} removed)</dd><dt>I²</dt><dd>${p.i2}</dd><dt>Placebo p / normal p</dt><dd>${p.p_placebo.toFixed(4)} / ${p.p_norm.toFixed(3)}</dd><dt>BH q</dt><dd>${p.q.toFixed(4)}</dd><dt>Dose–response</dt><dd>slope ${p.dose.slope_per_unit}, p ${p.dose.p.toFixed(2)}</dd><dt>Regional passes / flat pre-trends</dt><dd>${p.n_regional_pass} / ${p.n_pretrend_flat}</dd><dt>Window</dt><dd>${p.window.pre} wk before, ${p.window.post} wk after</dd><dt>Ledger</dt><dd>freeze seq ${p.ledger_seq}</dd></dl></details></div>
      <div class="sect more"><h3>This wasn’t the end</h3><p>One more, in another family: what cold snaps do to the same grids.</p><button class="btn" type="button" data-more="next">One more<svg width="14" height="14" aria-hidden="true"><use href="#i-arrow"/></svg></button></div>`;
    wire(); highlight(id); showPanel();
  }
  function openUntested(id) {
    const u = P.untested.find(x => x.id === id); if (!u) return; current = id; currentKind = 'untested'; track('stop_open');
    const others = P.untested.filter(x => x.id !== id);
    body.innerHTML = `
      <p class="crumb">${esc(P.domains[u.domain])}, window closed ${fmtDayY(u.window_close)}. Registered before anyone looked.</p>
      <span class="chip untested">${glyph('untested')}Pre-registered, untested<em>hop ${u.hop_id}</em></span>
      <h2>${esc(u.name)}</h2>
      <div class="flat-hero">Not tested yet.</div>
      <p class="find">${esc(u.plain)}</p>
      ${u.mechanism ? `<div class="sect"><h3>Why it was registered</h3><p>${esc(u.mechanism.replace('->', '→'))}. Source: mechanism library v6.0, template ${esc(u.path_type === 'P-MECH' ? 'mechanism path' : 'family map')}.</p></div>` : `<div class="sect"><h3>Why it was registered</h3><p>Mapped from the storm family: every hurricane gets this series checked. Source: family mapper.</p></div>`}
      <div class="sect"><h3>Why we show it</h3><p>Hiding an untested series would make the one bright pad look like the whole story. When the queued test runs, this float becomes a pad if it moved, reeds if it stayed flat, or stays dotted if the data cannot say. The engine’s cascade currently files it under “window closed, no move”; that is a bookkeeping word, not a measurement, so the pond does not draw reeds here.</p></div>
      ${watchRow(u)}
      <div class="sect"><h3>Also waiting</h3><div class="chips" style="display:flex;flex-wrap:wrap;gap:6px">${others.map(o => `<button type="button" class="btn" style="padding:4px 10px;font-size:12.5px;border-color:var(--pline-2);color:var(--ink-2)" data-more="${o.id}" data-more-kind="untested">${esc(o.name)}</button>`).join('')}</div></div>`;
    wire(); highlight(id); showPanel();
  }
  function openFlat(id) {
    const n = (P.flats || []).find(x => x.id === id); if (!n) return; current = id; currentKind = 'flat';
    body.innerHTML = `<p class="crumb">${esc(P.domains[n.domain])}. Checked in advance, on purpose.</p><span class="chip flat">${glyph('flat')}Stayed flat</span><div class="flat-hero">The ripple stopped here.</div><p class="find">${esc(n.name)} stayed inside its normal range for the whole window we pre-registered.</p>`;
    wire(); highlight(id); showPanel();
  }
  function wire() {
    body.querySelectorAll('[data-more]').forEach(mb => mb.addEventListener('click', () => { track('one_more'); const k = mb.dataset.moreKind; if (mb.dataset.more === 'next') { closePanel(); $('#onemore').scrollIntoView({ behavior: reduce ? 'auto' : 'smooth' }); return; } open(mb.dataset.more, k); }));
    const wb = body.querySelector('[data-why]'); if (wb) wb.addEventListener('click', () => { track('why_open'); $('#why', body).scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' }); });
    body.querySelectorAll('[data-send]').forEach(b => b.addEventListener('click', send));
    body.querySelectorAll('[data-watch]').forEach(b => b.addEventListener('click', () => { toggleWatch(); b.textContent = watched() ? (b.classList.contains('primary') ? 'Watching this ripple' : 'Watching') : (b.classList.contains('primary') ? 'Keep watching' : 'Watch'); b.setAttribute('aria-pressed', watched()); }));
    body.querySelectorAll('[data-scroll]').forEach(a => a.addEventListener('click', ev => { ev.preventDefault(); track('seen_before_open'); closePanel(); $('#' + a.dataset.scroll).scrollIntoView({ behavior: reduce ? 'auto' : 'smooth' }); }));
    const luck = body.querySelector('#luck'); if (luck) { const io = new IntersectionObserver(en => { if (en.some(x => x.isIntersecting)) { track('luck_open'); io.disconnect(); } }, { root: panel, threshold: .5 }); io.observe(luck); }
    const seen = body.querySelector('#seen'); if (seen) { const io2 = new IntersectionObserver(en => { if (en.some(x => x.isIntersecting)) { track('seen_before_open'); io2.disconnect(); } }, { root: panel, threshold: .5 }); io2.observe(seen); }
  }
  function closePanel() {
    panel.classList.remove('open'); scrim.classList.remove('on'); document.body.classList.remove('panel-open');
    setTimeout(() => { if (!panel.classList.contains('open')) panel.hidden = true; }, 360);
    $('#pond').querySelectorAll('.effect, .shore-mark, .float').forEach(g => g.classList.remove('active', 'dim'));
    const back = current && $('#pond').querySelector(`[data-id="${current}"]`); if (back) back.focus({ preventScroll: true });
    current = null;
  }
  $('#close').addEventListener('click', closePanel);
  scrim.addEventListener('click', closePanel);
  addEventListener('keydown', ev => { if (ev.key === 'Escape' && current) closePanel(); });

  /* ---------- send ---------- */
  const url = P.links.site;
  const shareText = () => `${P.story.story_sentence}\n${P.story.conversation_hook}\n${P.story.share_line}\n${url}`;
  let tt; function toast(msg) { const t = $('#toast'); t.textContent = msg; t.classList.add('on'); clearTimeout(tt); tt = setTimeout(() => t.classList.remove('on'), 2400); }
  function copy(text) { const ok = () => toast('Copied. Paste it anywhere.'); if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text).then(ok, () => fallbackCopy(text, ok)); fallbackCopy(text, ok); }
  function fallbackCopy(text, ok) { const ta = document.createElement('textarea'); ta.value = text; ta.setAttribute('aria-hidden', 'true'); ta.style.cssText = 'position:fixed;top:-100px;opacity:0'; document.body.append(ta); ta.select(); try { document.execCommand('copy'); ok(); } catch { toast('Select the text to copy it'); } ta.remove(); }
  function send() {
    track('send');
    if (navigator.share) { navigator.share({ title: P.story.short_title, text: shareText(), url }).catch(err => { if (!err || err.name !== 'AbortError') copy(shareText()); }); return; }
    copy(shareText());
  }
  $('#btn-send').addEventListener('click', send);

  /* ---------- watch (device-local) and while you were gone ---------- */
  const WK = 'rm.pond.watch', VK = 'rm.pond.seen';
  const watchState = () => { try { return JSON.parse(ls.get(WK) || '{}'); } catch { return {}; } };
  const watched = () => !!watchState()[P.event.slug];
  function toggleWatch() { const w = watchState(); if (w[P.event.slug]) delete w[P.event.slug]; else { w[P.event.slug] = { version: P.version, at: new Date().toISOString().slice(0, 10) }; track('watch'); } ls.set(WK, JSON.stringify(w)); syncWatchBtn(); toast(watched() ? 'Watching. We keep the changes for you on this device.' : 'No longer watching.'); }
  function syncWatchBtn() { const b = $('#btn-watch'); b.setAttribute('aria-pressed', watched()); b.lastChild.textContent = watched() ? 'Watching this ripple' : 'Watch this ripple'; }
  $('#btn-watch').addEventListener('click', toggleWatch); syncWatchBtn();
  (function gone() {
    let seen = null; try { seen = JSON.parse(ls.get(VK) || 'null'); } catch { seen = null; }
    const w = watchState()[P.event.slug];
    if (seen && (w || seen.version < P.version)) {
      const since = P.changelog.filter(c => c.version > (w ? w.version : seen.version));
      const box = $('#gone'); box.hidden = false;
      box.innerHTML = `<div><b>While you were gone</b><span>${since.length ? since.map(c => `${esc(c.text)} (v${c.version}, ${fmtDay(c.at)})`).join(' ') : `Nothing has changed on this ripple since ${fmtDay(seen.at)}. Twelve tests are still queued; the snapshot is v${P.version}.`}</span></div>`;
    }
    ls.set(VK, JSON.stringify({ version: P.version, at: new Date().toISOString().slice(0, 10) }));
    try { const src = new URLSearchParams(location.search).get('src'); const ext = document.referrer && !/bensunter\.com/.test(document.referrer); if ((src || ext) && !sessionStorage.getItem('ko.land')) { sessionStorage.setItem('ko.land', '1'); track('landing'); } } catch { /* ignore */ }
  })();

  /* ---------- the shore: cards ---------- */
  const chain = $('#chain-list');
  chain.innerHTML = `<li><div class="card event">
      <div class="k"><span>The stone</span><span>${esc(P.event.strength)}</span></div>
      <div class="ev">${esc(P.event.name)} makes landfall</div>
      <p class="ev-sub">${esc(P.event.place)}, ${esc(P.event.date)}. Engine onset ${fmtDay(P.event.onset)}, the day it was registered.</p>
      <div class="strip"><div>Shock size<b>not scored</b></div><div>Series registered<b class="num">${P.untested.length + 2}</b></div><div>Tested<b class="num">1</b></div><div>Measured<b class="num">${P.honesty.measured}</b></div></div>
    </div></li>
    <li><button class="card" type="button" data-open="${E.id}" data-kind="effect">
      <div class="k"><span class="step">${glyph('contrast')}${esc(tierWord(E))}</span><span>${esc(P.domains[E.domain])}, ${esc(E.lag_text)}</span></div>
      <div class="n num">${esc(E.num)}<small>${esc(E.unit)}</small></div>
      <p class="f">${esc(E.plain.split('. ')[0])}.</p>
      <div class="spark chart">${seriesChart(E, 320, 56, true)}</div>
      <div class="foot"><span>Forks straight from the storm</span><span class="open">See the evidence</span></div>
    </button></li>
    <li><button class="card rule" type="button" data-open="${S.id}" data-kind="shore">
      <div class="k"><span class="step">${glyph('pattern')}${esc(S.pattern.strength)}</span><span>${S.pattern.n_events} hurricanes</span></div>
      <div class="n num">${esc(S.num)}<small>${esc(S.unit)}</small></div>
      <p class="f">${esc(S.story.story_sentence)} Milton itself is untested on this.</p>
      <div class="foot"><span>The far shore: a rule, not a Milton result</span><span class="open">See the rule</span></div>
    </button></li>
    <li><div class="card wait"><div class="k"><span>Waiting for their test</span><span>${P.untested.length} series</span></div><p class="f" style="color:var(--ink-2)">Registered on ${fmtDay(P.event.cascade.baseline.to === '2024-09-16' ? '2024-10-08' : '2024-10-08')} 2024 with windows and priors written down first. Every window has closed; none has been scored.</p>
      <div class="chips">${P.untested.map(u => `<button type="button" data-open="${u.id}" data-kind="untested"><svg aria-hidden="true"><use href="#k-float"/></svg>${esc(u.name)}</button>`).join('')}</div></div></li>
    <li><div class="card note"><div class="k"><span>Rings that overlap</span><span>${P.rivals[0].days_before} days apart</span></div><p><b>${esc(P.rivals[0].name)}</b> came ashore ${P.rivals[0].days_before} days before Milton and sits inside the 28-day pre-window. ${esc(P.rivals[0].note.split('. ').slice(1).join('. '))}</p></div></li>
    <li><div class="card note"><div class="k"><span>Filtered out</span><span>1 boulder</span></div><p><b>${esc(P.filtered[0].name)}</b>: ${esc(P.filtered[0].note)}</p></div></li>`;
  chain.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => open(b.dataset.open, b.dataset.kind)));

  /* replication strip: tiny ponds for the 24 past hurricanes on the same test */
  $('#past-h').textContent = `Passed after ${E.replication.n_seen} of ${E.replication.n_similar} past storms`;
  $('#past-lead').textContent = `The same grid-demand contrast, storm by storm since 2019. A half pad means the regional test passed; reeds mean it did not, whichever way demand moved. ${E.replication.family.note}`;
  const row = $('#past-row');
  E.replication.all.forEach(st => {
    const card = document.createElement('div'); card.className = 'past-card' + (st.pass ? '' : ' no'); card.setAttribute('role', 'img'); card.setAttribute('aria-label', `${st.label} ${st.year}: grid demand ${st.effect_pct}% against unaffected regions, ${st.pass ? 'regional test passed' : 'no pass'}`);
    const sv = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); card.appendChild(sv);
    Pond.render(sv, { event: { name: st.label, magnitude: .5, label: false }, domains: P.domains, rings: P.rings,
      effects: st.pass ? [{ id: 'c', domain: E.domain, lag_days: E.lag_days, magnitude: Math.min(1, Math.abs(st.effect_pct) / 25), tier: 'contrast', kind: 'pad', num: '', short: '', headline: '', plain: '' }] : [],
      flats: st.pass ? [] : [{ name: 'Grid demand', domain: E.domain, lag_days: E.lag_days }] }, { thumb: true, reduceMotion: true, viewBox: [-470, -470, 940, 940] });
    card.insertAdjacentHTML('beforeend', `<div class="pn">${esc(st.label.replace(/^(Hurricane|Tropical storm) /, ''))}<small class="num">${st.year}</small></div><div class="ps"><b>${st.effect_pct > 0 ? '+' : ''}${st.effect_pct}%</b> ${st.pass ? 'passed' : 'no pass'}</div>`);
    row.appendChild(card);
  });
  const me = document.createElement('div'); me.className = 'past-card'; me.setAttribute('aria-current', 'true'); me.setAttribute('role', 'img'); me.setAttribute('aria-label', `Milton 2024: ${E.contrast.effect_pct}%, regional test passed`);
  const msv = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); me.appendChild(msv);
  Pond.render(msv, { event: { name: 'Milton', magnitude: .5, label: false }, domains: P.domains, rings: P.rings, effects: [{ id: 'c', domain: E.domain, lag_days: E.lag_days, magnitude: E.magnitude, tier: 'contrast', kind: 'pad', num: '', short: '', headline: '', plain: '' }] }, { thumb: true, reduceMotion: true, viewBox: [-470, -470, 940, 940] });
  me.insertAdjacentHTML('beforeend', `<div class="pn">Milton<small class="num">2024</small></div><div class="ps"><b>${esc(E.num)}</b> passed</div>`);
  row.prepend(me);

  /* the ripple stopped here: honest when there are no flats */
  const sb = $('#stopped-body');
  if (P.flats.length) sb.innerHTML = `<p>${P.flats.length} things we said in advance might move, and didn’t.</p><div class="waiting">${P.flats.map(n => `<button type="button" data-open="${n.id}" data-kind="flat"><svg aria-hidden="true"><use href="#k-grass"/></svg>${esc(n.name)}</button>`).join('')}</div>`;
  else sb.innerHTML = `<p><b>Nowhere, yet.</b> ${esc(P.flats_note)} Three negative controls (${P.controls.map(c => esc(c.name.replace(' (control)', ''))).join(', ')}) were registered alongside them so a nationwide move could not pass as Florida’s.</p><div class="waiting">${P.untested.map(u => `<button type="button" data-open="${u.id}" data-kind="untested"><svg aria-hidden="true"><use href="#k-float"/></svg>${esc(u.name)}</button>`).join('')}</div>`;
  sb.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => open(b.dataset.open, b.dataset.kind)));

  /* one more: the next best real story, a world rule in another family */
  const N = P.pattern_next;
  const bars = P.shore[0].pattern.all.slice().sort((a, b) => a.effect_pct - b.effect_pct);
  $('#onemore').innerHTML = `<div><h3>This wasn’t the end</h3><p class="lead">One more. The same grids, a different kind of weather: what the engine finds when it pools every cold snap since 2015.</p>
      <a class="card" href="${esc(N.url)}?src=pond" data-onemore><div class="k"><span class="step">${glyph('pattern')}${esc(N.strength)}</span><span>${N.n_events} cold snaps</span></div>
      <p class="big-p">${esc(N.story.story_sentence)}</p>
      <p style="font-size:14px;color:var(--ink-2);margin:6px 0 0">Confidence interval ${N.ci[0]}% to ${N.ci[1]}%; ${esc(N.fluke_note)}. Largest: ${N.examples.map(x => `${esc(x.label.replace(/ \(\d+ states\)/, ''))} +${Math.round((Math.exp(x.d) - 1) * 100)}%`).join('; ')}.</p>
      <div class="foot"><span>What’s been moving the Real world?</span><span class="open">Open the land</span></div></a></div>
    <div><h3>Where storms usually reach</h3><p class="lead">Each bar is one past hurricane’s effect on new-business applications in the hit states, against unaffected states. The rule behind the cairn on the far shore.</p>
      <div class="card"><div class="dots" aria-hidden="true">${bars.map(b => `<i style="height:${Math.round(Math.min(100, Math.abs(b.effect_pct) / 25 * 100))}%;${b.effect_pct > 0 ? 'opacity:.35' : ''}" class="${b.pass ? 'm' : ''}" title="${esc(b.label)} ${b.effect_pct}%"></i>`).join('')}</div>
      <p style="font-size:12.5px;color:var(--muted);margin-top:6px">${bars.length} storms tested, sorted (${S.pattern.n_events} once overlapping storms are merged). Dark bars passed the regional test; faint bars moved the other way. Milton is not among them: it was not registered for this series.</p></div></div>`;
  $('[data-onemore]').addEventListener('click', () => track('one_more'));
})();
