-- Knock-On v5 / W2: migration ripples_v5_pipeline_ingest
-- Helpers (category, safety), edge-function write paths, the job queue (payloads, dispatch, completion).
alter table ripples.jobs add column if not exists not_before timestamptz;

-- ------------------------------------------------------------------ categories
create or replace function ripples._emoji(p_cat text) returns text
language sql immutable set search_path = '' as $$
  select case p_cat
    when 'person' then '👤' when 'place' then '📍' when 'film_tv' then '🎬' when 'music' then '🎵'
    when 'sport' then '🏅' when 'science_health' then '🧬' when 'tech' then '💻' when 'business' then '🏢'
    when 'politics_law' then '⚖️' when 'food_drink' then '🍎' when 'nature_weather' then '🌦'
    when 'history_culture' then '🏛' else '🔹' end
$$;

-- Keyword fallback on a Wikipedia short description or a Wikidata class label.
create or replace function ripples._text_category(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p is null or btrim(p) = '' then null
    when p ~* '(^|[^a-z])(film|movie|television|tv series|tv program|sitcom|miniseries|soap opera|anime|animated series|web series|documentary|reality (show|series|competition)|talk show|game show|video game|actor|actress|filmmaker|film director|screenwriter|comedian|youtuber|streamer|media franchise|episode)' then 'film_tv'
    when p ~* '(^|[^a-z])(song|single|album|band|singer|rapper|musician|composer|record label|music|disc jockey|dj|boy band|girl group|guitarist|drummer|pianist|opera|concert tour|mixtape|ep by)' then 'music'
    when p ~* '(^|[^a-z])(football|soccer|basketball|baseball|cricket|rugby|tennis|golf|boxer|boxing|wrestl|athlete|olympic|racing|formula one|nascar|hockey|cyclist|swimmer|sprinter|sportsperson|sports|league|club season|championship|tournament|world cup|grand prix|mixed martial|ufc|chess player|esports|jockey|skater|gymnast|coach|quarterback|pitcher|striker|midfielder|goalkeeper|defender)' then 'sport'
    when p ~* '(^|[^a-z])(disease|disorder|syndrome|infection|virus|bacteri|medication|drug|vaccine|protein|gene|enzyme|chemical|compound|element|mineral|physic|chemist|biolog|medical|medicine|species|genus|anatomy|symptom|therapy|psychology|mathemat|astronom|planet|star|galaxy|comet|asteroid|spacecraft|space probe|telescope|scientist|nutrient|vitamin)' then 'science_health'
    when p ~* '(^|[^a-z])(software|app|website|web browser|operating system|programming|computer|smartphone|internet|artificial intelligence|chatbot|social (media|network)|search engine|cryptocurrency|blockchain|semiconductor|processor|video game console|technology|file format|protocol|domain)' then 'tech'
    when p ~* '(^|[^a-z])(company|corporation|conglomerate|business|brand|retailer|manufacturer|airline|bank|startup|chain|store|businessperson|entrepreneur|executive|ceo|investor|stock|economy|currency|product)' then 'business'
    when p ~* '(^|[^a-z])(politician|election|political party|president|prime minister|minister|senator|governor|mayor|legislat|parliament|congress|court|judge|lawyer|law|act of|treaty|constitution|referendum|government|diplomat|monarch|king|queen|prince|princess|activist|civil servant)' then 'politics_law'
    when p ~* '(^|[^a-z])(food|dish|cuisine|beverage|drink|cocktail|beer|wine|coffee|tea|dessert|snack|restaurant|chef|fruit|vegetable|cheese|bread|sauce|candy|spice)' then 'food_drink'
    when p ~* '(^|[^a-z])(hurricane|typhoon|cyclone|storm|weather|climate|earthquake|volcano|river|mountain|lake|forest|animal|plant|bird|fish|mammal|insect|tree|flower|dog breed|cat breed|national park|natural)' then 'nature_weather'
    when p ~* '(^|[^a-z])(city|town|village|country|capital|state of|province|county|region|district|municipality|island|neighbourhood|neighborhood|borough|street|airport|stadium|arena|building|bridge|tower|university|school|hotel|park|sovereign state|census-designated)' then 'place'
    when p ~* '(^|[^a-z])(history|historical|empire|dynasty|ancient|medieval|century|religio|mytholog|deity|god|goddess|saint|church|temple|novel|book|poem|author|writer|poet|novelist|painter|painting|sculpt|artist|museum|philosoph|language|festival|holiday|tradition|culture|comic|manga|character|fictional)' then 'history_culture'
    when p ~* '(^|[^a-z])(born [0-9]{4}|\([0-9]{4}[–-][0-9]{4}\)|person|people|family)' then 'person'
    else null end
$$;

-- Keyword safety flag on a class label (used only for auto-mapped classes).
create or replace function ripples._text_flag(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p is null then null
    when p ~* '(^|[^a-z])(war|wars|battle|military (operation|campaign|conflict|offensive)|armed conflict|terror|attack|bombing|shooting|massacre|murder|homicide|killing|assassination|genocide|war crime|suicide|mass murder|violence|riot|insurgency|crime|criminal|sexual|pornograph|erotic|hate group|hate crime|lynching|abuse|execution|kidnapping)' then 'block'
    when p ~* '(^|[^a-z])(aviation accident|air crash|shipwreck|disaster|explosion|stampede|accident|collapse|derailment|epidemic|pandemic|famine)' then 'block'
    when p ~* '(^|[^a-z])(earthquake|tropical cyclone|hurricane|typhoon|tornado|flood|wildfire|bushfire|tsunami|volcanic eruption|landslide|heat wave|storm|blizzard|drought|natural disaster|weather event)' then 'sensitive'
    else null end
$$;

-- Category + flag for a set of P31 classes (direct class first, then P279 parents, then the description keywords).
create or replace function ripples._classify(p_p31 text[], p_desc text)
returns table (category text, flag text, flag_reason text)
language sql stable security definer set search_path = '' as $$
  with direct as (
    select c.*, u.o from unnest(coalesce(p_p31, '{}')) with ordinality u(q, o) join ripples.category_map c on c.class_qid = u.q
  ), par as (
    select c.*, d.o from direct d cross join unnest(d.parents) pq(q) join ripples.category_map c on c.class_qid = pq.q
  ), par2 as (
    select c.*, p.o from par p cross join unnest(p.parents) pq(q) join ripples.category_map c on c.class_qid = pq.q
  ), allc as (
    select category, flag, label, 1 lvl, o from direct union all
    select category, flag, label, 2, o from par union all
    select category, flag, label, 3, o from par2
  ), bl as (
    select b.action, b.reason from ripples.blocklist b
     where b.qid is not null and (b.qid = any(coalesce(p_p31, '{}'))
        or b.qid in (select unnest(d.parents) from direct d)
        or b.qid in (select unnest(p.parents) from par p))
  )
  select
    case when 'Q5' = any(coalesce(p_p31, '{}')) then 'person' else coalesce(
      (select a.category from allc a where a.category <> 'other' order by a.lvl, a.o limit 1),
      ripples._text_category(p_desc), 'other') end,
    coalesce((select 'block' from bl where action = 'block' limit 1),
             (select 'block' from allc a where a.flag = 'block' and a.lvl <= 2 limit 1),
             (select 'sensitive' from bl where action = 'sensitive' limit 1),
             (select 'sensitive' from allc a where a.flag = 'sensitive' and a.lvl <= 2 limit 1)),
    coalesce((select 'blocklist class: ' || reason from bl limit 1),
             (select 'class: ' || coalesce(a.label, '?') from allc a where a.flag is not null and a.lvl <= 2 order by (a.flag = 'block') desc, a.lvl limit 1))
$$;

-- Recompute derived fields (category, emoji, is_list, sensitive, blocked) of articles.
create or replace function ripples._refresh_articles(p_qids text[]) returns int
language plpgsql security definer set search_path = '' as $$
declare r record; k int := 0; c record; tflag text; treason text; bq text;
begin
  for r in select * from ripples.articles where qid = any(p_qids) loop
    select * into c from ripples._classify(r.p31, r.short_desc);
    select b.action, b.reason into tflag, treason from ripples.blocklist b
     where b.title_pattern is not null and r.title_en ~* b.title_pattern order by (b.action = 'block') desc limit 1;
    select b.reason into bq from ripples.blocklist b where b.qid = r.qid and b.action = 'block' limit 1;
    update ripples.articles a set
      category    = c.category,
      emoji       = ripples._emoji(c.category),
      is_human    = 'Q5' = any(r.p31),
      is_list     = r.is_list or 'Q13406463' = any(r.p31)
                    or r.title_en ~* '^(lists? of|index of|outline of|timeline of|glossary of|deaths in|bibliography of|discography of) '
                    or r.title_en ~ '^[0-9]{1,4}s?( BC| AD| BCE| CE)?$' or r.title_en ~ '^[0-9]{4}s? in ',
      is_disambig = r.is_disambig or 'Q4167410' = any(r.p31) or r.title_en ~* '\(disambiguation\)$',
      sensitive   = coalesce(c.flag = 'sensitive', false) or coalesce(tflag = 'sensitive', false)
                    or exists (select 1 from ripples.blocklist b where b.qid = r.qid and b.action = 'sensitive'),
      blocked     = coalesce(c.flag = 'block', false) or coalesce(tflag = 'block', false) or bq is not null,
      block_reason = coalesce(case when bq is not null then 'blocklist: ' || bq end,
                              case when tflag = 'block' then 'title: ' || treason end,
                              case when c.flag = 'block' then c.flag_reason end,
                              case when c.flag = 'sensitive' or tflag = 'sensitive' then 'sensitive: ' || coalesce(c.flag_reason, treason) end)
     where a.qid = r.qid;
    k := k + 1;
  end loop;
  return k;
end $$;

-- Safety filter at use time (SPEC §5.4). p_median: the article's baseline median views/day when known.
create or replace function ripples._safe(p_qid text, p_as_of date, p_median numeric default null, p_allow_sensitive boolean default false)
returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select not a.blocked and not a.is_disambig and not a.is_list
       and (p_allow_sensitive or not a.sensitive)
       and (a.date_of_death is null or a.date_of_death < p_as_of - 60)
       and not (a.is_human and coalesce(a.sitelinks, 0) <= 1 and coalesce(p_median, 0) < 20)
       and a.category is not null
       and not exists (select 1 from ripples.blocklist b where b.title_pattern is not null and b.action = 'block' and a.title_en ~* b.title_pattern)
       and not exists (select 1 from ripples.blocklist b where b.qid = a.qid and b.action = 'block')
       and (p_allow_sensitive or not exists (select 1 from ripples.blocklist b where b.title_pattern is not null and b.action = 'sensitive' and a.title_en ~* b.title_pattern))
      from ripples.articles a where a.qid = p_qid), false)
