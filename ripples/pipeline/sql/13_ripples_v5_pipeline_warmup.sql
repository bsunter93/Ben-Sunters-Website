-- Knock-On v5 / W2: migration ripples_v5_pipeline_warmup (in-place patch of one function body)
-- 1. ripples._fluke: the fluke meter is "warming up" while the pooled decoy pool has fewer than
--    config.pipeline.fluke_warm_min_decoy tests (default 500 as SPEC 5.2; set to 2000). With the first two practice
--    days (660 decoy tests) the pooled S >= 6 bin rested on 4 decoy passes, i.e. an estimate between ~0.04 and ~0.35.
--    While warming, a hop needs p_time <= 0.05 (SPEC 5.2) and the reveal says "fluke meter warming up".
update ripples.config set value = value || '{"fluke_warm_min_decoy":2000}'::jsonb where key = 'pipeline';
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('ripples._fluke(date,numeric)'::regprocedure) into d;
  d2 := replace(d, 'r.decoy_tested < 500 or r.fluke is null', 'r.decoy_tested < ripples._pcfg(''fluke_warm_min_decoy'', 500) or r.fluke is null');
  if d2 = d and position('fluke_warm_min_decoy' in d) = 0 then raise exception '_fluke patch did not apply'; end if;
  if d2 <> d then execute d2; end if;
end $$;
