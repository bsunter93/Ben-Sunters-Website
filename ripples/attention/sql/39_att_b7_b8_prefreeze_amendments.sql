-- Pre-freeze amendments to b7 (decade backfill) and pre-start amendments to b8 (anomaly-first), 2026-09-27.
--
-- Both batches were pre-registered (ledger 1211, 1212/1213) and neither had produced a result when these were written:
-- no library_hist event existed, no b7 grid was frozen, and no b8 anomaly link had been computed (the only b8
-- computation so far was the positive-control smoke test, ledger 1213). Each amendment is appended to the ledger
-- before the step it changes runs.
--
-- A. b7 catalog (applied before att_hist_fema_build first ran). Found by reading the raw OpenFEMA declaration rows,
--    before any historical event or any outcome was looked at:
--    A1. Evacuee-sheltering declarations are not damage. Hurricane Katrina (2005) came out "hitting" 47 states because
--        FEMA gave ~42 states emergency declarations titled "HURRICANE KATRINA EVACUATION" / "EVACUEES" to shelter
--        evacuees, plus late EMs in ID, KY and PA titled plain "HURRICANE KATRINA" (declared 12-20 days after the storm
--        began, no major-disaster declaration). Kept as-is, Katrina would be untestable (no clean donors), and every
--        state would be masked as a control for autumn 2005 for every other shock. Rule: drop declaration rows whose
--        title contains EVACU; for named storms, drop an emergency (EM) row for a state that has no major-disaster (DR)
--        row for the same storm when the EM was declared more than 7 days after the storm's earliest incident begin
--        date (sheltering EMs are declared after landfall; pre-landfall "threat" EMs, e.g. Texas for Gustav 2008 or
--        Florida for Ike 2008, are declared before and are kept).
--    A2. FEMA incident type "Fire" is not always a wildfire. Excluded: 2001-09-11 "FIRES AND EXPLOSIONS" (the
--        September 11 attacks: NY, NJ, VA), 2009-10-23 "EXPLOSIONS AND FIRE" (Puerto Rico refinery), 2011-04-15
--        "GOODYEAR PLANT FIRE" (OK). Rule: drop Fire rows whose title matches EXPLOS or PLANT FIRE.
--    The live 2019+ collector (att-library femaEvents) was checked for the same two patterns: no 2019+ library event
--    has an evacuation, explosion or plant-fire title, so the 2019+ catalog is unchanged and the two halves still use
--    the same rules in effect.
--
-- B. b8 (applied before att_anom_start ran):
--    B1. Season matching for weekly fake shocks: a shift of s * 52 weeks drifts 1.25 days a year (up to ~19 days at
--        s = 15 on the 2010+ claims panel). Now round(s * 52.1775) weeks, so every fake shock sits within half a week
--        of the real calendar position. Monthly panels unchanged (s * 12).
--    B2. Multiplicity at the confirmation stage. The registered rule confirmed every promoted hypothesis with one-sided
--        p <= 0.05 on held-out shocks, with no correction across the promoted list: 20 promoted nulls would give ~1
--        false confirmation. Now: Benjamini-Hochberg across the confirmation p-values of the promoted list; "confirmed"
--        needs q <= 0.05, enrichment >= 1.2, AND the empirical rank p <= 0.05 (a guard against the normal approximation,
--        whose right tail is too thin for skewed low-rate hit counts). Confirmation replays use 400 fake-shock draws
--        (empirical p resolves to 0.0025) instead of 100. A promoted link that reaches p <= 0.05 and enrichment >= 1.2
--        but fails q or the empirical guard is labelled "consistent with a pattern (not confirmed)" -- this is the
--        story layer's middle label, never a finding.
--    B3. A calibration read on the normal approximation: each hypothesis also stores how many of its own fake-shock
--        draws score z >= 2.326 (nominal 1%) and z >= 3.090 (nominal 0.1%) against the null mean and sd. Pooled over
--        every hypothesis this says whether the screen's p-values are honest in the tail. Reported with the verdicts.
--    B4. Throughput and a hang fix (no statistical change). The tick ran one task a minute, so ~110 national-shock
--        tasks with an empty footprint (film/game/model releases, macro releases: no state or BA) would each burn a
--        minute. The tick now works through tasks until ~60 s are spent. Separately, a task that ran past the cron's
--        110 s statement timeout rolled back its own 'running' mark and was retried forever; the link call now traps
--        the cancel, marks the task 'timeout' and moves on. Timed-out tasks are re-run by a slower job (10 minute
--        budget). The screen does not promote until every screen task is done or has failed twice (failures are
--        listed in the promotion ledger entry).

