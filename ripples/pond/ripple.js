/* Ripple Map v1: the ripple page. Renders any event's pond payload (the milton.json shape, or one built from the story layer),
   runs the signature reveal, opens the stop card, and handles Send / Share / Watch / Follow this / While you were gone.
   No number on the page is typed here. Tier words come from the gated published tier only (D-14/D-16). */
(async function () {
  const { $, esc, fmtDay, fmtDayY, TIER, ROOT, reduce, compact } = RM;
  RM.nav('now');
  document.body.classList.add('loading');
  const q = new URLSearchParams(location.search);
  const pathSlug = (location.pathname.match(/\/r\/([^/]+)\/?$/) || [])[1];
  let slug = q.get('e') || (pathSlug && pathSlug !== 'r' ? decodeURIComponent(pathSlug) : null);

  /* ---------- data ---------- */
  let P;
  try {
    if (!slug) { const reg = await RM.data.registry(); slug = (reg.events.find(e => e.flagship) || reg.events[0]).slug; }
    P = await RM.data.pond(slug);
  } catch (e) { P = null; }
  if (!P) { document.body.classList.remove('loading', 'hook'); $('#h1').textContent = 'No ripple here.'; $('#traced-sub').textContent = 'That event has no published pond yet. Try Wander, or go back to Now.'; $('#follow-hero').innerHTML = `<a href="${ROOT}wander/">Wander to a live ripple<span class="go">Go</span></a><a href="${ROOT}">Now<span class="go">Home</span></a>`; $('.stage').hidden = true; $('#shore').hidden = true; return; }
  RM.analytics('pond_ripple', P.analytics && P.analytics.kinds);
  RM.sawRipple(P.event.slug);
  const quiet = !!(P.honesty && P.honesty.quiet) || !!P.event.sensitive;
  if (quiet) document.body.classList.add('quiet');
  const isMilton = !!(P.effects[0] && P.effects[0].contrast);

  /* ---------- the hero object: the best stop by tier, else the open mystery, else the dead end ---------- */
  const rank = { measured: 3, likely: 2, contrast: 2, watching: 1 };
  const tierOf = e => e.published ? e.published.tier : e.tier;
  const E = P.effects.slice().sort((a, b) => (rank[tierOf(b)] || 0) - (rank[tierOf(a)] || 0) || (b.magnitude || 0) - (a.magnitude || 0))[0] || null;
  const U0 = (P.untested || [])[0] || null, F0 = (P.flats || [])[0] || null, S = (P.shore || [])[0] || null;
  const hero = E ? { kind: 'effect', o: E } : U0 ? { kind: 'untested', o: U0 } : F0 ? { kind: 'flat', o: F0 } : null;
  const stopParam = q.get('stop');
  const tierWord = e => e.published ? TIER[e.published.tier] : TIER[e.tier];          // the published tier is exactly what the gate returned
  const tierLine = e => e.published && e.published.reason ? e.published.text : tierWord(e);
  const NUMW = ['No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve'];
  const numw = n => NUMW[n] || String(n);
  const noun = (P.event.family || '').startsWith('hazard.storm') ? 'storm' : (P.event.family || '').startsWith('hazard') ? 'event' : (P.event.family === 'person') ? 'name' : 'event';
  const ev = P.event, name = ev.name;
  const src = P._src === 'live' ? 'live engine data' : P._src === 'stories' ? 'story layer, live' : `engine snapshot ${(P.snapshot_at || '').slice(0, 10)}`;

  /* ---------- hero copy (from the story and published fields; the frontend composes only the connective tissue) ---------- */
  $('#kicker').innerHTML = `${esc(name)} <span class="num">${esc(ev.date || fmtDayY(ev.onset))}</span> <span class="tag-src">${esc(src)}${quiet ? ', shown quietly' : ''}</span>${ev.is_control ? `<span class="tag-src" title="${esc((P.honesty && P.honesty.control_note) || 'A known-effect test case')}">known-effect test case</span>` : ''}`;
  if (P.story && (P.story.archetype || P.story.kind === 'cascade')) $('#arch').innerHTML = RM.archTag(P.story.archetype) + (P.story.archetype ? `<small style="font-size:12px;color:var(--text-3);margin-left:8px">${esc(RM.archText(P.story.archetype))} A story label, not evidence.</small>` : '');
  const hook = (P.story && P.story.hook) || (hero ? hero.kind === 'effect' ? `${hero.o.lag_text ? hero.o.lag_text[0].toUpperCase() + hero.o.lag_text.slice(1) : 'Afterwards'}, something moved in ${hero.o.short}.` : hero.kind === 'untested' ? `Something is still being watched in ${hero.o.name}.` : `The expected move in ${hero.o.name} never came.` : 'Nothing has resolved yet.');
  const H1 = { hook: `${esc(name)}. <span class="quiet">${esc(hook)}</span>` };
  const nMeasured = P.effects.filter(e => tierOf(e) === 'measured').length, nMoved = P.effects.length, nFlat = (P.flats || []).length, nWatch = (P.untested || []).length;
  // tier-driven traced headline: the word Measured appears only when a published tier is measured
  H1.traced = nMoved ? `One ${noun}.<br>${numw(nMoved)} ripple${nMoved === 1 ? '' : 's'}${nMeasured === nMoved ? ', measured' : nMeasured ? `, ${nMeasured} measured` : ''}.<br><span class="quiet">${nFlat ? `${numw(nFlat)} thing${nFlat === 1 ? '' : 's'} that stayed flat.` : nWatch ? `${numw(nWatch)} still being watched.` : ''}</span>`
    : nWatch ? `One ${noun}.<br>${numw(nWatch)} open question${nWatch === 1 ? '' : 's'}.<br><span class="quiet">${nFlat ? `${numw(nFlat)} thing${nFlat === 1 ? '' : 's'} that stayed flat.` : 'The rings are still travelling.'}</span>`
    : `One ${noun}.<br>The pond stayed still.<br><span class="quiet">${numw(nFlat)} thing${nFlat === 1 ? '' : 's'} that stayed flat.</span>`;
  $('#h1').innerHTML = H1.hook;
  const feel = e => e.num_pct ? `${e.num_pct} ${e.unit_plain || (e.num_pct_kind === 'peak' ? `${e.short} at its peak, vs its normal` : `${e.short}, vs its normal`)}` : `${e.short}: size not yet published`;
  function trustLine() {
    if (!hero) return 'Nothing has been tested yet.';
    const o = hero.o;
    if (hero.kind === 'effect') {
      // plain words for novices (CX fix 3): one sentence per check, the statistics stay in the card
      if (o.engine && o.engine.n_date) return `<b>${esc(tierLine(o))}.</b> We re-ran the test on ${o.engine.n_date.toLocaleString()} random days: only ${o.engine.exceed_date} looked this strong.${o.contrast ? ` And the ${o.contrast.n_donors} regions the storm missed didn’t move.` : ''}${o.forecast && o.forecast.state === 'agree' ? ' An independent forecast model agrees.' : o.published.reason ? ` ${esc(o.published.reason[0].toUpperCase() + o.published.reason.slice(1))}.` : ''}`;
      return `<b>${esc(tierLine(o))}.</b> ${o.fluke ? esc(o.fluke.text) : 'Not yet tested against lookalikes.'}${o.published.reason ? ` ${esc(o.published.reason[0].toUpperCase() + o.published.reason.slice(1))}.` : ''} ${o.replication && o.replication.wording ? `<span class="no">${esc(o.replication.wording[0].toUpperCase() + o.replication.wording.slice(1))}.</span>` : ''}`;
    }
    if (hero.kind === 'untested') return `<b>Watching.</b> Too early to tell: the window closes ${fmtDayY(o.window_close)} (${RM.countdown(o.window_close)}).${o.watch && o.watch.expected_1_in ? ` Similar ${noun}s: a move by then about 1 in ${o.watch.expected_1_in} times.` : o.prior != null ? ` Registered prior: ${Math.round(o.prior * 100)}%.` : ''}`;
    return `<b>Stayed flat.</b> ${o.prior != null ? `Expected to move about 1 in ${Math.round(1 / o.prior)} times; the` : 'The'} window closed ${fmtDayY(o.window_close)} without a detectable move.`;
  }
  $('#trust').innerHTML = trustLine();
  const T = P.travel;
  $('#reach').innerHTML = T && T.days != null ? `<span class="num">${T.domains}</span> domain${T.domains === 1 ? '' : 's'} · <span class="num">${T.days}</span> days · ${RM.ord(T.depth || 1)}-order<small>How far the ripple travelled.${T.usual_reach ? ' ' + esc(T.usual_reach[0].toUpperCase() + T.usual_reach.slice(1)) + '.' : ''}</small>` : `<span class="num">0</span> domains · nothing resolved yet<small>How far the ripple travelled. It has not reached a shore we can measure.</small>`;
  $('#traced-sub').textContent = P.story ? P.story.story_sentence : '';
  $('#foot-src').innerHTML = P.engine ? `Engine ${esc(P.engine.method_hop)} tests${P.engine.method_contrast ? `, ${esc(P.engine.method_contrast)} regional contrasts` : ''}, batch ${esc(P.engine.batch)}. Ledger head seq ${P.ledger_head.seq}, ${esc(P.ledger_head.chain_hash.slice(0, 12))}… <a href="${ROOT}how/">How Ripple Map knows</a>.` : `${esc(P.source || 'story layer')}, version ${P.version}. <a href="${ROOT}how/">How Ripple Map knows</a>.`;
  document.title = `${P.story ? P.story.short_title : name}: Ripple Map`;

  /* ---------- the pond ---------- */
  const svg = $('#pond');
  svg.setAttribute('aria-label', `The pond: ${name} as a stone, its knock-on effects placed by domain and by time after the event`);
  let pond = Pond.render(svg, P, { compact, viewBox: compact ? [-480, -480, 960, 960] : [-560, -470, 1120, 940], onSelect: open, timing: 'fast' });
  svg.classList.add('hook');

  /* reserve the taller of the hook and traced heights so Trace it never shifts the pond (CLS after Trace) */
  (function reserve() {
    const lede = $('.lede'), h1 = $('#h1');
    const a = lede.offsetHeight, ha = h1.offsetHeight;
    document.body.classList.remove('hook'); h1.innerHTML = H1.traced; renderFollow();
    const b = lede.offsetHeight, hb = h1.offsetHeight;
    document.body.classList.add('hook'); h1.innerHTML = H1.hook;
    if (!compact) { lede.style.minHeight = Math.max(a, b) + 'px'; h1.style.minHeight = Math.max(ha, hb) + 'px'; }
  })();
  document.body.classList.remove('loading');
  RM.track('hero_view');

  /* phone: numbered list under the pond */
  const list = $('#pond-list');
  list.innerHTML = [...P.effects.map((e, i) => `<li><button type="button" data-open="${esc(e.id)}" data-kind="effect"><span class="i">${i + 1}</span><span class="t"><b>${esc(e.num)}</b> ${esc(e.short)}</span><span class="c">${esc(tierWord(e))}</span></button></li>`),
    ...(P.shore || []).map(s => `<li><button type="button" data-open="${esc(s.id)}" data-kind="shore"><span class="i r">R</span><span class="t"><b>${esc(s.num)}</b> ${esc(s.short)}, far shore</span><span class="c">World rule, ${s.pattern.n_events} events</span></button></li>`),
    nWatch ? `<li><button type="button" data-open="${esc(U0.id)}" data-kind="untested"><span class="i u">⋯</span><span class="t">${nWatch} series still being watched</span><span class="c">Watching</span></button></li>` : '',
    nFlat ? `<li><button type="button" data-open="${esc(F0.id)}" data-kind="flat"><span class="i u" style="border-color:var(--grass);color:var(--grass)">${nFlat}</span><span class="t">${nFlat} thing${nFlat === 1 ? '' : 's'} stayed flat</span><span class="c">Stayed flat</span></button></li>` : ''].join('');
  list.querySelectorAll('button').forEach(b => b.addEventListener('click', () => open(b.dataset.open, b.dataset.kind)));

  /* ---------- the reveal (signature moment): drop, ring reaches the stop, count-up, lag, tier, settle ---------- */
  function trace() {
    document.body.classList.remove('hook'); RM.track('trace');
    $('#h1').innerHTML = H1.traced;
    svg.classList.remove('hook');
    if (!hero) { svg.classList.add('settling'); return; }
    const o = hero.o, g = hero.kind === 'effect' ? pond.nodes[o.id] : svg.querySelector(`[data-id="${o.id}"]`), p = o._pos || (hero.kind !== 'effect' ? pond.pos(o.domain, o.lag_days, o._off || 0) : { x: 0, y: -120, r: 120 });
    svg.classList.add('revealing'); if (g) g.classList.add('reveal-target');
    const th = svg.querySelector(`.thread[data-for="${o.id}"]`); if (th) th.classList.add('reveal-thread');
    const fresh = svg.cloneNode(true); svg.parentNode.replaceChild(fresh, svg);   // restart the CSS timeline
    const Sv = $('#pond'); rebind(Sv);
    const NS = 'http://www.w3.org/2000/svg';
    const rv = document.createElementNS(NS, 'g'); rv.setAttribute('class', 'reveal'); rv.setAttribute('aria-hidden', 'true'); Sv.appendChild(rv);
    const side = compact ? -1 : (p.x >= 0 ? 1 : -1), lx = p.x + side * 44, anchor = side > 0 ? 'start' : 'end';
    const mk = (cls, y, txt) => { const t = document.createElementNS(NS, 'text'); t.setAttribute('class', 'rv ' + cls); t.setAttribute('x', lx); t.setAttribute('y', p.y + y); t.setAttribute('text-anchor', anchor); t.textContent = txt; rv.appendChild(t); return t; };
    const isE = hero.kind === 'effect';
    const num = mk('rv-num', -6, ''), what = mk('rv-what', 18, isE ? (o.unit_plain || o.short) : o.name), lag = mk('rv-lag', 40, isE ? o.lag_text : hero.kind === 'untested' ? `window closes ${fmtDay(o.window_close)}` : `window closed ${fmtDay(o.window_close)}`), tier = mk('rv-tier', 60, isE ? (compact && o.published && o.published.reason ? `${tierWord(o)}: ${o.published.reason}` : tierLine(o)) : hero.kind === 'untested' ? 'Watching, too early to tell' : 'Stayed flat');
    // D-15 timeline: shock 0, line 250 ms, stop 500, count-up 800, lag 1100, tier 1300, settle 1600
    const hit = reduce ? 0 : pond.ringDelay(p.r) * 1000;   // the ring front reaches the stop (~0.5 s)
    const Tm = reduce ? [0, 0, 0, 0, 0] : [hit + 300, 500, hit + 600, hit + 800, hit + 1100];
    if (isE && o.num_pct) {
      const target_v = parseInt(o.num_pct.replace(/[^\d]/g, ''), 10) * (o.num_pct.startsWith('−') ? -1 : 1), prefix = target_v < 0 ? '−' : '+';
      const t0 = performance.now() + Tm[0];
      function tick(now) { const k = Math.min(1, Math.max(0, (now - t0) / Tm[1])); const v = Math.abs(target_v) * (1 - Math.pow(1 - k, 3)); num.textContent = prefix + Math.round(v) + '%'; if (k < 1) requestAnimationFrame(tick); }
      if (reduce) num.textContent = o.num_pct; else requestAnimationFrame(tick);
    } else { num.textContent = hero.kind === 'untested' ? '?' : isE ? '?' : 'flat'; }
    setTimeout(() => lag.classList.add('on'), Tm[2]);
    // the headline changes only after the tier lands (CX fix 1); the number stays pinned on the water; the card is one tap away
    setTimeout(() => { tier.classList.add('on'); $('#h1').innerHTML = H1.traced; }, Tm[3]);
    setTimeout(() => { Sv.classList.add('settling'); Sv.classList.remove('revealing'); rv.classList.add('pinned'); afterReveal(); }, Tm[4] + (reduce ? 10 : 500));
  }
  /* after the reveal: the flats right under the pond (the counter-intuitive part), and one button to the evidence */
  function afterReveal() {
    const a = $('#after'); if (!a || a.dataset.on) return; a.dataset.on = '1'; a.hidden = false;
    const o = hero && hero.o;
    a.innerHTML = `<div class="after-row"><button class="btn primary" type="button" id="btn-evidence">${hero ? hero.kind === 'effect' ? 'See the evidence' : hero.kind === 'untested' ? 'See the window' : 'See why it stayed flat' : 'See the pond'}<svg width="14" height="14" aria-hidden="true"><use href="#i-arrow"/></svg></button>${nFlat ? `<span class="after-k">${nFlat === 1 ? 'One thing' : numw(nFlat) + ' things'} everyone might expect to move stayed flat:</span>` : nWatch ? `<span class="after-k">${nWatch} series still being watched:</span>` : ''}</div>
      ${nFlat ? `<div class="after-chips">${P.flats.slice(0, 8).map(f => `<button type="button" data-open="${esc(f.id)}" data-kind="flat"><svg aria-hidden="true"><use href="#k-grass"/></svg>${esc(f.short_name || f.name)}</button>`).join('')}${nFlat > 8 ? `<button type="button" data-scroll="stopped">and ${nFlat - 8} more</button>` : ''}</div>` : nWatch ? `<div class="after-chips">${P.untested.slice(0, 6).map(u => `<button type="button" data-open="${esc(u.id)}" data-kind="untested"><svg aria-hidden="true"><use href="#k-float"/></svg>${esc(u.name)}<small>${RM.countdown(u.window_close)}</small></button>`).join('')}</div>` : ''}`;
    if (o) $('#btn-evidence').addEventListener('click', () => open(o.id, hero.kind));
    a.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => open(b.dataset.open, b.dataset.kind)));
    a.querySelectorAll('[data-scroll]').forEach(b => b.addEventListener('click', () => $('#' + b.dataset.scroll).scrollIntoView({ behavior: reduce ? 'auto' : 'smooth' })));
  }
  function rebind(Sv) {
    const bind = (sel, kind) => Sv.querySelectorAll(sel).forEach(g => { g.addEventListener('click', () => open(g.dataset.id, kind)); g.addEventListener('keydown', ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(g.dataset.id, kind); } }); if (kind === 'effect') pond.nodes[g.dataset.id] = g; });
    bind('.effect', 'effect'); bind('.shore-mark', 'shore'); bind('.float', 'untested'); bind('.grass', 'flat');
  }
  $('#btn-trace').addEventListener('click', trace);
  if (location.hash === '#traced' || stopParam) { document.body.classList.remove('hook'); svg.classList.remove('hook'); $('#h1').innerHTML = H1.traced; afterReveal(); }

  /* ---------- charts (actual vs normal range, direct labels, no chartjunk) ---------- */
  function seriesChart(e, w = 420, h = 170, mini = false) {
    const c = e.chart, Sr = c.series, m = { t: mini ? 6 : 24, r: mini ? 6 : 96, b: mini ? 4 : 22, l: mini ? 4 : 30 };
    const x = i => m.l + i / (Sr.length - 1) * (w - m.l - m.r);
    const vals = Sr.flatMap(s => [s.t, s.o]).concat([c.band.lo, c.band.hi]);
    let ymin = Math.min(...vals), ymax = Math.max(...vals); const pad = (ymax - ymin) * .1; ymin -= pad; ymax += pad;
    const y = v => h - m.b - (v - ymin) / (ymax - ymin) * (h - m.t - m.b);
    const idx = d => Sr.findIndex(s => s.d === d);
    let band = `M${x(0)},${y(c.band.hi)}L${x(Sr.length - 1)},${y(c.band.hi)}L${x(Sr.length - 1)},${y(c.band.lo)}L${x(0)},${y(c.band.lo)}`;
    let l1 = '', l2 = ''; Sr.forEach((s, i) => { l1 += (i ? 'L' : 'M') + x(i) + ',' + y(s.t); l2 += (i ? 'L' : 'M') + x(i) + ',' + y(s.o); });
    const pk = idx(c.peak.d), lf = idx(c.landfall || c.onset), pw = [idx(c.post_window[0]), idx(c.post_window[1])];
    const nd = e.contrast ? e.contrast.n_donors : null;
    let s = `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(e.title)} against its own normal band${nd ? ` and ${nd} unaffected regions` : ''}, indexed to normal. On ${fmtDay(c.peak.d)} it sat at ${Math.round(c.peak.t * 100)}% of normal${nd ? ` while the other regions sat at ${Math.round(c.peak.o * 100)}%` : ''}.">`;
    s += `<rect class="win" x="${x(pw[0])}" y="${m.t - 4}" width="${x(pw[1]) - x(pw[0])}" height="${h - m.b - m.t + 4}"/>`;
    s += `<path class="band" d="${band}Z"/>`;
    s += `<line class="onset" x1="${x(lf)}" x2="${x(lf)}" y1="${m.t - 4}" y2="${h - m.b}"/>`;
    s += `<path class="line2" d="${l2}"/><path class="line" d="${l1}"/><circle class="pk" cx="${x(pk)}" cy="${y(Sr[pk].t)}" r="3.5"/>`;
    if (!mini) {
      s += `<text class="lab strong" x="${x(lf)}" y="${m.t - 8}" text-anchor="middle">${c.landfall ? 'landfall' : 'onset'}</text>`;
      s += `<text class="lab acc" x="${x(pk) - 9}" y="${y(Sr[pk].t) + 4}" text-anchor="end">${Math.round(Sr[pk].t * 100)}% of normal, ${fmtDay(c.peak.d)}</text>`;
      if (nd) s += `<text class="lab" x="${w - m.r + 8}" y="${y(Sr[Sr.length - 1].o) - 6}">${nd} other regions</text><text class="lab" x="${w - m.r + 8}" y="${y(Sr[Sr.length - 1].o) + 8}">(their normal)</text>`;
      s += `<text class="lab acc" x="${w - m.r + 8}" y="${y(Sr[Sr.length - 1].t) + 14}">${esc(e.short_label || 'this series')}</text>`;
      s += `<text class="lab" x="${x(0) + 4}" y="${y(c.band.hi) - 4}">normal band</text>`;
      [1, .8, .6].forEach(v => { if (v > ymin && v < ymax) s += `<text class="lab" x="${m.l - 6}" y="${y(v) + 4}" text-anchor="end">${Math.round(v * 100)}%</text>`; });
      s += `<text class="lab" x="${m.l}" y="${h - 4}">${fmtDay(Sr[0].d)}</text><text class="lab" x="${w - m.r}" y="${h - 4}" text-anchor="end">${fmtDay(Sr[Sr.length - 1].d)}</text>`;
      s += `<text class="lab" x="${x(pw[1]) + 5}" y="${m.t + 8}">${(idx(c.post_window[1]) - idx(c.post_window[0]) + 1)}-day test window</text>`;
    }
    return s + '</svg>';
  }
  function luckPanel(e) {
    if (!e.engine || !e.engine.n_date || e.engine.exceed_topic == null) return `<p>${e.fluke ? esc(e.fluke.text) : 'This stop has not been tested against lookalikes yet.'}${e.fluke && e.fluke.f_1_in ? ` Decoy links this strong turn out to be flukes about 1 in ${e.fluke.f_1_in} times.` : ''} The full placebo families (fake dates, other series, random links) arrive with this event's pond payload.</p>`;
    const g = e.engine, fam = [
      { name: `${g.n_date.toLocaleString()} fake dates, same series`, n: g.n_date, hits: g.exceed_date, p: g.p_date },
      { name: `${g.n_topic} other series, same date`, n: g.n_topic, hits: g.exceed_topic, p: g.p_topic },
      { name: `${g.n_link} random links`, n: g.n_link, hits: g.exceed_link, p: g.p_link }];
    const rows = fam.map(f => `<div class="pf"><span>${esc(f.name)}</span><span class="pf-bar" aria-hidden="true"><i style="width:${Math.max(1.5, Math.min(100, f.hits / f.n * 100))}%"></i></span><b class="num">${f.hits} of ${f.n}</b><small>about 1 in ${Math.round(1 / f.p)}</small></div>`).join('');
    let sv = '', tail = '';
    if (e.contrast) {
      const c = e.contrast, v = c.in_time.values_logpts.map(x => Math.abs(x - c.in_time.centre) * 100), real = Math.abs(c.d_logpts - c.in_time.centre) * 100;
      const w = 420, h = 100, bins = 26, mx = Math.max(real * 1.08, Math.max(...v) * 1.1), cnt = new Array(bins).fill(0);
      v.forEach(x => cnt[Math.min(bins - 1, Math.floor(x / mx * bins))]++);
      const top = Math.max(...cnt), bw = (w - 20) / bins;
      sv = `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${c.in_time.n} pseudo-storms at the same date in other years: the size of the Florida-minus-donors gap each produced. The real storm's gap of ${Math.round(real)} points sits beyond every one of them.">`;
      cnt.forEach((n, i) => { const bx = i * bw, bh = n / top * (h - 34); sv += `<rect class="bar ${i * mx / bins >= real ? 'tail' : ''}" x="${bx + 1}" y="${h - 20 - bh}" width="${bw - 2}" height="${bh}" rx="1.5"/>`; });
      const rx = Math.min(w - 20, real / mx * (w - 20));
      sv += `<line class="you" x1="${rx}" x2="${rx}" y1="4" y2="${h - 20}"/><text class="lab strong" x="${rx - 6}" y="12" text-anchor="end">this storm, ${Math.round(real)} pts</text><text class="lab" x="0" y="${h - 5}">${c.in_time.n} pseudo-storms, same dates in other years</text><text class="lab" x="${w - 20}" y="${h - 5}" text-anchor="end">bigger gap →</text></svg>`;
      tail = `<h4>And against the rest of the country</h4>${sv}<p>${c.in_time.n_bigger === 0 ? 'None' : c.in_time.n_bigger} of the ${c.in_time.n} pseudo-storms came close (in-time p ${c.p_time}). Against ${c.n_donors} unaffected regions shuffled into 30 fake Floridas, the real pair ranked first: about <b>1 in ${c.p_space_odds}</b>.</p>`;
    }
    return `<div class="luck"><div class="pfs" role="list" aria-label="Placebo families for the single-event test">${rows}</div><p>The engine's single-event test: T ${g.t_stat.toFixed(2)}${g.bh ? `, corrected over ${g.bh.m} tests` : ''} (q ${g.q_w.toFixed(3)}). A random date on this series looks this strong about <b>1 in ${Math.round(1 / g.p_date)}</b> times.${g.f === 1 ? ' The calibrated fluke rate for this T bin is still warming up (too few decoys), so no fluke odds are quoted here.' : ''}</p>${tail}</div>`;
  }
  /* the third independent check: an ARIMA forecast of each series, per-series effect with its interval */
  function forecastPanel(e) {
    const f = e.forecast; if (!f) return '';
    const lo = Math.min(...f.series.map(s => s.lo_pct), 0) - 3, hi = Math.max(...f.series.map(s => s.hi_pct), 0) + 3, X = v => (v - lo) / (hi - lo) * 100;
    return `<div class="sect" id="forecast"><h3>An independent forecast model${f.state === 'agree' ? ' agrees' : f.state === 'pending' ? ' has not checked yet' : ' disagrees'}</h3><p>${esc(f.text)}</p><div class="fc">${f.series.map(s => `<div class="row"><span>Series ${s.series_id}, ${s.pre_days} days of history, ${s.post_days} days after onset</span><b>${s.effect_pct}% [${s.lo_pct}, ${s.hi_pct}]</b><div class="ci" role="img" aria-label="${s.effect_pct}% against the forecast, 95% interval ${s.lo_pct} to ${s.hi_pct}"><i style="left:${X(s.lo_pct)}%;width:${X(s.hi_pct) - X(s.lo_pct)}%"></i><em style="left:${X(0)}%"></em><b style="left:${X(s.effect_pct)}%"></b></div></div>`).join('')}<small>Zero is the model's own forecast (the thin line). Model ${esc(f.model)}, horizon ${f.horizon_days} days, evaluated ${fmtDayY(f.evaluated_at)}. ${esc(f.calib_text)}</small></div></div>`;
  }
  function replicationRow(r) {
    if (r.all) {
      const pips = r.all.map(s => `<i class="${s.pass ? '' : s.effect_pct < 0 ? 'dir' : 'no'}" title="${esc(s.label)} ${s.year}: ${s.effect_pct}%"></i>`).join('');
      return `<div class="repl"><span class="pips" aria-hidden="true">${pips}</span><span>Passed after <b class="num">${r.n_seen} of ${r.n_similar}</b> past storms tested; <span class="num">${r.n_same_direction}</span> moved the same way</span></div>
      <p style="font-size:13px;color:var(--muted);margin-top:6px">${r.examples.map(x => `${esc(x.label)}, ${x.effect_pct}%`).join('; ')}. ${esc(r.family && r.family.note ? r.family.note : 'Most past storms were mapped to multi-state grid operators, where a landfall is a rounding error; the storms measured on a Florida utility are the ones that pass.')} <a href="#past" data-scroll="past" style="color:var(--accent-ink);font-weight:500">Flip through them</a>.</p>`;
    }
    const n = r.n_similar || 0, k = r.n_seen || 0, pips = Array.from({ length: Math.min(n, 40) }, (_, i) => `<i class="${i < k ? '' : 'no'}"></i>`).join('');
    return `<div class="repl"><span class="pips" aria-hidden="true">${pips}</span><span>${esc(r.wording ? r.wording[0].toUpperCase() + r.wording.slice(1) : `Seen after ${k} of ${n} similar events`)}</span></div>${r.examples && r.examples.length ? `<p style="font-size:13px;color:var(--muted);margin-top:6px">For example ${r.examples.map(x => esc(x.label)).join('; ')}.</p>` : ''}`;
  }
  function watchRow(hop) {
    const w = hop ? { ...(P.watching || {}), window_close: hop.window_close, prior: hop.prior, name: hop.name, window_start: (P.watching && P.watching.window_start) || P.event.registered || P.event.onset } : P.watching; if (!w) return '';
    const wd = hop && hop.watch;
    return `<div class="sect" id="next"><h3>What happens next</h3><div class="win">${RM.winBar(w.window_start, w.window_close, `${fmtDayY(w.window_start)}, registered`, `${fmtDayY(w.window_close)}, window ${RM.daysUntil(w.window_close) >= 0 ? 'closes' : 'closed'}`)}
      <p style="margin-top:10px">${esc(w.text || '')} ${w.prior != null ? `Prior for ${esc(String(w.name || '').toLowerCase())}: <b class="num">${Math.round(w.prior * 100)}%</b>.` : ''}${wd && wd.expected_1_in ? ` Similar ${noun}s: a move by then about <b class="num">1 in ${wd.expected_1_in}</b> times. Next look ${fmtDayY(wd.next_look)}.` : ''}</p></div><div class="why keep"><button class="btn primary" type="button" data-watch>${watched() ? 'Watching this ripple' : 'Keep watching'}</button></div></div>`;
  }
  function drawers(e) {
    if (!e.engine) return `<details class="drawer"><summary>Where the numbers come from</summary><p>This stop is drawn from the story layer's public payload (story ${esc(e.story_id || '')}, version ${P.version}): tier, effect, lag and the placebo odds above. The series chart, the three placebo families, the regional contrast and the ledger sequence numbers arrive with the event's pond payload. Until then the card shows only what has been published.</p><p><a href="${ROOT}how/">How Ripple Map knows</a>.</p></details>`;
    const c = e.contrast, L = e.ledger, led = P.ledger;
    const row = (k, v, h) => `<dt>${k}</dt><dd${h ? ' class="h"' : ''}>${v}</dd>`;
    const g = e.engine;
    return `<details class="drawer"><summary>The single-event test (engine ${esc(g.version)})</summary><dl class="dl">
      ${row('Series', e.node + ' (hop ' + e.hop_id + ')')}${row('Observed onset', fmtDayY(e.onset_observed) + ', lag ' + e.lag_from_event_days + ' d from the event')}${g.rho && typeof g.rho === 'object' && g.rho.shrunk != null ? row('Effect (shrunk)', g.rho.shrunk.toFixed(3) + '× [' + g.rho.lo.toFixed(3) + ', ' + g.rho.hi.toFixed(3) + ']' + (g.rho.raw != null ? '; raw ' + g.rho.raw.toFixed(3) : '')) : row('Effect', e.num || 'not yet published')}
      ${e.chart && e.chart.peak ? row('Peak day', fmtDayY(e.chart.peak.d) + ', ' + Math.round(e.chart.peak.t * 100) + '% of normal') : ''}${g.t_stat != null ? row('T statistic', g.t_stat.toFixed(3)) : ''}${g.n_date ? row('Fake dates', `${g.exceed_date} of ${g.n_date} (p ${g.p_date.toFixed(4)})`) : ''}${g.n_topic ? row('Other series', `${g.exceed_topic ?? '–'} of ${g.n_topic} (p ${g.p_topic})`) : ''}${g.n_link ? row('Random links', `${g.exceed_link ?? '–'} of ${g.n_link} (p ${g.p_link.toFixed(3)})`) : ''}
      ${g.bh ? row('BH (m ' + g.bh.m + ', weight ' + g.bh.weight + ')', 'q ' + g.q_w.toFixed(4)) : row('Corrected q', g.q_w != null ? g.q_w.toFixed(4) : '–')}${g.channels ? row('Channels', g.channels.agree + ' of ' + g.channels.of + (g.channels.names ? ' (' + g.channels.names.join(', ') + ')' : '')) : ''}${row('Fluke-rate bin', `T ${g.f_bin}: reads ${g.f}${g.f === 1 ? ' (warming up: too few decoys in this bin yet)' : ''}`)}${row('Flags / fails', ((g.flags || []).join(', ') || 'none') + ' / ' + ((g.fails || []).join(', ') || 'none'))}
      ${row('Engine tier', TIER[e.engine_tier])}${e.published.ce ? row('Forecast gate', `${e.published.tier} (${e.published.reason || 'agrees'}; mode ${e.published.mode}; state ${e.published.ce.state}${e.published.ce.n_agree != null ? `, ${e.published.ce.n_agree} of ${e.published.ce.n_eligible} series agree` : ''})`) : ''}</dl>${g.f_note ? `<p>${esc(g.f_note)}</p>` : ''}</details>
      ${c ? `<details class="drawer"><summary>The regional contrast (engine 6.2.1)</summary><dl class="dl">
      ${row('Treated regions', c.treated.join(' + ') + ' (Florida)')}${row('Donor regions', c.n_donors)}${row('Window', `${c.window.pre_days} d before, ${c.window.post_days} d after ${fmtDayY(c.window.onset)}`)}
      ${row('Treated change alone', c.treated_only_pct + '%')}${row('Contrast (treated − donors)', c.d_logpts + ' log pts = ' + c.effect_pct + '%')}${row('Centred on in-time median', c.d_centred + ' log pts')}
      ${row('Robust se (1.4826 · MAD)', c.se)}${row('z', c.z)}${row('Peak day', fmtDayY(e.chart.peak.d) + ', Florida ' + Math.round(e.chart.peak.t * 100) + '% vs donors ' + Math.round(e.chart.peak.o * 100) + '%')}
      </dl><p>${P.links && (P.links.csv_local || P.links.csv) ? `<a href="${esc(P.links.csv_local ? ROOT + P.links.csv_local : RM.STORAGE + P.links.csv)}" download>Download the daily series (CSV)</a>. ` : ''}Values are each region’s demand divided by its own mean over ${fmtDay(e.chart.pre_window[0])}–${fmtDay(e.chart.pre_window[1])}.</p></details>
      <details class="drawer"><summary>Baseline, lag and pre-trends</summary><dl class="dl">${row('Baseline', 'season-matched: the same dates in every other panel year, never after the event')}${row('Lag', `${e.lag_days} days to the peak gap; the pre-registered window has no lag`)}
      ${row('Leads (3 blocks before onset)', c.leads.join(', '))}${row('Pre-trend p', c.p_pre + ' (flat: p ≥ 0.10)')}</dl></details>
      <details class="drawer"><summary>Placebos, synthetic control, multiple testing</summary><dl class="dl">${row('In-space p (30 fake Floridas)', `${c.p_space} (1 in ${c.p_space_odds})`)}${row('In-time p (' + c.in_time.n + ' pseudo-storms)', c.p_time)}
      ${row('Synthetic control', `${c.synth_d} log pts, same sign; RMSPE ratio ${c.synth_ratio}, rank p ${c.synth_p}`)}${e.replication && e.replication.family ? row('Family q (24 hurricanes, BH)', e.replication.family.q + ' — ' + e.replication.family.strength) : ''}
      ${P.calibration ? row('Decoy false-alarm rate (120 sets)', `${Math.round(P.calibration.decoy_fp_rate * 1000) / 10}% [${P.calibration.wilson.map(x => Math.round(x * 1000) / 10).join(', ')}]`) : ''}</dl></details>` : ''}
      ${e.forecast ? `<details class="drawer"><summary>The forecast check (BigQuery, ${esc(e.forecast.model)})</summary><dl class="dl">${e.forecast.series.map(s => row(`Series ${s.series_id}`, `${s.effect_pct}% [${s.lo_pct}, ${s.hi_pct}], p ${s.p}`)).join('')}${row('Verdict', `${e.forecast.state}: ${e.forecast.n_agree} of ${e.forecast.n_eligible} series`)}${e.forecast.calibration.map(c => row(`Calibration, ${c.role.replace('_', ' ')}`, `${c.hops_sig} of ${c.hops_evaluated} significant, ${c.hops_agree} agree`)).join('')}${row('Run', esc(e.forecast.run))}</dl></details>` : ''}
      <details class="drawer"><summary>Ledger and provenance</summary><dl class="dl">${row('Hop id', e.hop_id)}${L.register_seq ? row('Registered', `seq ${L.register_seq}${led && led[0] ? ', ' + fmtDayY(led[0].day) : ''}`) : ''}${led && led[0] && led[0].payload_hash ? row('Register hash', led[0].payload_hash, 1) : ''}
      ${L.freeze_seq ? row('Grid frozen', `seq ${L.freeze_seq}${P.engine && P.engine.batch ? ', batch ' + esc(P.engine.batch) : ''}`) : ''}${L.frozen_hash ? row('Frozen hash', L.frozen_hash, 1) : ''}${L.model_seq ? row('Model versions', L.model_seq.join(', ') + ' (6.2, 6.2.1)') : ''}${L.calibration_seq ? row('Calibration', 'seq ' + L.calibration_seq) : ''}${L.control_seq ? row('Control audit', `seq ${L.control_seq}`) : ''}${L.resolve_seq ? row('Resolved', `seq ${L.resolve_seq}${g.resolved_at ? ', ' + fmtDayY(g.resolved_at.slice(0, 10)) : ''}`) : ''}${L.publish_seq || L.version_seq ? row('Version published', `seq ${L.publish_seq || L.version_seq}`) : ''}${L.cascade_head ? row('Cascade ledger head', L.cascade_head, 1) : ''}
      ${P.ledger_head ? row('Chain head', `seq ${P.ledger_head.seq}`) + row('Head hash', P.ledger_head.chain_hash, 1) : ''}${c && c.computed_at ? row('Computed', c.computed_at.slice(0, 16).replace('T', ' ') + ' UTC') : ''}</dl><p><a href="${ROOT}how/">How Ripple Map knows</a>.</p></details>`;
  }
  const glyph = t => `<svg aria-hidden="true"><use href="#g-${t === 'measured' ? 'measured' : t === 'likely' || t === 'contrast' ? 'half' : t === 'pattern' ? 'rule' : t === 'flat' ? 'flat' : 'dotted'}"/></svg>`;

  /* ---------- Follow this: the rabbit hole (every stop points to the next thing) ---------- */
  const N = (P.story && P.story.next) || {};
  const domKey = i => (P.domain_keys || [])[i] || null;
  function followLinks(o, kind) {
    const L = [];
    const dk = o && o.domain != null ? domKey(o.domain) : null, dl = dk ? RM.DLABEL[dk] || dk : null;
    if (kind !== 'event') L.push(`<button type="button" data-scroll="shore">What else did ${esc(name)} touch?<small>${nMoved} moved · ${nFlat} stayed flat · ${nWatch} watched${S ? ' · 1 world rule' : ''}</small><span class="go">Shore</span></button>`);
    if (N.stop_connections && (kind === 'effect' || kind === 'untested' || kind === 'flat') && o === hero.o) L.push(`<a href="${RM.url.land(dk || 'real_world')}&stop=${encodeURIComponent(o.name || o.title)}">This stop connects to ${N.stop_connections} other thing${N.stop_connections === 1 ? '' : 's'}<small>Other events that reached ${esc(o.short || o.name)}</small><span class="go">Follow</span></a>`);
    (N.same_stop || []).forEach(s => L.push(`<a href="${ROOT}r/?e=${encodeURIComponent(s.story_id.split(':')[1])}&stop=${s.story_id.split(':')[2]}">${esc(s.short_title)}<small>Another event, the same stop · ${esc(TIER[s.tier] || s.tier)}</small><span class="go">Open</span></a>`));
    (N.same_event || []).forEach(s => L.push(`<a href="${ROOT}r/?e=${encodeURIComponent(P.event.slug)}&stop=${s.story_id.split(':')[2]}">${esc(s.short_title)}<small>Same event, another stop · ${esc(TIER[s.tier] || s.tier)}${s.archetype ? ' · ' + esc(s.archetype) : ''}</small><span class="go">Open</span></a>`));
    if (dl) L.push(`<a href="${RM.url.land(dk)}">What’s been moving ${esc(dl)}?<small>Every stop in that land, by event</small><span class="go">Land</span></a>`);
    if (N.one_more) L.push(`<a href="${N.one_more.story_id.startsWith('pattern:') ? RM.url.pattern(N.one_more.story_id.split(':')[1]) : ROOT + 'r/?e=' + encodeURIComponent(N.one_more.story_id.split(':')[1])}" data-onemore>One more: ${esc(N.one_more.short_title)}<small>${N.one_more.archetype ? esc(N.one_more.archetype) + ' · ' : ''}${N.one_more.story_id.startsWith('pattern:') ? 'a world rule' : 'another ripple'}</small><span class="go">Go</span></a>`);
    L.push(`<a href="${RM.url.wander()}" data-wander>Wander<small>Land somewhere interesting</small><span class="go">Jump</span></a>`);
    return `<div class="follow">${L.join('')}</div>`;
  }
  function renderFollow() {
    const box = $('#follow-hero'); if (!box || box.dataset.done) return; box.dataset.done = '1';
    const L = [];
    if (S) L.push(`<a href="#" data-open="${esc(S.id)}" data-kind="shore">Where ${noun}s like it usually reach<small>${esc(S.short)}: a rule across ${S.pattern.n_events} ${noun}s, on the far shore</small><span class="go">Rule</span></a>`);
    else if (N.one_more) L.push(`<a href="${N.one_more.story_id.startsWith('pattern:') ? RM.url.pattern(N.one_more.story_id.split(':')[1]) : ROOT + 'r/?e=' + encodeURIComponent(N.one_more.story_id.split(':')[1])}">One more: ${esc(N.one_more.short_title)}<small>${N.one_more.story_id.startsWith('pattern:') ? 'a world rule' : 'another ripple'}</small><span class="go">Go</span></a>`);
    const dk = hero && hero.o.domain != null ? domKey(hero.o.domain) : null;
    if (dk) L.push(`<a href="${RM.url.land(dk)}">What’s been moving ${esc(RM.DLABEL[dk] || dk)}?<small>Every stop in that land</small><span class="go">Land</span></a>`);
    L.push(`<a href="${RM.url.wander()}" data-wander>Wander<small>Land on something else interesting</small><span class="go">Jump</span></a>`);
    box.innerHTML = L.join('');
    box.querySelectorAll('[data-open]').forEach(a => a.addEventListener('click', ev => { ev.preventDefault(); open(a.dataset.open, a.dataset.kind); }));
    box.querySelectorAll('[data-wander]').forEach(a => a.addEventListener('click', () => RM.track('wander')));
  }

  /* ---------- the stop card ---------- */
  const panel = $('#panel'), body = $('#panel-body'), scrim = $('#scrim');
  let current = null, currentKind = null;
  function showPanel() { panel.hidden = false; requestAnimationFrame(() => { panel.classList.add('open'); if (compact) scrim.classList.add('on'); document.body.classList.add('panel-open'); panel.scrollTo({ top: 0 }); $('#close').focus({ preventScroll: true }); }); }
  function highlight(id) { $('#pond').querySelectorAll('.effect, .shore-mark, .float').forEach(g => { g.classList.toggle('active', g.dataset.id === id); g.classList.toggle('dim', g.dataset.id !== id); }); }
  function open(id, kind) {
    if (kind === 'effect' || (!kind && E && id === E.id)) return openEffect(id);
    if (kind === 'shore') return openShore(id);
    if (kind === 'untested') return openUntested(id);
    if (kind === 'flat') return openFlat(id);
  }
  const shareBtns = (o, kind) => `<button class="btn" type="button" data-send="${esc(o.id)}" data-send-kind="${kind}">Send this</button>`;
  function openEffect(id) {
    const e = P.effects.find(x => x.id === id); if (!e) return; current = id; currentKind = 'effect'; RM.track('stop_open');
    const r = e.replication, g = e.engine, chain = e.parent && e.parent !== 'event' && e.mediation_supported;
    const parentE = chain ? P.effects.find(x => x.id === e.parent) : null;
    const agree = g ? `<span><i></i>Moved unusually after the ${noun}: ${g.exceed_date} of ${g.n_date.toLocaleString()} fake dates come close</span>${e.contrast ? `<span><i></i>Moved against ${e.contrast.n_donors} unaffected regions, pre-trends flat</span>` : ''}${e.sources ? `<span><i class="${e.sources.agree > 1 ? '' : 'o'}"></i>${esc(e.sources.text)}</span>` : ''}${r && r.n_similar ? `<span><i class="${r.n_seen ? '' : 'o'}"></i>Passed after ${r.n_seen} of ${r.n_similar} similar ${noun}s tested</span>` : ''}<span><i class="${(e.forecast && e.forecast.state === 'agree') || (e.published.ce && e.published.ce.state === 'agree') ? '' : 'o'}"></i>Independent forecast model: ${esc(e.published.ce ? e.published.ce.state === 'agree' ? `agrees (${e.published.ce.n_agree} of ${e.published.ce.n_eligible} series)` : e.published.ce.state : 'not run')}</span>`
      : `${e.fluke ? `<span><i></i>${esc(e.fluke.text)}</span>` : '<span><i class="o"></i>Not yet tested against lookalikes</span>'}${e.sources ? `<span><i class="${e.sources.agree > 1 ? '' : 'o'}"></i>${esc(e.sources.text)}</span>` : ''}${r && r.wording ? `<span><i class="${r.n_seen ? '' : 'o'}"></i>${esc(r.wording[0].toUpperCase() + r.wording.slice(1))}</span>` : ''}${e.published.reason ? `<span><i class="o"></i>Forecast gate: ${esc(e.published.reason)}</span>` : ''}`;
    body.innerHTML = `
      <p class="crumb">${esc(P.domains[e.domain])}, ${esc(e.lag_text || '')}. ${chain ? `This stop is reached <b>through ${esc(parentE ? parentE.short : e.parent)}</b>: the engine's mediation check supports the chain.` : `This ripple <b>forks straight from the ${noun}</b>: no chain through another stop is claimed.`}</p>
      <span class="chip ${esc(tierOf(e))}">${glyph(tierOf(e))}${esc(tierWord(e))}${e.published.reason || (e.published.detail && e.published.detail !== tierWord(e)) ? `<em>${esc(e.published.reason ? e.published.detail : e.published.detail.replace(/^[^:]+:\s*/, ''))}</em>` : ''}</span>
      <h2>${esc(e.title)}</h2>
      <div class="big num">${esc(e.num_pct || e.num || '?')}<small>${esc(e.unit_plain || (e.num_pct_kind === 'peak' ? 'at its peak, vs its normal' : e.unit || 'vs its normal'))}${e.num && e.num_pct ? ` · ${esc(e.num)} its normal` : ''}</small></div>
      <p class="find">${esc(e.plain_long || e.plain)}</p>
      <div class="agree">${agree}</div>
      <div class="why"><button class="btn primary" type="button" data-why>Why?</button>${shareBtns(e, 'stop')}<button class="btn" type="button" data-watch aria-pressed="${watched()}">${watched() ? 'Watching' : 'Watch'}</button></div>
      ${e.chart && e.chart.series ? `<div class="chart">${seriesChart(e)}</div><div class="legend"><span><i class="l"></i>${esc(e.short_label || e.title)}</span>${e.contrast ? `<span><i class="l2"></i>${e.contrast.n_donors} unaffected regions</span>` : ''}<span><i></i>The engine's normal band (±1.28σ)</span></div>` : ''}
      <div class="sect" id="why"><h3>Why? How the ripple got there</h3>${e.mechanism ? `<ul class="steps">${e.mechanism.map((m, i) => `<li><i class="${i === 0 ? 'f' : ''}"></i><span>${esc(m.step)}<small>${m.why ? esc(m.why) + ' ' : ''}${m.source ? 'Source: ' + esc(m.source) + '.' : ''}</small></span></li>`).join('')}</ul>` : e.why && e.why.length ? `<ul class="steps">${e.why.map((w, i) => `<li><i class="${i === 0 ? 'f' : ''}"></i><span>${esc(w[0].toUpperCase() + w.slice(1))}</span></li>`).join('')}</ul><p style="font-size:13px;color:var(--muted)">The named mechanism steps arrive with the event's pond payload.</p>` : '<p>A mechanism from the library links this stop to the event; its steps are not published for this stop yet.</p>'}</div>
      <div class="sect" id="luck"><h3>Could it be luck?</h3>${luckPanel(e)}${e.how ? `<p style="margin-top:8px">${esc(e.how)}</p>` : ''}</div>
      ${forecastPanel(e)}
      ${e.mind ? `<div class="sect"><h3>What would change our mind</h3><p>${esc(e.mind)}</p></div>` : ''}
      ${r ? `<div class="sect" id="seen"><h3>Seen before?</h3>${replicationRow(r)}</div>` : ''}
      ${P.watching ? watchRow() : ''}
      <div class="sect"><h3>In plain words</h3><p><b>${esc(tierWord(e))}.</b> ${g && g.n_date ? `The engine’s own test calls this ${esc(TIER[e.engine_tier])}: the series moved, ${g.n_date.toLocaleString()} fake dates say it is not the calendar${e.contrast ? `, and ${e.contrast.n_donors} unaffected regions say it is not the country` : ''}. ${e.published.reason ? `<b>Published as ${esc(tierWord(e))}</b> because the independent forecast model has not yet checked it (${esc(e.published.reason)}). When it agrees, the word becomes Measured; if it disagrees, it stays Likely.` : e.published.ce && e.published.ce.state === 'agree' ? `<b>Published as ${esc(tierWord(e))}</b> because an independent forecast model agrees on ${e.published.ce.n_agree} of ${e.published.ce.n_eligible} series.` : ''}` : tierOf(e) === 'likely' ? 'Well supported by the engine’s test, but not yet Measured: the final look or the forecast check is still to come, and a fluke is not ruled out.' : esc(P.story && P.story.tier_wording ? P.story.tier_wording : '')} Consistent with, never proof of cause.</p></div>
      <div class="sect" id="deep"><h3>Deep evidence</h3>${drawers(e)}</div>
      <div class="sect more"><h3>This wasn’t the end</h3>${followLinks(e, 'effect')}</div>`;
    wire(); highlight(id); showPanel();
  }
  function openShore(id) {
    const s = (P.shore || []).find(x => x.id === id); if (!s) return; current = id; currentKind = 'shore'; RM.track('stop_open');
    const p = s.pattern;
    const pips = (p.all || []).map(x => `<i class="${x.pass ? '' : x.effect_pct < 0 ? 'dir' : 'no'}" title="${esc(x.label)} ${x.year}: ${x.effect_pct}%"></i>`).join('');
    body.innerHTML = `
      <p class="crumb">${esc(P.domains[s.domain])}, ${esc(s.lag_text || 'four weeks on')}. <b>The far shore.</b> A rule about ${p.n_events} past ${noun}s, drawn on the bank because it is not evidence about ${esc(name)}.</p>
      <span class="chip pattern">${glyph('pattern')}${esc(p.strength)}<em>${esc(p.fluke_note)}</em></span>
      <h2>${esc(s.title)}</h2>
      <div class="big num">${esc(s.num)}<small>${esc(s.unit)}</small></div>
      <p class="find">${esc(s.plain)}</p>
      <div class="agree"><span><i></i>Pooled across ${p.n_events} ${noun}s${p.n_clustered_out ? ` (${p.n_clustered_out} overlapping removed)` : ''}</span><span><i></i>Survives correction over the pre-registered pairs (q ${Math.round(p.q * 1000) / 1000})</span><span><i class="o"></i>${esc(name)}: not pre-registered for this series, untested</span></div>
      <div class="why"><button class="btn primary" type="button" data-why>Why?</button>${shareBtns(s, 'rule')}</div>
      <div class="sect" id="why"><h3>Why? How ${noun}s reach here</h3>${s.mechanism ? `<ul class="steps">${s.mechanism.map((m, i) => `<li><i class="${i === 0 ? 'f' : ''}"></i><span>${esc(m.step)}<small>${esc(m.why)} Source: ${esc(m.source)}.</small></span></li>`).join('')}</ul>` : `<ul class="steps"><li><i class="f"></i><span>Would-be founders lose premises, savings and customers<small>Uninsured losses and closed storefronts delay new ventures. Source: mechanism library.</small></span></li><li><i></i><span>Applications to start a business slip for about a month<small>Weekly Census filings in the hit states run below unaffected states, then recover. Source: Census Business Formation Statistics, weekly by state.</small></span></li><li><i></i><span>The effect is concentrated in the big landfalls<small>Heterogeneity I² ${p.i2}. Source: engine 6.2 pool.</small></span></li></ul>`}</div>
      <div class="sect" id="luck"><h3>Could it be luck?</h3><p>300 fake pools, each built from one pseudo-${noun} per real ${noun} at the same dates in other years, produced an effect this large about <b class="num">1 in ${Math.round(1 / p.p_placebo)}</b> times (placebo p ${p.p_placebo.toFixed(3)}). ${P.calibration ? `Across ${P.calibration.decoy_n} decoy families the engine raised a false alarm ${Math.round(P.calibration.decoy_fp_rate * 100)}% of the time, so a single strong pattern still carries roughly that fluke risk: ` : ''}${esc(p.fluke_note)}.</p></div>
      ${p.all ? `<div class="sect" id="seen"><h3>Seen before?</h3><div class="repl"><span class="pips" aria-hidden="true">${pips}</span><span>Fell after <b class="num">${p.fell_after} of ${p.of}</b> ${noun}s</span></div><p style="font-size:13px;color:var(--muted);margin-top:6px">Largest: ${p.examples.map(x => `${esc(x.label)} ${x.effect_pct}%`).join('; ')}. Confidence interval ${p.ci[0]}% to ${p.ci[1]}%${p.ci[1] >= 0 ? ': the top end touches zero' : ''}.</p></div>` : ''}
      <div class="sect"><h3>In plain words</h3><p><b>${esc(p.strength[0].toUpperCase() + p.strength.slice(1))}.</b> Across many ${noun}s, ${esc(s.short)} moved. <b>Not a finding about ${esc(name)}:</b> nobody registered this series for it, so the pond shows it on the bank, where the ripple would land if it reaches. Consistent with, never proof of cause.</p></div>
      <div class="sect" id="deep"><h3>Deep evidence</h3><details class="drawer"><summary>The raw numbers</summary><dl class="dl"><dt>Pooled effect</dt><dd>${p.effect_logpts} log pts = ${p.effect}%</dd><dt>95% CI</dt><dd>${p.ci[0]}% to ${p.ci[1]}%</dd><dt>Events (after overlap rule)</dt><dd>${p.n_events}${p.n_clustered_out ? ` (${p.n_clustered_out} removed)` : ''}</dd><dt>I²</dt><dd>${p.i2}</dd><dt>Placebo p / normal p</dt><dd>${p.p_placebo.toFixed(4)} / ${p.p_norm != null ? p.p_norm.toFixed(3) : '–'}</dd><dt>BH q</dt><dd>${p.q.toFixed(4)}</dd>${p.dose ? `<dt>Dose–response</dt><dd>slope ${p.dose.slope_per_unit}, p ${p.dose.p.toFixed(2)}</dd>` : ''}<dt>Regional passes / flat pre-trends</dt><dd>${p.n_regional_pass} / ${p.n_pretrend_flat}</dd><dt>Window</dt><dd>${p.window.pre} ${p.window.grain === 'week' ? 'wk' : 'd'} before, ${p.window.post} after</dd><dt>Ledger</dt><dd>freeze seq ${p.ledger_seq}</dd></dl><p><a href="${RM.url.pattern(p.id)}">Open the world rule</a> with every past ${noun} on it.</p></details></div>
      <div class="sect more"><h3>This wasn’t the end</h3>${followLinks(s, 'shore')}</div>`;
    wire(); highlight(id); showPanel();
  }
  function openUntested(id) {
    const u = (P.untested || []).find(x => x.id === id); if (!u) return; current = id; currentKind = 'untested'; RM.track('stop_open');
    const others = P.untested.filter(x => x.id !== id);
    body.innerHTML = `
      <p class="crumb">${esc(P.domains[u.domain])}, window ${RM.daysUntil(u.window_close) >= 0 ? 'closes' : 'closed'} ${fmtDayY(u.window_close)}. Registered before anyone looked.</p>
      <span class="chip watching">${glyph('watching')}Watching<em>${esc(String(u.status || 'window open').replace(/_/g, ' '))}</em></span>
      <h2>${esc(u.name)}</h2>
      <div class="flat-hero">Too early to tell.</div>
      <p class="find">${esc(u.plain)}</p>
      <div class="why">${shareBtns(u, 'watching')}</div>
      ${u.mechanism ? `<div class="sect"><h3>Why it was registered</h3><p>${esc(u.mechanism.replace('->', '→'))}. Source: mechanism library v6.0, template ${esc(u.path_type === 'P-MECH' ? 'mechanism path' : 'family map')}.</p></div>` : u.story && u.story.why ? `<div class="sect"><h3>Why it was registered</h3><ul class="steps">${u.story.why.map((w, i) => `<li><i class="${i === 0 ? 'f' : ''}"></i><span>${esc(w[0].toUpperCase() + w.slice(1))}</span></li>`).join('')}</ul></div>` : `<div class="sect"><h3>Why it was registered</h3><p>Mapped from the ${noun} family: every ${noun} gets this series checked. Source: family mapper.</p></div>`}
      <div class="sect"><h3>Why we show it</h3><p>Hiding an open question would make the bright pads look like the whole story. When the window closes, this float becomes a pad if it moved or reeds if it stayed flat.${others.length ? ` ${others.length} other series on this ${noun} are still open.` : ' Its sibling series have all been resolved; this is the last one open.'}</p></div>
      ${watchRow(u)}
      ${others.length ? `<div class="sect"><h3>Also being watched</h3><div class="chips" style="display:flex;flex-wrap:wrap;gap:6px">${others.map(o => `<button type="button" class="btn" style="padding:4px 10px;font-size:12.5px;border-color:var(--pline-2);color:var(--ink-2)" data-more="${esc(o.id)}" data-more-kind="untested">${esc(o.name)}<small style="color:var(--muted)">${RM.countdown(o.window_close)}</small></button>`).join('')}</div></div>` : ''}
      <div class="sect more"><h3>This wasn’t the end</h3>${followLinks(u, 'untested')}</div>`;
    wire(); highlight(id); showPanel();
  }
  function openFlat(id) {
    const n = (P.flats || []).find(x => x.id === id); if (!n) return; current = id; currentKind = 'flat'; RM.track('stop_open');
    const others = P.flats.filter(x => x.id !== id);
    body.innerHTML = `<p class="crumb">${esc(P.domains[n.domain])}, window to ${fmtDayY(n.window_close)}. Checked in advance, on purpose.</p><span class="chip flat">${glyph('flat')}Stayed flat<em>a dead end, disclosed</em></span>
      <div class="flat-hero">The ripple stopped here.</div><h2 style="margin-top:0">${esc(n.name)}</h2><p class="find">${esc(n.plain)}</p>
      <div class="why">${shareBtns(n, 'dead')}</div>
      ${n.mechanism ? `<div class="sect"><h3>Why it was registered</h3><p>${esc(n.mechanism.replace('->', '→'))}. Source: mechanism library v6.0.</p></div>` : n.story && n.story.why ? `<div class="sect"><h3>Why it was registered</h3><ul class="steps">${n.story.why.map((w, i) => `<li><i class="${i === 0 ? 'f' : ''}"></i><span>${esc(w[0].toUpperCase() + w.slice(1))}</span></li>`).join('')}</ul></div>` : `<div class="sect"><h3>Why it was registered</h3><p>Mapped from the ${noun} family: every ${noun} gets this series checked. Source: family mapper.</p></div>`}
      <div class="sect"><h3>How sure?</h3><p>${n.t_stat != null ? `The same test as the bright pad: the series against its own normal, then against fake dates. Test statistic <b class="num">${n.t_stat.toFixed(2)}</b>; ${Math.round(n.p_date * n.n_date)} of ${n.n_date} fake dates did as well or better; corrected q ${n.q_w.toFixed(2)}.${n.flags && n.flags.length ? ' Flags: ' + esc(n.flags.join(', ').replace(/_/g, ' ')) + '.' : ''}` : `${n.prior != null ? `We expected a move about 1 in ${Math.round(1 / n.prior)} times. ` : ''}The window closed without a detectable move against the series' own normal. The test statistics arrive with the event's pond payload.`}</p></div>
      <div class="sect"><h3>Why we show it</h3><p>${P.flats.length} reed${P.flats.length === 1 ? '' : 's'} on this pond absorbed the wave. Without them, a bright pad would look like the ${noun} touched everything.${P.controls && P.controls.length ? ` ${P.controls.length} negative controls (${P.controls.map(c => esc(c.name.replace(' (control)', ''))).join(', ')}) also stayed flat, so a nationwide move could not pass as local.` : ''} A dead end we disclose is a finding too.</p></div>
      ${others.length ? `<div class="sect"><h3>Also flat</h3><div class="chips" style="display:flex;flex-wrap:wrap;gap:6px">${others.map(o => `<button type="button" class="btn" style="padding:4px 10px;font-size:12.5px;border-color:var(--pline-2);color:var(--ink-2)" data-more="${esc(o.id)}" data-more-kind="flat">${esc(o.name)}</button>`).join('')}</div></div>` : ''}
      <div class="sect more"><h3>This wasn’t the end</h3>${E ? `<p>Back to the thing that moved.</p><button class="btn" type="button" data-more="${esc(E.id)}" data-more-kind="effect">One more<svg width="14" height="14" aria-hidden="true"><use href="#i-arrow"/></svg></button>` : ''}${followLinks(n, 'flat')}</div>`;
    wire(); highlight(id); showPanel();
  }
  function wire() {
    body.querySelectorAll('[data-more]').forEach(mb => mb.addEventListener('click', () => { RM.track('one_more'); open(mb.dataset.more, mb.dataset.moreKind); }));
    const wb = body.querySelector('[data-why]'); if (wb) wb.addEventListener('click', () => { RM.track('why_open'); $('#why', body).scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' }); });
    body.querySelectorAll('[data-send]').forEach(b => b.addEventListener('click', () => sendObject(b.dataset.send, b.dataset.sendKind)));
    body.querySelectorAll('[data-watch]').forEach(b => b.addEventListener('click', () => { toggleWatch(); b.textContent = watched() ? (b.classList.contains('primary') ? 'Watching this ripple' : 'Watching') : (b.classList.contains('primary') ? 'Keep watching' : 'Watch'); b.setAttribute('aria-pressed', watched()); }));
    body.querySelectorAll('[data-scroll]').forEach(a => a.addEventListener('click', ev => { ev.preventDefault(); RM.track(a.dataset.scroll === 'past' ? 'seen_before_open' : 'one_more'); closePanel(); $('#' + a.dataset.scroll).scrollIntoView({ behavior: reduce ? 'auto' : 'smooth' }); }));
    body.querySelectorAll('[data-onemore]').forEach(a => a.addEventListener('click', () => RM.track('one_more')));
    body.querySelectorAll('[data-wander]').forEach(a => a.addEventListener('click', () => RM.track('wander')));
    const luck = body.querySelector('#luck'); if (luck) { const io = new IntersectionObserver(en => { if (en.some(x => x.isIntersecting)) { RM.track('luck_open'); io.disconnect(); } }, { root: panel, threshold: .5 }); io.observe(luck); }
    const seen = body.querySelector('#seen'); if (seen) { const io2 = new IntersectionObserver(en => { if (en.some(x => x.isIntersecting)) { RM.track('seen_before_open'); io2.disconnect(); } }, { root: panel, threshold: .5 }); io2.observe(seen); }
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

  /* ---------- send / share: canonical frozen objects (D-16) ---------- */
  const canonRipple = RM.url.canon.ripple(P.event.slug), st = P.story || {};
  function objFor(id, kind) {
    // short (CX fix 8): the story sentence, one number, the tier, the frozen url
    if (kind === 'ripple' || !id) return { title: st.short_title || name, sentence: st.story_sentence, hook: E ? `${feel(E)}${nFlat ? `; ${nFlat} things stayed flat` : ''}. ${tierLine(E)}, never proof of cause.` : (quiet ? null : st.conversation_hook), line: null, url: RM.frozen(canonRipple, P.version), tier: E ? tierOf(E) : (U0 ? 'watching' : 'flat') };
    if (kind === 'stop') { const e = P.effects.find(x => x.id === id); return { title: `${name} → ${e.title}`, sentence: `${name} → ${e.short}: ${feel(e)}.`, hook: `${tierLine(e)}, never proof of cause.`, line: null, url: RM.frozen(RM.url.canon.stop(P.event.slug, e.hop_id || e.id), P.version), tier: tierOf(e) }; }
    if (kind === 'rule') { const s = P.shore.find(x => x.id === id); return { title: s.title, sentence: s.story ? s.story.story_sentence : s.plain, hook: `Seen across ${s.pattern.n_events} past ${noun}s, not one.`, line: `${s.headline} · ${s.pattern.strength} · a pattern, never proof of cause`, url: RM.url.canon.pattern(s.pattern.id), tier: s.pattern.strength }; }
    if (kind === 'watching') { const u = P.untested.find(x => x.id === id); return { title: `${name} → ${u.name}?`, sentence: `${name} might be showing up in ${u.name}. Too early to tell: the window closes ${fmtDayY(u.window_close)}.`, hook: null, line: `${name} → ${u.name}? · still being watched · closes ${fmtDayY(u.window_close)}`, url: RM.frozen(RM.url.canon.stop(P.event.slug, u.hop_id || u.id), P.version), tier: 'watching' }; }
    const n = P.flats.find(x => x.id === id); return { title: `${name} → ${n.name}: dead end`, sentence: `${name} was expected to ripple into ${n.name}. It didn't: the window closed ${fmtDayY(n.window_close)} without a detectable move.`, hook: null, line: `${name} → ${n.name}: dead end · stayed flat`, url: RM.frozen(RM.url.canon.stop(P.event.slug, n.hop_id || n.id), P.version), tier: 'flat' };
  }
  function sendObject(id, kind) { RM.sendObj(objFor(id, kind)); }
  $('#btn-send').addEventListener('click', () => sendObject(null, 'ripple'));
  const bsh = $('#btn-send-hook'); if (bsh) bsh.addEventListener('click', () => sendObject(null, 'ripple'));
  $('#btn-share').addEventListener('click', () => { RM.track('share_tap'); RM.copy(objFor(null, 'ripple').url); });
  // read by tools/shoot.mjs for the tier-wording guard: every share surface with the tier that governs it
  window.__pond = { publishedTier: E ? tierOf(E) : (U0 ? 'watching' : 'flat'), shareText: () => RM.shareText(objFor(null, 'ripple')),
    objects: () => [{ id: 'ripple', tier: E ? tierOf(E) : 'watching', surfaces: { share: RM.shareText(objFor(null, 'ripple')), title: document.title } },
      ...P.effects.map(e => ({ id: e.id, tier: tierOf(e), surfaces: { share: RM.shareText(objFor(e.id, 'stop')), aria: (pond.nodes[e.id] || {}).getAttribute ? pond.nodes[e.id].getAttribute('aria-label') : '' } })),
      ...(P.shore || []).map(s => ({ id: s.id, tier: 'pattern', surfaces: { share: RM.shareText(objFor(s.id, 'rule')) } })),
      ...(P.untested || []).map(u => ({ id: u.id, tier: 'watching', surfaces: { share: RM.shareText(objFor(u.id, 'watching')) } })),
      ...(P.flats || []).map(n => ({ id: n.id, tier: 'flat', surfaces: { share: RM.shareText(objFor(n.id, 'dead')) } }))] };

  /* ---------- watch (device-local) and while you were gone ---------- */
  const WID = 'ripple:' + P.event.slug;
  const watched = () => RM.watched(WID);
  function toggleWatch() { const on = RM.toggleWatch(WID, { kind: 'ripple', title: st.short_title || name, version: P.version, url: RM.url.ripple(P.event.slug), tier: E ? tierOf(E) : 'watching' }); syncWatchBtn(); RM.toast(on ? 'Watching. We keep the changes for you on this device.' : 'No longer watching.'); }
  function syncWatchBtn() { const b = $('#btn-watch'); b.setAttribute('aria-pressed', watched()); b.lastChild.textContent = watched() ? 'Watching this ripple' : 'Watch this ripple'; }
  $('#btn-watch').addEventListener('click', toggleWatch); syncWatchBtn();
  (function gone() {
    const VK = 'rm.pond.seen.' + P.event.slug;
    const seen = RM.ls.json(VK, null), w = RM.watchAll()[WID];
    const from = w ? w.version : seen ? seen.version : null, wasTier = (w && w.tier) || (seen && seen.tier), nowTier = E ? tierOf(E) : (U0 ? 'watching' : 'flat');
    if (from != null && (w || from < P.version || (wasTier && wasTier !== nowTier))) {
      const box = $('#gone'); box.hidden = false;
      // a replayed moment, not a changelog (CX fix 6)
      const changed = wasTier && wasTier !== nowTier;
      box.innerHTML = `<div><b>Since you last looked</b><span>${changed ? `${esc(TIER[wasTier] || wasTier)} → ${esc(TIER[nowTier] || nowTier)}${nowTier === 'measured' ? ': the independent forecast check agreed, so the pad is now solid.' : nowTier === 'flat' ? ': the window closed without a move.' : '.'}` : from < P.version ? `This ripple has grown since ${fmtDay((w && w.seen_at) || seen.at)}.` : `Nothing has changed since ${fmtDay((w && w.seen_at) || seen.at)}.${nWatch ? ` ${nWatch} series ${nWatch === 1 ? 'is' : 'are'} still being watched.` : ''}`}</span>${changed || from < P.version ? `<button class="btn" type="button" id="btn-showme" style="margin-left:auto;padding:5px 12px;font-size:13px">Show me</button>` : ''}</div>`;
      const sm = $('#btn-showme'); if (sm) sm.addEventListener('click', () => { document.body.classList.add('hook'); $('#h1').innerHTML = H1.hook; trace(); });
    }
    RM.ls.set(VK, JSON.stringify({ version: P.version, at: RM.today(), tier: nowTier }));
    if (w) { RM.setWatchVersion(WID, P.version); const all = RM.watchAll(); if (all[WID]) { all[WID].tier = nowTier; RM.ls.set('rm.watch', JSON.stringify(all)); } }
  })();
  /* banners: landed here (Wander), grown since shared (frozen version), fixture data */
  (function banners() {
    const B = $('#banners'); let h = '';
    if (q.get('landed')) h += `<div class="banner landed"><b>You landed here.</b><span>${esc(hook)} What moved, and how sure are we?</span><a class="x" href="${RM.url.wander()}">Wander again</a></div>`;
    const v = parseInt(q.get('v'), 10);
    if (!isNaN(v) && v < P.version) { const since = (P.changelog || []).filter(c => c.version > v); h += `<div class="banner"><b>Grown since you shared it.</b><span>The link was frozen at v${v}; this is v${P.version}. ${since.length ? esc(since.map(c => c.text).join(' ')) : 'The evidence was refreshed.'}</span></div>`; }
    if (P._fixture || (P.event && /polo/i.test(P.event.slug))) h += `<div class="banner fixture"><b>Fixture data.</b><span>This event is a synthetic contract fixture, shown to exercise the design. Nothing here happened.</span></div>`;
    if (h) { B.innerHTML = h; B.style.padding = compact ? '12px 16px 0' : '20px 40px 0'; B.style.maxWidth = '1440px'; B.style.margin = '0 auto'; }
  })();

  /* ---------- the shore: cards ---------- */
  $('#shore-h').textContent = `What else did ${name} touch?`;
  $('#shore-lead').textContent = P.honesty && P.honesty.note ? P.honesty.note : `Everything the engine registered for this ${noun}, in one place.`;
  const chain = $('#chain-list');
  const eventCard = `<li><div class="card event">
      <div class="k"><span>The stone</span><span>${esc(ev.strength || RM.DLABEL[ev.family] || ev.family || '')}</span></div>
      <div class="ev">${esc(name)}${noun === 'storm' ? ' makes landfall' : ''}</div>
      <p class="ev-sub">${esc([ev.place, ev.date || fmtDayY(ev.onset)].filter(Boolean).join(', '))}.${ev.onset ? ` Engine onset ${fmtDay(ev.onset)}.` : ''}</p>
      <div class="strip"><div>Shock size<b>${ev.magnitude == null ? 'not scored' : `<span class="num">${Math.round(ev.magnitude * 100)}</span> / 100`}</b></div><div>Series registered<b class="num">${nFlat + nWatch + nMoved}</b></div><div>Moved<b class="num">${nMoved}</b></div><div>Stayed flat<b class="num">${nFlat}</b></div><div>Watched<b class="num">${nWatch}</b></div>${E ? `<div>Published tier<b>${esc(tierWord(E))}</b></div>` : ''}</div>
    </div></li>`;
  const effectCards = P.effects.map(e => `<li><button class="card" type="button" data-open="${esc(e.id)}" data-kind="effect">
      <div class="k"><span class="step">${glyph(tierOf(e))}${esc(tierLine(e))}</span><span>${esc(P.domains[e.domain])}, ${esc(e.lag_text || '')}</span></div>
      <div class="n num">${esc(e.num_pct || e.num || '?')}<small>${esc(e.unit_plain || (e.num_pct_kind === 'peak' ? 'at its peak, vs its normal' : 'vs its normal'))}</small></div>
      <p class="f">${esc((e.plain_long || e.plain).split('. ')[0])}.</p>
      ${e.chart && e.chart.series ? `<div class="spark chart">${seriesChart(e, 320, 56, true)}</div>` : ''}
      <div class="foot"><span>${e.mediation_supported && e.parent !== 'event' ? 'A chain: mediation supported' : `Forks straight from the ${noun}`}</span><span class="open">See the evidence</span></div>
    </button></li>`).join('');
  const ruleCards = (P.shore || []).map(s => `<li><button class="card rule" type="button" data-open="${esc(s.id)}" data-kind="shore">
      <div class="k"><span class="step">${glyph('pattern')}${esc(s.pattern.strength)}</span><span>${s.pattern.n_events} ${noun}s</span></div>
      <div class="n num">${esc(s.num)}<small>${esc(s.unit)}</small></div>
      <p class="f">${esc(s.story ? s.story.story_sentence : s.plain)} ${esc(name)} itself is untested on this.</p>
      <div class="foot"><span>The far shore: a rule, not a ${esc(name)} result</span><span class="open">See the rule</span></div>
    </button></li>`).join('');
  const flatCard = nFlat ? `<li><div class="card wait"><div class="k"><span>The ripple stopped here</span><span>${nFlat} reed${nFlat === 1 ? '' : 's'}</span></div><p class="f" style="color:var(--ink-2)">Registered ${ev.registered ? 'on ' + fmtDayY(ev.registered) : 'in advance'} with windows and priors written down first. Each was tested the same way as a bright pad and stayed inside its normal range.</p>
      <div class="chips">${P.flats.map(u => `<button type="button" data-open="${esc(u.id)}" data-kind="flat"><svg aria-hidden="true"><use href="#k-grass"/></svg>${esc(u.name)}</button>`).join('')}</div></div></li>` : '';
  const watchCards = nWatch ? `<li><button class="card" type="button" data-open="${esc(U0.id)}" data-kind="untested"><div class="k"><span class="step">${glyph('watching')}Watching</span><span>${nWatch === 1 ? esc(P.domains[U0.domain]) : nWatch + ' series'}</span></div><p class="f">${nWatch === 1 ? `${esc(U0.name)}: the engine is still waiting. Too early to tell.` : `${nWatch} series are still being watched: ${P.untested.slice(0, 3).map(u => esc(u.name)).join(', ')}${nWatch > 3 ? '…' : ''}.`}</p><div class="foot"><span>Window ${RM.daysUntil(U0.window_close) >= 0 ? 'closes' : 'closed'} ${fmtDayY(U0.window_close)}</span><span class="open">See the window</span></div></button></li>` : '';
  const rivalCards = (P.rivals || []).map(rv => `<li><div class="card note"><div class="k"><span>Rings that overlap</span><span>${rv.days_before} days apart</span></div><p><b>${esc(rv.name)}</b> came ${rv.days_before} days before ${esc(name)}. ${esc((rv.note || '').split('. ').slice(1).join('. '))}</p></div></li>`).join('');
  const boulderCards = (P.filtered || []).map(b => `<li><div class="card note"><div class="k"><span>Filtered out</span><span>1 boulder</span></div><p><b>${esc(b.name)}</b>: ${esc(b.note || '')}</p></div></li>`).join('');
  chain.innerHTML = eventCard + effectCards + ruleCards + flatCard + watchCards + rivalCards + boulderCards;
  chain.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => open(b.dataset.open, b.dataset.kind)));

  /* replication strip: tiny ponds for the past events on the same test */
  if (E && E.replication && E.replication.all) {
    const R = E.replication; $('#past').hidden = false;
    $('#past-h').textContent = `Passed after ${R.n_seen} of ${R.n_similar} past ${noun}s`;
    $('#past-lead').textContent = `The regional contrast on ${E.short}, ${noun} by ${noun}. A half pad means the regional test passed; reeds mean it did not, whichever way it moved. ${R.family ? R.family.note : ''}`;
    const row = $('#past-row');
    const mini = (label, year, pct, pass, cur) => { const card = document.createElement('div'); card.className = 'past-card' + (pass ? '' : ' no'); if (cur) card.setAttribute('aria-current', 'true'); card.setAttribute('role', 'img'); card.setAttribute('aria-label', `${label} ${year}: ${E.short} ${pct}% against unaffected regions, ${pass ? 'regional test passed' : 'no pass'}`);
      const sv = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); card.appendChild(sv);
      Pond.render(sv, { event: { name: label, magnitude: .5, label: false }, domains: P.domains, rings: P.rings, effects: pass ? [{ id: 'c', domain: E.domain, lag_days: E.lag_days, magnitude: Math.min(1, Math.abs(pct) / 25), tier: 'likely', kind: 'pad', num: '', short: '', headline: '', plain: '' }] : [], flats: pass ? [] : [{ name: E.short, domain: E.domain, lag_days: E.lag_days }] }, { thumb: true, reduceMotion: true, viewBox: [-470, -470, 940, 940] });
      card.insertAdjacentHTML('beforeend', `<div class="pn">${esc(label.replace(/^(Hurricane|Tropical storm) /, ''))}<small class="num">${year}</small></div><div class="ps"><b>${pct > 0 ? '+' : ''}${pct}%</b> ${pass ? 'passed' : 'no pass'}</div>`); return card; };
    R.all.forEach(s => row.appendChild(mini(s.label, s.year, s.effect_pct, s.pass, false)));
    if (E.contrast) row.prepend(mini(name.replace(/^Hurricane /, ''), String(ev.onset).slice(0, 4), E.contrast.effect_pct, true, true));
  }

  /* the ripple stopped here: honest when there are no flats */
  const sb = $('#stopped-body');
  if (nFlat) sb.innerHTML = `<p><b>${numw(nFlat)} thing${nFlat === 1 ? '' : 's'}</b> we said in advance might move, and did not. ${esc(P.flats_note || '')}${P.controls && P.controls.length ? ` ${P.controls.length} negative controls (${P.controls.map(c => esc(c.name.replace(' (control)', ''))).join(', ')}) also stayed flat, so a nationwide move could not pass as local.` : ''} ${nMoved ? 'They are the reason the bright pad can be trusted.' : 'A dead end we disclose is a finding too.'}</p><div class="waiting">${P.flats.map(n => `<button type="button" data-open="${esc(n.id)}" data-kind="flat"><svg aria-hidden="true"><use href="#k-grass"/></svg>${esc(n.name)}${n.t_stat != null ? `<small style="color:var(--muted)">T ${n.t_stat.toFixed(1)}</small>` : ''}</button>`).join('')}</div>`;
  else sb.innerHTML = `<p><b>Nowhere, yet.</b> ${esc(P.flats_note || '')}${nWatch ? ` ${nWatch} series ${nWatch === 1 ? 'is' : 'are'} still inside ${nWatch === 1 ? 'its' : 'their'} window.` : ' Nothing registered for this event has closed flat.'}</p><div class="waiting">${(P.untested || []).map(u => `<button type="button" data-open="${esc(u.id)}" data-kind="untested"><svg aria-hidden="true"><use href="#k-float"/></svg>${esc(u.name)}</button>`).join('')}</div>`;
  sb.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => open(b.dataset.open, b.dataset.kind)));

  /* one more: the next best real story (a world rule in another family), plus where events like it usually reach */
  const NX = P.pattern_next;
  let om = '';
  try {
    const idx = await RM.data.pondIndex();
    const next = (idx.ponds || []).filter(p => p.slug !== P.event.slug && (p.stops.measured + p.stops.likely > 0)).sort((a, b) => (b.stops.measured * 3 + b.stops.likely) - (a.stops.measured * 3 + a.stops.likely))[0] || (idx.ponds || []).find(p => p.slug !== P.event.slug);
    if (next) { const nn = next.name.replace(/ \(positive control\)$/, ''), moved = next.stops.measured + next.stops.likely, tease = moved ? `${moved} thing${moved === 1 ? '' : 's'} moved and ${next.stops.flat} stayed flat. Which?` : `${next.stops.watching} series are being watched. Nothing has resolved yet.`;
      om += `<div><h3>This wasn’t the end</h3><p class="lead">One more. Another stone, another pond.</p><a class="card" href="${RM.url.ripple(next.slug)}" data-onemore><div class="k"><span class="step">${esc(RM.DLABEL[next.family] || next.family.replace(/^hazard\./, '').replace(/^tech\./, '').replace(/^policy\./, '').replace(/_/g, ' '))}</span><span>${fmtDayY(next.onset)}</span></div><p class="big-p">${esc(nn)}${/\d{4}\)$/.test(nn) || /\d{4}-\d\d-\d\d/.test(nn) ? '' : ' hits'}. ${esc(tease)}</p><div class="foot"><span>${next.is_control ? 'A known-effect test case' : next.sensitive ? 'Shown quietly' : 'A live line'}</span><span class="open">Trace it</span></div></a></div>`; }
  } catch { /* no index */ }
  if (NX) om += `<div><h3>${om ? 'And a world rule' : 'This wasn’t the end'}</h3><p class="lead">${om ? '' : 'One more. '}A different kind of ${noun === 'storm' ? 'weather' : 'event'}: what the engine finds when it pools every ${esc(NX.event_label.toLowerCase())} since 2015.</p>
      <a class="card" href="${RM.url.pattern(NX.id)}" data-onemore><div class="k"><span class="step">${glyph('pattern')}${esc(NX.strength)}</span><span>${NX.n_events} ${esc(NX.event_label.toLowerCase())}</span></div>
      <p class="big-p">${esc(NX.story.story_sentence)}</p>
      <p style="font-size:14px;color:var(--ink-2);margin:6px 0 0">Confidence interval ${NX.ci[0]}% to ${NX.ci[1]}%; ${esc(NX.fluke_note)}. Largest: ${NX.examples.map(x => `${esc(x.label.replace(/ \(\d+ states\)/, ''))} +${Math.round((Math.exp(x.d) - 1) * 100)}%`).join('; ')}.</p>
      <div class="foot"><span>A world rule, flip through every ${esc(NX.event_label.toLowerCase().replace(/s$/, ''))}</span><span class="open">Open the rule</span></div></a></div>`;
  else if (N.one_more) om += `<div><h3>This wasn’t the end</h3><p class="lead">One more.</p><a class="card" href="${N.one_more.story_id.startsWith('pattern:') ? RM.url.pattern(N.one_more.story_id.split(':')[1]) : ROOT + 'r/?e=' + encodeURIComponent(N.one_more.story_id.split(':')[1])}" data-onemore><div class="k"><span class="step">${N.one_more.story_id.startsWith('pattern:') ? glyph('pattern') + 'World rule' : 'Ripple'}</span>${N.one_more.archetype ? `<span>${esc(N.one_more.archetype)}</span>` : ''}</div><p class="big-p">${esc(N.one_more.short_title)}</p><div class="foot"><span>${N.one_more.story_id.startsWith('pattern:') ? 'Across many past events' : 'Another event'}</span><span class="open">Open</span></div></a></div>`;
  if (S && S.pattern.all) { const bars = S.pattern.all.slice().sort((a, b) => a.effect_pct - b.effect_pct);
    om += `<div><h3>Where ${noun}s usually reach</h3><p class="lead">Each bar is one past ${noun}’s effect on ${esc(S.short)} in the hit states, against unaffected states. The rule behind the cairn on the far shore.</p>
      <div class="card"><div class="dots" aria-hidden="true">${bars.map(b => `<i style="height:${Math.round(Math.min(100, Math.abs(b.effect_pct) / 25 * 100))}%;${b.effect_pct > 0 ? 'opacity:.35' : ''}" class="${b.pass ? 'm' : ''}" title="${esc(b.label)} ${b.effect_pct}%"></i>`).join('')}</div>
      <p style="font-size:12.5px;color:var(--muted);margin-top:6px">${bars.length} ${noun}s tested, sorted (${S.pattern.n_events} once overlapping ones are merged). Dark bars passed the regional test; faint bars moved the other way. ${esc(name)} is not among them: it was not registered for this series.</p></div></div>`; }
  if (!om) om = `<div><h3>This wasn’t the end</h3><p class="lead">Wander lands you on another ripple or a world rule, instantly.</p><a class="card" href="${RM.url.wander()}" data-wander><p class="big-p">Wander</p><div class="foot"><span>Never a dead end</span><span class="open">Jump</span></div></a></div>`;
  $('#onemore').innerHTML = om;
  document.querySelectorAll('[data-onemore]').forEach(a => a.addEventListener('click', () => RM.track('one_more')));
  document.querySelectorAll('[data-wander]').forEach(a => a.addEventListener('click', () => RM.track('wander')));

  /* deep link: ?stop=hop opens that card */
  if (stopParam) { const all = [...P.effects.map(e => [e, 'effect']), ...(P.untested || []).map(u => [u, 'untested']), ...(P.flats || []).map(f => [f, 'flat']), ...(P.shore || []).map(s => [s, 'shore'])]; const hit = all.find(([o]) => String(o.hop_id) === stopParam || o.id === stopParam); if (hit) setTimeout(() => open(hit[0].id, hit[1]), 300); }
})();
