-- Knock-On v5 / W2: migration ripples_v5_pipeline_decoy_spark (in-place patch of ripples._pick_decoys)
-- SPEC 12.3 "decoys are shown with their flat sparklines": the 90-day sparkline of a decoy may not reach
--   min(config.pipeline.decoy_max_spark_ratio, config.pipeline.decoy_max_spark_frac x the answer's multiple)
-- times the decoy's baseline median on any day. Defaults 3.0 and 0.75: no decoy day at 3x normal or more, and the
-- answer's peak always stands at least a third above every decoy day on the shared "x normal" scale. (sql/18 used a flat
-- 2.0 cap; on the 2026-09-23/24 data that left no hop with 3 usable decoys at all.)
update ripples.config set value = value || '{"decoy_max_spark_ratio":3.0,"decoy_max_spark_frac":0.75}'::jsonb where key = 'pipeline';
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('ripples._pick_decoys(date,text,text,text,text[],boolean)'::regprocedure) into d;
  d2 := replace(d, 'least(ripples._pcfg(''decoy_max_spark_ratio'', 2.0), ans.amult)',
                   'least(ripples._pcfg(''decoy_max_spark_ratio'', 3.0), ripples._pcfg(''decoy_max_spark_frac'', 0.75) * ans.amult)');
  if d2 = d then raise exception 'migration 21: pattern not found in ripples._pick_decoys'; end if;
  execute d2;
end $$;
