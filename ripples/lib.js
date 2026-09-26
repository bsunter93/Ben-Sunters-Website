// Ripple Map v6: pure helpers (no DOM). Used by app.js, the methods page, /pro/ and tools/test-lib.mjs.
// Every number shown comes from the payload (SQL); these functions only format and arrange it (ENGINE §8, EXPERIENCE §12).

export const DOMAINS = ['reading', 'chatter', 'markets', 'builders', 'real_world', 'jobs', 'institutions', 'stuff'];
export const DOM = {
  reading: { w: 'Reading', i: '📖', d: 'Wikipedia readers and search' },
  chatter: { w: 'Chatter', i: '💬', d: 'posts, news and TV' },
  markets: { w: 'Markets', i: '📊', d: 'prediction markets, rates and prices' },
  builders: { w: 'Builders', i: '🧰', d: 'package downloads, code and developer questions' },
  real_world: { w: 'Real world', i: '🛫', d: 'air travel, transit, grid demand and felt reports' },
  jobs: { w: 'Jobs', i: '🧑‍💼', d: 'job postings and jobless claims' },
  institutions: { w: 'Institutions', i: '🏛', d: 'declarations, warnings, filings and spending' },
  stuff: { w: 'Stuff', i: '🛍', d: 'what people read, watch, play and buy' },
};
export const domWord = d => (DOM[d] ? DOM[d].w : 'Other');
export const domIcon = d => (DOM[d] ? DOM[d].i : '▫️');

// Tiers: word + glyph + pips + fill (EXPERIENCE §3). Definitions are the plain-language ones for the ? sheet and stamps.
export const TIER = {
  measured: { w: 'Measured', g: '●', pips: 3, def: 'Moved against its own normal, after the shock, with two sources agreeing, and it passed the fluke tests.' },
  likely: { w: 'Likely', g: '◐', pips: 2, def: "Moved after the shock, but one test is still short, so a fluke isn't ruled out." },
  watching: { w: 'Watching', g: '○', pips: 1, def: 'A known mechanism says it could move. Its window is still open, so there is no result yet.' },
  retracted: { w: 'Retracted', g: '✕', pips: 0, def: 'It was on the map, then a later check pushed it below the bar. It stays visible.' },
  flat: { w: 'Stayed flat', g: '⊥', pips: 0, def: 'Tested and stayed inside its normal range. Counted, drawn grey, never a stop.' },
};
export const tierWord = t => (TIER[t] ? TIER[t].w : t || '');
export const isStation = n => !!n && (n.tier === 'measured' || n.tier === 'likely' || n.tier === 'retracted');
export const isMoved = n => !!n && (n.tier === 'measured' || n.tier === 'likely');
export const FOOT = 'Consistent with, never proof of cause.';
export const CARD_FOOT = 'Measured movement, not proof of cause.';

// ---------- numbers ----------
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const DAY = 864e5;
const fin = x => x !== null && x !== undefined && x !== '' && isFinite(Number(x));
export const fmtInt = x => (fin(x) ? Math.round(Number(x)).toLocaleString('en-US') : '–');
// "× its own normal" as digits (no sign): 0.91, 3.4, 12
export function num(x) {
  if (!fin(x)) return '';
  const v = Number(x);
  if (v < 1) return v.toFixed(2);
  if (v < 10) return v.toFixed(1).replace(/\.0$/, '');
  return String(Math.round(v));
}
// a rate series' rho is a difference (percentage or probability), never a multiple (fixtures README "Units")
export function mult(x, unit = 'x') {
  if (!fin(x)) return '';
  const v = Number(x);
  if (unit === 'points') return (v >= 0 ? '+' : '−') + Math.abs(v).toFixed(2);
  return num(v) + '×';
}
export function rel(x, unit = 'x', tail = 'its normal') {
  if (!fin(x)) return '';
  const v = Number(x);
  if (unit === 'points') { const a = Math.abs(v).toFixed(2); return `${a} ${a === '1.00' ? 'point' : 'points'} ${v < 0 ? 'below' : 'above'} ${tail}`; }
  return `${num(v)}× ${tail}`;
}
export const oneIn = n => (fin(n) && Number(n) >= 1 ? `1 in ${fmtInt(n)}` : '');
// A multiple read as a percentage, so 0.91× reads as a signal: "9% fewer" / "240% more". A caption only, never a flap;
// empty for rates in points and for moves under 1%.
export function pctGloss(x, unit = 'x') {
  if (!fin(x) || unit === 'points') return '';
  const v = Number(x), p = v < 1 ? Math.round((1 - v) * 100) : Math.round((v - 1) * 100);
  if (p < 1) return '';
  return v < 1 ? `${p}% fewer` : `${fmtInt(p)}% more`;
}
// the arrow before a flap: ↓ for a dip, ↑ for a rise, nothing within ±3.5% (|log2| ≤ .05)
export const dirGlyph = (x, unit = 'x') => (!fin(x) ? '' : unit === 'points' ? (Number(x) < 0 ? '↓' : Number(x) > 0 ? '↑' : '') : Math.abs(log2(Number(x))) > 0.05 ? (Number(x) < 1 ? '↓' : '↑') : '');
export const plural = (n, one, many = one + 's') => `${fmtInt(n)} ${Number(n) === 1 ? one : many}`;

