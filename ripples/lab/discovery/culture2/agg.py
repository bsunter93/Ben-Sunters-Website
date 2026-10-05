import json, glob, statistics as st, os
D = os.path.dirname(os.path.abspath(__file__)) + '/'
items = {it['id']: it for it in json.load(open(D + 'items_r1.json'))}; key = json.load(open(D + 'key.json'))
R = {f.split('_r')[-1].split('.')[0]: {x['id']: x for x in json.load(open(f))} for f in sorted(glob.glob(D + 'ratings_r*.json'))}
rows = []
for i in sorted(items):
    have = [r for r in R if i in R[r]]
    m = {sc: st.mean(R[r][i][sc] for r in have) for sc in ['predicted', 'surprise', 'interest', 'believable']}
    rows.append({'id': i, 'source': key[i][0], 'ref': key[i][1], 'claim': items[i]['claim'], **{k: round(v, 2) for k, v in m.items()}, 'si': round((m['surprise'] + 6 - m['predicted']) / 2, 2)})
def grp(s): return [r for r in rows if r['source'] == s]
ob, fk, cd = grp('planted_obvious'), grp('planted_fabricated'), grp('candidate')
chk = {'raters': len(R), 'obvious_si': round(st.mean(r['si'] for r in ob), 2), 'fabricated_believable': round(st.mean(r['believable'] for r in fk), 2)}
chk['valid'] = chk['obvious_si'] <= 2.5 and chk['fabricated_believable'] <= 2.5
good = [r for r in cd if r['si'] >= 3.5 and r['believable'] >= 3.5]
out = {'checks': chk, 'candidates': len(cd), 'good': len(good), 'good_rate': round(len(good) / max(1, len(cd)), 3), 'rows': rows}
json.dump(out, open(D + 'panel_result.json', 'w'), indent=1, ensure_ascii=False)
print(json.dumps({k: out[k] for k in ['checks', 'candidates', 'good', 'good_rate']}))
for r in sorted(good, key=lambda r: -r['si'] - r['interest'] / 5): print(r['si'], r['believable'], r['interest'], r['ref'], r['claim'][:100])
