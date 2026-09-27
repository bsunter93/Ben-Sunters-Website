-- Migration `att_market_cron` (W7 att-market builder, 2026-09-25). Schedule per ATTENTION_STACK §3.4 (UTC).
--   att-finra      02 06  FINRA previous trading day (Query API), mirror + tickers + abnormal-volume candidates
--   att-predmkts   03 06  Polymarket;  att-kalshi 04 06  Kalshi   (before att-discover 06:24 / resolve 06:25)
--   att-usasp      27 07  USAspending rotation (each key every 7 days)
--   att-edgar      26 07  SEC EDGAR: scheduled but INACTIVE (sec.efts disabled: needs owner contact email)
-- Backfill jobs (FINRA files and tickers, USAspending windows) drain through att-backfill (att_tick('backfill'),
-- */2 10-23) once att-market is on the live_fns allow-list.
do $$
declare j text;
begin
  foreach j in array array['att-finra','att-predmkts','att-kalshi','att-usasp','att-edgar'] loop
    if exists (select 1 from cron.job where jobname = j) then perform cron.unschedule(j); end if;
  end loop;
end $$;
select cron.schedule('att-finra',    '2 6 * * *',  $$select public.call_collector('att-market', '{"mode":"finra"}'::jsonb)$$);
select cron.schedule('att-predmkts', '3 6 * * *',  $$select public.call_collector('att-market', '{"mode":"polymarket"}'::jsonb)$$);
select cron.schedule('att-kalshi',   '4 6 * * *',  $$select public.call_collector('att-market', '{"mode":"kalshi"}'::jsonb)$$);
select cron.schedule('att-usasp',    '27 7 * * *', $$select public.call_collector('att-market', '{"mode":"usaspending"}'::jsonb)$$);
select cron.schedule('att-edgar',    '26 7 * * *', $$select public.call_collector('att-market', '{"mode":"edgar"}'::jsonb)$$);
select cron.alter_job(jobid, active := false) from cron.job where jobname = 'att-edgar';
select ripples.att_fn_live('att-market', true);

-- ---- operational record (applied with execute_sql during the first test runs, 2026-09-25 ~15:36 UTC)
-- Gamma /markets returns at most 100 rows per page (limit=500 is capped); Kalshi open events = ~14.6k (73 pages of 200).
update ripples.att_config set value = value || '{"poly_page":100,"poly_max_pages":15,"kalshi_max_pages":100}'::jsonb
 where key = 'market';
-- today's finra.api budget row had been created with the first cap (250) before the source row was raised to 500:
update ripples.att_budget set cap = 500 where bucket = 'finra.api' and day = date '2026-09-25';
-- topic-match cleanup after the matcher experiment (m3 briefly dropped single-word terms; m4 restored them):
--   deleted the day-1 poly/kalshi 'topic:<id>' series (re-created by the next run) and restored 9 event/market topic links.
-- m5 (short-lived recurring markets excluded): the day-1 kalshi.mkt rows and poly.mkt vol24h rows for 2026-09-25 plus
-- their candidates were deleted (orphan series removed) and both modes re-run with m5 the same afternoon.
-- FINRA file backfill job priority raised to 4 for the first-day backfill (ticker / USAspending jobs are 5); set back to
-- 6 after the first 60 trading days were mirrored:
--   update ripples.att_jobs set priority = 6 where dedupe_key = 'finra:files' and status in ('queued','running');

-- ---- m6 (2026-09-25 ~16:15 UTC): a single Kalshi run over all ~73 pages hit WORKER_RESOURCE_LIMIT (HTTP 546) once, so
-- the crawl is split over up to four runs (25 pages each, cursor + day sums in att_state 'kalshi.crawl').
update ripples.att_config set value = (value - 'kalshi_max_events' - 'kalshi_max_markets')
  || '{"kalshi_pages_per_run":25,"kalshi_chunk_events":80,"kalshi_chunk_markets":40}'::jsonb where key = 'market';
select cron.schedule('att-kalshi-2', '6 6 * * *',  $$select public.call_collector('att-market', '{"mode":"kalshi"}'::jsonb)$$);
select cron.schedule('att-kalshi-3', '8 6 * * *',  $$select public.call_collector('att-market', '{"mode":"kalshi"}'::jsonb)$$);
select cron.schedule('att-kalshi-4', '10 6 * * *', $$select public.call_collector('att-market', '{"mode":"kalshi"}'::jsonb)$$);

-- ---- temporary first-day FINRA backfill driver (2026-09-25 16:10 UTC; unscheduled again once >= 60 trading days were
-- mirrored). Fires only when no att-market run holds the api.finra.org lease, the job is not running and < 470 of
-- today's 500 finra.api units are used; the queued job's not_before was pushed 4 h meanwhile.
--   select cron.schedule('att-finra-bf-temp', '* * * * *', $$select public.call_collector('att-market',
--     '{"mode":"backfill","params":{"source":"finra.api","files":true}}'::jsonb)
--     where not exists (select 1 from ripples.att_host_lease where host = 'api.finra.org' and until > now())
--       and not exists (select 1 from ripples.att_jobs where dedupe_key = 'finra:files' and status = 'running')
--       and coalesce((select used from ripples.att_budget where bucket = 'finra.api' and day = current_date), 0) < 470$$);
--   select cron.unschedule('att-finra-bf-temp');
--   update ripples.att_jobs set priority = 6, not_before = now() where dedupe_key = 'finra:files' and status = 'queued';
--   (done 2026-09-25 ~16:52 UTC: 64 trading days mirrored (2026-06-25..09-24), ring 22,258 tickers, finra.api 388/500
--    used; job finra:files (id 2086) queued again at priority 6 and continues via att_tick('backfill').)
