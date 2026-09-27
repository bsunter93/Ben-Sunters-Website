-- 19_att_social_fixes5 (W7 att-social, 2026-09-25, applied as migration att_social_fixes5)
-- Addresses the four advisories of the independent verification (18:27-18:30 UTC):
--  1. hashtags: k-anonymity floor of >= 3 distinct authors (HLL) before a tag row is first stored; existing rows below
--     the floor, or without an author sketch, are deleted (DEMARCATION Q5 "aggregates only").
--  2. bsky.jet per_day_cap: 600 -> 432 = the 288 scheduled runs of ATTENTION_STACK sec 3.5 + 144 catch-up runs
--     (50 %) for the sec 9 "catch-up every minute while lagging" rule; flagged as a deviation in the source row.
--  3. Jetstream failover after a kill: any kill written for one bsky.jet host (jetstream1/jetstream2, same operator)
--     is copied to every other bsky.jet host by trigger, and the cron gate refuses to call the edge function while
--     any bsky.jet host has an active kill. A 401/403 therefore stops Jetstream entirely until the owner reviews it
--     (ripples.att_host_unkill on each host, or on the host that was killed: sibling copies are removed with it).
--  4. (owner action, no SQL) publish https://bensunter.com/ripples/methods/.

-- ---------------------------------------------------------------- 1. hashtag author floor
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
      -- size + privacy guard: a tag that does not reach the author floor is only added to a row that already exists
      -- identifier screen: hashtags that look like handles, DIDs, domains or URLs are never stored (hard rule 4)
      -- plus the tag screen: no '.', '@', '/', ':', whitespace, control chars or backslash, <= 40 chars
      where ripples.att_social_tag_ok(t.tag)
        and not ripples._att_ident_like(t.tag, p_tags->>'source', true)
        -- k-anonymity floor (fixes5): a new tag row needs >= 3 distinct authors in this run (HLL estimate; the
        -- linear-counting range is exact enough at 1-3 and collisions only under-count). Once stored, a row's
        -- register only grows, so every stored row keeps >= 3 distinct authors.
        and (coalesce(ripples._att_hll_est(t.reg), 0) >= 3
             or exists (select 1 from ripples.att_social_tags x
                        where x.day = t.day and x.source = p_tags->>'source' and x.tag = t.tag))
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
  -- completed days (older than the 36 h Jetstream buffer) keep only tags with >= 5 posts (baseline for burst z)
  delete from ripples.att_social_tags where day < (now() at time zone 'utc')::date - 2 and n < 5;

  drop table if exists pg_temp._sa;
  drop table if exists pg_temp._sb;
  return v_res || jsonb_build_object('bad_rows', v_bad, 'tags', v_tags);
end $$;

-- ---------------------------------------------------------------- 2. budget: spec 288 + catch-up headroom
update ripples.att_sources
   set per_day_cap = 432,
       reason = 'Q6: no published limit (default 1 req/5 s per host); one websocket per run. per_day_cap 432 = 288 '
             || 'scheduled runs (ATTENTION_STACK 3.5) + 144 catch-up runs (sec 9 risk row: catch-up every minute while '
             || 'lagging); DEVIATION from the 288 in 3.5, recorded 2026-09-25. Any kill on one host stops both hosts.'
 where source = 'bsky.jet';

-- ---------------------------------------------------------------- 3. kills cover every bsky.jet host
create or replace function ripples._att_social_jet_kill_sync() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_hosts text[]; v_host text;
begin
  if pg_trigger_depth() > 1 then return null; end if;
  select array_agg(lower(h)) into v_hosts
    from ripples.att_sources s, unnest(s.hosts) h where s.source = 'bsky.jet';
  if v_hosts is null then return null; end if;
  if tg_op = 'DELETE' then
    v_host := substr(old.k, 6);
    if v_host = any(v_hosts) then
      -- unkilling the host that was killed also lifts the copies made from it
      delete from ripples.att_state
       where k = any(array(select 'kill:' || h from unnest(v_hosts) h where h <> v_host))
         and v->>'via' = v_host;
    end if;
    return null;
  end if;
  v_host := substr(new.k, 6);
  if not (v_host = any(v_hosts)) or new.v ? 'via' then return null; end if;
  insert into ripples.att_state(k, v, updated_at)
  select 'kill:' || h, new.v || jsonb_build_object('via', v_host,
           'note', 'copied from ' || v_host || ': same operator, no failover after a kill (hard rule 3)'), now()
    from unnest(v_hosts) h where h <> v_host
  on conflict (k) do update set v = excluded.v, updated_at = now()
   where not coalesce((ripples.att_state.v->>'permanent')::boolean, false); -- never downgrade a permanent kill
  return null;
