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

-- =====================================================================================================================
-- P2 (migration att_engine_63_p2_pipeline): grid spec, exploration freeze, chunked parallel-safe runner, decoy universes,
-- the pre-declared selection rule, confirmation freeze, verdicts + BH over the confirmation set, calibration, model_version.
-- Batch naming: att_fx_grid's unique index is (batch, family, sub, source, metric, geo_kind) — it has no window columns — so the
-- two window variants of a pair are stored under batch '<base>/immediate' and '<base>/delayed'; att_fx63_batch.batch is <base>.
-- =====================================================================================================================
alter table ripples.att_fx63_batch add column if not exists confirm_hashes jsonb;   -- {grid_id: sha256 of the held-out event list}

-- 5. The exploration grid: every hazard family × every regional panel × two pre-registered window variants
--    (immediate / delayed = distributed-lag "Delay" window). Sign 0 = two-sided exploration; the exploration sign becomes the
--    confirmation's expected sign. definitional = the outcome defines the events (FEMA-declared families → FEMA counts): a CHECK
--    (bh_weight 0), published as a known positive, never a finding.
create or replace function ripples.att_fx63_grid_spec() returns jsonb
language sql immutable set search_path = '' as $$
  with fam as (select * from (values
      ('hazard.storm', null::text, true), ('hazard.storm', 'hurricane', true), ('hazard.heat', null, false), ('hazard.cold', null, true),
      ('hazard.flood', null, true), ('hazard.wildfire', null, true), ('hazard.quake', null, true)) f(family, sub, fema_defined)),
  pan as (select * from (values
      ('dol.claims', 'ic', 'state', 'labor', '[[8,4,0,"immediate"],[8,4,4,"delayed"]]'::jsonb),
      ('dol.claims', 'cw', 'state', 'labor', '[[8,4,1,"immediate"],[8,4,5,"delayed"]]'),
      ('census.bfs', 'ba', 'state', 'business', '[[8,4,0,"immediate"],[8,4,4,"delayed"]]'),
      ('eia.930', 'demand', 'ba', 'power', '[[28,7,0,"immediate"],[28,14,7,"delayed"]]'),
      ('eia.930', 'demand_w', 'ba', 'power', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('fema.decl', 'n_w', 'state', 'government', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('fred.state', 'leih_m', 'state', 'labor', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('fred.state', 'cons_m', 'state', 'labor', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('fred.state', 'ur_m', 'state', 'labor', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('fred.state', 'bppriv_m', 'state', 'housing', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]')) p(source, metric, geo_kind, dom, variants))
  select jsonb_agg(jsonb_build_object('family', f.family, 'sub', f.sub, 'source', p.source, 'metric', p.metric, 'geo_kind', p.geo_kind,
                                      'de', 'hazard', 'do', p.dom, 'variants', p.variants,
                                      'definitional', (p.source = 'fema.decl' and f.fema_defined),
                                      'w', case when p.source = 'fema.decl' and f.fema_defined then 0 else 1 end)
                   order by f.family, f.sub nulls first, p.source, p.metric)
  from fam f cross join pan p
$$;

-- held-out (confirmation) candidates of a grid row, straight from the archive (used by the freeze hash, the confirmation freeze
-- and the decoy confirmation seeding; the freeze asserts this list is unchanged between the two freezes)
create or replace function ripples.att_fx63_confirm_events(p_grid int) returns table(event_id bigint, onset date, treated text[], magnitude real)
language plpgsql stable security definer set search_path = '' as $$
declare g record; pan record; e record; tr text[]; split date := (ripples._att_cfg('engine63') ->> 'split_date')::date;
begin
  select * into g from ripples.att_fx_grid where grid_id = p_grid;
  select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
  if not found then return; end if;
  for e in select ev.event_id, ev.onset, ev.magnitude from ripples.att_events ev join ripples.att_topics t on t.topic_id = ev.topic_id
           where ev.family = g.family and ev.role = 'library' and (g.sub is null or (g.sub = 'hurricane' and t.meta ? 'storm'))
             and ev.onset >= split and ev.onset between pan.days[1] and pan.days[pan.n] order by ev.onset, ev.event_id loop
    tr := ripples.att_fx_treated(e.event_id, g.geo_kind, g.target_map);
    select coalesce(array_agg(x order by x), '{}') into tr from unnest(tr) x where x = any(pan.regions);
    continue when cardinality(tr) = 0;
    event_id := e.event_id; onset := e.onset; treated := tr; magnitude := e.magnitude;
    return next;
  end loop;
end $$;
create or replace function ripples.att_fx63_confirm_hash(p_grid int) returns text
language sql stable security definer set search_path = '' as $$
  select encode(extensions.digest(coalesce((select string_agg(event_id || ':' || onset || ':' || array_to_string(treated, ',') || ':' || coalesce(magnitude::text, ''), '|' order by event_id)
                                            from ripples.att_fx63_confirm_events(p_grid)), ''), 'sha256'), 'hex')
$$;

-- 6. Exploration freeze: grid rows + exploration event lists + the held-out candidate lists, hashed into the ledger BEFORE any
--    exploration effect exists. Pairs whose panel is absent are skipped (a later batch can add them). Idempotent per batch.
create or replace function ripples.att_fx63_freeze(p_batch text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := ripples._att_cfg('engine63'); split date := (cfg ->> 'split_date')::date; s jsonb; v jsonb; g record; e record; tr text[];
        n_x int := 0; n_c int := 0; n_g int := 0; payload jsonb; h text; v_seq bigint; pan record; conf jsonb := '[]'::jsonb; hashes jsonb := '{}'::jsonb;
begin
  if exists (select 1 from ripples.att_fx63_batch where batch = p_batch and explore_seq is not null) then
    return jsonb_build_object('batch', p_batch, 'already_frozen', true, 'seq', (select explore_seq from ripples.att_fx63_batch where batch = p_batch));
  end if;
  insert into ripples.att_fx63_batch(batch, split_date, cfg, status) values (p_batch, split, cfg, 'exploring') on conflict (batch) do nothing;
  for s in select * from jsonb_array_elements(ripples.att_fx63_grid_spec()) loop
    continue when not exists (select 1 from ripples.att_fx_panel p where p.source = s ->> 'source' and p.metric = s ->> 'metric' and p.geo_kind = s ->> 'geo_kind');
    for v in select * from jsonb_array_elements(s -> 'variants') loop
      insert into ripples.att_fx_grid(batch, family, sub, source, metric, geo_kind, pre_n, post_n, lag_n, expected_sign, synth, definitional,
                                      domain_event, domain_outcome, target_map, bh_weight, label, status)
      values (p_batch || '/' || (v ->> 3), s ->> 'family', s ->> 'sub', s ->> 'source', s ->> 'metric', s ->> 'geo_kind', (v ->> 0)::int, (v ->> 1)::int, (v ->> 2)::int,
              0, false, (s ->> 'definitional')::boolean, s ->> 'de', s ->> 'do', null, (s ->> 'w')::real,
              coalesce(s ->> 'sub', s ->> 'family') || ' → ' || (s ->> 'source') || ':' || (s ->> 'metric') || ' [' || (v ->> 3) || ']', 'fx63')
      on conflict do nothing;
      n_g := n_g + 1;
    end loop;
  end loop;
  for g in select * from ripples.att_fx_grid where batch like p_batch || '/%' order by grid_id loop
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    for e in select ev.event_id, ev.onset, ev.magnitude from ripples.att_events ev join ripples.att_topics t on t.topic_id = ev.topic_id
             where ev.family = g.family and ev.role = 'library' and (g.sub is null or (g.sub = 'hurricane' and t.meta ? 'storm'))
               and ev.onset < split and ev.onset between pan.days[1] and pan.days[pan.n] order by ev.onset loop
      tr := ripples.att_fx_treated(e.event_id, g.geo_kind, g.target_map);
      select coalesce(array_agg(x order by x), '{}') into tr from unnest(tr) x where x = any(pan.regions);
      continue when cardinality(tr) = 0;
      insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude)
      values (g.grid_id, e.event_id, 'explore', 0, e.onset, tr, e.magnitude) on conflict do nothing;
      n_x := n_x + 1;
    end loop;
    -- held-out candidates: listed and hashed now, computed only if the pair is selected
    select conf || coalesce(jsonb_agg(jsonb_build_array(g.grid_id, c.event_id, c.onset, c.treated, c.magnitude) order by c.event_id), '[]'::jsonb), n_c + count(*)
      into conf, n_c from ripples.att_fx63_confirm_events(g.grid_id) c;
    hashes := hashes || jsonb_build_object(g.grid_id::text, ripples.att_fx63_confirm_hash(g.grid_id));
  end loop;
  payload := jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'explore', 'batch', p_batch, 'split_date', split, 'config', cfg,
    'grid', (select jsonb_agg(jsonb_build_array(grid_id, batch, family, sub, source, metric, geo_kind, pre_n, post_n, lag_n, definitional, bh_weight) order by grid_id) from ripples.att_fx_grid where batch like p_batch || '/%'),
    'explore_events', (select jsonb_agg(jsonb_build_array(f.grid_id, f.event_id, f.onset, f.treated, f.magnitude) order by f.grid_id, f.event_id) from ripples.att_fx_event f join ripples.att_fx_grid g2 on g2.grid_id = f.grid_id where g2.batch like p_batch || '/%' and f.role = 'explore'),
    'confirm_candidates', conf, 'confirm_hashes', hashes,
    'panels', (select jsonb_agg(jsonb_build_array(source, metric, geo_kind, grain, n, cardinality(regions), days[1], days[n]) order by source, metric) from ripples.att_fx_panel));
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'explore', 'batch', p_batch,
                                     'n_pairs', n_g, 'n_explore_events', n_x, 'n_confirm_candidates', n_c, 'split_date', split, 'rule', cfg -> 'rule'), payload);
  update ripples.att_fx_grid set frozen_hash = h, frozen_at = now() where batch like p_batch || '/%';          -- ledger_seq stays NULL (see header)
  update ripples.att_fx63_batch set explore_seq = v_seq, explore_hash = h, confirm_hashes = hashes, updated_at = now() where batch = p_batch;
  return jsonb_build_object('batch', p_batch, 'n_pairs', n_g, 'n_explore_events', n_x, 'n_confirm_candidates', n_c, 'seq', v_seq, 'hash', h);
end $$;

-- 7. Decoy universes: season-matched pseudo-onsets (same calendar date ± band in another panel year, ≥ 120 d from the real onset,
--    inside the panel) for the exploration events (role dx) — the same geography, so a decoy pair goes through exactly the real pipeline.
create or replace function ripples.att_fx63_decoy_seed(p_batch text, p_sets int default null) returns int
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := ripples._att_cfg('engine63'); sets int := coalesce(p_sets, (cfg ->> 'decoy_sets')::int, 2); band int := coalesce((cfg -> 'explore' ->> 'season_band')::int, 21);
        g record; pan record; e record; s int; y0 int; yr int; yrs int[]; cand date; tries int; ok boolean; n_ins int := 0;
begin
  for g in select * from ripples.att_fx_grid where batch like p_batch || '/%' order by grid_id loop
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    for s in 1..sets loop
      perform setseed(((hashtext('fx63decoy:' || g.grid_id || ':' || s) % 100000) / 100000.0)::float8);
      for e in select * from ripples.att_fx_event f where f.grid_id = g.grid_id and f.role = 'explore' order by f.event_id loop
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
        values (g.grid_id, e.event_id, 'dx', s, cand, e.treated, e.magnitude) on conflict do nothing;
        n_ins := n_ins + 1;
      end loop;
    end loop;
  end loop;
  return n_ins;
end $$;

-- 8. Chunked, parallel-safe runner (advisory lock per grid; ≤ p_budget_s seconds; pools every complete (grid, role, set) group
--    with 6.2's att_fx_pool_run). Exploration roles use cfg.explore, confirmation roles cfg.confirm. State in att_state 'engine63.run'.
create or replace function ripples.att_fx63_step(p_budget_s int default 50, p_roles text[] default array['explore', 'dx', 'confirm', 'dc']) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t0 timestamptz := clock_timestamp(); cfg jsonb := ripples._att_cfg('engine63'); g record; pan record; e record; j jsonb; c jsonb;
        n_done int := 0; pooled int := 0; v_grid int; pr record; tried int[] := '{}';
begin
  loop
    select f.grid_id into v_grid from ripples.att_fx_event f join ripples.att_fx_grid gr on gr.grid_id = f.grid_id
     where gr.status = 'fx63' and f.computed_at is null and f.role = any(p_roles) and not (f.grid_id = any(tried)) order by f.grid_id limit 1;
    exit when v_grid is null;
    tried := tried || v_grid;
    continue when not pg_try_advisory_xact_lock(hashtext('fx63:' || v_grid));
    select * into g from ripples.att_fx_grid where grid_id = v_grid;
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    for e in select * from ripples.att_fx_event f where f.grid_id = v_grid and f.computed_at is null and f.role = any(p_roles) order by f.role, f.decoy_set, f.event_id loop
      c := case when e.role in ('explore', 'dx') then cfg -> 'explore' else cfg -> 'confirm' end;
      j := ripples.att_fx_calc(pan.ps, pan.pc, pan.days, pan.regions, pan.grain, e.treated, e.onset, g.pre_n, g.post_n, g.lag_n, false,
                               ((hashtext(v_grid || ':' || e.event_id || ':' || e.role || ':' || e.decoy_set) % 100000) / 100000.0)::float8, c);
      update ripples.att_fx_event f set
        n_treated = (j ->> 'n_treated')::int, n_donors = (j ->> 'n_donors')::int, d = (j ->> 'd')::real, d_treated = (j ->> 'd_treated')::real,
        med = (j ->> 'med')::real, se = (j ->> 'se')::real, z = (j ->> 'z')::real, p_time = (j ->> 'p_time')::real, p_space = (j ->> 'p_space')::real,
        p_pre = (j ->> 'p_pre')::real, lead = (select array_agg(x::real) from jsonb_array_elements_text(coalesce(j -> 'lead', '[]'::jsonb)) x),
        placebo_d = (select array_agg(x::real) from jsonb_array_elements_text(coalesce(j -> 'placebo_d', '[]'::jsonb)) x),
        note = j ->> 'note', computed_at = now()
      where f.grid_id = e.grid_id and f.event_id = e.event_id and f.role = e.role and f.decoy_set = e.decoy_set;
      n_done := n_done + 1;
      exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s);
    end loop;
    exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s);
  end loop;
  for pr in select f.grid_id, f.role, f.decoy_set from ripples.att_fx_event f join ripples.att_fx_grid gr on gr.grid_id = f.grid_id
            where gr.status = 'fx63' and f.role = any(p_roles)
            group by 1, 2, 3 having bool_and(f.computed_at is not null)
            and not exists (select 1 from ripples.att_fx_pool p where p.grid_id = f.grid_id and p.role = f.role and p.decoy_set = f.decoy_set) loop
    continue when not pg_try_advisory_xact_lock(hashtext('fx63pool:' || pr.grid_id || ':' || pr.role || ':' || pr.decoy_set));
    perform ripples.att_fx_pool_run(pr.grid_id, pr.role, pr.decoy_set);
    pooled := pooled + 1;
    exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s + 20);
  end loop;
  j := jsonb_build_object('at', now(), 'done', n_done, 'pooled', pooled, 'secs', round(extract(epoch from clock_timestamp() - t0)::numeric, 1),
                          'pending', (select count(*) from ripples.att_fx_event f join ripples.att_fx_grid gr on gr.grid_id = f.grid_id where gr.status = 'fx63' and f.computed_at is null));
  insert into ripples.att_state(k, v) values ('engine63.run', j) on conflict (k) do update set v = excluded.v, updated_at = now();
  return j;
end $$;

-- 9. The pre-declared selection rule (pure over the stored exploration pools; set 0 = real, s ≥ 1 = decoy universe s):
--    candidate = n ≥ x_n_min AND placebo p ≤ x_p_max AND |d| ≥ threshold (log panels 0.01, rate panels 0.05 raw);
--    one variant per (family, sub, outcome): the smaller p (tie → shorter window); findings ranked by p, cap K; checks (weight 0)
--    selected by the same candidate test outside the cap.
create or replace function ripples.att_fx63_select_run(p_batch text, p_set int default 0) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := ripples._att_cfg('engine63'); rule jsonb := cfg -> 'rule'; v_role text := case when p_set = 0 then 'explore' else 'dx' end;
        x_n_min int := (rule ->> 'x_n_min')::int; x_p_max float8 := (rule ->> 'x_p_max')::float8; thr_log float8 := (rule ->> 'x_abs_min_log')::float8;
        thr_raw float8 := (rule ->> 'x_abs_min_raw')::float8; k_cap int := (rule ->> 'k_cap')::int; n_sel int; n_chk int; n_cand int;
begin
  create temp table _fx63sel on commit drop as
  with pools as (
    select g.grid_id, g.family, coalesce(g.sub, '') as sub, g.source, g.metric, g.geo_kind, g.post_n, g.lag_n, g.bh_weight, g.domain_event, g.domain_outcome,
           pn.value_kind, p.n_events, p.d, p.se, p.p_placebo,
           case when pn.value_kind = 'rate' then thr_raw else thr_log end as thr
      from ripples.att_fx_grid g join ripples.att_fx_panel pn on pn.source = g.source and pn.metric = g.metric and pn.geo_kind = g.geo_kind
      left join ripples.att_fx_pool p on p.grid_id = g.grid_id and p.role = v_role and p.decoy_set = p_set
     where g.batch like p_batch || '/%'),
  ok as (select *, coalesce(n_events >= x_n_min and p_placebo <= x_p_max and abs(d) >= thr, false) as x_ok from pools),
  best as (select *, row_number() over (partition by family, sub, source, metric, geo_kind order by (not x_ok), p_placebo nulls last, post_n + lag_n, grid_id) = 1 as variant_best from ok),
  ranked as (select *, case when x_ok and variant_best and bh_weight > 0 then row_number() over (partition by (x_ok and variant_best and bh_weight > 0) order by p_placebo, abs(d) desc, grid_id) end as rnk from best)
  select * from ranked;
  insert into ripples.att_fx63_select(batch, grid_id, decoy_set, x_n, x_d, x_se, x_p, x_sign, x_ok, variant_best, rank, selected, reason, domain_distance, expected_by_mechanism, computed_at)
  select p_batch, r.grid_id, p_set, r.n_events, r.d, r.se, r.p_placebo, sign(r.d)::smallint, r.x_ok, r.variant_best, r.rnk,
         (r.x_ok and r.variant_best and (r.bh_weight = 0 or r.rnk <= k_cap)),
         case when r.n_events is null then 'no exploration pool' when r.n_events < x_n_min then 'too few exploration events (' || r.n_events || ')'
              when r.p_placebo > x_p_max then 'exploration p above ' || x_p_max when abs(r.d) < r.thr then 'effect below threshold'
              when not r.variant_best then 'other window variant preferred' when r.bh_weight > 0 and r.rnk > k_cap then 'beyond the cap of ' || k_cap
              when r.bh_weight = 0 then 'selected (check)' else 'selected' end,
         ripples.att_fx63_domain_distance(r.domain_event, r.domain_outcome), ripples.att_fx63_expected_by_mechanism(r.family, r.source), now()
    from _fx63sel r
  on conflict (batch, grid_id, decoy_set) do update set x_n = excluded.x_n, x_d = excluded.x_d, x_se = excluded.x_se, x_p = excluded.x_p, x_sign = excluded.x_sign,
    x_ok = excluded.x_ok, variant_best = excluded.variant_best, rank = excluded.rank, selected = excluded.selected, reason = excluded.reason,
    domain_distance = excluded.domain_distance, expected_by_mechanism = excluded.expected_by_mechanism, computed_at = now();
  select count(*) filter (where selected and bh_weight > 0), count(*) filter (where selected and bh_weight = 0), count(*) filter (where x_ok)
    into n_sel, n_chk, n_cand from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id where s.batch = p_batch and s.decoy_set = p_set;
  drop table _fx63sel;
  return jsonb_build_object('batch', p_batch, 'set', p_set, 'n_pairs', (select count(*) from ripples.att_fx63_select where batch = p_batch and decoy_set = p_set),
                            'n_candidates', n_cand, 'n_selected', n_sel, 'n_checks_selected', n_chk);
end $$;

-- 10. Confirmation freeze (set 0): the selected pairs + their held-out event lists (asserted identical to the exploration-freeze
--     hash) go to the ledger; role 'confirm' rows are inserted (uncomputed). Decoy universes: role 'dc' pseudo-onsets of the
--     held-out candidates for the pairs the rule selected in that decoy universe.
create or replace function ripples.att_fx63_confirm_freeze(p_batch text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b record; sr record; cr record; n_ev int := 0; n_sel int := 0; bad text[] := '{}'; payload jsonb; h text; v_seq bigint;
begin
  select * into b from ripples.att_fx63_batch where batch = p_batch;
  if not found or b.explore_seq is null then return jsonb_build_object('error', 'exploration not frozen'); end if;
  if b.confirm_seq is not null then return jsonb_build_object('batch', p_batch, 'already_frozen', true, 'seq', b.confirm_seq); end if;
  for sr in select * from ripples.att_fx63_select where batch = p_batch and decoy_set = 0 and selected order by grid_id loop
    if ripples.att_fx63_confirm_hash(sr.grid_id) is distinct from (b.confirm_hashes ->> sr.grid_id::text) then bad := bad || sr.grid_id::text; continue; end if;
    n_sel := n_sel + 1;
    for cr in select * from ripples.att_fx63_confirm_events(sr.grid_id) loop
      insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude)
      values (sr.grid_id, cr.event_id, 'confirm', 0, cr.onset, cr.treated, cr.magnitude) on conflict do nothing;
      n_ev := n_ev + 1;
    end loop;
  end loop;
  if cardinality(bad) > 0 then return jsonb_build_object('error', 'held-out event list changed since the exploration freeze', 'grids', bad); end if;
  payload := jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'confirm', 'batch', p_batch, 'explore_seq', b.explore_seq, 'rule', b.cfg -> 'rule',
    'selected', (select jsonb_agg(jsonb_build_array(s.grid_id, g.label, s.x_n, s.x_d, s.x_p, s.x_sign, s.rank, g.bh_weight) order by s.grid_id)
                   from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id where s.batch = p_batch and s.decoy_set = 0 and s.selected),
    'events', (select jsonb_agg(jsonb_build_array(f.grid_id, f.event_id, f.onset, f.treated, f.magnitude) order by f.grid_id, f.event_id)
                 from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like p_batch || '/%' and f.role = 'confirm'));
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'confirm', 'batch', p_batch,
                                     'n_selected', n_sel, 'n_confirm_events', n_ev, 'explore_seq', b.explore_seq), payload);
  update ripples.att_fx63_batch set confirm_seq = v_seq, confirm_hash = h, status = 'confirming', updated_at = now() where batch = p_batch;
  return jsonb_build_object('batch', p_batch, 'n_selected', n_sel, 'n_confirm_events', n_ev, 'seq', v_seq, 'hash', h);
