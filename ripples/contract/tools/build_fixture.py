#!/usr/bin/env python3
"""Build the n=0 TEST fixture (deterministic) for Knock-On v5.

Writes ripples/contract/fixtures/*.json and ripples/contract/sql/03_fixture_n0.sql.
Every title says "Test"; every QID is in the fake range Q99999xxxx; every URL outside
en.wikipedia.org is example.com. Nothing here is real data.

Usage: python3 ripples/contract/tools/build_fixture.py
"""
import hashlib, json, math, os, random
from datetime import date, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                      # ripples/contract
FIX = os.path.join(ROOT, 'fixtures')
SQL = os.path.join(ROOT, 'sql')

N = 0
EPOCH = date(2026, 9, 25)
PUZZLE_DATE = EPOCH                               # fixture uses the epoch date
AS_OF = PUZZLE_DATE - timedelta(days=1)           # data_date
rng = random.Random(20260925)

EMOJI = {'person': '👤', 'place': '📍', 'film_tv': '🎬', 'music': '🎵', 'sport': '🏅',
         'science_health': '🧬', 'tech': '💻', 'business': '🏢', 'politics_law': '⚖️',
         'food_drink': '🍎', 'nature_weather': '🌦', 'history_culture': '🏛', 'other': '🔹'}


def d(x):
    return x.isoformat()


def wiki(title):
    return 'https://en.wikipedia.org/wiki/' + title.replace('%', '%25').replace(' ', '_') \
        .replace('?', '%3F').replace('#', '%23').replace('"', '%22')


def answer_h(n, i, qid):
    return hashlib.sha256(f'{n}|{i}|{qid}'.encode('utf-8')).hexdigest()


def flat_spark(median, days=90, noise=0.08):
    return [max(0, int(round(median * math.exp(rng.gauss(0, noise))))) for _ in range(days)]


def spike_spark(median, peak_mult, spike_at_from_end, days=90, decay=0.55, noise=0.08):
    s = flat_spark(median, days, noise)
    start = days - spike_at_from_end
    for k in range(start, days):
        m = 1 + (peak_mult - 1) * (decay ** (k - start))
        s[k] = int(round(median * m * math.exp(rng.gauss(0, 0.03))))
    return s


def opt(oid, qid, title, cat, desc):
    return {'id': oid, 'qid': qid, 'title': title, 'emoji': EMOJI[cat], 'desc': desc}


def calm(o, median):
    return {'id': o['id'], 'qid': o['qid'], 'url': wiki(o['title']),
            'multiple': round(rng.uniform(0.85, 1.15), 2), 'z': round(rng.uniform(-0.6, 0.7), 2),
            'calm': True, 'spark': flat_spark(median), 'median': median,
            'lag_days': None, 'timing': None}


def hit(o, median, multiple, z, lag, spike_from_end):
    return {'id': o['id'], 'qid': o['qid'], 'url': wiki(o['title']),
            'multiple': multiple, 'z': z, 'calm': False,
            'spark': spike_spark(median, multiple, spike_from_end), 'median': median,
            'lag_days': lag, 'timing': 'alongside' if lag == 0 else 'after'}


# ---------------------------------------------------------------- seed
seed_onset = date(2026, 9, 21)
seed = {
    'qid': 'Q999990001', 'title': 'Test Seed Article', 'emoji': EMOJI['person'], 'category': 'person',
    'desc': 'TEST fixture seed article (not real data)',
    'multiple': 41.2, 'biggest_in_days': 1240, 'biggest_since_records': False, 'langs': 6,
    'onset': d(seed_onset),
    'spark': spike_spark(2100, 41.2, 4, decay=0.7),
    'baseline': {'from': d(seed_onset - timedelta(days=111)), 'to': d(seed_onset - timedelta(days=21)), 'median': 2100},
    'why': [
        {'title': 'TEST news headline one (fixture)', 'source': 'Example News (TEST)', 'url': 'https://example.com/test-news-1'},
        {'title': 'TEST news headline two (fixture)', 'source': 'Example Daily (TEST)', 'url': 'https://example.com/test-news-2'},
    ],
    'badges': ['gtrends:US', 'bsky'],
    'cross': [
        {'source': 'gtrends', 'label': 'TEST: listed in Google Trends daily trending searches (US)', 'multiple': None, 'z': None, 'when': 'before'},
        {'source': 'bsky', 'label': 'TEST: trending on Bluesky', 'multiple': None, 'z': None, 'when': 'alongside'},
    ],
}

