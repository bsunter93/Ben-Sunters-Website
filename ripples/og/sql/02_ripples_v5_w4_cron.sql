-- Knock-On v5 W4: pg_cron schedule (migration ripples_v5_w4_cron). UTC.
-- 07:25 pre-stages today's files (publish_bundle(null) picks today's puzzle from 07:20), 07:45 rewrites latest.json
-- after the 07:30 rollover and picks up late captions, 08:30 is a catch-up run. 07:35 posts yesterday's reveal.
-- cron.schedule(name, ...) upserts by job name, so re-running this file is idempotent.
select cron.schedule('ripples-publish-0725', '25 7 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.schedule('ripples-publish-0745', '45 7 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.schedule('ripples-publish-0830', '30 8 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.schedule('ripples-bot-daily',    '35 7 * * *', $$select public.call_collector('ripples-bot', '{}'::jsonb)$$);
