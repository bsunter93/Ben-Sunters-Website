-- Compliance audit fix (2026-09-25): the Knock-On SQL dispatcher requeued a failed job up to 3 times (30-60 s later)
-- whatever the error, so a 401/403 or a 429/503 from a host was retried within the same daily run.
-- ATTENTION_STACK §0 hard rule 3 ("no retry after a 403, no retry storms after a 429") and DEMARCATION §7.3
-- ("on any 429 or 503, stop that source for the run"): such jobs now end as 'failed' (no requeue). The one in-process
-- AQS retry in kn.ts is unchanged, and a MediaWiki maxlag error (API:Etiquette says wait and retry) still requeues.
-- Everything else in the function is unchanged.
-- Previous definition: the same function without v_noretry (st := case when p_ok then 'done' when j.attempts < 3 ...).
CREATE OR REPLACE FUNCTION public.ripples_job_done(p_job bigint, p_ok boolean, p_err text, p_calls integer, p_result jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j ripples.jobs; st text; v_noretry boolean;
begin
  select * into j from ripples.jobs where id = p_job for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown job'); end if;
  if j.status <> 'running' then
    update ripples.runs set wm_calls = wm_calls + greatest(coalesce(p_calls, 0), 0) where as_of = j.as_of;
    return jsonb_build_object('ok', true, 'late', true);
  end if;
  -- 401/403 (barrier) or 429/503 (rate limit): never requeue within the run
  v_noretry := not p_ok and coalesce(p_err, '') ~* '(\m(aqs|api|http|status)\s+(401|403)\M)|(^rate_limited: \S+( api)? (429|503)\M)';
  st := case when p_ok then 'done' when v_noretry then 'failed' when j.attempts < 3 then 'queued' else 'failed' end;
  update ripples.jobs set status = st, calls = calls + greatest(coalesce(p_calls, 0), 0), error = left(p_err, 500),
    result = p_result, finished_at = case when st in ('done','failed') then now() end,
    not_before = case when st = 'queued' then now() + case when p_err like 'rate_limited%'
      then make_interval(secs => greatest(30, coalesce(substring(p_err from 'retry-after=([0-9]+)')::int, 55) + 5))
      else interval '30 seconds' end end
  where id = p_job;
  update ripples.runs set wm_calls = wm_calls + greatest(coalesce(p_calls, 0), 0),
    errors = errors + case when p_ok then 0 else 1 end where as_of = j.as_of;
  perform ripples._dispatch(6);
  return jsonb_build_object('ok', true, 'status', st);
end $function$;
