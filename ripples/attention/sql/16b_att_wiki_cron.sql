-- 16b_att_wiki_cron (W7 att-wiki, 2026-09-25, applied as migration att_wiki_cron)
-- ATTENTION_STACK §3.4 schedule for att-wiki (UTC). No attention Wikimedia call between 06:30 and 07:20 (main
-- pipeline window): enforced by att_take_budget / politeFetch whatever the schedule says.
--   att-topcc      06:23  top_country (before att_discover_trends 06:24 / SPEC resolve 06:25)
--   att-topcc-2/3  09:23, 13:23  top_country again: fills countries whose list was not published yet (no-op when all done)
--   att-wiki-pv-1..3  07:21, 07:24, 07:27  pageviews (active topics first; §3.4 says 07:22 - moved to keep three
--                  110 s runs clear of each other and of the 07:33 hop tick)
--   att-wiki-pv-pm :07 past 10-23  pageviews continuation (panel incrementals, first sight of new registrations)
--   att-media      07:30 (+ 12:37)  mediarequests (§3.4 says 07:24; deferred automatically until pageview histories exist)
--   att-clickstream  10:31 on the 7th  clickstream_small (HEAD size check; large files are GitHub-Action-only)
-- wiki.pv backfill jobs are drained by the existing att-backfill cron (att_tick('backfill'), */2 10-23) once att-wiki is
-- on the live_fns allow-list.
do $$
declare j text;
begin
  foreach j in array array['att-topcc','att-topcc-2','att-topcc-3','att-wiki-pv-1','att-wiki-pv-2','att-wiki-pv-3',
                           'att-wiki-pv-pm','att-media','att-media-pm','att-clickstream'] loop
    perform cron.unschedule(j) where exists (select 1 from cron.job where jobname = j);
  end loop;
end $$;

select cron.schedule('att-topcc',       '23 6 * * *',     $$select public.call_collector('att-wiki', '{"mode":"top_country"}'::jsonb)$$);
select cron.schedule('att-topcc-2',     '23 9 * * *',     $$select public.call_collector('att-wiki', '{"mode":"top_country"}'::jsonb)$$);
select cron.schedule('att-topcc-3',     '23 13 * * *',    $$select public.call_collector('att-wiki', '{"mode":"top_country"}'::jsonb)$$);
select cron.schedule('att-wiki-pv-1',   '21 7 * * *',     $$select public.call_collector('att-wiki', '{"mode":"pageviews"}'::jsonb)$$);
select cron.schedule('att-wiki-pv-2',   '24 7 * * *',     $$select public.call_collector('att-wiki', '{"mode":"pageviews"}'::jsonb)$$);
select cron.schedule('att-wiki-pv-3',   '27 7 * * *',     $$select public.call_collector('att-wiki', '{"mode":"pageviews"}'::jsonb)$$);
select cron.schedule('att-wiki-pv-pm',  '7 10-23 * * *',  $$select public.call_collector('att-wiki', '{"mode":"pageviews"}'::jsonb)$$);
select cron.schedule('att-media',       '30 7 * * *',     $$select public.call_collector('att-wiki', '{"mode":"mediarequests"}'::jsonb)$$);
select cron.schedule('att-media-pm',    '37 12 * * *',    $$select public.call_collector('att-wiki', '{"mode":"mediarequests"}'::jsonb)$$);
select cron.schedule('att-clickstream', '31 10 7 * *',    $$select public.call_collector('att-wiki', '{"mode":"clickstream_small"}'::jsonb)$$);

-- dispatch queued wiki.pv backfill jobs to att-wiki (att_tick allow-list)
select ripples.att_fn_live('att-wiki', true);
