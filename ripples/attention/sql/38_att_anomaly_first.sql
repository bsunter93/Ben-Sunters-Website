-- Anomaly-first discovery (b8), 2026-09-27.
--
-- Owner direction (2026-09-27): "it can't be based on a rigid list, the chance of the overlap is too small. Start at the
-- anomalies, whatever they might be, and see if there are links you can draw and attribution that can be made."
--
-- Every earlier batch started from a hand-written list of shock -> outcome pairs, so it could only find links someone
-- had already thought of. This lane starts from the data:
--
--   1. SCAN. For every regional panel (state or balancing-authority; weekly or monthly), each place's value is compared
--      with the same period a year earlier (removes seasonality), then the same-period median across all places is
--      subtracted (removes national swings: recessions, the pandemic, holidays), then scored against that place's own
--      robust spread (median / 1.4826 MAD). |z| >= 3.5 is an anomaly. No shock is looked at.
--   2. WORK BACKWARDS, IN AGGREGATE. For each kind of shock and each panel: of the places a shock hit, how often did an
--      anomaly of each sign appear 0-1, 2-4, 5-12, 13-26 weeks (0-1, 2-3, 4-6, 7-12 months) later? One anomaly after one
--      shock proves nothing (something is always odd somewhere); the evidence is a REPEAT across many shocks.
--   3. FAKE SHOCKS SET THE BAR. The same shocks are replayed 100 times at the same calendar position in other years of the
--      panel, same places (each shock moves as a unit, so shared-footprint correlation is kept). The observed rate is
--      compared with that null (normal approximation over draws; the empirical rank is stored too). Seasonality is
--      handled by construction: the null is season-matched.
--   4. SCREEN, THEN CONFIRM. The screen uses shocks before the split date (2024-01-01), including historical shocks
--      (engine63.hist_batches). Benjamini-Hochberg over every hypothesis the screen produced; promoted if q <= 0.10,
--      enrichment >= 1.5x, >= 8 hit places and >= 10 shocks. The promoted list is frozen in the ledger, then each is
--      re-tested once on held-out shocks (on/after the split): confirmed if one-sided p <= 0.05 and enrichment >= 1.2x.
--      Links whose outcome defines the shock (FEMA declarations for FEMA-defined families) are kept as positive
--      controls and flagged, never published as findings.
--   5. ATTRIBUTION FOR A SINGLE SHOCK (story layer, later): anomalies in a shock's footprint after it are "attributed"
--      only when their (shock kind, outcome, timing, direction) link is confirmed; "consistent with a pattern" when only
--      screened; otherwise "unexplained" -- shown as such, never assigned.
-- Regime exclusions (pandemic, 2008-09) drop any place-window touching them, for real and fake shocks alike.
-- Lane 2 (not in this file): national series without geography (Wikipedia, news, social, markets), time-only design.

create table if not exists ripples.att_anom (
  source text not null, metric text not null, geo_kind text not null, region text not null, i int not null, t date not null, z real not null,
  primary key (source, metric, geo_kind, region, i));
create table if not exists ripples.att_anom_hyp (
  run text not null, stage text not null, family text not null, sub text not null default '', source text not null, metric text not null,
  geo_kind text not null, bucket int not null, sign smallint not null, n_events int, n_units int, hits int, obs real, null_mean real,
  null_sd real, p real, p_emp real, enrich real, q real, promoted boolean, definitional boolean, verdict text, computed_at timestamptz default now(),
  primary key (run, stage, family, sub, source, metric, geo_kind, bucket, sign));
create table if not exists ripples.att_anom_queue (
  run text not null, stage text not null, family text not null, sub text not null default '', source text not null, metric text not null,
  geo_kind text not null, status text not null default 'queued', note text, done_at timestamptz,
  primary key (run, stage, family, sub, source, metric, geo_kind));
