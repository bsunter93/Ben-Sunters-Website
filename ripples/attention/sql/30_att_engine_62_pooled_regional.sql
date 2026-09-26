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

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Pre-registration: the frozen grid (batch 'fx-2026-09-26'), the event lists, the ledger freeze row
-- ---------------------------------------------------------------------------------------------------------------------
-- Windows are in observations of the panel's grain (weekly claims: pre 8 / post 4 weeks; daily: pre 28 / post 7–14 days).
-- bh_weight 0 marks a pre-registered CHECK (manipulation check or a definitional pair: storm/flood/wildfire events are themselves
-- FEMA declarations) — computed and published as a check, excluded from the BH family of findings.
create or replace function ripples.att_fx_grid_spec() returns jsonb
language sql immutable set search_path = '' as $$
  select '[
    {"family":"hazard.storm","sub":null,"source":"dol.claims","metric":"ic","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"labor","w":1},
    {"family":"hazard.storm","sub":null,"source":"dol.claims","metric":"cw","geo_kind":"state","pre":8,"post":4,"lag":1,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"labor","w":1},
    {"family":"hazard.storm","sub":null,"source":"eia.930","metric":"demand","geo_kind":"ba","pre":28,"post":7,"lag":0,"sign":-1,"synth":false,"definitional":false,"de":"hazard","do":"power","w":1},
    {"family":"hazard.storm","sub":null,"source":"census.bfs","metric":"ba","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":-1,"synth":false,"definitional":false,"de":"hazard","do":"business","w":1},
    {"family":"hazard.storm","sub":null,"source":"noaa.ghcnd","metric":"prcp","geo_kind":"state","pre":28,"post":3,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"weather","w":0},
    {"family":"hazard.storm","sub":"hurricane","source":"dol.claims","metric":"ic","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":1,"synth":true,"definitional":false,"de":"hazard","do":"labor","w":1},
    {"family":"hazard.storm","sub":"hurricane","source":"dol.claims","metric":"cw","geo_kind":"state","pre":8,"post":4,"lag":1,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"labor","w":1},
    {"family":"hazard.storm","sub":"hurricane","source":"eia.930","metric":"demand","geo_kind":"ba","pre":28,"post":7,"lag":0,"sign":-1,"synth":true,"definitional":false,"de":"hazard","do":"power","w":1},
    {"family":"hazard.storm","sub":"hurricane","source":"tsa.pax","metric":"n","geo_kind":"national","pre":28,"post":7,"lag":0,"sign":-1,"synth":false,"definitional":false,"de":"hazard","do":"travel","w":1,"target_map":{".":["checkpoint"]}},
    {"family":"hazard.storm","sub":"hurricane","source":"census.bfs","metric":"ba","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":-1,"synth":true,"definitional":false,"de":"hazard","do":"business","w":1},
    {"family":"hazard.storm","sub":"hurricane","source":"fema.decl","metric":"n","geo_kind":"state","pre":28,"post":14,"lag":0,"sign":1,"synth":false,"definitional":true,"de":"hazard","do":"government","w":0},
    {"family":"hazard.storm","sub":"hurricane","source":"noaa.ghcnd","metric":"prcp","geo_kind":"state","pre":28,"post":3,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"weather","w":0},
    {"family":"hazard.heat","sub":null,"source":"eia.930","metric":"demand","geo_kind":"ba","pre":28,"post":7,"lag":0,"sign":1,"synth":true,"definitional":false,"de":"hazard","do":"power","w":1},
    {"family":"hazard.heat","sub":null,"source":"noaa.ghcnd","metric":"temp","geo_kind":"state","pre":28,"post":7,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"weather","w":0},
    {"family":"hazard.heat","sub":null,"source":"dol.claims","metric":"ic","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"labor","w":1},
    {"family":"hazard.heat","sub":null,"source":"fema.decl","metric":"n","geo_kind":"state","pre":28,"post":14,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"government","w":1},
    {"family":"hazard.cold","sub":null,"source":"eia.930","metric":"demand","geo_kind":"ba","pre":28,"post":7,"lag":0,"sign":1,"synth":true,"definitional":false,"de":"hazard","do":"power","w":1},
    {"family":"hazard.cold","sub":null,"source":"dol.claims","metric":"ic","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"labor","w":1},
    {"family":"hazard.cold","sub":null,"source":"fema.decl","metric":"n","geo_kind":"state","pre":28,"post":14,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"government","w":1},
    {"family":"hazard.cold","sub":null,"source":"census.bfs","metric":"ba","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":-1,"synth":false,"definitional":false,"de":"hazard","do":"business","w":1},
    {"family":"hazard.flood","sub":null,"source":"dol.claims","metric":"ic","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"labor","w":1},
    {"family":"hazard.flood","sub":null,"source":"eia.930","metric":"demand","geo_kind":"ba","pre":28,"post":7,"lag":0,"sign":-1,"synth":false,"definitional":false,"de":"hazard","do":"power","w":1},
    {"family":"hazard.flood","sub":null,"source":"census.bfs","metric":"ba","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":-1,"synth":false,"definitional":false,"de":"hazard","do":"business","w":1},
    {"family":"hazard.wildfire","sub":null,"source":"dol.claims","metric":"ic","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"labor","w":1},
    {"family":"hazard.wildfire","sub":null,"source":"eia.930","metric":"demand","geo_kind":"ba","pre":28,"post":7,"lag":0,"sign":-1,"synth":false,"definitional":false,"de":"hazard","do":"power","w":1},
    {"family":"hazard.wildfire","sub":null,"source":"census.bfs","metric":"ba","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":-1,"synth":false,"definitional":false,"de":"hazard","do":"business","w":1},
    {"family":"hazard.quake","sub":null,"source":"dol.claims","metric":"ic","geo_kind":"state","pre":8,"post":4,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"hazard","do":"labor","w":1},
    {"family":"hazard.quake","sub":null,"source":"eia.930","metric":"demand","geo_kind":"ba","pre":28,"post":7,"lag":0,"sign":-1,"synth":false,"definitional":false,"de":"hazard","do":"power","w":1},
    {"family":"tech.model_release","sub":null,"source":"npm.dl","metric":"n","geo_kind":"national","pre":28,"post":14,"lag":0,"sign":1,"synth":false,"definitional":false,"de":"tech","do":"developer","w":1,
      "target_map":{"claude|anthropic":["@anthropic-ai/sdk"],"gpt|openai|whisper":["openai"],"llama|deepseek|mistral":["ollama"]}}
  ]'::jsonb
$$;

-- treated regions of an event for a grid row (state → 'US-XX' geo; ba → BA key; national → target_map regex on the event label)
create or replace function ripples.att_fx_treated(p_event bigint, p_geo_kind text, p_target_map jsonb) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare m jsonb; lbl text; out text[] := '{}'; k text; v jsonb;
begin
  select t.meta, e.label into m, lbl from ripples.att_events e join ripples.att_topics t on t.topic_id = e.topic_id where e.event_id = p_event;
  if p_geo_kind = 'state' then
    select coalesce(array_agg(distinct 'US-' || upper(x)), '{}') into out from jsonb_array_elements_text(coalesce(m -> 'state', '[]'::jsonb)) x;
  elsif p_geo_kind = 'ba' then
    select coalesce(array_agg(distinct upper(x)), '{}') into out from jsonb_array_elements_text(coalesce(m -> 'ba', '[]'::jsonb)) x;
  else
    for k, v in select * from jsonb_each(coalesce(p_target_map, '{}'::jsonb)) loop
      if lbl ~* k then select out || array_agg(x) into out from jsonb_array_elements_text(v) x; end if;
    end loop;
  end if;
  return out;
end $$;

-- freeze a batch: grid rows + event lists, hashed into the ledger BEFORE any effect is computed. Idempotent per batch.
create or replace function ripples.att_fx_freeze(p_batch text default 'fx-2026-09-26') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare s jsonb; g record; e record; tr text[]; n_ev int := 0; n_g int := 0; payload jsonb; h text; v_seq bigint; pan record; cfg jsonb;
begin
  if exists (select 1 from ripples.att_fx_grid where batch = p_batch and ledger_seq is not null) then
    return jsonb_build_object('batch', p_batch, 'already_frozen', true, 'seq', (select min(ledger_seq) from ripples.att_fx_grid where batch = p_batch));
  end if;
  cfg := ripples._att_cfg('engine62');
  for s in select * from jsonb_array_elements(ripples.att_fx_grid_spec()) loop
    insert into ripples.att_fx_grid(batch, family, sub, source, metric, geo_kind, pre_n, post_n, lag_n, expected_sign, synth, definitional,
                                    domain_event, domain_outcome, target_map, bh_weight, label)
    values (p_batch, s ->> 'family', s ->> 'sub', s ->> 'source', s ->> 'metric', s ->> 'geo_kind', (s ->> 'pre')::int, (s ->> 'post')::int,
            (s ->> 'lag')::int, (s ->> 'sign')::int, (s ->> 'synth')::boolean, (s ->> 'definitional')::boolean, s ->> 'de', s ->> 'do',
            s -> 'target_map', (s ->> 'w')::real, coalesce(s ->> 'sub', s ->> 'family') || ' → ' || (s ->> 'source') || ':' || (s ->> 'metric'))
    on conflict do nothing;
    n_g := n_g + 1;
  end loop;
  for g in select * from ripples.att_fx_grid where batch = p_batch loop
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    continue when not found;
    for e in select ev.event_id, ev.onset, ev.magnitude from ripples.att_events ev join ripples.att_topics t on t.topic_id = ev.topic_id
             where ev.family = g.family and ev.role = 'library'
               and (g.sub is null or (g.sub = 'hurricane' and t.meta ? 'storm'))
               and ev.onset between pan.days[1] and pan.days[pan.n] order by ev.onset loop
      tr := ripples.att_fx_treated(e.event_id, g.geo_kind, g.target_map);
      select coalesce(array_agg(x), '{}') into tr from unnest(tr) x where x = any(pan.regions);
      continue when cardinality(tr) = 0;
      insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude)
      values (g.grid_id, e.event_id, 'real', 0, e.onset, tr, e.magnitude) on conflict do nothing;
      n_ev := n_ev + 1;
    end loop;
  end loop;
  payload := jsonb_build_object('object', 'fx_grid', 'batch', p_batch, 'method', '6.2', 'config', cfg,
    'grid', (select jsonb_agg(jsonb_build_array(grid_id, family, sub, source, metric, geo_kind, pre_n, post_n, lag_n, expected_sign, synth, definitional, bh_weight, target_map) order by grid_id) from ripples.att_fx_grid where batch = p_batch),
    'events', (select jsonb_agg(jsonb_build_array(f.grid_id, f.event_id, f.onset, f.treated, f.magnitude) order by f.grid_id, f.event_id) from ripples.att_fx_event f join ripples.att_fx_grid g2 on g2.grid_id = f.grid_id where g2.batch = p_batch and f.role = 'real'),
    'panels', (select jsonb_agg(jsonb_build_array(source, metric, geo_kind, grain, n, cardinality(regions), days[1], days[n]) order by source, metric) from ripples.att_fx_panel));
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'fx_grid', 'batch', p_batch, 'method', '6.2', 'n_pairs', n_g, 'n_events', n_ev, 'k_min', cfg -> 'k_min'), payload);
  update ripples.att_fx_grid set frozen_hash = h, frozen_at = now(), ledger_seq = v_seq where batch = p_batch;
  return jsonb_build_object('batch', p_batch, 'n_pairs', n_g, 'n_events', n_ev, 'seq', v_seq, 'hash', h);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Chunked runner (≤ p_budget_s seconds per call; state in att_state 'engine62.run')
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_fx_step(p_budget_s int default 40, p_role text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t0 timestamptz := clock_timestamp(); g record; pan record; e record; j jsonb; n_done int := 0; cfg jsonb := ripples._att_cfg('engine62');
        v_grid int; pooled int := 0; pr record;
begin
  loop
    select f.grid_id into v_grid from ripples.att_fx_event f where f.computed_at is null and (p_role is null or f.role = p_role) order by f.grid_id limit 1;
    exit when v_grid is null;
    select * into g from ripples.att_fx_grid where grid_id = v_grid;
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    for e in select * from ripples.att_fx_event f where f.grid_id = v_grid and f.computed_at is null and (p_role is null or f.role = p_role) order by f.role, f.decoy_set, f.event_id loop
      j := ripples.att_fx_calc(pan.ps, pan.pc, pan.days, pan.regions, pan.grain, e.treated, e.onset, g.pre_n, g.post_n, g.lag_n, g.synth,
                               ((hashtext(v_grid || ':' || e.event_id || ':' || e.role || ':' || e.decoy_set) % 100000) / 100000.0)::float8, cfg);
      update ripples.att_fx_event f set
        n_treated = (j ->> 'n_treated')::int, n_donors = (j ->> 'n_donors')::int, d = (j ->> 'd')::real, d_treated = (j ->> 'd_treated')::real,
        med = (j ->> 'med')::real, se = (j ->> 'se')::real, z = (j ->> 'z')::real, p_time = (j ->> 'p_time')::real, p_space = (j ->> 'p_space')::real,
        p_pre = (j ->> 'p_pre')::real, lead = (select array_agg(x::real) from jsonb_array_elements_text(coalesce(j -> 'lead', '[]'::jsonb)) x),
        synth_d = (j ->> 'synth_d')::real, synth_p = (j ->> 'synth_p')::real, synth_ratio = (j ->> 'synth_ratio')::real,
        placebo_d = (select array_agg(x::real) from jsonb_array_elements_text(coalesce(j -> 'placebo_d', '[]'::jsonb)) x),
        note = j ->> 'note', computed_at = now()
      where f.grid_id = e.grid_id and f.event_id = e.event_id and f.role = e.role and f.decoy_set = e.decoy_set;
      n_done := n_done + 1;
      exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s);
    end loop;
    exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s);
  end loop;
  -- pool every (grid, role, set) that is complete and not yet pooled
  for pr in select f.grid_id, f.role, f.decoy_set from ripples.att_fx_event f
            group by 1, 2, 3 having bool_and(f.computed_at is not null)
            and not exists (select 1 from ripples.att_fx_pool p where p.grid_id = f.grid_id and p.role = f.role and p.decoy_set = f.decoy_set) loop
    perform ripples.att_fx_pool_run(pr.grid_id, pr.role, pr.decoy_set);
    pooled := pooled + 1;
    exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s + 15);
  end loop;
  j := jsonb_build_object('at', now(), 'done', n_done, 'pooled', pooled, 'secs', round(extract(epoch from clock_timestamp() - t0)::numeric, 1),
                          'pending', (select count(*) from ripples.att_fx_event where computed_at is null));
  insert into ripples.att_state(k, v) values ('engine62.run', j) on conflict (k) do update set v = excluded.v, updated_at = now();
  return j;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Pooling: DerSimonian–Laird random effects, placebo pool, dose–response
