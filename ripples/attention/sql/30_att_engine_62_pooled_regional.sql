-- Migration: att_engine_62_pooled_regional (engine method 6.1 → 6.2, 2026-09-26)
-- Two stronger, ADDITIVE statistical designs on top of the 6.1 per-event / per-series event study. Nothing in 20–28 is rewritten;
-- the only touch on a 6.1 body is one clearly-marked hook line in att_finalize's tier decision (installed by
-- ripples.att_fx_hook_install(), anchor-checked, idempotent).
--
--   A. FAMILY-POOLED EFFECTS (event-class meta-analysis). For a frozen (family × outcome) pair, every archived event of the family
--      gets a standardised effect d_e (log points, robust null scale = 1.4826·MAD of the SAME statistic at season-matched pseudo-onsets
--      in other years, centred on their median, floored) and the events are combined with DerSimonian–Laird random effects (τ², I²).
--      The pooled p-value comes from a PLACEBO POOL: B replicates that pool one season-matched pseudo-event per real event with the
--      same DL estimator (the normal-approximation p is reported next to it, never instead of it). Dose–response = weighted
--      meta-regression slope of d_e on the event magnitude where one exists.
--   B. AFFECTED-vs-UNAFFECTED REGIONAL CONTRASTS. For series that exist per region (state / balancing authority / npm package as an
--      "ecosystem region"), the treated geography (event meta.state / meta.ba) is contrasted with the donor pool of untreated regions:
--      difference-in-differences on the log scale (post-window mean − pre-window mean, treated minus donors), with
--        · pre-trend check: three pre-onset leads, joint Q = Σ lead², compared with the same Q on in-space placebo groups (p_pre),
--        · in-space placebo inference: random donor groups of the same size treated as if affected, p_space = rank of |DiD|,
--        · in-time placebo inference: the same contrast at season-matched pseudo-onsets in other years (p_time, and the null scale),
--        · a demeaned synthetic control (non-negative weights on the pre-period, exponentiated-gradient NNLS, Abadie-style
--          RMSPE-ratio rank test against in-space placebo groups) on the pairs flagged synth = true.
--      Common shocks (holidays, national news, macro) cancel in the contrast by construction.
--
-- Pre-registration: the grid of pairs, windows, donor rules, K and the per-grid event lists are frozen and hashed into the ledger
-- (kind 'freeze', ref.object = 'fx_grid') BEFORE any effect is computed; the grid is one BH family with frozen equal weights; a
-- 'model_version' ledger row records the 6.2 method. Tiering: a hop may reach Measured when (i) the 6.1 per-event test passes OR the
-- regional contrast passes (p_space ≤ q_measured, flat pre-trends, sign agrees, synthetic control agrees when computed), AND (ii) the
-- family pooled effect — when the family has ≥ K events in the frozen pair — has the same sign with pooled placebo p ≤ 0.05, AND (iii)
-- the BigQuery forecast gate (att_ce_gate) still applies downstream (untouched). Family-level findings are a new object
-- (ripples.att_family_effects + public.rm_patterns) labelled "measured across N past events" — never "probability of causation".
--
-- Storage: the panel cache (prefix sums per region) ≈ 8 MB, per-event rows with 40-float placebo arrays ≈ 3 MB, pools < 1 MB.
-- Every statement is chunked (att_fx_step, ≤ 40 s per call) so pg_cron keeps launching other jobs.

