-- 15b_att_charts_cron (W7 att-charts, 2026-09-25, applied as migration att_charts_cron)
-- ATTENTION_STACK §3.4 schedule for att-charts (UTC). All discovery candidates land before the 06:24 att_discover_trends
-- / 06:25 SPEC resolve stage. Apple needs three slots because 25 feeds at the 5 s floor (DEMARCATION Q6) do not fit one
-- 110 s run; the mode is resumable (att_state 'charts.apple') and a slot with nothing left makes no request.
-- Backfill jobs (npm.dl, pypi.dl, anilist, gh.stars) are drained by the existing 'att-backfill' cron through
-- ripples.att_tick('backfill') once att-charts is on the live_fns allow-list (ripples.att_fn_live('att-charts')).
do $$
declare j text;
begin
  foreach j in array array['att-apple-1','att-apple-2','att-apple-3','att-steamspy','att-hf','att-github',
                           'att-openlibrary','att-anilist','att-npm','att-pypi','att-tranco'] loop
    perform cron.unschedule(j) where exists (select 1 from cron.job where jobname = j);
  end loop;
end $$;

select cron.schedule('att-apple-1',     '10 6 * * *', $$select public.call_collector('att-charts', '{"mode":"apple"}'::jsonb)$$);
select cron.schedule('att-apple-2',     '13 6 * * *', $$select public.call_collector('att-charts', '{"mode":"apple"}'::jsonb)$$);
select cron.schedule('att-apple-3',     '16 6 * * *', $$select public.call_collector('att-charts', '{"mode":"apple"}'::jsonb)$$);
select cron.schedule('att-steamspy',    '12 6 * * *', $$select public.call_collector('att-charts', '{"mode":"steamspy"}'::jsonb)$$);
select cron.schedule('att-hf',          '13 6 * * *', $$select public.call_collector('att-charts', '{"mode":"hf"}'::jsonb)$$);
select cron.schedule('att-github',      '14 6 * * *', $$select public.call_collector('att-charts', '{"mode":"github"}'::jsonb)$$);
select cron.schedule('att-openlibrary', '15 6 * * *', $$select public.call_collector('att-charts', '{"mode":"openlibrary"}'::jsonb)$$);
select cron.schedule('att-anilist',     '17 6 * * *', $$select public.call_collector('att-charts', '{"mode":"anilist"}'::jsonb)$$);
select cron.schedule('att-npm',         '18 6 * * *', $$select public.call_collector('att-charts', '{"mode":"npm"}'::jsonb)$$);
select cron.schedule('att-pypi',        '19 6 * * *', $$select public.call_collector('att-charts', '{"mode":"pypi"}'::jsonb)$$);
select cron.schedule('att-tranco',      '19 6 * * *', $$select public.call_collector('att-charts', '{"mode":"tranco"}'::jsonb)$$);
