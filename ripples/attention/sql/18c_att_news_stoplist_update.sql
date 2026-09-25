-- 18c_att_news_stoplist_update.sql (migration att_news_stoplist_update)
-- Site furniture seen in the first n7 files: the "Trinity Audio" text-to-speech widget name (15 documents, 4 outlets in
-- 20260925171500). Appended to att_config('news_candidate_stoplist') and removed from today's candidates and edges.
update ripples.att_config
   set value = (select jsonb_agg(distinct x) from jsonb_array_elements_text(value || '["trinity audio", "listen to this article", "audio player"]'::jsonb) x)
 where key = 'news_candidate_stoplist';
delete from ripples.att_trend_candidates where source in ('gdelt.gkg', 'news.sitemap') and lower(btrim(label)) in ('trinity audio');
delete from ripples.att_edges where source = 'gdelt.gkg' and to_key in ('trinity audio');

-- Section labels that sitemap runs before KW_SKIP covered them wrote as keyword candidates ("Culture", "Politics",
-- "Business"): on the stoplist too, so the SQL screen matches KW_SKIP, and removed from today's rows.
update ripples.att_config
   set value = (select jsonb_agg(distinct x) from jsonb_array_elements_text(value || '["news", "live", "video", "videos",
     "opinion", "analysis", "latest", "update", "updates", "world", "world news", "us news", "uk news", "politics",
     "business", "sport", "sports", "lifestyle", "entertainment", "culture", "technology", "science", "health",
     "travel"]'::jsonb) x)
 where key = 'news_candidate_stoplist';
delete from ripples.att_trend_candidates t
 where t.source = 'news.sitemap'
   and lower(btrim(t.label)) in (select x from jsonb_array_elements_text(ripples._att_cfg('news_candidate_stoplist')) x);
