#!/usr/bin/env python3
"""md5 of every W2 function body as defined by replaying the migration files sql/01..09 and sql/12+ in order (last
definition wins, then the guarded in-place patches of 07-09; 10_seed_data and 11_cron define no functions). Compare with the live database:

  select n.nspname || '.' || p.proname, md5(btrim(regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g')))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname = 'public' and p.proname like 'ripples\\_%') or (n.nspname = 'ripples' and p.proname ~ '^_(emoji|text_|class_|classify|refresh_articles|safe|sbin|qnorm|pcfg|job_payload|enqueue|dispatch|fluke|shared_trigger|pre_eligible|seed_sources|advance_beams|tick_run|stem_ok|pick_decoys|caption|render|rederive_classes)')
   order by 1;
"""
import hashlib, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SQL = os.path.join(os.path.dirname(HERE), 'sql')
FILES = sorted(f for f in os.listdir(SQL) if re.match(r'\d\d_.*\.sql$', f) and not f.startswith(('10_', '11_')))
PATCHES = [  # (function, old, new) exactly as in sql/07-09 and sql/13
    ('public.ripples_build_puzzle', 'c.used_n is null and c.kind = p_kind and c.as_of between',
     "c.used_n is null and (c.kind = p_kind or p_kind = 'live') and c.as_of between"),
    ('ripples._enqueue_resolve', "(t.source = 'topcountry' and t.rank <= 100)",
     "(t.source = 'topcountry' and (t.rank <= 100 or (t.lang = 'en' and t.rank <= 200)))"),
    ('ripples._advance_beams', "           and c.split_ok and ripples._pre_eligible(c)\n           and c.qid <> r.root_qid",
     "           and c.split_ok and ripples._pre_eligible(c)\n           and ripples._pick_decoys(p_as_of, c.root_qid, c.parent_qid, c.qid, array[c.root_qid, c.parent_qid]) is not null\n           and c.qid <> r.root_qid"),
    ('ripples._tick_run', "      if live and t >= time '07:20' then",
     "      if (live and t >= time '07:20') or (not live and now() - r.started_at > make_interval(mins => ripples._pcfg('practice_deadline_min', 22)::int)) then"),
    ('public.ripples_job_done', "case when p_err like 'rate_limited%' then interval '3 minutes' else interval '30 seconds' end",
     "case when p_err like 'rate_limited%' then make_interval(secs => greatest(30, coalesce(substring(p_err from 'retry-after=([0-9]+)')::int, 55) + 5)) else interval '30 seconds' end"),
    ('ripples._fluke', 'r.decoy_tested < 500 or r.fluke is null',
     "r.decoy_tested < ripples._pcfg('fluke_warm_min_decoy', 500) or r.fluke is null"),
]
FN = re.compile(r"create or replace function\s+([a-z_]+\.[a-z_0-9]+)\s*\(.*?\bas \$\$(.*?)\$\$", re.S | re.I)

bodies = {}
for f in FILES:
    txt = open(os.path.join(SQL, f), encoding='utf-8').read()
    for m in FN.finditer(txt):
        bodies[m.group(1).lower()] = m.group(2)
for fn, old, new in PATCHES:
    if fn in bodies and old in bodies[fn]:
        bodies[fn] = bodies[fn].replace(old, new)
def norm(b):
    # comments and whitespace do not count (the migrations were applied without the explanatory comments)
    return re.sub(r'\s+', ' ', re.sub(r'--[^\n]*', '', b)).strip()
for name in sorted(bodies):
    print(name, hashlib.md5(norm(bodies[name]).encode('utf-8')).hexdigest())
