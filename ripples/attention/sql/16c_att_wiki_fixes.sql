-- 16c_att_wiki_fixes (W7 att-wiki, 2026-09-25, applied as migration att_wiki_fixes_coverage_media_daycap)
-- Verifier findings fixed here:
--  (1) Completeness is judged by DAILY COVERAGE, not by first_day span. A wiki.pv series counts as complete only when it
--      has one row for every day from as_of - (pv_days - 20) to its last day. Gappy series (mirrored from
--      public.signal_obs with holes, or older core-build series) are planned as 'first' = one AQS call for the full
--      window, which zero-fills correctly (AQS omits zero days). Missing days in public.signal_obs are NOT zero-filled
--      in SQL, because a hole there can be a collection gap rather than a zero.
--      att_wiki_progress reports 'with_400d_complete' (every day of the last 400 present) instead of a span count.
--  (2) Lead images for mediarequests are resolved from Wikidata Special:EntityData/<QID>.json (claim P18; a /wiki/ path
--      that Wikimedia's robots.txt allows; robots.txt is checked at run time) instead of the Action API. The Action
--      API route (prop=pageimages) runs only if the owner sets att_config.wiki.action_api_ok = true (confirming
--      DEMARCATION §7.1 over §0 / matrix row 200) AND adds 'wikipedia.org' back to att_sources.wiki.media.hosts.
--  (3) att_sources.per_day_cap is enforced even when the source draws on a shared bucket (wiki.cs: 3/day inside the
--      'wikimedia' share): att.ts politeFetch also charges the per-source bucket 'src:<source>', which _att_bucket
--      now resolves to that source's per_day_cap.

-- (3) per-source day buckets -------------------------------------------------------------------------------------------
create or replace function ripples._att_bucket(p_bucket text, out bucket text, out cap int, out enabled boolean)
returns record language plpgsql stable security definer set search_path = '' as $$
declare s record;
begin
  bucket := p_bucket; enabled := true;
  if p_bucket like 'src:%' then
    -- per-source daily cap inside a shared bucket (att.ts charges both); no row / no per_day_cap = no units
    select * into s from ripples.att_sources where source = substr(p_bucket, 5);
    if found then enabled := s.enabled; cap := s.per_day_cap; else enabled := false; end if;
    return;
  end if;
  select * into s from ripples.att_sources where source = p_bucket;
  if found then
    enabled := s.enabled;
    if s.budget_bucket is not null then bucket := s.budget_bucket; else cap := s.per_day_cap; end if;
  end if;
  if cap is null then
    cap := (ripples._att_cfg('budgets') ->> bucket)::int;
  end if;
end $$;
revoke all on function ripples._att_bucket(text) from public, anon, authenticated;
grant execute on function ripples._att_bucket(text) to service_role;

-- (2) wiki.media: EntityData host instead of the Action API; config flag ---------------------------------------------
update ripples.att_sources set hosts = array['wikimedia.org', 'www.wikidata.org'],
  reason = 'Q6: AQS 100 req/s published -> 1 req/s serial; lead image = Wikidata P18 via Special:EntityData (robots.txt checked); Action API pageimages only if att_config.wiki.action_api_ok (owner, §7.1); shared wikimedia bucket'
 where source = 'wiki.media';
update ripples.att_config set value = value || '{"action_api_ok": false, "entitydata_max_mb": 12}'::jsonb, updated_at = now()
 where key = 'wiki' and not (value ? 'action_api_ok');

-- (1) coverage-aware planner ---------------------------------------------------------------------------------------------
-- kinds: first  = no series, or the series is not complete over [as_of - (pv_days - 20), last day] (late start or gaps)
--        incr   = complete but behind as_of (active: daily; panel-only: every panel_every_days)
--        signal = public.signals title whose mirrored series is complete (collect-wikipedia keeps it current)
--        done / nodata / inactive as before
create or replace function ripples.att_wiki_pv_plan(p_as_of date, p_limit int default 500, p_keys jsonb default null)
returns table(key text, geo text, topic_id bigint, series_id bigint, from_day date, kind text, prio int,
              last_day date, first_day date, act boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  cfg jsonb := coalesce(ripples._att_cfg('wiki'), '{}'::jsonb);
  v_prof text := coalesce(ripples._att_cfg('profile') #>> '{}', 'free');
  v_days int := coalesce((cfg->>'pv_days')::int, 420);
  v_every int := coalesce((cfg->'panel_every_days'->>v_prof)::int, 2);
  v_retry int := coalesce((cfg->>'nodata_retry_days')::int, 7);
  v_nodata jsonb := coalesce((select s.v from ripples.att_state s where s.k = 'wiki.pv.nodata'), '{}'::jsonb);
  v_win date := p_as_of - (coalesce((cfg->>'pv_days')::int, 420) - 20);
begin
  return query
  with inp as (
    select distinct e->>'key' as key, coalesce(e->>'geo', 'en.wikipedia') as geo
    from jsonb_array_elements(coalesce(p_keys, '[]'::jsonb)) e where e->>'key' is not null),
  reg as (
    select r.* from ripples._att_wiki_reg() r
    where p_keys is null or exists (select 1 from inp i where i.key = r.key and i.geo = r.geo)),
  s as (
    select r.key, r.geo, r.topic_id, r.act, sr.series_id, st.l as last_day, st.f as first_day,
           (st.f is not null and st.f <= v_win and st.n = (st.l - v_win + 1)) as complete,
           exists (select 1 from public.signals g where g.kind = 'wikipedia_pageviews' and g.active
                    and g.project = r.geo and g.article = r.key) as sig
    from reg r
    left join ripples.att_series sr on sr.source = 'wiki.pv' and sr.metric = 'n' and sr.geo = r.geo and sr.key = r.key
    left join lateral (
      select min(o.day) as f, max(o.day) as l, count(*) filter (where o.day >= v_win) as n
      from ripples.attention_obs o where o.series_id = sr.series_id) st on true),
  c as (
    select s.*, case
      when s.sig and s.complete then 'signal'
      when v_nodata ? (s.geo || '|' || s.key)
           and (v_nodata->>(s.geo || '|' || s.key))::date > p_as_of - v_retry then 'nodata'
      when s.series_id is null or not s.complete then 'first'
      when s.last_day >= p_as_of then 'done'
      when not s.act and s.last_day > p_as_of - v_every then 'done'
      else 'incr' end as kind
    from s),
  res as (
    select c.key, c.geo, c.topic_id, c.series_id,
           case c.kind when 'first' then p_as_of - v_days
                       when 'incr' then greatest(c.last_day + 1, p_as_of - v_days) end as from_day,
           c.kind,
           case when c.kind = 'first' and c.act then 0 when c.kind = 'incr' and c.act then 1
                when c.kind = 'first' then 2 when c.kind = 'incr' then 3 else 9 end as prio,
           c.last_day, c.first_day, c.act
    from c
    union all
    select i.key, i.geo, null::bigint, null::bigint, null::date, 'inactive', 9, null::date, null::date, false
    from inp i where not exists (select 1 from ripples._att_wiki_reg() r where r.key = i.key and r.geo = i.geo))
  select o.key, o.geo, o.topic_id, o.series_id, o.from_day, o.kind, o.prio, o.last_day, o.first_day, o.act
  from res o
  where p_keys is not null or o.kind in ('first', 'incr')
  order by o.prio, o.last_day nulls first, o.key
  limit greatest(p_limit, 0);
end $$;

-- Progress: complete daily coverage (not first_day span).
create or replace function ripples.att_wiki_progress(p_as_of date default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with a as (select coalesce(p_as_of, (now() at time zone 'utc')::date - 1) as d),
  p as (select * from ripples.att_wiki_pv_plan((select d from a), 1000000,
          (select jsonb_agg(jsonb_build_object('key', r.key, 'geo', r.geo)) from ripples._att_wiki_reg() r))),
  cov as (   -- per registry key: rows present in the last 400 days up to as_of, and whether the span is gap-free
    select p.key, p.geo, p.kind, p.act, st.n400, st.f, st.l
    from p
    left join ripples.att_series sr on sr.source = 'wiki.pv' and sr.metric = 'n' and sr.geo = p.geo and sr.key = p.key
    left join lateral (
      select count(*) filter (where o.day between (select d from a) - 399 and (select d from a)) as n400,
             min(o.day) as f, max(o.day) as l
      from ripples.attention_obs o where o.series_id = sr.series_id) st on true
    where p.kind <> 'inactive')
  select jsonb_build_object(
    'as_of', (select d from a),
    'registry_keys', (select count(*) from cov),
    'by_kind', (select jsonb_object_agg(kind, n) from (select kind, count(*) n from p group by kind) x),
    'active_first_pending', (select count(*) from p where p.kind = 'first' and p.act),
    'panel_first_pending', (select count(*) from p where p.kind = 'first' and not p.act),
    -- every one of the 400 days up to as_of present (as_of itself may lag one day for mirrored signal series)
    'with_400d_complete', (select count(*) from cov
                            where cov.f <= (select d from a) - 399 and cov.l >= (select d from a) - 1
                              and cov.n400 = cov.l - ((select d from a) - 399) + 1),
    'with_400d_span_only', (select count(*) from cov where cov.f <= (select d from a) - 399),
    'gappy_series', (select count(*) from cov where cov.f is not null and cov.n400 < least(cov.l, (select d from a)) - greatest(cov.f, (select d from a) - 399) + 1),
    'wikimedia_budget', (select jsonb_agg(jsonb_build_object('day', b.day, 'used', b.used, 'cap', b.cap, 'killed', b.killed) order by b.day)
                         from ripples.att_budget b where b.bucket = 'wikimedia' and b.day >= (select d from a)),
    'topcc_series', (select count(*) from ripples.att_series s where s.source = 'wiki.topcc'),
    'topcc_countries_latest', (select count(distinct s.geo) from ripples.att_series s
                                 where s.source = 'wiki.topcc' and s.metric = 'rank' and s.last_day >= (select d from a) - 1),
    'media_keys', (select count(*) from ripples.att_keys k where k.source = 'wiki.media'))
$$;

-- (2) media plan now carries the topic QID (EntityData P18 resolver) --------------------------------------------------
drop function if exists public.att_wiki_media_plan(date, int);
drop function if exists ripples.att_wiki_media_plan(date, int);
create function ripples.att_wiki_media_plan(p_as_of date, p_limit int default 300)
returns table(kind text, topic_id bigint, project text, title text, qid text, key text, path text, series_id bigint,
              from_day date, last_day date)
language plpgsql stable security definer set search_path = '' as $$
declare
  cfg jsonb := coalesce(ripples._att_cfg('wiki'), '{}'::jsonb);
  v_prof text := coalesce(ripples._att_cfg('profile') #>> '{}', 'free');
  v_scope text := coalesce(cfg->'media_scope'->>v_prof, 'active');
  v_days int := coalesce((cfg->>'media_days')::int, 420);
  v_every int := coalesce((cfg->>'media_every_days')::int, 3);
  v_recheck int := coalesce((cfg->>'media_recheck_days')::int, 30);
  v_none jsonb := coalesce((select s.v from ripples.att_state s where s.k = 'wiki.media.none'), '{}'::jsonb);
begin
  return query
  with tp as (
    select t.topic_id, t.qid, (t.status = 'active') as act from ripples.att_topics t
    where t.status = 'active' or (v_scope = 'all' and t.in_panel)),
  pv as (  -- one article per topic: prefer enwiki
    select distinct on (k.topic_id) k.topic_id, tp.qid, k.geo, k.key from ripples.att_keys k join tp on tp.topic_id = k.topic_id
    where k.source = 'wiki.pv' and k.enabled and k.geo like '%.wikipedia'
    order by k.topic_id, (k.geo = 'en.wikipedia') desc, k.geo),
  res as (
    select 'resolve'::text as kind, pv.topic_id, pv.geo as project, pv.key as title,
           case when pv.qid ~ '^Q[0-9]+$' then pv.qid end as qid, null::text as key, null::text as path,
           null::bigint as series_id, null::date as from_day, null::date as last_day, 0 as prio
    from pv
    where not exists (select 1 from ripples.att_keys m where m.topic_id = pv.topic_id and m.source = 'wiki.media')
      and not (v_none ? pv.topic_id::text and (v_none->>pv.topic_id::text)::date > p_as_of - v_recheck)),
  fk as (
    select distinct on (m.key) m.topic_id, m.key, m.match->>'path' as path, s.series_id, s.last_day, tp.act,
           (select min(o.day) from ripples.attention_obs o where o.series_id = s.series_id) as first_day
    from ripples.att_keys m join tp on tp.topic_id = m.topic_id
    left join ripples.att_series s on s.source = 'wiki.media' and s.metric = 'n' and s.geo = 'ALL' and s.key = m.key
    where m.source = 'wiki.media' and m.enabled and m.match ? 'path'
    order by m.key, tp.act desc),
  fx as (
    select case when fk.series_id is null or fk.first_day is null or fk.first_day > p_as_of - (v_days - 20) then 'first'
                when fk.last_day <= p_as_of - v_every then 'incr' end as kind,
           fk.* from fk)
  select x.kind, x.topic_id, x.project, x.title, x.qid, x.key, x.path, x.series_id, x.from_day, x.last_day from (
    select * from res
    union all
    select fx.kind, fx.topic_id, null, null, null, fx.key, fx.path, fx.series_id,
           case fx.kind when 'first' then p_as_of - v_days else greatest(fx.last_day + 1, p_as_of - v_days) end,
           fx.last_day, case fx.kind when 'first' then 1 else 2 end
    from fx where fx.kind is not null) x
  order by x.prio, x.last_day nulls first, x.topic_id
  limit greatest(p_limit, 0);
end $$;
create function public.att_wiki_media_plan(p_as_of date, p_limit int default 300)
returns table(kind text, topic_id bigint, project text, title text, qid text, key text, path text, series_id bigint,
              from_day date, last_day date)
language sql stable security definer set search_path = '' as $$ select * from ripples.att_wiki_media_plan(p_as_of, p_limit) $$;

do $$
declare f text;
begin
  foreach f in array array[
    'ripples.att_wiki_pv_plan(date, int, jsonb)', 'ripples.att_wiki_progress(date)',
    'ripples.att_wiki_media_plan(date, int)', 'public.att_wiki_media_plan(date, int)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