// ---------- dates (UTC dates as yyyy-mm-dd strings) ----------
export const dayMs = d => Date.parse(String(d).slice(0, 10) + 'T00:00:00Z');
export const isoDay = t => new Date(typeof t === 'number' ? t : dayMs(t)).toISOString().slice(0, 10);
export const addDays = (d, n) => isoDay(dayMs(d) + n * DAY);
export const daysBetween = (a, b) => Math.round((dayMs(b) - dayMs(a)) / DAY);
export function fmtDate(iso, long) {
  if (!iso) return '';
  const d = new Date(String(iso).slice(0, 10) + 'T12:00:00Z');
  if (long) return d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }).replace(',', '');
  return `${WD[d.getUTCDay()]} ${d.getUTCDate()} ${MO[d.getUTCMonth()]}`;
}
export const fmtDay = iso => { if (!iso) return ''; const d = new Date(String(iso).slice(0, 10) + 'T12:00:00Z'); return `${d.getUTCDate()} ${MO[d.getUTCMonth()]}`; };
export const fmtDayY = iso => (iso ? `${fmtDay(iso)} ${String(iso).slice(0, 4)}` : '');
export const fmtMonth = ym => (ym ? `${MO[+ym.slice(5, 7) - 1]} ${ym.slice(0, 4)}` : '');
export const fmtTime = ts => (ts ? String(ts).slice(11, 16) + ' UTC' : '');
export function isoWeek(dstr) {
  const d = new Date(dayMs(dstr));
  const wd = (d.getUTCDay() + 6) % 7; d.setUTCDate(d.getUTCDate() - wd + 3);
  const y = d.getUTCFullYear(), j4 = new Date(Date.UTC(y, 0, 4));
  const w = 1 + Math.round(((d - j4) / DAY - 3 + ((j4.getUTCDay() + 6) % 7)) / 7);
  return `${y}-${String(w).padStart(2, '0')}`;
}
export function weekRange(w) {
  const m = /^(\d{4})-(\d{2})$/.exec(w || ''); if (!m) return null;
  const j4 = Date.UTC(+m[1], 0, 4), mon1 = j4 - ((new Date(j4).getUTCDay() + 6) % 7) * DAY;
  const from = isoDay(mon1 + (+m[2] - 1) * 7 * DAY);
  return { from, to: addDays(from, 6) };
}
export const lagText = l => (!fin(l) ? '' : Number(l) === 0 ? 'the same day as' : `${plural(Math.round(Number(l)), 'day')} after`);
// a look dated after the window closes reads the window's data after the fact: it is the final look, not a next one
export const lookWord = (due, close) => (due && close && String(due) > String(close) ? 'Final look' : 'Next look');
export const lagShort = l => (!fin(l) ? '' : Number(l) === 0 ? 'same day' : `+${Math.round(Number(l))} d`);

