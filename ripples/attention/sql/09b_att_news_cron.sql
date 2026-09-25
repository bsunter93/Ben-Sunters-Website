-- 09b_att_news_cron.sql — ATTENTION_STACK §3.4 cron rows for att-news (migration att_news_cron).
-- GKG publishes at :00/:15/:30/:45 -> collect at :04/:19/:34/:49 (one file per run; the collector walks forward from
-- att_state 'gkg.state' and falls back to lastupdate.txt). Third Eye hourly at :12 (last=2, complete hours only).
-- Sitemaps four times a day. No Wikimedia calls are made by att-news, so the 06:30-07:20 quiet window is unaffected.
select cron.unschedule(jobname) from cron.job where jobname in ('att-gkg', 'att-thirdeye', 'att-sitemaps');
select cron.schedule('att-gkg', '4,19,34,49 * * * *',
  $$select public.call_collector('att-news', '{"mode":"gkg"}'::jsonb)$$);
select cron.schedule('att-thirdeye', '12 * * * *',
  $$select public.call_collector('att-news', '{"mode":"thirdeye","params":{"last":2}}'::jsonb)$$);
select cron.schedule('att-sitemaps', '22 0,6,12,18 * * *',
  $$select public.call_collector('att-news', '{"mode":"sitemaps"}'::jsonb)$$);
