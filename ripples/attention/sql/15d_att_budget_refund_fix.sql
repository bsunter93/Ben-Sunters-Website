-- 15d_att_budget_refund_fix (W7 att-charts, 2026-09-25, applied as migration att_budget_refund_fix)
-- Bug found by att-charts: att.ts takes daily budget in chunks of min(25, per_run_cap) and refunds unspent units in
-- Run.finish() via att_budget_refund. The refund was refused whenever used = cap ("a bucket spent by a kill stays
-- spent"), but a chunk that takes the whole day's cap also leaves used = cap. So every source whose per_run_cap equals
-- its per_day_cap (gh.search 8/8, steamspy 5/5, ol.trending 5/5, tranco.rank 2/2) was marked spent for the day after a
-- single request, and apple.rss (20 per run, 30 per day) lost its unspent units whenever a chunk reached the cap.
-- Fix: record kill-spent buckets explicitly (att_budget.killed) and refuse refunds only for those.
alter table ripples.att_budget add column if not exists killed boolean not null default false;

-- today's buckets spent by an active kill stay spent
update ripples.att_budget b set killed = true
  from ripples.att_state s, lateral ripples._att_bucket(s.v->>'source') kb
 where s.k like 'kill:%' and s.v ? 'source'
   and (coalesce((s.v->>'permanent')::boolean, false) or (s.v->>'until')::timestamptz > now())
   and b.bucket = kb.bucket and b.day = (now() at time zone 'utc')::date;

create or replace function ripples.att_budget_refund(p_bucket text, p_n integer)
returns integer
language plpgsql security definer set search_path = '' as $$
declare b record; v int; v_day date := (now() at time zone 'utc')::date;
begin
  if p_n is null or p_n <= 0 or p_bucket is null then return 0; end if;
  select * into b from ripples._att_bucket(p_bucket);
  update ripples.att_budget set used = greatest(0, used - p_n)
   where bucket = b.bucket and day = v_day and not killed   -- a bucket spent by a kill stays spent
  returning used into v;
  return coalesce(p_n, 0) * (case when v is null then 0 else 1 end);
end $$;

create or replace function ripples.att_host_kill(p_host text, p_status integer, p_source text default null, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b record; v_day date := (now() at time zone 'utc')::date; v_until timestamptz; v_perm boolean;
begin
  v_perm := p_status in (401, 403) or p_reason is not null;
  v_until := case when v_perm then null else (v_day + 1)::timestamp at time zone 'utc' end;
  perform ripples.att_state_set('kill:' || lower(p_host),
    jsonb_strip_nulls(jsonb_build_object('status', p_status, 'at', now(), 'until', v_until, 'permanent', v_perm,
      'source', p_source, 'reason', p_reason,
      'note', case when v_perm then 'barrier (DEMARCATION Q2): stays stopped until the owner reviews it; clear with ripples.att_host_unkill(host)' end)));
  if p_source is not null then
    select * into b from ripples._att_bucket(p_source);
    if b.cap is not null then
      insert into ripples.att_budget(bucket, day, used, cap, killed) values (b.bucket, v_day, b.cap, b.cap, true)
      on conflict (bucket, day) do update set used = ripples.att_budget.cap, killed = true;
      if p_status in (429, 503) then
        insert into ripples.att_budget(bucket, day, used, cap) values (b.bucket, v_day + 1, 0, greatest(1, b.cap / 2))
        on conflict (bucket, day) do update set cap = least(ripples.att_budget.cap, excluded.cap);
      end if;
    end if;
  end if;
  return jsonb_build_object('host', p_host, 'until', v_until, 'permanent', v_perm);
end $$;

revoke all on function ripples.att_budget_refund(text, integer) from public, anon, authenticated;
grant execute on function ripples.att_budget_refund(text, integer) to service_role;
revoke all on function ripples.att_host_kill(text, integer, text, text) from public, anon, authenticated;
grant execute on function ripples.att_host_kill(text, integer, text, text) to service_role;

-- Correct today's over-charged att-charts buckets to the requests actually made (att_runs; robots.txt fetches are not
-- charged). apple.rss is corrected after its in-flight run finished (see 15c ops record).
update ripples.att_budget set used = v.used
  from (values ('gh.search', 1), ('steamspy', 1), ('ol.trending', 1), ('tranco.rank', 2)) v(bucket, used)
 where att_budget.bucket = v.bucket and att_budget.day = date '2026-09-25' and not att_budget.killed;