end $$;

create or replace function ripples.att_fx63_decoy_confirm_seed(p_batch text) returns int
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := ripples._att_cfg('engine63'); band int := coalesce((cfg -> 'confirm' ->> 'season_band')::int, 21); s record; pan record; c record;
        y0 int; yr int; yrs int[]; cand date; tries int; ok boolean; n_ins int := 0;
begin
  for s in select sl.*, g.source, g.metric, g.geo_kind from ripples.att_fx63_select sl join ripples.att_fx_grid g on g.grid_id = sl.grid_id
           where sl.batch = p_batch and sl.decoy_set > 0 and sl.selected order by sl.decoy_set, sl.grid_id loop
    select * into pan from ripples.att_fx_panel p where p.source = s.source and p.metric = s.metric and p.geo_kind = s.geo_kind;
    perform setseed(((hashtext('fx63dc:' || s.grid_id || ':' || s.decoy_set) % 100000) / 100000.0)::float8);
    for c in select * from ripples.att_fx63_confirm_events(s.grid_id) loop
      y0 := extract(year from c.onset)::int; yrs := '{}';
      for yr in (extract(year from pan.days[1])::int + 1)..(extract(year from pan.days[pan.n])::int) loop if yr <> y0 then yrs := yrs || yr; end if; end loop;
      ok := false; tries := 0;
      while not ok and tries < 20 loop
        tries := tries + 1;
        yr := yrs[1 + floor(random() * cardinality(yrs))::int];
        cand := (c.onset + make_interval(years => yr - y0))::date + (floor(random() * (2 * band + 1))::int - band);
        ok := cand between pan.days[1] + 200 and pan.days[pan.n] - 60 and abs(cand - c.onset) > 120;
      end loop;
      continue when not ok;
      insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude)
      values (s.grid_id, c.event_id, 'dc', s.decoy_set, cand, c.treated, c.magnitude) on conflict do nothing;
      n_ins := n_ins + 1;
    end loop;
  end loop;
  return n_ins;
end $$;

-- 11. Verdicts: confirmation pools → sign vs the exploration sign, BH over the confirmation set only (equal weights; checks
--     outside), the plain-English strength word. Hunch statuses for exploration hits that were not confirmed.
create or replace function ripples.att_fx63_verdict(p_batch text, p_set int default 0) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := ripples._att_cfg('engine63'); rule jsonb := cfg -> 'rule'; v_role text := case when p_set = 0 then 'confirm' else 'dc' end;
        c_n_min int := (rule ->> 'c_n_min')::int; q_strong float8 := (rule ->> 'q_strong')::float8; q_pat float8 := (rule ->> 'q_pattern')::float8;
        ids int[]; ps float8[]; qs float8[]; i int; n_conf int; n_weak int; n_sel int;
begin
  update ripples.att_fx63_select s set
    c_n = p.n_events, c_d = p.d, c_se = p.se, c_ci_lo = p.ci_lo, c_ci_hi = p.ci_hi, c_tau2 = p.tau2, c_i2 = p.i2, c_p = p.p_placebo, c_p_norm = p.p_norm,
    c_sign_ok = (sign(p.d) = s.x_sign), c_n_clustered_out = (p.payload ->> 'n_clustered_out')::int, c_n_regional_pass = (p.payload ->> 'n_regional_pass')::int,
    c_q = null, computed_at = now()
    from ripples.att_fx_pool p
   where p.grid_id = s.grid_id and p.role = v_role and p.decoy_set = p_set and s.batch = p_batch and s.decoy_set = p_set and s.selected;
  -- BH over the confirmation set only: selected findings (weight > 0) with enough held-out events
  select array_agg(s.grid_id order by s.grid_id), array_agg(coalesce(s.c_p, 1)::float8 order by s.grid_id) into ids, ps
    from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id
   where s.batch = p_batch and s.decoy_set = p_set and s.selected and g.bh_weight > 0 and s.c_n >= c_n_min;
  if ids is not null then
    qs := ripples.att_bh_q(ps, array_fill(1::float8, array[cardinality(ps)]));
    for i in 1..cardinality(ids) loop update ripples.att_fx63_select set c_q = qs[i] where batch = p_batch and decoy_set = p_set and grid_id = ids[i]; end loop;
  end if;
  update ripples.att_fx63_select s set
    verdict = case when not s.selected then case when s.x_ok then 'not tested (' || s.reason || ')' else 'not a candidate' end
                   when s.c_n is null then 'confirmation pending'
                   when s.c_n < c_n_min then 'too few held-out events (' || s.c_n || ')'
                   when g.bh_weight = 0 then case when s.c_p <= 0.05 and s.c_sign_ok then 'check passed' else 'check failed' end
                   when coalesce(s.c_q, 1) <= q_strong and s.c_sign_ok then 'confirmed'
                   when coalesce(s.c_q, 1) <= q_pat and s.c_sign_ok then 'confirmed (weaker)'
                   when s.c_p <= 0.05 and not s.c_sign_ok then 'reversed'
                   else 'not replicated' end,
    strength = case when not s.selected then case when s.x_ok then 'hunch' else null end
                    when s.c_n is null then 'hunch'
                    when s.c_n < c_n_min then 'hunch'
                    when g.bh_weight = 0 then case when s.c_p <= 0.05 and s.c_sign_ok then 'check passed' else 'check failed' end
                    when coalesce(s.c_q, 1) <= q_strong and s.c_sign_ok then 'confirmed pattern'
                    when coalesce(s.c_q, 1) <= q_pat and s.c_sign_ok then 'confirmed pattern (weaker)'
                    else 'hunch' end
    from ripples.att_fx_grid g where g.grid_id = s.grid_id and s.batch = p_batch and s.decoy_set = p_set;
  select count(*) filter (where verdict = 'confirmed'), count(*) filter (where verdict = 'confirmed (weaker)'), count(*) filter (where selected)
    into n_conf, n_weak, n_sel from ripples.att_fx63_select where batch = p_batch and decoy_set = p_set;
  if p_set = 0 then update ripples.att_fx63_batch set status = 'confirmed', updated_at = now() where batch = p_batch; end if;
  return jsonb_build_object('batch', p_batch, 'set', p_set, 'n_selected', n_sel, 'n_in_bh', coalesce(cardinality(ids), 0), 'n_confirmed', n_conf, 'n_confirmed_weaker', n_weak);
end $$;

-- 12. Calibration: decoy universes through the full pipeline → false-confirmation rate (Wilson), exploration decoy hit rate,
--     in-space placebo uniformity per panel (decoy events), known positives, the tier-guard assertions. Ledger 'calibration' row.
create or replace function ripples.att_fx63_calibration(p_batch text, p_ledger boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare j jsonb; n_dsel int; n_dconf int; n_dconf_w int; n_draw05 int; wi float8[]; wi_w float8[]; x_rate jsonb; unif jsonb; kp jsonb; guard jsonb; v_seq bigint; hk text;
begin
  select count(*) filter (where s.selected and g.bh_weight > 0 and s.c_n >= 8),
         count(*) filter (where s.verdict = 'confirmed'), count(*) filter (where s.verdict in ('confirmed', 'confirmed (weaker)')),
         count(*) filter (where s.selected and g.bh_weight > 0 and s.c_n >= 8 and s.c_p <= 0.05 and s.c_sign_ok)
    into n_dsel, n_dconf, n_dconf_w, n_draw05
    from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id where s.batch = p_batch and s.decoy_set > 0;
  wi := ripples.att_fx_wilson(n_dconf, greatest(n_dsel, 0)); wi_w := ripples.att_fx_wilson(n_dconf_w, greatest(n_dsel, 0));
  select jsonb_build_object('n_pools', count(*), 'share_x_ok', round(avg(s.x_ok::int)::numeric, 3), 'share_p_le10', round(avg((s.x_p <= 0.10)::int)::numeric, 3),
                            'n_selected_per_set', (select jsonb_object_agg(decoy_set, n) from (select decoy_set, count(*) filter (where selected) n from ripples.att_fx63_select where batch = p_batch and decoy_set > 0 group by 1) z))
    into x_rate from ripples.att_fx63_select s where s.batch = p_batch and s.decoy_set > 0 and s.x_n >= 6;
  select jsonb_agg(jsonb_build_object('panel', x.panel, 'n', x.n, 'share_le05', x.s05, 'share_le10', x.s10, 'share_pre_le10', x.pre10, 'deciles', x.dec) order by x.panel) into unif
    from (select g.source || ':' || g.metric as panel, count(*) n, round(avg((f.p_space <= 0.05)::int)::numeric, 3) s05, round(avg((f.p_space <= 0.10)::int)::numeric, 3) s10,
                 round(avg((f.p_pre <= 0.10)::int)::numeric, 3) pre10,
                 (select jsonb_agg(c order by b) from (select width_bucket(f2.p_space, 0, 1.0001, 10) b, count(*) c from ripples.att_fx_event f2 join ripples.att_fx_grid g2 on g2.grid_id = f2.grid_id
                                                     where g2.batch like p_batch || '/%' and g2.source = g.source and g2.metric = g.metric and f2.role = 'dx' and f2.p_space is not null group by 1) y) dec
            from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id
           where g.batch like p_batch || '/%' and f.role = 'dx' and f.p_space is not null group by 1) x;
  select jsonb_agg(jsonb_build_object('pair', g.label, 'is_check', g.bh_weight = 0, 'x_n', s.x_n, 'x_d', round(s.x_d::numeric, 4), 'x_p', s.x_p, 'selected', s.selected,
                                      'c_n', s.c_n, 'c_d', round(s.c_d::numeric, 4), 'c_p', s.c_p, 'c_q', s.c_q, 'verdict', s.verdict) order by g.grid_id) into kp
    from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id
   where s.batch = p_batch and s.decoy_set = 0 and (g.bh_weight = 0 or (g.family in ('hazard.cold', 'hazard.heat') and g.source = 'eia.930'));
  -- tier guard: the 6.2 hook's liftable list is unchanged and no 6.3 function touches att_finalize / att_hop_tests / att_fx_hook
  select pg_get_functiondef(p.oid) into hk from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'ripples' and p.proname = 'att_fx_hook';
  guard := jsonb_build_object(
    'hook_liftable_unchanged', position($l$liftable text[] := array['q above 0.05', 'a placebo family disagrees', 'one channel only', 'placebo families', 'final look not reached']$l$ in hk) > 0,
    'no_63_function_touches_tiers', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'ripples' and p.proname like 'att\_fx63\_%'
                                                 and (pg_get_functiondef(p.oid) ~ 'att_finalize\(' or pg_get_functiondef(p.oid) ~ 'att_hop_tests' or pg_get_functiondef(p.oid) ~ 'att_fx_hook\(')),
    'no_63_grid_has_ledger_seq', not exists (select 1 from ripples.att_fx_grid where status = 'fx63' and ledger_seq is not null));
  j := jsonb_build_object('batch', p_batch, 'at', now(), 'method', '6.3',
        'decoy_pipeline', jsonb_build_object('n_decoy_selected', n_dsel, 'n_false_confirmed_q05', n_dconf, 'rate', case when n_dsel > 0 then round(n_dconf::numeric / n_dsel, 3) end, 'wilson', wi,
                                             'n_false_confirmed_q20', n_dconf_w, 'rate_q20', case when n_dsel > 0 then round(n_dconf_w::numeric / n_dsel, 3) end, 'wilson_q20', wi_w,
                                             'n_raw_p05_sign', n_draw05),
        'decoy_exploration', x_rate, 'in_space_placebos_by_panel', unif, 'known_positives', kp, 'tier_guard', guard);
  insert into ripples.att_state(k, v) values ('engine63.calibration', j) on conflict (k) do update set v = excluded.v, updated_at = now();
  if p_ledger then
    v_seq := ripples.att_ledger_append(current_date, 'calibration', jsonb_build_object('object', 'fx_grid', 'batch', p_batch, 'method', '6.3'), j);
    update ripples.att_fx63_batch set calib_seq = v_seq, updated_at = now() where batch = p_batch;
    j := j || jsonb_build_object('seq', v_seq);
  end if;
  return j;
end $$;

-- 13. model_version row for 6.3 (config incl. the selection rule, grid + panel specs; deduped by hash)
create or replace function ripples.att_fx63_model_version_register() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare payload jsonb; h text; existing bigint; v_seq bigint;
begin
  payload := jsonb_build_object('method', '6.3', 'object', 'engine63', 'engine63_config', ripples._att_cfg('engine63'), 'grid_spec', ripples.att_fx63_grid_spec(),
                                'panel_spec', ripples.att_fx63_panel_spec(), 'base', ripples._att_cfg('engine62') ->> 'method',
                                'tier_rule', 'none: 6.3 publishes confirmed patterns (held-out replication, BH over the confirmation set) and hunches; att_finalize / att_fx_hook / att_ce_gate untouched; a confirmed pattern never changes an event tier',
                                'selection_rule', 'exploration (onset < split_date): n >= x_n_min, placebo p <= x_p_max, |d| >= threshold, one variant per pair (smaller p, tie shorter window), cap k_cap by p; confirmation (onset >= split_date): full 6.2 config, sign = exploration sign, BH over the confirmation set only');
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  select seq into existing from ripples.att_ledger where kind = 'model_version' and payload_hash = h limit 1;
  if existing is not null then return jsonb_build_object('seq', existing, 'hash', h, 'new', false); end if;
  v_seq := ripples.att_ledger_append(current_date, 'model_version', jsonb_build_object('method', '6.3', 'object', 'engine63'), payload);
  return jsonb_build_object('seq', v_seq, 'hash', h, 'new', true);
end $$;

do $$ declare t text; begin
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_fx63\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;

-- =====================================================================================================================
-- P2b (migration att_engine_63_p2b_frozen_extents_model_version): att_fx63_batch.panel_extents (every panel's from / to /
-- regions at exploration-freeze time) and att_fx63_confirm_events() reading the FROZEN extents, so a nightly panel refresh can
-- never change the held-out candidate list between the two freezes. (The deployed bodies are the P2 ones with that change;
-- see the migration.) Then: select ripples.att_fx63_model_version_register();   -- the 6.3 model_version row (rule pre-declared)
-- =====================================================================================================================

-- =====================================================================================================================
-- P3 (migration att_engine_63_p3_public_view_cron): the internal view, the public read-only RPCs and the nightly panel cron.
-- Public outputs follow the story layer's presentation rule: sensitive events are QUIET (quiet:true), never excluded; the only
-- exclusion is ripples.att_story_off_limits(event_id).
-- =====================================================================================================================
drop view if exists ripples.att_fx63_patterns;
create view ripples.att_fx63_patterns as
  select s.batch, s.grid_id, s.decoy_set, g.family, f.label as family_label, g.sub, g.source, g.metric, g.geo_kind,
         ripples.att_fx63_outcome_label(g.source, g.metric) as outcome_label, g.domain_event, g.domain_outcome, g.definitional, (g.bh_weight = 0) as is_check,
         g.pre_n, g.post_n, g.lag_n, split_part(g.batch, '/', 2) as variant, pn.grain, case when pn.value_kind = 'rate' then 'raw' else 'pct' end as unit,
         b.split_date, b.explore_seq, b.confirm_seq, b.calib_seq,
         s.x_n, s.x_d, s.x_se, s.x_p, s.x_sign, s.x_ok, s.variant_best, s.rank, s.selected, s.reason,
         s.c_n, s.c_d, s.c_se, s.c_ci_lo, s.c_ci_hi, s.c_tau2, s.c_i2, s.c_p, s.c_p_norm, s.c_q, s.c_sign_ok, s.c_n_clustered_out, s.c_n_regional_pass,
         case when pn.value_kind = 'rate' then round(s.c_d::numeric, 2) else round((100 * (exp(s.c_d) - 1))::numeric, 1) end as c_pct,
         case when pn.value_kind = 'rate' then round(s.c_ci_lo::numeric, 2) else round((100 * (exp(s.c_ci_lo) - 1))::numeric, 1) end as c_pct_lo,
         case when pn.value_kind = 'rate' then round(s.c_ci_hi::numeric, 2) else round((100 * (exp(s.c_ci_hi) - 1))::numeric, 1) end as c_pct_hi,
         case when pn.value_kind = 'rate' then round(s.x_d::numeric, 2) else round((100 * (exp(s.x_d) - 1))::numeric, 1) end as x_pct,
         s.verdict, s.strength, s.domain_distance, s.expected_by_mechanism, s.computed_at
    from ripples.att_fx63_select s
    join ripples.att_fx_grid g on g.grid_id = s.grid_id
    join ripples.att_fx63_batch b on b.batch = s.batch
    join ripples.att_families f on f.family = g.family
    left join ripples.att_fx_panel pn on pn.source = g.source and pn.metric = g.metric and pn.geo_kind = g.geo_kind;
revoke all on ripples.att_fx63_patterns from anon, authenticated, public;

-- sample events of a 6.3 pair for one role (confirm / explore): the 3 largest |z| after the overlap rule, quiet when sensitive,
-- excluded only when off limits
create or replace function ripples.att_fx63_sample_events(p_grid int, p_role text, p_limit int default 3) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('label', coalesce(ripples.rm_label_resolve(e.qid, e.label), e.label), 'onset', f.onset,
                                               'effect', case when pn.value_kind = 'rate' then round((f.d - f.med)::numeric, 2) else round((100 * (exp(f.d - f.med) - 1))::numeric, 1) end,
                                               'z', round(f.z::numeric, 2), 'p_space', f.p_space, 'stone', ripples.att_fx_shock_norm(e.event_id), 'quiet', coalesce(e.sensitive, false))
                            order by abs(f.z) desc), '[]'::jsonb)
    from (select f0.* from ripples.att_fx_event f0 where f0.grid_id = p_grid and f0.role = p_role and f0.decoy_set = 0 and f0.z is not null
            and not exists (select 1 from ripples.att_fx_cluster_dups(p_grid, p_role, 0) d where d.event_id = f0.event_id) order by abs(f0.z) desc limit p_limit) f
    join ripples.att_events e on e.event_id = f.event_id
    join ripples.att_fx_grid g on g.grid_id = p_grid
    left join ripples.att_fx_panel pn on pn.source = g.source and pn.metric = g.metric and pn.geo_kind = g.geo_kind
   where not ripples.att_story_off_limits(e.event_id)
