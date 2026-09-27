-- 41: operations after the 2026-09-27 04:24 UTC outage (no statistical change).
--
-- What happened: session 2 ran two fx63 step workers, two finishers, the b8 tick (45 s of work per minute) and a one-off
-- b7 decoy seed (~330k inserts in ONE transaction) on top of ~a dozen existing every-minute jobs. The instance used up
-- its disk-IO burst budget, throughput fell to the 5 MB/s baseline, statements timed out, cron jobs failed to start and
-- the database stopped accepting connections until the owner restarted it (05:24 UTC). Committed work survived: b6
-- and b7 exploration were complete; the b7 seed transaction never committed; b8 had 131/273 screen tasks done.
--
-- Changes (applied 05:40 UTC):
--  1. att_fx63_decoy_seed_grid(batch, grid): the same seeding as att_fx63_decoy_seed, one grid per call (same per-grid
--     random seeds, so the rows are identical to a single-transaction run). b7 is seeded 3 grids per job run.
--     The b7 finisher stays unscheduled until every b7 grid has its dx rows, otherwise stage 2 could select on a
--     partial decoy set. Re-arm it with:
--       select cron.schedule('att-fx63-finisher-fx63-b7-decade', '4-59/5 * * * *',
--         $$set statement_timeout = '100s'; select ripples.att_fx63_finisher('fx63-b7-decade')$$);
--  2. b8 tick budget 45 s -> 25 s; job every 4 minutes with an 80 s statement timeout; slow retry hourly.
--  3. One fx63 step worker (35 s every 2 minutes) instead of two every minute; b6 finisher every 5 minutes.
--  4. Jobs staggered across minutes (step even minutes, b8 1-59/4, seed 3-59/4, finisher 2-59/5).
-- Rule for later sessions: never add more than one heavy every-minute job, and never write >~20k rows in one
-- transaction on this instance.

do $$ declare d text;
begin
  d := pg_get_functiondef('ripples.att_fx63_decoy_seed(text,integer)'::regprocedure);
  d := replace(d, 'ripples.att_fx63_decoy_seed(p_batch text, p_sets integer DEFAULT NULL::integer)', 'ripples.att_fx63_decoy_seed_grid(p_batch text, p_grid integer, p_sets integer DEFAULT NULL::integer)');
  if position('where batch like p_batch || ''/%'' order by grid_id' in d) = 0 then raise exception 'anchor grid loop'; end if;
  d := replace(d, 'where batch like p_batch || ''/%'' order by grid_id', 'where batch like p_batch || ''/%'' and grid_id = p_grid order by grid_id');
  if position('''engine63.decoy_seed''' in d) = 0 then raise exception 'anchor state'; end if;
  d := replace(d, '''engine63.decoy_seed''', '''engine63.decoy_seed:'' || p_batch');
  execute d;
end $$;
revoke all on function ripples.att_fx63_decoy_seed_grid(text, integer, integer) from anon, authenticated, public;

do $$ declare d text; a text := $a$clock_timestamp() - t0 > interval '45 seconds'$a$; b text := $b$clock_timestamp() - t0 > interval '25 seconds'$b$;
begin d := pg_get_functiondef('ripples.att_anom_tick(text)'::regprocedure);
  if position(b in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'tick anchor'; end if; execute replace(d, a, b); end $$;

select cron.schedule('att-fx63-step-1', '*/2 * * * *', $$set statement_timeout = '80s'; select ripples.att_fx63_step(35)$$);
select cron.schedule('att-fx63-seed-b7', '3-59/4 * * * *', $$set statement_timeout = '100s';
  select ripples.att_fx63_decoy_seed_grid('fx63-b7-decade', g.grid_id) from (select g.grid_id from ripples.att_fx_grid g where g.batch like 'fx63-b7-decade/%'
    and not exists (select 1 from ripples.att_fx_event f where f.grid_id = g.grid_id and f.role = 'dx') order by g.grid_id limit 3) g$$);
select cron.schedule('att-anom-b8', '1-59/4 * * * *', $c$
  set statement_timeout = '80s';
  select ripples.att_anom_tick('b8-anomaly-first')
   where coalesce((ripples._att_cfg('engine63') ->> 'anom_go')::boolean, false)
     and exists (select 1 from ripples.att_anom_queue where run = 'b8-anomaly-first')
     and not exists (select 1 from ripples.att_anom_queue where run = 'b8-anomaly-first' and stage = 'done')
$c$);
select cron.schedule('att-anom-b8-slow', '37 * * * *', $c$
  set statement_timeout = '300s';
  select ripples.att_anom_retry('b8-anomaly-first') where exists (select 1 from ripples.att_anom_queue where run = 'b8-anomaly-first' and status = 'timeout')
$c$);
select cron.schedule('att-fx63-finisher-fx63-b6-unexpected', '2-59/5 * * * *', $$set statement_timeout = '100s'; select ripples.att_fx63_finisher('fx63-b6-unexpected')$$);

-- 06:30 UTC addendum.
--  5. b8: att_norm_cdf underflowed on one screen task with an extreme z, so every tick failed (05:41-06:25) and the
--     queue stalled on that task. z is clamped to [-30, 30] before the CDF (ledger 1225; no rule change).
--  6. The b6 finisher's verdict stage needs more than 100 s: it now runs every 10 minutes with a 280 s timeout.
--  7. b7 decoy seed raised to 6 grids per run (runs took ~6 s at 3 grids).
do $$ declare d text;
  a text := $a$1 - ripples.att_norm_cdf(((o.r - nl.m) / nl.s)::float8)$a$;
  b text := $b$1 - ripples.att_norm_cdf(least(30, greatest(-30, (o.r - nl.m) / nl.s))::float8)$b$;
begin d := pg_get_functiondef('ripples.att_anom_link(text,text,text,text,text,text,text,integer)'::regprocedure);
  if position(b in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'cdf anchor'; end if; execute replace(d, a, b); end $$;
select cron.schedule('att-fx63-finisher-fx63-b6-unexpected', '6-59/10 * * * *', $$set statement_timeout = '280s'; select ripples.att_fx63_finisher('fx63-b6-unexpected')$$);
select cron.schedule('att-fx63-seed-b7', '3-59/4 * * * *', $$set statement_timeout = '100s';
  select ripples.att_fx63_decoy_seed_grid('fx63-b7-decade', g.grid_id) from (select g.grid_id from ripples.att_fx_grid g where g.batch like 'fx63-b7-decade/%'
    and not exists (select 1 from ripples.att_fx_event f where f.grid_id = g.grid_id and f.role = 'dx') order by g.grid_id limit 6) g$$);

-- 07:40 UTC: b8 post-verdict robustness (ledger 1229, late disclosure). 5 confirmations on dol.claims ic_w withheld as a
-- year-composition confound; b7 seed back to 3 grids per run after one 100 s timeout at 6.
update ripples.att_anom_hyp set verdict = 'withheld (year confound)'
 where run = 'b8-anomaly-first' and stage = 'explore' and promoted and verdict = 'confirmed' and source = 'dol.claims' and metric = 'ic_w';
