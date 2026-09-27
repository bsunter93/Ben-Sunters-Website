-- Knock-On v5 / W2: pg_cron jobs (SPEC §5.5). Re-running replaces the jobs (cron.schedule upserts by name).
select cron.schedule('ripples-trends-hourly', '7 * * * *', $$select public.call_collector('ripples-collect', '{"mode":"trends"}'::jsonb)$$);
select cron.schedule('ripples-tick', '* 6-8 * * *', $$select public.ripples_tick()$$);
select cron.schedule('ripples-retention', '50 3 * * *', $$select public.ripples_retention()$$);
-- 'ripples-run-day' ('20 seconds', select public.ripples_tick()) is created by ripples_run_day() and removes itself.
