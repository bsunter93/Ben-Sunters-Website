-- 16b_att_world_cron (W7 att-world, 2026-09-25, applied as migration att_world_cron)
-- ATTENTION_STACK §3.4: `21 6 * * *` att-world {"mode":"all"}. Split into two invocations so each stays well inside the
-- edge CPU budget: the light API sources at 06:21 and the two file sources (Hiring Lab conditional GET, Citi Bike monthly
-- archive) at 06:22. Both land before the 06:24 att_discover_trends / 06:25 resolve stage.
-- TSA publishes the previous day's number around 12:30 UTC and MTA updates in the day, so a 13:41 pass fills in as_of
-- values the 06:21 pass could not see yet (1 request each; DEMARCATION Q6 daily cadence).
-- Backfill jobs (queued once, source rows backfill_fn = 'att-world') are drained by the existing 'att-backfill' cron via
-- ripples.att_tick('backfill') once att-world is on the live_fns allow-list.
do $$
declare j text;
begin
  foreach j in array array['att-world','att-world-files','att-world-pm'] loop
    perform cron.unschedule(j) where exists (select 1 from cron.job where jobname = j);
  end loop;
end $$;

select cron.schedule('att-world',       '21 6 * * *',
  $$select public.call_collector('att-world', '{"mode":"all","params":{"only":["tsa","usgs","iem","fema","gdacs","mta"]}}'::jsonb)$$);
select cron.schedule('att-world-files', '22 6 * * *',
  $$select public.call_collector('att-world', '{"mode":"all","params":{"only":["hiringlab","citibike"]}}'::jsonb)$$);
select cron.schedule('att-world-pm',    '41 13 * * *',
  $$select public.call_collector('att-world', '{"mode":"all","params":{"only":["tsa","mta"]}}'::jsonb)$$);

select ripples.att_fn_live('att-world');
