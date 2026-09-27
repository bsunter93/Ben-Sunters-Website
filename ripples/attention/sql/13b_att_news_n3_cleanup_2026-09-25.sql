-- 13b_att_news_n3_cleanup_2026-09-25.sql: one-off data cleanup run with execute_sql (not a migration) when att-news
-- NEWS_VERSION 2026-09-25.n3 was deployed. Removed rows: 3 daily obs, 10 hourly obs, 3 acc, 18 edges, 2,276 candidates.
-- 1. Third Eye no longer counts network names (TV_BRANDS); drop the 'cnn' rows counted before n3 (on-screen branding).
-- 2. GKG discovery now uses a size-normalised baseline; drop 2026-09-25 gdelt.gkg candidates from the old baseline.
with s as (select series_id from ripples.att_series where source = 'ia.thirdeye' and key = 'cnn'),
d1 as (delete from ripples.attention_obs o using s where o.series_id = s.series_id returning 1),
d2 as (delete from ripples.attention_obs_hourly o using s where o.series_id = s.series_id returning 1),
d3 as (delete from ripples.att_news_acc where source = 'ia.thirdeye' and key = 'cnn' returning 1),
d4 as (delete from ripples.att_trend_candidates where source = 'gdelt.gkg' and day = '2026-09-25' returning 1)
select (select count(*) from d1), (select count(*) from d2), (select count(*) from d3), (select count(*) from d4);
delete from ripples.att_edges where source = 'ia.thirdeye' and 'cnn' in (from_key, to_key);
