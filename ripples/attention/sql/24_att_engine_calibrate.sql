-- Migration: att_engine_calibrate (WS-B, Ripple Map v6, 2026-09-25)
-- ENGINE_SPEC §5.5 circuit breaker, §5.6 calibration proof (decoy realised FDR with Wilson intervals, KS on 500 held-out pairs,
-- spike-in power curves in SQL, positive/negative controls, forward Receipts, re-fire), §5.7 time split (edge-prior refit),
-- §4.5 route verification and dose-response with 10k permutations, att_calibration_public (CalibrationPayload, §11),
-- and the deploy gate att_run_controls(). Depends on 20–23.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Small statistics helpers
-- ---------------------------------------------------------------------------------------------------------------------
-- Wilson score interval (default 90 %: z = 1.6449)
create or replace function ripples.att_wilson(p_k bigint, p_n bigint, p_z float8 default 1.6449) returns jsonb
language sql immutable set search_path = '' as $$
  select case when p_n is null or p_n = 0 then jsonb_build_object('rate', null, 'lo', null, 'hi', null, 'n', 0)
  else (select jsonb_build_object('rate', ph, 'n', p_n,
           'lo', greatest(0, (ph + z2 / (2 * p_n) - p_z * sqrt(ph * (1 - ph) / p_n + z2 / (4 * p_n * p_n))) / (1 + z2 / p_n)),
           'hi', least(1, (ph + z2 / (2 * p_n) + p_z * sqrt(ph * (1 - ph) / p_n + z2 / (4 * p_n * p_n))) / (1 + z2 / p_n)))
        from (select p_k::float8 / p_n ph, p_z * p_z z2) q) end
$$;

-- Kolmogorov distribution tail P(K > x) (asymptotic series), for the KS test of p-values against Uniform(0,1)
create or replace function ripples.att_ks_pvalue(p_d float8, p_n int) returns float8
language plpgsql immutable set search_path = '' as $$
declare x float8; s float8 := 0; k int; term float8;
begin
  if p_n is null or p_n < 5 or p_d is null then return null; end if;
  x := (sqrt(p_n) + 0.12 + 0.11 / sqrt(p_n)) * p_d;
  for k in 1..100 loop
    term := 2 * power(-1, k - 1) * exp(-2 * k * k * x * x);
    s := s + term;
    exit when abs(term) < 1e-10;
  end loop;
  return least(1, greatest(0, s));
end $$;

-- KS statistic and 20-bin histogram for a set of p-values
create or replace function ripples.att_ks_uniform(p_vals float8[]) returns jsonb
language sql immutable set search_path = '' as $$
  with v as (select x, row_number() over (order by x) i, count(*) over () n from unnest(p_vals) x where x is not null),
  d as (select max(greatest(i::float8 / n - x, x - (i - 1)::float8 / n)) d, max(n) n from v),
  h as (select jsonb_agg(c order by b) hist from (select b, count(x) c from generate_series(0, 19) b left join v on floor(least(v.x, 0.99999) * 20) = b group by b) q)
  select jsonb_build_object('stat', d.d, 'p', ripples.att_ks_pvalue(d.d, d.n::int), 'n', d.n, 'hist', h.hist) from d, h
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Held-out null pairs (ENGINE §5.6.2): a random panel series × a past real event of an unrelated family, p from the date family
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_heldout_p(p_series bigint, p_onset date, p_end date, p_draws int default 200) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare bundle jsonb; b record; res jsonb; t_h float8; d date; tv float8; exceed int := 0; n int := 0; lo date; hi date; stopped boolean := false;
        cfg jsonb := coalesce(ripples._att_cfg('engine'), '{}'::jsonb); bc int := coalesce((cfg ->> 'bc_stop')::int, 10); dd date[] := '{}'; k int; gate boolean;
begin
  perform ripples.att_hb_load(array[p_series]);
  select * into b from _hb where series_id = p_series;
  if not found then return jsonb_build_object('p', null, 'reason', 'no zvec'); end if;
  bundle := jsonb_build_array(jsonb_build_object('series_id', p_series, 'channel', b.channel));
  res := ripples.att_hop_stat_b(bundle, p_onset, p_end, 0, '{}', null, false);
  t_h := (res ->> 'T')::float8;
  if t_h is null then return jsonb_build_object('p', null, 'reason', 'no statistic'); end if;
  gate := coalesce((res ->> 's_pre')::float8, 0) < 2;           -- same gate rule as att_run_placebos
  lo := b.from_day + 112; hi := b.from_day + b.n - 1 - (p_end - p_onset) - 30;
  d := lo;
  while d <= hi loop
    if abs(d - p_onset) >= 30 then dd := dd || d; end if;
    d := d + 1;
  end loop;
  select coalesce(array_agg(x order by encode(extensions.digest(x::text || p_series::text, 'sha256'), 'hex')), '{}') into dd from unnest(dd) x;
  for k in 1..least(cardinality(dd), p_draws) loop
    res := ripples.att_hop_stat_b(bundle, dd[k], dd[k] + (p_end - p_onset), 0, '{}', null, false);
    tv := (res ->> 'T')::float8;
    continue when tv is null;
    n := n + 1;
    if tv >= t_h and ((not gate) or coalesce((res ->> 's_pre')::float8, 0) < 2) then exceed := exceed + 1; end if;
    if exceed >= bc then stopped := true; exit; end if;
  end loop;
  if n < 30 then return jsonb_build_object('p', null, 'reason', 'few draws', 'n', n); end if;
  return jsonb_build_object('p', case when stopped then bc::float8 / n else (1 + exceed)::float8 / (1 + n) end, 'n', n, 't', t_h, 'exceed', exceed);