# ---------------------------------------------------------------- round 1 (continues from seed; answer c; flowed)
r1 = [opt('a', 'Q999990011', 'Test Decoy Place A', 'place', 'TEST decoy: a calm linked place page'),
      opt('b', 'Q999990012', 'Test Decoy Film B', 'film_tv', 'TEST decoy: a calm linked film page'),
      opt('c', 'Q999990013', 'Test Answer Place One', 'place', 'TEST answer: a linked place page that spiked'),
      opt('d', 'Q999990014', 'Test Decoy Place D', 'place', 'TEST decoy: another calm linked place page')]
# ---------------------------------------------------------------- round 2 (continues from round-1 answer; answer a; shared-trigger stop)
r2 = [opt('a', 'Q999990021', 'Test Answer Film Two', 'film_tv', 'TEST answer: a linked film page that spiked alongside'),
      opt('b', 'Q999990022', 'Test Decoy Film E', 'film_tv', 'TEST decoy: a calm linked film page'),
      opt('c', 'Q999990023', 'Test Decoy Film F', 'film_tv', 'TEST decoy: another calm linked film page'),
      opt('d', 'Q999990024', 'Test Decoy Music G', 'music', 'TEST decoy: a calm linked music page')]
# ---------------------------------------------------------------- round 3 (fresh ripple from a second seed; answer d; fluke warming)
seed2 = {'qid': 'Q999990002', 'title': 'Test Second Seed', 'emoji': EMOJI['music'], 'multiple': 18.5, 'biggest_in_days': 400}
r3 = [opt('a', 'Q999990031', 'Test Decoy Sport H', 'sport', 'TEST decoy: a calm linked sports page'),
      opt('b', 'Q999990032', 'Test Decoy Sport I', 'sport', 'TEST decoy: another calm linked sports page'),
      opt('c', 'Q999990033', 'Test Decoy Person J', 'person', 'TEST decoy: a calm linked biography'),
      opt('d', 'Q999990034', 'Test Answer Sport Three', 'sport', 'TEST answer: a linked sports page that spiked after')]

answers = [{'i': 1, 'qid': 'Q999990013', 'option_id': 'c'},
           {'i': 2, 'qid': 'Q999990021', 'option_id': 'a'},
           {'i': 3, 'qid': 'Q999990034', 'option_id': 'd'}]
FINAL_MULTIPLE = 3.8

callit_opts = [
    {'qid': 'Q999990041', 'title': 'Test Call Option Hit', 'emoji': EMOJI['film_tv'], 'category': 'film_tv',
     'desc': 'TEST Call It option (resolved: hit)', 'baseline_median': 5200, 'model_p': 0.11,
     'outcome': 'hit', 'max_z': 4.2},
    {'qid': 'Q999990042', 'title': 'Test Call Option Miss', 'emoji': EMOJI['film_tv'], 'category': 'film_tv',
     'desc': 'TEST Call It option (resolved: miss)', 'baseline_median': 3100, 'model_p': 0.08,
     'outcome': 'miss', 'max_z': 1.1},
    {'qid': 'Q999990043', 'title': 'Test Call Option Pending One', 'emoji': EMOJI['history_culture'],
     'category': 'history_culture', 'desc': 'TEST Call It option (pending)', 'baseline_median': 2400,
     'model_p': 0.09, 'outcome': 'pending', 'max_z': None},
    {'qid': 'Q999990044', 'title': 'Test Call Option Pending Two', 'emoji': EMOJI['science_health'],
     'category': 'science_health', 'desc': 'TEST Call It option (pending)', 'baseline_median': 2050,
     'model_p': 0.07, 'outcome': 'pending', 'max_z': None},
]
win_start = PUZZLE_DATE
win_end = PUZZLE_DATE + timedelta(days=6)