alter table ripples.att_anom enable row level security;
alter table ripples.att_anom_hyp enable row level security;
alter table ripples.att_anom_queue enable row level security;
revoke all on ripples.att_anom, ripples.att_anom_hyp, ripples.att_anom_queue from anon, authenticated, public;

-- 1. scan one panel -------------------------------------------------------------------------------------------------
create or replace function ripples.att_anom_scan(p_source text, p_metric text, p_geo_kind text, p_thr real default 3.5) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare pan record; lagn int; k int;
begin
  select * into pan from ripples.att_fx_panel p where p.source = p_source and p.metric = p_metric and p.geo_kind = p_geo_kind;
  if pan.source is null or pan.grain not in ('week', 'month') then return jsonb_build_object('skip', true); end if;
  lagn := case pan.grain when 'week' then 52 else 12 end;
  delete from ripples.att_anom a where a.source = p_source and a.metric = p_metric and a.geo_kind = p_geo_kind;
  insert into ripples.att_anom(source, metric, geo_kind, region, i, t, z)
  with u as (
    select r.region, g.i, pan.days[g.i] t,
           case when pan.pc[r.ri][g.i] - coalesce(pan.pc[r.ri][g.i - 1], 0) = 1 then pan.ps[r.ri][g.i] - coalesce(pan.ps[r.ri][g.i - 1], 0) end y
      from unnest(pan.regions) with ordinality r0(region, ri0) cross join lateral (select r0.region, r0.ri0::int ri) r, generate_series(1, pan.n) g(i)),
  d as (select u.region, u.i, u.t, u.y - lag(u.y, lagn) over (partition by u.region order by u.i) x from u),
  c as (select d.i, percentile_cont(0.5) within group (order by d.x) cm, count(d.x) nx from d where d.x is not null group by d.i),
  e as (select d.region, d.i, d.t, d.x - c.cm xr from d join c on c.i = d.i where d.x is not null and c.nx >= 5),
  s as (select e.region, percentile_cont(0.5) within group (order by e.xr) med from e group by e.region),
  m as (select e.region, s.med, percentile_cont(0.5) within group (order by abs(e.xr - s.med)) mad, stddev_samp(e.xr) sd
          from e join s on s.region = e.region group by e.region, s.med),
  -- sparse count series (e.g. FEMA declarations: zero most weeks) have MAD = 0; fall back to the standard deviation
  -- (amendment before any real result, ledger: smoke test on the positive control found 0 anomalies)
  zz as (select e.region, e.i, e.t, (e.xr - m.med) / coalesce(nullif(1.4826 * m.mad, 0), nullif(m.sd, 0)) z from e join m on m.region = e.region)
  select p_source, p_metric, p_geo_kind, zz.region, zz.i, zz.t, zz.z from zz where abs(zz.z) >= p_thr;
  get diagnostics k = row_count;
  return jsonb_build_object('source', p_source, 'metric', p_metric, 'geo_kind', p_geo_kind, 'grain', pan.grain, 'anomalies', k);
end $$;

-- 2 + 3. work backwards from anomalies to one kind of shock, against season-matched fake shocks -------------------------
create or replace function ripples.att_anom_link(p_run text, p_family text, p_sub text, p_source text, p_metric text, p_geo_kind text,
                                                 p_stage text, p_k int default 100) returns int
