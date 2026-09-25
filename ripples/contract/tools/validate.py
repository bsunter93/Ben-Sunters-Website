#!/usr/bin/env python3
"""Dependency-free validator for the Knock-On v5 contract.

  python3 ripples/contract/tools/validate.py                 # validate every fixture + cross-checks
  python3 ripples/contract/tools/validate.py SCHEMA FILE     # validate one JSON file against one schema
  python3 ripples/contract/tools/validate.py --md5 FILE      # md5 of the file in Postgres jsonb::text form

Supports the JSON-Schema subset used by the contract: type (incl. lists), const, enum, pattern,
minLength/maxLength, minimum/maximum, required, properties, additionalProperties:false, items,
minItems/maxItems, anyOf, $ref (local #/$defs/.. and sibling files). A top-level "_comment" key
(used by *.sample*.json files) is ignored.

--md5 lets you prove a DB value equals a file without copying it:
  select md5(public.ripples_puzzle(0)::text);   -- compare with: validate.py --md5 fixtures/puzzle-0.json
"""
import hashlib, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
_cache = {}


def load_schema(name):
    if name not in _cache:
        with open(os.path.join(ROOT, name), encoding='utf-8') as f:
            _cache[name] = json.load(f)
    return _cache[name]


def resolve(ref, base):
    file, _, frag = ref.partition('#')
    doc_name = file or base
    node = load_schema(doc_name)
    if frag:
        for part in frag.strip('/').split('/'):
            node = node[part]
    return node, doc_name


def is_type(v, t):
    return {
        'null': v is None, 'boolean': isinstance(v, bool),
        'integer': isinstance(v, int) and not isinstance(v, bool) or (isinstance(v, float) and v.is_integer() and False),
        'number': isinstance(v, (int, float)) and not isinstance(v, bool),
        'string': isinstance(v, str), 'array': isinstance(v, list), 'object': isinstance(v, dict),
    }[t]


def validate(v, s, base, path, errs):
    if '$ref' in s:
        target, doc = resolve(s['$ref'], base)
        validate(v, target, doc, path, errs)
        rest = {k: x for k, x in s.items() if k != '$ref'}
        if rest:
            validate(v, rest, base, path, errs)
        return
    if 'anyOf' in s:
        ok = False
        for sub in s['anyOf']:
            e = []
            validate(v, sub, base, path, e)
            if not e:
                ok = True
                break
        if not ok:
            errs.append(f'{path}: matches no anyOf branch (value={json.dumps(v, ensure_ascii=False)[:80]})')
        return
    if 'type' in s:
        ts = s['type'] if isinstance(s['type'], list) else [s['type']]
        if not any(is_type(v, t) for t in ts):
            errs.append(f'{path}: expected {ts}, got {type(v).__name__}')
            return
    if 'const' in s and v != s['const']:
        errs.append(f'{path}: expected const {s["const"]!r}')
    if 'enum' in s and v not in s['enum']:
        errs.append(f'{path}: {v!r} not in {s["enum"]}')
    if isinstance(v, str):
        if 'pattern' in s and not re.search(s['pattern'], v):
            errs.append(f'{path}: {v!r} !~ {s["pattern"]}')
        if 'minLength' in s and len(v) < s['minLength']:
            errs.append(f'{path}: shorter than {s["minLength"]}')
        if 'maxLength' in s and len(v) > s['maxLength']:
            errs.append(f'{path}: longer than {s["maxLength"]}')
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        if 'minimum' in s and v < s['minimum']:
            errs.append(f'{path}: {v} < {s["minimum"]}')
        if 'maximum' in s and v > s['maximum']:
            errs.append(f'{path}: {v} > {s["maximum"]}')
    if isinstance(v, list):
        if 'minItems' in s and len(v) < s['minItems']:
            errs.append(f'{path}: {len(v)} items < {s["minItems"]}')
        if 'maxItems' in s and len(v) > s['maxItems']:
            errs.append(f'{path}: {len(v)} items > {s["maxItems"]}')
        if 'items' in s:
            for k, x in enumerate(v):
                validate(x, s['items'], base, f'{path}[{k}]', errs)
    if isinstance(v, dict):
        props = s.get('properties', {})
        for r in s.get('required', []):
            if r not in v:
                errs.append(f'{path}: missing key {r!r}')
        if s.get('additionalProperties') is False:
            for k in v:
                if k not in props:
                    errs.append(f'{path}: unexpected key {k!r}')
        for k, sub in props.items():
            if k in v:
                validate(v[k], sub, base, f'{path}.{k}', errs)


