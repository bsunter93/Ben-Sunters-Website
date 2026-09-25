// node ripples/tools/test-lib.mjs  (exits non-zero on any failure)
// Checks lib.js against the W1 fixture: SPEC §3 share text byte for byte, scoring and helpers.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as L from '../lib.js';

const root = fileURLToPath(new URL('..', import.meta.url));
const fx = f => JSON.parse(readFileSync(root + 'contract/fixtures/' + f, 'utf8'));
const puzzle = fx('puzzle-0.json'), reveal = fx('reveal-0.json');
let fails = 0, passes = 0;
const eq = (name, got, want) => {
  if (got === want) { passes++; return; }
  fails++; console.error(`FAIL ${name}\n  got:  ${JSON.stringify(got)}\n  want: ${JSON.stringify(want)}`);
};

// Answers come from the client-side hash check, not from the reveal file.
const answers = [];
for (const r of puzzle.rounds) answers.push(await L.findAnswer(puzzle.n, r));
eq('answers via answer_h', answers.join(''), reveal.rounds.map(r => r.answer).join(''));
eq('answerCheck negative', await L.answerCheck(0, 1, 'Q999990011', puzzle.rounds[0].answer_h), false);
eq('sha256Hex', await L.sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');

const chain = L.chainFromPuzzle(puzzle, answers);
const path = L.pathEmoji(puzzle.seed.emoji, chain);
eq('path with fresh-ripple break', path, '👤→📍→🎬 · 🎵→🏅');
const actual = reveal.final_multiple;
const base = { n: puzzle.n, seedTitle: puzzle.seed.title, path };

// 1. All correct, streak 5, slider exact.
eq('scenario 1: all correct, streak 5', L.shareText({ ...base, codes: [2, 2, 2], streak: 5, guess: 3.8, actual }),
  'Knock-On #0 · Test Seed Article\n👤→📍→🎬 · 🎵→🏅\n🟩🟩🟩 8/8 🔥5\n📏 last hop within 1.0×\nbensunter.com/ripples/0/3');
// 2. Mixed, fresh-ripple break, streak 1 (no suffix), slider within 1.5× (2 points, line shown).
eq('scenario 2: mixed', L.shareText({ ...base, codes: [2, 1, 0], streak: 1, guess: 5, actual }),
  'Knock-On #0 · Test Seed Article\n👤→📍→🎬 · 🎵→🏅\n🟩🟨🟥 5/8\n📏 last hop within 1.3×\nbensunter.com/ripples/0/1');
// 2b. D-2: within 2× but not 1.5× scores 1 point and the mag line is omitted.
eq('scenario 2b: within 2x, no line', L.shareText({ ...base, codes: [2, 1, 0], streak: 2, guess: 6, actual }),
  'Knock-On #0 · Test Seed Article\n👤→📍→🎬 · 🎵→🏅\n🟩🟨🟥 4/8 🔥2\nbensunter.com/ripples/0/1');
// 3. All missed, slider outside 3× (and 2×): mag line omitted, 0 slider points.
eq('scenario 3: missed, slider outside 3x', L.shareText({ ...base, codes: [0, 0, 0], streak: 0, guess: 50, actual }),
  'Knock-On #0 · Test Seed Article\n👤→📍→🎬 · 🎵→🏅\n🟥🟥🟥 0/8\nbensunter.com/ripples/0/0');
// SPEC §3 illustrative example (4 rounds, all continuing). The spec's 6/10 is illustrative and
// inconsistent (🟩🟨🟩🟥 = 5, plus 2 for a guess within 1.4× = 7), so the arithmetic is asserted.
eq('spec example', L.shareText({ n: 12, seedTitle: 'Lizzie Borden', path: '👤→📍→🎬→🍎', codes: [2, 1, 2, 0], streak: 3, guess: 1.4 * 5, actual: 5 }),
  'Knock-On #12 · Lizzie Borden\n👤→📍→🎬→🍎\n🟩🟨🟩🟥 7/10 🔥3\n📏 last hop within 1.4×\nbensunter.com/ripples/12/2');
eq('practice url', L.shareText({ n: -3, seedTitle: 'X', path: '👤→📍', codes: [2], guess: null }).split('\n').pop(), 'bensunter.com/ripples/?p=-3');

// Scoring (SPEC §7).
eq('scoreRound first', L.scoreRound(['c'], 'c'), 2);
eq('scoreRound second', L.scoreRound(['a', 'c'], 'c'), 1);
eq('scoreRound miss', L.scoreRound(['a', 'b'], 'c'), 0);
// OWNER_DECISIONS D-2: 2 within 1.5×, 1 within 2× (was 3×), else 0.
eq('magPoints 1.47x', L.magPoints(5.6, 3.8), 2);
eq('magPoints 1.58x', L.magPoints(6, 3.8), 1);
eq('magPoints 1.97x', L.magPoints(7.5, 3.8), 1);
eq('magPoints 2.1x', L.magPoints(8, 3.8), 0);
eq('magPoints 2.1x under', L.magPoints(1.8, 3.8), 0);
eq('magPoints 3.1x', L.magPoints(12, 3.8), 0);
eq('magLine 1.497x shown', L.magLine(5.69, 3.8), '📏 last hop within 1.5×');
// log10(1.5) = 0.17609 > 0.176, so exactly 1.5× (and 1.50–1.549×) scores 1 point and the line is omitted.
eq('magLine exactly 1.5x omitted', L.magLine(5.7, 3.8), '');
eq('magPoints exactly 1.5x = 1', L.magPoints(5.7, 3.8), 1);
eq('magLine 1.54x omitted', L.magLine(3.8 * 1.54, 3.8), '');
eq('magLine 1.6x omitted', L.magLine(6, 3.8), '');
eq('maxScore', L.maxScore(4), 10);
eq('gridEmoji', L.gridEmoji([2, 1, 0, 2]), '🟩🟨🟥🟩');
eq('fmtMultiple small', L.fmtMultiple(6.2), '6.2×');
eq('fmtMultiple big', L.fmtMultiple(41.2), '41×');
eq('fmtMultiple 1dp', L.fmtMultiple(1.04), '1.0×');
eq('fmtBiggestIn', L.fmtBiggestIn(puzzle.seed), 'Biggest day in 1,240 days');
eq('fmtBiggestIn records', L.fmtBiggestIn({ biggest_since_records: true }), 'Biggest day since records began, Jul 2015');
eq('fmtTiming +1', L.fmtTiming(1, 'after'), '+1 day after');
eq('fmtTiming 0', L.fmtTiming(0, 'alongside'), 'alongside');
eq('fmtFluke', L.fmtFluke(reveal.rounds[0].evidence), 'About 1 in 12 passes like this are chance');
eq('fmtFluke 50+', L.fmtFluke(reveal.rounds[1].evidence), 'About 1 in 50+ passes like this are chance');
eq('fmtFluke warming', L.fmtFluke(reveal.rounds[2].evidence), 'Fluke meter warming up');
eq('percentileLine', L.percentileLine({ percentile: 82 }), 'You scored higher than 82% of players');
eq('percentileLine null', L.percentileLine({ percentile: null }), '');
eq('puzzleNoForDate launch', L.puzzleNoForDate('2026-09-26', '2026-09-25'), 1);
eq('puzzleNoForDate', L.puzzleNoForDate('2026-10-07', '2026-09-25'), 12);
eq('currentPuzzleDate before 07:30', L.currentPuzzleDate(Date.parse('2026-09-26T07:29:00Z')), '2026-09-25');
eq('currentPuzzleDate after 07:30', L.currentPuzzleDate(Date.parse('2026-09-26T07:30:00Z')), '2026-09-26');
eq('timeToNext', L.timeToNext(Date.parse('2026-09-25T05:00:00Z')), 2.5 * 36e5);
eq('timeToNext wraps', L.timeToNext(Date.parse('2026-09-25T08:00:00Z')), 23.5 * 36e5);
eq('fmtCountdown', L.fmtCountdown(14 * 36e5 + 22 * 6e4), '14h 22m');
eq('callClosesAt spec window', new Date(L.callClosesAt('2026-09-25', '2026-09-25')).toISOString(), '2026-09-26T00:00:00.000Z');
eq('callClosesAt shifted window', new Date(L.callClosesAt('2026-09-25', '2026-09-26')).toISOString(), '2026-09-26T07:30:00.000Z');
eq('slider ends', [L.magFromPos(0), Math.round(L.magFromPos(1))].join(), '1.5,100');
eq('slider inverse', Math.round(L.posFromMag(L.magFromPos(0.37)) * 1000), 370);
eq('streak', L.streakFrom([3, 4, 5, 7], 7), 1);
eq('streak unplayed today', L.streakFrom([3, 4, 5], 6), 3);
eq('sparkWindow', JSON.stringify(L.sparkWindow(90, '2026-09-24', puzzle.seed.baseline.from, puzzle.seed.baseline.to)), '[0,65]');
eq('bellyFlop', L.bellyFlopText({ title: 'T', splash_multiple: 22, quadrant: 'belly_flop', sensitive: false }), '💥 Belly Flop: T. 22× normal readers, no measured wake on Wikipedia. bensunter.com/ripples/');
eq('bellyFlop sensitive', L.bellyFlopText({ title: 'T', splash_multiple: 22, quadrant: 'belly_flop', sensitive: true }), '');

eq('fmtDate', L.fmtDate('2026-09-25'), 'Fri 25 Sep');
eq('fmtMonth', L.fmtMonth('2026-08'), 'Aug 2026');
const st = { shown: true, rounds: [{ i: 1, first_try_pct: 62, found_pct: 88 }, { i: 2, first_try_pct: 41, found_pct: 70 }, { i: 3, first_try_pct: 9, found_pct: 35 }] };
eq('rarity: rarest first-try round', L.rarityLine(st, [2, 2, 2]), 'Only 9% of players found round 3 first try');
eq('rarity: not rare is omitted', L.rarityLine(st, [2, 0, 0]), '');
eq('rarity: found at all', L.rarityLine(st, [0, 0, 1]), 'Only 35% of players found round 3');
eq('rarity hidden under 30', L.rarityLine({ shown: false, rounds: null }, [2, 2, 2]), '');
// Cross badges (contract extension): corroboration wording, numbers only from the item.
const xs = [puzzle.seed.cross[0], reveal.rounds[0].evidence.cross[0], reveal.rounds[2].evidence.cross[0]].map(L.crossText);
eq('cross listing', xs[0], 'Also on Google Trends: TEST: listed in Google Trends daily trending searches (US) · earlier');
eq('cross z only', xs[1], 'Also spiked on TV news: TEST: mentioned on TV news captions · later');
eq('cross multiple not printed', xs[2], 'Also spiked on Mastodon: TEST: trending hashtag on Mastodon · same day');
eq('cross never prints a number', xs.some(x => /\d(\.\d)?×|z ?=/.test(x)), false);
eq('cross autocomplete tagged unofficial', L.crossText({ source: 'autocomplete', label: 'TEST', multiple: null, z: null, when: null }), 'Also on search autocomplete (unofficial): TEST');
eq('cross no causal words', xs.some(x => /caus|drove|flood/i.test(x)), false);

// Backup code round trip (D-3) and rejection of junk.
const hist = { 12: { grid: '🟩🟨🟥', score: 5, max: 8, mag: 4.2, s: 1, picks: [['a']] }, 13: { grid: '🟩🟩🟩🟩', score: 10, max: 10, mag: 3, s: 4 }, [-3]: { grid: '🟩', score: 2, max: 4 } };
const code = L.encodeBackup(hist, { 12: 'Q42', 13: 'bad' });
const back = L.decodeBackup(code);
eq('backup prefix', code.slice(0, 4), 'KO1.');
eq('backup restores live history', JSON.stringify(Object.keys(back.hist)), '["12","13"]');
eq('backup grid', back.hist[13].grid, '🟩🟩🟩🟩');
eq('backup drops bad calls', JSON.stringify(back.calls), '{"12":"Q42"}');
eq('backup junk', L.decodeBackup('KO1.<script>'), null);
eq('backup wrong prefix', L.decodeBackup('hello'), null);

// Calendar event: CRLF, UTC times, escaped text, folded lines.
const ics = L.icsEvent({ uid: 'ko-call-12', start: Date.parse('2026-10-15T08:00:00Z'), title: 'Knock-On: your call on A, B; C resolves', url: 'https://bensunter.com/ripples/12/?src=ics', now: Date.parse('2026-10-07T09:00:00Z') });
eq('ics start', ics.includes('\r\nDTSTART:20261015T080000Z\r\n'), true);
eq('ics escape', ics.includes('SUMMARY:Knock-On: your call on A\\, B\\; C resolves'), true);
eq('ics fold', ics.split('\r\n').every(l => l.length <= 75), true);
eq('ics ends', ics.endsWith('END:VCALENDAR\r\n'), true);
// Non-ASCII titles: fold by octets (RFC 5545 §3.1), never splitting a character; unfolding restores the text.
const title2 = 'Knock-On: 🎬 Zoë Saldaña → Évora café, 東京タワー 🗼 résout ' + '✓'.repeat(40);
const ics2 = L.icsEvent({ uid: 'ko-call-13', start: Date.parse('2026-10-16T08:00:00Z'), title: title2, url: 'https://bensunter.com/ripples/13/?src=ics', now: Date.parse('2026-10-08T09:00:00Z') });
eq('ics fold octets', ics2.split('\r\n').every(l => Buffer.byteLength(l, 'utf8') <= 75), true);
eq('ics fold no split char', ics2.includes('\uFFFD'), false);
eq('ics unfold', ics2.replace(/\r\n /g, '').includes('SUMMARY:' + title2.replace(/,/g, '\\,') + '\r\n'), true);
eq('ics fold ascii still 75', Math.max(...ics.split('\r\n').map(l => l.length)) <= 75, true);

console.log(`${passes} passed, ${fails} failed`);
process.exit(fails ? 1 : 0);
