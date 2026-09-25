// Knock-On v5 page. No framework. All data-sourced text goes in via textContent (h() below never parses HTML).
import * as C from '/ripples/config.js';
import * as L from '/ripples/lib.js';

const $ = id => document.getElementById(id);
const q = new URLSearchParams(location.search);
const FIX = q.get('fixture') === '1';
const RM = matchMedia('(prefers-reduced-motion: reduce)').matches;
const NS = 'http://www.w3.org/2000/svg';
function h(tag, a, ...kids) {
  const e = document.createElement(tag);
  if (tag === 'button') e.type = 'button';
  for (const k in a || {}) {
    const v = a[k];
    if (v == null || v === false) continue;
    if (k === 'class') e.className = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const c of kids.flat(3)) if (c != null && c !== false && c !== '') e.append(c.nodeType ? c : String(c));
  return e;
}
const hp = (c, ...k) => h('p', { class: c }, ...k), hs = (c, ...k) => h('span', { class: c }, ...k);
function sv(tag, a, ...kids) {
  const e = document.createElementNS(NS, tag);
  for (const k in a || {}) if (a[k] != null) e.setAttribute(k, a[k]);
  for (const c of kids.flat(3)) if (c != null) e.append(c.nodeType ? c : String(c));
  return e;
}
const put = (el, ...k) => el.replaceChildren(...k.flat(3).filter(c => c != null && c !== false && c !== ''));
const ls = {
  get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} },
};
const fmtM = L.fmtMultiple, fmtD = L.fmtDate;
const scr = (el, block) => el.scrollIntoView({ behavior: RM ? 'auto' : 'smooth', block }), cdb = t => h('b', { 'data-cd': t }, L.fmtCountdown(t - Date.now()));
const pct = p => (p == null ? '–' : Math.round(p * 100) + '%');
const safeUrl = (u, wiki) => (typeof u === 'string' && (wiki ? /^https:\/\/[a-z-]+\.wikipedia\.org\//.test(u) : /^https?:\/\//.test(u)) ? u : null);
function toast(msg) { const t = $('toast'); t.textContent = msg; t.classList.add('on'); clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.remove('on'), 2400); }
function banner(text, cls, link) {
  $('banners').append(h('p', { class: 'ban ' + (cls || '') }, text, link ? [' ', h('a', { href: link[1] }, link[0])] : null));
}
function countUp(el, to, fmt) {
  if (RM || !(to > 0)) { el.textContent = fmt(to); return; }
  const t0 = performance.now(), from = Math.min(1, to);
  const step = t => { const k = Math.min(1, (t - t0) / 800), e = 1 - Math.pow(1 - k, 3); el.textContent = fmt(from + (to - from) * e); if (k < 1) requestAnimationFrame(step); };
  requestAnimationFrame(step);
}

// ---------- data ----------
async function getJSON(url) {
  try { const r = await fetch(url); return r.ok ? await r.json() : undefined; } catch (e) { return undefined; }
}
async function rpc(fn, args = {}, post) {
  if (post) {
    try {
      const r = await fetch(`${C.SB_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: C.SB_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
      const j = await r.json().catch(() => null);
      return r.ok ? { ok: true, data: j } : { ok: false, error: (j && j.message) || 'error' };
    } catch (e) { return { ok: false, error: 'network' }; }
  }
  const u = new URLSearchParams({ apikey: C.SB_KEY });
  for (const k in args) if (args[k] != null) u.set(k, args[k]);
  return getJSON(`${C.SB_URL}/rest/v1/rpc/${fn}?${u}`);
}
const fx = f => getJSON(`/ripples/contract/fixtures/${f}`);
// Storage mirror first, RPC fallback; the shapes are identical.
async function load(path, fn, args) {
  const a = await getJSON(`${C.STORAGE}/${path}`);
  return a != null ? a : rpc(fn, args);
}
async function getLatest() {
  let l = await getJSON(`${C.STORAGE}/latest.json`);
  if (!l || (l.next_at && Date.parse(l.next_at) <= Date.now())) l = (await rpc('ripples_latest')) || l;
  return l || null;
}
const getPuzzle = n => (FIX ? fx('puzzle-0.json') : load(`puzzle/${n}.json`, 'ripples_puzzle', { p_n: n }));
const getReveal = n => (FIX ? fx('reveal-0.json') : load(`reveal/${n}.json`, 'ripples_reveal', { p_n: n }));
const getCallit = n => (FIX ? fx('callit-0.json') : load(`callit/${n}.json`, 'ripples_callit', { p_n: n }));
function clientId() {
  let c = ls.get('ko.client');
  if (typeof c !== 'string' || !/^[A-Za-z0-9_-]{16,64}$/.test(c)) {
    const b = crypto.getRandomValues(new Uint8Array(16));
    c = btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    ls.set('ko.client', c);
  }
  return c;
}

// ---------- state ----------
const S = { P: null, n: null, ans: [], picks: [], codes: [], k: 0, lock: false, guess: null, st: null, you: null, rv: null, rvP: null, latest: null, hist: ls.get('ko.history', {}), calls: ls.get('ko.calls', {}), streak: 0 };
const live = () => !FIX && S.P && S.P.kind === 'live';
const R = () => S.P.rounds.length;
const chain = () => L.chainFromPuzzle(S.P, S.ans);
function prefetch() {
  if (S.rvP) return;
  S.rvP = getReveal(S.n).then(r => (S.rv = r || null));
  S.stP = (FIX ? fx('stats-0.json') : S.P.kind === 'practice' ? Promise.resolve(null) : rpc('ripples_stats', { p_n: S.n })).then(s => (S.st = s || null));
}
function computeStreak() {
  const upto = (S.latest && S.latest.n) || (live() ? S.n : 0);
  S.streak = upto > 0 ? L.streakFrom(Object.keys(S.hist).map(Number).filter(n => n > 0), upto) : 0;
  const old = ls.get('ko.streak', {});
  if (!FIX) ls.set('ko.streak', { c: S.streak, n: upto, best: Math.max(old.best || 0, S.streak) });
  const p = $('streak');
  p.hidden = S.streak < 1;
  p.textContent = '🔥 ' + S.streak;
  p.title = `Streak: ${S.streak} puzzle${S.streak === 1 ? '' : 's'} in a row`;
}

// ---------- boot ----------
async function boot() {
  ui();
  const dn = document.body.dataset.n, ds = document.body.dataset.s, pn = q.get('p');
  let P = null;
  if (FIX) {
    P = await getPuzzle(0);
    banner('TEST fixture: made-up data for checking the page. Nothing here is real, and nothing you do is sent.', 'info');
  } else if (pn != null && /^-\d{1,4}$/.test(pn)) {
    [P, S.latest] = await Promise.all([getPuzzle(+pn), getLatest()]);
  } else if (dn) {
    [P, S.latest] = await Promise.all([getPuzzle(+dn), getLatest()]);
  } else {
    S.latest = await getLatest();
    if (S.latest && S.latest.n == null) return prelaunch(S.latest);
    P = S.latest && S.latest.puzzle;
    if (P && S.latest.status === 'delayed') banner("Today's puzzle is delayed. Here's yesterday's.");
  }
  if (!P) return missing(dn || pn);
  S.P = P; S.n = P.n;
  $('no').textContent = P.kind === 'practice' ? 'practice' : '#' + P.n;
  $('date').textContent = fmtD(P.date);
  document.title = P.kind === 'practice' ? 'Knock-On practice' : `Knock-On #${P.n}`;
  if (P.from_date) banner(`From ${fmtD(P.from_date, true)}: a reserve puzzle, shown with its real date.`);
  if (P.kind === 'practice') banner(`Practice puzzle, reconstructed from ${fmtD(P.data_date, true)} data. It doesn't count toward your streak.`, 'info');
  const ln = S.latest && S.latest.n;
  if (dn && ln && P.kind === 'live' && P.n !== ln) banner(`This is Knock-On #${P.n} from ${fmtD(P.date)}.`, 'info', [`Play today's #${ln} →`, '/ripples/']);
  S.ans = await Promise.all(P.rounds.map(r => L.findAnswer(P.n, r)));
  const done = live() && S.hist[P.n];
  if (Object.keys(S.hist).length) $('hook').hidden = true;
  else if (standalone()) banner('New home-screen app? Bring your streak over: tap ? and paste your backup code under Restore.', 'info');
  if (ds != null && !done && /^[0-4]$/.test(ds)) banner(`A friend found ${Math.min(+ds, R())} of ${R()} first try. Your turn.`, 'info');
  computeStreak();
  renderSeed();
  if (done) restore(done); else { renderRound(0); callitTeaser(); }
  renderJoin();
  board();
  practice();
  health();
  tick();
}

function missing(n) {
  $('seed').removeAttribute('aria-busy');
  put($('seed'), hp('eb', 'Not here yet'),
    h('h2', null, n ? `Knock-On ${n < 0 ? 'practice ' + n : '#' + n} isn't available` : "Couldn't load today's puzzle"),
    hp('sub', n ? 'It may not be live yet. Puzzles go live at 07:30 UTC.' : 'Check your connection and try again.'),
    h('a', { class: 'btn', href: '/ripples/' }, "Go to today's puzzle"));
  renderJoin();
}

function prelaunch(l) {
  const next = Math.max(Date.parse(l.next_at) || L.nextRollover(), Date.parse(L.addDays(C.EPOCH, 1) + 'T07:30:00Z')), d = L.isoDay(next), n1 = Math.max(1, L.puzzleNoForDate(d, C.EPOCH));
  $('no').textContent = '#' + n1;
  $('date').textContent = fmtD(d);
  const cd = h('p', { class: 'count', 'data-cd': next }, L.fmtCountdown(next - Date.now()));
  $('seed').removeAttribute('aria-busy');
  put($('seed'), hp('eb', 'Starts soon'),
    h('h2', null, `Knock-On #${n1} goes live ${fmtD(d, true)}, 07:30 UTC`), cd,
    h('ol', { class: 'steps' },
      h('li', null, "Every morning: one real trend, measured on Wikipedia's daily readers."),
      h('li', null, 'Each round, pick which of four linked pages spiked after it. The other three are real pages that stayed flat.'),
      h('li', null, 'Share your grid, call what spikes next, come back tomorrow.')));
  S.prelaunch = next;
  renderJoin(next);
  practice();
  health();
  tick();
}

// ---------- seed ----------
function crossRow(items) {
  if (!items || !items.length) return null;
  return [hp('xlab', 'Other channels · corroboration only, not part of the measurement'),
    h('ul', { class: 'bdgs' }, items.map(x => h('li', { class: 'bdg x' }, L.crossText(x))))];
}
const BADGE = { gtrends: 'Google Trends', bsky: 'Trending on Bluesky', featured: 'Wikipedia most-read', wiki_top: 'Wikipedia most-read', top_country: 'Top in' };
function spark(vals, opt) {
  const W = 300, H = opt.h || 64, top = opt.top || Math.max(...vals, 1);
  const d = L.sparkPath(vals, W, H, top);
  const svg = sv('svg', { class: 'spk ' + (opt.cls || ''), viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'none', 'aria-hidden': 'true' });
  if (opt.win) svg.append(sv('rect', { class: 'base', x: (opt.win[0] * W) / (vals.length - 1), y: 0, width: ((opt.win[1] - opt.win[0]) * W) / (vals.length - 1), height: H }));
  if (opt.med) { const y = 2 + (H - 4) * (1 - Math.min(opt.med, top) / top); svg.append(sv('line', { class: 'med', x1: 0, x2: W, y1: y, y2: y, 'vector-effect': 'non-scaling-stroke' })); }
  if (opt.area) svg.append(sv('path', { class: 'ar', d: `${d}L${W},${H}L0,${H}Z` }));
  svg.append(sv('path', { class: 'ln ' + (opt.line || ''), d, 'vector-effect': 'non-scaling-stroke' }));
  return svg;
}
function renderSeed() {
  const P = S.P, sd = P.seed, bl = sd.baseline || {}, el = $('seed');
  const xs = new Set((sd.cross || []).map(x => x.source));
  const badges = (sd.badges || []).filter(b => !xs.has(b.split(':')[0])).map(b => { const [k, g] = b.split(':'); return h('li', { class: 'bdg' }, `${BADGE[k] || k}${g ? ' ' + g : ''}`); });
  const why = (sd.why || []).filter(w => safeUrl(w.url));
  el.removeAttribute('aria-busy');
  put(el, 
    hp('eb', `${P.date === L.currentPuzzleDate() ? "Today's trend" : 'Trend of ' + fmtD(P.date)} · ${L.CAT_NAMES[sd.category] || ''}`),
    h('h2', null, h('span', { class: 'em', 'aria-hidden': 'true' }, sd.emoji), sd.title),
    P.headline && P.headline.text ? hp('headline', P.headline.text, P.headline.source === 'ai' ? [' ', hs('tag', 'AI-written')] : null) : null,
    hp('hl', L.fmtBiggestIn(sd)),
    hp('sub', `${fmtM(sd.multiple)} its normal Wikipedia readers${sd.langs > 1 ? ` · ${sd.langs} languages` : ''}`),
    sd.spark && sd.spark.length ? spark(sd.spark, { win: bl.from && L.sparkWindow(sd.spark.length, P.data_date, bl.from, bl.to), med: bl.median, area: 1, line: 'draw' }) : null,
    hp('cap', `Daily Wikipedia readers, 90 days to ${fmtD(P.data_date)}. Shaded: baseline ${fmtD(bl.from)} – ${fmtD(bl.to)}, median ${L.fmtInt(bl.median)}/day (dashed).`),
    why.length || badges.length || (sd.cross || []).length ? h('details', null, h('summary', null, "Why it's trending", (sd.cross || []).length ? ` · also on ${sd.cross.length} other channel${sd.cross.length > 1 ? 's' : ''}` : ''),
      why.length ? h('ul', { class: 'why' }, why.slice(0, 3).map(w => h('li', null, h('a', { href: w.url, target: '_blank', rel: 'noopener nofollow ugc' }, w.title), w.source ? ` · ${w.source}` : ''))) : null,
      badges.length ? h('ul', { class: 'bdgs' }, badges) : null, crossRow(sd.cross)) : null);
}

// ---------- rounds ----------
function trail(upto) {
  const c = chain(), out = [h('li', null, S.P.seed.emoji, h('b', null, S.P.seed.title))];
  for (let k = 0; k < upto; k++) {
    if (!c[k].continues) out.push(h('li', null, '·'), h('li', null, c[k].seedEmoji, h('b', null, c[k].seedTitle)));
    out.push(h('li', { 'aria-hidden': 'true' }, '→'), h('li', null, L.SQUARES[S.codes[k]], c[k].emoji, h('b', null, c[k].title)));
  }
  return h('ol', { class: 'trail', 'aria-label': 'Your trail so far' }, out);
}
function dots(k) {
  return h('div', { class: 'dots', 'aria-hidden': 'true' }, [...Array(R() + 1)].map((_, j) => h('i', { class: j < k ? 'c' + S.codes[j] : j === k ? 'on' : '' })));
}
function renderRound(k) {
  S.k = k; S.lock = false;
  const P = S.P, r = P.rounds[k], c = chain()[k];
  const say = h('p', { class: 'say', 'aria-live': 'polite' }), rv = h('div', { 'aria-live': 'polite' });
  const opts = h('div', { class: 'opts', role: 'group', 'aria-label': 'Four linked pages' },
    r.options.map(o => h('button', { class: 'opt', 'data-id': o.id, onclick: e => pick(k, o.id, e.currentTarget, say, rv) },
      h('span', { class: 'e', 'aria-hidden': 'true' }, o.emoji), h('b', null, o.title), h('small', null, o.desc))));
  const prompt = h('p', { class: 'prompt', tabindex: '-1' }, 'All four are linked from ', h('em', null, r.parent.title), '. Which one spiked after it?');
  put($('round'), h('div', { class: 'card' },
    k ? trail(k) : null, dots(k),
    hp('eb', `Round ${k + 1} of ${R()}`),
    !c.continues ? hp('fresh', '🌊 ', h('b', null, 'New ripple from today’s seeds: '), `${r.seed.emoji} ${r.seed.title}`,
      r.seed.multiple ? ` · ${fmtM(r.seed.multiple)} normal readers` : '', r.seed.biggest_in_days ? ` · biggest day in ${L.fmtInt(r.seed.biggest_in_days)} days` : '',
      '. It shows as a · break in your share.') : null,
    prompt,
    !k && !Object.keys(S.hist).length ? hp('coach', 'Pick one. You get two tries.') : null,
    opts, say, rv));
  if (k) { prompt.focus({ preventScroll: true }); scr($('round'), 'start'); }
}
function pick(k, id, btn, say, rv) {
  if (S.lock || S.k !== k) return;
  const picks = (S.picks[k] = S.picks[k] || []);
  if (picks.includes(id)) return;
  picks.push(id);
  prefetch();
  if (id === S.ans[k]) {
    btn.classList.add('yes');
    try { navigator.vibrate && navigator.vibrate(10); } catch (e) {}
    return resolve(k, picks.length === 1 ? 2 : 1, say, rv);
  }
  btn.classList.add('no'); btn.setAttribute('aria-disabled', 'true');
  if (picks.length === 1) say.textContent = 'Not this one. One more try.';
  else resolve(k, 0, say, rv);
}
async function resolve(k, code, say, rv) {
  S.lock = true; S.codes[k] = code;
  say.textContent = ['🟥 Missed. Here is the page that spiked.', '🟨 Got it on the second try.', '🟩 First try!'][code];
  await S.rvP; await S.stP;
  revealRound(k, rv);
}
function sharedTop(opts) {
  let top = 3;
  for (const o of opts) { const m = o.median || L.median(o.spark || []) || 1; for (const v of o.spark || []) top = Math.max(top, v / m); }
  return top * 1.05;
}
function ratio(o) { const m = o.median || L.median(o.spark || []) || 1; return (o.spark || []).slice(-60).map(v => v / m); }
function revealRound(k, rv) {
  const P = S.P, r = P.rounds[k], ans = S.ans[k], rr = S.rv && S.rv.rounds.find(x => x.i === r.i);
  const grid = $('round').querySelector('.opts'), picks = S.picks[k] || [];
  const srow = S.st && S.st.shown && S.st.rounds ? S.st.rounds.find(x => x.i === r.i) : null;
  if (!rr) {
    grid.querySelectorAll('.opt').forEach(b => { b.classList.add('done'); b.disabled = true; if (b.dataset.id === ans && !b.classList.contains('yes')) b.classList.add('ans'); });
    put(rv, h('div', { class: 'rvl' }, h('p', null, "Couldn't load the measurements for this round, but the answer is marked above.")), nextBtn(k));
    return;
  }
  const top = sharedTop(rr.options);
  put(grid, ...r.options.map(o => {
    const m = rr.options.find(x => x.id === o.id) || {}, isA = o.id === ans, url = safeUrl(m.url, 1);
    const cls = 'opt done' + (isA ? (picks.includes(ans) ? ' yes' : ' ans') : picks.includes(o.id) ? ' no' : '');
    return h('div', { class: cls },
      h('span', { class: 'e', 'aria-hidden': 'true' }, o.emoji), h('b', null, o.title),
      h('div', { class: 'rv' }, spark(ratio(m), { h: 38, top, med: 1, line: isA ? 'hot draw late' : 'draw' })),
      hs('rl', isA ? [h('strong', null, `${fmtM(m.multiple)} normal`), ` · ${L.fmtTiming(m.lag_days, m.timing)}`] : `also linked; views normal, ${fmtM(m.multiple)}`),
      srow && srow.split ? hs('pp', `players' picks ${srow.split[o.id] ?? 0}%`) : null,
      url ? h('a', { href: url, target: '_blank', rel: 'noopener' }, 'Wikipedia ↗') : null);
  }));
  const a = rr.options.find(x => x.id === ans) || {}, ao = r.options.find(x => x.id === ans), ev = rr.evidence || {};
  const parent = r.parent.title, timing = L.fmtTiming(a.lag_days, a.timing);
  const big = hs('big', '1.0×');
  const fl = ev.fluke_warming || ev.fluke == null ? 0 : Math.min(100, (ev.fluke / 0.2) * 100);
  const bdg = [ev.linked ? `🔗 Linked from ${parent}` : null, `📈 Spiked ${timing === 'alongside' ? 'alongside' : 'after'} ${parent}`,
    ev.badge === 'flowed' && ev.clickstream ? `👣 In ${L.fmtMonth(ev.clickstream.month)}, ${L.fmtInt(ev.clickstream.clicks)} readers clicked from ${parent} to ${ao.title}` : null,
    ev.split_ok ? '📱💻 Up on desktop and mobile' : null].filter(Boolean);
  const cap = rr.caption && rr.caption.text ? rr.caption : null;
  const beat = Math.max(0, Math.round((ev.p_time || 0) * ((ev.placebos || 0) + 1)) - 1);
  put(rv, h('div', { class: 'rvl pop' },
    h('h3', null, `${L.SQUARES[S.codes[k]]} ${ao.emoji} ${ao.title}`),
    h('div', { class: 'bigrow' }, big, h('span', null, `its normal readers · spiked ${timing} ${parent}`)),
    hp('fl', h('i', { style: `--f:${fl}%`, 'aria-hidden': 'true' }), `🎲 ${L.fmtFluke(ev)}${ev.fluke_warming ? ' (this hop also passed a stricter time-shift test)' : ''}`),
    h('ul', { class: 'bdgs' }, bdg.map(b => h('li', { class: 'bdg' }, b))),
    crossRow(ev.cross),
    srow ? hp('meas', `Players' picks: ${srow.first_try_pct}% found it first try, ${srow.found_pct}% found it at all.`) : null,
    cap ? hp('quote', cap.text, cap.source === 'ai' ? hs('tag', 'AI-written context') : cap.source === 'wikipedia' ? hs('tag', 'Wikipedia description') : null) : null,
    rr.shared_trigger_stop ? hp('stop', '⛔ The chain stops here: the next page may be reacting to the same news as the seed, so it is not counted as a knock-on.') : null,
    h('details', null, h('summary', null, 'How measured?'), h('p', { class: 'meas' },
      `Baseline: ${ao.title}'s median daily readers over 91 days ending three weeks before ${parent}'s spike, ${L.fmtInt(a.median)} a day. `,
      `Peak within 3 days: ${fmtM(a.multiple)} that baseline (robust z ${a.z != null ? a.z.toFixed(1) : '–'}). `,
      ev.placebos ? `Time-shift test: ${beat} of ${ev.placebos} earlier weeks did as well (p = ${ev.p_time}). ` : '',
      'The three decoys are real pages linked from the same parent whose readers stayed calm. ',
      h('a', { href: '/ripples/methods/' }, 'Method'))),
    k === R() - 1 && S.rv.end ? hp('stop', S.rv.end.text) : null), nextBtn(k));
  countUp(big, a.multiple, fmtM);
  scr(rv, 'nearest');
}
function nextBtn(k) {
  const last = k === R() - 1;
  return h('div', { class: 'nextrow' }, h('button', { class: 'btn wide', onclick: () => (last ? renderFinal() : renderRound(k + 1)) }, last ? 'Last question →' : 'Next round →'));
}

// ---------- final slider ----------
function finalInfo() {
  const fr = (S.P.final && S.P.final.round) || R(), c = chain()[fr - 1], rr = S.rv && S.rv.rounds.find(x => x.i === fr);
  const opt = rr && rr.options.find(o => o.id === S.ans[fr - 1]);
  return { title: c.title, emoji: c.emoji, actual: (S.rv && S.rv.final_multiple) || (opt && opt.multiple), opt, rr };
}
function renderFinal() {
  const f = finalInfo(), lo = (S.P.final && S.P.final.mag_min) || 1.5, hi = (S.P.final && S.P.final.mag_max) || 100;
  put($('round'), h('div', { class: 'card' }, trail(R()), hp('stop', (S.rv && S.rv.end && S.rv.end.text) || 'The measured trail ends here.')));
  const read = h('p', { class: 'read unset', 'aria-hidden': 'true' }, '?×');
  const go = h('button', { class: 'btn wide', disabled: true }, 'Lock it in');
  const rng = h('input', { type: 'range', min: 0, max: 1000, value: 500, 'aria-label': `Your guess, ${lo}× to ${hi}× normal`, 'aria-valuetext': 'no guess yet' });
  const wrap = h('div', { class: 'unset' }, rng);
  let g = null;
  const set = () => { g = L.roundMag(L.magFromPos(rng.value / 1000, lo, hi)); read.textContent = g + '×'; read.classList.remove('unset'); wrap.classList.remove('unset'); rng.setAttribute('aria-valuetext', g + ' times normal'); go.disabled = false; };
  rng.addEventListener('input', set);
  rng.addEventListener('pointerdown', () => setTimeout(set, 0));
  go.addEventListener('click', () => { if (g) lock(g); });
  const ticks = h('div', { class: 'ticks', 'aria-hidden': 'true', style: 'position:relative;height:14px' },
    [lo, 3, 10, 30, hi].map((v, i, a) => h('span', { style: `position:absolute;left:${(L.posFromMag(v, lo, hi) * 100).toFixed(1)}%;transform:translateX(${i ? (i === a.length - 1 ? '-100%' : '-50%') : '0'})` }, v + '×')));
  put($('final'), h('div', { class: 'card' }, dots(R()), hp('eb', 'Final guess'),
    h('p', { class: 'ask', tabindex: '-1' }, 'How many times its normal traffic did ', h('em', null, f.title), ' get?'),
    read, wrap, ticks, hp('coach', 'Tap or drag the track to guess. Within 1.5× scores 2, within 2× scores 1.'), go));
  scr($('final'), 'start');
  $('final').querySelector('.ask').focus({ preventScroll: true });
}
function shot() {
  const f = finalInfo(), a = f.actual, g = S.guess, x = L.magX(g, a), pts = L.magPoints(g, a);
  const big = hp('big', '1.0×');
  let svg = null;
  if (f.opt && f.rr) {
    const W = 300, H = 110, top = Math.max(sharedTop(f.rr.options), g * 1.15), y = v => 4 + (H - 8) * (1 - Math.min(v, top) / top);
    svg = sv('svg', { viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'none', role: 'img', 'aria-label': `Daily readers of ${f.title} against normal, with your guess of ${g}×` });
    for (const o of f.rr.options) if (o !== f.opt) svg.append(sv('path', { class: 'dc', d: L.sparkPath(ratio(o), W, H, top, 4), 'vector-effect': 'non-scaling-stroke' }));
    svg.append(sv('line', { class: 'gs', x1: 0, x2: W, y1: y(g), y2: y(g), 'vector-effect': 'non-scaling-stroke' }));
    svg.append(sv('path', { class: 'ln draw', d: L.sparkPath(ratio(f.opt), W, H, top, 4), 'vector-effect': 'non-scaling-stroke' }));
  }
  const el = h('div', { class: 'shot pop' },
    h('div', { class: 'strip' }, h('span', null, S.P.kind === 'practice' ? 'Knock-On practice' : `Knock-On #${S.n}`), hs('ashown', `#${S.n} · answer shown`)),
    hp('t', `${f.emoji} ${f.title}`), big,
    hp('vs', `You said ${fmtM(g)}. It hit ${fmtM(a)}.`),
    svg ? [svg, h('p', { class: 'xlab', style: 'color:#9FBCB8;margin-top:4px' }, `dashed: your guess · bright: ${f.title} · faint: the three calm decoys`)] : null,
    hp('pts', pts ? `+${pts} point${pts > 1 ? 's' : ''} · within ${x.toFixed(1)}×` : `No points this time: ${x.toFixed(1)}× off (within 2× scores 1)`),
    hp('foot2', `${C.SITE} · Measured attention, not proof of cause.`));
  countUp(big, a, fmtM);
  return el;
}
async function lock(g) {
  S.guess = g;
  await S.rvP;
  put($('final'), h('div', { class: 'card', 'aria-live': 'polite' }, hp('eb', 'Final guess'), shot()));
  const score = L.totalScore(S.codes, L.magPoints(g, finalInfo().actual));
  if (live()) {
    S.hist[S.n] = { grid: L.gridEmoji(S.codes), score, max: L.maxScore(R()), mag: g, picks: S.picks, s: L.firstTries(S.codes) };
    ls.set('ko.history', S.hist);
  }
  computeStreak();
  renderResult();
  renderCallit();
  setTimeout(() => scr($('result'), 'start'), RM ? 0 : 1600);
  if (FIX || S.P.kind === 'practice') return;
  const res = await rpc('ripples_submit_play', { p_client: clientId(), p_n: S.n, p_picks: S.picks, p_mag: g }, true);
  if (res.ok && res.data) { S.st = res.data; S.you = res.data.you; if (live() && S.you) { S.hist[S.n].pct = S.you.percentile; ls.set('ko.history', S.hist); } }
  else S.err = res.error;
  renderResult();
}
async function restore(hh) {
  S.picks = hh.picks || [];
  S.codes = S.picks.map((p, k) => L.scoreRound(p, S.ans[k]));
  S.guess = hh.mag;
  if (S.picks.length !== R() || !S.guess) { delete S.hist[S.n]; return renderRound(0); }
  prefetch(); await S.rvP;
  if (hh.pct != null) S.you = { percentile: hh.pct };
  put($('round'), h('div', { class: 'card' }, hp('eb', `You played #${S.n}`), trail(R()), hp('stop', (S.rv && S.rv.end && S.rv.end.text) || '')));
  if (S.rv) put($('final'), h('div', { class: 'card' }, shot()));
  renderResult();
  renderCallit();
}

// ---------- result + share ----------
function renderResult() {
  const P = S.P, c = chain(), f = finalInfo(), a = f.actual;
  const pts = L.magPoints(S.guess, a), score = L.totalScore(S.codes, pts), max = L.maxScore(R());
  const path = L.pathEmoji(P.seed.emoji, c);
  const text = L.shareText({ n: S.n, seedTitle: P.seed.title, path, codes: S.codes, streak: live() ? S.streak : 0, guess: S.guess, actual: a });
  S.text = text;
  const st = S.st, rare = L.rarityLine(st, S.codes), pl = L.percentileLine(S.you);
  const crowd = st && !st.shown ? `${st.players} player${st.players === 1 ? '' : 's'} so far. Crowd stats appear at 30.` : '';
  const err = { closed: 'This puzzle is closed for crowd stats; your score is saved on this device.', rate_limited: 'Too many plays from this network today; your score is saved on this device.', invalid: "We couldn't record this play." }[S.err] || (S.err ? "Couldn't reach the server; your score is saved on this device." : '');
  const rr = k => S.rv && S.rv.rounds.find(x => x.i === P.rounds[k].i), am = k => { const r = rr(k); const o = r && r.options.find(x => x.id === S.ans[k]); return o || {}; };
  const items = [h('li', null, P.seed.emoji, h('b', null, P.seed.title), hs('m', fmtM(P.seed.multiple)))];
  c.forEach((r, k) => {
    if (!r.continues) items.push(h('li', { class: 'sep' }, `New ripple · ${r.seedEmoji} ${r.seedTitle}`));
    items.push(h('li', null, L.SQUARES[S.codes[k]], r.emoji, h('b', null, r.title), hs('m', fmtM(am(k).multiple)), hs('muted sm', L.fmtTiming(am(k).lag_days, am(k).timing))));
  });
  const share = h('button', { class: 'btn', onclick: () => doShare(text) }, 'Share');
  const copy = h('button', { class: 'btn ghost', onclick: () => copyText(text) }, 'Copy text');
  const next = L.nextRollover();
  put($('result'), h('div', { class: 'card' },
    hp('eb', 'Your chain'),
    h('p', { class: 'grid', 'aria-label': `Score ${score} of ${max}` }, L.gridEmoji(S.codes), hs('score', `${score}/${max}`)),
    rare ? hp('rare', rare, h('span', { class: 'tag', style: 'margin-left:6px' }, "players' picks")) : null,
    pl ? hp('sub', pl) : null,
    crowd ? hp('sub', crowd) : null,
    err ? hp('sub', err) : null,
    h('ol', { class: 'path' }, items),
    hp('sm muted', `📏 You guessed ${fmtM(S.guess)}; it hit ${fmtM(a)}. Measured attention, not proof of cause.`),
    h('div', { class: 'btns' }, share, copy),
    h('pre', { class: 'st', id: 'sharetext' }, text),
    hp('cd', 'Next chain in ', cdb(next), live() && S.streak ? ` · 🔥 ${S.streak} in a row` : ''),
    live() && done2() && !standalone() && !ls.get('ko.a2hs') ? h('button', { class: 'btn ghost wide', style: 'margin-top:10px', onclick: a2hs }, '📲 Keep your streak: add to home screen') : null));
  prefetchPng(L.firstTries(S.codes));
}
function prefetchPng(s) {
  if (S.png !== undefined || !navigator.canShare || S.n <= 0) return;
  S.png = null;
  (async () => {
    for (const u of [`${C.STORAGE}/og/${S.n}-s${s}.png`, `${C.OG}?n=${S.n}&s=${s}`]) {
      try { const r = await fetch(u); if (r.ok && /image\/png/.test(r.headers.get('content-type') || '')) { S.png = new File([await r.blob()], `knock-on-${S.n}.png`, { type: 'image/png' }); return; } } catch (e) {}
    }
  })();
}
async function doShare(text) {
  try {
    if (S.png && navigator.canShare && navigator.canShare({ files: [S.png] })) return await navigator.share({ files: [S.png], text });
    if (navigator.share && matchMedia('(pointer:coarse)').matches) return await navigator.share({ text });
  } catch (e) { if (e && e.name === 'AbortError') return; }
  copyText(text);
}
async function copyText(text) {
  let ok = false;
  try { await navigator.clipboard.writeText(text); ok = true; } catch (e) {
    const t = h('textarea', { style: 'position:fixed;opacity:0' }); t.value = text; document.body.append(t); t.select();
    try { ok = document.execCommand('copy'); } catch (e2) {} t.remove();
  }
  toast(ok ? 'Copied: paste it anywhere' : 'Select the text below to copy it');
}

// ---------- Call It ----------
function callitTeaser() {
  if (S.P.callit && S.P.callit.options && S.P.callit.options.length) put($('callit'), h('div', { class: 'card' }, hp('eb', 'Call It'), hp('sub', 'Finish the chain to call which quiet page spikes next.')));
}
async function renderCallit() {
  const P = S.P, co = P.callit;
  if (!co || !co.options || !co.options.length) return;
  const ci = (await getCallit(S.n)) || {}, byQ = {};
  (ci.options || []).forEach(o => (byQ[o.qid] = o));
  const closes = L.callClosesAt(P.date, co.window_start), closed = P.kind === 'practice' || Date.now() >= closes;
  const mine = S.calls[S.n] || S.mem;
  const shown = !!mine || closed, list = h('div', { class: 'cl' }), note = h('p', { class: 'sm', 'aria-live': 'polite' });
  const draw = split => put(list, ...co.options.map(o => {
    const d = byQ[o.qid] || {}, sp = split && split.find(x => x.qid === o.qid), cp = sp ? sp.pct : d.crowd_pct, url = d.url && safeUrl(d.url, 1);
    const out = d.outcome === 'hit' ? hs('out hit', mine === o.qid ? '🎯 called it' : '🎯 spiked') : d.outcome === 'miss' ? hs('out miss', mine === o.qid ? '✗ missed' : 'stayed calm') : null;
    const body = [h('span', { class: 'e', 'aria-hidden': 'true' }, o.emoji), hs('tx', h('b', null, o.title), h('small', null, o.desc), out, url ? [' ', h('a', { href: url, target: '_blank', rel: 'noopener', class: 'xs' }, 'Wikipedia ↗')] : null)];
    if (!shown) return h('button', { class: 'co', onclick: () => call(o.qid) }, body);
    return h('div', { class: 'co dis' + (mine === o.qid ? ' mine' : '') }, body,
      hs('st', h('strong', null, pct(d.model_p)), 'Model', cp != null ? [h('br'), `players ${cp}%`] : null));
  }));
  const call = async qid => {
    if (FIX) { S.mem = qid; return renderCallit(); }
    note.textContent = 'Sending…';
    const r = await rpc('ripples_submit_call', { p_client: clientId(), p_n: S.n, p_qid: qid }, true);
    if (!r.ok) { note.textContent = { closed: 'Calls are closed for this puzzle.', rate_limited: 'Too many calls from this network today.' }[r.error] || "Couldn't record that call. Try again."; return; }
    S.calls[S.n] = qid; ls.set('ko.calls', S.calls); S.split = r.data && r.data.split;
    renderCallit();
  };
  draw(S.split);
  const resolves = ci.resolves_on || L.addDays(co.window_start, 8);
  note.textContent = mine ? `Your call is in. It resolves on ${fmtD(resolves)}. The Model v0 (base rate) % is shown beside each page; players' picks appear at 30+ calls.` : closed ? 'Calls are closed for this puzzle.' : '';
  put($('callit'), h('div', { class: 'card' },
    hp('eb', 'Call It'),
    h('h2', null, 'What spikes next?'),
    h('p', null, 'Which of these 4 quiet pages linked from ', h('em', null, P.seed.title), ' will spike in the next 7 days?'),
    hp('xs muted', `Window ${fmtD(co.window_start)} – ${fmtD(co.window_end)} · resolves ${fmtD(resolves)} · ${closed ? 'calls closed' : `calls close ${fmtD(L.isoDay(closes))} ${new Date(closes).toISOString().slice(11, 16)} UTC`}. A hit is any day at 3+ robust deviations and 1.5× normal.`),
    list, note, mine && (byQ[mine] || {}).outcome !== 'hit' && (byQ[mine] || {}).outcome !== 'miss' ? h('button', { class: 'btn ghost wide', style: 'margin-top:10px', onclick: () => remind(resolves) }, '⏰ Remind me when it resolves') : null,
    h('div', { class: 'rec', id: 'rec' })));
  record();
}
function remind(day) {
  const ics = L.icsEvent({ uid: `ko-call-${S.n}`, start: Date.parse(day + 'T08:00:00Z'), title: `Knock-On: your call on ${S.P.seed.title} resolves`, url: `https://bensunter.com/ripples/${S.n}/?src=ics`, desc: 'See whether your pick spiked.' });
  const a = h('a', { href: URL.createObjectURL(new Blob([ics], { type: 'text/calendar' })), download: `knock-on-${S.n}-call.ics` });
  document.body.append(a); a.click(); a.remove();
}
async function record() {
  const el = $('rec'), rn = S.n - 8;
  if (FIX || !el) return;
  const ns = Object.keys(S.calls).map(Number).filter(n => n !== S.n && n > 0).sort((a, b) => b - a).slice(0, 8);
  const [cs, last] = await Promise.all([Promise.all(ns.map(getCallit)), rn > 0 ? getCallit(rn) : null]);
  let hit = 0, res = 0;
  const chips = ns.map((n, j) => {
    const o = cs[j] && (cs[j].options || []).find(x => x.qid === S.calls[n]);
    const oc = o ? o.outcome : 'pending';
    if (oc !== 'pending') res++;
    if (oc === 'hit') hit++;
    return hs('bdg', oc === 'hit' ? `🎯 #${n} called it` : oc === 'miss' ? `✗ #${n} missed` : `⏳ #${n} pending`);
  });
  // The Call It that resolved today (window_start + 8 = this puzzle's date): every option's outcome.
  const lo = last && (last.options || []).filter(o => o.outcome !== 'pending');
  put(el, ns.length ? hs('xs muted w100', `Your calls: ${hit} of ${res} resolved called`) : null, ...chips,
    lo && lo.length ? [hs('xs muted w100', `Just resolved, Call It from #${rn}:`), lo.map(o => hs('bdg', `${o.outcome === 'hit' ? '🎯' : '·'} ${o.emoji} ${o.title} ${o.outcome === 'hit' ? 'spiked' : 'stayed calm'}`))] : null);
}

// ---------- tomorrow: reminders + price test (OWNER_DECISIONS D-1, D-3) ----------
const done2 = () => Object.keys(S.hist).filter(n => +n > 0).length >= 2;
const standalone = () => matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
function a2hs() {
  const code = L.encodeBackup(S.hist, S.calls), d = h('dialog', { 'aria-label': 'Add Knock-On to your home screen' });
  const ios = /iP(hone|ad|od)/.test(navigator.userAgent), bip = S.bip;
  put(d, h('h2', null, 'Keep your streak'),
    hp('sm', 'Your streak lives in this browser. Save this backup code first: on iPhone a home-screen app keeps its own storage. Paste it under ? → Restore on any device.'),
    h('pre', { class: 'st code' }, code), h('button', { class: 'btn ghost wide', onclick: () => copyText(code) }, 'Copy backup code'),
    h('h3', null, 'Then add it'),
    bip ? h('button', { class: 'btn wide', onclick: async () => { bip.prompt(); try { await bip.userChoice; } catch (e) {} S.bip = null; d.close(); } }, '📲 Add to home screen')
      : h('ol', { class: 'sm' }, ios ? [h('li', null, 'Tap Share in Safari'), h('li', null, 'Tap "Add to Home Screen"'), h('li', null, 'Tap Add')] : [h('li', null, 'Open your browser menu'), h('li', null, 'Choose "Install app" or "Add to Home screen"')]),
    h('form', { method: 'dialog' }, h('button', { type: 'submit', class: 'btn ghost wide', style: 'margin-top:10px' }, 'Close')));
  d.addEventListener('close', () => d.remove());
  document.body.append(d); d.showModal ? d.showModal() : d.setAttribute('open', '');
  ls.set('ko.a2hs', 1);
}
function renderJoin(at) {
  const next = at || L.nextRollover(), form = h('form', { class: 'jf', hidden: true });
  const topics = new Set();
  const email = h('input', { type: 'email', required: true, autocomplete: 'email', placeholder: 'you@example.com', id: 'jem', maxlength: 254 });
  const role = h('select', { id: 'jrole' }, [['', 'Role (optional)'], ['player', 'Just playing'], ['creator', 'Creator'], ['newsletter', 'Newsletter writer'], ['pr_comms', 'PR / comms'], ['seo_content', 'SEO / content'], ['journalist', 'Journalist'], ['researcher', 'Researcher'], ['brand', 'Brand'], ['analyst', 'Analyst'], ['other', 'Other']].map(([v, t]) => h('option', { value: v }, t)));
  const chips = h('div', { class: 'chips wrapchips' }, Object.keys(L.CATS).map(c => h('button', { class: 'chip', 'aria-pressed': 'false', onclick: e => { const b = e.currentTarget, on = !topics.has(c); on ? topics.add(c) : topics.delete(c); b.setAttribute('aria-pressed', on); } }, `${L.CATS[c]} ${L.CAT_NAMES[c]}`)));
  const send = h('button', { class: 'btn wide', type: 'submit' }, 'Save my spot');
  form.append(hp('sm', "We don't send email yet; we'll write once when the daily email starts."), h('label', { for: 'jem' }, 'Email'), email, h('label', { for: 'jrole' }, 'What do you do?'), role,
    h('fieldset', null, h('legend', null, 'Topics (optional)'), chips), send,
    hp('xs muted', 'We store your email, role and topics for this list only, plus a daily-salted hash of your IP for rate limits. Emails cannot be read back through the site.'));
  form.addEventListener('submit', async e => {
    e.preventDefault();
    send.disabled = true;
    if (!FIX) await rpc('ripples_join', { p_email: email.value.trim(), p_role: role.value || null, p_price: 'free', p_topics: topics.size ? [...topics] : null, p_source: 'game' }, true);
    put(form, h('p', { class: 'sub', role: 'status' }, FIX ? 'Fixture mode: nothing was sent.' : "Saved. We'll write once, when the daily email starts."));
  });
  const free = h('button', { class: 'pb', 'aria-expanded': 'false', onclick: () => { free.setAttribute('aria-expanded', 'true'); form.hidden = false; email.focus(); } }, h('b', null, "📬 Email me tomorrow's chain"), h('small', null, 'Free. One address, no account.'));
  const sup = C.STRIPE.support ? h('a', { class: 'pb', href: C.STRIPE.support, target: '_blank', rel: 'noopener' }, h('b', null, '☕ Support Knock-On'), h('small', null, 'Pay what you want, from $2. It unlocks nothing: the game stays free.')) : null;
  const rem = h('div', { class: 'rem' },
    h('a', { class: 'chip', href: '/ripples/remind.ics', download: 'knock-on-daily.ics' }, '📅 Daily reminder, 19:00'),
    C.RSS ? h('a', { class: 'chip', href: C.RSS }, '📰 RSS') : null,
    done2() && !standalone() ? h('button', { class: 'chip', onclick: a2hs }, '📲 Home screen') : null);
  put($('join'), h('div', { class: 'card' }, hp('eb', 'Tomorrow'), h('h2', null, "Get tomorrow's chain"),
    hp('sm muted', at ? 'Knock-On #1 goes live in ' : 'A new chain goes live every day at 07:30 UTC, the next in ', cdb(next), '.'),
    rem, h('div', { class: 'pt' }, free, sup), form));
}
function restoreFrom(code, out) {
  const r = L.decodeBackup(code);
  if (!r) { out.textContent = "That doesn't look like a Knock-On backup code."; return; }
  const hist = Object.assign({}, r.hist, ls.get('ko.history', {})), calls = Object.assign({}, r.calls, ls.get('ko.calls', {}));
  ls.set('ko.history', hist); ls.set('ko.calls', calls);
  out.textContent = `Restored ${Object.keys(r.hist).length} puzzle${Object.keys(r.hist).length === 1 ? '' : 's'}. Reloading…`;
  setTimeout(() => location.reload(), 700);
}

// ---------- board ----------
const QN = { big_wave: 'Big Wave', sleeper: 'Sleeper', belly_flop: 'Belly Flop', ripple: 'Ripple' };
async function board() {
  const dn = document.body.dataset.n || q.get('p');
  const B = FIX ? await fx('board-0.json') : dn ? await load(`board/${S.n}.json`, 'ripples_board', { p_n: S.n }) : await load('board/latest.json', 'ripples_board', {});
  if (!B || !B.trends || !B.trends.length) return;
  const T = B.trends, cnt = {};
  T.forEach(t => (cnt[t.category] = (cnt[t.category] || 0) + 1));
  let cat = null;
  const W = 340, H = 236, ml = 26, mb = 36, mt = 8, mr = 8;
  const xmax = Math.max(100, ...T.map(t => t.splash_multiple * 1.25)), lx = v => ml + ((Math.log10(Math.max(v, 1.5)) - Math.log10(1.5)) / (Math.log10(xmax) - Math.log10(1.5))) * (W - ml - mr);
  const ly = k => mt + (1 - Math.min(k, 20) / 20) * (H - mt - mb);
  const svg = sv('svg', { class: 'sc', viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': 'Splash versus wake scatter of today’s trends; the list below has the same data' });
  svg.append(sv('line', { class: 'ax', x1: ml, x2: W - mr, y1: H - mb, y2: H - mb }), sv('line', { class: 'ax', x1: ml, x2: ml, y1: mt, y2: H - mb }),
    sv('line', { class: 'qd', x1: lx(10), x2: lx(10), y1: mt, y2: H - mb }), sv('line', { class: 'qd', x1: ml, x2: W - mr, y1: ly(2.5), y2: ly(2.5) }));
  [3, 10, 30, 100].forEach(v => svg.append(sv('text', { x: lx(v), y: H - mb + 18, 'text-anchor': 'middle' }, v + '×')));
  [0, 3, 10, 20].forEach(v => svg.append(sv('text', { x: ml - 4, y: ly(v) + 3, 'text-anchor': 'end' }, v)));
  svg.append(sv('text', { x: (W + ml) / 2, y: H - 2, 'text-anchor': 'middle' }, 'SPLASH: biggest day vs normal (log)'),
    sv('text', { class: 'ql', x: W - mr - 2, y: mt + 10, 'text-anchor': 'end' }, 'BIG WAVE'), sv('text', { class: 'ql', x: ml + 4, y: mt + 10 }, 'SLEEPER'),
    sv('text', { class: 'ql', x: W - mr - 2, y: H - mb - 5, 'text-anchor': 'end' }, 'BELLY FLOP'), sv('text', { class: 'ql', x: ml + 4, y: H - mb - 5 }, 'RIPPLE'));
  const pts = T.map((t, i) => {
    if (t.sensitive || !t.quadrant) return null; // sensitive rows: list only, never placed in a named quadrant
    const g = sv('text', { class: 'pt', x: lx(t.splash_multiple), y: ly(t.wake_k) + 6 - ((i % 3) - 1) * 3, 'text-anchor': 'middle', tabindex: 0 }, t.emoji, sv('title', null, `${t.title}: ${fmtM(t.splash_multiple)} normal, wake ${t.wake_k} of ${t.wake_of}`));
    svg.append(g);
    return g;
  });
  const list = h('ul', { class: 'bl' });
  const drawList = () => put(list, ...T.filter(t => !cat || t.category === cat).sort((a, b) => b.splash_multiple - a.splash_multiple).map(t => {
    const bf = L.bellyFlopText(t);
    return h('li', null, h('span', { class: 'e', 'aria-hidden': 'true' }, t.emoji), h('b', null, t.title), hs('n', `${fmtM(t.splash_multiple)} · ${t.wake_k}/${t.wake_of}`),
      hs('q', t.sensitive || !t.quadrant ? 'Sensitive topic: no label' : QN[t.quadrant], t.biggest_in_days ? ` · biggest day in ${L.fmtInt(t.biggest_in_days)} days` : '',
        bf ? [' ', h('button', { class: 'lk', onclick: () => copyText(bf) }, 'Copy')] : null, crossRow(t.cross)));
  }));
  const chips = h('div', { class: 'chips', role: 'group', 'aria-label': 'Topic' });
  const mk = (c, label, n) => h('button', { class: 'chip', 'aria-pressed': String(c === cat), disabled: c && !n ? true : null, onclick: () => { cat = c; chips.querySelectorAll('.chip').forEach(b => b.setAttribute('aria-pressed', b.dataset.c === String(c))); pts.forEach((p, i) => p && p.setAttribute('opacity', !cat || T[i].category === cat ? 1 : 0.15)); drawList(); }, 'data-c': String(c) }, label);
  chips.append(mk(null, 'All', T.length), ...Object.keys(L.CATS).map(c => mk(c, `${L.CATS[c]} ${L.CAT_NAMES[c]}${cnt[c] ? ' ' + cnt[c] : ''}`, cnt[c] || 0)));
  drawList();
  put($('board'), h('div', { class: 'card' }, hp('eb', `Today's Board · ${fmtD(B.date)}`), h('h2', null, 'Where attention went today, by topic'),
    hp('sm muted', 'Every trend measured today. Splash: its biggest day against its own normal readers. Wake: how many of a fixed set of 20 linked pages spiked after it.'),
    chips, svg, hp('cap', 'Wake k of 20 on the vertical axis. Measured attention, not proof of cause.'), list));
}

// ---------- practice: which spiked harder? ----------
function practice() {
  const out = h('div'), btn = h('button', { class: 'btn ghost wide', onclick: () => startPractice(out, btn) }, 'Play practice');
  put($('practice'), h('div', { class: 'card' }, hp('eb', 'Practice'), h('h2', null, 'Which spiked harder?'),
    hp('sm muted', 'Two measured hops from past puzzles. Pick the one that ran further above its own normal readers. Scored on this device only.'), btn, out));
}
async function startPractice(out, btn) {
  btn.hidden = true;
  put(out, hp('sm muted', 'Loading past hops…'));
  let arc = FIX ? await fx('archive-fixture.json') : await load('archive.json', 'ripples_archive', { p_limit: 500, p_kind: 'all' });
  const ln = (S.latest && S.latest.n) || 0; // no spoilers
  arc = (arc || []).filter(e => S.hist[e.n] || (e.n === S.n ? S.guess : e.n < 1 || e.n < ln - 7));
  const pickN = arc.sort(() => Math.random() - 0.5).slice(0, 5), pool = [];
  const pairs = await Promise.all(pickN.map(e => (FIX ? Promise.all([fx('puzzle-0.json'), fx('reveal-0.json')]) : Promise.all([getPuzzle(e.n), getReveal(e.n)]))));
  for (const [p, r] of pairs) {
    if (!p || !r) continue;
    r.rounds.forEach(rr => {
      const pr = p.rounds.find(x => x.i === rr.i), o = pr && pr.options.find(x => x.id === rr.answer), m = rr.options.find(x => x.id === rr.answer);
      if (o && m) pool.push({ title: o.title, emoji: o.emoji, parent: pr.parent.title, m });
    });
  }
  if (pool.length < 2) { put(out, hp('sm muted', 'Practice opens once past puzzles are archived.')); return; }
  let streak = 0;
  const best = () => ls.get('ko.practice', 0);
  const round = () => {
    let a, b, t = 0;
    do { a = pool[(Math.random() * pool.length) | 0]; b = pool[(Math.random() * pool.length) | 0]; t++; } while ((a === b || Math.max(a.m.multiple, b.m.multiple) / Math.min(a.m.multiple, b.m.multiple) < 1.15) && t < 60);
    if (a === b) { put(out, hp('sm muted', 'Not enough distinct hops yet.')); return; }
    const say = h('p', { class: 'say', 'aria-live': 'polite' }), top = sharedTop([a.m, b.m]);
    const cards = [a, b].map(x => h('button', { class: 'opt', onclick: () => choose(x) }, h('span', { class: 'e', 'aria-hidden': 'true' }, x.emoji), h('b', null, x.title), h('small', null, `linked from ${x.parent}`)));
    const choose = x => {
      const win = x.m.multiple >= (x === a ? b : a).m.multiple;
      streak = win ? streak + 1 : 0;
      if (!FIX && streak > best()) ls.set('ko.practice', streak);
      [a, b].forEach((y, i) => { const c = cards[i]; c.disabled = true; c.classList.add('done', y.m.multiple >= (y === a ? b : a).m.multiple ? 'yes' : 'no');
        c.querySelector('small').replaceWith(h('div', { class: 'rv' }, spark(ratio(y.m), { h: 38, top, med: 1, line: 'draw' })), hs('rl', h('strong', null, fmtM(y.m.multiple) + ' normal'), ` · ${L.fmtTiming(y.m.lag_days, y.m.timing)} ${y.parent}`)); });
      say.textContent = `${win ? '✓ Right.' : '✗ Not this time.'} Streak ${streak} · best ${Math.max(best(), streak)}`;
      say.after(h('button', { class: 'btn ghost wide', style: 'margin-top:10px', onclick: round }, 'Next pair →'));
    };
    put(out, h('div', { class: 'duel' }, cards), say);
  };
  round();
}

// ---------- chrome ----------
async function health() {
  if (FIX) return;
  const hl = await rpc('ripples_health');
  if (hl) $('cs').textContent = hl.clickstream_month ? `Clickstream data: ${L.fmtMonth(hl.clickstream_month)}.` : 'Clickstream data: not loaded yet.';
}
function tick() {
  const up = () => {
    document.querySelectorAll('[data-cd]').forEach(e => (e.textContent = +e.dataset.cd > Date.now() ? L.fmtCountdown(+e.dataset.cd - Date.now()) : 'any minute now'));
    const due = S.prelaunch || (S.latest && Date.parse(S.latest.next_at));
    if (!FIX && due && Date.now() >= due && !S.rolled) {
      S.rolled = true;
      rpc('ripples_latest').then(l => {
        if (!l || l.n == null) { setTimeout(() => (S.rolled = false), 120000); return; }
        if (S.prelaunch) location.reload();
        else if (l.n !== S.n) banner(`Knock-On #${l.n} is live.`, 'info', ['Play it →', '/ripples/']);
      });
    }
  };
  setInterval(up, 30000);
}
function ui() {
  const root = document.documentElement;
  $('theme').addEventListener('click', () => {
    const dark = root.getAttribute('data-theme') === 'dark' || (!root.hasAttribute('data-theme') && matchMedia('(prefers-color-scheme: dark)').matches);
    root.setAttribute('data-theme', dark ? 'light' : 'dark');
    try { localStorage.setItem('ko.theme', dark ? 'light' : 'dark'); } catch (e) {}
  });
  addEventListener('beforeinstallprompt', e => { e.preventDefault(); S.bip = e; });
  const rs = $('rsgo');
  if (rs) rs.addEventListener('click', () => restoreFrom($('rscode').value, $('rsout')));
  const d = $('helpdlg');
  $('help').addEventListener('click', () => (d.showModal ? d.showModal() : d.setAttribute('open', '')));
  d.addEventListener('click', e => { if (e.target === d) d.close(); });
}

boot();