// ---------- routes ----------
// /ripples/line/{slug}-{id}/[v{k}/][stop/{hop}/], /ripples/lands/{d}/, /ripples/week/{yyyy-ww}/, /ripples/map/, /archive/, /methods/
export function parseRoute(path, ds = {}) {
  const p = String(path || '/').replace(/index\.html$/, '');
  let m;
  const r = { route: 'home' };
  if ((m = /\/ripples\/line\/([a-z0-9-]*?-?(\d+))\/(?:v(\d+)\/)?(?:stop\/(\d+)\/)?$/.exec(p))) {
    r.route = m[4] ? 'stop' : 'line'; r.slug = m[1]; r.event = +m[2]; if (m[3]) r.version = +m[3]; if (m[4]) r.hop = +m[4];
  } else if (/\/ripples\/line\/$/.test(p)) r.route = 'lines';
  else if ((m = /\/ripples\/lands\/([a-z_]+)\/$/.exec(p)) && DOM[m[1]]) { r.route = 'lands'; r.domain = m[1]; }
  else if (/\/ripples\/lands\/$/.test(p)) r.route = 'lands';
  else if ((m = /\/ripples\/week\/(\d{4}-\d{2})\/$/.exec(p))) { r.route = 'week'; r.week = m[1]; }
  else if (/\/ripples\/week\/$/.test(p)) r.route = 'week';
  else if (/\/ripples\/map\/$/.test(p)) r.route = 'map';
  else if (/\/ripples\/archive\/$/.test(p)) r.route = 'archive';
  else if (/\/ripples\/methods\/$/.test(p)) r.route = 'methods';
  // stub attributes (gen-stubs.mjs) win: data-route/event/version/hop/domain/week
  // the bare /line/ shell (data-route=lines) also serves line URLs when a host falls back to it: the path wins then
  if (ds.route && !(ds.route === 'lines' && r.route !== 'home')) r.route = ds.route;
  if (ds.event) r.event = +ds.event;
  if (ds.version && r.route !== 'line') r.version = +ds.version;
  if (ds.version && r.route === 'line' && /\/v\d+\/$/.test(p)) r.version = +ds.version;
  if (ds.hop) r.hop = +ds.hop;
  if (ds.domain) r.domain = ds.domain;
  if (ds.week) r.week = ds.week;
  return r;
}
export const lineUrl = (slug, k) => `/ripples/line/${slug}/${k ? `v${k}/` : ''}`;
export const stopUrl = (slug, h) => `/ripples/line/${slug}/stop/${h}/`;
export const SITE = 'https://bensunter.com';

