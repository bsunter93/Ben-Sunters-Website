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
// SPEC §7: 2 points within 1.5× (e ≤ 0.176), 1 point within 3× (e ≤ 0.477).
export function magPoints(guess, actual) {
  if (!(guess > 0) || !(actual > 0)) return 0;
  const e = magErr(guess, actual);
  return e <= 0.176 ? 2 : e <= 0.477 ? 1 : 0;
}
export const magX = (guess, actual) => Math.pow(10, magErr(guess, actual));
export const maxScore = rounds => 2 * rounds + 2;
export function totalScore(codes, magPts) {
  return codes.reduce((a, c) => a + c, 0) + (magPts || 0);
}
export const gridEmoji = codes => codes.map(c => SQUARES[c]).join('');
export const firstTries = codes => codes.filter(c => c === 2).length;

// Rounds as the share path sees them: [{continues, seedEmoji, emoji, title}] from the puzzle
// plus the answer option id of each round (known on the client after hashing).
export function chainFromPuzzle(puzzle, answerIds) {
  return puzzle.rounds.map((r, k) => {
    const o = r.options.find(x => x.id === answerIds[k]) || {};
    const fresh = !r.continues && r.seed && !(k === 0 && r.seed.qid === puzzle.seed.qid);
    return { i: r.i, continues: !fresh, seedEmoji: fresh ? r.seed.emoji : null, seedTitle: fresh ? r.seed.title : null, emoji: o.emoji || '🔹', title: o.title || '', qid: o.qid, id: o.id, parent: r.parent };
  });
}
// SPEC §3 {path}: seed emoji, each answer emoji joined with →; a fresh ripple is joined with ' · ' and
// starts with that round's seed emoji, e.g. 👤→📍→🎬 · 🎵→🏅
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
  const x = magX(guess, actual);
  return x <= 3 ? `📏 last hop within ${x.toFixed(1)}×` : '';
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
// Crowd rarity, only when it is actually rare (< 50%), from players' picks (≥30 players only):
// the rarest round the player found first try, else the round the fewest players found at all.
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
// Call It closes at the earlier of 07:30 UTC on puzzle_date+1 and 00:00 UTC after window_start (contract README).
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
