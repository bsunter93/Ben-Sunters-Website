-- Migration `att_social_support` (W7 att-social builder, 2026-09-25).
-- Support objects for edge function att-social (modes jetstream, mastodon, hn, stackex, backfill).
-- Everything is service_role only: RLS on, no policies, revoked from anon/authenticated/PUBLIC,
-- functions SECURITY DEFINER with search_path=''.
--
--  * ripples.att_social_acc   transient HyperLogLog sketches (registers only, never identifiers) per series bucket so
--                             distinct-author counts can be merged across 5-minute Jetstream runs. Kept <= 3 days.
--  * ripples.att_social_tags  transient daily hashtag counts (+ 64-register HLL) for bsky.jet discovery. Kept 8 days.
--  * ripples.att_social_accum(rows, state, tags)  ADDS counts to hourly/daily observations (att_ingest overwrites),
--                             merges sketches, and saves the Jetstream cursor in the same transaction (optimistic check
--                             against the cursor the run started from, so an overlapping run can never double count).
--  * ripples.att_social_tag_cands(source, day)  burst-z hashtag discovery candidates (§4 / §6.5).
--  * ripples.att_social_keys(source, limit)     watchlist + active flag + category + the topic's hashtag keys.
--  * ripples.att_social_bf_done(ids, keys, status, error)  per-key completion of merged backfill jobs.

create table if not exists ripples.att_social_acc (
  source     text not null,
  metric     text not null default 'n',
  geo        text not null default 'ALL',
  key        text not null,
  bucket     text not null,                 -- 'h:YYYY-MM-DDTHH' (UTC hour) | 'd:YYYY-MM-DD'
  reg        bytea not null,                -- HLL registers (p=8), no identifiers
  updated_at timestamptz not null default now(),
  primary key (source, metric, geo, key, bucket)
);
create table if not exists ripples.att_social_tags (
  day    date not null,
  source text not null,
  tag    text not null,
  n      bigint not null default 0,
  reg    bytea,                             -- HLL registers (p=6) of distinct authors, no identifiers
  primary key (day, source, tag)
);
alter table ripples.att_social_acc enable row level security;
alter table ripples.att_social_tags enable row level security;
revoke all on ripples.att_social_acc, ripples.att_social_tags from anon, authenticated, public;

-- ---------------------------------------------------------------- HLL helpers
create or replace function ripples._att_hll_merge(a bytea, b bytea) returns bytea
language plpgsql immutable security definer set search_path = '' as $$
declare r bytea; i int; n int; x int;
begin
  if a is null then return b; end if;
  if b is null then return a; end if;
  if length(a) <> length(b) then return b; end if;
  r := a; n := length(a);
  for i in 0 .. n - 1 loop
    x := get_byte(b, i);
    if x > get_byte(r, i) then r := set_byte(r, i, x); end if;
  end loop;
  return r;
end $$;

create or replace function ripples._att_hll_est(r bytea) returns double precision
language plpgsql immutable security definer set search_path = '' as $$
declare m int; s double precision := 0; z int := 0; i int; v int; e double precision; alpha double precision;
begin
  if r is null then return null; end if;
  m := length(r);
  if m = 0 then return null; end if;
  for i in 0 .. m - 1 loop
    v := get_byte(r, i);
    s := s + power(2::double precision, -v);
    if v = 0 then z := z + 1; end if;
  end loop;
  alpha := case m when 16 then 0.673 when 32 then 0.697 when 64 then 0.709 else 0.7213 / (1 + 1.079 / m) end;
  e := alpha * m * m / s;
  if e <= 2.5 * m and z > 0 then e := m * ln(m::double precision / z); end if;
  return round(e);
end $$;

drop aggregate if exists ripples._att_hll_union(bytea);
create aggregate ripples._att_hll_union(bytea) (sfunc = ripples._att_hll_merge, stype = bytea);

