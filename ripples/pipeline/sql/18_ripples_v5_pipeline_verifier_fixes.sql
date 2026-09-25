-- Knock-On v5 / W2: migration ripples_v5_pipeline_verifier_fixes (applied 2026-09-25 after the independent verifier)
--  1. Fluke meter back to SPEC 5.2: "warming up" only while the pooled decoy pool has < 500 tests
--     (config.pipeline.fluke_warm_min_decoy = 500; it was raised to 2000 in sql/13, which hid measured rates of ~1 in 4).
--     config.pipeline.fluke_gate_fallback (default 0) is the SPEC 13 fallback switch for the LEAD only: when set to 1 the
--     answer gate f <= 0.10 is dropped (p_time <= 0.05 still applies) and the reveal prints the measured fluke rate.
--  2. Safety in daily running (SPEC 5.4): facts (P570, short description, P31, sitelinks) of every HUMAN that can be
--     shown are re-fetched from Wikidata/enwiki inside the run: new run stage-step before seeds (screened seed
--     candidates) and a new stage 'recheck' between expand and build (seeds, calm and passing candidates, reserve-bank
--     pages). ripples._fresh() makes a human that was not re-checked in this run ineligible as seed, option, Call It
--     or Board row. ripples._safe() also treats a human whose short description ends in a death year within the 60-day
--     window as unsafe even before Wikidata has P570. (Year/month-precision P570 now maps to the LAST possible day, kn.ts.)
--  3. Dispatch (SPEC 5.5 "depth 1 for all seeds and decoys, then deeper beams"): live run first, then newest as_of,
--     then job kind, then depth, then real before decoy. While today's live run is active no practice/backfill job is
--     started, and ripples_run_day defers new practice runs between 05:40 and 07:35 UTC.
--  4. Seed reuse (30 days) counts puzzles of the run's own kind only: practice/backfill days never use up live seeds.
--  5. Decoys (SPEC 12.3): the whole 90-day sparkline shown after the reveal must read flat: no day above
--     min(config.pipeline.decoy_max_spark_ratio 2.0, the answer's multiple) x the decoy's baseline median.
--  6. Board: 'belly_flop' only when the seed has no shown-level pass among ALL tested depth-1 neighbours and no puzzle
--     round (the K = 20 wake count itself is unchanged).
--  7. Wording (SPEC 12.1): evidence badge 'spiked_alongside' for lag-0 answers (reveal schema enum extended); template
--     headline "{seed}: which linked pages also spiked?" (no "next").
--  8. Expand cut-off for live runs moves to 07:16 so the recheck and build finish by the 07:20 hard deadline.
--  9. EXECUTE on every W2 helper in schema ripples is revoked from public/anon/authenticated (defence in depth).

update ripples.config set value = value || '{"fluke_warm_min_decoy":500,"fluke_gate_fallback":0,"decoy_max_spark_ratio":2.0,"recheck_per_job":400}'::jsonb
 where key = 'pipeline';

alter table ripples.runs drop constraint if exists runs_stage_check;
alter table ripples.runs add constraint runs_stage_check
  check (stage in ('collect_daily','resolve','screen','seeds','expand','recheck','build','done','delayed','failed'));

create or replace function ripples._safe(p_qid text, p_as_of date, p_median numeric default null, p_allow_sensitive boolean default false)
returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select not a.blocked and not a.is_disambig and not a.is_list
       and (p_allow_sensitive or not a.sensitive)
       and (a.date_of_death is null or a.date_of_death < p_as_of - 60)
       -- a death year in the enwiki short description ("American actor (1950–2026)") counts before Wikidata has P570
       and not (coalesce(a.is_human, false) and a.date_of_death is null
                and coalesce(substring(a.short_desc from '[0-9]{3,4}\s*[–—-]\s*([0-9]{4})\s*\)?\s*$')::int, 0) >= extract(year from p_as_of - 60))
       and not (a.is_human and coalesce(a.sitelinks, 0) <= 1 and coalesce(p_median, 0) < 20)
       and a.category is not null
       and not exists (select 1 from ripples.blocklist b where b.title_pattern is not null and b.action = 'block' and a.title_en ~* b.title_pattern)
       and not exists (select 1 from ripples.blocklist b where b.desc_pattern is not null and b.action = 'block' and coalesce(a.short_desc, '') ~* b.desc_pattern)
       and not exists (select 1 from ripples.blocklist b where b.qid = a.qid and b.action = 'block')
       and (p_allow_sensitive or not exists (select 1 from ripples.blocklist b where b.title_pattern is not null and b.action = 'sensitive' and a.title_en ~* b.title_pattern))
      from ripples.articles a where a.qid = p_qid), false)
