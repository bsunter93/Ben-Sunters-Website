-- 14_att_news_candidate_stoplist.sql (migration att_news_candidate_stoplist)
-- GKG AllNames includes wire credits, copyright lines and share-button names ("All Rights", "news service",
-- "Associated Press", "Facebook"). They surge with file composition, not attention, so they are never discovery
-- candidates. The list is in att_config('news_candidate_stoplist') so it can be extended without a deploy.
insert into ripples.att_config(key, value) values ('news_candidate_stoplist', '[
  "all rights", "all rights reserved", "rights reserved", "copyright", "news service", "news agency", "wire service",
  "associated press", "the associated press", "ap photo", "reuters", "thomson reuters", "agence france presse",
  "agence france-presse", "afp", "getty images", "press association", "pa media", "press trust of india", "pti",
  "ians", "asian news international", "xinhua", "tass", "anadolu agency", "dpa", "efe", "ansa", "kyodo", "yonhap",
  "bernama", "newswire", "pr newswire", "business wire", "globe newswire", "accesswire", "staff writer",
  "facebook", "twitter", "instagram", "linkedin", "whatsapp", "telegram", "youtube", "google news", "apple news",
  "read more", "click here", "sign up", "privacy policy", "terms of use", "cookie policy"
]'::jsonb)
on conflict (key) do update set value = excluded.value;

create or replace function ripples.att_news_candidates_merge(p_rows jsonb)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v int; v_stop text[];
begin
  select coalesce(array_agg(lower(x)), '{}') into v_stop
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('news_candidate_stoplist'), '[]'::jsonb)) x;
  with c as (
    select distinct on (x.day, x.source, coalesce(x.geo, 'ALL'), x.label) x.*
    from jsonb_to_recordset(p_rows) as x(day date, source text, geo text, label text, rank int, value double precision,
                                          evidence real, qid text, topic_id bigint, meta jsonb)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.day is not null and x.label is not null and x.evidence between 0 and 1 and length(x.label) <= 200
      and not ripples._att_ident_like(x.label, x.source, true)
      and lower(btrim(x.label)) <> all (v_stop)
    order by x.day, x.source, coalesce(x.geo, 'ALL'), x.label, x.evidence desc),
  up as (
    insert into ripples.att_trend_candidates as t (day, source, geo, label, rank, value, evidence, qid, topic_id, meta)
    select day, source, coalesce(geo, 'ALL'), label, rank, value, evidence, qid, topic_id, ripples._att_clean_meta(meta) from c
    on conflict (day, source, geo, label) do update
      set evidence = greatest(t.evidence, excluded.evidence),
          value = greatest(t.value, excluded.value),
          rank = least(t.rank, excluded.rank),
          topic_id = coalesce(excluded.topic_id, t.topic_id),
          meta = case when excluded.evidence >= t.evidence then excluded.meta else t.meta end,
          observed_at = now()
    returning 1)
  select count(*) into v from up;
  return jsonb_build_object('rows', v, 'rejected', jsonb_array_length(p_rows) - v);
end $function$;
revoke all on function ripples.att_news_candidates_merge(jsonb) from public, anon, authenticated;
grant execute on function ripples.att_news_candidates_merge(jsonb) to service_role;

delete from ripples.att_trend_candidates t
 where t.source in ('gdelt.gkg', 'news.sitemap')
   and lower(btrim(t.label)) in (select lower(x) from jsonb_array_elements_text(ripples._att_cfg('news_candidate_stoplist')) x);
