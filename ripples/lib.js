// Knock-On v5: pure functions (no DOM). Imported by app.js and tools/test-lib.mjs.
export const CATS = { person: '👤', place: '📍', film_tv: '🎬', music: '🎵', sport: '🏅', science_health: '🧬', tech: '💻', business: '🏢', politics_law: '⚖️', food_drink: '🍎', nature_weather: '🌦', history_culture: '🏛', other: '🔹' };
export const CAT_NAMES = { person: 'People', place: 'Places', film_tv: 'Film & TV', music: 'Music', sport: 'Sport', science_health: 'Science & health', tech: 'Tech', business: 'Business', politics_law: 'Politics & law', food_drink: 'Food & drink', nature_weather: 'Nature & weather', history_culture: 'History & culture', other: 'Other' };
export const SQUARES = ['🟥', '🟨', '🟩'];
const DAY = 864e5;

// 2 = first try, 1 = second try, 0 = missed.
export function scoreRound(picks, answerId) {
  if (!picks || !picks.length) return 0;
  if (picks[0] === answerId) return 2;
  return picks[1] === answerId ? 1 : 0;
}
export const magErr = (guess, actual) => Math.abs(Math.log10(guess / actual));
// SPEC §7 as amended by OWNER_DECISIONS D-2: 2 points within 1.5× (e ≤ 0.176), 1 point within 2× (e ≤ 0.301).
export function magPoints(guess, actual) {
  if (!(guess > 0) || !(actual > 0)) return 0;
  const e = magErr(guess, actual);
  return e <= 0.176 ? 2 : e <= 0.301 ? 1 : 0;
}
export const magX = (guess, actual) => Math.pow(10, magErr(guess, actual));
export const maxScore = rounds => 2 * rounds + 2;
export function totalScore(codes, magPts) {
  return codes.reduce((a, c) => a + c, 0) + (magPts || 0);
}
export const gridEmoji = codes => codes.map(c => SQUARES[c]).join('');
export const firstTries = codes => codes.filter(c => c === 2).length;

// Rounds as the share path sees them (answers found by hashing).
export function chainFromPuzzle(puzzle, answerIds) {
  return puzzle.rounds.map((r, k) => {
    const o = r.options.find(x => x.id === answerIds[k]) || {};
    const fresh = !r.continues && r.seed && !(k === 0 && r.seed.qid === puzzle.seed.qid);
    return { i: r.i, continues: !fresh, seedEmoji: fresh ? r.seed.emoji : null, seedTitle: fresh ? r.seed.title : null, emoji: o.emoji || '🔹', title: o.title || '', qid: o.qid, id: o.id, parent: r.parent };
  });
}
// SPEC §3 {path}, e.g. 👤→📍→🎬 · 🎵→🏅 (a fresh ripple is joined with ' · ' and starts with its seed emoji).
export function pathEmoji(seedEmoji, chain) {
  let out = seedEmoji;
  chain.forEach((r, k) => {
    if (r.continues) out += '→' + r.emoji;
    else out = (k === 0 ? r.seedEmoji : out + ' · ' + r.seedEmoji) + '→' + r.emoji;
  });
  return out;
}
export function magLine(guess, actual) {
  if (!(guess > 0) || !(actual > 0)) return '';
  // D-2: only for a 2-point guess (same test as the server).
  return magPoints(guess, actual) === 2 ? `📏 last hop within ${magX(guess, actual).toFixed(1)}×` : '';
}
// SPEC §3 exactly. Blank lines are omitted.
export function shareText({ n, seedTitle, path, codes, streak = 0, guess = null, actual = null }) {
  const pts = guess == null ? 0 : magPoints(guess, actual);
  const score = totalScore(codes, pts), max = maxScore(codes.length), s = firstTries(codes);
  const head = n < 0 ? `Knock-On practice · ${seedTitle}` : `Knock-On #${n} · ${seedTitle}`;
  const url = n < 0 ? `bensunter.com/ripples/?p=${n}` : `bensunter.com/ripples/${n}/${s}`;
  return [head, path, `${gridEmoji(codes)} ${score}/${max}${streak >= 2 ? ' 🔥' + streak : ''}`,
    guess == null ? '' : magLine(guess, actual), url].filter(Boolean).join('\n');
}
// Board row share (SPEC §3 second format). Never for sensitive rows.
export function bellyFlopText(t) {
  if (!t || t.sensitive || t.quadrant !== 'belly_flop') return '';
  return `💥 Belly Flop: ${t.title}. ${fmtMultiple(t.splash_multiple)} normal readers, no measured wake on Wikipedia. bensunter.com/ripples/`;
}

export async function sha256Hex(str) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str));
  return Array.from(new Uint8Array(buf), b => b.toString(16).padStart(2, '0')).join('');
}
// answer_h = hex(sha256(utf8(n|i|qid))). Anti-glance only.
export async function answerCheck(n, i, qid, answerH) {
  return (await sha256Hex(`${n}|${i}|${qid}`)) === answerH;
}
export async function findAnswer(n, round) {
  for (const o of round.options) if (await answerCheck(n, round.i, o.qid, round.answer_h)) return o.id;
  return null;
}