$$;

-- a human's facts must have been re-fetched during this as_of's run (no run row: within the last 36 hours)
create or replace function ripples._fresh(p_qid text, p_as_of date) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select not coalesce(a.is_human, false)
        or a.updated_at >= coalesce((select r.started_at from ripples.runs r where r.as_of = p_as_of), now() - interval '36 hours')
      from ripples.articles a where a.qid = p_qid), false)
$$;

-- highest day of a sparkline relative to the page's baseline median
create or replace function ripples._spark_peak(p_spark int[], p_median numeric) returns numeric
language sql immutable set search_path = '' as $$
  select case when p_spark is null or cardinality(p_spark) = 0 then null
              else (select max(v) from unnest(p_spark) v)::numeric / greatest(coalesce(p_median, 0), 1) end
$$;

create or replace function ripples._pre_eligible(c ripples.candidates) returns boolean
language sql stable security definer set search_path = '' as $$
  select c.role = 'real' and not c.extra and c.pass_raw and c.p_time <= 0.05 and c.multiple >= 1.5 and coalesce(c.onset_lag, -1) >= 0
     and not c.main_page and c.linked
     and (select fl.warming or fl.f <= 0.10 or ripples._pcfg('fluke_gate_fallback', 0) = 1 from ripples._fluke(c.as_of, c.s_stat) fl)
     and ripples._safe(c.qid, c.as_of, c.median_views, false)
     and (c.depth = 1 or not ripples._shared_trigger(c))
$$;

drop function if exists ripples._pick_decoys(date, text, text, text, text[]);
create or replace function ripples._pick_decoys(p_as_of date, p_root text, p_parent text, p_answer text, p_exclude text[],
                                                p_fresh boolean default false)
returns text[]
language sql stable security definer set search_path = '' as $$
  with ans as (
    select c.qid, round(c.median_views) med, a.category, a.title_en, c.multiple amult
      from ripples.candidates c join ripples.articles a on a.qid = c.qid
     where c.as_of = p_as_of and c.role = 'real' and c.root_qid = p_root and c.parent_qid = p_parent and c.qid = p_answer
  ), sib as (
    select c.qid, (a.category = ans.category) same_cat, ripples._spark_peak(c.spark, c.median_views) peak,
           abs(ln(greatest(round(c.median_views), 1) / greatest(ans.med, 1))) dist
      from ans
      join ripples.candidates c on c.as_of = p_as_of and c.role = 'real' and c.root_qid = p_root and c.parent_qid = p_parent
      join ripples.articles a on a.qid = c.qid
     where c.qid <> ans.qid and c.calm and c.linked and c.spark is not null
       and abs(coalesce(c.max_abs_z, 9)) < 1 and c.multiple < 1.25
       and c.multiple >= ripples._pcfg('decoy_min_multiple', 0.67)
       -- SPEC 12.3: the 90-day sparkline shown after the reveal reads flat (no day above min(2.0, answer multiple) x normal)
       and ripples._spark_peak(c.spark, c.median_views) <= least(ripples._pcfg('decoy_max_spark_ratio', 2.0), ans.amult)
       and not (c.qid = any(coalesce(p_exclude, '{}')))
       and round(c.median_views) >= 0.5 * ans.med and round(c.median_views) <= 2 * ans.med
       and ripples._stem_ok(a.title_en, ans.title_en)
       and ripples._safe(c.qid, p_as_of, c.median_views, false)
       and (not p_fresh or ripples._fresh(c.qid, p_as_of))
  ), ranked as (
    select qid, same_cat, row_number() over (order by same_cat desc, round(peak, 1), dist, qid) rn from sib
  )
  select case when (select count(*) from ranked where same_cat) >= 2 and (select count(*) from ranked) >= 3
              then array(select qid from ranked order by rn limit 3) end
