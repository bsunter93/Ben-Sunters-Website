-- =====================================================================================================================
-- 28_att_wiki_hist.sql — cold-storage pre-history for wiki.pv (Ripple Map read side; ATTENTION_STACK §3.4 companion)
--
-- Problem: attention_obs stores every wiki.pv day at ~115 bytes/row; giving all 996 wiki.pv series >= 3 years of daily
-- history there would add ~100 MB and blow the self-imposed 400 MB DB cap (free-tier hard limit 500 MB; attention_obs
-- alone is already 202 MB of ~340-350 MB used). Wikimedia's per-article AQS endpoint returns an entire date range in
-- ONE call, so old history (everything strictly before a series' current earliest attention_obs day) is fetched once
-- and folded into a single small array row per series (~4.4 KB for 3 y as int4[]) instead of ~1,100 attention_obs rows
-- (~126 KB) per series. 996 series x ~4.4 KB =~ 4.4 MB total: far under the cap.
--
-- What this file owns:
--   * ripples.att_hist_arr        — one row per series: compact int4[] of daily views starting at start_day (nulls for
--                                    missing days so 0 vs "not fetched" stay distinguishable), RLS on, no policies
--                                    (service role only; anon/authenticated/public revoked, matching every other
--                                    ripples.att_* table in this stack).
--   * ripples.att_hist_wiki_plan   — series lacking pre-history back to the 3y+30d target, oldest-covered first, capped
--                                    at p_limit; only series that already have at least one attention_obs row (a series
--                                    with none yet is still being onboarded by att-wiki itself; picked up once it has one).
--   * ripples.att_hist_wiki_upsert — batched writer (db_cap_mb guard, same -10 MB margin as att_ingest) for the array
--                                    rows the backfill edge function fetches.
--   * ripples.att_hist_wiki_progress / att_hist_wiki_autostop — coverage counters and the cron self-unschedule.
--   * ripples.att_series_daily / att_series_daily_many — the READ interface for the Ripple Map engine: attention_obs
--                                    wins on any day it has, else the cold array is unnested; STABLE, security definer,
--                                    service-role only (matches every other att_* RPC's grant pattern).
--
-- Does NOT touch: att_ingest, att_tick, att_finalize/calibrate/freeze or any function defined in 20-25_att_engine_*.sql
-- (another agent owns those). This file only adds new objects; it revokes nothing and alters no existing table.
-- Applied as migration att_wiki_hist_cold_storage.
-- =====================================================================================================================

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Cold storage table
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists ripples.att_hist_arr (
  series_id  bigint primary key references ripples.att_series(series_id) on delete cascade,
  start_day  date not null,
  vals       int4[] not null,                          -- vals[1] = start_day; null element = day not returned by AQS
  end_day    date generated always as (start_day + (coalesce(array_length(vals, 1), 1) - 1)) stored,
  fetched_at timestamptz not null default now(),
  meta       jsonb
);
create index if not exists att_hist_arr_end_idx on ripples.att_hist_arr (end_day);
alter table ripples.att_hist_arr enable row level security;
revoke all on table ripples.att_hist_arr from public, anon, authenticated;

comment on table ripples.att_hist_arr is
  'Cold pre-history for wiki.pv (and any future daily-count source): one row per series, one array covering '
  '[start_day, end_day]. Always strictly before that series'' earliest ripples.attention_obs.day — att_series_daily '
  'lets attention_obs win on any overlap, so this table is never the source of truth for a day attention_obs also has.';

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Planner: which wiki.pv series still need pre-history, oldest target first
-- ---------------------------------------------------------------------------------------------------------------------
-- p_target_start: the oldest day we want covered (today - 3y - 30d, computed by the caller so a test run can pin it).
-- Returns one row per series still short of that, with the exact [from_day, to_day] this run should fetch in ONE call:
--   to_day   = (series' earliest attention_obs day) - 1   -- never overlaps what attention_obs already holds
--   from_day = greatest(p_target_start, att_sources.history_from)  -- never asks AQS for pre-2015-07-01 data
-- A series already covered back to p_target_start (or with nothing left to fetch, to_day < from_day) is not returned.
create or replace function ripples.att_hist_wiki_plan(p_target_start date, p_limit int default 60)
returns table(series_id bigint, geo text, key text, topic_id bigint, from_day date, to_day date)
language sql stable security definer set search_path = '' as $$
  with earliest as (
    select o.series_id, min(o.day) as min_day
    from ripples.attention_obs o
    join ripples.att_series s on s.series_id = o.series_id
    where s.source = 'wiki.pv'
    group by o.series_id
  ),
  bound as (
    select coalesce((select history_from from ripples.att_sources where source = 'wiki.pv'), date '2015-07-01') as hist_from
  )
  select s.series_id, s.geo, s.key, s.topic_id,
         greatest(p_target_start, (select hist_from from bound))                as from_day,
         (e.min_day - 1)                                                        as to_day
  from ripples.att_series s
  join earliest e on e.series_id = s.series_id
  left join ripples.att_hist_arr h on h.series_id = s.series_id
  where s.source = 'wiki.pv'
    and (h.series_id is null or h.start_day > greatest(p_target_start, (select hist_from from bound)))
    and (e.min_day - 1) >= greatest(p_target_start, (select hist_from from bound))
  order by e.min_day asc, s.series_id asc     -- series with the least history (newest onboarded) first: they need the most days
  limit greatest(p_limit, 0)
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Writer: one array row per series, same db_cap_mb - 10 MB guard as att_ingest
-- ---------------------------------------------------------------------------------------------------------------------
-- p_rows: [{"series_id":..,"start_day":"YYYY-MM-DD","vals":[int|null,...],"meta":{...}}, ...]
create or replace function ripples.att_hist_wiki_upsert(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_cap numeric; v_n int := 0;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object('rows', 0);
  end if;
  v_cap := coalesce((ripples._att_cfg('db_cap_mb'))::text::numeric, 400);
  if pg_database_size(current_database()) > (v_cap - 10) * 1048576 then
    return jsonb_build_object('rows', 0, 'rejected', 'db_size_cap');
  end if;

  with in_rows as (
    select (e.r->>'series_id')::bigint                                          as series_id,
           (e.r->>'start_day')::date                                           as start_day,
           (select array_agg(nullif(x.val::text, 'null')::int order by x.ord)
              from jsonb_array_elements(e.r->'vals') with ordinality as x(val, ord))  as vals,
           coalesce(e.r->'meta', '{}'::jsonb)                                   as meta
    from jsonb_array_elements(p_rows) e(r)
    where e.r->>'series_id' is not null and e.r->>'start_day' is not null and jsonb_typeof(e.r->'vals') = 'array'
  ),
  ins as (
    insert into ripples.att_hist_arr as h (series_id, start_day, vals, fetched_at, meta)
    select series_id, start_day, vals, now(), meta from in_rows
    on conflict (series_id) do update
      set start_day = excluded.start_day, vals = excluded.vals, fetched_at = now(), meta = excluded.meta
      -- never let a hist write clobber a wider range already stored with a newer/narrower one by mistake
      where excluded.start_day <= h.start_day or h.start_day is null
    returning 1
  )
  select count(*) into v_n from ins;
  return jsonb_build_object('rows', v_n);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Coverage / autostop
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_hist_wiki_progress(p_target_start date default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  with tgt as (select coalesce(p_target_start, (current_date - interval '3 years' - interval '30 days')::date) as d),
  earliest as (
    select o.series_id, min(o.day) as min_day
    from ripples.attention_obs o join ripples.att_series s on s.series_id = o.series_id
    where s.source = 'wiki.pv' group by o.series_id
  ),
  cov as (
    select e.series_id,
           (h.series_id is not null and h.start_day <= (select d from tgt)) as covered
    from earliest e left join ripples.att_hist_arr h on h.series_id = e.series_id
  )
  select jsonb_build_object(
    'target_start', (select d from tgt),
    'wiki_pv_series', (select count(*) from ripples.att_series where source = 'wiki.pv'),
    'series_with_obs', (select count(*) from earliest),
    'series_with_hist_row', (select count(*) from ripples.att_hist_arr h join ripples.att_series s on s.series_id = h.series_id where s.source = 'wiki.pv'),
    'covered_to_target', (select count(*) filter (where covered) from cov),
    'remaining', (select count(*) filter (where not covered) from cov)
  )
$$;

-- Called by the edge function after each run: unschedules att-wiki-hist once every wiki.pv series with observations is
-- covered back to the target (no-op, never errors, if the job is already gone or was never scheduled).
create or replace function ripples.att_hist_wiki_autostop() returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_remaining int;
begin
  select (ripples.att_hist_wiki_progress()->>'remaining')::int into v_remaining;
  if coalesce(v_remaining, 1) = 0 then
    perform cron.unschedule('att-wiki-hist') where exists (select 1 from cron.job where jobname = 'att-wiki-hist');
    return true;
  end if;
  return false;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Read interface for the Ripple Map engine — attention_obs wins on overlap, else the cold array
-- ---------------------------------------------------------------------------------------------------------------------
-- attention_obs wins on any day it also has (by construction att_hist_arr never covers a day attention_obs already
-- has, but DISTINCT ON makes that a guarantee of this function, not just of the planner): prio 0 (attention_obs)
-- sorts first per day, so it wins the DISTINCT ON tie-break.
create or replace function ripples.att_series_daily(p_series_id bigint, p_from date, p_to date)
returns table(day date, value double precision)
language sql stable security definer set search_path = '' as $$
  select distinct on (d.day) d.day, d.value
  from (
    select o.day, o.value, 0 as prio
    from ripples.attention_obs o
    where o.series_id = p_series_id and o.day between p_from and p_to
    union all
    select (h.start_day + (u.ord - 1)::int)::date as day, u.v::double precision as value, 1 as prio
    from ripples.att_hist_arr h
    cross join lateral unnest(h.vals) with ordinality as u(v, ord)
    where h.series_id = p_series_id
      and (h.start_day + (u.ord - 1)::int) between p_from and p_to
      and u.v is not null
  ) d
  order by d.day, d.prio
$$;

-- Bulk variant: many series in one call (the engine's normal access pattern — one query per chart, not per series).
create or replace function ripples.att_series_daily_many(p_series_ids bigint[], p_from date, p_to date)
returns table(series_id bigint, day date, value double precision)
language sql stable security definer set search_path = '' as $$
  select distinct on (d.series_id, d.day) d.series_id, d.day, d.value
  from (
    select o.series_id, o.day, o.value, 0 as prio
    from ripples.attention_obs o
    where o.series_id = any(p_series_ids) and o.day between p_from and p_to
    union all
    select h.series_id, (h.start_day + (u.ord - 1)::int)::date as day, u.v::double precision as value, 1 as prio
    from ripples.att_hist_arr h
    cross join lateral unnest(h.vals) with ordinality as u(v, ord)
    where h.series_id = any(p_series_ids)
      and (h.start_day + (u.ord - 1)::int) between p_from and p_to
      and u.v is not null
  ) d
  order by d.series_id, d.day, d.prio
$$;

-- public wrappers (service-role only: no grants to anon/authenticated, matching every other public.att_* wrapper in
-- this stack — see 16_att_wiki.sql's public.att_wiki_pv_plan etc.)
create or replace function public.att_series_daily(p_series_id bigint, p_from date, p_to date)
returns table(day date, value double precision)
language sql stable security definer set search_path = '' as $$ select * from ripples.att_series_daily(p_series_id, p_from, p_to) $$;
create or replace function public.att_series_daily_many(p_series_ids bigint[], p_from date, p_to date)
returns table(series_id bigint, day date, value double precision)
language sql stable security definer set search_path = '' as $$ select * from ripples.att_series_daily_many(p_series_ids, p_from, p_to) $$;
create or replace function public.att_hist_wiki_plan(p_target_start date, p_limit int default 60)
returns table(series_id bigint, geo text, key text, topic_id bigint, from_day date, to_day date)
language sql stable security definer set search_path = '' as $$ select * from ripples.att_hist_wiki_plan(p_target_start, p_limit) $$;
create or replace function public.att_hist_wiki_upsert(p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_hist_wiki_upsert(p_rows) $$;
create or replace function public.att_hist_wiki_autostop() returns boolean
language sql security definer set search_path = '' as $$ select ripples.att_hist_wiki_autostop() $$;
create or replace function public.att_hist_wiki_progress(p_target_start date default null) returns jsonb
language sql stable security definer set search_path = '' as $$ select ripples.att_hist_wiki_progress(p_target_start) $$;

do $$
declare f text;
begin
  foreach f in array array[
    'ripples.att_hist_wiki_plan(date, int)', 'ripples.att_hist_wiki_upsert(jsonb)', 'ripples.att_hist_wiki_progress(date)',
    'ripples.att_hist_wiki_autostop()', 'ripples.att_series_daily(bigint, date, date)',
    'ripples.att_series_daily_many(bigint[], date, date)',
    'public.att_series_daily(bigint, date, date)', 'public.att_series_daily_many(bigint[], date, date)',
    'public.att_hist_wiki_plan(date, int)', 'public.att_hist_wiki_upsert(jsonb)', 'public.att_hist_wiki_autostop()',
    'public.att_hist_wiki_progress(date)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Cron: every 10 min, up to 60 series/run (~1 min at 1 req/s serial, inside the WALL_MS budget); auto-stops (see
--    att_hist_wiki_autostop, called by the edge function itself at the end of every run) once fully covered.
-- ---------------------------------------------------------------------------------------------------------------------
select cron.unschedule('att-wiki-hist') where exists (select 1 from cron.job where jobname = 'att-wiki-hist');
select cron.schedule('att-wiki-hist', '*/10 * * * *',
  $$select public.call_collector('att-wiki-hist', '{"mode":"hist_backfill"}'::jsonb)$$);
