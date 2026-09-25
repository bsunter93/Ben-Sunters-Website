-- 18b_att_news_n4_cleanup_2026-09-25.sql (one-off, run with execute_sql at 17:50 UTC on 2026-09-25; NOT a migration)
-- Before att-news n4 (deployed 17:40 UTC), GKG discovery candidates and co-mention edge endpoints were not screened for
-- photo/syndication credits, bylines, V1-only ("ghost") names or outlet breadth, and they included journalists' and
-- photographers' names. They cannot be re-screened after the fact (the per-file outlet and credit context is gone), so
-- every pre-n4 GKG candidate and edge is deleted. No n4 production run had written GKG edges or candidates yet (the
-- last GKG run, 17:40:00, ran the n3 code; the n4/n5 runs before this cleanup were dry runs, which write nothing).
-- GKG edges for 2026-09-25 therefore cover files from 17:45 UTC on; later days are complete.
begin;
delete from ripples.att_edges where source = 'gdelt.gkg' and period <= date '2026-09-25';
delete from ripples.att_trend_candidates
 where source = 'gdelt.gkg' and coalesce(meta->>'method', '') <> 'gkg_burst_ewma_v2';
-- sitemap keyword candidates written before the KW_SKIP / brand fixes ('The', 'Media', 'CNN', 'MS NOW', ...)
delete from ripples.att_trend_candidates
 where source = 'news.sitemap'
   and lower(btrim(label)) in ('the', 'media', 'cnn', 'ms now', 'msnow', 'msnbc', 'fox', 'fox news', 'bbc', 'bbc news',
     'new york times', 'the new york times', 'nyt', 'guardian', 'the guardian', 'her', 'his', 'age', 'people', 'women',
     'men', 'children', 'youth', 'students', 'schools', 'abc news', 'cbs news', 'nbc news', 'sky news');
commit;

-- Second pass, 18:05 UTC (run with execute_sql). The 17:55 production run used n5, which still let AP contributor
-- lines ("Associated Press writers ... contributed") and a photo credit whose V1Persons ghost share was 41% through
-- (292 edges, 169 candidates from file 20260925164500). n7 (deployed 18:04, version 9) screens article-tail names and
-- uses a ghost share of 0.3; its dry run on the same file rejects all of them. The pre-n7 rows are deleted so every
-- stored GKG candidate and edge has passed the n7 screen. GKG edges for 2026-09-25 cover files from 18:00 UTC on.
begin;
delete from ripples.att_edges where source = 'gdelt.gkg' and period <= date '2026-09-25';
delete from ripples.att_trend_candidates where source = 'gdelt.gkg' and day <= date '2026-09-25';
commit;