end $$;

create or replace function ripples.att_calibrate_ks(p_as_of date, p_n int default 500) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; ps float8[] := '{}'; j jsonb; n_try int := 0;
begin
  for r in
    select z.series_id, e.onset, e.family, ripples.att_series_channel(z.series_id) ch
    from ripples.att_zvec z join ripples.att_series s on s.series_id = z.series_id
    join ripples.att_events e on e.role = 'real' and e.topic_id is distinct from s.topic_id and e.onset <= p_as_of - 40 and e.onset >= z.from_day + 120
    where z.grain = 'day' and z.kappa >= 0.5 and s.key <> '__total__' and (s.topic_id is null or exists (select 1 from ripples.att_topics t where t.topic_id = s.topic_id and t.in_panel))
      and not exists (select 1 from ripples.att_hop_candidates c where c.event_id = e.event_id and c.v_topic = s.topic_id)
    order by encode(extensions.digest(z.series_id::text || e.event_id::text || p_as_of::text, 'sha256'), 'hex')
    limit p_n * 2
  loop
    exit when cardinality(ps) >= p_n;
    n_try := n_try + 1;
    j := ripples.att_heldout_p(r.series_id, r.onset, r.onset + ripples.att_l_days(r.ch), 200);
    if (j ->> 'p') is not null then ps := ps || (j ->> 'p')::float8; end if;
  end loop;
  return ripples.att_ks_uniform(ps) || jsonb_build_object('tried', n_try);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Spike-in power curves (ENGINE §5.6.3): +δσ responses with lag ℓ and half-life injected into copies of real panel arrays
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_spikein(p_as_of date, p_per_channel int default 25) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; delta float8; lagv int; hl float8; ar real[]; i int; t0 date; i0 int; v_kind text; l int; sdj jsonb; s jsonb; zs float8;
        p float8; hit boolean; sd real; mu real; d date; n_d int; ex int; tv float8; out jsonb := '[]'::jsonb; done int;
begin
  create temp table if not exists _sp (channel text, delta float8, lag int, hl float8, tested int default 0, hits int default 0, primary key (channel, delta, lag, hl)) on commit drop;
  truncate _sp;
  for r in
    select z.series_id, z.from_day, z.n, z.ar, z.resid, cs.channel, cs.stat_kind, cs.kind = 'attention' att
    from ripples.att_zvec z join ripples.att_series s on s.series_id = z.series_id
    join ripples.att_channel_stat cs on cs.channel = ripples.att_series_channel(z.series_id)
    where z.grain = 'day' and z.kappa >= 0.5 and s.key <> '__total__' and cs.channel <> 'MONEY'
    order by cs.channel, encode(extensions.digest(z.series_id::text || p_as_of::text, 'sha256'), 'hex')
  loop
    select coalesce(max(tested), 0) into done from _sp where channel = r.channel;
    continue when done >= p_per_channel;
    v_kind := r.stat_kind; l := ripples.att_l_days(r.channel);
    sdj := ripples.att_sd_null_calc(r.ar, r.from_day, r.n, l, v_kind, 1);
    continue when (sdj ->> 'sd') is null;
    sd := (sdj ->> 'sd')::real; mu := coalesce((sdj ->> 'mean')::real, 0);
    -- a clean past onset (deterministic), ≥ 140 d after the array start and ≥ 60 d before its end
    i0 := 140 + (abs(hashtext(r.series_id::text || p_as_of::text)) % greatest(1, r.n - 200));
    t0 := r.from_day + (i0 - 1);
    foreach delta in array array[1, 2, 3, 5] loop
      foreach lagv in array array[0, 1, 3, 7] loop
        foreach hl in array array[1, 3, 7] loop
          ar := r.ar;
          for i in i0 + lagv .. least(r.n, i0 + lagv + 30) loop
            if ar[i] is not null then ar[i] := ar[i] + delta * exp(-ln(2) * (i - i0 - lagv) / hl); end if;
          end loop;
          s := ripples.att_win_stat(ar, r.resid, r.from_day, r.n, t0, l, v_kind, 1, case when v_kind = 'car' then ripples.att_rho1(ar, r.from_day, r.n, t0) else 0 end, t0 + l, r.att);
          zs := case when (s ->> 'S') is null then null else ((s ->> 'S')::float8 - mu) / sd end;
          -- date-family p on the injected array (weekday-aligned shifts ≥ 30 d away)
          ex := 0; n_d := 0; d := t0 - 7 * 4;
          while n_d < 200 and d >= r.from_day + 112 loop
            if abs(d - t0) >= 30 then
              tv := (ripples.att_win_stat(ar, null, r.from_day, r.n, d, l, v_kind, 1, case when v_kind = 'car' then ripples.att_rho1(ar, r.from_day, r.n, d) else 0 end, d + l, false) ->> 'S')::float8;
              if tv is not null then n_d := n_d + 1; if (tv - mu) / sd >= zs then ex := ex + 1; end if; end if;
            end if;
            d := d - 7;
          end loop;
          p := case when n_d = 0 then null else (1 + ex)::float8 / (1 + n_d) end;
          hit := zs is not null and zs >= 3 and p is not null and p <= 0.05;
          insert into _sp(channel, delta, lag, hl, tested, hits) values (r.channel, delta, lagv, hl, 1, hit::int)
          on conflict (channel, delta, lag, hl) do update set tested = _sp.tested + 1, hits = _sp.hits + excluded.hits;
        end loop;
      end loop;
    end loop;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('channel', channel, 'delta', delta, 'lag', lag, 'half_life', hl, 'tested', tested, 'recall', round((hits::numeric / nullif(tested, 0)), 3)) order by channel, delta, lag, hl), '[]'::jsonb)
    into out from _sp;
  return out;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Decoy realised FDR, breaker, replication / dose / route, prior refit, Receipts, re-fire