payload = {
    'v': 1, 'n': N, 'kind': 'fixture', 'date': d(PUZZLE_DATE), 'data_date': d(AS_OF), 'from_date': None,
    'status': 'fixture', 'method': '5.0',
    'seed': seed,
    'rounds': [
        {'i': 1, 'continues': True, 'parent': {'qid': seed['qid'], 'title': seed['title'], 'emoji': seed['emoji']},
         'seed': None, 'options': r1, 'answer_h': answer_h(N, 1, 'Q999990013')},
        {'i': 2, 'continues': True, 'parent': {'qid': 'Q999990013', 'title': 'Test Answer Place One', 'emoji': EMOJI['place']},
         'seed': None, 'options': r2, 'answer_h': answer_h(N, 2, 'Q999990021')},
        {'i': 3, 'continues': False, 'parent': {'qid': seed2['qid'], 'title': seed2['title'], 'emoji': seed2['emoji']},
         'seed': seed2, 'options': r3, 'answer_h': answer_h(N, 3, 'Q999990034')},
    ],
    'final': {'round': 3, 'mag_min': 1.5, 'mag_max': 100},
    'callit': {'window_start': d(win_start), 'window_end': d(win_end),
               'options': [{k: c[k] for k in ('qid', 'title', 'emoji', 'desc')} for c in callit_opts]},
    'headline': {'text': 'TEST fixture puzzle: three hops of made-up data', 'source': 'template'},
}

reveal = {
    'v': 1, 'n': N,
    'rounds': [
        {'i': 1, 'answer': 'c', 'answer_qid': 'Q999990013',
         'options': [calm(r1[0], 900), calm(r1[1], 1300), hit(r1[2], 800, 6.2, 7.1, 1, 3), calm(r1[3], 700)],
         'evidence': {'linked': True, 'clickstream': {'month': '2026-08', 'clicks': 12345, 'rank': 3},
                      'fluke': 0.08, 'fluke_1_in': 12, 'fluke_warming': False, 'p_time': 0.026, 'placebos': 38,
                      'split_ok': True, 'badge': 'flowed',
                      'cross': [{'source': 'gdelt_tv', 'label': 'TEST: mentioned on TV news captions', 'multiple': None,
                                 'z': 3.4, 'when': 'after'}]},
         'caption': {'text': 'TEST caption: Test Answer Place One is linked from Test Seed Article; it ran 6.2x its normal readers the day after.',
                     'source': 'template'},
         'shared_trigger_stop': False},
        {'i': 2, 'answer': 'a', 'answer_qid': 'Q999990021',
         'options': [hit(r2[0], 1500, 2.4, 4.3, 0, 2), calm(r2[1], 1100), calm(r2[2], 2600), calm(r2[3], 1900)],
         'evidence': {'linked': True, 'clickstream': None,
                      'fluke': 0.02, 'fluke_1_in': 50, 'fluke_warming': False, 'p_time': 0.03, 'placebos': 38,
                      'split_ok': True, 'badge': 'spiked_after', 'cross': []},
         'caption': {'text': 'TEST caption from a Wikipedia short description (fixture).', 'source': 'wikipedia'},
         'shared_trigger_stop': True},
        {'i': 3, 'answer': 'd', 'answer_qid': 'Q999990034',
         'options': [calm(r3[0], 2800), calm(r3[1], 3500), calm(r3[2], 4100), hit(r3[3], 3000, FINAL_MULTIPLE, 5.0, 2, 2)],
         'evidence': {'linked': True, 'clickstream': None,
                      'fluke': None, 'fluke_1_in': None, 'fluke_warming': True, 'p_time': 0.04, 'placebos': 36,
                      'split_ok': True, 'badge': 'spiked_after',
                      'cross': [{'source': 'mastodon', 'label': 'TEST: trending hashtag on Mastodon', 'multiple': 4.5,
                                 'z': None, 'when': 'alongside'}]},
         'caption': {'text': 'TEST AI caption: this sports page and the second test seed likely drew attention from the same news story.',
                     'source': 'ai'},
         'shared_trigger_stop': False},
    ],
    'end': {'reason': 'evidence_ended', 'text': 'The measured trail ends here.'},
    'final_multiple': FINAL_MULTIPLE,
}


def board_row(qid, title, cat, splash, big, wake, quad, sensitive=False, cross=None):
    return {'qid': qid, 'title': title, 'emoji': EMOJI[cat], 'category': cat, 'splash_multiple': splash,
            'biggest_in_days': big, 'wake_k': wake, 'wake_of': 20, 'quadrant': quad, 'sensitive': sensitive,
            'spark': spike_spark(1000, splash, 4, days=30, decay=0.7), 'cross': cross or []}