-- A. b7 catalog ------------------------------------------------------------------------------------------------------
create or replace function ripples.att_hist_fema_build() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rows jsonb; res jsonb := '[]'::jsonb; i int := 0; v_n int;
begin
  with fam(it, family) as (values
      ('hurricane', 'hazard.storm'), ('tropical storm', 'hazard.storm'), ('typhoon', 'hazard.storm'), ('tropical depression', 'hazard.storm'),
      ('coastal storm', 'hazard.storm'), ('severe storm', 'hazard.storm'), ('severe storm(s)', 'hazard.storm'), ('tornado', 'hazard.storm'),
      ('straight-line winds', 'hazard.storm'), ('flood', 'hazard.flood'), ('dam/levee break', 'hazard.flood'), ('mud/landslide', 'hazard.flood'),
      ('fire', 'hazard.wildfire'), ('winter storm', 'hazard.cold'), ('severe ice storm', 'hazard.cold'), ('snowstorm', 'hazard.cold'),
      ('freezing', 'hazard.cold'), ('earthquake', 'hazard.quake')),
  recs0 as (
    select h.*, f.family, ripples.att_storm_name(h.title) storm from ripples.att_hist_fema h join fam f on f.it = lower(h.it)
     where h.began >= date '2000-01-01' and h.began < date '2019-01-01'
       and h.title !~* 'EVACU'                                                   -- A1: evacuee-sheltering declarations
       and not (lower(h.it) = 'fire' and h.title ~* 'EXPLOS|PLANT FIRE')),       -- A2: fire that is not a wildfire
  st0 as (select r.storm, extract(year from r.began)::int yr, min(r.began) b0 from recs0 r where r.storm is not null group by 1, 2),
  recs as (
    select r.* from recs0 r left join st0 on st0.storm = r.storm and st0.yr = extract(year from r.began)::int
     where r.storm is null or r.type <> 'EM' or r.day <= st0.b0 + 7
        or exists (select 1 from recs0 d where d.storm = r.storm and extract(year from d.began) = extract(year from r.began)
                     and d.state = r.state and d.type = 'DR')),                  -- A1: late EM-only state = sheltering
  keyed as (
    select r.*, case when storm is not null then 'storm|' || storm || '|' || extract(year from began)::int else it || '|' || upper(btrim(title)) end k from recs r),
  brk as (
    select k2.*, case when storm is null and began > max(began) over (partition by k order by began, num rows between unbounded preceding and 1 preceding) + 7 then 1 else 0 end nb from keyed k2),
  grp as (select b.*, sum(nb) over (partition by k order by began, num rows unbounded preceding) gi from brk b),
  g as (
    select k, gi, min(storm) storm, min(family) family, min(it) it, min(title) title, min(began) began, count(*) areas,
           array_agg(distinct state order by state) filter (where state ~ '^[A-Z]{2}$') states,
           array_agg(distinct type order by type) types, (array_agg(distinct num order by num))[1:8] nums, array_agg(title) titles
      from grp group by k, gi),
  lbl as (
    select g.*, case when exists (select 1 from unnest(titles) t where t ~* 'HURRICANE') then 'Hurricane'
                     when exists (select 1 from unnest(titles) t where t ~* 'TYPHOON') then 'Typhoon' else 'Tropical storm' end kind,
           trim(both '-' from left(trim(both '-' from regexp_replace(lower(coalesce(nullif(title, ''), it)), '[^a-z0-9]+', '-', 'g')), 60)) sl
      from g)
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'role', 'library_hist', 'onset', began, 'states', to_jsonb(coalesce(states, '{}')), 'merge', true,
           'magnitude', round(ln(1 + areas)::numeric, 3), 'source', 'OpenFEMA DisasterDeclarationsSummaries',
           'ref', array_to_string(types, '/') || '-' || array_to_string(nums, ','), 'defined_by', '["fema.decl"]'::jsonb,
           'slug', case when storm is not null then 'storm-' || storm || '-' || extract(year from began)::int else 'fema-' || sl || '-' || began end,
           'storm', storm, 'family', case when storm is not null then 'hazard.storm' else family end,
           'label', case when storm is not null then kind || ' ' || initcap(storm) || ' (' || extract(year from began)::int || ')'
                         else left(initcap(coalesce(nullif(title, ''), it)) || ' (' || it || ', ' || began || ')', 200) end,
           'label_weak', case when storm is not null then kind = 'Tropical storm' end)))
    into v_rows from lbl;
  v_n := coalesce(jsonb_array_length(v_rows), 0);
  while i < v_n loop
    res := res || jsonb_build_array(ripples.att_library_upsert((select jsonb_agg(x) from (select x from jsonb_array_elements(v_rows) with ordinality e(x, o) where o > i and o <= i + 200) z)));
    i := i + 200;
  end loop;
  perform ripples.att_fx63_fam_events_build();
  return jsonb_build_object('events', v_n, 'upserts', res);
