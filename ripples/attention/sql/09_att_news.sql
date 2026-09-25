-- 09_att_news.sql — att-news collector support (W7, component att-news). Migration name: att_news_collector.
-- Sources: gdelt.gkg (GDELT GKG 2.1 raw 15-min files), ia.thirdeye (IA TV News Archive Third Eye chyrons),
-- news.sitemap (BBC, NYT, Guardian, Fox news sitemaps). Counts only: no headlines, chyron text or article text is stored.
--
-- Why extra SQL beyond att_ingest: att_ingest overwrites (series, day|hour). GKG publishes 96 files a day and Third Eye
-- is read hour by hour, so daily (and GKG hourly) values are sums over parts. att_news_accum adds each part exactly once
-- (idempotent per batch id) and keeps the distinct member sets (source countries, TV channels) so aux is an exact union
-- count, then writes the totals through ripples.att_ingest (all its checks apply). Sitemaps are 48 h rolling windows, so
-- their per-outlet cells are merged with greatest() and summed across outlets (att_news_sitemap_merge).

-- ---------- budgets for the three sources (DEMARCATION Q6: no published limits -> daily cadence floor 5 s per host) ----
update ripples.att_sources set per_run_cap = 2, per_day_cap = 200,
  reason = 'Q6: GDELT raw files, no published limit; 1 lastupdate.txt + 1 GKG zip per run, 96 runs/day, 5 s spacing'
 where source = 'gdelt.gkg';
update ripples.att_sources set per_run_cap = 2, per_day_cap = 48,
  reason = 'Q6: no published limit; 1 Third Eye request per hourly run (+1 redirect hop allowed), 5 s spacing'
 where source = 'ia.thirdeye';
update ripples.att_sources set per_run_cap = 8, per_day_cap = 32,
  reason = 'AP skipped (Cloudflare); Q6: no published limit -> 1 req/5 s per host; 4 outlets x 4 runs/day (+redirect hops)'
 where source = 'news.sitemap';

-- ---------- term keys for news.sitemap (same terms as gdelt.gkg / ia.thirdeye) ----------
insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match)
select k.topic_id, 'news.sitemap', k.metric, k.geo, k.key, k.key_type, k.match
from ripples.att_keys k where k.source = 'gdelt.gkg' and k.key_type = 'term'
on conflict do nothing;

create or replace function ripples._att_news_key_copy() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.source = 'gdelt.gkg' and new.key_type = 'term' then
    insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match, enabled)
    values (new.topic_id, 'news.sitemap', new.metric, new.geo, new.key, new.key_type, new.match, new.enabled)
    on conflict (topic_id, source, metric, geo, key) do update set match = excluded.match, enabled = excluded.enabled;
  end if;
  return new;
end $$;
drop trigger if exists att_news_key_copy on ripples.att_keys;
create trigger att_news_key_copy after insert or update of match, enabled on ripples.att_keys
  for each row when (new.source = 'gdelt.gkg') execute function ripples._att_news_key_copy();

-- ---------- accumulation state (small; 3-day retention) ----------
create table if not exists ripples.att_news_acc (
  source     text not null,
  metric     text not null,
  geo        text not null,
  key        text not null,
  grain      text not null check (grain in ('day','hour')),
  period     timestamptz not null,
  value      double precision not null default 0,
  members    text[],                 -- distinct source countries (GKG) or channels (Third Eye); aux = cardinality
  parts      int not null default 1, -- files / hours added (coverage)
  topic_id   bigint,
  updated_at timestamptz not null default now(),
  primary key (source, metric, geo, key, grain, period)
);
create table if not exists ripples.att_news_batches (
  batch text primary key,
  at    timestamptz not null default now()
);
create table if not exists ripples.att_news_cells (
  day      date not null,
  outlet   text not null,
  key      text not null,
  n        int not null,
  topic_id bigint,
  primary key (day, outlet, key)
);
do $$ declare t text; begin
  foreach t in array array['att_news_acc','att_news_batches','att_news_cells'] loop
    execute format('alter table ripples.%I enable row level security', t);
    execute format('revoke all on ripples.%I from public, anon, authenticated', t);
    execute format('grant all on ripples.%I to service_role', t);
  end loop;
end $$;

-- ---------- terms with their active flag (att_watchlist + status) ----------
create or replace function ripples.att_news_terms(p_source text, p_limit int default 5000)
returns table(key text, match jsonb, topic_id bigint, active boolean, key_type text)
language sql stable security definer set search_path = '' as $$
  select w.key, w.match, w.topic_id, w.act, w.key_type from (
    select distinct on (k.key) k.key, k.match, k.topic_id, (t.status = 'active') act, k.key_type, t.last_active
    from ripples.att_keys k join ripples.att_topics t on t.topic_id = k.topic_id
    where k.source = p_source and k.enabled and k.metric = 'n' and k.geo = 'ALL'
      and (t.status = 'active' or t.in_panel)
    order by k.key, (t.status = 'active') desc, k.topic_id) w
  order by w.act desc, w.last_active desc nulls last, w.topic_id
  limit greatest(p_limit, 0)
