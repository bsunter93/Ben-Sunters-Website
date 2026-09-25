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
