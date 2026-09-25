-- Knock-On v5 / W2: migration ripples_v5_pipeline_tuning (after the first live test run)
-- 1. one running job at a time (the shared Supabase egress IP got 429s from AQS and the Action API when two
--    jobs overlapped); 2. class-label categories no longer inherit "person" from "legal person" etc.;
-- 3. extra screening pool for decoy epicenters (calm pages are rare among top-list articles).

update ripples.config set value = value || '{"max_running_total":1,"expand_prefilter_calls":10,"decoy_pool_titles":80}'::jsonb
 where key = 'pipeline';

-- Category for a Wikidata class label: the keyword map, except that only "human" itself maps to person
-- (labels such as "legal person" or "people" describe organisations and groups, not a person).
create or replace function ripples._class_category(p text) returns text
language sql immutable set search_path = '' as $$
  select case when p ~* '^(fictional )?human$' then 'person'
              when ripples._text_category(p) = 'person' then null
              else ripples._text_category(p) end
$$;

create or replace function ripples._text_flag(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p is null then null
    when p ~* '(^|[^a-z])(film|series|novel|fiction|genre|game|album|song|book|television|episode|character|comic|manga|anime|franchise|magazine|podcast|video|play|musical|show|literature|work)s?([^a-z]|$)' then null
    when p ~* '(^|[^a-z])(war|civil war|battle|military (operation|campaign|conflict|offensive)|armed conflict|military conflict|invasion|terrorism|terrorist attack|attack|bombing|shooting|mass shooting|massacre|murder|homicide|killing|assassination|genocide|war crime|suicide|suicide attack|mass murder|violence|riot|insurgency|crime|pornography|sexual violence|rape|hate group|hate crime|lynching|kidnapping|disappearance|terrorist organi[sz]ation)s?([^a-z]|$)' then 'block'
    when p ~* '(^|[^a-z])(aviation accident|aviation incident|air crash|shipwreck|disaster|explosion|stampede|accident|structural collapse|derailment|epidemic|pandemic|famine|mass casualty incident)s?([^a-z]|$)' then 'block'
    when p ~* '(^|[^a-z])(earthquake|tropical cyclone|hurricane|typhoon|tornado|flood|wildfire|bushfire|tsunami|volcanic eruption|landslide|heat wave|storm|blizzard|drought|natural disaster|weather event|extratropical cyclone|cold wave)s?([^a-z]|$)' then 'sensitive'
    else null end
$$;

-- Re-derive every auto-mapped class: own label first, then a parent whose category is seeded/manual or itself
-- label-derived (never a category that was only inherited), else other. Flags propagate from parents.
create or replace function ripples._rederive_classes(p_only text[] default null) returns int
language plpgsql security definer set search_path = '' as $$
declare i int; k int := 0; n int;
begin
  for i in 1..4 loop
    update ripples.category_map c set
      category = coalesce(ripples._class_category(c.label),
                          (select p.category from unnest(c.parents) with ordinality u(q, o)
                             join ripples.category_map p on p.class_qid = u.q
                            where p.category <> 'other' and (p.source <> 'auto' or ripples._class_category(p.label) is not null)
                            order by u.o limit 1),
                          'other'),
      flag = coalesce(ripples._text_flag(c.label),
                      (select 'block' from unnest(c.parents) u(q) join ripples.category_map p on p.class_qid = u.q where p.flag = 'block' limit 1),
                      (select 'block' from unnest(c.parents) u(q) join ripples.blocklist b on b.qid = u.q and b.action = 'block' limit 1),
                      (select 'sensitive' from unnest(c.parents) u(q) join ripples.category_map p on p.class_qid = u.q where p.flag = 'sensitive' limit 1),
                      (select 'sensitive' from unnest(c.parents) u(q) join ripples.blocklist b on b.qid = u.q and b.action = 'sensitive' limit 1)),
      flag_reason = coalesce(case when ripples._text_flag(c.label) is not null then 'label: ' || left(c.label, 100) end,
                             (select 'parent: ' || coalesce(p.label, p.class_qid) from unnest(c.parents) u(q) join ripples.category_map p
                                on p.class_qid = u.q where p.flag is not null order by (p.flag = 'block') desc limit 1),
                             (select 'parent blocklist: ' || b.reason from unnest(c.parents) u(q) join ripples.blocklist b on b.qid = u.q limit 1)),
      updated_at = now()
     where c.source = 'auto' and (p_only is null or c.class_qid = any(p_only) or c.parents && p_only);
    get diagnostics n = row_count;
    k := k + n;
  end loop;
  return k;
end $$;

create or replace function public.ripples_ingest_articles(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare nt int := 0; na int := 0; nc int := 0; qids text[]; newcls text[]; need text[]; unk text[];
begin
  with c as (
    select * from jsonb_to_recordset(coalesce(p_rows->'classes', '[]')) as x(class_qid text, label text, parents text[])
     where x.class_qid ~ '^Q[0-9]+$'
  ), up as (
    insert into ripples.category_map (class_qid, category, label, parents, flag, flag_reason, source)
    select distinct on (class_qid) class_qid, coalesce(ripples._class_category(label), 'other'), left(label, 200), coalesce(parents, '{}'),
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
    perform ripples._rederive_classes(newcls);
    perform ripples._refresh_articles(array(select qid from ripples.articles where p31 && newcls
                                            or p31 && array(select class_qid from ripples.category_map where parents && newcls)));
    select array_agg(distinct q) into unk from (
      select unnest(parents) q from ripples.category_map where class_qid = any(newcls)
             and category = 'other' and flag is null) s
     where not exists (select 1 from ripples.category_map m where m.class_qid = s.q);
  end if;

  with t as (
    select * from jsonb_to_recordset(coalesce(p_rows->'titles', '[]')) as x(lang text, title text, qid text, title_en text, status text)
     where x.lang is not null and x.title is not null and x.status in ('ok','missing','no_en','no_match')
  ), up as (
    insert into ripples.title_map (lang, title, qid, title_en, status, resolved_at)
    select distinct on (lang, left(title, 300)) lang, left(title, 300), case when qid ~ '^Q[0-9]+$' then qid end, title_en, status, now() from t
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

-- Screening list: the top seed-source articles, plus a decoy-epicenter pool (calm candidates from the last 7 days'
-- runs, else steady top-per-country titles ranked 101-200) so decoys can be matched on median decile and category.
create or replace function ripples._enqueue_screen(p_as_of date) returns int
language plpgsql security definer set search_path = '' as $$
declare per int := ripples._pcfg('screen_per_job', 80); mx int := ripples._pcfg('screen_titles', 240);
        extra int := ripples._pcfg('decoy_pool_titles', 80); items jsonb; k int := 0; i int;
begin
  with s as (
    select ss.qid, a.title_en, ss.nsrc, ss.best_rank from ripples._seed_sources(p_as_of) ss
      join ripples.articles a on a.qid = ss.qid
     where not a.is_disambig and not a.is_list and not a.blocked
       and not exists (select 1 from ripples.screen x where x.as_of = p_as_of and x.qid = ss.qid)
     order by ss.nsrc desc, ss.best_rank, ss.qid
     limit mx
  ), pool1 as (
    select distinct on (c.qid) c.qid, a.title_en, 1 pri, c.median_views
      from ripples.candidates c join ripples.articles a on a.qid = c.qid
     where c.as_of between p_as_of - 7 and p_as_of - 1 and c.calm and not a.blocked and not a.sensitive
       and not a.is_disambig and not a.is_list and a.category is not null
     order by c.qid, c.as_of desc
  ), pool2 as (
    select distinct on (m.qid) m.qid, a.title_en, 2 pri, null::numeric median_views
      from ripples.trend_obs t join ripples.title_map m on m.lang = t.lang and m.title = t.query
      join ripples.articles a on a.qid = m.qid
     where t.source = 'topcountry' and t.lang = 'en' and t.day = p_as_of and t.rank between 101 and 200
       and not a.blocked and not a.sensitive and not a.is_disambig and not a.is_list
     order by m.qid
  ), extra_list as (
    select p.qid, p.title_en from (select * from pool1 union all select * from pool2) p
     where p.qid not in (select qid from s)
       and not exists (select 1 from ripples.screen x where x.as_of = p_as_of and x.qid = p.qid)
     order by p.pri, md5(p.qid || p_as_of::text)
     limit extra
  ), allx as (
    select qid, title_en, 0 grp, nsrc, best_rank from s
    union all select qid, title_en, 1, 0, 0 from extra_list
  )
  select coalesce(jsonb_agg(jsonb_build_object('qid', qid, 'title', title_en) order by grp, nsrc desc, best_rank), '[]') into items
    from (select distinct on (qid) * from allx order by qid, grp) d;
  for i in 0 .. greatest(0, (jsonb_array_length(items) - 1) / per) loop
    exit when jsonb_array_length(items) = 0;
    perform ripples._enqueue(p_as_of, 'screen', null, null, null, null, null, null,
      jsonb_build_object('items', (select jsonb_agg(e) from jsonb_array_elements(items) with ordinality x(e, o)
                                    where o > i * per and o <= (i + 1) * per)));
    k := k + 1;
  end loop;
  return k;
end $$;

-- Dispatcher: at most `max_running_total` running jobs overall (default 1), within that at most
-- `max_running_api` Action-API jobs and `max_running_aqs` AQS-only jobs; at most p_max per call.
create or replace function ripples._dispatch(p_max int default 6) returns int
language plpgsql security definer set search_path = '' as $$
declare j record; k int := 0; cap int; used int; run_api int; run_aqs int; max_api int; max_aqs int; max_tot int;
        bud int; fn text; nid bigint;
begin
  if not pg_try_advisory_xact_lock(hashtext('ripples_dispatch')) then return 0; end if;
  cap := coalesce((ripples._cfg('wm_daily_cap') #>> '{}')::int, 6000);
  max_api := ripples._pcfg('max_running_api', 1);
  max_aqs := ripples._pcfg('max_running_aqs', 1);
  max_tot := ripples._pcfg('max_running_total', 1);
  for j in
    select q.* from ripples.jobs q join ripples.runs r on r.as_of = q.as_of
     where q.status = 'queued' and (q.not_before is null or q.not_before <= now())
       and r.stage in ('collect_daily','resolve','screen','seeds','expand','build','done')
     order by case q.kind when 'collect' then 0 when 'resolve' then 1 when 'screen' then 2 when 'history' then 3
                          when 'split' then 4 when 'expand' then 5 else 6 end,
              q.as_of desc, (q.role = 'decoy'), q.depth nulls first, q.id
     for update of q skip locked
  loop
    exit when k >= p_max;
    select count(*) filter (where kind in ('collect','resolve','expand')), count(*) filter (where kind in ('screen','history','split','refresh'))
      into run_api, run_aqs from ripples.jobs where status = 'running';
    exit when run_api + run_aqs >= max_tot;
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

select ripples._rederive_classes(null);
select ripples._refresh_articles(array(select qid from ripples.articles));
