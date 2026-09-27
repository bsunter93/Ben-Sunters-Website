// Knock⌃On Ripple Map v6 (WS-D). One module for every /ripples/ page; the page's <body data-route> (set by the shells and by
// ripples/tools/gen-stubs.mjs) picks the renderer. Data: the stub's inlined #rm-data first, then Storage v2/, then the RPC.
import * as C from './config.js';
import * as L from './lib.js';
import { $, add, h, S, em, sep, joinSep, put, icon, IC, RM, desk, ls, today, INLINE, D, rpc, load, event, toast, copy, share, prefetchImg, shareImage, landing, flaps, countUp, setFlaps, untilLook, tt_, pips, stamp, dtile, strip, legend, spark, theme, wander, chrome, visits, seedChart, getBip } from './ui.js';

// ---------- HOME ----------
function heroTicket(S0, archive) {
  const hero = S0?.hero;
  const tk = h('section', { class: 'ticket hero grain', 'aria-labelledby': 'hero-t' });
  if (!hero) {
    // Cold start with nothing Measured anywhere: the board is watching. Say what is open and when the first look lands
    // (never pad a headline); the reconstructed archive line follows as a second ticket (home(), archiveTicket)
    const rows = (S0?.shocks || []);
    const due = rows.map(r => r.next_due).filter(d => d && d >= today()).sort()[0];
    const dueRow = due ? rows.find(r => r.next_due === due) : null;
    // the hook states only what the rows show: Measured and Likely counts are summed from the board, never assumed zero
    const nM = rows.reduce((a, r) => a + (r.stops?.measured || 0), 0), nL = rows.reduce((a, r) => a + (r.stops?.likely || 0), 0), nW = rows.reduce((a, r) => a + (r.stops?.watching || 0), 0);
    const hook = !rows.length ? 'No lines are published yet.'
      : nM ? `${L.plural(rows.length, 'line')} on the board, with ${L.plural(nM, 'Measured stop')} among them. None is picked as the headline today.`
      : `${L.plural(rows.length, 'line')}, ${L.plural(nW, 'window')} open.${nL ? ` ${L.plural(nL, 'Likely stop')} so far, none Measured yet.` : ''}${due ? ` First result due ${L.fmtDate(due)}.` : ''}`;
    tk.classList.add('cold');
    const cd = due ? flaps(untilLook(due), 'ink', `${untilLook(due)} to the next look`) : null;
    if (cd && !RM) { const t = setInterval(() => { if (!cd.isConnected) return clearInterval(t); setFlaps(cd, untilLook(due)); }, 60000); }
    add(tk, h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, 'Ripple of the week')),
      h('div', { class: 'tk-body' },
        h('h1', { class: 'tk-title', id: 'hero-t' }, nM ? 'No headline today' : 'The board is watching'),
        h('p', { class: 'tk-hook' }, hook),
        h('p', { class: 'tk-sub' }, 'A stop lands here only when it passes every test: its own normal, timing, two sources, and the fluke controls.'),
        h('div', { class: 'tk-path' }, h('span', { class: 'dt shock', 'aria-hidden': 'true' }, em(dueRow?.emoji || rows[0]?.emoji || '🌀')), h('span', { class: 'trk', 'aria-hidden': 'true' }), h('span', { class: 'dt q', 'aria-hidden': 'true' }, '?'),
          h('span', { class: 'lbl' }, cd ? [cd, h('br'), h('span', { style: 'font-weight:500' }, `to the next look${dueRow ? `: ${dueRow.label}` : ''}`)] : 'Waiting for the first result'))),
      h('div', { class: 'tk-perf', 'aria-hidden': 'true' }, h('span', { class: 'notch l' }), h('span', { class: 'notch r' })),
      h('div', { class: 'tk-foot' }, h('a', { class: 'btn', href: '#departures' }, 'See what we are watching')));
    return tk;
  }
  const s = (S0.shocks || []).find(x => x.event_id === hero.event_id) || (archive || []).find(x => x.event_id === hero.event_id) || {};
  const quiet = !!(hero.sensitive || s.sensitive);
  if (quiet) tk.classList.add('quiet');
  const svg = S('svg', { class: 'tk-chart', role: 'img', 'aria-label': `${hero.title}: attention against its own normal over the last weeks, peaking at ${L.num(s.magnitude_x)} times normal.` });
  const hasChart = s.spark ? seedChart(svg, s.spark, quiet, L.num(s.magnitude_x) + '×') : false;
  const st = hero.stop || {};
  // the tile row: shock → the Measured stop (or, for an archive line without a headline stop, the domains it reached)
  const tiles = st.domain ? [st.domain] : (s.domains_reached || s.domains || []).slice(0, 3);
  const path = h('div', { class: 'tk-path', id: 'hero-path' }, h('span', { class: 'dt shock', 'aria-hidden': 'true' }, em(s.emoji || '🌀')),
    tiles.map((d, i) => [h('span', { class: 'trk', 'aria-hidden': 'true' }), h('span', { class: 'dt measured', 'aria-hidden': 'true' }, em(L.domIcon(d))),
      i === tiles.length - 1 ? h('span', { class: 'lbl' }, tiles.length === 1 ? L.domWord(d) : tiles.map(L.domWord).join(', '), h('br'), h('span', { class: 'tier' }, pips(3), 'Measured')) : null]));
  // a live row carries stops as {measured, likely, …}; an archive row (reconstructed hero) carries a count and `domains`
  const stops = typeof s.stops === 'number' ? s.stops : s.stops ? (s.stops.measured || 0) + (s.stops.likely || 0) : null;
  const doms = s.domains_reached || s.domains;
  const meta = joinSep([stops != null ? L.plural(stops, 'stop') : null, doms ? L.plural(doms.length, 'domain') : null, L.STATUS[s.status] || null, hero.reconstructed ? 'reconstructed' : null]);
  // the size in words under the engine's headline: "9% fewer US air travellers than on a normal Wednesday." (client gloss, §4)
  const gloss = L.pctGloss(st.rho, st.unit);
  const onsetDay = st.onset || (s.onset && st.lag_days != null ? L.addDays(s.onset, Math.round(st.lag_days)) : null);
  const sub = gloss && st.label ? `${gloss[0].toUpperCase()}${gloss.slice(1)} ${st.domain === 'reading' && !/readers?$/i.test(st.label) ? `${st.label} readers` : st.label} than on a normal ${onsetDay ? L.fmtDate(onsetDay, true).split(' ')[0] : 'day'}.` : null;
  // the staircase (signature B) replaces the seed chart once the cascade arrives; its height is reserved so nothing shifts
  const stage = h('div', { class: 'tk-stage' + (stops >= 2 ? ' tall' : '') }, hasChart ? svg : null);
  add(tk,
    h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, hero.reconstructed ? 'From the archive, reconstructed' : 'Ripple of the week'), !hero.reconstructed && visits() < 2 ? h('span', { class: 'tag2' }, 'shock → where it showed up') : null, hero.version ? h('span', { class: 'ver' }, 'v' + hero.version) : null),
    h('div', { class: 'tk-body' },
      h('div', { class: 'tk-row' }, h('span', { class: 'tk-emo', 'aria-hidden': 'true' }, em(s.emoji || '🌀')), h('h1', { class: 'tk-title', id: 'hero-t' }, hero.title)),
      h('p', { class: 'tk-hook' }, hero.headline),
      sub ? h('p', { class: 'tk-sub gloss' }, sub) : null,
      s.magnitude_x ? h('p', { class: 'tk-sub' }, joinSep([`Peaked at ${L.num(s.magnitude_x)}× its normal readers`, L.biggest(s) || null])) : null,
      hasChart || stops >= 2 ? stage : null, path),
    h('div', { class: 'tk-perf', 'aria-hidden': 'true' }, h('span', { class: 'notch l' }), h('span', { class: 'notch r' })),
    h('div', { class: 'tk-foot' }, meta.length ? h('p', { class: 'tk-meta' }, meta) : null, h('a', { class: 'btn', href: L.lineUrl(hero.slug) + (ls.get('ko.hide_middle') === '1' ? '?hide=1' : '') }, 'Trace the line')));
  // "?" tiles hide only the stops between the shock and that Measured stop; they flip once through domain icons (not in quiet mode)
  D.cascade(hero.event_id).then(c => {
    if (!c || L.stopCount(c) < 2) { if (!hasChart) stage.remove(); else stage.classList.remove('tall'); }
    if (!c) return;
    const mid = st.hop_id ? L.ancestors(c, st.hop_id) : [];
    const trk = path.children[1];
    mid.forEach(() => {
      const q = h('span', { class: 'dt q', 'aria-hidden': 'true' }, '?');
      trk.after(q, h('span', { class: 'trk', 'aria-hidden': 'true' }));
      if (!RM && !quiet) { const ic = L.DOMAINS.map(k => L.DOM[k].i); let i = 0; const t = setInterval(() => { q.textContent = i < 6 ? ic[i++ % ic.length] : '?'; if (i >= 6) { clearInterval(t); q.textContent = '?'; } }, 110); }
    });
    // Signature B: with two or more moved stops the ticket carries the line's staircase, auto-replayed every 6 s
    // (lanes draw in the order the stops moved, hold, loop); reduced motion and quiet mode show the final frame. One tap opens the line.
    if (L.stopCount(c) < 2 || !stage.isConnected) return;
    import('./line.js').then(m => {
      const entries = L.lineOrder(c).filter(e => e.depth < 3).slice(0, 6);
      const still = RM || quiet;
      const sc = m.staircase(c, entries, { all: still, cls: 'tk', narrow: true, caption: still ? 'Each lane: one stop against its own normal, on one shared scale.' : 'Replaying the line: each lane is one stop against its own normal.' });
      sc.fig.setAttribute('role', 'img'); sc.fig.setAttribute('aria-label', `${hero.title}: ${L.plural(L.stopCount(c), 'stop')} drawn as a staircase, each against its own normal.`);
      sc.fig.addEventListener('click', () => { sc.stopLoop && sc.stopLoop(); location.href = L.lineUrl(hero.slug); });
      stage.replaceChildren(sc.fig); stage.classList.add('tall');
      if (!still) requestAnimationFrame(() => sc.loop(6000));
    }).catch(() => {});
  });
  return tk;
}
// The archive ticket under the cold hero: the best reconstructed line (most Measured stops) rendered like a headline ticket,
// with its first Measured stop as the hook when its cascade is published, or its domains reached when it is not.
async function archiveTicket(S0, archive) {
  const pool = (archive || []).filter(x => x.reconstructed && x.measured > 0).sort((a, b) => (b.measured - a.measured) || (a.sensitive ? 1 : 0) - (b.sensitive ? 1 : 0));
  const a = pool[0]; if (!a) return null;
  const c = await D.cascade(a.event_id);
  const first = c ? (c.nodes || []).filter(n => n.tier === 'measured' && n.onset).sort((x, y) => String(x.onset).localeCompare(String(y.onset)))[0] : null;
  const who = first ? (first.domain === 'reading' && !/readers?$/i.test(first.label) ? `${first.label} readers` : first.label) : '';
  const headline = first ? `${first.lag_days > 0 ? `${L.plural(Math.round(first.lag_days), 'day')} later` : 'The same day'} it showed up in ${who}.`
    : `Reached ${(a.domains || []).map(L.domWord).join(' and ') || 'other parts of life'}: ${L.plural(a.measured, 'Measured stop')}.`;
  const hero = { source: 'archive', reconstructed: true, event_id: a.event_id, version: a.version, slug: a.slug, title: a.label, sensitive: a.sensitive, headline,
    stop: first ? { hop_id: first.hop_id, label: first.label, domain: first.domain, rho: first.rho, unit: first.unit, lag_days: first.lag_days, onset: first.onset } : null };
  const tk = heroTicket({ ...S0, hero, shocks: [] }, archive);
  tk.classList.add('arch'); tk.querySelector('h1')?.replaceWith(h('h2', { class: 'tk-title', id: 'arch-t' }, a.label)); tk.setAttribute('aria-labelledby', 'arch-t');
  return tk;
}
// A board row's destination column, in order of what the line has: the farthest Measured domain; else its Likely domain
// (never labelled "watching"); else "went nowhere"; else the live countdown to its next look (signature A: the board as a
// split-flap clock, ticking every minute; "today" in marigold once the look is due; static under reduced motion).
const tickers = [];
function depRow(s, fresh) {
  const st = s.stops || {};
  const due = s.next_due && s.next_due >= today() ? s.next_due : null;
  const when = due ? `${L.lookWord(due, s.window_close).toLowerCase()} ${L.fmtDay(due)}` : `since ${L.fmtDay(s.onset)}`;
  let dest, said;
  if (s.farthest_measured_domain) { dest = h('span', { class: 'dest' }, h('span', null, em(L.domIcon(s.farthest_measured_domain)), ' ', L.domWord(s.farthest_measured_domain)), h('small', null, when)); said = `farthest ${L.domWord(s.farthest_measured_domain)}, Measured`; }
  else if (st.likely > 0 && (s.domains_reached || []).length) { const d = s.domains_reached[0]; dest = h('span', { class: 'dest' }, h('span', null, tt_('likely'), ' ', em(L.domIcon(d)), ' ', L.domWord(d)), h('small', null, when)); said = `Likely in ${L.domWord(d)}`; }
  else if (s.status === 'nowhere') { dest = h('span', { class: 'dest wat' }, 'went nowhere', h('small', null, when)); said = 'went nowhere'; }
  else if (due) {
    const cd = flaps(untilLook(due), 'mute' + (untilLook(due) === 'today' ? ' hot' : ''), false);
    dest = h('span', { class: 'dest clock' }, cd, h('small', null, `${untilLook(due) === 'today' ? L.lookWord(due, s.window_close).toLowerCase() : 'to the next look'}`));
    tickers.push(() => { const t = untilLook(due); setFlaps(cd, t); cd.classList.toggle('hot', t === 'today'); });
    said = `next look ${L.fmtDate(due)}`;
  } else { dest = h('span', { class: 'dest wat' }, 'watching', h('small', null, when)); said = 'watching'; }
  const label = `${s.label}${s.reconstructed ? ', reconstructed' : ''}: ${st.measured || 0} Measured, ${st.likely || 0} Likely, ${st.watching || 0} Watching, ${st.flat || 0} stayed flat; ${said}${due ? `; next look ${L.fmtDate(due)}` : ''}${fresh ? '; new since your last visit' : ''}`;
  return h('a', { class: 'dep' + (fresh ? ' new' : ''), href: L.lineUrl(s.slug), 'aria-label': label },
    h('span', { class: 'ic', 'aria-hidden': 'true' }, em(s.emoji || '▫️')),
    h('span', { 'aria-hidden': 'true' }, h('span', { class: 'nm' }, s.label), h('span', { class: 'sub' }, strip(st, 7, true, s.watching_domains), fresh ? [sep(), h('span', { class: 'hl' }, 'new')] : null)),
    dest, icon('chev', 'chev'));
}
function board(S0, fresh) {
  const rows = (S0?.shocks || []).slice().sort((a, b) => (b.stops?.measured || 0) - (a.stops?.measured || 0) || (b.stops?.likely || 0) - (a.stops?.likely || 0) || String(b.onset).localeCompare(String(a.onset)));
  const pub = S0?.published_at;
  const el = h('section', { class: 'panel board grain', id: 'departures', 'aria-labelledby': 'dep-t' },
    h('div', { class: 'bd-head' }, h('h2', { id: 'dep-t', class: 'fw', 'aria-label': 'Departures' }, [...'DEPARTURES'].map(ch => h('b', { 'aria-hidden': 'true' }, ch))),
      h('p', { class: 'bd-time' }, h('b', null, pub ? L.fmtTime(pub) : '--:--'), S0?.day ? L.fmtDate(S0.day) : '')),
    rows.length ? rows.map(s => depRow(s, fresh.has(s.event_id))) : h('p', { class: 'dep' }, h('span'), h('span', { class: 'sub' }, 'No lines published today yet.')));
  const ctl = S0?.control;
  if (ctl) el.append(h('div', { class: 'dep ctl', role: 'group', 'aria-label': 'The control ripple' },
    h('span', { class: 'ic', 'aria-hidden': 'true' }, em('📄')),
    h('span', null, h('span', { class: 'nm' }, L.plural(ctl.n_decoys || 1, 'page') + " that weren't trending"), h('span', { class: 'sub' }, strip(ctl.stops || {}, 6, true), h('span', { style: 'white-space:nowrap' }, sep(), 'same tests'))),
    h('span', { class: 'dest wat' }, 'the control'), h('span')));
  const dl = L.dayLine(S0?.line), ll = S0?.listed_lines_sum;
  // nothing Measured on the board yet: say so, and name the next look (the board is a clock, not a graveyard)
  const nM = rows.reduce((a, r) => a + (r.stops?.measured || 0), 0);
  const nextRow = rows.filter(r => r.next_due && r.next_due >= today()).sort((a, b) => String(a.next_due).localeCompare(String(b.next_due)))[0];
  const waiting = !nM && rows.length ? h('b', { class: 'wait' }, `Nothing has passed yet.${nextRow ? ` Next look: ${nextRow.label}, ${L.fmtDate(nextRow.next_due)}.` : ''}`) : null;
  el.append(legend(), h('p', { class: 'bd-foot' }, waiting ? [waiting, h('br')] : null,
    dl ? [h('b', null, `Tested ${L.fmtInt(dl.tested)} paths today`), sep(), `${L.fmtInt(dl.moved)} moved`, sep(), `${L.fmtInt(dl.measured ?? 0)} Measured`, L.flukeClause(dl.expected, dl.measured) ? [sep(), L.flukeClause(dl.expected, dl.measured)] : null]
      : [h('b', null, "Today's tests are not in yet.")],
    ll && ll.lines ? [h('br'), `On the ${L.plural(ll.lines, 'listed line')}, over all their days: ${L.fmtInt(ll.tested)} paths tested, ${L.fmtInt(ll.moved)} moved, ${L.fmtInt(ll.measured)} Measured.`] : null));
  return el;
}
function sinceSnap(S0) {
  // localStorage ko.seen_at: {t, s:{event_id:[measured, likely, watching, flat]}}; lemon marks what changed since
  let prev = null; try { prev = JSON.parse(ls.get('ko.seen_at') || 'null'); } catch (e) { prev = null; }
  const now = {}, rows = [], fresh = new Set();
  for (const s of S0?.shocks || []) {
    const st = s.stops || {}, cur = [st.measured || 0, st.likely || 0, st.watching || 0, st.flat || 0];
    now[s.event_id] = cur;
    if (prev && prev.s) {
      const p = prev.s[s.event_id];
      if (!p) { rows.push({ s, txt: 'new line' }); fresh.add(s.event_id); continue; }
      const lit = cur[0] + cur[1] - p[0] - p[1], flat = cur[3] - p[3];
      if (lit || flat) { rows.push({ s, txt: [lit ? `${lit > 0 ? '+' : ''}${L.plural(lit, 'stop')}` : '', flat > 0 ? `${flat} stayed flat` : ''].filter(Boolean).join(', ') }); fresh.add(s.event_id); }
    }
  }
  if (S0?.shocks?.length) ls.set('ko.seen_at', JSON.stringify({ t: Date.now(), s: now }));
  return { prev, rows, fresh };
}
function sinceBlock(sn) {
  if (!sn.prev || !sn.rows.length) return null;
  return h('section', { class: 'since', 'aria-labelledby': 'since-t' }, h('h2', { id: 'since-t' }, `Since you were here (${L.fmtDate(L.isoDay(sn.prev.t)).slice(0, 3)})`),
    h('ul', null, sn.rows.slice(0, 6).map(r => h('li', null, h('a', { href: L.lineUrl(r.s.slug) }, em(r.s.emoji), h('b', null, r.s.label), h('span', { class: 'hl' }, 'new'), h('span', { class: 'muted' }, r.txt))))));
}
function domChips(S0) {
  const reached = new Set((S0?.shocks || []).flatMap(s => s.domains_reached || []));
  const order = [...L.DOMAINS].sort((a, b) => (reached.has(b) ? 1 : 0) - (reached.has(a) ? 1 : 0));
  return h('section', { class: 'sec', 'aria-labelledby': 'dom-t' }, h('h2', { class: 'h2', id: 'dom-t' }, 'Where lines landed lately'),
    h('p', { class: 'lede', style: 'margin:-4px 0 10px' }, 'Read the map backwards: what has been moving each part of life.'),
    h('div', { class: 'chips' }, order.map(k => h('a', { class: 'chip' + (reached.has(k) ? '' : ' dim'), href: `/ripples/lands/${k}/` }, em(L.DOM[k].i), L.DOM[k].w))),
    h('button', { class: 'row', id: 'a2hs', hidden: true, style: 'margin-top:14px;width:100%' }, h('span', { class: 'ic', 'aria-hidden': 'true' }, em('📲')), h('span', null, 'Add the Ripple Map to your home screen'), icon('chev', 'chev')));
}
async function home() {
  ls.set('ko.visits', String(visits() + 1));
  const S0 = INLINE && INLINE.shocks ? INLINE : await D.shocks();
  const main = $('#main');
  if (!S0) { put(main, h('div', { class: 'empty' }, 'The Ripple Map could not load. Please try again in a minute.')); return; }
  const sn = sinceSnap(S0);
  const ar = !S0.hero || S0.hero.reconstructed ? await D.archive() : null;
  // cold start: the reconstructed archive line is the second ticket, so the fold has a real staircase (EXPERIENCE §2);
  // it is awaited so the page paints once, without a shift
  const arch = !S0.hero && ar ? await archiveTicket(S0, ar).catch(() => null) : null;
  put(main, h('div', { class: 'home' }, h('div', null, heroTicket(S0, ar), arch, sinceBlock(sn)), h('div', null, board(S0, sn.fresh), domChips(S0))));
  // the board's countdown flaps tick once a minute (only the changed digit folds); paused while the tab is hidden
  if (tickers.length) { const tick = () => { if (!document.hidden) tickers.forEach(f => f()); }; setInterval(tick, 60000); document.addEventListener('visibilitychange', tick); }
  // the board clacks over once: each flap cycles a few letters and lands (not under reduced motion)
  if (!RM) main.querySelectorAll('.fw b').forEach((b, i) => {
    const fin = b.textContent, AZ = 'ABCDEFGHIJKLMNOPRSTUVWXYZ'; let n = 3 + (i % 4);
    const t = setInterval(() => { if (n-- <= 0) { b.textContent = fin; clearInterval(t); return; } b.textContent = AZ[(Math.random() * AZ.length) | 0]; b.animate([{ transform: 'rotateX(0)' }, { transform: 'rotateX(-70deg)' }, { transform: 'rotateX(0)' }], { duration: 70 }); }, 60 + i * 6);
  });
  if (visits() >= 2 && getBip()) $('#a2hs') && ($('#a2hs').hidden = false);
}
// ---------- boot ----------
// Deep-link fallback: the site's /404.html sends a line/stop/lands/week URL that has no static stub yet to the /line/ shell
// as ?rm_path=…; put the real address back before routing (same origin, /ripples/ paths only)
function restorePath() {
  let q = null; try { q = new URLSearchParams(location.search).get('rm_path'); } catch (e) { q = null; }
  if (!q || !/^\/ripples\/(line|lands|week)\/[^\s]*$/.test(q) || q.startsWith('//')) return;
  try { const u = new URL(q, location.origin); if (u.origin === location.origin) history.replaceState(history.state, '', u.pathname + u.search + u.hash); } catch (e) { /* keep the shell's own URL */ }
}
async function boot() {
  restorePath();
  chrome();
  const r = L.parseRoute(location.pathname, document.body.dataset);
  try {
    if (r.route === 'home') await home();
    else if (r.route === 'line' || r.route === 'stop') await (await import('./line.js')).linePage(r);
    else if (r.route === 'lines') await (await import('./lists.js')).mapPage('Every line');
    else if (r.route === 'map') await (await import('./lists.js')).mapPage();
    else if (r.route === 'archive') await (await import('./lists.js')).archivePage();
    else if (r.route === 'lands') await (await import('./lists.js')).landsPage(r);
    else if (r.route === 'week') await (await import('./line.js')).weekPage(r);
    else if (r.route === 'methods') await (await import('./lists.js')).methodsPage();
  } catch (e) {
    console.error(e);
    put($('#main'), h('p', { class: 'empty' }, 'Something went wrong loading this page. Please reload.'));
  }
  const a = $('#a2hs'); if (a && visits() >= 2 && getBip()) a.hidden = false;
}
boot();