def validate_file(schema_name, file_path):
    with open(file_path, encoding='utf-8') as f:
        data = json.load(f)
    if isinstance(data, dict):
        data.pop('_comment', None)
    errs = []
    validate(data, load_schema(schema_name), schema_name, '$', errs)
    return data, errs


# ---------- Postgres jsonb::text canonical form (keys ordered by byte length, then bytes) ----------
def pg_canon(v):
    if isinstance(v, dict):
        keys = sorted(v.keys(), key=lambda k: (len(k.encode('utf-8')), k.encode('utf-8')))
        return '{' + ', '.join(json.dumps(k, ensure_ascii=False) + ': ' + pg_canon(v[k]) for k in keys) + '}'
    if isinstance(v, list):
        return '[' + ', '.join(pg_canon(x) for x in v) + ']'
    return json.dumps(v, ensure_ascii=False)


def pg_md5(v):
    return hashlib.md5(pg_canon(v).encode('utf-8')).hexdigest()


FIXTURES = [
    ('puzzle.schema.json', 'puzzle-0.json'), ('reveal.schema.json', 'reveal-0.json'),
    ('board.schema.json', 'board-0.json'), ('callit.schema.json', 'callit-0.json'),
    ('stats.schema.json', 'stats-0.json'), ('stats.schema.json', 'stats-0.sample-shown.json'),
    ('archive.schema.json', 'archive-fixture.json'), ('latest.schema.json', 'latest.json'),
    ('latest.schema.json', 'latest.sample-published.json'), ('brief.schema.json', 'brief.sample.json'),
    ('health.schema.json', 'health.sample.json'), ('og-data.schema.json', 'og-data-0.json'),
    ('answers.schema.json', 'answers-0.json'),
]