-- ---------------------------------------------------------------------------------------------------------------------
-- returns [d_pooled, se_pooled, tau2, i2, Q, k]
create or replace function ripples.att_fx_dl(dc float8[], se float8[]) returns float8[]
language plpgsql immutable set search_path = '' as $$
declare k int := cardinality(dc); i int; w float8; sw float8 := 0; sw2 float8 := 0; swd float8 := 0; dbar float8; q float8 := 0; c float8; tau2 float8;
        ws float8; sws float8 := 0; swsd float8 := 0;
begin
  if k = 0 then return null; end if;
  for i in 1..k loop w := 1 / (se[i]^2); sw := sw + w; sw2 := sw2 + w^2; swd := swd + w * dc[i]; end loop;
  dbar := swd / sw;
  for i in 1..k loop q := q + (dc[i] - dbar)^2 / (se[i]^2); end loop;
  c := sw - sw2 / sw;
  tau2 := case when k > 1 and c > 0 then greatest(0, (q - (k - 1)) / c) else 0 end;
  for i in 1..k loop ws := 1 / (se[i]^2 + tau2); sws := sws + ws; swsd := swsd + ws * dc[i]; end loop;
  return array[swsd / sws, sqrt(1 / sws), tau2, case when q > 0 and k > 1 then greatest(0, (q - (k - 1)) / q) else 0 end, q, k];
