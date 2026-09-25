-- Knock-On v5 / W2: migration ripples_v5_pipeline_tuning3 (in-place patches of two function bodies)
-- 1. ripples._advance_beams: deeper beams only continue from hops that can be puzzle rounds (3 calm decoys exist);
--    a chain needs every hop usable, so expanding from an unusable hop only spends Wikimedia calls.
-- 2. ripples._tick_run: practice runs build after config.pipeline.practice_deadline_min (22) minutes even if deeper
--    beams are still queued (the practice analogue of the live 07:20 deadline).
update ripples.config set value = value || '{"practice_deadline_min":22}'::jsonb where key = 'pipeline';
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('ripples._advance_beams(date)'::regprocedure) into d;
  d2 := replace(d, '           and c.split_ok and ripples._pre_eligible(c)
           and c.qid <> r.root_qid',
                   '           and c.split_ok and ripples._pre_eligible(c)
           and ripples._pick_decoys(p_as_of, c.root_qid, c.parent_qid, c.qid, array[c.root_qid, c.parent_qid]) is not null
           and c.qid <> r.root_qid');
  if d2 = d and position('_pick_decoys(p_as_of, c.root_qid' in d) = 0 then raise exception 'advance_beams patch did not apply'; end if;
  if d2 <> d then execute d2; end if;
  select pg_get_functiondef('ripples._tick_run(date)'::regprocedure) into d;
  d2 := replace(d, '      if live and t >= time ''07:20'' then',
                   '      if (live and t >= time ''07:20'') or (not live and now() - r.started_at > make_interval(mins => ripples._pcfg(''practice_deadline_min'', 22)::int)) then');
  if d2 = d and position('practice_deadline_min' in d) = 0 then raise exception 'tick_run patch did not apply'; end if;
  if d2 <> d then execute d2; end if;
end $$;
