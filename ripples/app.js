// Knock⌃On Ripple Map v6 (WS-D). One module for every /ripples/ page; the page's <body data-route> (set by the shells and by
// ripples/tools/gen-stubs.mjs) picks the renderer. Data: the stub's inlined #rm-data first, then Storage v2/, then the RPC.
import * as C from './config.js';
import * as L from './lib.js';
import { $, add, h, S, em, sep, joinSep, put, icon, IC, RM, desk, ls, today, INLINE, D, rpc, load, event, toast, copy, share, prefetchImg, shareImage, landing, flaps, countUp, tt_, pips, stamp, dtile, strip, legend, spark, theme, help, wander, chrome, visits, seedChart, getBip } from './ui.js';

// ---------- HOME ----------
function heroTicket(S0, archive) {
  const hero = S0?.hero;
  const tk = h('section', { class: 'ticket hero grain', 'aria-labelledby': 'hero-t' });
  if (!hero) {
    // Cold start with nothing Measured anywhere: say so, and point at what is being watched (never pad a headline)
    const rows = (S0?.shocks || []);
    const due = rows.map(r => r.next_due).filter(d => d && d >= today()).sort()[0];
    tk.classList.add('empty');
    add(tk, h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, 'Ripple of the week')),
      h('div', { class: 'tk-body' },
        h('h1', { class: 'tk-title', id: 'hero-t' }, 'Nothing Measured yet'),
        h('p', { class: 'tk-hook' }, rows.length ? `${L.plural(rows.length, 'line')} on the board, every stop still Watching or flat.` : 'No lines are published yet.'),
        h('p', { class: 'tk-sub' }, 'A stop lands here only when it passes every test: its own normal, timing, two sources, and the fluke controls.'),
        h('div', { class: 'tk-path', 'aria-hidden': 'true' }, h('span', { class: 'dt shock' }, em(rows[0]?.emoji || '🌀')), h('span', { class: 'trk' }), h('span', { class: 'dt q' }, '?'), h('span', { class: 'lbl' }, due ? `Next result due ${L.fmtDay(due)}` : 'Waiting for the first result'))),
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
  const path = h('div', { class: 'tk-path', id: 'hero-path' }, h('span', { class: 'dt shock', 'aria-hidden': 'true' }, em(s.emoji || '🌀')), h('span', { class: 'trk', 'aria-hidden': 'true' }),
    h('span', { class: 'dt measured', 'aria-hidden': 'true' }, em(L.domIcon(st.domain))), h('span', { class: 'lbl' }, L.domWord(st.domain), h('br'), h('span', { style: 'font-weight:500' }, 'Measured')));
  const stops = s.stops ? (s.stops.measured || 0) + (s.stops.likely || 0) : null;
  const meta = joinSep([stops != null ? L.plural(stops, 'stop') : null, s.domains_reached ? L.plural(s.domains_reached.length, 'domain') : null, L.STATUS[s.status] || null, hero.reconstructed ? 'reconstructed' : null]);
  add(tk,
    h('p', { class: 'tk-top' }, h('span', { class: 'tag' }, hero.reconstructed ? 'From the archive, reconstructed' : 'Ripple of the week'), hero.version ? h('span', { class: 'ver' }, 'v' + hero.version) : null),
    h('div', { class: 'tk-body' },
      h('div', { class: 'tk-row' }, h('span', { class: 'tk-emo', 'aria-hidden': 'true' }, em(s.emoji || '🌀')), h('h1', { class: 'tk-title', id: 'hero-t' }, hero.title)),
      h('p', { class: 'tk-hook' }, hero.headline),
      s.magnitude_x ? h('p', { class: 'tk-sub' }, joinSep([`Peaked at ${L.num(s.magnitude_x)}× its normal attention`, L.biggest(s) || null])) : null,
      hasChart ? svg : null, path),
    h('div', { class: 'tk-perf', 'aria-hidden': 'true' }, h('span', { class: 'notch l' }), h('span', { class: 'notch r' })),
    h('div', { class: 'tk-foot' }, meta.length ? h('p', { class: 'tk-meta' }, meta) : null, h('a', { class: 'btn', href: L.lineUrl(hero.slug) + (ls.get('ko.hide_middle') === '1' ? '?hide=1' : '') }, 'Trace the line')));
  // "?" tiles hide only the stops between the shock and that Measured stop; they flip once through domain icons (not in quiet mode)
  D.cascade(hero.event_id).then(c => {
    if (!c) return;
    const mid = L.ancestors(c, st.hop_id);
    if (!mid.length) return;
    const trk = path.children[1];
    mid.forEach(() => {
      const q = h('span', { class: 'dt q', 'aria-hidden': 'true' }, '?');
      trk.after(q, h('span', { class: 'trk', 'aria-hidden': 'true' }));
      if (!RM && !quiet) { const ic = L.DOMAINS.map(k => L.DOM[k].i); let i = 0; const t = setInterval(() => { q.textContent = i < 6 ? ic[i++ % ic.length] : '?'; if (i >= 6) { clearInterval(t); q.textContent = '?'; } }, 110); }
    });
  });
  return tk;
}
function depRow(s, fresh) {
  const st = s.stops || {};
  const where = s.farthest_measured_domain ? [em(L.domIcon(s.farthest_measured_domain)), L.domWord(s.farthest_measured_domain)] : s.status === 'nowhere' ? ['went nowhere'] : ['watching'];
  const when = s.next_due && s.next_due >= today() ? `due ${L.fmtDay(s.next_due)}` : `since ${L.fmtDay(s.onset)}`;
  const dest = s.farthest_measured_domain ? h('span', { class: 'dest' }, h('span', null, em(L.domIcon(s.farthest_measured_domain)), ' ', L.domWord(s.farthest_measured_domain)), h('small', null, when)) : h('span', { class: 'dest wat' }, s.status === 'nowhere' ? 'went nowhere' : 'watching', h('small', null, when));
  void where;
  return h('a', { class: 'dep' + (fresh ? ' new' : ''), href: L.lineUrl(s.slug) },
    h('span', { class: 'ic', 'aria-hidden': 'true' }, em(s.emoji || '▫️')),
    h('span', null, h('span', { class: 'nm' }, s.label, s.reconstructed ? h('span', { class: 'sr' }, ' (reconstructed)') : null), h('span', { class: 'sub' }, strip(st, 7, true), fresh ? [sep(), h('span', { class: 'hl' }, 'new')] : null)),
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
    h('span', null, h('span', { class: 'nm' }, L.plural(ctl.n_decoys || 1, 'page') + " that weren't trending"), h('span', { class: 'sub' }, strip(ctl.stops || {}, 6, true), sep(), 'same tests')),
    h('span', { class: 'dest wat' }, 'the control'), h('span')));
  const dl = L.dayLine(S0?.line), ll = S0?.listed_lines_sum;
  el.append(legend(), h('p', { class: 'bd-foot' },
    dl ? [h('b', null, `Tested ${L.fmtInt(dl.tested)} paths today`), sep(), `${L.fmtInt(dl.moved)} moved`, sep(), `about ${L.expected(dl.expected)} expected by chance`]
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
    h('div', { class: 'chips' }, order.map(k => h('a', { class: 'chip' + (reached.has(k) ? '' : ' dim'), href: `/ripples/lands/${k}/` }, em(L.DOM[k].i), L.DOM[k].w))));
}
async function home() {
  ls.set('ko.visits', String(visits() + 1));
  const S0 = INLINE && INLINE.shocks ? INLINE : await D.shocks();
  const main = $('#main');
  if (!S0) { put(main, h('div', { class: 'empty' }, 'The Ripple Map could not load. Please try again in a minute.')); return; }
  const sn = sinceSnap(S0);
  const ar = S0.hero && S0.hero.reconstructed ? await D.archive() : null;
  put(main, h('div', { class: 'home' }, h('div', null, heroTicket(S0, ar), sinceBlock(sn)), h('div', null, board(S0, sn.fresh), domChips(S0))));
  // the board clacks over once: each flap cycles a few letters and lands (not under reduced motion)
  if (!RM) main.querySelectorAll('.fw b').forEach((b, i) => {
    const fin = b.textContent, AZ = 'ABCDEFGHIJKLMNOPRSTUVWXYZ'; let n = 3 + (i % 4);
    const t = setInterval(() => { if (n-- <= 0) { b.textContent = fin; clearInterval(t); return; } b.textContent = AZ[(Math.random() * AZ.length) | 0]; b.animate([{ transform: 'rotateX(0)' }, { transform: 'rotateX(-70deg)' }, { transform: 'rotateX(0)' }], { duration: 70 }); }, 60 + i * 6);
  });
  if (visits() >= 2 && getBip()) $('#a2hs') && ($('#a2hs').hidden = false);
}
// ---------- boot ----------
async function boot() {
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