end $$;

create or replace function ripples.att_fx_pool_run(p_grid int, p_role text default 'real', p_set int default 0) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := ripples._att_cfg('engine62'); b int := coalesce((cfg ->> 'b_pool')::int, 300); g record; dc float8[]; se float8[]; mags float8[];
        pds real[][]; npd int[]; k int; n_skip int; r float8[]; dp float8; sp float8; i int; rep int; pdc float8[]; rr float8[]; n_ge int := 0;
        p_plc float8; p_norm float8; ws float8; sw float8; swm float8; swd float8; swmm float8; swmd float8; mbar float8; slope float8; slope_se float8; dose_p float8; n_dose int := 0;
        ev record; pd_row real[]; sign_ok boolean; strength text; payload jsonb; n_reg_pass int; n_flat int; n_space_tested int; n_synth_ok int;
        ci_lo float8; ci_hi float8; ok_sign int;
begin
  select * into g from ripples.att_fx_grid where grid_id = p_grid;
  perform setseed(((hashtext('pool:' || p_grid || ':' || p_role || ':' || p_set) % 100000) / 100000.0)::float8);
  dc := '{}'; se := '{}'; mags := '{}'; k := 0;
  create temp table _fxe on commit drop as
    select f.*, f.d - f.med as dc from ripples.att_fx_event f where f.grid_id = p_grid and f.role = p_role and f.decoy_set = p_set and f.se is not null and f.med is not null;
  select count(*) into n_skip from ripples.att_fx_event f where f.grid_id = p_grid and f.role = p_role and f.decoy_set = p_set and (f.se is null or f.med is null);
  select coalesce(array_agg(x.dc order by x.event_id), '{}'), coalesce(array_agg(x.se::float8 order by x.event_id), '{}'), coalesce(array_agg(x.magnitude::float8 order by x.event_id), '{}'), count(*)
    into dc, se, mags, k from _fxe x;
  if k < 2 then
    insert into ripples.att_fx_pool(grid_id, role, decoy_set, n_events, n_skipped, strength, computed_at) values (p_grid, p_role, p_set, k, n_skip, 'too few events', now())
    on conflict (grid_id, role, decoy_set) do update set n_events = excluded.n_events, n_skipped = excluded.n_skipped, strength = excluded.strength, computed_at = now();
    drop table _fxe;
    return jsonb_build_object('grid', p_grid, 'n', k, 'skipped', n_skip);
  end if;
  r := ripples.att_fx_dl(dc, se);
  dp := r[1]; sp := r[2];
  p_norm := 2 * (1 - ripples.att_norm_cdf(abs(dp / sp)));
  -- placebo pool: B replicates, one season-matched pseudo-event per real event, pooled with the same estimator
  for rep in 1..b loop
    pdc := '{}';
    i := 0;
    for ev in select x.placebo_d, x.med from _fxe x order by x.event_id loop
      i := i + 1;
      pdc := pdc || (ev.placebo_d[1 + floor(random() * cardinality(ev.placebo_d))::int]::float8 - ev.med);
    end loop;
    rr := ripples.att_fx_dl(pdc, se);
    if abs(rr[1]) >= abs(dp) then n_ge := n_ge + 1; end if;
  end loop;
  p_plc := (1 + n_ge)::float8 / (b + 1);
  -- dose–response: weighted (random-effects weights) least squares of dc on magnitude
  sw := 0; swm := 0; swd := 0;
  for i in 1..k loop
    if mags[i] is not null then ws := 1 / (se[i]^2 + r[3]); sw := sw + ws; swm := swm + ws * mags[i]; swd := swd + ws * dc[i]; n_dose := n_dose + 1; end if;
  end loop;
  if n_dose >= 6 and sw > 0 then
    mbar := swm / sw; swmm := 0; swmd := 0;
    for i in 1..k loop
      if mags[i] is not null then ws := 1 / (se[i]^2 + r[3]); swmm := swmm + ws * (mags[i] - mbar)^2; swmd := swmd + ws * (mags[i] - mbar) * dc[i]; end if;
    end loop;
    if swmm > 0 then slope := swmd / swmm; slope_se := sqrt(1 / swmm); dose_p := 2 * (1 - ripples.att_norm_cdf(abs(slope / slope_se))); end if;
  end if;
  sign_ok := g.expected_sign = 0 or sign(dp) = g.expected_sign;
  ci_lo := dp - 1.96 * sp; ci_hi := dp + 1.96 * sp;
  select count(*) filter (where x.p_space <= (cfg ->> 'q_measured')::float8 and x.p_pre >= (cfg ->> 'p_pretrend')::float8 and (g.expected_sign = 0 or sign(x.d) = g.expected_sign)),
         count(*) filter (where x.p_pre >= (cfg ->> 'p_pretrend')::float8), count(*) filter (where x.p_space is not null),
         count(*) filter (where x.synth_d is not null and sign(x.synth_d) = sign(x.d))
    into n_reg_pass, n_flat, n_space_tested, n_synth_ok from _fxe x;
  strength := case when k < (cfg ->> 'k_min')::int then 'too few events' when p_plc <= 0.05 then 'hint (before multiplicity)' else 'no pattern' end;
  payload := jsonb_build_object('n_regional_pass', n_reg_pass, 'n_pretrend_flat', n_flat, 'n_space_tested', n_space_tested, 'n_synth_agree', n_synth_ok,
                                'q_stat', r[5], 'b', b, 'share_positive', (select round(avg((x.dc > 0)::int)::numeric, 3) from _fxe x),
                                'median_z', (select percentile_cont(0.5) within group (order by x.z) from _fxe x));
  insert into ripples.att_fx_pool(grid_id, role, decoy_set, n_events, n_skipped, d, se, ci_lo, ci_hi, tau2, i2, p_norm, p_placebo, q, sign_ok,
                                  dose_slope, dose_se, dose_p, n_dose, strength, payload, computed_at)
  values (p_grid, p_role, p_set, k, n_skip, dp, sp, ci_lo, ci_hi, r[3], r[4], p_norm, p_plc, null, sign_ok, slope, slope_se, dose_p, n_dose, strength, payload, now())
  on conflict (grid_id, role, decoy_set) do update set n_events = excluded.n_events, n_skipped = excluded.n_skipped, d = excluded.d, se = excluded.se,
    ci_lo = excluded.ci_lo, ci_hi = excluded.ci_hi, tau2 = excluded.tau2, i2 = excluded.i2, p_norm = excluded.p_norm, p_placebo = excluded.p_placebo, q = null,
    sign_ok = excluded.sign_ok, dose_slope = excluded.dose_slope, dose_se = excluded.dose_se, dose_p = excluded.dose_p, n_dose = excluded.n_dose,
    strength = excluded.strength, payload = excluded.payload, computed_at = now();
  drop table _fxe;
  return jsonb_build_object('grid', p_grid, 'role', p_role, 'set', p_set, 'n', k, 'd', dp, 'se', sp, 'tau2', r[3], 'i2', r[4], 'p_norm', p_norm, 'p_placebo', p_plc, 'dose_slope', slope, 'dose_p', dose_p);
