import json, glob, statistics as st, itertools, os
P = os.path.dirname(os.path.abspath(__file__)) + '/'
items = {it['id']: it for it in json.load(open(P + 'items_r1.json'))}
key = json.load(open(P + 'key.json'))
src = {f"P{int(k):03d}": v for k, v in key.items()}
R = {}
for f in sorted(glob.glob(P + 'ratings_r*.json')):
    r = f.split('_r')[-1].split('.')[0]; R[r] = {x['id']: x for x in json.load(open(f))}
raters = sorted(R)
def rank(xs):
    s = sorted(range(len(xs)), key=lambda i: xs[i]); out = [0] * len(xs); i = 0
    while i < len(s):
        j = i
        while j + 1 < len(s) and xs[s[j + 1]] == xs[s[i]]: j += 1
        for k in range(i, j + 1): out[s[k]] = (i + j) / 2
        i = j + 1
    return out
def spear(a, b):
    ra, rb = rank(a), rank(b); ma, mb = st.mean(ra), st.mean(rb)
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb)); den = (sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb)) ** .5
    return num / den if den else 0
ids = sorted(items)
agree = {}
for sc in ['predicted', 'surprise', 'interest', 'believable']:
    vals = [spear([R[a][i][sc] for i in ids], [R[b][i][sc] for i in ids]) for a, b in itertools.combinations(raters, 2)]
    agree[sc] = round(st.mean(vals), 3) if vals else None
rows = []
for i in ids:
    m = {sc: st.mean(R[r][i][sc] for r in raters) for sc in ['predicted', 'surprise', 'interest', 'believable']}
    si = (m['surprise'] + (6 - m['predicted'])) / 2
    rows.append({'id': i, 'source': src[i][0], 'ref': src[i][1], 'claim': items[i]['claim'], **{k: round(v, 2) for k, v in m.items()}, 'surprise_index': round(si, 2)})
by = {}
for r in rows: by.setdefault(r['source'], []).append(r)
summary = {}
for s, rs in by.items():
    summary[s] = {'n': len(rs), 'surprise_index_mean': round(st.mean(r['surprise_index'] for r in rs), 2), 'believable_mean': round(st.mean(r['believable'] for r in rs), 2),
                  'interest_mean': round(st.mean(r['interest'] for r in rs), 2), 'good': sum(1 for r in rs if r['surprise_index'] >= 3.5 and r['believable'] >= 3.5)}
eng = [r['surprise_index'] for r in by.get('engine', [])]; real = [r['believable'] for r in rows if not r['source'].startswith('planted')]
checks = {'obvious_si_mean': summary.get('planted_obvious', {}).get('surprise_index_mean'), 'engine_si_median': round(st.median(eng), 2) if eng else None,
          'fabricated_believable_mean': summary.get('planted_fabricated', {}).get('believable_mean'), 'real_believable_median': round(st.median(real), 2)}
checks['obvious_ok'] = checks['obvious_si_mean'] is not None and checks['obvious_si_mean'] <= 2.5 and checks['obvious_si_mean'] < checks['engine_si_median']
checks['fabricated_ok'] = checks['fabricated_believable_mean'] is not None and checks['fabricated_believable_mean'] <= 2.5 and checks['fabricated_believable_mean'] < checks['real_believable_median']
out = {'raters': raters, 'agreement_mean_pairwise_spearman': agree, 'validity': checks, 'by_source': summary,
       'top_surprising_and_believable': sorted([r for r in rows if not r['source'].startswith('planted') and r['believable'] >= 3.5], key=lambda r: -r['surprise_index'])[:25], 'items': rows}
json.dump(out, open(P + 'panel_v1.json', 'w'), indent=1, ensure_ascii=False)
print(json.dumps({k: out[k] for k in ['raters', 'agreement_mean_pairwise_spearman', 'validity', 'by_source']}, indent=1))
for r in out['top_surprising_and_believable'][:15]: print(r['surprise_index'], r['believable'], r['source'], r['claim'][:90])
