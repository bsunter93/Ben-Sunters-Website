-- Compliance audit fix (2026-09-25): att-wikidata ran hourly at :17, including 07:17, which is inside the
-- 06:30-07:20 UTC "no attention Wikimedia calls" window (ATTENTION_STACK §3.4). att.ts already refused the calls
-- (wm_quiet_utc), but the schedule itself now skips hour 7.
select cron.alter_job((select jobid from cron.job where jobname = 'att-wikidata'), schedule := '17 0-6,8-23 * * *');