end $$;

-- BH over the batch's real pools (frozen equal weights; checks with bh_weight 0 are outside the family) + the plain-English strength word.
-- The strength scale is honest about multiplicity: 'strong pattern' = q ≤ 0.05 (about 1 in 20 such findings could be a fluke),
-- 'pattern' = q ≤ 0.20 (about 1 in 5), 'hint' = placebo p ≤ 0.05 but not surviving BH, 'no pattern' otherwise.
create or replace function ripples.att_fx_bh(p_batch text default 'fx-2026-09-26') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ids int[]; ps float8[]; ws float8[]; qs float8[]; i int; cfg jsonb := ripples._att_cfg('engine62'); kmin int := (cfg ->> 'k_min')::int;
begin
  select array_agg(p.grid_id order by p.grid_id), array_agg(coalesce(p.p_placebo, 1)::float8 order by p.grid_id), array_agg(g.bh_weight::float8 order by p.grid_id)
    into ids, ps, ws
    from ripples.att_fx_pool p join ripples.att_fx_grid g on g.grid_id = p.grid_id
   where g.batch = p_batch and p.role = 'real' and p.decoy_set = 0 and g.bh_weight > 0 and p.n_events >= 2;
  if ids is null then return jsonb_build_object('n', 0); end if;
  qs := ripples.att_bh_q(ps, ws);
  for i in 1..cardinality(ids) loop update ripples.att_fx_pool set q = qs[i] where grid_id = ids[i] and role = 'real' and decoy_set = 0; end loop;
  update ripples.att_fx_pool p set strength =
    case when p.n_events < kmin then 'too few events'
         when coalesce(p.q, 1) <= 0.05 and p.sign_ok then 'strong pattern'
         when coalesce(p.q, 1) <= 0.05 and not p.sign_ok then 'unexpected direction'
         when coalesce(p.q, 1) <= (cfg ->> 'q_pattern')::float8 and p.sign_ok then 'pattern'
         when coalesce(p.q, 1) <= (cfg ->> 'q_pattern')::float8 then 'unexpected direction'
         when p.p_placebo <= 0.05 then 'hint'
         else 'no pattern' end
    from ripples.att_fx_grid g where g.grid_id = p.grid_id and g.batch = p_batch and p.role = 'real' and p.decoy_set = 0;
  -- checks (bh_weight 0): labelled by their own placebo p, outside the family
  update ripples.att_fx_pool p set q = null, strength = case when p.n_events < kmin then 'too few events' when p.p_placebo <= 0.05 and p.sign_ok then 'check passed' else 'check failed' end
    from ripples.att_fx_grid g where g.grid_id = p.grid_id and g.batch = p_batch and g.bh_weight = 0 and p.role = 'real' and p.decoy_set = 0 and p.n_events >= 2;
  return jsonb_build_object('n', cardinality(ids), 'n_q05', (select count(*) from unnest(qs) q where q <= 0.05), 'n_q20', (select count(*) from unnest(qs) q where q <= 0.20));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Calibration: decoy families (random season-matched pseudo-event sets with the real events' geography)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_fx_decoy_seed(p_grid int, p_sets int, p_n int) returns int
language plpgsql security definer set search_path = '' as $$
declare s int; e record; pan record; g record; y0 int; yr int; cand date; tries int; n_ins int := 0; band int := coalesce((ripples._att_cfg('engine62') ->> 'season_band')::int, 21);
        yrs int[]; ok boolean;
begin
  select * into g from ripples.att_fx_grid where grid_id = p_grid;
  select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
  for s in 1..p_sets loop
    perform setseed(((hashtext('decoy:' || p_grid || ':' || s) % 100000) / 100000.0)::float8);
    for e in select * from ripples.att_fx_event f where f.grid_id = p_grid and f.role = 'real' order by random() limit p_n loop
      y0 := extract(year from e.onset)::int; yrs := '{}';
      for yr in (extract(year from pan.days[1])::int + 1)..(extract(year from pan.days[pan.n])::int) loop if yr <> y0 then yrs := yrs || yr; end if; end loop;
      ok := false; tries := 0;
      while not ok and tries < 20 loop
        tries := tries + 1;
        yr := yrs[1 + floor(random() * cardinality(yrs))::int];
        cand := (e.onset + make_interval(years => yr - y0))::date + (floor(random() * (2 * band + 1))::int - band);
        ok := cand between pan.days[1] + 200 and pan.days[pan.n] - 60 and abs(cand - e.onset) > 120;
      end loop;
      continue when not ok;
      insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude)
      values (p_grid, e.event_id, 'decoy', s, cand, e.treated, e.magnitude) on conflict do nothing;
      n_ins := n_ins + 1;
    end loop;
  end loop;
  return n_ins;
