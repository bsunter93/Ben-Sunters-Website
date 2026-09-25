-- Knock-On v5 W4: pg_cron schedule (migration ripples_v5_w4_cron). UTC. OWNER-APPLIED (see ../README.md).
--
-- LAUNCH-BLOCKING: ripples_publish_bundle (called by ripples-publish) is the ONLY code that marks a live puzzle
-- 'published' and writes its ledger row. ripples_latest / _visible / _latest_live_n only show live puzzles with
-- status 'published', so without these jobs (or a manual publish every day) puzzle #1 (2026-09-26 07:30 UTC) stays
-- invisible and the page shows 'delayed', through Storage AND the RPCs.
--
-- 07:25  pre-stages today's puzzle (publish_bundle(null) picks today's puzzle from 07:20, the veto deadline),
--        marks it published, writes the ledger row, puzzle/reveal/callit/board files and the OG PNGs that are
--        already visible. latest.json still shows yesterday's puzzle at this point (_current_date() rolls at 07:30).
-- 07:31  first run after the 07:30 rollover: rewrites latest.json (and board/latest.json) to today's puzzle and
--        stores today's OG PNGs. Without it latest.json would show yesterday's puzzle as current until 07:45.
-- 07:45  picks up late captions / social copy.
-- 08:30  catch-up run (late build, Call It resolutions from the tick).
--
-- There is deliberately NO bot job: automated Bluesky posting is deferred to v5.1 (OWNER_DECISIONS D-3), and the
-- ripples-bot function refuses to post (POSTING_ENABLED = false). The unschedule below removes a bot job if an
-- older copy of this file was ever applied.
-- cron.schedule(name, ...) upserts by job name, so re-running this file is idempotent.
select cron.schedule('ripples-publish-0725', '25 7 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.schedule('ripples-publish-0731', '31 7 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.schedule('ripples-publish-0745', '45 7 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.schedule('ripples-publish-0830', '30 8 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.unschedule(jobid) from cron.job where jobname = 'ripples-bot-daily';

-- check: select jobname, schedule, active from cron.job where jobname like 'ripples-publish-%' or jobname = 'ripples-bot-daily';
-- expect 4 rows ripples-publish-0725/0731/0745/0830, active = true, and no ripples-bot-daily.
