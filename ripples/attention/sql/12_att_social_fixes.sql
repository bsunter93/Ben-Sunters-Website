-- 12_att_social_fixes (W7 att-social, 2026-09-25, applied as migration att_social_fixes3)
-- 1) att_social_accum: hashtag rows pass the strict identifier screen before storage (a facet tag such as
--    'someone.bsky.social' or 'shop.etsy.com' is a handle/personal domain, not a topic). Existing matches deleted.
-- 2) close the orphan run left by the WORKER_RESOURCE_LIMIT catch-up attempt (run 28).
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
      where not ripples._att_ident_like(t.tag, p_tags->>'source', true)
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

delete from ripples.att_social_tags where ripples._att_ident_like(tag, source, true);

update ripples.att_runs set finished_at = coalesce(finished_at, started_at + interval '150 seconds'), ok = false,
       error = coalesce(error, 'worker killed (WORKER_RESOURCE_LIMIT, HTTP 546); no data written, cursor not advanced')
 where fn = 'att-social' and finished_at is null and started_at < now() - interval '1 hour';
