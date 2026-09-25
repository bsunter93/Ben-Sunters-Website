-- Knock-On v5 / W2: migration ripples_v5_pipeline_tuning4 (in-place patch)
-- AQS answered 429 with Retry-After of 8-14 s during the second test run: pace AQS at 4 requests/s and requeue a
-- rate-limited job after the server's Retry-After (+5 s, at least 30 s; 60 s when none was sent) instead of 3 minutes.
update ripples.config set value = value || '{"aqs_spacing_ms":250}'::jsonb where key = 'pipeline';
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('public.ripples_job_done(bigint,boolean,text,integer,jsonb)'::regprocedure) into d;
  d2 := replace(d, 'case when p_err like ''rate_limited%'' then interval ''3 minutes'' else interval ''30 seconds'' end',
                   'case when p_err like ''rate_limited%'' then make_interval(secs => greatest(30, coalesce(substring(p_err from ''retry-after=([0-9]+)'')::int, 55) + 5)) else interval ''30 seconds'' end');
  if d2 = d and position('retry-after=' in d) = 0 then raise exception 'job_done patch did not apply'; end if;
  if d2 <> d then execute d2; end if;
end $$;
