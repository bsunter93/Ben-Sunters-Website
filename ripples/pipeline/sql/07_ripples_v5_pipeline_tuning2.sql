-- Knock-On v5 / W2: migration ripples_v5_pipeline_tuning2 (applied as an in-place patch of two function bodies)
-- 1. ripples_build_puzzle: a live puzzle may draw on unused compositions from practice (reconstructed) runs in the
--    reserve bank; from_date still shows the real date.
-- 2. ripples._enqueue_resolve: resolve en top-per-country titles down to rank 200 (steady pages feed the decoy pool).
-- The files 03/04 already contain the patched text; the guarded block below is a no-op on a fresh install.
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('public.ripples_build_puzzle(date,text)'::regprocedure) into d;
  d2 := replace(d, 'c.used_n is null and c.kind = p_kind and c.as_of between', 'c.used_n is null and (c.kind = p_kind or p_kind = ''live'') and c.as_of between');
  if d2 <> d then execute d2; end if;
  select pg_get_functiondef('ripples._enqueue_resolve(date)'::regprocedure) into d;
  d2 := replace(d, '(t.source = ''topcountry'' and t.rank <= 100)', '(t.source = ''topcountry'' and (t.rank <= 100 or (t.lang = ''en'' and t.rank <= 200)))');
  if d2 <> d then execute d2; end if;
end $$;
