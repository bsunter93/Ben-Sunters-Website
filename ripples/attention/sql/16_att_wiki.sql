-- 16_att_wiki (W7 att-wiki, 2026-09-25, applied as migration att_wiki_collector)
-- ATTENTION_STACK §3.3 att-wiki: wiki.topcc (top-per-country), wiki.pv (AQS per-article), wiki.media (Commons
-- mediarequests), wiki.cs (clickstream, small wikis only). Every attention Wikimedia call draws on the shared
-- 'wikimedia' bucket (att_config.budgets.wikimedia = 1500/day), charged inside att.ts politeFetch; the quiet window
-- 06:30-07:20 UTC is enforced by att_take_budget and politeFetch. Everything below is service_role only:
-- SECURITY DEFINER, search_path '', revoked from PUBLIC/anon/authenticated.

-- 1. source rows ---------------------------------------------------------------------------------------------------
-- AQS answered 429 at ~4 req/s from the shared Supabase egress IP on 2026-09-25 04:05 UTC. att-wiki paces every
-- Wikimedia call at >= 1 s (1 req/s; far below 50% of AQS's published 100 req/s, DEMARCATION Q6) and serially.
update ripples.att_sources set spacing_ms = 1000,
  reason = 'Q6: AQS publishes 100 req/s -> <= 50%; after the 2026-09-25 429 (~4 req/s from the shared Supabase IP) att-wiki paces 1 req/s, serial; shared wikimedia bucket (1500/day attention share)'
 where source in ('wiki.pv', 'wiki.topcc');
-- wiki.media: AQS mediarequests + lead-image lookup via the MediaWiki Action API (prop=pageimages, 50 titles/call,
-- maxlag=5, serial >= 1.1 s; DEMARCATION §7.1 GREEN with conditions)
update ripples.att_sources set spacing_ms = 1000, per_run_cap = 150, hosts = array['wikimedia.org', 'wikipedia.org'],
  reason = 'Q6: AQS 100 req/s published -> 1 req/s serial; lead images via Action API pageimages (§7.1: maxlag=5, serial >= 1.1 s); shared wikimedia bucket'
 where source = 'wiki.media';
-- wiki.cs: dumps.wikimedia.org is not an API -> robots.txt applies; counted against the wikimedia share
update ripples.att_sources set budget_bucket = 'wikimedia', per_run_cap = 3, robots_required = true, spacing_ms = 5000,
  reason = 'Q6: dumps, no published limit -> 1 req/5 s; files > att_config.wiki.cs_max_mb are GitHub-Action-only (ripples-clickstream.yml)'
 where source = 'wiki.cs';

-- 2. config ----------------------------------------------------------------------------------------------------------
insert into ripples.att_config(key, value) values ('wiki', $j${
  "countries": ["US","GB","CA","AU","IN","IE","NZ","ZA","NG","KE","PH","SG","MY","PK","BD",
                "DE","FR","ES","IT","NL","BE","CH","AT","PT","PL","SE","UA","TR",
                "BR","MX","AR","CO","CL","PE","JP","KR","TW","HK","ID","TH","VN","EG","SA","AE","IL"],
  "topcc_access": "all-access",
  "topcc_max_tries": 3,
  "topcc_hist_days": 3,
  "topcc_cand_max_rank": 200,
  "topcc_cand_min_ratio": 2,
  "topcc_snap_keep_days": 5,
  "pv_days": 420,
  "pv_max_articles": 400,
  "panel_every_days": {"free": 2, "pro": 1},
  "nodata_retry_days": 7,
  "media_scope": {"free": "active", "pro": "all"},
  "media_days": 420,
  "media_every_days": 3,
  "media_day_cap": 200,
  "media_recheck_days": 30,
  "cs_wikis": ["ptwiki","plwiki","zhwiki"],
  "cs_max_mb": 8
}$j$::jsonb)
on conflict (key) do update set value = excluded.value, updated_at = now();

-- 3. planners and helpers ---------------------------------------------------------------------------------------------
-- Registry wiki.pv keys (active topics first, then the panel), one row per (title, project).
create or replace function ripples._att_wiki_reg()
returns table(key text, geo text, topic_id bigint, act boolean, in_panel boolean, last_active date)
language sql stable security definer set search_path = '' as $$
  select distinct on (k.key, k.geo) k.key, k.geo, k.topic_id, (t.status = 'active'), t.in_panel, t.last_active
  from ripples.att_keys k join ripples.att_topics t on t.topic_id = k.topic_id
  where k.source = 'wiki.pv' and k.metric = 'n' and k.enabled and (t.status = 'active' or t.in_panel)
  order by k.key, k.geo, (t.status = 'active') desc, k.topic_id
$$;

-- AQS pageview work list. p_keys null: only rows to fetch (kind first|incr) in priority order.
-- p_keys [{key,geo}]: every requested key with its state (first|incr|done|signal|nodata|inactive).
-- first  = no series, or the series starts later than as_of - (pv_days - 20)  -> one call for the full history
-- incr   = series behind as_of (active: daily; panel-only: every panel_every_days) -> one call from last_day + 1
-- signal = title is a public.signals row (collect-wikipedia collects it; mirrored by att_wiki_mirror_signals) and the
--          mirrored series already reaches back pv_days - 20 days (shorter signal histories get one AQS 'first' fetch)
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
begin
  return query
  with inp as (
    select distinct e->>'key' as key, coalesce(e->>'geo', 'en.wikipedia') as geo
    from jsonb_array_elements(coalesce(p_keys, '[]'::jsonb)) e where e->>'key' is not null),
  reg as (
    select r.* from ripples._att_wiki_reg() r
    where p_keys is null or exists (select 1 from inp i where i.key = r.key and i.geo = r.geo)),
  s as (
    select r.key, r.geo, r.topic_id, r.act, sr.series_id, sr.last_day,
           (select min(o.day) from ripples.attention_obs o where o.series_id = sr.series_id) as first_day,
           exists (select 1 from public.signals g where g.kind = 'wikipedia_pageviews' and g.active
                    and g.project = r.geo and g.article = r.key) as sig
    from reg r
    left join ripples.att_series sr on sr.source = 'wiki.pv' and sr.metric = 'n' and sr.geo = r.geo and sr.key = r.key),
  c as (
    select s.*, case
      when s.sig and s.first_day is not null and s.first_day <= p_as_of - (v_days - 20) then 'signal'
      when v_nodata ? (s.geo || '|' || s.key)
           and (v_nodata->>(s.geo || '|' || s.key))::date > p_as_of - v_retry then 'nodata'
      when s.series_id is null or s.first_day is null or s.first_day > p_as_of - (v_days - 20) then 'first'
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

-- Mirror collect-wikipedia's daily views (public.signal_obs: all-access, agent=user, same as AQS here) into wiki.pv
-- series for registry titles that are signals. SQL only, no outbound request, idempotent.
create or replace function ripples.att_wiki_mirror_signals(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_days int := coalesce((ripples._att_cfg('wiki')->>'pv_days')::int, 420);
  v_as date := coalesce(p_as_of, (now() at time zone 'utc')::date - 1);
  v_rows jsonb; v_res jsonb;
begin
  with m as (
    select r.key, r.geo, r.topic_id, g.id as sid, s.last_day
    from ripples._att_wiki_reg() r
    join public.signals g on g.kind = 'wikipedia_pageviews' and g.active and g.project = r.geo and g.article = r.key
    left join ripples.att_series s on s.source = 'wiki.pv' and s.metric = 'n' and s.geo = r.geo and s.key = r.key)
  select jsonb_agg(jsonb_build_object('source', 'wiki.pv', 'geo', m.geo, 'key', m.key, 'day', o.day,
                                      'value', o.value, 'topic_id', m.topic_id))
    into v_rows
  from m join public.signal_obs o on o.signal_id = m.sid
  where o.day between greatest(v_as - v_days, coalesce(m.last_day - 3, v_as - v_days)) and v_as;
  if v_rows is null then return jsonb_build_object('rows', 0, 'series_new', 0); end if;
  v_res := ripples.att_ingest(v_rows);
  return jsonb_build_object('rows', v_res->'rows', 'series_new', v_res->'series_new',
                            'rejected', jsonb_array_length(coalesce(v_res->'rejected', '[]'::jsonb)));
end $$;

-- Reach (§6.2): number of top-per-country lists (of the countries fetched for p_day) that contain the article, per
-- registry title; aux = sum of views_ceil over those countries. Written for every registry title (0 = in none).
-- Also drops top-per-country snapshots older than topcc_snap_keep_days.
create or replace function ripples.att_wiki_topcc_reach(p_day date, p_coverage int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_rows jsonb; v_res jsonb; v_keep int := coalesce((ripples._att_cfg('wiki')->>'topcc_snap_keep_days')::int, 5); v_gc int;
begin
  with reg as (
    select split_part(g.geo, '.', 1) || ':' || g.key as k, g.topic_id from ripples._att_wiki_reg() g
    where g.geo like '%.wikipedia'),
  rk as (
    select s.key, count(*) as n, sum(o.aux) as views
    from ripples.att_series s join ripples.attention_obs o on o.series_id = s.series_id and o.day = p_day
    where s.source = 'wiki.topcc' and s.metric = 'rank' group by s.key)
  select jsonb_agg(jsonb_build_object('source', 'wiki.topcc', 'metric', 'reach', 'geo', 'ALL', 'key', reg.k,
                                      'day', p_day, 'value', coalesce(rk.n, 0), 'aux', coalesce(rk.views, 0),
                                      'topic_id', reg.topic_id, 'meta', jsonb_build_object('coverage', p_coverage)))
    into v_rows
  from reg left join rk on rk.key = reg.k;
  v_res := case when v_rows is null then '{"rows":0}'::jsonb else ripples.att_ingest(v_rows) end;
  delete from ripples.att_state
   where k like 'topcc.snap:%' and split_part(k, ':', 3) ~ '^\d{4}-\d{2}-\d{2}$'
     and split_part(k, ':', 3)::date < p_day - v_keep;
  get diagnostics v_gc = row_count;
  delete from ripples.att_state
   where k like 'topcc.day:%' and split_part(k, ':', 2) ~ '^\d{4}-\d{2}-\d{2}$'
     and split_part(k, ':', 2)::date < p_day - 30;
  return jsonb_build_object('rows', v_res->'rows', 'series_new', v_res->'series_new', 'snapshots_dropped', v_gc);
end $$;

-- Prior top-per-country snapshots (for the evergreen filter on discovery candidates).
create or replace function ripples.att_wiki_topcc_prev(p_day date, p_days int default 3)
returns table(cc text, day date, v jsonb)
language sql stable security definer set search_path = '' as $$
  select split_part(s.k, ':', 2), split_part(s.k, ':', 3)::date, s.v
  from ripples.att_state s
  where s.k like 'topcc.snap:%' and split_part(s.k, ':', 3) ~ '^\d{4}-\d{2}-\d{2}$'
    and split_part(s.k, ':', 3)::date between p_day - greatest(p_days, 1) and p_day - 1
$$;

-- Commons mediarequests work list: 'resolve' = topic in scope without a wiki.media key (and not recently found to have
-- no free lead image); 'first' / 'incr' = file series to fetch (every media_every_days, full window on first sight).
create or replace function ripples.att_wiki_media_plan(p_as_of date, p_limit int default 300)
returns table(kind text, topic_id bigint, project text, title text, key text, path text, series_id bigint,
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
    select t.topic_id, (t.status = 'active') as act from ripples.att_topics t
    where t.status = 'active' or (v_scope = 'all' and t.in_panel)),
  pv as (  -- one article per topic: prefer enwiki
    select distinct on (k.topic_id) k.topic_id, k.geo, k.key from ripples.att_keys k join tp on tp.topic_id = k.topic_id
    where k.source = 'wiki.pv' and k.enabled and k.geo like '%.wikipedia'
    order by k.topic_id, (k.geo = 'en.wikipedia') desc, k.geo),
  res as (
    select 'resolve'::text as kind, pv.topic_id, pv.geo as project, pv.key as title, null::text as key, null::text as path,
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
  select x.kind, x.topic_id, x.project, x.title, x.key, x.path, x.series_id, x.from_day, x.last_day from (
    select * from res
    union all
    select fx.kind, fx.topic_id, null, null, fx.key, fx.path, fx.series_id,
           case fx.kind when 'first' then p_as_of - v_days else greatest(fx.last_day + 1, p_as_of - v_days) end,
           fx.last_day, case fx.kind when 'first' then 1 else 2 end
    from fx where fx.kind is not null) x
  order by x.prio, x.last_day nulls first, x.topic_id
  limit greatest(p_limit, 0);
end $$;

-- Register resolved lead images as wiki.media keys (key 'commons:<File>' or '<wiki>:<File>', match.path = upload
-- path) and remember topics without a free lead image (att_state 'wiki.media.none', re-checked after 30 days).
create or replace function ripples.att_wiki_media_keys(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_ins int; v_none jsonb;
begin
  with ins as (
    insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match, weight, verified, enabled, created_by)
    select distinct on ((e->>'topic_id')::bigint, left(e->>'key', 300))
           (e->>'topic_id')::bigint, 'wiki.media', 'n', 'ALL', left(e->>'key', 300), 'media',
           jsonb_build_object('path', e->>'path'), 1, false, true, 'auto'
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e
    where e->>'topic_id' ~ '^\d+$' and e->>'key' is not null
      and e->>'path' ~ '^/wikipedia/[a-z0-9-]+/[0-9a-f]/[0-9a-f]{2}/[^/]+$'
      and exists (select 1 from ripples.att_topics t where t.topic_id = (e->>'topic_id')::bigint)
      and not ripples._att_ident_like(e->>'key', 'wiki.media', false)
    on conflict do nothing
    returning 1)
  select count(*) into v_ins from ins;
  select jsonb_object_agg(e->>'topic_id', to_char((now() at time zone 'utc')::date, 'YYYY-MM-DD'))
    into v_none
  from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e
  where (e->>'none')::boolean is true and e->>'topic_id' ~ '^\d+$';
  if v_none is not null then
    insert into ripples.att_state(k, v) values ('wiki.media.none', v_none)
    on conflict (k) do update set v = ripples.att_state.v || excluded.v, updated_at = now();
  end if;
  return jsonb_build_object('keys', v_ins, 'none', coalesce((select count(*) from jsonb_object_keys(v_none)), 0));
end $$;

-- Keys of att-wiki jobs (per-job settlement of merged backfill dispatches).
create or replace function ripples.att_wiki_jobs(p_ids bigint[])
returns table(id bigint, keys jsonb)
language sql stable security definer set search_path = '' as $$
  select j.id, coalesce(j.payload->'keys', '[]'::jsonb) from ripples.att_jobs j
  where j.id = any(p_ids) and j.fn = 'att-wiki'
$$;

-- Close queued wiki.pv backfill jobs whose keys no longer need a full-history fetch (already complete, mirrored from
-- public.signals, no data, or the topic is no longer active/panel). Saves dispatches; no outbound requests.
create or replace function ripples.att_wiki_jobs_sweep(p_as_of date default null)
returns int language plpgsql security definer set search_path = '' as $$
declare v_as date := coalesce(p_as_of, (now() at time zone 'utc')::date - 1); v_keys jsonb; v int;
begin
  select jsonb_agg(distinct jsonb_build_object('key', k->>'key', 'geo', coalesce(k->>'geo', 'en.wikipedia')))
    into v_keys
  from ripples.att_jobs j, jsonb_array_elements(coalesce(j.payload->'keys', '[]'::jsonb)) k
  where j.fn = 'att-wiki' and j.status = 'queued' and j.kind = 'backfill';
  if v_keys is null then return 0; end if;
  with p as (select * from ripples.att_wiki_pv_plan(v_as, 1000000, v_keys)),
  pend as (
    select distinct j.id from ripples.att_jobs j, jsonb_array_elements(coalesce(j.payload->'keys', '[]'::jsonb)) k
    join p on p.key = k->>'key' and p.geo = coalesce(k->>'geo', 'en.wikipedia')
    where j.fn = 'att-wiki' and j.status = 'queued' and j.kind = 'backfill' and p.kind = 'first'),
  up as (
    update ripples.att_jobs j set status = 'done', finished_at = now(), error = 'complete (att-wiki sweep: no full-history fetch needed)'
    where j.fn = 'att-wiki' and j.status = 'queued' and j.kind = 'backfill'
      and coalesce(j.payload->'params'->>'source', '') = 'wiki.pv' and j.id not in (select id from pend)
    returning 1)
  select count(*) into v from up;
  return v;
end $$;

-- Requests made today by an att-wiki mode (att_runs.requests), for per-mode soft caps inside the shared bucket.
create or replace function ripples.att_wiki_calls_today(p_mode text)
returns int language sql stable security definer set search_path = '' as $$
  select coalesce(sum(r.requests), 0)::int from ripples.att_runs r
  where r.fn = 'att-wiki' and r.mode = p_mode
    and r.started_at >= ((now() at time zone 'utc')::date)::timestamp at time zone 'utc'
$$;

-- Progress report for the owner / verifier (no requests).
create or replace function ripples.att_wiki_progress(p_as_of date default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with a as (select coalesce(p_as_of, (now() at time zone 'utc')::date - 1) as d),
  p as (select * from ripples.att_wiki_pv_plan((select d from a), 1000000,
          (select jsonb_agg(jsonb_build_object('key', r.key, 'geo', r.geo)) from ripples._att_wiki_reg() r)))
  select jsonb_build_object(
    'as_of', (select d from a),
    'registry_keys', (select count(*) from p where p.kind <> 'inactive'),
    'by_kind', (select jsonb_object_agg(kind, n) from (select kind, count(*) n from p group by kind) x),
    'active_first_pending', (select count(*) from p where p.kind = 'first' and p.act),
    'panel_first_pending', (select count(*) from p where p.kind = 'first' and not p.act),
    'with_400d_history', (select count(*) from p where p.first_day <= (select d from a) - 400),
    'wikimedia_budget', (select jsonb_agg(jsonb_build_object('day', b.day, 'used', b.used, 'cap', b.cap, 'killed', b.killed) order by b.day)
                         from ripples.att_budget b where b.bucket = 'wikimedia' and b.day >= (select d from a)),
    'topcc_series', (select count(*) from ripples.att_series s where s.source = 'wiki.topcc'),
    'media_keys', (select count(*) from ripples.att_keys k where k.source = 'wiki.media'))
$$;

-- 4. public wrappers (the ripples schema is not exposed to PostgREST); service_role only ------------------------------
create or replace function public.att_wiki_pv_plan(p_as_of date, p_limit int default 500, p_keys jsonb default null)
returns table(key text, geo text, topic_id bigint, series_id bigint, from_day date, kind text, prio int,
              last_day date, first_day date, act boolean)
language sql stable security definer set search_path = '' as $$
  select * from ripples.att_wiki_pv_plan(p_as_of, p_limit, p_keys) $$;
create or replace function public.att_wiki_mirror_signals(p_as_of date default null)
returns jsonb language sql security definer set search_path = '' as $$ select ripples.att_wiki_mirror_signals(p_as_of) $$;
create or replace function public.att_wiki_topcc_reach(p_day date, p_coverage int)
returns jsonb language sql security definer set search_path = '' as $$ select ripples.att_wiki_topcc_reach(p_day, p_coverage) $$;
create or replace function public.att_wiki_topcc_prev(p_day date, p_days int default 3)
returns table(cc text, day date, v jsonb)
language sql stable security definer set search_path = '' as $$ select * from ripples.att_wiki_topcc_prev(p_day, p_days) $$;
create or replace function public.att_wiki_media_plan(p_as_of date, p_limit int default 300)
returns table(kind text, topic_id bigint, project text, title text, key text, path text, series_id bigint,
              from_day date, last_day date)
language sql stable security definer set search_path = '' as $$ select * from ripples.att_wiki_media_plan(p_as_of, p_limit) $$;
create or replace function public.att_wiki_media_keys(p_rows jsonb)
returns jsonb language sql security definer set search_path = '' as $$ select ripples.att_wiki_media_keys(p_rows) $$;
create or replace function public.att_wiki_jobs(p_ids bigint[])
returns table(id bigint, keys jsonb)
language sql stable security definer set search_path = '' as $$ select * from ripples.att_wiki_jobs(p_ids) $$;
create or replace function public.att_wiki_jobs_sweep(p_as_of date default null)
returns int language sql security definer set search_path = '' as $$ select ripples.att_wiki_jobs_sweep(p_as_of) $$;
create or replace function public.att_wiki_calls_today(p_mode text)
returns int language sql stable security definer set search_path = '' as $$ select ripples.att_wiki_calls_today(p_mode) $$;

do $$
declare f text;
begin
  foreach f in array array[
    'ripples._att_wiki_reg()', 'ripples.att_wiki_pv_plan(date, int, jsonb)', 'ripples.att_wiki_mirror_signals(date)',
    'ripples.att_wiki_topcc_reach(date, int)', 'ripples.att_wiki_topcc_prev(date, int)',
    'ripples.att_wiki_media_plan(date, int)', 'ripples.att_wiki_media_keys(jsonb)', 'ripples.att_wiki_jobs(bigint[])',
    'ripples.att_wiki_jobs_sweep(date)', 'ripples.att_wiki_calls_today(text)', 'ripples.att_wiki_progress(date)',
    'public.att_wiki_pv_plan(date, int, jsonb)', 'public.att_wiki_mirror_signals(date)',
    'public.att_wiki_topcc_reach(date, int)', 'public.att_wiki_topcc_prev(date, int)',
    'public.att_wiki_media_plan(date, int)', 'public.att_wiki_media_keys(jsonb)', 'public.att_wiki_jobs(bigint[])',
    'public.att_wiki_jobs_sweep(date)', 'public.att_wiki_calls_today(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