end $$;

drop trigger if exists att_social_jet_kill_sync on ripples.att_state;
create trigger att_social_jet_kill_sync
  after insert or update on ripples.att_state
  for each row when (new.k like 'kill:jetstream%')
  execute function ripples._att_social_jet_kill_sync();
drop trigger if exists att_social_jet_kill_sync_del on ripples.att_state;
create trigger att_social_jet_kill_sync_del
  after delete on ripples.att_state
  for each row when (old.k like 'kill:jetstream%')
  execute function ripples._att_social_jet_kill_sync();

-- cron gate: no Jetstream call while any bsky.jet host has an active (permanent or not yet expired) kill
create or replace function ripples.att_social_jet_budget(p_lane text default 'live') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_day date := (now() at time zone 'utc')::date; v_cap int; v_used int; v_killed boolean; v_slots int; v_reserve int;
        v_hostkill text;
begin
  select per_day_cap into v_cap from ripples.att_sources where source = 'bsky.jet' and enabled;
  if v_cap is null then return jsonb_build_object('ok', false, 'reason', 'disabled'); end if;
  select string_agg(substr(st.k, 6), ',') into v_hostkill
    from ripples.att_state st
   where st.k = any(array(select 'kill:' || lower(h) from ripples.att_sources s, unnest(s.hosts) h where s.source = 'bsky.jet'))
     and (coalesce((st.v->>'permanent')::boolean, false)
          or (st.v->>'until' is not null and (st.v->>'until')::timestamptz > now()));
  insert into ripples.att_budget(bucket, day, used, cap) values ('bsky.jet', v_day, 0, v_cap)
  on conflict (bucket, day) do update set cap = excluded.cap where ripples.att_budget.cap is distinct from excluded.cap;
  select used, cap, killed into v_used, v_cap, v_killed from ripples.att_budget where bucket = 'bsky.jet' and day = v_day;
  v_slots := ceil(extract(epoch from ((v_day + 1)::timestamp - (now() at time zone 'utc'))) / 300.0)::int;
  v_reserve := v_slots + 12;
  return jsonb_strip_nulls(jsonb_build_object('used', v_used, 'cap', v_cap, 'left', greatest(0, v_cap - v_used),
    'reserve', v_reserve, 'killed', coalesce(v_killed, false), 'host_killed', v_hostkill,
    'ok', not coalesce(v_killed, false) and v_hostkill is null
          and case when p_lane = 'backfill' then v_cap - v_used > v_reserve else v_cap - v_used > 0 end));
end $$;

do $$ declare f text; begin
  foreach f in array array['ripples.att_social_accum(jsonb,jsonb,jsonb)', 'ripples._att_social_jet_kill_sync()',
                           'ripples.att_social_jet_budget(text)', 'public.att_social_jet_budget(text)']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- ---------------------------------------------------------------- 1b. existing tags below the author floor
delete from ripples.att_social_tags where reg is null or ripples._att_hll_est(reg) < 3;

-- ---------------------------------------------------------------- 3b. (migration att_social_fixes5b)
-- a later 429/503 day kill written straight to a Jetstream host must not replace a permanent (401/403) kill that the
-- host already holds, directly or as a copy from its sister host
create or replace function ripples._att_social_jet_kill_keep_perm() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((old.v->>'permanent')::boolean, false) and not coalesce((new.v->>'permanent')::boolean, false) then
    return old; -- keep the permanent kill as it is
  end if;
  return new;
end $$;
drop trigger if exists att_social_jet_kill_keep_perm on ripples.att_state;
create trigger att_social_jet_kill_keep_perm
  before update on ripples.att_state
  for each row when (new.k like 'kill:jetstream%')
  execute function ripples._att_social_jet_kill_keep_perm();
revoke all on function ripples._att_social_jet_kill_keep_perm() from public, anon, authenticated;
grant execute on function ripples._att_social_jet_kill_keep_perm() to service_role;
