-- Migration: attention_stack_core_hardening (W7 att-core, 2026-09-25, after independent verification)
-- (Applied via apply_migration with the same statements; explanatory comments were trimmed from the applied text.)
-- Fixes the verifier's compliance findings:
--  * 401/403 (and sign-in redirects) are PERMANENT host kills until the owner clears them (hard rule 3, DEMARCATION Q2);
--    429/503 still stop the host until the next UTC midnight and halve tomorrow's cap.
--  * cross-isolate host lease (one request stream per host across all concurrent att-* runs);
--  * att_tick: at most 1 running edge job per function and never two running jobs whose sources share a host;
--  * Wikimedia quiet window also covers the 'wikidata' bucket;
--  * per-run caps for shared buckets (config run_caps);
--  * att_ingest / edges / candidates: meta allow-list + size cap; candidate labels that look like handles/URLs rejected;
--  * DEMARCATION Q6 budgets (<= 50% of a published limit; 1 request / 5 s per host where none is published).

-- ---------- config ----------
insert into ripples.att_config(key, value) values
  ('run_caps',   '{"wikimedia":500,"wikidata":150}'),
  ('meta_allow', '["sampled","partial","weekly","monthly","est","method","unit","window","coverage","n_docs","n_posts","n_langs","lang","rank","rank_prev","denominator","total","gap","filled","hll","version","k","bucket","cadence","q"]'),
  ('meta_max_bytes', '512')
on conflict (key) do nothing;
update ripples.att_config set value = value || '{"max_inflight_per_fn":1}'::jsonb, updated_at = now() where key = 'tick';
update ripples.att_config set value = '{"from":"06:30","to":"07:20","buckets":["wikimedia","wikidata"]}'::jsonb,
       updated_at = now() where key = 'wm_quiet_utc';

