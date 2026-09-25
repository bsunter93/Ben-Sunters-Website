-- 18_att_news_entity_screen.sql (migration att_news_entity_screen)
-- Second line of defence behind att-news n4/n5 (which screens GKG names for photo/syndication credits, bylines,
-- V1-only "ghost" names and outlet breadth before anything leaves the function): discovery candidates AND co-mention
-- edge endpoints from att-news are dropped when their label is on att_config('news_candidate_stoplist') or matches a
-- pattern in att_config('news_entity_stop_regex') (lower-cased label, Postgres ARE). Both lists can be extended without
-- a deploy.
insert into ripples.att_config(key, value) values ('news_candidate_stoplist', '[
  "all rights", "all rights reserved", "rights reserved", "copyright", "news service", "news agency", "wire service",
  "associated press", "the associated press", "the associated", "ap photo", "reuters", "reuters connect",
  "thomson reuters", "agence france presse", "agence france-presse", "afp", "getty images", "press association",
  "pa media", "pa wire", "press trust of india", "pti", "ians", "asian news international", "xinhua", "tass",
  "anadolu agency", "dpa", "efe", "ansa", "kyodo", "yonhap", "bernama", "newswire", "pr newswire", "business wire",
  "globe newswire", "accesswire", "staff writer", "tribune content agency", "tribune news service", "canadian press",
  "the canadian press", "australian associated", "mandatory credit", "pool photo", "trusted news", "subscribe now",
  "get free report", "view full", "wikimedia commons", "updated september",
  "facebook", "twitter", "instagram", "linkedin", "whatsapp", "telegram", "youtube", "google news", "apple news",
  "read more", "click here", "sign up", "privacy policy", "terms of use", "terms of service", "cookie policy",
  "the", "media", "cnn", "cnn international", "ms now", "msnow", "msnbc", "fox", "fox news", "fox news channel",
  "fox business", "bbc", "bbc news", "new york times", "the new york times", "nyt", "guardian", "the guardian",
  "abc news", "cbs news", "nbc news", "sky news"
]'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into ripples.att_config(key, value) values ('news_entity_stop_regex', '[
  "(^| )(photo|photos|getty|image|images|shutterstock|alamy|imagn|handout)( |$)",
  "(^| )(content agency|news service|news agency|newswire|wire service|press release|image credit|photo credit|mandatory credit)( |$)",
  "(^| )(staff )?(writer|reporter|correspondent|photographer|contributor|columnist|editor)$",
  "^(senior |staff |contributing )?(writer|reporter|correspondent|photographer|contributor|columnist|content writer|research analyst) ",
  "[a-z](writer|reporter|photographer)$",
  "(^| )(whatsapp|facebook|instagram|youtube|linkedin|twitter|tiktok|telegram|podcast network)( |$)",
  "(^| )(website access|online edition|print edition|latest edition|headline news|daily headlines|newsletter)( |$)",
  "(^| )(contact email|more information|privacy (notice|policy)|terms of (service|use)|cookie|subscribe|sign up)( |$)",
  "(^| )(read more|click here|share this|help someone|donating proceeds|sale notice|plaintiff deadline)( |$)"
]'::jsonb)
on conflict (key) do update set value = excluded.value;

-- true = the label must not be stored as an att-news candidate or edge endpoint
create or replace function ripples._att_news_stop(p text, p_stop text[], p_re text[])
 returns boolean language sql immutable security definer set search_path to ''
as $function$
  select p is not null and (lower(btrim(p)) = any (p_stop)
    or exists (select 1 from unnest(p_re) r where lower(btrim(p)) ~ r))
$function$;
revoke all on function ripples._att_news_stop(text, text[], text[]) from public, anon, authenticated;
grant execute on function ripples._att_news_stop(text, text[], text[]) to service_role;