// ---------- line structure ----------
const TR = { measured: 0, likely: 1, retracted: 2, watching: 3 };
function sib(a, b) {
  const wa = a.tier === 'watching' ? 1 : 0, wb = b.tier === 'watching' ? 1 : 0;
  if (wa !== wb) return wa - wb;
  if (!wa) {
    // attention ripples are muted on the map: outcome stations lead, attention-only co-moves follow
    const ra = a.attention_ripple ? 1 : 0, rb = b.attention_ripple ? 1 : 0;
    if (ra !== rb) return ra - rb;
    const oa = a.onset || '9999', ob = b.onset || '9999';
    if (oa !== ob) return oa < ob ? -1 : 1;
    if (TR[a.tier] !== TR[b.tier]) return TR[a.tier] - TR[b.tier];
    return (a.q ?? 1) - (b.q ?? 1) || a.hop_id - b.hop_id;
  }
  const da = a.window_closed ? 'z' : a.due || a.window_close || 'y', db = b.window_closed ? 'z' : b.due || b.window_close || 'y';
  return da < db ? -1 : da > db ? 1 : a.hop_id - b.hop_id;
}
export function kidsOf(c) {
  const k = new Map();
  const ids = new Set((c.nodes || []).map(n => n.hop_id));
  for (const n of c.nodes || []) {
    const p = n.parent_hop && ids.has(n.parent_hop) ? n.parent_hop : 0;
    if (!k.has(p)) k.set(p, []);
    k.get(p).push(n);
  }
  for (const v of k.values()) v.sort(sib);
  return k;
}
// The reading order of a line: depth-first, stations before Watching, subtrees kept next to their parent.
// Below the shock every stop is shown; at a deeper fork the spine follows the strongest child (lowest q) and the other
// station children fold into a track-switch chip (choice[parentHop] = hop_id re-routes the spine). Desktop passes
// nofold and shows the branches side by side instead (EXPERIENCE §4.2).
export function lineOrder(c, choice = {}, nofold = false) {
  const kids = kidsOf(c), out = [];
  const walk = (pid, depth) => {
    let ch = kids.get(pid) || [];
    let folded = [];
    if (pid && !nofold) {
      const st = ch.filter(isMoved);
      if (st.length > 1) {
        const pick = st.some(x => x.hop_id === choice[pid]) ? choice[pid] : st.slice().sort((a, b) => (a.q ?? 1) - (b.q ?? 1))[0].hop_id;
        folded = st.filter(x => x.hop_id !== pick);
        ch = ch.filter(x => !folded.includes(x));
      }
    }
    const parent = out.find(e => e.n.hop_id === pid);
    if (parent) parent.folded = folded;
    for (const n of ch) { out.push({ n, depth, folded: [] }); walk(n.hop_id, depth + 1); }
  };
  walk(0, 1);
  return out;
}
export function counts(c) {
  const s = { measured: 0, likely: 0, watching: 0, retracted: 0, flat: (c.flat || []).length };
  for (const n of c.nodes || []) if (s[n.tier] !== undefined) s[n.tier]++;
  return s;
}
export const stopCount = c => (c.nodes || []).filter(isMoved).length;
export const movedDomains = c => [...new Set((c.nodes || []).filter(isMoved).map(n => n.domain))];
export function lineDays(c) { return c.as_of && c.event?.onset ? Math.max(0, daysBetween(c.event.onset, c.as_of)) : 0; }
export const STATUS = { running: 'still running', ended: 'line ended', nowhere: 'went nowhere', archived: 'archived' };
export function lineMeta(c) {
  const n = stopCount(c), d = movedDomains(c).length, days = lineDays(c);
  return [plural(n, 'stop'), d ? plural(d, 'domain') : '', plural(days, 'day'), STATUS[c.status] || c.status].filter(Boolean);
}
export function lineEnd(c) {
  if (c.status === 'nowhere') return `Went nowhere: ${plural(c.denominators?.tested ?? 0, 'path')} tested, none moved.`;
  if (c.status === 'ended' || c.status === 'archived') return 'Line ends: nothing downstream passed.';
  return 'Line ends here for now.';
}
export const parentLabel = (c, n) => {
  if (!n || !n.parent_hop) return c.event.label;
  const p = (c.nodes || []).find(x => x.hop_id === n.parent_hop);
  return p ? p.label : c.event.label;
};
export function ancestors(c, hop) {
  const by = new Map((c.nodes || []).map(n => [n.hop_id, n])), out = [];
  let n = by.get(hop);
  while (n && n.parent_hop && by.has(n.parent_hop)) { n = by.get(n.parent_hop); out.unshift(n); }
  return out;
}
// Frozen version vs the live line: "It's grown since this was shared: +N stops" (Measured + Likely; can be negative)
export function grownSince(frozen, live) {
  if (!frozen || !live || frozen.version >= live.version) return null;
  return { version: live.version, stops_added: stopCount(live) - stopCount(frozen) };
}