-- ---------------------------------------------------------------- accumulate (add) observations
create or replace function ripples.att_social_accum(p_rows jsonb, p_state jsonb default null, p_tags jsonb default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_rows jsonb; v_res jsonb; v_cur jsonb; v_bad int := 0; v_tags int := 0;
begin
  perform pg_advisory_xact_lock(hashtext('ripples.att_social_accum'));
  -- optimistic cursor check: the state must still hold the cursor this run started from
  if p_state is not null and p_state ? 'k' then
    select v into v_cur from ripples.att_state where k = p_state->>'k' for update;
    if p_state ? 'expect' and coalesce(v_cur->'cursor', 'null'::jsonb) is distinct from coalesce(p_state->'expect', 'null'::jsonb) then
      raise exception 'cursor_moved: expected %, found %', p_state->'expect', v_cur->'cursor';
    end if;
  end if;

  drop table if exists pg_temp._sa;
  create temp table _sa on commit drop as
  select e.r->>'source' as source,
         coalesce(nullif(e.r->>'metric', ''), 'n') as metric,
         coalesce(nullif(e.r->>'geo', ''), 'ALL') as geo,
         nullif(e.r->>'key', '') as key,
         case when e.r->>'day' ~ '^\d{4}-\d{2}-\d{2}$' then (e.r->>'day')::date end as day,
         case when e.r->>'ts' ~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}' then date_trunc('hour', (e.r->>'ts')::timestamptz) end as ts,
         case when e.r->>'add' ~ '^-?\d+(\.\d+)?$' then (e.r->>'add')::double precision end as addv,
         case when e.r->>'reg' ~ '^[0-9a-f]+$' and length(e.r->>'reg') between 32 and 2048 then decode(e.r->>'reg', 'hex') end as reg,
         case when e.r->>'topic_id' ~ '^\d+$' then (e.r->>'topic_id')::bigint end as topic_id,
         case when jsonb_typeof(e.r->'meta') = 'object' then e.r->'meta' end as meta
  from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e(r);

  select count(*) into v_bad from pg_temp._sa
   where source is null or key is null or addv is null or ((day is null) = (ts is null));

  drop table if exists pg_temp._sb;
  create temp table _sb on commit drop as
  select source, metric, geo, key, day, ts, sum(addv) as addv, ripples._att_hll_union(reg) as reg,
         max(topic_id) as topic_id, (array_agg(meta) filter (where meta is not null))[1] as meta,
         case when ts is not null then 'h:' || to_char(ts at time zone 'utc', 'YYYY-MM-DD"T"HH24')
              else 'd:' || day::text end as bucket
  from pg_temp._sa
  where source is not null and key is not null and addv is not null and ((day is null) <> (ts is null))
  group by source, metric, geo, key, day, ts;

  insert into ripples.att_social_acc(source, metric, geo, key, bucket, reg)
  select source, metric, geo, key, bucket, reg from pg_temp._sb where reg is not null
  on conflict (source, metric, geo, key, bucket) do update
    set reg = ripples._att_hll_merge(ripples.att_social_acc.reg, excluded.reg), updated_at = now();

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'source', b.source, 'metric', b.metric, 'geo', b.geo, 'key', b.key,
           'day', b.day, 'ts', b.ts,
           'value', coalesce(coalesce(h.value, d.value), 0) + b.addv,
           'aux', coalesce(ripples._att_hll_est(a.reg), coalesce(h.aux, d.aux)::double precision),
           'topic_id', b.topic_id, 'meta', b.meta))), '[]'::jsonb)
    into v_rows
  from pg_temp._sb b
  left join ripples.att_series s on s.source = b.source and s.metric = b.metric and s.geo = b.geo and s.key = b.key
  left join ripples.attention_obs_hourly h on b.ts is not null and h.series_id = s.series_id and h.ts = b.ts
  left join ripples.attention_obs d on b.day is not null and d.series_id = s.series_id and d.day = b.day
  left join ripples.att_social_acc a on a.source = b.source and a.metric = b.metric and a.geo = b.geo
        and a.key = b.key and a.bucket = b.bucket;

  v_res := ripples.att_ingest(v_rows);

  -- hashtag accumulation (discovery); rows [{day, tag, n, reg}]
  if p_tags is not null and jsonb_typeof(p_tags->'rows') = 'array' then
    with t as (
      select (x->>'day')::date as day, lower(left(x->>'tag', 64)) as tag, sum((x->>'n')::bigint) as n,
             ripples._att_hll_union(case when x->>'reg' ~ '^[0-9a-f]+$' and length(x->>'reg') between 32 and 512 then decode(x->>'reg', 'hex') end) as reg
      from jsonb_array_elements(p_tags->'rows') x
      where x->>'day' ~ '^\d{4}-\d{2}-\d{2}$' and coalesce(x->>'tag', '') <> '' and x->>'n' ~ '^\d+$'
      group by 1, 2),
    up as (
      insert into ripples.att_social_tags(day, source, tag, n, reg)
      select t.day, p_tags->>'source', t.tag, t.n, t.reg from t
      join ripples.att_sources s on s.source = p_tags->>'source' and s.enabled
      on conflict (day, source, tag) do update
        set n = ripples.att_social_tags.n + excluded.n,
            reg = ripples._att_hll_merge(ripples.att_social_tags.reg, excluded.reg)
      returning 1)
    select count(*) into v_tags from up;
  end if;

  if p_state is not null and p_state ? 'k' then
    perform ripples.att_state_set(p_state->>'k', p_state->'v');
  end if;

  delete from ripples.att_social_acc
   where (bucket like 'h:%' and updated_at < now() - interval '12 hours')
      or updated_at < now() - interval '3 days';
  delete from ripples.att_social_tags where day < (now() at time zone 'utc')::date - 8;

  drop table if exists pg_temp._sa;
  drop table if exists pg_temp._sb;
  return v_res || jsonb_build_object('bad_rows', v_bad, 'tags', v_tags);
