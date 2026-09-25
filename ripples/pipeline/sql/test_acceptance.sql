-- Knock-On v5 / W2 acceptance checks (read-only unless noted). Run with the MCP execute_sql tool or psql as postgres.
-- Replace :as_of / :n below (the defaults are the first practice run: as_of 2026-09-24 -> n = -1).

-- A1. run finished, Wikimedia calls under the cap, job errors < 10% of jobs, wall time
select r.as_of, r.kind, r.stage, r.wm_calls, (ripples._cfg('wm_daily_cap') #>> '{}')::int as cap,
       r.finished_at - r.started_at as took,
       (select count(*) from ripples.jobs j where j.as_of = r.as_of) as jobs,
       (select count(*) from ripples.jobs j where j.as_of = r.as_of and j.status = 'failed') as failed_jobs,
       round(100.0 * (select count(*) from ripples.jobs j where j.as_of = r.as_of and j.status = 'failed')
             / nullif((select count(*) from ripples.jobs j where j.as_of = r.as_of), 0), 1) as failed_pct,
       r.errors as failed_attempts
  from ripples.runs r where r.kind = 'practice' order by r.as_of desc;

-- A2. rounds and the evidence behind every answer / decoy (expects 3-4 rounds; all flags true)
with p as (select * from ripples.puzzles where n = -1),
r as (select (rr->>'i')::int i, rr from p, jsonb_array_elements(p.reveal->'rounds') rr),
pr as (select (x->>'i')::int i, x from p, jsonb_array_elements(p.payload->'rounds') x),
opt as (
  select r.i, o, (o->>'id') = (r.rr->>'answer') is_ans, pr.x from r join pr using (i), jsonb_array_elements(r.rr->'options') o)
select opt.i, opt.is_ans, o->>'qid' qid, a.title_en, a.category,
       c.pass_raw, c.p_time, c.multiple, c.onset_lag, c.split_ok, c.calm, round(c.median_views) med
  from opt
  join ripples.puzzles p on p.n = -1
  join ripples.candidates c on c.as_of = p.data_date and c.role = 'real' and c.qid = o->>'qid'
   and c.parent_qid = (opt.x->'parent'->>'qid')
  join ripples.articles a on a.qid = c.qid
 order by opt.i, opt.is_ans desc;

-- A4. answer_h equals sha256(n|i|answer_qid) and differs for every decoy
select pr.i,
       pr.x->>'answer_h' = encode(extensions.digest(p.n || '|' || pr.i || '|' || (a->>'qid'), 'sha256'), 'hex') as answer_matches,
       bool_and(encode(extensions.digest(p.n || '|' || pr.i || '|' || (o->>'qid'), 'sha256'), 'hex') <> pr.x->>'answer_h')
         filter (where o->>'qid' <> a->>'qid') as decoys_differ
  from ripples.puzzles p
  cross join lateral (select (x->>'i')::int i, x from jsonb_array_elements(p.payload->'rounds') x) pr
  join lateral jsonb_array_elements(p.answers) a on (a->>'i')::int = pr.i
  cross join lateral jsonb_array_elements(pr.x->'options') o
 where p.n = -1 group by pr.i, pr.x, p.n, a;

-- A5. safety: a synthetic human who died 5 days ago is excluded (run inside a transaction and roll back)
-- begin;
--   insert into ripples.articles (qid, title_en, category, emoji, p31, date_of_death, is_human, sitelinks)
--   values ('Q999999901', 'Test Recently Deceased Person', 'person', '👤', '{Q5}', current_date - 5, true, 40);
--   select ripples._safe('Q999999901', current_date - 1, 5000) as safe_should_be_false;
--   ... (see the W2 report for the full pick/build exclusion test)
-- rollback;

-- A6. cron jobs
select jobname, schedule, command, active from cron.job where jobname like 'ripples-%' order by jobname;

-- A7. fluke rates (4 S-bins) and Call It medians
select * from ripples.fluke_rates where as_of = '2026-09-24' order by sbin;
select n, qid, title, baseline_median, model_p, window_start, window_end from ripples.callit where n = -1;

-- Grants: every W2 service function is executable by service_role only
select * from ripples._grant_audit();
