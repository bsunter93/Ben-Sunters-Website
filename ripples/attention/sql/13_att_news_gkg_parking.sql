-- 13_att_news_gkg_parking.sql (migration att_news_gkg_parking), att-news NEWS_VERSION 2026-09-25.n2
-- 1. GKG cron moves from :04/:19/:34/:49 to :10/:25/:40/:55. On 2026-09-25, 7 of ~40 files requested 4 min after their
--    timestamp answered 404 and the CDN kept answering 404 for that URL for 45-60 min, so the walk stalled for 3-4 runs
--    each time. att-news now never requests a file younger than 8 min, parks a 404 file in att_state 'gkg.state'.pending
--    (retried 50 min after its last 404, counted as a gap after 4 h) and moves on to the next file.
-- 2. news.sitemap: the four sitemap requests are now made one after another. In parallel, each drew a budget chunk
--    of 8 before any was spent, which took the day's 32 units at once; att_budget_refund keeps a bucket at its cap
--    spent, so the unused units were never returned. Today's row is reset to the requests actually made (16).
select cron.alter_job(jobid, schedule := '10,25,40,55 * * * *') from cron.job where jobname = 'att-gkg';
update ripples.att_budget b
   set used = least(b.cap, coalesce((
         select sum((h.value)::int)
           from ripples.att_runs r, jsonb_each(r.http) hh, jsonb_each_text(hh.value) h
          where r.fn = 'att-news' and r.mode = 'sitemaps' and hh.key in ('www.bbc.com','www.nytimes.com','www.theguardian.com','www.foxnews.com')
            and (r.started_at at time zone 'utc')::date = b.day), 0))
 where b.bucket = 'news.sitemap' and b.day = (now() at time zone 'utc')::date;
