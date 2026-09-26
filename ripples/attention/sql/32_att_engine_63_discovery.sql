-- Migration: att_engine_63_discovery (engine method 6.2.1 → 6.3 "discovery expansion", 2026-09-26)
-- ADDITIVE on top of 6.1 (28_) and 6.2 (30_). Nothing in 20–30 is rewritten; the only touch on a 6.2 body is one anchor-checked,
-- idempotent hook line in ripples.att_fx_cluster_dups (monthly grain for the overlap rule, installed by att_fx63_hook_install()).
-- The 6.2 tier hook (att_fx_hook / att_finalize) and public.rm_patterns are NOT touched by anything here: every 6.3 grid row keeps
-- att_fx_grid.ledger_seq NULL (its ledger seqs live in att_fx63_batch), so the 6.2 hook, att_fx_live_calc and rm_patterns never
-- see a 6.3 row; 6.3 event rows use roles explore / confirm / dx / dc (never 'real' / 'live' / 'decoy'); 6.3 panels use metric
-- suffixes _w / _m so the nightly 6.2 panel refresh skips them and no series metric ever matches them.
--
--   1. SPLIT-SAMPLE DISCOVERY → CONFIRMATION. An exploration grid over ALL (event family × regional outcome panel × window
--      variant) pairs is computed on the EXPLORATION half of the archive (event onset < split_date 2022-01-01) with a permissive
--      config (30 in-time / 20 in-space placebo draws, no synthetic control), pooled with 6.2's DerSimonian–Laird + placebo-pool
--      estimator (att_fx_pool_run, unchanged), and ranked by the pre-declared rule (config engine63.rule, hashed into the ledger
--      BEFORE any exploration effect is computed): n ≥ 6, placebo p ≤ 0.10, |effect| ≥ 1 % (0.05 raw units for rates), one window
--      variant per (family, outcome) pair (the smaller p; tie → the shorter window), at most K = 12 findings by p rank. Checks
--      (definitional pairs, bh_weight 0) are selected by the same rule but sit outside the cap and the BH family. The selected
--      pairs are FROZEN (windows, exploration sign, held-out event lists; ledger kind 'freeze', object fx_grid, stage confirm) and
--      CONFIRMED on the HELD-OUT half (onset ≥ split_date) with the full 6.2 config (40 / 30 draws), placebo-pool p, sign must
--      match the exploration sign, BH over the confirmation set only. Published patterns = confirmed only ('confirmed pattern'
--      q ≤ 0.05, 'confirmed pattern (weaker)' q ≤ 0.20); exploration hits that did not confirm are 'hunches' (public.rm_hunches),
--      never Likely / Measured, never a "pattern" — with their held-out verdict ('not replicated' / 'reversed' / 'too few held-out
--      events') shown next to them ("things we thought would move, but didn't").
--      The exploration freeze payload ALSO lists every pair's held-out event ids (hashed) so the held-out set is provably fixed
--      before exploration results existed; the confirmation freeze re-derives them and asserts the per-grid hash is unchanged.
--   2. NEW PANELS (6.3 builders, att_fx63_panel_build): weekly aggregates of daily series (fema.decl:n_w = weekly declaration
--      counts, eia.930:demand_w = weekly mean demand) and monthly state panels from FRED (fred.state: leih_m leisure & hospitality
--      employment, cons_m construction employment, ur_m unemployment rate [raw pp], bppriv_m private housing permits) — official,
--      keyed, first-release values (att-econ mode fred_state).
--   3. NEW FAMILY: policy.min_wage — one event per January 1 (2016 →) whose treated set is the states whose DOL minimum wage rose
--      vs the prior year (FRED STTMINWG<ST>, source U.S. Department of Labor). States with statutory non-January effective dates
--      are excluded (list in att_fx63_minwage_register). N ≈ 11 → no held-out confirmation is possible; registered and run as a
--      clearly-labelled single-sample pre-registered test (its own BH family), never as a confirmed pattern.
--   4. POWER: window variants (immediate + delayed = pre-registered distributed-lag "Delay" windows), weekly aggregation for sparse
--      or noisy daily outcomes, EB shrinkage of event-level estimates toward the confirmed pool (att_fx63_shrink), all measured on
--      the spike-in tests T44/T45.
--   5. CALIBRATION: decoy universes (season-matched pseudo-onsets for BOTH halves, roles dx / dc) through the full pipeline →
--      false-confirmation rate with Wilson CI; in-space placebo uniformity per panel; known positives (definitional checks,
--      cold → demand, heat → demand out of sample); the 6.1 common-shock (Thanksgiving) guard is untouched (T48).
--   6. SURPRISE FIELDS for the story layer: domain_distance (0 / 0.5 / 1 from the config domain matrix) and expected_by_mechanism
--      (the family's mapper or the mechanism graph already links the family to the outcome source). No story score is computed here.
--   Storage: ≤ ~12 MB (event rows with 30/40-float placebo arrays; decoy explore arrays are nulled after the calibration row is
--   on the ledger). Every statement is chunked (att_fx63_step ≤ 50 s, parallel-safe via advisory locks).

create schema if not exists ripples;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0. Config (frozen defaults; `on conflict do nothing` so a re-run never silently changes a pre-registered threshold)
-- ---------------------------------------------------------------------------------------------------------------------
insert into ripples.att_config(key, value) values ('engine63', jsonb_build_object(
  'method', '6.3',
  'split_date', '2022-01-01',
  'explore', jsonb_build_object('n_time', 30, 'n_space', 20, 'n_synth', 0, 'min_cover', 0.7, 'season_band', 21, 'se_floor', 0.005, 'min_donors', 5),
  'confirm', jsonb_build_object('n_time', 40, 'n_space', 30, 'n_synth', 0, 'min_cover', 0.7, 'season_band', 21, 'se_floor', 0.005, 'min_donors', 5),
  'rule', jsonb_build_object('x_n_min', 6, 'x_p_max', 0.10, 'x_abs_min_log', 0.01, 'x_abs_min_raw', 0.05, 'k_cap', 12, 'c_n_min', 8,
                             'q_strong', 0.05, 'q_pattern', 0.20, 'one_variant_per_pair', true, 'tie_break', 'shorter window'),
  'decoy_sets', 2,
  'domains', jsonb_build_object(
    'hazard', jsonb_build_object('hazard', 0, 'weather', 0, 'power', 0.5, 'government', 0.5, 'labor', 1, 'business', 1, 'travel', 1, 'developer', 1, 'housing', 1),
    'policy', jsonb_build_object('policy', 0, 'labor', 0, 'business', 0.5, 'housing', 0.5, 'government', 0.5, 'power', 1, 'weather', 1, 'travel', 1, 'developer', 1),
    'tech',   jsonb_build_object('tech', 0, 'developer', 0, 'business', 0.5, 'labor', 1, 'housing', 1, 'government', 1, 'power', 1, 'weather', 1, 'travel', 1))))
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tables (service-only: RLS on, no grants)
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists ripples.att_fx63_batch (
  batch text primary key, split_date date not null, cfg jsonb not null,
  explore_seq bigint, confirm_seq bigint, calib_seq bigint, explore_hash text, confirm_hash text,
  status text not null default 'frozen', note text, created_at timestamptz not null default now(), updated_at timestamptz);

create table if not exists ripples.att_fx63_select (
  batch text not null references ripples.att_fx63_batch(batch), grid_id int not null references ripples.att_fx_grid(grid_id),
  decoy_set int not null default 0,
  x_n int, x_d real, x_se real, x_p real, x_sign smallint, x_ok boolean, variant_best boolean, rank int,
  selected boolean not null default false, reason text,
  c_n int, c_d real, c_se real, c_ci_lo real, c_ci_hi real, c_tau2 real, c_i2 real, c_p real, c_p_norm real, c_q real, c_sign_ok boolean,
  c_n_clustered_out int, c_n_regional_pass int, verdict text, strength text,
  domain_distance real, expected_by_mechanism boolean, computed_at timestamptz,
  primary key (batch, grid_id, decoy_set));

alter table ripples.att_fx63_batch enable row level security;
alter table ripples.att_fx63_select enable row level security;
revoke all on ripples.att_fx63_batch, ripples.att_fx63_select from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. 6.3 panel builders: weekly aggregates of daily series and monthly panels (metric suffix _w / _m; same prefix-sum layout
--    as att_fx_panel_build so every 6.2 estimator works unchanged)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_fx63_panel_build(p_source text, p_metric text, p_geo_kind text, p_agg text, p_value_kind text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_from date := '2015-01-01'; v_to date := current_date; vk text; out_metric text; grain text; days date[]; regs text[]; n int; nr int;
        ps float8[] := '{}'; pc int2[] := '{}'; r record; i int; acc float8; cnt int; v float8[]; ps_r float8[]; pc_r int2[];
begin
  if p_agg not in ('week', 'month') then return jsonb_build_object('error', 'p_agg must be week or month'); end if;
  out_metric := p_metric || case p_agg when 'week' then '_w' else '_m' end;
  create temp table _fxs63 on commit drop as
    select case when p_geo_kind = 'state' then s.geo else s.key end as region, s.series_id
    from ripples.att_series s
    where s.source = p_source and s.metric = p_metric
      and case p_geo_kind when 'state' then s.geo ~ '^US-[A-Z]{2}$'
                          when 'ba' then s.key !~ '^(US48|__total__|all)$' and s.key !~ ':'
                          else true end;
  if not exists (select 1 from _fxs63) then drop table _fxs63; return jsonb_build_object('error', 'no series'); end if;
  vk := coalesce(p_value_kind,
                 (select z.value_kind from ripples.att_zvec z join _fxs63 f on f.series_id = z.series_id where z.value_kind is not null limit 1),
                 (select so.value_kind from ripples.att_sources so where so.source = p_source), 'count');
  if vk not in ('rate', 'count', 'level') then vk := 'level'; end if;
  -- raw per (region, day); several series per region are averaged on the raw scale
  create temp table _fxr63 on commit drop as
    select f.region, o.day, avg(o.value) as y
    from _fxs63 f join lateral (select * from ripples.att_series_daily(f.series_id, v_from, v_to)) o on true
    where o.value is not null group by 1, 2;
  if p_agg = 'week' then
    -- Saturday-ending weeks (the claims / BFS convention); counts are summed, levels averaged, rates averaged; ≥ 4 observed days
    create temp table _fxo63 on commit drop as
      select region, (date_trunc('week', (day + 1)::timestamp)::date + 5) as day,
             case when vk = 'rate' then avg(y) when vk = 'count' then ln(1 + greatest(sum(y), 0)) else ln(1 + greatest(avg(y), 0)) end as y
      from _fxr63 group by 1, 2 having count(*) >= 4;
    grain := 'week';
  else
    create temp table _fxo63 on commit drop as
      select region, day, case when vk = 'rate' then y else ln(1 + greatest(y, 0)) end as y from _fxr63;
    grain := 'month';
  end if;
  select array_agg(d order by d) into days from (select distinct day d from _fxo63) x;
  n := cardinality(days);
  select array_agg(region order by region) into regs from (select distinct region from _fxo63) x;
  nr := cardinality(regs);
  create temp table _fxd63 on commit drop as select d, ord::int as idx from unnest(days) with ordinality u(d, ord);
  create index on _fxd63(d);
  for r in select region from unnest(regs) region order by region loop
    select array_agg(o.y order by dd.idx) into v from _fxd63 dd left join _fxo63 o on o.day = dd.d and o.region = r.region;
    acc := 0; cnt := 0; ps_r := array_fill(0::float8, array[n]); pc_r := array_fill(0::int2, array[n]);
    for i in 1..n loop
      if v[i] is not null then acc := acc + v[i]; cnt := cnt + 1; end if;
      ps_r[i] := acc; pc_r[i] := cnt;
    end loop;
    if cardinality(ps) = 0 then ps := array[ps_r]; pc := array[pc_r]; else ps := ps || ps_r; pc := pc || pc_r; end if;
  end loop;
  insert into ripples.att_fx_panel(source, metric, geo_kind, grain, value_kind, days, regions, n, ps, pc, built_at)
  values (p_source, out_metric, p_geo_kind, grain, vk, days, regs, n, ps, pc, now())
  on conflict (source, metric, geo_kind) do update set grain = excluded.grain, value_kind = excluded.value_kind, days = excluded.days,
    regions = excluded.regions, n = excluded.n, ps = excluded.ps, pc = excluded.pc, built_at = now();
  drop table _fxs63; drop table _fxr63; drop table _fxo63; drop table _fxd63;
  return jsonb_build_object('source', p_source, 'metric', out_metric, 'geo_kind', p_geo_kind, 'grain', grain, 'value_kind', vk, 'n', n,
                            'regions', nr, 'from', days[1], 'to', days[n]);
end $$;

-- the 6.3 panel set (built now and nightly after the 6.2 refresh; a missing source simply returns an error object)
create or replace function ripples.att_fx63_panel_spec() returns jsonb
language sql immutable set search_path = '' as $$
  select '[
    {"source":"fema.decl","metric":"n","geo_kind":"state","agg":"week","value_kind":"count"},
    {"source":"eia.930","metric":"demand","geo_kind":"ba","agg":"week","value_kind":"level"},
    {"source":"fred.state","metric":"leih","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"cons","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"ur","geo_kind":"state","agg":"month","value_kind":"rate"},
    {"source":"fred.state","metric":"bppriv","geo_kind":"state","agg":"month","value_kind":"count"}
  ]'::jsonb
$$;
create or replace function ripples.att_fx63_panel_refresh() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare s jsonb; out jsonb := '[]'::jsonb;
begin
  for s in select * from jsonb_array_elements(ripples.att_fx63_panel_spec()) loop
    out := out || ripples.att_fx63_panel_build(s ->> 'source', s ->> 'metric', s ->> 'geo_kind', s ->> 'agg', s ->> 'value_kind');
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. HOOK on a 6.2 body (anchor-checked, idempotent, re-reads the live definition): the overlap rule's day-per-observation
--    factor for the new 'month' grain. Without it a monthly panel would treat 'lag + post' months as days.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_fx63_hook_install() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare def text; n int;
        anchor text := $a$case pn.grain when 'week' then 7 else 1 end as gd$a$;
        hook text := $a$case pn.grain when 'week' then 7 when 'month' then 30 /* ENGINE 6.3 (32_att_engine_63): monthly grain */ else 1 end as gd$a$;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace where n2.nspname = 'ripples' and p.proname = 'att_fx_cluster_dups';
  if position('ENGINE 6.3 (32_att_engine_63)' in def) > 0 then return jsonb_build_object('installed', true, 'already', true); end if;
  n := (length(def) - length(replace(def, anchor, ''))) / length(anchor);
  if n <> 1 then return jsonb_build_object('installed', false, 'reason', 'anchor count ' || n); end if;
  execute replace(def, anchor, hook);
  return jsonb_build_object('installed', true, 'already', false);
end $$;
select ripples.att_fx63_hook_install();

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Surprise fields (pure): domain distance from the config matrix; "expected by the mechanism library" = the family's mapper
--    or a live mechanism-graph edge already links the family to the outcome source (dol.claims ≡ fred.claims: both state claims)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.att_fx63_domain_distance(p_de text, p_do text) returns real
language sql stable set search_path = '' as $$
  select coalesce((ripples._att_cfg('engine63') -> 'domains' -> p_de ->> p_do)::real,
                  case when p_de = p_do then 0 else 1 end)
$$;
create or replace function ripples.att_fx63_expected_by_mechanism(p_family text, p_source text) returns boolean
language sql stable security definer set search_path = '' as $$
  with src as (select unnest(case when p_source in ('dol.claims', 'fred.claims') then array['dol.claims', 'fred.claims'] else array[p_source] end) s)
  select exists (select 1 from ripples.att_families f, jsonb_array_elements(coalesce(f.mapper, '[]'::jsonb)) m, src
                  where f.family = p_family
                    and (m ->> 'node' like src.s || ':%' or m ->> 'node_pattern' like src.s || ':%' or m ->> 'source' = src.s))
      or exists (select 1 from ripples.att_mech_edges e, src where e.valid_to is null and e.from_node = 'family:' || p_family and e.to_node like src.s || ':%')
$$;
create or replace function ripples.att_fx63_outcome_label(p_source text, p_metric text) returns text
language sql immutable set search_path = '' as $$
  select case p_source || ':' || p_metric
    when 'fema.decl:n_w' then 'FEMA disaster declarations in the state (weekly)'
    when 'eia.930:demand_w' then 'regional grid electricity demand (weekly)'
    when 'fred.state:leih_m' then 'state leisure & hospitality employment'
    when 'fred.state:cons_m' then 'state construction employment'
    when 'fred.state:ur_m' then 'state unemployment rate'
    when 'fred.state:bppriv_m' then 'state private housing permits'
    else ripples.att_fx_outcome_label(p_source, p_metric) end
$$;

-- empirical-Bayes partial pooling (pure): event-level estimates d[] with se[] shrunk toward the DL random-effects pool of the same
-- inputs (τ² from att_fx_dl). Returns rows (i, d_raw, se_raw, d_shrunk, se_shrunk, weight_on_pool).
create or replace function ripples.att_fx63_shrink(p_d float8[], p_se float8[])
returns table(i int, d_raw float8, se_raw float8, d_shrunk float8, se_shrunk float8, w_pool float8)
language plpgsql immutable set search_path = '' as $$
declare r float8[]; k int := cardinality(p_d); j int; tau2 float8; b float8;
begin
  if k = 0 then return; end if;
  r := ripples.att_fx_dl(p_d, p_se);
  tau2 := coalesce(r[3], 0);
  for j in 1..k loop
    b := p_se[j]^2 / (p_se[j]^2 + tau2);                       -- weight on the pool (1 when τ² = 0: full pooling)
    i := j; d_raw := p_d[j]; se_raw := p_se[j];
    d_shrunk := (1 - b) * p_d[j] + b * r[1];
    se_shrunk := sqrt(1 / (1 / greatest(p_se[j]^2, 1e-12) + 1 / greatest(tau2, 1e-12)));
    if tau2 <= 0 then se_shrunk := r[2]; end if;
    w_pool := b;
    return next;
  end loop;
end $$;

do $$ declare t text; begin
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_fx63\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;