end $$;
revoke all on function ripples.att_hist_fema_build() from anon, authenticated, public;

select ripples.att_ledger_append(current_date, 'register', jsonb_build_object(
  'object', 'fx63_batch', 'batch', 'fx63-b7-decade', 'stage', 'pre-freeze amendment (catalog)', 'file', '39_att_b7_b8_prefreeze_amendments.sql',
  'note', 'Written after reading raw OpenFEMA declaration rows and before any library_hist event exists, any b7 grid is frozen or any b7 outcome is '
       || 'looked at. (1) Evacuee-sheltering declarations dropped: titles containing EVACU, and for named storms an EM-only state (no DR for that '
       || 'storm) declared more than 7 days after the storm''s earliest incident begin. Without this Katrina 2005 covers 47 states (host states for '
       || 'evacuees), which makes it untestable and masks every control state for autumn 2005. Pre-landfall threat EMs (Gustav TX, Ike FL) are kept. '
       || '(2) Fire declarations that are not wildfires dropped (title EXPLOS or PLANT FIRE): 2001-09-11 FIRES AND EXPLOSIONS (NY, NJ, VA; the '
       || 'September 11 attacks), 2009 PR refinery explosion, 2011 OK Goodyear plant fire. The 2019+ library has none of either pattern. '
       || 'Deviation from 37''s "exactly att-library femaEvents grouping", disclosed here.'),
  jsonb_build_object('rules', jsonb_build_array('title !~* EVACU', 'storm EM-only state declared > earliest begin + 7 days: dropped', 'Fire and title ~* EXPLOS|PLANT FIRE: dropped')));

-- B. b8 --------------------------------------------------------------------------------------------------------------
alter table ripples.att_anom_hyp add column if not exists k_null int, add column if not exists n_null_z2 int, add column if not exists n_null_z3 int;

-- B1 (season-exact weekly shifts) + B3 (tail calibration counts); otherwise identical to 38
create or replace function ripples.att_anom_link(p_run text, p_family text, p_sub text, p_source text, p_metric text, p_geo_kind text,
                                                 p_stage text, p_k int default 100) returns int
