-- Knock-On v5 / W2 acceptance checks. Run each block with the MCP execute_sql tool (or psql as postgres).
-- The defaults are the practice run for as_of 2026-09-24 -> n = -1. Blocks A5 and A8 change data inside a DO block
-- that ends with an exception, so everything they write is rolled back; read the result from the error message.

-- A1. run finished, Wikimedia calls under the cap, job errors < 10% of jobs, wall time <= 25 minutes
select r.as_of, r.kind, r.stage, r.wm_calls, (ripples._cfg('wm_daily_cap') #>> '{}')::int as cap,
       r.finished_at - r.started_at as took,
       (select count(*) from ripples.jobs j where j.as_of = r.as_of) as jobs,
       (select count(*) from ripples.jobs j where j.as_of = r.as_of and j.status = 'failed') as failed_jobs,
       round(100.0 * (select count(*) from ripples.jobs j where j.as_of = r.as_of and j.status = 'failed')
             / nullif((select count(*) from ripples.jobs j where j.as_of = r.as_of), 0), 1) as failed_pct,
       r.errors as failed_attempts, r.detail->'build' as build
  from ripples.runs r where r.as_of = '2026-09-24';

-- A2. 3-4 rounds; every answer: pass_raw, p_time <= 0.05, multiple >= 1.5, onset_lag >= 0, split_ok;
--     every decoy: calm, median within 0.5-2x the answer's; >= 2 of 3 decoys share the answer's category
with p as (select * from ripples.puzzles where n = -1),
pr as (select (x->>'i')::int i, x from p, jsonb_array_elements(p.payload->'rounds') x),
opt as (
  select pr.i, o->>'qid' qid, (o->>'qid') = (select a->>'qid' from p, jsonb_array_elements(p.answers) a where (a->>'i')::int = pr.i) is_ans,
         pr.x->'parent'->>'qid' parent, coalesce(pr.x->'seed'->>'qid', p.payload->'seed'->>'qid') root_hint
    from p, pr, jsonb_array_elements(pr.x->'options') o),
c as (
  select opt.*, c.pass_raw, c.p_time, c.multiple, c.onset_lag, c.split_ok, c.calm, c.median_views, c.extra, a.category
    from opt join p on true
    join ripples.candidates c on c.as_of = p.data_date and c.role = 'real' and c.parent_qid = opt.parent and c.qid = opt.qid
    join ripples.articles a on a.qid = c.qid)
select i,
       (select jsonb_array_length(payload->'rounds') from p) rounds,
       bool_and(pass_raw and p_time <= 0.05 and multiple >= 1.5 and onset_lag >= 0 and split_ok) filter (where is_ans) answer_ok,
       bool_and(calm) filter (where not is_ans) decoys_calm,
       bool_and(median_views between 0.5 * (select max(median_views) from c c2 where c2.i = c.i and c2.is_ans)
                                 and 2 * (select max(median_views) from c c2 where c2.i = c.i and c2.is_ans)) filter (where not is_ans) decoys_median_ok,
       count(*) filter (where not is_ans and category = (select max(category) from c c2 where c2.i = c.i and c2.is_ans)) same_cat,
       count(*) filter (where not is_ans and extra) decoys_from_reserve
  from c group by i order by i;

-- A3. contract shape: run tools/validate.py on the exported JSON (see the W2 report), or this key check
select jsonb_object_keys(payload) k from ripples.puzzles where n = -1 order by 1;

-- A4. answer_h equals sha256(n|i|answer_qid) and differs for every decoy
select pr.i,
       pr.x->>'answer_h' = encode(extensions.digest(p.n || '|' || pr.i || '|' || (a->>'qid'), 'sha256'), 'hex') as answer_matches,
       bool_and(encode(extensions.digest(p.n || '|' || pr.i || '|' || (o->>'qid'), 'sha256'), 'hex') <> pr.x->>'answer_h')
         filter (where o->>'qid' <> a->>'qid') as decoys_differ
  from ripples.puzzles p
  cross join lateral (select (x->>'i')::int i, x from jsonb_array_elements(p.payload->'rounds') x) pr
  join lateral jsonb_array_elements(p.answers) a on (a->>'i')::int = pr.i
  cross join lateral jsonb_array_elements(pr.x->'options') o
 where p.n = -1 group by pr.i, pr.x, p.n, a order by pr.i;

-- A5. safety. (a) no seed / option / Call It article is blocked or died within 60 days of as_of;
with p as (select * from ripples.puzzles where n = -1),
q as (select p.payload->'seed'->>'qid' qid, 'seed' what from p
      union all select r->'seed'->>'qid', 'round seed' from p, jsonb_array_elements(p.payload->'rounds') r where r->'seed' <> 'null'
      union all select o->>'qid', 'option' from p, jsonb_array_elements(p.payload->'rounds') r, jsonb_array_elements(r->'options') o
      union all select o->>'qid', 'callit' from p, jsonb_array_elements(p.payload->'callit'->'options') o)
select what, count(*) n, count(*) filter (where a.blocked or (a.date_of_death is not null and a.date_of_death >= p.data_date - 60)) bad
  from q join ripples.articles a using (qid) cross join p group by what;
-- (b) a synthetic article with P570 = current_date - 5 is excluded: the round-1 answer (and the seed, separately) get
--     a death date 5 days ago, the puzzle is rebuilt, and the QID must be gone. Rolled back.
do $$
declare p ripples.puzzles; q text; s text; r1 jsonb; r2 jsonb; ok1 boolean; ok2 boolean; safe_syn boolean;
begin
  perform public.ripples_ingest_articles(jsonb_build_object('articles', jsonb_build_array(jsonb_build_object(
    'qid', 'Q999999901', 'title_en', 'Test Recently Deceased Person', 'short_desc', 'Test person (1950-2026)',
    'p31', jsonb_build_array('Q5'), 'date_of_death', current_date - 5, 'sitelinks', 40))));
  safe_syn := ripples._safe('Q999999901', current_date - 1, 5000);
  select * into p from ripples.puzzles where n = -1;
  q := p.answers->0->>'qid';
  s := p.payload->'seed'->>'qid';
  update ripples.articles set date_of_death = current_date - 5 where qid = q;
  r1 := public.ripples_build_puzzle(p.data_date, 'practice');
  ok1 := not exists (select 1 from ripples.puzzles x, jsonb_array_elements(x.payload->'rounds') r, jsonb_array_elements(r->'options') o
                      where x.n = -1 and o->>'qid' = q)
         and not exists (select 1 from ripples.callit c where c.n = -1 and c.qid = q);
  update ripples.articles set date_of_death = current_date - 5 where qid = s;
  r2 := public.ripples_build_puzzle(p.data_date, 'practice');
  ok2 := not exists (select 1 from ripples.puzzles x where x.n = -1 and (x.payload->'seed'->>'qid' = s
                       or exists (select 1 from jsonb_array_elements(x.payload->'rounds') r where r->'seed'->>'qid' = s
                                    or r->'parent'->>'qid' = s)));
  raise exception 'A5 synthetic_safe=% answer_excluded=% (%, rebuild %) seed_excluded=% (%, rebuild %)',
    safe_syn, ok1, q, r1->>'status', ok2, s, coalesce(r2->>'status', '?') || '/' || coalesce(r2->>'format', '');
end $$;

-- A6. cron jobs, and a manual trends collection (then count the new rows a minute later)
select jobname, schedule, command, active from cron.job where jobname like 'ripples-%' order by jobname;
-- select public.call_collector('ripples-collect', '{"mode":"trends"}'::jsonb);
-- select count(*) from ripples.trend_obs where observed_at > now() - interval '2 minutes';

-- A7. fluke rates (4 S-bins) and Call It medians >= 2000
select as_of, sbin, real_tested, real_pass, decoy_tested, decoy_pass, fluke, fluke_bins from ripples.fluke_rates
 where as_of = '2026-09-24' order by sbin;
select n, qid, title, baseline_median, model_p, window_start, window_end from ripples.callit where n = -1;

-- Grants: every W2 service function is executable by service_role only
select * from ripples._grant_audit();

-- ---------------------------------------------------------------------------------------------------------------
-- Checks added with sql/18 (independent verifier findings)

-- V1. SPEC 5.2 fluke gate: warm-up threshold is 500 pooled decoy tests; every answer has f <= 0.10 unless the meter was
--     warming (then p_time <= 0.05), and the reveal's fluke fields agree with fluke_rates.
select (select value->>'fluke_warm_min_decoy' from ripples.config where key = 'pipeline') warm_min,
       (select value->>'fluke_gate_fallback' from ripples.config where key = 'pipeline') fallback;
with p as (select * from ripples.puzzles where n = -1)
select (r->>'i')::int i, r->>'answer_qid' qid, c.s_stat, fl.f, fl.warming, c.p_time,
       (fl.warming and c.p_time <= 0.05) or (not fl.warming and fl.f <= 0.10) as answer_gate_ok,
       r->'evidence'->>'fluke' reveal_fluke, r->'evidence'->>'fluke_warming' reveal_warming,
       (select decoy_tested from ripples.fluke_rates f where f.as_of = p.data_date limit 1) pooled_decoy_tested
  from p cross join lateral jsonb_array_elements(p.reveal->'rounds') r
  join lateral (select * from ripples.candidates c where c.as_of = p.data_date and c.role = 'real' and c.qid = r->>'answer_qid'
                   and c.parent_qid = (select x->'parent'->>'qid' from jsonb_array_elements(p.payload->'rounds') x where x->>'i' = r->>'i')) c on true
  cross join lateral ripples._fluke(p.data_date, c.s_stat) fl order by 1;

-- V2. SPEC 12.3: every decoy's 90-day sparkline reads flat: max day < min(3.0, 0.75 x answer multiple) x its baseline median
with p as (select * from ripples.puzzles where n = -1)
select (r->>'i')::int i, o->>'qid' qid, (o->>'median')::numeric median,
       (select max(v::numeric) from jsonb_array_elements_text(o->'spark') v) spark_max,
       round((select max(v::numeric) from jsonb_array_elements_text(o->'spark') v) / greatest((o->>'median')::numeric, 1), 2) peak_ratio,
       (select (a->>'multiple')::numeric from jsonb_array_elements(r->'options') a where a->>'id' = r->>'answer') answer_multiple
  from p cross join lateral jsonb_array_elements(p.reveal->'rounds') r cross join lateral jsonb_array_elements(r->'options') o
 where o->>'id' <> r->>'answer' order by 1, 2;

-- V3. SPEC 5.4 in daily running: every human seed / option / Call It article was re-checked during the run
with p as (select * from ripples.puzzles where n = -1),
q as (select p.payload->'seed'->>'qid' qid from p
      union select r->'seed'->>'qid' from p, jsonb_array_elements(p.payload->'rounds') r where r->'seed' <> 'null'
      union select o->>'qid' from p, jsonb_array_elements(p.payload->'rounds') r, jsonb_array_elements(r->'options') o
      union select o->>'qid' from p, jsonb_array_elements(p.payload->'callit'->'options') o)
select count(*) articles, count(*) filter (where a.is_human) humans,
       count(*) filter (where a.is_human and a.updated_at < ru.started_at) humans_not_rechecked,
       count(*) filter (where not ripples._safe(a.qid, p.data_date, null, true)) unsafe
  from q join ripples.articles a using (qid) cross join p join ripples.runs ru on ru.as_of = p.data_date;
select as_of, stage, detail->'recheck_seed_jobs' seed_jobs, detail->'recheck_build_jobs' build_jobs,
       (select jsonb_agg(j.result) from ripples.jobs j where j.as_of = r.as_of and j.kind = 'resolve' and j.payload ? 'recheck') results
  from ripples.runs r where as_of = '2026-09-24';
-- (b) a death year in the short description counts before Wikidata has P570 (rolled back)
do $$
declare a boolean; b boolean;
begin
  perform public.ripples_ingest_articles(jsonb_build_object('articles', jsonb_build_array(jsonb_build_object(
    'qid', 'Q999999902', 'title_en', 'Test Person Desc Only', 'short_desc', 'Test actor (1950–2026)',
    'p31', jsonb_build_array('Q5'), 'date_of_death', null, 'sitelinks', 40))));
  a := ripples._safe('Q999999902', current_date - 1, 5000);
  update ripples.articles set short_desc = 'Test actor (1950–2019)' where qid = 'Q999999902';
  b := ripples._safe('Q999999902', current_date - 1, 5000);
  raise exception 'V3b safe_with_2026_death_year=% (expect false) safe_with_2019_death_year=% (expect true)', a, b;
end $$;

-- V4. wording: badge follows timing (lag 0 -> spiked_alongside unless flowed); headline has no "next"
with p as (select * from ripples.puzzles where n = -1)
select (r->>'i')::int i, r->'evidence'->>'badge' badge,
       (select a->>'timing' from jsonb_array_elements(r->'options') a where a->>'id' = r->>'answer') timing,
       p.payload->'headline'->>'text' headline
  from p cross join lateral jsonb_array_elements(p.reveal->'rounds') r order by 1;

-- V5. Board vs puzzle: no puzzle seed (round 1's or a fresh ripple's) is a belly_flop
with p as (select * from ripples.puzzles where n = -1),
s as (select p.payload->'seed'->>'qid' qid from p union select r->'seed'->>'qid' from p, jsonb_array_elements(p.payload->'rounds') r where r->'seed' <> 'null')
select t->>'title' title, t->>'quadrant' quadrant, t->>'wake_k' wake_k, t->>'wake_of' wake_of
  from p cross join lateral jsonb_array_elements(p.board->'trends') t where t->>'qid' in (select qid from s);

-- V6. dispatch: decoy depth-1 expand jobs were not skipped; no deeper real beam started before the last depth-1 job
select as_of,
       count(*) filter (where kind = 'expand' and role = 'decoy') decoy_jobs,
       count(*) filter (where kind = 'expand' and role = 'decoy' and status = 'done') decoy_done,
       count(*) filter (where kind = 'expand' and depth = 1 and status = 'skipped') depth1_skipped,
       (select min(started_at) from ripples.jobs x where x.as_of = j.as_of and x.kind = 'expand' and x.depth >= 2)
         >= max(started_at) filter (where kind = 'expand' and depth = 1) depth_order_ok
  from ripples.jobs j where as_of in ('2026-09-23', '2026-09-24') group by as_of order by as_of;

-- V7. EXECUTE on W2 helpers: nobody but postgres / service_role
select p.oid::regprocedure fn, p.proacl from pg_proc p
 where p.pronamespace = 'ripples'::regnamespace and p.proname like '\_%'
   and (p.proacl is null or has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'));