create or replace function ripples.att_news_candidates_merge(p_rows jsonb)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v int; v_stop text[]; v_re text[];
begin
  select coalesce(array_agg(lower(x)), '{}') into v_stop
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('news_candidate_stoplist'), '[]'::jsonb)) x;
  select coalesce(array_agg(x), '{}') into v_re
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('news_entity_stop_regex'), '[]'::jsonb)) x;
  with c as (
    select distinct on (x.day, x.source, coalesce(x.geo, 'ALL'), x.label) x.*
    from jsonb_to_recordset(p_rows) as x(day date, source text, geo text, label text, rank int, value double precision,
                                          evidence real, qid text, topic_id bigint, meta jsonb)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.day is not null and x.label is not null and x.evidence between 0 and 1 and length(x.label) <= 200
      and not ripples._att_ident_like(x.label, x.source, true)
      and not ripples._att_news_stop(x.label, v_stop, v_re)
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

create or replace function ripples.att_news_edges_accum(p_batch text, p_rows jsonb)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_n int; v int; v_stop text[]; v_re text[];
begin
  if p_batch is not null then
    insert into ripples.att_news_batches(batch) values (p_batch) on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n = 0 then return jsonb_build_object('dup', true, 'rows', 0); end if;
  end if;
  select coalesce(array_agg(lower(x)), '{}') into v_stop
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('news_candidate_stoplist'), '[]'::jsonb)) x;
  select coalesce(array_agg(x), '{}') into v_re
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('news_entity_stop_regex'), '[]'::jsonb)) x;
  with e as (
    select distinct on (x.source, coalesce(x.geo, 'ALL'), x.from_key, x.to_key, x.day) x.*
    from jsonb_to_recordset(p_rows) as x(source text, geo text, from_key text, to_key text, day date, n double precision,
                                         from_topic bigint, to_topic bigint, to_total double precision)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.from_key is not null and x.to_key is not null and x.day is not null and x.n > 0
      and length(x.to_key) <= 120
      and not ripples._att_ident_like(x.from_key, x.source, true) and not ripples._att_ident_like(x.to_key, x.source, true)
      and not ripples._att_news_stop(x.to_key, v_stop, v_re)),
  up as (
    insert into ripples.att_edges as t (source, geo, from_key, to_key, period, grain, n, from_topic, to_topic, meta)
    select source, coalesce(geo, 'ALL'), from_key, to_key, day, 'day', n, from_topic, to_topic,
           case when to_total is not null then jsonb_build_object('total', to_total) end
    from e
    on conflict (source, geo, from_key, to_key, period, grain) do update
      set n = t.n + excluded.n,
          meta = case when excluded.meta is null then t.meta
                      else jsonb_build_object('total', coalesce((t.meta->>'total')::double precision, 0)
                                                        + (excluded.meta->>'total')::double precision) end,
          from_topic = coalesce(excluded.from_topic, t.from_topic),
          to_topic = coalesce(excluded.to_topic, t.to_topic)
    returning t.source, t.geo, t.from_key, t.to_key, t.period)
  select count(*) into v from up;

  -- PMI from the running daily totals (only where all counts exist)
  update ripples.att_edges g set pmi = ln(g.n * tot.value / (fa.value * (g.meta->>'total')::double precision))
    from jsonb_to_recordset(p_rows) as x(source text, geo text, from_key text, to_key text, day date),
         ripples.att_news_acc fa, ripples.att_news_acc tot
   where g.source = x.source and g.geo = coalesce(x.geo, 'ALL') and g.from_key = x.from_key and g.to_key = x.to_key
     and g.period = x.day and g.grain = 'day'
     and fa.source = g.source and fa.metric = 'n' and fa.geo = 'ALL' and fa.key = g.from_key and fa.grain = 'day'
     and fa.period = (g.period::timestamp at time zone 'UTC')
     and tot.source = g.source and tot.metric = 'n' and tot.geo = 'ALL' and tot.key = '__total__' and tot.grain = 'day'
     and tot.period = fa.period
     and fa.value > 0 and tot.value > 0 and coalesce((g.meta->>'total')::double precision, 0) > 0;
  return jsonb_build_object('rows', v, 'rejected', jsonb_array_length(p_rows) - v);
end $function$;
revoke all on function ripples.att_news_edges_accum(text, jsonb) from public, anon, authenticated;
grant execute on function ripples.att_news_edges_accum(text, jsonb) to service_role;
