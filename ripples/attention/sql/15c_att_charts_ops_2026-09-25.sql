-- 15c_att_charts_ops_2026-09-25 (W7 att-charts): operational statements run with execute_sql during the first runs.
-- Recorded here so the state can be reproduced; not a migration.

-- 1) Tranco: one list download per day; a same-host redirect hop to the dated list would count as a second request.
update ripples.att_sources
   set per_run_cap = 2, per_day_cap = 2,
       reason = 'Q6: one list download per day (a same-host redirect hop to the dated list counts as a request, so cap 2)'
 where source = 'tranco.rank';

-- 2) ChatGPT (Q115564437, active + panel) gets its official SDK packages / repo as keys (the registry's Wikidata facts
--    were not available because the UA contact gate blocks Wikidata until the methods page is published). The att_keys
--    trigger queued the matching backfill jobs (npm.dl, pypi.dl, gh.stars).
insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match, weight, created_by)
select t.topic_id, x.source, 'n', 'ALL', x.key, x.kt, '{"via":"att-charts: official OpenAI SDK packages/repo"}'::jsonb, 1, 'manual'
from ripples.att_topics t,
     (values ('npm.dl','openai','package'), ('pypi.dl','openai','package'), ('gh.stars','openai/openai-python','repo')) x(source, key, kt)
where t.qid = 'Q115564437'
on conflict do nothing;

-- 3) Apple: the first attempt used rss.marketingtools.apple.com and its robots.txt fetch timed out (cached as deny for
--    24 h, rule "unreachable = deny"); c3 tried the legacy rss.applemarketingtools.com, whose robots.txt 301-redirects
--    cross-host (deny). A later robots.txt fetch of rss.marketingtools.apple.com answered 200 with no rules, so c4 uses
--    that host and the stale deny entry was removed once:
delete from ripples.att_state where k = 'robots:https://rss.marketingtools.apple.com';

-- 4) Allow att_tick to dispatch att-charts backfill jobs.
select ripples.att_fn_live('att-charts');

-- 5) Apple: the feed host answered 504 / timed out on some feeds, so failed feeds are retried by later runs (c5/c6).
--    Daily cap raised from 25 to 35 (25 feeds + retries; still 1 request / 5 s end-to-start) and 3 tries per feed.
update ripples.att_sources
   set per_day_cap = 35,
       reason = 'Q6: no published limit -> 1 req/5 s (end-to-start); 25 feeds/day + up to 10 later-run retries (Apple answers 504/timeouts at times); a run backs off after 2 failures in a row'
 where source = 'apple.rss';
update ripples.att_config set value = jsonb_set(value, '{apple,max_tries}', '3'::jsonb), updated_at = now() where key = 'charts';

-- 6) Budget rows over-charged by the refund bug fixed in 15d (a chunk that reached the cap could not be refunded):
--    set to the requests actually made (att_runs.http; robots.txt fetches are not charged).
update ripples.att_budget set used = 22, cap = 35 where bucket = 'apple.rss' and day = date '2026-09-25' and not killed;
update ripples.att_budget set used = 1 where bucket = 'gh.stars' and day = date '2026-09-25' and not killed;

-- 7) npm reports days it has not computed (the last 1-3 days and outage days) as 0 for every package. c7 no longer
--    stores such zeros; the zeros already stored by the first 400-day backfills were removed once:
with gap as (
  select o.day from ripples.att_series s join ripples.attention_obs o using(series_id)
  where s.source = 'npm.dl' and s.key = '__total__' and o.value = 0)
delete from ripples.attention_obs o using ripples.att_series s
 where o.series_id = s.series_id and s.source = 'npm.dl' and o.value = 0 and o.day in (select day from gap);
with p as (
  select s.series_id, percentile_disc(0.75) within group (order by o.value) p75
  from ripples.att_series s join ripples.attention_obs o using(series_id) where s.source = 'npm.dl' group by 1)
delete from ripples.attention_obs o using p where o.series_id = p.series_id and p.p75 > 100 and o.value = 0;