$$;

-- CONFIRMED patterns only (p_min 'confirmed' = q ≤ 0.05; 'weaker' adds q ≤ 0.20; 'all' adds the checks). Never a tier.
create or replace function public.rm_patterns63(p_family text default null, p_min text default 'confirmed') returns jsonb
language sql stable security definer set search_path = '' as $$
  with ranked as (
    select v.*, case v.strength when 'confirmed pattern' then 4 when 'confirmed pattern (weaker)' then 3 when 'check passed' then 1 else 0 end as rank_
      from ripples.att_fx63_patterns v
     where v.decoy_set = 0 and v.selected and v.confirm_seq is not null and v.c_n is not null
       and not ripples.rm_node_hidden(v.source || ':' || v.metric)
       and (p_family is null or v.family = p_family))
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.grid_id, 'batch', r.batch, 'method', '6.3', 'family', r.family, 'family_label', r.family_label, 'sub', r.sub,
    'event_label', case when r.sub = 'hurricane' then 'Hurricanes' else r.family_label || 's' end,
    'outcome', r.source || ':' || r.metric, 'outcome_label', r.outcome_label, 'geo_kind', r.geo_kind,
    'design', 'split sample: found on events before ' || r.split_date || ', confirmed on held-out events since; affected vs unaffected regions (difference-in-differences, in-space + in-time placebos), BH over the confirmation set',
    'window', jsonb_build_object('pre', r.pre_n, 'post', r.post_n, 'lag', r.lag_n, 'grain', r.grain, 'variant', r.variant),
    'unit', r.unit, 'effect', r.c_pct, 'ci', jsonb_build_array(r.c_pct_lo, r.c_pct_hi), 'effect_logpts', round(r.c_d::numeric, 4),
    'n_events', r.c_n, 'n_clustered_out', r.c_n_clustered_out, 'i2', round(coalesce(r.c_i2, 0)::numeric, 2), 'p_placebo', r.c_p, 'p_norm', r.c_p_norm, 'q', r.c_q,
    'sign', r.x_sign, 'sign_ok', r.c_sign_ok, 'n_regional_pass', r.c_n_regional_pass,
    'exploration', jsonb_build_object('n_events', r.x_n, 'effect', r.x_pct, 'p_placebo', r.x_p, 'period', 'before ' || r.split_date),
    'confirmation', jsonb_build_object('n_events', r.c_n, 'effect', r.c_pct, 'ci', jsonb_build_array(r.c_pct_lo, r.c_pct_hi), 'p_placebo', r.c_p, 'q', r.c_q, 'period', 'since ' || r.split_date),
    'strength', r.strength, 'verdict', r.verdict, 'is_check', r.is_check, 'definitional', r.definitional,
    'domain_distance', r.domain_distance, 'expected_by_mechanism', r.expected_by_mechanism, 'non_obvious', (r.domain_distance >= 1),
    'pond', ripples.att_fx_pond(r.c_d, r.domain_event, r.domain_outcome, r.unit)
            || jsonb_build_object('stone', (select percentile_cont(0.5) within group (order by ripples.att_fx_shock_norm(f.event_id)) from ripples.att_fx_event f where f.grid_id = r.grid_id and f.role = 'confirm' and f.magnitude is not null)),
    'fluke_note', case r.strength when 'confirmed pattern' then 'found in one half of the archive and seen again in the other; about 1 in 20 findings at this level could be a fluke'
                                  when 'confirmed pattern (weaker)' then 'found in one half of the archive and seen again in the other; about 1 in 5 findings at this level could be a fluke'
                                  when 'check passed' then 'a pre-registered sanity check, not a finding' else null end,
    'headline', case when r.sub = 'hurricane' then 'Hurricanes' else r.family_label || 's' end || ' → ' || r.outcome_label || ': ' || case when r.c_pct >= 0 then '+' else '' end || r.c_pct
                || case when r.unit = 'pct' then '%' else ' (raw units)' end || ' over ' || r.post_n || ' ' || case r.grain when 'week' then 'weeks' when 'month' then 'months' else 'days' end
                || case when r.lag_n > 0 then ', starting ' || r.lag_n || ' ' || case r.grain when 'week' then 'weeks' when 'month' then 'months' else 'days' end || ' after the event' else '' end
                || ', seen again in ' || r.c_n || ' held-out events',
    'wording', 'found in ' || r.x_n || ' events before ' || r.split_date || ', seen again in ' || r.c_n || ' events since',
    'sample_events', ripples.att_fx63_sample_events(r.grid_id, 'confirm', 3),
    'ledger', jsonb_build_object('explore_seq', r.explore_seq, 'confirm_seq', r.confirm_seq, 'calibration_seq', r.calib_seq), 'computed_at', r.computed_at
  ) order by r.rank_ desc, coalesce(r.c_q, 1), r.c_p), '[]'::jsonb)
  from ranked r
  where r.rank_ >= case p_min when 'confirmed' then 4 when 'weaker' then 3 when 'all' then 1 else 4 end
$$;
revoke all on function public.rm_patterns63(text, text) from public;
grant execute on function public.rm_patterns63(text, text) to anon, authenticated, service_role;

-- HUNCHES: exploration hits that were not confirmed (or could not be tested). Labelled 'hunch'; never Likely / Measured / pattern.
create or replace function public.rm_hunches(p_family text default null, p_limit int default 50) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.grid_id, 'batch', r.batch, 'method', '6.3', 'label', 'hunch', 'family', r.family, 'family_label', r.family_label, 'sub', r.sub,
    'event_label', case when r.sub = 'hurricane' then 'Hurricanes' else r.family_label || 's' end,
    'outcome', r.source || ':' || r.metric, 'outcome_label', r.outcome_label, 'geo_kind', r.geo_kind,
    'window', jsonb_build_object('pre', r.pre_n, 'post', r.post_n, 'lag', r.lag_n, 'grain', r.grain, 'variant', r.variant), 'unit', r.unit,
    'exploration', jsonb_build_object('n_events', r.x_n, 'effect', r.x_pct, 'p_placebo', r.x_p, 'period', 'before ' || r.split_date),
    'held_out', case when r.c_n is not null then jsonb_build_object('n_events', r.c_n, 'effect', r.c_pct, 'ci', jsonb_build_array(r.c_pct_lo, r.c_pct_hi), 'p_placebo', r.c_p, 'q', r.c_q, 'sign_ok', r.c_sign_ok, 'period', 'since ' || r.split_date) end,
    'status', r.verdict, 'strength', 'hunch',
    'status_label', case when r.verdict = 'not replicated' then 'did not show up again in the held-out events'
                         when r.verdict = 'reversed' then 'moved the other way in the held-out events'
                         when r.verdict like 'too few held-out%' then 'not enough held-out events yet to test it'
                         when r.verdict like 'not tested%' then 'a lead that was not tested (' || r.reason || ')'
                         when r.verdict = 'confirmation pending' then 'held-out test pending' else r.verdict end,
    'domain_distance', r.domain_distance, 'expected_by_mechanism', r.expected_by_mechanism, 'non_obvious', (r.domain_distance >= 1),
    'note', 'an exploratory lead from one half of the archive that did not survive (or has not yet had) an out-of-sample test; not evidence about any event',
    'sample_events', ripples.att_fx63_sample_events(r.grid_id, 'explore', 2),
    'ledger', jsonb_build_object('explore_seq', r.explore_seq, 'confirm_seq', r.confirm_seq), 'computed_at', r.computed_at
  ) order by (r.verdict = 'not replicated') desc, r.x_p), '[]'::jsonb)
  from (select v.* from ripples.att_fx63_patterns v
         where v.decoy_set = 0 and v.x_ok and v.strength = 'hunch' and not v.is_check
           and not ripples.rm_node_hidden(v.source || ':' || v.metric)
           and (p_family is null or v.family = p_family)
         order by (v.verdict = 'not replicated') desc, v.x_p limit greatest(1, least(p_limit, 200))) r
$$;
revoke all on function public.rm_hunches(text, int) from public;
grant execute on function public.rm_hunches(text, int) to anon, authenticated, service_role;

do $$ declare t text; begin
  for t in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'ripples' and p.proname like 'att\_fx63\_%' loop
    execute format('revoke all on function %s from anon, authenticated, public', t);
  end loop;
end $$;

-- Cron (UTC): the 6.3 panels are rebuilt nightly AFTER the 6.2 refresh (07:40); the chunked runner is scheduled only while a batch
-- computes (see the run log in ENGINE_63.md) and unscheduled afterwards.
do $$ declare j record; begin
  for j in select jobid from cron.job where jobname in ('att-fx63-panel') loop perform cron.unschedule(j.jobid); end loop;
  perform cron.schedule('att-fx63-panel', '52 7 * * *', $c$set statement_timeout = '100s'; select ripples.att_fx63_panel_refresh()$c$);
end $$;
-- select cron.schedule('att-fx63-step', '* * * * *', $$set statement_timeout = '100s'; select ripples.att_fx63_step(50)$$);

-- =====================================================================================================================
-- P4 (migration att_engine_63_p4_minwage_family): NEW EVENT FAMILY policy.min_wage from the DOL state minimum-wage history as
-- republished by FRED (STTMINWG<ST>, annual, "rate as of January 1", source U.S. Department of Labor; fetched first-release by
-- att-econ mode fred_state through the documented keyed API — the DOL HTML page itself is not scraped).
-- One event per January 1 (2016 →): treated = the states whose rate is higher than the prior January 1 by ≥ $0.05, EXCLUDING the
-- states whose statutory effective dates are not January 1 in at least one year of 2015–2026 (DC, OR, NV: July 1; FL: Sept 30 from
-- 2021; CT, DE, IL, VA, RI, MN, HI, AK, MD, MI: mid-year steps in some years) — for them a January-1 onset would be wrong. NY's
-- December-31 steps count as January 1 (one day). Donors = every other state with a series, incl. the five federal-floor states
-- without a state series (AL, LA, MS, SC, TN: no state minimum-wage law) which never move.
-- N = 11 events → no held-out confirmation is possible (c_n_min = 8 per half); the family is registered for the archive and run as a
-- clearly-labelled SINGLE-SAMPLE pre-registered test in its own batch (att_fx63_freeze_single), never a confirmed pattern.
-- Expected direction (literature): employment effects near zero / small negative in the affected sectors, unemployment rate ≈ 0,
-- claims ≈ 0 — recorded honestly as "no strong expectation" (sign 0).
-- =====================================================================================================================
insert into ripples.att_families(family, label, scheduled, mapper) values ('policy.min_wage', 'State minimum-wage increase', false, '[]'::jsonb) on conflict (family) do nothing;

create or replace function ripples.att_fx63_minwage_register() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare excl text[] := array['DC', 'OR', 'NV', 'FL', 'CT', 'DE', 'IL', 'VA', 'RI', 'MN', 'HI', 'AK', 'MD', 'MI'];
        y int; r record; states text[]; incs float8[]; n_ev int := 0; v_topic bigint; lbl text; key text; mag real; out jsonb := '[]'::jsonb;
begin
  for y in 2016..extract(year from current_date)::int loop
    select array_agg(x.st order by x.st), array_agg(x.inc order by x.st) into states, incs
      from (select substr(s.geo, 4, 2) as st, (cur.value - prev.value) / nullif(prev.value, 0) as inc
              from ripples.att_series s
              join ripples.attention_obs cur on cur.series_id = s.series_id and cur.day = make_date(y, 1, 1)
              join ripples.attention_obs prev on prev.series_id = s.series_id and prev.day = make_date(y - 1, 1, 1)
             where s.source = 'fred.state' and s.metric = 'minwage' and s.geo ~ '^US-[A-Z]{2}$'
               and cur.value >= prev.value + 0.05 and substr(s.geo, 4, 2) <> all(excl)) x;
    continue when states is null or cardinality(states) < 2;
    lbl := 'State minimum-wage increases, ' || y || '-01-01 (' || cardinality(states) || ' states)';
    key := 'lib:minwage-' || y;
    select percentile_cont(0.5) within group (order by v) into mag from unnest(incs) v;
    insert into ripples.att_topics(qid, label_key, label, title_en, lang, category, status, in_panel, origin, meta)
    values (null, key, lbl, lbl, 'en', 'policy', 'dormant', false, 'manual',
            jsonb_build_object('state', to_jsonb(states), 'family', 'policy.min_wage', 'library', true, 'defined_by', jsonb_build_array('fred.state'),
                               'lib_source', 'FRED STTMINWG<ST> (U.S. Department of Labor, state minimum wage as of January 1)', 'lib_ref', 'minwage-' || y,
                               'excluded_non_jan1_states', to_jsonb(excl), 'median_increase', mag))
    on conflict (label_key) do update set meta = excluded.meta, label = excluded.label returning topic_id into v_topic;
    insert into ripples.att_events(as_of, topic_id, qid, label, family, role, onset, magnitude, sensitive, slug, reconstructed, status)
    values (make_date(y, 1, 2), v_topic, null, lbl, 'policy.min_wage', 'library', make_date(y, 1, 1), mag, false, 'lib-minwage-' || y, true, 'ended')
    on conflict (slug) do update set magnitude = excluded.magnitude, label = excluded.label;
    n_ev := n_ev + 1;
    out := out || jsonb_build_object('year', y, 'n_states', cardinality(states), 'median_increase', round(mag::numeric, 3));
  end loop;
  return jsonb_build_object('n_events', n_ev, 'events', out, 'excluded_states', to_jsonb(excl));
end $$;

-- single-sample pre-registered batch for a family whose archive is too small for a split (all events in role 'explore'; the
-- exploration pool IS the result; labelled 'single-sample' by the reporting; its own BH family; never confirmed)
create or replace function ripples.att_fx63_freeze_single(p_batch text, p_family text, p_pairs jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg jsonb := ripples._att_cfg('engine63'); s jsonb; g record; e record; tr text[]; n_x int := 0; n_g int := 0; payload jsonb; h text; v_seq bigint; pan record; ext jsonb;
begin
  if exists (select 1 from ripples.att_fx63_batch where batch = p_batch and explore_seq is not null) then return jsonb_build_object('batch', p_batch, 'already_frozen', true); end if;
  select jsonb_object_agg(source || ':' || metric || ':' || geo_kind, jsonb_build_object('from', days[1], 'to', days[n], 'regions', to_jsonb(regions), 'n', n, 'grain', grain)) into ext from ripples.att_fx_panel;
  insert into ripples.att_fx63_batch(batch, split_date, cfg, status, panel_extents, note) values (p_batch, '2100-01-01', cfg, 'single-sample', ext, 'single-sample pre-registered test: no held-out half (N too small)')
  on conflict (batch) do nothing;
  for s in select * from jsonb_array_elements(p_pairs) loop
    continue when not exists (select 1 from ripples.att_fx_panel p where p.source = s ->> 'source' and p.metric = s ->> 'metric' and p.geo_kind = s ->> 'geo_kind');
    insert into ripples.att_fx_grid(batch, family, sub, source, metric, geo_kind, pre_n, post_n, lag_n, expected_sign, synth, definitional, domain_event, domain_outcome, target_map, bh_weight, label, status)
    values (p_batch || '/single', p_family, null, s ->> 'source', s ->> 'metric', s ->> 'geo_kind', (s ->> 'pre')::int, (s ->> 'post')::int, (s ->> 'lag')::int, coalesce((s ->> 'sign')::int, 0), false, false,
            s ->> 'de', s ->> 'do', null, 1, p_family || ' → ' || (s ->> 'source') || ':' || (s ->> 'metric') || ' [single-sample]', 'fx63')
    on conflict do nothing;
    n_g := n_g + 1;
  end loop;
  for g in select * from ripples.att_fx_grid where batch = p_batch || '/single' order by grid_id loop
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    for e in select ev.event_id, ev.onset, ev.magnitude from ripples.att_events ev where ev.family = g.family and ev.role = 'library' and ev.onset between pan.days[1] and pan.days[pan.n] order by ev.onset loop
      tr := ripples.att_fx_treated(e.event_id, g.geo_kind, g.target_map);
      select coalesce(array_agg(x order by x), '{}') into tr from unnest(tr) x where x = any(pan.regions);
      continue when cardinality(tr) = 0;
      insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude) values (g.grid_id, e.event_id, 'explore', 0, e.onset, tr, e.magnitude) on conflict do nothing;
      n_x := n_x + 1;
    end loop;
  end loop;
  payload := jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'single', 'batch', p_batch, 'family', p_family, 'config', cfg, 'pairs', p_pairs,
    'grid', (select jsonb_agg(jsonb_build_array(grid_id, family, source, metric, geo_kind, pre_n, post_n, lag_n, expected_sign) order by grid_id) from ripples.att_fx_grid where batch = p_batch || '/single'),
    'events', (select jsonb_agg(jsonb_build_array(f.grid_id, f.event_id, f.onset, f.treated, f.magnitude) order by f.grid_id, f.event_id) from ripples.att_fx_event f join ripples.att_fx_grid g2 on g2.grid_id = f.grid_id where g2.batch = p_batch || '/single' and f.role = 'explore'),
    'panel_extents', ext);
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'single', 'batch', p_batch, 'family', p_family, 'n_pairs', n_g, 'n_events', n_x), payload);
  update ripples.att_fx_grid set frozen_hash = h, frozen_at = now() where batch = p_batch || '/single';
  update ripples.att_fx63_batch set explore_seq = v_seq, explore_hash = h, updated_at = now() where batch = p_batch;
  return jsonb_build_object('batch', p_batch, 'n_pairs', n_g, 'n_events', n_x, 'seq', v_seq);
end $$;
revoke all on function ripples.att_fx63_minwage_register(), ripples.att_fx63_freeze_single(text, text, jsonb) from anon, authenticated, public;