end $$;

-- ---------------------------------------------------------------- hashtag burst candidates (§4 bsky.jet row, §6.5)
-- Burst z of today's (coverage-projected) count against the trailing 7 days (robust: median/MAD of ln(1+n), Poisson
-- floor), distinct authors >= p_min_distinct; evidence = clamp(z/8, 0, 1). Needs >= 3 baseline days with >= 50%
-- stream coverage; before that (warm-up) the top tags by distinct authors get rank evidence x 0.5 (meta.method=rank_warmup).
create or replace function ripples.att_social_tag_cands(p_source text, p_day date, p_limit int default 100,
                                                       p_min_distinct int default 50)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_cov double precision; v_base int; v_rows jsonb; v_res jsonb; v_method text;
begin
  select o.value into v_cov
  from ripples.att_series s join ripples.attention_obs o on o.series_id = s.series_id
  where s.source = p_source and s.metric = 's' and s.geo = 'ALL' and s.key = '__coverage__' and o.day = p_day;
  if coalesce(v_cov, 0) < 3600 then
    return jsonb_build_object('rows', 0, 'reason', 'coverage_below_1h', 'coverage_s', coalesce(v_cov, 0));
  end if;
  select count(*) into v_base
  from ripples.att_series s join ripples.attention_obs o on o.series_id = s.series_id
  where s.source = p_source and s.metric = 's' and s.key = '__coverage__'
    and o.day between p_day - 7 and p_day - 1 and o.value >= 43200;

  if v_base >= 3 then
    v_method := 'burst_z';
    with today as (
      select t.tag, t.n, t.n * 86400.0 / v_cov as n_proj, ripples._att_hll_est(t.reg) as dist
      from ripples.att_social_tags t
      where t.day = p_day and t.source = p_source
      order by t.n desc limit 3000),
    okdays as (
      select o.day from ripples.att_series s join ripples.attention_obs o on o.series_id = s.series_id
      where s.source = p_source and s.metric = 's' and s.key = '__coverage__'
        and o.day between p_day - 7 and p_day - 1 and o.value >= 43200),
    base as (
      select td.tag, od.day, coalesce(b.n, 0) * 86400.0 / greatest(c.value, 1) as n
      from today td cross join okdays od
      join ripples.att_series cs on cs.source = p_source and cs.metric = 's' and cs.key = '__coverage__'
      join ripples.attention_obs c on c.series_id = cs.series_id and c.day = od.day
      left join ripples.att_social_tags b on b.source = p_source and b.day = od.day and b.tag = td.tag),
    stats as (
      select tag, percentile_cont(0.5) within group (order by ln(1 + n)) as m,
             percentile_cont(0.5) within group (order by n) as lam
      from base group by tag),
    mad as (
      select b.tag, percentile_cont(0.5) within group (order by abs(ln(1 + b.n) - s.m)) as mad
      from base b join stats s using (tag) group by b.tag),
    z as (
      select td.tag, td.n, td.dist, (ln(1 + td.n_proj) - s.m)
               / greatest(1.4826 * md.mad, 1 / sqrt(s.lam + 1), 0.02) as z
      from today td join stats s using (tag) join mad md using (tag)
      where td.dist >= p_min_distinct),
    top as (select *, row_number() over (order by z desc) as rk from z where z >= 3 order by z desc limit p_limit)
    select coalesce(jsonb_agg(jsonb_build_object(
             'day', p_day, 'source', p_source, 'geo', 'ALL', 'label', '#' || tag, 'rank', rk, 'value', n,
             'evidence', least(1, greatest(0, z / 8)),
             'meta', jsonb_build_object('method', 'burst_z', 'k', round(z::numeric, 2), 'n_posts', n,
                                        'coverage', round((v_cov / 86400)::numeric, 3)))), '[]'::jsonb)
      into v_rows from top;
  else
    v_method := 'rank_warmup';
    with today as (
      select t.tag, t.n, ripples._att_hll_est(t.reg) as dist
      from ripples.att_social_tags t where t.day = p_day and t.source = p_source
      order by t.n desc limit 3000),
    top as (select *, row_number() over (order by dist desc, n desc) as rk from today
            where dist >= p_min_distinct order by dist desc, n desc limit p_limit)
    select coalesce(jsonb_agg(jsonb_build_object(
             'day', p_day, 'source', p_source, 'geo', 'ALL', 'label', '#' || tag, 'rank', rk, 'value', n,
             'evidence', 0.5 * (1 - ln(rk) / ln(p_limit + 1)),
             'meta', jsonb_build_object('method', 'rank_warmup', 'rank', rk, 'n_posts', n,
                                        'coverage', round((v_cov / 86400)::numeric, 3)))), '[]'::jsonb)
      into v_rows from top;
  end if;
  v_res := ripples.att_ingest_candidates(v_rows);
  return v_res || jsonb_build_object('method', v_method, 'baseline_days', v_base, 'coverage_s', v_cov);