def cross_checks(fx):
    """Semantic checks mirroring spec 5.2/7/12 on puzzle+reveal+answers."""
    errs = []
    p, r, a = fx['puzzle-0.json'], fx['reveal-0.json'], fx['answers-0.json']
    if len(p['rounds']) != len(r['rounds']) or len(a) != len(p['rounds']):
        errs.append('round counts differ between puzzle, reveal and answers')
    if p['final']['round'] != len(p['rounds']):
        errs.append('final.round must equal the number of rounds')
    last = r['rounds'][-1]
    last_ans = next(o for o in last['options'] if o['id'] == last['answer'])
    if abs(last_ans['multiple'] - r['final_multiple']) > 1e-9:
        errs.append('final_multiple must equal the last answer multiple')
    for pr, rr, aa in zip(p['rounds'], r['rounds'], a):
        i = pr['i']
        if not (rr['i'] == aa['i'] == i):
            errs.append(f'round {i}: index mismatch')
        if rr['answer'] != aa['option_id'] or rr['answer_qid'] != aa['qid']:
            errs.append(f'round {i}: answer mismatch between reveal and answers')
        h = hashlib.sha256(f"{p['n']}|{i}|{aa['qid']}".encode()).hexdigest()
        if pr['answer_h'] != h:
            errs.append(f'round {i}: answer_h is not sha256(n|i|qid)')
        for o in pr['options']:
            if o['qid'] != aa['qid'] and hashlib.sha256(f"{p['n']}|{i}|{o['qid']}".encode()).hexdigest() == pr['answer_h']:
                errs.append(f'round {i}: a decoy hashes to answer_h')
        if [o['id'] for o in pr['options']] != ['a', 'b', 'c', 'd']:
            errs.append(f'round {i}: option ids must be a,b,c,d in order')
        if [o['qid'] for o in pr['options']] != [o['qid'] for o in rr['options']]:
            errs.append(f'round {i}: puzzle/reveal options differ')
        ans_emoji = next(o['emoji'] for o in pr['options'] if o['id'] == aa['option_id'])
        decoys = [o for o in pr['options'] if o['id'] != aa['option_id']]
        if sum(1 for o in decoys if o['emoji'] == ans_emoji) < 2:
            errs.append(f'round {i}: fewer than 2 decoys share the answer category')
        ans_r = next(o for o in rr['options'] if o['id'] == aa['option_id'])
        for o in rr['options']:
            if o['id'] == aa['option_id']:
                if o['calm'] or o['multiple'] < 1.5 or o['lag_days'] is None or o['lag_days'] < 0:
                    errs.append(f'round {i}: answer must be non-calm, multiple>=1.5, lag>=0')
            else:
                if not o['calm'] or o['multiple'] >= 1.25 or abs(o['z']) >= 1:
                    errs.append(f'round {i}: decoy {o["id"]} is not calm')
                if not (0.5 * ans_r['median'] <= o['median'] <= 2 * ans_r['median']):
                    errs.append(f'round {i}: decoy {o["id"]} median outside 0.5-2x answer')
        if pr['continues'] != (pr['seed'] is None):
            errs.append(f'round {i}: seed must be null iff continues')
        if pr['continues'] and i > 1:
            prev = a[i - 2]['qid']
            if pr['parent']['qid'] != prev:
                errs.append(f'round {i}: continuing round parent must be the previous answer')
        if rr['evidence']['badge'] == 'flowed' and rr['evidence']['clickstream'] is None:
            errs.append(f'round {i}: flowed badge requires a clickstream edge')
        if rr['evidence']['fluke_warming'] is False and rr['evidence']['fluke'] is None:
            errs.append(f'round {i}: fluke is required unless warming up')
    # honesty: every fixture title says Test
    def titles(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in ('title', 'seed_title', 'hop_title') and isinstance(v, str):
                    yield v
                else:
                    yield from titles(v)
        elif isinstance(o, list):
            for x in o:
                yield from titles(x)
    for name, doc in fx.items():
        for t in titles(doc):
            if 'test' not in t.lower():
                errs.append(f'{name}: title without "Test": {t!r}')
    return errs


def main(argv):
    if len(argv) == 3 and argv[1] == '--md5':
        with open(argv[2], encoding='utf-8') as f:
            d = json.load(f)
        if isinstance(d, dict):
            d.pop('_comment', None)
        print(pg_md5(d))
        return 0
    if len(argv) == 3:
        _, errs = validate_file(argv[1], argv[2])
        for e in errs:
            print('FAIL', e)
        print('OK' if not errs else f'{len(errs)} error(s)')
        return 1 if errs else 0
    total = 0
    fx = {}
    for schema, name in FIXTURES:
        data, errs = validate_file(schema, os.path.join(ROOT, 'fixtures', name))
        fx[name] = data
        total += len(errs)
        print(('PASS' if not errs else 'FAIL'), f'{name:32s} vs {schema}')
        for e in errs:
            print('   ', e)
    errs = cross_checks(fx)
    total += len(errs)
    print(('PASS' if not errs else 'FAIL'), 'semantic cross-checks (answer_h, decoys calm, categories, Test titles)')
    for e in errs:
        print('   ', e)
    print('\nmd5 of jsonb::text form (compare with select md5(<rpc>::text)):')
    for name in ('puzzle-0.json', 'reveal-0.json', 'board-0.json', 'callit-0.json', 'stats-0.json',
                 'archive-fixture.json', 'og-data-0.json', 'answers-0.json'):
        print(f'  {name:24s} {pg_md5(fx[name])}')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
