-- 16c_att_world_fixes.sql  (migration att_world_fixes, 2026-09-25, att-world WORLD_VERSION 2026-09-25.w3)
-- Verifier follow-ups for att-world:
--  1. citibike.trips per_day_cap was raised to 30 for the one-off 14-month JC backfill. A cron job puts it back to the
--     steady-state 4 (1 bucket listing + 1 monthly file + 1 NYC size listing per month, plus one spare) as soon as the
--     backfill cursor world.bf.citibike.trips says complete (or on 2026-09-28 00:00 UTC at the latest, whichever comes
--     first), lowers the same day's att_budget row too, and then unschedules itself.
--  2. Ledger entry (DEMARCATION §1.1 / §6.7) for the Citi Bike virtual-host robots.txt decision, stored in
--     att_sources.license_note / reason and as att_state 'ledger:citibike.trips' (also recorded in README.md).
--  3. att_runs 599 (IEM backfill stopped by per_run_cap:iem.warn) relabelled from 'http_error' to 'budget_exhausted';
--     w3 of the function labels such stops itself.
-- No new tables or functions; nothing granted to anon/authenticated.

-- 1 ---------------------------------------------------------------------------------------------------------------
select cron.unschedule(jobid) from cron.job where jobname = 'att-world-citibike-cap';
select cron.schedule('att-world-citibike-cap', '7,27,47 * * * *', $cron$
  with done as (
    select coalesce((select (v->>'complete')::boolean from ripples.att_state where k = 'world.bf.citibike.trips'), false)
           or now() >= timestamptz '2026-09-28 00:00+00' as ok
  ), src as (
    update ripples.att_sources
       set per_day_cap = 4,
           reason = 'Q6: no published limit -> 1 req/5 s; steady state 4/day (bucket listing + 1 JC monthly file + NYC size listing, once a month after the 6th). The one-off 14-month JC backfill ran at 30/day on 2026-09-25 and was reset automatically. NYC monthly files are ~1 GB: too large for the 110 s / CPU budget, reported partial'
     where source = 'citibike.trips' and per_day_cap > 4 and (select ok from done)
    returning 1
  )
  update ripples.att_budget
     set cap = least(cap, greatest(used, 4))
   where bucket = 'citibike.trips' and day = (now() at time zone 'utc')::date and exists (select 1 from src);
  select cron.unschedule(jobid) from cron.job
   where jobname = 'att-world-citibike-cap'
     and exists (select 1 from ripples.att_sources where source = 'citibike.trips' and per_day_cap <= 4);
$cron$);

-- 2 ---------------------------------------------------------------------------------------------------------------
update ripples.att_sources
   set license_note = 'Citi Bike Data License Agreement (citibikenyc.com/data-sharing-policy); no use of its trademarks. '
       || 'Ledger 2026-09-25: fetched via the bucket virtual-host tripdata.s3.amazonaws.com (robots.txt 404 = allowed). '
       || 'The path-style s3.amazonaws.com/robots.txt answers 403 AccessDenied (S3''s generic response for the bucket-less '
       || 'root, not a bot barrier); both addresses reach the same public bucket Citi Bike links from its System Data page. '
       || 'Decided by the W7 lead under DEMARCATION Q3 (documented channel); owner to confirm.'
 where source = 'citibike.trips';

select ripples.att_state_set('ledger:citibike.trips', jsonb_build_object(
  'date', '2026-09-25',
  'source', 'citibike.trips',
  'tier', 'G',
  'terms', jsonb_build_object('url', 'https://citibikenyc.com/data-sharing-policy',
    'clause', 'Citi Bike Data License Agreement: public trip data may be used for analysis; no use of Citi Bike trademarks'),
  'paths', jsonb_build_array('https://tripdata.s3.amazonaws.com/?list-type=2&prefix=...',
                             'https://tripdata.s3.amazonaws.com/JC-YYYYMM-citibike-tripdata[.csv].zip'),
  'robots', jsonb_build_array(
    jsonb_build_object('url', 'https://tripdata.s3.amazonaws.com/robots.txt', 'status', 404, 'body', 'S3 NoSuchKey',
      'sha256', 'bf1b20d0472320c1d2243e72bc16a4996ec8d57bc22c2e6f1c9220cc823982e4', 'verdict', 'allowed (no robots.txt)'),
    jsonb_build_object('url', 'https://s3.amazonaws.com/robots.txt', 'status', 403, 'body', 'S3 AccessDenied',
      'sha256', 'c72db483c17a4d3ac1d22a2f112cf3b585cbd3c00dfa9c3cf084e64b9c524c1c',
      'verdict', 'not used: generic S3 AccessDenied for the bucket-less root; att.ts would treat it as a permanent kill')),
  'decision', 'Use the virtual-host address of the documented public bucket; never the path-style host. NYC monthly files (~1 GB) are not downloaded.',
  'decided_by', 'W7 lead (DEMARCATION Q3 documented-channel rule); owner confirmation pending',
  'recheck', '2026-12-24'));

-- 3 ---------------------------------------------------------------------------------------------------------------
update ripples.att_runs
   set detail = jsonb_set(detail, '{sources,0}',
         (detail->'sources'->0) || jsonb_build_object('status', 'budget_exhausted',
            'note', coalesce(detail->'sources'->0->>'note', '') || '; stopped by per_run_cap:iem.warn (relabelled 2026-09-25)'))
 where run_id = 599 and fn = 'att-world'
   and detail->'sources'->0->>'source' = 'iem.warn' and detail->'sources'->0->>'status' = 'http_error';
