-- Knock-On v5 / W2: migration ripples_v5_pipeline_stages
-- Stage functions: resolve/screen enqueueing, seed picking, beams, fluke rates, Call It resolution, retention,
-- the ripples_tick() state machine and the ripples_run_day() driver.

-- ------------------------------------------------------------------ fluke lookup
-- Fluke rate for a hop's S-bin from the newest fluke_rates row on or before p_as_of (within 7 days).
create or replace function ripples._fluke(p_as_of date, p_s numeric)
returns table (f numeric, warming boolean, one_in int)
language sql stable security definer set search_path = '' as $$
  with r as (
    select fr.* from ripples.fluke_rates fr
     where fr.sbin = ripples._sbin(p_s) and fr.as_of <= p_as_of and fr.as_of >= p_as_of - 7
     order by fr.as_of desc limit 1)
  select (select r.fluke from r),
         coalesce((select r.decoy_tested < 500 or r.fluke is null from r), true),
         (select case when r.fluke is null then null when r.fluke <= 0.02 then 50 else least(50, floor(1 / r.fluke))::int end from r)
$$;

-- Shared-trigger flag (depth >= 2): the candidate is in the seed's own depth-1 candidate set, or it is a passing hop
-- for another of today's seeds with an earlier onset.
create or replace function ripples._shared_trigger(c ripples.candidates) returns boolean
language sql stable security definer set search_path = '' as $$
  select c.depth >= 2 and (
    exists (select 1 from ripples.candidates d where d.as_of = c.as_of and d.role = 'real' and d.root_qid = c.root_qid
              and d.depth = 1 and d.qid = c.qid)
    or exists (select 1 from ripples.candidates o
                 join ripples.seeds so on so.as_of = o.as_of and so.qid = o.root_qid and so.role = 'real'
                 join ripples.seeds sc on sc.as_of = c.as_of and sc.qid = c.root_qid and sc.role = 'real'
                where o.as_of = c.as_of and o.role = 'real' and o.root_qid <> c.root_qid and o.qid = c.qid and o.pass_raw
                  and so.onset < sc.onset))
$$;

-- Answer-eligibility before the desktop/mobile split (SPEC §5.2): pass_raw, p_time <= 0.05, f <= 0.10 (or the fluke
-- meter is warming up), not a Main Page feature, linked, safe (no sensitive), and at depth >= 2 no shared trigger.
create or replace function ripples._pre_eligible(c ripples.candidates) returns boolean
language sql stable security definer set search_path = '' as $$
  select c.role = 'real' and c.pass_raw and c.p_time <= 0.05 and c.multiple >= 1.5 and coalesce(c.onset_lag, -1) >= 0
     and not c.main_page and c.linked
     and (select fl.warming or fl.f <= 0.10 from ripples._fluke(c.as_of, c.s_stat) fl)
     and ripples._safe(c.qid, c.as_of, c.median_views, false)
     and (c.depth = 1 or not ripples._shared_trigger(c))
$$;

-- ------------------------------------------------------------------ resolve / screen enqueueing
create or replace function ripples._enqueue_resolve(p_as_of date) returns int
language plpgsql security definer set search_path = '' as $$
declare per_t int := ripples._pcfg('resolve_titles_per_job', 150); per_q int := ripples._pcfg('resolve_queries_per_job', 40);
        max_t int := ripples._pcfg('resolve_max_titles', 1500); max_q int := ripples._pcfg('resolve_max_queries', 160);
        items jsonb; qs jsonb; k int := 0; i int;
