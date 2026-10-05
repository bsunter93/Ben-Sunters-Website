# selected.json (verified survivors) -> stones appended to demo/discovered_wiki.json in its own shape
import json, re, sys, unicodedata
D = '/private/tmp/claude-501/-Users-bensunter-Desktop-resumes/511a7150-f13b-4094-ab15-ead71a0ece09/scratchpad/'
sel = json.load(open(D + 'culture/selected.json'))
wpath = D + 'site/ripples/demo/discovered_wiki.json'; W = json.load(open(wpath))
def slug(s): s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode(); return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')[:48]
def prec(d): return 'day' if re.match(r'^\d{4}-\d{2}-\d{2}$', d) else 'month' if re.match(r'^\d{4}-\d{2}$', d) else 'year'
def full(d): return d if prec(d) == 'day' else (d + '-01' if prec(d) == 'month' else d + '-01-01')
added = []
for s in sel:
    sl = slug(s['stone']) + '-c2'
    if sl in W['stones']: continue
    marks = []
    for i, m in enumerate(s['marks']):
        marks.append({'label': m['label'], 'title': m['title'], 'kind': m['kind'], 'date': m['date'], 'precision': prec(m['date']),
                      'sentence': m['sentence'], 'source_label': 'Wikipedia: ' + m['source_article'], 'source_url': 'https://en.wikipedia.org/wiki/' + m['source_article'].replace(' ', '_'),
                      'found': m.get('found', 'reverse'), 'mark_url': ('https://en.wikipedia.org/wiki/' + m['mark_article'].replace(' ', '_')) if m.get('mark_article') else None,
                      'mark_article': m.get('mark_article'), 'id': f'c{i}', 'verified': 'read', **({'grade': 'disputed'} if m.get('disputed') else {}), **({'note': m['note']} if m.get('note') else {})})
    sd = s['stone_date']; W['stones'][sl] = {'stone': s['stone'], 'article': s['stone_article'], 'date': sd if prec(sd) == 'day' else (sd + '-15' if prec(sd) == 'month' else sd + '-07-01'), **({} if prec(sd) == 'day' else {'date_precision': prec(sd)}), 'title': s['title'], 'first': s['first'], 'marks': marks, 'screen': 'read'}
    added.append((sl, s['title']))
json.dump(W, open(wpath, 'w'), indent=1 if '\n ' in open(wpath).read()[:200] else None, ensure_ascii=False)
json.dump(added, open(D + 'culture/added.json', 'w'), indent=1, ensure_ascii=False)
print(len(added))