end $$;

-- ---------------------------------------------------------------- watchlist with activity, category and hashtags
create or replace function ripples.att_social_keys(p_source text, p_limit int default 5000)
returns table(key text, geo text, metric text, match jsonb, series_id bigint, topic_id bigint, key_type text,
              active boolean, category text, tags text[])
language sql stable security definer set search_path = '' as $$
  with k as (
    select k.key, k.geo, k.metric, k.match, k.series_id, k.topic_id, k.key_type, t.status, t.category, t.last_active
    from ripples.att_keys k join ripples.att_topics t on t.topic_id = k.topic_id
    where k.source = p_source and k.enabled and (t.status = 'active' or t.in_panel)),
  g as (
    select k.key, k.geo, k.metric,
           (array_agg(k.match order by (k.status = 'active') desc, k.topic_id))[1] as match,
           (array_agg(k.series_id order by (k.status = 'active') desc, k.topic_id))[1] as series_id,
           (array_agg(k.topic_id order by (k.status = 'active') desc, k.topic_id))[1] as topic_id,
           (array_agg(k.key_type order by (k.status = 'active') desc, k.topic_id))[1] as key_type,
           bool_or(k.status = 'active') as active,
           (array_agg(k.category order by (k.status = 'active') desc, k.topic_id))[1] as category,
           array_agg(distinct k.topic_id) as topics,
           max(k.last_active) as last_active
    from k group by k.key, k.geo, k.metric)
  select g.key, g.geo, g.metric, g.match, g.series_id, g.topic_id, g.key_type, g.active, g.category,
         coalesce((select array_agg(distinct m.key) from ripples.att_keys m
                   where m.source = 'masto.tags' and m.enabled and m.topic_id = any(g.topics)), '{}') as tags
  from g
  order by g.active desc, g.last_active desc nulls last, g.topic_id, g.key
  limit greatest(p_limit, 0)
$$;