language plpgsql security definer set search_path = '' as $$
declare pan record; lagn int; per float8; lo int[]; hi int[]; v_split date; reg jsonb; n_ins int; defn boolean;
begin
  select * into pan from ripples.att_fx_panel p where p.source = p_source and p.metric = p_metric and p.geo_kind = p_geo_kind;
  if pan.source is null or pan.grain not in ('week', 'month') then return 0; end if;
  if pan.grain = 'week' then lagn := 52; per := 52.1775; lo := array[0, 2, 5, 13]; hi := array[1, 4, 12, 26];
  else lagn := 12; per := 12; lo := array[0, 2, 4, 7]; hi := array[1, 3, 6, 12]; end if;
  v_split := (ripples._att_cfg('engine63') ->> 'split_date')::date;
  reg := coalesce(ripples._att_cfg('engine63') -> 'regime_exclusions', '[]'::jsonb);
  defn := p_source = 'fema.decl' and p_family like 'hazard.%' and p_family <> 'hazard.heat';
  drop table if exists pg_temp._au; drop table if exists pg_temp._ad;
  create temp table _au on commit drop as
    select distinct ev.event_id, rr.region, (select count(*)::int from unnest(pan.days) dd where dd < ev.onset) + 1 as i0
      from ripples.att_events ev
      join ripples.att_topics t on t.topic_id = ev.topic_id
      cross join lateral unnest(ripples.att_fx_treated(ev.event_id, p_geo_kind, null)) x(region)
      join unnest(pan.regions) rr(region) on rr.region = x.region
     where ev.family = p_family and ev.role in ('library', 'library_hist')
       and (p_sub = '' or (p_sub = 'hurricane' and t.meta ? 'storm'))
       and ((p_stage = 'explore' and ev.onset < v_split) or (p_stage = 'confirm' and ev.onset >= v_split))
       and ev.onset > pan.days[1] and ev.onset <= pan.days[pan.n];
  delete from _au where i0 <= lagn + 1 or i0 > pan.n;
  if not exists (select 1 from _au) then return 0; end if;
  create temp table _ad on commit drop as
    with evs as (select distinct a.event_id, a.i0 from _au a),
    cand as (select evs.event_id, evs.i0 + round(s * per)::int i0k, s from evs, generate_series(-25, 25) s
              where s <> 0 and evs.i0 + round(s * per)::int > lagn + 1 and evs.i0 + round(s * per)::int + hi[4] <= pan.n),
    pick as (select kk.k, cand.event_id, cand.i0k,
                    row_number() over (partition by kk.k, cand.event_id order by md5(p_run || ':' || cand.event_id || ':' || kk.k || ':' || cand.s)) rn
               from cand, generate_series(1, p_k) kk(k))
    select 0 k, evs.event_id, evs.i0 i0k from evs
    union all select pick.k, pick.event_id, pick.i0k from pick where pick.rn = 1;
  with u as (select d.k, a.event_id, a.region, d.i0k from _ad d join _au a on a.event_id = d.event_id),
  uf as (select u.* from u where not exists (
           select 1 from jsonb_array_elements(reg) r
            where pan.days[greatest(1, u.i0k - lagn)] <= (r ->> 'to')::date and pan.days[least(pan.n, u.i0k + hi[4])] >= (r ->> 'from')::date)),
  ub as (select uf.k, uf.event_id, uf.region, uf.i0k, g.b from uf, generate_series(1, 4) g(b) where uf.i0k + hi[g.b] <= pan.n),
  hit as (select ub.k, ub.b, ub.event_id, ub.region, coalesce(bool_or(a.z > 0), false) up, coalesce(bool_or(a.z < 0), false) dn
            from ub left join ripples.att_anom a
              on a.source = p_source and a.metric = p_metric and a.geo_kind = p_geo_kind and a.region = ub.region
             and a.i between ub.i0k + lo[ub.b] and ub.i0k + hi[ub.b]
           group by ub.k, ub.b, ub.event_id, ub.region),
  rate as (select h.k, h.b, sg.sign, count(*) nu, count(distinct h.event_id) ne,
                  sum(case when (sg.sign = 1 and h.up) or (sg.sign = -1 and h.dn) then 1 else 0 end) hits,
                  avg(case when (sg.sign = 1 and h.up) or (sg.sign = -1 and h.dn) then 1.0 else 0.0 end) r
             from hit h cross join (values (1::smallint), (-1::smallint)) sg(sign) group by h.k, h.b, sg.sign),
  o as (select * from rate where k = 0),
  nl as (select r.b, r.sign, avg(r.r) m, stddev_samp(r.r) s, count(*) nk from rate r where r.k > 0 group by r.b, r.sign),
  tl as (select r.b, r.sign, count(*) filter (where nl.s > 0 and (r.r - nl.m) / nl.s >= 2.326) z2,
                count(*) filter (where nl.s > 0 and (r.r - nl.m) / nl.s >= 3.090) z3
           from rate r join nl on nl.b = r.b and nl.sign = r.sign where r.k > 0 group by r.b, r.sign),
  ge as (select o.b, o.sign, count(*) filter (where r.r >= o.r) nge from o join rate r on r.b = o.b and r.sign = o.sign and r.k > 0 group by o.b, o.sign)
  insert into ripples.att_anom_hyp(run, stage, family, sub, source, metric, geo_kind, bucket, sign, n_events, n_units, hits, obs,
                                   null_mean, null_sd, p, p_emp, enrich, definitional, k_null, n_null_z2, n_null_z3, computed_at)
  select p_run, p_stage, p_family, p_sub, p_source, p_metric, p_geo_kind, o.b, o.sign, o.ne, o.nu, o.hits, o.r, nl.m, nl.s,
         case when nl.s > 0 then 1 - ripples.att_norm_cdf(((o.r - nl.m) / nl.s)::float8) when o.r > nl.m then 0 else 1 end,
         (1 + coalesce(ge.nge, 0))::real / (1 + nl.nk), case when nl.m > 0 then o.r / nl.m end, defn, nl.nk, tl.z2, tl.z3, now()
    from o join nl on nl.b = o.b and nl.sign = o.sign left join ge on ge.b = o.b and ge.sign = o.sign left join tl on tl.b = o.b and tl.sign = o.sign
  on conflict (run, stage, family, sub, source, metric, geo_kind, bucket, sign) do update set
    n_events = excluded.n_events, n_units = excluded.n_units, hits = excluded.hits, obs = excluded.obs, null_mean = excluded.null_mean,
    null_sd = excluded.null_sd, p = excluded.p, p_emp = excluded.p_emp, enrich = excluded.enrich, definitional = excluded.definitional,
    k_null = excluded.k_null, n_null_z2 = excluded.n_null_z2, n_null_z3 = excluded.n_null_z3, computed_at = now();
  get diagnostics n_ins = row_count;
  return n_ins;