board = {'n': N, 'date': d(PUZZLE_DATE), 'trends': [
    board_row('Q999990001', 'Test Seed Article', 'person', 41.2, 1240, 5, 'big_wave',
              cross=[{'source': 'gtrends', 'label': 'TEST: listed in Google Trends daily trending searches (US)', 'multiple': None, 'z': None, 'when': 'before'}]),
    board_row('Q999990002', 'Test Second Seed', 'music', 18.5, 400, 3, 'big_wave'),
    board_row('Q999990051', 'Test Board Sleeper', 'science_health', 6.1, 95, 4, 'sleeper'),
    board_row('Q999990052', 'Test Board Belly Flop', 'tech', 22.0, 610, 0, 'belly_flop'),
    board_row('Q999990053', 'Test Board Ripple', 'business', 4.2, 60, 1, 'ripple'),
    board_row('Q999990054', 'Test Board Storm (sensitive)', 'nature_weather', 14.2, 700, 3, None, sensitive=True),
]}

# ---------------------------------------------------------------- derived RPC-shaped fixtures
def callit_payload():
    return {'n': N, 'window_start': d(win_start), 'window_end': d(win_end),
            'resolves_on': d(win_start + timedelta(days=8)), 'model': 'v0 base rate',
            'options': [{'qid': c['qid'], 'title': c['title'], 'emoji': c['emoji'], 'model_p': c['model_p'],
                         'crowd_pct': None, 'outcome': c['outcome'],
                         'max_z': c['max_z'] if c['outcome'] != 'pending' else None,
                         'url': wiki(c['title']) if c['outcome'] != 'pending' else None} for c in callit_opts]}


stats = {'n': N, 'players': 0, 'shown': False, 'rounds': None, 'score_hist': None, 'mag_median_x': None, 'you': None}
stats_shown_sample = {  # synthetic, NOT from the DB: exercises the >=30 players UI state
    '_comment': 'TEST sample: synthetic StatsPayload with shown=true for UI development; not produced by the DB fixture',
    'n': N, 'players': 1234, 'shown': True,
    'rounds': [{'i': 1, 'first_try_pct': 62, 'found_pct': 88, 'split': {'a': 10, 'b': 8, 'c': 62, 'd': 20}},
               {'i': 2, 'first_try_pct': 41, 'found_pct': 70, 'split': {'a': 41, 'b': 22, 'c': 25, 'd': 12}},
               {'i': 3, 'first_try_pct': 9, 'found_pct': 35, 'split': {'a': 30, 'b': 28, 'c': 33, 'd': 9}}],
    'score_hist': [12, 40, 88, 150, 210, 260, 230, 160, 84],
    'mag_median_x': 1.9, 'you': {'score': 5, 'max': 8, 'percentile': 57}}

archive = [{'n': N, 'date': d(PUZZLE_DATE), 'from_date': None, 'kind': 'fixture',
            'seed_title': seed['title'], 'seed_emoji': seed['emoji'], 'rounds': 3,
            'path': seed['emoji'] + EMOJI['place'] + EMOJI['film_tv'] + '·' + seed2['emoji'] + EMOJI['sport']}]

latest_delayed = {'n': None, 'date': d(PUZZLE_DATE), 'status': 'delayed', 'puzzle': None,
                  'next_at': '2026-09-26T07:30:00+00:00'}
latest_published_sample = {
    '_comment': 'TEST sample: latest.json as it looks once a puzzle is published (puzzle = fixture payload)',
    'n': N, 'date': d(PUZZLE_DATE), 'status': 'published', 'puzzle': payload,
    'next_at': '2026-09-26T07:30:00+00:00'}

brief_sample = {
    '_comment': 'TEST sample: BriefPayload built from the fixture; the DB never returns fixture rows from ripples_brief',
    'from': d(PUZZLE_DATE - timedelta(days=7)), 'to': d(PUZZLE_DATE - timedelta(days=1)), 'category': None,
    'intro': {'text': 'TEST intro paragraph (fixture). Labeled AI-written on the page.', 'source': 'ai'},
    'reconstructed': False,
    'items': [
        {'n': N, 'date': d(PUZZLE_DATE), 'seed_title': 'Test Seed Article', 'hop_title': 'Test Answer Place One',
         'category': 'place', 'emoji': EMOJI['place'], 'multiple': 6.2, 'fluke_1_in': 12, 'lag_days': 1, 'timing': 'after'},
        {'n': N, 'date': d(PUZZLE_DATE), 'seed_title': 'Test Seed Article', 'hop_title': 'Test Answer Film Two',
         'category': 'film_tv', 'emoji': EMOJI['film_tv'], 'multiple': 2.4, 'fluke_1_in': 50, 'lag_days': 0, 'timing': 'alongside'},
        {'n': N, 'date': d(PUZZLE_DATE), 'seed_title': 'Test Second Seed', 'hop_title': 'Test Answer Sport Three',
         'category': 'sport', 'emoji': EMOJI['sport'], 'multiple': 3.8, 'fluke_1_in': None, 'lag_days': 2, 'timing': 'after'}]}