-- =====================================================================================================================
-- P5–P16 (migrations att_engine_63_p5_method_631_both_p … p16_patterns_fluke_line_calibrated) — methods 6.3.1 → 6.3.4 and the v1 inputs.
-- Config (att_config 'engine63') at hand-back: method 6.3.4; split_date 2024-01-01; regime_exclusions [2020-02-15..2021-06-30, all panels];
-- decoy_sets 8; conditional_dc 24 (12 → 24 after the first calibration, ledger register row); clean_null true; clean_control_donors true;
-- winners_curse_shrink 0.6; month_band 45; month_min_distinct 20; outcome_concepts {demand_w: demand}; family_tree {hazard.storm|hurricane:
-- hazard.storm}; prior_exposure_batch fx-2026-09-26; studentised_pool true; mde_ceilings {labor/business/housing 0.03, power/government 0.05,
-- rate 0.3 pp}; forward {lower 0.2, upper 20, shrink 0.6, lambda 0.1..3}; disclosure_634 / disclosure_634b (see ENGINE_63.md §4).
-- Tables (RLS, no grants): att_fx63_batch, att_fx63_select, att_fx63_kill_log, att_fx63_fam_events, att_fx63_forward, att_fx63_rule,
-- att_eia_subregion_map (P13, zone -> states); view att_fx63_patterns; public RPCs rm_patterns63 / rm_hunches / rm_kill_list63 / rm_kill_log63.
-- Hooks on 6.2 bodies (anchor-checked, idempotent): att_fx_cluster_dups (att_fx63_hook_install), att_fx_pool_run (att_fx63_pool_hook_install),
-- public.rm_patterns (att_fx_rm_patterns_quiet_install), att_fx_treated (P13: additive geo kind 'sub'), rm_grant_audit allow-list.
-- Below: the LIVE definitions of every 6.3 function and public RPC, exported from the database after P16 (source of record; the P1–P4
-- bodies above are superseded where a name repeats). Byte-for-byte equal to pg_get_functiondef at export time.
-- =====================================================================================================================
CREATE OR REPLACE FUNCTION ripples.att_fx63_calibration(p_batch text, p_ledger boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j jsonb; n_dsel int; n_dconf int; n_dconf_w int; wi float8[]; wi_w float8[]; x_rate jsonb; unif jsonb; kp jsonb; guard jsonb; v_seq bigint; hk text; cond jsonb; n_ct int; n_cf int; wc float8[];
        c_n_min int := (ripples._att_cfg('engine63') -> 'rule' ->> 'c_n_min')::int; sets int := (ripples._att_cfg('engine63') ->> 'decoy_sets')::int; s int;
begin
  -- conditional: every dc universe of every selected real pair is pooled; a false confirmation = q-equivalent p ≤ 0.05 AND p_norm ≤ 0.05 AND sign = exploration sign
  select count(*), count(*) filter (where p.p_placebo <= 0.05 and coalesce(p.p_norm, 1) <= 0.05 and sign(p.d) = s.x_sign)
    into n_ct, n_cf
    from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id join ripples.att_fx_pool p on p.grid_id = s.grid_id and p.role = 'dc' and p.decoy_set > 0
   where s.batch = p_batch and s.decoy_set = 0 and s.selected and g.bh_weight > 0 and p.n_events >= c_n_min;
  wc := ripples.att_fx_wilson(coalesce(n_cf, 0), greatest(coalesce(n_ct, 0), 0));
  -- end-to-end: decoy exploration selections (dx sets) — how many decoy pairs the rule would have selected
  select count(*) filter (where s.selected and g.bh_weight > 0), count(*) into n_dsel, n_dconf
    from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id where s.batch = p_batch and s.decoy_set > 0;
  select jsonb_build_object('n_pools', count(*), 'share_x_ok', round(avg(s.x_ok::int)::numeric, 3), 'share_p_le10', round(avg((s.x_p <= 0.10)::int)::numeric, 3),
                            'n_selected_per_set', (select jsonb_object_agg(decoy_set, n) from (select decoy_set, count(*) filter (where selected) n from ripples.att_fx63_select where batch = p_batch and decoy_set > 0 group by 1) z))
    into x_rate from ripples.att_fx63_select s where s.batch = p_batch and s.decoy_set > 0 and s.x_n >= 6;
  select jsonb_agg(jsonb_build_object('panel', x.panel, 'n', x.n, 'share_le05', x.s05, 'share_le10', x.s10, 'share_pre_le10', x.pre10) order by x.panel) into unif
    from (select g.source || ':' || g.metric as panel, count(*) n, round(avg((f.p_space <= 0.05)::int)::numeric, 3) s05, round(avg((f.p_space <= 0.10)::int)::numeric, 3) s10, round(avg((f.p_pre <= 0.10)::int)::numeric, 3) pre10
            from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like p_batch || '/%' and f.role = 'dx' and f.p_space is not null group by 1) x;
  select jsonb_agg(jsonb_build_object('pair', g.label, 'is_check', g.bh_weight = 0, 'x_n', s.x_n, 'x_d', round(s.x_d::numeric, 4), 'x_p', s.x_p, 'selected', s.selected, 'c_n', s.c_n, 'c_d', round(s.c_d::numeric, 4), 'c_p', s.c_p, 'c_q', s.c_q, 'verdict', s.verdict, 'mde_80', round(s.mde_80::numeric, 4), 'power_at_x', round(s.power_at_x::numeric, 2)) order by g.grid_id) into kp
    from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id
   where s.batch = p_batch and s.decoy_set = 0 and (g.bh_weight = 0 or (g.family in ('hazard.cold', 'hazard.heat') and g.source = 'eia.930'));
  select pg_get_functiondef(p.oid) into hk from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'ripples' and p.proname = 'att_fx_hook';
  guard := jsonb_build_object(
    'hook_liftable_unchanged', position($l$liftable text[] := array['q above 0.05', 'a placebo family disagrees', 'one channel only', 'placebo families', 'final look not reached']$l$ in hk) > 0,
    'no_63_function_touches_tiers', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'ripples' and p.proname like 'att\_fx63\_%'
                                                 and p.proname <> 'att_fx63_calibration' and (pg_get_functiondef(p.oid) ~ ('att_fin' || 'alize\(') or pg_get_functiondef(p.oid) ~ ('att_hop' || '_tests') or pg_get_functiondef(p.oid) ~ ('att_fx' || '_hook\('))),
    'no_63_grid_has_ledger_seq', not exists (select 1 from ripples.att_fx_grid where status = 'fx63' and ledger_seq is not null));
  j := jsonb_build_object('batch', p_batch, 'at', now(), 'method', ripples._att_cfg('engine63') ->> 'method',
        'decoy_pipeline', jsonb_build_object('kind', 'conditional false-confirmation rate: dc universes of every selected real pair', 'n_decoy_selected', n_ct, 'n_false_confirmed_q05', n_cf,
                                             'rate', case when n_ct > 0 then round(n_cf::numeric / n_ct, 3) end, 'wilson', wc),
        'decoy_end_to_end', jsonb_build_object('n_decoy_pairs_selected_by_rule', n_dsel, 'n_decoy_pair_rows', n_dconf, 'sets', sets),
        'decoy_exploration', x_rate, 'in_space_placebos_by_panel', unif, 'known_positives', kp, 'tier_guard', guard);
  insert into ripples.att_state(k, v) values ('engine63.calibration', j) on conflict (k) do update set v = excluded.v, updated_at = now();
  if p_ledger then
    v_seq := ripples.att_ledger_append(current_date, 'calibration', jsonb_build_object('object', 'fx_grid', 'batch', p_batch, 'method', ripples._att_cfg('engine63') ->> 'method'), j);
    update ripples.att_fx63_batch set calib_seq = v_seq, updated_at = now() where batch = p_batch;
    j := j || jsonb_build_object('seq', v_seq);
  end if;
  return j;
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_clean_null(p_family text, p_cand date, p_treated text[], p_geo_kind text, p_pre integer, p_post integer, p_lag integer, p_grain text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select not exists (select 1 from ripples.att_fx63_fam_events fe where fe.family = split_part(p_family, '|', 1) and fe.geo_kind = p_geo_kind
                      and fe.onset between p_cand - (p_pre + p_lag + p_post + 1) * ripples.att_fx63_gd(p_grain) and p_cand + (p_pre + p_lag + p_post + 1) * ripples.att_fx63_gd(p_grain)
                      and fe.treated && p_treated)
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_confirm_events(p_grid integer)
 RETURNS TABLE(event_id bigint, onset date, treated text[], magnitude real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare g record; pan record; e record; tr text[]; b record; ext jsonb; d0 date; d1 date; regs text[]; split date; cutoff date;
begin
  select * into g from ripples.att_fx_grid where grid_id = p_grid;
  select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
  if not found then return; end if;
  select * into b from ripples.att_fx63_batch bb where g.batch like bb.batch || '/%' limit 1;
  split := coalesce(b.split_date, (ripples._att_cfg('engine63') ->> 'split_date')::date);
  ext := b.panel_extents -> (g.source || ':' || g.metric || ':' || g.geo_kind);
  d0 := coalesce((ext ->> 'from')::date, pan.days[1]); d1 := coalesce((ext ->> 'to')::date, pan.days[pan.n]);
  cutoff := coalesce(b.confirm_cutoff, d1) - (g.lag_n + g.post_n + 1) * ripples.att_fx63_gd(pan.grain);
  select coalesce((select array_agg(x) from jsonb_array_elements_text(ext -> 'regions') x), pan.regions) into regs;
  for e in select ev.event_id, ev.onset, ev.magnitude from ripples.att_events ev join ripples.att_topics t on t.topic_id = ev.topic_id
           where ev.family = g.family and ev.role = 'library' and (g.sub is null or (g.sub = 'hurricane' and t.meta ? 'storm'))
             and ev.onset >= split and ev.onset between d0 and least(d1, cutoff)
             and ripples.att_fx63_regime_ok(ev.onset, g.pre_n, g.post_n, g.lag_n, pan.grain) order by ev.onset, ev.event_id loop
    tr := ripples.att_fx_treated(e.event_id, g.geo_kind, g.target_map);
    select coalesce(array_agg(x order by x), '{}') into tr from unnest(tr) x where x = any(regs);
    continue when cardinality(tr) = 0;
    event_id := e.event_id; onset := e.onset; treated := tr; magnitude := e.magnitude; return next;
  end loop;
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_confirm_freeze(p_batch text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare b record; sr record; cr record; n_ev int := 0; n_sel int := 0; bad text[] := '{}'; payload jsonb; h text; v_seq bigint;
begin
  select * into b from ripples.att_fx63_batch where batch = p_batch;
  if not found or b.explore_seq is null then return jsonb_build_object('error', 'exploration not frozen'); end if;
  if b.confirm_seq is not null then return jsonb_build_object('batch', p_batch, 'already_frozen', true, 'seq', b.confirm_seq); end if;
  for sr in select * from ripples.att_fx63_select where batch = p_batch and decoy_set = 0 and selected order by grid_id loop
    if ripples.att_fx63_confirm_hash(sr.grid_id) is distinct from (b.confirm_hashes ->> sr.grid_id::text) then bad := bad || sr.grid_id::text; continue; end if;
    n_sel := n_sel + 1;
    for cr in select * from ripples.att_fx63_confirm_events(sr.grid_id) loop
      insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude)
      values (sr.grid_id, cr.event_id, 'confirm', 0, cr.onset, cr.treated, cr.magnitude) on conflict do nothing;
      n_ev := n_ev + 1;
    end loop;
  end loop;
  if cardinality(bad) > 0 then return jsonb_build_object('error', 'held-out event list changed since the exploration freeze', 'grids', bad); end if;
  payload := jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'confirm', 'batch', p_batch, 'explore_seq', b.explore_seq, 'rule', b.cfg -> 'rule',
    'selected', (select jsonb_agg(jsonb_build_array(s.grid_id, g.label, s.x_n, s.x_d, s.x_p, s.x_sign, s.rank, g.bh_weight) order by s.grid_id)
                   from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id where s.batch = p_batch and s.decoy_set = 0 and s.selected),
    'events', (select jsonb_agg(jsonb_build_array(f.grid_id, f.event_id, f.onset, f.treated, f.magnitude) order by f.grid_id, f.event_id)
                 from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like p_batch || '/%' and f.role = 'confirm'));
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'confirm', 'batch', p_batch,
                                     'n_selected', n_sel, 'n_confirm_events', n_ev, 'explore_seq', b.explore_seq), payload);
  update ripples.att_fx63_batch set confirm_seq = v_seq, confirm_hash = h, status = 'confirming', updated_at = now() where batch = p_batch;
  return jsonb_build_object('batch', p_batch, 'n_selected', n_sel, 'n_confirm_events', n_ev, 'seq', v_seq, 'hash', h);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_confirm_hash(p_grid integer)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select encode(extensions.digest(coalesce((select string_agg(event_id || ':' || onset || ':' || array_to_string(treated, ',') || ':' || coalesce(magnitude::text, ''), '|' order by event_id)
                                            from ripples.att_fx63_confirm_events(p_grid)), ''), 'sha256'), 'hex')
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_contaminated(p_family text, p_geo_kind text, p_onset date, p_pre integer, p_post integer, p_lag integer, p_grain text, p_self bigint)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(distinct x), '{}') from ripples.att_fx63_fam_events fe, unnest(fe.treated) x
   where fe.family = p_family and fe.geo_kind = p_geo_kind and fe.event_id is distinct from p_self
     and abs(fe.onset - p_onset) <= (p_pre + p_lag + p_post) * ripples.att_fx63_gd(p_grain)
$function$
;
CREATE OR REPLACE FUNCTION public.rm_hunches(p_family text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.grid_id, 'batch', r.batch, 'method', '6.3', 'label', 'hunch', 'family', r.family, 'family_label', r.family_label, 'sub', r.sub,
    'event_label', case when r.sub = 'hurricane' then 'Hurricanes' else r.family_label || 's' end,
    'outcome', r.source || ':' || r.metric, 'outcome_label', r.outcome_label, 'geo_kind', r.geo_kind,
    'window', jsonb_build_object('pre', r.pre_n, 'post', r.post_n, 'lag', r.lag_n, 'grain', r.grain, 'variant', r.variant), 'unit', r.unit,
    'exploration', jsonb_build_object('n_events', r.x_n, 'effect', r.x_pct, 'p_placebo', r.x_p, 'period', 'before ' || r.split_date),
    'held_out', case when r.c_n is not null then jsonb_build_object('n_events', r.c_n, 'effect', r.c_pct, 'ci', jsonb_build_array(r.c_pct_lo, r.c_pct_hi), 'p_placebo', r.c_p, 'q', r.c_q, 'sign_ok', r.c_sign_ok, 'period', 'since ' || r.split_date) end,
    'status', r.verdict, 'strength', 'hunch',
    'status_label', case when r.verdict = 'not replicated' then 'did not show up again in the held-out events'
                         when r.verdict = 'reversed' then 'moved the other way in the held-out events'
                         when r.verdict like 'too few held-out%' then 'not enough held-out events yet to test it'
                         when r.verdict like 'not tested%' then 'a lead that was not tested (' || r.reason || ')'
                         when r.verdict = 'confirmation pending' then 'held-out test pending' else r.verdict end,
    'domain_distance', r.domain_distance, 'expected_by_mechanism', r.expected_by_mechanism, 'non_obvious', (r.domain_distance >= 1),
    'note', 'an exploratory lead from one half of the archive that did not survive (or has not yet had) an out-of-sample test; not evidence about any event',
    'sample_events', ripples.att_fx63_sample_events(r.grid_id, 'explore', 2),
    'ledger', jsonb_build_object('explore_seq', r.explore_seq, 'confirm_seq', r.confirm_seq), 'computed_at', r.computed_at
  ) order by (r.verdict = 'not replicated') desc, r.x_p), '[]'::jsonb)
  from (select v.* from ripples.att_fx63_patterns v
         where v.decoy_set = 0 and v.x_ok and v.strength = 'hunch' and not v.is_check
           and not ripples.rm_node_hidden(v.source || ':' || v.metric)
           and (p_family is null or v.family = p_family)
         order by (v.verdict = 'not replicated') desc, v.x_p limit greatest(1, least(p_limit, 200))) r
$function$
;
CREATE OR REPLACE FUNCTION public.rm_kill_list63(p_batch text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', v.grid_id, 'batch', v.batch, 'family', v.family, 'family_label', v.family_label, 'sub', v.sub,
    'event_label', case when v.sub = 'hurricane' then 'Hurricanes' else v.family_label || 's' end,
    'outcome', v.source || ':' || v.metric, 'outcome_label', v.outcome_label, 'window', jsonb_build_object('pre', v.pre_n, 'post', v.post_n, 'lag', v.lag_n, 'grain', v.grain, 'variant', v.variant),
    'unit', v.unit, 'is_check', v.is_check,
    'exploration', jsonb_build_object('n_events', v.x_n, 'effect', v.x_pct, 'effect_logpts', round(v.x_d::numeric, 4), 'se_logpts', round(v.x_se::numeric, 4),
                                      'ci_logpts', jsonb_build_array(round((v.x_d - 1.96 * v.x_se)::numeric, 4), round((v.x_d + 1.96 * v.x_se)::numeric, 4)), 'p_placebo', v.x_p, 'period', 'before ' || v.split_date),
    'held_out', case when v.c_n is not null then jsonb_build_object('n_events', v.c_n, 'effect', v.c_pct, 'ci', jsonb_build_array(v.c_pct_lo, v.c_pct_hi), 'i2', round(coalesce(v.c_i2, 0)::numeric, 2), 'p_placebo', v.c_p, 'p_norm', v.c_p_norm, 'q', v.c_q, 'sign_ok', v.c_sign_ok, 'period', 'since ' || v.split_date) end,
    'candidate', v.x_ok, 'selected', v.selected, 'reason', v.reason, 'verdict', coalesce(v.verdict, case when v.x_ok then 'pending' else 'not a candidate' end), 'strength', v.strength,
    'ghost', (not coalesce(v.x_ok, false) and v.x_n >= 20 and v.x_se is not null and 2 * 1.96 * v.x_se <= 0.06),
    'ghost_note', case when (not coalesce(v.x_ok, false) and v.x_n >= 20 and v.x_se is not null and 2 * 1.96 * v.x_se <= 0.06)
                       then 'well-powered null: across ' || v.x_n || ' events the 95% interval is narrower than ±' || round((100 * 1.96 * v.x_se)::numeric, 1) || '%' end,
    'domain_distance', v.domain_distance, 'expected_by_mechanism', v.expected_by_mechanism, 'non_obvious', (v.domain_distance >= 1),
    'ledger', jsonb_build_object('explore_seq', v.explore_seq, 'confirm_seq', v.confirm_seq)
  ) order by v.selected desc, coalesce(v.verdict, 'z'), v.x_p nulls last, v.grid_id), '[]'::jsonb)
  from ripples.att_fx63_patterns v
  where v.decoy_set = 0 and (p_batch is null or v.batch = p_batch) and not ripples.rm_node_hidden(v.source || ':' || v.metric)
