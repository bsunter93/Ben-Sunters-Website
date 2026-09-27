-- Knock-On v5 / W2: migration ripples_v5_pipeline_stop_flag (in-place patch of ripples._render)
-- reveal.rounds[].shared_trigger_stop is true only where the chain actually stopped: the round is the last one that
-- continues the chain (the next round is a fresh ripple or there is none) and a passing next hop was a shared trigger.
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('ripples._render(integer,text,date,date,date,date,jsonb,text,bigint)'::regprocedure) into d;
  d2 := replace(d, 'st_stop := exists (', 'st_stop := not coalesce((p_rounds->i->>''continues'')::boolean, false) and exists (');
  if d2 = d and position('p_rounds->i->>''continues''' in d) = 0 then raise exception '_render patch did not apply'; end if;
  if d2 <> d then execute d2; end if;
end $$;