language plpgsql security definer set search_path = '' as $$
declare pan record; lagn int; lo int[]; hi int[]; v_split date; reg jsonb; n_ins int; defn boolean;
begin
  select * into pan from ripples.att_fx_panel p where p.source = p_source and p.metric = p_metric and p.geo_kind = p_geo_kind;
  if pan.source is null or pan.grain not in ('week', 'month') then return 0; end if;
  if pan.grain = 'week' then lagn := 52; lo := array[0, 2, 5, 13]; hi := array[1, 4, 12, 26];
  else lagn := 12; lo := array[0, 2, 4, 7]; hi := array[1, 3, 6, 12]; end if;
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
  -- k = 0: the real shocks. k >= 1: each shock moved, as a whole, to the same calendar position in another year.
  create temp table _ad on commit drop as
    with evs as (select distinct a.event_id, a.i0 from _au a),
    cand as (select evs.event_id, evs.i0 + s * lagn i0k, s from evs, generate_series(-25, 25) s
              where s <> 0 and evs.i0 + s * lagn > lagn + 1 and evs.i0 + s * lagn + hi[4] <= pan.n),
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
  ge as (select o.b, o.sign, count(*) filter (where r.r >= o.r) nge from o join rate r on r.b = o.b and r.sign = o.sign and r.k > 0 group by o.b, o.sign)
  insert into ripples.att_anom_hyp(run, stage, family, sub, source, metric, geo_kind, bucket, sign, n_events, n_units, hits, obs,
                                   null_mean, null_sd, p, p_emp, enrich, definitional, computed_at)
  select p_run, p_stage, p_family, p_sub, p_source, p_metric, p_geo_kind, o.b, o.sign, o.ne, o.nu, o.hits, o.r, nl.m, nl.s,
         case when nl.s > 0 then 1 - ripples.att_norm_cdf(((o.r - nl.m) / nl.s)::float8) when o.r > nl.m then 0 else 1 end,
         (1 + coalesce(ge.nge, 0))::real / (1 + nl.nk), case when nl.m > 0 then o.r / nl.m end, defn, now()
    from o join nl on nl.b = o.b and nl.sign = o.sign left join ge on ge.b = o.b and ge.sign = o.sign
  on conflict (run, stage, family, sub, source, metric, geo_kind, bucket, sign) do update set
    n_events = excluded.n_events, n_units = excluded.n_units, hits = excluded.hits, obs = excluded.obs, null_mean = excluded.null_mean,
    null_sd = excluded.null_sd, p = excluded.p, p_emp = excluded.p_emp, enrich = excluded.enrich, definitional = excluded.definitional, computed_at = now();
  get diagnostics n_ins = row_count;
  return n_ins;
end $$;

-- 4. driver ---------------------------------------------------------------------------------------------------------
-- start: scan every regional weekly/monthly panel, queue the screen (every shock kind with >= 10 events x every panel),
-- and write the frozen task list to the ledger before any link is computed.
create or replace function ripples.att_anom_start(p_run text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare pan record; scans jsonb := '[]'::jsonb; n int; v_seq bigint;
begin
  if exists (select 1 from ripples.att_anom_queue where run = p_run) then return jsonb_build_object('already_started', p_run); end if;
  for pan in select source, metric, geo_kind from ripples.att_fx_panel where geo_kind in ('state', 'ba') and grain in ('week', 'month') order by 1, 2, 3 loop
    scans := scans || jsonb_build_array(ripples.att_anom_scan(pan.source, pan.metric, pan.geo_kind));
  end loop;
  insert into ripples.att_anom_queue(run, stage, family, sub, source, metric, geo_kind)
    select p_run, 'explore', f.family, f.sub, p.source, p.metric, p.geo_kind
      from (select e.family, '' sub from ripples.att_events e where e.role in ('library', 'library_hist') group by e.family having count(*) >= 10
            union all select 'hazard.storm', 'hurricane') f
      cross join (select source, metric, geo_kind from ripples.att_fx_panel where geo_kind in ('state', 'ba') and grain in ('week', 'month')) p
    on conflict do nothing;
  get diagnostics n = row_count;
  v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'anom_run', 'run', p_run, 'stage', 'screen',
             'n_tasks', n, 'n_anomalies', (select count(*) from ripples.att_anom), 'split_date', ripples._att_cfg('engine63') ->> 'split_date'),
             jsonb_build_object('scans', scans, 'tasks', (select jsonb_agg(jsonb_build_array(family, sub, source, metric, geo_kind) order by family, sub, source, metric, geo_kind)
                                                          from ripples.att_anom_queue where run = p_run)));
  return jsonb_build_object('run', p_run, 'tasks', n, 'scans', scans, 'ledger', v_seq);