end $$;

-- Wilson interval helper: [lo, hi] for x successes of n at 95 %
create or replace function ripples.att_fx_wilson(x int, n int) returns float8[]
language sql immutable set search_path = '' as $$
  select case when n = 0 then null else array[
    greatest(0, ((x::float8 / n) + 1.96^2 / (2 * n) - 1.96 * sqrt((x::float8 / n) * (1 - x::float8 / n) / n + 1.96^2 / (4 * n^2))) / (1 + 1.96^2 / n)),
    least(1, ((x::float8 / n) + 1.96^2 / (2 * n) + 1.96 * sqrt((x::float8 / n) * (1 - x::float8 / n) / n + 1.96^2 / (4 * n^2))) / (1 + 1.96^2 / n))] end
$$;

-- the calibration summary (decoy pooled FP rate with Wilson CI, in-space placebo uniformity, known positives) → att_state + ledger 'calibration'
create or replace function ripples.att_fx_calibration(p_batch text default 'fx-2026-09-26', p_ledger boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare j jsonb; n_dec int; n_fp int; wi float8[]; unif jsonb; kp jsonb; v_seq bigint;
begin
  select count(*), count(*) filter (where p_placebo <= 0.05) into n_dec, n_fp
    from ripples.att_fx_pool p join ripples.att_fx_grid g on g.grid_id = p.grid_id where g.batch = p_batch and p.role = 'decoy' and p.n_events >= 8;
  wi := ripples.att_fx_wilson(n_fp, n_dec);
  -- in-space placebo p-values of the real events should be roughly uniform under no effect; report deciles and the share ≤ 0.05 / ≤ 0.10
  select jsonb_build_object('n', count(*), 'share_le05', round(avg((p_space <= 0.05)::int)::numeric, 3), 'share_le10', round(avg((p_space <= 0.10)::int)::numeric, 3),
                            'share_pre_le10', round(avg((p_pre <= 0.10)::int)::numeric, 3),
                            'deciles', (select jsonb_agg(round(c::numeric / greatest(sum(c) over (), 1), 3) order by b) from (select width_bucket(p_space, 0, 1.0001, 10) b, count(*) c from ripples.att_fx_event f2 join ripples.att_fx_grid g2 on g2.grid_id = f2.grid_id where g2.batch = p_batch and f2.role = 'decoy' and f2.p_space is not null group by 1) x))
    into unif
    from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch = p_batch and f.role = 'decoy' and f.p_space is not null;
  select jsonb_agg(jsonb_build_object('pair', g.label, 'n', p.n_events, 'd', round(p.d::numeric, 4), 'p_placebo', p.p_placebo, 'q', p.q, 'strength', p.strength, 'sign_ok', p.sign_ok) order by g.grid_id) into kp
    from ripples.att_fx_pool p join ripples.att_fx_grid g on g.grid_id = p.grid_id
   where g.batch = p_batch and p.role = 'real' and ((g.sub = 'hurricane' and g.source in ('fema.decl', 'eia.930')) or (g.family = 'hazard.heat' and g.source = 'eia.930') or g.source = 'npm.dl');
  j := jsonb_build_object('batch', p_batch, 'at', now(), 'method', '6.2',
        'decoy_families', jsonb_build_object('n', n_dec, 'n_fp_05', n_fp, 'rate', case when n_dec > 0 then round((n_fp::numeric / n_dec), 3) end, 'wilson', wi),
        'in_space_placebos', unif, 'known_positives', kp);
  insert into ripples.att_state(k, v) values ('engine62.calibration', j) on conflict (k) do update set v = excluded.v, updated_at = now();
  if p_ledger then
    v_seq := ripples.att_ledger_append(current_date, 'calibration', jsonb_build_object('object', 'fx_grid', 'batch', p_batch, 'method', '6.2'), j);
    j := j || jsonb_build_object('seq', v_seq);
  end if;
  return j;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Tier hook (engine 6.2): called from att_finalize's tier decision with the 6.1 failure list; returns the adjusted list.
-- ---------------------------------------------------------------------------------------------------------------------
-- (B) regional contrast pass = p_space ≤ q_measured AND pre-trends flat (p_pre ≥ p_pretrend) AND sign agrees with the hop's sign AND
--     the synthetic control (when computed) agrees in sign → the 6.1 STATISTICAL failures are lifted ('q above 0.05', 'a placebo
--     family disagrees', 'one channel only', 'placebo families', 'final look not reached'); substantive failures (common shock,
--     already moving, rival, reversed, parent, breaker, young series…) are never lifted.
-- (A) family pattern: when the frozen pair has ≥ K events, Measured additionally needs the pooled effect to have the hop's sign with
--     placebo p ≤ 0.05; otherwise 'no pattern across N past events' is appended. Pairs with < K events are neutral (never lift, never block).
-- Evidence is written to att_hop_tests.detail -> 'fx62' (additive key) so the card can show both the event's own evidence and the family's.
create or replace function ripples.att_fx_hook(p_hop bigint, p_look int, p_fails text[]) returns text[]
language plpgsql security definer set search_path = '' as $$
declare c record; src text; rest text; ser record; g record; fe record; po record; fails text[] := p_fails; cfg jsonb := ripples._att_cfg('engine62');
        qm float8 := coalesce((cfg ->> 'q_measured')::float8, 0.05); ppre float8 := coalesce((cfg ->> 'p_pretrend')::float8, 0.10); kmin int := coalesce((cfg ->> 'k_min')::int, 8);
        region text; reg_pass boolean := false; fam_state text := 'none'; ev jsonb := '{}'::jsonb; lifted text[] := '{}';
begin
  select h.hop_id, h.event_id, h.node, h.sign into c from ripples.att_hop_candidates h where h.hop_id = p_hop;
  if not found or c.event_id is null or c.node is null or c.node ~ '^Q[0-9]+$' then return p_fails; end if;
  src := split_part(c.node, ':', 1); rest := substr(c.node, length(src) + 2);
  select s.metric, s.geo, s.key into ser from ripples.att_series s where s.source = src and s.key = rest limit 1;
  if not found then return p_fails; end if;
  for g in select gr.* from ripples.att_fx_grid gr join ripples.att_events e on e.family = gr.family and e.event_id = c.event_id
           where gr.source = src and gr.metric = ser.metric and gr.ledger_seq is not null order by (gr.sub is not null) desc, gr.grid_id loop
    region := case g.geo_kind when 'state' then ser.geo when 'ba' then ser.key else ser.key end;
    select * into fe from ripples.att_fx_event f where f.grid_id = g.grid_id and f.event_id = c.event_id and f.role = 'real' and f.decoy_set = 0 and f.computed_at is not null;
    if found and region = any(fe.treated) and fe.p_space is not null then
      reg_pass := fe.p_space <= qm and coalesce(fe.p_pre, 0) >= ppre and (c.sign = 0 or sign(fe.d) = c.sign) and (fe.synth_d is null or sign(fe.synth_d) = sign(fe.d));
      ev := ev || jsonb_build_object('grid_id', g.grid_id, 'pair', g.label, 'region', region, 'd', fe.d, 'z', fe.z, 'p_space', fe.p_space, 'p_pre', fe.p_pre,
                                     'p_time', fe.p_time, 'synth_d', fe.synth_d, 'synth_p', fe.synth_p, 'n_donors', fe.n_donors, 'regional_pass', reg_pass,
                                     'window', jsonb_build_object('pre', g.pre_n, 'post', g.post_n, 'lag', g.lag_n));
    end if;
    select * into po from ripples.att_fx_pool p where p.grid_id = g.grid_id and p.role = 'real' and p.decoy_set = 0;
    if found and po.n_events >= kmin then
      fam_state := case when (c.sign = 0 or sign(po.d) = c.sign) and po.p_placebo <= 0.05 then 'agrees' else 'disagrees' end;
      ev := ev || jsonb_build_object('family', jsonb_build_object('grid_id', g.grid_id, 'n_events', po.n_events, 'd', po.d, 'se', po.se, 'i2', po.i2, 'p_placebo', po.p_placebo, 'q', po.q, 'strength', po.strength, 'state', fam_state));
    elsif found then
      fam_state := 'too few events';
      ev := ev || jsonb_build_object('family', jsonb_build_object('grid_id', g.grid_id, 'n_events', po.n_events, 'state', fam_state));
    end if;
    exit;   -- the most specific frozen pair (sub-family first) binds
  end loop;
  if ev = '{}'::jsonb then return p_fails; end if;
  if reg_pass then
    lifted := array(select x from unnest(fails) x where x in ('q above 0.05', 'a placebo family disagrees', 'one channel only', 'placebo families', 'final look not reached'));
    fails := array(select x from unnest(fails) x where x not in ('q above 0.05', 'a placebo family disagrees', 'one channel only', 'placebo families', 'final look not reached'));
  end if;
  if fam_state = 'disagrees' then fails := array_append(fails, 'no pattern across ' || (ev #>> '{family,n_events}') || ' past events'); end if;
  update ripples.att_hop_tests t set detail = coalesce(t.detail, '{}'::jsonb) || jsonb_build_object('fx62', ev || jsonb_build_object('lifted', to_jsonb(lifted), 'family_state', fam_state))
   where t.hop_id = p_hop and t.look_no = p_look;
  return fails;
end $$;

-- install the hook line in att_finalize (anchor-checked; idempotent; re-reads the LIVE definition so a redeploy by the 6.1 owner is respected)
create or replace function ripples.att_fx_hook_install() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare def text; anchor text := E'elsif not (v_final_agree or r.is_final) then fails := array_append(fails, \'final look not reached\'); end if;\n    cs := coalesce(r.common_shock, false);';
        hook text := E'elsif not (v_final_agree or r.is_final) then fails := array_append(fails, \'final look not reached\'); end if;\n    fails := ripples.att_fx_hook(r.hop_id, r.look_no, fails);   -- ENGINE 6.2 HOOK (30_att_engine_62): regional contrast / family pattern\n    cs := coalesce(r.common_shock, false);';
        n int;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace where n2.nspname = 'ripples' and p.proname = 'att_finalize';
  if def is null then return jsonb_build_object('installed', false, 'reason', 'att_finalize not found'); end if;
  if position('ripples.att_fx_hook(' in def) > 0 then return jsonb_build_object('installed', true, 'already', true); end if;
  n := (length(def) - length(replace(def, anchor, ''))) / length(anchor);
  if n <> 1 then return jsonb_build_object('installed', false, 'reason', 'anchor count ' || n); end if;
  execute replace(def, anchor, hook);
  return jsonb_build_object('installed', true, 'already', false);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 9. Family-level findings: view + public RPC (leak-guarded, anon read of public-safe fields only)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_fx_outcome_label(p_source text, p_metric text) returns text
language sql immutable set search_path = '' as $$
  select case p_source || ':' || p_metric
    when 'dol.claims:ic' then 'state initial jobless claims' when 'dol.claims:cw' then 'state continued jobless claims'
    when 'eia.930:demand' then 'regional grid electricity demand' when 'census.bfs:ba' then 'state new-business applications'
    when 'fema.decl:n' then 'FEMA disaster declarations in the state' when 'noaa.ghcnd:prcp' then 'state precipitation'
    when 'noaa.ghcnd:temp' then 'state temperature' when 'tsa.pax:n' then 'US airport checkpoint passengers'
    when 'npm.dl:n' then 'npm downloads of the vendor SDK' else p_source || ':' || p_metric end
$$;

create or replace view ripples.att_family_effects as
  select g.grid_id, g.batch, g.family, f.label as family_label, g.sub, g.source, g.metric, g.geo_kind, ripples.att_fx_outcome_label(g.source, g.metric) as outcome_label,
         g.domain_event, g.domain_outcome, g.definitional, (g.bh_weight = 0) as is_check, g.expected_sign, g.pre_n, g.post_n, g.lag_n,
         (select grain from ripples.att_fx_panel pn where pn.source = g.source and pn.metric = g.metric and pn.geo_kind = g.geo_kind) as grain,
         p.n_events, p.n_skipped, p.d, p.se, p.ci_lo, p.ci_hi, round((100 * (exp(p.d) - 1))::numeric, 1) as pct, round((100 * (exp(p.ci_lo) - 1))::numeric, 1) as pct_lo,
         round((100 * (exp(p.ci_hi) - 1))::numeric, 1) as pct_hi, p.tau2, p.i2, p.p_norm, p.p_placebo, p.q, p.sign_ok, p.dose_slope, p.dose_se, p.dose_p, p.n_dose,
         p.strength, p.payload, p.computed_at, g.ledger_seq, g.frozen_hash
    from ripples.att_fx_grid g join ripples.att_families f on f.family = g.family
    left join ripples.att_fx_pool p on p.grid_id = g.grid_id and p.role = 'real' and p.decoy_set = 0;
revoke all on ripples.att_family_effects from anon, authenticated, public;

-- public read: "patterns across N past events". Only frozen, computed pairs; MONEY-channel outcomes hidden by rm_node_hidden; sample
-- events resolved through rm_label_resolve. Wording is fixed here: "measured across N past events" — never a probability of causation.
create or replace function public.rm_patterns(p_family text default null, p_min text default 'hint') returns jsonb
language sql stable security definer set search_path = '' as $$
  with ranked as (
    select v.*, case v.strength when 'strong pattern' then 4 when 'pattern' then 3 when 'unexpected direction' then 2 when 'hint' then 1 when 'check passed' then 1 else 0 end as rank_
    from ripples.att_family_effects v
    where v.ledger_seq is not null and v.computed_at is not null and v.n_events is not null
      and not ripples.rm_node_hidden(v.source || ':' || v.metric)
      and (p_family is null or v.family = p_family))
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.grid_id, 'family', r.family, 'family_label', r.family_label, 'sub', r.sub,
    'event_label', case when r.sub = 'hurricane' then 'Hurricanes' else r.family_label || 's' end,
    'outcome', r.source || ':' || r.metric, 'outcome_label', r.outcome_label, 'geo_kind', r.geo_kind,
    'design', case when r.geo_kind = 'national' and r.source = 'tsa.pax' then 'event study (season-matched placebos)' else 'affected vs unaffected regions (difference-in-differences, in-space + in-time placebos)' end,
    'window', jsonb_build_object('pre', r.pre_n, 'post', r.post_n, 'lag', r.lag_n, 'grain', r.grain),
    'n_events', r.n_events, 'effect_pct', r.pct, 'ci_pct', jsonb_build_array(r.pct_lo, r.pct_hi), 'effect_logpts', round(r.d::numeric, 4),
    'i2', round(coalesce(r.i2, 0)::numeric, 2), 'p_placebo', r.p_placebo, 'q', r.q, 'strength', r.strength, 'sign_expected', r.expected_sign, 'sign_ok', r.sign_ok,
    'is_check', r.is_check, 'definitional', r.definitional, 'non_obvious', r.domain_outcome in ('labor', 'business', 'travel', 'developer'),
    'dose', case when r.dose_slope is not null then jsonb_build_object('slope_logpts_per_unit', round(r.dose_slope::numeric, 4), 'p', r.dose_p, 'n', r.n_dose) end,
    'n_regional_pass', r.payload -> 'n_regional_pass', 'n_pretrend_flat', r.payload -> 'n_pretrend_flat', 'share_positive', r.payload -> 'share_positive',
    'fluke_note', case r.strength when 'strong pattern' then 'about 1 in 20 findings at this level could be a fluke' when 'pattern' then 'about 1 in 5 findings at this level could be a fluke'
                                  when 'hint' then 'did not survive the multiple-comparison correction; treat as a lead' when 'check passed' then 'a pre-registered sanity check, not a finding' else null end,
    'headline', case when r.sub = 'hurricane' then 'Hurricanes' else r.family_label || 's' end || ' → ' || r.outcome_label || ': ' || case when r.pct >= 0 then '+' else '' end || r.pct || '% over ' || r.post_n || ' ' || case r.grain when 'week' then 'weeks' else 'days' end || ', measured across ' || r.n_events || ' past events',
    'wording', 'measured across ' || r.n_events || ' past events',
    'sample_events', (select jsonb_agg(jsonb_build_object('label', coalesce(ripples.rm_label_resolve(e.qid, e.label), e.label), 'onset', f.onset, 'effect_pct', round((100 * (exp(f.d - f.med) - 1))::numeric, 1), 'z', round(f.z::numeric, 2), 'p_space', f.p_space) order by abs(f.z) desc)
                      from (select * from ripples.att_fx_event f0 where f0.grid_id = r.grid_id and f0.role = 'real' and f0.z is not null order by abs(f0.z) desc limit 3) f
                      join ripples.att_events e on e.event_id = f.event_id where coalesce(e.sensitive, false) = false),
    'ledger_seq', r.ledger_seq, 'computed_at', r.computed_at
  ) order by r.rank_ desc, coalesce(r.q, 1), r.p_placebo), '[]'::jsonb)
  from ranked r
  where r.rank_ >= case p_min when 'strong pattern' then 4 when 'pattern' then 3 when 'hint' then 1 else 0 end