$$;

-- safety re-check jobs: humans that can be shown and whose facts were not fetched during this run
create or replace function ripples._enqueue_recheck(p_as_of date, p_phase text) returns int
language plpgsql security definer set search_path = '' as $$
declare since timestamptz; q jsonb; per int := greatest(50, ripples._pcfg('recheck_per_job', 400)::int); k int := 0; i int;
begin
  select r.started_at into since from ripples.runs r where r.as_of = p_as_of;
  since := coalesce(since, now());
  if p_phase = 'seeds' then
    select coalesce(jsonb_agg(distinct s.qid), '[]') into q
      from ripples.screen s join ripples.articles a on a.qid = s.qid
     where s.as_of = p_as_of and s.onset is not null and s.peak_multiple >= 3 and coalesce(a.is_human, false) and a.updated_at < since;
  else
    select coalesce(jsonb_agg(distinct x.qid), '[]') into q from (
      select s.qid from ripples.seeds s where s.as_of = p_as_of and s.role = 'real'
      union select c.qid from ripples.candidates c where c.as_of = p_as_of and c.role = 'real' and (c.calm or c.pass_raw)
      union select z.q from ripples.chains ch
              cross join lateral jsonb_array_elements(ch.rounds) r
              cross join lateral (select r->>'root' q union all select r->>'qid' union all select jsonb_array_elements_text(r->'decoys')) z
             where ch.used_n is null and ch.as_of between p_as_of - 14 and p_as_of - 1) x
      join ripples.articles a on a.qid = x.qid
     where coalesce(a.is_human, false) and a.updated_at < since;
  end if;
  for i in 0 .. greatest(0, (jsonb_array_length(q) - 1) / per) loop
    exit when jsonb_array_length(q) = 0;
    perform ripples._enqueue(p_as_of, 'resolve', null, null, null, null, null, null,
      jsonb_build_object('phase', p_phase, 'recheck', (select jsonb_agg(e) from jsonb_array_elements(q) with ordinality x(e, o)
                                                        where o > i * per and o <= (i + 1) * per)));
    k := k + 1;
  end loop;
  return k;
end $$;

create or replace function ripples._dispatch(p_max int default 6) returns int
language plpgsql security definer set search_path = '' as $$
declare j record; k int := 0; cap int; used int; run_api int; run_aqs int; max_api int; max_aqs int; max_tot int;
        bud int; fn text; nid bigint; live_active boolean;