end $$;

-- tick: one task per call; after the screen, BH + promotion (frozen to the ledger), then the confirmation tasks, then verdicts.
create or replace function ripples.att_anom_tick(p_run text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record; n int; v_seq bigint; v_m int;
begin
  select * into t from ripples.att_anom_queue where run = p_run and status = 'queued' order by stage desc, family, sub, source, metric limit 1 for update skip locked;
  if t.run is not null then
    update ripples.att_anom_queue set status = 'running' where run = t.run and stage = t.stage and family = t.family and sub = t.sub and source = t.source and metric = t.metric and geo_kind = t.geo_kind;
    n := ripples.att_anom_link(p_run, t.family, t.sub, t.source, t.metric, t.geo_kind, t.stage);
    update ripples.att_anom_queue set status = 'done', note = n || ' rows', done_at = now()
     where run = t.run and stage = t.stage and family = t.family and sub = t.sub and source = t.source and metric = t.metric and geo_kind = t.geo_kind;
    return jsonb_build_object('task', t.stage || ' ' || t.family || coalesce('/' || nullif(t.sub, ''), '') || ' x ' || t.source || ':' || t.metric, 'rows', n);
  end if;
  if exists (select 1 from ripples.att_anom_queue where run = p_run and status = 'running') then return jsonb_build_object('waiting', true); end if;
  -- screen finished and not yet promoted: BH across every screen hypothesis, promote, freeze the list, queue confirmation
  if not exists (select 1 from ripples.att_anom_queue where run = p_run and stage = 'confirm')
     and not exists (select 1 from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted is not null) then
    with r as (select family, sub, source, metric, geo_kind, bucket, sign, p, row_number() over (order by p) rk, count(*) over () m
                 from ripples.att_anom_hyp where run = p_run and stage = 'explore' and p is not null),
    q as (select r.*, min(p * m / rk) over (order by rk desc rows between unbounded preceding and current row) qv from r)
    update ripples.att_anom_hyp h set q = least(1, q.qv),
           promoted = (q.qv <= 0.10 and h.enrich >= 1.5 and h.hits >= 8 and h.n_events >= 10)
      from q where h.run = p_run and h.stage = 'explore' and h.family = q.family and h.sub = q.sub and h.source = q.source and h.metric = q.metric
       and h.geo_kind = q.geo_kind and h.bucket = q.bucket and h.sign = q.sign;
    update ripples.att_anom_hyp set promoted = false where run = p_run and stage = 'explore' and promoted is null;
    select count(*) into v_m from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted;
    v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'anom_run', 'run', p_run, 'stage', 'promote', 'n_promoted', v_m,
               'rule', 'BH q <= 0.10, enrichment >= 1.5, hits >= 8, shocks >= 10; confirm: one-sided p <= 0.05 and enrichment >= 1.2 on shocks on/after split'),
               (select coalesce(jsonb_agg(jsonb_build_array(family, sub, source, metric, geo_kind, bucket, sign, round(enrich::numeric, 3), round(q::numeric, 5)) order by q), '[]'::jsonb)
                  from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted));
    insert into ripples.att_anom_queue(run, stage, family, sub, source, metric, geo_kind)
      select distinct p_run, 'confirm', family, sub, source, metric, geo_kind from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted
    on conflict do nothing;
    return jsonb_build_object('promoted', v_m, 'ledger', v_seq);
  end if;
  -- confirmation finished: verdicts on the promoted hypotheses only (once; a 'done' marker ends the run)
  if not exists (select 1 from ripples.att_anom_queue where run = p_run and stage = 'done') then
    update ripples.att_anom_hyp e set verdict = case
        when c.run is null or c.n_events < 5 then 'too few held-out shocks'
        when c.p <= 0.05 and c.enrich >= 1.2 then case when e.definitional then 'confirmed (positive control)' else 'confirmed' end
        else 'not confirmed' end
      from ripples.att_anom_hyp e2 left join ripples.att_anom_hyp c
        on c.run = e2.run and c.stage = 'confirm' and c.family = e2.family and c.sub = e2.sub and c.source = e2.source and c.metric = e2.metric
       and c.geo_kind = e2.geo_kind and c.bucket = e2.bucket and c.sign = e2.sign
     where e.run = p_run and e.stage = 'explore' and e.promoted and e2.run = e.run and e2.stage = e.stage and e2.family = e.family and e2.sub = e.sub
       and e2.source = e.source and e2.metric = e.metric and e2.geo_kind = e.geo_kind and e2.bucket = e.bucket and e2.sign = e.sign;
    v_seq := ripples.att_ledger_append(current_date, 'register', jsonb_build_object('object', 'anom_run', 'run', p_run, 'stage', 'verdicts',
               'n_confirmed', (select count(*) from ripples.att_anom_hyp where run = p_run and stage = 'explore' and verdict like 'confirmed%')),
               (select coalesce(jsonb_agg(jsonb_build_array(family, sub, source, metric, bucket, sign, verdict) order by verdict, family), '[]'::jsonb)
                  from ripples.att_anom_hyp where run = p_run and stage = 'explore' and promoted));
    insert into ripples.att_anom_queue(run, stage, family, sub, source, metric, geo_kind, status, done_at)
      values (p_run, 'done', '-', '', '-', '-', '-', 'done', now()) on conflict do nothing;
    return jsonb_build_object('verdicts', true, 'ledger', v_seq);
  end if;
  return jsonb_build_object('complete', true);