-- ---------------------------------------------------------------- per-key completion of merged backfill jobs
create or replace function ripples.att_social_bf_done(p_ids bigint[], p_keys text[], p_status text, p_error text default null)
returns int
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  if p_status not in ('done', 'skipped', 'failed') then raise exception 'att_social_bf_done: bad status %', p_status; end if;
  update ripples.att_jobs j set status = p_status, finished_at = now(), error = left(p_error, 2000)
   where j.id = any(p_ids) and j.status in ('running', 'queued')
     and exists (select 1 from jsonb_array_elements(coalesce(j.payload->'keys', '[]'::jsonb)) e where e->>'key' = any(p_keys));
  get diagnostics v = row_count;
  return v;
end $$;

-- ---------------------------------------------------------------- public wrappers (edge functions use PostgREST public)
create or replace function public.att_social_accum(p_rows jsonb, p_state jsonb default null, p_tags jsonb default null)
returns jsonb language sql security definer set search_path = '' as
$$ select ripples.att_social_accum(p_rows, p_state, p_tags) $$;
create or replace function public.att_social_tag_cands(p_source text, p_day date, p_limit int default 100,
                                                      p_min_distinct int default 50)
returns jsonb language sql security definer set search_path = '' as
$$ select ripples.att_social_tag_cands(p_source, p_day, p_limit, p_min_distinct) $$;
create or replace function public.att_social_keys(p_source text, p_limit int default 5000)
returns table(key text, geo text, metric text, match jsonb, series_id bigint, topic_id bigint, key_type text,
              active boolean, category text, tags text[])
language sql security definer set search_path = '' as
$$ select * from ripples.att_social_keys(p_source, p_limit) $$;
create or replace function public.att_social_bf_done(p_ids bigint[], p_keys text[], p_status text, p_error text default null)
returns int language sql security definer set search_path = '' as
$$ select ripples.att_social_bf_done(p_ids, p_keys, p_status, p_error) $$;

do $$ declare f text; begin
  foreach f in array array[
    'ripples._att_hll_merge(bytea,bytea)', 'ripples._att_hll_est(bytea)',
    'ripples.att_social_accum(jsonb,jsonb,jsonb)', 'ripples.att_social_tag_cands(text,date,int,int)',
    'ripples.att_social_keys(text,int)', 'ripples.att_social_bf_done(bigint[],text[],text,text)',
    'public.att_social_accum(jsonb,jsonb,jsonb)', 'public.att_social_tag_cands(text,date,int,int)',
    'public.att_social_keys(text,int)', 'public.att_social_bf_done(bigint[],text[],text,text)']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
revoke all on function ripples._att_hll_union(bytea) from public, anon, authenticated;
grant execute on function ripples._att_hll_union(bytea) to service_role;

-- ---------------------------------------------------------------- config + source rows (att_* only)
-- Stack Exchange relevance by topic category (unkeyed 300/day quota; our cap 150/day). '*' = default for unmapped
-- categories. With an SE app key the owner can widen this (e.g. '*': ['stackoverflow']).
insert into ripples.att_config(key, value) values
  ('se.sites_by_category', '{"tech":["stackoverflow"],"business":["money","stackoverflow"],"places":["travel"],
     "events":["travel"],"science_health":["gardening","cooking"],"food":["cooking"],"*":[]}'::jsonb),
  ('social', '{"jet_host":"jetstream2.us-east.bsky.network","jet_hosts":["jetstream2.us-east.bsky.network","jetstream1.us-east.bsky.network"],
     "jet_max_stream_min":10,"jet_proc_ms":1100,"jet_start_back_min":10,
     "masto_instances":["mastodon.social","mstdn.jp"],"masto_split":{"mastodon.social":32,"mstdn.jp":16},
     "hn_days":3,"hn_max_calls_per_term":150,"se_daily_cap":60,"se_min_quota":20}'::jsonb)
on conflict (key) do nothing;

-- the non-English Mastodon instance (DEMARCATION §3: mstdn.jp official API, G)
update ripples.att_sources set hosts = array(select distinct unnest(hosts || array['mstdn.jp']))
 where source in ('masto.tags', 'masto.trends') and not ('mstdn.jp' = any(hosts));
