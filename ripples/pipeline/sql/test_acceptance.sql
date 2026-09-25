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