end $$;
revoke all on function ripples.att_anom_scan(text, text, text, real), ripples.att_anom_link(text, text, text, text, text, text, text, int),
  ripples.att_anom_start(text), ripples.att_anom_tick(text) from anon, authenticated, public;

-- the run starts only when engine63.anom_go is set (after historical shocks and the b6 panels exist); one task a minute
select cron.schedule('att-anom-b8', '* * * * *', $c$
  set statement_timeout = '110s';
  select ripples.att_anom_tick('b8-anomaly-first')
   where coalesce((ripples._att_cfg('engine63') ->> 'anom_go')::boolean, false)
     and exists (select 1 from ripples.att_anom_queue where run = 'b8-anomaly-first')
     and not exists (select 1 from ripples.att_anom_queue where run = 'b8-anomaly-first' and stage = 'done')
$c$);

-- pre-registration (before any anomaly is computed or any link is looked at)
select ripples.att_ledger_append(current_date, 'register', jsonb_build_object(
  'object', 'anom_run', 'run', 'b8-anomaly-first', 'stage', 'pre-registration', 'file', '38_att_anomaly_first.sql',
  'note', 'anomaly-first discovery lane, declared before any anomaly is computed: scan every regional weekly/monthly panel (year-over-year change, '
       || 'minus the same-period cross-place median, robust z vs the place''s own spread; |z| >= 3.5); for every shock kind with >= 10 events '
       || '(library + library_hist) x every panel x 4 lag windows x 2 signs, the share of hit places with an anomaly vs 100 season-matched fake-shock replays '
       || '(whole shock shifted to the same calendar position in another year); screen on shocks before 2024-01-01; BH q <= 0.10, enrichment >= 1.5, '
       || 'hits >= 8, shocks >= 10 -> promoted list frozen in the ledger -> one re-test on held-out shocks on/after 2024-01-01 (one-sided p <= 0.05, '
       || 'enrichment >= 1.2). Regime windows (pandemic, 2008-09) excluded for real and fake shocks. FEMA declarations for FEMA-defined families are '
       || 'positive controls, never findings. Single-shock attribution uses confirmed links only; other anomalies are shown as unexplained.'),
  jsonb_build_object('thr', 3.5, 'k_null', 100, 'buckets_week', '[[0,1],[2,4],[5,12],[13,26]]'::jsonb, 'buckets_month', '[[0,1],[2,3],[4,6],[7,12]]'::jsonb));
