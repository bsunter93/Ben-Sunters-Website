-- Migration: attention_stack_core_tick_merge (W7 att-core): att_tick also merges queued 'resolve' jobs (items arrays).
create or replace function ripples.att_tick(p_mode text default 'collect') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  cfg jsonb := coalesce(ripples._att_cfg('tick'), '{}'::jsonb);
  v_live text[]; v_kinds text[]; v_max int; v_batch int; v_stuck int; v_maxsql int;
  v_inflight int; v_slots int; j record; r record;
  v_ids bigint[]; v_keys jsonb; v_payload jsonb; v_req bigint; v_rpc text;
  n_disp int := 0; n_done int := 0; n_fail int := 0; n_requeue int := 0; n_sql int := 0;
begin
  v_max    := coalesce((cfg->>'max_edge_inflight')::int, 6);
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
    select * into j from ripples.att_jobs
     where status = 'queued' and not_before <= now() and fn is not null and fn = any(v_live) and kind = any(v_kinds)
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
revoke all on function ripples.att_tick(text) from public, anon, authenticated;
grant execute on function ripples.att_tick(text) to service_role;
