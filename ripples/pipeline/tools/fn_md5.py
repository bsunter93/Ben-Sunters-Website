#!/usr/bin/env python3
"""md5 of every W2 function body as defined by replaying the migration files sql/01..09 and sql/12+ in order: within each
file the definitions it contains, then the in-place patches it applies (07-09, 13, 15, 17 and 18); the last definition
wins. 10_seed_data and 11_cron define no functions. Compare with the live database:

  select n.nspname || '.' || p.proname, md5(btrim(regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g')))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname = 'public' and p.proname like 'ripples\\_%') or (n.nspname = 'ripples' and p.proname ~ '^_(emoji|text_|class_|classify|refresh_articles|safe|sbin|qnorm|pcfg|job_payload|enqueue|dispatch|fluke|shared_trigger|pre_eligible|seed_sources|advance_beams|tick_run|stem_ok|pick_decoys|caption|render|rederive_classes|flat30|fresh|spark_peak)')
   order by 1;
"""
import hashlib, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SQL = os.path.join(os.path.dirname(HERE), 'sql')
FILES = sorted(f for f in os.listdir(SQL) if re.match(r'\d\d_.*\.sql$', f) and not f.startswith(('10_', '11_')))
PATCHES = {  # file prefix -> [(function, old, new)] exactly as the guarded in-place patches in that file
    '07': [
        ('public.ripples_build_puzzle',
         'c.used_n is null and c.kind = p_kind and c.as_of between',
         "c.used_n is null and (c.kind = p_kind or p_kind = 'live') and c.as_of between"),
        ('ripples._enqueue_resolve',
         "(t.source = 'topcountry' and t.rank <= 100)",
         "(t.source = 'topcountry' and (t.rank <= 100 or (t.lang = 'en' and t.rank <= 200)))"),
    ],
    '08': [
        ('ripples._advance_beams',
         '           and c.split_ok and ripples._pre_eligible(c)\n           and c.qid <> r.root_qid',
         '           and c.split_ok and ripples._pre_eligible(c)\n           and ripples._pick_decoys(p_as_of, c.root_qid, c.parent_qid, c.qid, array[c.root_qid, c.parent_qid]) is not null\n           and c.qid <> r.root_qid'),
        ('ripples._tick_run',
         "      if live and t >= time '07:20' then",
         "      if (live and t >= time '07:20') or (not live and now() - r.started_at > make_interval(mins => ripples._pcfg('practice_deadline_min', 22)::int)) then"),
    ],
    '09': [
        ('public.ripples_job_done',
         "case when p_err like 'rate_limited%' then interval '3 minutes' else interval '30 seconds' end",
         "case when p_err like 'rate_limited%' then make_interval(secs => greatest(30, coalesce(substring(p_err from 'retry-after=([0-9]+)')::int, 55) + 5)) else interval '30 seconds' end"),
    ],
    '13': [
        ('ripples._fluke',
         'r.decoy_tested < 500 or r.fluke is null',
         "r.decoy_tested < ripples._pcfg('fluke_warm_min_decoy', 500) or r.fluke is null"),
    ],
    '15': [
        ('public.ripples_build_puzzle',
         "\n  return jsonb_build_object('n', v_n, 'status', 'delayed', 'hops'",
         "\n  if p_kind = 'practice' then\n    if exists (select 1 from ripples.puzzles z where z.n = v_n and z.kind = 'practice' and z.status <> 'published') then\n      delete from ripples.callit z where z.n = v_n;\n      delete from ripples.copy z where z.n = v_n;\n      delete from ripples.puzzles z where z.n = v_n;\n    end if;\n  else\n    update ripples.puzzles z set status = 'delayed' where z.n = v_n and z.kind = 'live' and z.status = 'built';\n  end if;\n  return jsonb_build_object('n', v_n, 'status', 'delayed', 'hops'"),
    ],
    '17': [
        ('ripples._render',
         'st_stop := exists (',
         "st_stop := not coalesce((p_rounds->i->>'continues')::boolean, false) and exists ("),
    ],
    '18': [
        ('ripples._render',
         "then 'flowed' else 'spiked_after' end,",
         "then 'flowed' when ans.onset_lag = 0 then 'spiked_alongside' else 'spiked_after' end,"),
        ('ripples._render',
         "  headline := left(seed.title_en || ': which linked pages spiked next?', 70);\n  if length(seed.title_en || ': which linked pages spiked next?') > 70 then headline := 'One trend. Which linked pages spiked next?'; end if;",
         "  headline := seed.title_en || ': which linked pages also spiked?';\n  if length(headline) > 70 then headline := 'One trend. Which linked pages also spiked?'; end if;"),
        ('ripples._render',
         'and ripples._safe(c.qid, p_data_as_of, c.median_views, false)) c',
         'and ripples._safe(c.qid, p_data_as_of, c.median_views, false) and ripples._fresh(c.qid, p_data_as_of)) c'),
        ('ripples._render',
         'least(20, count(*))::int tested',
         "least(20, count(*))::int tested,\n                 (select count(*) from ripples.candidates c3 cross join lateral ripples._fluke(c3.as_of, c3.s_stat) f3\n                   where c3.as_of = s.as_of and c3.role = 'real' and c3.root_qid = s.qid and c3.parent_qid = s.qid and c3.depth = 1\n                     and not c3.extra and c3.pass_raw\n                     and ((f3.warming and c3.p_time <= 0.05) or (not f3.warming and c3.p_time <= 0.10 and f3.f <= 0.20)))::int any_shown"),
        ('ripples._render',
         "when s.peak_multiple >= 10 and w.k = 0 and w.tested >= 15 then 'belly_flop'",
         "when s.peak_multiple >= 10 and w.k = 0 and w.tested >= 15 and w.any_shown = 0 and not exists (select 1 from jsonb_array_elements(p_rounds) pr where pr->>'root' = s.qid) then 'belly_flop'"),
        ('ripples._render',
         'and ripples._safe(s.qid, p_board_as_of, s.median_views, true)\n',
         'and ripples._safe(s.qid, p_board_as_of, s.median_views, true) and ripples._fresh(s.qid, p_board_as_of)\n'),
        ('public.ripples_build_puzzle',
         "     and exists (select 1 from ripples.seeds s where s.as_of = p_as_of and s.role = 'real' and s.qid = c.root_qid\n                   and ripples._safe(s.qid, p_as_of, s.median_views, false))\n     and ripples._pick_decoys(p_as_of, c.root_qid, c.parent_qid, c.qid, array[c.root_qid, c.parent_qid]) is not null;",
         "     and ripples._fresh(c.qid, p_as_of)\n     and exists (select 1 from ripples.seeds s where s.as_of = p_as_of and s.role = 'real' and s.qid = c.root_qid\n                   and ripples._safe(s.qid, p_as_of, s.median_views, false) and ripples._fresh(s.qid, p_as_of))\n     and ripples._pick_decoys(p_as_of, c.root_qid, c.parent_qid, c.qid, array[c.root_qid, c.parent_qid], true) is not null;"),
        ('public.ripples_build_puzzle',
         'ripples._pick_decoys(p_as_of, best.root, best.parents[k], best.path[k], used || best.path)',
         'ripples._pick_decoys(p_as_of, best.root, best.parents[k], best.path[k], used || best.path, true)'),
        ('public.ripples_build_puzzle',
         'ripples._pick_decoys(p_as_of, hop.root, hop.parent, hop.qid, used || hop.root)',
         'ripples._pick_decoys(p_as_of, hop.root, hop.parent, hop.qid, used || hop.root, true)'),
        ('public.ripples_build_puzzle',
         'ripples._pick_decoys(p_as_of, alt_c.root, alt_c.parents[k], alt_c.path[k], u2 || alt_c.path)',
         'ripples._pick_decoys(p_as_of, alt_c.root, alt_c.parents[k], alt_c.path[k], u2 || alt_c.path, true)'),
        ('public.ripples_build_puzzle',
         '   order by c.as_of desc, c.score desc limit 1;',
         "     and not exists (select 1 from jsonb_array_elements(c.rounds) r\n                      cross join lateral (select r->>'root' q union all select r->>'qid' union all select jsonb_array_elements_text(r->'decoys')) z\n                      where not ripples._safe(z.q, p_as_of, (select max(x.median_views) from ripples.candidates x where x.as_of = c.as_of and x.qid = z.q), false)\n                         or not ripples._fresh(z.q, p_as_of))\n   order by c.as_of desc, c.score desc limit 1;"),
        ('public.ripples_pick_seeds',
         "        used text[] := '{}'; kr int := 0;",
         "        v_kind text := coalesce((select kind from ripples.runs where as_of = p_as_of), 'live');\n        used text[] := '{}'; kr int := 0;"),
        ('public.ripples_pick_seeds',
         '         and ripples._safe(s.qid, p_as_of, s.median_views, true)\n',
         '         and ripples._safe(s.qid, p_as_of, s.median_views, true) and ripples._fresh(s.qid, p_as_of)\n'),
        ('public.ripples_pick_seeds',
         "where p.kind in ('live','practice') and p.data_date between p_as_of - 30 and p_as_of - 1",
         "where p.kind = v_kind and p.status <> 'delayed' and p.data_date between p_as_of - 30 and p_as_of - 1"),
    ],
}
FN = re.compile(r"create or replace function\s+([a-z_]+\.[a-z_0-9]+)\s*\(.*?\bas \$\$(.*?)\$\$", re.S | re.I)

bodies = {}
for f in FILES:
    txt = open(os.path.join(SQL, f), encoding='utf-8').read()
    for m in FN.finditer(txt):
        bodies[m.group(1).lower()] = m.group(2)
    for fn, old, new in PATCHES.get(f[:2], []):
        if fn in bodies and old in bodies[fn]:
            bodies[fn] = bodies[fn].replace(old, new, 1)
def norm(b):
    # comments and whitespace do not count (the migrations were applied without the explanatory comments)
    return re.sub(r'\s+', ' ', re.sub(r'--[^\n]*', '', b)).strip()
for name in sorted(bodies):
    print(name, hashlib.md5(norm(bodies[name]).encode('utf-8')).hexdigest())
