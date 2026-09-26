/* Ripple Map v1: NOW. The flagship pond, then story cards ranked by the story layer, world rules, dead ends and open windows.
   Every sentence comes from rm_stories / the pond payload; tier words are the gated published tiers. */
(async function () {
  const { $, esc, fmtDayY, TIER, ROOT, compact } = RM;
  RM.nav('now'); RM.analytics('pond_now');
  let S, X, F;
  try { [S, X] = await Promise.all([RM.data.stories(), RM.data.pondIndex()]); } catch (e) { S = { featured: [] }; X = { ponds: [] }; }
  const items = (S.featured || []).filter(s => !s.is_control || (s.event && s.event.slug === X.flagship));
  const score = s => (s.scores && s.scores.story) || 0;
  const tierRank = { measured: 3, likely: 2, 'strong pattern': 2, pattern: 1, watching: 0, flat: 0 };

  /* ---------- the ripple of the moment: the highest story score with a published Measured or Likely stop; else the flagship pond ---------- */
  const cascades = items.filter(s => s.kind === 'cascade' && (s.tier === 'measured' || s.tier === 'likely')).sort((a, b) => (tierRank[b.tier] - tierRank[a.tier]) || score(b) - score(a));
  const heroStory = cascades[0] || null;
  const heroSlug = heroStory ? heroStory.event.slug : (X.flagship || (X.ponds[0] && X.ponds[0].slug));
  try { F = heroSlug ? await RM.data.pond(heroSlug) : null; } catch { F = null; }
  document.body.classList.remove('loading');
  const feat = $('#feat');
  if (F) {
    const E = F.effects.slice().sort((a, b) => (tierRank[(b.published || b).tier] || 0) - (tierRank[(a.published || a).tier] || 0) || (b.magnitude || 0) - (a.magnitude || 0))[0];
    const tier = E ? (E.published || E).tier : 'watching';
    const st = F.story || {};
    $('#feat-arch').innerHTML = RM.tierPill(tier, E ? E.published.text : 'Watching') + ' ' + (st.archetype ? RM.archTag(st.archetype) : '');
    $('#feat-h1').innerHTML = `${esc(F.event.name)}. <span class="quiet">${esc(st.hook || (E ? `${E.lag_text[0].toUpperCase() + E.lag_text.slice(1)}, something moved in ${E.short}.` : 'The rings are still travelling.'))}</span>`;
    $('#feat-num').innerHTML = E && E.num_pct ? `${esc(E.num_pct)}<small>${esc(E.unit_plain || `${E.short}, vs its normal`)}</small>` : '';
    $('#feat-trust').innerHTML = E && E.engine && E.engine.n_date ? `We re-ran the test on ${E.engine.n_date.toLocaleString()} random days: only ${E.engine.exceed_date} looked this strong.${E.contrast ? ` The ${E.contrast.n_donors} regions the storm missed didn’t move.` : ''}${E.published.ce && E.published.ce.state === 'agree' ? ' An independent forecast model agrees.' : ''}` : E && E.fluke ? esc(E.fluke.text) : esc(st.tier_wording || '');
    const T = F.travel, nFlat = (F.flats || []).length;
    $('#feat-reach').innerHTML = `${nFlat ? `<span class="num">${nFlat}</span> things stayed flat · ` : ''}${T && T.days != null ? `<span class="num">${T.domains}</span> domain${T.domains === 1 ? '' : 's'} · <span class="num">${T.days}</span> days` : `<span class="num">${(F.untested || []).length}</span> still being watched`}<small>${nFlat ? 'The expected ripple moved; the surprise is what didn’t.' : 'How far the ripple travelled.'}</small>`;
    $('#feat-trace').href = RM.url.ripple(F.event.slug); $('#feat-link').href = RM.url.ripple(F.event.slug) + '#traced';
    $('#feat-note').textContent = F.event.is_control ? (F.honesty && F.honesty.control_note) || 'A known-effect test case, published with its real, gated tiers.' : F.honesty && F.honesty.quiet ? 'A sensitive event, shown quietly.' : '';
    const sv = $('#feat-pond');
    Pond.render(sv, { ...F, rivals: [], filtered: [] }, { compact, reduceMotion: true, viewBox: compact ? [-480, -480, 960, 960] : [-560, -470, 1120, 940] });
    sv.setAttribute('aria-label', `The pond: ${F.event.name} as a stone; ${F.effects.length} pad${F.effects.length === 1 ? '' : 's'} for the things that moved, ${nFlat} reed beds for the things that stayed flat.`);
    sv.querySelectorAll('[tabindex]').forEach(g => g.removeAttribute('tabindex'));
    $('#feat-send').addEventListener('click', () => RM.sendObj({ title: st.short_title || F.event.name, sentence: st.story_sentence, hook: E ? `${E.num_pct} ${E.unit_plain || E.short + ', vs its normal'}${nFlat ? `; ${nFlat} things stayed flat` : ''}. ${E.published.text}, never proof of cause.` : null, url: RM.frozen(RM.url.canon.ripple(F.event.slug), F.version) }));
    window.__pond = { publishedTier: tier, shareText: () => [$('#feat-h1').textContent, $('#feat-trust').textContent].join(' '), objects: () => [{ id: 'feat', tier, surfaces: { h1: $('#feat-h1').textContent, trust: $('#feat-trust').textContent, pill: $('#feat-arch').textContent, aria: sv.getAttribute('aria-label') } }] };
  } else {
    feat.innerHTML = `<div class="empty"><b>Quiet on the pond.</b> No ripple has resolved yet today. The open questions below each have a date; Wander lands you on the most interesting one.</div>`;
    window.__pond = { publishedTier: 'watching', shareText: () => '', objects: () => [] };
  }

  /* ---------- story cards: one pattern, then the best cascades, one per event, controls excluded ---------- */
  const seen = new Set(F ? [F.event.slug] : []);
  const pick = (list, n) => { const out = []; for (const s of list) { const k = s.event ? s.event.slug : 'pattern:' + s.pattern.id; if (seen.has(k)) continue; seen.add(k); out.push(s); if (out.length >= n) break; } return out; };
  const patterns = items.filter(s => s.kind === 'pattern').sort((a, b) => score(b) - score(a));
  const cardList = [...pick(patterns, 1), ...pick(cascades, 2)];
  if (cardList.length < 3) cardList.push(...pick(items.filter(s => s.kind === 'watching').sort((a, b) => score(b) - score(a)), 3 - cardList.length));
  const card = s => {
    const kind = s.kind, ev = s.event, href = RM.storyHref(s), tier = s.tier;
    const travel = s.travel && s.travel.days != null && kind !== 'pattern' ? `${s.travel.domains_crossed} domain${s.travel.domains_crossed === 1 ? '' : 's'} · ${s.travel.days} days · ${RM.ord(s.travel.depth || 1)}-order` : kind === 'pattern' ? `${s.pattern.n_events} past events` : s.watching ? `closes ${fmtDayY(s.watching.window_close)}` : '';
    return `<li><a class="sc ${kind === 'pattern' ? 'rule' : kind === 'non_event' ? 'dead' : kind === 'watching' ? 'watching' : ''}" href="${href}">
      <div class="k">${RM.archTag(s.archetype)}${RM.tierPill(tier, s.demoted && s.gate_reason ? `${TIER[tier]}, ${s.gate_reason}` : null)}</div>
      <div class="thumb"><svg></svg></div>
      <p class="s">${esc(s.story_sentence)}</p>
      <div class="m"><span>${esc(travel)}${ev && ev.sensitive ? ' · quiet' : ''}</span><span class="go">${kind === 'pattern' ? 'Open the rule' : kind === 'watching' ? 'See the window' : 'Trace it'}</span></div></a></li>`;
  };
  const fill = (id, list, empty) => { const el = $(id); if (!list.length) { el.outerHTML = `<div class="empty">${empty}</div>`; return; } el.innerHTML = list.map(card).join(''); el.querySelectorAll('.thumb svg').forEach((sv, i) => RM.thumb(sv, list[i])); };
  fill('#cards', cardList, '<b>Nothing resolved yet.</b> When a stop reaches Likely or Measured it appears here.');

  /* ---------- world rules ---------- */
  let rules = [];
  try { const Pt = await RM.data.patterns(); rules = (Pt.patterns || Pt).filter(p => p.strength === 'strong pattern' || p.strength === 'pattern').sort((a, b) => a.q - b.q); } catch { rules = []; }
  const rc = $('#rule-cards');
  if (!rules.length) rc.outerHTML = '<div class="empty"><b>No rule has cleared the bar yet.</b> Patterns need q ≤ 0.05 with the expected sign across enough past events.</div>';
  else {
    rc.innerHTML = rules.map(p => { const st = items.find(s => s.kind === 'pattern' && s.pattern.id === p.id); return `<li><a class="sc rule" href="${RM.url.pattern(p.id)}">
      <div class="k">${RM.archTag(st ? st.archetype : null)}${RM.tierPill(p.strength)}</div>
      <div class="thumb"><svg></svg></div>
      <p class="s">${esc(st ? st.story_sentence : `Across ${p.n_events} past ${p.event_label.toLowerCase()}, ${p.outcome_label} ${p.effect > 0 ? 'rose' : 'fell'}: ${Math.abs(p.effect)}% vs unaffected regions.`)}</p>
      <div class="m"><span>${p.n_events} past events · ${esc(p.fluke_note)}</span><span class="go">Flip through them</span></div></a></li>`; }).join('');
    rc.querySelectorAll('.thumb svg').forEach((sv, i) => RM.thumb(sv, { kind: 'pattern', pattern: rules[i], event: null }));
  }

  /* ---------- the ripple that died: dead ends, one per event first ---------- */
  const dead = items.filter(s => s.kind === 'non_event').sort((a, b) => score(b) - score(a));
  const deadPick = []; const dseen = new Set(); dead.forEach(s => { if (deadPick.length < 4 && !dseen.has(s.event.slug)) { dseen.add(s.event.slug); deadPick.push(s); } }); dead.forEach(s => { if (deadPick.length < 4 && !deadPick.includes(s)) deadPick.push(s); });
  const dc = $('#dead-cards');
  if (!deadPick.length) dc.outerHTML = '<div class="empty"><b>No window has closed flat yet.</b> Every pre-registered series that stays inside its normal range will be shown here.</div>';
  else dc.innerHTML = deadPick.map(s => `<li><a class="sc dead" href="${RM.storyHref(s)}"><div class="k">${RM.archTag('Dead end')}${RM.tierPill('flat')}</div><p class="s"><svg style="width:22px;height:16px;vertical-align:-2px;margin-right:4px" aria-hidden="true"><use href="#k-grass"/></svg>${esc(s.story_sentence)}</p><div class="m"><span>${s.watching && s.watching.expected_1_in ? `expected about 1 in ${s.watching.expected_1_in} times` : ''}${s.watching && s.watching.window_close ? ` · closed ${fmtDayY(s.watching.window_close)}` : ''}</span><span class="go">See why</span></div></a></li>`).join('');

  /* ---------- still being watched: nearest windows first, one per event first ---------- */
  const watching = items.filter(s => s.kind === 'watching' && s.watching && s.watching.window_close).sort((a, b) => new Date(a.watching.window_close) - new Date(b.watching.window_close) || score(b) - score(a));
  const wPick = []; const wseen = new Set(); watching.forEach(s => { if (wPick.length < 4 && !wseen.has(s.event.slug)) { wseen.add(s.event.slug); wPick.push(s); } }); watching.forEach(s => { if (wPick.length < 4 && !wPick.includes(s)) wPick.push(s); });
  const wc = $('#watch-cards');
  if (!wPick.length) wc.outerHTML = '<div class="empty"><b>Nothing is open.</b> Every registered window has resolved.</div>';
  else wc.innerHTML = wPick.map(s => `<li><a class="sc watching" href="${RM.storyHref(s)}"><div class="k">${RM.tierPill('watching')}<span>${esc(s.event.label.replace(/ \(positive control\)$/, ''))}</span></div><div class="cd">${esc(RM.countdown(s.watching.window_close))}<small>window ${RM.daysUntil(s.watching.window_close) >= 0 ? 'closes' : 'closed'} ${fmtDayY(s.watching.window_close)}</small></div>${RM.winBar(s.event.onset, s.watching.window_close)}<p class="s" style="font-size:15px;margin-top:8px">${esc(s.story_sentence)}</p><div class="m"><span>${s.watching.expected_1_in ? `a move about 1 in ${s.watching.expected_1_in} times` : ''}</span><span class="go">Watch</span></div></a></li>`).join('');

  /* ---------- the forward-test ticket: the next window to close ---------- */
  const next = watching.find(s => RM.daysUntil(s.watching.window_close) >= 0);
  if (next) { $('#ticket-sec').hidden = false; $('#ticket').innerHTML = `<div><span class="eyebrow" style="margin-bottom:4px">Next forward test</span><b>${esc(next.short_title)}</b><span>${esc(next.story_sentence)}${next.watching.expected_1_in ? ` Similar events: a move by then about 1 in ${next.watching.expected_1_in} times.` : ''} Registered before anyone looked.</span></div><div class="cd">${esc(RM.countdown(next.watching.window_close))}<small>window closes ${fmtDayY(next.watching.window_close)}</small><a class="btn" style="margin-top:8px" href="${RM.storyHref(next)}"><svg width="16" height="16" aria-hidden="true"><use href="#i-eye"/></svg>Watch it</a></div>`; }

  /* ---------- while you were gone (device-local; keyed on story versions and tiers) ---------- */
  const prev = RM.noteSeen(S);
  const diff = RM.gone(S, prev);
  if (diff && diff.length) {
    const g = $('#gone'); g.hidden = false;
    const top = diff.slice(0, 6);
    g.innerHTML = `<div class="sec" style="margin-top:0;padding-top:0;border:0"><div class="head"><h2>While you were gone</h2><a href="${RM.url.watch()}">Everything you watch</a></div><p class="lead">Since ${fmtDayY(prev.at)}: ${diff.length} change${diff.length === 1 ? '' : 's'}${Object.keys(RM.watchAll()).length ? ', watched items first' : ''}.</p><ul class="timeline">${top.map(d => `<li><i class="${d.kind === 'flat' ? 'flat' : d.kind === 'new' || d.kind === 'pattern' ? 'new' : d.kind === 'moved' || d.kind === 'grew' ? '' : 'dot'}"></i><span>${esc(d.text)} ${d.watched ? '<small>(watched)</small>' : ''}</span><a href="${d.href}">Show me</a></li>`).join('')}</ul></div>`;
  }
  $('#foot').textContent = `${S._src === 'live' ? 'Live' : 'Snapshot'} ${S.as_of || ''}: ${S.pool ? `${S.pool.public} public stories across ${S.pool.events_with_story} events` : ''}. ${S.note || ''}`;
})();
