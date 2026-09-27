-- Knock-On v5 W4: pg_cron schedule (migration ripples_v5_w4_cron). UTC.
--
-- LAUNCH-BLOCKING: ripples_publish_bundle (called by ripples-publish) is the ONLY code that marks a live puzzle
-- 'published' and writes its ledger row. ripples_latest / _visible / _latest_live_n only show live puzzles with
-- status 'published', so without these jobs (or a manual publish every day) puzzle #1 (2026-09-26 07:30 UTC) stays
-- invisible and the page shows 'delayed', through Storage AND the RPCs.
--
-- 07:25  publishes today's puzzle (publish_bundle(null) picks today's puzzle from 07:20, the veto deadline): marks it
--        published and writes the ledger row. The puzzle is not visible until the 07:30 rollover (_current_date()), so
--        ripples-publish runs in "staged" mode: it writes NO per-puzzle file for it (no puzzle/reveal/callit/board/{n},
--        no data/{date}.csv|json with the answer column, no OG PNGs; SPEC §12, no early spoilers). latest.json stays
--        yesterday's with next_at = today 07:30; from 07:30 the client (app.js getLatest) sees next_at has passed and
--        reads ripples_latest() directly, and load() falls back to the RPC for any missing Storage file.
-- 07:45  first run after the rollover: mirrors everything (latest, puzzle, reveal, callit, board, open data, OG PNGs)
--        and picks up late captions / social copy.
-- 08:30  catch-up run (late build, Call It resolutions from the tick).
-- 07:35  ripples-bot (SPEC §5.5). OWNER_DECISIONS D-3 defers automated Bluesky posting to v5.1: the function has
--        POSTING_ENABLED = false and returns {"skipped":true,"reason":"deferred_v5_1"} on every scheduled call, so this
--        job posts nothing. It exists so v5.1 only has to flip the flag and add the vault secrets.
-- cron.schedule(name, ...) upserts by job name, so re-running this file is idempotent.
select cron.schedule('ripples-publish-0725', '25 7 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.schedule('ripples-publish-0745', '45 7 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.schedule('ripples-publish-0830', '30 8 * * *', $$select public.call_collector('ripples-publish', '{}'::jsonb)$$);
select cron.schedule('ripples-bot-daily',    '35 7 * * *', $$select public.call_collector('ripples-bot', '{}'::jsonb)$$);

-- check: select jobname, schedule, active from cron.job where jobname like 'ripples-publish-%' or jobname = 'ripples-bot-daily';
-- expect 4 rows (ripples-publish-0725/0745/0830, ripples-bot-daily), active = true.
-- migration ripples_v5_w4_cron_spec4 removed the earlier extra job ripples-publish-0731 (not in SPEC §5.5):
--   select cron.unschedule(jobid) from cron.job where jobname = 'ripples-publish-0731';
-- remove: select cron.unschedule(jobname) from cron.job where jobname like 'ripples-publish-%' or jobname = 'ripples-bot-daily';