begin
  with src as (
    select t.lang, t.query title, min(t.rank) rk, count(*) n from ripples.trend_obs t
     where t.day between p_as_of - 2 and p_as_of + 1 and t.lang ~ '^[a-z]{2,3}$'
       and ((t.source = 'topcountry' and (t.rank <= 100 or (t.lang = 'en' and t.rank <= 200))) or (t.source = 'wikitop' and t.rank <= 60) or t.source = 'featured')
     group by 1, 2
    union all
    select split_part(w.project, '.', 1), replace(w.article, '_', ' '), min(w.rank), count(*) from public.wiki_top w
     where w.day between p_as_of - 2 and p_as_of and w.rank <= 60 and w.project ~ '^[a-z]{2,3}\.wikipedia$'
     group by 1, 2
  ), t as (
    select lang, title, min(rk) rk, sum(n) n from src group by 1, 2
  ), todo as (
    select t.* from t
     where not exists (select 1 from ripples.title_map m where m.lang = t.lang and m.title = t.title
                         and m.resolved_at > now() - interval '30 days')
     order by (t.lang = 'en') desc, t.n desc, t.rk, t.title
     limit max_t
  )
  select coalesce(jsonb_agg(jsonb_build_object('lang', lang, 'title', title) order by lang, title), '[]') into items from todo;
  for i in 0 .. greatest(0, (jsonb_array_length(items) - 1) / per_t) loop
    exit when jsonb_array_length(items) = 0;
    perform ripples._enqueue(p_as_of, 'resolve', null, null, null, null, null, null,
      jsonb_build_object('items', (select jsonb_agg(e) from jsonb_array_elements(items) with ordinality x(e, o)
                                    where o > i * per_t and o <= (i + 1) * per_t)));
    k := k + 1;
  end loop;

  with q as (
    select t.lang, ripples._qnorm(t.query) q, min(t.rank) rk from ripples.trend_obs t
     where t.source = 'gtrends' and t.day between p_as_of - 2 and p_as_of + 1 and t.lang is not null
     group by 1, 2
  ), todo as (
    select * from q where not exists (select 1 from ripples.title_map m where m.lang = 'q:' || q.lang and m.title = q.q
                                        and m.resolved_at > now() - interval '30 days')
     order by rk, q limit max_q
  )
  select coalesce(jsonb_agg(jsonb_build_object('lang', lang, 'q', q)), '[]') into qs from todo;
  for i in 0 .. greatest(0, (jsonb_array_length(qs) - 1) / per_q) loop
    exit when jsonb_array_length(qs) = 0;
    perform ripples._enqueue(p_as_of, 'resolve', null, null, null, null, null, null,
      jsonb_build_object('queries', (select jsonb_agg(e) from jsonb_array_elements(qs) with ordinality x(e, o)
                                      where o > i * per_q and o <= (i + 1) * per_q)));
    k := k + 1;
  end loop;
  return k;
end $$;

-- Seed-source appearances per QID in [as_of-2, as_of+1] (source:geo labels, best rank, languages).
create or replace function ripples._seed_sources(p_as_of date)
returns table (qid text, sources text[], nsrc int, best_rank int, langs int, featured_geos text[])
language sql stable security definer set search_path = '' as $$
  with obs as (
    select coalesce(t.qid, m.qid) qid, t.source, t.geo, t.lang, t.rank, t.day from ripples.trend_obs t
      left join ripples.title_map m
        on m.lang = case when t.source = 'gtrends' then 'q:' || t.lang else t.lang end
       and m.title = case when t.source = 'gtrends' then ripples._qnorm(t.query) else t.query end
     where t.day between p_as_of - 2 and p_as_of + 1 and t.source in ('gtrends','topcountry','wikitop','featured')
    union all
    select m.qid, 'wikitop', split_part(w.project, '.', 1), split_part(w.project, '.', 1), w.rank, w.day
      from public.wiki_top w
      join ripples.title_map m on m.lang = split_part(w.project, '.', 1) and m.title = replace(w.article, '_', ' ')
     where w.day between p_as_of - 2 and p_as_of
  )
  select qid,
         array_agg(distinct source || coalesce(':' || geo, '')),
         count(distinct source || coalesce(':' || geo, ''))::int,
         min(rank)::int,
         greatest(1, count(distinct lang) filter (where source in ('topcountry','wikitop','featured')))::int,
         array_agg(distinct geo) filter (where source = 'featured')
    from obs where qid is not null group by qid
$$;