-- ---------------------------------------------------------------------------------------------------------------------
-- Latest finalised look per hop (helper view)
create or replace view ripples.att_hop_latest with (security_invoker = true) as
  select distinct on (t.hop_id) t.*, c.role, c.event_id, c.path_type, c.depth, c.node, c.prior, c.reconstructed, c.parent_hop,
         coalesce((select k from jsonb_each(t.s_by_channel) e(k, v) where (v ->> 'zhat')::float8 >= 3
                   order by (select cs.kind from ripples.att_channel_stat cs where cs.channel = k) = 'outcome' desc, (v ->> 'zhat')::float8 desc limit 1),
                  c.channels[1], 'none') best_channel
  from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
  where t.tier is not null
  order by t.hop_id, t.look_no desc;

-- Decoy realised FDR per (path type × channel) cell and overall, trailing p_days (ENGINE §5.5 / §5.6.1 / §12.2).
-- p_scope 'live' (default; the public number), 'library' (reconstructed backfill) or 'all'. Library / positive-control events count as real.
drop function if exists ripples.att_decoy_fdr(date, int);
create or replace function ripples.att_decoy_fdr(p_as_of date, p_days int default 28, p_scope text default 'live') returns jsonb
language sql stable security definer set search_path = '' as $$
  with h as (
    select * from ripples.att_hop_latest where look_day between p_as_of - p_days and p_as_of and role in ('real','decoy','library','positive_control')
      and (p_scope = 'all' or (p_scope = 'live' and not reconstructed) or (p_scope = 'library' and reconstructed))),
  ev as (
    select count(distinct event_id) filter (where role = 'decoy') decoy_events, count(distinct event_id) filter (where role <> 'decoy') real_events from h),
  cells as (
    select path_type || '×' || best_channel cell,
           count(*) filter (where role = 'decoy') decoy_tested, count(*) filter (where role = 'decoy' and tier = 'measured') decoy_measured,
           count(*) filter (where role <> 'decoy') real_tested, count(*) filter (where role <> 'decoy' and tier = 'measured') real_measured
    from h group by 1),
  overall as (
    select count(*) filter (where role = 'decoy') decoy_tested, count(*) filter (where role = 'decoy' and tier = 'measured') decoy_measured,
           count(*) filter (where role <> 'decoy') real_tested, count(*) filter (where role <> 'decoy' and tier = 'measured') real_measured from h)
  select jsonb_build_object(
    'as_of', p_as_of, 'days', p_days, 'scope', p_scope,
    'overall', ripples.att_wilson(o.decoy_measured, o.decoy_tested) || jsonb_build_object('decoy_events', e.decoy_events, 'real_events', e.real_events,
                 'decoy_measured', o.decoy_measured, 'decoy_tested', o.decoy_tested, 'real_measured', o.real_measured, 'real_tested', o.real_tested,
                 'event_rate', case when e.decoy_events > 0 and o.real_measured > 0 then (o.decoy_measured::float8 / e.decoy_events) * (e.real_events::float8 / o.real_measured) end),
    'cells', (select coalesce(jsonb_agg(ripples.att_wilson(c.decoy_measured, c.decoy_tested) || jsonb_build_object('cell', c.cell, 'decoy_measured', c.decoy_measured, 'decoy_tested', c.decoy_tested,
                 'real_measured', c.real_measured, 'real_tested', c.real_tested,
                 'event_rate', case when e.decoy_events > 0 and c.real_measured > 0 then (c.decoy_measured::float8 / e.decoy_events) * (e.real_events::float8 / c.real_measured) end)
                 order by c.cell), '[]'::jsonb) from cells c))
  from overall o, ev e
$$;