export const fmtInt = x => (x == null ? '–' : Math.round(x).toLocaleString('en-US'));
export function fmtMultiple(x) {
  if (x == null || !isFinite(x)) return '–';
  return (x >= 10 ? String(Math.round(x)) : (Math.round(x * 10) / 10).toFixed(1)) + '×';
}
export function fmtBiggestIn(seed) {
  if (!seed) return '';
  if (seed.biggest_since_records) return 'Biggest day since records began, Jul 2015';
  return seed.biggest_in_days ? `Biggest day in ${fmtInt(seed.biggest_in_days)} days` : '';
}
export function fmtTiming(lag, timing) {
  if (timing === 'alongside' || lag === 0) return 'alongside';
  if (lag == null) return timing === 'after' ? 'after' : '';
  return `+${lag} day${lag === 1 ? '' : 's'} after`;
}
export function fmtFluke(ev) {
  if (!ev) return '';
  if (ev.fluke_warming || ev.fluke_1_in == null) return 'Fluke meter warming up';
  const k = ev.fluke_1_in >= 50 ? '50+' : ev.fluke_1_in;
  return `About 1 in ${k} passes like this are chance`;
}
export const fmtPct = p => (p == null ? '–' : Math.round(p) + '%');
export function percentileLine(you) {
  if (!you || you.percentile == null) return '';
  return `You scored higher than ${fmtPct(you.percentile)} of players`;
}
// Crowd rarity from players' picks (≥30 players), only when < 50%.
export function rarityLine(stats, codes) {
  if (!stats || !stats.shown || !stats.rounds) return '';
  const low = (k, ok) => stats.rounds.filter(r => r[k] != null && r[k] < 50 && ok(r)).sort((a, b) => a[k] - b[k])[0];
  const a = low('first_try_pct', r => codes[r.i - 1] === 2);
  if (a) return `Only ${fmtPct(a.first_try_pct)} of players found round ${a.i} first try`;
  const b = low('found_pct', r => codes[r.i - 1] > 0);
  return b ? `Only ${fmtPct(b.found_pct)} of players found round ${b.i}` : '';
}
// Dates are UTC ISO days (YYYY-MM-DD).
export const isoDay = ms => new Date(ms).toISOString().slice(0, 10);
export const addDays = (iso, k) => isoDay(Date.parse(iso + 'T00:00:00Z') + k * DAY);
export const puzzleNoForDate = (iso, epoch) => Math.round((Date.parse(iso + 'T00:00:00Z') - Date.parse(epoch + 'T00:00:00Z')) / DAY);
// Current puzzle date: the puzzle rolls over at 07:30 UTC.
export const currentPuzzleDate = (now = Date.now()) => isoDay(now - 7.5 * 36e5);
export function nextRollover(now = Date.now()) {
  const d = new Date(now), t = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 7, 30);
  return t > now ? t : t + DAY;
}
export const timeToNext = (now = Date.now()) => nextRollover(now) - now;
export function fmtCountdown(ms) {
  const m = Math.max(0, Math.ceil(ms / 6e4)), h = Math.floor(m / 60);
  return h ? `${h}h ${String(m % 60).padStart(2, '0')}m` : `${m}m`;
}
// Call It closes at min(07:30 UTC on date+1, 00:00 UTC after window_start).
export function callClosesAt(puzzleDate, windowStart) {
  return Math.min(Date.parse(addDays(puzzleDate, 1) + 'T07:30:00Z'), Date.parse(addDays(windowStart, 1) + 'T00:00:00Z'));
}
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'], MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
// 'Fri 25 Sep' (long: 'Friday 25 September'), always UTC.
export function fmtDate(iso, long) {
  if (!iso) return '';
  const d = new Date(iso.slice(0, 10) + 'T12:00:00Z');
  if (long) return d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }).replace(',', '');
  return `${WD[d.getUTCDay()]} ${d.getUTCDate()} ${MO[d.getUTCMonth()]}`;
}
export const fmtMonth = ym => (ym ? `${MO[+ym.slice(5, 7) - 1]} ${ym.slice(0, 4)}` : '');

// Log slider 1.5×..100×, t in [0,1].
export const magFromPos = (t, lo = 1.5, hi = 100) => lo * Math.pow(hi / lo, t);
export const posFromMag = (m, lo = 1.5, hi = 100) => Math.log(m / lo) / Math.log(hi / lo);
export const roundMag = m => (m >= 10 ? Math.round(m) : Math.round(m * 10) / 10);