$$;

-- ---------- additive accumulation (GKG files, Third Eye hours) ----------
-- p_rows: [{source,key,metric?='n',geo?='ALL',day|ts,value,members?:[text],topic_id?,meta?}], unique per batch.
-- Adds each row to att_news_acc once per p_batch (a repeated batch id is a no-op), then upserts the running totals
-- through ripples.att_ingest (aux = number of distinct members; meta.coverage = parts added so far).
create or replace function ripples.att_news_accum(p_run jsonb, p_batch text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rows jsonb; v_n int; r jsonb;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('rows', 0, 'series_new', 0, 'rejected', jsonb_build_array(jsonb_build_object('i', -1, 'reason', 'p_rows must be an array')));
  end if;
  if p_batch is not null then
    insert into ripples.att_news_batches(batch) values (p_batch) on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n = 0 then
      return jsonb_build_object('dup', true, 'rows', 0, 'series_new', 0, 'rejected', '[]'::jsonb);
    end if;
  end if;

  with x as (
    select distinct on (source, metric, geo, key, grain, period) *
    from (
      select e.r->>'source' source, coalesce(nullif(e.r->>'metric', ''), 'n') metric,
             coalesce(nullif(e.r->>'geo', ''), 'ALL') geo, e.r->>'key' key,
             case when e.r ? 'ts' then 'hour' else 'day' end as grain,
             case when e.r ? 'ts' then date_trunc('hour', (e.r->>'ts')::timestamptz)
                  else ((e.r->>'day')::date)::timestamp at time zone 'UTC' end as period,
             coalesce((e.r->>'value')::double precision, 0) as value,
             case when jsonb_typeof(e.r->'members') = 'array'
                  then array(select distinct m from jsonb_array_elements_text(e.r->'members') m order by m) end as members,
             case when e.r->>'topic_id' ~ '^\d+$' then (e.r->>'topic_id')::bigint end as topic_id,
             e.ord
      from jsonb_array_elements(p_rows) with ordinality e(r, ord)
      where e.r->>'key' is not null and e.r->>'source' is not null
        and ((e.r ? 'ts') <> (e.r ? 'day'))) z
    order by source, metric, geo, key, grain, period, ord desc),
  up as (
    insert into ripples.att_news_acc as t (source, metric, geo, key, grain, period, value, members, parts, topic_id)
    select source, metric, geo, key, grain, period, value, members, 1, topic_id from x
    on conflict (source, metric, geo, key, grain, period) do update
      set value = t.value + excluded.value,
          members = case when excluded.members is null then t.members
                         else (select array_agg(distinct m order by m) from unnest(coalesce(t.members, '{}') || excluded.members) m) end,
          parts = t.parts + 1,
          topic_id = coalesce(t.topic_id, excluded.topic_id),
          updated_at = now()
    returning t.*)
  select coalesce(jsonb_agg(
           jsonb_build_object('source', up.source, 'metric', up.metric, 'geo', up.geo, 'key', up.key, 'value', up.value,
                              'aux', case when up.members is not null then cardinality(up.members) end,
                              'topic_id', up.topic_id,
                              'meta', jsonb_build_object('coverage', up.parts, 'unit',
                                        case when up.source = 'ia.thirdeye' then 'chyron_min' else 'docs' end))
           || case when up.grain = 'hour'
                   then jsonb_build_object('ts', to_char(up.period at time zone 'UTC', 'YYYY-MM-DD"T"HH24:00:00"Z"'))
                   else jsonb_build_object('day', to_char(up.period at time zone 'UTC', 'YYYY-MM-DD')) end), '[]'::jsonb)
    into v_rows from up;

  r := ripples.att_ingest(coalesce(p_run, '{}'::jsonb), v_rows);

  delete from ripples.att_news_acc where period < now() - interval '3 days';
  delete from ripples.att_news_batches where at < now() - interval '8 days';
  return r || jsonb_build_object('accumulated', jsonb_array_length(v_rows));
end $$;

-- ---------- sitemaps: per-outlet cells merged with greatest(), summed across outlets ----------
-- p_rows: [{outlet?, key, day, n, topic_id?}]. A row with outlet null only asks for the (key, day) total to be written
-- (zero fill). key '__total__' rows also produce per-outlet __total__ series (geo = outlet).
create or replace function ripples.att_news_sitemap_merge(p_run jsonb, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rows jsonb; r jsonb;
begin
  drop table if exists pg_temp._nsm;
  create temp table _nsm on commit drop as
  select e.r->>'outlet' as outlet, e.r->>'key' as key, (e.r->>'day')::date as day,
         coalesce((e.r->>'n')::int, 0) as n,
         case when e.r->>'topic_id' ~ '^\d+$' then (e.r->>'topic_id')::bigint end as topic_id
  from jsonb_array_elements(p_rows) e(r)
  where e.r->>'key' is not null and e.r->>'day' ~ '^\d{4}-\d{2}-\d{2}$';

  insert into ripples.att_news_cells as c (day, outlet, key, n, topic_id)
  select distinct on (day, outlet, key) day, outlet, key, n, topic_id from pg_temp._nsm
   where outlet is not null and n > 0
   order by day, outlet, key, n desc
  on conflict (day, outlet, key) do update set n = greatest(c.n, excluded.n),
                                               topic_id = coalesce(c.topic_id, excluded.topic_id);

  with want as (select key, day, max(topic_id) topic_id from pg_temp._nsm group by key, day),
  tot as (
    select w.key, w.day, w.topic_id, coalesce(sum(c.n), 0) v, count(c.n) filter (where c.n > 0) outlets,
           (select count(distinct c2.outlet) from ripples.att_news_cells c2 where c2.day = w.day and c2.key = '__total__') cov
    from want w left join ripples.att_news_cells c on c.day = w.day and c.key = w.key
    group by w.key, w.day, w.topic_id),
  per_outlet as (
    select c.key, c.day, c.outlet, c.n from ripples.att_news_cells c
    join (select distinct n2.day from pg_temp._nsm n2) d on d.day = c.day
    where c.key = '__total__')
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_rows from (
    select jsonb_build_object('source', 'news.sitemap', 'key', key, 'geo', 'ALL', 'metric', 'n',
                              'day', to_char(day, 'YYYY-MM-DD'), 'value', v, 'aux', outlets, 'topic_id', topic_id,
                              'meta', jsonb_build_object('unit', 'headlines', 'coverage', cov)) x from tot
    union all
    select jsonb_build_object('source', 'news.sitemap', 'key', '__total__', 'geo', outlet, 'metric', 'n',
                              'day', to_char(day, 'YYYY-MM-DD'), 'value', n,
                              'meta', jsonb_build_object('unit', 'headlines')) from per_outlet) q;

  r := ripples.att_ingest(coalesce(p_run, '{}'::jsonb), v_rows);
  delete from ripples.att_news_cells where day < (now() at time zone 'utc')::date - 4;
  drop table if exists pg_temp._nsm;
  return r;
end $$;

-- ---------- co-mention edges, additive per batch (GKG files, Third Eye hours) ----------
-- p_rows: [{source, from_key, to_key, day, n, from_topic?, to_topic?, to_total?, geo?}]
-- n and meta.total (documents mentioning to_key) accumulate; pmi = ln(n * N / (n_from * n_to)) from the running daily
-- totals in att_news_acc (N = the source's __total__).
create or replace function ripples.att_news_edges_accum(p_batch text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_n int; v int;
begin
  if p_batch is not null then
    insert into ripples.att_news_batches(batch) values (p_batch) on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n = 0 then return jsonb_build_object('dup', true, 'rows', 0); end if;
  end if;
  with e as (
    select distinct on (x.source, coalesce(x.geo, 'ALL'), x.from_key, x.to_key, x.day) x.*
    from jsonb_to_recordset(p_rows) as x(source text, geo text, from_key text, to_key text, day date, n double precision,
                                         from_topic bigint, to_topic bigint, to_total double precision)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.from_key is not null and x.to_key is not null and x.day is not null and x.n > 0
      and length(x.to_key) <= 120
      and not ripples._att_ident_like(x.from_key, x.source, true) and not ripples._att_ident_like(x.to_key, x.source, true)),
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
end $$;

-- ---------- discovery candidates: keep the strongest evidence of the day ----------
create or replace function ripples.att_news_candidates_merge(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  with c as (
    select distinct on (x.day, x.source, coalesce(x.geo, 'ALL'), x.label) x.*
    from jsonb_to_recordset(p_rows) as x(day date, source text, geo text, label text, rank int, value double precision,
                                          evidence real, qid text, topic_id bigint, meta jsonb)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.day is not null and x.label is not null and x.evidence between 0 and 1 and length(x.label) <= 200
      and not ripples._att_ident_like(x.label, x.source, true)
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
end $$;

-- ---------- public wrappers (PostgREST exposes public only; service_role only) ----------
create or replace function public.att_news_terms(p_source text, p_limit int default 5000)
returns table(key text, match jsonb, topic_id bigint, active boolean, key_type text)
language sql stable security definer set search_path = '' as $$ select * from ripples.att_news_terms(p_source, p_limit) $$;
create or replace function public.att_news_accum(p_run jsonb, p_batch text, p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_news_accum(p_run, p_batch, p_rows) $$;
create or replace function public.att_news_sitemap_merge(p_run jsonb, p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_news_sitemap_merge(p_run, p_rows) $$;
create or replace function public.att_news_edges_accum(p_batch text, p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_news_edges_accum(p_batch, p_rows) $$;
create or replace function public.att_news_candidates_merge(p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_news_candidates_merge(p_rows) $$;

-- ---------- grants (every att function: service_role only) ----------
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where (n.nspname = 'ripples' and (p.proname like 'att\_news%' or p.proname like '\_att\_news%'))
              or (n.nspname = 'public' and p.proname like 'att\_news%')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