// ---------- words ----------
// The stop card's flap sentence: parts are text or {flap}. Watching/retracted stops get words only.
export function stopSentence(n, parent) {
  if (n.tier === 'retracted' && n.retracted) return [{ t: `Retracted ${fmtDay(n.retracted.date)}: ${n.retracted.reason}.` }];
  if (n.tier === 'watching' || !fin(n.rho)) {
    if (n.window_closed) return [{ t: `${n.label}: its window closed ${fmtDay(n.window_close)}. The result is pending.` }];
    return [{ t: `${n.label}: no measurable move yet.` }];
  }
  const who = n.domain === 'reading' ? `${n.label} readers` : n.label;
  const parts = [{ t: `${n.domain === 'reading' && !/readers?$/i.test(n.label) ? who : n.label} ran ` }];
  // {dir} is the ↓/↑ glyph before the flap; {g} is the percentage gloss after it (Plex caption, never a flap)
  const dir = dirGlyph(n.rho, n.unit), g = pctGloss(n.rho, n.unit);
  if (dir) parts.push({ dir });
  if (n.unit === 'points') parts.push({ flap: mult(n.rho, 'points') }, { t: ` ${Math.abs(n.rho).toFixed(2) === '1.00' ? 'point' : 'points'} ${n.rho < 0 ? 'below' : 'above'} its normal, ` });
  else parts.push({ flap: num(n.rho) + '×' }, { t: ' its normal' }, ...(g ? [{ g: ` (${g})` }] : []), { t: ', ' });
  if (fin(n.lag_days) && Number(n.lag_days) > 0) parts.push({ flap: `+${Math.round(n.lag_days)}` }, { t: ` ${Number(n.lag_days) === 1 ? 'day' : 'days'} after ${parent}.` });
  else parts.push({ t: `the same day as ${parent}.` });
  return parts;
}
// the plain sentence (screen readers, tests): flaps as digits; the ↓/↑ glyph and the percentage gloss are visual only
export const plainParts = parts => parts.map(p => (p.g != null || p.dir != null ? '' : p.t ?? p.flap)).join('');
// Evidence sheet headline (§5): the shrunk multiple with its interval
export function evidenceHeadline(h) {
  const x = h.headline || {}, u = h.q1_normal?.unit || 'x', node = h.node?.label || '';
  if (!fin(x.rho)) return `${node}: no measurable move yet.`;
  const iv = fin(x.rho_lo) && fin(x.rho_hi) ? ` [${u === 'points' ? mult(x.rho_lo, u) : num(x.rho_lo)}–${u === 'points' ? mult(x.rho_hi, u) : num(x.rho_hi)}]` : '';
  const size = u === 'points' ? `${rel(x.rho, u, 'its normal')}${iv}` : `${num(x.rho)}×${iv} its normal`;
  const when = !fin(x.lag_days) ? '' : Number(x.lag_days) === 0 ? ' on the same day' : ` ${plural(Math.round(x.lag_days), 'day')} earlier`;
  return `${node} at ${size}, consistent with ${x.parent_label || h.parent?.label || 'the shock'}${when}.`;
}
// The two fluke numbers, two labels, never merged (ENGINE §8)
export const lookalikes = p1 => (fin(p1) ? `A random pairing looks this strong about 1 in ${fmtInt(p1)} times.` : '');
// f is shown as 1 in ⌊1/f⌋, capped at "1 in 50+" (ENGINE §5.4); the label is ENGINE §8 verbatim
export const flukeK = f1 => (!fin(f1) ? '' : Math.floor(Number(f1)) >= 50 ? '50+' : fmtInt(Math.floor(Number(f1))));
export const flukeRate = (f1, warming) => (warming ? 'Fluke rate still warming up: too few decoy links this strong yet.' : fin(f1) ? `Links like this turn out to be flukes about 1 in ${flukeK(f1)} times.` : '');
export function dayLine(line) {
  if (!line || line.source === 'not available' || !fin(line.tested)) return null;
  return { tested: line.tested, moved: line.moved, measured: line.measured, expected: line.expected_flukes };
}
export const expected = x => (fin(x) ? (Number(x) < 10 ? Number(x).toFixed(1).replace(/\.0$/, '') : fmtInt(x)) : '–');
// Σ f over the Measured stops (ENGINE §5.3 "expected flukes among the Measured"): always phrased against the Measured count,
// never against paths tested or moved. Null when nothing is Measured (then there is nothing to expect a fluke among).
export function flukeClause(x, measured) {
  if (!fin(measured) || Number(measured) <= 0 || !fin(x)) return null;
  return Number(measured) === 1 ? `about ${expected(x)} expected to be a fluke` : `about ${expected(x)} of those ${fmtInt(measured)} expected to be flukes`;
}
export function biggest(s) {
  if (!s) return '';
  if (s.biggest_basis === 'days_since_higher' && fin(s.biggest_in_days)) return `Biggest day in ${fmtInt(s.biggest_in_days)} days`;
  if (s.biggest_basis === 'highest_in_window' && fin(s.biggest_window_days)) return `Highest in the ${fmtInt(s.biggest_window_days)} days we store`;
  return '';
}
// Placebo strip: 200 tiles for fake dates, fake starts and fake pages; the ones that beat the real hop are lit (≥ 1 if any did)
export function placeboStrip(pl, tiles = 200) {
  const fam = ['date', 'link', 'topic'].map(k => ({ k, n: pl?.[k]?.n || 0, exceed: pl?.[k]?.exceed || 0 })).filter(f => f.n > 0);
  const n = fam.reduce((a, f) => a + f.n, 0), ex = fam.reduce((a, f) => a + f.exceed, 0);
  if (!n) return { n: 0, exceed: 0, lit: 0, tiles: 0, fam };
  return { n, exceed: ex, lit: ex ? Math.max(1, Math.round((tiles * ex) / n)) : 0, tiles, fam };
}
export const FAM_WORD = { date: 'fake dates', link: 'fake starts', topic: 'fake pages' };
// Fluke meter: K tiles with one marigold tile ("1 in K", K = ⌊1/f⌋); text only at the 50+ cap
export const flukeTiles = f1 => (fin(f1) && f1 >= 2 && f1 < 50 ? Math.floor(f1) : 0);