-- ---------- meta sanitiser: allow-listed keys, scalar values, short strings without '@' or URLs ----------
create or replace function ripples._att_clean_meta(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_allow text[]; v_max int; r jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  select coalesce(array_agg(x), '{}') into v_allow
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('meta_allow'), '[]'::jsonb)) x;
  v_max := coalesce((ripples._att_cfg('meta_max_bytes'))::text::int, 512);
  select jsonb_object_agg(e.key, e.value) into r
    from jsonb_each(p) e
   where e.key = any(v_allow)
     and (jsonb_typeof(e.value) in ('number','boolean')
          or (jsonb_typeof(e.value) = 'string' and length(e.value #>> '{}') <= 40
              and (e.value #>> '{}') !~ '(@|https?://|www\.)'));
  if r is null or length(r::text) > v_max then return null; end if;
  return r;
end $$;

-- ---------- host lease (cross-isolate: one run per host at a time) ----------
create table if not exists ripples.att_host_lease (
  host     text primary key,
  run_id   bigint not null,
  fn       text,
  until    timestamptz not null,
  taken_at timestamptz not null default now()
);
alter table ripples.att_host_lease enable row level security;
revoke all on ripples.att_host_lease from public, anon, authenticated;
grant all on ripples.att_host_lease to service_role;

create or replace function ripples.att_host_lease_take(p_host text, p_run bigint, p_fn text, p_ttl_s int) returns boolean
language plpgsql security definer set search_path = '' as $$
declare ok boolean;
begin
  insert into ripples.att_host_lease(host, run_id, fn, until)
  values (lower(p_host), p_run, p_fn, now() + make_interval(secs => greatest(5, least(coalesce(p_ttl_s, 130), 600))))
  on conflict (host) do update set run_id = excluded.run_id, fn = excluded.fn, until = excluded.until, taken_at = now()
   where ripples.att_host_lease.until < now() or ripples.att_host_lease.run_id = excluded.run_id
  returning true into ok;
  return coalesce(ok, false);
end $$;

create or replace function ripples.att_host_lease_release(p_run bigint) returns int
language sql security definer set search_path = '' as $$
  with d as (delete from ripples.att_host_lease where run_id = p_run returning 1) select count(*)::int from d
$$;

-- ---------- kill switch: 401/403/sign-in redirect = permanent until the owner clears it ----------
drop function if exists public.att_host_kill(text, int, text);
drop function if exists ripples.att_host_kill(text, int, text);
create or replace function ripples.att_host_kill(p_host text, p_status int, p_source text default null,
                                                 p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b record; v_day date := (now() at time zone 'utc')::date; v_until timestamptz; v_perm boolean;
begin
  v_perm := p_status in (401, 403) or p_reason is not null;   -- a barrier: never retried automatically
  v_until := case when v_perm then null else (v_day + 1)::timestamp at time zone 'utc' end;
  perform ripples.att_state_set('kill:' || lower(p_host),
    jsonb_strip_nulls(jsonb_build_object('status', p_status, 'at', now(), 'until', v_until, 'permanent', v_perm,
      'source', p_source, 'reason', p_reason,
      'note', case when v_perm then 'barrier (DEMARCATION Q2): stays stopped until the owner reviews it; clear with ripples.att_host_unkill(host)' end)));
  if p_source is not null then
    select * into b from ripples._att_bucket(p_source);
    if b.cap is not null then
      insert into ripples.att_budget(bucket, day, used, cap) values (b.bucket, v_day, b.cap, b.cap)
      on conflict (bucket, day) do update set used = ripples.att_budget.cap;
      if p_status in (429, 503) then
        insert into ripples.att_budget(bucket, day, used, cap) values (b.bucket, v_day + 1, 0, greatest(1, b.cap / 2))
        on conflict (bucket, day) do update set cap = least(ripples.att_budget.cap, excluded.cap);
      end if;
    end if;
  end if;
  return jsonb_build_object('host', p_host, 'until', v_until, 'permanent', v_perm);
end $$;

-- owner-only (service_role / SQL editor): lift a kill after review
create or replace function ripples.att_host_unkill(p_host text) returns boolean
language sql security definer set search_path = '' as $$
  with d as (delete from ripples.att_state where k = 'kill:' || lower(p_host) returning 1) select count(*) > 0 from d
$$;

-- kill check used by att_tick-independent SQL callers and by tests
create or replace function ripples.att_host_killed(p_host text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select coalesce((v->>'permanent')::boolean, false)
                          or coalesce((v->>'until')::timestamptz > now(), false)
                     from ripples.att_state where k = 'kill:' || lower(p_host)), false)
$$;

-- ---------- budget: quiet window covers every bucket listed in wm_quiet_utc.buckets ----------
create or replace function ripples.att_take_budget(p_bucket text, p_n int) returns int
language plpgsql security definer set search_path = '' as $$
declare b record; v_used int; v_cap int; v_grant int; v_q jsonb; v_t time; v_day date := (now() at time zone 'utc')::date;
begin
  if p_n is null or p_n <= 0 or p_bucket is null then return 0; end if;
  select * into b from ripples._att_bucket(p_bucket);
  if not b.enabled or b.cap is null then return 0; end if;
  v_q := ripples._att_cfg('wm_quiet_utc');
  if v_q is not null and b.bucket in (select jsonb_array_elements_text(coalesce(v_q->'buckets', '["wikimedia","wikidata"]'::jsonb))) then
    v_t := (now() at time zone 'utc')::time;       -- no attention Wikimedia calls while the puzzle build runs
    if v_t >= (v_q->>'from')::time and v_t < (v_q->>'to')::time then return 0; end if;
  end if;
  insert into ripples.att_budget(bucket, day, used, cap) values (b.bucket, v_day, 0, b.cap)
  on conflict (bucket, day) do nothing;
  select used, cap into v_used, v_cap from ripples.att_budget where bucket = b.bucket and day = v_day for update;
  v_grant := greatest(0, least(p_n, v_cap - v_used));
  if v_grant > 0 then
    update ripples.att_budget set used = used + v_grant where bucket = b.bucket and day = v_day;
  end if;
  return v_grant;
end $$;

create or replace function ripples.att_ingest(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_new int := 0; v_daily int := 0; v_hourly int := 0; v_rej jsonb; v_cap numeric;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('series_new', 0, 'rows', 0,
      'rejected', jsonb_build_array(jsonb_build_object('i', -1, 'reason', 'p_rows must be a JSON array')));
  end if;
  v_cap := coalesce((ripples._att_cfg('db_cap_mb'))::text::numeric, 400);
  if pg_database_size(current_database()) > (v_cap - 10) * 1048576 then
    return jsonb_build_object('series_new', 0, 'rows', 0,
      'rejected', jsonb_build_array(jsonb_build_object('i', -1, 'reason', 'db_size_cap')));
  end if;

  drop table if exists pg_temp._att_in;
  create temp table _att_in on commit drop as
  select (e.ord - 1)::int                                   as i,
         e.r->>'source'                                     as source,
         coalesce(nullif(e.r->>'metric', ''), 'n')          as metric,
         coalesce(nullif(e.r->>'geo', ''), 'ALL')           as geo,
         nullif(e.r->>'key', '')                            as key,
         case when e.r->>'day' ~ '^\d{4}-\d{2}-\d{2}$' then (e.r->>'day')::date end as day,
         case when e.r->>'ts' ~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}'
              then date_trunc('hour', (e.r->>'ts')::timestamptz) end as ts,
         (e.r ? 'day') as has_day, (e.r ? 'ts') as has_ts,
         case when jsonb_typeof(e.r->'value') = 'number' then (e.r->>'value')::double precision
              when e.r->>'value' ~ '^-?\d+(\.\d+)?([eE][-+]?\d+)?$' then (e.r->>'value')::double precision end as value,
         case when jsonb_typeof(e.r->'aux') = 'number' then (e.r->>'aux')::real end as aux,
         ripples._att_clean_meta(case when jsonb_typeof(e.r->'meta') = 'object' then e.r->'meta' end) as meta,
         case when e.r->>'topic_id' ~ '^\d+$' then (e.r->>'topic_id')::bigint end as topic_id,
         null::bigint as series_id,
         null::text   as reason
  from jsonb_array_elements(p_rows) with ordinality e(r, ord);

  update pg_temp._att_in set reason = 'missing_source_or_key' where source is null or key is null;
  update pg_temp._att_in i set reason = 'unknown_source'
   where reason is null and not exists (select 1 from ripples.att_sources s where s.source = i.source);
  update pg_temp._att_in i set reason = 'disabled_source'
   where reason is null and exists (select 1 from ripples.att_sources s where s.source = i.source and not s.enabled);
  update pg_temp._att_in set reason = 'need_exactly_one_of_day_ts'
   where reason is null and ((has_day and has_ts) or (not has_day and not has_ts));
  update pg_temp._att_in set reason = 'bad_time'
   where reason is null and ((has_day and day is null) or (has_ts and ts is null)
         or day > (now() at time zone 'utc')::date + 1 or ts > now() + interval '1 hour');
  update pg_temp._att_in set reason = 'bad_value'
   where reason is null and (value is null or value = 'NaN'::double precision
         or value in ('Infinity'::double precision, '-Infinity'::double precision));

  with ins as (
    insert into ripples.att_series(source, metric, geo, key, topic_id)
    select distinct on (i.source, i.metric, i.geo, i.key) i.source, i.metric, i.geo, i.key,
           coalesce(i.topic_id, (select k.topic_id from ripples.att_keys k
                                 where k.source = i.source and k.key = i.key
                                 order by (k.metric = i.metric and k.geo = i.geo) desc, k.topic_id limit 1))
    from pg_temp._att_in i where i.reason is null
    order by i.source, i.metric, i.geo, i.key, i.topic_id nulls last
    on conflict (source, metric, geo, key) do nothing
    returning 1)
  select count(*) into v_new from ins;

  update pg_temp._att_in i set series_id = s.series_id
    from ripples.att_series s
   where i.reason is null and s.source = i.source and s.metric = i.metric and s.geo = i.geo and s.key = i.key;

  update ripples.att_keys k set series_id = s.series_id
    from ripples.att_series s
   where k.series_id is null and s.source = k.source and s.metric = k.metric and s.geo = k.geo and s.key = k.key
     and s.series_id in (select series_id from pg_temp._att_in where series_id is not null);

  -- free-tier profile: hourly series only for active topics (source totals / unlinked keys are allowed)
  if coalesce((ripples._att_cfg('hourly_active_only'))::text::boolean, true) then
    update pg_temp._att_in i set reason = 'hourly_active_only'
      from ripples.att_series s join ripples.att_topics t on t.topic_id = s.topic_id
     where i.reason is null and i.ts is not null and s.series_id = i.series_id and t.status <> 'active';
  end if;

  with d as (
    select distinct on (series_id, day) series_id, day, value, aux, meta
    from pg_temp._att_in where reason is null and day is not null
    order by series_id, day, i desc),
  up as (
    insert into ripples.attention_obs(series_id, day, value, aux, meta)
    select series_id, day, value, aux, meta from d
    on conflict (series_id, day) do update set value = excluded.value, aux = excluded.aux, meta = excluded.meta
    returning 1)
  select count(*) into v_daily from up;

  with h as (
    select distinct on (series_id, ts) series_id, ts, value, aux
    from pg_temp._att_in where reason is null and ts is not null
    order by series_id, ts, i desc),
  up as (
    insert into ripples.attention_obs_hourly(series_id, ts, value, aux)
    select series_id, ts, value, aux from h
    on conflict (series_id, ts) do update set value = excluded.value, aux = excluded.aux
    returning 1)
  select count(*) into v_hourly from up;

  update ripples.att_series s set last_day = greatest(coalesce(s.last_day, x.d), x.d)
    from (select series_id, max(coalesce(day, (ts at time zone 'utc')::date)) d
          from pg_temp._att_in where reason is null group by series_id) x
   where s.series_id = x.series_id;

  select coalesce(jsonb_agg(jsonb_build_object('i', i, 'reason', reason) order by i), '[]'::jsonb) into v_rej
  from (select i, reason from pg_temp._att_in where reason is not null order by i limit 200) r;

  drop table if exists pg_temp._att_in;
  return jsonb_build_object('series_new', v_new, 'rows', v_daily + v_hourly, 'daily', v_daily, 'hourly', v_hourly, 'rejected', v_rej);
end $$;

create or replace function ripples.att_tick(p_mode text default 'collect') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  cfg jsonb := coalesce(ripples._att_cfg('tick'), '{}'::jsonb);
  v_live text[]; v_kinds text[]; v_max int; v_batch int; v_stuck int; v_maxsql int;
  v_inflight int; v_slots int; v_perfn int; j record; r record;
  v_ids bigint[]; v_keys jsonb; v_payload jsonb; v_req bigint; v_rpc text;
  n_disp int := 0; n_done int := 0; n_fail int := 0; n_requeue int := 0; n_sql int := 0;
begin
  v_max    := coalesce((cfg->>'max_edge_inflight')::int, 6);
  v_perfn  := coalesce((cfg->>'max_inflight_per_fn')::int, 1);
  v_batch  := coalesce((cfg->>'backfill_batch')::int, 25);
  v_stuck  := coalesce((cfg->>'stuck_min')::int, 5);
  v_maxsql := coalesce((cfg->>'max_sql')::int, 40);
  select coalesce(array_agg(x), '{}') into v_live
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('live_fns'), '[]'::jsonb)) x;
  v_kinds := case p_mode
    when 'hops' then array['ensure_series','test','placebo']
    when 'backfill' then array['backfill','resolve']
    else array['backfill','ensure_series','test','placebo','resolve'] end;

  -- 1. reconcile pg_net responses for running jobs
  for r in
    select a.id, a.attempts, h.status_code, h.timed_out, h.error_msg
    from ripples.att_jobs a join net._http_response h on h.id = a.http_req
    where a.status = 'running'
  loop
    if r.status_code between 200 and 299 then
      update ripples.att_jobs set status = 'done', finished_at = now() where id = r.id; n_done := n_done + 1;
    elsif r.attempts >= 3 then
      update ripples.att_jobs set status = 'failed', finished_at = now(),
             error = coalesce(r.error_msg, 'http ' || coalesce(r.status_code::text, 'timeout')) where id = r.id;
      n_fail := n_fail + 1;
    else
      update ripples.att_jobs set status = 'queued', http_req = null, not_before = now() + interval '10 minutes',
             error = coalesce(r.error_msg, 'http ' || coalesce(r.status_code::text, 'timeout')) where id = r.id;
      n_requeue := n_requeue + 1;
    end if;
  end loop;

  -- 2. stuck jobs (no response after stuck_min)
  with s as (
    update ripples.att_jobs set
      status = case when attempts >= 3 then 'failed' else 'queued' end,
      finished_at = case when attempts >= 3 then now() end,
      http_req = null, error = 'stuck > ' || v_stuck || ' min'
    where status = 'running' and started_at < now() - make_interval(mins => v_stuck)
    returning 1)
  select n_requeue + count(*) into n_requeue from s;

  -- 3. dispatch edge jobs
  select count(*) into v_inflight from ripples.att_jobs where status = 'running' and fn is not null;
  v_slots := greatest(0, v_max - v_inflight);
  while v_slots > 0 loop
    select * into j from ripples.att_jobs q
     where status = 'queued' and not_before <= now() and fn is not null and fn = any(v_live) and kind = any(v_kinds)
       -- at most v_perfn (default 1) running edge jobs per function ...
       and (select count(*) from ripples.att_jobs rf where rf.status = 'running' and rf.fn = q.fn) < v_perfn
       -- ... and never two running jobs whose sources share a host (one request stream per host, DEMARCATION §7.1)
       and not exists (
         select 1 from ripples.att_jobs rh
           join ripples.att_sources rs on rs.source = coalesce(rh.payload->'params'->>'source', rh.payload->>'source')
           join ripples.att_sources qs on qs.source = coalesce(q.payload->'params'->>'source', q.payload->>'source')
          where rh.status = 'running' and rh.fn is not null and rs.hosts && qs.hosts)
     order by priority, id limit 1 for update skip locked;
    exit when not found;
    if j.kind in ('backfill','resolve') and j.batch_key is not null then
      -- merge queued jobs with the same fn + batch_key: their 'keys' (backfill) or 'items' (resolve) arrays are concatenated
      with b as (
        select id, payload from ripples.att_jobs
         where (id = j.id) or (status = 'queued' and not_before <= now() and fn = j.fn and batch_key = j.batch_key)
         order by (id = j.id) desc, priority, id limit v_batch for update skip locked)
      select array_agg(b.id),
             coalesce((select jsonb_agg(k.v) from b b2, jsonb_array_elements(coalesce(b2.payload->(case when j.kind = 'resolve' then 'items' else 'keys' end), '[]'::jsonb)) k(v)), '[]'::jsonb)
        into v_ids, v_keys
        from b;
      v_payload := j.payload || jsonb_build_object(case when j.kind = 'resolve' then 'items' else 'keys' end, v_keys,
                                                   'job_id', j.id, 'job_ids', to_jsonb(v_ids));
    else
      v_ids := array[j.id];
      v_payload := j.payload || jsonb_build_object('job_id', j.id, 'job_ids', to_jsonb(v_ids));
    end if;
    v_req := public.call_collector(j.fn, v_payload);
    update ripples.att_jobs set status = 'running', started_at = now(), attempts = attempts + 1, http_req = v_req, error = null
     where id = any(v_ids);
    n_disp := n_disp + 1; v_slots := v_slots - 1;
  end loop;

  -- 4. SQL jobs (fn null): payload {"rpc":"att_xxx","args":{...}} -> select ripples.att_xxx(args::jsonb)
  for j in
    select * from ripples.att_jobs
     where status = 'queued' and fn is null and not_before <= now() and kind = any(v_kinds)
     order by priority, id limit v_maxsql for update skip locked
  loop
    v_rpc := j.payload->>'rpc';
    if v_rpc is null or v_rpc !~ '^att_[a-z0-9_]+$' or to_regprocedure('ripples.' || v_rpc || '(jsonb)') is null then
      update ripples.att_jobs set status = 'failed', finished_at = now(), error = 'unknown rpc ' || coalesce(v_rpc, 'null')
       where id = j.id;
      continue;
    end if;
    begin
      execute format('select ripples.%I($1)', v_rpc) using coalesce(j.payload->'args', '{}'::jsonb);
      update ripples.att_jobs set status = 'done', attempts = attempts + 1, started_at = now(), finished_at = now() where id = j.id;
    exception when others then
      update ripples.att_jobs set attempts = attempts + 1, error = left(sqlerrm, 2000),
             status = case when attempts + 1 >= 3 then 'failed' else 'queued' end,
             not_before = now() + interval '5 minutes' where id = j.id;
    end;
    n_sql := n_sql + 1;
  end loop;

  return jsonb_build_object('mode', p_mode, 'dispatched', n_disp, 'reconciled_done', n_done, 'failed', n_fail,
                            'requeued', n_requeue, 'sql_jobs', n_sql,
                            'queued', (select count(*) from ripples.att_jobs where status = 'queued'),
                            'running', (select count(*) from ripples.att_jobs where status = 'running'));
end $$;

-- ---------- edges / candidates: sanitised meta; candidate labels must not look like handles or URLs ----------
create or replace function ripples.att_ingest_edges(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v int; v_bad int;
begin
  with e as (
    select distinct on (x.source, coalesce(x.geo,'ALL'), x.from_key, x.to_key, x.period, x.grain) x.*
    from jsonb_to_recordset(p_rows) as x(source text, geo text, from_key text, to_key text, period date, grain text,
                                          n double precision, lift real, pmi real, from_topic bigint, to_topic bigint, meta jsonb)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.from_key is not null and x.to_key is not null and x.period is not null and x.n is not null
      and x.grain in ('day','month')
      and x.from_key !~ '^@|https?://' and x.to_key !~ '^@|https?://'),
  up as (
    insert into ripples.att_edges(source, geo, from_key, to_key, period, grain, n, lift, pmi, from_topic, to_topic, meta)
    select source, coalesce(geo,'ALL'), from_key, to_key, period, grain, n, lift, pmi, from_topic, to_topic,
           ripples._att_clean_meta(meta) from e
    on conflict (source, geo, from_key, to_key, period, grain) do update
      set n = excluded.n, lift = excluded.lift, pmi = excluded.pmi, meta = excluded.meta,
          from_topic = coalesce(excluded.from_topic, ripples.att_edges.from_topic),
          to_topic = coalesce(excluded.to_topic, ripples.att_edges.to_topic)
    returning 1)
  select count(*) into v from up;
  v_bad := jsonb_array_length(p_rows) - v;
  return jsonb_build_object('rows', v, 'rejected', v_bad);
end $$;

create or replace function ripples.att_ingest_candidates(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  with c as (
    select distinct on (x.day, x.source, coalesce(x.geo,'ALL'), x.label) x.*
    from jsonb_to_recordset(p_rows) as x(day date, source text, geo text, label text, rank int, value double precision,
                                          evidence real, qid text, topic_id bigint, meta jsonb)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.day is not null and x.label is not null and x.evidence between 0 and 1
      and x.label !~ '(^@|@[A-Za-z0-9_.-]+\.[a-z]{2,}|https?://|^did:)' and length(x.label) <= 200),
  up as (
    insert into ripples.att_trend_candidates(day, source, geo, label, rank, value, evidence, qid, topic_id, meta)
    select day, source, coalesce(geo,'ALL'), left(label, 200), rank, value, evidence, qid, topic_id,
           ripples._att_clean_meta(meta) from c
    on conflict (day, source, geo, label) do update
      set rank = excluded.rank, value = excluded.value, evidence = excluded.evidence,
          qid = coalesce(excluded.qid, ripples.att_trend_candidates.qid),
          topic_id = coalesce(excluded.topic_id, ripples.att_trend_candidates.topic_id),
          meta = excluded.meta, observed_at = now()
    returning 1)
  select count(*) into v from up;
  return jsonb_build_object('rows', v, 'rejected', jsonb_array_length(p_rows) - v);
end $$;

-- ---------- public wrappers (service_role only) ----------
create or replace function public.att_host_kill(p_host text, p_status int, p_source text default null, p_reason text default null)
returns jsonb language sql security definer set search_path = '' as $$
  select ripples.att_host_kill(p_host, p_status, p_source, p_reason) $$;
create or replace function public.att_host_lease_take(p_host text, p_run bigint, p_fn text, p_ttl_s int) returns boolean
language sql security definer set search_path = '' as $$ select ripples.att_host_lease_take(p_host, p_run, p_fn, p_ttl_s) $$;
create or replace function public.att_host_lease_release(p_run bigint) returns int
language sql security definer set search_path = '' as $$ select ripples.att_host_lease_release(p_run) $$;

-- ---------- DEMARCATION Q6 budgets (it overrides ATTENTION_STACK §3.5 where they differ) ----------
-- published limit -> <= 50% of it; none published -> 1 request / 5 s per host (spacing_ms 5000), daily cadence.
update ripples.att_sources s set spacing_ms = v.sp, per_run_cap = v.run, per_day_cap = v.day,
       reason = nullif(concat_ws('; ', nullif(s.reason, ''), v.why), '')
from (values
  ('anilist',        4000,  25,  150, 'Q6: 30/min degraded limit -> 15/min'),
  ('apple.rss',      5000,  20,   25, 'Q6: no published limit -> 1 req/5 s'),
  ('bsky.jet',       5000,   1,  288, 'Q6: one stream connection per run'),
  ('bsky.trends',    1000,   2,   48, 'Q6: 3000/5 min published -> far below 50%'),
  ('citibike.trips', 5000,   3,    3, 'Q6: no published limit -> 1 req/5 s'),
  ('fema.decl',      5000,   3,    3, 'Q6: no published limit -> 1 req/5 s'),
  ('finra.shvol',    5000,  20,  251, 'Q6: no published limit -> 1 req/5 s'),
  ('gdacs',          5000,   3,    3, 'Q6: no published limit -> 1 req/5 s'),
  ('gdelt.gkg',      5000,   1,   96, 'Q6: one file per run'),
  ('gh.search',     12000,   8,    8, 'Q6: 10/min unauthenticated -> 5/min'),
  ('gh.stars',       5000,  25,   25, 'Q6: 60/h unauthenticated (shared api.github.com) -> <= 30/h'),
  ('gt.rss',         5000,   8,  192, 'Q6: no published limit -> 1 req/5 s'),
  ('hf.trending',    1500,  60,  100, 'Q6: ~500/5 min anonymous -> <= 50%'),
  ('hiringlab.postings', 5000, 3,  3, 'Q6: no published limit -> 1 req/5 s'),
  ('hn.algolia',      750, 140, 4000, 'Q6: 10,000/h per IP -> <= 5,000/h (750 ms)'),
  ('ia.thirdeye',    5000,   1,   24, 'Q6: one file per run'),
  ('iem.warn',      10000,   3,    3, 'Q6: no published limit -> >= 5 s'),
  ('kalshi.mkt',      200, 300,  300, 'Q6: 20 reads/s basic tier -> 5/s'),
  ('masto.tags',     2000,  50,  750, 'Q6: 300/5 min per IP (shared mastodon.social) -> 150/5 min'),
  ('masto.trends',   2000,  10,   30, 'Q6: 300/5 min per IP (shared mastodon.social) -> 150/5 min'),
  ('mta.ridership',  5000,   3,    3, 'Q6: no published limit -> 1 req/5 s'),
  ('news.sitemap',   5000,   4,   16, 'Q6: no published limit -> 1 req/5 s per host'),
  ('npm.dl',         5000,  20,   80, 'Q6: no published limit -> 1 req/5 s (bulk up to 128 packages/request)'),
  ('ol.trending',    5000,   5,    5, 'Q6: no published limit -> 1 req/5 s'),
  ('poly.mkt',        500, 200,  220, 'Q6: gamma API limits are >= 100/10 s -> far below 50%'),
  ('pypi.dl',        5000,  20,   30, 'Q6: no published limit -> 1 req/5 s'),
  ('se.api',          200, 150,  150, 'Q6: 300/day unkeyed -> 150/day; 30 req/s -> 5/s'),
  ('steamspy',       2000,   5,    5, 'Q6: 1 req/s published -> 0.5/s (the "all" endpoint: 1/60 s -> use >= 120 s)'),
  ('tranco.rank',    5000,   1,    1, 'Q6: one file per day'),
  ('tsa.pax',        5000,   3,    3, 'Q6: no published limit -> 1 req/5 s'),
  ('usasp.spend',    5000,  20,   50, 'Q6: no published limit -> 1 req/5 s'),
  ('usgs.eq',        5000,   3,    3, 'Q6: no published limit -> 1 req/5 s'),
  ('wiki.cs',        5000,   3,    3, 'Q6: dumps -> 1 req/5 s'),
  ('wiki.pv',         500, 200, null, 'Q6: AQS 100 req/s published -> far below 50%; 500 ms after the 2026-09-25 429'),
  ('wiki.media',      500, 200, null, 'Q6: AQS 100 req/s published -> far below 50%; 500 ms after the 2026-09-25 429'),
  ('wiki.topcc',      500,  60, null, 'Q6: AQS 100 req/s published -> far below 50%; 500 ms after the 2026-09-25 429')
) as v(source, sp, run, day, why)
where s.source = v.source;

-- ---------- grants (every att function: service_role only) ----------
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where (n.nspname = 'ripples' and (p.proname like 'att\_%' or p.proname like '\_att\_%'))
              or (n.nspname = 'public' and p.proname like 'att\_%')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
