-- Knock-On v5 / W2: migration ripples_v5_pipeline_delayed_row (in-place patch of ripples_build_puzzle)
-- A rebuild that ends "delayed" must not leave an earlier composition for the same n behind (it may contain a page
-- that has since become unsafe): an unpublished practice puzzle is removed with its Call It and copy rows; a live
-- puzzle still in status 'built' becomes 'delayed' (never published; a vetoed row stays 'vetoed').
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('public.ripples_build_puzzle(date,text)'::regprocedure) into d;
  d2 := replace(d, $x$
  return jsonb_build_object('n', v_n, 'status', 'delayed', 'hops'$x$, $x$
  if p_kind = 'practice' then
    if exists (select 1 from ripples.puzzles z where z.n = v_n and z.kind = 'practice' and z.status <> 'published') then
      delete from ripples.callit z where z.n = v_n;
      delete from ripples.copy z where z.n = v_n;
      delete from ripples.puzzles z where z.n = v_n;
    end if;
  else
    update ripples.puzzles z set status = 'delayed' where z.n = v_n and z.kind = 'live' and z.status = 'built';
  end if;
  return jsonb_build_object('n', v_n, 'status', 'delayed', 'hops'$x$);
  if d2 = d and position('z.status = ''built''' in d) = 0 then raise exception 'build_puzzle patch did not apply'; end if;
  if d2 <> d then execute d2; end if;
end $$;