begin
  if not pg_try_advisory_xact_lock(hashtext('ripples_dispatch')) then return 0; end if;
  cap := coalesce((ripples._cfg('wm_daily_cap') #>> '{}')::int, 6000);
  max_api := ripples._pcfg('max_running_api', 1);
  max_aqs := ripples._pcfg('max_running_aqs', 1);
  max_tot := ripples._pcfg('max_running_total', 1);
  -- today's live run has priority: while it is active, no practice / backfill job is started
  live_active := exists (select 1 from ripples.runs x where x.kind = 'live' and x.as_of >= (now() at time zone 'utc')::date - 1
                           and x.stage not in ('done','delayed','failed'));
  for j in
    select q.* from ripples.jobs q join ripples.runs r on r.as_of = q.as_of
     where q.status = 'queued' and (q.not_before is null or q.not_before <= now())
       and r.stage in ('collect_daily','resolve','screen','seeds','expand','recheck','build','done')
       and (r.kind = 'live' or not live_active)
     -- live first, newest day first, then stage order, then depth (depth 1 of every real seed AND decoy epicenter
     -- before any deeper beam, SPEC 5.5), real before decoy within a depth
     order by (r.kind = 'live') desc, q.as_of desc,
              case q.kind when 'collect' then 0 when 'resolve' then 1 when 'screen' then 2 when 'history' then 3
                          when 'split' then 4 when 'expand' then 5 else 6 end,
              q.depth nulls first, (q.role = 'decoy'), q.id
     for update of q skip locked
  loop
    exit when k >= p_max;
    select count(*) filter (where kind in ('collect','resolve','expand')), count(*) filter (where kind in ('screen','history','split','refresh'))
      into run_api, run_aqs from ripples.jobs where status = 'running';
    exit when run_api + run_aqs >= max_tot;
    if j.kind in ('collect','resolve','expand') and run_api >= max_api then continue; end if;
    if j.kind in ('screen','history','split','refresh') and run_aqs >= max_aqs then continue; end if;
    select r.wm_calls + coalesce((select sum(100) from ripples.jobs x where x.as_of = j.as_of and x.status = 'running'), 0)
      into used from ripples.runs r where r.as_of = j.as_of;
    bud := least(100, cap - coalesce(used, 0));
    if bud < 10 then
      if (select wm_calls from ripples.runs where as_of = j.as_of) >= cap - 10 then
        update ripples.jobs set status = 'skipped', error = 'wm_daily_cap reached', finished_at = now() where id = j.id;
      end if;
      continue;
    end if;
    fn := case j.kind when 'collect' then 'ripples-collect' when 'resolve' then 'ripples-resolve' else 'ripples-expand' end;
    update ripples.jobs set status = 'running', attempts = attempts + 1, started_at = now(), error = null where id = j.id;
    nid := public.call_collector(fn, ripples._job_payload(j.id, bud));
    update ripples.jobs set net_id = nid where id = j.id;
    k := k + 1;
  end loop;
  return k;
end $$;

create or replace function ripples._tick_run(p_as_of date) returns text
language plpgsql security definer set search_path = '' as $$
declare r ripples.runs; live boolean; t time := (now() at time zone 'utc')::time; n int; st text; guard int := 0;
        pending int; res jsonb; pz record; dl int := ripples._pcfg('practice_deadline_min', 22)::int;
begin
  loop
    guard := guard + 1;
    exit when guard > 8;
    select * into r from ripples.runs where as_of = p_as_of for update;
    if not found then return 'no run'; end if;
    live := r.kind = 'live';
    st := r.stage;
    select count(*) into pending from ripples.jobs where as_of = p_as_of and status in ('queued','running') and kind <> 'refresh';
    if st = 'collect_daily' then
      if not exists (select 1 from ripples.jobs where as_of = p_as_of and kind = 'collect') then
        if live and t < time '06:10' then return st; end if;
        perform ripples._enqueue(p_as_of, 'collect', null, null, null, null, null, null,
          jsonb_build_object('mode', case when live then 'daily' else 'date' end, 'date', p_as_of));
        return st;
      end if;
      if pending > 0 then return st; end if;
      update ripples.runs set stage = 'resolve', stage_at = now() where as_of = p_as_of;
    elsif st = 'resolve' then
      if live and t < time '06:25' then return st; end if;
      if not exists (select 1 from ripples.jobs where as_of = p_as_of and kind = 'resolve') then
        n := ripples._enqueue_resolve(p_as_of);
        update ripples.runs set detail = detail || jsonb_build_object('resolve_jobs', n) where as_of = p_as_of;
        if n > 0 then return st; end if;
      elsif pending > 0 then return st;
      end if;
      update ripples.runs set stage = 'screen', stage_at = now() where as_of = p_as_of;
    elsif st = 'screen' then
      if not exists (select 1 from ripples.jobs where as_of = p_as_of and kind = 'screen') then
        n := ripples._enqueue_screen(p_as_of);
        update ripples.runs set detail = detail || jsonb_build_object('screen_jobs', n) where as_of = p_as_of;
        if n > 0 then return st; end if;
      elsif pending > 0 then return st;
      end if;
      update ripples.runs set stage = 'seeds', stage_at = now() where as_of = p_as_of;
    elsif st = 'seeds' then
      -- SPEC 5.4 in daily running: re-fetch P570 / description of screened human seed candidates first
      if not exists (select 1 from ripples.jobs where as_of = p_as_of and kind = 'resolve' and payload->>'phase' = 'seeds') then
        n := ripples._enqueue_recheck(p_as_of, 'seeds');
        update ripples.runs set detail = detail || jsonb_build_object('recheck_seed_jobs', n) where as_of = p_as_of;
        if n > 0 then return st; end if;
      elsif pending > 0 and not (live and t >= time '06:50')
            and not (not live and now() - r.started_at > make_interval(mins => dl)) then
        return st;
      end if;
      res := public.ripples_pick_seeds(p_as_of);
      update ripples.runs set stage = 'expand', stage_at = now(), detail = detail || jsonb_build_object('seeds', res) where as_of = p_as_of;
      return 'expand';
    elsif st = 'expand' then
      perform ripples._advance_beams(p_as_of);
      select count(*) into pending from ripples.jobs where as_of = p_as_of and status in ('queued','running') and kind <> 'refresh';
      if (live and t >= time '07:16') or (not live and now() - r.started_at > make_interval(mins => dl)) then
        update ripples.jobs set status = 'skipped', error = 'expand deadline', finished_at = now()
         where as_of = p_as_of and status = 'queued' and kind <> 'refresh';
      elsif pending > 0 or (live and t < time '06:58') then
        return st;
      end if;
      update ripples.runs set stage = 'recheck', stage_at = now() where as_of = p_as_of;
    elsif st = 'recheck' then
      -- SPEC 5.4 in daily running: re-fetch facts of every human that can be shown (seeds, options, Call It, reserve)
      if not exists (select 1 from ripples.jobs where as_of = p_as_of and kind = 'resolve' and payload->>'phase' = 'build') then
        n := ripples._enqueue_recheck(p_as_of, 'build');
        update ripples.runs set detail = detail || jsonb_build_object('recheck_build_jobs', n) where as_of = p_as_of;
        if n > 0 then return st; end if;
      elsif pending > 0 and not ((live and t >= time '07:20') or (not live and now() - r.started_at > make_interval(mins => dl + 4))) then
        return st;
      end if;
      -- at the hard deadline: whatever was not re-checked is simply not eligible (ripples._fresh)
      update ripples.jobs set status = 'skipped', error = 'recheck deadline', finished_at = now()
       where as_of = p_as_of and status = 'queued' and kind <> 'refresh';
      update ripples.runs set stage = 'build', stage_at = now() where as_of = p_as_of;
    elsif st = 'build' then
      begin
        res := jsonb_build_object('fluke', public.ripples_update_fluke(p_as_of));
        res := res || jsonb_build_object('build', public.ripples_build_puzzle(p_as_of, r.kind));
        if live then res := res || jsonb_build_object('refresh_jobs', public.ripples_resolve_calls((now() at time zone 'utc')::date)); end if;
        update ripples.runs set stage = case when res->'build'->>'status' = 'delayed' then 'delayed' else 'done' end,
               stage_at = now(), finished_at = now(), detail = detail || res where as_of = p_as_of;
      exception when others then
        update ripples.runs set stage = 'failed', stage_at = now(), finished_at = now(), errors = errors + 1,
               detail = detail || jsonb_build_object('build_error', sqlerrm) where as_of = p_as_of;
      end;
      return 'built';
    elsif st = 'done' then
      -- a veto (W6, before 07:20) triggers a rebuild from the next chain or the reserve bank
      if live and t < time '07:20' then
        select * into pz from ripples.puzzles where kind = 'live' and data_date = p_as_of order by n desc limit 1;
        if found and pz.status = 'vetoed' then
          res := public.ripples_build_puzzle(p_as_of, 'live');
          update ripples.runs set detail = detail || jsonb_build_object('rebuild', res) where as_of = p_as_of;
        end if;
      end if;
      return st;
    else
      return st;
    end if;
  end loop;
  return (select stage from ripples.runs where as_of = p_as_of);
end $$;

create or replace function public.ripples_run_day(p_as_of date, p_kind text default 'practice', p_reset boolean default false)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r ripples.runs; v_n int; v_exists boolean; t time := (now() at time zone 'utc')::time; later jsonb;
begin
  if p_kind is distinct from 'practice' then raise exception 'ripples_run_day only runs practice (reconstructed) days; live runs are driven by ripples_tick'; end if;
  if p_as_of >= (now() at time zone 'utc')::date then raise exception 'as_of must be a complete past day'; end if;
  v_n := p_as_of - ripples._epoch();
  if v_n >= 0 then raise exception 'practice n = data_date - epoch must be negative (as_of < %)', ripples._epoch(); end if;
  select * into r from ripples.runs where as_of = p_as_of;
  v_exists := found;
  if v_exists and r.kind = 'live' then raise exception 'as_of % already has a live run', p_as_of; end if;
  if v_exists and not p_reset and r.stage in ('done','delayed','failed') then
    return jsonb_build_object('as_of', p_as_of, 'kind', 'practice', 'n', v_n, 'stage', r.stage, 'started_at', r.started_at,
      'finished_at', r.finished_at, 'note', 'already finished; pass p_reset => true to run it again');
  end if;
  -- the live run (06:10-07:20 UTC) has priority on the shared Wikimedia budget and the serial dispatcher
  if (not v_exists or p_reset) and t >= time '05:40' and t < time '07:35' then
    return jsonb_build_object('as_of', p_as_of, 'kind', 'practice', 'n', v_n, 'deferred', true,
      'note', 'practice/backfill runs do not start between 05:40 and 07:35 UTC (live run window); call again after 07:35');
  end if;
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
  -- later days whose pooled fluke rates included this day's counts (rerun them, oldest first, to reproduce)
  select jsonb_agg(distinct f.as_of) into later from ripples.fluke_rates f where f.as_of > p_as_of and f.as_of <= p_as_of + 89;
  if not v_exists then
    insert into ripples.runs (as_of, kind, stage) values (p_as_of, 'practice', 'collect_daily');
  end if;
  if not exists (select 1 from cron.job where jobname = 'ripples-run-day') then
    perform cron.schedule('ripples-run-day', '20 seconds', 'select public.ripples_tick()');
  end if;
  select * into r from ripples.runs where as_of = p_as_of;
  return jsonb_build_object('as_of', p_as_of, 'kind', 'practice', 'n', v_n, 'stage', r.stage, 'started_at', r.started_at,
    'poll', format('select stage, wm_calls, errors, detail from ripples.runs where as_of = %L', p_as_of))
    || case when p_reset and later is not null then jsonb_build_object('stale_later_days', later) else '{}'::jsonb end;
end $$;

-- in-place patch of public.ripples_pick_seeds (the live bodies were applied without comments, so the match is whitespace-tolerant)
do $$
declare d text; d2 text; n int;
begin
  select pg_get_functiondef('public.ripples_pick_seeds(date)'::regprocedure) into d;
  d2 := regexp_replace(d, $p$used\s+text\[\]\s+:=\s+'\{\}';\s+kr\s+int\s+:=\s+0;$p$, $r$v_kind text := coalesce((select kind from ripples.runs where as_of = p_as_of), 'live');
        used text[] := '{}'; kr int := 0;$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in public.ripples_pick_seeds: %', $m$used text[] := '{}'; kr int := 0;$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$and\s+ripples\._safe\(s\.qid,\s+p_as_of,\s+s\.median_views,\s+true\)$p$, $r$and ripples._safe(s.qid, p_as_of, s.median_views, true) and ripples._fresh(s.qid, p_as_of)$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in public.ripples_pick_seeds: %', $m$and ripples._safe(s.qid, p_as_of, s.median_views, true)$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$where\s+p\.kind\s+in\s+\('live','practice'\)\s+and\s+p\.data_date\s+between\s+p_as_of\s+\-\s+30\s+and\s+p_as_of\s+\-\s+1$p$, $r$where p.kind = v_kind and p.status <> 'delayed' and p.data_date between p_as_of - 30 and p_as_of - 1$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in public.ripples_pick_seeds: %', $m$where p.kind in ('live','practice') and p.data_date between $m$; end if;
  d := d2;
  execute d;
end $$;

-- in-place patch of public.ripples_build_puzzle (the live bodies were applied without comments, so the match is whitespace-tolerant)
do $$
declare d text; d2 text; n int;
begin
  select pg_get_functiondef('public.ripples_build_puzzle(date,text)'::regprocedure) into d;
  d2 := regexp_replace(d, $p$and\s+exists\s+\(select\s+1\s+from\s+ripples\.seeds\s+s\s+where\s+s\.as_of\s+=\s+p_as_of\s+and\s+s\.role\s+=\s+'real'\s+and\s+s\.qid\s+=\s+c\.root_qid\s+and\s+ripples\._safe\(s\.qid,\s+p_as_of,\s+s\.median_views,\s+false\)\)\s+and\s+ripples\._pick_decoys\(p_as_of,\s+c\.root_qid,\s+c\.parent_qid,\s+c\.qid,\s+array\[c\.root_qid,\s+c\.parent_qid\]\)\s+is\s+not\s+null;$p$, $r$and ripples._fresh(c.qid, p_as_of)
     and exists (select 1 from ripples.seeds s where s.as_of = p_as_of and s.role = 'real' and s.qid = c.root_qid
                   and ripples._safe(s.qid, p_as_of, s.median_views, false) and ripples._fresh(s.qid, p_as_of))
     and ripples._pick_decoys(p_as_of, c.root_qid, c.parent_qid, c.qid, array[c.root_qid, c.parent_qid], true) is not null;$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in public.ripples_build_puzzle: %', $m$and exists (select 1 from ripples.seeds s where s.as_of = p_$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$ripples\._pick_decoys\(p_as_of,\s+best\.root,\s+best\.parents\[k\],\s+best\.path\[k\],\s+used\s+\|\|\s+best\.path\)$p$, $r$ripples._pick_decoys(p_as_of, best.root, best.parents[k], best.path[k], used || best.path, true)$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in public.ripples_build_puzzle: %', $m$ripples._pick_decoys(p_as_of, best.root, best.parents[k], be$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$ripples\._pick_decoys\(p_as_of,\s+hop\.root,\s+hop\.parent,\s+hop\.qid,\s+used\s+\|\|\s+hop\.root\)$p$, $r$ripples._pick_decoys(p_as_of, hop.root, hop.parent, hop.qid, used || hop.root, true)$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in public.ripples_build_puzzle: %', $m$ripples._pick_decoys(p_as_of, hop.root, hop.parent, hop.qid,$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$ripples\._pick_decoys\(p_as_of,\s+alt_c\.root,\s+alt_c\.parents\[k\],\s+alt_c\.path\[k\],\s+u2\s+\|\|\s+alt_c\.path\)$p$, $r$ripples._pick_decoys(p_as_of, alt_c.root, alt_c.parents[k], alt_c.path[k], u2 || alt_c.path, true)$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in public.ripples_build_puzzle: %', $m$ripples._pick_decoys(p_as_of, alt_c.root, alt_c.parents[k], $m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$order\s+by\s+c\.as_of\s+desc,\s+c\.score\s+desc\s+limit\s+1;$p$, $r$  and not exists (select 1 from jsonb_array_elements(c.rounds) r
                      cross join lateral (select r->>'root' q union all select r->>'qid' union all select jsonb_array_elements_text(r->'decoys')) z
                      where not ripples._safe(z.q, p_as_of, (select max(x.median_views) from ripples.candidates x where x.as_of = c.as_of and x.qid = z.q), false)
                         or not ripples._fresh(z.q, p_as_of))
   order by c.as_of desc, c.score desc limit 1;$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in public.ripples_build_puzzle: %', $m$order by c.as_of desc, c.score desc limit 1;$m$; end if;
  d := d2;
  execute d;
end $$;

-- in-place patch of ripples._render (the live bodies were applied without comments, so the match is whitespace-tolerant)
do $$
declare d text; d2 text; n int;
begin
  select pg_get_functiondef('ripples._render(integer,text,date,date,date,date,jsonb,text,bigint)'::regprocedure) into d;
  d2 := regexp_replace(d, $p$then\s+'flowed'\s+else\s+'spiked_after'\s+end,$p$, $r$then 'flowed' when ans.onset_lag = 0 then 'spiked_alongside' else 'spiked_after' end,$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in ripples._render: %', $m$then 'flowed' else 'spiked_after' end,$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$headline\s+:=\s+left\(seed\.title_en\s+\|\|\s+':\s+which\s+linked\s+pages\s+spiked\s+next\?',\s+70\);\s+if\s+length\(seed\.title_en\s+\|\|\s+':\s+which\s+linked\s+pages\s+spiked\s+next\?'\)\s+>\s+70\s+then\s+headline\s+:=\s+'One\s+trend\.\s+Which\s+linked\s+pages\s+spiked\s+next\?';\s+end\s+if;$p$, $r$headline := seed.title_en || ': which linked pages also spiked?';
  if length(headline) > 70 then headline := 'One trend. Which linked pages also spiked?'; end if;$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in ripples._render: %', $m$headline := left(seed.title_en || ': which linked pages spik$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$and\s+ripples\._safe\(c\.qid,\s+p_data_as_of,\s+c\.median_views,\s+false\)\)\s+c$p$, $r$and ripples._safe(c.qid, p_data_as_of, c.median_views, false) and ripples._fresh(c.qid, p_data_as_of)) c$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in ripples._render: %', $m$and ripples._safe(c.qid, p_data_as_of, c.median_views, false$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$least\(20,\s+count\(\*\)\)::int\s+tested$p$, $r$least(20, count(*))::int tested,
                 (select count(*) from ripples.candidates c3 cross join lateral ripples._fluke(c3.as_of, c3.s_stat) f3
                   where c3.as_of = s.as_of and c3.role = 'real' and c3.root_qid = s.qid and c3.parent_qid = s.qid and c3.depth = 1
                     and not c3.extra and c3.pass_raw
                     and ((f3.warming and c3.p_time <= 0.05) or (not f3.warming and c3.p_time <= 0.10 and f3.f <= 0.20)))::int any_shown$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in ripples._render: %', $m$least(20, count(*))::int tested$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$when\s+s\.peak_multiple\s+>=\s+10\s+and\s+w\.k\s+=\s+0\s+and\s+w\.tested\s+>=\s+15\s+then\s+'belly_flop'$p$, $r$when s.peak_multiple >= 10 and w.k = 0 and w.tested >= 15 and w.any_shown = 0 and not exists (select 1 from jsonb_array_elements(p_rounds) pr where pr->>'root' = s.qid) then 'belly_flop'$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in ripples._render: %', $m$when s.peak_multiple >= 10 and w.k = 0 and w.tested >= 15 th$m$; end if;
  d := d2;
  d2 := regexp_replace(d, $p$and\s+ripples\._safe\(s\.qid,\s+p_board_as_of,\s+s\.median_views,\s+true\)$p$, $r$and ripples._safe(s.qid, p_board_as_of, s.median_views, true) and ripples._fresh(s.qid, p_board_as_of)$r$);
  if d2 = d then raise exception 'migration 18: pattern not found in ripples._render: %', $m$and ripples._safe(s.qid, p_board_as_of, s.median_views, true$m$; end if;
  d := d2;
  execute d;
end $$;

-- defence in depth: no W2 helper is executable by PUBLIC (anon/authenticated also lack USAGE on schema ripples)
do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p
     where p.pronamespace = 'ripples'::regnamespace
       and p.proname in ('_advance_beams','_caption','_class_category','_classify','_dispatch','_emoji','_enqueue','_enqueue_resolve',
                         '_enqueue_screen','_enqueue_recheck','_flat30','_fluke','_fresh','_job_payload','_pcfg','_pick_decoys',
                         '_pre_eligible','_qnorm','_rederive_classes','_refresh_articles','_render','_safe','_sbin','_seed_sources',
                         '_shared_trigger','_spark_peak','_stem_ok','_text_category','_text_flag','_tick_run')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $$;
revoke all on function public.ripples_run_day(date, text, boolean) from public, anon, authenticated;
grant execute on function public.ripples_run_day(date, text, boolean) to service_role;
notify pgrst, 'reload schema';