-- Circuit breaker (ENGINE §5.5): per cell, daily; trips after 14 consecutive days over 2 × 0.05 or 2 bad KS weeks; restores after 14 days under 1.5 ×
create or replace function ripples.att_breaker_update(p_as_of date, p_ks_bad boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare fdr jsonb; c jsonb; rate float8; v_seq bigint; tripped int := 0; restored int := 0; b record;
begin
  fdr := ripples.att_decoy_fdr(p_as_of, 28);
  for c in select x from jsonb_array_elements(fdr -> 'cells') x loop
    rate := coalesce((c ->> 'event_rate')::float8, (c ->> 'rate')::float8);
    insert into ripples.att_breaker(cell) values (c ->> 'cell') on conflict (cell) do nothing;
    select * into b from ripples.att_breaker where cell = c ->> 'cell';
    if rate is not null and rate > 2 * 0.05 then
      update ripples.att_breaker set days_over = b.days_over + 1, days_under = 0, last_rate = rate, last_lo = (c ->> 'lo')::real, last_hi = (c ->> 'hi')::real,
             ks_bad_weeks = case when p_ks_bad then b.ks_bad_weeks + 1 else b.ks_bad_weeks end, updated_at = now() where cell = b.cell;
    else
      update ripples.att_breaker set days_over = 0, days_under = case when rate is null or rate <= 1.5 * 0.05 then b.days_under + 1 else 0 end,
             last_rate = rate, last_lo = (c ->> 'lo')::real, last_hi = (c ->> 'hi')::real,
             ks_bad_weeks = case when p_ks_bad then b.ks_bad_weeks + 1 else 0 end, updated_at = now() where cell = b.cell;
    end if;
    select * into b from ripples.att_breaker where cell = c ->> 'cell';
    if b.tripped_at is null and (b.days_over >= 14 or b.ks_bad_weeks >= 2) then
      update ripples.att_breaker set tripped_at = p_as_of, restored_at = null where cell = b.cell;
      v_seq := ripples.att_ledger_append(p_as_of, 'breaker', jsonb_build_object('cell', b.cell, 'action', 'trip'),
                 jsonb_build_object('cell', b.cell, 'day', p_as_of, 'rate', rate, 'days_over', b.days_over, 'ks_bad_weeks', b.ks_bad_weeks));
      tripped := tripped + 1;
    elsif b.tripped_at is not null and b.restored_at is null and b.days_under >= 14 then
      update ripples.att_breaker set restored_at = p_as_of, tripped_at = null, days_over = 0, ks_bad_weeks = 0 where cell = b.cell;
      v_seq := ripples.att_ledger_append(p_as_of, 'breaker', jsonb_build_object('cell', b.cell, 'action', 'restore'),
                 jsonb_build_object('cell', b.cell, 'day', p_as_of, 'rate', rate));
      restored := restored + 1;
    end if;
  end loop;
  return jsonb_build_object('tripped', tripped, 'restored', restored,
                            'open', (select coalesce(jsonb_agg(jsonb_build_object('cell', cell, 'since', tripped_at, 'rate', last_rate)), '[]'::jsonb)
                                     from ripples.att_breaker where tripped_at is not null and restored_at is null));
end $$;

-- Permutation p-value for the correlation between x and y (10k shuffles, deterministic LCG)
create or replace function ripples.att_perm_corr_p(p_x float8[], p_y float8[], p_perm int default 10000) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare n int := cardinality(p_x); i int; k int; j int; r0 float8; cnt int := 0; y float8[]; tmp float8; seed bigint := 12345;
        mx float8; my float8; sxy float8; sxx float8; syy float8;
begin
  if n < 4 or n <> cardinality(p_y) then return jsonb_build_object('r', null, 'p', null, 'n', n); end if;
  select avg(v) into mx from unnest(p_x) v; select avg(v) into my from unnest(p_y) v;
  sxy := 0; sxx := 0; syy := 0;
  for i in 1..n loop sxy := sxy + (p_x[i] - mx) * (p_y[i] - my); sxx := sxx + (p_x[i] - mx)^2; syy := syy + (p_y[i] - my)^2; end loop;
  if sxx <= 0 or syy <= 0 then return jsonb_build_object('r', null, 'p', null, 'n', n); end if;
  r0 := sxy / sqrt(sxx * syy);
  y := p_y;
  for k in 1..p_perm loop
    for i in reverse n..2 loop
      seed := (seed * 6364136223846793005 + 1442695040888963407) % 9223372036854775807;
      j := 1 + (abs(seed) % i)::int;
      tmp := y[i]; y[i] := y[j]; y[j] := tmp;
    end loop;
    sxy := 0;
    for i in 1..n loop sxy := sxy + (p_x[i] - mx) * (y[i] - my); end loop;
    if sxy / sqrt(sxx * syy) >= r0 then cnt := cnt + 1; end if;
  end loop;
  return jsonb_build_object('r', r0, 'p', (1 + cnt)::float8 / (1 + p_perm), 'n', n);
end $$;

-- Replication (§5.6.7), dose-response (§8 second clause) and route verification (§4.5) per (family, edge class, channel) on the
-- replication set (onset ≥ prior_cutoff, positive controls excluded). edge_class = the path's template (or first edge type → node source).
create or replace function ripples.att_replication_refresh(p_as_of date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cutoff date := coalesce((ripples._att_cfg('engine') ->> 'prior_cutoff')::date, '2026-01-01'); r record; xs float8[]; ys float8[]; dose jsonb; route text; rv jsonb;
        n_rows int := 0; one_off boolean;
begin
  delete from ripples.att_replication where as_of = p_as_of;
  for r in
    select ev.family, coalesce(c.path -> 0 ->> 'template', (c.path -> 0 ->> 'type') || '→' || split_part(c.node, ':', 1)) edge_class, h.best_channel channel,
           count(distinct ev.event_id) n, count(distinct ev.event_id) filter (where h.tier in ('likely','measured')) hits,
           array_agg(coalesce(ev.magnitude, 0) order by ev.event_id) mags, array_agg(coalesce(h.t_stat, 0) order by ev.event_id) ts,
           array_agg((h.tier in ('likely','measured')) order by ev.onset desc) hits_by_recency
    from ripples.att_hop_latest h join ripples.att_hop_candidates c on c.hop_id = h.hop_id join ripples.att_events ev on ev.event_id = c.event_id
    where ev.role in ('real','library') and ev.onset >= cutoff and h.is_final and h.depth = 1
    group by 1, 2, 3
  loop
    dose := case when r.n >= 8 then ripples.att_perm_corr_p(r.mags, r.ts, 10000) else null end;
    -- route verification needs a parent statistic (depth-2); for depth-1 classes the route is the direct edge: 'na'
    route := 'na';
    one_off := r.n >= 2 and not r.hits_by_recency[1] and not r.hits_by_recency[2];
    insert into ripples.att_replication(as_of, family, edge_class, channel, n, hits, p_dose, route, q_family, one_off)
    values (p_as_of, r.family, r.edge_class, r.channel, r.n, r.hits, (dose ->> 'p')::real, route, null, one_off);
    n_rows := n_rows + 1;
    if one_off then
      -- prior reset to the seed for that (etype, channel): the fitted row is retired (ENGINE §5.6.7)
      update ripples.att_edge_priors set fitted_to = p_as_of, tested = 0, measured = 0, prior = ripples.att_edge_prior(etype, channel, 'any')
       where not seeded and family = r.family and channel = r.channel;
    end if;
  end loop;
  -- depth-2 route verification: regress S_w on S_v and M_e across family events with n ≥ 8
  for r in
    select ev.family, coalesce(c.path -> 0 ->> 'template', (c.path -> 0 ->> 'type') || '→' || split_part(c.node, ':', 1)) edge_class, h.best_channel channel,
           count(distinct ev.event_id) n, count(distinct ev.event_id) filter (where h.tier in ('likely','measured')) hits,
           array_agg(coalesce(pv.t_stat, 0) order by ev.event_id) sv, array_agg(coalesce(h.t_stat, 0) order by ev.event_id) sw, array_agg(coalesce(ev.magnitude, 0) order by ev.event_id) mags
    from ripples.att_hop_latest h join ripples.att_hop_candidates c on c.hop_id = h.hop_id join ripples.att_events ev on ev.event_id = c.event_id
    join ripples.att_hop_latest pv on pv.hop_id = c.parent_hop
    where ev.role in ('real','library') and ev.onset >= cutoff and h.is_final and h.depth >= 2
    group by 1, 2, 3 having count(distinct ev.event_id) >= 8
  loop
    -- partial out M: residualise S_w and S_v on M (simple OLS), then permutation test on the residual correlation
    with m as (select unnest(r.mags) m, unnest(r.sv) sv, unnest(r.sw) sw),
    a as (select avg(m) mm, avg(sv) msv, avg(sw) msw from m),
    st as (select a.mm, a.msv, a.msw, sum((m.m - a.mm) * (m.sv - a.msv)) / nullif(sum((m.m - a.mm)^2), 0) bv, sum((m.m - a.mm) * (m.sw - a.msw)) / nullif(sum((m.m - a.mm)^2), 0) bw from m, a group by a.mm, a.msv, a.msw)
    select array_agg(m.sv - st.msv - coalesce(st.bv, 0) * (m.m - st.mm)), array_agg(m.sw - st.msw - coalesce(st.bw, 0) * (m.m - st.mm)) into xs, ys from m, st;
    rv := ripples.att_perm_corr_p(xs, ys, 10000);
    route := case when (rv ->> 'r')::float8 > 0 and (rv ->> 'p')::float8 <= 0.05 then 'solid' else 'dashed' end;
    insert into ripples.att_replication(as_of, family, edge_class, channel, n, hits, p_dose, route, q_family, one_off)
    values (p_as_of, r.family, 'via:' || r.edge_class, r.channel, r.n, r.hits, (rv ->> 'p')::real, route, null, false)
    on conflict (as_of, family, edge_class, channel) do update set route = excluded.route, p_dose = excluded.p_dose;
    n_rows := n_rows + 1;
  end loop;
  -- stamp current hops with their class replication
  update ripples.att_hop_tests t set replication = jsonb_build_object('family', rp.family, 'n', rp.n, 'hits', rp.hits, 'p_dose', rp.p_dose, 'route', rp.route, 'one_off', rp.one_off)
  from ripples.att_hop_latest h join ripples.att_hop_candidates c on c.hop_id = h.hop_id join ripples.att_events ev on ev.event_id = c.event_id
  join ripples.att_replication rp on rp.as_of = p_as_of and rp.family = ev.family and rp.channel = h.best_channel
       and rp.edge_class = coalesce(c.path -> 0 ->> 'template', (c.path -> 0 ->> 'type') || '→' || split_part(c.node, ':', 1))
  where t.hop_id = h.hop_id and t.look_no = h.look_no;
  return jsonb_build_object('as_of', p_as_of, 'rows', n_rows);
end $$;

-- Edge-prior refit under the time split (ENGINE §2.1 / §5.7): only library events with onset < prior_cutoff; ≥ 30 resolved hops per cell
create or replace function ripples.att_priors_refit(p_as_of date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cutoff date := coalesce((ripples._att_cfg('engine') ->> 'prior_cutoff')::date, '2026-01-01'); r record; n int := 0; ver text := '6.0-' || to_char(p_as_of, 'YYYYMMDD');
begin
  for r in
    select c.path -> 0 ->> 'type' etype, h.best_channel channel, ev.family, count(*) tested, count(*) filter (where h.tier = 'measured') measured
    from ripples.att_hop_latest h join ripples.att_hop_candidates c on c.hop_id = h.hop_id join ripples.att_events ev on ev.event_id = c.event_id
    where ev.role = 'library' and ev.onset < cutoff and h.is_final
    group by grouping sets ((1, 2, 3), (1, 2))
    having count(*) >= 30
  loop
    insert into ripples.att_edge_priors(etype, channel, family, tested, measured, prior, seeded, fitted_to, version)
    values (r.etype, r.channel, coalesce(r.family, 'any'), r.tested, r.measured, (1 + r.measured)::float8 / (2 + r.tested), false, cutoff, ver)
    on conflict (etype, channel, family, version) do update set tested = excluded.tested, measured = excluded.measured, prior = excluded.prior, fitted_to = excluded.fitted_to;
    n := n + 1;
  end loop;
  return jsonb_build_object('as_of', p_as_of, 'cells', n, 'cutoff', cutoff, 'version', ver);
end $$;

-- Weekly L_c re-estimation: 90th percentile of Measured lags once a channel has ≥ 30 Measured hops (ENGINE §3.6)
create or replace function ripples.att_lag_windows_refresh(p_as_of date) returns int
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in select h.best_channel ch, count(*) n, percentile_cont(0.9) within group (order by h.lag_days) l90
           from ripples.att_hop_latest h where h.tier = 'measured' and h.lag_days is not null and h.role = 'real' group by 1 having count(*) >= 30 loop
    insert into ripples.att_lag_windows(channel, event_type, l_days, n, as_of) values (r.ch, 'any', greatest(1, r.l90), r.n, p_as_of)
    on conflict (channel, event_type) do update set l_days = excluded.l_days, n = excluded.n, as_of = excluded.as_of;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Channel correlation R̂ from real hop tests' channel ž over 180 days (≥ 100 rows), stored for att_channel_r (shrunk at read time)
create or replace function ripples.att_channel_corr_refresh(p_as_of date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare chans text[]; i int; j int; m float8[][]; n int; v float8;
begin
  select array_agg(distinct k order by k) into chans from ripples.att_hop_latest h, jsonb_object_keys(h.s_by_channel) k
   where h.look_day >= p_as_of - 180 and h.role = 'real';
  if chans is null or cardinality(chans) < 2 then return jsonb_build_object('skipped', 'too few channels'); end if;
  select count(*) into n from ripples.att_hop_latest h where h.look_day >= p_as_of - 180 and h.role = 'real';
  if n < 100 then return jsonb_build_object('skipped', 'fewer than 100 rows', 'n', n); end if;
  m := array_fill(0::float8, array[cardinality(chans), cardinality(chans)]);
  for i in 1..cardinality(chans) loop
    for j in 1..cardinality(chans) loop
      select corr((h.s_by_channel -> chans[i] ->> 'zhat')::float8, (h.s_by_channel -> chans[j] ->> 'zhat')::float8) into v
        from ripples.att_hop_latest h where h.look_day >= p_as_of - 180 and h.role = 'real' and h.s_by_channel ? chans[i] and h.s_by_channel ? chans[j];
      m[i][j] := case when i = j then 1 else coalesce(v, 0) end;
    end loop;
  end loop;
  insert into ripples.att_channel_corr(as_of, channels, r, sd_null) values (p_as_of, chans, m::real[][], '{}'::jsonb)
  on conflict (as_of) do update set channels = excluded.channels, r = excluded.r;
  return jsonb_build_object('as_of', p_as_of, 'channels', chans, 'n', n);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Controls (ENGINE §5.6.4–5.6.5) and the deploy gate
-- ---------------------------------------------------------------------------------------------------------------------
-- Positive-control fixtures (spec: event + expected Measured nodes). Library runs are WS-E's; the gate re-runs each fixture here.
-- QIDs are left null where not verified from Wikidata; the fixtures are keyed by mapper targets (nodes), not by the shock's own series.
insert into ripples.att_controls(kind, spec)
select 'positive', x::jsonb from (values
 ('{"name":"Helene → TSA / FEMA / IEM","qid":null,"label":"Hurricane Helene","family":"hazard.storm","onset":"2024-09-26","expect":["tsa.pax:checkpoint","fema.decl:DR","iem.warn:__total__"],"any_of":true}'),
 ('{"name":"Milton → TSA / FEMA / IEM","qid":null,"label":"Hurricane Milton","family":"hazard.storm","onset":"2024-10-07","expect":["tsa.pax:checkpoint","fema.decl:DR","iem.warn:__total__"],"any_of":true}'),
 ('{"name":"ChatGPT launch → npm openai / HN","qid":"Q115564437","label":"ChatGPT","family":"tech.model_release","onset":"2022-11-30","expect":["npm.dl:openai","hn.algolia:chatgpt"],"any_of":true}'),
 ('{"name":"Texas heat dome → ERCOT demand","qid":null,"label":"July 2023 Texas heat dome","family":"hazard.heat","onset":"2023-07-10","expect":["eia.930:ERCO"],"any_of":true}'),
 ('{"name":"Llama 3 release → HF / npm / pypi","qid":null,"label":"Llama 3","family":"tech.model_release","onset":"2024-04-18","expect":["pypi.dl:transformers","hf.trending:models"],"any_of":true}'),
 ('{"name":"DeepSeek-R1 release → HF / pypi","qid":null,"label":"DeepSeek-R1","family":"tech.model_release","onset":"2025-01-20","expect":["pypi.dl:transformers","hn.algolia:deepseek"],"any_of":true}')) v(x)
where not exists (select 1 from ripples.att_controls k where k.kind = 'positive' and k.spec ->> 'name' = (x::jsonb ->> 'name'));

-- Run one positive control through library mode and check the expected node reached Measured
create or replace function ripples.att_run_positive_control(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k record; ev bigint; res jsonb; ok boolean := false; nodes jsonb; got jsonb; x text; missing text[] := '{}';
begin
  select * into k from ripples.att_controls where id = p_id and kind = 'positive';
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such control'); end if;
  ev := ripples.att_library_event(k.spec ->> 'qid', k.spec ->> 'label', k.spec ->> 'family', (k.spec ->> 'onset')::date, 'positive_control');
  res := ripples.att_run_library(ev);
  select coalesce(jsonb_agg(jsonb_build_object('node', h.node, 'tier', h.tier, 'q', h.q_w, 'T', h.t_stat, 'reason', h.tier_reason, 'fails', h.detail -> 'fails')), '[]'::jsonb)
    into nodes from ripples.att_hop_latest h where h.event_id = ev;
  got := '[]'::jsonb;
  for x in select jsonb_array_elements_text(k.spec -> 'expect') loop
    if exists (select 1 from ripples.att_hop_latest h where h.event_id = ev and h.node = x and h.tier = 'measured') then got := got || to_jsonb(x); else missing := array_append(missing, x); end if;
  end loop;
  ok := case when coalesce((k.spec ->> 'any_of')::boolean, false) then jsonb_array_length(got) > 0 else cardinality(missing) = 0 end;
  update ripples.att_controls set last_run = current_date, passed = ok,
         detail = jsonb_build_object('event_id', ev, 'measured', got, 'missing', to_jsonb(missing), 'nodes', nodes, 'run', res) where id = p_id;
  return jsonb_build_object('id', p_id, 'name', k.spec ->> 'name', 'ok', ok, 'measured', got, 'missing', to_jsonb(missing), 'event_id', ev);
end $$;

-- Deploy gate: every positive control Measured and the negative-control pass rate inside the decoys' Wilson interval; ledger 'control' row
create or replace function ripples.att_run_controls(p_strict boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k record; res jsonb := '[]'::jsonb; r jsonb; all_ok boolean := true; neg jsonb; neg_ok boolean; v_seq bigint;
        n_neg int; k_neg int; n_dec int; k_dec int; w jsonb;
begin
  for k in select id from ripples.att_controls where kind = 'positive' order by id loop
    begin
      r := ripples.att_run_positive_control(k.id);
    exception when others then
      r := jsonb_build_object('id', k.id, 'ok', false, 'error', left(sqlerrm, 300));
      update ripples.att_controls set last_run = current_date, passed = false, detail = jsonb_build_object('error', left(sqlerrm, 300)) where id = k.id;
    end;
    res := res || r;
    all_ok := all_ok and coalesce((r ->> 'ok')::boolean, false);
  end loop;
  -- negative controls vs decoys (trailing 90 days; live and library runs both count, they share the code path): pass = Likely+.
  -- The rule is registered as the single att_controls 'negative' row (ENGINE §10.2), updated with every run.
  select count(*), count(*) filter (where tier in ('likely','measured')) into n_neg, k_neg from ripples.att_hop_latest where role = 'negative_control' and look_day >= current_date - 90;
  select count(*), count(*) filter (where tier in ('likely','measured')) into n_dec, k_dec from ripples.att_hop_latest where role = 'decoy' and look_day >= current_date - 90;
  w := ripples.att_wilson(k_dec, n_dec);
  neg_ok := n_neg = 0 or n_dec = 0 or (k_neg::float8 / n_neg between (w ->> 'lo')::float8 and (w ->> 'hi')::float8);
  neg := jsonb_build_object('pass_rate', case when n_neg > 0 then k_neg::float8 / n_neg end, 'n', n_neg, 'passes', k_neg, 'decoy_n', n_dec, 'decoy_passes', k_dec,
                            'decoy_rate', w ->> 'rate', 'decoy_lo', w ->> 'lo', 'decoy_hi', w ->> 'hi', 'ok', neg_ok);
  insert into ripples.att_controls(kind, spec)
  select 'negative', '{"name":"negative controls vs decoys","rule":"3 outcome nodes per real event that the family mapper rules out (role negative_control, frozen with the day); their Likely+ rate over 90 days must lie inside the decoys'' 90% Wilson interval (ENGINE §5.6.5)"}'::jsonb
  where not exists (select 1 from ripples.att_controls where kind = 'negative');
  update ripples.att_controls set last_run = current_date, passed = neg_ok, detail = neg where kind = 'negative';
  v_seq := ripples.att_ledger_append(current_date, 'control', jsonb_build_object('positive_ok', all_ok, 'negative_ok', neg_ok),
                                     jsonb_build_object('day', current_date, 'positive', res, 'negative', neg));
  if p_strict and not (all_ok and neg_ok) then
    raise exception 'att_run_controls: deploy gate failed (positive_ok=%, negative_ok=%)', all_ok, neg_ok;
  end if;
  return jsonb_build_object('ok', all_ok and neg_ok, 'positive', res, 'negative', neg, 'ledger_seq', v_seq);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. att_calibrate (Sunday 09:10) and the public payload
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_calibrate(p_as_of date default current_date - 1) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ks jsonb; power jsonb; fdr jsonb; brk jsonb; rep jsonb; pri jsonb; rc jsonb; payload jsonb; v_seq bigint; t0 timestamptz := clock_timestamp();
        receipts jsonb; refire jsonb; retr jsonb; ctrl jsonb; ks_bad boolean; mv jsonb; head text;
begin
  ks := ripples.att_calibrate_ks(p_as_of, 500);
  ks_bad := (ks ->> 'p') is not null and (ks ->> 'p')::float8 < 0.01;
  power := ripples.att_spikein(p_as_of, 25);
  fdr := ripples.att_decoy_fdr(p_as_of, 28);
  brk := ripples.att_breaker_update(p_as_of, ks_bad);
  rep := ripples.att_replication_refresh(p_as_of);
  pri := ripples.att_priors_refit(p_as_of);
  perform ripples.att_lag_windows_refresh(p_as_of);
  rc := ripples.att_channel_corr_refresh(p_as_of);
  -- Receipts (§5.6.6): raw counts until 200 resolved
  select jsonb_build_object('registered', count(*), 'resolved', count(*) filter (where resolved_at is not null), 'hits', count(*) filter (where hit),
                            'base_rate_hits', round(coalesce(sum(p_hat) filter (where resolved_at is not null), 0)::numeric, 1),
                            'show_reliability', count(*) filter (where resolved_at is not null) >= 200,
                            'brier', case when count(*) filter (where resolved_at is not null) >= 200 then round(avg((hit::int - p_hat)^2) filter (where resolved_at is not null)::numeric, 4) end,
                            'reliability', case when count(*) filter (where resolved_at is not null) >= 200 then
                              (select jsonb_agg(jsonb_build_object('bin', b, 'n', n, 'predicted', round(pp::numeric, 3), 'observed', round(oo::numeric, 3)) order by b)
                               from (select width_bucket(p_hat, 0, 1, 10) b, count(*) n, avg(p_hat) pp, avg(hit::int) oo from ripples.att_hop_registry where resolved_at is not null group by 1) q) end)
    into receipts from ripples.att_hop_registry g join ripples.att_hop_candidates c on c.hop_id = g.hop_id where not c.reconstructed;
  select coalesce(jsonb_agg(jsonb_build_object('family', family, 'edge_class', edge_class, 'channel', channel, 'n', n, 'hits', hits, 'p_dose', p_dose, 'route', route, 'one_off', one_off) order by family, edge_class), '[]'::jsonb)
    into refire from ripples.att_replication where as_of = p_as_of;
  select coalesce(jsonb_agg(jsonb_build_object('hop_id', hop_id, 'date', to_char(retracted_at, 'YYYY-MM-DD'), 'reason', retract_reason) order by retracted_at desc), '[]'::jsonb)
    into retr from (select distinct on (hop_id) hop_id, retracted_at, retract_reason from ripples.att_hop_tests where retracted_at is not null order by hop_id, look_no desc) x;
  select jsonb_build_object('positive', coalesce(jsonb_agg(jsonb_build_object('name', spec ->> 'name', 'passed', passed, 'last_run', last_run, 'measured', detail -> 'measured') order by id) filter (where kind = 'positive'), '[]'::jsonb),
                            'negative', (select jsonb_build_object('pass_rate', case when count(*) > 0 then round((count(*) filter (where tier in ('likely','measured')))::numeric / count(*), 4) end, 'n', count(*),
                                                                   'decoy_rate', (select round((count(*) filter (where tier in ('likely','measured')))::numeric / nullif(count(*), 0), 4) from ripples.att_hop_latest where role = 'decoy' and not reconstructed and look_day >= p_as_of - 90))
                                         from ripples.att_hop_latest where role = 'negative_control' and not reconstructed and look_day >= p_as_of - 90))
    into ctrl from ripples.att_controls;
  select coalesce(jsonb_agg(jsonb_build_object('seq', seq, 'day', day, 'hash', payload_hash, 'ref', ref) order by seq), '[]'::jsonb) into mv from ripples.att_ledger where kind = 'model_version';
  head := ripples.att_ledger_head();
  payload := jsonb_build_object('v', 2, 'as_of', p_as_of, 'method', coalesce(ripples._att_cfg('engine') ->> 'method', '6.0'),
    'decoy_fdr', fdr - 'as_of' - 'days', 'null_ks', ks, 'power', power, 'controls', ctrl, 'receipts', receipts, 'refire', refire,
    'breaker', brk -> 'open', 'retractions', retr, 'ledger', jsonb_build_object('head', head, 'seq', (select max(seq) from ripples.att_ledger)),
    'model_versions', mv, 'priors', pri, 'fluke_bins', (select coalesce(jsonb_agg(jsonb_build_object('s_bin', s_bin, 'h_bin', h_bin, 'f', f, 'decoy_tested', decoy_tested, 'real_tested', real_tested, 'warming', warming) order by s_bin, h_bin), '[]'::jsonb)
                                                          from ripples.att_fluke_bins where as_of = (select max(as_of) from ripples.att_fluke_bins)),
    'p_floors', jsonb_build_object('date', 1.0 / 2001, 'date_default', 1.0 / 201, 'topic', 1.0 / 301, 'link', 1.0 / 201),
    'day_lines', (select coalesce(jsonb_agg(jsonb_build_object('day', substr(k, 12), 'line', v) order by k), '[]'::jsonb) from ripples.att_state where k like 'engine.day.%' and k >= 'engine.day.' || (p_as_of - 30)::text));
  v_seq := ripples.att_ledger_append(p_as_of, 'calibration', jsonb_build_object('as_of', p_as_of), payload);
  payload := payload || jsonb_build_object('ledger', jsonb_build_object('head', ripples.att_ledger_head(), 'seq', v_seq));
  insert into ripples.att_calibration_public(as_of, payload) values (p_as_of, payload) on conflict (as_of) do update set payload = excluded.payload;
  return jsonb_build_object('as_of', p_as_of, 'ks', ks - 'hist', 'fdr', fdr -> 'overall', 'breaker', brk, 'replication', rep, 'priors', pri, 'corr', rc,
                            'seconds', round(extract(epoch from clock_timestamp() - t0)::numeric, 1), 'ledger_seq', v_seq);
end $$;

do $$ declare t text; begin
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
  revoke all on ripples.att_hop_latest from anon, authenticated, public;
end $$;