health_sample = {'_comment': 'TEST sample: ripples_health() shape', 'latest_n': None, 'published_at': None, 'stale': True,
                 'expected_n': 0, 'stage': None, 'wm_calls': None, 'errors': None, 'clickstream_month': None}

og_data = {'n': N, 'kind': 'fixture', 'status': 'fixture', 'date': d(PUZZLE_DATE), 'from_date': None, 'past': False,
           'seed': {'title': seed['title'], 'emoji': seed['emoji'], 'biggest_in_days': 1240, 'since_records': False,
                    'multiple': 41.2, 'langs': 6},
           'rounds': [{'i': 1, 'continues': True, 'seed_emoji': None, 'emoji': EMOJI['place'], 'title': 'Test Answer Place One', 'multiple': 6.2},
                      {'i': 2, 'continues': True, 'seed_emoji': None, 'emoji': EMOJI['film_tv'], 'title': 'Test Answer Film Two', 'multiple': 2.4},
                      {'i': 3, 'continues': False, 'seed_emoji': seed2['emoji'], 'emoji': EMOJI['sport'], 'title': 'Test Answer Sport Three', 'multiple': 3.8}],
           'R': 3}


def dump(name, obj):
    with open(os.path.join(FIX, name), 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write('\n')


def sqlq(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    os.makedirs(FIX, exist_ok=True)
    dump('puzzle-0.json', payload)
    dump('reveal-0.json', reveal)
    dump('board-0.json', board)
    dump('callit-0.json', callit_payload())
    dump('stats-0.json', stats)
    dump('archive-fixture.json', archive)
    dump('latest.json', latest_delayed)
    dump('og-data-0.json', og_data)
    dump('answers-0.json', answers)
    dump('stats-0.sample-shown.json', stats_shown_sample)
    dump('latest.sample-published.json', latest_published_sample)
    dump('brief.sample.json', brief_sample)
    dump('health.sample.json', health_sample)

    js = lambda o: sqlq(json.dumps(o, ensure_ascii=False, sort_keys=True))
    lines = [
        '-- Knock-On v5 / W1: TEST fixture n=0 (generated by ripples/contract/tools/build_fixture.py; do not edit by hand)',
        'begin;',
        'delete from ripples.callit where n = 0;',
        'delete from ripples.puzzles where n = 0;',
        'insert into ripples.puzzles (n, kind, puzzle_date, data_date, from_date, status, payload, reveal, board, answers, final_multiple, chain_id, built_at, published_at)',
        f"values (0, 'fixture', {sqlq(d(PUZZLE_DATE))}, {sqlq(d(AS_OF))}, null, 'fixture', {js(payload)}::jsonb, {js(reveal)}::jsonb, {js(board)}::jsonb, {js(answers)}::jsonb, {FINAL_MULTIPLE}, null, now(), null);",
    ]
    for c in callit_opts:
        resolved = 'now()' if c['outcome'] != 'pending' else 'null'
        mz = 'null' if c['max_z'] is None else str(c['max_z'])
        lines.append(
            'insert into ripples.callit (n, qid, title, emoji, category, baseline_median, model_p, window_start, window_end, outcome, max_z, resolved_at) values '
            f"(0, {sqlq(c['qid'])}, {sqlq(c['title'])}, {sqlq(c['emoji'])}, {sqlq(c['category'])}, {c['baseline_median']}, {c['model_p']}, "
            f"{sqlq(d(win_start))}, {sqlq(d(win_end))}, {sqlq(c['outcome'])}, {mz}, {resolved});")
    lines.append('commit;')
    with open(os.path.join(SQL, '03_fixture_n0.sql'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print('fixtures written to', FIX)


if __name__ == '__main__':
    main()
