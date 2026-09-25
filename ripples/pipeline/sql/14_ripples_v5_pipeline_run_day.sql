-- Knock-On v5 / W2: migration ripples_v5_pipeline_run_day
-- ripples_run_day: p_reset also removes that day's unpublished practice puzzle, its Call It and template copy rows
-- (a rerun that ends "delayed" must not leave a puzzle built from deleted candidates); calling it for a day that has
-- already finished (done / delayed / failed) without p_reset reports the finished run and starts nothing.
create or replace function public.ripples_run_day(p_as_of date, p_kind text default 'practice', p_reset boolean default false)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r ripples.runs; v_n int; v_exists boolean;
begin
  if p_kind is distinct from 'practice' then raise exception 'ripples_run_day only runs practice (reconstructed) days; live runs are driven by ripples_tick'; end if;
  if p_as_of >= (now() at time zone 'utc')::date then raise exception 'as_of must be a complete past day'; end if;
  v_n := p_as_of - ripples._epoch();
  if v_n >= 0 then raise exception 'practice n = data_date - epoch must be negative (as_of < %)', ripples._epoch(); end if;
  select * into r from ripples.runs where as_of = p_as_of;
  v_exists := found;
  if v_exists and r.kind = 'live' then raise exception 'as_of % already has a live run', p_as_of; end if;
  if v_exists and p_reset then
    delete from ripples.jobs where as_of = p_as_of;
    delete from ripples.screen where as_of = p_as_of;
    delete from ripples.seeds where as_of = p_as_of;
    delete from ripples.candidates where as_of = p_as_of;
    delete from ripples.chains where as_of = p_as_of;
    delete from ripples.fluke_rates where as_of = p_as_of;
    delete from ripples.runs where as_of = p_as_of;
    if exists (select 1 from ripples.puzzles where puzzles.n = v_n and puzzles.kind = 'practice' and puzzles.status <> 'published') then
      delete from ripples.callit where callit.n = v_n;
      delete from ripples.copy where copy.n = v_n;
      delete from ripples.puzzles where puzzles.n = v_n;
    end if;
    v_exists := false;
  end if;
  if v_exists and r.stage in ('done','delayed','failed') then
    return jsonb_build_object('as_of', p_as_of, 'kind', 'practice', 'n', v_n, 'stage', r.stage, 'started_at', r.started_at,
      'finished_at', r.finished_at, 'note', 'already finished; pass p_reset => true to run it again');
  end if;
  if not v_exists then
    insert into ripples.runs (as_of, kind, stage) values (p_as_of, 'practice', 'collect_daily');
  end if;
  if not exists (select 1 from cron.job where jobname = 'ripples-run-day') then
    perform cron.schedule('ripples-run-day', '20 seconds', 'select public.ripples_tick()');
  end if;
  select * into r from ripples.runs where as_of = p_as_of;
  return jsonb_build_object('as_of', p_as_of, 'kind', 'practice', 'n', v_n, 'stage', r.stage, 'started_at', r.started_at,
    'poll', format('select stage, wm_calls, errors, detail from ripples.runs where as_of = %L', p_as_of));
end $$;
revoke execute on function public.ripples_run_day(date, text, boolean) from public, anon, authenticated;
grant execute on function public.ripples_run_day(date, text, boolean) to service_role;
