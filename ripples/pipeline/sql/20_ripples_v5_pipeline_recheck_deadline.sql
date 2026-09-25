-- Knock-On v5 / W2: migration ripples_v5_pipeline_recheck_deadline (in-place patch of ripples._tick_run)
-- Practice runs: the safety re-check stage ends at practice_deadline_min + 2 (24 min) instead of + 4, so a practice day
-- always finishes within the 25-minute acceptance bound (the re-check job itself takes ~10 s).
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('ripples._tick_run(date)'::regprocedure) into d;
  d2 := replace(d, 'make_interval(mins => dl + 4)', 'make_interval(mins => dl + 2)');
  if d2 = d then raise exception 'migration 20: pattern not found in ripples._tick_run'; end if;
  execute d2;
end $$;