$$;
revoke all on function public.rm_patterns(text, text) from public;
grant execute on function public.rm_patterns(text, text) to anon, authenticated, service_role;

-- per-hop evidence for the card: the event's own regional contrast + the family pattern (detail -> 'fx62' of the latest tiered look)
create or replace function public.rm_hop_fx62(p_hop bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select t.detail -> 'fx62' from ripples.att_hop_tests t join ripples.att_hop_candidates c on c.hop_id = t.hop_id
   where t.hop_id = p_hop and t.tier is not null and not ripples.rm_node_hidden(c.node) order by t.look_no desc limit 1
$$;
revoke all on function public.rm_hop_fx62(bigint) from public;
grant execute on function public.rm_hop_fx62(bigint) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 10. Method bump: a model_version ledger row for 6.2 (config + grid spec hashed)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_fx_model_version_register() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare payload jsonb; h text; existing bigint; v_seq bigint;
begin
  payload := jsonb_build_object('method', '6.2', 'object', 'engine62', 'engine62_config', ripples._att_cfg('engine62'), 'grid_spec', ripples.att_fx_grid_spec(),
                                'base', ripples._att_cfg('engine') ->> 'method', 'tier_rule', 'Measured: (6.1 per-event pass OR regional contrast pass) AND (family pattern agrees when the frozen pair has >= K events) AND the downstream forecast gate (att_ce_gate)');
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  select seq into existing from ripples.att_ledger where kind = 'model_version' and payload_hash = h limit 1;
  if existing is not null then return jsonb_build_object('seq', existing, 'hash', h, 'new', false); end if;
  v_seq := ripples.att_ledger_append(current_date, 'model_version', jsonb_build_object('method', '6.2', 'object', 'engine62'), payload);
  return jsonb_build_object('seq', v_seq, 'hash', h, 'new', true);
end $$;

do $$ declare t text; begin
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_fx\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;