end $$;

-- one task, with the statement-timeout cancel trapped (B4)
create or replace function ripples._att_anom_run_task(p_run text, p_stage text, p_family text, p_sub text, p_source text, p_metric text,
                                                      p_geo_kind text, p_fail_status text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rows int;
begin
  begin
    v_rows := ripples.att_anom_link(p_run, p_family, p_sub, p_source, p_metric, p_geo_kind, p_stage, case when p_stage = 'confirm' then 400 else 100 end);
  exception when query_canceled then
    update ripples.att_anom_queue set status = p_fail_status, note = 'statement timeout', done_at = now()
     where run = p_run and stage = p_stage and family = p_family and sub = p_sub and source = p_source and metric = p_metric and geo_kind = p_geo_kind;
    return jsonb_build_object('timeout', p_stage || ' ' || p_family || coalesce('/' || nullif(p_sub, ''), '') || ' x ' || p_source || ':' || p_metric);
  end;
  update ripples.att_anom_queue set status = 'done', note = v_rows || ' rows', done_at = now()
   where run = p_run and stage = p_stage and family = p_family and sub = p_sub and source = p_source and metric = p_metric and geo_kind = p_geo_kind;
  return jsonb_build_object('task', p_stage || ' ' || p_family || coalesce('/' || nullif(p_sub, ''), '') || ' x ' || p_source || ':' || p_metric, 'rows', v_rows);
end $$;

-- tick: tasks until ~45 s are spent (B4); promotion waits for timed-out tasks; verdicts with BH + empirical guard (B2)
create or replace function ripples.att_anom_tick(p_run text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record; r jsonb; done_list jsonb := '[]'::jsonb; t0 timestamptz := clock_timestamp(); v_seq bigint; v_m int;
begin
  loop
    select * into t from ripples.att_anom_queue where run = p_run and status = 'queued' and stage in ('explore', 'confirm')
     order by stage desc, family, sub, source, metric limit 1 for update skip locked;
    exit when t.run is null;
    update ripples.att_anom_queue set status = 'running' where run = t.run and stage = t.stage and family = t.family and sub = t.sub and source = t.source and metric = t.metric and geo_kind = t.geo_kind;
    r := ripples._att_anom_run_task(t.run, t.stage, t.family, t.sub, t.source, t.metric, t.geo_kind, 'timeout');
    done_list := done_list || jsonb_build_array(r);
    if r ? 'timeout' or clock_timestamp() - t0 > interval '45 seconds' then return jsonb_build_object('tasks', done_list); end if;
  end loop;
  if jsonb_array_length(done_list) > 0 then return jsonb_build_object('tasks', done_list); end if;
  if exists (select 1 from ripples.att_anom_queue where run = p_run and status in ('running', 'timeout', 'retrying')) then return jsonb_build_object('waiting', true); end if;
  -- screen finished and not yet promoted: BH across every screen hypothesis, promote, freeze the list, queue confirmation (rule unchanged from 38)
  if not exists (select 1 from ripples.att_anom_queue where run = p_run and stage = 'confirm')
     and not exists (select 1 from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted is not null) then
    with rr as (select family, sub, source, metric, geo_kind, bucket, sign, p, row_number() over (order by p) rk, count(*) over () m
                  from ripples.att_anom_hyp where run = p_run and stage = 'explore' and p is not null),
    q as (select rr.*, min(p * m / rk) over (order by rk desc rows between unbounded preceding and current row) qv from rr)
    update ripples.att_anom_hyp h set q = least(1, q.qv),
           promoted = (q.qv <= 0.10 and h.enrich >= 1.5 and h.hits >= 8 and h.n_events >= 10)
      from q where h.run = p_run and h.stage = 'explore' and h.family = q.family and h.sub = q.sub and h.source = q.source and h.metric = q.metric
       and h.geo_kind = q.geo_kind and h.bucket = q.bucket and h.sign = q.sign;
    update ripples.att_anom_hyp set promoted = false where run = p_run and stage = 'explore' and promoted is null;
    select count(*) into v_m from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted;
    v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'anom_run', 'run', p_run, 'stage', 'promote', 'n_promoted', v_m,
               'n_screen_hypotheses', (select count(*) from ripples.att_anom_hyp where run = p_run and stage = 'explore' and p is not null),
               'failed_tasks', (select coalesce(jsonb_agg(family || coalesce('/' || nullif(sub, ''), '') || ' x ' || source || ':' || metric), '[]'::jsonb)
                                  from ripples.att_anom_queue where run = p_run and stage = 'explore' and status = 'failed'),
               'rule', 'screen: BH q <= 0.10, enrichment >= 1.5, hits >= 8, shocks >= 10; confirm (39/B2): BH q <= 0.05 across the promoted list on shocks on/after split, '
                    || 'enrichment >= 1.2, empirical p <= 0.05 with 400 fake-shock draws'),
               (select coalesce(jsonb_agg(jsonb_build_array(family, sub, source, metric, geo_kind, bucket, sign, round(enrich::numeric, 3), round(q::numeric, 5)) order by q), '[]'::jsonb)
                  from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted));
    insert into ripples.att_anom_queue(run, stage, family, sub, source, metric, geo_kind)
      select distinct p_run, 'confirm', family, sub, source, metric, geo_kind from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted
    on conflict do nothing;
    return jsonb_build_object('promoted', v_m, 'ledger', v_seq);
  end if;
  -- confirmation finished: verdicts on the promoted hypotheses only (once; a 'done' marker ends the run)
  if not exists (select 1 from ripples.att_anom_queue where run = p_run and stage = 'done') then
    with c as (select c.run, c.family, c.sub, c.source, c.metric, c.geo_kind, c.bucket, c.sign, c.p,
                      row_number() over (order by c.p) rk, count(*) over () m
                 from ripples.att_anom_hyp c
                 join ripples.att_anom_hyp e on e.run = c.run and e.stage = 'explore' and e.promoted and e.family = c.family and e.sub = c.sub
                  and e.source = c.source and e.metric = c.metric and e.geo_kind = c.geo_kind and e.bucket = c.bucket and e.sign = c.sign
                where c.run = p_run and c.stage = 'confirm' and c.p is not null and c.n_events >= 5),
    q as (select c.*, min(c.p * c.m / c.rk) over (order by c.rk desc rows between unbounded preceding and current row) qv from c)
    update ripples.att_anom_hyp h set q = least(1, q.qv)
      from q where h.run = q.run and h.stage = 'confirm' and h.family = q.family and h.sub = q.sub and h.source = q.source and h.metric = q.metric
       and h.geo_kind = q.geo_kind and h.bucket = q.bucket and h.sign = q.sign;
    update ripples.att_anom_hyp e set verdict = case
        when c.run is null or c.n_events < 5 or c.p is null then 'too few held-out shocks'
        when c.q <= 0.05 and c.p_emp <= 0.05 and c.enrich >= 1.2 then case when e.definitional then 'confirmed (positive control)' else 'confirmed' end
        when c.p <= 0.05 and c.enrich >= 1.2 then 'consistent with a pattern (not confirmed)'
        else 'not confirmed' end
      from ripples.att_anom_hyp e2 left join ripples.att_anom_hyp c
        on c.run = e2.run and c.stage = 'confirm' and c.family = e2.family and c.sub = e2.sub and c.source = e2.source and c.metric = e2.metric
       and c.geo_kind = e2.geo_kind and c.bucket = e2.bucket and c.sign = e2.sign
     where e.run = p_run and e.stage = 'explore' and e.promoted and e2.run = e.run and e2.stage = e.stage and e2.family = e.family and e2.sub = e.sub
       and e2.source = e.source and e2.metric = e.metric and e2.geo_kind = e.geo_kind and e2.bucket = e.bucket and e2.sign = e.sign;
    v_seq := ripples.att_ledger_append(current_date, 'register', jsonb_build_object('object', 'anom_run', 'run', p_run, 'stage', 'verdicts',
               'n_confirmed', (select count(*) from ripples.att_anom_hyp where run = p_run and stage = 'explore' and verdict like 'confirmed%'),
               'normal_tail_calibration', (select jsonb_build_object('draws', sum(k_null), 'share_z_ge_2_326', round((sum(n_null_z2)::numeric / nullif(sum(k_null), 0)), 5),
                                                  'nominal_2_326', 0.01, 'share_z_ge_3_090', round((sum(n_null_z3)::numeric / nullif(sum(k_null), 0)), 6), 'nominal_3_090', 0.001)
                                             from ripples.att_anom_hyp where run = p_run and stage = 'explore' and null_sd > 0)),
               (select coalesce(jsonb_agg(jsonb_build_array(family, sub, source, metric, bucket, sign, verdict) order by verdict, family), '[]'::jsonb)
                  from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted));
    insert into ripples.att_anom_queue(run, stage, family, sub, source, metric, geo_kind, status, done_at)
      values (p_run, 'done', '-', '', '-', '-', '-', 'done', now()) on conflict do nothing;
    return jsonb_build_object('verdicts', true, 'ledger', v_seq);
  end if;
  return jsonb_build_object('complete', true);