create schema if not exists ripples;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0. Config (frozen defaults; `on conflict do nothing` so a re-run never silently changes a frozen threshold)
-- ---------------------------------------------------------------------------------------------------------------------
insert into ripples.att_config(key, value) values ('engine62', jsonb_build_object(
  'method', '6.2',
  'k_min', 8,              -- K: a family pattern binds the per-hop tier only with ≥ K events in the pair
  'b_pool', 300,           -- placebo-pool replicates for the pooled p
  'n_time', 40,            -- season-matched in-time pseudo-onsets per event (null scale + p_time)
  'n_space', 30,           -- in-space placebo groups per event (p_space, p_pre)
  'n_synth', 20,           -- in-space placebo groups for the synthetic-control RMSPE-ratio test
  'synth_iter', 80, 'synth_donors', 15,
  'q_measured', 0.05, 'q_pattern', 0.20, 'p_pretrend', 0.10,
  'min_cover', 0.7,        -- share of a window that must be observed
  'season_band', 21,       -- ± days around the same calendar date in other years
  'se_floor', 0.005,       -- log points
  'min_donors', 5))
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tables (service-only: RLS on, no grants)
-- ---------------------------------------------------------------------------------------------------------------------
-- panel cache: one row per (source, metric, geo_kind); per region the prefix sums / prefix counts of the transformed value over a
-- common observation index (daily calendar, or the source's own weekly dates), so any window mean is two array reads.
create table if not exists ripples.att_fx_panel (
  source text not null, metric text not null, geo_kind text not null,
  grain text not null, value_kind text not null, days date[] not null, regions text[] not null, n int not null,
  ps float8[] not null, pc int2[] not null, built_at timestamptz not null default now(),
  primary key (source, metric, geo_kind));

create table if not exists ripples.att_fx_grid (
  grid_id int generated always as identity primary key,
  batch text not null, family text not null, sub text, source text not null, metric text not null, geo_kind text not null,
  pre_n int not null, post_n int not null, lag_n int not null default 0,
  expected_sign smallint not null default 0, synth boolean not null default false, definitional boolean not null default false,
  domain_event text, domain_outcome text, target_map jsonb, bh_weight real not null default 1,
  label text, frozen_hash text, frozen_at timestamptz, ledger_seq bigint, status text not null default 'frozen');
create unique index if not exists att_fx_grid_pair_uidx on ripples.att_fx_grid (batch, family, coalesce(sub, ''), source, metric, geo_kind);

create table if not exists ripples.att_fx_event (
  grid_id int not null references ripples.att_fx_grid(grid_id), event_id bigint not null,
  role text not null default 'real', decoy_set int not null default 0,
  onset date not null, treated text[] not null, magnitude real,
  n_treated int, n_donors int, d real, d_treated real, med real, se real, z real,
  p_time real, p_space real, p_pre real, lead real[], synth_d real, synth_p real, synth_ratio real, placebo_d real[],
  note text, computed_at timestamptz,
  primary key (grid_id, event_id, role, decoy_set));
create index if not exists att_fx_event_pending_idx on ripples.att_fx_event (grid_id) where computed_at is null;

create table if not exists ripples.att_fx_pool (
  grid_id int not null references ripples.att_fx_grid(grid_id), role text not null default 'real', decoy_set int not null default 0,
  n_events int, n_skipped int, d real, se real, ci_lo real, ci_hi real, tau2 real, i2 real, p_norm real, p_placebo real, q real,
  sign_ok boolean, dose_slope real, dose_se real, dose_p real, n_dose int, strength text, payload jsonb, computed_at timestamptz,
  primary key (grid_id, role, decoy_set));

alter table ripples.att_fx_panel enable row level security;
alter table ripples.att_fx_grid  enable row level security;
alter table ripples.att_fx_event enable row level security;
alter table ripples.att_fx_pool  enable row level security;
revoke all on ripples.att_fx_panel, ripples.att_fx_grid, ripples.att_fx_event, ripples.att_fx_pool from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Panel cache build
-- ---------------------------------------------------------------------------------------------------------------------
-- geo_kind: 'state' → region = geo 'US-XX' (several series per state are averaged after transform), 'ba' → region = series key
-- (balancing authority; US48 / aggregates excluded), 'national' → region = series key (every key of the source is a "region": the
-- donor pool for an npm package is the other tracked packages). Transform: log(1 + y) for counts/levels, raw for rates (temperature).
create or replace function ripples.att_fx_panel_build(p_source text, p_metric text, p_geo_kind text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_from date := '2015-01-01'; v_to date := current_date; vk text; grain text; days date[]; regs text[]; n int; nr int;
        ps float8[] := '{}'; pc int2[] := '{}'; r record; i int; acc float8; cnt int; v float8[]; ps_r float8[]; pc_r int2[];
        v_span int; v_days int;
begin
  create temp table _fxs on commit drop as
    select case when p_geo_kind = 'state' then s.geo else s.key end as region, s.series_id
    from ripples.att_series s
    where s.source = p_source and s.metric = p_metric
      and case p_geo_kind when 'state' then s.geo ~ '^US-[A-Z]{2}$'
                          when 'ba' then s.key !~ '^(US48|__total__|all)$' and s.key !~ ':'
                          else true end;
  if not exists (select 1 from _fxs) then return jsonb_build_object('error', 'no series'); end if;
  select coalesce((select z.value_kind from ripples.att_zvec z join _fxs f on f.series_id = z.series_id where z.value_kind is not null limit 1), 'count') into vk;
  create temp table _fxo on commit drop as
    select f.region, o.day, avg(case when vk = 'rate' then o.value else ln(1 + greatest(o.value, 0)) end) as y
    from _fxs f join lateral (select * from ripples.att_series_daily(f.series_id, v_from, v_to)) o on true
    where o.value is not null group by 1, 2;
  select count(distinct day), (max(day) - min(day) + 1) into v_days, v_span from _fxo;
  if v_days::float8 / greatest(v_span, 1) < 0.5 then
    grain := 'week'; select array_agg(d order by d) into days from (select distinct day d from _fxo) x;
  else
    grain := 'day'; select array_agg(d::date order by d) into days from generate_series((select min(day) from _fxo), (select max(day) from _fxo), '1 day') d;
  end if;
  n := cardinality(days);
  select array_agg(region order by region) into regs from (select distinct region from _fxo) x;
  nr := cardinality(regs);
  create temp table _fxd on commit drop as select d, ord::int as idx from unnest(days) with ordinality u(d, ord);
  create index on _fxd(d);
  for r in select region from unnest(regs) region order by region loop
    select array_agg(o.y order by dd.idx) into v from _fxd dd left join _fxo o on o.day = dd.d and o.region = r.region;
    acc := 0; cnt := 0; ps_r := array_fill(0::float8, array[n]); pc_r := array_fill(0::int2, array[n]);
    for i in 1..n loop
      if v[i] is not null then acc := acc + v[i]; cnt := cnt + 1; end if;
      ps_r[i] := acc; pc_r[i] := cnt;
    end loop;
    if cardinality(ps) = 0 then ps := array[ps_r]; pc := array[pc_r]; else ps := ps || ps_r; pc := pc || pc_r; end if;
  end loop;
  insert into ripples.att_fx_panel(source, metric, geo_kind, grain, value_kind, days, regions, n, ps, pc, built_at)
  values (p_source, p_metric, p_geo_kind, grain, vk, days, regs, n, ps, pc, now())
  on conflict (source, metric, geo_kind) do update set grain = excluded.grain, value_kind = excluded.value_kind, days = excluded.days,
    regions = excluded.regions, n = excluded.n, ps = excluded.ps, pc = excluded.pc, built_at = now();
  drop table _fxs; drop table _fxo; drop table _fxd;
  return jsonb_build_object('source', p_source, 'metric', p_metric, 'geo_kind', p_geo_kind, 'grain', grain, 'value_kind', vk, 'n', n,
                            'regions', nr, 'from', days[1], 'to', days[n]);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Core estimators (pure; all arrays passed in, nothing read from tables)
-- ---------------------------------------------------------------------------------------------------------------------
-- window mean of region r over obs [a, b] from the prefix arrays; null when the coverage is below p_cover
create or replace function ripples.att_fx_wm(ps float8[], pc int2[], r int, a int, b int, p_cover float8) returns float8
language plpgsql immutable set search_path = '' as $$
declare c int; begin
  if a < 2 or b < a then return null; end if;
  c := pc[r][b] - pc[r][a - 1];
  if c < greatest(1, ceil(p_cover * (b - a + 1))) then return null; end if;
  return (ps[r][b] - ps[r][a - 1]) / c;
end $$;

-- difference-in-differences at obs index i0: Δ_r = mean(post) − mean(pre); returns [did, d_treated, d_donors, n_donors_used]
-- (d_donors / did fall back to the treated change alone when there are no donors — the plain event-study case)
create or replace function ripples.att_fx_did(ps float8[], pc int2[], tset int[], dset int[], i0 int, pre int, post int, lag int, p_cover float8) returns float8[]
language plpgsql immutable set search_path = '' as $$
declare r int; m1 float8; m0 float8; st float8 := 0; nt int := 0; sd float8 := 0; nd int := 0; dt float8; dd float8;
begin
  foreach r in array tset loop
    m0 := ripples.att_fx_wm(ps, pc, r, i0 - pre, i0 - 1, p_cover); m1 := ripples.att_fx_wm(ps, pc, r, i0 + lag, i0 + lag + post - 1, p_cover);
    if m0 is not null and m1 is not null then st := st + (m1 - m0); nt := nt + 1; end if;
  end loop;
  if nt = 0 or nt * 2 < cardinality(tset) then return null; end if;
  dt := st / nt;
  foreach r in array coalesce(dset, '{}') loop
    m0 := ripples.att_fx_wm(ps, pc, r, i0 - pre, i0 - 1, p_cover); m1 := ripples.att_fx_wm(ps, pc, r, i0 + lag, i0 + lag + post - 1, p_cover);
    if m0 is not null and m1 is not null then sd := sd + (m1 - m0); nd := nd + 1; end if;
  end loop;
  if nd = 0 then return array[dt, dt, null, 0]; end if;
  dd := sd / nd;
  return array[dt - dd, dt, dd, nd];
end $$;

-- pre-trend joint statistic: leads k = 1..3 are the DiD with the "post" block moved to the k-th block of post obs before i0 (lag 0)
create or replace function ripples.att_fx_leads(ps float8[], pc int2[], tset int[], dset int[], i0 int, pre int, post int, p_cover float8) returns float8[]
language plpgsql immutable set search_path = '' as $$
declare k int; x float8[]; out float8[] := '{}';
begin
  for k in 1..3 loop
    x := ripples.att_fx_did(ps, pc, tset, dset, i0 - k * post, pre, post, 0, p_cover);
    out := out || coalesce(x[1], 0::float8);
  end loop;
  return out;
end $$;

-- demeaned synthetic control (Abadie-style non-negative weights fitted on the pre-period by exponentiated gradient; the p_ndon donors
-- most correlated with the treated pre-series are eligible). Returns [effect, rmspe_pre, rmspe_post, ratio] or null.
create or replace function ripples.att_fx_synth(ps float8[], pc int2[], tset int[], dset int[], i0 int, pre int, post int, lag int, p_iter int, p_ndon int) returns float8[]
language plpgsql immutable set search_path = '' as $$
declare t int; r int; k int; j int; it int; y float8[] := '{}'; yp float8[] := '{}'; v float8; ok boolean;
        m int; xs float8[]; -- donor pre matrix flattened [j][t]
        xp float8[]; -- donor post matrix
        cand int[] := '{}'; cor float8[] := '{}'; mu float8; mux float8; sxy float8; sxx float8; syy float8;
        w float8[]; g float8[]; pred float8; res float8; eta float8; ssq float8; s float8; eff float8; rp float8; rq float8; z float8;
        row_pre float8[]; row_post float8[]; ymean float8; xm float8; tot float8;
begin
  -- treated series (average over treated regions), one value per obs; every obs must be observed in every treated region
  for t in (i0 - pre)..(i0 - 1) loop
    s := 0;
    foreach r in array tset loop
      if pc[r][t] - pc[r][t - 1] <> 1 then return null; end if;
      s := s + (ps[r][t] - ps[r][t - 1]);
    end loop;
    y := y || (s / cardinality(tset));
  end loop;
  for t in (i0 + lag)..(i0 + lag + post - 1) loop
    s := 0;
    foreach r in array tset loop
      if pc[r][t] - pc[r][t - 1] <> 1 then return null; end if;
      s := s + (ps[r][t] - ps[r][t - 1]);
    end loop;
    yp := yp || (s / cardinality(tset));
  end loop;
  select avg(x) into ymean from unnest(y) x;
  -- donor candidates: complete in both windows; keep the p_ndon most correlated with the demeaned treated pre-series
  foreach r in array dset loop
    ok := true; row_pre := '{}'; row_post := '{}';
    for t in (i0 - pre)..(i0 - 1) loop
      if pc[r][t] - pc[r][t - 1] <> 1 then ok := false; exit; end if;
      row_pre := row_pre || (ps[r][t] - ps[r][t - 1]);
    end loop;
    continue when not ok;
    for t in (i0 + lag)..(i0 + lag + post - 1) loop
      if pc[r][t] - pc[r][t - 1] <> 1 then ok := false; exit; end if;
      row_post := row_post || (ps[r][t] - ps[r][t - 1]);
    end loop;
    continue when not ok;
    select avg(x) into xm from unnest(row_pre) x;
    sxy := 0; sxx := 0; syy := 0;
    for t in 1..pre loop sxy := sxy + (row_pre[t] - xm) * (y[t] - ymean); sxx := sxx + (row_pre[t] - xm)^2; syy := syy + (y[t] - ymean)^2; end loop;
    cand := cand || r; cor := cor || case when sxx > 0 and syy > 0 then sxy / sqrt(sxx * syy) else 0 end;
  end loop;
  if cardinality(cand) < 3 then return null; end if;
  -- top p_ndon by correlation
  select array_agg(c order by cc desc) into cand from (select c, cc from unnest(cand, cor) u(c, cc) order by cc desc limit p_ndon) x;
  m := cardinality(cand);
  -- build demeaned matrices
  xs := array_fill(0::float8, array[m, pre]); xp := array_fill(0::float8, array[m, post]);
  for j in 1..m loop
    r := cand[j]; xm := 0;
    for t in 1..pre loop xm := xm + (ps[r][i0 - pre + t - 1] - ps[r][i0 - pre + t - 2]); end loop;
    xm := xm / pre;
    for t in 1..pre loop xs[j][t] := (ps[r][i0 - pre + t - 1] - ps[r][i0 - pre + t - 2]) - xm; end loop;
    for t in 1..post loop xp[j][t] := (ps[r][i0 + lag + t - 1] - ps[r][i0 + lag + t - 2]) - xm; end loop;
  end loop;
  for t in 1..pre loop y[t] := y[t] - ymean; end loop;
  for t in 1..post loop yp[t] := yp[t] - ymean; end loop;
  -- exponentiated gradient on the simplex
  w := array_fill(1::float8 / m, array[m]); g := array_fill(0::float8, array[m]);
  ssq := 0; for j in 1..m loop for t in 1..pre loop ssq := ssq + xs[j][t]^2; end loop; end loop;
  eta := 0.5 * m * pre / greatest(ssq, 1e-9);
  for it in 1..p_iter loop
    for j in 1..m loop g[j] := 0; end loop;
    for t in 1..pre loop
      pred := 0; for j in 1..m loop pred := pred + w[j] * xs[j][t]; end loop;
      res := pred - y[t];
      for j in 1..m loop g[j] := g[j] + res * xs[j][t]; end loop;
    end loop;
    tot := 0;
    for j in 1..m loop w[j] := w[j] * exp(greatest(least(-eta * g[j], 20), -20)); tot := tot + w[j]; end loop;
    for j in 1..m loop w[j] := w[j] / tot; end loop;
  end loop;
  rp := 0;
  for t in 1..pre loop pred := 0; for j in 1..m loop pred := pred + w[j] * xs[j][t]; end loop; rp := rp + (y[t] - pred)^2; end loop;
  rp := sqrt(rp / pre);
  rq := 0; eff := 0;
  for t in 1..post loop pred := 0; for j in 1..m loop pred := pred + w[j] * xp[j][t]; end loop; z := yp[t] - pred; eff := eff + z; rq := rq + z^2; end loop;
  rq := sqrt(rq / post); eff := eff / post;
  return array[eff, rp, rq, rq / greatest(rp, 1e-6)];
end $$;

-- first obs index with days[i] ≥ d (binary search); null when out of range
create or replace function ripples.att_fx_idx(days date[], d date) returns int
language plpgsql immutable set search_path = '' as $$
declare lo int := 1; hi int := cardinality(days); mid int;
begin
  if d > days[hi] then return null; end if;
  while lo < hi loop mid := (lo + hi) / 2; if days[mid] >= d then hi := mid; else lo := mid + 1; end if; end loop;
  return lo;
end $$;

-- the per-event computation. p_seed in [-1, 1] makes every draw reproducible. Returns the row shape of att_fx_event.
create or replace function ripples.att_fx_calc(ps float8[], pc int2[], days date[], regions text[], grain text,
                                               p_treated text[], p_onset date, p_pre int, p_post int, p_lag int, p_synth boolean,
                                               p_seed float8, p_cfg jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare n int := cardinality(days); nr int := cardinality(regions); tset int[] := '{}'; dset int[] := '{}'; r int; i0 int; x float8[];
        cover float8 := coalesce((p_cfg ->> 'min_cover')::float8, 0.7); n_time int := coalesce((p_cfg ->> 'n_time')::int, 40);
        n_space int := coalesce((p_cfg ->> 'n_space')::int, 30); n_synth int := coalesce((p_cfg ->> 'n_synth')::int, 20);
        band int := coalesce((p_cfg ->> 'season_band')::int, 21); se_floor float8 := coalesce((p_cfg ->> 'se_floor')::float8, 0.005);
        min_don int := coalesce((p_cfg ->> 'min_donors')::int, 5);
        d float8; dt float8; nd int; leads float8[]; qt float8; k int; g int[]; rest int[]; s int; ns int := 0; n_ge int := 0; n_qge int := 0;
        pp_space float8; pp_pre float8; pd float8[] := '{}'; med float8; mad float8; se float8; z float8; p_time float8; nt_ge int := 0;
        yr int; y0 int := extract(year from p_onset)::int; yrs int[] := '{}'; tries int; cand date; ci int; per_year int; got int; span int;
        sy float8[]; syn_d float8; syn_p float8; syn_ratio float8; n_sy int := 0; n_sy_ge int := 0; note text := null; w int;
        u float8; pos int; tmp int; pool int[]; j int;
begin
  perform setseed(p_seed);
  -- region indexes
  for r in 1..nr loop if regions[r] = any(p_treated) then tset := tset || r; else dset := dset || r; end if; end loop;
  if cardinality(tset) = 0 then return jsonb_build_object('note', 'no treated region in panel'); end if;
  i0 := ripples.att_fx_idx(days, p_onset);
  if i0 is null or i0 - p_pre - 3 * p_post < 2 or i0 + p_lag + p_post - 1 > n then return jsonb_build_object('note', 'window outside data'); end if;
  x := ripples.att_fx_did(ps, pc, tset, dset, i0, p_pre, p_post, p_lag, cover);
  if x is null then return jsonb_build_object('note', 'treated regions not observed'); end if;
  d := x[1]; dt := x[2]; nd := x[4]::int;
  -- keep only donors observed in this event's windows (the placebo groups are drawn from these)
  pool := '{}';
  foreach r in array dset loop
    if ripples.att_fx_wm(ps, pc, r, i0 - p_pre, i0 - 1, cover) is not null and ripples.att_fx_wm(ps, pc, r, i0 + p_lag, i0 + p_lag + p_post - 1, cover) is not null then pool := pool || r; end if;
  end loop;
  leads := ripples.att_fx_leads(ps, pc, tset, pool, i0, p_pre, p_post, cover);
  qt := leads[1]^2 + leads[2]^2 + leads[3]^2;
  -- in-space placebos: random donor groups of the treated size, contrasted with the remaining donors
  k := cardinality(tset);
  if cardinality(pool) >= k + min_don then
    for s in 1..n_space loop
      -- partial Fisher–Yates on a copy of pool
      g := pool;
      for j in 1..k loop
        pos := j + floor(random() * (cardinality(g) - j + 1))::int; tmp := g[j]; g[j] := g[pos]; g[pos] := tmp;
      end loop;
      rest := g[k + 1:cardinality(g)]; g := g[1:k];
      x := ripples.att_fx_did(ps, pc, g, rest, i0, p_pre, p_post, p_lag, cover);
      continue when x is null;
      ns := ns + 1;
      if abs(x[1]) >= abs(d) then n_ge := n_ge + 1; end if;
      sy := ripples.att_fx_leads(ps, pc, g, rest, i0, p_pre, p_post, cover);
      if sy[1]^2 + sy[2]^2 + sy[3]^2 >= qt then n_qge := n_qge + 1; end if;
    end loop;
    if ns >= 10 then pp_space := (1 + n_ge)::float8 / (ns + 1); pp_pre := (1 + n_qge)::float8 / (ns + 1); end if;
  end if;
  -- in-time placebos: season-matched pseudo-onsets in the other years covered by the panel
  span := greatest(1, p_pre + p_post + p_lag);
  for yr in (extract(year from days[1])::int)..(extract(year from days[n])::int) loop if yr <> y0 then yrs := yrs || yr; end if; end loop;
  if cardinality(yrs) > 0 then
    per_year := ceil(n_time::float8 / cardinality(yrs))::int;
    foreach yr in array yrs loop
      got := 0; tries := 0;
      while got < per_year and tries < 12 loop
        tries := tries + 1;
        cand := (p_onset + make_interval(years => yr - y0))::date + (floor(random() * (2 * band + 1))::int - band);
        ci := ripples.att_fx_idx(days, cand);
        continue when ci is null or ci - p_pre < 2 or ci + p_lag + p_post - 1 > n or abs(ci - i0) <= span;
        x := ripples.att_fx_did(ps, pc, tset, pool, ci, p_pre, p_post, p_lag, cover);
        continue when x is null;
        pd := pd || x[1]; got := got + 1;
      end loop;
    end loop;
  end if;
  if cardinality(pd) >= 12 then
    select percentile_cont(0.5) within group (order by v) into med from unnest(pd) v;
    select percentile_cont(0.5) within group (order by abs(v - med)) into mad from unnest(pd) v;
    se := greatest(1.4826 * mad, se_floor); z := (d - med) / se;
    select count(*) into nt_ge from unnest(pd) v where abs(v - med) >= abs(d - med);
    p_time := (1 + nt_ge)::float8 / (cardinality(pd) + 1);
  else
    note := 'few in-time placebos (' || cardinality(pd) || ')';
  end if;
  -- synthetic control with in-space placebo ratio test
  if p_synth and cardinality(pool) >= k + min_don then
    sy := ripples.att_fx_synth(ps, pc, tset, pool, i0, p_pre, p_post, p_lag, coalesce((p_cfg ->> 'synth_iter')::int, 80), coalesce((p_cfg ->> 'synth_donors')::int, 15));
    if sy is not null then
      syn_d := sy[1]; syn_ratio := sy[4];
      for s in 1..n_synth loop
        g := pool;
        for j in 1..k loop pos := j + floor(random() * (cardinality(g) - j + 1))::int; tmp := g[j]; g[j] := g[pos]; g[pos] := tmp; end loop;
        rest := g[k + 1:cardinality(g)]; g := g[1:k];
        x := ripples.att_fx_synth(ps, pc, g, rest, i0, p_pre, p_post, p_lag, coalesce((p_cfg ->> 'synth_iter')::int, 80), coalesce((p_cfg ->> 'synth_donors')::int, 15));
        continue when x is null;
        n_sy := n_sy + 1; if x[4] >= syn_ratio then n_sy_ge := n_sy_ge + 1; end if;
      end loop;
      if n_sy >= 10 then syn_p := (1 + n_sy_ge)::float8 / (n_sy + 1); end if;
    end if;
  end if;
  return jsonb_build_object('n_treated', k, 'n_donors', nd, 'd', d, 'd_treated', dt, 'med', med, 'se', se, 'z', z, 'p_time', p_time,
                            'p_space', pp_space, 'p_pre', pp_pre, 'lead', to_jsonb(leads), 'synth_d', syn_d, 'synth_p', syn_p, 'synth_ratio', syn_ratio,
                            'placebo_d', to_jsonb(pd), 'n_space', ns, 'note', note, 'i0', i0);
end $$;
