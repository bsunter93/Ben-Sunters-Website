-- 09c_att_news_gkg_catchup.sql (migration att_news_gkg_catchup)
-- lastupdate.txt can list a GKG file before the CDN serves it (observed 2026-09-25 05:49: listed 060000, zip 404).
-- att-news now always reads lastupdate.txt, walks forward from att_state 'gkg.state' one file at a time, and processes
-- up to 2 files per run while behind: 1 lastupdate.txt + 2 zips = 3 requests per run; ~96 + 96 (+ catch-up) per day.
update ripples.att_sources set per_run_cap = 3, per_day_cap = 300,
  reason = 'Q6: GDELT raw files (operator publishes every 15 min for download), no published limit; per run 1 lastupdate.txt + <= 2 GKG zips (catch-up), 96 runs/day, 5 s spacing'
 where source = 'gdelt.gkg';