end $$;

-- slow lane: re-run one timed-out task with a 10 minute budget; a second timeout marks it failed (B4)
create or replace function ripples.att_anom_retry(p_run text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record;
begin
  select * into t from ripples.att_anom_queue where run = p_run and status = 'timeout' order by stage desc, family, sub, source, metric limit 1 for update skip locked;
  if t.run is null then return jsonb_build_object('idle', true); end if;
  update ripples.att_anom_queue set status = 'retrying' where run = t.run and stage = t.stage and family = t.family and sub = t.sub and source = t.source and metric = t.metric and geo_kind = t.geo_kind;
  return ripples._att_anom_run_task(t.run, t.stage, t.family, t.sub, t.source, t.metric, t.geo_kind, 'failed');
end $$;
revoke all on function ripples.att_anom_link(text, text, text, text, text, text, text, int), ripples._att_anom_run_task(text, text, text, text, text, text, text, text),
  ripples.att_anom_tick(text), ripples.att_anom_retry(text) from anon, authenticated, public;

select cron.schedule('att-anom-b8-slow', '*/10 * * * *', $c$
  set statement_timeout = '590s';
  select ripples.att_anom_retry('b8-anomaly-first')
   where exists (select 1 from ripples.att_anom_queue where run = 'b8-anomaly-first' and status = 'timeout')
$c$);

select ripples.att_ledger_append(current_date, 'register', jsonb_build_object(
  'object', 'anom_run', 'run', 'b8-anomaly-first', 'stage', 'pre-start amendment', 'file', '39_att_b7_b8_prefreeze_amendments.sql',
  'note', 'Written before att_anom_start (no b8 anomaly link computed; only the positive-control smoke test of ledger 1213). (B1) weekly fake shocks '
       || 'shifted by round(s * 52.1775) weeks instead of s * 52 (removes up to ~19 days of calendar drift). (B2) confirmation now corrects for the '
       || 'number of promoted links: confirmed = BH q <= 0.05 across the promoted list AND enrichment >= 1.2 AND empirical p <= 0.05 with 400 fake-shock '
       || 'draws (was: p <= 0.05 each, no correction, 100 draws); p <= 0.05 and enrichment >= 1.2 without the rest = "consistent with a pattern (not '
       || 'confirmed)". Stricter than registered. (B3) each hypothesis stores how many of its own fake-shock draws reach z >= 2.326 / 3.090, a pooled '
       || 'check on the normal approximation, reported with the verdicts. (B4) tick runs tasks for ~45 s per call; a statement-timeout cancel is '
       || 'trapped (task -> timeout -> one slow retry with a 590 s budget -> failed), fixing an endless retry; the screen promotes only when no task '
       || 'is running, timed out or retrying; failed tasks are listed in the promotion entry.'),
  jsonb_build_object('week_period', 52.1775, 'k_confirm', 400, 'confirm_q', 0.05, 'confirm_p_emp', 0.05, 'confirm_enrich', 1.2, 'tick_budget_s', 45, 'retry_budget_s', 590));

-- C. Engine 6.3 operations (no statistical change) -------------------------------------------------------------------
-- C1. The finisher unscheduled every att-fx63-step-% worker as soon as ANY batch reached calibration, stranding any other
--     frozen batch mid-run; now it does so only when no other frozen, unfinished batch remains. Its last stage removed only
--     a job literally named att-fx63-finisher; it now also removes att-fx63-finisher-<batch>, so each batch can have its
--     own finisher job.
-- C2. Decoy exploration rows (role dx) are seeded by att_fx63_decoy_seed(batch), which nothing calls automatically and
--     which the 2026-09-27 handoff runbook omitted. Without it the finisher can never reach stage 2/3. Run it once per
--     batch right after the freeze (b6 and b7 were seeded this way).
do $$ declare d text;
  a1 text := $a$perform cron.unschedule(jobid) from cron.job where jobname like 'att-fx63-step-%';$a$;
  b1 text := $b$if not exists (select 1 from ripples.att_fx63_batch b2 where b2.batch <> p_batch and b2.explore_seq is not null and b2.calib_seq is null
                    and b2.status not in ('superseded', 'not testable', 'withheld')) then
      perform cron.unschedule(jobid) from cron.job where jobname like 'att-fx63-step-%';
    end if;$b$;
  a2 text := $a$perform cron.unschedule(jobid) from cron.job where jobname = 'att-fx63-finisher';$a$;
  b2 text := $b$perform cron.unschedule(jobid) from cron.job where jobname in ('att-fx63-finisher', 'att-fx63-finisher-' || p_batch);$b$;
begin
  d := pg_get_functiondef('ripples.att_fx63_finisher(text)'::regprocedure);
  if position('att-fx63-finisher-' in d) > 0 then return; end if;
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 or position(a2 in d) = 0 then raise exception 'finisher anchors'; end if;
  execute replace(replace(d, a1, b1), a2, b2);
end $$;

-- B5 (b8, before start). Two engine generations left duplicate panels of the same data: dol.claims ic / cw (engine 6.2,
-- 2015+) next to ic_w / cw_w (engine 6.3, 2010+). The scan would test every claims hypothesis twice. A panel is skipped
-- when the same source has <metric>_w for the same geography.
do $$ declare d text;
  a text := $a$for pan in select source, metric, geo_kind from ripples.att_fx_panel where geo_kind in ('state', 'ba') and grain in ('week', 'month') order by 1, 2, 3 loop$a$;
  b text := $b$for pan in select p0.source, p0.metric, p0.geo_kind from ripples.att_fx_panel p0 where p0.geo_kind in ('state', 'ba') and p0.grain in ('week', 'month')
               and not exists (select 1 from ripples.att_fx_panel p2 where p2.source = p0.source and p2.geo_kind = p0.geo_kind and p2.metric = p0.metric || '_w') order by 1, 2, 3 loop$b$;
  a2 text := $a$cross join (select source, metric, geo_kind from ripples.att_fx_panel where geo_kind in ('state', 'ba') and grain in ('week', 'month')) p$a$;
  b2 text := $b$cross join (select p0.source, p0.metric, p0.geo_kind from ripples.att_fx_panel p0 where p0.geo_kind in ('state', 'ba') and p0.grain in ('week', 'month')
                     and not exists (select 1 from ripples.att_fx_panel p2 where p2.source = p0.source and p2.geo_kind = p0.geo_kind and p2.metric = p0.metric || '_w')) p$b$;
begin
  d := pg_get_functiondef('ripples.att_anom_start(text)'::regprocedure);
  if position('p0.metric || ''_w''' in d) > 0 then return; end if;
  if position(a in d) = 0 or position(a2 in d) = 0 then raise exception 'anom_start anchors'; end if;
  execute replace(replace(d, a, b), a2, b2);
end $$;

select ripples.att_ledger_append(current_date, 'register', jsonb_build_object(
  'object', 'anom_run', 'run', 'b8-anomaly-first', 'stage', 'pre-start amendment (panels)', 'file', '39_att_b7_b8_prefreeze_amendments.sql',
  'note', 'Before att_anom_start. (B5) Duplicate panels of the same data from two engine generations are skipped: dol.claims ic and cw (engine 6.2, '
       || '2015+) duplicate ic_w and cw_w (engine 6.3, 2010+). Rule: skip a panel when the same source has <metric>_w for the same geography. Scan set: '
       || 'every remaining state / BA weekly or monthly panel (cdc.deaths all_w; census.bfs ba; dol.claims ic_w, cw_w; fema.decl n_w [positive control]; '
       || 'eia.930 demand_w; fred.state bppriv, cons, dom, eduh, fire, govt, leih, listings, mfg, newlist, nonfarm, pbsv, srvo, trad, ur). Daily weather and '
       || 'declaration panels stay out (they define shocks rather than measure outcomes).'),
  jsonb_build_object('skipped', jsonb_build_array('dol.claims:ic', 'dol.claims:cw')));
