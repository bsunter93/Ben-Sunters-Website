# Switch-off, Oct 9, 2026 (owner approved)

The read-only engine audit of Oct 8 found the parked September engine still running: 134 of 135 cron jobs active,
196,221 runs and 76.4 database hours in 14 days, 78% of edge runs since Oct 1 writing zero rows, and nothing reaching the
live page. The owner approved switching it off. Nothing was deleted. Every step below can be undone.

## 1. Supabase cron (project kffkasnzqcddpystszch)
- **Paused (active = false): 129 jobs**, including the armed Bluesky poster `ripples-bot-daily` (jobid 31), every
  every-minute engine job, Jetstream, the Wikipedia lane, Wikidata, the finished backfill drains, the four failing SQL jobs,
  the Knock-On / v6 builders and every collector with no consumer. `att-edgar` (jobid 40) was already off.
- **Still active: 5**, all cleanup or guards: `ripples-retention` (15), `att-engine-retention` (135),
  `att-youtube-raw-cleanup` (184, the YouTube 28-day rule), `att-fx63-space-guard` (238), `att-net-watchdog` (272).
- Paused job ids: 1,2,3,4,5,6,7,8,9,11,13,14,16,17,18,20,21,22,23,24,25,27,29,30,31,36,37,38,39,52,53,54,55,56,57,58,59,60,61,62,63,64,65,67,68,69,72,73,74,75,76,77,78,79,80,81,82,83,84,89,90,91,92,93,94,95,96,97,100,101,102,103,104,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,131,132,133,134,138,140,149,150,151,152,157,158,159,160,167,172,178,179,181,182,183,188,191,192,193,195,196,197,211,212,217,218,219,225,242,243,244,245,274
- **Undo** (all, or pick ids):
  `do $$ declare r int; begin foreach r in array array[<ids>] loop perform cron.alter_job(job_id := r, active := true); end loop; end $$;`

## 2. Public database functions
- 27 legacy SECURITY DEFINER functions in `public` (`ripples_*`, `rm_*`, among them `ripples_join`, which takes an email,
  and `rm_event`) could be executed by `anon`. Their pages are orphaned. EXECUTE was revoked from `public`, `anon` and
  `authenticated`, and granted to `service_role` explicitly. After: anon can execute 0; service_role all 50.
- Left as is: `ripples.att_plain_place(text)` (read-only helper, also anon-executable; review later).
- **Undo:** `grant execute on function public.<name>(<args>) to anon, authenticated;`

## 3. GitHub workflows (disabled; each can still be enabled with `gh workflow enable <file>`)
ripples-q3-wide (12 of 16 runs failed), ripples-storm-events (2 of 2 failed), ripples-gdelt (0 rows), ripples-causal-effect
(daily BigQuery, output unused), ripples-hud-epa, ripples-nyt-archive, ripples-wiki-bq-backfill.

## Kept running
The page's producers (chain check, bill-act, maps), the Trends archive (`ripples-gt-archive`), data day, assets, predict.

## Not done (needs a separate yes)
Deleting the 14 retired `probe-*` functions. Purging `att_social_tags` past its 8-day rule (it held rows from Sep 23 to
Sep 30; its pruning ran inside Jetstream). The YouTube 30-day reading for `att_yt_videos` and `att_yt_breadth` (due about
Oct 27 to 30). Purging `cron.job_run_details`.
