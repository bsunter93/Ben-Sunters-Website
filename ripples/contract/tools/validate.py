#!/usr/bin/env python3
"""Dependency-free validator for the Knock-On v5 contract.

  python3 ripples/contract/tools/validate.py                 # validate every fixture + cross-checks
  python3 ripples/contract/tools/validate.py SCHEMA FILE     # validate one JSON file against one schema
  python3 ripples/contract/tools/validate.py --md5 FILE      # md5 of the file in Postgres jsonb::text form
  python3 ripples/contract/tools/validate.py --ledger-hash N PUZZLE.json REVEAL.json CALLIT.json
        # recompute a ledger payload_hash from the PUBLIC files v1/puzzle/N.json, v1/reveal/N.json, v1/callit/N.json
  python3 ripples/contract/tools/validate.py --ledger-chain LEDGER.json [PUZZLE_DIR REVEAL_DIR CALLIT_DIR]
        # check prev/chain linkage of a ledger rows file ([{n,payload_hash,prev_hash,chain_hash}] in write order,
        # e.g. publish_bundle.ledger); with the three dirs, also recompute every payload_hash from {dir}/{n}.json
  python3 ripples/contract/tools/validate.py --wording FILE [FILE...]
        # SPEC 12.1 wording lint on any Puzzle/Reveal/Brief/Board JSON (or a JSON list of them): banned causal
        # words ("caused", "drove", "flooded into", "went from X to Y", ...) in every text/label field, and
        # reader-flow words ("readers", "clicked", ...) in the caption of any round whose badge is not "flowed"
  python3 ripples/contract/tools/validate.py --no-samples DIR
        # fails if any file under DIR references a synthetic fixtures/*.sample*.json file (they must never ship)

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


# ---------- ledger (mirrors ripples._canon / ripples._ledger_input in SQL) ----------
def _num15(x):
    # Postgres to_jsonb(x::float8): 15 significant digits, plain notation, no trailing zeros
    from decimal import Decimal
    d = Decimal('%.15g' % float(x))
    if d == 0:
        return 0
    t = format(d, 'f')
    if '.' in t:
        t = t.rstrip('0').rstrip('.')
    return _Raw(t)


class _Raw(str):
    pass


def ledger_canon(v):
    if isinstance(v, bool) or v is None or isinstance(v, str):
        return v
    if isinstance(v, (int, float)):
        return _num15(v)
    if isinstance(v, dict):
        return {k: ledger_canon(x) for k, x in v.items()}
    if isinstance(v, list):
        return [ledger_canon(x) for x in v]
    raise TypeError(type(v))


def _canon_text(v):
    if isinstance(v, _Raw):
        return str(v)
    if isinstance(v, dict):
        keys = sorted(v.keys(), key=lambda k: (len(k.encode('utf-8')), k.encode('utf-8')))
        return '{' + ', '.join(json.dumps(k, ensure_ascii=False) + ': ' + _canon_text(v[k]) for k in keys) + '}'
    if isinstance(v, list):
        return '[' + ', '.join(_canon_text(x) for x in v) + ']'
    return json.dumps(v, ensure_ascii=False)


def ledger_payload_hash(n, puzzle, reveal, callit):
    """payload_hash from the public puzzle/reveal/callit JSON: drop puzzle.headline and every reveal round's
    caption (copy is overlaid after publish), Call It = [[qid, model_p]] sorted by qid (byte order)."""
    pz = dict(puzzle) if isinstance(puzzle, dict) else puzzle
    if isinstance(pz, dict):
        pz.pop('headline', None)
    rv = dict(reveal) if isinstance(reveal, dict) else reveal
    if isinstance(rv, dict) and isinstance(rv.get('rounds'), list):
        rv['rounds'] = [{k: x for k, x in r.items() if k != 'caption'} if isinstance(r, dict) else r for r in rv['rounds']]
    opts = (callit or {}).get('options') or []
    cl = [[o['qid'], o.get('model_p')] for o in sorted(opts, key=lambda o: o['qid'].encode('utf-8'))]
    doc = {'n': n, 'puzzle': pz, 'reveal': rv, 'callit': cl}
    return hashlib.sha256(_canon_text(ledger_canon(doc)).encode('utf-8')).hexdigest()


def ledger_chain_check(rows, dirs=None):
    errs, prev = [], '0' * 64
    for r in rows:
        if r['prev_hash'] != prev:
            errs.append(f"n={r['n']}: prev_hash does not equal the previous row's chain_hash")
        if hashlib.sha256((r['prev_hash'] + r['payload_hash']).encode()).hexdigest() != r['chain_hash']:
            errs.append(f"n={r['n']}: chain_hash != sha256(prev_hash || payload_hash)")
        if dirs:
            docs = []
            for d in dirs:
                with open(os.path.join(d, f"{r['n']}.json"), encoding='utf-8') as f:
                    docs.append(json.load(f))
            if ledger_payload_hash(r['n'], *docs) != r['payload_hash']:
                errs.append(f"n={r['n']}: payload_hash does not match the public files")
        prev = r['chain_hash']
    return errs


FIXTURES = [
    ('puzzle.schema.json', 'puzzle-0.json'), ('reveal.schema.json', 'reveal-0.json'),
    ('board.schema.json', 'board-0.json'), ('callit.schema.json', 'callit-0.json'),
    ('stats.schema.json', 'stats-0.json'), ('stats.schema.json', 'stats-0.sample-shown.json'),
    ('archive.schema.json', 'archive-fixture.json'), ('latest.schema.json', 'latest.json'),
    ('latest.schema.json', 'latest.sample-published.json'), ('brief.schema.json', 'brief.sample.json'),
    ('health.schema.json', 'health.sample.json'), ('og-data.schema.json', 'og-data-0.json'),
    ('answers.schema.json', 'answers-0.json'),
]


# SPEC 12.1: never "caused", "flooded into", "drove" or "went from X to Y" as a claim (checked on EVERY round,
# headline, intro, end text and cross label, flowed or not).
CAUSAL_RE = re.compile(
    r"\b(caus(e|es|ed|ing)|dr(o|i)ve[ns]?|driving|flood(s|ed|ing)?\s+(in)?to|a flood of|"
    r"sen(t|ds?|ding) (readers|traffic|people|visitors)|went from\b[^.;:!?]{1,80}?\bto)\b", re.I)
# only a flowed (clickstream-edge) round may use reader-flow language
FLOW_RE = re.compile(
    r"\b(readers?|clicked|clicks?|click(ed)? through|looked up|went on to|moved (on )?to|followed|navigat\w*)\b", re.I)


def wording_errors(doc, where=''):
    """Lint every 'text'/'label' string in doc; round captions also get the reader-flow rule."""
    errs = []

    def walk(o, path, flowed):
        if isinstance(o, dict):
            if isinstance(o.get('evidence'), dict) and 'caption' in o:   # a reveal round
                flowed = o['evidence'].get('badge') == 'flowed'
            # a Wikipedia short description (caption source "wikipedia") describes the subject itself
            # ("Disease caused by ..."), not reader flow, so it is exempt
            wiki = o.get('source') == 'wikipedia'
            for k, v in o.items():
                if k in ('text', 'label') and isinstance(v, str) and not wiki:
                    hits = [m.group(0) for m in CAUSAL_RE.finditer(v)]
                    if hits:
                        errs.append(f'{where}{path}.{k}: banned causal wording {hits}: {v!r}')
                    if path.endswith('.caption') and flowed is False:
                        m = FLOW_RE.search(v)
                        if m:
                            errs.append(f'{where}{path}.{k}: reader-flow wording {m.group(0)!r} in a non-flowed round: {v!r}')
                elif k not in ('text', 'label'):
                    walk(v, f'{path}.{k}', flowed)
        elif isinstance(o, list):
            for j, x in enumerate(o):
                walk(x, f'{path}[{j}]', flowed)
    walk(doc, '$', None)
    return errs


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
    # SPEC 12.1 wording on every fixture document (causal words anywhere; reader-flow only on flowed rounds)
    for name, doc in fx.items():
        errs.extend(wording_errors(doc, f'{name}: '))
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


SAMPLE_RE = re.compile(r'[\w.-]*\.sample[\w.-]*\.json|sample-shown|sample-published')


def no_samples(root):
    errs = []
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in ('.git', 'node_modules', '__pycache__')
                   and os.path.abspath(os.path.join(d, x)) != ROOT]          # the contract itself may list them
        for fn in files:
            fp = os.path.join(d, fn)
            if SAMPLE_RE.search(fn):
                errs.append(f'{fp}: a synthetic sample file is inside the shipped tree')
                continue
            try:
                with open(fp, encoding='utf-8') as f:
                    txt = f.read()
            except (UnicodeDecodeError, OSError):
                continue
            m = SAMPLE_RE.search(txt)
            if m:
                errs.append(f'{fp}: references synthetic sample {m.group(0)!r}')
    return errs


def main(argv):
    if len(argv) >= 3 and argv[1] == '--wording':
        errs = []
        for fp in argv[2:]:
            with open(fp, encoding='utf-8') as f:
                errs.extend(wording_errors(json.load(f), f'{fp}: '))
        for e in errs:
            print('FAIL', e)
        print('OK' if not errs else f'{len(errs)} error(s)')
        return 1 if errs else 0
    if len(argv) == 3 and argv[1] == '--no-samples':
        errs = no_samples(argv[2])
        for e in errs:
            print('FAIL', e)
        print('OK' if not errs else f'{len(errs)} error(s)')
        return 1 if errs else 0
    if len(argv) == 6 and argv[1] == '--ledger-hash':
        docs = []
        for fp in argv[3:6]:
            with open(fp, encoding='utf-8') as f:
                docs.append(json.load(f))
        print(ledger_payload_hash(int(argv[2]), *docs))
        return 0
    if len(argv) in (3, 6) and argv[1] == '--ledger-chain':
        with open(argv[2], encoding='utf-8') as f:
            rows = json.load(f)
        errs = ledger_chain_check(rows, argv[3:6] if len(argv) == 6 else None)
        for e in errs:
            print('FAIL', e)
        print('OK' if not errs else f'{len(errs)} error(s)', f'({len(rows)} rows, head {rows[-1]["chain_hash"] if rows else None})')
        return 1 if errs else 0
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
    print(('PASS' if not errs else 'FAIL'), 'semantic cross-checks (answer_h, decoys calm, categories, Test titles, SPEC 12.1 wording)')
    for e in errs:
        print('   ', e)
    print('\nmd5 of jsonb::text form (compare with select md5(<rpc>::text)):')
    for name in ('puzzle-0.json', 'reveal-0.json', 'board-0.json', 'callit-0.json', 'stats-0.json',
                 'archive-fixture.json', 'og-data-0.json', 'answers-0.json'):
        print(f'  {name:24s} {pg_md5(fx[name])}')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