// SVG path for a series on a fixed y domain [0, yMax].
export function sparkPath(vals, w, h, yMax, pad = 2) {
  if (!vals || !vals.length) return '';
  const top = yMax || Math.max(...vals) || 1, dx = vals.length > 1 ? w / (vals.length - 1) : 0;
  return vals.map((v, i) => `${i ? 'L' : 'M'}${(i * dx).toFixed(1)},${(pad + (h - 2 * pad) * (1 - Math.min(v, top) / top)).toFixed(1)}`).join('');
}
// Index range of a date window inside a spark that ends on endDate (oldest first).
export function sparkWindow(len, endDate, from, to) {
  const d = iso => len - 1 - puzzleNoForDate(endDate, '1970-01-01') + puzzleNoForDate(iso, '1970-01-01');
  const a = Math.max(0, d(from)), b = Math.min(len - 1, d(to));
  return a <= b ? [a, b] : null;
}
export function median(a) {
  const s = a.filter(x => x != null).sort((x, y) => x - y), m = s.length >> 1;
  return s.length ? (s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2) : 0;
}
// Longest-run streak ending at `upto` over a set of completed puzzle numbers.
export function streakFrom(doneNs, upto) {
  const set = new Set(doneNs.map(Number));
  let k = set.has(upto) ? upto : upto - 1, c = 0;
  while (set.has(k)) { c++; k--; }
  return c;
}

// Cross-channel badge: never evidence, never a number (its baseline isn't ours, §12.2).
const XSRC = { gtrends: 'Google Trends', bsky: 'Bluesky', mastodon: 'Mastodon', gdelt_tv: 'TV news', autocomplete: 'search autocomplete (unofficial)', polymarket: 'Polymarket' };
export function crossText(x) {
  if (!x || !x.label) return '';
  return `${x.multiple != null || x.z != null ? 'Also spiked on' : 'Also on'} ${XSRC[x.source] || x.source || 'another channel'}: ${x.label}${WHEN[x.when] ? ' · ' + WHEN[x.when] : ''}`;
}
const WHEN = { before: 'earlier', alongside: 'same day', after: 'later' };

// Streak backup code (D-3): 'KO1.' + base64url(utf8 JSON) of ko.history + ko.calls.
const b64u = s => btoa(Array.from(new TextEncoder().encode(s), b => String.fromCharCode(b)).join('')).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
export function encodeBackup(hist, calls) {
  const h = {};
  Object.keys(hist || {}).map(Number).filter(n => n > 0).sort((a, b) => b - a).slice(0, 60)
    .forEach(n => { const e = hist[n]; h[n] = { grid: e.grid, score: e.score, max: e.max, mag: e.mag, s: e.s }; });
  return 'KO1.' + b64u(JSON.stringify({ h, c: calls || {} }));
}
export function decodeBackup(code) {
  try {
    const m = String(code).trim().match(/^KO1\.([A-Za-z0-9_-]{8,20000})$/);
    if (!m) return null;
    const bin = atob(m[1].replace(/-/g, '+').replace(/_/g, '/'));
    const o = JSON.parse(new TextDecoder().decode(Uint8Array.from(bin, c => c.charCodeAt(0))));
    const hist = {}, calls = {};
    for (const n in o.h || {}) { const e = o.h[n]; if (+n > 0 && e && typeof e.grid === 'string' && /^[🟩🟨🟥]{1,8}$/u.test(e.grid)) hist[+n] = { grid: e.grid, score: +e.score || 0, max: +e.max || 0, mag: +e.mag || null, s: +e.s || 0 }; }
    for (const n in o.c || {}) if (+n > 0 && /^Q\d+$/.test(o.c[n])) calls[+n] = o.c[n];
    return { hist, calls };
  } catch (e) { return null; }
}

// One-off calendar event (RFC 5545), UTC start, 15 min, alarm at start.
const icsT = ms => new Date(ms).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const icsEsc = s => String(s).replace(/[\\;,]/g, m => '\\' + m).replace(/\r?\n/g, '\\n');
// Fold at 75 octets, never inside a UTF-8 sequence.
const fold = l => { let o = '', k = 0; for (const c of l) { const b = new TextEncoder().encode(c).length; if (k + b > 75) o += '\r\n ', k = 1; o += c; k += b; } return o; };
export function icsEvent({ uid, start, title, url, desc = '', now = Date.now() }) {
  return ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//bensunter.com//Knock-On//EN', 'BEGIN:VEVENT', `UID:${uid}@bensunter.com`, `DTSTAMP:${icsT(now)}`,
    `DTSTART:${icsT(start)}`, `DTEND:${icsT(start + 9e5)}`, `SUMMARY:${icsEsc(title)}`, `DESCRIPTION:${icsEsc(desc ? desc + ' ' + url : url)}`, `URL:${url}`,
    'BEGIN:VALARM', 'ACTION:DISPLAY', `DESCRIPTION:${icsEsc(title)}`, 'TRIGGER:PT0M', 'END:VALARM', 'END:VEVENT', 'END:VCALENDAR', ''].map(fold).join('\r\n');
}