$$;

create or replace function ripples._sbin(p_s numeric) returns text
language sql immutable set search_path = '' as $$
  select case when p_s is null or p_s < 3 then null when p_s < 4 then '3-4' when p_s < 6 then '4-6'
              when p_s < 10 then '6-10' else '10+' end
$$;

create or replace function ripples._qnorm(p text) returns text
language sql immutable set search_path = '' as $$ select lower(regexp_replace(btrim(p), '\s+', ' ', 'g')) $$;

-- ------------------------------------------------------------------ write paths (service_role only)
create or replace function public.ripples_ingest_trends(p_rows jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare k int;
begin
  with rows as (
    select * from jsonb_to_recordset(coalesce(p_rows, '[]')) as x(day date, source text, geo text, lang text, query text,
      traffic int, rank int, news jsonb)
    where x.query is not null and btrim(x.query) <> '' and x.day is not null
      and x.source in ('gtrends','bsky','topcountry','wikitop','featured')
  ), ins_wiki as (
    insert into ripples.trend_obs (day, source, geo, lang, query, traffic, rank, news)
    select distinct on (day, source, geo, query) day, source, geo, lang, left(query, 300), traffic, rank, news
      from rows where source in ('topcountry','wikitop','featured')
     order by day, source, geo, query, rank
    on conflict (day, source, geo, query) where source in ('topcountry','wikitop','featured')
    do update set rank = excluded.rank, traffic = excluded.traffic, observed_at = now()
    returning 1
  ), ins_other as (
    insert into ripples.trend_obs (day, source, geo, lang, query, traffic, rank, news)
    select day, source, geo, lang, left(query, 300), traffic, rank,
           case when jsonb_typeof(news) = 'array' then news end
      from rows where source in ('gtrends','bsky')
    returning 1
  )
  select (select count(*) from ins_wiki) + (select count(*) from ins_other) into k;
  -- attach QIDs already known
  update ripples.trend_obs t set qid = m.qid
    from ripples.title_map m
   where t.qid is null and t.observed_at > now() - interval '1 minute' and m.qid is not null
     and ((t.source in ('topcountry','wikitop','featured') and m.lang = t.lang and m.title = t.query)
       or (t.source = 'gtrends' and m.lang = 'q:' || t.lang and m.title = ripples._qnorm(t.query)));
  return k;
end $$;

-- p_rows: {"titles":[{lang,title,qid,title_en,status}], "articles":[{qid,title_en,short_desc,p31,date_of_death,
--          is_disambig,sitelinks}], "classes":[{class_qid,label,parents}]}
-- returns {"titles":n,"articles":n,"classes":n,"need_facts":[qid...],"unknown_classes":[qid...]}
create or replace function public.ripples_ingest_articles(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare nt int := 0; na int := 0; nc int := 0; qids text[]; newcls text[]; need text[]; unk text[]; i int;
begin
  -- classes
  with c as (
    select * from jsonb_to_recordset(coalesce(p_rows->'classes', '[]')) as x(class_qid text, label text, parents text[])
     where x.class_qid ~ '^Q[0-9]+$'
  ), up as (
    insert into ripples.category_map (class_qid, category, label, parents, flag, flag_reason, source)
    select class_qid, coalesce(ripples._text_category(label), 'other'), left(label, 200), coalesce(parents, '{}'),
           ripples._text_flag(label), case when ripples._text_flag(label) is not null then 'label: ' || left(label, 100) end, 'auto'
      from c
    on conflict (class_qid) do update set label = coalesce(ripples.category_map.label, excluded.label),
      parents = case when ripples.category_map.source = 'auto' or cardinality(ripples.category_map.parents) = 0
                     then excluded.parents else ripples.category_map.parents end,
      updated_at = now()
    returning class_qid
  )
  select array_agg(class_qid) into newcls from up;
  nc := coalesce(cardinality(newcls), 0);
  if nc > 0 then
    -- auto classes inherit category / flag from mapped parents (3 passes = up to 3 levels)
    for i in 1..3 loop
      update ripples.category_map c set
        category = coalesce((select p.category from unnest(c.parents) with ordinality u(q, o)
                               join ripples.category_map p on p.class_qid = u.q where p.category <> 'other' order by u.o limit 1),
                            ripples._text_category(c.label), 'other'),
        flag = coalesce(ripples._text_flag(c.label),
                        (select 'block' from unnest(c.parents) u(q) join ripples.category_map p on p.class_qid = u.q where p.flag = 'block' limit 1),
                        (select 'block' from unnest(c.parents) u(q) join ripples.blocklist b on b.qid = u.q and b.action = 'block' limit 1),
                        (select 'sensitive' from unnest(c.parents) u(q) join ripples.category_map p on p.class_qid = u.q where p.flag = 'sensitive' limit 1),
                        (select 'sensitive' from unnest(c.parents) u(q) join ripples.blocklist b on b.qid = u.q and b.action = 'sensitive' limit 1)),
        flag_reason = coalesce(case when ripples._text_flag(c.label) is not null then 'label: ' || left(c.label, 100) end,
                               (select 'parent: ' || coalesce(p.label, p.class_qid) from unnest(c.parents) u(q) join ripples.category_map p
                                  on p.class_qid = u.q where p.flag is not null order by (p.flag = 'block') desc limit 1),
                               (select 'parent blocklist: ' || b.reason from unnest(c.parents) u(q) join ripples.blocklist b on b.qid = u.q limit 1))
       where c.source = 'auto' and (c.class_qid = any(newcls) or c.parents && newcls);
    end loop;
    perform ripples._refresh_articles(array(select qid from ripples.articles where p31 && newcls
                                            or p31 && array(select class_qid from ripples.category_map where parents && newcls)));
    select array_agg(distinct q) into unk from (
      select unnest(parents) q from ripples.category_map where class_qid = any(newcls)
             and category = 'other' and flag is null) s
     where not exists (select 1 from ripples.category_map m where m.class_qid = s.q);
  end if;

  -- title map
  with t as (
    select * from jsonb_to_recordset(coalesce(p_rows->'titles', '[]')) as x(lang text, title text, qid text, title_en text, status text)
     where x.lang is not null and x.title is not null and x.status in ('ok','missing','no_en','no_match')
  ), up as (
    insert into ripples.title_map (lang, title, qid, title_en, status, resolved_at)
    select distinct on (lang, title) lang, left(title, 300), case when qid ~ '^Q[0-9]+$' then qid end, title_en, status, now() from t
    on conflict (lang, title) do update set qid = excluded.qid, title_en = excluded.title_en, status = excluded.status, resolved_at = now()
    returning qid
  )
  select count(*), array_agg(distinct qid) filter (where qid is not null) into nt, qids from up;
  if nt > 0 then
    update ripples.trend_obs t set qid = m.qid
      from ripples.title_map m
     where t.qid is null and m.qid is not null and t.day >= current_date - 30
       and ((t.source in ('topcountry','wikitop','featured') and m.lang = t.lang and m.title = t.query)
         or (t.source = 'gtrends' and m.lang = 'q:' || t.lang and m.title = ripples._qnorm(t.query)));
    select array_agg(q) into need from unnest(coalesce(qids, '{}')) q
     where not exists (select 1 from ripples.articles a where a.qid = q and a.updated_at > now() - interval '30 days');
  end if;

  -- articles
  with a as (
    select * from jsonb_to_recordset(coalesce(p_rows->'articles', '[]')) as x(qid text, title_en text, short_desc text,
      p31 text[], date_of_death date, is_disambig boolean, sitelinks int)
     where x.qid ~ '^Q[0-9]+$' and x.title_en is not null
  ), up as (
    insert into ripples.articles (qid, title_en, short_desc, p31, date_of_death, is_disambig, sitelinks, updated_at)
    select distinct on (qid) qid, left(title_en, 300), left(short_desc, 300), coalesce(p31, '{}'), date_of_death,
           coalesce(is_disambig, false), sitelinks, now() from a
    on conflict (qid) do update set title_en = excluded.title_en,
      short_desc = coalesce(excluded.short_desc, ripples.articles.short_desc), p31 = excluded.p31,
      date_of_death = excluded.date_of_death, is_disambig = excluded.is_disambig, sitelinks = excluded.sitelinks,
      updated_at = now()
    returning qid
  )
  select count(*), array_agg(qid) into na, qids from up;
  if na > 0 then
    perform ripples._refresh_articles(qids);
    select array_agg(distinct q) into unk from (
      select unnest(coalesce(unk, '{}')) q
      union select unnest(p31) from ripples.articles where qid = any(qids)) s
     where s.q is not null and not exists (select 1 from ripples.category_map m where m.class_qid = s.q);
  end if;
  return jsonb_build_object('titles', nt, 'articles', na, 'classes', nc,
    'need_facts', to_jsonb(coalesce(need, '{}')), 'unknown_classes', to_jsonb(coalesce(unk, '{}')));
end $$;

-- Edge write path for screen / expand / split / refresh jobs (dispatch on the job's kind).
create or replace function public.ripples_ingest_candidates(p_job bigint, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare j ripples.jobs; k int := 0; need text[];
begin
  select * into j from ripples.jobs where id = p_job;
  if not found then raise exception 'unknown job %', p_job; end if;
  if j.kind = 'screen' then
    insert into ripples.screen (as_of, qid, title, median_views, onset, z_peak, peak_multiple, peak_day, max_abs_z14, base_from, base_to, spark)
    select j.as_of, x.qid, x.title, x.median_views, x.onset, x.z_peak, x.peak_multiple, x.peak_day, x.max_abs_z14, x.base_from, x.base_to, x.spark
      from jsonb_to_recordset(coalesce(p_rows, '[]')) as x(qid text, title text, median_views numeric, onset date, z_peak numeric,
           peak_multiple numeric, peak_day date, max_abs_z14 numeric, base_from date, base_to date, spark int[])
     where x.qid ~ '^Q[0-9]+$'
    on conflict (as_of, qid) do update set title = excluded.title, median_views = excluded.median_views, onset = excluded.onset,
      z_peak = excluded.z_peak, peak_multiple = excluded.peak_multiple, peak_day = excluded.peak_day,
      max_abs_z14 = excluded.max_abs_z14, base_from = excluded.base_from, base_to = excluded.base_to, spark = excluded.spark;
    get diagnostics k = row_count;
    return jsonb_build_object('inserted', k);
  elsif j.kind = 'expand' then
    insert into ripples.candidates (as_of, role, root_qid, depth, parent_qid, qid, title, cs_rank, cs_clicks, set_rank, linked,
      median_views, s_stat, onset_lag, multiple, p_time, n_placebo, pass_raw, calm, max_abs_z, spark, main_page, category, job_id)
    select j.as_of, j.role, j.root_qid, j.depth, j.parent_qid, x.qid, x.title, x.cs_rank, x.cs_clicks, x.set_rank, coalesce(x.linked, true),
           x.median_views, x.s_stat, x.onset_lag, x.multiple, x.p_time, x.n_placebo, coalesce(x.pass_raw, false), coalesce(x.calm, false),
           x.max_abs_z, x.spark,
           -- Main Page feature (TFA / DYK / On this day / In the news) within ±1 day of the candidate's onset
           exists (select 1 from ripples.trend_obs t where t.source = 'featured' and t.geo in ('tfa','dyk','onthisday','news')
                     and (t.qid = x.qid or (t.lang = 'en' and t.query = x.title))
                     and t.day between j.parent_onset + coalesce(x.onset_lag, 0) - 1 and j.parent_onset + coalesce(x.onset_lag, 0) + 1),
           (select a.category from ripples.articles a where a.qid = x.qid), j.id
      from jsonb_to_recordset(coalesce(p_rows, '[]')) as x(qid text, title text, cs_rank int, cs_clicks int, set_rank int, linked boolean,
           median_views numeric, s_stat numeric, onset_lag int, multiple numeric, p_time numeric, n_placebo int, pass_raw boolean,
           calm boolean, max_abs_z numeric, spark int[])
     where x.qid ~ '^Q[0-9]+$'
    on conflict (as_of, role, root_qid, parent_qid, qid) do update set title = excluded.title, cs_rank = excluded.cs_rank,
      cs_clicks = excluded.cs_clicks, set_rank = excluded.set_rank, linked = excluded.linked, median_views = excluded.median_views,
      s_stat = excluded.s_stat, onset_lag = excluded.onset_lag, multiple = excluded.multiple, p_time = excluded.p_time,
      n_placebo = excluded.n_placebo, pass_raw = excluded.pass_raw, calm = excluded.calm, max_abs_z = excluded.max_abs_z,
      spark = excluded.spark, main_page = excluded.main_page, job_id = excluded.job_id;
    get diagnostics k = row_count;
    select array_agg(distinct c.qid) into need from ripples.candidates c
     where c.job_id = j.id and (c.pass_raw or c.calm)
       and not exists (select 1 from ripples.articles a where a.qid = c.qid and a.updated_at > now() - interval '30 days');
    return jsonb_build_object('inserted', k, 'need_articles', to_jsonb(coalesce(need, '{}')));
  elsif j.kind = 'split' then
    update ripples.candidates c set mult_desktop = x.mult_desktop, mult_mobile = x.mult_mobile,
           split_ok = coalesce(x.mult_desktop >= 1.3 and x.mult_mobile >= 1.3, false)
      from jsonb_to_recordset(coalesce(p_rows, '[]')) as x(parent_qid text, qid text, mult_desktop numeric, mult_mobile numeric)
     where c.as_of = j.as_of and c.role = 'real' and c.root_qid = j.root_qid and c.parent_qid = x.parent_qid and c.qid = x.qid;
    get diagnostics k = row_count;
    return jsonb_build_object('updated', k);
  elsif j.kind = 'refresh' then
    update ripples.callit c set max_z = x.max_z, outcome = case when x.hit then 'hit' else 'miss' end, resolved_at = now()
      from jsonb_to_recordset(coalesce(p_rows, '[]')) as x(n int, qid text, max_z numeric, hit boolean)
     where c.n = x.n and c.qid = x.qid and c.outcome = 'pending' and x.max_z is not null;
    get diagnostics k = row_count;
    return jsonb_build_object('resolved', k);
  end if;
  raise exception 'job kind % has no candidate rows', j.kind;
end $$;

create or replace function public.ripples_ingest_seed_history(p_job bigint, p_row jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare j ripples.jobs; k int;
begin
  select * into j from ripples.jobs where id = p_job;
  if not found then raise exception 'unknown job %', p_job; end if;
  update ripples.seeds s set biggest_in_days = (p_row->>'biggest_in_days')::int,
         biggest_since_records = coalesce((p_row->>'biggest_since_records')::boolean, false)
   where s.as_of = j.as_of and s.qid = p_row->>'qid' and s.role = 'real';
  get diagnostics k = row_count;
  return jsonb_build_object('updated', k);
end $$;

-- ------------------------------------------------------------------ job queue
create or replace function ripples._pcfg(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path = '' as $$
  select coalesce((select (value->>p_key)::numeric from ripples.config where key = 'pipeline'), p_default)
$$;

-- The JSON body sent to the edge function for a job.
create or replace function ripples._job_payload(p_job bigint, p_budget int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare j ripples.jobs; body jsonb; cs jsonb := '[]'; cm date;
begin
  select * into j from ripples.jobs where id = p_job;
  body := jsonb_build_object('job', jsonb_build_object('id', j.id, 'as_of', j.as_of, 'kind', j.kind, 'role', j.role,
            'root_qid', j.root_qid, 'parent_qid', j.parent_qid, 'parent_title', j.parent_title, 'parent_onset', j.parent_onset,
            'depth', j.depth),
          'budget', p_budget,
          'cfg', (select value from ripples.config where key = 'pipeline')) || j.payload;
  if j.kind = 'expand' then
    -- clickstream top 20 of the parent (W3 table; used only when it has rows)
    if to_regclass('ripples.clickstream') is not null then
      begin
        execute 'select max(month) from ripples.clickstream' into cm;
        if cm is not null then
          execute $q$select coalesce(jsonb_agg(jsonb_build_object('title', replace(curr, '_', ' '), 'clicks', n, 'rank', rank) order by rank), '[]')
                     from (select curr, n, rank from ripples.clickstream
                            where month = $1 and replace(prev, '_', ' ') = $2 order by rank limit 20) s$q$
            into cs using cm, j.parent_title;
        end if;
      exception when others then cs := '[]';
      end;
    end if;
    body := body || jsonb_build_object('clickstream', cs, 'clickstream_month', to_char(cm, 'YYYY-MM'),
      'block_patterns', (select coalesce(jsonb_agg(title_pattern), '[]') from ripples.blocklist where title_pattern is not null and action = 'block'));
  elsif j.kind = 'collect' then
    body := body || jsonb_build_object('trending_now', coalesce((select value = 'true'::jsonb from ripples.config where key = 'gt_trending_now'), false));
  end if;
  return body;
end $$;

create or replace function ripples._enqueue(p_as_of date, p_kind text, p_role text, p_root text, p_parent text, p_parent_title text,
  p_onset date, p_depth int, p_payload jsonb default '{}') returns bigint
language sql security definer set search_path = '' as $$
  insert into ripples.jobs (as_of, kind, role, root_qid, parent_qid, parent_title, parent_onset, depth, payload)
  values (p_as_of, p_kind, p_role, p_root, p_parent, p_parent_title, p_onset, p_depth, coalesce(p_payload, '{}'))
  returning id
$$;

-- Dispatch queued jobs through public.call_collector. At most one running job that uses the MediaWiki Action API
-- (collect / resolve / expand: one request stream per host) and `max_running_aqs` AQS-only jobs; at most p_max per call.
create or replace function ripples._dispatch(p_max int default 6) returns int
language plpgsql security definer set search_path = '' as $$
declare j record; k int := 0; cap int; used int; run_api int; run_aqs int; max_api int; max_aqs int; bud int; fn text; nid bigint;
begin
  if not pg_try_advisory_xact_lock(hashtext('ripples_dispatch')) then return 0; end if;
  cap := coalesce((ripples._cfg('wm_daily_cap') #>> '{}')::int, 6000);
  max_api := ripples._pcfg('max_running_api', 1);
  max_aqs := ripples._pcfg('max_running_aqs', 2);
  for j in
    select q.* from ripples.jobs q join ripples.runs r on r.as_of = q.as_of
     where q.status = 'queued' and (q.not_before is null or q.not_before <= now())
       and r.stage in ('collect_daily','resolve','screen','seeds','expand','build','done')
     order by case q.kind when 'collect' then 0 when 'resolve' then 1 when 'screen' then 2 when 'history' then 3
                          when 'expand' then 4 when 'split' then 5 else 6 end,
              q.as_of desc, (q.role = 'decoy'), q.depth nulls first, q.id
     for update of q skip locked
  loop
    exit when k >= p_max;
    select count(*) filter (where kind in ('collect','resolve','expand')), count(*) filter (where kind in ('screen','history','split','refresh'))
      into run_api, run_aqs from ripples.jobs where status = 'running';
    if j.kind in ('collect','resolve','expand') and run_api >= max_api then continue; end if;
    if j.kind in ('screen','history','split','refresh') and run_aqs >= max_aqs then continue; end if;
    select r.wm_calls + coalesce((select sum(100) from ripples.jobs x where x.as_of = j.as_of and x.status = 'running'), 0)
      into used from ripples.runs r where r.as_of = j.as_of;
    bud := least(100, cap - coalesce(used, 0));
    if bud < 10 then
      if (select wm_calls from ripples.runs where as_of = j.as_of) >= cap - 10 then
        update ripples.jobs set status = 'skipped', error = 'wm_daily_cap reached', finished_at = now() where id = j.id;
      end if;
      continue;
    end if;
    fn := case j.kind when 'collect' then 'ripples-collect' when 'resolve' then 'ripples-resolve' else 'ripples-expand' end;
    update ripples.jobs set status = 'running', attempts = attempts + 1, started_at = now(), error = null where id = j.id;
    nid := public.call_collector(fn, ripples._job_payload(j.id, bud));
    update ripples.jobs set net_id = nid where id = j.id;
    k := k + 1;
  end loop;
  return k;
end $$;

-- Edge completion callback: records the outcome and Wikimedia call count, retries failures (<= 3 attempts,
-- after a pause), and dispatches the next queued jobs.
create or replace function public.ripples_job_done(p_job bigint, p_ok boolean, p_err text, p_calls int, p_result jsonb default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare j ripples.jobs; st text;
begin
  select * into j from ripples.jobs where id = p_job for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown job'); end if;
  if j.status <> 'running' then
    -- late completion of a job that was requeued: count the calls, keep the newer state
    update ripples.runs set wm_calls = wm_calls + greatest(coalesce(p_calls, 0), 0) where as_of = j.as_of;
    return jsonb_build_object('ok', true, 'late', true);
  end if;
  st := case when p_ok then 'done' when j.attempts < 3 then 'queued' else 'failed' end;
  update ripples.jobs set status = st, calls = calls + greatest(coalesce(p_calls, 0), 0), error = left(p_err, 500),
         result = p_result, finished_at = case when st in ('done','failed') then now() end,
         not_before = case when st = 'queued' then now() + case when p_err like 'rate_limited%' then interval '3 minutes' else interval '30 seconds' end end
   where id = p_job;
  update ripples.runs set wm_calls = wm_calls + greatest(coalesce(p_calls, 0), 0),
         errors = errors + case when p_ok then 0 else 1 end
   where as_of = j.as_of;
  perform ripples._dispatch(6);
  return jsonb_build_object('ok', true, 'status', st);
end $$;

do $$
declare f text;
begin
  foreach f in array array['public.ripples_ingest_trends(jsonb)', 'public.ripples_ingest_articles(jsonb)',
    'public.ripples_ingest_candidates(bigint, jsonb)', 'public.ripples_ingest_seed_history(bigint, jsonb)',
    'public.ripples_job_done(bigint, boolean, text, integer, jsonb)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