create or replace function ripples._enqueue_screen(p_as_of date) returns int
language plpgsql security definer set search_path = '' as $$
declare per int := ripples._pcfg('screen_per_job', 80); mx int := ripples._pcfg('screen_titles', 240); items jsonb; k int := 0; i int;
begin
  with s as (
    select ss.qid, a.title_en, ss.nsrc, ss.best_rank from ripples._seed_sources(p_as_of) ss
      join ripples.articles a on a.qid = ss.qid
     where not a.is_disambig and not a.is_list and not a.blocked
       and not exists (select 1 from ripples.screen x where x.as_of = p_as_of and x.qid = ss.qid)
     order by ss.nsrc desc, ss.best_rank, ss.qid
     limit mx
  )
  select coalesce(jsonb_agg(jsonb_build_object('qid', qid, 'title', title_en) order by nsrc desc, best_rank), '[]') into items from s;
  for i in 0 .. greatest(0, (jsonb_array_length(items) - 1) / per) loop
    exit when jsonb_array_length(items) = 0;
    perform ripples._enqueue(p_as_of, 'screen', null, null, null, null, null, null,
      jsonb_build_object('items', (select jsonb_agg(e) from jsonb_array_elements(items) with ordinality x(e, o)
                                    where o > i * per and o <= (i + 1) * per)));
    k := k + 1;
  end loop;
  return k;
end $$;

