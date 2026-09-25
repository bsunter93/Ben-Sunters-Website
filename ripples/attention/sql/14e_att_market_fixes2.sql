-- Migration `att_market_fixes2` (W7 att-market builder, 2026-09-25, second verification round; code MARKET_VERSION
-- 2026-09-25.m8, deploy v10). Data/ops only; no new objects, no grants changed.
-- 1. USAspending backfill gaps: until m7 a 3-month window that timed out was recorded as walked (att_state 'usasp.bf'
--    moved past it) and never retried. m8 tracks such windows in att_state 'usasp.bfgap' {key: {window_start: tries}}
--    and retries them first (give-up after 3 failed tries). Seed 'usasp.bfgap' with the windows already lost: every
--    walked backfill window (from the newest backfill window, current month - 5, down to usasp.bf[key]) that has no
--    stored month at all.
-- 2. Close the orphan run row 525 (att-market kalshi, killed by WORKER_RESOURCE_LIMIT before Run.finish).
-- 3. Queued att-market jobs deferred to 00:10 UTC: att-backfill (att_tick('backfill')) only runs 10:00-23:58 UTC, so
--    set their not_before to 10:05 UTC (what m8 settleJobs now writes) so the queue states when they will really run.
do $$
declare
  bf jsonb := coalesce((select v from ripples.att_state where k = 'usasp.bf'), '{}'::jsonb);
  gaps jsonb := coalesce((select v from ripples.att_state where k = 'usasp.bfgap'), '{}'::jsonb);
  kk text; oldest date; w date; newest date := (date_trunc('month', current_date) - interval '5 months')::date;
  has int;
begin
  for kk in select jsonb_object_keys(bf) loop
    oldest := (bf ->> kk)::date;
    w := newest;
    while w >= oldest loop
      select count(*) into has
        from ripples.attention_obs o join ripples.att_series s on s.series_id = o.series_id
       where s.source = 'usasp.spend' and s.key = kk and o.day >= w and o.day < (w + interval '3 months')::date;
      if has = 0 then
        gaps := jsonb_set(gaps, array[kk], coalesce(gaps -> kk, '{}'::jsonb) || jsonb_build_object(w::text, 1), true);
      end if;
      w := (w - interval '3 months')::date;
    end loop;
  end loop;
  insert into ripples.att_state (k, v, updated_at) values ('usasp.bfgap', gaps, now())
  on conflict (k) do update set v = excluded.v, updated_at = now();
end $$;

update ripples.att_runs
   set finished_at = started_at + interval '110 seconds', ok = false, partial = true,
       error = 'WORKER_RESOURCE_LIMIT: worker killed before Run.finish (row closed by builder 2026-09-25; requests counted in att_budget)'
 where run_id = 525 and fn = 'att-market' and finished_at is null;

update ripples.att_jobs
   set not_before = date_trunc('day', not_before) + interval '10 hours 5 minutes'
 where fn = 'att-market' and status = 'queued'
   and not_before::time < time '10:00' and not_before > now();

-- 4. (applied as migration `att_market_fixes2b`) keys whose backfill job was already 'done' but now have seeded gaps
--    ('die linke', "anna's archive", 'new people') get their job requeued so m8 retries the lost windows.
update ripples.att_jobs j
   set status = 'queued', not_before = (current_date + 1) + interval '10 hours 5 minutes', finished_at = null,
       error = 'requeued: retry timed-out USAspending windows (usasp.bfgap)'
 where j.fn = 'att-market' and j.status = 'done' and j.payload -> 'params' ->> 'source' = 'usasp.spend'
   and (select v from ripples.att_state where k = 'usasp.bfgap') ? (j.payload -> 'keys' -> 0 ->> 'key');

-- ---- applied 2026-09-25 ~19:05 UTC. Result: usasp.bfgap = {die linke: [2025-10-01], new people: [2026-01-01,
-- 2026-04-01], anna's archive: [2025-01-01, 2026-04-01], 2026 asian games: [2025-10-01]} (each 1 failed try);
-- run 525 closed (ok=false, partial=true); the 48 queued att-market jobs (incl. finra:files 2086) not_before
-- 2026-09-26 10:05 UTC; jobs 2035 / 2036 / 2060 requeued for the same time (51 queued in all). Ping run 799 = m8.