// ---------- share (text first; the URL sits inside the text, playbook §3.4) ----------
export function shareLine(c) {
  if (c.text_share) return c.text_share;
  const url = `${SITE}${lineUrl(c.event.slug, c.version)}`;
  const tiles = lineOrder(c).filter(e => e.depth === 1 && e.n.tier !== 'retracted').slice(0, 6).map(e => (e.n.tier === 'watching' ? '┄' : '━') + domIcon(e.n.domain)).join('');
  return `${c.event.emoji || ''} ${c.event.label} ${tiles}\n${plural(stopCount(c), 'stop')} in ${plural(lineDays(c), 'day')}, ${STATUS[c.status] || c.status}\nconsistent with, not proof of cause\n${url}`;
}
export function shareStop(h) {
  const u = h.q1_normal?.unit || 'x', x = h.headline || {};
  const url = `${SITE}${stopUrl(h.event.slug, h.hop_id)}`;
  const size = h.tier === 'retracted' ? `retracted ${fmtDay(h.retracted?.date)}` : fin(x.rho) ? `${rel(x.rho, u, 'its normal')}, ${lagText(x.lag_days)} ${x.parent_label || h.event.label}` : 'no measurable move yet';
  return `${h.event.emoji || ''} ${h.event.label} ━${domIcon(h.node.domain)} ${h.node.label}\n${tierWord(h.tier)}: ${size}\nconsistent with, not proof of cause\n${url}`;
}

// ---------- staircase geometry ----------
// x = days since the shock began: a short run-up before d0, linear to +7, then log to the end (≤ +90)
export function xScale(dEnd, x0, x1, dStart = -14) {
  const end = Math.max(10, Math.min(90, dEnd)), W = x1 - x0;
  const f = d => {
    if (d <= 0) return 0.16 * Math.max(0, d - dStart) / (0 - dStart);
    if (d <= 7) return 0.16 + 0.44 * d / 7;
    return 0.6 + 0.4 * Math.log(Math.min(d, end) / 7) / Math.log(end / 7);
  };
  const s = d => x0 + W * f(d);
  s.ticks = [0, 1, 3, 7, 14, 28, 60, 90].filter(t => t <= end);
  s.start = dStart; s.end = end;
  return s;
}
// A series of daily values that ends on as_of → [{d, v}] relative to the shock onset
export function seriesDays(arr, asOf, onset) {
  if (!Array.isArray(arr) || !arr.length || !asOf || !onset) return [];
  const last = daysBetween(onset, asOf), n = arr.length;
  return arr.map((v, i) => ({ d: last - (n - 1 - i), v })).filter(p => fin(p.v));
}
export const log2 = v => Math.log(Math.max(1e-3, v)) / Math.LN2;

// ---------- legacy exports kept for /ripples/pro/ (its sample brief reads the v5 files) ----------
export const CATS = { person: '👤', place: '📍', film_tv: '🎬', music: '🎵', sport: '🏅', science_health: '🧬', tech: '💻', business: '🏢', politics_law: '⚖️', food_drink: '🍎', nature_weather: '🌦', history_culture: '🏛', other: '🔹' };
export const CAT_NAMES = { person: 'People', place: 'Places', film_tv: 'Film & TV', music: 'Music', sport: 'Sport', science_health: 'Science & health', tech: 'Tech', business: 'Business', politics_law: 'Politics & law', food_drink: 'Food & drink', nature_weather: 'Nature & weather', history_culture: 'History & culture', other: 'Other' };
export const fmtMultiple = x => (fin(x) ? num(x) + '×' : '–');
export function fmtTiming(lag, timing) {
  if (timing === 'alongside' || lag === 0) return 'alongside';
  if (lag == null) return timing === 'after' ? 'after' : '';
  return `+${lag} day${lag === 1 ? '' : 's'} after`;
}
