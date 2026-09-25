-- 17_att_social_fixes4 (W7 att-social, 2026-09-25, applied as migration att_social_fixes4)
-- Verifier round 2:
-- 1) Jetstream stalled on budget: today's att_budget row for bsky.jet was frozen at an old cap (288) while
--    att_sources.per_day_cap is 600, and the morning buffer-replay lane spent ~200 units. Fixes:
--    a) today's row raised to the configured cap;
--    b) ripples.att_social_jet_budget(lane) syncs the bsky.jet row cap to att_sources.per_day_cap and keeps a
--       live-lane reserve (remaining 5-min slots today + 12): the buffer-replay lane may only spend units above it;
--    c) the catch-up cron no longer invokes the edge function when the bsky.jet budget is spent/killed or the
--       replay lane is deferred (jet.bf.defer_until).
-- 2) Hashtag screen tightened: tags containing '.', '@', '/', ':', whitespace, control chars or a backslash, or
--    longer than 40 chars, are never stored; existing ones deleted.

create or replace function ripples.att_social_tag_ok(p_tag text) returns boolean
language sql immutable set search_path = '' as $$
  select p_tag is not null and char_length(p_tag) between 1 and 40
     and p_tag !~ '[.@/:[:space:][:cntrl:]]' and strpos(p_tag, chr(92)) = 0
$$;

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
      -- size guard: a tag seen once in a run is only added to a row that already exists
      -- identifier screen: hashtags that look like handles, DIDs, domains or URLs are never stored (hard rule 4)
      -- plus the tag screen: no '.', '@', '/', ':', whitespace, control chars or backslash, <= 40 chars
      where ripples.att_social_tag_ok(t.tag)
        and not ripples._att_ident_like(t.tag, p_tags->>'source', true)
        and (t.n >= 2 or exists (select 1 from ripples.att_social_tags x
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

-- bsky.jet budget gate: sync today's row cap to the configured cap, report what is left and whether this lane may
-- take a unit. The live lane may use everything; the replay lane only what is above the live reserve.
create or replace function ripples.att_social_jet_budget(p_lane text default 'live') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_day date := (now() at time zone 'utc')::date; v_cap int; v_used int; v_killed boolean; v_slots int; v_reserve int;
begin
  select per_day_cap into v_cap from ripples.att_sources where source = 'bsky.jet' and enabled;
  if v_cap is null then return jsonb_build_object('ok', false, 'reason', 'disabled'); end if;
  insert into ripples.att_budget(bucket, day, used, cap) values ('bsky.jet', v_day, 0, v_cap)
  on conflict (bucket, day) do update set cap = excluded.cap where ripples.att_budget.cap is distinct from excluded.cap;
  select used, cap, killed into v_used, v_cap, v_killed from ripples.att_budget where bucket = 'bsky.jet' and day = v_day;
  -- live runs still due today (every 5 min) + a margin for catch-up after a hiccup
  v_slots := ceil(extract(epoch from ((v_day + 1)::timestamp - (now() at time zone 'utc'))) / 300.0)::int;
  v_reserve := v_slots + 12;
  return jsonb_build_object('used', v_used, 'cap', v_cap, 'left', greatest(0, v_cap - v_used), 'reserve', v_reserve,
    'killed', coalesce(v_killed, false),
    'ok', not coalesce(v_killed, false) and case when p_lane = 'backfill' then v_cap - v_used > v_reserve
                                                 else v_cap - v_used > 0 end);
end $$;
create or replace function public.att_social_jet_budget(p_lane text default 'live') returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_social_jet_budget(p_lane) $$;

do $$ declare f text; begin
  foreach f in array array['ripples.att_social_tag_ok(text)', 'ripples.att_social_jet_budget(text)',
                           'public.att_social_jet_budget(text)']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- today's frozen row: raise to the configured cap
update ripples.att_budget b set cap = s.per_day_cap
  from ripples.att_sources s
 where s.source = 'bsky.jet' and b.bucket = 'bsky.jet' and b.day = (now() at time zone 'utc')::date
   and b.cap < s.per_day_cap;

-- existing tags that fail the tightened screen
delete from ripples.att_social_tags where not ripples.att_social_tag_ok(tag);

-- catch-up cron: skip the edge call when nothing can happen (budget spent/killed, replay lane deferred)
select cron.alter_job((select jobid from cron.job where jobname = 'att-jetstream-catchup'), command => $cmd$
  with st as (
    select coalesce((select (v->>'cursor')::bigint from ripples.att_state where k = 'jet.cursor'), 0)
             < (extract(epoch from now()) * 1e6)::bigint - 1800000000 as lagging,
           exists (select 1 from ripples.att_state where k = 'jet.bf'
                    and (v->>'cursor')::bigint < (v->>'until')::bigint
                    and coalesce((v->>'defer_until')::timestamptz, '-infinity'::timestamptz) <= now()) as replay,
           not exists (select 1 from ripples.att_budget b
                        where b.bucket = 'bsky.jet' and b.day = (now() at time zone 'utc')::date
                          and (b.killed or b.used >= greatest(b.cap, coalesce((select per_day_cap from ripples.att_sources
                                                                                 where source = 'bsky.jet'), 0)))) as has_budget)
  select public.call_collector('att-social',
           case when lagging then '{"mode":"jetstream"}' else '{"mode":"jetstream","params":{"lane":"backfill"}}' end::jsonb)
  from st
  where extract(minute from now())::int % 5 <> 1 and has_budget and (lagging or replay)
$cmd$);