-- ------------------------------------------------------------------ seeds
-- SPEC §5.2: real seeds (top 12 by sources count, z_peak) and 8 decoy epicenters matched on baseline-median decile
-- and category with |z| < 1 over the last 14 days. Enqueues depth-1 expand jobs (real + decoy) and one history job.
create or replace function public.ripples_pick_seeds(p_as_of date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare nreal int := ripples._pcfg('seeds_real', 12); ndec int := ripples._pcfg('seeds_decoy', 8); r record; d record;
        used text[] := '{}'; kr int := 0; kd int := 0; hist jsonb;
begin
  delete from ripples.seeds where as_of = p_as_of;
  -- real seeds
  insert into ripples.seeds (as_of, qid, role, title, onset, peak_multiple, z_peak, median_views, langs, sources, spark, baseline, rank)
  select p_as_of, x.qid, 'real', x.title_en, x.onset, x.peak_multiple, x.z_peak, x.median_views, x.langs, x.sources, x.spark,
         jsonb_build_object('from', x.base_from, 'to', x.base_to, 'median', round(x.median_views)), x.rk
    from (
      select s.*, a.title_en, ss.langs, ss.sources, row_number() over (order by ss.nsrc desc, s.z_peak desc, s.qid) rk
        from ripples.screen s
        join ripples.articles a on a.qid = s.qid
        join ripples._seed_sources(p_as_of) ss on ss.qid = s.qid
       where s.as_of = p_as_of and s.onset is not null and s.peak_multiple >= 3
         and ripples._safe(s.qid, p_as_of, s.median_views, true)
         -- not a puzzle seed in the last 30 days
         and not exists (select 1 from ripples.puzzles p
                          where p.kind in ('live','practice') and p.data_date between p_as_of - 30 and p_as_of - 1
                            and (p.payload->'seed'->>'qid' = s.qid
                                 or exists (select 1 from jsonb_array_elements(p.payload->'rounds') rr where rr->'seed'->>'qid' = s.qid)))
         -- not only a Main Page feature (TFA / DYK / OTD on the onset day with fewer than 2 other sources)
         and not (exists (select 1 from ripples.trend_obs t
                           where t.source = 'featured' and t.geo in ('tfa','dyk','onthisday') and t.day = s.onset
                             and (t.qid = s.qid or t.query = a.title_en))
                  and (select count(*) from unnest(ss.sources) src where src not like 'featured:%') < 2)
    ) x
   where x.rk <= nreal;
  get diagnostics kr = row_count;

  -- decoy epicenters: calm screened pages, matched 1:1 to the top real seeds on median decile and category
  for r in
    with pool as (
      select s.qid, s.title, s.median_views, a.category, ntile(10) over (order by s.median_views) dec
        from ripples.screen s join ripples.articles a on a.qid = s.qid
       where s.as_of = p_as_of and s.median_views is not null)
    select se.qid, se.onset, p.dec, a.category from ripples.seeds se
      join ripples.articles a on a.qid = se.qid
      left join pool p on p.qid = se.qid
     where se.as_of = p_as_of and se.role = 'real' order by se.rank limit ndec
  loop
    select c.* into d from (
      select s.qid, s.title, s.median_views, a.category, ntile(10) over (order by s.median_views) dec, s.max_abs_z14
        from ripples.screen s join ripples.articles a on a.qid = s.qid
       where s.as_of = p_as_of and s.median_views is not null) c
     where c.max_abs_z14 < 1 and not (c.qid = any(used))
       and not exists (select 1 from ripples.seeds x where x.as_of = p_as_of and x.qid = c.qid)
       and ripples._safe(c.qid, p_as_of, c.median_views, false)
     order by abs(c.dec - coalesce(r.dec, 5)), (c.category is distinct from r.category), c.qid
     limit 1;
    if found then
      insert into ripples.seeds (as_of, qid, role, title, onset, median_views, matched_to, rank)
      values (p_as_of, d.qid, 'decoy', d.title, r.onset, d.median_views, r.qid, kd + 1);
      used := used || d.qid;
      kd := kd + 1;
    end if;
  end loop;

  -- depth-1 expand jobs (identical code for real and decoy) + one history job for the real seeds
  for r in select s.*, a.title_en from ripples.seeds s join ripples.articles a on a.qid = s.qid
            where s.as_of = p_as_of order by (s.role = 'decoy'), s.rank loop
    perform ripples._enqueue(p_as_of, 'expand', r.role, r.qid, r.qid, r.title_en, r.onset, 1, '{}');
  end loop;
  select jsonb_agg(jsonb_build_object('qid', s.qid, 'title', a.title_en, 'onset', s.onset, 'as_of', p_as_of) order by s.rank)
    into hist from ripples.seeds s join ripples.articles a on a.qid = s.qid where s.as_of = p_as_of and s.role = 'real';
  if hist is not null then
    perform ripples._enqueue(p_as_of, 'history', 'real', null, null, null, null, null, jsonb_build_object('items', hist));
  end if;
  return jsonb_build_object('real', kr, 'decoy', kd);
end $$;

-- ------------------------------------------------------------------ beams (split checks, deeper expansion)
create or replace function ripples._advance_beams(p_as_of date) returns int
language plpgsql security definer set search_path = '' as $$
declare r record; items jsonb; k int := 0; nb int; cap int := coalesce((ripples._cfg('wm_daily_cap') #>> '{}')::int, 6000);
begin
  for r in
    select j.root_qid, j.depth from ripples.jobs j
     where j.as_of = p_as_of and j.kind = 'expand' and j.role = 'real'
     group by 1, 2 having bool_and(j.status in ('done','failed','skipped'))
  loop
    -- 1. desktop/mobile split for pre-eligible hops at this depth that have not been checked
    if not exists (select 1 from ripples.jobs s where s.as_of = p_as_of and s.kind = 'split' and s.root_qid = r.root_qid and s.depth = r.depth) then
      select jsonb_agg(jsonb_build_object('parent_qid', c.parent_qid, 'qid', c.qid, 'title', coalesce(a.title_en, c.title),
                                          'parent_onset', (pj.parent_onset)) order by c.p_time, c.s_stat desc)
        into items
        from ripples.candidates c
        join ripples.jobs pj on pj.id = c.job_id
        left join ripples.articles a on a.qid = c.qid
       where c.as_of = p_as_of and c.role = 'real' and c.root_qid = r.root_qid and c.depth = r.depth
         and c.split_ok is null and ripples._pre_eligible(c);
      if items is not null then
        perform ripples._enqueue(p_as_of, 'split', 'real', r.root_qid, null, null, null, r.depth,
          jsonb_build_object('items', (select jsonb_agg(e) from jsonb_array_elements(items) with ordinality x(e, o) where o <= 45)));
        k := k + 1;
        continue;
      end if;
    end if;
    -- 2. once the split check is finished: beam of 2 into depth+1 (real only, depth <= 4)
    if r.depth < 4
       and not exists (select 1 from ripples.jobs s where s.as_of = p_as_of and s.kind = 'split' and s.root_qid = r.root_qid
                         and s.depth = r.depth and s.status in ('queued','running'))
       and not exists (select 1 from ripples.jobs e where e.as_of = p_as_of and e.kind = 'expand' and e.root_qid = r.root_qid
                         and e.depth = r.depth + 1)
       and (select wm_calls from ripples.runs where as_of = p_as_of) < cap then
      insert into ripples.jobs (as_of, kind, role, root_qid, parent_qid, parent_title, parent_onset, depth)
      select p_as_of, 'expand', 'real', r.root_qid, b.qid, b.title, b.onset, r.depth + 1 from (
        select c.qid, coalesce(a.title_en, c.title) title, pj.parent_onset + c.onset_lag onset,
               row_number() over (order by -log(greatest(coalesce(fl.f, c.p_time), 1e-6) * c.p_time) desc, c.qid) rn
          from ripples.candidates c
          join ripples.jobs pj on pj.id = c.job_id
          left join ripples.articles a on a.qid = c.qid
          cross join lateral ripples._fluke(c.as_of, c.s_stat) fl
         where c.as_of = p_as_of and c.role = 'real' and c.root_qid = r.root_qid and c.depth = r.depth
           and c.split_ok and ripples._pre_eligible(c)
           and c.qid <> r.root_qid
           and not exists (select 1 from ripples.jobs e where e.as_of = p_as_of and e.kind = 'expand' and e.root_qid = r.root_qid
                             and e.parent_qid = c.qid)
      ) b where b.rn <= 2;
      get diagnostics nb = row_count;
      k := k + nb;
    end if;
  end loop;
  return k;
end $$;

-- ------------------------------------------------------------------ fluke rates
create or replace function public.ripples_update_fluke(p_as_of date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare rt int; dt int;
begin
  select count(*) filter (where role = 'real'), count(*) filter (where role = 'decoy') into rt, dt
    from ripples.candidates where as_of = p_as_of;
  insert into ripples.fluke_rates (as_of, sbin, real_tested, real_pass, decoy_tested, decoy_pass, fluke,
                                   d_real_tested, d_real_pass, d_decoy_tested, d_decoy_pass)
  select p_as_of, b.sbin, 0, 0, 0, 0, null, rt,
         (select count(*) from ripples.candidates c where c.as_of = p_as_of and c.role = 'real' and c.pass_raw and ripples._sbin(c.s_stat) = b.sbin),
         dt,
         (select count(*) from ripples.candidates c where c.as_of = p_as_of and c.role = 'decoy' and c.pass_raw and ripples._sbin(c.s_stat) = b.sbin)
    from unnest(array['3-4','4-6','6-10','10+']) b(sbin)
  on conflict (as_of, sbin) do update set d_real_tested = excluded.d_real_tested, d_real_pass = excluded.d_real_pass,
    d_decoy_tested = excluded.d_decoy_tested, d_decoy_pass = excluded.d_decoy_pass;
  update ripples.fluke_rates f set real_tested = p.rt, real_pass = p.rp, decoy_tested = p.dt, decoy_pass = p.dp,
         fluke = case when p.rt > 0 and p.rp > 0 and p.dt > 0 then least(1, (p.dp::numeric / p.dt) / (p.rp::numeric / p.rt)) end
    from (select sbin, sum(d_real_tested)::int rt, sum(d_real_pass)::int rp, sum(d_decoy_tested)::int dt, sum(d_decoy_pass)::int dp
            from ripples.fluke_rates where as_of between p_as_of - 89 and p_as_of group by sbin) p
   where f.as_of = p_as_of and f.sbin = p.sbin;
  return (select jsonb_agg(jsonb_build_object('sbin', sbin, 'real_tested', real_tested, 'real_pass', real_pass,
            'decoy_tested', decoy_tested, 'decoy_pass', decoy_pass, 'fluke', round(fluke, 4)) order by sbin)
            from ripples.fluke_rates where as_of = p_as_of);
end $$;

-- ------------------------------------------------------------------ Call It resolution
-- Enqueue refresh jobs for pending Call It rows whose window ended by d-1; the refresh job writes outcome and max_z
-- (baseline frozen at window_start) through ripples_ingest_candidates.
create or replace function public.ripples_resolve_calls(p_d date) returns int
language plpgsql security definer set search_path = '' as $$
declare items jsonb; k int := 0; i int;
begin
  insert into ripples.runs (as_of, kind, stage, detail) values (p_d - 1, 'live', 'done', '{"note":"created by ripples_resolve_calls"}')
  on conflict (as_of) do nothing;
  select jsonb_agg(jsonb_build_object('n', c.n, 'qid', c.qid, 'title', coalesce(a.title_en, c.title),
                                      'window_start', c.window_start, 'window_end', c.window_end) order by c.n, c.qid)
    into items
    from ripples.callit c left join ripples.articles a on a.qid = c.qid
   where c.outcome = 'pending' and c.window_end <= p_d - 1 and c.n <> 0
     and not exists (select 1 from ripples.jobs j where j.kind = 'refresh' and j.status in ('queued','running')
                       and j.payload->'items' @> jsonb_build_array(jsonb_build_object('n', c.n, 'qid', c.qid)));
  if items is null then return 0; end if;
  for i in 0 .. (jsonb_array_length(items) - 1) / 90 loop
    perform ripples._enqueue(p_d - 1, 'refresh', 'callit', null, null, null, null, null,
      jsonb_build_object('items', (select jsonb_agg(e) from jsonb_array_elements(items) with ordinality x(e, o)
                                    where o > i * 90 and o <= (i + 1) * 90)));
    k := k + 1;
  end loop;
  return k;
end $$;

-- ------------------------------------------------------------------ retention (cron 03:50 UTC)
create or replace function public.ripples_retention() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c1 int; c2 int; c3 int; c4 int; c5 int; c6 int; c7 int;
begin
  -- non-shown candidate rows after 15 days (fluke counts are already aggregated in fluke_rates; the reserve bank
  -- looks back 14 days); pass_raw rows (a superset of shown hops) are kept
  delete from ripples.candidates where as_of < current_date - 15 and not pass_raw;  get diagnostics c1 = row_count;
  delete from ripples.screen     where as_of < current_date - 30;                     get diagnostics c2 = row_count;
  delete from ripples.trend_obs  where day < current_date - 60;                       get diagnostics c3 = row_count;
  delete from ripples.jobs       where created_at < now() - interval '30 days';       get diagnostics c4 = row_count;
  delete from ripples.plays      where created_at < now() - interval '400 days';      get diagnostics c5 = row_count;
  delete from ripples.rate_limits where day < current_date - 400;                     get diagnostics c6 = row_count;
  delete from ripples.chains     where as_of < current_date - 60 and used_n is null;  get diagnostics c7 = row_count;
  return jsonb_build_object('candidates', c1, 'screen', c2, 'trend_obs', c3, 'jobs', c4, 'plays', c5, 'rate_limits', c6, 'chains', c7);
end $$;

-- ------------------------------------------------------------------ state machine
-- One step (or a few) of the run for p_as_of: collect_daily -> resolve -> screen -> seeds -> expand -> build -> done.
-- Live runs keep the SPEC §5.5 clock (collect 06:10, resolve 06:25, build >= 06:58 with an empty queue or at the
-- 07:20 deadline); practice runs (ripples_run_day) move as fast as their jobs finish.
create or replace function ripples._tick_run(p_as_of date) returns text
language plpgsql security definer set search_path = '' as $$
declare r ripples.runs; live boolean; t time := (now() at time zone 'utc')::time; n int; st text; guard int := 0;
        pending int; res jsonb; pz record;
begin
  loop
    guard := guard + 1;
    exit when guard > 6;
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
      res := public.ripples_pick_seeds(p_as_of);
      update ripples.runs set stage = 'expand', stage_at = now(), detail = detail || jsonb_build_object('seeds', res) where as_of = p_as_of;
      return 'expand';
    elsif st = 'expand' then
      perform ripples._advance_beams(p_as_of);
      select count(*) into pending from ripples.jobs where as_of = p_as_of and status in ('queued','running') and kind <> 'refresh';
      if live and t >= time '07:20' then
        update ripples.jobs set status = 'skipped', error = 'build deadline 07:20', finished_at = now()
         where as_of = p_as_of and status = 'queued' and kind <> 'refresh';
      elsif pending > 0 or (live and t < time '06:58') then
        return st;
      end if;
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

-- pg_cron '* 6-8 * * *' (and the transient 'ripples-run-day' driver while a ripples_run_day run is active).
create or replace function public.ripples_tick() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare live_asof date := (now() at time zone 'utc')::date - 1; h int := extract(hour from now() at time zone 'utc');
        v_out jsonb := '{}'; r record; k int; active int;
begin
  if not pg_try_advisory_xact_lock(hashtext('ripples_tick')) then return '{"skipped":"busy"}'; end if;
  -- requeue jobs stuck in running for more than 5 minutes (at most 3 attempts)
  update ripples.jobs set status = case when attempts < 3 then 'queued' else 'failed' end,
         error = 'stuck in running > 5 min', not_before = now(),
         finished_at = case when attempts < 3 then null else now() end
   where status = 'running' and started_at < now() - interval '5 minutes';
  get diagnostics k = row_count;
  if k > 0 then v_out := v_out || jsonb_build_object('requeued', k); end if;
  -- today's live run (only once puzzle n = (as_of + 1) - epoch is positive)
  if h between 6 and 8 and (live_asof + 1 - ripples._epoch()) > 0 then
    insert into ripples.runs (as_of, kind) values (live_asof, 'live') on conflict (as_of) do nothing;
    if (select kind from ripples.runs where as_of = live_asof) = 'live' then
      v_out := v_out || jsonb_build_object('live', ripples._tick_run(live_asof));
    end if;
  end if;
  -- practice / backfill runs started by ripples_run_day
  for r in select as_of from ripples.runs where kind = 'practice' and stage not in ('done','delayed','failed') order by as_of desc loop
    v_out := v_out || jsonb_build_object(r.as_of::text, ripples._tick_run(r.as_of));
  end loop;
  k := ripples._dispatch(ripples._pcfg('dispatch_per_tick', 6)::int);
  v_out := v_out || jsonb_build_object('dispatched', k);
  -- the transient driver unschedules itself once no practice run is active
  select count(*) into active from ripples.runs where kind = 'practice' and stage not in ('done','delayed','failed');
  if active = 0 and exists (select 1 from cron.job where jobname = 'ripples-run-day') then
    perform cron.unschedule('ripples-run-day');
    v_out := v_out || '{"driver":"stopped"}';
  end if;
  return v_out;
end $$;

-- Driver for a past date (W3 backfill, tests). Registers the run and starts the transient pg_cron job
-- 'ripples-run-day' (every 20 s, calls ripples_tick) which advances it through every stage; returns at once
-- (pg_net requests are only sent after the calling transaction commits, so a single SQL call cannot wait for them).
-- Poll: select stage, wm_calls, errors, detail from ripples.runs where as_of = ...;
-- p_reset = true deletes that as_of's previous pipeline rows (jobs, screen, seeds, candidates, chains) and starts over.
create or replace function public.ripples_run_day(p_as_of date, p_kind text default 'practice', p_reset boolean default false)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r ripples.runs; n int; v_exists boolean;
begin
  if p_kind is distinct from 'practice' then raise exception 'ripples_run_day only runs practice (reconstructed) days; live runs are driven by ripples_tick'; end if;
  if p_as_of >= (now() at time zone 'utc')::date then raise exception 'as_of must be a complete past day'; end if;
  n := p_as_of - ripples._epoch();
  if n >= 0 then raise exception 'practice n = data_date - epoch must be negative (as_of < %)', ripples._epoch(); end if;
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
    v_exists := false;
  end if;
  if not v_exists then
    insert into ripples.runs (as_of, kind, stage) values (p_as_of, 'practice', 'collect_daily');
  end if;
  if not exists (select 1 from cron.job where jobname = 'ripples-run-day') then
    perform cron.schedule('ripples-run-day', '20 seconds', 'select public.ripples_tick()');
  end if;
  select * into r from ripples.runs where as_of = p_as_of;
  return jsonb_build_object('as_of', p_as_of, 'kind', 'practice', 'n', n, 'stage', r.stage, 'started_at', r.started_at,
    'poll', format('select stage, wm_calls, errors, detail from ripples.runs where as_of = %L', p_as_of));
end $$;

do $$
declare f text;
begin
  foreach f in array array['public.ripples_pick_seeds(date)', 'public.ripples_update_fluke(date)', 'public.ripples_resolve_calls(date)',
    'public.ripples_retention()', 'public.ripples_tick()', 'public.ripples_run_day(date, text, boolean)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