$function$
;
CREATE OR REPLACE FUNCTION public.rm_kill_log63(p_batch text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('batch', k.batch, 'id', k.grid_id, 'pair', g.label, 'family', coalesce(k.family, g.family), 'attack', k.attack, 'evidence', k.evidence, 'decided_at', k.decided_at, 'ledger_seq', k.ledger_seq) order by k.decided_at desc, k.id desc), '[]'::jsonb)
    from ripples.att_fx63_kill_log k left join ripples.att_fx_grid g on g.grid_id = k.grid_id where p_batch is null or k.batch = p_batch
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_decoy_confirm_seed(p_batch text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb := ripples._att_cfg('engine63'); m int := coalesce((cfg ->> 'conditional_dc')::int, 30); split date := (cfg ->> 'split_date')::date;
        s record; pan record; c record; y0 int; yr int; yrs int[]; cand date; tries int; ok boolean; n_ins int := 0; band int; k int;
begin
  for s in select sl.*, g.source, g.metric, g.geo_kind, g.family, g.pre_n, g.post_n, g.lag_n from ripples.att_fx63_select sl join ripples.att_fx_grid g on g.grid_id = sl.grid_id
           where sl.batch = p_batch and sl.decoy_set = 0 and sl.selected order by sl.grid_id loop
    select * into pan from ripples.att_fx_panel p where p.source = s.source and p.metric = s.metric and p.geo_kind = s.geo_kind;
    band := case when pan.grain = 'month' then coalesce((cfg ->> 'month_band')::int, 45) else coalesce((cfg -> 'confirm' ->> 'season_band')::int, 21) end;
    for k in 1..m loop
      perform setseed(((hashtext('fx63dc2:' || s.grid_id || ':' || k) % 100000) / 100000.0)::float8);
      for c in select * from ripples.att_fx63_confirm_events(s.grid_id) loop
        y0 := extract(year from c.onset)::int; yrs := '{}';
        for yr in extract(year from split)::int..(extract(year from pan.days[pan.n])::int) loop if yr <> y0 then yrs := yrs || yr; end if; end loop;
        continue when cardinality(yrs) = 0;
        ok := false; tries := 0;
        while not ok and tries < 30 loop
          tries := tries + 1;
          yr := yrs[1 + floor(random() * cardinality(yrs))::int];
          cand := (c.onset + make_interval(years => yr - y0))::date + (floor(random() * (2 * band + 1))::int - band);
          ok := cand >= split and cand between pan.days[1] + 200 and pan.days[pan.n] - (s.lag_n + s.post_n + 1) * ripples.att_fx63_gd(pan.grain) and abs(cand - c.onset) > 120
                and ripples.att_fx63_regime_ok(cand, s.pre_n, s.post_n, s.lag_n, pan.grain)
                and ripples.att_fx63_clean_null(s.family, cand, c.treated, s.geo_kind, s.pre_n, s.post_n, s.lag_n, pan.grain);
        end loop;
        continue when not ok;
        insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude) values (s.grid_id, c.event_id, 'dc', k, cand, c.treated, c.magnitude) on conflict do nothing;
        n_ins := n_ins + 1;
      end loop;
    end loop;
  end loop;
  return n_ins;
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_decoy_confirm_seed_step(p_batch text, p_budget_s integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb := ripples._att_cfg('engine63'); m int := coalesce((cfg ->> 'conditional_dc')::int, 12); split date := (cfg ->> 'split_date')::date; t0 timestamptz := clock_timestamp();
        s record; pan record; c record; y0 int; yr int; yrs int[]; cand date; tries int; ok boolean; n_ins int := 0; band int; kk int; done jsonb; key text; n_groups int := 0;
begin
  select coalesce(v -> 'done', '{}'::jsonb) into done from ripples.att_state where k = 'engine63.dc_seed:' || p_batch;
  done := coalesce(done, '{}'::jsonb);
  for s in select sl.*, g.source, g.metric, g.geo_kind, g.family, g.pre_n, g.post_n, g.lag_n from ripples.att_fx63_select sl join ripples.att_fx_grid g on g.grid_id = sl.grid_id
           where sl.batch = p_batch and sl.decoy_set = 0 and sl.selected order by sl.grid_id loop
    select * into pan from ripples.att_fx_panel p where p.source = s.source and p.metric = s.metric and p.geo_kind = s.geo_kind;
    band := case when pan.grain = 'month' then coalesce((cfg ->> 'month_band')::int, 45) else coalesce((cfg -> 'confirm' ->> 'season_band')::int, 21) end;
    for kk in 1..m loop
      key := s.grid_id || ':' || kk;
      continue when done ? key;
      perform setseed(((hashtext('fx63dc3:' || s.grid_id || ':' || kk) % 100000) / 100000.0)::float8);
      for c in select * from ripples.att_fx63_confirm_events(s.grid_id) loop
        y0 := extract(year from c.onset)::int; yrs := '{}';
        for yr in extract(year from split)::int..(extract(year from pan.days[pan.n])::int) loop if yr <> y0 then yrs := yrs || yr; end if; end loop;
        continue when cardinality(yrs) = 0;
        ok := false; tries := 0;
        while not ok and tries < 30 loop
          tries := tries + 1;
          yr := yrs[1 + floor(random() * cardinality(yrs))::int];
          cand := (c.onset + make_interval(years => yr - y0))::date + (floor(random() * (2 * band + 1))::int - band);
          ok := cand >= split and cand between pan.days[1] + 200 and pan.days[pan.n] - (s.lag_n + s.post_n + 1) * ripples.att_fx63_gd(pan.grain) and abs(cand - c.onset) > 120
                and ripples.att_fx63_regime_ok(cand, s.pre_n, s.post_n, s.lag_n, pan.grain)
                and ripples.att_fx63_clean_null(s.family, cand, c.treated, s.geo_kind, s.pre_n, s.post_n, s.lag_n, pan.grain);
        end loop;
        continue when not ok;
        insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude) values (s.grid_id, c.event_id, 'dc', kk, cand, c.treated, c.magnitude) on conflict do nothing;
        n_ins := n_ins + 1;
      end loop;
      done := done || jsonb_build_object(key, true); n_groups := n_groups + 1;
      insert into ripples.att_state(k, v) values ('engine63.dc_seed:' || p_batch, jsonb_build_object('done', done, 'at', now())) on conflict (k) do update set v = excluded.v, updated_at = now();
      if clock_timestamp() - t0 > make_interval(secs => p_budget_s) then return jsonb_build_object('inserted', n_ins, 'groups', n_groups, 'complete', false); end if;
    end loop;
  end loop;
  return jsonb_build_object('inserted', n_ins, 'groups', n_groups, 'complete', true);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_decoy_seed(p_batch text, p_sets integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb := ripples._att_cfg('engine63'); sets int := coalesce(p_sets, (cfg ->> 'decoy_sets')::int, 2); split date := (cfg ->> 'split_date')::date;
        g record; pan record; e record; s int; y0 int; yr int; yrs int[]; cand date; tries int; ok boolean; n_ins int := 0; band int; n_rej int := 0;
begin
  for g in select * from ripples.att_fx_grid where batch like p_batch || '/%' order by grid_id loop
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    band := case when pan.grain = 'month' then coalesce((cfg ->> 'month_band')::int, 45) else coalesce((cfg -> 'explore' ->> 'season_band')::int, 21) end;
    for s in 1..sets loop
      perform setseed(((hashtext('fx63decoy2:' || g.grid_id || ':' || s) % 100000) / 100000.0)::float8);
      for e in select * from ripples.att_fx_event f where f.grid_id = g.grid_id and f.role = 'explore' order by f.event_id loop
        y0 := extract(year from e.onset)::int; yrs := '{}';
        for yr in (extract(year from pan.days[1])::int + 1)..(extract(year from split)::int - 1) loop if yr <> y0 then yrs := yrs || yr; end if; end loop;
        continue when cardinality(yrs) = 0;
        ok := false; tries := 0;
        while not ok and tries < 30 loop
          tries := tries + 1;
          yr := yrs[1 + floor(random() * cardinality(yrs))::int];
          cand := (e.onset + make_interval(years => yr - y0))::date + (floor(random() * (2 * band + 1))::int - band);
          ok := cand between pan.days[1] + 200 and pan.days[pan.n] - 60 and cand < split and abs(cand - e.onset) > 120
                and ripples.att_fx63_regime_ok(cand, g.pre_n, g.post_n, g.lag_n, pan.grain)
                and ripples.att_fx63_clean_null(g.family, cand, e.treated, g.geo_kind, g.pre_n, g.post_n, g.lag_n, pan.grain);
        end loop;
        if not ok then n_rej := n_rej + 1; continue; end if;
        insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude) values (g.grid_id, e.event_id, 'dx', s, cand, e.treated, e.magnitude) on conflict do nothing;
        n_ins := n_ins + 1;
      end loop;
    end loop;
  end loop;
  insert into ripples.att_state(k, v) values ('engine63.decoy_seed', jsonb_build_object('batch', p_batch, 'sets', sets, 'inserted', n_ins, 'rejected_no_clean_draw', n_rej, 'at', now()))
  on conflict (k) do update set v = excluded.v, updated_at = now();
  return n_ins;
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_domain_distance(p_de text, p_do text)
 RETURNS real
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce((ripples._att_cfg('engine63') -> 'domains' -> p_de ->> p_do)::real,
                  case when p_de = p_do then 0 else 1 end)
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_expected_by_mechanism(p_family text, p_source text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with src as (select unnest(case when p_source in ('dol.claims', 'fred.claims') then array['dol.claims', 'fred.claims'] else array[p_source] end) s)
  select exists (select 1 from ripples.att_families f, jsonb_array_elements(coalesce(f.mapper, '[]'::jsonb)) m, src
                  where f.family = p_family
                    and (m ->> 'node' like src.s || ':%' or m ->> 'node_pattern' like src.s || ':%' or m ->> 'source' = src.s))
      or exists (select 1 from ripples.att_mech_edges e, src where e.valid_to is null and e.from_node = 'family:' || p_family and e.to_node like src.s || ':%')
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_fam_events_build()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; tr text[]; n int := 0;
begin
  truncate ripples.att_fx63_fam_events;
  for r in select distinct e.event_id, e.onset, e.family, gk.geo_kind from ripples.att_events e cross join (values ('state'), ('ba')) gk(geo_kind)
           where e.role = 'library' and e.family in (select distinct family from ripples.att_fx_grid where status = 'fx63') loop
    tr := ripples.att_fx_treated(r.event_id, r.geo_kind, null);
    continue when tr is null or cardinality(tr) = 0;
    insert into ripples.att_fx63_fam_events(family, geo_kind, event_id, onset, treated) values (r.family, r.geo_kind, r.event_id, r.onset, tr) on conflict do nothing;
    n := n + 1;
  end loop;
  return n;
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_finisher(p_batch text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare b record; n_x_pending int; n_c_pending int; n_dx_pending int; n_dc_pending int; n_dx int; n_dc int; out jsonb := '{}'::jsonb; s int; sets int := (ripples._att_cfg('engine63') ->> 'decoy_sets')::int; r record; dcs jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('fx63finisher')) then return jsonb_build_object('skipped', 'running'); end if;
  select * into b from ripples.att_fx63_batch where batch = p_batch;
  if not found or b.explore_seq is null then return jsonb_build_object('error', 'not frozen'); end if;
  select count(*) filter (where f.role = 'explore' and f.computed_at is null), count(*) filter (where f.role = 'confirm' and f.computed_at is null),
         count(*) filter (where f.role = 'dx' and f.computed_at is null), count(*) filter (where f.role = 'dc' and f.computed_at is null), count(*) filter (where f.role = 'dx'), count(*) filter (where f.role = 'dc')
    into n_x_pending, n_c_pending, n_dx_pending, n_dc_pending, n_dx, n_dc from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like p_batch || '/%';
  -- stage 1: exploration complete + pooled → select + confirmation freeze (short)
  if n_x_pending = 0 and b.confirm_seq is null and not exists (select 1 from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like p_batch || '/%' and f.role = 'explore'
                                                             and not exists (select 1 from ripples.att_fx_pool p where p.grid_id = f.grid_id and p.role = 'explore' and p.decoy_set = 0)) then
    out := out || jsonb_build_object('select0', ripples.att_fx63_select_run(p_batch, 0), 'confirm_freeze', ripples.att_fx63_confirm_freeze(p_batch));
    return out;
  end if;
  -- stage 1b: conditional decoys, chunked
  if b.confirm_seq is not null then
    select v into dcs from ripples.att_state where k = 'engine63.dc_seed:' || p_batch;
    if dcs is null or not coalesce((dcs ->> 'complete')::boolean, false) then
      out := out || jsonb_build_object('dc_seed', ripples.att_fx63_decoy_confirm_seed_step(p_batch, 45));
      if (out -> 'dc_seed' ->> 'complete')::boolean then
        update ripples.att_state set v = v || '{"complete": true}'::jsonb where k = 'engine63.dc_seed:' || p_batch;
      end if;
      return out;
    end if;
  end if;
  -- stage 2: decoy exploration complete → decoy selections
  if n_dx > 0 and n_dx_pending = 0 and not exists (select 1 from ripples.att_fx63_select where batch = p_batch and decoy_set > 0) then
    for s in 1..sets loop out := out || jsonb_build_object('select' || s, ripples.att_fx63_select_run(p_batch, s)); end loop;
    return out;
  end if;
  -- stage 3: confirmation + conditional decoys complete → verdicts, repeatability, calibration, forward set
  if b.confirm_seq is not null and n_c_pending = 0 and n_dc > 0 and n_dc_pending = 0 and n_dx_pending = 0 and b.calib_seq is null
     and exists (select 1 from ripples.att_fx63_select where batch = p_batch and decoy_set > 0)
     and not exists (select 1 from ripples.att_fx_event f join ripples.att_fx_grid g on g.grid_id = f.grid_id where g.batch like p_batch || '/%' and f.role in ('confirm', 'dc')
                       and not exists (select 1 from ripples.att_fx_pool p where p.grid_id = f.grid_id and p.role = f.role and p.decoy_set = f.decoy_set)) then
    out := out || jsonb_build_object('verdict0', ripples.att_fx63_verdict(p_batch, 0));
    for r in select s2.grid_id, s2.x_sign from ripples.att_fx63_select s2 where s2.batch = p_batch and s2.decoy_set = 0 and s2.selected loop
      update ripples.att_fx63_select set repeat_detail = ripples.att_fx63_repeatability(r.grid_id, 'confirm', r.x_sign), repeatability = (ripples.att_fx63_repeatability(r.grid_id, 'confirm', r.x_sign) ->> 'score')::int
       where batch = p_batch and decoy_set = 0 and grid_id = r.grid_id;
    end loop;
    out := out || jsonb_build_object('calibration', ripples.att_fx63_calibration(p_batch, true) - 'in_space_placebos_by_panel' - 'known_positives');
    out := out || jsonb_build_object('forward', ripples.att_fx63_forward_register(p_batch));
    perform cron.unschedule(jobid) from cron.job where jobname like 'att-fx63-step-%';
    return out || jsonb_build_object('finished', true);
  end if;
  -- stage 4: score forward events (after calibration), then unschedule the finisher
  if b.calib_seq is not null then
    out := out || jsonb_build_object('forward_score', ripples.att_fx63_forward_score(p_batch, 45));
    if (out -> 'forward_score' ->> 'pending')::int = 0 then perform cron.unschedule(jobid) from cron.job where jobname = 'att-fx63-finisher'; out := out || '{"all_done": true}'::jsonb; end if;
    return out;
  end if;
  return out || jsonb_build_object('pending', jsonb_build_object('explore', n_x_pending, 'confirm', n_c_pending, 'dx', n_dx_pending, 'dc', n_dc_pending));
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_fluke_line(p_rung text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with c as (select s.v -> 'decoy_pipeline' d from ripples.att_state s where s.k = 'engine63.calibration')
  select case when p_rung in ('pattern', 'consistent') then
                case when coalesce((d ->> 'n_decoy_selected')::int, 0) >= 45 and (d -> 'wilson' ->> 2)::float8 > 0
                     then 'found in one half of the archive and seen again in the other; calibrated on decoy families, fewer than 1 in ' || floor(1 / (d -> 'wilson' ->> 2)::float8)::int || ' findings at this level are flukes'
                     else 'found in one half of the archive and seen again in the other; fluke rate not yet calibrated (' || coalesce(d ->> 'n_decoy_selected', '0') || ' decoy trials so far), shown as weaker until it is' end
              when p_rung = 'pattern_weaker' then 'found in one half of the archive and seen again in the other; about 1 in 5 findings at this level could be a fluke'
              when p_rung = 'check' then 'a pre-registered sanity check, not a finding' else null end from c
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_forward_register(p_batch text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb := ripples._att_cfg('engine63') -> 'forward'; b record; s record; pan record; fc jsonb; n_rules int := 0; n_ev int := 0; payload jsonb; v_seq bigint; gd int;
begin
  select * into b from ripples.att_fx63_batch where batch = p_batch;
  for s in select sl.*, g.source, g.metric, g.geo_kind, g.post_n, g.lag_n from ripples.att_fx63_select sl join ripples.att_fx_grid g on g.grid_id = sl.grid_id
           where sl.batch = p_batch and sl.decoy_set = 0 and sl.rung in ('pattern', 'pattern_weaker', 'consistent') loop
    select * into pan from ripples.att_fx_panel p where p.source = s.source and p.metric = s.metric and p.geo_kind = s.geo_kind;
    gd := ripples.att_fx63_gd(pan.grain);
    insert into ripples.att_fx63_rule(batch, grid_id, delta_ref, sign, lambda_min, lambda_max, upper_bound, lower_bound, updated_at)
    values (p_batch, s.grid_id, (cfg ->> 'shrink')::float8 * s.c_d, s.x_sign, (cfg ->> 'lambda_min')::real, (cfg ->> 'lambda_max')::real, (cfg ->> 'upper')::real, (cfg ->> 'lower')::real, now())
    on conflict (batch, grid_id) do nothing;
    n_rules := n_rules + 1;
    for fc in select * from jsonb_array_elements(coalesce(b.forward_candidates, '[]'::jsonb)) x where (x ->> 0)::int = s.grid_id loop
      insert into ripples.att_fx63_forward(batch, grid_id, event_id, onset, treated, window_close)
      select p_batch, s.grid_id, (fc ->> 1)::bigint, (fc ->> 2)::date, ripples.att_fx_treated((fc ->> 1)::bigint, s.geo_kind, null), (fc ->> 2)::date + (s.lag_n + s.post_n + 1) * gd
      on conflict do nothing;
      n_ev := n_ev + 1;
    end loop;
  end loop;
  payload := jsonb_build_object('object', 'fx63_forward', 'batch', p_batch, 'rules', (select jsonb_agg(to_jsonb(r) - 'updated_at' order by r.grid_id) from ripples.att_fx63_rule r where r.batch = p_batch),
                                'events', (select jsonb_agg(jsonb_build_array(f.grid_id, f.event_id, f.onset, f.window_close) order by f.grid_id, f.event_id) from ripples.att_fx63_forward f where f.batch = p_batch), 'config', cfg);
  if n_rules > 0 then
    v_seq := ripples.att_ledger_append(current_date, 'register', jsonb_build_object('object', 'fx63_forward', 'batch', p_batch, 'n_rules', n_rules, 'n_events', n_ev), payload);
    update ripples.att_fx63_rule set registered_seq = v_seq where batch = p_batch and registered_seq is null;
  end if;
  return jsonb_build_object('rules', n_rules, 'events', n_ev, 'seq', v_seq);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_forward_score(p_batch text, p_budget_s integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb := ripples._att_cfg('engine63'); t0 timestamptz := clock_timestamp(); f record; g record; pan record; ru record; j jsonb; lam float8; z float8; ev float8; n int := 0; dc float8;
begin
  for f in select fw.* from ripples.att_fx63_forward fw where fw.batch = p_batch and fw.computed_at is null and fw.window_close <= current_date order by fw.grid_id, fw.onset loop
    select * into g from ripples.att_fx_grid where grid_id = f.grid_id;
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    select * into ru from ripples.att_fx63_rule where batch = p_batch and grid_id = f.grid_id;
    if not ripples.att_fx63_regime_ok(f.onset, g.pre_n, g.post_n, g.lag_n, pan.grain) or cardinality(f.treated) = 0 then
      update ripples.att_fx63_forward set computed_at = now(), status_after = 'skipped' where batch = p_batch and grid_id = f.grid_id and event_id = f.event_id; continue;
    end if;
    j := ripples.att_fx_calc(pan.ps, pan.pc, pan.days, pan.regions, pan.grain, f.treated, f.onset, g.pre_n, g.post_n, g.lag_n, false, ((hashtext('fwd:' || f.grid_id || ':' || f.event_id) % 100000) / 100000.0)::float8, cfg -> 'confirm');
    if j ->> 'se' is null then update ripples.att_fx63_forward set computed_at = now(), status_after = 'no estimate' where batch = p_batch and grid_id = f.grid_id and event_id = f.event_id; continue; end if;
    dc := (j ->> 'd')::float8 - (j ->> 'med')::float8; z := ru.sign * dc / (j ->> 'se')::float8;
    lam := least(greatest(abs(ru.delta_ref) / (j ->> 'se')::float8, ru.lambda_min), ru.lambda_max);
    ev := exp(lam * z - lam * lam / 2);
    update ripples.att_fx63_rule set cum_e = least(cum_e * ev, 1e12), n_forward = n_forward + 1, n_hits = n_hits + (z > 0)::int, last_event = f.onset,
           status = case when least(cum_e * ev, 1e12) >= upper_bound then 'standing (re-confirmed)' when cum_e * ev <= lower_bound then 'retired' else 'watching' end, updated_at = now()
     where batch = p_batch and grid_id = f.grid_id;
    update ripples.att_fx63_forward set d = (j ->> 'd')::real, med = (j ->> 'med')::real, se = (j ->> 'se')::real, z = z, e_value = ev, cum_e = (select cum_e from ripples.att_fx63_rule where batch = p_batch and grid_id = f.grid_id),
           status_after = (select status from ripples.att_fx63_rule where batch = p_batch and grid_id = f.grid_id), computed_at = now()
     where batch = p_batch and grid_id = f.grid_id and event_id = f.event_id;
    n := n + 1;
    exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s);
  end loop;
  return jsonb_build_object('scored', n, 'pending', (select count(*) from ripples.att_fx63_forward where batch = p_batch and computed_at is null and window_close <= current_date));
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_freeze(p_batch text, p_set text DEFAULT 'b1'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb := ripples._att_cfg('engine63'); split date := (cfg ->> 'split_date')::date; s jsonb; v jsonb; g record; e record; tr text[];
        n_x int := 0; n_c int := 0; n_g int := 0; n_reg int := 0; n_fwd int := 0; payload jsonb; h text; v_seq bigint; pan record; conf jsonb := '[]'::jsonb; fwd jsonb := '[]'::jsonb;
        hashes jsonb := '{}'::jsonb; ext jsonb; regs jsonb := '{}'::jsonb; cutoff date := current_date; gd int; n_reg_g int;
begin
  if exists (select 1 from ripples.att_fx63_batch where batch = p_batch and explore_seq is not null) then
    return jsonb_build_object('batch', p_batch, 'already_frozen', true, 'seq', (select explore_seq from ripples.att_fx63_batch where batch = p_batch));
  end if;
  select jsonb_object_agg(source || ':' || metric || ':' || geo_kind, jsonb_build_object('from', days[1], 'to', days[n], 'regions', to_jsonb(regions), 'n', n, 'grain', grain)) into ext from ripples.att_fx_panel;
  insert into ripples.att_fx63_batch(batch, split_date, cfg, status, panel_extents, confirm_cutoff) values (p_batch, split, cfg, 'exploring', ext, cutoff)
  on conflict (batch) do update set panel_extents = excluded.panel_extents, confirm_cutoff = excluded.confirm_cutoff, split_date = excluded.split_date, cfg = excluded.cfg where ripples.att_fx63_batch.explore_seq is null;
  for s in select * from jsonb_array_elements(ripples.att_fx63_grid_spec(p_set)) loop
    continue when not exists (select 1 from ripples.att_fx_panel p where p.source = s ->> 'source' and p.metric = s ->> 'metric' and p.geo_kind = s ->> 'geo_kind');
    for v in select * from jsonb_array_elements(s -> 'variants') loop
      insert into ripples.att_fx_grid(batch, family, sub, source, metric, geo_kind, pre_n, post_n, lag_n, expected_sign, synth, definitional, domain_event, domain_outcome, target_map, bh_weight, label, status)
      values (p_batch || '/' || (v ->> 3), s ->> 'family', s ->> 'sub', s ->> 'source', s ->> 'metric', s ->> 'geo_kind', (v ->> 0)::int, (v ->> 1)::int, (v ->> 2)::int,
              0, false, (s ->> 'definitional')::boolean, s ->> 'de', s ->> 'do', null, (s ->> 'w')::real,
              coalesce(s ->> 'sub', s ->> 'family') || ' → ' || (s ->> 'source') || ':' || (s ->> 'metric') || ' [' || (v ->> 3) || ']', 'fx63')
      on conflict do nothing;
      n_g := n_g + 1;
    end loop;
  end loop;
  for g in select * from ripples.att_fx_grid where batch like p_batch || '/%' order by grid_id loop
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    gd := ripples.att_fx63_gd(pan.grain); n_reg_g := 0;
    for e in select ev.event_id, ev.onset, ev.magnitude from ripples.att_events ev join ripples.att_topics t on t.topic_id = ev.topic_id
             where ev.family = g.family and ev.role = 'library' and (g.sub is null or (g.sub = 'hurricane' and t.meta ? 'storm'))
               and ev.onset < split and ev.onset between pan.days[1] and pan.days[pan.n] order by ev.onset loop
      tr := ripples.att_fx_treated(e.event_id, g.geo_kind, g.target_map);
      select coalesce(array_agg(x order by x), '{}') into tr from unnest(tr) x where x = any(pan.regions);
      continue when cardinality(tr) = 0;
      if not ripples.att_fx63_regime_ok(e.onset, g.pre_n, g.post_n, g.lag_n, pan.grain) then n_reg_g := n_reg_g + 1; continue; end if;
      insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude) values (g.grid_id, e.event_id, 'explore', 0, e.onset, tr, e.magnitude) on conflict do nothing;
      n_x := n_x + 1;
    end loop;
    select conf || coalesce(jsonb_agg(jsonb_build_array(g.grid_id, c.event_id, c.onset, c.treated, c.magnitude) order by c.event_id), '[]'::jsonb), n_c + count(*) into conf, n_c from ripples.att_fx63_confirm_events(g.grid_id) c;
    -- forward set: regime-clean held-out events after the cut-off (scored later, never in this batch's confirmation)
    select fwd || coalesce(jsonb_agg(jsonb_build_array(g.grid_id, ev.event_id, ev.onset) order by ev.onset), '[]'::jsonb), n_fwd + count(*) into fwd, n_fwd
      from ripples.att_events ev join ripples.att_topics t on t.topic_id = ev.topic_id
     where ev.family = g.family and ev.role = 'library' and (g.sub is null or (g.sub = 'hurricane' and t.meta ? 'storm'))
       and ev.onset > cutoff - (g.lag_n + g.post_n + 1) * gd and ev.onset <= pan.days[pan.n];
    hashes := hashes || jsonb_build_object(g.grid_id::text, ripples.att_fx63_confirm_hash(g.grid_id));
    regs := regs || jsonb_build_object(g.grid_id::text, n_reg_g); n_reg := n_reg + n_reg_g;
  end loop;
  payload := jsonb_build_object('object', 'fx_grid', 'method', cfg ->> 'method', 'stage', 'explore', 'batch', p_batch, 'split_date', split, 'confirm_cutoff', cutoff, 'config', cfg,
    'grid', (select jsonb_agg(jsonb_build_array(grid_id, batch, family, sub, source, metric, geo_kind, pre_n, post_n, lag_n, definitional, bh_weight) order by grid_id) from ripples.att_fx_grid where batch like p_batch || '/%'),
    'explore_events', (select jsonb_agg(jsonb_build_array(f.grid_id, f.event_id, f.onset, f.treated, f.magnitude) order by f.grid_id, f.event_id) from ripples.att_fx_event f join ripples.att_fx_grid g2 on g2.grid_id = f.grid_id where g2.batch like p_batch || '/%' and f.role = 'explore'),
    'confirm_candidates', conf, 'confirm_hashes', hashes, 'forward_candidates', fwd, 'n_excluded_regime', regs, 'panel_extents', ext,
    'prior_exposure', (select jsonb_object_agg(g3.grid_id::text, 'full_sample_seen:' || g6.ledger_seq) from ripples.att_fx_grid g3 join ripples.att_fx_grid g6
                         on g6.batch = (cfg ->> 'prior_exposure_batch') and g6.family = g3.family and coalesce(g6.sub, '') = coalesce(g3.sub, '') and g6.source = g3.source and g6.metric = g3.metric and g6.geo_kind = g3.geo_kind and g6.ledger_seq is not null
                        where g3.batch like p_batch || '/%'));
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'fx_grid', 'method', cfg ->> 'method', 'stage', 'explore', 'batch', p_batch,
                                     'n_pairs', n_g, 'n_explore_events', n_x, 'n_confirm_candidates', n_c, 'n_forward_candidates', n_fwd, 'n_excluded_regime', n_reg, 'split_date', split, 'confirm_cutoff', cutoff, 'rule', cfg -> 'rule'), payload);
  update ripples.att_fx_grid set frozen_hash = h, frozen_at = now() where batch like p_batch || '/%';
  update ripples.att_fx63_batch set explore_seq = v_seq, explore_hash = h, confirm_hashes = hashes, forward_candidates = fwd, updated_at = now() where batch = p_batch;
  insert into ripples.att_fx63_kill_log(batch, grid_id, family, attack, evidence, ledger_seq)
    select p_batch, (k.key)::int, null, 'regime', jsonb_build_object('n_excluded', k.value::int, 'range', cfg -> 'regime_exclusions'), v_seq from jsonb_each_text(regs) k where k.value::int > 0;
  return jsonb_build_object('batch', p_batch, 'n_pairs', n_g, 'n_explore_events', n_x, 'n_confirm_candidates', n_c, 'n_forward', n_fwd, 'n_excluded_regime', n_reg, 'seq', v_seq, 'hash', h);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_freeze_single(p_batch text, p_family text, p_pairs jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb := ripples._att_cfg('engine63'); s jsonb; g record; e record; tr text[]; n_x int := 0; n_g int := 0; payload jsonb; h text; v_seq bigint; pan record; ext jsonb;
begin
  if exists (select 1 from ripples.att_fx63_batch where batch = p_batch and explore_seq is not null) then return jsonb_build_object('batch', p_batch, 'already_frozen', true); end if;
  select jsonb_object_agg(source || ':' || metric || ':' || geo_kind, jsonb_build_object('from', days[1], 'to', days[n], 'regions', to_jsonb(regions), 'n', n, 'grain', grain)) into ext from ripples.att_fx_panel;
  insert into ripples.att_fx63_batch(batch, split_date, cfg, status, panel_extents, note) values (p_batch, '2100-01-01', cfg, 'single-sample', ext, 'single-sample pre-registered test: no held-out half (N too small)')
  on conflict (batch) do nothing;
  for s in select * from jsonb_array_elements(p_pairs) loop
    continue when not exists (select 1 from ripples.att_fx_panel p where p.source = s ->> 'source' and p.metric = s ->> 'metric' and p.geo_kind = s ->> 'geo_kind');
    insert into ripples.att_fx_grid(batch, family, sub, source, metric, geo_kind, pre_n, post_n, lag_n, expected_sign, synth, definitional, domain_event, domain_outcome, target_map, bh_weight, label, status)
    values (p_batch || '/single', p_family, null, s ->> 'source', s ->> 'metric', s ->> 'geo_kind', (s ->> 'pre')::int, (s ->> 'post')::int, (s ->> 'lag')::int, coalesce((s ->> 'sign')::int, 0), false, false,
            s ->> 'de', s ->> 'do', null, 1, p_family || ' → ' || (s ->> 'source') || ':' || (s ->> 'metric') || ' [single-sample]', 'fx63')
    on conflict do nothing;
    n_g := n_g + 1;
  end loop;
  for g in select * from ripples.att_fx_grid where batch = p_batch || '/single' order by grid_id loop
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    for e in select ev.event_id, ev.onset, ev.magnitude from ripples.att_events ev where ev.family = g.family and ev.role = 'library' and ev.onset between pan.days[1] and pan.days[pan.n] order by ev.onset loop
      tr := ripples.att_fx_treated(e.event_id, g.geo_kind, g.target_map);
      select coalesce(array_agg(x order by x), '{}') into tr from unnest(tr) x where x = any(pan.regions);
      continue when cardinality(tr) = 0;
      insert into ripples.att_fx_event(grid_id, event_id, role, decoy_set, onset, treated, magnitude) values (g.grid_id, e.event_id, 'explore', 0, e.onset, tr, e.magnitude) on conflict do nothing;
      n_x := n_x + 1;
    end loop;
  end loop;
  payload := jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'single', 'batch', p_batch, 'family', p_family, 'config', cfg, 'pairs', p_pairs,
    'grid', (select jsonb_agg(jsonb_build_array(grid_id, family, source, metric, geo_kind, pre_n, post_n, lag_n, expected_sign) order by grid_id) from ripples.att_fx_grid where batch = p_batch || '/single'),
    'events', (select jsonb_agg(jsonb_build_array(f.grid_id, f.event_id, f.onset, f.treated, f.magnitude) order by f.grid_id, f.event_id) from ripples.att_fx_event f join ripples.att_fx_grid g2 on g2.grid_id = f.grid_id where g2.batch = p_batch || '/single' and f.role = 'explore'),
    'panel_extents', ext);
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  v_seq := ripples.att_ledger_append(current_date, 'freeze', jsonb_build_object('object', 'fx_grid', 'method', '6.3', 'stage', 'single', 'batch', p_batch, 'family', p_family, 'n_pairs', n_g, 'n_events', n_x), payload);
  update ripples.att_fx_grid set frozen_hash = h, frozen_at = now() where batch = p_batch || '/single';
  update ripples.att_fx63_batch set explore_seq = v_seq, explore_hash = h, updated_at = now() where batch = p_batch;
  return jsonb_build_object('batch', p_batch, 'n_pairs', n_g, 'n_events', n_x, 'seq', v_seq);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_gd(p_grain text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$ select case p_grain when 'week' then 7 when 'month' then 30 else 1 end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_grant_audit_install()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare def text; n int; anchor text := $a$'rm_patterns','rm_hop_fx62',$a$; hook text := $a$'rm_patterns','rm_hop_fx62','rm_patterns63','rm_hunches',$a$;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace where n2.nspname = 'ripples' and p.proname = 'rm_grant_audit';
  if position('rm_patterns63' in def) > 0 then return jsonb_build_object('installed', true, 'already', true); end if;
  n := (length(def) - length(replace(def, anchor, ''))) / length(anchor);
  if n <> 1 then return jsonb_build_object('installed', false, 'reason', 'anchor count ' || n); end if;
  execute replace(def, anchor, hook);
  return jsonb_build_object('installed', true, 'already', false);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_grid_spec()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$ select ripples.att_fx63_grid_spec('b1') $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_grid_spec(p_set text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  with fam as (select * from (values
      ('hazard.storm', null::text, true), ('hazard.storm', 'hurricane', true), ('hazard.heat', null, false), ('hazard.cold', null, true),
      ('hazard.flood', null, true), ('hazard.wildfire', null, true), ('hazard.quake', null, true)) f(family, sub, fema_defined)),
  pan as (select * from (values
      ('b1', 'dol.claims', 'ic', 'state', 'labor', '[[8,4,0,"immediate"],[8,4,4,"delayed"]]'::jsonb),
      ('b1', 'dol.claims', 'cw', 'state', 'labor', '[[8,4,1,"immediate"],[8,4,5,"delayed"]]'),
      ('b1', 'census.bfs', 'ba', 'state', 'business', '[[8,4,0,"immediate"],[8,4,4,"delayed"]]'),
      ('b1', 'eia.930', 'demand', 'ba', 'power', '[[28,7,0,"immediate"],[28,14,7,"delayed"]]'),
      ('b1', 'eia.930', 'demand_w', 'ba', 'power', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('b1', 'fema.decl', 'n_w', 'state', 'government', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('b1', 'fred.state', 'leih_m', 'state', 'labor', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('b1', 'fred.state', 'cons_m', 'state', 'labor', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('b1', 'fred.state', 'ur_m', 'state', 'labor', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('b1', 'fred.state', 'bppriv_m', 'state', 'housing', '[[12,2,0,"immediate"],[12,3,2,"delayed"]]'),
      ('b2', 'eia.930', 'ng_solar_w', 'ba', 'power', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('b2', 'eia.930', 'ng_wind_w', 'ba', 'power', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]'),
      ('b2', 'eia.930', 'sub_demand_w', 'sub', 'power', '[[8,2,0,"immediate"],[8,4,2,"delayed"]]')) p(pset, source, metric, geo_kind, dom, variants))
  select jsonb_agg(jsonb_build_object('family', f.family, 'sub', f.sub, 'source', p.source, 'metric', p.metric, 'geo_kind', p.geo_kind,
                                      'de', 'hazard', 'do', p.dom, 'variants', p.variants,
                                      'definitional', (p.source = 'fema.decl' and f.fema_defined),
                                      'w', case when p.source = 'fema.decl' and f.fema_defined then 0 else 1 end)
                   order by f.family, f.sub nulls first, p.source, p.metric)
  from fam f cross join pan p where p.pset = p_set and (p_set <> 'b2' or f.family <> 'hazard.quake')
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_hook_install()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_minwage_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare excl text[] := array['DC', 'OR', 'NV', 'FL', 'CT', 'DE', 'IL', 'VA', 'RI', 'MN', 'HI', 'AK', 'MD', 'MI'];
        y int; r record; states text[]; incs float8[]; n_ev int := 0; v_topic bigint; lbl text; key text; mag real; out jsonb := '[]'::jsonb;
begin
  for y in 2016..extract(year from current_date)::int loop
    select array_agg(x.st order by x.st), array_agg(x.inc order by x.st) into states, incs
      from (select substr(s.geo, 4, 2) as st, (cur.value - prev.value) / nullif(prev.value, 0) as inc
              from ripples.att_series s
              join ripples.attention_obs cur on cur.series_id = s.series_id and cur.day = make_date(y, 1, 1)
              join ripples.attention_obs prev on prev.series_id = s.series_id and prev.day = make_date(y - 1, 1, 1)
             where s.source = 'fred.state' and s.metric = 'minwage' and s.geo ~ '^US-[A-Z]{2}$'
               and cur.value >= prev.value + 0.05 and substr(s.geo, 4, 2) <> all(excl)) x;
    continue when states is null or cardinality(states) < 2;
    lbl := 'State minimum-wage increases, ' || y || '-01-01 (' || cardinality(states) || ' states)';
    key := 'lib:minwage-' || y;
    select percentile_cont(0.5) within group (order by v) into mag from unnest(incs) v;
    insert into ripples.att_topics(qid, label_key, label, title_en, lang, category, status, in_panel, origin, meta)
    values (null, key, lbl, lbl, 'en', 'policy', 'dormant', false, 'manual',
            jsonb_build_object('state', to_jsonb(states), 'family', 'policy.min_wage', 'library', true, 'defined_by', jsonb_build_array('fred.state'),
                               'lib_source', 'FRED STTMINWG<ST> (U.S. Department of Labor, state minimum wage as of January 1)', 'lib_ref', 'minwage-' || y,
                               'excluded_non_jan1_states', to_jsonb(excl), 'median_increase', mag))
    on conflict (label_key) do update set meta = excluded.meta, label = excluded.label returning topic_id into v_topic;
    insert into ripples.att_events(as_of, topic_id, qid, label, family, role, onset, magnitude, sensitive, slug, reconstructed, status)
    values (make_date(y, 1, 2), v_topic, null, lbl, 'policy.min_wage', 'library', make_date(y, 1, 1), mag, false, 'lib-minwage-' || y, true, 'ended')
    on conflict (slug) do update set magnitude = excluded.magnitude, label = excluded.label;
    n_ev := n_ev + 1;
    out := out || jsonb_build_object('year', y, 'n_states', cardinality(states), 'median_increase', round(mag::numeric, 3));
  end loop;
  return jsonb_build_object('n_events', n_ev, 'events', out, 'excluded_states', to_jsonb(excl));
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_model_version_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare payload jsonb; h text; existing bigint; v_seq bigint;
begin
  payload := jsonb_build_object('method', '6.3', 'object', 'engine63', 'engine63_config', ripples._att_cfg('engine63'), 'grid_spec', ripples.att_fx63_grid_spec(),
                                'panel_spec', ripples.att_fx63_panel_spec(), 'base', ripples._att_cfg('engine62') ->> 'method',
                                'tier_rule', 'none: 6.3 publishes confirmed patterns (held-out replication, BH over the confirmation set) and hunches; att_finalize / att_fx_hook / att_ce_gate untouched; a confirmed pattern never changes an event tier',
                                'selection_rule', 'exploration (onset < split_date): n >= x_n_min, placebo p <= x_p_max, |d| >= threshold, one variant per pair (smaller p, tie shorter window), cap k_cap by p; confirmation (onset >= split_date): full 6.2 config, sign = exploration sign, BH over the confirmation set only');
  h := encode(extensions.digest(ripples._canon(payload)::text, 'sha256'), 'hex');
  select seq into existing from ripples.att_ledger where kind = 'model_version' and payload_hash = h limit 1;
  if existing is not null then return jsonb_build_object('seq', existing, 'hash', h, 'new', false); end if;
  v_seq := ripples.att_ledger_append(current_date, 'model_version', jsonb_build_object('method', '6.3', 'object', 'engine63'), payload);
  return jsonb_build_object('seq', v_seq, 'hash', h, 'new', true);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_outcome_label(p_source text, p_metric text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_source || ':' || p_metric
    when 'fema.decl:n_w' then 'FEMA disaster declarations in the state (weekly)'
    when 'eia.930:demand_w' then 'regional grid electricity demand (weekly)'
    when 'eia.930:ng_solar_w' then 'regional grid solar generation (weekly)'
    when 'eia.930:ng_wind_w' then 'regional grid wind generation (weekly)'
    when 'eia.930:sub_demand_w' then 'grid sub-region electricity demand (weekly)'
    when 'fred.state:leih_m' then 'state leisure & hospitality employment'
    when 'fred.state:cons_m' then 'state construction employment'
    when 'fred.state:ur_m' then 'state unemployment rate'
    when 'fred.state:bppriv_m' then 'state private housing permits'
    else ripples.att_fx_outcome_label(p_source, p_metric) end
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_panel_build(p_source text, p_metric text, p_geo_kind text, p_agg text, p_value_kind text DEFAULT NULL::text, p_weekly boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_from date := '2015-01-01'; v_to date := current_date; vk text; out_metric text; grain text; days date[]; regs text[]; n int; nr int;
        ps float8[] := '{}'; pc int2[] := '{}'; r record; i int; acc float8; cnt int; v float8[]; ps_r float8[]; pc_r int2[];
begin
  if p_agg not in ('week', 'month') then return jsonb_build_object('error', 'p_agg must be week or month'); end if;
  out_metric := p_metric || case p_agg when 'week' then '_w' else '_m' end;
  create temp table _fxs63 on commit drop as
    select case when p_geo_kind = 'state' then s.geo else s.key end as region, s.series_id from ripples.att_series s
    where s.source = p_source and s.metric = p_metric
      and case p_geo_kind when 'state' then s.geo ~ '^US-[A-Z]{2}$' when 'ba' then s.key !~ '^(US48|__total__|all)$' and s.key !~ ':' else true end;
  if not exists (select 1 from _fxs63) then drop table _fxs63; return jsonb_build_object('error', 'no series'); end if;
  vk := coalesce(p_value_kind, (select z.value_kind from ripples.att_zvec z join _fxs63 f on f.series_id = z.series_id where z.value_kind is not null limit 1),
                 (select so.value_kind from ripples.att_sources so where so.source = p_source), 'count');
  if vk not in ('rate', 'count', 'level') then vk := 'level'; end if;
  create temp table _fxr63 on commit drop as
    select f.region, o.day, avg(o.value) as y from _fxs63 f join lateral (select * from ripples.att_series_daily(f.series_id, v_from, v_to)) o on true where o.value is not null group by 1, 2;
  if p_agg = 'week' then
    create temp table _fxo63 on commit drop as
      select region, (date_trunc('week', (day + 1)::timestamp)::date + 5) as day,
             case when vk = 'rate' then avg(y) when vk = 'count' then ln(1 + greatest(sum(y), 0)) else ln(1 + greatest(avg(y), 0)) end as y
      from _fxr63 group by 1, 2 having count(*) >= case when p_weekly then 1 else 4 end;
    grain := 'week';
  else
    create temp table _fxo63 on commit drop as
      select region, (date_trunc('month', day::timestamp)::date + 11) as day, case when vk = 'rate' then avg(y) else ln(1 + greatest(avg(y), 0)) end as y from _fxr63 group by 1, 2;
    grain := 'month';
  end if;
  select array_agg(d order by d) into days from (select distinct day d from _fxo63) x; n := cardinality(days);
  select array_agg(region order by region) into regs from (select distinct region from _fxo63) x; nr := cardinality(regs);
  create temp table _fxd63 on commit drop as select d, ord::int as idx from unnest(days) with ordinality u(d, ord);
  create index on _fxd63(d);
  for r in select region from unnest(regs) region order by region loop
    select array_agg(o.y order by dd.idx) into v from _fxd63 dd left join _fxo63 o on o.day = dd.d and o.region = r.region;
    acc := 0; cnt := 0; ps_r := array_fill(0::float8, array[n]); pc_r := array_fill(0::int2, array[n]);
    for i in 1..n loop if v[i] is not null then acc := acc + v[i]; cnt := cnt + 1; end if; ps_r[i] := acc; pc_r[i] := cnt; end loop;
    if cardinality(ps) = 0 then ps := array[ps_r]; pc := array[pc_r]; else ps := ps || ps_r; pc := pc || pc_r; end if;
  end loop;
  insert into ripples.att_fx_panel(source, metric, geo_kind, grain, value_kind, days, regions, n, ps, pc, built_at)
  values (p_source, out_metric, p_geo_kind, grain, vk, days, regs, n, ps, pc, now())
  on conflict (source, metric, geo_kind) do update set grain = excluded.grain, value_kind = excluded.value_kind, days = excluded.days, regions = excluded.regions, n = excluded.n, ps = excluded.ps, pc = excluded.pc, built_at = now();
  drop table _fxs63; drop table _fxr63; drop table _fxo63; drop table _fxd63;
  return jsonb_build_object('source', p_source, 'metric', out_metric, 'geo_kind', p_geo_kind, 'grain', grain, 'value_kind', vk, 'n', n, 'regions', nr, 'from', days[1], 'to', days[n]);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_panel_refresh()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s jsonb; out jsonb := '[]'::jsonb;
begin
  for s in select * from jsonb_array_elements(ripples.att_fx63_panel_spec()) loop
    out := out || ripples.att_fx63_panel_build(s ->> 'source', s ->> 'metric', s ->> 'geo_kind', s ->> 'agg', s ->> 'value_kind', coalesce((s ->> 'weekly')::boolean, false));
  end loop;
  return out;
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_panel_spec()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select '[
    {"source":"fema.decl","metric":"n","geo_kind":"state","agg":"week","value_kind":"count"},
    {"source":"eia.930","metric":"demand","geo_kind":"ba","agg":"week","value_kind":"level"},
    {"source":"eia.930","metric":"ng_solar","geo_kind":"ba","agg":"week","value_kind":"level","weekly":true},
    {"source":"eia.930","metric":"ng_wind","geo_kind":"ba","agg":"week","value_kind":"level","weekly":true},
    {"source":"eia.930","metric":"sub_demand","geo_kind":"sub","agg":"week","value_kind":"level","weekly":true},
    {"source":"fred.state","metric":"leih","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"cons","geo_kind":"state","agg":"month","value_kind":"level"},
    {"source":"fred.state","metric":"ur","geo_kind":"state","agg":"month","value_kind":"rate"},
    {"source":"fred.state","metric":"bppriv","geo_kind":"state","agg":"month","value_kind":"count"}
  ]'::jsonb
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_pool_hook_install()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare def text; n int; anchor text := $a$    if abs(rr[1]) >= abs(dp) then n_ge := n_ge + 1; end if;$a$;
        hook text := $a$    -- ENGINE 6.3.3 (32_att_engine_63): studentised placebo pool for the 6.3 roles only; 6.2 roles unchanged
    if (case when p_role in ('explore', 'dx', 'confirm', 'dc') and coalesce((ripples._att_cfg('engine63') ->> 'studentised_pool')::boolean, false)
             then abs(rr[1] / greatest(rr[2], 1e-12)) >= abs(dp / greatest(sp, 1e-12)) else abs(rr[1]) >= abs(dp) end) then n_ge := n_ge + 1; end if;$a$;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace where n2.nspname = 'ripples' and p.proname = 'att_fx_pool_run';
  if position('ENGINE 6.3.3 (32_att_engine_63)' in def) > 0 then return jsonb_build_object('installed', true, 'already', true); end if;
  n := (length(def) - length(replace(def, anchor, ''))) / length(anchor);
  if n <> 1 then return jsonb_build_object('installed', false, 'reason', 'anchor count ' || n); end if;
  execute replace(def, anchor, hook);
  return jsonb_build_object('installed', true, 'already', false);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_power_curve(p_source text, p_metric text, p_geo_kind text, p_pre integer, p_post integer, p_lag integer, p_deltas double precision[] DEFAULT ARRAY[(0)::numeric, 0.01, 0.02, 0.03, 0.05, 0.10], p_k integer DEFAULT 12, p_reps integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare pan record; cfg jsonb := ripples._att_cfg('engine63') -> 'confirm'; delta float8; rep int; k int; r int; i0 int; t int; ps float8[]; pc int2[];
        j jsonb; dc float8[]; se float8[]; dl float8[]; p_norm float8; n_det int; n_ev_det int; n_ev int; out jsonb := '[]'::jsonb; nr int; n int; span int;
        min_start int; max_start int; rnd float8; row_ps float8[];
begin
  select * into pan from ripples.att_fx_panel p where p.source = p_source and p.metric = p_metric and p.geo_kind = p_geo_kind;
  if not found then return jsonb_build_object('error', 'no panel'); end if;
  nr := cardinality(pan.regions); n := pan.n; span := p_pre + 3 * p_post + 2; min_start := span + 200; max_start := n - p_lag - p_post - 60;
  foreach delta in array p_deltas loop
    n_det := 0; n_ev_det := 0; n_ev := 0;
    for rep in 1..p_reps loop
      perform setseed(((hashtext('power:' || p_source || p_metric || delta || rep) % 100000) / 100000.0)::float8);
      dc := '{}'; se := '{}';
      for k in 1..p_k loop
        r := 1 + floor(random() * nr)::int; i0 := min_start + floor(random() * greatest(1, max_start - min_start))::int;
        ps := pan.ps; pc := pan.pc;
        -- plant delta into region r over [i0 + lag, i0 + lag + post): prefix sums shift by delta·(t − start + 1) inside, by delta·post after (one slice assignment)
        row_ps := array(select pan.ps[r][tt] + case when tt >= i0 + p_lag then delta * least(tt - (i0 + p_lag) + 1, p_post) else 0 end from generate_series(1, n) tt);
        ps[r:r][1:n] := array[row_ps];
        j := ripples.att_fx_calc(ps, pc, pan.days, pan.regions, pan.grain, array[pan.regions[r]], pan.days[i0], p_pre, p_post, p_lag, false, random() * 2 - 1, cfg);
        continue when j ->> 'se' is null;
        n_ev := n_ev + 1;
        dc := dc || ((j ->> 'd')::float8 - (j ->> 'med')::float8); se := se || (j ->> 'se')::float8;
        if (j ->> 'p_time')::float8 <= 0.05 then n_ev_det := n_ev_det + 1; end if;
      end loop;
      continue when cardinality(dc) < 2;
      dl := ripples.att_fx_dl(dc, se);
      p_norm := 2 * (1 - ripples.att_norm_cdf(abs(dl[1] / dl[2])));
      if p_norm <= 0.05 and (delta = 0 or sign(dl[1]) = sign(delta)) then n_det := n_det + 1; end if;
    end loop;
    out := out || jsonb_build_object('delta_logpts', delta, 'family_power_pnorm05', round(n_det::numeric / p_reps, 2), 'event_power_ptime05', case when n_ev > 0 then round(n_ev_det::numeric / n_ev, 2) end, 'k', p_k, 'reps', p_reps);
  end loop;
  return jsonb_build_object('panel', p_source || ':' || p_metric || ':' || p_geo_kind, 'window', jsonb_build_object('pre', p_pre, 'post', p_post, 'lag', p_lag), 'curve', out);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_regime_ok(p_onset date, p_pre integer, p_post integer, p_lag integer, p_grain text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select not exists (select 1 from jsonb_array_elements(coalesce(ripples._att_cfg('engine63') -> 'regime_exclusions', '[]'::jsonb)) x
                      where daterange(p_onset - p_pre * ripples.att_fx63_gd(p_grain), p_onset + (p_lag + p_post) * ripples.att_fx63_gd(p_grain), '[]')
                         && daterange((x ->> 'from')::date, (x ->> 'to')::date, '[]'))
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_repeatability(p_grid integer, p_role text, p_sign integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare dc float8[]; se float8[]; ons date[]; k int; i int; r float8[]; z_loo_min float8 := 1e9; share float8; z_early float8; z_late float8; score int := 0; dc2 float8[]; se2 float8[]; h int;
begin
  select array_agg((f.d - f.med)::float8 order by f.onset), array_agg(f.se::float8 order by f.onset), array_agg(f.onset order by f.onset), count(*)
    into dc, se, ons, k from ripples.att_fx_event f where f.grid_id = p_grid and f.role = p_role and f.decoy_set = 0 and f.se is not null and f.med is not null
     and not exists (select 1 from ripples.att_fx_cluster_dups(p_grid, p_role, 0) d where d.event_id = f.event_id);
  if k < 4 then return jsonb_build_object('score', null, 'note', 'fewer than 4 events'); end if;
  select avg((sign(x) = p_sign)::int) into share from unnest(dc) x;
  for i in 1..k loop
    dc2 := dc[1:i-1] || dc[i+1:k]; se2 := se[1:i-1] || se[i+1:k];
    r := ripples.att_fx_dl(dc2, se2); z_loo_min := least(z_loo_min, p_sign * r[1] / greatest(r[2], 1e-12));
  end loop;
  h := k / 2;
  r := ripples.att_fx_dl(dc[1:h], se[1:h]); z_early := p_sign * r[1] / greatest(r[2], 1e-12);
  r := ripples.att_fx_dl(dc[h+1:k], se[h+1:k]); z_late := p_sign * r[1] / greatest(r[2], 1e-12);
  score := (share >= 0.6)::int + (z_loo_min >= 1.96)::int + (z_early >= 1 and z_late >= 1)::int;
  return jsonb_build_object('score', score, 'n', k, 'share_expected_sign', round(share::numeric, 2), 'loo_min_z', round(z_loo_min::numeric, 2), 'z_early', round(z_early::numeric, 2), 'z_late', round(z_late::numeric, 2),
                            'label', case score when 3 then 'rock solid' when 2 then 'solid' when 1 then 'fragile' else 'very fragile' end);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_sample_events(p_grid integer, p_role text, p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('label', coalesce(ripples.rm_label_resolve(e.qid, e.label), e.label), 'onset', f.onset,
                                               'effect', case when pn.value_kind = 'rate' then round((f.d - f.med)::numeric, 2) else round((100 * (exp(f.d - f.med) - 1))::numeric, 1) end,
                                               'z', round(f.z::numeric, 2), 'p_space', f.p_space, 'stone', ripples.att_fx_shock_norm(e.event_id), 'quiet', coalesce(e.sensitive, false))
                            order by abs(f.z) desc), '[]'::jsonb)
    from (select f0.* from ripples.att_fx_event f0 where f0.grid_id = p_grid and f0.role = p_role and f0.decoy_set = 0 and f0.z is not null
            and not exists (select 1 from ripples.att_fx_cluster_dups(p_grid, p_role, 0) d where d.event_id = f0.event_id) order by abs(f0.z) desc limit p_limit) f
    join ripples.att_events e on e.event_id = f.event_id
    join ripples.att_fx_grid g on g.grid_id = p_grid
    left join ripples.att_fx_panel pn on pn.source = g.source and pn.metric = g.metric and pn.geo_kind = g.geo_kind
   where not ripples.att_story_off_limits(e.event_id)
$function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_select_run(p_batch text, p_set integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb := ripples._att_cfg('engine63'); rule jsonb := cfg -> 'rule'; v_role text := case when p_set = 0 then 'explore' else 'dx' end;
        x_n_min int := (rule ->> 'x_n_min')::int; x_p_max float8 := (rule ->> 'x_p_max')::float8; thr_log float8 := (rule ->> 'x_abs_min_log')::float8;
        thr_raw float8 := (rule ->> 'x_abs_min_raw')::float8; k_cap int := (rule ->> 'k_cap')::int; x_pn_max float8 := coalesce((rule ->> 'x_pnorm_max')::float8, 1);
        shrink float8 := coalesce((cfg ->> 'winners_curse_shrink')::float8, 0.6); n_sel int; n_chk int; n_cand int; pe_batch text := cfg ->> 'prior_exposure_batch'; ceil_ jsonb := cfg -> 'mde_ceilings';
begin
  create temp table _fx63sel on commit drop as
  with pools as (
    select g.grid_id, g.family, coalesce(g.sub, '') as sub, g.source, coalesce(cfg -> 'outcome_concepts' ->> g.metric, g.metric) as concept, g.metric, g.geo_kind, g.post_n, g.lag_n, g.bh_weight, g.domain_event, g.domain_outcome,
           pn.value_kind, p.n_events, p.d, p.se, p.p_placebo, p.p_norm, coalesce(p.tau2, 0) as tau2, case when pn.value_kind = 'rate' then thr_raw else thr_log end as thr,
           case when pn.value_kind = 'rate' then (ceil_ ->> 'rate')::float8 else coalesce((ceil_ ->> g.domain_outcome)::float8, 0.03) end as ceiling,
           (select 'full_sample_seen:' || g6.ledger_seq from ripples.att_fx_grid g6 where g6.batch = pe_batch and g6.family = g.family and coalesce(g6.sub, '') = coalesce(g.sub, '') and g6.source = g.source and g6.metric = g.metric and g6.geo_kind = g.geo_kind and g6.ledger_seq is not null limit 1) as prior_exposure,
           (select percentile_cont(0.5) within group (order by f.se * f.se) from ripples.att_fx_event f where f.grid_id = g.grid_id and f.role = v_role and f.decoy_set = p_set and f.se is not null) as se2_ev,
           (select count(*) from ripples.att_fx63_confirm_events(g.grid_id)) as n_cc
      from ripples.att_fx_grid g join ripples.att_fx_panel pn on pn.source = g.source and pn.metric = g.metric and pn.geo_kind = g.geo_kind
      left join ripples.att_fx_pool p on p.grid_id = g.grid_id and p.role = v_role and p.decoy_set = p_set
     where g.batch like p_batch || '/%'),
  ok0 as (select *, sqrt(se2_ev + tau2) / sqrt(greatest(n_cc, 1)) as se_exp from pools),
  ok as (select *, 2.8 * se_exp as mde, coalesce(n_events >= x_n_min and p_placebo <= x_p_max and p_norm <= x_pn_max and abs(d) >= thr, false) as x_ok,
                   coalesce(2.8 * se_exp <= ceiling, false) as powered from ok0),
  best as (select *, row_number() over (partition by family, sub, source, concept, geo_kind order by (not (x_ok and powered)), (not x_ok), p_placebo nulls last, post_n + lag_n, grid_id) = 1 as variant_best from ok),
  ranked as (select *, case when x_ok and powered and variant_best and bh_weight > 0 then row_number() over (partition by (x_ok and powered and variant_best and bh_weight > 0) order by p_placebo, abs(d) desc, grid_id) end as rnk from best)
  select * from ranked;
  insert into ripples.att_fx63_select(batch, grid_id, decoy_set, x_n, x_d, x_se, x_p, x_sign, x_ok, variant_best, rank, selected, reason, domain_distance, expected_by_mechanism, computed_at,
                                      prior_exposure, n_confirm_candidates, mde_80, power_at_x)
  select p_batch, r.grid_id, p_set, r.n_events, r.d, r.se, r.p_placebo, sign(r.d)::smallint, r.x_ok, r.variant_best, r.rnk,
         (r.x_ok and r.powered and r.variant_best and (r.bh_weight = 0 or r.rnk <= k_cap)),
         case when r.n_events is null then 'no exploration pool' when r.n_events < x_n_min then 'too few exploration events (' || r.n_events || ')'
              when r.p_placebo > x_p_max then 'exploration p above ' || x_p_max when r.p_norm > x_pn_max then 'normal-approximation p above ' || x_pn_max || ' (families disagree)'
              when abs(r.d) < r.thr then 'effect below threshold'
              when not r.powered then 'underpowered (MDE80 ' || round((100 * r.mde)::numeric, 1) || case when r.value_kind = 'rate' then ' pp' else '%' end || ' above the ' || round((100 * r.ceiling)::numeric, 1) || ' ceiling)'
              when not r.variant_best then 'other window variant / grain of the same outcome preferred'
              when r.bh_weight > 0 and r.rnk > k_cap then 'beyond the cap of ' || k_cap when r.bh_weight = 0 then 'selected (check)' else 'selected' end,
         ripples.att_fx63_domain_distance(r.domain_event, r.domain_outcome), ripples.att_fx63_expected_by_mechanism(r.family, r.source), now(),
         coalesce(r.prior_exposure, 'none'), r.n_cc, r.mde,
         case when r.se_exp is null or r.se_exp <= 0 then null else ripples.att_norm_cdf(abs(shrink * r.d) / r.se_exp - 1.96) end
    from _fx63sel r
  on conflict (batch, grid_id, decoy_set) do update set x_n = excluded.x_n, x_d = excluded.x_d, x_se = excluded.x_se, x_p = excluded.x_p, x_sign = excluded.x_sign,
    x_ok = excluded.x_ok, variant_best = excluded.variant_best, rank = excluded.rank, selected = excluded.selected, reason = excluded.reason,
    domain_distance = excluded.domain_distance, expected_by_mechanism = excluded.expected_by_mechanism, computed_at = now(),
    prior_exposure = excluded.prior_exposure, n_confirm_candidates = excluded.n_confirm_candidates, mde_80 = excluded.mde_80, power_at_x = excluded.power_at_x;
  if p_set = 0 then
    insert into ripples.att_fx63_kill_log(batch, grid_id, family, attack, evidence)
      select p_batch, r.grid_id, r.family, 'underpowered', jsonb_build_object('mde_80', r.mde, 'ceiling', r.ceiling, 'n_confirm_candidates', r.n_cc, 'x_ok', r.x_ok) from _fx63sel r
       where r.x_ok and not r.powered and not exists (select 1 from ripples.att_fx63_kill_log k where k.batch = p_batch and k.grid_id = r.grid_id and k.attack = 'underpowered');
  end if;
  select count(*) filter (where selected and bh_weight > 0), count(*) filter (where selected and bh_weight = 0), count(*) filter (where x_ok)
    into n_sel, n_chk, n_cand from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id where s.batch = p_batch and s.decoy_set = p_set;
  drop table _fx63sel;
  return jsonb_build_object('batch', p_batch, 'set', p_set, 'n_pairs', (select count(*) from ripples.att_fx63_select where batch = p_batch and decoy_set = p_set), 'n_candidates', n_cand, 'n_selected', n_sel, 'n_checks_selected', n_chk);
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_shrink(p_d double precision[], p_se double precision[])
 RETURNS TABLE(i integer, d_raw double precision, se_raw double precision, d_shrunk double precision, se_shrunk double precision, w_pool double precision)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare r float8[]; k int := cardinality(p_d); j int; tau2 float8; b float8;
begin
  if k = 0 then return; end if;
  r := ripples.att_fx_dl(p_d, p_se);
  tau2 := coalesce(r[3], 0);
  for j in 1..k loop
    b := p_se[j]^2 / (p_se[j]^2 + tau2);
    i := j; d_raw := p_d[j]; se_raw := p_se[j];
    d_shrunk := (1 - b) * p_d[j] + b * r[1];
    se_shrunk := sqrt(1 / (1 / greatest(p_se[j]^2, 1e-12) + 1 / greatest(tau2, 1e-12)));
    if tau2 <= 0 then se_shrunk := r[2]; end if;
    w_pool := b;
    return next;
  end loop;
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_slice(ps double precision[], pc smallint[], keep integer[], OUT ps2 double precision[], OUT pc2 smallint[])
 RETURNS record
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare i int; n int := array_length(ps, 2); first boolean := true;
begin
  foreach i in array keep loop
    if first then ps2 := ps[i:i][1:n]; pc2 := pc[i:i][1:n]; first := false; else ps2 := ps2 || ps[i:i][1:n]; pc2 := pc2 || pc[i:i][1:n]; end if;
  end loop;
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_step(p_budget_s integer DEFAULT 50, p_roles text[] DEFAULT ARRAY['explore'::text, 'dx'::text, 'confirm'::text, 'dc'::text])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t0 timestamptz := clock_timestamp(); cfg jsonb := ripples._att_cfg('engine63'); g record; pan record; e record; j jsonb; c jsonb;
        n_done int := 0; pooled int := 0; v_grid int; pr record; tried int[] := '{}'; n_dist int; mind int := coalesce((cfg ->> 'month_min_distinct')::int, 20);
        mask boolean := coalesce((cfg ->> 'clean_control_donors')::boolean, false); cont text[]; keep int[]; regs text[]; ps2 float8[]; pc2 int2[]; min_don int; i int; n_masked int; fam text; note_extra text;
begin
  loop
    select f.grid_id into v_grid from ripples.att_fx_event f join ripples.att_fx_grid gr on gr.grid_id = f.grid_id
     where gr.status = 'fx63' and f.computed_at is null and f.role = any(p_roles) and not (f.grid_id = any(tried)) order by (f.role in ('confirm', 'explore')) desc, f.grid_id limit 1;
    exit when v_grid is null;
    tried := tried || v_grid;
    continue when not pg_try_advisory_xact_lock(hashtext('fx63:' || v_grid));
    select * into g from ripples.att_fx_grid where grid_id = v_grid;
    select * into pan from ripples.att_fx_panel p where p.source = g.source and p.metric = g.metric and p.geo_kind = g.geo_kind;
    fam := g.family;
    for e in select * from ripples.att_fx_event f where f.grid_id = v_grid and f.computed_at is null and f.role = any(p_roles) order by (f.role in ('confirm', 'explore')) desc, f.role, f.decoy_set, f.event_id loop
      c := case when e.role in ('explore', 'dx') then cfg -> 'explore' else cfg -> 'confirm' end;
      if pan.grain = 'month' then c := c || jsonb_build_object('season_band', coalesce((cfg ->> 'month_band')::int, 45)); end if;
      min_don := coalesce((c ->> 'min_donors')::int, 5); note_extra := null;
      if mask then
        cont := ripples.att_fx63_contaminated(fam, g.geo_kind, e.onset, g.pre_n, g.post_n, g.lag_n, pan.grain, case when e.role in ('explore', 'confirm') then e.event_id else null end);
        cont := array(select x from unnest(cont) x where not (x = any(e.treated)));
        if cardinality(cont) > 0 then
          keep := array(select gs from generate_subscripts(pan.regions, 1) gs where not (pan.regions[gs] = any(cont)));
          if cardinality(keep) - cardinality(e.treated) >= min_don then
            select s.ps2, s.pc2 into ps2, pc2 from ripples.att_fx63_slice(pan.ps, pan.pc, keep) s;
            regs := array(select pan.regions[kk] from unnest(keep) kk order by kk);
            n_masked := cardinality(cont);
          else
            ps2 := pan.ps; pc2 := pan.pc; regs := pan.regions; n_masked := 0; note_extra := 'mask_fallback (' || cardinality(cont) || ' contaminated, too few clean donors)';
          end if;
        else ps2 := pan.ps; pc2 := pan.pc; regs := pan.regions; n_masked := 0; end if;
      else ps2 := pan.ps; pc2 := pan.pc; regs := pan.regions; n_masked := 0; end if;
      j := ripples.att_fx_calc(ps2, pc2, pan.days, regs, pan.grain, e.treated, e.onset, g.pre_n, g.post_n, g.lag_n, false,
                               ((hashtext(v_grid || ':' || e.event_id || ':' || e.role || ':' || e.decoy_set) % 100000) / 100000.0)::float8, c);
      if pan.grain = 'month' and j ? 'placebo_d' then
        select count(distinct round(x::numeric, 6)) into n_dist from jsonb_array_elements_text(j -> 'placebo_d') x;
        if n_dist < mind then j := j || jsonb_build_object('se', null, 'med', null, 'note', 'degenerate null (' || n_dist || ' distinct pseudo-onsets)'); end if;
      end if;
      update ripples.att_fx_event f set
        n_treated = (j ->> 'n_treated')::int, n_donors = (j ->> 'n_donors')::int, d = (j ->> 'd')::real, d_treated = (j ->> 'd_treated')::real,
        med = (j ->> 'med')::real, se = (j ->> 'se')::real, z = (j ->> 'z')::real, p_time = (j ->> 'p_time')::real, p_space = (j ->> 'p_space')::real,
        p_pre = (j ->> 'p_pre')::real, lead = (select array_agg(x::real) from jsonb_array_elements_text(coalesce(j -> 'lead', '[]'::jsonb)) x),
        placebo_d = (select array_agg(x::real) from jsonb_array_elements_text(coalesce(j -> 'placebo_d', '[]'::jsonb)) x),
        note = concat_ws('; ', j ->> 'note', note_extra, case when n_masked > 0 then 'masked ' || n_masked || ' contaminated donors' end), computed_at = now()
      where f.grid_id = e.grid_id and f.event_id = e.event_id and f.role = e.role and f.decoy_set = e.decoy_set;
      n_done := n_done + 1;
      exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s);
    end loop;
    exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s);
  end loop;
  for pr in select f.grid_id, f.role, f.decoy_set from ripples.att_fx_event f join ripples.att_fx_grid gr on gr.grid_id = f.grid_id
            where gr.status = 'fx63' and f.role = any(p_roles) group by 1, 2, 3 having bool_and(f.computed_at is not null)
            and not exists (select 1 from ripples.att_fx_pool p where p.grid_id = f.grid_id and p.role = f.role and p.decoy_set = f.decoy_set) loop
    continue when not pg_try_advisory_xact_lock(hashtext('fx63pool:' || pr.grid_id || ':' || pr.role || ':' || pr.decoy_set));
    perform ripples.att_fx_pool_run(pr.grid_id, pr.role, pr.decoy_set);
    if pr.role in ('dx', 'dc') then update ripples.att_fx_event set placebo_d = null, lead = null where grid_id = pr.grid_id and role = pr.role and decoy_set = pr.decoy_set; end if;
    pooled := pooled + 1;
    exit when clock_timestamp() - t0 > make_interval(secs => p_budget_s + 20);
  end loop;
  j := jsonb_build_object('at', now(), 'done', n_done, 'pooled', pooled, 'secs', round(extract(epoch from clock_timestamp() - t0)::numeric, 1),
                          'pending', (select count(*) from ripples.att_fx_event f join ripples.att_fx_grid gr on gr.grid_id = f.grid_id where gr.status = 'fx63' and f.computed_at is null));
  insert into ripples.att_state(k, v) values ('engine63.run', j) on conflict (k) do update set v = excluded.v, updated_at = now();
  return j;
end $function$
;
CREATE OR REPLACE FUNCTION ripples.att_fx63_verdict(p_batch text, p_set integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb := ripples._att_cfg('engine63'); rule jsonb := cfg -> 'rule'; v_role text := case when p_set = 0 then 'confirm' else 'dc' end;
        c_n_min int := (rule ->> 'c_n_min')::int; q_strong float8 := (rule ->> 'q_strong')::float8; q_pat float8 := (rule ->> 'q_pattern')::float8;
        pn_strong float8 := coalesce((rule ->> 'c_pnorm_max')::float8, 1); pn_weak float8 := coalesce((rule ->> 'c_pnorm_max_weaker')::float8, 1);
        shrink float8 := coalesce((cfg ->> 'winners_curse_shrink')::float8, 0.6); ids int[]; ps float8[]; qs float8[]; i int; n_conf int; n_weak int; n_sel int;
begin
  update ripples.att_fx63_select s set
    c_n = p.n_events, c_d = p.d, c_se = p.se, c_ci_lo = p.ci_lo, c_ci_hi = p.ci_hi, c_tau2 = p.tau2, c_i2 = p.i2, c_p = p.p_placebo, c_p_norm = p.p_norm,
    c_sign_ok = (sign(p.d) = s.x_sign), c_n_clustered_out = (p.payload ->> 'n_clustered_out')::int, c_n_regional_pass = (p.payload ->> 'n_regional_pass')::int, c_q = null, computed_at = now()
    from ripples.att_fx_pool p
   where p.grid_id = s.grid_id and p.role = v_role and (case when p_set = 0 then p.decoy_set = 0 else p.decoy_set = s.decoy_set end) and s.batch = p_batch and s.decoy_set = p_set and s.selected;
  select array_agg(s.grid_id order by s.grid_id), array_agg(coalesce(s.c_p, 1)::float8 order by s.grid_id) into ids, ps
    from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id
   where s.batch = p_batch and s.decoy_set = p_set and s.selected and g.bh_weight > 0 and s.c_n >= c_n_min;
  if ids is not null then
    qs := ripples.att_bh_q(ps, array_fill(1::float8, array[cardinality(ps)]));
    for i in 1..cardinality(ids) loop update ripples.att_fx63_select set c_q = qs[i] where batch = p_batch and decoy_set = p_set and grid_id = ids[i]; end loop;
  end if;
  update ripples.att_fx63_select s set
    verdict3 = case when not s.selected or s.c_n is null then null
                    when s.c_n < c_n_min or coalesce(s.power_at_x, 0) < 0.5 then 'inconclusive'
                    when g.bh_weight = 0 then case when s.c_p <= 0.05 and coalesce(s.c_p_norm, 1) <= 0.05 and s.c_sign_ok then 'replicated' else 'inconclusive' end
                    when coalesce(s.c_q, 1) <= q_strong and coalesce(s.c_p_norm, 1) <= pn_strong and s.c_sign_ok then 'replicated'
                    when coalesce(s.c_q, 1) <= q_pat and coalesce(s.c_p_norm, 1) <= pn_weak and s.c_sign_ok then 'replicated (weaker)'
                    when s.c_p <= 0.05 and coalesce(s.c_p_norm, 1) <= 0.05 and not s.c_sign_ok then 'contradicted'
                    when s.c_ci_lo <= 0 and s.c_ci_hi >= 0 and not (shrink * s.x_d between s.c_ci_lo and s.c_ci_hi) then 'contradicted'
                    else 'inconclusive' end
    from ripples.att_fx_grid g where g.grid_id = s.grid_id and s.batch = p_batch and s.decoy_set = p_set;
  update ripples.att_fx63_select s set
    verdict = case when not s.selected then case when s.x_ok then 'not tested (' || s.reason || ')' else 'not a candidate' end
                   when s.c_n is null then 'confirmation pending'
                   when g.bh_weight = 0 then case when s.verdict3 = 'replicated' then 'check passed' else 'check inconclusive' end
                   when s.verdict3 = 'replicated' then case when s.prior_exposure = 'none' then 'confirmed' else 'consistent across both halves' end
                   when s.verdict3 = 'replicated (weaker)' then case when s.prior_exposure = 'none' then 'confirmed (weaker)' else 'consistent across both halves (weaker)' end
                   when s.verdict3 = 'contradicted' then 'contradicted' else 'inconclusive' end,
    strength = case when not s.selected then case when s.x_ok then 'hunch' else null end
                    when s.c_n is null then 'hunch'
                    when g.bh_weight = 0 then case when s.verdict3 = 'replicated' then 'check passed' else 'check inconclusive' end
                    when s.verdict3 = 'replicated' then case when s.prior_exposure = 'none' then 'confirmed pattern' else 'consistent pattern' end
                    when s.verdict3 = 'replicated (weaker)' then case when s.prior_exposure = 'none' then 'confirmed pattern (weaker)' else 'consistent pattern (weaker)' end
                    else 'hunch' end,
    rung = case when not s.selected then case when s.x_ok then 'hunch' else null end
                when s.c_n is null then 'hunch' when g.bh_weight = 0 then 'check'
                when s.verdict3 = 'replicated' then case when s.prior_exposure = 'none' then 'pattern' else 'consistent' end
                when s.verdict3 = 'replicated (weaker)' then case when s.prior_exposure = 'none' then 'pattern_weaker' else 'consistent' end
                else 'hunch' end
    from ripples.att_fx_grid g where g.grid_id = s.grid_id and s.batch = p_batch and s.decoy_set = p_set;
  if p_set = 0 then
    insert into ripples.att_fx63_kill_log(batch, grid_id, family, attack, evidence)
      select p_batch, s.grid_id, g.family, case when s.verdict3 = 'contradicted' then 'contradicted_held_out' when s.verdict3 = 'inconclusive' and coalesce(s.power_at_x, 0) < 0.5 then 'underpowered' when s.prior_exposure <> 'none' then 'prior_exposure' end,
             jsonb_build_object('x_d', s.x_d, 'x_p', s.x_p, 'c_n', s.c_n, 'c_d', s.c_d, 'c_ci', jsonb_build_array(s.c_ci_lo, s.c_ci_hi), 'mde_80', s.mde_80, 'power_at_x', s.power_at_x, 'prior_exposure', s.prior_exposure)
        from ripples.att_fx63_select s join ripples.att_fx_grid g on g.grid_id = s.grid_id where s.batch = p_batch and s.decoy_set = 0 and s.selected
         and (s.verdict3 = 'contradicted' or (s.verdict3 = 'inconclusive' and coalesce(s.power_at_x, 0) < 0.5) or s.prior_exposure <> 'none')
         and not exists (select 1 from ripples.att_fx63_kill_log k where k.batch = p_batch and k.grid_id = s.grid_id and k.attack in ('contradicted_held_out', 'underpowered', 'prior_exposure'));
    update ripples.att_fx63_batch set status = 'confirmed', updated_at = now() where batch = p_batch;
  end if;
  select count(*) filter (where verdict3 = 'replicated'), count(*) filter (where verdict3 = 'replicated (weaker)'), count(*) filter (where selected)
    into n_conf, n_weak, n_sel from ripples.att_fx63_select where batch = p_batch and decoy_set = p_set;
  return jsonb_build_object('batch', p_batch, 'set', p_set, 'n_selected', n_sel, 'n_in_bh', coalesce(cardinality(ids), 0), 'n_replicated', n_conf, 'n_replicated_weaker', n_weak);
end $function$
;
CREATE OR REPLACE FUNCTION public.rm_patterns63(p_family text DEFAULT NULL::text, p_min text DEFAULT 'confirmed'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ranked as (
    select v.*, case v.strength when 'confirmed pattern' then 4 when 'confirmed pattern (weaker)' then 3 when 'check passed' then 1 else 0 end as rank_
      from ripples.att_fx63_patterns v
     where v.decoy_set = 0 and v.selected and v.confirm_seq is not null and v.c_n is not null
       and not ripples.rm_node_hidden(v.source || ':' || v.metric)
       and (p_family is null or v.family = p_family))
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.grid_id, 'batch', r.batch, 'method', '6.3', 'family', r.family, 'family_label', r.family_label, 'sub', r.sub,
    'event_label', case when r.sub = 'hurricane' then 'Hurricanes' else r.family_label || 's' end,
    'outcome', r.source || ':' || r.metric, 'outcome_label', r.outcome_label, 'geo_kind', r.geo_kind,
    'design', 'split sample: found on events before ' || r.split_date || ', confirmed on held-out events since; affected vs unaffected regions (difference-in-differences, in-space + in-time placebos), BH over the confirmation set',
    'window', jsonb_build_object('pre', r.pre_n, 'post', r.post_n, 'lag', r.lag_n, 'grain', r.grain, 'variant', r.variant),
    'unit', r.unit, 'effect', r.c_pct, 'ci', jsonb_build_array(r.c_pct_lo, r.c_pct_hi), 'effect_logpts', round(r.c_d::numeric, 4),
    'n_events', r.c_n, 'n_clustered_out', r.c_n_clustered_out, 'i2', round(coalesce(r.c_i2, 0)::numeric, 2), 'p_placebo', r.c_p, 'p_norm', r.c_p_norm, 'q', r.c_q,
    'sign', r.x_sign, 'sign_ok', r.c_sign_ok, 'n_regional_pass', r.c_n_regional_pass,
    'exploration', jsonb_build_object('n_events', r.x_n, 'effect', r.x_pct, 'p_placebo', r.x_p, 'period', 'before ' || r.split_date),
    'confirmation', jsonb_build_object('n_events', r.c_n, 'effect', r.c_pct, 'ci', jsonb_build_array(r.c_pct_lo, r.c_pct_hi), 'p_placebo', r.c_p, 'q', r.c_q, 'period', 'since ' || r.split_date),
    'strength', r.strength, 'verdict', r.verdict, 'is_check', r.is_check, 'definitional', r.definitional,
    'domain_distance', r.domain_distance, 'expected_by_mechanism', r.expected_by_mechanism, 'non_obvious', (r.domain_distance >= 1),
    'pond', ripples.att_fx_pond(r.c_d, r.domain_event, r.domain_outcome, r.unit)
            || jsonb_build_object('stone', (select percentile_cont(0.5) within group (order by ripples.att_fx_shock_norm(f.event_id)) from ripples.att_fx_event f where f.grid_id = r.grid_id and f.role = 'confirm' and f.magnitude is not null)),
    'fluke_note', ripples.att_fx63_fluke_line(case r.strength when 'confirmed pattern' then 'pattern' when 'consistent pattern' then 'consistent' when 'confirmed pattern (weaker)' then 'pattern_weaker' when 'consistent pattern (weaker)' then 'pattern_weaker' when 'check passed' then 'check' else 'hunch' end),
    'headline', case when r.sub = 'hurricane' then 'Hurricanes' else r.family_label || 's' end || ' → ' || r.outcome_label || ': ' || case when r.c_pct >= 0 then '+' else '' end || r.c_pct
                || case when r.unit = 'pct' then '%' else ' (raw units)' end || ' over ' || r.post_n || ' ' || case r.grain when 'week' then 'weeks' when 'month' then 'months' else 'days' end
                || case when r.lag_n > 0 then ', starting ' || r.lag_n || ' ' || case r.grain when 'week' then 'weeks' when 'month' then 'months' else 'days' end || ' after the event' else '' end
                || ', seen again in ' || r.c_n || ' held-out events',
    'wording', 'found in ' || r.x_n || ' events before ' || r.split_date || ', seen again in ' || r.c_n || ' events since',
    'sample_events', ripples.att_fx63_sample_events(r.grid_id, 'confirm', 3),
    'ledger', jsonb_build_object('explore_seq', r.explore_seq, 'confirm_seq', r.confirm_seq, 'calibration_seq', r.calib_seq), 'computed_at', r.computed_at
  ) order by r.rank_ desc, coalesce(r.c_q, 1), r.c_p), '[]'::jsonb)
  from ranked r
  where r.rank_ >= case p_min when 'confirmed' then 4 when 'weaker' then 3 when 'all' then 1 else 4 end
$function$
;
